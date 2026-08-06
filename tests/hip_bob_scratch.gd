extends Node
## SCRATCH — sweep the head stabiliser's strength/sign and report how much the head moves
## RELATIVE TO THE BODY at each setting. The right value is the one that makes a walking
## and galloping cat's head quietest; the wrong SIGN doubles the trunk's motion instead of
## cancelling it, which is indistinguishable from "it does nothing" if you only read code.

const RIG := preload("res://scripts/world/cat_rig.gd")
const GLB := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"

func _ready() -> void:
	var root: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(root)
	var sk: Skeleton3D = null
	for n in root.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	var hi: int = sk.find_bone("Head")
	print("[stab] %-7s %14s %14s" % ["HEAD_STAB", "walk deg/s p99", "run deg/s p99"])
	for stab in [0.0, 0.35, 0.72, 1.0, -0.72]:
		RIG.HEAD_STAB = stab
		var out: Array[float] = []
		for speed_pose in [[1.55, "walk"], [4.4, "run"]]:
			var rig = RIG.new(sk, "")
			var speed: float = float(speed_pose[0])
			rig.set_pose(String(speed_pose[1]), 10.0)
			var spd: Array[float] = []
			var prev := Vector3.ZERO
			for i in range(900):
				rig.tick(1.0 / 60.0, speed, speed / 60.0)
				sk.force_update_all_bone_transforms()
				# Head forward in the SKELETON's own frame — the skeleton node never
				# rotates here, so this is head-relative-to-body by construction.
				var f: Vector3 = (sk.get_bone_global_pose(hi).basis * Vector3(0, 1, 0)).normalized()
				if i > 150 and prev != Vector3.ZERO:
					spd.append(rad_to_deg(f.angle_to(prev)) * 60.0)
				prev = f
			spd.sort()
			out.append(spd[int(float(spd.size()) * 0.99)])
		print("[stab] %-7.2f %14.1f %14.1f" % [stab, out[0], out[1]])
	get_tree().quit()
