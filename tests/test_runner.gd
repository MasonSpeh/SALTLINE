extends Node
## Headless integration test for the v0.1 slice: boots Main, then walks the core loop —
## verbs, power puzzle chain, night crab, contact-respawn, end-card path. Run with:
##   godot --headless res://tests/TestRunner.tscn

var failures: int = 0
const DECK_Y_TEST: float = 18.0

func _count_structures(main: Node) -> int:
	return main.get_tree().get_nodes_in_group("built_structures").size()

## Find a Takeable anywhere in the tree by item id.
func _find_takeable(root: Node, id: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Takeable and n.item_id == id:
			return n
	return null

## Find a node whose script path contains `frag` (new classes: cache-safe lookup).
func _find_class(root: Node, frag: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).contains(frag):
			return n
	return null

func _find_ladder(root: Node, name_: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Ladder and n.display_name == name_:
			return n
	return null

func _fish_total() -> int:
	var n: int = 0
	for id in ["fish_herring", "fish_slate_cod", "fish_chimefish", "fish_sable_hake"]:
		n += _item_count(id)
	return n

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

	# Movable prop: a spawned chair-class prop can be grabbed, carried, and released.
	var chair := PropLib.spawn("plastic_monobloc_chair_01", main, Vector3(2, DECK_Y_TEST + 0.2, 12),
		0.0, 1.0, false, -1.0, true)
	_check(chair is MovableProp, "moveable prop spawns as MovableProp")
	if chair is MovableProp:
		_check((chair as MovableProp).freeze, "moveable prop rests frozen until grabbed")
		player.global_position = Vector3(2, DECK_Y_TEST + 0.2, 13.2)
		player.try_grab(chair)
		_check(player.carried == chair, "player grabs the moveable prop")
		await get_tree().physics_frame
		_check(not (chair as MovableProp).freeze, "grabbed prop wakes into physics")
		player.drop_carried()
		_check(player.carried == null, "player releases the moveable prop")
	var lamp_fixed: bool = PropLib.FIXED.has("portable_generator") and not PropLib.is_moveable("portable_generator")
	_check(lamp_fixed, "fixed heavy machinery stays non-moveable")

	# Storm: force a squall and confirm rain + darkening engage, then clear.
	if main.get("storm") != null:
		main.storm.trigger_storm()
		main.storm._intensity = 1.0
		main.storm._phase = 2
		main.storm._apply_intensity()
		await get_tree().process_frame
		_check(main.storm._rain.emitting, "storm rain emits at full intensity")
		_check(main.sun_ctl.storm_intensity > 0.5, "storm darkens the sky via SunController")
		main.storm._intensity = 0.0
		main.storm._phase = 0
		main.storm._apply_intensity()

	# Fishing: the rod is placed in the world, a landed fight yields a fish,
	# the stove sears it, and the seared meal actually feeds you.
	_check(_find_takeable(main, "fishing_rod") != null, "fishing rod placed in a storage room")
	var rod: Node3D = preload("res://scripts/components/fishing_rod.gd").new()
	main.add_child(rod)
	rod.setup(player, player.camera)
	rod._fish = {"id": "fish_herring", "name": "Lantern Herring", "fight": 0.8, "pull": 0.65}
	rod._state = rod.State.FIGHT
	var herring_before: int = _item_count("fish_herring")
	rod._land()
	_check(_item_count("fish_herring") > herring_before, "landed fight puts the fish in the pack")
	_check(player.fishing == null or not is_instance_valid(rod), "rod cleans up after landing")
	# The Looker is never kept — canon.
	var rod2: Node3D = preload("res://scripts/components/fishing_rod.gd").new()
	main.add_child(rod2)
	rod2.setup(player, player.camera)
	var looker: Dictionary = preload("res://scripts/world/fish_table.gd").all()["the_looker"].duplicate()
	looker["id"] = "the_looker"
	rod2._fish = looker
	rod2._state = rod2.State.FIGHT
	rod2._land()
	_check(not PlayerState.has_item("the_looker"), "The Looker is released, never kept")

	# Stove: sear the herring, then eat the meal.
	var stove: Node = _find_class(main, "cook_stove")
	_check(stove != null, "galley stove exists")
	if stove:
		var cooked_before: int = _item_count("cooked_fish")
		stove.interact("COOK", player)
		_check(_item_count("cooked_fish") > cooked_before, "stove sears raw fish into a meal")
		_check(_item_count("fish_herring") == herring_before, "searing consumes the raw fish")
		PlayerState.hunger = 0.2
		var cslot: int = PlayerState.hotbar.find("cooked_fish")
		if cslot == -1:
			PlayerState.add_item("cooked_fish")
			cslot = PlayerState.hotbar.find("cooked_fish")
		PlayerState.use_hotbar(cslot)
		_check(PlayerState.hunger > 0.5, "eating seared fish restores hunger")

	# Drop net: build, lower, force-mature, haul — fish arrive.
	var net_rig: Node3D = Structures.build("drop_net_kit", false)
	main.add_child(net_rig)
	net_rig.global_position = Vector3(19.5, 2.0, -21.8)   # dock edge, water below
	await get_tree().physics_frame
	var winch: Node = _find_class(net_rig, "drop_net")
	_check(winch != null, "drop net structure carries its winch")
	PlayerState.inventory.clear()   # make room — the haul needs pack space
	if winch:
		winch.interact("LOWER", player)
		_check(winch._state == winch.NetState.SOAKING, "net lowers into a soak")
		winch._state = winch.NetState.READY
		winch._wet = true
		winch._soaked_dark = true
		var fish_before: int = _fish_total()
		winch.interact("HAUL", player)
		_check(_fish_total() > fish_before, "hauled net yields fish")

	# Fish table integrity + the condition variables that gate the catch.
	var FT := preload("res://scripts/world/fish_table.gd")
	var table_ok: bool = true
	var cooked_ok: bool = true
	for fid in FT.all():
		var fdef: Dictionary = FT.all()[fid]
		if not fdef.get("release", false) and not PlayerState.items.has(fid):
			table_ok = false
		var ct: String = fdef.get("cooked_to", "")
		if ct != "" and not PlayerState.items.has(ct):
			cooked_ok = false
	_check(table_ok, "every keepable fish.json species is a real item")
	_check(cooked_ok, "every cooked_to target is a real item")
	var calm_ctx := {"phase": "day", "storming": false, "lit": false, "open": true}
	var storm_ctx := {"phase": "day", "storming": true, "lit": false, "open": true}
	_check(FT.weight_for("fish_drum_croaker", "rod", calm_ctx) == 0.0, "drum croaker never bites in calm")
	_check(FT.weight_for("fish_drum_croaker", "rod", storm_ctx) > 0.0, "drum croaker bites in storms")
	_check(FT.weight_for("fish_chimefish", "rod", storm_ctx) == 0.0, "chimefish refuses storm seas")
	_check(FT.weight_for("fish_fathom_halibut", "rod", calm_ctx) == 0.0, "halibut never takes a rod")
	var night_ctx := {"phase": "night", "storming": false, "lit": false, "open": true}
	_check(FT.weight_for("fish_fathom_halibut", "net", night_ctx) > 0.0, "halibut takes a night net")
	var lit_ctx := {"phase": "night", "storming": false, "lit": true, "open": false}
	_check(FT.weight_for("fish_sable_hake", "rod", lit_ctx) > FT.weight_for("fish_sable_hake", "rod", night_ctx),
		"worklight doubles the hake draw")
	_check(_find_class(main, "underwater_world") != null, "underwater world exists below the line")
	# Angler's notes placed by the rod.
	var notes_found: bool = false
	var nstack: Array[Node] = [main]
	while not nstack.is_empty():
		var nn: Node = nstack.pop_back()
		for nc in nn.get_children():
			nstack.append(nc)
		if nn is Readable and nn.readable_id == "anglers_notes":
			notes_found = true
			break
	_check(notes_found, "Angler's Notes placed beside the rod")
	# Underwater environment swap: force the camera below the swell.
	player._fly = true
	player.set_collision_layer_value(1, false)
	player.set_collision_mask_value(1, false)
	player.global_position = Vector3(0, -4.0, -34)
	main._process(0.016)
	var cam: Camera3D = player.get_node("Head/Camera3D")
	_check(cam.environment != null, "camera goes underwater below the wave line")
	player.global_position = Vector3(20, 6.0, -10)
	main._process(0.016)
	_check(cam.environment == null, "camera surfaces back to the world environment")
	if player._fly:
		player._toggle_fly()
	player.global_position = Vector3(0, DECK_Y_TEST + 0.2, 12)

	# Swimming: water is survivable now — buoyant, cold, and mortal at depth.
	GameClock.force_phase(GameClock.Phase.DAY)
	player.input_locked = false
	player.global_position = Vector3(0, -1.5, -34)
	player.velocity = Vector3.ZERO
	player._check_water()
	_check(player.swimming, "entering water starts swimming, not a respawn")
	var warmth_before: float = PlayerState.warmth
	player._swim_process(0.5)
	_check(PlayerState.warmth < warmth_before, "cold water drains warmth")
	_check(not player._drowning, "surface swimming does not black out")
	player.global_position = Vector3(0, -16.0, -34)   # far past the deep-death line
	player._swim_process(1.0)
	player._swim_process(1.0)
	_check(player._drowning or player.global_position.distance_to(player.respawn_point) < 3.0,
		"the deep takes swimmers who go too far down")
	await get_tree().create_timer(2.0).timeout   # let the fade/respawn resolve
	player.input_locked = false
	_check(_find_ladder(main, "Dock Ladder") != null, "dock ladder gives a way out of the sea")

	# Ultra Hammerhead: a charge that connects takes a bite of life.
	var shark: Node3D = preload("res://scripts/world/shark.gd").new(0)
	main.add_child(shark)
	player.global_position = Vector3(0, -1.5, -38)
	player.swimming = true
	shark.global_position = player.global_position + Vector3(1.0, 0, 0)
	shark._state = shark.SState.CHARGE
	var life_before: float = PlayerState.life
	shark._process(0.05)
	_check(PlayerState.life < life_before, "hammerhead charge that connects bites")
	_check(shark._state == shark.SState.FLEE, "after the bite it breaks off (a test, not a meal)")
	player.swimming = false
	player.global_position = Vector3(0, DECK_Y_TEST + 0.2, 12)

	# Preservation: raw rots on the line, cooked cures to dried; fridge is inert.
	var line: Node = preload("res://scripts/components/hang_line.gd").new()
	main.add_child(line)
	line.global_position = Vector3(0, DECK_Y_TEST + 1.8, 12)
	PlayerState.add_item("fish_herring")
	line._hang()
	_check(line._hung.size() == 1, "raw fish hangs on the line")
	line._hung[0]["age_h"] = 4.1
	line._process(0.016)
	_check(line._hung[0]["id"] == "fish_rotten", "raw fish rots after 4 game hours hung")
	PlayerState.add_item("cooked_fish")
	line._hang()
	line._hung[1]["age_h"] = 4.1
	line._process(0.016)
	_check(line._hung[1]["id"] == "dried_fish", "cooked fish cures to dried on the line")
	line._take()
	_check(PlayerState.has_item("dried_fish"), "taking from the line returns the cured fish")
	var fridge: Node = preload("res://scripts/components/cold_store.gd").new()
	main.add_child(fridge)
	PlayerState.add_item("fish_herring")
	fridge.interact("STOW", player)
	_check(fridge._stored.size() == 1, "fridge stows fish")
	fridge.interact("TAKE", player)
	_check(PlayerState.has_item("fish_herring"), "fridge returns fish, forever fresh")

	# Drop net reaches water from the topside deck now (DROP_MAX fix).
	var top_net: Node3D = Structures.build("drop_net_kit", false)
	main.add_child(top_net)
	top_net.global_position = Vector3(26, DECK_Y_TEST + 0.15, -30)
	await get_tree().physics_frame
	var top_winch: Node = _find_class(top_net, "drop_net")
	if top_winch:
		top_winch.interact("LOWER", player)
		_check(top_winch._wet, "topside drop net reaches the water")

	# Save round-trip.
	SaveManager.save_game()
	PlayerState.hunger = 0.123
	var ok: bool = SaveManager.load_game()
	_check(ok, "save file loads")
	_check(absf(PlayerState.hunger - 0.123) > 0.01, "load restores saved hunger")
