extends Node
## STATIC MESH BATCHER — the second half of the frame budget (render_budget.gd is the first).
##
## gl_compatibility draws one call per mesh surface. render_budget already dropped tiny
## meshes out of the shadow cascades and gave dressing a distance range, but every one of
## the rig's ~6,700 dressing primitives is still its own draw call whenever it is on screen,
## which is what held the deck and sea-level vantages under 60 fps after the shadow work.
##
## This pass BAKES all the static, co-material dressing into one mesh per material. A wall
## of rusted-steel bolts, pipes, gauges, girders, cable trays and weld seams — hundreds of
## separate MeshInstance3D and non-colliding CSG nodes that share MatLib.rust_steel() — all
## become a single ArrayMesh with the geometry pre-transformed into world space. MatLib's
## structural surfaces are WORLD-SPACE triplanar (mat_lib.gd), so a baked vertex textures
## exactly as it did loose: no UVs, no seams, no visible change. ~6,700 dressing draw calls
## collapse to a dozen. (seabed.gd bakes its floor the same way; this generalises it.)
##
## THAT CLAIM WAS AUDITED IN s35 AND HOLDS — recorded because the weld is the obvious
## suspect for an owner report of "wall textures moving as the player moves", and the next
## agent will suspect it too. Three things had to be true and all three are:
##   1. `_bake` writes `xf * sv[vi]`, i.e. GLOBAL vertices, and hangs the chunk off a plain
##      Node3D under rig_root — and main.gd:48 adds RigBuilder with no transform, so
##      rig_root is identity. A baked vertex therefore holds the world position it had.
##   2. Godot 4.7's BaseMaterial3D emits, verbatim,
##        uv1_triplanar_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * uv1_scale + uv1_offset;
##      for world triplanar. There is no camera term in it.
##   3. The gl_compatibility scene shader's model_matrix is the raw instance transform; the
##      camera-relative rebase only exists under USE_DOUBLE_PRECISION, which this build is
##      not. (Both read out of the shipping binary, not from memory.)
## So a welded wall cannot swim, and neither can a loose one. What DOES move on a wall here
## is the caustic band — see materials/caustics.gdshader.
##
## KNOWN GAP, deliberately left: mesh_batcher.gd (dead code — main.gd only ever builds this
## one) refuses to weld OBJECT-space triplanar because baking rotates the projection axes
## out from under it. This pass has no such guard, so MatLib.rope_mat and every _surface /
## _fine fallback gets welded with its mapping quietly rebased. Not fixed: placement_probe.gd
## records that the room floor overlays (lino, rubber, tile, medical) are a large share of
## the ~2,950 primitives this collapses, so the guard would cost real interior draw calls to
## correct a shift that is invisible on isotropic noise. Worth doing only for rope_mat, whose
## strands are directional, and only with a draw-call measurement in hand.
##
## WHAT IT LEAVES ALONE (so nothing gameplay- or physics-related shifts):
##   - Interactables (Interactable = StaticBody3D subclass), rigid/movable props, and their
##     subtrees — they move, hide, get carried, or are queried by id.
##   - Colliding CSG (walls, floors, decks) and every StaticBody collider — collision is
##     untouched, so the player, the stairs and build-mode raycasts see the same solids.
##   - Transparent / billboard / shader materials (glass, stains, motes, the sea) — baking
##     opaque-only keeps blend order correct.
##   - Anything still streaming or animated (fauna, flares, player-built structures).
##
## TIMING. It waits for interior_props.settle_done: SupportIndex rests every loose item on
## the VISUAL mesh beneath it, so the merge must not remove those surfaces until the last
## prop has landed. Runs ONCE, then frees itself.

## Dressing this size or under never casts a directional shadow once merged — a pipe or a
## bolt's shadow is shadow-map noise. Bigger merged members (girders) also stop casting:
## the rig's shadow silhouette is carried by the caissons, decks and walls (structural CSG,
## left untouched), and dropping the dressing out of the 2 shadow splits is most of the win.
const MERGE_SHADOWS: bool = false   ## merged dressing casts no directional shadow

