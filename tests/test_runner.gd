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
	# Count every species the table can land — the net rolls from all of them.
	var n: int = 0
	for id in preload("res://scripts/world/fish_table.gd").all():
		n += _item_count(id)
	return n

## Swings of a `dmg` weapon a full-health giant crab survives before it turns over. Drives
## the REAL repel() on a real crab rather than doing the arithmetic here, so the answer
## covers the whole path the player's swing takes (player_controller._melee_attack -> repel)
## and not just a subtraction. Leaves the crab alive, on its roost, exactly as it found it.
func _crab_kill_hits(crab: Node3D, from: Node3D, dmg: float) -> int:
	var CrabS := preload("res://scripts/world/crab.gd")
	crab._respawn()
	crab.state = CrabS.State.PATROL
	crab.global_position = Vector3(20, 2.6, -10)
	var hits: int = 0
	while crab.state != CrabS.State.DEAD and hits < 99:
		crab.repel(from.global_position, dmg)
		hits += 1
	crab._respawn()
	return hits

func _item_count(id: String) -> int:
	var n: int = 0
	for it in PlayerState.hotbar:
		if it == id:
			n += 1
	for it in PlayerState.inventory:
		if it == id:
			n += 1
	return n

## Drive a decimated creature's _process until it is GUARANTEED to have thought at least
## once. AiBudget runs distant animals on every 2nd or 4th frame, so a single hand-driven
## `_process(0.016)` may legitimately be a frame that animal skips — which turned four
## snail-breeding checks into coin flips. AiBudget's own contract is that nothing ever goes
## longer than MAX_STEP without a tick, so pumping past that is deterministic, and it is a
## STRONGER test than one call was: the rule under test (two fed snails in range breed
## exactly one baby) has to hold across repeated ticks, not just land on the first.
func _pump(node: Node, seconds: float = AiBudget.MAX_STEP + 0.05, step: float = 0.016) -> void:
	var n: int = int(ceil(seconds / step))
	for i in range(n):
		node._process(step)

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

## ambience.gd::_collect_sway finds hanging things to blow about BY NAME FRAGMENT and then
## writes transform.basis on whatever it matched. exterior_dress.gd builds each prop as a
## node at the world origin with parts carrying absolute coordinates, so a rotation written
## to one of those nodes swings the whole prop through an arc as long as its distance from
## the middle of the map. That is how a lashed pallet load in the alley ended up hanging
## several metres over the deck in a storm, looking like a lifeboat.
##
## Two invariants keep it dead: every assembly is seated on its own geometry (so a stray
## rotation pivots it in place), and no assembly is named such that the sway collector
## claims it in the first place.
const SWAY_NAME_FRAGMENTS: Array[String] = [
	"hanging", "chain", "windsock", "flag", "banner", "tarp", "drying",
]

func _check_exterior_dress_anchors(main: Node) -> void:
	var dress: Node = _find_class(main, "exterior_dress.gd")
	_check(dress != null, "exterior dress built")
	if dress == null:
		return
	var assemblies: int = 0
	var adrift: Array[String] = []
	var swayable: Array[String] = []
	for child in dress.get_children():
		var a := child as Node3D
		if a == null or a is LightZone:
			continue
		var box: AABB = _visual_aabb(a)
		if box.size == Vector3.ZERO:
			continue
		assemblies += 1
		# The pivot must lie inside the prop's own silhouette (grown a little, so a flat
		# thing like the deck paint whose AABB has ~zero height still passes).
		var grown: AABB = box.grow(0.5)
		if not grown.has_point(a.global_position):
			adrift.append("%s@%.0f,%.0f,%.0f" % [a.name,
				a.global_position.x, a.global_position.y, a.global_position.z])
		var lower: String = String(a.name).to_lower()
		for frag in SWAY_NAME_FRAGMENTS:
			if lower.contains(frag):
				swayable.append(String(a.name))
				break
	_check(assemblies >= 30, "exterior dress assemblies present (found %d)" % assemblies)
	_check(adrift.is_empty(),
		"every exterior-dress assembly pivots inside itself (adrift: %s)" % str(adrift))
	_check(swayable.is_empty(),
		"no exterior-dress assembly is named as wind-sway fodder (matched: %s)" % str(swayable))

func _visual_aabb(n: Node3D) -> AABB:
	var acc := AABB()
	var first: bool = true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var vi := cur as VisualInstance3D
		if vi == null or vi.get_aabb().size == Vector3.ZERO:
			continue
		var a: AABB = vi.global_transform * vi.get_aabb()
		if first:
			acc = a
			first = false
		else:
			acc = acc.merge(a)
	return acc if not first else AABB()

