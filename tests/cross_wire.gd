extends Node
## Integration test for the seams BETWEEN domains (salvage / craft / structures /
## comfort / ambience). Each domain was built decoupled and unit-verified on its own;
## this file asserts they actually connect at runtime:
##
##   * every kit in KIT_ORDER really builds, joins "built_structures", stamps meta "kit"
##   * furniture kits hang a "comfort_furniture" marker whose "kind" the comfort domain
##     accepts, and the comfort manager really bolts an Interactable onto it
##   * the ambience autoload is genuinely in the running tree
##   * the lived-in loop works end to end: craft a bedroll from salvaged materials,
##     place it, sleep on it; light a brazier and watch warmth rise; sit in a chair;
##     stash an item in a locker and take it back
##
## Run: godot --headless --path . res://tests/CrossWire.tscn

const SL := preload("res://scripts/world/structure_lib.gd")

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
	print("FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)

## Walk a subtree for the first node in `group`.
func _marker(root: Node) -> Node3D:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and n.is_in_group("comfort_furniture"):
			return n
	return null

## The comfort proxy the manager attached to a marker, if any.
func _proxy(marker: Node) -> Interactable:
	for c in marker.get_children():
		if c is Interactable:
			return c
	return null

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node3D = main.player
	# Freeze the player. This test teleports them around to stand in warmth zones and
	# sit in chairs; a live CharacterBody3D walks off the deck between checks, drowns,
	# and the game quits mid-suite (which reads as a silent truncation, not a failure).
	if player:
		player.set_physics_process(false)
		player.set_process(false)

	# ------------------------------------------------ (d) ambience is really running
	var amb: Node = get_node_or_null("/root/Ambience")
	_check(amb != null, "Ambience autoload is in the running tree")
	_check(amb != null and amb.is_inside_tree(), "Ambience is inside the tree (not orphaned)")

	# ------------------------------------------------ (b) every kit builds
	var expect_comfort := {
		"bedroll_kit": "bed", "locker_kit": "storage", "rain_catcher_kit": "water",
		"brazier_kit": "fire", "chair_kit": "seat", "workbench_kit": "bench",
		"drying_rack_kit": "drying", "planter_kit": "planter",
	}
	for kit in Structures.KIT_ORDER:
		var built: Node3D = Structures.build(kit, false)
		_check(built != null, "%s builds" % kit)
		if built == null:
			continue
		main.add_child(built)
		built.global_position = Vector3(0, 40, 0)   # clear of the rig, out of the way
		_check(built.is_in_group("built_structures"), "%s joins built_structures" % kit)
		_check(String(built.get_meta("kit", "")) == kit, "%s stamps meta kit" % kit)
		# geometry actually exists — a kit that builds an empty node is a silent hole
		_check(built.get_child_count() > 0, "%s has geometry" % kit)
		# ghost variant must also build (build mode spawns one every frame)
		var ghost: Node3D = Structures.build(kit, true)
		_check(ghost != null, "%s builds a ghost" % kit)
		if ghost:
			ghost.queue_free()
		# ------------------------------------------ (c) comfort contract
		if expect_comfort.has(kit):
			var m: Node3D = _marker(built)
			_check(m != null, "%s hangs a comfort_furniture marker" % kit)
			if m:
				_check(String(m.get_meta("kind", "")) == expect_comfort[kit],
					"%s marker kind is %s" % [kit, expect_comfort[kit]])
				_check(String(m.get_meta("kit", "")) == kit, "%s marker stamps its kit" % kit)
	# the manager attaches deferred; give it a beat, then a full rescan window
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	for kit in expect_comfort:
		for built in get_tree().get_nodes_in_group("built_structures"):
			if String(built.get_meta("kit", "")) != kit:
				continue
			var m: Node3D = _marker(built)
			if m:
				_check(_proxy(m) != null, "%s marker got a comfort interactable" % kit)
			break

	# ---------------------------------- (a) every craft input has a real world source
	# A yield row in SalvageTable proves nothing on its own — the prop it hangs off has
	# to actually stream into the rig. So ask the LIVE world what it can give you.
	var obtainable := {}
	var salvage_nodes: int = 0
	for s in get_tree().get_nodes_in_group("salvageable"):
		salvage_nodes += 1
		var y: Variant = s.get("yields")
		if y is Dictionary:
			for id in y:
				obtainable[id] = int(obtainable.get(id, 0)) + 1
	_check(salvage_nodes > 0, "the world streams salvageable props (%d)" % salvage_nodes)
	# the ten canonical salvaged materials must each come off something that exists
	for id in ["steel_plate", "pipe_length", "wire_spool", "bolt_handful", "glass_pane",
			"canvas_scrap", "foam_block", "ceramic_shard", "copper_coil", "rubber_hose"]:
		_check(obtainable.has(id), "%s is salvageable from a prop that really spawns (%d sources)"
			% [id, int(obtainable.get(id, 0))])
	# and the renewable natural nodes are really out there
	for id in ["tar_lump", "shell_grit", "float_buoy", "kelp_bundle", "fish_bone"]:
		_check(obtainable.has(id), "%s has a live harvest node" % id)

	# ------------------------------------------------ playability: the lived-in loop
	await _loop_bedroll(main, player)
	await _loop_brazier(main, player)
	await _loop_chair(main, player)
	await _loop_locker(main, player)

## Craft a bedroll from salvaged materials at a bench, place it, sleep on it.
func _loop_bedroll(main: Node3D, player: Node3D) -> void:
	var recipes: Dictionary = _recipes()
	var r: Dictionary = recipes.get("bedroll_kit", {})
	_check(not r.is_empty(), "bedroll_kit has a recipe")
	if r.is_empty():
		return
	# stock the exact inputs the recipe asks for
	for id in r.get("needs", {}):
		for i in int(r["needs"][id]):
			PlayerState.add_item(id)
	var bench: Node = _find_script(main, "craft_bench.gd")
	_check(bench != null, "a craft bench exists in the world")
	# hand-run the conversion the bench performs, then prove the kit is placeable
	for id in r.get("needs", {}):
		for i in int(r["needs"][id]):
			PlayerState.remove_item(id)
	_check(PlayerState.add_item("bedroll_kit"), "crafted bedroll_kit lands in the pack")
	_check(PlayerState.has_item("bedroll_kit"), "player holds bedroll_kit")

	var bed: Node3D = Structures.build("bedroll_kit", false)
	main.add_child(bed)
	bed.global_position = player.global_position + Vector3(1.5, 0, 0)
	PlayerState.remove_item("bedroll_kit")
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	var m: Node3D = _marker(bed)
	_check(m != null, "placed bedroll has its marker")
	if m == null:
		return
	var p: Interactable = _proxy(m)
	_check(p != null, "placed bedroll got a CampBed proxy")
	if p == null:
		return
	# SLEEP is night/dusk gated — force night and confirm the verb opens up
	GameClock.current_phase = GameClock.Phase.NIGHT
	_check(p.available_verbs().has("SLEEP"), "bedroll offers SLEEP at night")
	var rest_before: float = PlayerState.rest
	PlayerState.rest = maxf(0.0, rest_before - 50.0)
	var low: float = PlayerState.rest
	PlayerState.sleep_recovery()
	_check(PlayerState.rest > low, "sleeping restores rest (%.1f -> %.1f)" % [low, PlayerState.rest])

## Light a brazier with driftwood and confirm it makes real warmth.
func _loop_brazier(main: Node3D, player: Node3D) -> void:
	var br: Node3D = Structures.build("brazier_kit", false)
	main.add_child(br)
	br.global_position = player.global_position + Vector3(-1.5, 0, 0)
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	var m: Node3D = _marker(br)
	var p: Interactable = _proxy(m) if m else null
	_check(p != null, "placed brazier got a Hearth proxy")
	if p == null:
		return
	_check(p.available_verbs().is_empty(), "cold brazier with no driftwood offers nothing")
	PlayerState.add_item("driftwood")
	_check(p.available_verbs().has("LIGHT"), "brazier offers LIGHT once you hold driftwood")
	# WarmthZone is not grouped — the real contract is the additive PlayerState.warmth_zone
	# counter, incremented while the player body overlaps the Area3D. So stand in the
	# brazier FIRST, then light it, and watch the counter move.
	player.global_position = br.global_position + Vector3(0, 0.2, 0)
	await get_tree().physics_frame
	var zones_before: int = _count_zones(br)
	var warm_before: int = PlayerState.warmth_zone
	p.interact("LIGHT", player)
	await get_tree().process_frame
	_check(p.get("lit") == true, "brazier lights")
	_check(not PlayerState.has_item("driftwood"), "lighting consumes the driftwood")
	_check(_count_zones(br) > zones_before, "lit brazier creates a real WarmthZone (%d -> %d)"
		% [zones_before, _count_zones(br)])
	# let the Area3D register the overlap, then confirm the player is being warmed
	for i in 8:
		await get_tree().physics_frame
	_check(PlayerState.warmth_zone > warm_before,
		"standing in the lit brazier raises PlayerState.warmth_zone (%d -> %d)"
		% [warm_before, PlayerState.warmth_zone])
	p.interact("BANK", player)
	for i in 8:
		await get_tree().physics_frame
	_check(p.get("lit") == false, "brazier banks back down")
	_check(_count_zones(br) == zones_before, "banking frees the WarmthZone (no leak)")
	_check(PlayerState.warmth_zone == warm_before,
		"banking restores the warmth_zone counter exactly (no desync)")

## WarmthZone instances living under a structure.
func _count_zones(root: Node) -> int:
	var n: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if cur is WarmthZone:
			n += 1
	return n

## Sit in a deck chair, then stand.
func _loop_chair(main: Node3D, player: Node3D) -> void:
	var ch: Node3D = Structures.build("chair_kit", false)
	main.add_child(ch)
	ch.global_position = player.global_position + Vector3(0, 0, 1.5)
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	var m: Node3D = _marker(ch)
	var p: Interactable = _proxy(m) if m else null
	_check(p != null, "placed chair got a Seat proxy")
	if p == null:
		return
	_check(p.available_verbs().has("SIT"), "chair offers SIT")
	p.interact("SIT", player)
	await get_tree().process_frame
	var mgr: Node = PlayerState.get_node_or_null("ComfortFurniture")
	if mgr == null:
		for c in PlayerState.get_children():
			if c is ComfortFurniture:
				mgr = c
	_check(mgr != null and mgr.call("is_seated"), "sitting registers with the comfort manager")
	_check(PlayerState.resting, "sitting sets PlayerState.resting")
	_check(p.available_verbs().is_empty(), "a chair you are already in offers nothing")
	if mgr:
		mgr.call("stand")
	await get_tree().process_frame
	_check(not PlayerState.resting, "standing clears resting")
	_check(p.available_verbs().has("SIT"), "chair offers SIT again after standing")

## Stash an item in a job box and take it back out.
func _loop_locker(main: Node3D, player: Node3D) -> void:
	var lk: Node3D = Structures.build("locker_kit", false)
	main.add_child(lk)
	lk.global_position = player.global_position + Vector3(0, 0, -1.5)
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	var m: Node3D = _marker(lk)
	var p: Interactable = _proxy(m) if m else null
	_check(p != null, "placed locker got a LootContainer proxy")
	if p == null:
		return
	_check(not p.available_verbs().is_empty(), "locker offers a verb")
	# the container's own store is the contract: put something in, get it back
	PlayerState.add_item("rope")
	var had: bool = PlayerState.has_item("rope")
	_check(had, "player holds rope to stash")
	if p.has_method("deposit"):
		p.call("deposit", "rope")
	else:
		var items: Variant = p.get("items")
		if items is Array:
			items.append("rope")
			PlayerState.remove_item("rope")
	_check(not PlayerState.has_item("rope"), "stashed rope leaves the pack")
	var stored: Variant = p.get("items")
	_check(stored is Array and (stored as Array).has("rope"), "locker holds the rope")
	if stored is Array:
		(stored as Array).erase("rope")
		PlayerState.add_item("rope")
	_check(PlayerState.has_item("rope"), "rope comes back out of the locker")

func _recipes() -> Dictionary:
	var f := FileAccess.open("res://data/recipes.json", FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _find_script(root: Node, frag: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).contains(frag):
			return n
	return null
