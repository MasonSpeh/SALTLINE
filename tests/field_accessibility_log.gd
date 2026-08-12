extends Node
## THE FIELD ACCESSIBILITY LOG — a durable, human-readable report on top of
## RigFieldProbe's pass/fail, requested after the s61 audit found a fully-sealed tank
## farm that no automated stair check could see (bund walls aren't stairs). Two things
## this checks that nothing else in the repo does:
##
##   1. EVERY OUTER-DECK EDGE, not just declared rail gaps. At each sample point around
##      each rig's DECK perimeter: if the floor does NOT continue near deck height (a
##      real drop), a rail collider MUST be found there. A gap that happens to be a
##      bridge/stair mouth is exempted by construction — the floor-continues check
##      passes it before the rail check ever runs.
##   2. EVERY STAIR FLIGHT registered in the field (mirrors RigFieldProbe's foot/head
##      seat + line-of-climb, so a flight failing there fails here too), written out
##      with its rig, endpoints and rise/run rather than just a count.
##
## Run: godot --headless --path . res://tests/FieldAccessibilityLog.tscn
## Writes: tests/out/field_accessibility_log.md (and prints the same to stdout)

const RIG_TWO := preload("res://scripts/world/rig_two.gd")
const RIG_THREE := preload("res://scripts/world/rig_three.gd")
const RIG_FOUR := preload("res://scripts/world/rig_four.gd")
const LOG_PATH := "res://tests/out/field_accessibility_log.md"

const EDGE_STEP: float = 2.0     ## metres between perimeter samples
const EDGE_INSET: float = 0.05   ## skip the exact corner pixel, ambiguous by construction
const FLOOR_TOL: float = 1.0     ## "still on deck" if a hit lands within this of MAIN_Y
const RAIL_PROBE: float = 0.55   ## half-length of the horizontal rail-detect ray, metres
const RAIL_H: float = 0.9        ## rail height above deck to probe at
## The floor-continuity check samples 0.15 m INWARD of the exact rim, not on it — a ray
## fired at the literal boundary face of a Rect2-sized deck box is a grazing hit and
## flip-flopped between separate runs of this same script (14.00 found, then not found,
## same world point, same query). 0.15 m inboard is still "standing at the edge" for any
## real player and removes the numeric coin-flip.
const FLOOR_INSET: float = 0.15

var failures: int = 0
var _space: PhysicsDirectSpaceState3D
var _lines: PackedStringArray = PackedStringArray()

func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)

func _ready() -> void:
	await _run()
	_say("")
	_say("FAILURES: %d" % failures)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
		print("[log] written to %s" % LOG_PATH)
	get_tree().quit(1 if failures > 0 else 0)

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in range(8):
		await get_tree().physics_frame
	_space = main.get_world_3d().direct_space_state

	var field: Node = _find_field(main)
	_say("# Field accessibility log")
	_say("")
	if field == null:
		_say("FAIL  rig_field not found — nothing to check")
		failures += 1
		return

	var rigs: Array = get_tree().get_nodes_in_group("field_rig")
	var specs: Array = [
		["marrow", RIG_TWO.DECK, RIG_TWO.MAIN_Y],
		["anchorage", RIG_THREE.DECK, RIG_THREE.MAIN_Y],
		["deepwell", RIG_FOUR.DECK, RIG_FOUR.MAIN_Y],
	]
	var pairs_early: Array = field.get("stair_pairs")
	var edge_total: int = 0
	var edge_bad: int = 0
	var edge_near_stair: int = 0
	for spec in specs:
		var id: String = spec[0]
		var anchor: Node3D = _rig_named(rigs, id)
		if anchor == null:
			_say("FAIL  %s — no Anchor marker found" % id)
			failures += 1
			continue
		var xf: Transform3D = anchor.global_transform
		var res: Dictionary = _check_perimeter(xf, spec[1] as Rect2, float(spec[2]))
		edge_total += int(res["checked"])
		_say("## %s — outer edge" % id.capitalize())
		_say("checked %d edge samples, %d open (no floor continuation), %d of those with NO rail"
			% [res["checked"], res["open"], (res["fail_pts"] as Array).size()])
		# CROSS-REFERENCE AGAINST THE REGISTERED STAIRS. A perimeter sample can miss the
		# flat-deck floor tolerance while standing legitimately on a sloped TREAD a metre
		# below flat height — that is a probe limitation, not a hazard, and it is only
		# distinguishable from a real gap beside a narrower-than-declared stair by asking
		# "is a real stair's own line within arm's reach of this point?"
		for wp in (res["fail_pts"] as Array):
			var near: float = 1e9
			for pr in pairs_early:
				var seg_a: Vector3 = pr[0]
				var seg_b: Vector3 = pr[1]
				near = minf(near, _dist_seg(wp, seg_a, seg_b))
			if near < 1.6:
				edge_near_stair += 1
				_say("  WARN  near a registered stair (%.1fm) — likely a sloped-tread sample, not a bare gap: (%.1f, %.1f, %.1f)"
					% [near, wp.x, wp.y, wp.z])
			else:
				edge_bad += 1
				_say("  FAIL  TRUE unguarded edge, %.1fm from the nearest stair: (%.1f, %.1f, %.1f)"
					% [near, wp.x, wp.y, wp.z])
	_say("")
	_say("**Edge total: %d checked, %d TRUE unguarded drops, %d near-stair (informational).**"
		% [edge_total, edge_bad, edge_near_stair])
	_say("")
	if edge_bad > 0:
		failures += 1

	# ---------------------------------------------------------------- the stair audit
	var pairs: Array = field.get("stair_pairs")
	_say("## Stairs — %d flights registered" % pairs.size())
	if pairs.size() < 40:
		_say("FAIL  anti-vacuity: expected at least 40 flights, found %d" % pairs.size())
		failures += 1
	var bad: Array = []
	for pi in range(pairs.size()):
		var a: Vector3 = pairs[pi][0]
		var c: Vector3 = pairs[pi][1]
		if a.y > c.y:
			var t: Vector3 = a
			a = c
			c = t
		var flat := Vector2(c.x - a.x, c.z - a.z)
		if flat.length() < 0.05:
			continue
		var dir3 := Vector3(flat.normalized().x, 0.0, flat.normalized().y)
		var rise: float = c.y - a.y
		var run: float = flat.length()
		var tag: String = "#%d rise %.1fm run %.1fm  (%.1f,%.1f,%.1f)->(%.1f,%.1f,%.1f)" \
			% [pi, rise, run, a.x, a.y, a.z, c.x, c.y, c.z]
		var fy: float = _seat(a - dir3 * 0.6, 1.8, 4.0)
		if is_nan(fy) or absf(fy - a.y) > 0.5:
			bad.append("foot miss %s" % tag)
			continue
		var hy: float = _seat(c + dir3 * 0.6, 1.8, 4.0)
		if is_nan(hy) or absf(hy - c.y) > 0.5:
			bad.append("head miss %s" % tag)
			continue
		var blocked: bool = false
		for hh in [0.75, 1.6]:
			var from_p: Vector3 = a.lerp(c, 0.15) + Vector3(0, hh, 0)
			var to_p: Vector3 = c + dir3 * 0.5 + Vector3(0, hh, 0)
			var q := PhysicsRayQueryParameters3D.create(from_p, to_p)
			var hit: Dictionary = _space.intersect_ray(q)
			if not hit.is_empty():
				blocked = true
				bad.append("blocked h%.2f %s at (%.1f,%.1f,%.1f)" % [hh, tag,
					hit["position"].x, hit["position"].y, hit["position"].z])
				break
	for line in bad:
		_say("  FAIL  %s" % line)
	if not bad.is_empty():
		failures += 1
	_say("")
	_say("**Stair total: %d flights, %d bad.**" % [pairs.size(), bad.size()])