## Physics ray between two world points. True if it hits any static body.
func _ray_blocked(main: Node3D, from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return not space.intersect_ray(q).is_empty()

## A point the player can stand on: solid floor just below, ~1.8m headroom clear above.
func _standable(main: Node3D, p: Vector3) -> bool:
	var has_floor: bool = _ray_blocked(main, p + Vector3(0, 1.2, 0), p + Vector3(0, -0.6, 0))
	var head_clear: bool = not _ray_blocked(main, p + Vector3(0, 0.3, 0), p + Vector3(0, 2.0, 0))
	return has_floor and head_clear

## The intended power route is physically walkable, and both annex doors are open holes.
## The "can a real player REACH the breaker room" guard - geometry, not story.
func _check_power_reachability(main: Node3D) -> void:
	var route := {
		"tower entry pad": Vector3(23.0, 2.0, -4.6),
		"landing 1 (machinery)": Vector3(29.25, 6.0, -1.0),
		"machinery floor": Vector3(26.0, 6.0, 7.5),
		"landing 2 (breaker)": Vector3(22.75, 10.0, -1.0),
		"breaker floor (by panel)": Vector3(24.0, 10.0, 7.9),
		"breaker floor (by cable gap)": Vector3(27.0, 10.0, 6.0),
	}
	var blocked: Array[String] = []
	for label in route:
		if not _standable(main, route[label]):
			blocked.append(label)
	_check(blocked.is_empty(),
		"whole power route is walkable, floor + headroom (blocked: %s)" % str(blocked))
	_check(not _ray_blocked(main, Vector3(28.5, 7.2, 0.8), Vector3(28.5, 7.2, 3.5)),
		"machinery-room doorway is an open hole")
	_check(not _ray_blocked(main, Vector3(23.5, 11.2, 0.8), Vector3(23.5, 11.2, 3.5)),
		"breaker-room doorway is an open hole")

func _run() -> void:
	# Every save/load check below writes real files under user://. Redirect the slot stem
	# to a throwaway so the suite can never overwrite the player's actual save slots.
	SaveManager.slot_file_prefix = "saltline_test_"
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

	_check_exterior_dress_anchors(main)

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
	# A real player has to physically reach the breaker room before any of this matters.
	# Let CSG collision finish baking before the reachability rays fly.
	for _pf in range(8):
		await get_tree().physics_frame
	_check_power_reachability(main)
	# The wet-deck notice that names the route + the on-panel order hint are both posted.
	_check(Readable._texts.has("breaker_notice"), "wet-deck power notice text exists")
	var wl_count: int = get_tree().get_nodes_in_group("wet_deck_worklights").size()
	_check(wl_count >= 3, "wet-deck worklights placed (found %d)" % wl_count)
	var wl_lit_before: int = 0
	for w in get_tree().get_nodes_in_group("wet_deck_worklights"):
		if (w as Light3D).visible:
			wl_lit_before += 1
	_check(wl_lit_before == 0, "wet-deck worklights start dark (unpowered)")
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
	# PAYOFF: closing the master must produce an unmistakable, wired reaction.
	var wl_lit_after: int = 0
	for w in get_tree().get_nodes_in_group("wet_deck_worklights"):
		if (w as Light3D).visible:
			wl_lit_after += 1
	_check(wl_lit_after == wl_count, "wet-deck worklights light up when powered")
	_check(Journal.discovered.has("place_power"), "power-restored journal entry fires")
	# The breaker's own toast/objective is the final word: it names the payoff (floodlights).
	_check(main.hud.objective_label.text.to_lower().contains("floodlight"),
		"objective updates to the power-on payoff")

	# ---- move_slot: the one verb the inventory panel's pick-then-place click runs on.
	# Every direction has to work, because the old panel could only do pack->hand and
	# hand->end-of-pack and that is exactly what made it feel glitchy.
	PlayerState.hotbar = PlayerState._new_hotbar()
	PlayerState.hotbar_counts = PlayerState._new_hotbar_counts()
	PlayerState.inventory.clear()
	PlayerState.inventory_counts.clear()
	PlayerState.hotbar[0] = "flare"
	PlayerState.hotbar[2] = "bandage"
	PlayerState.inventory.append("scrap_metal")
	PlayerState.inventory_counts.append(3)
	var H: int = PlayerState.HOTBAR_SIZE
	# hotbar -> empty hotbar slot
	_check(PlayerState.move_slot(0, 1), "move_slot: hotbar to an empty hotbar slot")
	_check(PlayerState.hotbar[1] == "flare" and PlayerState.hotbar[0] == null,
		"the flare moved and vacated its old slot")
	# hotbar -> occupied hotbar slot exchanges both ways
	PlayerState.move_slot(1, 2)
	_check(PlayerState.hotbar[2] == "flare" and PlayerState.hotbar[1] == "bandage",
		"move_slot: two occupied hotbar slots exchange")
	# pack -> hotbar, counts carried
	_check(PlayerState.move_slot(H + 0, 0), "move_slot: pack to hotbar")
	_check(PlayerState.hotbar[0] == "scrap_metal" and int(PlayerState.hotbar_counts[0]) == 3,
		"the whole stack of 3 came with it")
	_check(PlayerState.inventory.is_empty(), "the emptied pack entry is removed, not left null")
	# hotbar -> the empty cell past the end of the pack = stow
	_check(PlayerState.move_slot(0, H + 0), "move_slot: hotbar stows into an empty pack")
	_check(PlayerState.inventory.size() == 1 and PlayerState.hotbar[0] == null,
		"stowing appends to the pack and clears the hand")
	# pack -> pack reorder (was impossible before)
	PlayerState.inventory.append("rope")
	PlayerState.inventory_counts.append(1)
	PlayerState.move_slot(H + 0, H + 1)
	_check(PlayerState.inventory[0] == "rope" and PlayerState.inventory[1] == "scrap_metal",
		"move_slot: two pack slots reorder")
	# same id merges into one stack instead of shuffling two of the same thing
	PlayerState.hotbar[0] = "scrap_metal"
	PlayerState.hotbar_counts[0] = 2
	PlayerState.move_slot(0, H + 1)
	_check(int(PlayerState.inventory_counts[1]) == 5 and PlayerState.hotbar[0] == null,
		"move_slot: two stacks of the same item merge")
	# a move that means nothing is refused rather than corrupting a slot
	_check(not PlayerState.move_slot(3, 3), "move_slot: same slot is a no-op")
	_check(not PlayerState.move_slot(3, 0), "move_slot: an empty source is a no-op")
	# move to ANY empty pack slot, not just the one immediately past the end (owner report,
	# 2026-07-27: "clicks an item, clicks a new spot, item should just move there — currently
	# it only swaps with another item"). Two items in, one far-empty slot targeted directly.
	PlayerState.inventory.append("flare")
	PlayerState.inventory_counts.append(1)
	PlayerState.inventory.append("bandage")
	PlayerState.inventory_counts.append(1)
	var far_empty: int = H + 5   # well past inventory.size() == 2, still inside capacity
	_check(PlayerState.move_slot(H + 0, far_empty),
		"move_slot: a distant empty pack slot is a legal target, not just the next one")
	_check(PlayerState.inventory.has("flare") and not PlayerState.inventory.is_empty(),
		"the moved item actually landed in the pack rather than vanishing")
	PlayerState.hotbar = PlayerState._new_hotbar()
	PlayerState.hotbar_counts = PlayerState._new_hotbar_counts()
	PlayerState.inventory.clear()
	PlayerState.inventory_counts.clear()

	# ---- hotbar/backpack sizing (owner call, 2026-07-27): 4 -> 6 hotbar, +6 backpack.
	_check(PlayerState.HOTBAR_SIZE == 6, "hotbar grew to 6 slots")
	_check(PlayerState.hotbar.size() == 6, "the live hotbar array matches HOTBAR_SIZE")
	_check(PlayerState.MAX_BACKPACK == 18, "base backpack grew to 18 slots")

	# Inventory + eating.
	PlayerState.add_item("canned_food")
	var before: float = 0.4
	PlayerState.hunger = before
	var slot: int = PlayerState.hotbar.find("canned_food")
	_check(slot != -1, "canned food in hotbar")
	PlayerState.use_hotbar(slot)
	_check(PlayerState.hunger > before, "eating restores hunger")

	# Giant crabs: SIX small ones around the base of the rig — underwater cling roosts by
	# day (surface-frame seated on the leg faces, no hover), a climb over the EAST deck rim
	# at night, a 0.2-life bite, brightness-gated light scare, and scuttle audio hard-gated
	# on visibility. Read the count from BloomFauna rather than restating it: this assertion
	# has already gone stale twice (its own comment still said "a pack of TEN" while it was
	# checking for fourteen), and a test that has to be hand-edited to match a design tweak
	# is a test that will be wrong again.
	var CrabS := preload("res://scripts/world/crab.gd")
	var Bloom := preload("res://scripts/world/bloom_fauna.gd")
	var want_crabs: int = Bloom.CRAB_COUNT
	var crabs: Array = get_tree().get_nodes_in_group("giant_crab")
	_check(crabs.size() == want_crabs,
		"%d giant crabs live on the rig (got %d)" % [want_crabs, crabs.size()])
	var under: int = 0
	var on_deck: int = 0
	var at_legs: int = 0
	for cc in crabs:
		var cp: Vector3 = (cc as Node3D).global_position
		if cp.y > 0.5:
			on_deck += 1
		else:
			under += 1
		if absf(absf(cp.x) - 22.0) < 5.0 and absf(absf(cp.z) - 12.0) < 5.0:
			at_legs += 1
	_check(under == crabs.size(), "the whole pack roosts below the waterline by day (%d)" % under)
	_check(on_deck == 0, "no crab is up on deck in daylight — night is their hour (%d)" % on_deck)
	_check(at_legs == crabs.size(), "every day roost clings to a caisson leg (%d/%d)" % [at_legs, crabs.size()])
	var lamp_free: bool = crabs.size() > 0
	for cc in crabs:
		if not (cc as Node).find_children("*", "Light3D", true, false).is_empty():
			lamp_free = false
	_check(lamp_free, "no crab carries a lamp or any light node (naturalistic)")
	var crab: Node3D = crabs[0] if crabs.size() > 0 else null
	if crab:
		# Night hunt: emerged crab + dark deck + player in reach -> PURSUE.
		GameClock.force_phase(GameClock.Phase.NIGHT)
		crab.state = CrabS.State.PATROL   # emerged (the staged climb is tested via FLEE below)
		crab.global_position = Vector3(20, 2.6, -10)
		player.global_position = Vector3(21, 2.6, -10)   # dark wet deck, 1m away
		await get_tree().process_frame
		await get_tree().process_frame
		_check(crab.state == CrabS.State.PURSUE, "crab hunts the player in darkness")
		# The bite: 0.25 normalized life + a shove, on a cooldown — no blackout teleport.
		PlayerState.life = 1.0
		crab._bite_cd = 0.0
		crab._try_bite(player)
		_check(absf(PlayerState.life - 0.8) < 0.001, "a bite costs 0.2 life")
		_check(crab._bite_cd > 0.0, "bites are on a cooldown")
		# Light scare: a held torch beam on it for half a second sends it to the water.
		PlayerState.add_item("flashlight")
		var fslot: int = PlayerState.hotbar.find("flashlight")
		_check(fslot != -1, "flashlight lands in the hotbar")
		PlayerState.selected_hotbar = fslot
		player._flashlight_on = true
		crab.state = CrabS.State.PURSUE
		crab._recoil = 0.0
		var cam3: Camera3D = player.get_node("Head/Camera3D") as Camera3D
		crab.global_position = cam3.global_position + (-cam3.global_transform.basis.z) * 3.0
		_check(player.light_aimed_at(crab.global_position + Vector3(0, 0.3, 0)),
			"a held flashlight beam reads as aimed at the crab")
		crab._lit_t = 0.0
		crab._check_light_scare(0.6, player)
		_check(crab.state == CrabS.State.FLEE, "a beam-lit crab bolts for the water")
		_check(crab._scare_cd > 0.0, "scared crab re-approaches on a cooldown")
		PlayerState.remove_item("flashlight")
		# Scuttle audio gate: silence unless the crab is near AND actually visible.
		crab.global_position = player.global_position + Vector3(30, 0, 0)
		_check(not crab._audio_gate_open(), "scuttle audio gated silent beyond 10 m")
		crab.global_position = cam3.global_position + cam3.global_transform.basis.z * 3.0
		_check(not crab._audio_gate_open(), "scuttle audio gated silent behind the camera")
		player.global_position = Vector3(45, 60, -45)   # open air: nothing to occlude
		await get_tree().physics_frame
		await get_tree().physics_frame
		crab.global_position = cam3.global_position + (-cam3.global_transform.basis.z) * 4.0
		_check(crab._audio_gate_open(), "scuttle audio opens when near, framed, and unoccluded")
		# Dawn: deck crabs visibly head back over the rim (FLEE walks the climb reversed).
		crab.state = CrabS.State.PATROL
		GameClock.force_phase(GameClock.Phase.DAWN)
		_check(crab.state == CrabS.State.FLEE, "dawn sends deck crabs back to the water")
		_check(not main._ending, "dawn does not end the game (open-ended survival)")

		# --- KILLING ONE, AND WHAT COMES OFF IT (owner spec, 2026-07-26) -----------------
		# Four spear hits, six knife hits. Asserted against the REAL melee_damage out of
		# data/items.json rather than a hand-copied 1.7 and 1.0: the crab's health pool is
		# derived from those numbers (crab.gd MAX_HP), so if anyone retunes a weapon this is
		# the test that says the pool has to move with it. The crude pair is what the spec's
		# counts describe — they are the first two weapons anyone on this rig owns — and the
		# honed pair is asserted to be strictly FASTER, which is what honing is for.
		var spear_dmg: float = float(PlayerState.items.get("crude_spear", {}).get("melee_damage", 0.0))
		var knife_dmg: float = float(PlayerState.items.get("crude_knife", {}).get("melee_damage", 0.0))
		var hspear_dmg: float = float(PlayerState.items.get("honed_spear", {}).get("melee_damage", 0.0))
		var hknife_dmg: float = float(PlayerState.items.get("honed_knife", {}).get("melee_damage", 0.0))
		_check(_crab_kill_hits(crab, player, spear_dmg) == 4, "a crude spear kills a giant crab in 4 hits")
		_check(_crab_kill_hits(crab, player, knife_dmg) == 6, "a crude knife kills a giant crab in 6 hits")
		_check(_crab_kill_hits(crab, player, hspear_dmg) < 4, "a honed spear kills it quicker than a crude one")
		_check(_crab_kill_hits(crab, player, hknife_dmg) < 6, "a honed knife kills it quicker than a crude one")

		# The corpse. It is the SAME node — nothing is freed — turned over on its back with
		# its legs drawn in, and its touch collider is live where it was dead before.
		crab._respawn()
		crab.state = CrabS.State.PATROL
		crab.global_position = Vector3(20, 2.6, -10)
		while crab.state != CrabS.State.DEAD:
			crab.repel(player.global_position, spear_dmg)
		_check(is_instance_valid(crab), "a killed crab stays in the world as a corpse")
		_check(crab.corpse_touch != null and (crab.corpse_touch as CollisionObject3D).collision_layer == 1,
			"the corpse becomes something you can walk up to")
		for k in range(6):
			crab._dead_tick(0.4)          # let the flop settle
		if crab._model != null:
			_check(absf(crab._model.rotation.z - PI) < 0.25, "the corpse has turned over onto its back")
			_check(crab._model.scale.y < crab._model_scale0.y, "the corpse has curled up")

		# Eight legs, and they are food AND bait.
		_check(crab.corpse_verbs() == ["HARVEST"], "a fresh corpse offers HARVEST")
		# count_item, not _item_count: legs stack, so the whole harvest lands in ONE slot and
		# a slot count would read eight legs as "1".
		var legs_before: int = PlayerState.count_item("crab_leg")
		crab.corpse_act("HARVEST", player)
		_check(PlayerState.count_item("crab_leg") - legs_before == 8,
			"harvesting a crab corpse yields 8 crab legs")
		_check(crab.corpse_verbs().is_empty(), "a picked-clean shell offers nothing more")
		_check(PlayerState.items.get("crab_leg", {}).get("use", "") == "eat",
			"a crab leg is food")
		# Bait: the deep rig takes cheaper bait first, so clear the pack of chum before
		# asking — and put it back afterwards, since later checks own those items.
		var had_snail: int = PlayerState.count_item("snail_live")
		var had_rot: int = PlayerState.count_item("fish_rotten")
		while PlayerState.remove_item("snail_live"):
			pass
		while PlayerState.remove_item("fish_rotten"):
			pass
		var rod_probe: Node = preload("res://scripts/components/fishing_rod.gd").new()
		_check(rod_probe._find_bait() == "crab_leg", "a crab leg baits the deep-drop rig")
		rod_probe.free()
		for k in range(had_snail):
			PlayerState.add_item("snail_live")
		for k in range(had_rot):
			PlayerState.add_item("fish_rotten")

		# Respawn: the next DUSK, and nothing before it. A crab that popped back up mid-hunt
		# would make the fight pointless and take the corpse out from under the player.
		GameClock.force_phase(GameClock.Phase.NIGHT)
		_check(crab.state == CrabS.State.DEAD, "a corpse does not get up during the night it died in")
		GameClock.force_phase(GameClock.Phase.DAWN)
		_check(crab.state == CrabS.State.DEAD, "the corpse lies through the day, harvestable in daylight")
		GameClock.force_phase(GameClock.Phase.DUSK)
		_check(crab.state == CrabS.State.ROOST, "dusk puts a fresh crab back on its roost")
		_check(is_equal_approx(crab.hp, CrabS.MAX_HP), "the respawned crab is whole again")
		_check(crab.global_position.y < 0.5, "the respawned crab is back under the waterline")

		# The supports: most of the pack is authored a climb up its own caisson leg. The
		# geometry of those routes is proven in CrabNightProbe (it sphere-casts every
		# waypoint and every landing); all this asserts is that they were handed out.
		var with_routes: int = 0
		for cc in crabs:
			if not (cc.leg_climb as Array).is_empty():
				with_routes += 1
		_check(with_routes >= 4, "most of the pack climbs the rig supports at night (%d of %d)"
			% [with_routes, crabs.size()])

		GameClock.force_phase(GameClock.Phase.DAWN)   # leave the clock where this block found it
		# Put the crab back on its roost so later checks see the resting pack.
		crab.state = CrabS.State.ROOST
		crab._scare_cd = 0.0
		if not crab.roost_loop.is_empty():
			crab.global_position = crab.roost_loop[0]

	# Lamp snails: gentle bioluminescent pools at night. Identify the snails DIRECTLY by
	# their group (not by light colour): a planter kit's glow light is an exact-match teal
	# with the same shadow/range signature, so a colour probe would miscount if one is ever
	# pre-placed. Each lamp snail owns exactly one shadow-off OmniLight3D in the range band.
	var snail_lights: Array = []
	for snail in get_tree().get_nodes_in_group("snail_lamp"):
		var stack: Array[Node] = [snail]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is OmniLight3D and n.shadow_enabled == false \
					and n.omni_range >= 2.5 and n.omni_range <= 3.5:
				snail_lights.append(n)
	# One light each, so this is a head count. s20 added lamp snails on the CAISSON FACES
	# (leg_reef.gd::_grow_snails) on top of BloomFauna's six on the pontoon tops, so the
	# invariant worth asserting is "every lamp snail owns exactly one" rather than a fixed
	# total that any new habitat breaks.
	_check(snail_lights.size() == get_tree().get_nodes_in_group("snail_lamp").size(),
		"every lamp snail owns exactly one bioluminescent light (%d)" % snail_lights.size())
	# Check that lights have proper range (2.5-3.5m) and are shadows-off for gl_compatibility.
	var snail_light_range_ok: bool = true
	for light in snail_lights:
		if light.omni_range < 2.5 or light.omni_range > 3.5:
			snail_light_range_ok = false
			break
	_check(snail_light_range_ok, "lamp snail light range is in expected band (2.5-3.5m)")

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
		main.storm._cover_frac = 0.0                 # open sky
		main.storm._apply_intensity()
		await get_tree().process_frame
		_check(main.storm._rain.emitting, "storm rain emits at full intensity")
		# Rain no longer stops when the player is sheltered: it keeps falling and the
		# particle shader scales drops inside roofed volumes to zero, so a squall is
		# still visible through every window and across every open deck.
		main.storm._cover_frac = 1.0                 # under a roof -> still emitting
		main.storm._roof_dist = 3.0
		main.storm._apply_intensity()
		_check(main.storm._rain.emitting, "storm rain keeps emitting under a roof")
		var rain_mat: Material = main.storm._rain.process_material
		_check(rain_mat is ShaderMaterial, "rain uses the covered-volume particle shader")
		_check(int((rain_mat as ShaderMaterial).get_shader_parameter("box_count")) > 0,
			"covered volumes baked into the rain shader")
		main.storm._cover_frac = 0.0
		main.storm._apply_intensity()
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
	_check(stove != null, "dining hall range exists")
	if stove:
		# Per-species cooking: a herring sears to its OWN meal, not a generic fillet.
		# The range now takes CookStove.COOK_SECONDS and needs mains power (the breaker
		# was closed above), so the cook is started and then driven to completion rather
		# than resolving inside interact().
		var cooked_before: int = _item_count("cooked_fish_herring")
		stove.interact("COOK", player)
		_check(stove._cooking, "the range lights up and starts cooking")
		_check(_item_count("fish_herring") == herring_before, "the raw fish goes in when the cook starts")
		stove._timer = 0.0
		stove._process(0.016)
		_check(not stove._cooking, "the cook finishes and the range goes cold")
		_check(_item_count("cooked_fish_herring") > cooked_before, "stove sears raw fish into its species meal")
		_check(_item_count("fish_herring") == herring_before, "searing consumes the raw fish")
		PlayerState.hunger = 0.2
		var cslot: int = PlayerState.hotbar.find("cooked_fish_herring")
		if cslot == -1:
			PlayerState.add_item("cooked_fish_herring")
			cslot = PlayerState.hotbar.find("cooked_fish_herring")
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

	# Swimming: water is survivable now — buoyant, cold, and mortal only when your
	# breath runs out. No fixed deep-death line: depth is free, air is the clock.
	GameClock.force_phase(GameClock.Phase.DAY)
	player.input_locked = false
	player.global_position = Vector3(0, -1.5, -34)
	player.velocity = Vector3.ZERO
	PlayerState.oxygen = 1.0
	player._check_water()
	_check(player.swimming, "entering water starts swimming, not a respawn")
	var warmth_before: float = PlayerState.warmth
	player._swim_process(0.5)
	_check(PlayerState.warmth < warmth_before, "cold water drains warmth")
	_check(not player._drowning, "surface swimming does not black out")
	# Diving deep is now allowed: past the old 13m line, a full breath does NOT kill you.
	PlayerState.oxygen = 1.0
	player.global_position = Vector3(0, -16.0, -34)
	player.velocity = Vector3.ZERO
	player._swim_process(0.5)
	_check(not player._drowning, "diving deep on a full breath no longer drowns you")
	_check(PlayerState.oxygen < 1.0, "submerging spends the breath (oxygen drains)")
	# ...but an EMPTY breath held underwater does drown you, to the usual respawn.
	PlayerState.oxygen = 0.0
	player._airless_t = 0.0
	player._drowning = false
	for _i in range(24):
		player.global_position = Vector3(0, -6.0, -34)   # hold them under the swell
		player.velocity = Vector3.ZERO
		player._swim_process(0.1)
		if player._drowning:
			break
	_check(player._drowning or player.global_position.distance_to(player.respawn_point) < 3.0,
		"an empty breath underwater drowns you")
	await get_tree().create_timer(2.0).timeout   # let the fade/respawn resolve
	player.input_locked = false
	PlayerState.oxygen = 1.0
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
	# WHICH fish actually went on the hook matters, and the old assertion did not say.
	# _hang() takes the first hangable thing in the player's hotbar/pack, not necessarily
	# the herring this block just added — so anything an earlier check left in the pack can
	# be hung instead, and a BIG fish cures to dried_fish rather than rotting. That made
	# this check a silent hostage to test order. Report what was hung and what it became.
	var hung_id: String = String(line._hung[0]["id"])
	line._hung[0]["age_h"] = 4.1
	line._process(0.016)
	_check(line._hung[0]["id"] == "fish_rotten",
		"raw fish rots after 4 game hours hung (hung %s -> %s)" % [hung_id, line._hung[0]["id"]])
	# Isolate the cure test: the drop-net haul above leaves random raw species in the
	# pack, and _hang() takes the first hangable fish it finds — so without clearing,
	# slot 1 sometimes got a leftover raw fish (which rots) instead of the cooked one.
	PlayerState.load_inventory([], [], [], [])
	PlayerState.add_item("cooked_fish")
	line._hang()
	line._hung[1]["age_h"] = 4.1
	line._process(0.016)
	_check(line._hung[1]["id"] == "dried_fish", "cooked fish cures to dried on the line")
	line._take()
	_check(PlayerState.has_item("dried_fish"), "taking from the line returns the cured fish")
	# The fridge is a LootContainer now: it uses the ordinary crate ⇄ pack panel instead
	# of its own STOW/TAKE verbs, and what makes it a fridge is that its contents only
	# spoil while it is UNPOWERED. The breaker was closed earlier in this run.
	var fridge: Node = preload("res://scripts/components/cold_store.gd").new()
	main.add_child(fridge)
	fridge.items = ["fish_herring"] as Array[String]
	_check(fridge.get_prompt().contains("1 cold"), "powered fridge reports its contents")
	fridge._warm_h = fridge.FRESH_HOURS + 0.1
	fridge._process(0.016)
	_check(fridge.items[0] == "fish_herring", "a powered fridge holds the catch fresh")
	PowerGrid.lose_circuit("topside_floodlights")
	_check(fridge.get_prompt().contains("no power"), "an unpowered fridge says so")
	fridge.interact("OPEN", player)   # refuses, quietly — must not throw or lose contents
	_check(fridge.items.size() == 1, "an unpowered fridge keeps hold of what is in it")
	fridge._warm_h = fridge.FRESH_HOURS + 0.1
	fridge._process(0.016)
	_check(fridge.items[0] == "fish_rotten", "a warm fridge lets the catch turn")
	PowerGrid.power_circuit("topside_floodlights")

	# Drop net reaches water from the topside deck now (DROP_MAX fix).
	var top_net: Node3D = Structures.build("drop_net_kit", false)
	main.add_child(top_net)
	top_net.global_position = Vector3(26, DECK_Y_TEST + 0.15, -30)
	await get_tree().physics_frame
	var top_winch: Node = _find_class(top_net, "drop_net")
	if top_winch:
		top_winch.interact("LOWER", player)
		_check(top_winch._wet, "topside drop net reaches the water")

	# Corvid theft: the thief carries a loose deck item to the nest cache.
	var corvid: Node3D = null
	var nest_node: Node = null
	var cstack: Array[Node] = [main]
	while not cstack.is_empty():
		var cn: Node = cstack.pop_back()
		for cc in cn.get_children():
			cstack.append(cc)
		if cn.get("thief") != null and cn.thief:
			corvid = cn
		if cn.is_in_group("gull_nest"):
			nest_node = cn
	_check(corvid != null, "a thief corvid exists")
	_check(nest_node != null, "the gull nest cache exists")
	if corvid and nest_node:
		var bait := Takeable.new()
		bait.item_id = "rope"
		bait.display_name = "Rope Coil"
		main.add_child(bait)
		bait.global_position = Vector3(5, DECK_Y_TEST + 0.2, 0)
		await get_tree().process_frame
		corvid._target = bait
		corvid._steal_phase = 1
		corvid.global_position = bait.global_position
		corvid._theft(0.1)   # grab
		_check(corvid._steal_phase == 2 and corvid._loot_id == "rope", "corvid grabs loose loot")
		corvid.global_position = nest_node.global_position + Vector3(0, 0.6, 0)
		corvid._theft(0.1)   # deposit
		_check(nest_node.items.has("rope"), "stolen loot lands in the nest cache")
	# Crab anatomy (s11): the persistent giant crab — generated mesh preferred, eight
	# articulated procedural legs as the fallback. Naturalistic: no lamp (asserted above).
	var crab2: Node3D = null
	for c2 in get_tree().get_nodes_in_group("giant_crab"):
		crab2 = c2
	if crab2:
		_check(crab2._model != null or crab2._legs.size() == 8,
			"crab has a body: generated mesh or eight articulated legs")
		if crab2._model != null:
			_check(not crab2._mats.is_empty(), "generated crab is driven by the motion shader")
	var overlay_hidden: bool = true
	for leg in crab2._legs:
		for m in (leg["hip"] as Node3D).get_children():
			if m is MeshInstance3D and (m as MeshInstance3D).visible:
				overlay_hidden = false
	_check(overlay_hidden,
		"the procedural fallback limbs stay hidden under the generated shell")
	GameClock.force_phase(GameClock.Phase.DAY)

	# Save round-trip.
	SaveManager.save_game()
	PlayerState.hunger = 0.123
	var ok: bool = SaveManager.load_game()
	_check(ok, "save file loads")
	_check(absf(PlayerState.hunger - 0.123) > 0.01, "load restores saved hunger")

	# --- comfort + camp persistence -----------------------------------------
	# These were dead code for a whole batch: comfort_payload()/apply_comfort_payload()
	# existed and were correct, but nothing called them, so a night's rest and the
	# one-time camp acknowledgement reset on every load. Guard the wiring, not the maths.
	PlayerState.rest = 0.42
	PlayerState.comfort = 0.66
	PlayerState.camp_found = true
	PlayerState.thirst = 0.31
	SaveManager.save_game()
	PlayerState.rest = 1.0
	PlayerState.comfort = 0.0
	PlayerState.camp_found = false
	PlayerState.thirst = 1.0
	_check(SaveManager.load_game(), "save reloads after a comfort write")
	_check(absf(PlayerState.rest - 0.42) < 0.02, "load restores rest")
	_check(absf(PlayerState.comfort - 0.66) < 0.02, "load restores comfort")
	_check(PlayerState.camp_found, "load restores camp_found (the camp line stays one-time)")
	_check(absf(PlayerState.thirst - 0.31) < 0.02, "load restores thirst")

	# --- built structures survive a reload -----------------------------------
	# "Build personal areas" is the stated goal; a camp that evaporates on load is
	# not a camp. Structures serialise as kit id + transform and rebuild via
	# Structures.build, so this asserts the round-trip, not the geometry.
	for leftover in get_tree().get_nodes_in_group("built_structures"):
		leftover.free()
	var kit_a: Node3D = Structures.build("brazier_kit", false)
	get_tree().current_scene.add_child(kit_a)
	kit_a.global_position = Vector3(11.0, 19.0, -4.0)
	var kit_b: Node3D = Structures.build("chair_kit", false)
	get_tree().current_scene.add_child(kit_b)
	kit_b.global_position = Vector3(12.5, 19.0, -4.0)
	await get_tree().process_frame
	SaveManager.save_game()
	for s in get_tree().get_nodes_in_group("built_structures"):
		s.free()
	_check(get_tree().get_nodes_in_group("built_structures").is_empty(),
		"the camp is torn down before the reload")
	_check(SaveManager.load_game(), "save reloads with structures in it")
	await get_tree().process_frame
	var back: Array = get_tree().get_nodes_in_group("built_structures")
	_check(back.size() == 2, "both placed structures come back (got %d)" % back.size())
	var kits: Array = []
	var placed_ok: bool = false
	for s in back:
		kits.append(String((s as Node3D).get_meta("kit", "")))
		if String((s as Node3D).get_meta("kit", "")) == "brazier_kit":
			placed_ok = (s as Node3D).global_position.distance_to(Vector3(11.0, 19.0, -4.0)) < 0.05
	_check(kits.has("brazier_kit") and kits.has("chair_kit"),
		"they come back as the right kits")
	_check(placed_ok, "they come back where they were put")
	# Loading twice must not double the camp.
	_check(SaveManager.load_game(), "save reloads a second time")
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("built_structures").size() == 2,
		"a second load does not duplicate the camp")

	# --- found lockers/cabinets are real, working, persistent containers ------------
	# Bunkhouse "wardrobe" lockers and the Deck B cabin lockers used to be a bare
	# collision box with no name match and no Interactable — pure scenery a player
	# could stand next to forever and never open. rig_builder._wardrobe_locker and
	# rig_superstructure._locker now hang a real LootContainer there.
	var found_lockers: Array[LootContainer] = []
	for c in get_tree().get_nodes_in_group("loot_container"):
		if c is LootContainer and String((c as LootContainer).display_name).to_lower().contains("locker"):
			found_lockers.append(c as LootContainer)
	_check(found_lockers.size() >= 10,
		"bunkhouse + cabin lockers are real openable containers (got %d)" % found_lockers.size())
	if not found_lockers.is_empty():
		var test_locker: LootContainer = found_lockers[0]
		var locker_before: Array[String] = test_locker.items.duplicate()
		test_locker.items = ["rope"]
		SaveManager.save_game()
		test_locker.items = []   # simulate the world coming back empty before load
		_check(SaveManager.load_game(), "save reloads with a stowed locker item in it")
		_check(test_locker.items.has("rope"), "an item stowed in a found locker survives a reload")
		test_locker.items = locker_before   # leave the world as this test found it

	# --- a crafted storage bin holds items and survives a reload ---------------------
	# storage_bin_kit is bench-craftable (recipes.json) and, via ComfortFurniture's
	# "storage" contract, gets a real LootContainer proxy — the same crate <-> pack
	# exchange every other stash uses. Prove the whole chain: craft, stow, save, reload.
	var bin: Node3D = Structures.build("storage_bin_kit", false)
	get_tree().current_scene.add_child(bin)
	bin.global_position = Vector3(13.0, 19.0, -4.0)
	await get_tree().process_frame
	await get_tree().create_timer(1.7).timeout   # ComfortFurniture's RESCAN_SEC sweep
	var bin_box: LootContainer = null
	for m in get_tree().get_nodes_in_group("comfort_furniture"):
		if not is_instance_valid(m):
			continue
		if String((m as Node3D).get_meta("kind", "")) != "storage":
			continue
		if (m as Node3D).global_position.distance_to(bin.global_position) > 1.0:
			continue
		for ch in m.get_children():
			if ch is LootContainer:
				bin_box = ch as LootContainer
	_check(bin_box != null, "a crafted storage bin gets a working container")
	if bin_box:
		bin_box.items = ["scrap_metal"]
		SaveManager.save_game()
		_check(SaveManager.load_game(), "save reloads with the crafted storage bin in it")
		await get_tree().process_frame
		var bin2: Node3D = null
		for s in get_tree().get_nodes_in_group("built_structures"):
			if String((s as Node3D).get_meta("kit", "")) == "storage_bin_kit":
				bin2 = s as Node3D
		_check(bin2 != null, "the crafted storage bin comes back after reload")
		if bin2:
			await get_tree().create_timer(1.7).timeout   # let the proxy re-attach
			var bin2_box: LootContainer = null
			for ch in bin2.get_children():
				if ch is Node3D and (ch as Node3D).is_in_group("comfort_furniture"):
					for gc in ch.get_children():
						if gc is LootContainer:
							bin2_box = gc as LootContainer
			_check(bin2_box != null and bin2_box.items.has("scrap_metal"),
				"crafted storage bin contents survive a reload")

	# --- Snail feeding + breeding + escargot ----------------------------------------
	# Kelp Bundle is the existing greens item (already edible, already harvestable near
	# the boat landing at wet_deck_detail.gd) — the "reachable without deep-death" greens
	# source the spec asked for, so no new item was needed.
	_check(_find_takeable(main, "kelp_bundle") != null, "kelp bundle is harvestable on the open deck")

	var lamp_snails: Array = get_tree().get_nodes_in_group("snail_lamp")
	# BloomFauna seeds six on the pontoon tops; LegReef seeds more on the submerged caisson
	# faces (s20). Both are deterministic, and what this guards is that nothing has BRED yet
	# — every snail standing at this point must be an adult with a distinct index.
	var lamp_ids: Dictionary = {}
	for ls in lamp_snails:
		lamp_ids[int(ls.get("_idx"))] = true
	_check(lamp_snails.size() >= 6 and lamp_ids.size() == lamp_snails.size()
			and not lamp_snails.any(func(n: Node) -> bool: return bool(n.get("_is_baby"))),
		"lamp snails spawn as %d distinct adults before any breeding" % lamp_snails.size())
	if lamp_snails.size() >= 3:
		var sa: Node3D = lamp_snails[0]
		var sb: Node3D = lamp_snails[1]
		var sc: Node3D = lamp_snails[2]
		sb.global_position = sa.global_position + Vector3(0.5, 0, 0)   # inside BREED_RADIUS
		PlayerState.load_inventory([], [], [], [])
		PlayerState.add_item("kelp_bundle")
		PlayerState.add_item("kelp_bundle")
		sa._feed(player)
		_check(sa._fed, "feeding a lamp snail sets its fed flag")
		sb._feed(player)
		_pump(sb)   # the breed check runs continuously in _process, not in _feed
		var babies: Array = get_tree().get_nodes_in_group("snail_lamp").filter(
			func(n: Node) -> bool: return bool(n.get("_is_baby")))
		_check(babies.size() == 1, "two fed lamp snails within range spawn exactly one permanent baby")
		_check(not sa._fed and not sb._fed, "breeding resets both parents' fed flag")
		if not babies.is_empty():
			var baby: Node3D = babies[0]
			_check(is_instance_valid(baby) and baby.get_parent() != null, "the baby is a live node in the tree")
			baby.set("_grow_h", 999.0)
			_pump(baby)
			_check(not bool(baby.get("_is_baby")), "a baby fully grows into an adult after enough game-hours")
		# COLLECT (crouch-gated in play; called directly here like every other private
		# interaction method the suite exercises) removes the snail and yields snail_live.
		PlayerState.load_inventory([], [], [], [])
		sc._collect(player)
		_check(PlayerState.has_item("snail_live"), "collecting a snail yields snail_live")
		_check(sc.is_queued_for_deletion(), "the collected snail is removed from the world")
		var stove3: Node = _find_class(main, "cook_stove")
		if stove3:
			PlayerState.hunger = 0.2
			PlayerState.comfort = 0.0
			stove3.interact("COOK", player)
			stove3._timer = 0.0
			stove3._process(0.016)
			_check(PlayerState.has_item("escargot"), "the stove sears snail_live into escargot")
			_check(not PlayerState.has_item("snail_live"), "cooking consumes the raw snail")
			var eslot: int = PlayerState.hotbar.find("escargot")
			if eslot == -1:
				PlayerState.add_item("escargot")
				eslot = PlayerState.hotbar.find("escargot")
			PlayerState.use_hotbar(eslot)
			_check(PlayerState.hunger > 0.5, "eating escargot restores hunger")
			_check(PlayerState.comfort > 0.0, "eating escargot gives a small comfort bonus")

	# Rust and glass snails breed the same way; species never cross-breed (find_breed_partner
	# matches on the exact script, so a fed lamp snail never pairs with a fed rust snail).
	var rust_snails: Array = get_tree().get_nodes_in_group("snail_rust")
	if rust_snails.size() >= 2:
		var ra: Node3D = rust_snails[0]
		var rb: Node3D = rust_snails[1]
		rb.global_position = ra.global_position + Vector3(0.5, 0, 0)
		PlayerState.load_inventory([], [], [], [])
		PlayerState.add_item("kelp_bundle")
		PlayerState.add_item("kelp_bundle")
		ra._feed(player)
		rb._feed(player)
		_pump(rb)
		var rust_babies: Array = get_tree().get_nodes_in_group("snail_rust").filter(
			func(n: Node) -> bool: return bool(n.get("_is_baby")))
		_check(rust_babies.size() == 1, "two fed rust snails within range spawn a baby")

	var glass_snails: Array = get_tree().get_nodes_in_group("snail_glass")
	if glass_snails.size() >= 2:
		var ga: Node3D = glass_snails[0]
		var gb: Node3D = glass_snails[1]
		gb.global_position = ga.global_position + Vector3(0.5, 0, 0)
		PlayerState.load_inventory([], [], [], [])
		PlayerState.add_item("kelp_bundle")
		PlayerState.add_item("kelp_bundle")
		ga._feed(player)
		gb._feed(player)
		_pump(gb)
		var glass_babies: Array = get_tree().get_nodes_in_group("snail_glass").filter(
			func(n: Node) -> bool: return bool(n.get("_is_baby")))
		_check(glass_babies.size() == 1, "two fed glass snails within range spawn a baby")

	# Persistence: a fed flag and any standing babies survive a save/load round trip —
	# additive to the existing SaveManager payload, same pattern as structures/containers.
	# lamp_snails[0]/[1] already bred once above and that baby was grown to an adult in
	# the growth-timer check, so breed a FRESH pair (indices 3/4) here — otherwise this
	# test would trivially compare zero babies to zero babies and prove nothing.
	if lamp_snails.size() >= 5:
		var pa2: Node3D = lamp_snails[0]
		pa2.set("_fed", true)
		var pd: Node3D = lamp_snails[3]
		var pe: Node3D = lamp_snails[4]
		pe.global_position = pd.global_position + Vector3(0.5, 0, 0)
		PlayerState.add_item("kelp_bundle")
		PlayerState.add_item("kelp_bundle")
		pd._feed(player)
		pe._feed(player)
		_pump(pe)
		var baby_before: int = get_tree().get_nodes_in_group("snail_lamp").filter(
			func(n: Node) -> bool: return bool(n.get("_is_baby"))).size()
		_check(baby_before == 1, "a fresh pair breeds a second baby for the persistence check")
		SaveManager.save_game()
		pa2.set("_fed", false)
		for n in get_tree().get_nodes_in_group("snail_lamp"):
			if bool(n.get("_is_baby")) and is_instance_valid(n):
				n.free()
		_check(SaveManager.load_game(), "save reloads with snail breeding state in it")
		await get_tree().process_frame
		_check(bool(pa2.get("_fed")), "load restores a snail's fed flag")
		var baby_after: int = get_tree().get_nodes_in_group("snail_lamp").filter(
			func(n: Node) -> bool: return bool(n.get("_is_baby"))).size()
		_check(baby_after == baby_before,
			"load recreates the baby snail(s) that existed at save time (got %d, want %d)" % [baby_after, baby_before])

	# --- oxygen: a held breath underwater, not a fixed deep-death line -----------------
	# The old instant deep-death is gone; drowning is now gated on PlayerState.oxygen.
	PlayerState.oxygen = 1.5
	_check(PlayerState.oxygen == 1.0, "oxygen clamps to a full breath at most")
	PlayerState.oxygen = -0.5
	_check(PlayerState.oxygen == 0.0, "oxygen clamps to empty, never negative")
	var ox_signal: Array = [false]
	var on_ox: Callable = func(_v: float) -> void: ox_signal[0] = true
	PlayerState.oxygen_changed.connect(on_ox)
	PlayerState.oxygen = 1.0
	_check(ox_signal[0], "oxygen_changed fires so the HUD bar can track it")
	PlayerState.oxygen_changed.disconnect(on_ox)
	_check(player.has_method("_drown"), "player drowns via _drown when air runs out")
	_check(not player.has_method("_deep_death"), "the fixed deep-death line is gone")
	_check("swimming" in player, "player exposes swimming for the HUD oxygen gate")
	_check(main.hud.oxygen_bar != null, "HUD has an oxygen bar")
	await get_tree().process_frame
	_check(not main.hud.oxygen_bar.visible,
		"oxygen bar stays hidden on dry land at a full breath")

	# --- three save slots + Continue --------------------------------------------------
	# (slot_file_prefix is the test stem set at the top of _run, so none of this touches
	# the player's real saltline_slot_*.json.)
	_check(SaveManager.SLOT_COUNT == 3, "there are three save slots")
	_check(SaveManager.slot_path(1) != SaveManager.slot_path(2)
		and SaveManager.slot_path(2) != SaveManager.slot_path(3),
		"each slot has its own file")
	SaveManager.begin_new_game(2)
	_check(SaveManager.active_slot == 2, "New Expedition makes its slot active")
	_check(not SaveManager.consume_pending_load(), "a new game does not flag a load")
	_check(not SaveManager.slot_info(2).get("exists"), "a fresh slot reads as empty")
	GameClock.day_count = 5
	SaveManager.save_game()
	var i2: Dictionary = SaveManager.slot_info(2)
	_check(bool(i2.get("exists")) and int(i2.get("day")) == 5, "slot 2 records its day on save")
	_check(String(i2.get("label")).begins_with("Continue"), "a filled slot offers Continue")
	SaveManager.begin_new_game(3)
	GameClock.day_count = 9
	SaveManager.save_game()
	_check(int(SaveManager.slot_info(2).get("day")) == 5
		and int(SaveManager.slot_info(3).get("day")) == 9, "slots stay isolated from each other")
	SaveManager.begin_continue(2)
	_check(SaveManager.consume_pending_load(), "Continue flags exactly one load")
	_check(not SaveManager.consume_pending_load(), "the load flag is consumed once")
	GameClock.day_count = 0
	SaveManager.active_slot = 2
	_check(SaveManager.load_game() and GameClock.day_count == 5, "loading slot 2 restores its day")
	SaveManager.active_slot = 3
	_check(SaveManager.load_game() and GameClock.day_count == 9, "loading slot 3 restores its day")
	# leave no test files behind, and hand the stem back to real saves
	for s in range(1, SaveManager.SLOT_COUNT + 1):
		SaveManager.erase_slot(s)
	SaveManager.slot_file_prefix = "saltline_slot_"
	SaveManager.active_slot = 1

	_check_wave_math()
	_check_ai_budget()
	await _check_decimation_equivalence(main)

