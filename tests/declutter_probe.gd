extends Node3D
## HOW CLEAR IS THE WALK OFF THE SPAWN DECK, ACTUALLY?
##
## Owner, s34: clear the main walkway of uninteractable scenery. The s33 attempt at this
## failed review for hand-typing coordinates, so this measures the route instead of
## describing it, and it measures the two things that are separately wrong with it:
##
##   1. HOW WIDE IS THE LANE. A capsule the size of the player (r 0.37) is stepped across
##      the walkway at each station and the widest CONTIGUOUS free span is reported. This
##      is what "the drum is in the doorway" means as a number.
##   2. WHAT DO YOU WALK THROUGH. Most of the clutter here has NO COLLIDER — the tire
##      fender and the bollard chain are bare MeshInstance3Ds, and the mooring links at
##      the caisson foot are too. A physics query cannot see any of them, so a probe built
##      only on shape casts would report the lane perfectly clear while the player walks
##      through a chain at shin height. So the visible MESHES are tested against the walk
##      volume as well, by AABB, which is the whole point: scenery you pass through is
##      exactly the complaint.
##
## Fauna is excluded from the physics side (every creature carries a solid FaunaTouch
## sphere on the default layer — the s20 trap that reported a caisson had moved 606 mm)
## and skipped on the mesh side, since a gull standing in the lane is not clutter.
##
##     godot --headless --path . res://tests/DeclutterProbe.tscn

const WET_Y: float = 2.0
const PLAYER_RADIUS: float = 0.37
const STAND_HEIGHT: float = 1.8
## How much room a walk needs beyond the capsule itself before it stops feeling like
## squeezing past something. Half a capsule width each side.
const COMFORT: float = 0.35

## The route the owner is describing: out of the SPHL hatch, over the gangplank, north
## across the wet deck, then the turn at the SE caisson foot. Stations are given as a
## centre and the axis to sweep across — the lane runs north-south to begin with, so the
## free span is measured in x, and turns east-west at the caisson foot.
## `scan` is whether to hunt loose SCENERY at this station as well as measuring the width.
## It is false at the hatch itself: door_frame.gd legitimately builds jambs, a coaming, a
## window and its bars, a handle and two hinges into that opening, and a scan that reports
## the door as clutter in the doorway is a scan nobody will read twice. The width sweep
## still runs there, because the width of that opening is exactly what matters.
## [name, centre, sweep_axis, scan]
const STATIONS := [
	["sphl_gap", Vector3(20.0, WET_Y, -22.90), Vector3.RIGHT, false],
	["gangplank", Vector3(20.0, WET_Y, -22.05), Vector3.RIGHT, true],
	["chain_line", Vector3(20.0, WET_Y, -21.70), Vector3.RIGHT, true],
	["plank_north", Vector3(20.0, WET_Y, -21.30), Vector3.RIGHT, true],
	["drum_row", Vector3(20.0, WET_Y, -20.40), Vector3.RIGHT, true],
	["deck_open", Vector3(20.5, WET_Y, -19.00), Vector3.RIGHT, true],
	["caisson_turn", Vector3(22.0, WET_Y, -15.85), Vector3.RIGHT, true],
]

## How far either side of the centre the sweep looks, and at what step.
const SWEEP_HALF: float = 3.2
const SWEEP_STEP: float = 0.05

var _main: Node3D
var _fail: int = 0
var _done: bool = false

