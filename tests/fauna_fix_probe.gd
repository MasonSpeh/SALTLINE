extends Node3D
## PERCH + HAUL-OUT GROUND TRUTH, second pass. FaunaSpotProbe answered "what is under this
## point"; this one answers the two questions that decided the actual placements:
##
##   1. does the COLLIDER under a point agree with the VISIBLE surface there? The topside
##      perimeter rails do not — rig_builder draws the top bar at y18.61 and fences it with
##      a collision slab whose top is y19.225 — so a bird that honestly down-probes onto a
##      rail lands 615 mm above the steel you can see. That is why none of the three perches
##      sits on a rail: a probe cannot be trusted there, and the whole point of this batch
##      is to stop hand-typing heights.
##   2. what does the SEAL's body actually intersect where it hauls out? A point probe says
##      "floor found, clear" for a 1.8 m animal that is elbow-deep in a pipe run, because a
##      0.3 m ball at the centre misses everything the flanks hit.
##
##   godot --headless --path . res://tests/FaunaFixProbe.tscn

var _skip: Array[RID] = []
var _vis: Array = []   ## [AABB] of every visual in the scene, world space

func _ready() -> void:
	add_child(load("res://scenes/Main.tscn").instantiate())
	for i in range(12):
		await get_tree().physics_frame
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = Vector3(180, 60, 180)
		player.set_physics_process(false)
	for n in get_tree().root.find_children("*", "CollisionObject3D", true, false):
		var host: Node = n
		while host != null:
			var s: Script = host.get_script()
			if s != null and String(s.resource_path).ends_with("bloom_fauna.gd"):
				_skip.append((n as CollisionObject3D).get_rid())
				break
			host = host.get_parent()
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = n
		if not vi.is_visible_in_tree():
			continue
		var a: AABB = vi.get_aabb()
		if a.size.length_squared() < 0.0001:
			continue
		_vis.append(vi.global_transform * a)
	print("[probe] %d visible volumes, %d fauna colliders excluded" % [_vis.size(), _skip.size()])
	await get_tree().physics_frame

	print("\n=== PERCH 0 — wet-deck tide-line drums (rig_builder: _cyl r0.45 h1.0 at WET_Y+0.5) ===")
	for d in [Vector3(20.6, 3.6, -20.4), Vector3(22.1, 3.6, -21.2), Vector3(26.0, 3.6, -21.4),
			Vector3(27.2, 3.6, -21.3), Vector3(28.6, 3.6, -20.2)]:
		_report("drum %5.1f,%6.1f" % [d.x, d.z], d)

	print("\n=== PERCH 1 — bunkhouse roof, thief's own roof (nest -20,12) ===")
	for z in [8.0, 10.0, 12.0, 14.0]:
		for x in [-22.0, -19.0, -16.0, -13.0, -10.0, -8.6]:
			_report("roof %5.1f,%5.1f" % [x, z], Vector3(x, 22.0, z))

	print("\n=== PERCH 2 — topside drums (z-16, x-6..5, _cyl r0.45 top y19) + SE plate ===")
	for d in [Vector3(-6.0, 19.6, -16.0), Vector3(-3.8, 19.6, -16.0), Vector3(-1.6, 19.6, -16.0),
			Vector3(0.6, 19.6, -16.0), Vector3(2.8, 19.6, -16.0), Vector3(5.0, 19.6, -16.0)]:
		_report("tdrum %5.1f,%6.1f" % [d.x, d.z], d)
	print("--- the east rail line itself, to DOCUMENT the collider/visual disagreement ---")
	for z in [4.0, 8.0]:
		for x in [29.6, 29.8, 30.0]:
			_report("rail %5.1f,%5.1f" % [x, z], Vector3(x, 19.6, z))

	print("\n=== PERCH 2 — every RAISED surface in the topside SE quadrant ===")
	print("--- grid probe down from y21.6; anything not the 18.0 plate is a candidate ---")
	_scan(16.0, 30.0, -8.0, 19.0, 0.5, 21.6, 18.0, 21.4)

	print("\n=== FINAL CANDIDATES — and does a MASK-1 probe (what the species uses) agree? ===")
	for spec in [["P0 drum  26.0,-21.4", Vector3(26.0, 3.6, -21.4)],
			["P0 drum  27.2,-21.3", Vector3(27.2, 3.6, -21.3)],
			["P1 roof  -8.6, 12.0", Vector3(-8.6, 22.0, 12.0)],
			["P1 roof  -8.6, 14.0", Vector3(-8.6, 22.0, 14.0)],
			["P2 recrf 27.6,  9.0", Vector3(27.6, 22.0, 9.0)],
			["P2 recrf 26.4, 10.0", Vector3(26.4, 22.0, 10.0)],
			["P2 recrf 24.0,  9.0", Vector3(24.0, 22.0, 9.0)]]:
		_report(String(spec[0]), spec[1])
		_mask_compare(String(spec[0]), spec[1])
	print("--- topside SE, on the plating, clear of the accommodation-stack overhang ---")
	for spec in [["P2 plate 27.6,  4.0", Vector3(27.6, 18.6, 4.0)],
			["P2 plate 27.6,  1.0", Vector3(27.6, 18.6, 1.0)],
			["P2 plate 27.6, -3.0", Vector3(27.6, 18.6, -3.0)],
			["P2 plate 20.0,-17.0", Vector3(20.0, 18.6, -17.0)],
			["P2 plate 26.0,-17.0", Vector3(26.0, 18.6, -17.0)],
			["P2 plate 28.5,-12.0", Vector3(28.5, 18.6, -12.0)]]:
		_report(String(spec[0]), spec[1])
	print("--- every RAISED surface on the OPEN topside deck (SE + south lane) ---")
	_scan(14.0, 30.0, -20.0, 4.0, 0.5, 21.0, 18.0, 20.9)

	# The wet-deck spot the seal was moved OFF. Kept as the before-reading: a point probe
	# calls it clear and a body-sized box does not.
	print("\n=== SEAL — the OLD wet-deck haul spot, body-sized overlap test ===")
	_body("old 9,2.25,-21.2", Vector3(9.0, 2.25, -21.2), Vector3(0.9, 0.55, 1.9))

	print("\n=== SEAL — south pontoon open foundation (slab top 0.95, x-28..28 z-16..-8) ===")
	print("--- Pontoon Ladder lands (7.8,0.95,-12); lamp snails ride x-17.2/-10/17.2 at z-12 ---")
	for z in [-14.5, -13.0, -11.5, -10.0]:
		for x in [-6.0, -3.0, 0.0, 3.0, 5.5]:
			_body("pont %5.1f,%6.1f" % [x, z], Vector3(x, 1.4, z), Vector3(0.9, 0.55, 1.9))

	print("\n=== SEAL — the PATROL formula walked, old radius vs new ===")
	print("--- pos = (cos(0.16t)*0.7r, -0.15+max(sin(0.6t),0)*0.5, centre + sin(0.16t)*r) ---")
	_patrol("old  r=20+6sin", 20.0, 6.0, -34.0)
	_patrol("new  r=12+4sin", 12.0, 4.0, -34.0)

	get_tree().quit()