var rig_root: Node3D                ## set by main.gd before add_child

var _merged_surfaces: int = 0
var _consumed: int = 0

func _ready() -> void:
	name = "RigBatcher"
	if rig_root == null:
		queue_free()
		return
	# Wait for the prop settle pass — SupportIndex reads the meshes we are about to merge.
	var ip: Node = _find_script(rig_root, "interior_props.gd")
	if ip != null:
		if not bool(ip.get("settle_complete")):
			await ip.settle_done
	else:
		await get_tree().create_timer(4.0).timeout   # fallback: no interior_props to gate on
	# One extra idle frame so any last deferred add is in the tree.
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_instance_valid(rig_root):
		return
	_run()
	print("[batcher] merged %d dressing primitives into %d material meshes" % [
		_consumed, _merged_surfaces])
	_shadow_audit()
	queue_free()

# ------------------------------------------------------------------ the pass

## Sentinel key: every flat single-colour dressing part (MatLib.flat) is folded into ONE
## vertex-coloured mesh regardless of its colour, so a hundred one-off tints (painted lanes,
## crate lids, stools, needles) cost one draw call instead of one each. Textured surfaces
## (rust_steel, concrete, ...) still batch per shared material, one draw call apiece.
const FLAT_KEY := "__flat_vertexcolor__"

## Batches are cut on a coarse spatial grid, NOT merged rig-wide. A single rig-spanning mesh
## per material has a rig-sized AABB that never frustum-culls, so every vantage — even one on
## the seabed looking away — pays the whole rig's vertex cost. Per-cell meshes keep compact,
## local AABBs, so the camera behind/below the rig culls the cells it cannot see (which is how
## render_budget's per-object culling paid off before the merge) while still collapsing the
## draw calls WITHIN each cell. 16 m trades a few more draw calls for real culling.
const CELL: float = 16.0

