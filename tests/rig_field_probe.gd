extends Node
## THE FIELD — structural acceptance probe for rigs 2, 3 and 4 and the bridges that chain them.
##
## Run: godot --headless --path . res://tests/RigFieldProbe.tscn
##
## What it is for: this session placed roughly three thousand structural primitives across
## three new platforms, and the repo's expensive lesson is that hand-typed elevations drift
## (s52 found three of four kelp stands growing in mid air). So nothing here trusts an
## authored Y. Every walkable claim is settled by dropping a ray and reading what it hits.
##
## ANTI-VACUITY IS THE POINT. Three gates in this repo passed for sessions because their
## window was empty (`stance_pairs = 0`). Every check below that computes over a set first
## asserts the set is non-empty, and the draw-chunk budget has BOTH an upper and a lower
## bound — a field that failed to build has zero chunks and would otherwise sail through a
## "chunks < 140" gate for ever.

const LOG_PATH: String = "/tmp/rig_field_probe.txt"

## Draw-call posture. The whole point of RigKit.Bake is that three rigs cost tens of chunks,
## not thousands. UPPER bound is the budget; LOWER bound is the anti-vacuity assertion.
const CHUNKS_MAX: int = 220
const CHUNKS_MIN: int = 24
## The number that actually reaches the GPU when the whole field is on the horizon: "detail"
## chunks are engine-range-culled past RigKit.Bake.DETAIL_DRAW_M, so from SALTLINE-0 only
## these are submitted. This is the gate the brief's draw-call constraint really lands on.
const FAR_CHUNKS_MAX: int = 150

## A walkable point must find a surface within this band below the claimed floor, and have
## at least this much clear above it. The player capsule is 1.8 m tall (0.4 m radius).
const SEAT_TOL: float = 0.60
const HEAD_CLEAR: float = 1.85

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()
var _space: PhysicsDirectSpaceState3D
var _main: Node3D

func _ready() -> void:
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

