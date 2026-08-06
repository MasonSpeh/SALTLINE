extends Node
## CAT JOINT PROBE — does the animal move like a BODY, or like a pile of bones that happen
## to be connected?
##
## WHY THIS EXISTS, AND WHY CatReviewProbE DID NOT CATCH ANY OF IT. The s40 gates measure
## foot-slide, phase lock, continuity and dt-equivalence: motion QUALITY of things that
## were already anatomically legal. The owner watched the s40 review pack and found, in
## seconds, four defects every one of those gates is blind to by construction:
##   "its limbs are turning against its joints"      — no gate looked at joint DIRECTION;
##   "going in and out the body"                     — no gate looked at where a paw IS;
##   "his arms go so wide when he sits"              — no gate looked at LATERAL splay;
##   "his knees dont bend, legs move like peg legs"  — no gate looked at how much a joint
##                                                     actually ARTICULATES.
## A smooth, foot-locked, phase-locked, perfectly continuous animation of an impossible
## animal passes all of s40's gates. This file measures the anatomy instead.
##
##   godot --headless --path . res://tests/CatJointProbe.tscn
##
## Everything is measured off the DRAWN skeleton of the SHIPPED ship_cat driven through
## its real behaviour states — never a bespoke rig probe, never the pose library directly.

const OUT_DIR := "res://tests/out/cat_review"
const DT: float = 1.0 / 60.0
const STAGE := Vector3(3.0, 18.0, -3.0)
## The limb chains, distal-most last. Names are this rig's (Tripo humanoid template).
const LIMBS := {
	"lf": ["L_Clavicle", "L_Upperarm", "L_Forearm", "L_Hand"],
	"rf": ["R_Clavicle", "R_Upperarm", "R_Forearm", "R_Hand"],
	"lh": ["L_Thigh", "L_Calf", "L_Foot", "L_ToeBase"],
	"rh": ["R_Thigh", "R_Calf", "R_Foot", "R_ToeBase"],
}
const PAWS := {"lf": "L_Hand", "rf": "R_Hand", "lh": "L_Foot", "rh": "R_Foot"}
## The trunk, as a polyline — a paw's distance to THIS is how far it is from being inside
## the animal.
const TORSO := ["Hip", "Spine01", "Spine02", "NeckTwist01", "Head"]

var failures: int = 0
var _completed: bool = false
var _main: Node3D
var _cat: Node3D
var _player: Node3D
var _skel: Skeleton3D
var _rig = null
var _hinge: Dictionary = {}       ## bone index -> its measured sagittal hinge (rig-derived)
var _rest: Dictionary = {}        ## bone index -> rest quaternion
var _rest_paw_axis: Dictionary = {}   ## limb -> rest distance from paw to the torso axis
var _rest_paw_side: Dictionary = {}   ## limb -> rest lateral (BODY_SIDE) coordinate
var _metrics: Dictionary = {}
## Per-joint accumulators across the whole run: bone name -> {min, max, off_max, scn}
var _joint: Dictionary = {}

