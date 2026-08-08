extends Node
## SCRATCH — WHERE IS THE NOSE ACTUALLY POINTING, measured off the MESH.
##
## Nine owner reports and three "fixed" constants, because every instrument in this repo
## defines the head's forward FROM THE SKELETON — and the skeleton is the thing being
## corrected, so each new constant re-zeroed its own gate (the s34 tautology, four times).
## This one takes the nose direction from the GEOMETRY: the centroid of the vertices whose
## dominant bone is Head, expressed in the Head bone's own local frame, computed ONCE off
## the untouched GLB. That vector is a fact about the model. Transform it by whatever the
## live bone ends up doing and you have the drawn nose, with no constant of ours in it.
##
## Then sweep HEAD_MESH_YAW and print the resulting world yaw. The zero of that curve is
## the answer, and its slope says whether the correction has the unit gain its algebra
## claims (if it does not, something downstream is absorbing it and the constant is the
## wrong lever entirely).

const RIG := preload("res://scripts/world/cat_rig.gd")
const GLB := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"
const BODY_FWD := Vector3(1, 0, 0)   ## nose-to-tail axis, per BoneDump's AABB

func _ready() -> void:
	var root: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(root)
	var sk: Skeleton3D = null
	var mi: MeshInstance3D = null
	for n in root.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mi = n
		break
	var head: int = sk.find_bone("Head")
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()

	# 1. THE NOSE, FROM THE MESH. Vertices whose heaviest weight is the Head bone.
	var mdt := MeshDataTool.new()
	var arr: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per: int = 4 if bones.size() == verts.size() * 4 else 8
	var acc := Vector3.ZERO
	var cnt: int = 0
	for v in range(verts.size()):
		var best_b: int = -1
		var best_w: float = 0.0
		for k in range(per):
			var w: float = weights[v * per + k]
			if w > best_w:
				best_w = w
				best_b = bones[v * per + k]
		if best_b == head:
			acc += verts[v]
			cnt += 1
	if cnt == 0:
		print("[nose] no vertices weighted to Head — cannot measure")
		get_tree().quit(1)
		return
	var centroid: Vector3 = acc / float(cnt)
	var head_rest: Transform3D = sk.get_bone_global_pose(head)
	# THE FACING AXIS IS THE HEAD'S LONG HORIZONTAL AXIS, not the joint-to-centroid ray.
	# The first cut used that ray and it is nearly VERTICAL — a cat's skull sits above the
	# atlas joint, so the centroid is 73 mm up and only 61 mm forward, and the yaw of a
	# near-vertical vector is numerically meaningless. A muzzle is the longest thing about a
	# head in the horizontal plane, so: flatten the head vertices, take their principal axis
	# by power iteration on the 2x2 horizontal covariance, and sign it away from the neck.
	# That is a property of the MODEL, measured once, with no constant of ours in it.
	var neck: int = sk.find_bone("NeckTwist01")
	var neck_p: Vector3 = sk.get_bone_global_pose(neck).origin if neck >= 0 else Vector3.ZERO
	# THE MUZZLE IS THE PART OF THE HEAD FARTHEST FROM THE NECK, and that definition is the
	# only one here that cannot be fooled by ears. The previous cut took the head's principal
	# horizontal axis, which came out 84 degrees off the neck->head line — because a cat's
	# EARS are weighted to the head and spread wider than the skull is long, so the principal
	# axis was ear-to-ear, i.e. exactly the across direction, i.e. 90 degrees wrong. Distance
	# from the neck has no such failure mode: the back of the skull is near the neck, the ears
	# are above it, and the only thing far from it in the horizontal plane is the muzzle.
	var far: Array = []
	for v in range(verts.size()):
		var best_b2: int = -1
		var best_w2: float = 0.0
		for k in range(per):
			var w2: float = weights[v * per + k]
			if w2 > best_w2:
				best_w2 = w2
				best_b2 = bones[v * per + k]
		if best_b2 != head:
			continue
		var d: Vector3 = verts[v] - neck_p
		d.y = 0.0
		far.append([d.length(), d])
	far.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	var keep: int = maxi(int(float(far.size()) * 0.05), 1)
	var axis := Vector3.ZERO
	for i in range(keep):
		axis += (far[i][1] as Vector3).normalized()
	axis = axis.normalized()
	var away: Vector3 = centroid - neck_p
	away.y = 0.0
	print("[nose] %d head verts, muzzle axis (top %d by neck distance) %s, neck->head %s, dot %.3f"
		% [cnt, keep, str(axis.snappedf(0.001)), str(away.normalized().snappedf(0.001)),
			axis.dot(away.normalized())])
	var nose_local: Vector3 = (head_rest.basis.inverse() * axis).normalized()

	# 2. SWEEP. Rebuild the rig at each candidate and read the drawn nose while walking.
	print("[nose] %-10s %14s" % ["HEAD_YAW", "nose yaw vs +X"])
	for cand in [-0.3325, -0.36, -0.40, -0.44, -0.48]:
		RIG.HEAD_MESH_YAW = cand
		var rig = RIG.new(sk, "")
		rig.set_pose("walk", 10.0)
		for i in range(240):
			rig.tick(1.0 / 60.0, 1.55, 1.55 / 60.0)
		sk.force_update_all_bone_transforms()
		var ht: Transform3D = sk.get_bone_global_pose(head)
		var nose_w: Vector3 = (ht.basis * nose_local).normalized()
		var yaw: float = rad_to_deg(atan2(nose_w.z, nose_w.x))   # 0 = straight along +X
		print("[nose] %-10.3f %14.2f" % [cand, yaw])
	print("[nose] the candidate whose yaw is ~0 is the one that points the drawn nose")
	print("[nose] down the body axis. A flat column means the constant is the WRONG LEVER.")
	get_tree().quit()
