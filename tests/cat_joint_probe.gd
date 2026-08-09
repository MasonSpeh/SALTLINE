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
## Last frame's WORLD orientation per bone (key -2 is the tail) — see the world-step block in
## `_sample`. Cleared at the top of every scenario, because a scenario boundary teleports the
## animal and a continuity baseline carried across one measures the teleport.
var _world_prev: Dictionary = {}
var _rest: Dictionary = {}        ## bone index -> rest quaternion
var _rest_paw_axis: Dictionary = {}   ## limb -> rest distance from paw to the torso axis
var _rest_paw_side: Dictionary = {}   ## limb -> rest lateral (BODY_SIDE) coordinate
## limb -> mm the paw BONE sits above the node origin in the rest pose. Zero of the deck scale.
var _rest_paw_y: Dictionary = {}
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
		# THE HEIGHT AT WHICH THIS PARTICULAR PAW IS TOUCHING THE DECK, which no gate in this
		# file has ever had. The paw BONE is not the sole: on this fit the four rest at
		# 25.9 / 27.5 / 12.9 / 16.5 mm above the node origin, a 14.6 mm spread between fore and
		# hind. `paw_below_deck_max_mm` compares all four against the origin with one flat
		# 25 mm allowance, so it hands the hind pair 13 mm of free sink and the fore pair none
		# — before anything has moved. Per-limb, off the rest skeleton, is the only baseline
		# under which "this paw is on the deck" means the same thing on all four legs.
		_rest_paw_y[k] = (_bone_w(_skel.find_bone(PAWS[k])).origin.y - _cat.global_position.y) \
			* 1000.0
	# THE CAT STAYS OFF THE ENGINE'S CLOCK FOR THE WHOLE RUN. This line used to be
	# `set_process(true)`, which meant every scenario DOUBLE-TICKED the animal: the
	# engine's own _process (with a headless world's 30-80 ms frame deltas) ran on top of
	# _step()'s hand-fed 1/60 — so between two consecutive samples the rig could
	# legitimately advance by a 60 Hz step PLUS an 80 ms step, and a rate divided by DT
	# read up to ~4x reality. Every head-speed p99 this probe printed before s44 carries
	# that inflation; the bare-rig harness (tests/head_rate_scratch.gd) is the number the
	# cap actually holds: worst 188 deg/s against the 189 ceiling, 0 frames over. A probe
	# that owns the clock (CLAUDE.md: the probe owns the clock) must own it EXCLUSIVELY.
	_cat.set_process(false)

	await _scn("stand_walk", 5.0, func(f): _player.global_position = _cat.global_position \
		+ Vector3(5.0, 0.1, 0.0))
	await _scn("sit", 7.0, func(f): _player.global_position = STAGE + Vector3(1.5, 0.1, 0.0))
	await _scn("groom", 7.0, func(f):
		_player.global_position = STAGE + Vector3(1.5, 0.1, 0.0)
		_cat.set("_wash_cd", 0.0))
	await _scn("run", 4.0, func(f): _player.global_position = _cat.global_position \
		+ Vector3(12.0, 0.1, 0.0))
	await _scn_sit_paws()
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
	# THE INSTINCT LAYER (s54) IS AN IDLER LIKE THE REST. Its actions can put a settled cat
	# into GROOM, STRETCH, SLEEP or PERCH of its own accord, which is exactly what this
	# harness must not have happening in the middle of a per-state measurement. `_idle_cd`
	# holds every action off; `_roam_cd` is the subset that would also MOVE the animal.
	_cat.set("_idle_cd", 999.0)
	_cat.set("_roam_cd", 999.0)

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
	# DO THE PAWS REACH THE DECK, OR GO THROUGH IT? The owner reports the cat sitting a few
	# inches low with its paws sunk into the plating, standing AND walking. Nothing else in
	# this file measures the animal against the ground it stands on — every other gate is
	# internal to the skeleton, which is exactly how a whole-body height error hides under a
	# green suite. World space, against the cat's own node origin, which `_reseat` puts on
	# the deck surface: a paw below that is a paw in the floor.
	for k in PAWS:
		var pw: Vector3 = _bone_w(_skel.find_bone(PAWS[k])).origin
		row["paw_below_deck_max_mm"] = maxf(float(row.get("paw_below_deck_max_mm", -1e9)),
			(_cat.global_position.y - pw.y) * 1000.0)
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
	# THE RATE CEILING'S BLIND SIDE, WHICH IS WHERE KNOWN_ISSUES SAID TO LOOK.
	#
	# `cat_rig.LIMB_MAX_RATE` bounds each limb bone's LOCAL pose rotation, and CatReviewProbe's
	# `joint_step_max_rad` gate measures the same local quantity — so both are blind to the one
	# thing an eye actually sees at the end of a chain: the bone's WORLD orientation, which is
	# the SUM of every parent's motion plus its own. Measured on the shipped walk, the worst
	# local step is 0.3167 rad/frame (the cap, saturated) while the worst WORLD step on the same
	# frames is 0.56-0.68 — two to three times it, on `L_Hand`/`R_Hand`, i.e. exactly the distal
	# joints a deeper carpal schedule moves. That is the coverage gap, and it is measured here
	# rather than argued.
	#
	# Reported per scenario with a POP gate rather than a quality bar: 1.0 rad/frame is 57
	# degrees in one frame, about 1.5x the current worst, so it catches a discontinuity without
	# encoding today's numbers as a target. Calibrating it into a real bar wants a session that
	# judges the render, and the honest first step is to make the number visible.
	for k in LIMBS:
		for bn2 in LIMBS[k]:
			var b2: int = _skel.find_bone(bn2)
			if b2 < 0:
				continue
			var gq: Quaternion = _bone_w(b2).basis.get_rotation_quaternion().normalized()
			if _world_prev.has(b2):
				var ws: float = (_world_prev[b2] as Quaternion).angle_to(gq)
				if ws > float(row.get("distal_world_step_max_rad", 0.0)):
					row["distal_world_step_max_rad"] = ws
					row["distal_world_step_bone"] = bn2
			_world_prev[b2] = gq
	# ...and the TAIL, which had no ceiling at all until s54 and whose world step is the only
	# quantity that ever meant anything on that bone (it is posed absolutely against a moving
	# parent, so its local step is its parent's by construction).
	var ti: int = _skel.find_bone("R_ThighTwist01")
	if ti >= 0:
		var tq: Quaternion = _bone_w(ti).basis.get_rotation_quaternion().normalized()
		if _world_prev.has(-2):
			row["tail_world_step_max_rad"] = maxf(float(row.get("tail_world_step_max_rad", 0.0)),
				(_world_prev[-2] as Quaternion).angle_to(tq))
		_world_prev[-2] = tq
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
	_world_prev.clear()
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
	# 25 mm of tolerance: the paw BONE sits a little inside the paw mesh, and a real paw
	# flattens on contact, so a few millimetres under the node origin is correct. Inches are
	# not — the owner can see 50 mm and so can this.
	_gate(scn, "paw_below_deck_max_mm", float(row.get("paw_below_deck_max_mm", 0.0)),
		25.0, true, "mm")
	_gate(scn, "paw_splay_max_m", float(row.get("splay_max", 0.0)), 0.10, true, "m")
	_gate(scn, "body_node_rot_max_deg", float(row.get("body_rot_max_deg", 0.0)), 1.0, true, "deg")
	_gate(scn, "body_node_pos_max_mm", float(row.get("body_pos_max_mm", 0.0)), 5.0, true, "mm")
	# A HEAD THAT WHIPS. Cats are the best head-stabilisers in the business; a settled or
	# walking animal's head should not exceed a brisk turn. 200 deg/s is already fast.
	_gate(scn, "head_speed_p99_deg_s", float(row.get("head_speed_p99_deg_s", 0.0)),
		200.0, true, "deg/s")
	_note(scn, "distal_world_step_bone", String(row.get("distal_world_step_bone", "")))
	_gate(scn, "distal_world_step_max_rad", float(row.get("distal_world_step_max_rad", 0.0)),
		1.0, true, "rad/frame")
	_gate(scn, "tail_world_step_max_rad", float(row.get("tail_world_step_max_rad", 0.0)),
		0.35, true, "rad/frame")