func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	if _main == null or _main.get_script() == null:
		print("FAIL  Main.tscn instantiated with its script (it did NOT)")
		get_tree().quit(1)
		return
	add_child(_main)
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 9000 or waited < 180:
		await get_tree().physics_frame
		waited += 1
	GameClock.force_phase(GameClock.Phase.DAY)
	_pin()
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
	# THE HINGES COME FROM THE RIG ITSELF, not from a table here. cat_rig derives each
	# limb's sagittal hinge from the skeleton's own geometry (n = r x BODY_FWD), which is
	# the only definition under which "positive swings the paw forward" is true on every
	# limb of an asymmetric auto-rig. A probe that re-guessed the axes would measure its
	# own guess.
	_hinge = _rig.get("_hinge")
	_rest = _rig.get("_rest")
	if _hinge == null or _hinge.is_empty():
		print("FAIL  read the rig's measured hinge map (got %s)" % str(_hinge))
		failures += 1
		_hinge = {}
	_cat.set_process(false)
	_skel.reset_bone_poses()
	_skel.force_update_all_bone_transforms()
	for k in PAWS:
		var p: Vector3 = _skel.get_bone_global_pose(_skel.find_bone(PAWS[k])).origin
		_rest_paw_axis[k] = _axis_dist(p)
		_rest_paw_side[k] = p.z          # BODY_SIDE is skeleton Z on this rig (BoneDump)
	_cat.set_process(true)

	await _scn("stand_walk", 5.0, func(f): _player.global_position = _cat.global_position \
		+ Vector3(5.0, 0.1, 0.0))
	await _scn("sit", 7.0, func(f): _player.global_position = STAGE + Vector3(1.5, 0.1, 0.0))
	await _scn("groom", 7.0, func(f):
		_player.global_position = STAGE + Vector3(1.5, 0.1, 0.0)
		_cat.set("_wash_cd", 0.0))
	await _scn("run", 4.0, func(f): _player.global_position = _cat.global_position \
		+ Vector3(12.0, 0.1, 0.0))
	await _scn_head_bias()

	_report_joints()
	_write_out()
	if not _completed:
		print("FAIL  the probe ran to completion (it did NOT — see the SCRIPT ERROR above)")
		failures += 1
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _pin() -> void:
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45

func _hold() -> void:
	_cat.set("_hunt_cd", 999.0)
	_cat.set("_zoom_cd", 999.0)
	_cat.set("_play_cd", 999.0)
	_cat.set("_chatter_cd", 999.0)

func _step() -> void:
	_pin()
	_cat.call("_process", DT)
	_skel.force_update_all_bone_transforms()

func _bone_w(b: int) -> Transform3D:
	return _skel.global_transform * _skel.get_bone_global_pose(b)

## Distance from a skeleton-space point to the trunk polyline.
func _axis_dist(p: Vector3) -> float:
	var best: float = 1e9
	for i in range(TORSO.size() - 1):
		var a: int = _skel.find_bone(TORSO[i])
		var b: int = _skel.find_bone(TORSO[i + 1])
		if a < 0 or b < 0:
			continue
		var pa: Vector3 = _skel.get_bone_global_pose(a).origin
		var pb: Vector3 = _skel.get_bone_global_pose(b).origin
		var ab: Vector3 = pb - pa
		var t: float = 0.0 if ab.length_squared() < 1e-9 \
			else clampf((p - pa).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(pa + ab * t))
	return best

## SWING-TWIST ABOUT THE JOINT'S OWN HINGE. Returns [angle_about_hinge, off_hinge_angle].
##
## A hinge joint has ONE degree of freedom. `off` is how much of the applied rotation is
## about anything else — and on this rig that is the numeric signature of the owner's
## "limbs turning against its joints": an elbow being twisted and abducted by a layer that
## thinks it is bending it.
func _hinge_split(rest_q: Quaternion, pose_q: Quaternion, hinge: Vector3) -> Array:
	var rel: Quaternion = rest_q.inverse() * pose_q
	if rel.w < 0.0:
		rel = Quaternion(-rel.x, -rel.y, -rel.z, -rel.w)
	var v := Vector3(rel.x, rel.y, rel.z)
	var along: float = v.dot(hinge)
	var ang: float = 2.0 * atan2(along, maxf(rel.w, 1e-9))
	var off: float = (v - hinge * along).length()
	return [ang, 2.0 * asin(clampf(off, 0.0, 1.0))]

