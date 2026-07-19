extends Node3D
## STATIC BATCHING — the pass that takes this rig from draw-call bound to fill bound.
##
## gl_compatibility issues one draw call per mesh surface, per shadow split it casts into.
## The rig is authored as ~8,400 individual primitives (every bolt, rung, cleat, flange and
## placard is its own node), which is the right way to author it and the wrong thing to hand
## a GL renderer: 6,695 draw calls standing on deck, 9,489 at sea level, and a frame rate
## that tracks the CALL count almost linearly while barely noticing triangles at all
## (the seabed vantage draws 3.2M tris in 265 calls at 71 fps).
##
## render_budget.gd already took everything that could be taken by NOT drawing things.
## What is left has to be drawn — so the only remaining lever is to draw it in fewer calls.
##
## WHAT THIS DOES
## Every sweep it collects static, script-free, opaque drawables that share a material,
## buckets them by (material, shadow setting, spatial cell), and welds each bucket's
## geometry into ONE ArrayMesh baked in world space. A bucket of 300 bolts becomes one
## draw call instead of 300. The source nodes are then dropped from the renderer.
##
## WHY IT LOOKS IDENTICAL
##   * Materials come from MatLib and are CACHED SHARED INSTANCES, so a bucket really is
##     one material — nothing is re-tinted to make it merge.
##   * MatLib's textured surfaces are WORLD-space triplanar: the texture is a function of
##     world position, not of UVs or of the model matrix. Welding geometry in world space
##     therefore cannot move the grain by so much as a texel. Materials that are NOT world
##     triplanar (rope, which is object-space) are excluded — see _mat_ok.
##   * Transparent, billboarded and emissive-sorted materials are excluded, because merging
##     changes draw order and billboarding depends on a per-instance model matrix.
##   * A bucket is banded by visibility range and inherits the MAXIMUM range of its members,
##     never a shorter one, so nothing that used to draw at a distance stops drawing, and a
##     short-range bolt is not dragged out to a long-range handrail's distance.
##   * A region lit by more than the renderer's per-object light cap is left UNWELDED, since
##     one merged object cannot receive as many lights as its scattered originals did — this
##     is what keeps the lamplit interiors from going dim. See LIGHT_CAP.
##
## HOW THE PROBES STILL SEE THE WORLD THEY AUDITED  <-- read this before changing anything
## The source nodes are NOT freed and NOT hidden. They keep their transform, their mesh,
## their AABB and their is_visible_in_tree() — only their render LAYER MASK is cleared, so
## the renderer culls them and nothing else can tell the difference. That is deliberate:
##   * support_index.gd resolves what a mug rests on by reading MeshInstance3D world AABBs.
##     It walks the same nodes it always did and gets the same answers, so no support
##     surface disappeared and SupportIndex needed no changes at all.
##   * placement_probe.gd, label_anchor_probe.gd, light_anchor_probe.gd, door_frame_probe.gd
##     and e2e_probe.gd all walk visual geometry the same way, and all still see it.
## The one thing that DID have to be taught: the welded output is a duplicate of geometry
## those probes already index, so the batch subtree must be skipped by them or it double
## counts. It carries the "render_batch" group and this script's path for exactly that, and
## support_index.gd's SKIP_SCRIPTS lists it (which covers placement_probe too).
##
## Collision is untouched throughout: nothing here creates, moves or removes a collider.

## Spatial bucket size. Merging the whole rig per material would be the fewest calls and the
## worst culling — one bucket spanning 60 m can never leave the frustum. Cells keep the
## welded chunks local enough that looking away from half the rig still culls half of it.
## (The interior-lighting concern that would otherwise force a tiny cell is handled instead
## by the per-bucket LIGHT_CAP veto, which lets this stay large for the exterior's benefit.)
const CELL: float = 16.0
## Largest world dimension a drawable may have and still be merged. Anything bigger is
## structure — few enough not to matter for the call count, and better left to cast, cull
## and light as its own object.
const MAX_SIZE: float = 16.0
## Don't weld a bucket until it actually saves calls. Welding 2 meshes saves 1 call and
## costs their culling; the final sweep drops this to FINAL_MIN to sweep up the tail.
const MIN_BATCH: int = 6
const FINAL_MIN: int = 2
## Cap on a single welded surface, so one bucket can't become an un-cullable megamesh.
const MAX_VERTS: int = 120000