## ALL FOUR PAWS, SIGNED, IN THE SIT — the owner's "when cat is sitting, game angled him
## backwards, causing front paws to float an inch above, and back paws to be sinking an inch".
##
## WHY THE EXISTING GATE COULD NOT SEE THIS, and why it looked like a flake for two sessions.
## `paw_below_deck_max_mm` is one number with three separate blind spots:
##   * it is a MAX OF ONE SIGN. `deck - paw`, maximised: a paw an inch IN THE AIR makes it
##     smaller, not larger. Half of the owner's report — the floating forepaws — is invisible
##     to it by construction, and always was.
##   * it is UN-BASELINED. All four paw bones are compared against the node origin with one
##     flat 25 mm allowance, while the four rest 25.9 / 27.5 / 12.9 / 16.5 mm above it. The
##     hind pair therefore start with ~13 mm of the budget already spent and the fore pair
##     with none.
##   * it is a MAX OVER A MIXED WINDOW. The `sit` scenario does not restage the animal, so
##     its seven seconds contain a walk, a `sit_pre`, a `sit_deep` and a `sit` — poses that
##     measured -2.9, -9.3 and -8.4 mm on the hind. Which of them the max lands on depends on
##     how much of the window the walk ate, i.e. on machine load. A gate whose value is set by
##     scheduling reports a PERMANENT defect intermittently, and that is exactly the "known
##     flake" the s52 notes blamed on a stray wash bout. The probe was right the whole time.
##
## So: this scenario stages the animal, drives it until the rig is genuinely WEARING the sit
## (name checked, not assumed — `set_pose` no-ops silently on a name it does not have), and
## then measures each paw against ITS OWN rest height. It reports all four signed, and it
## cannot go vacuous: the sample count is asserted, and so is the pose it was sampled under.
func _scn_sit_paws() -> void:
	var scn := "sit_paws"
	_cat.global_position = STAGE
	_cat.call("_reseat")
	_cat.call("_end_idle")
	_cat.set("_wash_t", 0.0)
	var settled: int = 0
	var acc := {}
	for k in PAWS:
		acc[k] = []
	for f in range(int(9.0 / DT)):
		_hold()
		_cat.set("_wash_cd", 999.0)
		_player.global_position = STAGE + Vector3(1.5, 0.1, 0.0)
		_step()
		# Only frames the animal is actually SITTING count, and "sitting" is read off the rig's
		# own target rather than off the state machine — a state that asked for a pose the
		# library does not carry would otherwise be measured wearing `stand`.
		if int(_cat.get("_state")) == 3 and String(_rig.get("_target")) == "sit":
			settled += 1
			if settled > 90:      # 1.5 s for the blend to land before anything is judged
				for k in PAWS:
					(acc[k] as Array).append(
						(_bone_w(_skel.find_bone(PAWS[k])).origin.y - _cat.global_position.y)
							* 1000.0 - float(_rest_paw_y[k]))
		await get_tree().physics_frame
	var n: int = (acc["lf"] as Array).size()
	# THE ANTI-VACUITY CLAUSE. Every other number below is a max over `acc`, and a max over an
	# empty array is whatever default it is given — which is how a gate certifies an animal it
	# never looked at. If the cat did not sit, this scenario has no opinion and says so.
	_gate(scn, "frames_measured_sitting", float(n), 120.0, false, "frames")
	if n == 0:
		return
	var mean := {}
	var float_max: float = -1e9
	var sink_max: float = -1e9
	for k in ["lf", "rf", "lh", "rh"]:
		var s: float = 0.0
		for v in acc[k]:
			s += v
			float_max = maxf(float_max, v)
			sink_max = maxf(sink_max, -v)
		mean[k] = s / float(n)
		_note(scn, "paw_%s_mean_mm" % k, snappedf(float(mean[k]), 0.1))
	var fore: float = (float(mean["lf"]) + float(mean["rf"])) * 0.5
	var hind: float = (float(mean["lh"]) + float(mean["rh"])) * 0.5
	# The wheelbase, measured off the rest skeleton — the lever the owner's "angled backwards"
	# is an angle over. Never typed: a re-rig changes it.
	_skel.reset_bone_poses()
	_skel.force_update_all_bone_transforms()
	var pf: Vector3 = _bone_w(_skel.find_bone("L_Hand")).origin
	var ph: Vector3 = _bone_w(_skel.find_bone("L_Foot")).origin
	var wb: float = maxf(Vector2(pf.x - ph.x, pf.z - ph.z).length(), 0.05)
	_note(scn, "wheelbase_m", snappedf(wb, 0.001))
	_note(scn, "fore_minus_hind_mm", snappedf(fore - hind, 0.1))
	# BOTH SIGNS, SEPARATELY. 15 mm is under two thirds of the smallest thing the owner has
	# ever reported on this animal (an inch = 25.4) and above the 8.5 mm of hind sink this
	# rig's short right femur and dead-straight left hind cannot pay off
	# (docs/CAT_RIG_CEILING.md §3) — it catches the defect and does not encode the asset.
	_gate(scn, "sit_paw_float_max_mm", float_max, 15.0, true, "mm")
	_gate(scn, "sit_paw_sink_max_mm", sink_max, 15.0, true, "mm")
	# ...AND THE PITCH ITSELF, which is what the owner actually SEES: not one paw wrong but the
	# whole body rotated nose-up about its lateral axis. A pair of single-paw gates can both
	# pass on an animal tilted by half their allowance each way, so the differential is its own
	# gate. 3 degrees over this wheelbase is 18 mm end to end.
	_gate(scn, "sit_body_pitch_deg", absf(rad_to_deg(atan2((fore - hind) * 0.001, wb))),
		3.0, true, "deg")

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
	# (stays off the engine clock — see the calibration note: re-enabling here is the
	# double-ticking bug wearing a second hat; _step() is the only driver.)
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
	# RE-ANCHORED WITH HEAD_MESH_YAW, AND THE TWO MOVE TOGETHER OR THIS GATE LIES: the
	# proxy is calibrated to the film-verified drawn head, so any change of Δ to cat_rig's
	# rest bake shifts this by exactly -Δ. (s44 proved the relation numerically — a 0.703
	# rad bake change read as exactly 40.28 deg here — and then abused it to certify a
	# regression: the constant this gate guards was re-anchored to a WRONG bake and the
	# gate dutifully printed 0.000 for a face 35 degrees off on film. s46: the bake is SOLVED off the
	# mesh now (-0.3325, tests/nose_scratch.gd), so this proxy is 0.4105 by the same
	# relation (proxy = 0.078 - bake). Re-derive it whenever that solve moves. This gate catches DRIFT from the
	# film-verified state; it cannot bless the state itself — only the head-on reel can.)
	const NOSE_OFF_Y: float = 0.628
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
