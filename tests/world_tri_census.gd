extends Node3D
## WHAT THE WORLD ACTUALLY SUBMITS, PER ASSET, COUNTED OFF THE LIVE TREE.
##
## The s31 mistake was costing meshes by FILE SIZE. tools/survey_tris.py fixes half of that
## by counting triangles off the glTF index accessors — but a raw per-asset count still
## cannot rank anything, because a 200 k mesh spawned ONCE is cheaper than a 30 k mesh
## spawned four hundred times. The number that decides a decimation is
##
##     triangles-in-the-mesh  x  instances-the-world-spawns
##
## and only the running world knows the second factor. So this walks the whole Main tree,
## groups every MeshInstance3D and MultiMeshInstance3D by its mesh RESOURCE PATH, and
## reports the product. Props and fauna together, not just fish.
##
## WHY RESOURCE PATH AND NOT NODE NAME. Godot shares one imported ArrayMesh between every
## instance of an asset, so the resource path is the asset identity and the instance count
## falls out of how many nodes point at it. Procedural meshes (the rig's own CSG bakes,
## ArrayMeshes built in code) have an empty resource path; they are bucketed under a
## `<procedural>` label by their node's script owner so they are visible but not confused
## with imported assets.
##
## HEADLESS IS HONEST FOR THIS. Triangle counts come off ArrayMesh.surface_get_arrays()
## index buffers, which is resource data — unlike MultiMesh instance TRANSFORMS, which read
## back as identity under --headless (see KNOWN_ISSUES). This probe never reads a transform;
## it only counts `instance_count`, which is a plain integer and is correct headless.
##
## WHAT THIS DOES NOT MEASURE. Everything here is SPAWNED geometry, not SUBMITTED geometry.
## Frustum culling, the reef's 55 m visibility_range_end and underwater_world's topside cull
## all cut what actually reaches the GPU in a given frame. Spawned is the right number for a
## decimation decision (it bounds the worst case and it is what VRAM holds); it is the wrong
## number to compare against a frame's primitive counter.
##
##     godot --headless --path . res://tests/WorldTriCensus.tscn

var _main: Node = null

## Pods and schools are spawned lazily by shift; give the world enough frames to stock.
const SETTLE_FRAMES: int = 240


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = load("res://scenes/Main.tscn").instantiate()
	if _main.get_script() == null:
		print("[census] Main.tscn instantiated WITHOUT its script — aborting")
		get_tree().quit(1)
		return
	add_child(_main)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	_report()
	get_tree().quit(0)


## Triangles in one mesh resource, summed over its surfaces, off the index buffer.
## Falls back to vertex_count / 3 for a surface that ships unindexed.
static func _mesh_tris(m: Mesh) -> int:
	var n: int = 0
	for s in m.get_surface_count():
		if m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = m.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
			else PackedInt32Array()
		if idx.size() > 0:
			n += idx.size() / 3
		else:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if \
				arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			n += verts.size() / 3
	return n


var _tri_cache: Dictionary = {}

func _tris_of(m: Mesh) -> int:
	if m == null:
		return 0
	var key: String = m.resource_path if m.resource_path != "" else str(m.get_instance_id())
	if _tri_cache.has(key):
		return int(_tri_cache[key])
	var n: int = _mesh_tris(m)
	_tri_cache[key] = n
	return n


func _report() -> void:
	# asset path -> [tris_per_instance, instances]
	var by_asset: Dictionary = {}

	for n_v in _main.find_children("*", "", true, false):
		var node: Node = n_v
		var mesh: Mesh = null
		var count: int = 1
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is MultiMeshInstance3D:
			var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			mesh = mm.mesh
			count = mm.instance_count
		else:
			continue
		if mesh == null or count <= 0:
			continue
		var tris: int = _tris_of(mesh)
		if tris <= 0:
			continue
		var path: String = mesh.resource_path
		if path == "":
			path = "<procedural> %s" % node.name
		if not by_asset.has(path):
			by_asset[path] = [tris, 0]
		(by_asset[path] as Array)[1] = int((by_asset[path] as Array)[1]) + count

	var rows: Array = []
	var total: int = 0
	for p_v in by_asset:
		var r: Array = by_asset[p_v]
		var world: int = int(r[0]) * int(r[1])
		total += world
		rows.append([String(p_v), int(r[0]), int(r[1]), world])
	rows.sort_custom(func(a, b): return int(a[3]) > int(b[3]))

	print("\n=== WORLD TRIANGLE CENSUS (spawned, not submitted) ===")
	print("  %-9s x %-6s = %-10s  %s" % ["TRIS", "INST", "WORLD", "ASSET"])
	for r_v in rows:
		var r2: Array = r_v
		print("  %-9d x %-6d = %-10d  %s"
			% [int(r2[1]), int(r2[2]), int(r2[3]), String(r2[0])])
	print("  TOTAL %.2f M triangles across %d distinct meshes"
		% [float(total) / 1.0e6, rows.size()])