func _run() -> void:
	# Collect records grouped by (spatial cell, material key), plus the originals to free.
	# Non-colliding CSG boxes/cylinders become the equivalent primitive mesh first so they
	# batch with the plain meshes that share their material.
	var groups: Dictionary = {}          # str -> {mat, vcolor, entries:[[Mesh,Transform3D,Color]]}
	var to_free: Array[Node] = []

	var stack: Array = [rig_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if _protected(n):
			continue                     # skip this node AND its whole subtree
		for c in n.get_children():
			stack.append(c)
		var rec = _record_for(n)
		if rec == null:
			continue
		var matkey = rec[0]
		var xf: Transform3D = rec[2]
		var p: Vector3 = xf.origin
		var cx: int = int(floor(p.x / CELL))
		var cy: int = int(floor(p.y / CELL))
		var cz: int = int(floor(p.z / CELL))
		var vcolor: bool = matkey is String   # FLAT_KEY sentinel vs a Material instance
		var gkey: String = "%d,%d,%d|%s" % [cx, cy, cz,
			FLAT_KEY if vcolor else str((matkey as Material).get_instance_id())]
		if not groups.has(gkey):
			groups[gkey] = {"mat": null if vcolor else matkey, "vcolor": vcolor, "entries": []}
		groups[gkey]["entries"].append([rec[1], xf, rec[3]])
		to_free.append(n)

	if to_free.is_empty():
		return

	var holder := Node3D.new()
	holder.name = "MergedDressing"
	rig_root.add_child(holder)

	for gkey in groups:
		var g: Dictionary = groups[gkey]
		var vcolor: bool = g["vcolor"]
		var mesh: ArrayMesh = _bake(g["entries"], vcolor)
		if mesh == null:
			continue
		mesh.surface_set_material(0, _flat_material() if vcolor else g["mat"] as Material)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if MERGE_SHADOWS \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# So render_budget's sweep leaves the batch alone (it is already budgeted).
		mi.set_meta("budgeted", true)
		# So a SupportIndex built AFTER this pass (e.g. an audit probe) never reads this
		# merged mesh's single multi-height AABB as one flat surface — see support_index.gd.
		mi.add_to_group("merged_dressing")
		holder.add_child(mi)
		_merged_surfaces += 1

	for n in to_free:
		_consumed += 1
		n.free()

## Directional-shadow audit for the COLLIDING structural CSG that render_budget cannot see
## (render_budget.gd only walks MeshInstance3D; every CSGBox/CSGCylinder wall, floor, deck and
## brace was casting into both shadow splits, unbudgeted — the bulk of the deck vantage's draw
## calls). The rig's read shadow silhouette is carried by the tall masses (the four caissons,
## the accommodation stack, the derrick and crane) and by whatever rises above the deck to
## throw a shadow the player actually stands in. Everything else — under-deck girders, the
## deck slab's own downward shadow, wet-deck rooms, low dock dressing — casts a shadow no
## play vantage sees, so it drops out of the splits. This is item 3 of the frame-budget pass.
const SHADOW_KEEP_TALL: float = 8.0     ## AABB this tall always casts (caissons, stacks, masts)
const SHADOW_KEEP_TOP: float = 20.0     ## ...or rises this far (above the y18 deck) to shade it
const SHADOW_KEEP_MIN_DIM: float = 1.2  ## ...and is at least this wide (not a thin rail up high)

func _shadow_audit() -> void:
	var dropped: int = 0
	var stack: Array = [rig_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var csg := n as CSGShape3D
		if csg == null or csg.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var a: AABB = csg.global_transform * csg.get_aabb()
		var keep: bool = a.size.y >= SHADOW_KEEP_TALL \
			or (a.position.y + a.size.y >= SHADOW_KEEP_TOP \
				and maxf(a.size.x, a.size.z) >= SHADOW_KEEP_MIN_DIM)
		if not keep:
			csg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dropped += 1
	print("[batcher] shadow audit: dropped %d structural-CSG shadow casters" % dropped)

## The one shared material every flat-coloured part is baked under: albedo comes from the
## vertex colour, so a single StandardMaterial3D reproduces every MatLib.flat() tint. Same
## roughness/metallic as MatLib.flat(), so the look is unchanged.
var _flat_mat: StandardMaterial3D
func _flat_material() -> StandardMaterial3D:
	if _flat_mat == null:
		_flat_mat = StandardMaterial3D.new()
		_flat_mat.vertex_color_use_as_albedo = true
		_flat_mat.roughness = 0.6
	return _flat_mat

# ------------------------------------------------------------------ records

## Returns [matkey, mesh, world_transform, colour] if this node is a mergeable static
## primitive, else null. matkey is the shared Material for textured/emissive surfaces, or the
## FLAT_KEY sentinel (with colour set) for a plain single-colour MatLib.flat() part. Handles
## plain MeshInstance3D and standalone non-colliding CSG box/cylinder.
func _record_for(n: Node):
	if n.get_child_count() != 0:
		return null                      # only leaves — never orphan a child
	var mi := n as MeshInstance3D
	if mi != null:
		if mi.mesh == null or mi.mesh.get_surface_count() != 1:
			return null
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
			return null
		var m: Material = mi.get_active_material(0)
		if not _mat_mergeable(m):
			return null
		return _classify(m, mi.mesh, mi.global_transform)
	var csg := n as CSGShape3D
	if csg != null:
		if csg.get_parent() is CSGShape3D:
			return null                  # child of a boolean op — leave the tree intact
		if bool(csg.get("use_collision")):
			return null                  # keep colliding structure as-is (Stage 1)
		var cm: Mesh = _csg_to_mesh(csg)
		if cm == null:
			return null
		var mat: Material = csg.material
		if not _mat_mergeable(mat):
			return null
		return _classify(mat, cm, csg.global_transform)

## Route to the vertex-colour bucket if this is a flat single-colour surface, else keep it
## batched under its own shared material.
func _classify(m: Material, mesh: Mesh, xf: Transform3D):
	var sm := m as StandardMaterial3D
	if sm.albedo_texture == null and not sm.uv1_triplanar and not sm.emission_enabled:
		return [FLAT_KEY, mesh, xf, sm.albedo_color]
	return [m, mesh, xf, null]

## Equivalent primitive mesh for a standalone CSG box/cylinder. Other CSG types (torus,
## polygon, sphere) are rare here and left as individual nodes.
func _csg_to_mesh(csg: CSGShape3D) -> Mesh:
	if csg is CSGBox3D:
		var bm := BoxMesh.new()
		bm.size = (csg as CSGBox3D).size
		return bm
	if csg is CSGCylinder3D:
		var c := csg as CSGCylinder3D
		var cyl := CylinderMesh.new()
		cyl.bottom_radius = c.radius
		cyl.top_radius = 0.0 if bool(c.get("cone")) else c.radius
		cyl.height = c.height
		cyl.radial_segments = maxi(3, int(c.get("sides")))
		return cyl
	return null

# ------------------------------------------------------------------ bake

## Bake a set of [mesh, world_transform] into ONE ArrayMesh, surface 0, geometry moved into
## world space. No UVs/tangents: MatLib surfaces are triplanar (UVs generated in-shader from
## position) and flat colours need none, so a world-baked vertex looks identical to the loose
## mesh. Normals use the inverse-transpose so rotated/squashed parts stay correctly lit.
func _bake(entries: Array, vcolor: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var cols := PackedColorArray()
	for e in entries:
		var src: Mesh = e[0]
		var xf: Transform3D = e[1]
		var col: Color = e[2] if (vcolor and e[2] != null) else Color.WHITE
		var nb: Basis = xf.basis.inverse().transposed()
		for s in range(src.get_surface_count()):
			var arr: Array = src.surface_get_arrays(s)
			var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if sv.is_empty():
				continue
			var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var si: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var base: int = verts.size()
			var have_norm: bool = sn.size() == sv.size()
			for vi in range(sv.size()):
				verts.append(xf * sv[vi])
				if have_norm:
					norms.append((nb * sn[vi]).normalized())
				else:
					norms.append(Vector3.UP)
				if vcolor:
					cols.append(col)
			if si.is_empty():
				# Unindexed triangle soup — emit sequential indices.
				for vi in range(sv.size()):
					idx.append(base + vi)
			else:
				for ii in range(si.size()):
					idx.append(base + si[ii])
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	if vcolor:
		arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ------------------------------------------------------------------ eligibility

## Opaque, non-billboard StandardMaterial3D only. Transparent (glass, stains, alpha decals),
## billboarded motes and ShaderMaterials (the sea, the sky, the seabed) all stay loose so
## their blend order and per-vertex behaviour are preserved.
func _mat_mergeable(m: Material) -> bool:
	var sm := m as StandardMaterial3D
	if sm == null:
		return false
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	if sm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return false
	return true

## True if this node, or any ancestor up to the rig, is something we must never fold into a
## static batch: an interactable, a physics prop, a light zone, a player-built structure, or
## the player. Skipping returns for the whole subtree, so a mug ON a merged desk is safe.
##
## "doorframe" (door_frame.gd's GROUP) is protected for the same reason: every DoorFrame
## root registers its own opening rect in metadata and tests/DoorFrameProbe.tscn audits it
## by reading that root's OWN child MeshInstance3Ds directly — folding those jamb/head/sill
## meshes into a merged batch elsewhere leaves the frame node with no geometry of its own,
## which the probe (rightly) reads as "casing has no geometry at all" for every door on
## the rig, not just one.
func _protected(n: Node) -> bool:
	var cur: Node = n
	while cur != null and cur != rig_root.get_parent():
		if cur is Interactable or cur is RigidBody3D or cur is LightZone:
			return true
		if cur.is_in_group("built_structures") or cur.is_in_group("player") \
				or cur.is_in_group("floating_debris") or cur.is_in_group("lit_flares") \
				or cur.is_in_group("dress_prop") or cur.is_in_group("doorframe"):
			return true
		cur = cur.get_parent()
	return false

# ------------------------------------------------------------------ util

func _find_script(root: Node, tail: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var s: Script = n.get_script() as Script
		if s != null and s.resource_path.ends_with(tail):
			return n
		for c in n.get_children():
			stack.append(c)
	return null
