extends Node3D
## Headless rig capture for the sonar-mcp scanner.
## Builds the LIVE rig exactly as the game does (RigBuilder + all its child
## dressing systems), waits for interior_props' settle passes to finish, then
## exports the whole tree — every named node — to GLB.
##
## Run:  godot --headless --path . res://tools/RigCapture.tscn
## (or just tools/export_rig.sh, which also re-scans it into sonar)

const OUT_PATH := "res://rig_capture.glb"

func _ready() -> void:
	# THE FIELD IS OPT-IN, and deliberately so. `--field` captures SALTLINE-0 *and* rigs 2-4
	# under one root, which is what the sonar oracle needs once the new platforms exist; the
	# default stays rig 1 alone so an existing scan and every coordinate in RIG_ATLAS.md
	# reproduce byte for byte. RigBuilder sits at identity under the wrapper either way, so
	# rig 1's coordinates are unchanged in both modes.
	#   godot --headless --path . res://tools/RigCapture.tscn -- --field
	var with_field: bool = false
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a == "--field":
			with_field = true
	print("[capture] building RigBuilder…", "  (+ THE FIELD)" if with_field else "")
	var root := Node3D.new()
	add_child(root)
	var rig := RigBuilder.new()
	root.add_child(rig)
	if with_field:
		root.add_child(preload("res://scripts/world/rig_field.gd").new())
	# interior_props settles props across frames; wait until the node count
	# holds still for three samples (hard cap 20 s so CI can't hang).
	var last := -1
	var stable := 0
	var waited := 0.0
	while stable < 3 and waited < 20.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		var count := _count(root)
		print("[capture] t=%.1fs nodes=%d" % [waited, count])
		stable = stable + 1 if count == last else 0
		last = count
	print("[capture] settled at %d nodes" % last)
	# Slim the export for the scanner: any imported sculpt above the triangle
	# threshold becomes a box of its local AABB (same node name, same pose) —
	# floor plans read clean, and multi-MB prop textures never embed. All
	# authored primitives (decks, walls, pipes, girders) keep exact geometry.
	var boxed := 0
	for mi: MeshInstance3D in _mesh_instances(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		if mesh.get_faces().size() / 3 > 2000:
			var aabb := mesh.get_aabb()
			var box := BoxMesh.new()
			box.size = aabb.size.max(Vector3(0.01, 0.01, 0.01))
			mi.mesh = box
			for si in range(mi.get_surface_override_material_count()):
				mi.set_surface_override_material(si, null)
			mi.transform *= Transform3D(Basis.IDENTITY, aabb.get_center())
			# Tag so the sonar ingest can manifest it by name ("what item, where").
			# Include the parent name — prop nodes are often generically named
			# while their parent carries the meaning ("Bunkhouse/bed_frame").
			var label := mi.name
			var par := mi.get_parent()
			if par != null and par != root:
				label = par.name + "." + label
			mi.name = ("PROP__" + label).validate_node_name()
			boxed += 1
	print("[capture] boxed %d high-poly props — exporting…" % boxed)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err != OK:
		push_error("[capture] append_from_scene failed: error %d" % err)
		get_tree().quit(1)
		return
	err = doc.write_to_filesystem(state, OUT_PATH)
	if err != OK:
		push_error("[capture] write_to_filesystem failed: error %d" % err)
		get_tree().quit(1)
		return
	print("[capture] wrote %s" % ProjectSettings.globalize_path(OUT_PATH))
	get_tree().quit(0)

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

func _mesh_instances(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for ch in n.get_children():
		out.append_array(_mesh_instances(ch))
	return out