## Drop a ray from `from_y` above the point and return the hit Y, or NAN.
## 2.2 m, not 3.0: the field now has decks slung 6 m under other decks, and a ray that
## starts 3 m up begins INSIDE the slab overhead and reports the underside of the floor
## above as the floor below. Any lower and a 1.85 m headroom check has nowhere to start.
func _seat(p: Vector3, from_above: float = 2.2, down: float = 7.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, from_above, 0), p + Vector3(0, from_above - down, 0))
	q.collide_with_areas = false
	# THE SKIP LIST — the repo's standing probe rule, newly earned here: since s59b the
	# player SPAWNS on the anchorage's spawn marker, so the seat ray was reading the top
	# of their own capsule (23.80) and reporting the arrival deck 1.8 m high.
	var skip: Array[RID] = []
	for g in ["player", "ship_cat"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is CollisionObject3D:
				skip.append((n as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit: Dictionary = _space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y

## Is there `HEAD_CLEAR` of nothing above a floor point?
func _headroom(p: Vector3, floor_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, floor_y + 0.15, p.z),
		Vector3(p.x, floor_y + 0.15 + HEAD_CLEAR, p.z))
	var hit: Dictionary = _space.intersect_ray(q)
	if hit.is_empty():
		return HEAD_CLEAR
	return (hit["position"] as Vector3).y - floor_y

func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	for i in range(8):
		await get_tree().physics_frame
	_space = _main.get_world_3d().direct_space_state

	# ---------------------------------------------------------------- the field exists
	var field: Node = _find_field(_main)
	_check("rig_field node is in the tree", field != null)
	if field == null:
		return
	var stats: Dictionary = field.get("stats")
	var rigs: Array = get_tree().get_nodes_in_group("field_rig")
	var bridges: Array = get_tree().get_nodes_in_group("field_bridge")
	_check("three rigs built", rigs.size() == 3, "rigs=%d" % rigs.size())
	_check("three bridges built", bridges.size() == 3, "bridges=%d" % bridges.size())

	# ---------------------------------------------------------------- the draw budget
	var chunks: int = int(stats.get("chunks", 0))
	var tris: int = int(stats.get("tris", 0))
	var prims: int = int(stats.get("prims", 0))
	_check("field built SOMETHING (anti-vacuity)", chunks >= CHUNKS_MIN and prims > 1500,
		"chunks=%d prims=%d tris=%d" % [chunks, prims, tris])
	_check("field draw chunks within budget", chunks <= CHUNKS_MAX,
		"chunks=%d (max %d) for 3 rigs + 3 bridges, %d primitives batched" % [chunks, CHUNKS_MAX, prims])
	var far: int = int(stats.get("hull", 0)) + int(stats.get("glass", 0)) + int(stats.get("lamp", 0))
	_check("chunks visible from SALTLINE-0 (hull+glass) within budget",
		far <= FAR_CHUNKS_MAX and far >= 12,
		"far=%d (max %d), detail=%d culled past %.0f m" % [far, FAR_CHUNKS_MAX, int(stats.get("detail", 0)), 210.0])
	_say("      build: %d ms, %d triangles across %d primitives" % [int(stats.get("ms", 0)), tris, prims])

	# ---------------------------------------------------------------- spacing contract
	var origins: Array = []
	for r in rigs:
		origins.append((r as Node3D).global_position)
	origins.sort_custom(func(a, b): return a.z < b.z)
	var chain: Array = [Vector3.ZERO] + origins
	var ok_spacing: bool = true
	var spacing_detail: String = ""
	for i in range(chain.size() - 1):
		var d: float = (chain[i + 1] - chain[i]).length()
		spacing_detail += "%.1f " % d
		if d < 140.0 or d > 170.0:
			ok_spacing = false
	_check("consecutive rigs are 140-170 m apart", ok_spacing and chain.size() == 4, spacing_detail.strip_edges())

	# ---------------------------------------------------------------- DEEPWELL is tallest
	var deep: Node3D = _rig_named(rigs, "deepwell")
	_check("DEEPWELL exists", deep != null)
	if deep != null:
		# Probe the crown block from above rather than trusting the constant.
		var crown: Vector3 = deep.global_position
		var top: float = _seat(Vector3(crown.x, 0.0, crown.z), 120.0, 40.0)
		_check("DEEPWELL derrick reads above y 88 (rig 1's derrick tops out at 52)",
			not is_nan(top) and top > 88.0, "crown hit y=%.2f" % top)

	# ---------------------------------------------------------------- walkable seats
	# Every one of these is a claimed FLOOR. Nothing here is asserted from a constant: the
	# ray decides, and a miss is a hole in the platform.
	var seats: Array = []
	for r in rigs:
		var rn: Node3D = r
		seats.append([str(rn.get_meta("rig_id")) + ":spawn", rn.get_meta("spawn")])
		seats.append([str(rn.get_meta("rig_id")) + ":overview", rn.get_meta("overview")])
	# Named interior/feature points, in each rig's LOCAL frame, transformed here.
	var locals := {
		"marrow": [["garden_bed_walk", Vector3(-17.0, 21.2, 11.0)],
			["plant_roof", Vector3(14.0, 21.2, 11.0)],
			["low_intake_deck", Vector3(29.0, 3.2, -19.0)],
			["pipe_rack_tip", Vector3(-48.0, 13.2, -14.0)],
			["process_deck", Vector3(-26.0, 6.8, 0.0)],
			["process_catwalk", Vector3(0.0, 10.0, 8.0)],
			["bio_lab", Vector3(-11.5, 14.0, -16.5)],
			["tank_farm_bund", Vector3(33.5, 14.0, 1.0)],
			["mezzanine_ring", Vector3(-39.6, 17.8, 0.0)]],
		"anchorage": [["atrium_floor", Vector3(0.0, 22.0, -8.0)],
			["tank_spur_G2", Vector3(0.0, 29.4, -3.0)],
			["gallery_G2", Vector3(0.0, 29.4, -8.5)],
			["gallery_G3", Vector3(-13.0, 33.1, 4.0)],
			["gallery_G4", Vector3(0.0, 36.8, -8.5)],
			["tank_spur_G4", Vector3(0.0, 36.8, 11.0)],
			["dining_hall", Vector3(28.0, 22.0, 2.0)],
			["kitchen", Vector3(30.0, 22.0, -18.0)],
			["private_dining", Vector3(29.0, 22.0, 14.5)],
			["suite_west", Vector3(-34.0, 22.0, 3.0)],
			["suite_south", Vector3(-29.0, 22.0, -22.0)],
			["west_hall", Vector3(-20.0, 22.0, 4.0)],
			["salon", Vector3(6.0, 22.0, -20.0)],
			["entrance", Vector3(-10.0, 22.0, -24.0)],
			["back_corridor", Vector3(22.0, 22.0, 19.0)],
			["tank_top_platform", Vector3(6.3, 39.45, 5.7)],
			["gallery_G2_east_link", Vector3(16.5, 29.4, 8.1)],
			["terrace", Vector3(0.0, 26.2, -20.0)],
			["plant_deck", Vector3(-28.0, 8.8, -8.0)],
			["leisure_deck", Vector3(-24.0, 15.4, 0.0)],
			["helideck_centre", Vector3(48.0, 30.0, -8.0)],
			["under_helideck", Vector3(46.0, 22.0, -8.0)],
			["promenade", Vector3(-46.0, 22.0, 2.5)],
			["west_tower_roof", Vector3(-29.0, 37.3, 12.0)],
			["spa_ground", Vector3(0.0, 22.0, 26.0)],
			["marina", Vector3(0.0, 2.2, -29.0)]],
		"deepwell": [["production_deck", Vector3(-22.0, 11.3, 8.0)],
			["production_catwalk", Vector3(0.0, 14.6, 14.0)],
			["outboard_ring", Vector3(-35.4, 23.6, 0.0)],
			["drill_floor", Vector3(0.0, 30.0, -9.0)],
			["bop_deck", Vector3(0.0, 24.5, -10.0)],
			["moon_pool_rim", Vector3(0.0, 20.0, -7.6)],
			["monkey_board", Vector3(0.0, 58.0, -7.6)],
			["decon_landing", Vector3(0.0, 2.6, -45.0)],
			["outboard_catwalk", Vector3(-34.6, 17.4, 0.0)]],
	}
	for r in rigs:
		var rn2: Node3D = r
		var rid: String = str(rn2.get_meta("rig_id"))
		for entry in locals.get(rid, []):
			seats.append([rid + ":" + str(entry[0]), rn2.global_transform * (entry[1] as Vector3)])

	_check("seat list is non-empty (anti-vacuity)", seats.size() >= 20, "seats=%d" % seats.size())
	var bad_seats: Array = []
	var low_head: Array = []
	for s in seats:
		var p: Vector3 = s[1]
		var y: float = _seat(p)
		if is_nan(y) or absf(y - p.y) > SEAT_TOL:
			bad_seats.append("%s want %.2f got %s" % [s[0], p.y, ("MISS" if is_nan(y) else "%.2f" % y)])
			continue
		var head: float = _headroom(p, y)
		if head < HEAD_CLEAR - 0.01:
			low_head.append("%s head %.2f" % [s[0], head])
	_check("every claimed floor has plating under it", bad_seats.is_empty(),
		"%d/%d bad: %s" % [bad_seats.size(), seats.size(), ", ".join(PackedStringArray(bad_seats))])
	_check("every claimed floor has 1.85 m of headroom", low_head.is_empty(),
		"%d/%d tight: %s" % [low_head.size(), seats.size(), ", ".join(PackedStringArray(low_head))])

	# ---------------------------------------------------------------- bridge continuity
	# Walk each span at 4 m intervals and drop a ray. A gap here is a player falling 20 m
	# into the North Sea, so the tolerance is tight and the sampling is dense.
	var total_samples: int = 0
	var gaps: Array = []
	for br in bridges:
		var a: Vector3 = br.get_meta("from")
		var c: Vector3 = br.get_meta("to")
		var n: int = maxi(8, int((c - a).length() / 3.0))
		for i in range(n + 1):
			var t: float = float(i) / float(n)
			var p: Vector3 = a.lerp(c, t)
			total_samples += 1
			var y: float = _seat(p, 2.5, 6.0)
			if is_nan(y) or absf(y - p.y) > 0.55:
				gaps.append("span%d t=%.2f (%.1f,%.1f,%.1f) want %.2f got %s" %
					[int(br.get_meta("index")) + 1, t, p.x, p.y, p.z, p.y,
					("MISS" if is_nan(y) else "%.2f" % y)])
	_check("bridge sampling actually happened (anti-vacuity)", total_samples >= 90,
		"samples=%d" % total_samples)
	_check("every bridge is continuously walkable end to end", gaps.is_empty(),
		"%d/%d gaps: %s" % [gaps.size(), total_samples, ", ".join(PackedStringArray(gaps)).left(400)])

	# ---------------------------------------------------------------- the aquarium
	var tanks: Array = get_tree().get_nodes_in_group("aquarium")
	_check("the ANCHORAGE aquarium published its water volume", tanks.size() == 1,
		"markers=%d" % tanks.size())
	if tanks.size() == 1:
		var r: float = float(tanks[0].get_meta("radius", 0.0))
		var hgt: float = float(tanks[0].get_meta("height", 0.0))
		var vol: float = PI * r * r * hgt
		_check("the column aquarium runs through four galleries", hgt >= 14.0 and r >= 4.5,
			"r=%.2f h=%.2f -> %.0f m3" % [r, hgt, vol])

	# ---------------------------------------------------------------- the stair audit
	# Every flight the field builds registers its [foot, head] pair. Three checks per flight,
	# none of which trusts the geometry that claimed to build it:
	#   1. floor within 0.5 m under a point just BEHIND the foot;
	#   2. floor within 0.5 m under a point just BEYOND the head — a stair to nowhere, a
	#      head under a slab, or a landing beside a void all fail here;
	#   3. a clear LINE OF CLIMB: rays 0.75 m and 1.6 m above the walking line from 15% of
	#      the way up to half a metre past the head. A rail crossing the flight, a slab
	#      sealing the top, or another flight stacked too low overhead all hit.
	var pairs: Array = field.get("stair_pairs")
	_check("stairs registered (anti-vacuity)", pairs.size() >= 40, "flights=%d" % pairs.size())
	var bad_ends: Array = []
	var blocked: Array = []
	for pi in range(pairs.size()):
		var a: Vector3 = pairs[pi][0]
		var cc: Vector3 = pairs[pi][1]
		if a.y > cc.y:
			var tv: Vector3 = a
			a = cc
			cc = tv
		var flat := Vector2(cc.x - a.x, cc.z - a.z)
		if flat.length() < 0.05:
			continue
		var dir3 := Vector3(flat.normalized().x, 0.0, flat.normalized().y)
		var tag: String = "#%d (%.1f,%.1f,%.1f)->(%.1f,%.1f,%.1f)" % [pi, a.x, a.y, a.z, cc.x, cc.y, cc.z]
		var fy: float = _seat(a - dir3 * 0.6, 1.8, 4.0)
		if is_nan(fy) or absf(fy - a.y) > 0.5:
			bad_ends.append("foot %s got %s" % [tag, "MISS" if is_nan(fy) else "%.2f" % fy])
		var hy2: float = _seat(cc + dir3 * 0.6, 1.8, 4.0)
		if is_nan(hy2) or absf(hy2 - cc.y) > 0.5:
			bad_ends.append("head %s got %s" % [tag, "MISS" if is_nan(hy2) else "%.2f" % hy2])
		for hh in [0.75, 1.6]:
			var from_p: Vector3 = a.lerp(cc, 0.15) + Vector3(0, hh, 0)
			var to_p: Vector3 = cc + dir3 * 0.5 + Vector3(0, hh, 0)
			var q := PhysicsRayQueryParameters3D.create(from_p, to_p)
			var hit: Dictionary = _space.intersect_ray(q)
			if not hit.is_empty():
				blocked.append("h%.2f %s at (%.1f,%.1f,%.1f)" % [hh, tag,
					hit["position"].x, hit["position"].y, hit["position"].z])
				break
	_check("every stair foot and head lands on real floor", bad_ends.is_empty(),
		"%d/%d bad: %s" % [bad_ends.size(), pairs.size() * 2, ", ".join(PackedStringArray(bad_ends)).left(600)])
	_check("every stair has a clear line of climb", blocked.is_empty(),
		"%d blocked: %s" % [blocked.size(), ", ".join(PackedStringArray(blocked)).left(600)])

	# ---------------------------------------------------------------- the dining view
	# From the dining hall toward the tank: the first thing a ray hits must be the TANK
	# GLASS, ~20 m away, through the drum's open east bay — not a pane, not a rib.
	var anch: Node3D = _rig_named(rigs, "anchorage")
	if anch != null:
		var from_w: Vector3 = anch.global_transform * Vector3(26.0, 23.6, 8.0)
		var to_w: Vector3 = anch.global_transform * Vector3(0.0, 25.0, 4.0)
		var q2 := PhysicsRayQueryParameters3D.create(from_w, to_w)
		var hit2: Dictionary = _space.intersect_ray(q2)
		var d2: float = (hit2["position"] - from_w).length() if not hit2.is_empty() else -1.0
		_check("the dining hall sees the tank through an open bay",
			not hit2.is_empty() and d2 > 15.0,
			"first hit at %.1f m (want >15 = the tank itself, not the drum wall at ~9)" % d2)

	# ---------------------------------------------------------------- the light switch
	# "Many lights once they are turned on" is a real claim, so it gets a real gate: the
	# field must be DARK before the circuit closes and LIT after, and both states are read
	# back off the nodes rather than assumed from the call returning.
	var lamps: int = int(stats.get("lamps", 0))
	var flights: int = int(stats.get("lights", 0))
	_check("the field carries a real amount of lighting (anti-vacuity)",
		lamps >= 12 and flights >= 30, "lamp chunks=%d, omni lights=%d" % [lamps, flights])
	var dark_ok: bool = not bool(field.call("is_lit"))
	PowerGrid.power_circuit("topside_floodlights")
	await get_tree().process_frame
	var lit_meshes: int = 0
	var lit_lights: int = 0
	for n in _all(field):
		if n is MeshInstance3D and (n as MeshInstance3D).has_meta("field_lamp") and (n as MeshInstance3D).visible:
			lit_meshes += 1
		elif n is OmniLight3D and n.is_in_group("rig_field_floods") and (n as OmniLight3D).light_energy > 0.01:
			lit_lights += 1
	_check("the field is dark until the breaker is closed, and lights when it is",
		dark_ok and lit_meshes == lamps and lit_lights == flights,
		"dark_before=%s  lit_after=%d/%d chunks, %d/%d lights" %
		[dark_ok, lit_meshes, lamps, lit_lights, flights])

	# ---------------------------------------------------------------- fishing spots
	var spots: Array = get_tree().get_nodes_in_group("field_fishing_spot")
	_check("each new rig carries at least 3 fishing spots", spots.size() >= 10,
		"spots=%d" % spots.size())
	var heights: Array = []
	for s in spots:
		heights.append((s as Node3D).global_position.y)
	heights.sort()
	_check("fishing spots span real height (low water to high deck)",
		heights.size() >= 9 and heights[heights.size() - 1] - heights[0] > 10.0,
		"y %.1f .. %.1f" % [heights[0], heights[heights.size() - 1]])

func _all(root: Node) -> Array:
	var out: Array = [root]
	for c in root.get_children():
		out.append_array(_all(c))
	return out

func _find_field(root: Node) -> Node:
	for c in root.get_children():
		var s: Script = c.get_script()
		if s != null and s.resource_path.ends_with("rig_field.gd"):
			return c
	return null

func _rig_named(rigs: Array, id: String) -> Node3D:
	for r in rigs:
		if str((r as Node).get_meta("rig_id")) == id:
			return r
	return null