## The Compatibility renderer forward-lights each object with at most this many omni/spot
## lights (rendering/limits/opengl/max_lights_per_object, engine default 8). A welded chunk
## is ONE object, so if the region it covers is touched by more than this many positional
## lights it drops the surplus and goes dim — measured at 9% darker across the rec room,
## while the sunlit exterior (no omni lights on it) stayed pixel-identical. So a bucket whose
## footprint is lit by more than LIGHT_CAP lights is left UNWELDED: the many small originals
## each keep their own ≤8 nearest lights and the room lights exactly as authored. One under
## the engine's 8, as a margin against its relevance heuristic dropping a borderline light.
const LIGHT_CAP: int = 7

## The dressing streams in over ~25 s and render_budget.gd sweeps behind it (its last pass
## lands at 22.5 s). Batching runs behind BOTH: a mesh is only eligible once render_budget
## has stamped it "budgeted", which guarantees its cast_shadow flag is final and will not
## change after it has been welded. The last sweep is deliberately just after the budget
## pass finishes rather than far behind it — the player should not spend the first half
## minute on deck paying full price for a world that stopped changing at 25 s.
const SWEEPS: Array[float] = [5.0, 9.0, 13.0, 17.0, 21.0, 24.0, 26.5]

## Builders whose output is pure static scenery. A mesh is only a candidate if EVERY node
## between it and the world root either has no script at all or has one of these — which is
## what keeps doors, ladders, salvage, readables, takeables, movable props, beds, containers
## and every creature out of the weld, since their own script sits nearer than the builder's.
## seabed.gd and reef_detail.gd earn their place here: both position everything at build
## time and never touch a transform again. seabed.gd's _process only animates a shader
## parameter on the floor, which is a ShaderMaterial and is refused by _mat_ok anyway.
const STATIC_BUILDERS: Array[String] = [
	"rig_builder.gd", "rig_superstructure.gd", "rig_exterior.gd", "exterior_dress.gd",
	"wet_deck_detail.gd", "stair_kit.gd", "door_frame.gd",
	"seabed.gd", "reef_detail.gd",
]

## Subtrees that must never be welded: they move, they are re-tinted, they are placed and
## settled after the fact, or they are somebody's interaction target.
## "dress_prop" is deliberately NOT here. exterior_dress.gd tags every one of its assemblies
## with it so PlacementProbe will audit them, not because anything ever moves them — and
## skipping the group cost 818 draw calls of pipe racks, gas cages, drums and ductwork. The
## stability check below is what actually guarantees a thing is not going to move, so the
## audit tag no longer has to double as a batching veto.
const SKIP_GROUPS: Array[String] = [
	"player", "floating_debris", "gyre_streaks", "lit_flares", "ocean_surface",
	"settle_me", "comfort_furniture", "built_structures", "salvageable",
	"salvaged", "dropped_item", "loot_container", "hittable", "gull_nest", "ambience",
	"light_zones", "spill_lights", "render_batch",
]

var _pending: Dictionary = {}      ## bucket key -> Array[MeshInstance3D]
var _welded: int = 0               ## source nodes absorbed
var _chunks: int = 0               ## draw calls they became
var _skipped_moving: int = 0
var _by_class: Dictionary = {}     ## what kind of node the welded sources were
var _why: Dictionary = {}          ## reason -> how many candidates it turned away
var _root: Node3D

func _ready() -> void:
	name = "MeshBatcher"
	add_to_group("render_batch")
	# A/B switch for the visual-diff harness. Comparing a screenshot from before this file
	# existed against one from after it landed also compares two different runs of a world
	# that has a clock, weather and fauna in it; --no-batch lets both halves of the
	# comparison come from the SAME build with only the welding turned off.
	if OS.get_cmdline_user_args().has("--no-batch"):
		print("[batch] disabled by --no-batch")
		return
	_root = Node3D.new()
	_root.name = "Welded"
	add_child(_root)
	_root.add_to_group("render_batch")
	for i in range(SWEEPS.size()):
		var wait: float = SWEEPS[i] - (SWEEPS[i - 1] if i > 0 else 0.0)
		await get_tree().create_timer(wait).timeout
		_collect(get_parent())
		_flush(FINAL_MIN if i == SWEEPS.size() - 1 else MIN_BATCH)
	_report()

