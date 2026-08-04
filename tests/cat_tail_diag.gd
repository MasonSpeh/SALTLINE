extends Node
## WHAT IS THE CAT'S TAIL ACTUALLY SKINNED TO? — flaw 5's first honest question.
##
## The tail has no bones: Tripo's template ends at the pelvis, so the 41-bone skeleton has
## nothing behind the hip and the tail is baked into the one skinned mesh. Tail carriage is a
## large part of cat body language — up on greeting, quiver at delight, low swish at
## annoyance — and none of it is available.
##
## Before reaching for the expensive routes (rebuild the skin weights offline, or at load, or
## bend the tail in a vertex shader), find out the cheap thing: WHICH bones the tail vertices
## are weighted to, and how many other vertices those bones own. If the tail turns out to
## dominate some bone that nothing else depends on, it can be driven directly for the cost of
## one more layer in cat_rig — and the whole problem evaporates.
##
##   godot --headless --path . res://tests/CatTailDiag.tscn

const GLB := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"

func _ready() -> void:
	var root: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(root)
	var sk: Skeleton3D = null
	for n in root.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	var mi: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mi = n
		break
	if sk == null or mi == null:
		print("no skeleton / no mesh")
		get_tree().quit(1)
		return
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var mesh: Mesh = mi.mesh
	print("surfaces: %d, bones: %d" % [mesh.get_surface_count(), sk.get_bone_count()])

	# The mesh's own frame: tests/BoneDump reports the AABB as 1.0 x 0.566 x 0.265, so X is
	# nose-to-tail. Which END of X is the tail is settled by the HEAD bone's position, not
	# assumed — the model could be authored either way round.
	var head_x: float = sk.get_bone_global_pose(sk.find_bone("Head")).origin.x
	var hip_x: float = sk.get_bone_global_pose(sk.find_bone("Hip")).origin.x
	var tail_sign: float = -1.0 if head_x > hip_x else 1.0
	print("Head x %.3f, Hip x %.3f -> the tail runs toward %+.0f X" % [head_x, hip_x, tail_sign])

	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if verts.is_empty() or bones.is_empty():
		print("mesh carries no skin arrays — nothing to reweight")
		get_tree().quit()
		return
	var per: int = bones.size() / verts.size()
	print("vertices: %d, %d bone influences each" % [verts.size(), per])

	# WHERE EACH BONE'S GEOMETRY ACTUALLY IS — the question that settles it. Assign every vertex
	# to whichever bone has the largest weight on it, and report that set's centroid and extent.
	# A bone whose vertices sit well behind the hip and clear of the deck IS the tail, whatever
	# the auto-rig chose to call it, and it can be driven directly.
	#
	# The first cut of this asked "which bones carry weight behind the hip" and swept in 40% of
	# the mesh — the whole hindquarters and both hind legs — so every foot and toe bone came
	# back at 100% and the answer was unreadable. Dominance and a centroid say it in one line.
	var owner_n := {}
	var owner_sum := {}
	var owner_lo := {}
	var owner_hi := {}
	for i in range(verts.size()):
		var best_b: int = -1
		var best_w: float = -1.0
		for j in range(per):
			var w: float = weights[i * per + j]
			if w > best_w:
				best_w = w
				best_b = bones[i * per + j]
		if best_b < 0:
			continue
		owner_n[best_b] = int(owner_n.get(best_b, 0)) + 1
		owner_sum[best_b] = (owner_sum.get(best_b, Vector3.ZERO) as Vector3) + verts[i]
		owner_lo[best_b] = (owner_lo.get(best_b, verts[i]) as Vector3).min(verts[i])
		owner_hi[best_b] = (owner_hi.get(best_b, verts[i]) as Vector3).max(verts[i])
	print("\n%-20s %7s %26s %10s %8s" % ["bone", "verts", "centroid (x,y,z)", "x behind hip", "x span"])
	var keys: Array = owner_n.keys()
	keys.sort_custom(func(a, b): return int(owner_n[a]) > int(owner_n[b]))
	for b in keys:
		var n: int = int(owner_n[b])
		if n < 400:
			continue
		var c: Vector3 = (owner_sum[b] as Vector3) / float(n)
		var behind: float = (c.x - hip_x) * tail_sign
		var span: float = (owner_hi[b] as Vector3).x - (owner_lo[b] as Vector3).x
		print("%-20s %7d %26s %10.3f %8.3f"
			% [sk.get_bone_name(int(b)), n, str(c.snappedf(0.001)), behind, span])
	print("\nThe TAIL is whichever bone's vertices sit furthest behind the hip with a long x span")
	print("and few of them — if one exists, flaw 5 costs one layer in cat_rig instead of a re-rig.")
	get_tree().quit()
