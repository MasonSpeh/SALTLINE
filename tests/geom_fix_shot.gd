extends Node
## Screenshots for the five world-geometry fixes, plus an END-TO-END climb of the
## machine-shop roof ladder driven through the real PlayerController input path (grab,
## hold E, mantle) rather than asserted. Saves /tmp/gf_*.png.
##
## Run WINDOWED — never --headless, which renders nothing and saves black PNGs:
##   godot --path . res://tests/GeomFixShot.tscn

var main: Node3D
var pause_menu: Node = null

## The game auto-pauses on window focus-out (pause_menu._notification), and a harness run
## from a terminal never has focus — so every frame here would otherwise render the PAUSED
## panel over the thing being photographed, and the paused tree would freeze the climb.
func _unpause() -> void:
	if pause_menu != null and is_instance_valid(pause_menu):
		var panel: Node = pause_menu.get("panel")
		if panel != null and is_instance_valid(panel) and panel.get("visible"):
			panel.set("visible", false)
	get_tree().paused = false

func _find_pause_menu() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("pause_menu.gd"):
			pause_menu = n
			return

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(14.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	_find_pause_menu()
	_unpause()
	var p: Node3D = main.player
	GameClock.force_phase(GameClock.Phase.DAY)
	# The breaker room is a blackout room; light it so the ceiling fitting is readable.
	PowerGrid.power_circuit("topside_floodlights")
	await get_tree().create_timer(3.0).timeout

	# --- 1. breaker-room ceiling beacon: flush to the deckhead, lens hanging down
	await _shot(Vector3(25.5, 10.2, 2.9), 180.0, 22.0, "gf_1_beacon")
	await _shot(Vector3(24.0, 10.2, 4.2), 168.0, 30.0, "gf_1_beacon_wide")
	# --- 2. DANGER / 440 V on the lintel over the door, not hanging in the opening
	await _shot(Vector3(23.5, 10.2, 6.6), 0.0, 14.0, "gf_2_danger")
	await _shot(Vector3(24.9, 10.2, 5.6), 14.0, 18.0, "gf_2_danger_angle")
	# --- 3. the splice stencils clear of the spare fuse box
	await _shot(Vector3(24.9, 10.2, 6.0), 180.0, 6.0, "gf_3_splice")
	await _shot(Vector3(23.4, 10.2, 6.2), -163.0, 6.0, "gf_3_splice_wide")
	# --- 4. wet deck: the dock locker clear of the tide-line drum
	await _shot(Vector3(26.2, 2.7, -17.2), -38.0, -10.0, "gf_4_crate")
	await _shot(Vector3(28.6, 5.2, -16.0), 0.0, -45.0, "gf_4_crate_top")
	# --- the welding bay, whose side screen moved out of the ladder keep-out
	await _shot(Vector3(-16.6, 18.7, -1.4), 0.0, -6.0, "gf_6_welding_bay")
	# --- 5. the machine-shop roof ladder, before the climb
	await _shot(Vector3(-14.8, 18.6, -2.4), 0.0, 16.0, "gf_5_ladder")
	await _shot(Vector3(-12.6, 18.6, -3.2), 33.0, 12.0, "gf_5_ladder_angle")

	# --- 5b. the CLIMB, for real: latch, hold E, ride it up, mantle at the top.
	await _climb_test()
	get_tree().quit()

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	var p: Node3D = main.player
	p.set("input_locked", true)
	p.set("_fly", true)
	p.set_collision_layer_value(1, false)
	p.set_collision_mask_value(1, false)
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.set("velocity", Vector3.ZERO)
	for i in range(30):
		_unpause()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	print("[gfshot] /tmp/%s.png err=%s" % [name_, img.save_png("/tmp/%s.png" % name_)])

## Drive the actual climb: this is the bug the owner reported, so it is played, not
## asserted. Prints where the capsule ends up at every stage.
func _climb_test() -> void:
	var p: Node3D = main.player
	var lad: Ladder = null
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Ladder and (n as Ladder).display_name == "Machine Shop Roof Ladder":
			lad = n as Ladder
	if lad == null:
		print("[gfshot] ladder not found")
		return
	p.set("_fly", false)
	p.set_collision_layer_value(1, true)
	p.set_collision_mask_value(1, true)
	p.set("input_locked", false)
	# Stand in the alley in front of the ladder, on the deck, looking at the rungs (-Z).
	p.global_position = Vector3(-14.8, 18.05, -4.0)
	p.rotation.y = 0.0
	p.get_node("Head").rotation.x = deg_to_rad(6.0)
	p.set("velocity", Vector3.ZERO)
	for i in range(20):
		_unpause()
		await get_tree().physics_frame
	print("[gfshot] standing at the foot: ", p.global_position)

	lad.interact("CLIMB", p)
	# E is re-pressed EVERY frame: a focus-out drops all held actions, and a harness
	# window never holds focus, so a single action_press() is released out from under
	# _climb_process on the first frame and the climb ends before it starts.
	var shot_low: bool = false
	var shot_mid: bool = false
	for i in range(320):
		_unpause()
		Input.action_press("interact")
		await get_tree().physics_frame
		if i == 1:
			print("[gfshot] latched at: ", p.global_position,
				"  (inside the shop is z < -5.875)")
		if not shot_low and i == 12:
			shot_low = true
			print("[gfshot] low on the ladder: ", p.global_position)
			await RenderingServer.frame_post_draw
			var a: Image = get_viewport().get_texture().get_image()
			print("[gfshot] /tmp/gf_5_climb_low.png err=%s" % a.save_png("/tmp/gf_5_climb_low.png"))
		if not shot_mid and p.global_position.y > 19.8:
			shot_mid = true
			print("[gfshot] mid-climb at: ", p.global_position)
			await RenderingServer.frame_post_draw
			var b: Image = get_viewport().get_texture().get_image()
			print("[gfshot] /tmp/gf_5_climb_mid.png err=%s" % b.save_png("/tmp/gf_5_climb_mid.png"))
		if p.get("_climbing") == null and i > 6:
			print("[gfshot] left the ladder on frame %d at %s" % [i, str(p.global_position)])
			break
	Input.action_release("interact")
	for i in range(40):
		_unpause()
		await get_tree().physics_frame
	print("[gfshot] after the top dismount: ", p.global_position,
		"  (roof top is y 21.325, roof spans z -18.25..-5.75)")
	p.get_node("Head").rotation.x = deg_to_rad(-14.0)
	p.rotation.y = deg_to_rad(180.0)
	for i in range(30):
		_unpause()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var c2: Image = get_viewport().get_texture().get_image()
	print("[gfshot] /tmp/gf_5_dismount.png err=%s" % c2.save_png("/tmp/gf_5_dismount.png"))
	# And a third-person look at where the player is standing, from out over the alley.
	var stood: Vector3 = p.global_position
	await _shot(stood + Vector3(3.6, 1.9, 3.4), 47.0, -20.0, "gf_5_on_the_roof")
	print("[gfshot] player finished at ", stood)
