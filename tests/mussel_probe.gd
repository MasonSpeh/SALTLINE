extends Node
## Ground truth for the harvestable mussel beds (s21).
##
## Five claims, each measured rather than asserted:
##   1. SEATING — every bed and every accent patch sits FLUSH on the real caisson concrete.
##      Measured as the distance from the patch's seat to the surface a ray finds under it,
##      with a bound in millimetres, plus the angle between the patch's own up axis and the
##      probed face normal.
##   2. REACHABLE — every bed is above the dive floor derived from the player controller's
##      own air budget, i.e. a diver can get to it, work it and get back on one breath.
##   3. HARVEST — GATHER hands over real `mussels` items, the node goes spent, and the bed
##      visibly loses geometry.
##   4. FIVE DAYS — a spent bed does NOT regrow at four and a half game days and DOES at
##      five, driven by advancing the game CLOCK rather than by waiting.
##   5. SAVE — harvest, save, reload: still spent, and still with the right amount of its
##      five days left to run.
##
## Runs HEADLESS on purpose, and that is safe here in a way it is not for ReefProbe: the beds
## are ordinary MeshInstance3D nodes, not MultiMesh instances, so their transforms live in the
## scene tree and read back correctly under the dummy renderer (docs/AGENT_TRAPS.md — the
## identity-transform trap only applies to MultiMesh).
##
## Run: godot --headless --path . res://tests/MusselProbe.tscn

const LOG_PATH: String = "/tmp/mussel_probe.txt"
const PC := preload("res://scripts/components/player_controller.gd")

## Flush means flush. A bed is deliberately recessed ~28 mm into the concrete (see
## MusselBeds.RECESS) so no cut edge shows, and the ray under it may legitimately hit a
## neighbouring reef instance's collider... except reef instances have none. So the only
## honest bound is: seat within a few centimetres of the measured surface, on the inside.
const FLUSH_MAX_MM: float = 60.0
## An encrusting mat lies on the rock: its up axis and the face normal must agree closely.
const TILT_MAX_DEG: float = 6.0

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()
var _space: PhysicsDirectSpaceState3D
var _skip: Array[RID] = []

func _say(s: String) -> void:
	print(s)
	_lines.append(s)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_say("  PASS  " + msg)
	else:
		failures += 1
		_say("  FAIL  " + msg)

## THE PROBE MUST NOT TOUCH THE OWNER'S SAVE, and it very nearly did. SaveManager connects
## GameClock.dawn and .dusk to save_game(), and this file drives the clock forward five days —
## so every DAWN it crosses would have autosaved the probe's half-drowned test state straight
## over the player's slot 1. Redirected to a throwaway stem for the WHOLE run, before anything
## can force a phase, and put back at the end.
var _slot_prefix: String = ""

## Keeping the diver alive. The worker stands 15 m under water for the whole harvest, and the
## breath is a 28-second clock: _drown() respawns the player on the deck, at which point
## Salvage._work correctly abandons the job as "you step away from it, half done" — and the
## probe would be measuring drowning while reporting on harvesting. PROCESS_MODE_ALWAYS
## because the pause menu opens itself on focus-out.
func _process(_delta: float) -> void:
	PlayerState.oxygen = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_slot_prefix = SaveManager.slot_file_prefix
	SaveManager.slot_file_prefix = "mussel_probe_slot_"
	# AND CLAIM A SLOT (2026-08-08). The four checks in _save_round_trip had been failing on
	# a green feature: `save_game()` returns false without writing anything when
	# active_slot < 1 (save_manager.gd:176, the "NO SESSION, NO WRITE" guard), and the only
	# thing that claims a slot is main.gd when Main is the SCENE ROOT — which it is not here,
	# it is a child of this probe. The symptom was "the save carries this bed's spent state
	# ... of 0 entries", i.e. indistinguishable from the mussel beds not persisting at all.
	# Verified pre-existing at HEAD before this line went in. Safe: the throwaway prefix
	# above is already set, so slot 1 is a scratch file, never the owner's.
	SaveManager.active_slot = 1
	var main: Node3D = null
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed != null:
		main = packed.instantiate()
	# A GDScript parse error does NOT make instantiate() fail — it hands back a bare node with
	# its script dropped, which builds nothing and lets every check below pass vacuously.
	if main != null and main.get_script() == null:
		_say("ABORT  Main.tscn instantiated WITHOUT its script — a world script does not parse.")
		_finish()
		return
	add_child(main)
	for i in range(120):
		await get_tree().process_frame
	_space = get_viewport().world_3d.direct_space_state
	var beds_node: Node = _find_beds(main)
	if beds_node == null:
		failures += 1
		_say("ABORT  no MusselBeds node in the tree")
		_finish()
		return
	var beds: Array = beds_node.get("beds")
	_say("=== mussel beds: %d planted ===" % beds.size())
	_ok(beds.size() >= 12, "at least 12 beds in the ocean (found %d)" % beds.size())
	_collect_skip(main)
	_seating(beds)
	_reach(beds_node, beds)
	_clock_maths(beds_node)
	await _harvest_and_regrow(beds)
	await _save_round_trip(beds)
	_finish()

