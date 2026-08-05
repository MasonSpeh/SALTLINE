extends Node
## SCRATCH 3 — per-frame joint continuity of the BARE rig at a constant walk and run.
## If the spikes live here they are solve-internal; if not, the live world feeds them.

const RIG := preload("res://scripts/world/cat_rig.gd")
const GLB := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"

func _ready() -> void:
	var root: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(root)
	var sk: Skeleton3D = null
	for n in root.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	for speed_pose in [[1.55, "walk"], [4.4, "run"], [0.62, "stalk"]]:
		var rig = RIG.new(sk, "")
		var speed: float = float(speed_pose[0])
		rig.set_pose(String(speed_pose[1]), 10.0)
		var prev := {}
		var worst: float = 0.0
		var worst_bone: String = ""
		var worst_i: int = -1
		var worst_ph: float = 0.0
		for i in range(900):
			rig.tick(1.0 / 60.0, speed, speed / 60.0)
			for b in range(sk.get_bone_count()):
				var q: Quaternion = sk.get_bone_pose_rotation(b)
				if prev.has(b) and i > 120:
					var st: float = (prev[b] as Quaternion).angle_to(q)
					if st > worst:
						worst = st
						worst_bone = sk.get_bone_name(b)
						worst_i = i
						worst_ph = float(rig.get("_phase"))
				prev[b] = q
		print("[s3] %-5s worst step %.4f rad/frame at %s (frame %d, phase %.3f)"
			% [String(speed_pose[1]), worst, worst_bone, worst_i, worst_ph])
	get_tree().quit()

## Quick geometry dump — run by editing _ready to call this if needed.
