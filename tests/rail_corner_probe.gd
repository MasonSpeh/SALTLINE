extends Node
## RAIL CORNER PROBE — the harness s59 deferred and s65 finally built.
##
## THE BUG IT GUARDS. `RigKit.rail_run()` emits ONE box collider per rail run, spanning the
## run's full authored length with a square cap at each end. Where two runs meet at a right
## angle those caps are two flat faces with an outside corner between them, and a capsule
## cutting the corner diagonally touches both in the same frame: it takes a slide direction
## from each, they cancel, and the player stops dead on thin air a hand's width from the
## rail. Rig 1 has shaved 0.18 m off every rail collider end since s20
## (`rig_builder.RAIL_END_SHAVE`); the KIT that builds MARROW, THE ANCHORAGE and DEEPWELL
## never received it, which is why the owner has reported being "permanently stuck on the
## corners of railing" in every session since the field was built.
##
## The worst case is not a corner at all. On the outboard mezzanine rings, four `railed_walk`
## runs share their corner points, so each run's INNER rail crosses the perpendicular walkway
## and terminates in mid-lane — leaving a PARALLEL-SIDED GATE between that end cap and the
## opposite outer rail. Measured before the fix: 0.83 m against a 0.74 m capsule. And a
## parallel slot defeats the controller's own `_wedge_escape`, which moves along the SUM of
## the wall normals — exactly zero when the two faces are opposed.
##
## WHY THIS MEASURES RATHER THAN ASSERTS. Neither existing instrument samples this geometry:
## `rig_field_probe` checks stair seating and lines of climb, and `field_accessibility_log`
## clamps its perimeter samples to [0.05, 0.95] of each edge — 3.3 m from the corner on
## DEEPWELL's 66 m deck. So both were green through the whole bug. This probe walks a capsule
## THROUGH each corner and prints the narrowest clearance it found, so a regression shows up
## as a number moving rather than as silence.
##
## Run:  godot --headless --path . res://tests/RailCornerProbe.tscn

const LOG_PATH: String = "/tmp/rail_corner_probe.txt"

## The player capsule, from player_controller.gd (PLAYER_RADIUS 0.37, scene height 1.8).
const CAP_R: float = 0.37
const CAP_H: float = 1.8
## A lane must clear the capsule by this much per side to be honestly walkable. Below it the
## player scrapes both faces at once, which is the condition that cancels the slide.
const MIN_SIDE_CLEAR: float = 0.06

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()
var _space: PhysicsDirectSpaceState3D
var _main: Node3D
var _shape: CapsuleShape3D

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

