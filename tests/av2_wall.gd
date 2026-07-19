extends Node
## AV2 pass 4 — item 6's one untested sub-feature: does a WALL_MOUNT kit really
## snap to a bulkhead and orient its local +Z out of the wall?
## Run: godot --headless --path . res://tests/AV2Wall.tscn

var _main: Node3D
var _player: Node3D

func _ready() -> void:
	await _run()
	get_tree().quit(0)

func _p(t: String, m: String) -> void:
	print("%-9s %s" % [t, m])

func _all(root: Node, type) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if is_instance_of(n, type):
			out.append(n)
	return out

func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	_player = get_tree().get_first_node_in_group("player")
	_player.set_physics_process(false)
	_player.set_process(false)
	var bm: Node = null
	for n in _all(_main, Node):
		if n is BuildMode:
			bm = n
			break
	if bm == null:
		_p("[DEFECT]", "no BuildMode")
		return
	for i in range(PlayerState.HOTBAR_SIZE):
		PlayerState.hotbar[i] = null
	PlayerState.inventory.clear()
	PlayerState.add_item("shelf_kit")
	bm.call("toggle")
	bm.call("select_kit", "shelf_kit")
	var cam: Camera3D = _player.get("camera") as Camera3D

	# Find a real vertical bulkhead by sweeping horizontal rays from inside the rig.
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var stand := Vector3(20.0, 19.6, 11.0)   # rec room, topside
	var found := false
	for deg in range(0, 360, 15):
		var a: float = deg_to_rad(float(deg))
		var dir := Vector3(cos(a), 0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(stand + Vector3(0, 0.6, 0),
			stand + Vector3(0, 0.6, 0) + dir * 6.0)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.has("normal") and absf((hit["normal"] as Vector3).y) < 0.4:
			# aim the camera at that wall
			_player.global_position = stand
			cam.global_position = stand + Vector3(0, 0.6, 0)
			cam.look_at(hit["position"], Vector3.UP)
			for i in 15:
				await get_tree().physics_frame
			if bool(bm.get("_wall_mode")) and bool(bm.get("_valid")):
				found = true
				var b: Basis = bm.get("_place_basis")
				var n: Vector3 = hit["normal"]
				var dot: float = b.z.normalized().dot(n.normalized())
				_p("[OK]", "shelf_kit enters WALL mode on a real bulkhead (normal=%.2f,%.2f,%.2f)"
					% [n.x, n.y, n.z])
				if dot > 0.95:
					_p("[OK]", "wall basis aligns local +Z to the wall normal (dot=%.3f)" % dot)
				else:
					_p("[DEFECT]", "wall basis misaligned: local +Z . normal = %.3f" % dot)
				if absf(b.y.normalized().dot(Vector3.UP)) > 0.95:
					_p("[OK]", "shelf stays upright on the wall (local +Y is world up)")
				else:
					_p("[DEFECT]", "shelf is rolled on the wall")
				var pos: Vector3 = bm.get("_place_pos")
				if absf(pos.y - snappedf(pos.y, bm.GRID)) < 0.001:
					_p("[OK]", "wall placement snaps height to the %.2fm grid" % bm.GRID)
				else:
					_p("[DEFECT]", "wall height not snapped: y=%.4f" % pos.y)
				# and it must really build there
				var before: int = get_tree().get_nodes_in_group("built_structures").size()
				var ok: bool = bool(bm.call("place"))
				var after: int = get_tree().get_nodes_in_group("built_structures").size()
				if ok and after > before:
					_p("[OK]", "shelf actually builds on the bulkhead")
				else:
					_p("[DEFECT]", "shelf would not place on the wall")
				break
	if not found:
		_p("[DEFECT]", "never found a bulkhead that put shelf_kit into wall mode")
	# A floor kit must NOT go into wall mode.
	PlayerState.add_item("chair_kit")
	bm.call("select_kit", "chair_kit")
	for i in 15:
		await get_tree().physics_frame
	if bool(bm.get("_wall_mode")):
		_p("[DEFECT]", "chair_kit (not in WALL_MOUNT) entered wall mode")
	else:
		_p("[OK]", "a floor kit aimed at the same wall stays a floor kit")
	bm.call("exit")
