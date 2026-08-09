extends Node
## SIT SCRATCH — where are the four paws, in millimetres, when this cat sits?
##
##   godot --headless --path . res://tests/SitScratch.tscn
##
## An INSTRUMENT, not a gate. The owner reports the seated cat pitched nose-up: forepaws an
## inch off the deck, hind paws an inch through it. CatJointProbe's `paw_below_deck_max_mm`
## only ever reported the WORST-SUNK of the four over a whole scenario — one number, one
## sign, no per-limb breakdown — so a body that is +25 mm at one end and -25 mm at the other
## is exactly the shape it cannot describe. This prints all four, signed, both from the
## STATIC pose library (no runtime layers at all) and from the LIVE animal driven into SIT.
##
## Sign convention throughout: +mm = paw ABOVE the deck (floating), -mm = paw BELOW the deck
## (sunk). The deck is the cat node's own origin, which `_reseat` puts on the ray hit.

const DT: float = 1.0 / 60.0
const STAGE := Vector3(3.0, 18.0, -3.0)
const PAWS := {"lf": "L_Hand", "rf": "R_Hand", "lh": "L_Foot", "rh": "R_Foot"}
## The paw BONE is not the sole of the paw. Every height here is quoted against the bone,
## and against the same bone in the `stand` pose, so the mesh offset cancels in the delta.
const POSES := ["stand", "walk", "sit", "sit_pre", "sit_deep", "rise", "groom", "lean"]

var _main: Node3D
var _cat: Node3D
var _player: Node3D
var _skel: Skeleton3D
var _rig = null

