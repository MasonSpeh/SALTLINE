extends RefCounted
## VISUAL support resolver — the root fix for dressing props that float in mid air.
##
## Why not physics: a downward raycast CANNOT settle this rig. Most dressing furniture is
## drawn with non-colliding geometry (MeshInstance3D, or CSG with use_collision=false), so
## a ray dropped from a mug standing on a desk passes straight through the desk and reports
## the deck 80cm below. Snapping to that rains every desk, shelf and counter item onto the
## floor — it was tried, measured WORSE (726 -> 770 flagged props), and reverted.
##
## So support is resolved from what you can SEE. Every VisualInstance3D in the world
## contributes the TOP FACE of its world-space AABB as a candidate support surface. The
## faces are bucketed into a coarse XZ grid (plus a short list of oversized ones — decks,
## slabs) so a lookup touches a handful of candidates instead of thousands.
##
## To settle an item we take the merged visual AABB of its own subtree, ask for the highest
## support top that (a) lies at or just above the item's underside and (b) whose footprint
## contains the item's centre, then rest the item's AABB bottom on it. Items already sunk a
## little INTO their surface are lifted out (up to RISE); items hanging above one are
## dropped onto it. Nothing found below means the thing is wall-mounted or hanging, and it
## is left exactly where the dressing code put it.
##
## Used by interior_props.gd (build-time settle) and tests/placement_probe.gd (the audit),
## so the game and the measurement agree on what "resting on something" means.

const CELL: float = 2.0            ## XZ grid cell, meters
const MAX_CELLS: int = 96          ## surfaces covering more cells than this go in _big
const SPAN_CAP: float = 70.0       ## ignore anything wider than the rig (ocean, sky)

## How far a support top may sit ABOVE an item's underside and still count. Covers items
## authored a few cm inside their surface; keeps a table 0.5m over a floor-standing crate
## from claiming it. Scaled up by half the item's own height (capped at RISE_CAP), because
## a great many glTF props pivot at their CENTRE, not their base — a megaphone authored
## "on the desk" therefore starts with its underside below the desk top, and a fixed 10cm
## tolerance would reject the desk and drop it on the floor. Half-height means the rule
## reads "the surface has to be below the middle of the object", which is what the eye
## uses too, while the cap stops a broom standing beside a table from hopping onto it.
const RISE: float = 0.10
const RISE_CAP: float = 0.45
## Rest this far proud of the surface, so coplanar faces don't z-fight.
const CLEAR: float = 0.005
## A correction bigger than this is not a settle, it's a teleport — leave it and let the
## probe report it instead of silently dropping a shelf item three meters.
const MAX_DROP: float = 2.5

## Subtrees that must never be indexed as scenery: they move. A fish swimming past is not
## a shelf. Matched against the node's script path.
## Plus one subtree that does not move but must still not be indexed: rig_batcher.gd's
## welded dressing output (MeshInstance3D in group "merged_dressing", skipped at L99 below —
## it carries no script, so SKIP_SCRIPTS cannot catch it). That weld is a DUPLICATE of
## geometry already in this index; indexing it too would add one enormous merged AABB per
## bucket and let a mug rest on the convex hull of a hundred scattered bolts.
## CAUTION for anyone building a SupportIndex AFTER the rig has been batched: rig_batcher.gd
## FREES its source nodes (rig_batcher.gd:139 n.free()) once it has welded them, so those
## real surfaces are gone from the tree and a from-scratch index will UNDER-count them and
## report false floaters. That is exactly why tests/placement_probe.gd frees RigBatcher
## before it welds (placement_probe.gd:82) and audits the pre-batch tree. This SKIP list is
## shared with tests/placement_probe.gd.
const SKIP_SCRIPTS := [
	"crab.gd", "shark.gd", "bloom_fauna.gd", "underwater_world.gd", "creature_kit.gd",
	"creature_anim.gd", "jelly_glow.gd", "gyre.gd", "storm_system.gd", "fish_model_lib.gd",
	"flare_stick.gd", "player.gd", "rain_audio.gd", "mesh_batcher.gd",
]

var _surf: Array = []              # [min_x, max_x, min_z, max_z, top_y, node]
var _cells: Dictionary = {}        # Vector2i -> PackedInt32Array of _surf indices
var _big: PackedInt32Array = PackedInt32Array()
var _of_node: Dictionary = {}      # node instance id -> _surf index

func surface_count() -> int:
	return _surf.size()

# ---------------------------------------------------------------- build