## One measured frame, folded into the per-joint accumulators and the scenario's rows.
func _sample(scn: String, row: Dictionary) -> void:
	for k in LIMBS:
		for bn in LIMBS[k]:
			var b: int = _skel.find_bone(bn)
			if b < 0 or not _hinge.has(b):
				continue
			var sp: Array = _hinge_split(_rest[b], _skel.get_bone_pose_rotation(b),
				_hinge[b] as Vector3)
			if not _joint.has(bn):
				_joint[bn] = {"min": 1e9, "max": -1e9, "off_max": 0.0, "off_scn": scn}
			var J: Dictionary = _joint[bn]
			J["min"] = minf(J["min"], float(sp[0]))
			J["max"] = maxf(J["max"], float(sp[0]))
			if float(sp[1]) > float(J["off_max"]):
				J["off_max"] = float(sp[1])
				J["off_scn"] = scn
	for k in PAWS:
		var p: Vector3 = _skel.get_bone_global_pose(_skel.find_bone(PAWS[k])).origin
		# ABSOLUTE clearance from the trunk, in metres — not a fraction of the rest
		# distance. A sitting cat legitimately brings its forepaws in under its chest, so
		# "closer to the spine than it stands" is normal anatomy and a ratio gate punishes
		# it; what is never normal is a paw INSIDE the trunk. This cat's body half-width
		# measures 0.10-0.26 m (ship_cat._body_r), so a paw centre nearer than ~50 mm to
		# the spine line is in the animal.
		row["axis_dist_min_m"] = minf(float(row.get("axis_dist_min_m", 1e9)), _axis_dist(p))
		var splay: float = absf(p.z - float(_rest_paw_side[k]))
		row["splay_max"] = maxf(float(row.get("splay_max", 0.0)), splay)
	# Whole-animal node motion: after the owner's "the game rotates the entire cat" is
	# fixed, everything except the steering yaw must be flat zero.
	var body: Node3D = _cat.get("_body")
	row["body_rot_max_deg"] = maxf(float(row.get("body_rot_max_deg", 0.0)),
		rad_to_deg(maxf(absf(body.rotation.x), maxf(absf(body.rotation.y), absf(body.rotation.z)))))
	row["body_pos_max_mm"] = maxf(float(row.get("body_pos_max_mm", 0.0)),
		body.position.length() * 1000.0)

func _scn(scn: String, seconds: float, drive: Callable) -> void:
	if scn == "stand_walk" or scn == "run":
		_cat.global_position = STAGE - Vector3(6.0, 0.0, 0.0)
		_cat.call("_reseat")
	var row := {}
	var head_prev := Vector3.ZERO
	var head_spd: Array[float] = []
	var hi: int = _skel.find_bone("Head")
	for f in range(int(seconds / DT)):
		_hold()
		drive.call(f)
		_step()
		if f < 30:
			continue
		_sample(scn, row)
		# HEAD SPEED IS MEASURED IN THE CAT'S OWN FRAME. The first cut took the head's
		# WORLD forward, which turns with the whole animal — so an ordinary steering turn
		# read as a head whip and the metric blamed the head for the body's yaw. What the
		# owner means by "his head shakes" is motion of the head RELATIVE to the shoulders.
		var fwd: Vector3 = _cat.global_transform.basis.inverse() \
			* (_bone_w(hi).basis * Vector3(0, 1, 0))
		if head_prev != Vector3.ZERO:
			head_spd.append(rad_to_deg(fwd.angle_to(head_prev)) / DT)
		head_prev = fwd
		await get_tree().physics_frame
	head_spd.sort()
	if not head_spd.is_empty():
		row["head_speed_p99_deg_s"] = head_spd[int(float(head_spd.size()) * 0.99)]
		row["head_speed_max_deg_s"] = head_spd[head_spd.size() - 1]
	_metrics[scn] = row
	_gate(scn, "paw_axis_clearance_min_m", float(row.get("axis_dist_min_m", 1.0)),
		0.050, false, "m")
	_gate(scn, "paw_splay_max_m", float(row.get("splay_max", 0.0)), 0.10, true, "m")
	_gate(scn, "body_node_rot_max_deg", float(row.get("body_rot_max_deg", 0.0)), 1.0, true, "deg")
	_gate(scn, "body_node_pos_max_mm", float(row.get("body_pos_max_mm", 0.0)), 5.0, true, "mm")
	# A HEAD THAT WHIPS. Cats are the best head-stabilisers in the business; a settled or
	# walking animal's head should not exceed a brisk turn. 200 deg/s is already fast.
	_gate(scn, "head_speed_p99_deg_s", float(row.get("head_speed_p99_deg_s", 0.0)),
		200.0, true, "deg/s")