func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 9000 or waited < 180:
		await get_tree().physics_frame
		waited += 1
	GameClock.force_phase(GameClock.Phase.DAY)
	_player = get_tree().get_first_node_in_group("player")
	_cat = get_tree().get_first_node_in_group("ship_cat")
	if _player == null or _cat == null:
		print("FAIL  found a player and a cat")
		get_tree().quit(1)
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	for c in _cat.get_children():
		if c is Interactable:
			(c as Interactable).emit_signal("interacted", "SAY HELLO")
			break
	await get_tree().physics_frame
	_rig = _cat.get("_rig")
	for n in (_cat.get("_host") as Node3D).find_children("*", "Skeleton3D", true, false):
		_skel = n
		break
	if _rig == null or _skel == null:
		print("FAIL  the cat carries a rig and a skeleton")
		get_tree().quit(1)
		return
	_cat.set_process(false)
	_cat.global_position = STAGE
	_cat.call("_reseat")
	_cat.rotation.y = 0.0
	for i in range(10):
		await get_tree().physics_frame

	print("")
	print("=== A. STATIC POSE LIBRARY — paw height vs the deck, mm (+ = floating, - = sunk)")
	print("    (the pose written straight to the skeleton; no gait, bob, breath or stabiliser)")
	print("  %-10s %9s %9s %9s %9s   %9s %9s" % ["pose", "lf", "rf", "lh", "rh",
		"fore-hind", "pitch deg"])
	var poses: Dictionary = _rig.get("_poses")
	var base := {}
	for nm in POSES:
		if not poses.has(nm):
			print("  %-10s  (NOT IN THE LIBRARY)" % nm)
			continue
		var h: Dictionary = _apply_static(poses[nm])
		if nm == "stand":
			base = h.duplicate()
		var row := "  %-10s" % nm
		for k in ["lf", "rf", "lh", "rh"]:
			row += " %9.1f" % (h[k] - float(base.get(k, 0.0)))
		var fore: float = ((h["lf"] - float(base.get("lf", 0.0)))
			+ (h["rf"] - float(base.get("rf", 0.0)))) * 0.5
		var hind: float = ((h["lh"] - float(base.get("lh", 0.0)))
			+ (h["rh"] - float(base.get("rh", 0.0)))) * 0.5
		# The nose-up pitch the owner describes, expressed as an angle over the wheelbase.
		var wb: float = _wheelbase()
		row += "   %9.1f %9.2f" % [fore - hind, rad_to_deg(atan2((fore - hind) * 0.001, wb))]
		# What the BAKE thinks it achieved, straight off the pose entry — so "the IK reached"
		# is read out of the solver rather than inferred from the paw heights it produced.
		var pe = (poses[nm] as Dictionary).get("paw_err_mm", null)
		if pe != null:
			row += "   ik_resid_mm %s" % str((pe as Dictionary).values().map(
				func(v): return snappedf(float(v), 0.1)))
		print(row)
	print("  (all four columns are RELATIVE to the same paw in `stand`, so the paw-bone's own")
	print("   height inside the mesh cancels; `stand` itself is the absolute baseline below)")
	var st: Dictionary = _apply_static(poses["stand"])
	print("  stand absolute: lf %.1f  rf %.1f  lh %.1f  rh %.1f   wheelbase %.3f m"
		% [st["lf"], st["rf"], st["lh"], st["rh"], _wheelbase()])

	print("")
	print("=== A2. WHAT THE HIND CANNOT REACH — the sit re-baked over a grid")
	print("    (the hind paw_shift is authored at +0.13 m FORWARD under the dropped pelvis;")
	print("     the right hind chain is Thigh 0.086 + Calf 0.106 m, so ask what it can pay)")
	print("  %-22s %8s %8s %8s %8s  %s" % ["variant", "lf", "rf", "lh", "rh", "ik_resid_mm"])
	for hs in [0.13, 0.09, 0.05, 0.0]:
		for drop in [0.118, 0.09]:
			var v: Dictionary = _rig.call("_bake", {
				"Hip": [[3, 0.58]],
				"NeckTwist01": [[0, -0.06]], "Head": [[0, 0.04]],
			}, drop, {"lf": Vector3(-0.06, 0, 0), "rf": Vector3(-0.06, 0, 0),
				"lh": Vector3(hs, 0, 0), "rh": Vector3(hs, 0, 0)}, 0.7)
			var h: Dictionary = _apply_static(v)
			var r := "  hind%+.3f drop%.3f " % [hs, drop]
			for k in ["lf", "rf", "lh", "rh"]:
				r += " %8.1f" % (h[k] - float(base.get(k, 0.0)))
			r += "  %s  trim %s" % [str((v["paw_err_mm"] as Dictionary).values().map(
				func(x): return snappedf(float(x), 0.1))), str(v.get("trim", []))]
			print(r)

	print("")
	print("=== B. LIVE — the shipped animal driven into SIT, all four paws per frame")
	_skel.reset_bone_poses()
	_skel.force_update_all_bone_transforms()
	_cat.global_position = STAGE
	_cat.call("_reseat")
	var deck: float = _cat.global_position.y
	var acc := {}
	for k in PAWS:
		acc[k] = []
	var last_pose := ""
	var states: Dictionary = {}
	for f in range(int(9.0 / DT)):
		_hold()
		_player.global_position = STAGE + Vector3(1.5, 0.1, 0.0)
		_cat.call("_process", DT)
		_skel.force_update_all_bone_transforms()
		var sname := str(_cat.get("_state"))
		states[sname] = int(states.get(sname, 0)) + 1
		if f > int(6.0 / DT):
			for k in PAWS:
				(acc[k] as Array).append(
					(_bone_w(_skel.find_bone(PAWS[k])).origin.y - deck) * 1000.0)
			last_pose = str(_rig.get("_target"))
		await get_tree().physics_frame
	print("  state histogram (State enum ordinal -> frames): %s" % str(states))
	print("  rig target pose at the end: %s" % last_pose)
	print("  %-6s %9s %9s %9s" % ["paw", "min mm", "mean mm", "max mm"])
	var mean := {}
	for k in ["lf", "rf", "lh", "rh"]:
		var a: Array = acc[k]
		var lo: float = 1e9
		var hi: float = -1e9
		var s: float = 0.0
		for v in a:
			lo = minf(lo, v)
			hi = maxf(hi, v)
			s += v
		mean[k] = s / maxf(float(a.size()), 1.0)
		print("  %-6s %9.1f %9.1f %9.1f" % [k, lo, mean[k], hi])
	var fore2: float = (float(mean["lf"]) + float(mean["rf"])) * 0.5
	var hind2: float = (float(mean["lh"]) + float(mean["rh"])) * 0.5
	# WHERE THE LIVE ANIMAL DISAGREES WITH ITS OWN POSE. Static and live wear the same `sit`;
	# any gap between them is a runtime layer, and naming the bone tells you which.
	var sit_pose: Dictionary = poses["sit"]
	var fin: Dictionary = _rig.get("_fin")
	print("  hip translation: pose %s  drawn %s  delta %.1f mm"
		% [str((sit_pose["hip_t"] as Vector3).snappedf(0.0001)),
			str((_rig.get("_out_hip") as Vector3).snappedf(0.0001)),
			((_rig.get("_out_hip") as Vector3) - (sit_pose["hip_t"] as Vector3)).length() * 1000.0])
	print("  %-16s %10s" % ["bone", "live-vs-pose deg"])
	for bn in ["Hip", "Spine01", "Spine02", "L_Clavicle", "R_Clavicle", "L_Upperarm",
			"R_Upperarm", "L_Forearm", "R_Forearm", "L_Thigh", "R_Thigh", "L_Calf", "R_Calf"]:
		var b: int = _skel.find_bone(bn)
		if b < 0 or not fin.has(b):
			continue
		var want: Quaternion = (sit_pose["q"] as Dictionary).get(b, Quaternion.IDENTITY)
		# ...and split that gap into the two things it can be: the runtime ROM clamp biting a
		# pose the bake thought was legal, or another LAYER writing the bone.
		var clamped: Quaternion = _rig.call("_clamp_joint", b, want)
		var layer: bool = (_rig.get("_out") as Dictionary).has(b)
		print("  %-16s %10.2f   rom_bites %6.2f  layer_wrote %s"
			% [bn, rad_to_deg((fin[b] as Quaternion).angle_to(want)),
				rad_to_deg(clamped.angle_to(want)), str(layer)])
	print("  fore mean %.1f mm, hind mean %.1f mm, fore-hind %.1f mm  (nose-up pitch %.2f deg)"
		% [fore2, hind2, fore2 - hind2,
			rad_to_deg(atan2((fore2 - hind2) * 0.001, _wheelbase()))])
	print("---")
	print("FAILURES: 0")
	get_tree().quit(0)

