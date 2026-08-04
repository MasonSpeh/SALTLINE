extends Node
## Which link drops the pelvis? Dump every stage of the hip chain off the LIVE cat.
func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(8.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	var host: Node3D = cat.get("_host")
	var rig = cat.get("_rig")
	var skel: Skeleton3D = null
	for n in host.find_children("*", "Skeleton3D", true, false):
		skel = n
		break
	var model: Node3D = host.get_child(0)
	print("[chain] cat node y      = %.3f" % cat.global_position.y)
	print("[chain] host pos        = %s" % str(host.position))
	print("[chain] model pos       = %s  rot=%s  scale=%s" % [str(model.position),
		str(model.rotation_degrees.snappedf(0.1)), str(model.scale.snappedf(0.001))])
	var hip: int = skel.find_bone("Hip")
	print("[chain] hip REST local  = %s" % str(skel.get_bone_rest(hip).origin))
	print("[chain] hip POSE local  = %s" % str(skel.get_bone_pose_position(hip)))
	print("[chain] rig _rest_t hip = %s" % str(rig.get("_rest_t")[hip]))
	print("[chain] rig _cur_hip    = %s" % str(rig.get("_cur_hip")))
	print("[chain] rig target      = %s" % str(rig.call("target")))
	var wp = rig.get("_poses")["walk"]["hip_t"]
	var sp = rig.get("_poses")["sit"]["hip_t"]
	var gp = rig.get("_poses")["groom"]["hip_t"]
	print("[chain] pose hip_t walk=%s sit=%s groom=%s" % [str(wp), str(sp), str(gp)])
	var pelv: int = skel.find_bone("Pelvis")
	print("[chain] pelvis world y  = %.3f (deck 18.0)" %
		(skel.global_transform * skel.get_bone_global_pose(pelv)).origin.y)
	# and the drawn box
	for m in host.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		print("[chain] mesh get_aabb   = %s" % str(mi.get_aabb()))
		print("[chain] custom_aabb     = %s" % str(mi.custom_aabb))
		var wb: AABB = mi.global_transform * mi.get_aabb()
		print("[chain] drawn world box y = %.3f .. %.3f" % [wb.position.y, wb.end.y])
		break
	# NOW BEFRIEND AND WALK IT, and watch the same numbers move — or not.
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	for c in cat.get_children():
		if c is Interactable:
			(c as Interactable).emit_signal("interacted", "SAY HELLO")
	player.global_position = Vector3(-14.5, 18.1, 11.5)
	var pelv2: int = skel.find_bone("Pelvis")
	var head2: int = skel.find_bone("Head")
	for i in range(240):
		await get_tree().physics_frame
		if i % 40 == 0:
			var pw: Vector3 = (skel.global_transform * skel.get_bone_global_pose(pelv2)).origin
			var hw: Vector3 = (skel.global_transform * skel.get_bone_global_pose(head2)).origin
			var d2: Vector3 = hw - pw
			print("[walkchk] i=%3d pose=%-6s cur_hip=%s pelvY=%.3f pitch=%+.0f" % [
				i, str(cat.get("_pose")), str((rig.get("_cur_hip") as Vector3).snappedf(0.001)),
				pw.y, rad_to_deg(asin(clampf(d2.normalized().y, -1, 1)))])
	# THE DECOMPOSITION: who carries the rotation?
	print("[decomp] cat.rotation   = %s" % str((cat.get("rotation") as Vector3)))
	print("[decomp] _body.rotation = %s" % str(((cat.get("_body") as Node3D).rotation)))
	print("[decomp] host.rotation  = %s" % str(host.rotation))
	print("[decomp] model.rotation = %s" % str(model.rotation_degrees.snappedf(0.1)))
	print("[decomp] skel node rot  = %s" % str((skel as Node3D).rotation_degrees.snappedf(0.1)))
	for bname in ["Root", "Hip", "Spine01", "Spine02", "NeckTwist01"]:
		var bi: int = skel.find_bone(bname)
		if bi < 0:
			continue
		var restq: Quaternion = skel.get_bone_rest(bi).basis.get_rotation_quaternion()
		var poseq: Quaternion = skel.get_bone_pose_rotation(bi)
		print("[decomp] bone %-12s delta from rest = %.1f deg" % [bname,
			rad_to_deg(restq.angle_to(poseq))])
	get_tree().quit()
