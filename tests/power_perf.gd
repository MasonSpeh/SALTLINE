extends Node3D
## POWER-ON frame cost — why the rig gets glitchy the moment the breaker closes.
##
## Must run WINDOWED on a real GPU (never --headless: headless renders nothing and every
## counter reads zero). Companion to ocean_perf.gd, which measures the ocean/draw-call
## side; this one measures the LIGHT side, which is a different bottleneck entirely.
##
## gl_compatibility forward-renders omni/spot lights per object: every fragment of every
## mesh loops over the lights touching it, up to max_lights_per_object. Draw calls barely
## move when the breaker closes — the cost is all fragment shading, so ocean_perf's
## tris/draws columns would show nothing wrong while the frame time doubles. This harness
## reports fps at the vantages that stack the most overlapping light volumes, with the
## breaker OFF and then ON, and then attributes the difference.

const SPOTS := [
	# label, camera pos, look-at — the places the most lit volumes overlap.
	["deck_floodlit", Vector3(0.0, 20.0, -1.0), Vector3(14.0, 19.0, 7.0)],
	["stack_corridor", Vector3(6.0, 23.2, 12.0), Vector3(24.0, 23.0, 12.0)],
	["stair_shaft", Vector3(26.0, 14.0, 0.0), Vector3(26.0, 26.0, 1.9)],
	["wet_deck", Vector3(16.0, 4.0, -19.0), Vector3(13.0, 3.5, -12.0)],
	["ops_lookout", Vector3(26.0, 39.0, -2.0), Vector3(20.0, 38.0, 6.0)],
]

var _main: Node3D
var _player: Node3D
var _cam: Camera3D

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	# Same 28 s settle ocean_perf uses: the dressing streams in and render_budget.gd
	# sweeps behind it, so measuring earlier measures a half-built rig.
	await get_tree().create_timer(28.0).timeout
	GameClock.force_phase(GameClock.Phase.NIGHT)   # power only reads as a change after dark
	_player = get_tree().get_first_node_in_group("player")
	_player.set_physics_process(false)
	_player.set_process(false)
	_cam = _player.get_node("Head/Camera3D")
	_cam.current = true
	_cam.fov = 72.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	_main.storm.set_process(false)

	print("=== light census ===")
	_census()

	print("=== power OFF (breaker open) ===")
	for s in SPOTS:
		await _at(s)
	PowerGrid.power_circuit("topside_floodlights")
	await get_tree().create_timer(3.0).timeout   # let the stagger queue fully drain
	print("=== power ON (breaker closed) ===")
	for s in SPOTS:
		await _at(s)

	print("=== attribution at the worst vantage ===")
	var worst: Array = SPOTS[1]
	_place(worst)
	await _report("everything on")
	# 1. What do the four shadow-casting pole floodlights cost?
	var shadowed: Array[Light3D] = []
	for l in _all_lights():
		if l.shadow_enabled and l.visible and not (l is DirectionalLight3D):
			shadowed.append(l)
			l.shadow_enabled = false
	await _report("omni/spot shadows OFF (%d)" % shadowed.size())
	for l in shadowed:
		l.shadow_enabled = true
	await _report("...restored")
	# 2. What does the whole mains set cost — i.e. how much is "lights" at all?
	var mains: Array[Light3D] = []
	for l in _all_lights():
		if l.visible and l.is_in_group("interior_mains"):
			mains.append(l)
			l.visible = false
	await _report("interior_mains OFF (%d)" % mains.size())
	for l in mains:
		l.visible = true
	# 3. Volumetric fog energy on the beams — cheap flag, expensive pass?
	var vol: Array[Light3D] = []
	for l in _all_lights():
		if l.visible and l.light_volumetric_fog_energy > 0.0:
			vol.append(l)
			l.light_volumetric_fog_energy = 0.0
	await _report("light fog energy OFF (%d)" % vol.size())
	get_tree().quit()

## How many lights exist, how many are visible, and how badly do they overlap? The
## overlap number is the one that matters: gl_compat's per-fragment loop is driven by how
## many light volumes cover the same point, not by the total in the level.
func _census() -> void:
	var all: Array[Light3D] = _all_lights()
	var vis: int = 0
	var shadowed: int = 0
	var omni: int = 0
	var spot: int = 0
	for l in all:
		if l.visible:
			vis += 1
		if l.shadow_enabled:
			shadowed += 1
		if l is OmniLight3D:
			omni += 1
		elif l is SpotLight3D:
			spot += 1
	print("lights total %d   visible %d   shadow-casting %d   (omni %d / spot %d)"
		% [all.size(), vis, shadowed, omni, spot])
	print("project max_lights_per_object = %s   max_renderable_lights = %s" % [
		ProjectSettings.get_setting("rendering/limits/opengl/max_lights_per_object", "?"),
		ProjectSettings.get_setting("rendering/limits/opengl/max_renderable_lights", "?")])

## Worst-case overlap: for each vantage, how many light volumes actually contain it.
func _overlap_at(p: Vector3) -> int:
	var n: int = 0
	for l in _all_lights():
		if not l.visible:
			continue
		var r: float = 0.0
		if l is OmniLight3D:
			r = (l as OmniLight3D).omni_range
		elif l is SpotLight3D:
			r = (l as SpotLight3D).spot_range
		else:
			continue
		if l.global_position.distance_to(p) <= r:
			n += 1
	return n

func _all_lights() -> Array[Light3D]:
	var out: Array[Light3D] = []
	var stack: Array = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Light3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

func _place(s: Array) -> void:
	_player.global_position = s[1]
	_cam.global_position = s[1]
	_cam.look_at(s[2], Vector3.UP)

func _at(s: Array) -> void:
	_place(s)
	await get_tree().create_timer(1.2).timeout
	var frames: int = 0
	var acc: float = 0.0
	var t0: float = Time.get_ticks_msec() / 1000.0
	while (Time.get_ticks_msec() / 1000.0) - t0 < 2.0:
		await get_tree().process_frame
		frames += 1
		acc += Engine.get_frames_per_second()
	print("%-16s fps %6.1f   lights covering camera %3d   tris %8d   draws %5d" % [
		s[0], acc / maxf(float(frames), 1.0), _overlap_at(s[1]),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])

func _report(label: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var frames: int = 0
	var acc: float = 0.0
	var t0: float = Time.get_ticks_msec() / 1000.0
	while (Time.get_ticks_msec() / 1000.0) - t0 < 1.5:
		await get_tree().process_frame
		frames += 1
		acc += Engine.get_frames_per_second()
	print("%-28s fps %6.1f   draws %5d" % [label,
		acc / maxf(float(frames), 1.0),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])