func _ok(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		_fail += 1

func _ready() -> void:
	await _run()
	if not _done:
		print("[declutter] the probe body did not reach its end — PARTIAL run")
		_fail += 1
	print("\n[declutter] FAILURES: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	if _main.get_script() == null:
		print("[declutter] Main.tscn came back WITHOUT its script — aborting")
		_fail += 1
		_done = true
		return
	add_child(_main)
	# CSG colliders do not exist on the frame the node enters the tree, and the dressing
	# streams in over ~1 s (interior_props queues its placements). Everything here is a
	# measurement against that geometry, so wait for it.
	for i in range(90):
		await get_tree().physics_frame
	_sweep()
	_walkthroughs()
	_candidates()
	_done = true

# ------------------------------------------------------------------ 1. the lane width

func _sweep() -> void:
	print("\n=== how wide is the walk? (player capsule r %.2f, so %.2f m is the minimum) ==="
		% [PLAYER_RADIUS, PLAYER_RADIUS * 2.0])
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	# The DOOR is excluded as well as the fauna. The question at the hatch is how wide the
	# OPENING is — a shut door reads as 0.00 m of lane, which is true and useless, and the
	# drum this is really about sits on the deck side of it either way.
	var skip: Array = _fauna_rids() + _door_rids()
	var cap := CapsuleShape3D.new()
	cap.radius = PLAYER_RADIUS
	cap.height = STAND_HEIGHT
	var worst: float = 1e9
	var worst_name: String = ""
	for st in STATIONS:
		var name: String = st[0]
		var centre: Vector3 = st[1]
		var axis: Vector3 = st[2]
		# Step the capsule across the lane and record which offsets are free.
		var free: Array = []
		var n: int = int(SWEEP_HALF * 2.0 / SWEEP_STEP)
		for i in range(n + 1):
			var off: float = -SWEEP_HALF + float(i) * SWEEP_STEP
			# The capsule's ORIGIN is its centre, so it has to be lifted half its height
			# off the plate or every query reports the deck itself.
			var at: Vector3 = centre + axis * off + Vector3(0, STAND_HEIGHT * 0.5 + 0.02, 0)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, at)
			q.collision_mask = 1
			q.collide_with_areas = false
			q.exclude = skip
			free.append(space.intersect_shape(q, 1).is_empty())
		# THE RUN THAT CONTAINS THE ROUTE LINE, not the widest run anywhere in range — the
		# first cut of this took the widest and duly reported the drum station as 3.00 m
		# clear, because there is open deck 1.70 m WEST of the walk. That is a true fact
		# about the deck and not an answer about the lane: a player coming off the plank
		# walks the line, and what matters is how much room there is where they are.
		var centre_i: int = int(SWEEP_HALF / SWEEP_STEP)
		var width: float = 0.0
		var mid: float = 0.0
		if free[centre_i]:
			var lo: int = centre_i
			var hi: int = centre_i
			while lo > 0 and free[lo - 1]:
				lo -= 1
			while hi < free.size() - 1 and free[hi + 1]:
				hi += 1
			# THE SWEEP FINDS THE SPAN OF VALID CAPSULE CENTRES, WHICH IS NOT THE WIDTH.
			# A 1.60 m doorway admits a 0.74 m capsule over 0.86 m of centre positions, so
			# the raw run under-reports every opening by exactly one capsule diameter — the
			# first version of this asserted the centre-span against a width and duly failed
			# a doorway that is built 1.60 m wide. Add the diameter back to get the clear
			# width a person would measure with a tape.
			width = float(hi - lo + 1) * SWEEP_STEP + PLAYER_RADIUS * 2.0
			mid = -SWEEP_HALF + (float(lo) + float(hi - lo + 1) * 0.5) * SWEEP_STEP
		print("  %-14s clear width ON the route %.2f m, centred %+.2f m off the line"
			% [name, width, mid])
		if width < worst:
			worst = width
			worst_name = name
	_ok(worst >= PLAYER_RADIUS * 2.0 + COMFORT,
		"the narrowest point of the spawn walk is %.2f m at `%s` (need %.2f)"
			% [worst, worst_name, PLAYER_RADIUS * 2.0 + COMFORT])

# ------------------------------------------------------- 2. what you walk THROUGH

## What geometry is standing in the walk volume — SEARCHED BY TRIANGLE, NOT BY NODE.
##
## The first cut of this walked MeshInstance3D nodes and reported "nothing", which was
## wrong in the most familiar way in this repo: `rig_batcher` WELDS the dressing into
## `MergedDressing` chunks, so by the time a probe runs, the tire fender, the bollard chain
## and the mooring links do not exist as nodes at all — they are triangles inside a handful
## of ArrayMesh chunks up to 13 m across, which a size filter then discards as "too big to
## be a prop". docs/AGENT_TRAPS.md has this twice already, and a per-node walk is how the
## blank yellow block on the spawn deck survived two hunts.
##
## So every mesh whose AABB reaches the lane is opened up and its FACES are tested: a
## triangle whose centroid falls inside the walk corridor is geometry the player's head or
## shins pass through. Reported as a triangle count and a bounding box per station, which
## also tells you WHERE in the lane it is.
func _walkthroughs() -> void:
	print("\n=== geometry standing in the walk corridor (welded dressing included) ===")
	var lane: Array = []
	var lane_name: Array = []
	for st in STATIONS:
		if not bool(st[3]):
			continue
		var centre: Vector3 = st[1]
		# Ankle to chest, the width of a comfortable walk. Starts 40 mm off the plate so the
		# deck itself is not the answer.
		lane.append(AABB(centre + Vector3(-0.8, 0.04, -0.5), Vector3(1.6, 1.5, 1.0)))
		lane_name.append(String(st[0]))
	var fauna: Dictionary = {}
	for n in _fauna_nodes():
		fauna[n] = true
	var counts: Array = []
	var boxes: Array = []
	for i in range(lane.size()):
		counts.append(0)
		boxes.append(AABB())
	var seen: Array = []
	for i in range(lane.size()):
		seen.append({})
	for n in _main.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if _under_any(mi, fauna):
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		var touches: bool = false
		for l in lane:
			if box.intersects(l):
				touches = true
				break
		if not touches:
			continue
		var xf: Transform3D = mi.global_transform
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var t: int = 0
		while t + 2 < faces.size():
			var c: Vector3 = xf * ((faces[t] + faces[t + 1] + faces[t + 2]) / 3.0)
			t += 3
			for i in range(lane.size()):
				if not (lane[i] as AABB).has_point(c):
					continue
				counts[i] = int(counts[i]) + 1
				boxes[i] = AABB(c, Vector3.ZERO) if int(counts[i]) == 1 \
					else (boxes[i] as AABB).expand(c)
				(seen[i] as Dictionary)[mi.name] = int((seen[i] as Dictionary).get(mi.name, 0)) + 1
				break
	var total: int = 0
	for i in range(lane.size()):
		var n_tri: int = int(counts[i])
		total += n_tri
		if n_tri == 0:
			print("  %-14s clear" % lane_name[i])
			continue
		var b: AABB = boxes[i]
		print("  %-14s %5d triangles, spanning %s .. %s"
			% [lane_name[i], n_tri, str(b.position.snappedf(0.01)),
				str((b.position + b.size).snappedf(0.01))])
		for k in (seen[i] as Dictionary):
			print("                   in %s (%d)" % [k, (seen[i] as Dictionary)[k]])
	_ok(total == 0,
		"nothing stands in the spawn walk corridor (%d triangles across %d stations)"
			% [total, lane.size()])

## Is there a collider where this mesh is? A prop you can walk THROUGH is the complaint;
## one that stops you is at least honest, and shows up in the lane sweep instead.
func _has_collider_near(box: AABB) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = box.size * 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, box.get_center())
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _fauna_rids()
	return not space.intersect_shape(q, 1).is_empty()