## THE HEAD BIAS, MEASURED AGAINST THE WORLD — never against the rest pose.
##
## tests/cat_film.gd calibrates the face bearing so that the REST POSE reads zero ("by
## construction"), which is the right instrument for "does the animation turn the head"
## and a tautology for "does the head point straight": a head baked turned in the asset
## is invisible to it, and so is any constant the pose library adds. The owner is looking
## at the drawn animal against the direction it is walking, so that is what this measures:
## the Head bone's world forward against the world travel direction, unbiased.
func _scn_head_bias() -> void:
	var scn := "head_bias"
	var dir := Vector3(1, 0, 0)
	_cat.global_position = STAGE - dir * 7.0
	_cat.call("_reseat")
	_cat.rotation.y = atan2(dir.x, dir.z) + PI
	for i in range(20):
		_player.global_position = _cat.global_position + dir * 5.0
		await get_tree().physics_frame
	var hi: int = _skel.find_bone("Head")
	# WHICH LOCAL VECTOR IS THE NOSE is a measured fact on this rig: every chain runs along
	# local +Y, so the head's forward is its +Y — confirmed by cat_film's own calibration
	# dump, which reports the rest-forward as (-0.06, 0.871, -0.488) in Head-local terms.
	# Taken as +Y here and reported with its rest residual so the reader can see both.
	_cat.set_process(false)
	_skel.reset_bone_poses()
	_skel.force_update_all_bone_transforms()
	var rest_fwd: Vector3 = (_bone_w(hi).basis * Vector3(0, 1, 0)).normalized()
	var node_fwd: Vector3 = -_cat.global_transform.basis.z
	var rest_bias: float = rad_to_deg(angle_difference(
		atan2(node_fwd.x, node_fwd.z), atan2(rest_fwd.x, rest_fwd.z)))
	_cat.set_process(true)
	# THE NOSE IS NOT THE HEAD BONE'S +Y, AND THIS CONSTANT IS CALIBRATED ON FILM — the
	# only definition that has survived contact with the owner. The first value here
	# (-0.600, derived from the mesh's symmetry planes) certified a head as straight that
	# the top-down reel showed cocked ~25 degrees: a derived proxy constant and a derived
	# fix constant were cancelling — the s34 tautology shape in yet another hat. The loop
	# is now closed the honest way round: cat_rig.HEAD_MESH_YAW was tuned until CatFilm's
	# `topdown` reel (camera straight down, screen-up locked to the travel direction — no
	# constant of its own to be wrong) shows the nose dead on the body line, and THEN this
	# offset was set so the probe reads that film-verified state as zero. The film defines
	# straight; this gate exists only to catch future drift away from it.
	const NOSE_OFF_Y: float = -1.222
	var yaws: Array[float] = []
	var pos_prev: Vector3 = _cat.global_position
	for f in range(int(5.0 / DT)):
		_hold()
		_player.global_position = _cat.global_position + dir * 5.0
		_step()
		if f > 60 and _cat.global_position.distance_to(pos_prev) > 0.002:
			var fw: Vector3 = (_bone_w(hi).basis * Vector3(0, 1, 0)).normalized() \
				.rotated(Vector3.UP, NOSE_OFF_Y)
			var travel: Vector3 = (_cat.global_position - pos_prev).normalized()
			yaws.append(rad_to_deg(angle_difference(
				atan2(travel.x, travel.z), atan2(fw.x, fw.z))))
		pos_prev = _cat.global_position
		await get_tree().physics_frame
	var mean: float = 0.0
	var lo: float = 1e9
	var hi_y: float = -1e9
	for y in yaws:
		mean += y
		lo = minf(lo, y)
		hi_y = maxf(hi_y, y)
	mean /= maxf(float(yaws.size()), 1.0)
	_metrics[scn] = {"mesh_rest_bias_deg": rest_bias, "n": yaws.size(),
		"mean": mean, "min": lo, "max": hi_y}
	_note(scn, "mesh_rest_bias_deg", snappedf(rest_bias, 0.01))
	_note(scn, "samples", yaws.size())
	_note(scn, "yaw_min_deg", snappedf(lo, 0.01))
	_note(scn, "yaw_max_deg", snappedf(hi_y, 0.01))
	# THE OWNER'S GATE: walking a straight line, the face points along it. A signed MEAN,
	# because the complaint is a constant lean to one side, which an absolute value or an
	# rms would launder into "a bit of wobble either way".
	_gate(scn, "head_yaw_mean_vs_travel_deg", absf(mean), 5.0, true, "deg")
	_completed = true