## Index every visual surface under `root`. Call once, after the world is built.
func build(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if _skipped(n):
			continue
		for c in n.get_children():
			stack.append(c)
		if is_geometry(n):
			_add(n as VisualInstance3D)

## Solid drawn geometry: a real surface you could put a mug on. Deliberately a whitelist —
## lights, decals, particles and Label3D stencil paint are all VisualInstance3D with a very
## real AABB, and none of them holds anything up.
static func is_geometry(n: Node) -> bool:
	return n is MeshInstance3D or n is CSGShape3D or n is MultiMeshInstance3D

func _skipped(n: Node) -> bool:
	if n.is_in_group("player"):
		return true
	# rig_batcher.gd bakes many separate dressing meshes — at many different real
	# heights — into ONE ArrayMesh per cell/material. That merged mesh's single AABB
	# top face is meaningless as "the surface here": a cell can combine a girder and a
	# nearby bolt, and the merged AABB reports the TALLER one across the whole footprint,
	# inventing a false shelf (or hiding a real one) anywhere within it. This never costs
	# real placement: interior_props' own settle pass builds and discards its SupportIndex
	# BEFORE the batcher merges anything (rig_batcher waits on settle_done precisely so it
	# never removes a surface something is still settling onto), so nothing at runtime
	# ever queries a SupportIndex again afterward — only a later, from-scratch audit would.
	if n.is_in_group("merged_dressing"):
		return true
	var s: Script = n.get_script() as Script
	if s != null:
		var p: String = s.resource_path
		for frag in SKIP_SCRIPTS:
			if p.ends_with(frag):
				return true
	return false

func _add(vi: VisualInstance3D) -> void:
	var a: AABB = world_aabb_of(vi)
	if a.size == Vector3.ZERO:
		return
	if a.size.x > SPAN_CAP or a.size.z > SPAN_CAP:
		return
	var min_x: float = a.position.x
	var max_x: float = a.position.x + a.size.x
	var min_z: float = a.position.z
	var max_z: float = a.position.z + a.size.z
	var idx: int = _surf.size()
	_surf.append([min_x, max_x, min_z, max_z, a.position.y + a.size.y, vi])
	_of_node[vi.get_instance_id()] = idx
	var c0 := Vector2i(floori(min_x / CELL), floori(min_z / CELL))
	var c1 := Vector2i(floori(max_x / CELL), floori(max_z / CELL))
	var span: int = (c1.x - c0.x + 1) * (c1.y - c0.y + 1)
	if span > MAX_CELLS:
		_big.append(idx)
		return
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var key := Vector2i(cx, cz)
			if not _cells.has(key):
				_cells[key] = PackedInt32Array()
			var arr: PackedInt32Array = _cells[key]
			arr.append(idx)
			_cells[key] = arr

# ---------------------------------------------------------------- query

## Highest visual support top under `aabb`, or -INF when nothing is below it (hanging).
## Surfaces belonging to `ignore` (the item itself, or anything parented under it) are
## skipped, so an object never rests on its own geometry.
func support_top(aabb: AABB, ignore: Node, rise: float = RISE) -> float:
	var cx: float = aabb.position.x + aabb.size.x * 0.5
	var cz: float = aabb.position.z + aabb.size.z * 0.5
	var limit: float = aabb.position.y + minf(maxf(rise, aabb.size.y * 0.5), RISE_CAP)
	var best: float = -INF
	var key := Vector2i(floori(cx / CELL), floori(cz / CELL))
	if _cells.has(key):
		best = _scan(_cells[key], cx, cz, limit, best, ignore)
	best = _scan(_big, cx, cz, limit, best, ignore)
	return best

func _scan(list, cx: float, cz: float, limit: float, best_in: float, ignore: Node) -> float:
	var best: float = best_in
	for i in list:
		var s: Array = _surf[i]
		var top: float = s[4]
		if top > limit or top <= best:
			continue
		if cx < s[0] or cx > s[1] or cz < s[2] or cz > s[3]:
			continue
		var n: Node = s[5]
		if not is_instance_valid(n):
			continue
		if ignore != null and (n == ignore or ignore.is_ancestor_of(n)):
			continue
		best = top
	return best

# ---------------------------------------------------------------- settle

## Rest `node` on the visual surface beneath it. Returns the vertical correction applied
## (negative = dropped), or 0.0 when the node was left alone (nothing below / out of range).
func settle(node: Node3D, aabb_in: AABB = AABB()) -> float:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return 0.0
	var a: AABB = aabb_in if aabb_in.size != Vector3.ZERO else world_aabb_of_tree(node)
	if a.size == Vector3.ZERO:
		return 0.0
	var top: float = support_top(a, node)
	if top == -INF:
		return 0.0                       # nothing under it: wall-mounted or hanging
	var delta: float = (top + CLEAR) - a.position.y
	if delta < -MAX_DROP or absf(delta) < 0.0005:
		return 0.0
	node.global_position.y += delta
	# The thing we just moved is itself a surface other items may be settling onto in this
	# same pass. Without this the index keeps serving its old top and a mug lands where a
	# crate USED to be — items end up floating inside the very furniture they belong on.
	_shift_surfaces(node, delta)
	return delta

func _shift_surfaces(node: Node, delta: float) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var idx = _of_node.get(n.get_instance_id())
		if idx != null:
			_surf[idx][4] = float(_surf[idx][4]) + delta

# ---------------------------------------------------------------- aabb helpers

## Wall furniture: a poster, a taped photograph, a breaker panel, a mounted screen — a slab
## whose THINNEST axis is horizontal and whose other two are several times bigger. Those
## bolt flush to a bulkhead; there is nothing under them and there is not meant to be, so
## neither the settle nor the audit should have an opinion about them. Shared by both so
## the game and the probe agree on what counts as "resting on something".
static func is_wall_panel(a: AABB) -> bool:
	var thin_h: float = minf(a.size.x, a.size.z)
	var wide_h: float = maxf(a.size.x, a.size.z)
	return thin_h < 0.35 and thin_h < a.size.y and minf(wide_h, a.size.y) >= thin_h * 2.0

static func world_aabb_of(vi: VisualInstance3D) -> AABB:
	return vi.global_transform * vi.get_aabb()

## Merged world AABB of every visual under `node` (inclusive) — a prop's real silhouette,
## not just its root mesh.
static func world_aabb_of_tree(node: Node) -> AABB:
	var acc := AABB()
	var first: bool = true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if is_geometry(n):
			var vi := n as VisualInstance3D
			if vi.get_aabb().size == Vector3.ZERO:
				continue
			var a: AABB = world_aabb_of(vi)
			if first:
				acc = a
				first = false
			else:
				acc = acc.merge(a)
	return acc if not first else AABB()
