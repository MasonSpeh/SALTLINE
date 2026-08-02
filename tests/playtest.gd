extends Node
## Headless playability smoke test: exercises the new player-facing features —
## cold-open skip, objective updates, prop grab/throw, crosshair targeting.

var failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		failures += 1
		printerr("FAIL  ", label)

func _ready() -> void:
	await _run()
	print("---")
	print("PLAYTEST FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout

	# Objective is set during cold open.
	_check(main.hud.objective_label.text.contains("pressure"), "objective shows during cold open")

	# Props spawned on the wet deck.
	var props: Array = []
	for c in main.get_children():
		if c is PhysProp:
			props.append(c)
	_check(props.size() == 3, "three grabbable props spawned (got %d)" % props.size())

	# Skip the cold open early.
	main._end_cold_open()
	await get_tree().process_frame
	_check(not main.rig.sphl_hatch.locked, "cold open skippable — hatch unlocks")
	_check(main.hud.objective_label.text.contains("power"), "objective advances after cold open")

	# Grab a prop and confirm carry state + crosshair prompt.
	var player: Node3D = main.player
	var prop: PhysProp = props[0]
	player.try_grab(prop)
	_check(player.carried == prop, "player can grab a prop")
	_check(prop.held_by == player, "prop knows it is held")
	_check(main.hud.prompt_label.text.contains("throw"), "carry prompt shows throw/drop")

	# Throw it — carry clears, impulse applied.
	player._throw_carried()
	await get_tree().physics_frame
	_check(player.carried == null, "throw releases the prop")
	_check(prop.linear_velocity.length() > 0.5, "thrown prop has velocity")

	# Crosshair targeting toggles with prompts.
	main.hud.set_targeting(true)
	_check(main.hud.crosshair.text == "◎", "crosshair swells when targeting")
	main.hud.set_targeting(false)
	_check(main.hud.crosshair.text == "·", "crosshair resets when not targeting")

	# Powering the circuit updates the objective.
	PowerGrid.power_circuit("topside_floodlights")
	await get_tree().process_frame
	_check(main.hud.objective_label.text.contains("light"), "objective updates on power restored")

	# --- Gyre + throwing hook loop ---
	var debris: Array = get_tree().get_nodes_in_group("floating_debris")
	_check(debris.size() >= 10, "gyre stocked with debris (got %d)" % debris.size())

	# Craft: lay-on-bench flow — partial hint, exact match, hold-to-work.
	var bench: CraftBench = null
	for c in main.rig.get_children():
		if c is CraftBench:
			bench = c
	_check(bench != null, "rigging bench exists on the wet deck")
	bench.interact("OPERATE", player)
	var bp: BenchPanel = main.hud.bench_panel
	_check(bp.visible, "bench opens its lay-parts panel")
	PlayerState.add_item("rope")
	PlayerState.add_item("mini_anchor")
	bp.refresh()
	_check(bp.lay_item("rope"), "can lay a part on the bench")
	_check(bp.current_match() == "" and bp.partial_matches().has("throwing_hook"),
		"partial parts whisper what they want to become")
	_check(bp._match_label.text.contains("still needs"), "bench lists the missing parts")
	bp.lay_item("mini_anchor")
	_check(bp.current_match() == "throwing_hook", "rope + mini anchor match the hook recipe")
	_check(not bp._work_button.disabled, "work button arms on an exact match")
	bp.test_hold = true
	var work_wait: float = 0.0
	while not PlayerState.has_item("throwing_hook") and work_wait < 6.0:
		await get_tree().create_timer(0.25).timeout
		work_wait += 0.25
	bp.test_hold = false
	_check(PlayerState.has_item("throwing_hook"), "holding the work makes the hook")
	_check(not PlayerState.has_item("rope") and not PlayerState.has_item("mini_anchor"),
		"crafting consumes the laid parts")
	_check(bp.laid.is_empty(), "bench surface clears after the work")
	# Panel closes politely and never eats parts.
	PlayerState.add_item("driftwood")
	bp.refresh()
	bp.lay_item("driftwood")
	main.hud.toggle_panel("bench")
	_check(PlayerState.has_item("driftwood"), "closing the bench returns laid parts")
	PlayerState.remove_item("driftwood")

	# --- Jump + crouch ---
	player.global_position = Vector3(0, 19.6, -5)   # open topside deck
	var grounded: bool = false
	for i in range(120):
		await get_tree().physics_frame
		if player.is_on_floor():
			grounded = true
			break
	_check(grounded, "player settles onto the deck")
	var jy: float = player.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	var jpeak: float = jy
	for i in range(40):
		await get_tree().physics_frame
		jpeak = maxf(jpeak, player.global_position.y)
	_check(jpeak - jy > 0.4, "Space jumps the player off the deck (rose %.2fm)" % (jpeak - jy))
	for i in range(30):
		await get_tree().physics_frame   # land again
	# Crouch: half capsule, lower eye line, halved detection.
	var cap: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	Input.action_press("crouch")
	for i in range(24):
		await get_tree().physics_frame
	_check(player.crouching, "holding crouch sets the crouch state")
	_check(cap.height < 1.0, "crouch halves the capsule (%.2f)" % cap.height)
	_check(player.detection_factor() < 0.6, "crouch halves creature detection")
	Input.action_release("crouch")
	for i in range(24):
		await get_tree().physics_frame
	_check(not player.crouching and cap.height > 1.5, "releasing crouch stands back up")

	# --- Un-crouching UNDER A CEILING must be refused, at BOTH heights ---
	#
	# KNOWN_ISSUES carried "un-crouching has no headroom check" as open. Half stale: the gate
	# was wired (player_controller._update_posture refuses a rise when _posture_fits fails) but
	# it only probed where the new HEAD lands (1.55..2.15 above the feet), so anything between
	# the crouched top (0.90) and 1.55 — a beam, a pipe run, a bunk frame — passed the check and
	# the capsule grew into it. Both cases are asserted here, because the entry survived
	# precisely because nothing ever tested a BLOCKED rise: an assertion that only ever stands
	# up in open air cannot tell a working gate from a missing one.
	#
	# Heights come from the controller's own posture constants, not typed by hand:
	#   crouched capsule 0.00..0.90    standing capsule 0.00..1.80
	for cse in [["chest", 1.25], ["head", 1.90]]:
		var lid := StaticBody3D.new()
		var lid_col := CollisionShape3D.new()
		var lid_box := BoxShape3D.new()
		lid_box.size = Vector3(4.0, 0.2, 4.0)
		lid_col.shape = lid_box
		lid.add_child(lid_col)
		main.add_child(lid)
		lid.global_position = player.global_position + Vector3(0.0, float(cse[1]), 0.0)
		await get_tree().physics_frame
		Input.action_press("crouch")
		for i in range(24):
			await get_tree().physics_frame
		_check(player.crouching, "crouches under the %s-height overhang" % cse[0])
		Input.action_release("crouch")
		for i in range(30):
			await get_tree().physics_frame
		_check(player.crouching and cap.height < 1.0,
			"rise under a %s-height obstruction is REFUSED (%.2f m capsule)" % [cse[0], cap.height])
		# Take the lid away and the same release must stand them up, or the refusal above would
		# pass equally for a player who simply cannot stand at all.
		lid.queue_free()
		for i in range(30):
			await get_tree().physics_frame
		_check(not player.crouching and cap.height > 1.5,
			"with the %s obstruction gone the player stands (%.2f m capsule)" % [cse[0], cap.height])

	# Build mode: craft a bloom lamp kit's worth, build it, verify REAL safety.
	PlayerState.add_item("bloom_lamp_kit")
	player.global_position = Vector3(0, 19.4, -5)   # open topside deck
	player.rotation.y = 0.0
	player.get_node("Head").rotation.x = deg_to_rad(-55)
	player.build.toggle()
	_check(player.build.active, "B enters build mode with a kit in the pack")
	_check(player.build._ghost != null, "build mode shows a ghost preview")
	var ghost_wait: float = 0.0
	while not player.build._valid and ghost_wait < 3.0:
		await get_tree().physics_frame
		ghost_wait += 0.016
	_check(player.build._valid, "ghost turns valid over open deck")
	var lamp_pos: Vector3 = player.build._place_pos
	_check(player.build.place(), "LMB places the structure")
	_check(not PlayerState.has_item("bloom_lamp_kit"), "placing consumes the kit")
	_check(not player.build.active, "build mode exits when the last kit is spent")
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("built_structures").size() >= 1, "structure stands in the world")
	_check(PowerGrid.is_powered("bloom_lamps"), "bloom circuit lives the moment a lamp exists")
	_check(LightZone.point_is_safe(get_tree(), lamp_pos + Vector3(1, 0.5, 1)),
		"player-built lamp casts REAL safety the crab honors")
	# Lean-to: warmth without the grid.
	PlayerState.add_item("leanto_kit")
	player.build.toggle()
	var g2: float = 0.0
	while not player.build._valid and g2 < 3.0:
		await get_tree().physics_frame
		g2 += 0.016
	player.build.place()
	await get_tree().process_frame
	var warm_zones: int = 0
	for s in get_tree().get_nodes_in_group("built_structures"):
		for ch in s.get_children():
			if ch is WarmthZone:
				warm_zones += 1
	_check(warm_zones >= 1, "built lean-to carries a live warmth zone")

	# Throw: stand over the gyre eye aimed down at a debris piece and reel one in.
	var target: Node3D = null
	for d in get_tree().get_nodes_in_group("floating_debris"):
		if d.gyre_radius < 12.0:
			target = d
			break
	_check(target != null, "debris circling near the gyre eye")
	# Hover nearly above the target and aim straight at it — steep drop, short flight.
	player.global_position = target.global_position + Vector3(2, 9, 0)
	var to_target: Vector3 = target.global_position - player.get_node("Head/Camera3D").global_position
	player.rotation.y = atan2(-to_target.x, -to_target.z)
	player.get_node("Head").rotation.x = atan2(to_target.y, Vector2(to_target.x, to_target.z).length())
	var inv_before: int = PlayerState.inventory.size() + PlayerState.hotbar.filter(func(x): return x != null).size()
	player._throw_hook()
	_check(player.hook_out, "hook launches on F")
	var waited: float = 0.0
	while player.hook_out and waited < 20.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	_check(not player.hook_out, "hook returns and clears the cooldown")
	var inv_after: int = PlayerState.inventory.size() + PlayerState.hotbar.filter(func(x): return x != null).size()
	_check(inv_after > inv_before, "hauled at least one resource from the gyre (%d -> %d)" % [inv_before, inv_after])

	# --- Journal / Help / Inventory UI ---
	_check(Journal.discovered.has("item_throwing_hook"), "journal logged the crafted hook")
	_check(Journal.discovered.has("place_rigging_bench"), "journal logged the rigging bench")
	_check(Journal.unseen_count > 0, "journal badge counts unseen entries")
	main.hud.toggle_panel("journal")
	_check(main.hud.journal_panel.visible, "journal panel opens (J / button)")
	_check(Journal.unseen_count == 0, "opening the journal clears the badge")
	_check(main.hud.journal_text.text.contains("Throwing Hook"), "journal lists the hook entry")
	main.hud.toggle_panel("inventory")
	_check(main.hud.inventory_panel.visible and not main.hud.journal_panel.visible,
		"inventory replaces journal (one panel at a time)")
	_check(player.ui_locked, "open panel locks player movement")
	# Click-to-move: hotbar slot 0 -> pack, then back.
	var first_item: Variant = PlayerState.hotbar[0]
	_check(first_item != null, "hotbar has an item to move")
	PlayerState.hotbar_to_backpack(0)
	_check(PlayerState.hotbar[0] == null and PlayerState.inventory.has(first_item), "hotbar -> pack move works")
	PlayerState.backpack_to_hotbar(PlayerState.inventory.find(first_item))
	_check(PlayerState.hotbar.has(first_item), "pack -> hotbar move works")
	main.hud.toggle_panel("inventory")
	_check(not main.hud.any_panel_open() and not player.ui_locked, "closing panel unlocks the player")
	main.hud.toggle_panel("help")
	_check(main.hud.help_panel.visible and main.hud.help_panel.get_child(0).text.contains("SALTLINE"),
		"help panel opens with the controls sheet")
	main.hud.toggle_panel("help")
	# Readable -> journal logs section.
	Journal.discover_log("sphl_manual", "SPHL OPERATIONS MANUAL — PAGE 12")
	main.hud.toggle_panel("journal")
	_check(main.hud.journal_text.text.contains("PAPERS I'VE READ"), "read papers appear in the journal")
	main.hud.toggle_panel("journal")