func _finish() -> void:
	SaveManager.erase_slot(SaveManager.active_slot)
	SaveManager.slot_file_prefix = _slot_prefix
	_say("---")
	_say("FAILURES: %d" % failures)
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	get_tree().quit(1 if failures > 0 else 0)

func _find_beds(root: Node) -> Node:
	for n in root.find_children("MusselBeds", "", true, false):
		return n
	return null

## Every live animal's collider, and every mussel bed's OWN collider, excluded from every ray
## this file fires at the concrete. s20 cost a whole session to this: a FaunaTouch sphere or an
## Interactable box standing proud of a wall makes a ray report the wall as having MOVED.
## A mussel bed is exactly such a box, so a probe that did not exclude them would measure the
## first bed on a face and call the second one buried.
const FAUNA_SCRIPTS := ["bloom_fauna.gd", "reef_life.gd", "reef_fish.gd", "leg_reef.gd",
	"mussel_beds.gd", "salvage.gd"]

func _collect_skip(root: Node) -> void:
	for node in root.find_children("*", "CollisionObject3D", true, false):
		var p: Node = node
		while p != null:
			var s: Script = p.get_script()
			if s != null and FAUNA_SCRIPTS.has(String(s.resource_path).get_file()):
				_skip.append((node as CollisionObject3D).get_rid())
				break
			p = p.get_parent()
	_say("  excluding %d animal/harvest colliders from every ray" % _skip.size())

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = _skip
	return _space.intersect_ray(q)

# ------------------------------------------------------------------ 1. seating

func _seating(beds: Array) -> void:
	_say("--- seating: flush against the measured concrete ---")
	var worst_mm: float = 0.0
	var worst_deg: float = 0.0
	var measured: int = 0
	var floating: int = 0
	var tilted: int = 0
	var unmeasured: int = 0
	var sum_mm: float = 0.0
	for b in beds:
		for mi in (b as Node).find_children("*", "MeshInstance3D", true, false):
			var patch: MeshInstance3D = mi
			if patch.mesh is CylinderMesh:
				continue                      # the scar disc, not a mussel patch
			var up: Vector3 = patch.global_transform.basis.y.normalized()
			var seat: Vector3 = patch.global_position
			# Ray in from open water along the patch's own up axis: if the patch is really
			# lying on the wall, the concrete is right underneath it.
			var hit: Dictionary = _ray(seat + up * 1.6, seat - up * 0.8)
			if hit.is_empty():
				unmeasured += 1
				_say("    no collider under %s at (%.2f, %.2f, %.2f), up (%.2f, %.2f, %.2f)"
					% [patch.get_parent().get_parent().name, seat.x, seat.y, seat.z,
						up.x, up.y, up.z])
				continue
			measured += 1
			var face: Vector3 = (hit["normal"] as Vector3).normalized()
			# Signed along the face normal: negative = recessed into the concrete (wanted),
			# positive = standing off it (a floating prop).
			var gap_mm: float = (seat - (hit["position"] as Vector3)).dot(face) * 1000.0
			sum_mm += gap_mm
			if absf(gap_mm) > absf(worst_mm):
				worst_mm = gap_mm
			if gap_mm > FLUSH_MAX_MM:
				floating += 1
			var deg: float = rad_to_deg(acos(clampf(up.dot(face), -1.0, 1.0)))
			worst_deg = maxf(worst_deg, deg)
			if deg > TILT_MAX_DEG:
				tilted += 1
	_say("  %d patches measured, %d found no collider under them" % [measured, unmeasured])
	_say("  gap to surface: mean %+.1f mm, worst %+.1f mm (negative = recessed into concrete)"
		% [sum_mm / maxf(float(measured), 1.0), worst_mm])
	_say("  up axis vs face normal: worst %.2f deg" % worst_deg)
	# A vacuous pass is the failure mode this guards: assert a plausible NUMBER of
	# measurements, not just the absence of failures.
	_ok(measured >= 30, "measured a plausible number of patches (%d)" % measured)
	_ok(unmeasured == 0, "every patch has real collider under it (%d without)" % unmeasured)
	_ok(floating == 0, "0 patches standing off the concrete (%d over %.0f mm)"
		% [floating, FLUSH_MAX_MM])
	_ok(tilted == 0, "0 patches tilted off the face (%d over %.1f deg)"
		% [tilted, TILT_MAX_DEG])