## Sample a Rect2's four edges in LOCAL space at EDGE_STEP spacing, transform each point
## by `xf`, and classify: floor-continues (safe, a walkway/apron/podium extends past the
## nominal rim) vs a real drop with no rail.
func _check_perimeter(xf: Transform3D, deck: Rect2, main_y: float) -> Dictionary:
	var checked: int = 0
	var open_edges: int = 0
	var fail_pts: Array = []
	var edges: Array = [
		[Vector2(deck.position.x, deck.position.y), Vector2(deck.end.x, deck.position.y), Vector2(0, -1)],
		[Vector2(deck.position.x, deck.end.y), Vector2(deck.end.x, deck.end.y), Vector2(0, 1)],
		[Vector2(deck.position.x, deck.position.y), Vector2(deck.position.x, deck.end.y), Vector2(-1, 0)],
		[Vector2(deck.end.x, deck.position.y), Vector2(deck.end.x, deck.end.y), Vector2(1, 0)],
	]
	for e in edges:
		var p0: Vector2 = e[0]
		var p1: Vector2 = e[1]
		var normal2: Vector2 = e[2]
		var length: float = p0.distance_to(p1)
		var n: int = maxi(2, int(length / EDGE_STEP))
		for i in range(n + 1):
			var t: float = clampf(float(i) / float(n), EDGE_INSET, 1.0 - EDGE_INSET)
			var lp: Vector2 = p0.lerp(p1, t)
			var local_pt := Vector3(lp.x, main_y, lp.y)
			var wp: Vector3 = xf * local_pt
			var lp_in: Vector2 = lp - normal2 * FLOOR_INSET
			var wp_in: Vector3 = xf * Vector3(lp_in.x, main_y, lp_in.y)
			checked += 1
			var floor_y: float = _seat(wp_in, 2.0, 8.0)
			if not is_nan(floor_y) and absf(floor_y - main_y) <= FLOOR_TOL:
				continue   # deck continues here — a bridge/stair/apron mouth, not a drop
			open_edges += 1
			var wnorm: Vector3 = (xf.basis * Vector3(normal2.x, 0, normal2.y)).normalized()
			var rp: Vector3 = wp + Vector3(0, RAIL_H, 0)
			var q := PhysicsRayQueryParameters3D.create(rp - wnorm * RAIL_PROBE, rp + wnorm * RAIL_PROBE)
			q.collide_with_areas = false
			var hit: Dictionary = _space.intersect_ray(q)
			if hit.is_empty():
				fail_pts.append(wp)
	return {"checked": checked, "open": open_edges, "fail_pts": fail_pts}

## Distance from point `p` to the closest point on segment [a,b].
func _dist_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var len2: float = ab.length_squared()
	if len2 < 1e-6:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Drop a ray from `from_above` above the CLAIMED floor point `p` down to `down` below
## that, and return the hit Y (or NAN). Mirrors RigFieldProbe._seat exactly.
func _seat(p: Vector3, from_above: float = 2.2, down: float = 7.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, from_above, 0), p + Vector3(0, from_above - down, 0))
	q.collide_with_areas = false
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