# ------------------------------------------------------------------------ plumbing

func _under_any(n: Node, set_: Dictionary) -> bool:
	var p: Node = n
	while p != null:
		if set_.has(p):
			return true
		p = p.get_parent()
	return false

func _fauna_nodes() -> Array:
	var out: Array = []
	for g in ["snail_pyramid", "snail_lamp", "ship_cat", "deck_gull", "corvid_gull"]:
		out.append_array(get_tree().get_nodes_in_group(g))
	for n in _main.find_children("*", "Node3D", true, false):
		var s: Script = n.get_script()
		if s != null and s.resource_path.get_file() in ["bloom_fauna.gd", "crab.gd",
				"leg_reef.gd", "mussel_beds.gd", "ship_cat.gd"]:
			out.append(n)
	return out

func _fauna_rids() -> Array:
	var out: Array = []
	for n in _fauna_nodes():
		for c in (n as Node).find_children("*", "CollisionObject3D", true, false):
			out.append((c as CollisionObject3D).get_rid())
	return out

## Every door body, so the width sweep measures the opening rather than the leaf.
func _door_rids() -> Array:
	var out: Array = []
	for n in _main.find_children("*", "Node3D", true, false):
		var sc: Script = n.get_script()
		if sc == null or sc.resource_path.get_file() != "door.gd":
			continue
		for c in n.find_children("*", "CollisionObject3D", true, false):
			out.append((c as CollisionObject3D).get_rid())
		if n is CollisionObject3D:
			out.append((n as CollisionObject3D).get_rid())
	return out

## ---------------------------------------------------------------- 3. relocation candidates
##
## Where CAN a moved prop go? The s33 declutter plan was rejected for hand-typing an answer
## to this and dropping a relocated chain heap on top of a live DeckGull, so candidates are
## checked against the real world instead of reasoned about: what collides there, how close
## the nearest authored fauna home is, and whether it is back in the walk corridor.
const FAUNA_HOMES := [
	["DeckGull home", Vector3(24.0, 2.0, -15.5)],
	["CorvidGull perch 0", Vector3(26.0, 3.4, -21.4)],
]
## [label, centre, radius of the thing being placed]
const CANDIDATES := [
	["heap W of turn", Vector3(19.6, WET_Y + 0.10, -15.90), 0.97],
	["heap W low", Vector3(19.0, WET_Y + 0.10, -16.40), 0.97],
	["heap far E", Vector3(26.4, WET_Y + 0.10, -15.60), 0.97],
	["heap SE apron", Vector3(23.2, WET_Y + 0.10, -19.30), 0.97],
]

func _candidates() -> void:
	print("\n=== relocation candidates ===")
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var skip: Array = _fauna_rids()
	for c in CANDIDATES:
		var label: String = c[0]
		var at: Vector3 = c[1]
		var r: float = c[2]
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = 0.9
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sh
		q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.45, 0))
		q.collision_mask = 1
		q.collide_with_areas = false
		q.exclude = skip
		var hits: Array = space.intersect_shape(q, 8)
		var names: Array = []
		for h in hits:
			names.append(str(h.get("collider")))
		# distance to the nearest AUTHORED fauna home, edge to point
		var near_home: float = 1e9
		var near_name: String = ""
		for fh in FAUNA_HOMES:
			var d: float = Vector2(at.x, at.z).distance_to(Vector2((fh[1] as Vector3).x, (fh[1] as Vector3).z)) - r
			if d < near_home:
				near_home = d
				near_name = String(fh[0])
		# and is it back in the walk?
		var in_walk: bool = false
		for st in STATIONS:
			if Vector2(at.x, at.z).distance_to(Vector2((st[1] as Vector3).x, (st[1] as Vector3).z)) < r + 0.8:
				in_walk = true
		print("  %-16s %d colliders %-34s | nearest fauna home %+.2f m (%s) | in walk: %s"
			% [label, hits.size(), str(names).substr(0, 34), near_home, near_name, str(in_walk)])
