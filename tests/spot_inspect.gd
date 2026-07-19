extends Node
## SPOT INSPECT — list every drawn mesh whose world AABB overlaps a small box, with its
## material identity (albedo colour, whether it has a texture at all) and the builder that
## made it. Answers "what IS that untextured cube in the photograph" without guessing.

const SUPPORT := preload("res://scripts/world/support_index.gd")

## Boxes to inspect: name, centre, half-extent.
const SPOTS := [
	["bench_toolbox", Vector3(24.5, 2.6, -19.5), Vector3(3.0, 1.6, 3.0)],
	["respawn_props", Vector3(20.0, 2.6, -9.6), Vector3(3.0, 1.6, 3.5)],
]

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(14.0).timeout
	for i in range(30):
		await get_tree().physics_frame

	var index = SUPPORT.new()
	index.build(main)
	for s in SPOTS:
		var c: Vector3 = s[1]
		var h: Vector3 = s[2]
		var box := AABB(c - h, h * 2.0)
		print("=== SPOT %s  box %s .. %s ===" % [s[0], _v(box.position), _v(box.position + box.size)])
		var rows: Array = []
		var stack: Array = [main]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for ch in n.get_children():
				stack.append(ch)
			var vi := n as VisualInstance3D
			if vi == null or not vi.is_inside_tree():
				continue
			var la: AABB = vi.get_aabb()
			if la.size == Vector3.ZERO:
				continue
			var a: AABB = vi.global_transform * la
			if not box.intersects(a) or a.size.x > 12.0:
				continue
			var top: float = index.support_top(a, vi, 0.0)
			rows.append("%-22s size %5.2fx%5.2fx%5.2f ctr %s base %5.2f gap %s\n      mat: %s\n      owner: %s" % [
				vi.name, a.size.x, a.size.y, a.size.z, _v(a.get_center()), a.position.y,
				("NONE" if top == -INF else "%.3f" % (a.position.y - top)),
				_mat_desc(vi), _owner(vi)])
		rows.sort()
		print("  ", rows.size(), " meshes")
		for r in rows:
			print("   ", r)
	get_tree().quit(0)

func _mat_desc(vi: VisualInstance3D) -> String:
	var m: Material = null
	var gi := vi as GeometryInstance3D
	if gi != null and gi.material_override != null:
		m = gi.material_override
	elif vi is MeshInstance3D and (vi as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = vi
		m = mi.get_active_material(0)
	if m == null:
		return "(none)"
	var sm := m as StandardMaterial3D
	if sm == null:
		return m.get_class()
	return "Std albedo=%s tex=%s rough=%.2f" % [
		sm.albedo_color.to_html(false),
		("YES" if sm.albedo_texture != null else "NONE"), sm.roughness]

func _owner(n: Node) -> String:
	var cur: Node = n
	while cur != null:
		var s: Script = cur.get_script() as Script
		if s != null:
			return "%s <%s>" % [s.resource_path.get_file(), cur.name]
		cur = cur.get_parent()
	return "?"

func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
