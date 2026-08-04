extends Node
## Where on the topside deck is there OPEN sky and clear floor? Probe, do not guess.
func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(10.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	var ds := (main as Node3D).get_world_3d().direct_space_state
	var best: Array = []
	for xi in range(-30, 32, 3):
		for zi in range(-24, 22, 3):
			var x := float(xi)
			var z := float(zi)
			# floor at y18?
			var down := PhysicsRayQueryParameters3D.create(
				Vector3(x, 19.2, z), Vector3(x, 17.0, z))
			down.collision_mask = 1
			var f: Dictionary = ds.intersect_ray(down)
			if f.is_empty():
				continue
			var fy: float = (f["position"] as Vector3).y
			if absf(fy - 18.0) > 0.35:
				continue
			# open sky above? (start above the floor so we are not inside CSG)
			var up := PhysicsRayQueryParameters3D.create(
				Vector3(x, fy + 0.5, z), Vector3(x, fy + 12.0, z))
			up.collision_mask = 1
			var roofed: bool = not ds.intersect_ray(up).is_empty()
			# clearance: how far can we walk in 4 compass directions at cat height
			var clear: float = 99.0
			for d in [Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,0,1), Vector3(0,0,-1)]:
				var sq := PhysicsRayQueryParameters3D.create(
					Vector3(x, fy + 0.30, z), Vector3(x, fy + 0.30, z) + d * 8.0)
				sq.collision_mask = 1
				var h: Dictionary = ds.intersect_ray(sq)
				var dist: float = 8.0 if h.is_empty() else Vector3(x, fy+0.30, z).distance_to(h["position"])
				clear = minf(clear, dist)
			if clear >= 3.0:
				best.append([clear, x, z, fy, roofed])
	best.sort_custom(func(a, b): return a[0] > b[0])
	for b in best.slice(0, 14):
		print("[deck] clear=%.1f m at (%.0f, %.2f, %.0f) roofed=%s" % [b[0], b[1], b[3], b[2], str(b[4])])
	get_tree().quit()
