extends Node
## Why is the cat's volume test refusing open floor? Prints what the sphere actually hits.
func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(6.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	var world: World3D = cat.get_world_3d()
	print("cat at ", cat.global_position, "  pose=", cat.get("_pose"))
	var r: float = float(cat.call("_body_r"))
	var L: float = float(cat.call("_body_len"))
	print("body radius=%.3f  body len=%.3f" % [r, L])
	var sphere := SphereShape3D.new()
	sphere.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = cat.call("_walk_skip")
	for h in [r + 0.04, r + 0.10, r + 0.20, 0.30]:
		q.transform = Transform3D(Basis.IDENTITY, cat.global_position + Vector3(0, h, 0))
		var hits: Array = world.direct_space_state.intersect_shape(q, 4)
		var names: Array = []
		for x in hits:
			var c = x.get("collider")
			names.append(str(c.name) if c != null else "?")
		print("  sphere at +%.3f : %d hits %s" % [h, hits.size(), str(names)])
	get_tree().quit()
