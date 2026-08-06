extends Node
## SCRATCH — does the HEAD_MAX_RATE ceiling actually bound the drawn head?
##
## CatJointProbe measures p99 head speeds of 400-800 deg/s against a cap whose algebra is
## a bounded pursuit (drawn step <= HEAD_MAX_RATE * dt, every frame, by construction).
## Both cannot be true, so one assumption is wrong somewhere between the tick and the
## probe — this strips the question to a bare rig, no world, no birds, no state machine:
## scripted glance retargets in the exact pattern that produces the weight-ramp sweep
## (acquire at invisible weight -> yaw snaps -> weight ramps), drawn head step measured
## off the skeleton every tick, worst frame printed WITH the tick that produced it.

const RIG := preload("res://scripts/world/cat_rig.gd")
const GLB := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"
const DT: float = 1.0 / 60.0

func _ready() -> void:
	var root: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(root)
	var sk: Skeleton3D = null
	for n in root.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	var hi: int = sk.find_bone("Head")
	var rig = RIG.new(sk, "")
	rig.set_pose("sit", 7.0)
	var prev := Vector3.ZERO
	var worst: float = 0.0
	var worst_i: int = -1
	var over: int = 0
	for i in range(1200):
		# A hostile glance schedule: every 0.9 s a new target on the OTHER side, asked for
		# at full weight just after the old look has decayed to invisibility — the exact
		# re-acquire-then-ramp pattern the game's idle attention produces.
		if i % 54 == 0:
			var side: float = 1.0 if (i / 54) % 2 == 0 else -1.0
			rig.look(side * 1.0, 0.3 * side, 1.0)
		rig.tick(DT, 0.0, 0.0)
		sk.force_update_all_bone_transforms()
		var f: Vector3 = (sk.get_bone_global_pose(hi).basis * Vector3(0, 1, 0)).normalized()
		if i > 5 and prev != Vector3.ZERO:
			var step_deg: float = rad_to_deg(f.angle_to(prev))
			if step_deg > worst:
				worst = step_deg
				worst_i = i
			if step_deg > rad_to_deg(3.3 * DT) + 0.05:
				over += 1
		prev = f
	print("[head_rate] worst drawn step %.3f deg/frame (=%.0f deg/s) at tick %d; cap %.3f deg/frame; frames over cap: %d / 1194"
		% [worst, worst * 60.0, worst_i, rad_to_deg(3.3 * DT), over])
	get_tree().quit()
