extends Node
## Ground truth for the s47 harvest-growth pass: "harvestable kelp and mussels should spawn in
## at specific frequencies over time".
##
## Six claims, each measured rather than asserted:
##   1. CALENDAR REGROW — every renewable node on the rig counts its span in GAME HOURS, not
##      in real `delta`. Asserted structurally (regrow_game_hours > 0 on every renewable node)
##      and then demonstrated on a live node: harvest it, SLEEP, and watch it come back —
##      which is the exact thing the old real-seconds countdown could not do, because
##      skip_to_next_dawn() spends no real time at all.
##   2. THE LADDER — the intervals are the ones the source documents, and they are all
##      DIFFERENT, so the player can learn a rhythm.
##   3. KELP SEATED — every kelp stand sits on a real, flat, splash-zone surface. This is the
##      check that fails on the pre-s47 world: three of the four authored stands hung in open
##      air under the wet-deck slab.
##   4. DENSITY CAP — advancing the calendar raises the kelp and mussel counts to their caps
##      and NO FURTHER, and the spawns are spread over the interval rather than all at once.
##   5. DETERMINISM — the positions of every planned kelp seat and every planned mussel bed,
##      hashed. The position-keyed save (save_manager.gd:460) rests on this, so the hash is
##      printed for a cross-run diff and the plan is also checked to be collision-free.
##   6. LATE ARRIVAL SURVIVES A SAVE — harvest a bed that only settled because the calendar
##      moved, save, force it back to grown, reload, and check it is still spent. That is the
##      claim_harvest hand-off (save_manager.gd:512) doing its job for a node that did not
##      exist when load_game() ran.
##
## Headless on purpose and safe there: everything read back is plain scene-tree state
## (node transforms, counts, flags), never MultiMesh instance data — see the identity-transform
## trap in docs/AGENT_TRAPS.md.
##
## Run: godot --headless --path . res://tests/HarvestGrowthProbe.tscn

const LOG_PATH: String = "/tmp/harvest_growth_probe.txt"
const HARVEST := preload("res://scripts/world/harvest_nodes.gd")
const MUSSELS := preload("res://scripts/world/mussel_beds.gd")

## The expected ladder, reached through the preloaded SCRIPT's own constants rather than
## restated as literals — a probe that hard-codes 6.0 only tests that somebody typed 6.0
## twice. (`Object.get()` cannot resolve script constants and cannot be called on a script
## object at all; a `const` reference through a `preload` is the reach that works.)
const LADDER := {
	"Kelp Growth": HARVEST.KELP_REGROW_H,
	"Glow Worm Cluster": HARVEST.GLOW_REGROW_H,
	"Tar Seam": HARVEST.TAR_REGROW_H,
	"Fish-Cleaning Board": HARVEST.BOARD_REGROW_H,
	"Barnacle Crust": HARVEST.BARNACLE_REGROW_H,
}

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()
var _space: PhysicsDirectSpaceState3D
var _skip: Array[RID] = []
var _slot_prefix: String = ""

func _say(s: String) -> void:
	print(s)
	_lines.append(s)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_say("  PASS  " + msg)
	else:
		failures += 1
		_say("  FAIL  " + msg)