## Does a player-sized capsule standing with its FEET at `foot` overlap anything solid?
## The player and the cat are excluded — the probe must not read the player's own body, the
## standing rule earned in s59b.
func _blocked(foot: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _shape
	params.transform = Transform3D(Basis.IDENTITY, foot + Vector3(0, CAP_H * 0.5, 0))
	params.collide_with_areas = false
	var skip: Array[RID] = []
	for g in ["player", "ship_cat"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is CollisionObject3D:
				skip.append((n as CollisionObject3D).get_rid())
	params.exclude = skip
	return not _space.intersect_shape(params, 1).is_empty()

## Sweep the capsule ACROSS a lane and return the widest continuous free width found, in
## metres. `mid` is a point on the lane's centreline at foot height, `across` a unit vector
## perpendicular to travel. Sampling at 2 cm, out to +-`reach`.
func _lane_width(mid: Vector3, across: Vector3, reach: float) -> float:
	var step: float = 0.02
	var best: float = 0.0
	var run: float = 0.0
	var t: float = -reach
	while t <= reach:
		if _blocked(mid + across * t):
			run = 0.0
		else:
			run += step
			best = maxf(best, run)
		t += step
	return best

## Walk the capsule round a corner along a quarter-arc and return the NARROWEST lane width
## found on the way. `c` is the inside corner point, `r` the walking radius, `a0`/`a1` the
## arc in radians. At each station the lane is measured radially.
func _corner_walk(c: Vector3, r: float, a0: float, a1: float, reach: float) -> float:
	var worst: float = 99.0
	for i in range(13):
		var a: float = lerpf(a0, a1, float(i) / 12.0)
		var dir := Vector3(cos(a), 0, sin(a))
		var w: float = _lane_width(c + dir * r, dir, reach)
		worst = minf(worst, w)
	return worst

func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(9.0).timeout
	_space = get_viewport().get_world_3d().direct_space_state
	_shape = CapsuleShape3D.new()
	_shape.radius = CAP_R
	_shape.height = CAP_H

	var field: Node = get_tree().get_first_node_in_group("field_rig")
	_check("the field is built (anti-vacuity)", field != null, "")
	if field == null:
		return

	var need: float = CAP_R * 2.0 + MIN_SIDE_CLEAR * 2.0
	_say("      capsule %.2f m wide; a lane must measure >= %.2f m to pass honestly" %
		[CAP_R * 2.0, need])

	# ---- THE MEZZANINE RINGS. The reported failure, on both rigs that have one.
	var rings: Array = []
	var T2 := preload("res://scripts/world/rig_two.gd")
	var T4 := preload("res://scripts/world/rig_four.gd")
	var F := preload("res://scripts/world/rig_field.gd")
	rings.append(["MARROW", Transform3D(Basis(Vector3.UP, deg_to_rad(F.MARROW_YAW)), F.MARROW_ORIGIN),
		T2.DECK, 1.6, T2.MEZZ_Y])
	rings.append(["DEEPWELL", Transform3D(Basis(Vector3.UP, deg_to_rad(F.DEEPWELL_YAW)), F.DEEPWELL_ORIGIN),
		T4.DECK, 2.4, T4.MEZZ_Y])
	var worst_ring: float = 99.0
	var worst_where: String = ""
	for spec in rings:
		var name_: String = spec[0]
		var xf: Transform3D = spec[1]
		var deck: Rect2 = spec[2]
		var o: float = spec[3]
		var y: float = spec[4]
		for cs in [[deck.position.x - o, deck.position.y - o], [deck.end.x + o, deck.position.y - o],
				[deck.position.x - o, deck.end.y + o], [deck.end.x + o, deck.end.y + o]]:
			var local := Vector3(float(cs[0]), y, float(cs[1]))
			var w: float = _corner_walk(xf * local, 0.0, 0.0, TAU * 0.999, 1.6)
			if w < worst_ring:
				worst_ring = w
				worst_where = "%s (%.1f, %.1f)" % [name_, cs[0], cs[1]]
	_check("mezzanine ring corners pass a player capsule", worst_ring >= need,
		"narrowest %.2f m at %s (need %.2f)" % [worst_ring, worst_where, need])

	# ---- EVERY OTHER RAIL CORNER: the four rigs' main-deck rims. rail_rect drives all four
	# sides off shared corner points, so each of these is the same square-cap junction.
	var decks: Array = [
		["MARROW", Transform3D(Basis(Vector3.UP, deg_to_rad(F.MARROW_YAW)), F.MARROW_ORIGIN), T2.DECK, T2.MAIN_Y],
		["DEEPWELL", Transform3D(Basis(Vector3.UP, deg_to_rad(F.DEEPWELL_YAW)), F.DEEPWELL_ORIGIN), T4.DECK, T4.MAIN_Y],
	]
	var T3 := preload("res://scripts/world/rig_three.gd")
	decks.append(["ANCHORAGE", Transform3D(Basis(Vector3.UP, deg_to_rad(F.ANCHORAGE_YAW)), F.ANCHORAGE_ORIGIN),
		T3.DECK, T3.MAIN_Y])
	var worst_deck_block: float = 0.0
	var worst_deck_where: String = ""
	var sampled: int = 0
	var obstructed_straights: int = 0
	for spec2 in decks:
		var name2: String = spec2[0]
		var xf2: Transform3D = spec2[1]
		var deck2: Rect2 = spec2[2]
		var y2: float = spec2[3]
		# Stand 0.75 m inboard of each corner — the diagonal a player actually cuts.
		for cs2 in [[deck2.position.x, deck2.position.y, 1.0, 1.0], [deck2.end.x, deck2.position.y, -1.0, 1.0],
				[deck2.position.x, deck2.end.y, 1.0, -1.0], [deck2.end.x, deck2.end.y, -1.0, -1.0]]:
			# WALK THE CORNER THE WAY A PLAYER DOES: an L-path held INSET from both rails,
			# in along one edge and out along the other. Two earlier shapes were tried and
			# rejected as bad proxies — a lane measured across the corner POCKET (a pocket is
			# tight by construction and nobody walks through it), and an arc centred on the
			# corner APEX (whose end stations sit ON the rail lines, so the capsule overlaps
			# the rail and the probe convicts its own geometry). INSET clears the rail
			# honestly: 0.07 rail half-thickness + 0.37 capsule radius = 0.44 minimum.
			var apex := Vector2(float(cs2[0]), float(cs2[1]))
			var sxx: float = float(cs2[2])
			var szz: float = float(cs2[3])
			# INSET IS MEASURED FROM THE DECK RECT, NOT FROM THE RAIL. `KIT.rail_rect` takes
			# its own inset (0.4 on THE ANCHORAGE, 0.2-0.35 elsewhere), so the rail line sits
			# INBOARD of the rect boundary by an amount that varies per rig. A first cut used
			# 0.55 and reported all twelve corners blocked — it was standing the capsule on
			# the rail. 1.0 m clears the deepest rail inset plus the 0.44 m a capsule needs,
			# and is a realistic walking line rather than a hugging one.
			var inset: float = 1.0
			var corner_blocked: int = 0
			var corner_stations: int = 0
			for i2 in range(9):
				# 0..4 run in along the first edge; 4..8 run out along the second.
				var t2: float = float(i2) / 4.0
				var lp: Vector3
				if i2 <= 4:
					lp = Vector3(apex.x + sxx * lerpf(2.6, inset, t2), y2, apex.y + szz * inset)
				else:
					lp = Vector3(apex.x + sxx * inset, y2, apex.y + szz * lerpf(inset, 2.6, t2 - 1.0))
				var seat: float = _seat_y(xf2 * lp)
				if is_nan(seat):
					continue       # deliberate opening (rig corners are open to the sea by design)
				corner_stations += 1
				var world: Vector3 = xf2 * lp
				world.y = seat + 0.03
				if _blocked(world):
					# ONLY THE TURN COUNTS. Stations 3-5 straddle the apex; those are the ones
					# the square-cap trap closes. A block further out (0-2, 6-8) is 2 m down a
					# straight run and means something is STANDING there — a mast, a crate, a
					# stair — which is furniture, not a corner defect, and is reported but not
					# failed. Confusing the two is how a probe starts crying wolf and gets
					# ignored, which is how this bug survived six sessions in the first place.
					if i2 >= 3 and i2 <= 5:
						corner_blocked += 1
					else:
						obstructed_straights += 1
			if corner_stations < 5:
				continue           # not a walkable corner — a designed gap, skip it
			sampled += 1
			var frac: float = float(corner_blocked) / float(corner_stations)
			if corner_blocked > 0:
				_say("      %-10s corner (%6.1f,%6.1f): %d/%d stations blocked" % [
					name2, cs2[0], cs2[1], corner_blocked, corner_stations])
			if frac > worst_deck_block:
				worst_deck_block = frac
				worst_deck_where = "%s (%.1f, %.1f) %d/%d stations blocked" % [
					name2, cs2[0], cs2[1], corner_blocked, corner_stations]
	_check("deck rail corners sampled (anti-vacuity)", sampled >= 6, "sampled=%d" % sampled)
	_say("      %d station(s) blocked out on the straights — furniture, not corner geometry" % obstructed_straights)
	_check("a capsule can walk round every deck rail corner", worst_deck_block <= 0.0,
		("clear at every station" if worst_deck_block <= 0.0 else "worst: " + worst_deck_where))

func _seat_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.2, 0), p + Vector3(0, -4.8, 0))
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