# ------------------------------------------------------------------ 2. reachable

func _reach(beds_node: Node, beds: Array) -> void:
	_say("--- reachable on one breath ---")
	var floor_y: float = beds_node.get("_dive_y")
	var lo: float = 1.0e9
	var hi: float = -1.0e9
	var too_deep: int = 0
	for b in beds:
		var y: float = (b as Node3D).global_position.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
		if y < floor_y:
			too_deep += 1
	# The air budget itself, independently: at the deepest bed, what fraction of a breath
	# does the round trip plus the work cost?
	var depth: float = -lo
	var shallow_m: float = minf(depth, PC.DEEP_UNEASE_M)
	var deep_m: float = maxf(0.0, depth - PC.DEEP_UNEASE_M)
	var work_rate: float = PC.OXYGEN_DRAIN_DEEP if depth > PC.DEEP_UNEASE_M else PC.OXYGEN_DRAIN
	var cost: float = (2.0 * shallow_m / PC.SWIM_SPEED) * PC.OXYGEN_DRAIN \
		+ (2.0 * deep_m / PC.SWIM_SPEED) * PC.OXYGEN_DRAIN_DEEP \
		+ 2.0 * work_rate
	_say("  beds seated y %.2f .. %.2f; derived dive floor y %.2f" % [lo, hi, floor_y])
	_say("  deepest bed costs %.0f%% of one breath (down %.1f s, work 2.0 s, up %.1f s)"
		% [cost * 100.0, depth / PC.SWIM_SPEED, depth / PC.SWIM_SPEED])
	_ok(too_deep == 0, "0 beds below the dive floor (%d too deep)" % too_deep)
	_ok(cost < 1.0, "the deepest bed is reachable and returnable on one breath (%.2f)" % cost)

# ------------------------------------------------------------------ 3/4. the clock

## The regrow arithmetic, checked against the clock's own phase plan rather than restated.
func _clock_maths(beds_node: Node) -> void:
	_say("--- five game days, in the clock's own units ---")
	var days: float = beds_node.get("REGROW_DAYS")
	var day_sec: float = GameClock.real_sec_per_game_day()
	_say("  1 game day = %.0f real s (%.0f min); %0.f days = %.0f game hours = %.0f real s (%.2f real h)"
		% [day_sec, day_sec / 60.0, days, days * 24.0, days * day_sec, days * day_sec / 3600.0])
	_ok(is_equal_approx(days, 5.0), "regrow is 5 game days")
	# The absolute clock has to be monotonic across a sleep, or a regrow measured on it could
	# run backwards. Checked here rather than trusted.
	var day0: int = GameClock.day_count
	var ph0: GameClock.Phase = GameClock.current_phase
	var el0: float = GameClock._phase_elapsed_sec
	GameClock.day_count = 3
	GameClock.force_phase(GameClock.Phase.NIGHT)
	GameClock._phase_elapsed_sec = float(GameClock.phase_durations_minutes[GameClock.Phase.NIGHT]) * 60.0 * 0.9
	var before: float = GameClock.game_time_hours()
	GameClock.skip_to_next_dawn()
	var after: float = GameClock.game_time_hours()
	_ok(after > before, "sleeping advances absolute game time (%.2f h -> %.2f h)"
		% [before, after])
	GameClock.day_count = day0
	GameClock.force_phase(ph0)
	GameClock._phase_elapsed_sec = el0

