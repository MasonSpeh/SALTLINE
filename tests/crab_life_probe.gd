extends Node
## THE CRAB'S WHOLE DAY, MEASURED. CrabNightProbe already proves the JOURNEY works (roost
## -> support/rim -> plating); what it never asked is whether the pack behaves like an
## animal on either side of that journey:
##
##   * DAY   — do they actually move? over what VERTICAL range (the owner wants them
##             crawling up and down the legs, not idling in one band)? are their home
##             dens spread around all four caissons, or piled on three of them? and is
##             any of them standing INSIDE the concrete rather than on it?
##   * NIGHT — does the turnout RAMP? A pack that is all out ten seconds after nightfall
##             is a switch, not a night. This samples the emerged count at ten points
##             across the real 780 s NIGHT phase and prints the curve.
##   * SEAT  — every crab's origin, measured against the face under it, held to crab.gd's
##             own CLEAR and never more than a FaunaMove.SurfaceCrawler.FOOT slack either
##             side of it.
##
## It also sweeps the caisson columns themselves, because "crawl up and down the legs"
## is only meaningful where a leg HAS an exposed face: the pontoon skirt (y -3.05..0.95)
## is one solid casting wrapping all four legs, so the column report below is what says
## which depths are real surface and which are the inside of a slab.
##
## Run: godot --headless --path . res://tests/CrabLifeProbe.tscn

