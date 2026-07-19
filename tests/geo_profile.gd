extends Node3D
## GEOMETRY PROFILE — where do the ~6,800 draw calls actually come from?
##
## Builds the real world, waits for the dressing to stream in, then walks the tree and
## groups every drawable by (owning script, node class, mesh class, rough size, material).
## Prints the top offenders so batching effort goes where the calls actually are.

var _main: Node3D

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(30.0).timeout

	var by_script: Dictionary = {}      # script tail -> count
	var unbatched: Dictionary = {}      # script tail -> count still costing a draw call
	var by_kind: Dictionary = {}        # "script | class | mesh | size | mat" -> count
	var by_class: Dictionary = {}
	var total_mesh: int = 0
	var total_csg: int = 0
	var total_mm: int = 0
	var mm_instances: int = 0

	var stack: Array = [[_main, "(root)"]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var n: Node = pair[0]
		var owner_tag: String = pair[1]
		var s: Script = n.get_script() as Script
		if s != null:
			# Inner classes have no resource_path; name them by their owning node instead,
			# or "(no script)" collapses a thousand different owners into one useless row.
			owner_tag = s.resource_path.get_file()
			if owner_tag == "":
				owner_tag = "inner:%s/%s" % [n.get_class(), n.name]
		for c in n.get_children():
			stack.append([c, owner_tag])

		var cls: String = n.get_class()
		if not (n is MeshInstance3D or n is CSGShape3D or n is MultiMeshInstance3D):
			continue
		if n is MeshInstance3D:
			total_mesh += 1
		elif n is MultiMeshInstance3D:
			total_mm += 1
			var mmi := n as MultiMeshInstance3D
			if mmi.multimesh != null:
				mm_instances += mmi.multimesh.instance_count
		else:
			total_csg += 1

		by_script[owner_tag] = int(by_script.get(owner_tag, 0)) + 1
		by_class[cls] = int(by_class.get(cls, 0)) + 1
		# mesh_batcher.gd clears the layer mask of everything it welds, so a non-zero mask
		# is exactly "this node still costs a draw call".
		if (n as VisualInstance3D).layers != 0 and not n.is_in_group("render_batch"):
			unbatched[owner_tag] = int(unbatched.get(owner_tag, 0)) + 1

		var mesh_tag: String = "-"
		var size_tag: String = "-"
		var surf: int = 1
		var vi := n as VisualInstance3D
		var a: AABB = vi.get_aabb()
		var scl: Vector3 = (n as Node3D).global_transform.basis.get_scale()
		var big: float = maxf(maxf(a.size.x * scl.x, a.size.y * scl.y), a.size.z * scl.z)
		size_tag = "%.2f" % (roundf(big * 20.0) / 20.0)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				mesh_tag = mi.mesh.get_class()
				surf = mi.mesh.get_surface_count()
				if mi.mesh is BoxMesh:
					mesh_tag = "Box%s" % _v3((mi.mesh as BoxMesh).size)
				elif mi.mesh is CylinderMesh:
					var cy := mi.mesh as CylinderMesh
					mesh_tag = "Cyl(%.2f/%.2f/%.2f)" % [cy.top_radius, cy.bottom_radius, cy.height]
				elif mi.mesh is SphereMesh:
					var sp := mi.mesh as SphereMesh
					mesh_tag = "Sph(%.2f/%.2f)" % [sp.radius, sp.height]
				elif mi.mesh is QuadMesh or mi.mesh is PlaneMesh:
					mesh_tag = "%s%s" % [mi.mesh.get_class(), _v2(mi.mesh.get("size"))]
				elif mi.mesh is TorusMesh:
					mesh_tag = "Torus"
		elif n is CSGShape3D:
			mesh_tag = cls
			if n is CSGBox3D:
				mesh_tag = "CSGBox%s" % _v3((n as CSGBox3D).size)
			elif n is CSGCylinder3D:
				var cc := n as CSGCylinder3D
				mesh_tag = "CSGCyl(%.2f/%.2f)" % [cc.radius, cc.height]
			elif n is CSGSphere3D:
				mesh_tag = "CSGSph(%.2f)" % (n as CSGSphere3D).radius

		var mat_tag: String = _mat_of(n)
		var key: String = "%-26s %-22s %-24s sz=%-6s surf=%d mat=%s" % [
			owner_tag, cls, mesh_tag, size_tag, surf, mat_tag]
		by_kind[key] = int(by_kind.get(key, 0)) + 1

	print("=== GEOMETRY PROFILE ===")
	print("MeshInstance3D %d   CSGShape3D %d   MultiMeshInstance3D %d (%d instances)" % [
		total_mesh, total_csg, total_mm, mm_instances])

	print("--- by node class ---")
	for k in _sorted(by_class):
		print("%6d  %s" % [by_class[k], k])

	print("--- by owning script (top 30) ---")
	var sk: Array = _sorted(by_script)
	for i in range(mini(30, sk.size())):
		print("%6d  %s" % [by_script[sk[i]], sk[i]])

	print("--- STILL DRAWING after batching, by owning script (top 25) ---")
	var un: Array = _sorted(unbatched)
	for i in range(mini(25, un.size())):
		var owner_name: String = un[i]
		print("%6d unbatched / %6d total   %s" % [
			unbatched[owner_name], by_script.get(owner_name, 0), owner_name])

	print("--- repeated identical primitives (count >= 12, top 90) ---")
	var kk: Array = _sorted(by_kind)
	var shown: int = 0
	for k in kk:
		if int(by_kind[k]) < 12:
			break
		print("%6d  %s" % [by_kind[k], k])
		shown += 1
		if shown >= 90:
			break
	get_tree().quit()

func _v3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]

func _v2(v) -> String:
	if v is Vector2:
		return "(%.2f,%.2f)" % [v.x, v.y]
	return "-"

func _mat_of(n: Node) -> String:
	var m: Material = null
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		m = mi.get_surface_override_material(0) if mi.get_surface_override_material_count() > 0 else null
		if m == null and mi.mesh != null:
			m = mi.mesh.surface_get_material(0)
		if m == null:
			m = mi.material_override
	elif n is CSGShape3D:
		m = n.get("material") as Material   # CSGCombiner3D has no material property
	if m == null:
		return "none"
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		return "std#%d(%s)" % [sm.get_instance_id() % 100000, sm.albedo_color.to_html(false)]
	return m.get_class()

func _sorted(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	return keys