## Keep the diver alive. Any node harvested underwater is worked while the breath runs, and
## _drown() respawning the player on the deck makes Salvage._work abandon the job as "you step
## away from it" — the probe would then be measuring drowning (tests/mussel_probe.gd's note).
func _process(_delta: float) -> void:
	PlayerState.oxygen = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# SaveManager autosaves on GameClock.dawn/.dusk and this probe drives the clock across
	# many dawns, so every one of them would write the probe's test state over the owner's
	# slot 1. Redirected before anything can force a phase, and put back at the end.
	_slot_prefix = SaveManager.slot_file_prefix
	SaveManager.slot_file_prefix = "harvest_growth_probe_slot_"
	# AND CLAIM A SLOT. `save_game()` returns false with no write when active_slot < 1
	# (save_manager.gd:176) and only main.gd claims one, and only when Main is the SCENE ROOT
	# — which it is not here, it is a child of this probe. Without this the save section
	# below reports "0 harvest entries" and reads like a persistence bug in the feature.
	# Safe: the throwaway prefix above is already in place, so slot 1 is a scratch file.
	SaveManager.active_slot = 1
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = packed.instantiate() if packed != null else null
	# A GDScript parse error does NOT make instantiate() fail — it hands back a bare node with
	# its script dropped, and every check below then passes vacuously on an empty tree.
	if main == null or main.get_script() == null:
		_say("ABORT  Main.tscn instantiated WITHOUT its script — a world script does not parse.")
		_finish()
		return
	add_child(main)
	for i in range(180):
		await get_tree().process_frame
	_space = get_viewport().world_3d.direct_space_state
	_collect_skip(main)
	var kelp_host: Node = _find(main, "HarvestNodes")
	var beds_host: Node = _find(main, "MusselBeds")
	if kelp_host == null or beds_host == null:
		failures += 1
		_say("ABORT  kelp host %s / mussel host %s" % [kelp_host, beds_host])
		_finish()
		return
	_ladder()
	_kelp_seats()
	_determinism(kelp_host, beds_host)
	_dive_floor_report(beds_host)
	# DENSITY FIRST, on a clock that has barely moved: the sleep test below jumps the calendar
	# a whole day, and after that the interval arithmetic has already been satisfied several
	# times over, so "one more stand per interval" would be untestable (measured — the first
	# run of this probe read 4, 8, 8, 8 for exactly that reason).
	await _density(kelp_host, beds_host)
	await _sleep_regrow()
	await _late_bed_save(beds_host)
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

func _find(root: Node, n: String) -> Node:
	for c in root.find_children(n, "", true, false):
		return c
	return null

const SKIP_SCRIPTS := ["bloom_fauna.gd", "reef_life.gd", "reef_fish.gd", "leg_reef.gd",
	"mussel_beds.gd", "salvage.gd", "harvest_nodes.gd", "shark.gd", "crab.gd", "king_crab.gd",
	"ship_cat.gd", "jelly_glow.gd", "structures.gd", "player_controller.gd"]

func _collect_skip(root: Node) -> void:
	for node in root.find_children("*", "CollisionObject3D", true, false):
		var p: Node = node
		while p != null:
			var s: Script = p.get_script()
			if s != null and SKIP_SCRIPTS.has(String(s.resource_path).get_file()):
				_skip.append((node as CollisionObject3D).get_rid())
				break
			p = p.get_parent()
	_say("  excluding %d animal/harvest/player colliders from every ray" % _skip.size())

func _renewables() -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("salvageable"):
		if s.has_method("renewable") and bool(s.call("renewable")):
			out.append(s)
	return out

# ---------------------------------------------------------------- 1/2. the ladder

func _ladder() -> void:
	_say("--- every renewable node counts on the CALENDAR, and the intervals differ ---")
	var per_hour: float = GameClock.real_sec_per_game_day() / 24.0
	var by_name: Dictionary = {}
	var on_delta: int = 0
	for s in _renewables():
		var h: float = float(s.get("regrow_game_hours"))
		if h <= 0.0:
			on_delta += 1
			_say("    %s is still on a real-seconds countdown (%.0f s)"
				% [s.get("display_name"), float(s.get("regrow_sec"))])
			continue
		var key: String = String(s.get("display_name")).trim_prefix("Stripped ")
		if not by_name.has(key):
			by_name[key] = [h, 0]
		(by_name[key] as Array)[1] = int((by_name[key] as Array)[1]) + 1
	var names: Array = by_name.keys()
	names.sort()
	for k in names:
		var row: Array = by_name[k]
		_say("    %-22s %6.1f game h = %7.0f real s   x%d"
			% [k, float(row[0]), float(row[0]) * per_hour, int(row[1])])
	_ok(on_delta == 0, "0 renewable nodes left on a real-seconds countdown (%d)" % on_delta)
	# The documented ladder, read off the SCRIPT's own constants rather than restated here.
	var wrong: int = 0
	for k in LADDER:
		if not by_name.has(k):
			continue
		var want: float = float(LADDER[k])
		if not is_equal_approx(float((by_name[k] as Array)[0]), want):
			wrong += 1
			_say("    %s carries %.1f h, harvest_nodes.gd says %.1f"
				% [k, float((by_name[k] as Array)[0]), want])
	_ok(wrong == 0, "every wet-deck node carries the interval its own constant names")
	var spans: Array = []
	for k in by_name:
		spans.append(float((by_name[k] as Array)[0]))
	spans.sort()
	var dupes: int = 0
	for i in range(1, spans.size()):
		if is_equal_approx(spans[i], spans[i - 1]):
			dupes += 1
	_ok(dupes == 0, "all %d intervals are distinct — a rhythm, not one cooldown" % spans.size())
	_ok(spans.size() >= 5 and spans[0] >= 1.0 and spans[spans.size() - 1] <= 240.0,
		"the ladder spans %.0f h .. %.0f h over %d kinds"
			% [spans[0], spans[spans.size() - 1], spans.size()])

