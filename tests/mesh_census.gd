extends Node
## MESH CENSUS — how many drawn MeshInstance3D each builder script is responsible for,
## and how many of those are the SAME (mesh, material) pair and could be one MultiMesh.
## Draw calls in gl_compatibility are ~1 per surface, so this list IS the frame budget.

const OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/87d5de70-f27c-48d3-bab9-cb1e9a8f822d/scratchpad"

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(12.0).timeout
	for i in range(10):
		await get_tree().physics_frame

	var by_owner: Dictionary = {}
	var total: int = 0
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		total += mi.mesh.get_surface_count()
		var o: String = _owner_script(mi)
		by_owner[o] = int(by_owner.get(o, 0)) + mi.mesh.get_surface_count()
	var rows: Array = []
	for k in by_owner:
		rows.append([by_owner[k], k])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("=== MESH SURFACES BY BUILDER (total ", total, ") ===")
	for r in rows:
		print("  %6d  %s" % [r[0], r[1]])
	get_tree().quit(0)

func _owner_script(n: Node) -> String:
	var cur: Node = n
	while cur != null:
		var s: Script = cur.get_script() as Script
		if s != null:
			return s.resource_path.get_file()
		cur = cur.get_parent()
	return "(none)"