## Walk the seal's own patrol expression and body-test every sample. A loop that is clear at
## its authored radius is not clear at r_max, and r_max is where it swam into the pontoon.
func _patrol(tag: String, r0: float, r1: float, centre: float) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var sp := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.7, 1.9)        # the swimming animal, roughly
	sp.shape = box
	sp.collision_mask = 0xFFFFFFFF
	sp.collide_with_areas = false
	sp.exclude = _skip
	var bad: int = 0
	var north: float = -1e9
	var worst: String = ""
	for i in range(4000):
		var t: float = i * 0.31
		var ang: float = t * 0.16
		var r: float = r0 + sin(t * 0.1) * r1
		var p := Vector3(cos(ang) * r * 0.7, -0.15 + maxf(sin(t * 0.6), 0.0) * 0.5,
			centre + sin(ang) * r)
		north = maxf(north, p.z)
		sp.transform = Transform3D(Basis(), p)
		var h: Array = space.intersect_shape(sp, 2)
		if not h.is_empty():
			bad += 1
			if worst == "":
				worst = "%s at (%.1f,%.2f,%.1f)" % [_name_of(h[0]["collider"]), p.x, p.y, p.z]
	print("  %-16s northernmost z=%7.2f   samples inside geometry: %4d/4000   %s"
		% [tag, north, bad, worst])

## The species' own snap uses collision_mask 1 (world geometry). gull_shot.gd warns that a
## mask-1 probe can miss the plating and quietly report the hull box eight metres down as
## "the deck", so every candidate is checked both ways before a bird is asked to trust one.
func _mask_compare(tag: String, p: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var out: Array[String] = []
	for mask in [1, 0xFFFFFFFF]:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.4, 0), p - Vector3(0, 4.5, 0))
		q.collision_mask = mask
		q.collide_with_areas = false
		q.exclude = _skip
		var hit: Dictionary = space.intersect_ray(q)
		out.append("%.3f" % hit["position"].y if not hit.is_empty() else "MISS")
	print("%-20s   mask1=%s  all=%s  %s" % [tag, out[0], out[1],
		"AGREE" if out[0] == out[1] else "*** DISAGREE ***"])