## A batcher that silently welds nothing looks exactly like a batcher that is working, so
## it says what it did and — more usefully when tuning — what it refused and why.
func _report() -> void:
	print("[batch] welded %d source meshes into %d draw calls (%d skipped as non-static)" % [
		_welded, _chunks, _skipped_moving])
	for c in _by_class:
		print("[batch]   from %6d  %s" % [_by_class[c], c])
	var reasons: Array = _why.keys()
	reasons.sort_custom(func(a, b): return int(_why[a]) > int(_why[b]))
	for r in reasons:
		print("[batch]   rejected %6d  %s" % [_why[r], r])
	var left: int = 0
	var biggest: int = 0
	for k in _pending:
		left += (_pending[k] as Array).size()
		biggest = maxi(biggest, (_pending[k] as Array).size())
	print("[batch]   %d bucketed but unwelded across %d buckets (largest %d, min to weld %d)" % [
		left, _pending.size(), biggest, FINAL_MIN])

# ---------------------------------------------------------------- collection

func _collect(root: Node) -> void:
	if root == null:
		return
	# Seed with the root's CHILDREN, never the root itself: the scope root is Main, whose
	# main.gd is not a static builder, so testing it rejects the entire world in one step.
	var stack: Array = []
	for c in root.get_children():
		stack.append(c)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if _skip_subtree(n):
			continue
		# A CSG root's children are its boolean OPERANDS, not scenery — never descend into
		# one. The root itself is judged by _csg_candidate, which only accepts shapes doing
		# no boolean work at all.
		if n is CSGShape3D:
			if _csg_candidate(n as CSGShape3D) and _settled(n as GeometryInstance3D):
				# `material` lives on CSGPrimitive3D, not on the CSGShape3D base — a
				# CSGCombiner3D has none at all, so this is read dynamically.
				_bucket(n as GeometryInstance3D, n.get("material") as Material)
			continue
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or not _candidate(mi) or not _settled(mi):
			continue
		_bucket(mi, mi.mesh.surface_get_material(0))

## Has this drawable stopped moving? Welding bakes a world transform, so anything that is
## still being positioned would freeze at wherever it happened to be when the weld ran.
##
## The first sweep that sees a node only REMEMBERS where it was; a later sweep welds it
## only if it has not moved since. That is a stronger guarantee than any list of "things
## that move" could be, and it is what makes it safe to batch exterior_dress.gd's
## dress_prop assemblies — the dressing streams in, gets nudged, and settles, all of it
## finished long before two consecutive sweeps agree on a transform.
func _settled(gi: GeometryInstance3D) -> bool:
	var xf: Transform3D = gi.global_transform
	if not gi.has_meta("batch_xform"):
		gi.set_meta("batch_xform", xf)
		return false
	if not (gi.get_meta("batch_xform") as Transform3D).is_equal_approx(xf):
		gi.set_meta("batch_xform", xf)
		_no("still moving between sweeps")
		return false
	return true

## File a drawable under (material, shadow setting, spatial cell).
func _bucket(gi: GeometryInstance3D, mat: Material) -> void:
	if mat == null:
		_no("no material")
		return
	if not _mat_ok(mat):
		return
	gi.set_meta("batch_seen", true)
	var p: Vector3 = gi.global_position
	# Bucket by visibility band as well as by cell. A chunk can only carry ONE distance
	# range, and it has to be the longest of its members or something would vanish early —
	# so welding a 40 m bolt in with a 200 m handrail drags the bolt out to 200 m and undoes
	# render_budget.gd's distance culling. Banding keeps short-range detail welded to
	# short-range detail: without it, sea level drew 260k more triangles than it needed to.
	var band: int = int(gi.visibility_range_end / 25.0)
	var key: String = "%d|%d|%d|%d|%d|%d" % [
		mat.get_instance_id(), gi.cast_shadow, band,
		floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL)]
	if not _pending.has(key):
		_pending[key] = []
	(_pending[key] as Array).append(gi)

