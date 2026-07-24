extends Node
func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	for i in range(6):
		await get_tree().physics_frame
	var fails := 0
	var rays := 0
	var giants := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.get("_span") != null and n.get("_band_y") != null:
			rays += 1
		elif n.get("_band_y") != null and n.get("slug") != null:
			giants += 1
	print("PROBE rays=%d giants=%d" % [rays, giants])
	fails += _chk("open-water rays spawn (>=3)", rays >= 3)
	fails += _chk("deep giants present (>=7)", giants >= 7)
	var spool := Vector3.INF
	stack = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.get("item_id") == "cable_spool":
			spool = (n as Node3D).global_position
	print("PROBE spool=%s" % spool)
	fails += _chk("spool is in the pump room", spool.x > 10 and spool.x < 18 and spool.z > -14 and spool.z < -6 and spool.y < 3)
	var shaft := 0
	for l in get_tree().get_nodes_in_group("interior_mains"):
		var p: Vector3 = (l as Node3D).global_position
		if p.x > 21 and p.x < 31 and p.z > -6 and p.z < 2 and p.y > 3 and p.y < 37:
			shaft += 1
	print("PROBE stairwell_lights=%d" % shaft)
	fails += _chk("stairwell has mains lights (>=8)", shaft >= 8)
	PowerGrid.power_circuit("topside_floodlights")
	await get_tree().process_frame
	var lit := 0
	for l in get_tree().get_nodes_in_group("interior_mains"):
		if (l as Node3D).visible:
			lit += 1
	print("PROBE lit_after_breaker=%d" % lit)
	fails += _chk("central lights turn on with the breaker (>=15)", lit >= 15)
	print("FAILURES: %d" % fails)
	get_tree().quit(fails)

func _chk(label: String, cond: bool) -> int:
	print(("PASS  " if cond else "FAIL  ") + label)
	return 0 if cond else 1
