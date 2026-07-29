extends Node
## The two ITEM-VISUAL claims the owner judges by screenshot, photographed in the live game:
##   1. the rebuilt offshore rod as it is HELD, as it sits in the WORLD, and as its pack
##      icon — with the cast line visibly leaving the roller tip;
##   2. the fish inventory PREVIEW at real size, across the size range.
##
## Runs Main windowed (a SubViewport read-back needs a real frame; --headless never draws),
## so:  godot --path . res://tests/ItemShot.tscn -- <out_dir>

var main: Node3D
var _out: String = "/tmp"

## PauseMenu auto-pauses on window focus-out, and a capture run has no one sitting at the
## keyboard to keep the window in front — every shot after the first stray focus change came
## back with the pause panel over it and a frozen physics world (the cast never flew). This
## runs while the tree is paused and undoes it.
func _process(_d: float) -> void:
	if not get_tree().paused:
		return
	get_tree().paused = false
	for n in get_tree().root.find_children("*", "PauseMenu", true, false):
		var panel: Variant = n.get("panel")
		if panel is Control:
			(panel as Control).visible = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(3.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	var p: Node3D = main.player

	# ---------------------------------------------------------------- 1. the rod
	# The rod propped in the store room, seen from the door — the WORLD copy.
	await _shot(Vector3(13.6, 3.4, -17.9), 92.0, -6.0, "rod_world")
	# Held: stand on the east rim over open sea and cast, so the line is in frame.
	PlayerState.add_item("fishing_rod")
	for i in range(PlayerState.hotbar.size()):
		if str(PlayerState.hotbar[i]) == "fishing_rod":
			PlayerState.selected_hotbar = i
	p.call("_update_held_item")
	await get_tree().process_frame
	await _shot(Vector3(27.0, 2.2, -20.0), 0.0, -8.0, "rod_held")
	# Where the line actually starts, versus where the fallback would have put it.
	_report_tip(p)
	# A cast only survives over OPEN water — the float raycasts as it flies and any rail or
	# grating it clips reels the line straight back in ("No open water there"). So try the
	# vantages in order and photograph the first one that actually gets a line out.
	for spot in [[Vector3(27.0, 2.2, -20.0), 0.0, -8.0], [Vector3(27.4, 2.2, -20.0), -90.0, -6.0],
			[Vector3(24.5, 3.6, -19.6), 75.0, -6.0], [Vector3(14.0, 3.2, -23.4), 84.0, -4.0],
			[Vector3(-30.0, 19.4, -2.0), 90.0, -10.0]]:
		if spot[0].x < -28.0:
			p.set("_fly", true)   # last resort: hover off the west rim, all open water
		await _park(spot[0], float(spot[1]), float(spot[2]))
		# fishing_rod._physics_process reels the line straight back in while input_locked is
		# set (that flag means "a panel is up"), so the parking lock has to come off first.
		p.set("input_locked", false)
		p.call("_start_fishing")
		await get_tree().create_timer(0.45).timeout
		var rod: Node3D = p.get("fishing")
		var live: bool = rod != null and is_instance_valid(rod)
		print("[itemshot] cast from %s yaw=%s -> %s" % [str(spot[0]), str(spot[1]),
			str(rod.global_position.snappedf(0.01)) if live else "NO OPEN WATER"])
		if not live:
			continue
		# Shot now, while the float is still close: the line is a 12 mm cylinder, so at
		# 15 m it is a sub-pixel thread and proves nothing about where it starts.
		_save("rod_cast")
		await get_tree().create_timer(1.6).timeout
		if p.get("fishing") != null:
			_save("rod_cast_settled")
		break
	p.set("_fly", false)

	# ---------------------------------------------------------------- 2. the pack
	for id in ["fish_copper_sprat", "fish_slate_cod", "fish_barrel_grouper",
			"fish_coelacanth", "fish_giant_oarfish"]:
		PlayerState.add_item(id)
	main.hud.toggle_panel("inventory")
	await get_tree().create_timer(1.5).timeout
	_save("pack_icons")
	# Click each fish slot in turn and photograph the preview it raises.
	for id in ["fish_copper_sprat", "fish_slate_cod", "fish_coelacanth",
			"fish_giant_oarfish", "fish_barrel_grouper"]:
		var idx: int = _slot_of(id)
		if idx < 0:
			print("[itemshot] %s not in any slot" % id)
			continue
		main.hud.call("_inv_slot_clicked", idx)
		await get_tree().create_timer(1.2).timeout
		_save("preview_%s" % id)
		main.hud.call("_inv_slot_clicked", idx)   # click again = put it back down
		await get_tree().process_frame
	# ---------------------------------------------------- 3. the rest of the pack
	# The icon framing changed for EVERY item, not just the rod, so a spread of shapes gets
	# photographed too: long tools, round tins, flat plates, kits and a lit thing.
	for id in ["prybar", "crude_spear", "deep_rig_pole", "wrench", "hacksaw", "canned_food",
			"water_ration", "rope", "flare", "life_ring", "steel_plate", "bloom_lamp_kit"]:
		PlayerState.add_item(id)
	await get_tree().create_timer(3.0).timeout
	_save("pack_mixed")
	get_tree().quit()

## Unified slot index (hotbar first, then pack) holding `id`, or -1.
func _slot_of(id: String) -> int:
	for i in range(PlayerState.HOTBAR_SIZE):
		if str(PlayerState.hotbar[i]) == id:
			return i
	for i in range(PlayerState.inventory.size()):
		if PlayerState.inventory[i] != null and str(PlayerState.inventory[i]) == id:
			return PlayerState.HOTBAR_SIZE + i
	return -1

func _report_tip(p: Node) -> void:
	var hand: Node3D = p.get("_hand_item")
	if hand == null or hand.get_child_count() == 0:
		print("[itemshot] hand is EMPTY")
		return
	var container: Node3D = hand.get_child(0)
	var marker: Node = container.find_child("hand_tip", true, false)
	var tip: Vector3 = p.call("hand_tip_world")
	var fallback: Vector3 = container.global_transform * (Vector3(0, 1, 0) * float(p.get("_hand_reach")))
	print("[itemshot] hand_tip=%s tip=%s fallback=%s delta=%.3f" % [
		"found" if marker is Node3D else "MISSING", str(tip.snappedf(0.001)),
		str(fallback.snappedf(0.001)), tip.distance_to(fallback)])

func _save(name_: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name_])
	print("[itemshot] saved %s/%s.png" % [_out, name_])

func _park(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	GameClock.force_phase(GameClock.Phase.DAY)
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.velocity = Vector3.ZERO
	p.input_locked = true
	await get_tree().create_timer(1.2).timeout

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	await _park(pos, yaw_deg, pitch_deg)
	_save(name_)