# ---------------------------------------------------------------- 3. kelp seating

func _kelp_stands() -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("salvageable"):
		var y: Variant = s.get("yields")
		if y is Dictionary and (y as Dictionary).has("kelp_bundle"):
			out.append(s)
	return out

func _kelp_seats() -> void:
	_say("--- every kelp stand is on real, flat, splash-zone deck ---")
	var stands: Array = _kelp_stands()
	var floating: int = 0
	var worst_mm: float = 0.0
	var worst_deg: float = 0.0
	var lo: float = 1.0e9
	var hi: float = -1.0e9
	for s in stands:
		var p: Vector3 = (s as Node3D).global_position
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.9, p - Vector3.UP * 1.2)
		q.collision_mask = 1
		q.exclude = _skip
		var hit: Dictionary = _space.intersect_ray(q)
		if hit.is_empty():
			floating += 1
			_say("    NOTHING under the stand at (%.2f, %.2f, %.2f)" % [p.x, p.y, p.z])
			continue
		var gap_mm: float = (p.y - (hit["position"] as Vector3).y) * 1000.0
		var deg: float = rad_to_deg(acos(clampf(
			(hit["normal"] as Vector3).normalized().dot(Vector3.UP), -1.0, 1.0)))
		if absf(gap_mm) > absf(worst_mm):
			worst_mm = gap_mm
		worst_deg = maxf(worst_deg, deg)
		if absf(gap_mm) > 50.0:
			floating += 1
			_say("    stand at (%.2f, %.2f, %.2f) is %+.0f mm off its surface" % [p.x, p.y, p.z, gap_mm])
	_say("  %d stands, seated y %.2f .. %.2f, worst gap %+.1f mm, worst tilt %.2f deg"
		% [stands.size(), lo, hi, worst_mm, worst_deg])
	_ok(stands.size() == HARVEST.KELP_OPENING,
		"the world opens with %d kelp stands (found %d)" % [HARVEST.KELP_OPENING, stands.size()])
	_ok(floating == 0, "0 kelp stands hanging off their surface (%d)" % floating)
	_ok(worst_deg < 2.0, "every stand is on a flat deck (worst %.2f deg)" % worst_deg)
	_ok(lo >= HARVEST.KELP_BAND_LO and hi <= HARVEST.KELP_BAND_HI,
		"every stand is inside the splash band %.2f .. %.2f"
			% [HARVEST.KELP_BAND_LO, HARVEST.KELP_BAND_HI])

# ---------------------------------------------------------------- 5. determinism

## The save is keyed by POSITION (save_manager.gd:460), so a spawner that chose positions at
## spawn time would break it. Hash every PLANNED position — the ones standing and the ones
## still to come — so two runs of this probe can be diffed for equality.
func _determinism(kelp_host: Node, beds_host: Node) -> void:
	_say("--- the whole spawn plan is decided at world build ---")
	var kelp_plan: Array = kelp_host.get("_kelp_plan")
	var bed_plan: Array = beds_host.get("_plan")
	var keys: PackedStringArray = PackedStringArray()
	for p in kelp_plan:
		keys.append("K %.2f,%.2f,%.2f" % [(p as Vector3).x, (p as Vector3).y, (p as Vector3).z])
	for pl in bed_plan:
		var p: Vector3 = (pl as Dictionary)["surface"]
		keys.append("M %.2f,%.2f,%.2f" % [p.x, p.y, p.z])
	for k in keys:
		_lines.append("    " + k)          # to the log only: this is the cross-run diff body
	var joined: String = "\n".join(keys)
	_say("  PLAN: %d kelp seats + %d mussel beds = %d positions" %
		[kelp_plan.size(), bed_plan.size(), keys.size()])
	_say("  PLAN HASH: %s" % joined.sha256_text())
	_ok(kelp_plan.size() >= HARVEST.KELP_OPENING,
		"the kelp plan covers at least the opening stock (%d)" % kelp_plan.size())
	_ok(bed_plan.size() > int(beds_host.get("_opening")),
		"the mussel plan has beds in reserve (%d planned, %d opening)"
			% [bed_plan.size(), int(beds_host.get("_opening"))])
	# A duplicate position is a COLLIDING save key — two nodes sharing one harvest entry.
	var seen: Dictionary = {}
	var dupes: int = 0
	for k in keys:
		var bare: String = k.substr(2)
		if seen.has(bare):
			dupes += 1
			_say("    duplicate save key %s" % bare)
		seen[bare] = true
	_ok(dupes == 0, "no two planned nodes share a save key (%d duplicates)" % dupes)

