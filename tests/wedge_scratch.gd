extends Node
## SCRATCH — what exactly refuses the cat's every step at (-21.9, 18, 12)?
##
## The CatProbe COME test wedges there deterministically: direct, all eight fan
## candidates AND the backward step refused every frame for eight seconds. On an open
## bunkhouse floor that should be geometrically impossible, so something is answering the
## volume query that is not a wall. Teleport the cat to the wedge, run its own gates by
## hand, and print WHAT each probe actually hits.

func _ready() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 9000 or waited < 180:
		await get_tree().physics_frame
		waited += 1
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector3(-12.0, 18.1, 10.0)
	cat.set_process(false)
	cat.global_position = Vector3(-21.9, 18.0, 12.0)
	cat.call("_reseat")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world: World3D = cat.get_world_3d()
	var r: float = float(cat.call("_body_r"))
	var blen: float = float(cat.call("_body_len"))
	print("[wedge] cat at %s  body_r %.3f  body_len %.3f  pose %s"
		% [str(cat.global_position), r, blen, str(cat.get("_pose"))])
	var dir: Vector3 = (player.global_position - cat.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	for ang in [0.0, 0.5, -0.5, 0.9, -0.9, 1.45, -1.45, 2.0, -2.0, PI]:
		var alt: Vector3 = dir.rotated(Vector3.UP, float(ang))
		var awant: Vector3 = cat.global_position + alt * 0.073
		# The deck ray, exactly as _walk_toward casts it.
		var q := PhysicsRayQueryParameters3D.create(
			awant + Vector3(0, 0.75, 0), awant + Vector3(0, 0.75, 0) - Vector3(0, 1.85, 0))
		q.collision_mask = 1
		q.collide_with_areas = false
		q.exclude = cat.call("_walk_skip")
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		var ground_s: String = "NO DECK"
		var clear_s: String = "-"
		if not hit.is_empty():
			var g: Vector3 = hit["position"]
			ground_s = "ground y %.2f (%s)" % [g.y, (hit["collider"] as Node).name]
			# The body volume test, and WHO answers it.
			var ok: bool = bool(cat.call("_step_clear", Vector3(awant.x, g.y, awant.z), alt))
			clear_s = "clear" if ok else "BLOCKED"
			if not ok:
				var sphere := SphereShape3D.new()
				sphere.radius = r
				var sq := PhysicsShapeQueryParameters3D.new()
				sq.shape = sphere
				sq.collision_mask = 1
				sq.collide_with_areas = false
				sq.exclude = cat.call("_walk_skip")
				var lead: float = blen * 0.5 - r
				for probe_i in range(2):
					var at: Vector3 = Vector3(awant.x, g.y, awant.z) \
						+ (Vector3.ZERO if probe_i == 0 else alt * maxf(lead, 0.0)) \
						+ Vector3(0, r + 0.04, 0)
					sq.transform = Transform3D(Basis.IDENTITY, at)
					for shp in world.direct_space_state.intersect_shape(sq, 4):
						var col: Node = shp["collider"]
						clear_s += " | %s hits %s (%s)" % [
							"centre" if probe_i == 0 else "nose", col.name,
							col.get_parent().name if col.get_parent() != null else "?"]
		print("[wedge] ang %+.2f -> %s, %s" % [ang, ground_s, clear_s])
	get_tree().quit()
