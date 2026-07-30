extends Node
## LOOK AT IT. Photographs the four placards the owner named, the rest of the signage pass,
## and the lifeboat in its new berth. Windowed and foreground only (headless never draws).
##
## Carries the three pause defences from docs/AGENT_TRAPS.md: PROCESS_MODE_ALWAYS, an
## unpause every frame, and hiding the PauseMenu's own CanvasLayer — a paused world still
## renders, so without all three the frames are stable, beautiful and meaningless.
## Prints the camera position actually reached beside the one asked for.

const EYE_UP: float = 1.6
var main: Node3D
var _pause: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(3.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	main.hud.visible = false
	_pause = _find_pause(get_tree().root)
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock._phase_elapsed_sec = GameClock.phase_durations_minutes[GameClock.Phase.DAY] * 60.0 * 0.45

	# --- the four placards the owner named, plus the rest of the signage pass ---
	# NOTE ON YAW: a Node3D's forward is its local -Z, so rotation.y = 0 LOOKS SOUTH (-Z)
	# and 180 looks north. The dorm and shop walls face south, hence 180 for those.
	await _shot(Vector3(-25.2, 18.0, 1.10), 180.0, 15.0, "sg_fire_hose_reel")
	await _shot(Vector3(-12.3, 18.0, 1.30), 180.0, 7.0, "sg_fire_point_4")
	await _shot(Vector3(-13.2, 18.0, 2.35), 180.0, 14.0, "sg_db4")
	await _shot(Vector3(-9.85, 18.0, 1.05), 180.0, 12.0, "sg_muster_station_b")
	await _shot(Vector3(-18.9, 18.0, -4.3), 175.0, 2.0, "sg_flammable_gas")
	await _shot(Vector3(-15.7, 18.0, -4.6), 3.0, 2.0, "sg_roof_access")
	await _shot(Vector3(-26.2, 18.0, -2.3), 178.0, -2.0, "sg_waste_oil")
	await _shot(Vector3(-16.3, 18.0, 0.6), 180.0, 4.0, "sg_basket_p04")

	# --- the lifeboat: new berth, and the crane it used to stand inside ---
	await _shot(Vector3(-10.2, 18.0, -12.6), 0.0, 0.0, "lb_berth_wide")
	await _shot(Vector3(-13.4, 18.0, -13.6), -38.0, 0.0, "lb_berth_three_quarter")
	await _shot(Vector3(-4.0, 18.0, -13.5), 45.0, 0.0, "lb_east_end_and_derrick")
	await _shot(Vector3(-3.5, 18.0, -12.0), 0.0, 0.0, "lb_old_spot_now_clear")
	await _shot(Vector3(2.0, 18.0, -7.5), 0.0, 4.0, "lb_derrick_base_clear")
	await _shot(Vector3(-10.2, 18.0, -21.0), 180.0, 3.0, "lb_from_seaward")

	# --- the wet deck: the floating bar that was the windlass brake lever ---
	await _shot(Vector3(11.7, 2.0, -21.9), 40.0, -14.0, "wd_windlass_brake")
	await _shot(Vector3(10.6, 2.0, -14.2), 6.0, -2.0, "wd_sw_main_plate")
	get_tree().quit()

func _shot(pos: Vector3, yaw: float, pitch: float, name_: String) -> void:
	var p: Node3D = main.player
	p.input_locked = true
	# Re-assert every frame of the settle: the controller keeps integrating (buoyancy, the
	# fly drift) across a plain await and has moved shots up to 3 m off their mark before.
	for i in range(48):
		get_tree().paused = false
		if _pause != null:
			_pause.visible = false
		p.global_position = pos
		p.rotation.y = deg_to_rad(yaw)
		p.get_node("Head").rotation.x = deg_to_rad(pitch)
		p.velocity = Vector3.ZERO
		await get_tree().process_frame
	var cam: Camera3D = p.get_node("Head/Camera3D")
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/sign_check/%s.png" % name_)
	print("%-28s asked (%.1f, %.1f, %.1f) yaw %.0f  ->  eye at %s"
		% [name_, pos.x, pos.y + EYE_UP, pos.z, yaw, str(cam.global_position.snappedf(0.01))])

func _find_pause(n: Node) -> CanvasLayer:
	var s: Script = n.get_script()
	if s != null and String(s.resource_path).ends_with("pause_menu.gd"):
		return n as CanvasLayer
	for c in n.get_children():
		var got: CanvasLayer = _find_pause(c)
		if got != null:
			return got
	return null