## Sweep a grid and print the cells whose floor is ABOVE the base plate — every crate, drum,
## bollard and roof a bird could actually stand on, found by asking physics instead of by
## reading the builder. Cells are merged into runs so the output stays readable.
func _scan(x0: float, x1: float, z0: float, z1: float, step: float,
		from_y: float, base: float, ceiling: float) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var found: Dictionary = {}   # "name|height" -> [count, min x, max x, min z, max z]
	var x: float = x0
	while x <= x1:
		var z: float = z0
		while z <= z1:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, base - 0.5, z))
			q.collision_mask = 0xFFFFFFFF
			q.collide_with_areas = false
			q.exclude = _skip
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				var fy: float = hit["position"].y
				if fy > base + 0.15 and fy < ceiling:
					var key: String = "%s @ %.3f" % [_name_of(hit["collider"]), fy]
					if not found.has(key):
						found[key] = [0, x, x, z, z]
					var e: Array = found[key]
					e[0] += 1
					e[1] = minf(e[1], x); e[2] = maxf(e[2], x)
					e[3] = minf(e[3], z); e[4] = maxf(e[4], z)
			z += step
		x += step
	for k in found:
		var e: Array = found[k]
		print("  %-46s cells=%3d  x[%.1f..%.1f] z[%.1f..%.1f]" % [k, e[0], e[1], e[2], e[3], e[4]])

## Point survey: floor under it, the highest VISIBLE surface under it, and open air around.
func _report(tag: String, p: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.4, 0), p - Vector3(0, 4.5, 0))
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = false
	q.exclude = _skip
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		print("%-20s  NO FLOOR" % tag)
		return
	var fy: float = hit["position"].y
	var seen: float = _visual_top(p.x, p.z, p.y + 0.4)
	var near: float = _open_air(Vector3(p.x, fy + 0.35, p.z))
	# SKY. A perch under the accommodation stack is a perch in a room: the rec-room roof
	# reads as a fine flat surface right up until you notice deck B's floor 0.28 m above it.
	var uq := PhysicsRayQueryParameters3D.create(Vector3(p.x, fy + 0.45, p.z),
		Vector3(p.x, fy + 40.0, p.z))
	uq.collision_mask = 0xFFFFFFFF
	uq.collide_with_areas = false
	uq.exclude = _skip
	var up: Dictionary = space.intersect_ray(uq)
	var head: String = "OPEN SKY" if up.is_empty() \
		else "roof %.2fm up (%s)" % [up["position"].y - fy, _name_of(up["collider"])]
	print("%-20s floor=%7.3f (%s)  visual_top=%7.3f  gap=%+6.1fmm  open=%.2fm  %s"
		% [tag, fy, _name_of(hit["collider"]), seen, (fy - seen) * 1000.0, near, head])

## Body survey: put a box the size of the animal on the found floor and list what it hits.
func _body(tag: String, p: Vector3, half: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.2, 0), p - Vector3(0, 5.0, 0))
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = false
	q.exclude = _skip
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		print("%-22s  NO FLOOR" % tag)
		return
	var fy: float = hit["position"].y
	var sp := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	sp.shape = box
	# Seated ON the floor: the body's own half-height above it, which is where a hauled-out
	# animal's flanks are — the height a centre-point probe never tests.
	sp.transform = Transform3D(Basis(), Vector3(p.x, fy + half.y, p.z))
	sp.collision_mask = 0xFFFFFFFF
	sp.collide_with_areas = false
	sp.exclude = _skip
	var inside: Array = space.intersect_shape(sp, 8)
	var block: String = ""
	for c in inside:
		block += _name_of(c["collider"]) + " "
	print("%-22s floor=%7.3f (%s)  open=%.2fm  body=%s"
		% [tag, fy, _name_of(hit["collider"]), _open_air(Vector3(p.x, fy + half.y, p.z)),
			"CLEAR" if block == "" else ("HITS " + block)])

## Highest visible surface at this XZ at or below `ceiling` — what the player's eye reads
## as "the thing it is standing on", which is not always what the collider says.
func _visual_top(x: float, z: float, ceiling: float) -> float:
	var best: float = -1e9
	for a in _vis:
		var box: AABB = a
		if x < box.position.x - 0.02 or x > box.end.x + 0.02:
			continue
		if z < box.position.z - 0.02 or z > box.end.z + 0.02:
			continue
		if box.end.y <= ceiling and box.end.y > best:
			best = box.end.y
	return best

func _open_air(from: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var near: float = 6.0
	for i in range(8):
		var a: float = TAU * i / 8.0
		var hq := PhysicsRayQueryParameters3D.create(from, from + Vector3(cos(a), 0, sin(a)) * 6.0)
		hq.collision_mask = 0xFFFFFFFF
		hq.collide_with_areas = false
		hq.exclude = _skip
		var hh: Dictionary = space.intersect_ray(hq)
		if not hh.is_empty():
			near = minf(near, from.distance_to(hh["position"]))
	return near

func _name_of(c: Object) -> String:
	var n: Node = c as Node
	if n == null:
		return "<null>"
	var parts: Array[String] = [n.name]
	var p: Node = n.get_parent()
	for i in range(2):
		if p == null:
			break
		parts.push_front(p.name)
		p = p.get_parent()
	return "/".join(parts)
