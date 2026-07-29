extends Node3D
## PERCH / HAUL-OUT SURVEY. Boots the real Main and asks the physics world, not the
## source, three questions about a candidate spot for an animal:
##
##   1. what is actually UNDER it (down-ray) and how far the authored y floats,
##   2. is the body volume there CLEAR (a small sphere at standing height),
##   3. how much open air is around it (8 horizontal rays) — the "blank wall" test the
##      bunkhouse gull failed.
##
## Ground truth for the CorvidGull perch and HarborSeal haul-out moves. Headless is fine:
## this reads colliders, it takes no pictures.
##   godot --headless --path . res://tests/FaunaSpotProbe.tscn

var _skip: Array[RID] = []

func _ready() -> void:
	add_child(load("res://scenes/Main.tscn").instantiate())
	# The rig is CSG: nothing has a collider until physics has stepped a few times.
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
	await get_tree().physics_frame

	print("\n=== CURRENT AUTHORED SPOTS ===")
	for spec in [["corvid0 wetdeck", Vector3(24.9, 2.75, -16.0)],
			["corvid1 bunkhouse", Vector3(-8.6, 18.75, 6.4)],
			["corvid2 east", Vector3(27.6, 18.75, 4.0)],
			["seal HAUL_SPOT", Vector3(9.0, 2.25, -21.2)]]:
		_report(String(spec[0]), spec[1])

	print("\n=== CORVID 0 — tide-line drums on the wet deck (cyl tops should read y 3.0) ===")
	for d in [Vector3(20.6, 4.2, -20.4), Vector3(22.1, 4.2, -21.2), Vector3(27.2, 4.2, -21.3),
			Vector3(28.6, 4.2, -20.2), Vector3(26.0, 4.2, -21.4),
			Vector3(-6.0, 20.2, -16.0), Vector3(-1.6, 20.2, -16.0), Vector3(2.8, 20.2, -16.0)]:
		_report("drum %6.1f,%6.1f" % [d.x, d.z], d)

	print("\n=== CORVID 1 — bunkhouse roof (slab top 21.325; nest -20,12; vents -24,8 / -14,14 / -20,14) ===")
	for z in [5.0, 7.0, 11.0, 16.0]:
		for x in [-26.0, -22.0, -16.4, -12.0, -9.5]:
			_report("roof %5.1f,%5.1f" % [x, z], Vector3(x, 22.5, z))

	print("\n=== CORVID 2 — topside SE, inboard of the east rail (x29.8, z2..12.6) ===")
	for z in [3.0, 5.5, 7.0, 11.0]:
		for x in [28.8, 29.0, 29.2, 29.4]:
			_report("top %5.1f,%5.1f" % [x, z], Vector3(x, 19.5, z))

	print("\n=== SEAL — south pontoon open foundation (slab top y 0.95, x-28..28 z-16..-8) ===")
	print("--- ladder down from the wet deck lands at (7.8, 0.95, -12) ---")
	for z in [-15.2, -14.6, -13.5, -12.0, -10.0]:
		for x in [-2.0, 0.0, 2.0, 4.6, 6.0]:
			_report("pont %6.1f,%6.1f" % [x, z], Vector3(x, 2.4, z))

	get_tree().quit()

## One spot: floor under it, body clearance in it, open air around it.
func _report(tag: String, p: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.2, 0), p - Vector3(0, 4.5, 0))
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = false
	q.exclude = _skip
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		print("%-22s  NO FLOOR within %.1f..%.1f" % [tag, p.y - 4.5, p.y + 1.2])
		return
	var fy: float = hit["position"].y
	var what: String = _name_of(hit["collider"])
	# Body volume: a 0.3 m ball at knee height on the found floor. A gull is ~0.4 m tall,
	# a hauled seal ~0.5 m at the shoulder, so this is the widest thing either occupies.
	var sp := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.3
	sp.shape = ball
	sp.transform = Transform3D(Basis(), Vector3(p.x, fy + 0.32, p.z))
	sp.collision_mask = 0xFFFFFFFF
	sp.collide_with_areas = false
	sp.exclude = _skip
	var inside: Array = space.intersect_shape(sp, 4)
	var block: String = ""
	for c in inside:
		block += _name_of(c["collider"]) + " "
	# Open air: 8 rays at head height. `near` is the closest wall in any direction.
	var near: float = 6.0
	var near_dir: String = "-"
	for i in range(8):
		var a: float = TAU * i / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var hq := PhysicsRayQueryParameters3D.create(Vector3(p.x, fy + 0.35, p.z),
			Vector3(p.x, fy + 0.35, p.z) + d * 6.0)
		hq.collision_mask = 0xFFFFFFFF
		hq.collide_with_areas = false
		hq.exclude = _skip
		var hh: Dictionary = space.intersect_ray(hq)
		if not hh.is_empty():
			var dist: float = Vector3(p.x, fy + 0.35, p.z).distance_to(hh["position"])
			if dist < near:
				near = dist
				near_dir = "%d deg %s" % [int(rad_to_deg(a)), _name_of(hh["collider"])]
	print("%-22s floor y=%7.3f (%s)  float=%+7.1fmm  clear=%s  nearest_wall=%.2fm %s"
		% [tag, fy, what, (p.y - fy) * 1000.0,
			"YES" if block == "" else ("NO: " + block), near, near_dir])

func _name_of(c: Object) -> String:
	if c == null:
		return "<null>"
	var n: Node = c as Node
	if n == null:
		return str(c)
	var parts: Array[String] = [n.name]
	var p: Node = n.get_parent()
	for i in range(2):
		if p == null:
			break
		parts.push_front(p.name)
		p = p.get_parent()
	return "/".join(parts)