## Move the CALENDAR forward, not the wall clock — this is what a player sleeping through
## nights does to the same number, and it is the only way to test a five-day span without
## waiting five hours.
##
## ADDITIVE, in absolute hours. The first version of this SET the intra-day position instead
## of adding to it, so a 4.5-day jump followed by a 0.6-day jump advanced the clock by 4.5 days
## and then by 0.1 — and the probe reported that a five-day bed had not regrown after five
## days. The failure looked exactly like a bug in the feature. Everything here goes through
## GameClock.game_time_hours(), the one number that is monotonic across both.
func _advance_game_days(d: float) -> void:
	var target: float = GameClock.game_time_hours() + d * 24.0
	GameClock.day_count = int(floor(target / 24.0))
	var hh: float = fposmod(target, 24.0)
	var total_min: float = 0.0
	for p in GameClock.phase_durations_minutes:
		total_min += float(GameClock.phase_durations_minutes[p])
	var want_min: float = hh / 24.0 * total_min
	var acc: float = 0.0
	for phase in [GameClock.Phase.DAWN, GameClock.Phase.DAY, GameClock.Phase.DUSK,
			GameClock.Phase.NIGHT]:
		var m: float = float(GameClock.phase_durations_minutes[phase])
		if want_min <= acc + m or phase == GameClock.Phase.NIGHT:
			GameClock.force_phase(phase)
			GameClock._phase_elapsed_sec = clampf(want_min - acc, 0.0, m) * 60.0
			return
		acc += m

func _harvest_and_regrow(beds: Array) -> void:
	_say("--- harvest, then five days ---")
	var bed: Node = beds[0]
	var before: int = _count_item("mussels")
	var meshes_before: int = _visible_patches(bed)
	# Empty the pack so the all-or-nothing grant has room, and stand a worker at the bed.
	for i in range(PlayerState.HOTBAR_SIZE):
		PlayerState.hotbar[i] = null
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var yield_n: int = int((bed.get("yields") as Dictionary).get("mussels", 0))
	_ok(yield_n >= 2 and yield_n <= 4, "the bed offers 2-4 mussels (rolled %d)" % yield_n)
	if player != null:
		player.global_position = (bed as Node3D).global_position
	bed.call("interact", "GATHER", player)
	await _work_out(bed, player)
	var got: int = _count_item("mussels") - before
	_ok(bed.get("spent") == true, "the bed is spent after a GATHER")
	_ok(got == yield_n, "GATHER handed over %d mussels (rolled %d)" % [got, yield_n])
	var meshes_after: int = _visible_patches(bed)
	_ok(meshes_after < meshes_before,
		"the picked bed visibly lost geometry (%d -> %d patches)" % [meshes_before, meshes_after])
	var picked_h: float = float(bed.get("_picked_at_h"))
	# FOUR AND A HALF DAYS: still bare.
	var d0: int = GameClock.day_count
	var ph0: GameClock.Phase = GameClock.current_phase
	_advance_game_days(4.5)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(bed.get("spent") == true, "still bare after 4.5 game days (%.1f h elapsed)"
		% (GameClock.game_time_hours() - picked_h))
	# FIVE AND A BIT: grown back.
	_advance_game_days(0.6)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(bed.get("spent") == false, "grown back after 5.1 game days (%.1f h elapsed)"
		% (GameClock.game_time_hours() - picked_h))
	# And it is a full bed again, not a shrunken one.
	for i in range(90):
		await get_tree().process_frame
	_ok(_visible_patches(bed) == meshes_before,
		"the regrown bed is whole again (%d patches)" % _visible_patches(bed))
	GameClock.day_count = d0
	GameClock.force_phase(ph0)

