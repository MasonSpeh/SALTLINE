extends Node
## Counts props left hovering above the surface beneath them. Boots the real Main,
## waits for the streamed dressing + one physics tick (SurfaceSnap corrects on its first
## physics frame), then raycasts down from every visual prop and reports the gap.
##
## Run: godot --headless --path . res://tests/PlacementProbe.tscn
## A prop is FLOATING if its mesh bottom sits more than TOL above whatever is below it.
## Wall-mounted dressing is exempt: anything whose nearest surface is far below is a
## poster/clock/socket, not a dropped mug — the same rule SurfaceSnap uses.

const TOL: float = 0.06        ## allowed gap before we call it floating
const WALL_EXEMPT: float = 0.55  ## must match InteriorProps.SNAP_MAX_DROP

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	# The dressing streams a few props per frame; give it time, plus physics ticks so
	# SurfaceSnap has run and rigid props have settled.
	await get_tree().create_timer(6.0).timeout
	for i in range(10):
		await get_tree().physics_frame

	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var floating: Array = []
	var checked: int = 0
	for n in _mesh_owners(main):
		var node: Node3D = n
		var aabb: AABB = _world_aabb(node)
		if aabb.size == Vector3.ZERO:
			continue
		# Ignore huge things (structure, decks, the ocean) and anything underwater.
		if aabb.size.x > 4.0 or aabb.size.z > 4.0 or aabb.size.y > 3.0:
			continue
		if aabb.position.y < 0.5:
			continue
		checked += 1
		var bottom: Vector3 = aabb.get_center()
		bottom.y = aabb.position.y
		var from: Vector3 = bottom + Vector3(0, 0.05, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -(WALL_EXEMPT + 0.2), 0))
		q.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue   # nothing within reach below → wall-mounted or hanging; exempt
		var gap: float = bottom.y - (hit.position as Vector3).y
		if gap > TOL:
			floating.append("%s  gap=%.3f  at %s" % [node.name, gap, str(bottom).pad_decimals(2)])

	print("--- placement probe ---")
	print("props checked: ", checked)
	print("FLOATING: ", floating.size())
	for f in floating.slice(0, 25):
		print("   ", f)
	get_tree().quit(0)

func _mesh_owners(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n)
	return out

func _world_aabb(mi: Node3D) -> AABB:
	var m := mi as MeshInstance3D
	if m == null or m.mesh == null:
		return AABB()
	return m.global_transform * m.get_aabb()