## The CPU sea and the drawn sea have to be the same sea, and Gyre's Gerstner sum was
## optimised (precomputed band constants, a height-only path that skips the horizontal
## displacement). Guard the two properties that could regress silently: the height path must
## agree with the full offset EXACTLY, and the analytic trough floor — which underwater_world
## uses to skip the sum for pods it can never reach — must really bound every sample.
func _check_wave_math() -> void:
	var worst: float = 0.0
	var lowest: float = 0.0
	for ss in [0.0, 0.4, 1.0]:
		Gyre.set_sea_state(ss)
		for i in range(400):
			var p := Vector2(float(i % 20) * 9.3 - 90.0, float(i / 20) * 9.7 - 90.0)
			var t: float = float(i) * 13.7
			var h: float = Gyre.wave_height(p, t)
			worst = maxf(worst, absf(h - Gyre.wave_offset(p, t).y))
			lowest = minf(lowest, h)
	Gyre.set_sea_state(Gyre.WAVE_SEA_STATE)
	# One float32 ULP, not zero: wave_offset returns a Vector3, whose components are single
	# precision, so reading `.y` rounds. wave_height now returns the raw double. The bound is
	# what proves the gap is that rounding and not an arithmetic difference.
	_check(worst <= 2.0e-6,
		"wave_height agrees with wave_offset().y to float32 (worst %.17f)" % worst)
	_check(Gyre.trough_floor() < -5.0 and lowest > Gyre.trough_floor(),
		"trough floor %.2f really bounds the sea (deepest sampled %.2f)"
			% [Gyre.trough_floor(), lowest])