## Let a Salvage job run to completion.
##
## TWO THINGS make this more than "await a few frames", both learned by watching it fail.
## Salvage._work counts REAL seconds, and a headless main loop runs unbounded — 140 frames is
## a quarter of a second here, not the two seconds the same loop buys at 60 fps — so the wait
## is on the JOB's own flag with a frame cap, never on a frame count. And the worker is
## standing 15 m under water: the breath runs out, _drown() respawns the player on the deck,
## and Salvage._work then correctly abandons the job as "you step away from it, half done".
## Topping the air up each frame is what keeps the probe measuring harvesting instead of
## accidentally measuring drowning.
func _work_out(bed: Node, player: Node3D) -> void:
	for i in range(20000):
		if bed.get("_working") != true:
			return
		PlayerState.oxygen = 1.0
		if player != null:
			player.global_position = (bed as Node3D).global_position
		await get_tree().process_frame
	_say("    WARNING the GATHER never completed in 20000 frames")

func _visible_patches(bed: Node) -> int:
	var n: int = 0
	for mi in bed.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh is CylinderMesh:
			continue                                 # the scar disc
		if (mi as MeshInstance3D).visible:
			n += 1
	return n

func _count_item(id: String) -> int:
	var n: int = 0
	for i in range(PlayerState.hotbar.size()):
		if PlayerState.hotbar[i] == id:
			n += int(PlayerState.hotbar_counts[i]) if i < PlayerState.hotbar_counts.size() else 1
	for i in range(PlayerState.inventory.size()):
		if PlayerState.inventory[i] == id:
			n += int(PlayerState.inventory_counts[i]) if i < PlayerState.inventory_counts.size() else 1
	return n

# ------------------------------------------------------------------ 5. save/load

func _save_round_trip(beds: Array) -> void:
	_say("--- spent state survives a save/load ---")
	var bed: Node = beds[1]
	var key: String = "%.2f,%.2f,%.2f" % [(bed as Node3D).global_position.x,
		(bed as Node3D).global_position.y, (bed as Node3D).global_position.z]
	for i in range(PlayerState.HOTBAR_SIZE):
		PlayerState.hotbar[i] = null
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null:
		player.global_position = (bed as Node3D).global_position
	bed.call("interact", "GATHER", player)
	if bed.get("_working") != true:
		_say("    interact() bailed: spent=%s yield_total=%d free_slots=%d pack_used=%d cap=%d"
			% [bed.get("spent"), int(bed.call("_yield_total")), int(bed.call("_free_slots")),
				PlayerState.pack_used(), PlayerState.backpack_capacity()])
	await _work_out(bed, player)
	_ok(bed.get("spent") == true, "bed 1 harvested and spent")
	var picked_h: float = float(bed.get("_picked_at_h"))
	SaveManager.save_game()
	var raw: FileAccess = FileAccess.open(SaveManager.slot_path(SaveManager.active_slot),
		FileAccess.READ)
	var saved: Dictionary = {}
	if raw:
		var parsed: Variant = JSON.parse_string(raw.get_as_text())
		raw.close()
		if parsed is Dictionary:
			saved = parsed
	var harvest: Dictionary = saved.get("harvest", {})
	_ok(harvest.has(key), "the save carries this bed's spent state (key %s of %d entries)"
		% [key, harvest.size()])
	# Now FORCE it back to grown — as a fresh world build would be — and reload.
	bed.call("harvest_restore", {"spent": false})
	_ok(bed.get("spent") == false, "bed forced back to grown, as a fresh world build is")
	_ok(SaveManager.load_game(), "the slot loads")
	await get_tree().process_frame
	_ok(bed.get("spent") == true, "STILL SPENT after the reload — it did not grow back free")
	var kept: float = float(bed.get("_picked_at_h"))
	# picked_h > 0 guards the whole comparison against a vacuous pass: two nodes that were
	# never harvested both read -1.0 and would agree perfectly.
	_ok(picked_h > 0.0 and absf(kept - picked_h) < 0.01,
		"the five-day clock resumed where it was (%.3f h vs %.3f h)" % [kept, picked_h])
	var left_days: float = (float(bed.get("regrow_game_hours"))
		- (GameClock.game_time_hours() - kept)) / 24.0
	_say("  %.2f of the five days still to run after the reload" % left_days)
	_ok(left_days > 4.0, "the reload did not eat the regrow timer (%.2f days left)" % left_days)
	# A bed that was never touched must come back untouched, not spent.
	_ok(beds[2].get("spent") == false, "an untouched bed is still untouched after the reload")