func _dive_floor_report(beds_host: Node) -> void:
	_say("--- the mussel dive floor, as it actually resolves ---")
	var y: float = float(beds_host.get("_dive_y"))
	var lo: float = float(MUSSELS.DIVE_FLOOR_MIN)
	_say("  shipping dive floor y %.2f (envelope floor %.2f); band bottom %.2f"
		% [y, lo, float(beds_host.get("_band_bottom"))])
	# WHAT THE CLAMP COSTS, in candidate seats. The docstring in mussel_beds._dive_floor used
	# to claim the clamp was inert because the coral stopped above it; that was an assertion,
	# and this is the measurement that replaced it.
	var seats: Array = beds_host.get("_seats")
	var above_clamped: int = 0
	var above_derived: int = 0
	var deepest_seat: float = 1.0e9
	for s in seats:
		var p: Vector3 = (s as Dictionary)["pos"]
		deepest_seat = minf(deepest_seat, p.y)
		if p.y >= y:
			above_clamped += 1
		if p.y >= -27.8:
			above_derived += 1
	_say("  colony seats: %d total, deepest y %.2f · %d above the shipped floor %.2f · %d above the derived -27.80 (the clamp costs %d candidate seats)"
		% [seats.size(), deepest_seat, above_clamped, y, above_derived,
			above_derived - above_clamped])
	var deepest: float = 1.0e9
	for b in (beds_host.get("beds") as Array):
		deepest = minf(deepest, (b as Node3D).global_position.y)
	_say("  deepest bed y %.2f — %.2f m of headroom over the floor that shipped"
		% [deepest, deepest - y])
	_ok(deepest >= y, "no bed is below the dive floor")

# ---------------------------------------------------------------- clock helpers

## Move the CALENDAR, additively, through the one absolute number that is monotonic across a
## sleep. Setting the intra-day position instead of adding to it is the s21 trap that made a
## five-day bed look broken (docs/AGENT_TRAPS.md).
func _advance_hours(h: float) -> void:
	var target: float = GameClock.game_time_hours() + h
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

func _tick(n: int = 3) -> void:
	for i in range(n):
		await get_tree().process_frame

## Wait for a live count to settle, on the WALL CLOCK rather than on a frame count.
##
## Both spawners poll on a real-seconds accumulator (4 s for kelp, 7 s for the reef) because
## nothing they watch moves faster than 900 real seconds. A headless main loop runs unbounded
## at ~0.2 ms a frame, so "await 300 frames" is 60 milliseconds here and the check has not run
## once — the same trap tests/mussel_probe.gd records for Salvage._work. Waits on the value,
## with a wall-clock cap, and returns as soon as it arrives.
func _settle_to(host: Node, want: int, counter: Callable, budget_ms: int = 14000) -> int:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < budget_ms:
		if int(counter.call(host)) >= want:
			break
		await get_tree().process_frame
	return int(counter.call(host))

## Run a Salvage job to completion. Waits on the job's OWN flag with a frame cap, never on a
## frame count: Salvage._work counts real seconds and a headless main loop runs unbounded, so
## 140 frames here is a quarter of a second rather than two (docs/AGENT_TRAPS.md).
func _work_out(node: Node, player: Node3D) -> void:
	for i in range(20000):
		if node.get("_working") != true:
			return
		PlayerState.oxygen = 1.0
		if player != null:
			player.global_position = (node as Node3D).global_position
		await get_tree().process_frame
	_say("    WARNING the job never completed in 20000 frames")

