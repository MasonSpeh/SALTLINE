extends Node
## ULTRA HAMMERHEAD — mesh geometry ground truth (2026-07-28 model swap).
##
## The new hammerhead is NOT authored the way every other generated model here is: it is
## posed in a crescent, so its bounding box is nearly cubic and the "longest axis" that
## CreatureAnim.load_model() normalises is no longer the animal's length. Guessing from a
## turntable render is what produced the last rejected pass; this prints numbers instead.
##
## Reports, for the raw GLB:
##   * the local AABB, so you can see which axis is actually longest
##   * a slice profile along each axis — vertex count and cross-section span per slice —
##     because a shark's HEAD end is bulky (skull + four eye stalks) and its TAIL end
##     tapers to a fluke, which is a signature you can read off numbers
##   * the arc length of the body centreline, which for a curved pose is the real
##     nose-to-tail length and is always longer than any AABB edge
##
## Run: godot --headless --path . res://tests/SharkProbe.tscn

const PATH := "res://assets/models/fauna/ultra_hammerhead/ultra_hammerhead.glb"
const SLICES: int = 12

func _ready() -> void:
	if not ResourceLoader.exists(PATH):
		print("[shark] MISSING: ", PATH)
		get_tree().quit()
		return
	var model: Node3D = (load(PATH) as PackedScene).instantiate()
	add_child(model)
	await get_tree().process_frame
	var verts: PackedVector3Array = _verts(model)
	print("[shark] surfaces=%d verts=%d" % [_mesh_count(model), verts.size()])
	var box: AABB = _bounds(model)
	print("[shark] local AABB pos=%s size=%s  (longest=%.3f)"
		% [str(box.position.snappedf(0.001)), str(box.size.snappedf(0.001)),
			maxf(box.size.x, maxf(box.size.y, box.size.z))])
	for axis in range(3):
		_profile(verts, box, axis)
	_arc(verts, box)
	get_tree().quit()

## Slice the cloud along `axis` and report how much animal is in each slice. The end that
## keeps a wide cross-section for several slices is the head; the end that thins to almost
## nothing over the last slices is the tail.
func _profile(verts: PackedVector3Array, box: AABB, axis: int) -> void:
	var name := ["X", "Y", "Z"][axis]
	var lo: float = box.position[axis]
	var span: float = maxf(box.size[axis], 0.0001)
	var counts := PackedInt32Array()
	var spans := PackedFloat32Array()
	counts.resize(SLICES)
	spans.resize(SLICES)
	var mins: Array = []
	var maxs: Array = []
	for i in range(SLICES):
		mins.append(Vector3(INF, INF, INF))
		maxs.append(Vector3(-INF, -INF, -INF))
	for v in verts:
		var i: int = clampi(int((v[axis] - lo) / span * SLICES), 0, SLICES - 1)
		counts[i] += 1
		mins[i] = (mins[i] as Vector3).min(v)
		maxs[i] = (maxs[i] as Vector3).max(v)
	var line := "[shark] %s profile  " % name
	for i in range(SLICES):
		var s: float = 0.0
		if counts[i] > 0:
			var d: Vector3 = (maxs[i] as Vector3) - (mins[i] as Vector3)
			# cross-section = the two axes that are NOT the slicing axis
			var a: float = d[(axis + 1) % 3]
			var b: float = d[(axis + 2) % 3]
			s = maxf(a, b)
		line += "%.2f/%d " % [s, counts[i]]
	print(line)

## Centreline arc length: per slice along the longest axis, take the centroid; the polyline
## through the centroids is the animal's spine. For a straight mesh this equals the AABB
## edge; for this crescent it is substantially more, and it is the number that answers
## "how long is the shark".
func _arc(verts: PackedVector3Array, box: AABB) -> void:
	var axis: int = 0
	for a in range(3):
		if box.size[a] > box.size[axis]:
			axis = a
	var lo: float = box.position[axis]
	var span: float = maxf(box.size[axis], 0.0001)
	var n: int = 24
	var sums: Array = []
	var cnt := PackedInt32Array()
	sums.resize(n)
	cnt.resize(n)
	for i in range(n):
		sums[i] = Vector3.ZERO
	for v in verts:
		var i: int = clampi(int((v[axis] - lo) / span * n), 0, n - 1)
		sums[i] = (sums[i] as Vector3) + v
		cnt[i] += 1
	var pts: Array = []
	for i in range(n):
		if cnt[i] > 0:
			pts.append((sums[i] as Vector3) / float(cnt[i]))
	var arc: float = 0.0
	for i in range(1, pts.size()):
		arc += (pts[i] as Vector3).distance_to(pts[i - 1] as Vector3)
	print("[shark] centreline along %s: %d nodes, arc=%.3f (AABB edge %.3f)"
		% [["X", "Y", "Z"][axis], pts.size(), arc, box.size[axis]])
	print("[shark] centreline head end=%s tail end=%s"
		% [str((pts[0] as Vector3).snappedf(0.01)), str((pts[pts.size() - 1] as Vector3).snappedf(0.01))])

func _verts(root: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var xf: Transform3D = mi.transform   # models here are flat under the root
		for s in range(mi.mesh.get_surface_count()):
			var arr: Array = mi.mesh.surface_get_arrays(s)
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				out.append(xf * v)
	return out

func _mesh_count(root: Node) -> int:
	return root.find_children("*", "MeshInstance3D", true, false).size()

func _bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var w: AABB = mi.transform * mi.get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	return acc