## A CSGShape3D that is pure decoration: its own root, performing no boolean operation,
## with no operand children. Almost every CSG shape on this rig is one of these — they were
## authored as CSG for the convenience of the helper that makes them, not to cut anything —
## and each one is a separate mesh generation and a separate draw call.
##
## The five real CSGCombiner3D assemblies (door openings, window cuts, hatches, the SPHL
## hull) are excluded on all three counts and are left completely alone.
func _csg_candidate(csg: CSGShape3D) -> bool:
	if csg.has_meta("batch_seen"):
		return false
	if csg is CSGCombiner3D:
		return _no("csg: combiner (real boolean work)")
	if csg.get_parent() is CSGShape3D:
		return _no("csg: operand, not a root")
	if csg.operation != CSGShape3D.OPERATION_UNION:
		return _no("csg: non-union operation")
	for c in csg.get_children():
		if c is CSGShape3D:
			return _no("csg: has operands cutting it")
	if csg.get_script() != null or not csg.get_groups().is_empty():
		return _no("csg: scripted or grouped")
	if not csg.is_visible_in_tree() or csg.material_override != null:
		return _no("csg: hidden or overridden")
	var a: AABB = csg.get_aabb()
	var scl: Vector3 = csg.global_transform.basis.get_scale()
	var big: float = maxf(maxf(a.size.x * scl.x, a.size.y * scl.y), a.size.z * scl.z)
	if big <= 0.0:
		return _no("csg: empty aabb")
	if big > MAX_SIZE:
		return _no("csg: bigger than MAX_SIZE")
	return true

## A subtree nothing static can live in. Groups are the reliable signal here: the placement
## system, the interaction system and the creature code all tag what they own.
func _skip_subtree(n: Node) -> bool:
	if n == self:
		return true
	for g in SKIP_GROUPS:
		if n.is_in_group(g):
			return true
	if n is CollisionObject3D:
		return true          # doors, ladders, pickups, crates — everything interactive
	var s: Script = n.get_script() as Script
	if s == null:
		return false
	var p: String = s.resource_path
	if p == "":
		return true          # inner class / unknown owner: assume it manages its own nodes
	for frag in STATIC_BUILDERS:
		if p.ends_with(frag):
			return false
	_skipped_moving += 1
	return true              # somebody's script owns this subtree: it may move or re-tint

## Record why a candidate was turned away, and return false so call sites read as
## `return _no("...")`. Tallied into the end-of-sweep report.
func _no(reason: String) -> bool:
	_why[reason] = int(_why.get(reason, 0)) + 1
	return false

func _candidate(mi: MeshInstance3D) -> bool:
	if mi.has_meta("batch_seen") or mi.mesh == null:
		return false
	# render_budget stamps this once it has settled the node's shadow flag and distance
	# range. Welding before that would bake a cast_shadow value that is about to change.
	if not mi.has_meta("budgeted"):
		return _no("not budgeted yet")
	if mi.get_child_count() > 0:
		return _no("has children")
	if mi.get_script() != null:
		return _no("own script")
	if not mi.get_groups().is_empty():
		return _no("in a group")
	if mi.material_override != null or mi.material_overlay != null:
		return _no("material override")
	if mi.skeleton != NodePath() and mi.skeleton != NodePath(".."):
		return _no("skinned")
	if mi.mesh.get_surface_count() != 1:
		return _no("multi-surface mesh")
	if mi.get_surface_override_material_count() > 0 \
			and mi.get_surface_override_material(0) != null:
		return _no("per-instance material")   # not shared: don't merge it away
	if not mi.is_visible_in_tree():
		return _no("hidden")
	var a: AABB = mi.get_aabb()
	var scl: Vector3 = mi.global_transform.basis.get_scale()
	var big: float = maxf(maxf(a.size.x * scl.x, a.size.y * scl.y), a.size.z * scl.z)
	if big <= 0.0:
		return _no("empty aabb")
	if big > MAX_SIZE:
		return _no("bigger than MAX_SIZE")
	return true

## Merging is only invisible for materials whose shading does not depend on the model
## matrix or on draw order.
func _mat_ok(m: Material) -> bool:
	var sm := m as StandardMaterial3D
	if sm == null:
		return _no("shader material")        # assume it reads model space
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return _no("transparent")            # merging reorders alpha blending
	if sm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return _no("billboard")              # billboarding IS the model matrix
	# Object-space triplanar maps texture from LOCAL position: welding moves it. World-space
	# triplanar maps from world position and is therefore weld-proof.
	if sm.uv1_triplanar and not sm.uv1_world_triplanar:
		return _no("uv1 object triplanar")
	if sm.uv2_triplanar and not sm.uv2_world_triplanar:
		return _no("uv2 object triplanar")
	return true

# ---------------------------------------------------------------- welding

