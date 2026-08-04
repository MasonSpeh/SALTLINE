extends Node
## Where IS the free corridor around the cat's HOME? Raycast the real world and print it,
## plus what the cat's own _step_clear says at each z — the two must agree or the cat's
## clearance test is broken.
func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(8.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	var world: World3D = (main as Node3D).get_world_3d()
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	print("[aisle] cat home = ", cat.global_position)
	# walls along z at several x stations, probed at cat body height
	for x in [-24.0, -22.0, -20.0, -18.0, -16.5]:
		var line: String = "[aisle] x=%5.1f  " % x
		for z0 in [4.5, 18.0]:
			pass
		# sweep z, mark solid/free at y 18.25
		var marks: String = ""
		for zi in range(40, 145, 5):
			var z: float = float(zi) / 10.0
			var q := PhysicsPointQueryParameters3D.new()
			# point query lies in CSG (documented) — use a short ray pair instead
			var up := PhysicsRayQueryParameters3D.create(
				Vector3(x, 19.4, z), Vector3(x, 18.05, z))
			up.collision_mask = 1
			var hit: Dictionary = world.direct_space_state.intersect_ray(up)
			var top: float = (hit["position"] as Vector3).y if not hit.is_empty() else -1.0
			marks += "#" if top > 18.4 else "."
		print(line + marks + "   (z 4.0 -> 14.0, # = solid above deck)")
	# and the cat's own verdict along its home lane
	for z in [10.6, 10.9, 11.1, 11.3, 11.5, 11.7, 12.0, 12.4]:
		var at := Vector3(-20.0, 18.0, z)
		var ok: bool = bool(cat.call("_step_clear", at, Vector3(1, 0, 0)))
		print("[aisle] _step_clear at z=%.1f -> %s" % [z, str(ok)])
	get_tree().quit()