func _clear_pack() -> void:
	for i in range(PlayerState.HOTBAR_SIZE):
		PlayerState.hotbar[i] = null

func _harvest(node: Node) -> void:
	_clear_pack()
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null:
		player.global_position = (node as Node3D).global_position
	node.call("interact", String(node.get("verb")), player)
	await _work_out(node, player)

# ---------------------------------------------------------------- 1b. sleep regrow

## THE BUG THE OWNER REPORTED, as a test. Harvest a kelp stand and then SLEEP: nothing but the
## calendar moves, no real seconds are spent, and the stand must come back. On the pre-s47
## real-seconds countdown this could never pass — that is the whole point of it.
func _sleep_regrow() -> void:
	_say("--- harvest, then SLEEP: the thing a delta countdown cannot do ---")
	var stands: Array = _kelp_stands()
	if stands.is_empty():
		failures += 1
		_say("  FAIL  no kelp stand to harvest")
		return
	var node: Node = stands[0]
	var span: float = float(node.get("regrow_game_hours"))
	var before: int = _count("kelp_bundle")
	await _harvest(node)
	_ok(bool(node.get("spent")), "the stand is spent after a GATHER")
	_ok(_count("kelp_bundle") > before, "GATHER handed over kelp (%d -> %d)"
		% [before, _count("kelp_bundle")])
	var picked: float = float(node.get("_picked_at_h"))
	# A real-seconds tick that is NOT enough calendar: it must still be bare.
	var t0: int = Time.get_ticks_msec()
	await _tick(30)
	_ok(bool(node.get("spent")), "still bare after %d ms of real time and no calendar"
		% (Time.get_ticks_msec() - t0))
	# Now sleep. skip_to_next_dawn() is what a bunk does: +1 day, phase reset, 0 real seconds.
	var real_before: int = Time.get_ticks_msec()
	var sleeps: int = 0
	while GameClock.game_time_hours() - picked < span and sleeps < 12:
		GameClock.skip_to_next_dawn()
		sleeps += 1
	await _tick(4)
	_say("  slept %d night(s): %.1f game hours passed against a %.1f h span, in %d ms of real time"
		% [sleeps, GameClock.game_time_hours() - picked, span,
			Time.get_ticks_msec() - real_before])
	_ok(not bool(node.get("spent")), "the kelp GREW BACK over a slept night")
	_ok(sleeps <= 2, "a kelp stand is worth revisiting after one night (%d sleeps)" % sleeps)

func _count(id: String) -> int:
	var n: int = 0
	for i in range(PlayerState.hotbar.size()):
		if PlayerState.hotbar[i] == id:
			n += int(PlayerState.hotbar_counts[i]) if i < PlayerState.hotbar_counts.size() else 1
	for i in range(PlayerState.inventory.size()):
		if PlayerState.inventory[i] == id:
			n += int(PlayerState.inventory_counts[i]) if i < PlayerState.inventory_counts.size() else 1
	return n

# ---------------------------------------------------------------- 4. density over time