## Per-joint ranges and off-hinge leakage, printed as a table and gated.
func _report_joints() -> void:
	print("")
	print("  %-14s %10s %10s %10s   %s" % ["joint", "min deg", "max deg", "range", "off-hinge deg"])
	var off_worst: float = 0.0
	var off_bone: String = ""
	var fold_min: float = 1e9
	var fold_bone: String = ""
	for bn in _joint:
		var J: Dictionary = _joint[bn]
		var rng: float = rad_to_deg(float(J["max"]) - float(J["min"]))
		print("  %-14s %10.1f %10.1f %10.1f   %.1f (%s)"
			% [bn, rad_to_deg(float(J["min"])), rad_to_deg(float(J["max"])), rng,
				rad_to_deg(float(J["off_max"])), J["off_scn"]])
		if float(J["off_max"]) > off_worst:
			off_worst = float(J["off_max"])
			off_bone = bn
		# THE PEG-LEG GATE. The distal joints — elbow/carpus, stifle/hock — are what a
		# cat's leg VISIBLY does; a real walk cycles the stifle ~37 deg and the hock ~24.
		# A chain whose knee moves five degrees is a peg leg however smoothly it swings.
		if bn.ends_with("Forearm") or bn.ends_with("Calf"):
			if rng < fold_min:
				fold_min = rng
				fold_bone = bn
	_metrics["joints"] = {}
	for bn in _joint:
		_metrics["joints"][bn] = {
			"min_deg": rad_to_deg(float(_joint[bn]["min"])),
			"max_deg": rad_to_deg(float(_joint[bn]["max"])),
			"off_hinge_deg": rad_to_deg(float(_joint[bn]["off_max"])),
		}
	_note("joints", "worst_off_hinge_bone", off_bone)
	_note("joints", "weakest_fold_bone", fold_bone)
	# A HINGE THAT ROTATES ABOUT ANYTHING ELSE. 15 deg is generous — it allows the small
	# off-axis component a quaternion slerp between two authored poses legitimately picks
	# up, and refuses a joint being actively abducted or twisted by a layer.
	_gate("joints", "off_hinge_max_deg", rad_to_deg(off_worst), 15.0, true, "deg")
	# ...and the fold: the weakest knee/elbow must still describe a real arc.
	_gate("joints", "weakest_knee_range_deg", fold_min if fold_min < 1e8 else 0.0,
		20.0, false, "deg")

func _gate(scn: String, name: String, value: float, threshold: float, below: bool,
		unit: String) -> void:
	var ok: bool = value < threshold if below else value > threshold
	if not _metrics.has(scn):
		_metrics[scn] = {}
	_metrics[scn][name] = {"value": value, "threshold": threshold, "pass": ok,
		"cmp": "<" if below else ">"}
	print("%s  [%s] %s = %.3f %s (gate %s %.3f)"
		% ["PASS" if ok else "FAIL", scn, name, value, unit, "<" if below else ">", threshold])
	if not ok:
		failures += 1

func _note(scn: String, name: String, value) -> void:
	if not _metrics.has(scn):
		_metrics[scn] = {}
	_metrics[scn][name] = {"value": value, "pass": true, "cmp": "logged"}
	print("      [%s] %s = %s" % [scn, name, str(value)])

func _write_out() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var f := FileAccess.open(OUT_DIR + "/joints.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_metrics, "  "))
		f.close()
	print("[cat_joints] -> %s/joints.json" % OUT_DIR)