func _flush(min_size: int) -> void:
	_rebuild_light_index()
	for key in _pending.keys():
		var members: Array = _pending[key]
		if members.size() < min_size:
			continue
		var alive: Array = []
		var region := AABB()
		var first: bool = true
		for m in members:
			if not is_instance_valid(m) or (m as GeometryInstance3D).layers == 0:
				continue
			alive.append(m)
			var wa: AABB = _world_aabb(m)
			region = wa if first else region.merge(wa)
			first = false
		_pending.erase(key)
		if alive.size() < min_size:
			continue
		# The lighting veto: one welded object is lit by at most LIGHT_CAP omni/spot lights,
		# so a region already lit by more would lose the surplus. Leave it as the many small
		# originals, each keeping its own nearest lights, and it renders exactly as authored.
		if _lights_overlapping(region) > LIGHT_CAP:
			_no("region lit by more than LIGHT_CAP lights")
			continue
		var i: int = 0
		while i < alive.size():
			var taken: int = _weld(alive, i)
			if taken <= 0:
				break
			i += taken

## Weld alive[start..] into one ArrayMesh until MAX_VERTS. Returns how many it consumed.
func _weld(alive: Array, start: int) -> int:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var used: Array = []
	var centre := Vector3.ZERO
	var i: int = start
	while i < alive.size():
		if verts.size() >= MAX_VERTS:
			break
		var gi: GeometryInstance3D = alive[i]
		i += 1
		var src: Array = _geometry_of(gi)
		if src.is_empty():
			_no("weld: no source mesh (%s)" % gi.get_class())
			continue
		if not _append(src[0], src[1], verts, norms, tans, uvs, idx):
			_no("weld: unusable vertex format (%s)" % gi.get_class())
			continue          # leave it drawing itself
		used.append(gi)
		centre += gi.global_position
	var consumed: int = maxi(i - start, 1)
	if used.is_empty() or verts.is_empty():
		return consumed
	centre /= float(used.size())

	# Rebase into a local frame at the bucket centre. World triplanar is unaffected (it
	# reads world position, which the chunk transform restores exactly) and the chunk gets
	# a sane origin for distance culling.
	for k in range(verts.size()):
		verts[k] = verts[k] - centre

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tans
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var first: GeometryInstance3D = used[0]
	mesh.surface_set_material(0, _material_of(first))

	var chunk := MeshInstance3D.new()
	chunk.mesh = mesh
	chunk.cast_shadow = first.cast_shadow
	_root.add_child(chunk)
	chunk.global_position = centre
	chunk.name = "Weld_%d" % _chunks
	# Never shorten a member's reach: take the longest, and unlimited beats any limit.
	var reach: float = 0.0
	for m in used:
		var r: float = (m as GeometryInstance3D).visibility_range_end
		if r <= 0.0:
			reach = 0.0
			break
		reach = maxf(reach, r)
	if reach > 0.0:
		chunk.visibility_range_end = reach
		chunk.visibility_range_end_margin = first.visibility_range_end_margin
		chunk.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

	# Drop the sources from the renderer WITHOUT hiding them: layers 0 fails every camera
	# and light cull mask, so they cost nothing to draw, while their transform, AABB and
	# is_visible_in_tree() stay exactly as the placement/support/label probes found them.
	for m in used:
		var mm: GeometryInstance3D = m
		mm.set_meta("welded_into", chunk.get_path())
		mm.layers = 0
		var cls: String = "MeshInstance3D" if mm is MeshInstance3D else "CSG"
		_by_class[cls] = int(_by_class.get(cls, 0)) + 1
	_welded += used.size()
	_chunks += 1
	return maxi(consumed, 1)

# ---------------------------------------------------------------- source geometry

## [Mesh, world Transform3D] for either node kind, or [] when there is nothing to weld.
## A CSGShape3D hands back its GENERATED mesh in its own local space, so the transform has
## to compose the shape's global transform with the local one it reports.
func _geometry_of(gi: GeometryInstance3D) -> Array:
	var mi := gi as MeshInstance3D
	if mi != null:
		return [] if mi.mesh == null else [mi.mesh, mi.global_transform]
	var csg := gi as CSGShape3D
	if csg == null:
		return []
	var parts: Array = csg.get_meshes()
	if parts.size() < 2 or parts[1] == null:
		return []
	var m := parts[1] as Mesh
	if m == null or m.get_surface_count() != 1:
		return []
	return [m, csg.global_transform * (parts[0] as Transform3D)]