func _density(kelp_host: Node, beds_host: Node) -> void:
	_say("--- density rises on the calendar and STOPS at the cap ---")
	var k0: int = _kelp_stands().size()
	var m0: int = (beds_host.get("beds") as Array).size()
	var k_cap: int = mini(int(HARVEST.KELP_CAP), (kelp_host.get("_kelp_plan") as Array).size())
	var m_cap: int = (beds_host.get("_plan") as Array).size()
	_say("  opening: %d kelp (cap %d), %d beds (cap %d)" % [k0, k_cap, m0, m_cap])
	_ok(k0 < k_cap, "the dock has room to fill in (%d of %d)" % [k0, k_cap])
	_ok(m0 < m_cap, "the reef has room to thicken (%d of %d)" % [m0, m_cap])
	# One kelp interval at a time: the count must go up by ONE each time, not jump to the cap.
	var kelp_count := func(_h: Node) -> int: return _kelp_stands().size()
	var steps: PackedStringArray = PackedStringArray()
	var stepped_by_one: bool = true
	for i in range(4):
		_advance_hours(float(HARVEST.KELP_SETTLE_H))
		var got: int = await _settle_to(kelp_host, mini(k0 + i + 1, k_cap), kelp_count)
		steps.append("%d" % got)
		if got != mini(k0 + i + 1, k_cap):
			stepped_by_one = false
	_say("  kelp after 1..4 x %.0f game h: %s" % [HARVEST.KELP_SETTLE_H, " ".join(steps)])
	var k1: int = _kelp_stands().size()
	_ok(k1 > k0, "kelp stands appeared over time (%d -> %d)" % [k0, k1])
	_ok(stepped_by_one, "one new stand per interval — a frequency, not a batch")
	_ok(k1 <= k_cap, "kelp never exceeded its cap (%d <= %d)" % [k1, k_cap])
	# Now jump a long way past every interval and check BOTH stop at their caps.
	_advance_hours(400.0)
	var bed_count := func(h: Node) -> int: return (h.get("beds") as Array).size()
	var k2: int = await _settle_to(kelp_host, k_cap, kelp_count)
	var m2: int = await _settle_to(beds_host, m_cap, bed_count)
	_say("  after +400 game h: %d kelp (cap %d), %d beds (cap %d)" % [k2, k_cap, m2, m_cap])
	_ok(k2 == k_cap, "kelp settled exactly at its density cap (%d of %d)" % [k2, k_cap])
	_ok(m2 == m_cap, "the reef settled exactly at its density cap (%d of %d)" % [m2, m_cap])
	_ok(m2 == mini(m_cap, int(beds_host.get("_opening"))
		+ int(GameClock.game_time_hours() / MUSSELS.SETTLE_HOURS)),
		"the live bed count is the calendar's own function of the date")
	# Every late arrival must be seated exactly where the plan said, or its save key is wrong.
	var drift: float = 0.0
	var plan: Array = beds_host.get("_plan")
	var live: Array = beds_host.get("beds")
	for i in range(mini(plan.size(), live.size())):
		drift = maxf(drift, ((plan[i] as Dictionary)["surface"] as Vector3)
			.distance_to((live[i] as Node3D).global_position))
	_ok(drift < 0.001, "every bed stands on its planned position (worst drift %.4f m)" % drift)
	var kplan: Array = kelp_host.get("_kelp_plan")
	var kdrift: float = 0.0
	var stands: Array = _kelp_stands()
	stands.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.get_index() < b.get_index())
	for i in range(mini(kplan.size(), stands.size())):
		kdrift = maxf(kdrift, (kplan[i] as Vector3).distance_to((stands[i] as Node3D).global_position))
	_ok(kdrift < 0.001, "every kelp stand stands on its planned seat (worst drift %.4f m)" % kdrift)

# ---------------------------------------------------------------- 6. late arrival + save

## A bed that only exists because the calendar moved still has to persist. It was not in the
## tree when load_game() ran, so it depends on the deferred claim_harvest hand-off.
func _late_bed_save(beds_host: Node) -> void:
	_say("--- a LATE-SETTLED bed's spent state survives a save/load ---")
	var live: Array = beds_host.get("beds")
	var opening: int = int(beds_host.get("_opening"))
	if live.size() <= opening:
		failures += 1
		_say("  FAIL  no late-settled bed to test (%d live, %d opening)" % [live.size(), opening])
		return
	var bed: Node = live[live.size() - 1]
	var p: Vector3 = (bed as Node3D).global_position
	var key: String = "%.2f,%.2f,%.2f" % [p.x, p.y, p.z]
	await _harvest(bed)
	_ok(bool(bed.get("spent")), "the late bed is spent after a GATHER")
	var picked: float = float(bed.get("_picked_at_h"))
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
	_ok(harvest.has(key), "the save carries the late bed under its own key %s (of %d entries)"
		% [key, harvest.size()])
	bed.call("harvest_restore", {"spent": false})
	_ok(not bool(bed.get("spent")), "forced back to grown, as a fresh world build is")
	_ok(SaveManager.load_game(), "the slot loads")
	await _tick(3)
	_ok(bool(bed.get("spent")), "STILL SPENT after the reload — a late bed persists")
	_ok(picked > 0.0 and absf(float(bed.get("_picked_at_h")) - picked) < 0.01,
		"its five-day clock resumed where it was (%.3f h vs %.3f h)"
			% [float(bed.get("_picked_at_h")), picked])
