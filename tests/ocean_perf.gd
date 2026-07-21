extends Node3D
## Frame-cost check for the ocean work, on a REAL GPU (run windowed, never --headless:
## headless renders nothing and every counter reads zero).
##
## Samples sustained FPS and the renderer's own primitive/draw-call counters at the
## vantages that cost the most: standing on deck looking out to the fog horizon (the
## whole 1500 m radial ocean mesh + the rig), the same in a storm (rain + full sea
## state), and mid-water among the seabed/reef/FX (every underwater system at once).
## Target is a MacBook, so the bar is "comfortably above 60 at 1280x720".

const SPOTS := [
	["deck_horizon", Vector3(0.0, 26.0, 0.0), Vector3(120.0, 8.0, 120.0), false],
	["deck_storm", Vector3(0.0, 26.0, 0.0), Vector3(120.0, 8.0, 120.0), true],
	["sea_level", Vector3(60.0, 2.6, 60.0), Vector3(0.0, 1.0, 0.0), false],
	["midwater_leg", Vector3(15.0, -4.2, -6.0), Vector3(22.0, -5.5, -12.0), false],
	# The floor dropped to -92 in the 4x-depth pass; this vantage rides the wreck field down.
	["seabed_wreck", Vector3(12.0, -80.0, -30.0), Vector3(-1.0, -89.0, -47.0), false],
]

var _main: Node3D

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	# WAIT FOR THE WORLD. The dressing streams in over ~20 s and render_budget.gd sweeps
	# behind it, so a 2.5 s wait measured a half-built rig with none of the frame budget
	# applied — the earlier spots came out several times worse than the same spots measured
	# later in the same run, which made this harness's own numbers inconsistent.
	await get_tree().create_timer(28.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.current = true
	cam.fov = 72.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	_main.storm.set_process(false)

	print("=== ocean frame cost (1280x720, Compatibility/OpenGL) ===")
	for s in SPOTS:
		_main.sun_ctl.set_storm(1.0 if s[3] else 0.0)
		player.global_position = s[1]
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		await get_tree().create_timer(1.2).timeout   # let it settle / stream in
		# Average over a real window rather than trusting one frame.
		var frames: int = 0
		var acc: float = 0.0
		var t0: float = Time.get_ticks_msec() / 1000.0
		while (Time.get_ticks_msec() / 1000.0) - t0 < 2.0:
			await get_tree().process_frame
			frames += 1
			acc += Engine.get_frames_per_second()
		var prim: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		print("%-14s fps %6.1f   tris %8d   draw calls %5d" % [
			s[0], acc / maxf(float(frames), 1.0), prim, draws])

	# ---- attribution: how much of the deck cost is the OCEAN work vs the rig? ----
	print("=== attribution at deck_horizon ===")
	_main.sun_ctl.set_storm(0.0)
	player.global_position = SPOTS[0][1]
	cam.global_position = SPOTS[0][1]
	cam.look_at(SPOTS[0][2], Vector3.UP)
	var uww: Node3D = _by_script(_main, "underwater_world.gd")
	var ocean: Node3D = _by_script(_main, "ocean_surface.gd")
	await _report("everything on")
	uww.visible = false
	await _report("underwater_world OFF")
	ocean.visible = false
	await _report("ocean OFF too")
	uww.visible = true
	ocean.visible = true
	get_tree().quit()

func _by_script(root: Node, tail: String) -> Node3D:
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		var s: Script = n.get_script()
		if s != null and s.resource_path.ends_with(tail):
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _report(label: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var frames: int = 0
	var acc: float = 0.0
	var t0: float = Time.get_ticks_msec() / 1000.0
	while (Time.get_ticks_msec() / 1000.0) - t0 < 1.5:
		await get_tree().process_frame
		frames += 1
		acc += Engine.get_frames_per_second()
	print("%-24s fps %6.1f   tris %8d   draw calls %5d" % [label,
		acc / maxf(float(frames), 1.0),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])