## THE CLAIM DECIMATION RESTS ON, ASSERTED RATHER THAN ARGUED.
##
## AiBudget lets a distant creature think once every N frames and hands it the N frames'
## worth of delta. The claim is that this puts the animal in EXACTLY the place it would
## have reached thinking every frame. tests/AiBudgetProbe measures that on the live world
## and finds the clock conserved to 0.1%, but a live world also contains coin flips (the
## seal decides at random whether to haul out), so the probe's speed column can never be
## perfectly clean. This is the clean version: one creature stepped 300 times at 1/30 s,
## an identical one stepped 75 times at 4/30 s — the same elapsed time, at stride 1 and at
## stride 4 — and they must finish at the same point.
##
## Only valid for the species whose position is a pure function of their own clock, which
## is what DeepGiant and PillarPatrol are (`pos = f(_t, home, radius)`). Creatures that
## INTEGRATE state instead — the glider ray banks with `lerp(delta * k)` — are rate-correct
## but not step-size-independent, and are covered by the probe's speed column instead.
func _check_decimation_equivalence(main: Node) -> void:
	var UW := preload("res://scripts/world/underwater_world.gd")
	var was: bool = AiBudget.enabled
	AiBudget.enabled = false          # drive the step sizes by hand, not the scheduler
	for spec in [["DeepGiant", UW.DeepGiant], ["PillarPatrol", UW.PillarPatrol]]:
		var fine: Node3D = (spec[1] as GDScript).new(3.0, -20.0, 12.0, 0.05, 1.0, Vector3.ZERO)
		var coarse: Node3D = (spec[1] as GDScript).new(3.0, -20.0, 12.0, 0.05, 1.0, Vector3.ZERO)
		main.add_child(fine)
		main.add_child(coarse)
		await get_tree().process_frame
		if not is_instance_valid(fine) or not is_instance_valid(coarse):
			_check(false, "%s: could not build a pair to compare (missing mesh?)" % spec[0])
			continue
		for i in range(300):
			fine._process(1.0 / 30.0)
		for i in range(75):
			coarse._process(4.0 / 30.0)     # stride 4, four frames of delta at a time
		var gap: float = fine.global_position.distance_to(coarse.global_position)
		_check(gap < 0.001,
			"%s ends in the same place at stride 1 and stride 4 (%.6f m apart over 10 s)"
				% [spec[0], gap])
		fine.queue_free()
		coarse.queue_free()
	AiBudget.enabled = was
	_check(AiBudget.enabled, "decimation is left enabled after the equivalence check")

