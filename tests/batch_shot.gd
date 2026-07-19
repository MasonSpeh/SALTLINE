extends Node3D
## VISUAL DIFF harness for the draw-call batching pass. Photographs a fixed set of
## vantages with a fixed camera, fixed phase and no weather, so a BEFORE and an AFTER
## run are directly comparable pixel for pixel. Nothing here is gameplay — it exists
## only to prove the rig still looks identical after geometry was merged.
##
## Output dir comes from --outdir=<path> on the command line.

const SHOTS := [
	["deck_horizon", Vector3(0.0, 26.0, 0.0), Vector3(120.0, 8.0, 120.0), 72.0],
	["sea_level", Vector3(60.0, 2.6, 60.0), Vector3(0.0, 1.0, 0.0), 72.0],
	["deck_close", Vector3(20.0, 20.2, -10.0), Vector3(12.0, 18.4, -15.0), 70.0],
	["interior_rec", Vector3(25.2, 19.8, 13.0), Vector3(18.1, 19.5, 13.0), 70.0],
	["wetdeck", Vector3(24.0, 4.6, -12.5), Vector3(16.0, 2.2, -17.0), 70.0],
	["stair_tower", Vector3(33.5, 19.6, -12.8), Vector3(30.6, 18.3, -16.0), 55.0],
	["midwater", Vector3(15.0, -4.2, -6.0), Vector3(22.0, -5.5, -12.0), 72.0],
]

var _main: Node3D

func _ready() -> void:
	var outdir: String = "/tmp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--outdir="):
			outdir = a.substr(9)
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(30.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.current = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	_main.storm.set_process(false)
	_main.sun_ctl.set_storm(0.0)

	for s in SHOTS:
		player.global_position = s[1]
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		cam.fov = s[3]
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = "%s/%s.png" % [outdir, s[0]]
		img.save_png(path)
		print("shot %-16s -> %s   draws %d  tris %d" % [
			s[0], path,
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))])
	print("SHOTS-DONE")
	get_tree().quit()