func _hold() -> void:
	_cat.set("_hunt_cd", 999.0)
	_cat.set("_zoom_cd", 999.0)
	_cat.set("_play_cd", 999.0)
	_cat.set("_chatter_cd", 999.0)
	_cat.set("_idle_cd", 999.0)
	_cat.set("_roam_cd", 999.0)
	_cat.set("_wash_cd", 999.0)

func _bone_w(b: int) -> Transform3D:
	return _skel.global_transform * _skel.get_bone_global_pose(b)

## Fore-aft distance between the fore and hind paw anchors in the REST pose — the lever the
## nose-up pitch is measured over. Derived, never typed.
func _wheelbase() -> float:
	_skel.reset_bone_poses()
	_skel.force_update_all_bone_transforms()
	var lf: Vector3 = _bone_w(_skel.find_bone("L_Hand")).origin
	var lh: Vector3 = _bone_w(_skel.find_bone("L_Foot")).origin
	return Vector2(lf.x - lh.x, lf.z - lh.z).length()

## Write a pose library entry straight onto the skeleton and read the four paws back.
func _apply_static(pose: Dictionary) -> Dictionary:
	_skel.reset_bone_poses()
	var hip: int = int(_rig.get("_hip"))
	var rest_t: Dictionary = _rig.get("_rest_t")
	for i in (pose["q"] as Dictionary):
		_skel.set_bone_pose_rotation(int(i), pose["q"][i])
	if hip >= 0:
		_skel.set_bone_pose_position(hip,
			_rig.call("_hip_pose_pos", (pose["hip_t"] as Vector3) - (rest_t[hip] as Vector3)))
	_skel.force_update_all_bone_transforms()
	var deck: float = _cat.global_position.y
	var out := {}
	for k in PAWS:
		out[k] = (_bone_w(_skel.find_bone(PAWS[k])).origin.y - deck) * 1000.0
	return out
