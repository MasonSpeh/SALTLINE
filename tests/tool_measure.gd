extends Node
## Measure the two fishing tools' geometry off the BUILT node — meshes, triangles, the AABB
## in model space, and where the "hand_tip" marker sits inside it. No world, no rendering, so
## it is safe headless and is the cheap gate before any windowed pass.
##
##   godot --headless --path . res://tests/ToolMeasure.tscn

func _ready() -> void:
	for id in ["fishing_rod", "deep_rig_pole"]:
		var n: Node3D = ItemVisual.build(id)
		var meshes: int = 0
		var tris: int = 0
		var box := AABB()
		var got: bool = false
		var stack: Array[Node] = [n]
		while not stack.is_empty():
			var x: Node = stack.pop_back()
			for c in x.get_children():
				stack.append(c)
			var mi := x as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			meshes += 1
			tris += mi.mesh.get_faces().size() / 3
			var b: AABB = _rel(mi, n) * mi.mesh.get_aabb()
			box = b if not got else box.merge(b)
			got = true
		var marker: Node = n.find_child("hand_tip", true, false)
		var tip := Vector3.INF
		if marker is Node3D:
			tip = _rel(marker as Node3D, n) * Vector3.ZERO
		print("%-14s meshes=%3d tris=%6d" % [id, meshes, tris])
		print("               aabb pos=%s size=%s centre=%s"
			% [str(box.position.snappedf(0.001)), str(box.size.snappedf(0.001)),
				str(box.get_center().snappedf(0.001))])
		print("               longest=%.3f  hand_tip(root-space)=%s"
			% [maxf(box.size.x, maxf(box.size.y, box.size.z)),
				("MISSING" if tip == Vector3.INF else str(tip.snappedf(0.001)))])
		n.queue_free()
	get_tree().quit()

func _rel(node: Node3D, base: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != base:
		t = cur.transform * t
		cur = cur.get_parent() as Node3D
	return t