## THE DECIMATION INVARIANT. AiBudget runs distant creatures on every Nth frame; the whole
## thing is only correct because the skipped frames' delta is handed over on the frame that
## does run. If that ever stops holding, every decimated animal silently runs at 1/N speed —
## which is the failure this project was warned about and which no screenshot would catch.
##
## Simulated rather than measured off a live creature so it runs headless with the rest of
## the suite: drive the same accumulate/spend loop the species prologues use and assert the
## time handed out equals the time that passed, and that no single step exceeds MAX_STEP.
## The largest `k` in any `lerpf(x, target, delta * k)` across the decimated species (the
## isopod's freeze reaction). See AiBudget.MAX_STEP.
const K_MAX_SMOOTH: float = 6.0

func _check_ai_budget() -> void:
	var frame: float = 1.0 / 30.0
	# Read the strides OFF THE CONSTANTS rather than hard-coding them. This list used to be
	# [1, 2, 4], which silently stopped covering the stride actually in use the moment
	# HIDDEN_STRIDE moved off 4 — and the whole point of this check is that the stride in use
	# conserves time.
	var strides: Array = [1, 2]
	for s in [AiBudget.FAR_STRIDE, AiBudget.HIDDEN_STRIDE]:
		if not strides.has(s):
			strides.append(s)          # the two are equal today; don't assert it twice
	for stride in strides:
		var acc: float = 0.0
		var spent: float = 0.0
		var worst_step: float = 0.0
		var ticks: int = 0
		for f in range(600):
			acc += frame
			var due: bool = acc >= AiBudget.MAX_STEP or stride <= 1 or (f % stride) == 0
			if not due:
				continue
			worst_step = maxf(worst_step, acc)
			spent += acc
			acc = 0.0
			ticks += 1
		var elapsed: float = 600.0 * frame
		_check(absf((spent + acc) - elapsed) < 1e-6,
			"AiBudget stride %d conserves elapsed time (%.4f vs %.4f)" % [stride, spent + acc, elapsed])
		_check(worst_step <= AiBudget.MAX_STEP + frame + 1e-6,
			"AiBudget stride %d never hands over more than MAX_STEP (%.4f)" % [stride, worst_step])
		# THE INVARIANT MAX_STEP EXISTS TO PROTECT, asserted directly instead of implied by a
		# constant. The species code smooths with `lerpf(x, target, delta * k)`, whose largest
		# k in the decimated classes is 6.0; that form overshoots the target past k*step > 1
		# and oscillates away from it past 2. So the number that must hold is k*step <= 1, and
		# it is the STRIDE CEILING — once the stride is above 4 the worst step stops being set
		# by the stride at all and is set by MAX_STEP plus one frame, which is why raising
		# HIDDEN_STRIDE further buys nothing and why lowering MAX_STEP would cost the existing
		# far-stride win. At 30 fps this lands on exactly 1.0: lerpf's snap point, the last
		# stable value, and reached only by creatures that are not being drawn.
		_check(K_MAX_SMOOTH * worst_step <= 1.0 + 1e-6,
			"AiBudget stride %d keeps k*step within lerpf's stable range (%.4f <= 1.0)"
				% [stride, K_MAX_SMOOTH * worst_step])
		_check(ticks > 0, "AiBudget stride %d still ticks" % stride)
	_check(AiBudget.enabled, "AiBudget is left enabled for the game")
