extends Node3D
## WHERE DOES THE FRAME GO? A ranking harness, not a pass/fail probe.
##
## Must run WINDOWED on a real GPU (--headless renders nothing and every counter is zero).
## PowerPerf answered "what does the breaker cost"; this answers the broader question the
## breaker fix exposed — the rig is only 10-30 fps BEFORE anything is switched on, and
## guessing which subsystem owns that has already been wrong once (the obvious suspect,
## light count, turned out to be worth 4%).
##
## Method: park at a vantage, measure, then hide ONE subsystem at a time and measure again,
## restoring between each. Sorted by fps gained, that is a ranked list of what to fix. It
## deliberately re-measures the baseline between every toggle, because a MacBook under
## thermal load drifts several fps over a run and a single up-front baseline would credit
## that drift to whichever subsystem happened to be measured last.

const SPOTS := [
	["wet_deck", Vector3(16.0, 4.0, -19.0), Vector3(13.0, 3.5, -12.0)],
	["deck_floodlit", Vector3(0.0, 20.0, -1.0), Vector3(14.0, 19.0, 7.0)],
	["ops_lookout", Vector3(26.0, 39.0, -2.0), Vector3(20.0, 38.0, 6.0)],
]

var _main: Node3D
var _player: Node3D
var _cam: Camera3D

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(28.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)
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

	_census()
	for s in SPOTS:
		await _rank(s)
	get_tree().quit()

## What is actually in this world, by node count and triangle count, per direct child of
## Main. Static cost, before any camera is pointed at it.
func _census() -> void:
	print("=== world census (per direct child of Main) ===")
	var rows: Array = []
	for c in _main.get_children():
		var mi: int = 0
		var tris: int = 0
		var lights: int = 0
		for n in _walk(c):
			if n is Light3D:
				lights += 1
			var m := n as MeshInstance3D
			if m != null and m.mesh != null:
				mi += 1
				tris += _tris(m.mesh)
		if mi + lights == 0:
			continue
		rows.append([tris, mi, lights, c.name])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for r in rows:
		print("  %-28s tris %9d   meshes %5d   lights %3d" % [r[3], r[0], r[1], r[2]])

func _tris(m: Mesh) -> int:
	var n: int = 0
	for s in range(m.get_surface_count()):
		var arr: Array = m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx != null:
			n += (idx as PackedInt32Array).size() / 3
		else:
			var v: Variant = arr[Mesh.ARRAY_VERTEX]
			if v != null:
				n += (v as PackedVector3Array).size() / 3
	return n

## Hide each subsystem in turn and report what the frame gets back.
func _rank(s: Array) -> void:
	print("=== %s ===" % s[0])
	_place(s)
	var base: float = await _fps("baseline")
	var results: Array = []
	# Every direct child of Main that draws anything, plus the two shadow toggles, which
	# are not nodes but are the single most expensive flag in a GL renderer.
	var targets: Array = []
	for c in _main.get_children():
		var vis: Variant = c.get("visible")
		if typeof(vis) == TYPE_BOOL:
			targets.append(c)
	for c in targets:
		if not bool(c.visible):
			continue
		c.visible = false
		var got: float = await _fps("  without %s" % c.name)
		c.visible = true
		results.append([got - base, c.name])
		base = await _fps("  (re-baseline)", true)
	# Sun shadow: the whole-scene cascade pass.
	var sun: DirectionalLight3D = null
	for c in _main.get_children():
		if c is DirectionalLight3D and (c as DirectionalLight3D).shadow_enabled:
			sun = c
			break
	if sun != null:
		sun.shadow_enabled = false
		var got: float = await _fps("  without SUN SHADOW")
		sun.shadow_enabled = true
		results.append([got - base, "SUN SHADOW"])
	results.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("  ---- ranked by fps recovered ----")
	for r in results:
		if r[0] >= 0.5:
			print("  %+6.1f fps   %s" % [r[0], r[1]])

func _walk(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

func _place(s: Array) -> void:
	_player.global_position = s[1]
	_cam.global_position = s[1]
	_cam.look_at(s[2], Vector3.UP)

func _fps(label: String, quiet: bool = false) -> float:
	await get_tree().create_timer(0.6).timeout
	var frames: int = 0
	var acc: float = 0.0
	var t0: float = Time.get_ticks_msec() / 1000.0
	while (Time.get_ticks_msec() / 1000.0) - t0 < 1.3:
		await get_tree().process_frame
		frames += 1
		acc += Engine.get_frames_per_second()
	var f: float = acc / maxf(float(frames), 1.0)
	if not quiet:
		print("%-34s fps %6.1f   tris %9d   draws %5d" % [label, f,
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])
	return f