func _material_of(gi: GeometryInstance3D) -> Material:
	var mi := gi as MeshInstance3D
	if mi != null:
		return mi.mesh.surface_get_material(0)
	return (gi as CSGShape3D).material

func _world_aabb(gi: GeometryInstance3D) -> AABB:
	return gi.global_transform * gi.get_aabb()

# ---------------------------------------------------------------- light index

## Positional lights that light the welded chunks: [world position, effective radius].
## Rebuilt each sweep because interior lamps stream in with the dressing. Spotlights are
## treated as a sphere of their range — conservative, which is the safe direction for a
## veto. DirectionalLight is not here: it is not part of the per-object positional cap.
var _lights: Array = []

func _rebuild_light_index() -> void:
	_lights.clear()
	var stack: Array = [get_parent()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var omni := n as OmniLight3D
		if omni != null:
			if omni.is_visible_in_tree() and omni.light_energy > 0.0:
				_lights.append([omni.global_position, omni.omni_range])
			continue
		var spot := n as SpotLight3D
		if spot != null and spot.is_visible_in_tree() and spot.light_energy > 0.0:
			_lights.append([spot.global_position, spot.spot_range])

## How many indexed lights reach into `region`. Counts a light when the nearest point of the
## AABB to it is within the light's radius — the same test the renderer's cull uses.
func _lights_overlapping(region: AABB) -> int:
	if region.size == Vector3.ZERO:
		return 0
	var lo: Vector3 = region.position
	var hi: Vector3 = region.position + region.size
	var count: int = 0
	for L in _lights:
		var p: Vector3 = L[0]
		var r: float = L[1]
		var nearest := Vector3(
			clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y), clampf(p.z, lo.z, hi.z))
		if p.distance_to(nearest) <= r:
			count += 1
			if count > LIGHT_CAP:
				return count      # no need to keep counting past the veto threshold
	return count

## Append one mesh's surface, transformed into world space. False when the mesh doesn't
## carry the full vertex format the weld needs (no tangents => broken normal mapping).
func _append(mesh: Mesh, xf: Transform3D, verts: PackedVector3Array, norms: PackedVector3Array,
		tans: PackedFloat32Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> bool:
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return false
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n = arrays[Mesh.ARRAY_NORMAL]
	var t = arrays[Mesh.ARRAY_TANGENT]
	var u = arrays[Mesh.ARRAY_TEX_UV]
	if v.is_empty() or n == null or t == null or u == null:
		return false
	# surface_get_primitive_type lives on ArrayMesh, not on the Mesh base — PrimitiveMesh
	# (Box/Cylinder/Sphere/Torus, most of this rig) has no such method and is always
	# triangles, so only the ArrayMesh case needs asking.
	var am := mesh as ArrayMesh
	if am != null and am.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return false
	# Normals need the inverse transpose under non-uniform scale, which plenty of these
	# have (a box scaled into a plank). Getting this wrong relights the whole rig.
	var nb: Basis = xf.basis.inverse().transposed()
	var base: int = verts.size()
	for i in range(v.size()):
		verts.append(xf * v[i])
		norms.append((nb * (n as PackedVector3Array)[i]).normalized())
		var tv := Vector3((t as PackedFloat32Array)[i * 4], (t as PackedFloat32Array)[i * 4 + 1],
			(t as PackedFloat32Array)[i * 4 + 2])
		tv = (xf.basis * tv).normalized()
		tans.append(tv.x)
		tans.append(tv.y)
		tans.append(tv.z)
		tans.append((t as PackedFloat32Array)[i * 4 + 3])
		uvs.append((u as PackedVector2Array)[i])
	var src_idx = arrays[Mesh.ARRAY_INDEX]
	# A mirrored transform reverses winding; unreversed, those faces are backface-culled
	# and the object turns inside out.
	var flip: bool = xf.basis.determinant() < 0.0
	if src_idx == null:
		for i in range(0, v.size(), 3):
			if flip:
				idx.append_array([base + i, base + i + 2, base + i + 1])
			else:
				idx.append_array([base + i, base + i + 1, base + i + 2])
	else:
		var si: PackedInt32Array = src_idx
		for i in range(0, si.size(), 3):
			if flip:
				idx.append_array([base + si[i], base + si[i + 2], base + si[i + 1]])
			else:
				idx.append_array([base + si[i], base + si[i + 1], base + si[i + 2]])
	return true
