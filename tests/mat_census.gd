extends Node
## Headless census of the materials underwater_world's cull toggles. Counting resources needs
## no drawing, so this one is safe under --headless (the MultiMesh *transform* trap does not
## apply — that is instance data in the RenderingServer; a mesh's materials are plain resources).
##
##   godot --headless --path . tests/MatCensus.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var uw: Node = _find_script(main, "underwater_world.gd")
	if uw == null:
		print("[census] underwater_world NOT FOUND")
		get_tree().quit()
		return
	var uniq: Dictionary = {}
	var by_kind: Dictionary = {}
	var surfaces: int = 0
	var stack: Array = [uw]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		for m in _materials_of(n):
			surfaces += 1
			var mat := m as Material
			if mat == null:
				continue
			uniq[mat.get_instance_id()] = mat
			var k: String = mat.get_class()
			var sm := mat as ShaderMaterial
			if sm != null and sm.shader != null:
				k = "Shader:" + String(sm.shader.resource_path).get_file()
			by_kind[k] = int(by_kind.get(k, 0)) + 1
	print("[census] material SURFACES in the subtree: %d" % surfaces)
	print("[census] UNIQUE material resources:        %d" % uniq.size())
	var keys: Array = by_kind.keys()
	keys.sort()
	for k in keys:
		print("           %-34s %d surfaces" % [k, int(by_kind[k])])
	get_tree().quit()

func _materials_of(n: Node) -> Array:
	var out: Array = []
	var gi := n as GeometryInstance3D
	if gi != null and gi.material_override != null:
		out.append(gi.material_override)
	var mi := n as MeshInstance3D
	if mi != null:
		for i in range(mi.get_surface_override_material_count()):
			var so: Material = mi.get_surface_override_material(i)
			if so != null:
				out.append(so)
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				var s: Material = mi.mesh.surface_get_material(i)
				if s != null:
					out.append(s)
	var mm := n as MultiMeshInstance3D
	if mm != null and mm.multimesh != null and mm.multimesh.mesh != null:
		for i in range(mm.multimesh.mesh.get_surface_count()):
			var s2: Material = mm.multimesh.mesh.surface_get_material(i)
			if s2 != null:
				out.append(s2)
	return out

func _find_script(root: Node, frag: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var sc: Script = n.get_script()
		if sc != null and String(sc.resource_path).ends_with(frag):
			return n
	return null
