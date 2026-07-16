extends Node
## Headless integration test for the v0.1 slice: boots Main, then walks the core loop —
## verbs, power puzzle chain, night crab, contact-respawn, end-card path. Run with:
##   godot --headless res://tests/TestRunner.tscn

var failures: int = 0
const DECK_Y_TEST: float = 18.0

func _count_structures(main: Node) -> int:
	return main.get_tree().get_nodes_in_group("built_structures").size()

func _item_count(id: String) -> int:
	var n: int = 0
	for it in PlayerState.hotbar:
		if it == id:
			n += 1
	for it in PlayerState.inventory:
		if it == id:
			n += 1
	return n

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		failures += 1
		printerr("FAIL  ", label)

func _ready() -> void:
	await _run()
	print("---")
	print("FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var rig: RigBuilder = main.rig
	var player: Node3D = main.player
	_check(rig != null, "rig built")
	_check(player != null, "player spawned")
	# Immediate-start design: the hatch is unlocked from the first frame, so a new
	# player can open it on the first E press instead of waiting out a countdown.
	_check(rig.sphl_hatch != null and not rig.sphl_hatch.locked, "SPHL hatch starts unlocked")
	_check(rig.countdown_label != null, "pressure readout exists")
	_check(player.global_position.distance_to(rig.player_spawn) < 1.0, "player starts at the hatch")

	# Opening the hatch advances the intro objective (cold_open_finished beat).
	_check(not rig.sphl_hatch.available_verbs().is_empty(), "hatch is OPEN-able immediately")
	rig.sphl_hatch.interact("OPEN", player)
	_check(rig.sphl_hatch.is_open, "hatch opens")
	await get_tree().process_frame
	_check(main.hud.objective_label.text.to_lower().contains("power"),
		"opening the hatch advances the objective")

	# Readables.
	Readable.load_texts()
	_check(Readable._texts.has("sphl_manual") and Readable._texts.has("breaker_log"),
		"readable texts loaded from data")
	var readable_count: int = 0
	for c in rig.get_children():
		if c is Readable:
			readable_count += 1
	_check(readable_count >= 8, "8+ readables placed (found %d)" % readable_count)

	# Power puzzle chain: gap blocks breaker; spool -> connect -> operate -> light.
	var cable: CableSegment = null
	var breaker: BreakerPanel = null
	var zone: LightZone = null
	for c in rig.get_children():
		if c is CableSegment:
			cable = c
		elif c is BreakerPanel:
			breaker = c
		elif c is LightZone:
			zone = c
	_check(cable != null and breaker != null and zone != null, "power chain nodes exist")
	breaker.interact("OPERATE", player)
	_check(not PowerGrid.is_powered("topside_floodlights"), "breaker refuses with burned cable")
	cable.interact("CONNECT", player)
	_check(not cable.connected, "cable refuses without spool")
	PlayerState.add_item("cable_spool")
	cable.interact("CONNECT", player)
	_check(cable.connected, "cable splices with spool")
	_check(not PlayerState.has_item("cable_spool"), "spool consumed")
	breaker.interact("OPERATE", player)
	_check(PowerGrid.is_powered("topside_floodlights"), "breaker powers circuit")
	_check(zone.is_lit(), "light zone lit")
	_check(LightZone.point_is_safe(get_tree(), Vector3(0, 20, 0)), "topside center is safe")
	_check(not LightZone.point_is_safe(get_tree(), Vector3(20, 3, -10)), "wet deck stays dark")

	# Inventory + eating.
	PlayerState.add_item("canned_food")
	var before: float = 0.4
	PlayerState.hunger = before
	var slot: int = PlayerState.hotbar.find("canned_food")
	_check(slot != -1, "canned food in hotbar")
	PlayerState.use_hotbar(slot)
	_check(PlayerState.hunger > before, "eating restores hunger")

	# Night: crab spawns, pursues in darkness, respects light.
	GameClock.force_phase(GameClock.Phase.NIGHT)
	await get_tree().process_frame
	var crab: LamplightCrab = null
	for c in main.get_children():
		if c is LamplightCrab:
			crab = c
	_check(crab != null, "crab spawns at night")
	if crab:
		crab.global_position = Vector3(20, 3, -10)
		player.global_position = Vector3(21, 3, -10)   # dark wet deck, 1m away
		await get_tree().process_frame
		await get_tree().process_frame
		_check(crab.state == LamplightCrab.State.PURSUE or crab._contact_fired,
			"crab pursues player in darkness")

	# Contact stub: blackout -> SPHL -> dawn.
	var start_day: int = GameClock.day_count
	EventBus.creature_contact.emit()
	await get_tree().create_timer(3.2).timeout
	_check(player.global_position.distance_to(rig.sphl_interior) < 2.0, "contact returns player to SPHL")
	_check(GameClock.day_count > start_day, "contact skips to dawn")
	_check(GameClock.current_phase == GameClock.Phase.DAWN, "phase is dawn after contact")
	_check(main._ending, "end sequence armed at final dawn")

	# Build mode: B toggles, ghost rides aim, place consumes the kit into a structure.
	GameClock.force_phase(GameClock.Phase.DAY)
	player.global_position = Vector3(0, DECK_Y_TEST + 0.2, 12)
	player.input_locked = false
	PlayerState.add_item("walkway_kit")
	player.build.toggle()
	_check(player.build.active, "build mode toggles on with a kit")
	_check(player.build._ghost != null, "build ghost spawns")
	# Force a valid placement and lay it down.
	player.build._valid = true
	player.build._place_pos = Vector3(0, DECK_Y_TEST, 12)
	var built_before: int = _count_structures(main)
	var placed: bool = player.build.place()
	_check(placed, "build place() succeeds on valid spot")
	_check(not PlayerState.has_item("walkway_kit"), "placing consumes the kit")
	await get_tree().process_frame
	_check(_count_structures(main) > built_before, "a real structure spawned")
	if player.build.active:
		player.build.exit()

	# Throwing hook: a caught debris is added to inventory when the hook lands.
	PlayerState.add_item("throwing_hook")
	var hook := ThrowingHook.new()
	main.add_child(hook)
	hook.setup(player, player.camera)
	player.hook_out = true
	var debris := Gyre.FloatingDebris.new()
	debris.item_id = "driftwood"
	debris.display_name = "Driftwood Plank"
	main.add_child(debris)
	debris.global_position = hook.global_position   # inside CATCH_RADIUS
	await get_tree().physics_frame
	hook._try_catch()
	_check(not hook._caught.is_empty(), "hook snags nearby floating debris")
	var wood_before: int = _item_count("driftwood")
	hook._land()
	_check(_item_count("driftwood") > wood_before, "landed hook hauls the catch into inventory")
	_check(not player.hook_out, "hook_out clears after the hook returns")

	# Dev fly mode: double-tap F toggles noclip flight off gravity.
	player._toggle_fly()
	_check(player._fly, "fly mode toggles on")
	var fly_start: Vector3 = player.global_position
	Input.action_press("move_forward")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(fly_start) > 0.01, "fly mode moves the player")
	player._toggle_fly()
	_check(not player._fly, "fly mode toggles off")

	# Save round-trip.
	SaveManager.save_game()
	PlayerState.hunger = 0.123
	var ok: bool = SaveManager.load_game()
	_check(ok, "save file loads")
	_check(absf(PlayerState.hunger - 0.123) > 0.01, "load restores saved hunger")
