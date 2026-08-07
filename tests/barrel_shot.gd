extends Node3D
## THE FIRE BARREL, AT NIGHT, FROM FOUR SIDES — the look the s46 fix was reasoned into
## and never actually seen.
##
## The barrel was shipped black-with-a-missing-wall because the drum SHADOWED ITS OWN FIRE:
## the interior light's rays were blocked by the sooted liner, so the skin was lit by
## nothing and sat inside a 2.42 m unlit moat of its own firelight. That diagnosis is
## arithmetic. This is the picture, and the repo's rule is that the picture is what counts.
##
##   godot --path . --fixed-fps 60 tests/BarrelShot.tscn
##
## Orbits the barrel at eye height so every face is seen, at NIGHT (the failing condition —
## at noon the sun lights the skin and hides the bug), plus one low angle looking into the
## drum for the rim gap.

const SHOT_PX := Vector2i(1152, 648)
const BARREL := Vector3(28.5, 2.0, -11.0)   ## rig_builder places it at WET_Y + 0.01

var _dir: String = "res://tests/out/barrel"
var _main: Node3D
var _cam: Camera3D
var _shot: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_dir = a
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 22000 or waited < 180:
		await get_tree().process_frame
		waited += 1
	var player: Node3D = get_tree().get_first_node_in_group("player")
	_cam = player.get_node("Head/Camera3D")
	_cam.current = true
	player.set_physics_process(false)
	for p in player.find_children("*", "CollisionObject3D", true, false):
		(p as CollisionObject3D).set_collision_mask_value(1, false)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	player.global_position = BARREL + Vector3(3.0, 0.0, 0.0)
	# NIGHT IS THE POINT. At noon the sun lights the drum skin and the bug is invisible;
	# the owner's screenshot was a night frame. Forced once and then held by writing the
	# phase fraction directly — GameClock.force_phase RESETS the phase clock, and calling
	# it every frame pins the sun at the phase's opening elevation (the s22 trap).
	GameClock.force_phase(GameClock.Phase.NIGHT)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.NIGHT]) * 60.0 * 0.5
	for i in range(30):
		await get_tree().physics_frame
	# Four sides at eye height, then two looking down into the drum.
	for i in range(6):
		var a: float = TAU * float(i) / 4.0
		var high: bool = i >= 4
		var r: float = 2.6 if not high else 1.5
		var eye: Vector3 = BARREL + Vector3(cos(a) * r, 1.45 if high else 0.55, sin(a) * r)
		for f in range(12):
			_pin()
			_cam.global_position = eye
			_cam.look_at(BARREL + Vector3(0, 0.55 if not high else 0.75, 0), Vector3.UP)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var tex: Texture2D = get_viewport().get_texture()
		var img: Image = tex.get_image() if tex != null else null
		if img != null:
			img.resize(SHOT_PX.x, SHOT_PX.y)
			img.save_png("%s/barrel_%02d_%s.png" % [_dir, _shot, "into" if high else "side"])
		_shot += 1
		print("[barrel] shot %d from %s" % [_shot, str(eye.snappedf(0.1))])
	print("[barrel] done -> %s (%d shots)" % [_dir, _shot])
	get_tree().quit()

func _pin() -> void:
	if get_tree().paused:
		get_tree().paused = false
	var pm: Node = get_tree().get_first_node_in_group("pause_menu")
	if pm != null and pm.get("panel") != null:
		(pm.get("panel") as CanvasItem).visible = false
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.NIGHT]) * 60.0 * 0.5
