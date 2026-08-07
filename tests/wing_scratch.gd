extends Node3D
## SCRATCH — ARE THE GULL'S OVERLAY WINGS LATERAL, OR ARE THEY A FIN?
##
## s46 shipped geometry wings whose only frames are from a FLUSH, where a raised wing is
## correct but magnified reads as a triangular sail off the bird's back. A still cannot
## separate "correct wing at its worst instant" from "wrong axis", and the rotation algebra
## is exactly the kind of thing this repo has been wrong about while being sure (the s37
## axis atlas exists because two rounds of poses were authored on guessed signs).
##
## So: build the real wings on the real model and read the panels' WORLD geometry back.
## A wing spans ACROSS the bird — the tip should be far out on the lateral axis and near
## zero fore-aft. A fin points UP. The numbers cannot be argued with either way.

const ANIM := preload("res://scripts/world/creature_anim.gd")
const GULL := "res://assets/models/fauna/herring_gull/herring_gull.glb"

func _ready() -> void:
	var host := Node3D.new()
	add_child(host)
	var gen: Dictionary = ANIM.attach(host, GULL, 0.55, ANIM.Mode.WING, 0.06, 2.0)
	if gen.is_empty():
		print("[wing] the gull asset did not load — nothing to measure")
		get_tree().quit(1)
		return
	var model: Node3D = gen["model"]
	await get_tree().process_frame
	# Body bounds first, so "far out" and "long" have a scale to be judged against.
	var acc := AABB()
	var first := true
	var inv: Transform3D = model.global_transform.affine_inverse()
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var src := n as MeshInstance3D
		if src.mesh == null:
			continue
		var b: AABB = (inv * src.global_transform) * src.get_aabb()
		acc = b if first else acc.merge(b)
		first = false
	print("[wing] body bounds (model-local): size %s" % str(acc.size.snappedf(0.001)))
	var wings = BloomFauna.GullWings.new()
	wings.build(model, Color(0.78, 0.82, 0.84))
	wings.shown(true)
	# THREE REAL FLIGHT STATES, not one. The first cut called drive(0.016, false, false) —
	# and `false` coerces to airtime 0.0, which is inside HOLD_S, so it measured the TAKEOFF
	# RAISE and nothing else. That is precisely the pose the owner-facing frames already
	# showed; measuring it again proved nothing. Cruise is where the "is it a wing" question
	# actually lives.
	for state in [["takeoff", 0.0, false], ["cruise", 3.0, false], ["glide", 3.0, true]]:
		# Settle the eased dihedral rather than reading its first frame — `base` chases its
		# target at 1-exp(-10*dt), so one call is 15% of the way there.
		for _i in range(180):
			wings.drive(1.0 / 60.0, float(state[1]), bool(state[2]))
		await get_tree().process_frame
		for label_pivot in [["L", wings.l], ["R", wings.r]]:
			var pivot: Node3D = label_pivot[1]
			if pivot == null:
				continue
			var mi: MeshInstance3D = null
			for c in pivot.get_children():
				if c is MeshInstance3D:
					mi = c
					break
			var box: AABB = mi.get_aabb()
			var to_model: Transform3D = model.global_transform.affine_inverse() \
				* mi.global_transform
			var lo: Vector3 = to_model * box.position
			var hi: Vector3 = to_model * (box.position + box.size)
			var ext: Vector3 = (hi - lo).abs()
			print("[wing] %-8s %s  lateral %.3f  vertical %.3f  fore-aft %.3f  (dihedral %+.1f deg)"
				% [state[0], label_pivot[0], ext.x, ext.y, ext.z,
					rad_to_deg(atan2(ext.y, ext.x))])
	print("[wing] VERDICT: a wing has its LARGEST extent lateral and its smallest vertical.")
	print("[wing] A fin has it the other way round. Body half-width is %.3f." % (acc.size.x * 0.5))
	get_tree().quit()