const MOVE := preload("res://scripts/world/fauna_move.gd")
const CRAWLER_FOOT: float = 0.02      ## FaunaMove.SurfaceCrawler.FOOT — the crawler's own
## clearance. The crab holds a deliberately larger CLEAR (0.10) because its body origin sits
## inside a 1.1 m shell rather than under a snail's foot; FOOT is the tolerance we allow
## around that, so "seated" means |gap - CLEAR| <= FOOT.
const TIME_SCALE: float = 6.0
const DAY_SAMPLE_SEC: float = 240.0   ## game seconds of daylight to watch. Long enough to
## cover a whole check-in cycle: crab.gd ranges for DEN_RANGE_MIN..MAX (55-145 s) before the
## den falls due, so a 45 s window measured the crawl but could never have caught a visit.
const DEN_HIT: float = 0.8            ## how close counts as "checked in"
## ---- CLUSTERING (s21). The owner's report is not "they never move", it is "they sit
## unnaturally NEXT TO EACH OTHER all day" — a complaint about the SPACING of the pack, which
## nothing here measured. travelled > 1 m over four minutes was the only movement bar, and a
## crab that shuffles a metre and stops passes it. So the day audit now also reports, every
## sample: each crab's nearest pack-mate, the closest pair anywhere in the pack, and what
## fraction of the window each animal was actually in motion. Those three numbers are what
## the complaint is about.
const CLUMP_DIST: float = 4.0         ## nearer than this and two giant crabs read as a pair
const MOVING_SPEED: float = 0.05      ## m/s under which a crab is "sitting", not crawling
const MOVING_SHARE: float = 0.60      ## and how much of the day a day crab has to spend above
## it. The bar is set BELOW what the pre-territory code already managed (68-80%) on purpose, so
## it is a real floor and not a rubber stamp for whatever the current build happens to do.
const RAMP_SAMPLES: int = 10          ## points across the night
const EMERGED_Y: float = 0.5          ## above this it is out of the water (test convention)
const LOG_PATH: String = "/tmp/crab_life_probe.txt"
## How far off the face a crab has to have open water before we call it VISIBLE. The rig is
## built out of CSG boxes, whose collision is a trimesh — and Godot's point query cannot see
## inside a concave shape at all, so point_solid() reports "open water" for a body sealed in
## the middle of a four-metre concrete slab. The honest test is the one a diver would run:
## cast from open water BACK at the animal along the face normal it is clinging to, because
## a trimesh front face does stop that ray.
const SIGHT: float = 6.0

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()
var _only: String = ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		_only = String(a).lstrip("-")
	await _run()
	_say("---")
	_say("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_say("PASS  " + label + ("  — " + detail if detail != "" else ""))
	else:
		failures += 1
		_say("FAIL  " + label + ("  — " + detail if detail != "" else ""))

## Land the clock on an exact fraction of a phase. force_phase() alone always starts a
## phase at 0.0, which is useless for measuring a ramp; the documented way to sit at an
## arbitrary point is to write _phase_elapsed_sec afterwards (tests/photo_shoot.gd).
func _set_time(phase: int, frac: float) -> void:
	GameClock.force_phase(phase)
	var dur: float = float(GameClock.phase_durations_minutes[phase]) * 60.0
	GameClock.set("_phase_elapsed_sec", clampf(frac, 0.0, 0.999) * dur)

## Which caisson a point sits over: "SE"/"NE"/"SW"/"NW", or "" for none. The legs are 6x6
## boxes centred on (+-22, +-12); the test convention for "at a leg" (content_probe,
## test_runner) is 5 m of slack around those centres, so the same window is used here.
func _leg_of(p: Vector3) -> String:
	if absf(absf(p.x) - 22.0) >= 5.0 or absf(absf(p.z) - 12.0) >= 5.0:
		return ""
	return ("N" if p.z > 0.0 else "S") + ("E" if p.x > 0.0 else "W")

## EVERY FAUNA COLLIDER IN THE WORLD, wherever it is parented — the skip list this probe has
## to carry now that the caissons are inhabited. `MOVE.kin_bodies` walks up to a
## `bloom_fauna.gd` host and collects what is under it, which is exactly the failure mode
## AGENT_TRAPS warns about: the reef's climbing snails are `BloomFauna.LampSnail` /
## `PyramidSnail` instances parented under `leg_reef`, and the s21 mussel beds under
## `mussel_beds` — so none of them were excluded, and each of them carries a solid
## FaunaTouch sphere standing up to 0.85 m proud of the concrete a crab clings to. The column
## sweep below sees them plainly ("face at |x| 25.48" against a real face at 25.00); the seat
## and visibility checks were silently measuring animals against animals.
##
## So: walk the tree once, and take every CollisionObject3D that lives under a node whose
## script is one of the fauna hosts. Cached — it is a whole-tree walk.
const FAUNA_HOSTS: Array = ["bloom_fauna.gd", "leg_reef.gd", "reef_life.gd", "reef_fish.gd",
	"mussel_beds.gd", "underwater_world.gd", "crab.gd", "king_crab.gd"]
var _fauna_skip: Array[RID] = []
var _fauna_skip_done: bool = false

func _fauna_bodies() -> Array[RID]:
	if _fauna_skip_done:
		return _fauna_skip
	_fauna_skip_done = true
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var s: Script = n.get_script() as Script
		var host: bool = false
		if s != null:
			for frag in FAUNA_HOSTS:
				if String(s.resource_path).ends_with(String(frag)):
					host = true
					break
		if host:
			for b in n.find_children("*", "CollisionObject3D", true, false):
				_fauna_skip.append((b as CollisionObject3D).get_rid())
			if n is CollisionObject3D:
				_fauna_skip.append((n as CollisionObject3D).get_rid())
			continue                     # everything beneath a fauna host is fauna
		for c in n.get_children():
			stack.append(c)
	_say("   fauna skip list: %d collision bodies excluded from every geometry cast"
		% _fauna_skip.size())
	return _fauna_skip

## Gap between a crab's origin and the face its own `up` says it is standing on. Negative
## means the origin is on the wrong side of the surface — i.e. inside it.
func _seat_gap(c: Node3D) -> float:
	var up: Vector3 = c.up
	var hit: Dictionary = MOVE.surface_hit(c, c.global_position, up, 0.9, 1.6,
		_fauna_bodies())
	if hit.is_empty():
		return INF
	return (c.global_position - (hit["point"] as Vector3)).dot(up)

## Could anyone SEE this crab? Ray from SIGHT metres out along the face normal of the leg it
## lives on, back to just off its shell. Anything in the way means it is crawling inside a
## casting or in a sealed pocket, however clean its seat reads.
##
## The AUTHORED normal (roost_up), not the crab's live `up`. A crab that is momentarily
## unseated — between faces, or drifting a hand's breadth off the concrete — has its `up`
## eased back toward +Y, and casting DOWNWARD at an animal that is legitimately underneath
## the pontoon slab hits the slab every time. That is a diver standing on the deck, not a
## diver in the water, and it failed a crab that was exactly where it was supposed to be.
func _exposed(c: Node3D) -> bool:
	var world: World3D = c.get_world_3d()
	if world == null:
		return true
	var up: Vector3 = (c.roost_up as Vector3).normalized()
	var q := PhysicsRayQueryParameters3D.create(c.global_position + up * SIGHT,
		c.global_position + up * 0.25)
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _fauna_bodies()
	return world.direct_space_state.intersect_ray(q).is_empty()

func world_of(n: Node3D) -> World3D:
	return n.get_world_3d()

## ---------------------------------------------------------------- the caisson columns
##
## For each leg, walk the outboard face from above the pontoon down into the deep and
## report where a body clinging at the authored 0.3 m stand-off would actually BE: in
## open water with concrete under it (a real cling face) or inside a casting.
func _sweep_columns(host: Node3D) -> void:
	_say("caisson column sweep — is there an exposed face to crawl, and where?")
	var skip: Array[RID] = _fauna_bodies()
	for leg in [Vector3(22, 0, -12), Vector3(22, 0, 12), Vector3(-22, 0, -12), Vector3(-22, 0, 12)]:
		var sx: float = signf(leg.x)
		var sz: float = signf(leg.z)
		var name: String = ("N" if sz > 0.0 else "S") + ("E" if sx > 0.0 else "W")
		# Swim in from open water at each depth and see WHAT you hit. The leg's own face is
		# at |x| 25; the pontoon skirt that sleeves it is at |x| 28. Which one answers tells
		# us, depth by depth, whether a crab clinging here is on the caisson or on the skirt
		# — and point_solid() cannot: CSG collision is a trimesh, and Godot's point query
		# never reports a point inside a concave shape, which is why the first version of
		# this sweep cheerfully called four metres of solid concrete "open water".
		var bands := {}
		var y: float = 2.0
		while y > -24.0:
			var from := Vector3(leg.x + sx * 12.0, y, leg.z)
			var to := Vector3(leg.x + sx * 1.0, y, leg.z)
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.collision_mask = 1
			q.collide_with_areas = false
			q.exclude = skip
			var hit: Dictionary = world_of(host).direct_space_state.intersect_ray(q)
			var face: String = "OPEN (nothing out to |x|%.0f)" % absf(to.x)
			if not hit.is_empty():
				face = "face at |x| %.2f" % absf((hit["position"] as Vector3).x)
			if not bands.has(face):
				bands[face] = [y, y]
			else:
				(bands[face] as Array)[1] = y
			y -= 0.5
		_say("   %s leg, swimming in along +-x:" % name)
		for k in bands:
			_say("      y %6.1f .. %6.1f   %s" % [(bands[k] as Array)[0], (bands[k] as Array)[1], k])

## ---------------------------------------------------------------- the territories
##
## What each crab has been given for the day, and whether it is real concrete. crab.gd works
## the territory out at runtime from the spawner's cling loops and from its own pack-mates, so
## the only honest way to check it is to read it back off the live animal and cast at it: both
## ends of every strip, at the top and the bottom of every depth slice, have to have the
## caisson behind them and open water in front.
func _territory_report(crabs: Array) -> void:
	_say("   day territories, read back off the live pack:")
	var off_face: Array[String] = []
	var overlap: Array[String] = []
	var terr: Array = []
	for c in crabs:
		var t: Dictionary = c.territory()
		terr.append(t)
		if not bool(t["ready"]):
			off_face.append("crab %d has no territory" % int(c.spawn_index))
			continue
		_say("      crab %d  face %-15s plane %6.2f  run %6.2f..%6.2f (%4.2f m)  "
			% [int(c.spawn_index), str((t["face"] as Vector3).snapped(Vector3.ONE * 0.01)),
				float(t["plane"]), float(t["tan_lo"]), float(t["tan_hi"]),
				float(t["tan_hi"]) - float(t["tan_lo"])]
			+ "column y %6.2f..%6.2f (%4.2f m)  leg %s"
				% [float(t["band_lo"]), float(t["band_hi"]),
					float(t["band_hi"]) - float(t["band_lo"]),
					str((t["leg"] as Vector3).snapped(Vector3.ONE * 0.1))])
		# Four corners of the patch. Each must have concrete a hand's breadth behind it.
		var n: Vector3 = t["face"]
		var tan: Vector3 = t["tan"]
		for tc in [float(t["tan_lo"]), float(t["tan_hi"])]:
			for y in [float(t["band_lo"]), float(t["band_hi"])]:
				var p: Vector3 = n * (float(t["plane"]) + 0.10) + tan * tc + Vector3.UP * y
				var q := PhysicsRayQueryParameters3D.create(p + n * SIGHT, p - n * 0.35)
				q.collision_mask = 1
				q.collide_with_areas = false
				q.exclude = _fauna_bodies()
				var hit: Dictionary = (c as Node3D).get_world_3d() \
					.direct_space_state.intersect_ray(q)
				if hit.is_empty() or absf((hit["position"] as Vector3).dot(n)
						- float(t["plane"])) > 0.25:
					off_face.append("crab %d corner t%.1f y%.1f" % [int(c.spawn_index), tc, y])
	# No two crabs on one caisson may share BOTH a face-parallel run and a depth slice.
	for i in range(crabs.size()):
		for j in range(i + 1, crabs.size()):
			var a: Dictionary = terr[i]
			var b: Dictionary = terr[j]
			if not bool(a["ready"]) or not bool(b["ready"]):
				continue
			if (a["leg"] as Vector3).distance_to(b["leg"] as Vector3) > 1.0:
				continue
			var dy: float = minf(float(a["band_hi"]), float(b["band_hi"])) \
				- maxf(float(a["band_lo"]), float(b["band_lo"]))
			if dy > 0.0:
				overlap.append("crabs %d+%d share %.2f m of depth on one leg"
					% [int(crabs[i].spawn_index), int(crabs[j].spawn_index), dy])
	_check("every day territory is a patch of real caisson, open on the water side",
		off_face.is_empty(), "off the concrete: %s" % str(off_face))
	_check("no two crabs on one caisson are given the same depth slice",
		overlap.is_empty(), str(overlap))

## ---------------------------------------------------------------- day
func _day_audit(crabs: Array) -> void:
	_say("")
	_say("=== DAY ===")
	_set_time(GameClock.Phase.DAY, 0.4)
	await get_tree().process_frame
	for i in range(30):
		await get_tree().physics_frame
	_territory_report(crabs)

	var n: int = crabs.size()
	var start: Array = []
	var lo_y: Array = []
	var hi_y: Array = []
	var travelled: Array = []
	var prev: Array = []
	var buried_frames: Array = []
	var worst_gap: Array = []
	# The check-in. HOME IS NOT WHERE THEY SIT (owner spec) — so this counts two different
	# things: how many separate visits each crab paid its den, and what share of the day it
	# spent parked in it. A pack that never goes home fails the first; a pack that lives at
	# home fails the second, and the old always-at-the-roost behaviour would have.
	var den_visits: Array = []
	var at_den: Array = []
	var den_frames: Array = []
	# Clustering + motion, per crab, over the whole window.
	var nn_sum: Array = []          ## sum of this crab's nearest-neighbour distance
	var nn_min: Array = []          ## and the closest it EVER got to another crab
	var clump_frames: Array = []    ## samples spent within CLUMP_DIST of any pack-mate
	var move_frames: Array = []     ## samples spent actually crawling
	var pack_min: float = INF       ## closest pair anywhere in the pack, over the window
	var pack_min_at: String = ""
	for c in crabs:
		start.append((c as Node3D).global_position)
		prev.append((c as Node3D).global_position)
		lo_y.append(99.0)
		hi_y.append(-99.0)
		travelled.append(0.0)
		buried_frames.append(0)
		worst_gap.append(0.0)
		den_visits.append(0)
		at_den.append(false)
		den_frames.append(0)
		nn_sum.append(0.0)
		nn_min.append(INF)
		clump_frames.append(0)
		move_frames.append(0)

	Engine.time_scale = TIME_SCALE
	var elapsed: float = 0.0
	var samples: int = 0
	var skip: Array[RID] = _fauna_bodies()
	while elapsed < DAY_SAMPLE_SEC:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		elapsed += dt
		samples += 1
		for i in range(n):
			var c: Node3D = crabs[i]
			if not is_instance_valid(c):
				continue
			var p: Vector3 = c.global_position
			var hop: float = (p - (prev[i] as Vector3)).length()
			if hop / maxf(dt, 0.0001) > MOVING_SPEED:
				move_frames[i] = int(move_frames[i]) + 1
			travelled[i] = float(travelled[i]) + hop
			prev[i] = p
			lo_y[i] = minf(float(lo_y[i]), p.y)
			hi_y[i] = maxf(float(hi_y[i]), p.y)
			if MOVE.point_solid(c, p, skip):
				buried_frames[i] = int(buried_frames[i]) + 1
			var g: float = _seat_gap(c)
			if g != INF:
				worst_gap[i] = maxf(float(worst_gap[i]), absf(g - c.CLEAR))
			var home: bool = p.distance_to(c._home as Vector3) < DEN_HIT
			if home:
				den_frames[i] = int(den_frames[i]) + 1
				if not bool(at_den[i]):
					den_visits[i] = int(den_visits[i]) + 1
			at_den[i] = home
		# THE SPACING. One pass over the pack per sample — 28 pairs for eight crabs, which is
		# nothing next to the eight seat raycasts above.
		for i in range(n):
			var near: float = INF
			var who: int = -1
			for j in range(n):
				if i == j:
					continue
				var d: float = (crabs[i] as Node3D).global_position.distance_to(
					(crabs[j] as Node3D).global_position)
				if d < near:
					near = d
					who = j
			if near == INF:
				continue
			nn_sum[i] = float(nn_sum[i]) + near
			nn_min[i] = minf(float(nn_min[i]), near)
			if near < CLUMP_DIST:
				clump_frames[i] = int(clump_frames[i]) + 1
			if near < pack_min:
				pack_min = near
				pack_min_at = "crabs %d+%d at t+%.0fs, %s" % [i, who, elapsed,
					str((crabs[i] as Node3D).global_position.snapped(Vector3.ONE * 0.1))]
		# Trace one crab's drift, so a pack that walks off its leg says WHERE it went and
		# where it thought it was going, rather than only showing up as a bad end position.
		if samples % 120 == 0:
			var t: Node3D = crabs[0]
			_say("      [t+%5.1fs] crab 0 %s at %s -> %s  up %s  %s"
				% [elapsed, preload("res://scripts/world/crab.gd").State.keys()[int(t.state)],
					str(t.global_position.snapped(Vector3.ONE * 0.1)),
					str((t._roam_target as Vector3).snapped(Vector3.ONE * 0.1)),
					str((t.up as Vector3).snapped(Vector3.ONE * 0.01)),
					"seated" if bool(t._seated) else "ADRIFT"])
		# Hold the phase: at 6x the 34-minute DAY still cannot roll over, but a probe that
		# silently drifted into DUSK would be measuring the wrong animal.
		if GameClock.current_phase != GameClock.Phase.DAY:
			_set_time(GameClock.Phase.DAY, 0.4)
	Engine.time_scale = 1.0

	var legs := {}
	var total_buried: int = 0
	var moved_any: int = 0
	var seen: int = 0
	var vert: Array = []
	for i in range(n):
		var c: Node3D = crabs[i]
		var p: Vector3 = c.global_position
		var leg: String = _leg_of(p)
		legs[leg] = int(legs.get(leg, 0)) + 1
		total_buried += int(buried_frames[i])
		var span: float = float(hi_y[i]) - float(lo_y[i])
		vert.append(span)
		if float(travelled[i]) > 1.0:
			moved_any += 1
		if _exposed(c):
			seen += 1
		var CrabS := preload("res://scripts/world/crab.gd")
		_say("   crab %d  leg %-3s  %-7s L%-2d  at %-22s up %-18s %s  -> target %-22s  crawled %5.1fm  y %6.2f..%6.2f (span %4.2f)  seat err %.3f  %s"
			% [i, leg if leg != "" else "--", CrabS.State.keys()[int(c.state)], int(c._level),
				str(p.snapped(Vector3.ONE * 0.01)),
				str((c.up as Vector3).snapped(Vector3.ONE * 0.01)),
				"seated" if bool(c._seated) else "ADRIFT",
				str((c._roam_target as Vector3).snapped(Vector3.ONE * 0.01)),
				float(travelled[i]),
				float(lo_y[i]), float(hi_y[i]), span, float(worst_gap[i]),
				"visible" if _exposed(c) else "BURIED"])
	_say("   den spread by caisson: %s" % str(legs))

	_check("every crab is awake and crawling by day", moved_any == n,
		"%d of %d moved more than a metre in %.0fs" % [moved_any, n, DAY_SAMPLE_SEC])
	_check("the dens are spread over all four caissons", legs.size() >= 4 and not legs.has(""),
		"occupied: %s" % str(legs))
	var max_per_leg: int = 0
	for k in legs:
		max_per_leg = maxi(max_per_leg, int(legs[k]))
	_check("no caisson carries more than a quarter of the pack, rounded up",
		max_per_leg <= int(ceil(float(n) / 4.0)), "busiest leg has %d of %d" % [max_per_leg, n])
	var climbers: int = 0
	for v in vert:
		if float(v) > 2.0:
			climbers += 1
	_check("the day crawl works the leg VERTICALLY, not one flat band", climbers >= n / 2,
		"%d of %d crabs covered more than 2 m of depth in %.0fs" % [climbers, n, DAY_SAMPLE_SEC])
	_check("no crab spends the day inside the concrete", total_buried == 0,
		"%d buried crab-frames across %d samples" % [total_buried, samples])
	_check("every day roost is out in the open water where it can be seen", seen == n,
		"%d of %d have %.0f m of clear water off the face they cling to" % [seen, n, SIGHT])
	var seated_ok: int = 0
	for g in worst_gap:
		if float(g) <= CRAWLER_FOOT:
			seated_ok += 1
	_check("every crab is seated flush (|gap - CLEAR| <= SurfaceCrawler.FOOT)",
		seated_ok == n, "%d of %d within %.2f m" % [seated_ok, n, CRAWLER_FOOT])
	var checked_in: int = 0
	var homebodies: int = 0
	var visit_total: int = 0
	for i in range(n):
		visit_total += int(den_visits[i])
		if int(den_visits[i]) > 0:
			checked_in += 1
		if float(den_frames[i]) / float(maxi(samples, 1)) > 0.5:
			homebodies += 1
	_say("   den visits in %.0fs: %s   (frames spent at home: %s of %d samples)"
		% [DAY_SAMPLE_SEC, str(den_visits), str(den_frames), samples])
	_check("the pack checks back in at its dens", checked_in >= n / 2,
		"%d of %d crabs visited home, %d visits total in %.0fs"
			% [checked_in, n, visit_total, DAY_SAMPLE_SEC])
	_check("but none of them LIVES there — home is a visit, not a seat", homebodies == 0,
		"%d of %d spent over half the day parked at the den" % [homebodies, n])

	# ---------------------------------------------------------------- the spacing
	_say("")
	_say("   --- pack spacing (the owner's complaint: 'sitting next to each other all day') ---")
	var nn_mean_all: float = 0.0
	var lonely: int = 0
	var busy: int = 0
	for i in range(n):
		var nn_mean: float = float(nn_sum[i]) / float(maxi(samples, 1))
		nn_mean_all += nn_mean
		if float(nn_min[i]) >= CLUMP_DIST:
			lonely += 1
		var mv: float = float(move_frames[i]) / float(maxi(samples, 1))
		if mv >= MOVING_SHARE:
			busy += 1
		_say("   crab %d  nearest pack-mate: mean %6.2f m, closest %6.2f m   "
			% [i, nn_mean, float(nn_min[i])]
			+ "within %.0f m for %4.1f%% of the day   moving %4.1f%% of the day   "
				% [CLUMP_DIST, 100.0 * float(clump_frames[i]) / float(maxi(samples, 1)), 100.0 * mv]
			+ "path %5.1f m, net %5.1f m"
				% [float(travelled[i]),
					(crabs[i] as Node3D).global_position.distance_to(start[i] as Vector3)])
	nn_mean_all /= float(maxi(n, 1))
	_say("   closest pair anywhere in the pack over %.0fs: %.2f m  (%s)"
		% [DAY_SAMPLE_SEC, pack_min, pack_min_at])
	_say("   end-of-window pairwise distance matrix (m):")
	for i in range(n):
		var row: PackedStringArray = PackedStringArray()
		for j in range(n):
			row.append("  --  " if i == j else "%6.1f" % (crabs[i] as Node3D)
				.global_position.distance_to((crabs[j] as Node3D).global_position))
		_say("      %d |%s" % [i, "".join(row)])
	_check("no two crabs spend the day within touching distance of each other",
		pack_min >= CLUMP_DIST,
		"closest pair %.2f m (bar %.1f m) — %s" % [pack_min, CLUMP_DIST, pack_min_at])
	_check("every crab keeps its own stretch of leg", lonely == n,
		"%d of %d never came within %.1f m of a pack-mate" % [lonely, n, CLUMP_DIST])
	_check("mean nearest-neighbour spacing is a rig apart, not a shell apart",
		nn_mean_all >= 8.0, "mean over the pack: %.2f m" % nn_mean_all)
	_check("a day crab is in motion, not parked", busy == n,
		"%d of %d were moving for at least %.0f%% of the window"
			% [busy, n, MOVING_SHARE * 100.0])
	return

## ---------------------------------------------------------------- night
func _night_ramp(crabs: Array) -> Array:
	_say("")
	_say("=== NIGHT (the emergence ramp) ===")
	var n: int = crabs.size()
	_set_time(GameClock.Phase.NIGHT, 0.0)
	GameClock.night.emit()          # force_phase already emitted; harmless, and it makes the
	# per-night roll explicit even if a future refactor moves the hook.
	await get_tree().process_frame

	var night_sec: float = float(GameClock.phase_durations_minutes[GameClock.Phase.NIGHT]) * 60.0
	_say("   night is %.0fs of game time; sampling %d points at %.0fx" % [night_sec, RAMP_SAMPLES, TIME_SCALE])
	Engine.time_scale = TIME_SCALE
	var curve: Array = []
	# High-water marks. Where a crab IS at a sample says little — it may be halfway up a leg,
	# or already walking back down the tower — so the peak is what proves the climb happened.
	var peak: Array = []
	for i in range(n):
		peak.append(-99.0)
	for s in range(RAMP_SAMPLES):
		var want_frac: float = float(s + 1) / float(RAMP_SAMPLES)
		while GameClock.phase_fraction() < want_frac \
				and GameClock.current_phase == GameClock.Phase.NIGHT:
			await get_tree().process_frame
			for i in range(n):
				if is_instance_valid(crabs[i]):
					peak[i] = maxf(float(peak[i]), (crabs[i] as Node3D).global_position.y)
		var out: int = 0
		var climbed: int = 0
		for i in range(n):
			var c: Node3D = crabs[i]
			if not is_instance_valid(c):
				continue
			if c.global_position.y > EMERGED_Y:
				out += 1
			if float(peak[i]) > 16.0:
				climbed += 1
		curve.append(out)
		_say("   night %3d%%   emerged %d/%d   (have reached the topside plate: %d)"
			% [int(want_frac * 100.0), out, n, climbed])
		if GameClock.current_phase != GameClock.Phase.NIGHT:
			break
	Engine.time_scale = 1.0
	var CrabS := preload("res://scripts/world/crab.gd")
	for i in range(n):
		var c: Node3D = crabs[i]
		_say("   crab %d  %-7s  y%6.2f  peak y%6.2f  %s"
			% [i, CrabS.State.keys()[int(c.state)], c.global_position.y, float(peak[i]),
				"[support route]" if not (c.leg_climb as Array).is_empty() else "[rim lane]"])
	return curve

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	for i in range(10):
		await get_tree().physics_frame

	var crabs: Array = get_tree().get_nodes_in_group("giant_crab")
	crabs.sort_custom(func(a, b): return int(a.spawn_index) < int(b.spawn_index))
	var want: int = int(preload("res://scripts/world/bloom_fauna.gd").CRAB_COUNT)
	_check("the pack spawned at its authored cap", crabs.size() == want,
		"%d crabs (cap %d)" % [crabs.size(), want])
	if crabs.is_empty():
		return

	# Park the player far away and non-colliding: a nearby player turns PATROL into PURSUE
	# and the day/night measurement would be measuring a chase instead.
	var p: Node3D = main.get("player")
	if p != null and p is CollisionObject3D:
		var pc := p as CollisionObject3D
		pc.set_collision_layer_value(1, false)
		pc.set_collision_mask_value(1, false)
		(p as Node3D).global_position = Vector3(-150, 40, 150)

	_sweep_columns(crabs[0])
	if _only != "night":
		await _day_audit(crabs)
	var curve: Array = []
	if _only != "day":
		curve = await _night_ramp(crabs)

	# THE RAMP ITSELF. Not "some crabs came out" — the turnout has to GROW: the first
	# tenth of the night must be quieter than the last, and the peak must be a real pack.
	if curve.size() >= RAMP_SAMPLES:
		var early: int = int(curve[0]) + int(curve[1])          # first 20% of the night
		var late: int = int(curve[curve.size() - 2]) + int(curve[curve.size() - 1])
		var peak: int = 0
		for v in curve:
			peak = maxi(peak, int(v))
		_check("early night is sparse", int(curve[0]) <= maxi(1, crabs.size() / 4),
			"%d of %d out at 10%% of the night" % [int(curve[0]), crabs.size()])
		_check("the turnout RAMPS across the night", late > early,
			"first 20%%: %d crab-samples, last 20%%: %d" % [early, late])
		_check("deep night is a real pack", peak >= crabs.size() / 2,
			"peak %d of %d" % [peak, crabs.size()])
		_say("   ramp: %s" % str(curve))

	if _only == "day":
		return
	# Nothing may finish the night standing in solid geometry.
	var skip: Array[RID] = _fauna_bodies()
	var buried: Array[String] = []
	for c in crabs:
		if MOVE.point_solid(c, (c as Node3D).global_position, skip):
			buried.append("crab %d at %s" % [int(c.spawn_index), str((c as Node3D).global_position)])
	_check("no crab ends the night inside a collider", buried.is_empty(), str(buried))
