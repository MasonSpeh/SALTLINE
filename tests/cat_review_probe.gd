extends Node
## CAT REVIEW PROBE — the numeric gates behind the s39+ animation rebuild, measured on the
## SHIPPED ship_cat driven through its real behaviour states, in a world-fixed frame.
##
## WHY THIS EXISTS: four sessions of "all green" shipped a cat that moonwalks in its two
## most-watched states. The greens were real and the gates were wrong — they measured node
## existence, no-crash, or a camera bolted to the cat's own basis (in which frame world-fixed
## sliding is invisible). Every gate here is designed backwards from a named defect:
##
##   * FOOT-SLIDE      — in-stance paw world-XZ drift, at walk, run, STALK and CARRY. The
##                       stalk and carry rows are the ones no previous harness ever measured,
##                       and they are where the moonwalk lives (cat_rig gates gait weight on
##                       an allow-set that excludes both poses while ship_cat translates the
##                       body through them).
##   * LOCOMOTES⇒STEPS — any state that moved the body > 5 cm must have gait weight > 0.
##   * HEAD STABILITY  — drawn head world roll/pitch while walking and while look-tracking.
##   * PHASE LOCK      — the pelvis-Y minimum must sit at a fixed offset from the nearest
##                       foot plant, not drift (two clocks = floating pelvis).
##   * FLATNESS        — after a ramp, a sitting cat on flat deck must return to level.
##   * CONTINUITY      — per-bone angular step per frame, fixed AND summed dt (AiBudget).
##   * DT-EQUIVALENCE  — the same commanded turn sampled at dt 1/60 and dt 0.15 must land in
##                       the same place at the same sim time (delta*k eases fail this).
##   * SANITY          — quaternions normalised, bone lengths constant, twist bones inert.
##
## Headless is correct: transforms and state, nothing drawn.
##   godot --headless --path . res://tests/CatReviewProbe.tscn
##
## Raw numbers land in tests/out/cat_review/metrics.json and metrics.md. A gate "passes"
## only against those logged numbers — never a bare boolean.

const OUT_DIR := "res://tests/out/cat_review"
const DT: float = 1.0 / 60.0
const BIG_DT: float = 0.15          ## AiBudget.MAX_STEP — the summed-delta worst case
const PAWS := {"lf": "L_Hand", "rf": "R_Hand", "lh": "L_Foot", "rh": "R_Foot"}
const STAGE := Vector3(3.0, 18.0, -3.0)   ## probed open deck (tests/DeckFind, s37)

var failures: int = 0
var _completed: bool = false
var _main: Node3D
var _cat: Node3D
var _player: Node3D
var _skel: Skeleton3D
var _rig = null
## Calibrated head axes (tests/cat_film.gd's idiom): the Head bone's own local vectors that
## meant "ahead" and "up" in the rest pose. Measured, never guessed — no cardinal axis of
## this rig points anywhere useful.
var _fwd_local := Vector3(0, 0, -1)
var _up_local := Vector3(0, 1, 0)
var _head_i: int = -1
var _hip_i: int = -1
## Global sanity accumulators, fed by every scenario.
var _quat_dev_max: float = 0.0
var _len_dev_max: float = 0.0
var _twist_dev_max: float = 0.0
var _nan_frames: int = 0
var _len0 := {}                     ## bone index -> rest distance to parent
var _twist_bones: Array[int] = []
var _prev_q := {}                   ## bone index -> last frame's drawn pose quaternion
## scenario name -> {metric: value}; gates print PASS/FAIL and count into `failures`.
var _metrics := {}

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	if _main == null or _main.get_script() == null:
		print("FAIL  Main.tscn instantiated with its script attached (it did NOT)")
		get_tree().quit(1)
		return
	add_child(_main)
	# Real-time build wait with a sim-frame floor — the film harness's lesson.
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
		print("FAIL  found a player and a cat (player %s, cat %s)" % [_player, _cat])
		get_tree().quit(1)
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	# Befriend it — every scenario below is companion behaviour.
	for c in _cat.get_children():
		if c is Interactable:
			(c as Interactable).emit_signal("interacted", "SAY HELLO")
			break
	await get_tree().physics_frame
	await get_tree().physics_frame
	_rig = _cat.get("_rig")
	for n in (_cat.get("_host") as Node3D).find_children("*", "Skeleton3D", true, false):
		_skel = n
		break
	if _rig == null or _skel == null:
		print("FAIL  the cat carries a rig and a skeleton (rig %s, skel %s)" % [_rig, _skel])
		get_tree().quit(1)
		return
	_head_i = _skel.find_bone("Head")
	_hip_i = _skel.find_bone("Hip")
	_calibrate()
	# THE PROBE OWNS THE CLOCK. The engine's headless delta is whatever the machine manages,
	# which is not a measurement. The cat's _process is driven by hand at exactly DT (and at
	# BIG_DT for the summed path), so every per-frame number below has known units.
	_cat.set_process(false)

	await _scn_walk("walk", 5.0, 4.6)
	await _scn_walk("run", 12.0, 2.6)
	await _scn_stalk()
	await _scn_carry()
	await _scn_lookwalk()
	await _scn_look_cal()
	await _scn_transitions("transitions", DT)
	await _scn_bigdt_equiv()
	await _scn_slope_sit()

	_gate("sanity", "quat_norm_dev_max", _quat_dev_max, 1e-3, true, "")
	_gate("sanity", "bone_len_dev_max_mm", _len_dev_max * 1000.0, 1.5, true, "mm")
	_gate("sanity", "twist_bone_dev_max_rad", _twist_dev_max, 0.02, true, "rad")
	_gate("sanity", "nan_frames", float(_nan_frames), 0.5, true, "frames")

	_write_out()
	if not _completed:
		print("FAIL  the probe ran to completion (it did NOT — see the SCRIPT ERROR above)")
		failures += 1
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Pin the sun and the weather every frame — a squall mid-run films the back half at night.
func _pin() -> void:
	if _main == null:
		return
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45

func _calibrate() -> void:
	_cat.set_process(false)
	_skel.reset_bone_poses()
	_skel.force_update_all_bone_transforms()
	var fwd: Vector3 = -_cat.global_transform.basis.z
	var bb: Basis = (_skel.global_transform * _skel.get_bone_global_pose(_head_i)).basis
	_fwd_local = (bb.inverse() * fwd).normalized()
	_up_local = (bb.inverse() * Vector3.UP).normalized()
	# Rest bone lengths, for the constancy gate; and the twist bones that must stay inert.
	for i in range(_skel.get_bone_count()):
		var p: int = _skel.get_bone_parent(i)
		if p >= 0:
			_len0[i] = _skel.get_bone_global_pose(i).origin.distance_to(
				_skel.get_bone_global_pose(p).origin)
		var nm: String = _skel.get_bone_name(i)
		if nm.contains("Twist") and nm != "R_ThighTwist01" and nm != "NeckTwist01":
			_twist_bones.append(i)
	_cat.set_process(true)

## One controlled think: hand the cat exactly `dt`, then flush the skeleton.
func _step(dt: float) -> void:
	_pin()
	_cat.call("_process", dt)
	_skel.force_update_all_bone_transforms()

## For the look-CALIBRATION only: the injected rig.look() must be the sole writer, so the
## glance system (which calls look through _drive_rig with its own random targets, at 0.85
## weight) is silenced. The first cut measured a superposition of the probe's command and
## whatever mark the cat had idly picked — chaos attributed to the axes.
func _lock_attention() -> void:
	_cat.set("_glance_cd", 999.0)
	_cat.set("_glance_hold", 0.0)
	_cat.set("_focus_w", 0.0)

func _hold_idlers() -> void:
	_cat.set("_hunt_cd", 999.0)
	_cat.set("_zoom_cd", 999.0)
	_cat.set("_play_cd", 999.0)
	_cat.set("_wash_cd", 999.0)
	_cat.set("_wash_t", 0.0)
	# The chatter watches AIRBORNE gulls — a target whose bearing sweeps fast and crosses
	# the +/-PI seam — so it is held off like every other idler in scenarios that measure
	# something else. Its own motion is covered by the smoothed look layer.
	_cat.set("_chatter_cd", 999.0)

func _bone_w(b: int) -> Transform3D:
	return _skel.global_transform * _skel.get_bone_global_pose(b)

func _head_ypr(travel_deg: float) -> Vector3:
	var b: Basis = _bone_w(_head_i).basis
	var f: Vector3 = (b * _fwd_local).normalized()
	var u: Vector3 = (b * _up_local).normalized()
	var yaw: float = rad_to_deg(atan2(f.x, f.z))
	var yaw_rel: float = rad_to_deg(angle_difference(deg_to_rad(travel_deg), deg_to_rad(yaw)))
	var pitch: float = rad_to_deg(asin(clampf(f.y, -1.0, 1.0)))
	# Roll: the head's own up tipped out of the world-vertical plane that contains its forward.
	var side: Vector3 = Vector3.UP.cross(f)
	side = Vector3.ZERO if side.length() < 1e-5 else side.normalized()
	var roll: float = rad_to_deg(asin(clampf(u.dot(side), -1.0, 1.0)))
	return Vector3(yaw_rel, pitch, roll)

## One frame of measurement. Also feeds the global sanity accumulators.
func _sample(travel_deg: float) -> Dictionary:
	var s := {}
	s["pos"] = _cat.global_position
	s["yaw"] = _cat.rotation.y
	s["pose"] = String(_cat.get("_pose"))
	s["gait_w"] = float(_rig.get("_gait_w"))
	s["phase"] = float(_rig.get("_phase"))
	s["hip_y"] = _bone_w(_hip_i).origin.y
	s["head"] = _head_ypr(travel_deg)
	var paw_w := {}
	for k in PAWS:
		paw_w[k] = _bone_w(_skel.find_bone(PAWS[k])).origin
	s["paw_w"] = paw_w
	# Sanity + continuity, across every bone, every sampled frame.
	#
	# THE TAIL IS MEASURED IN WORLD SPACE, SEPARATELY. Its LOCAL pose legitimately steps as
	# fast as its parent thigh moves, because the drive counter-rotates the parent exactly
	# to hold the tail world-stable — a local-step gate on the stabilised bone punishes the
	# stabilisation. What the eye sees is its world orientation, so that is what is gated.
	var worst_step: float = 0.0
	var worst_bone: String = ""
	var tail_i: int = _skel.find_bone("R_ThighTwist01")
	for i in range(_skel.get_bone_count()):
		var q: Quaternion = _skel.get_bone_pose_rotation(i)
		if not (is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)):
			_nan_frames += 1
			continue
		_quat_dev_max = maxf(_quat_dev_max, absf(q.length() - 1.0))
		if i == tail_i:
			var tw: Quaternion = _bone_w(i).basis.get_rotation_quaternion()
			if _prev_q.has(-2):
				s["tail_world_step"] = (_prev_q[-2] as Quaternion).angle_to(tw)
			_prev_q[-2] = tw
			continue
		if _prev_q.has(i):
			var st: float = (_prev_q[i] as Quaternion).angle_to(q)
			if st > worst_step:
				worst_step = st
				worst_bone = _skel.get_bone_name(i)
		_prev_q[i] = q
		var p: int = _skel.get_bone_parent(i)
		# The HIP is the one bone whose pose POSITION is legitimately written (the crouch,
		# the bob) — its distance to its parent is animation, not scale corruption.
		if i == _hip_i:
			continue
		if p >= 0 and _len0.has(i):
			var l: float = _skel.get_bone_global_pose(i).origin.distance_to(
				_skel.get_bone_global_pose(p).origin)
			_len_dev_max = maxf(_len_dev_max, absf(l - float(_len0[i])))
	for i in _twist_bones:
		var rest_q: Quaternion = _skel.get_bone_rest(i).basis.get_rotation_quaternion()
		_twist_dev_max = maxf(_twist_dev_max, rest_q.angle_to(_skel.get_bone_pose_rotation(i)))
	s["joint_step"] = worst_step
	s["joint_step_bone"] = worst_bone
	if not is_finite(_cat.global_position.x):
		_nan_frames += 1
	return s

## Wipe the continuity baseline — call after any deliberate teleport of the cat.
func _reset_prev() -> void:
	_prev_q.clear()

func _gate(scn: String, name: String, value: float, threshold: float, below: bool,
		unit: String) -> void:
	var ok: bool = value < threshold if below else value > threshold
	if not _metrics.has(scn):
		_metrics[scn] = {}
	_metrics[scn][name] = {"value": value, "threshold": threshold,
		"pass": ok, "cmp": "<" if below else ">"}
	print("%s  [%s] %s = %.4f %s (gate %s %.4f)"
		% ["PASS" if ok else "FAIL", scn, name, value, unit, "<" if below else ">", threshold])
	if not ok:
		failures += 1

func _note(scn: String, name: String, value) -> void:
	if not _metrics.has(scn):
		_metrics[scn] = {}
	_metrics[scn][name] = {"value": value, "pass": true, "cmp": "logged"}
	print("      [%s] %s = %s" % [scn, name, str(value)])

# ---------------------------------------------------------------- foot-slide analysis
##
## Stance detection is from the DRAWN paw, not the rig's tables: a paw is in stance while its
## world height sits within STANCE_BAND of its own minimum over the window. Drift is the
## world-XZ step between consecutive in-stance frames; a planted paw scores ~0.
##
## The window is ERODED one frame at each end of every stance run. Measured on the shipped
## walk: a 10 mm band on a 34 mm lift catches the last swing frame before the plant, where a
## paw legitimately covers ~44 mm — which read as a skate on a gait whose stance is genuinely
## planted. The first/last in-stance pair is touchdown/toe-off, not support.
const STANCE_BAND: float = 0.006

## Slide is scored over the ENGAGED gait (gait weight > 0.8): the ease-in/out ramps are
## transitions — a body accelerating onto legs still fading in covers real ground on
## partial-amplitude steps for ~0.2 s, which is not the steady-state skate this gate is
## about (the ramps answer to the continuity gates instead). A moonwalking state never
## reaches 0.8 while moving, so it cannot hide here — the gait-weight gate names it.
## `band` widens for the gallop: its stance dwells ~3 frames against the walk's ~8, and the
## 6 mm walk band eroded a gallop window to nothing — a vacuous zero. 14 mm covers the full
## stance arc (STANCE_ARC 12 mm) while admitting < 0.2 frames of swing at gallop lift.
func _slide_stats(frames: Array, poses: Array, band: float = STANCE_BAND) -> Dictionary:
	var per_frame_max: float = 0.0
	var per_window_max: float = 0.0
	var pairs: int = 0
	var contacts: Array = []          ## [frame_index, paw] stance starts, for the phase lock
	for k in PAWS:
		var ys: Array[float] = []
		for s in frames:
			ys.append((s["paw_w"][k] as Vector3).y)
		if ys.is_empty():
			continue
		var y_min: float = ys.min()
		# Contiguous stance runs, then drift only over the eroded interior of each run.
		var runs: Array = []
		var start: int = -1
		for j in range(frames.size()):
			var st: bool = ys[j] < y_min + band and float(frames[j]["gait_w"]) > 0.6
			if st and start < 0:
				start = j
			elif not st and start >= 0:
				runs.append([start, j - 1])
				start = -1
		if start >= 0:
			runs.append([start, frames.size() - 1])
		for r in runs:
			var a: int = int(r[0])
			var b: int = int(r[1])
			contacts.append([a, k])
			var run_total: float = 0.0
			for j in range(a + 2, b):
				if poses[j] != poses[j - 1]:
					continue
				var p0: Vector3 = frames[j - 1]["paw_w"][k]
				var p1: Vector3 = frames[j]["paw_w"][k]
				var d: float = Vector2(p1.x - p0.x, p1.z - p0.z).length()
				per_frame_max = maxf(per_frame_max, d)
				run_total += d
				per_window_max = maxf(per_window_max, run_total)
				pairs += 1
	return {"frame_mm": per_frame_max * 1000.0, "window_mm": per_window_max * 1000.0,
		"pairs": pairs, "contacts": contacts}

## Pelvis-vs-footfall lock: offset (in cycles) from each pelvis-Y local minimum to the
## nearest foot plant. Reported as mean and spread — a drift is two clocks.
func _phase_lock(frames: Array, contacts: Array) -> Dictionary:
	var hy: Array[float] = []
	for s in frames:
		hy.append(float(s["hip_y"]))
	# 5-frame box smooth so millimetre noise does not mint minima.
	var sm: Array[float] = []
	for i in range(hy.size()):
		var a: int = maxi(0, i - 2)
		var b: int = mini(hy.size() - 1, i + 2)
		var acc: float = 0.0
		for j in range(a, b + 1):
			acc += hy[j]
		sm.append(acc / float(b - a + 1))
	var minima: Array[int] = []
	for i in range(3, sm.size() - 3):
		if sm[i] <= sm[i - 1] and sm[i] <= sm[i + 1] and sm[i] < sm[i - 3] - 0.0005 \
				and sm[i] < sm[i + 3] - 0.0005:
			if minima.is_empty() or i - minima[-1] > 6:
				minima.append(i)
	if minima.size() < 4 or contacts.is_empty():
		return {"n": minima.size(), "mean_phase": 0.0, "std": 1.0}
	# THE LOCK IS PHASE CONSISTENCY, NOT PROXIMITY. At a walk there are four contacts per
	# cycle, so "distance to the nearest contact" is bounded at 0.125 cycles and a bob on a
	# completely different clock still scores well. What a second clock CANNOT fake is the
	# rig phase AT each pelvis minimum being constant: a locked bob puts every minimum at
	# the same point of the cycle (mod 0.5 — there are two minima per cycle), a drifting
	# one spreads them round the circle. Circular statistics, so the wrap costs nothing.
	var sx: float = 0.0
	var sy: float = 0.0
	for m in minima:
		var a: float = fposmod(float(frames[m]["phase"]), 0.5) * 2.0 * TAU
		sx += cos(a)
		sy += sin(a)
	var r: float = sqrt(sx * sx + sy * sy) / float(minima.size())
	var circ_std_rad: float = sqrt(maxf(-2.0 * log(maxf(r, 1e-6)), 0.0))
	var mean_phase: float = fposmod(atan2(sy, sx) / (2.0 * TAU), 1.0) * 0.5
	return {"n": minima.size(), "mean_phase": mean_phase,
		"std": circ_std_rad / (2.0 * TAU) * 0.5}

# ---------------------------------------------------------------- scenarios

## Straight-line locomotion: player teleported to a fixed lead each frame (the lead picks
## the gait — 5 m is FOLLOW at WALK_SPEED, 12 m is RUN, exactly as the game does it).
func _scn_walk(scn: String, lead: float, seconds: float) -> void:
	var dir := Vector3(1, 0, 0)
	_cat.global_position = STAGE - dir * 7.0
	_cat.call("_reseat")
	_cat.rotation.y = atan2(dir.x, dir.z) + PI
	_reset_prev()
	_hold_idlers()
	for i in range(20):
		_player.global_position = _cat.global_position + dir * lead
		await get_tree().physics_frame
	var frames: Array = []
	var poses: Array = []
	var settle: int = 60
	var n: int = int(seconds / DT)
	for f in range(n):
		_hold_idlers()
		_player.global_position = _cat.global_position + dir * lead
		_step(DT)
		if f >= settle:
			frames.append(_sample(90.0))    # +X travel = bearing 90 in atan2(x, z) degrees
			poses.append(String(_cat.get("_pose")))
		await get_tree().physics_frame
	var moved: float = (frames[-1]["pos"] as Vector3).distance_to(frames[0]["pos"])
	var gw_sum: float = 0.0
	var gw_n: int = 0
	var still_frames: int = 0
	var step_max: float = 0.0
	var step_bone: String = ""
	var tail_max: float = 0.0
	var roll_max: float = 0.0
	var pitches: Array[float] = []
	var yaw_rms: float = 0.0
	var hip_lo: float = 1e9
	var hip_hi: float = -1e9
	for i in range(1, frames.size()):
		var d: float = (frames[i]["pos"] as Vector3).distance_to(frames[i - 1]["pos"])
		if d > 0.004:
			gw_sum += float(frames[i]["gait_w"])
			gw_n += 1
		else:
			still_frames += 1
		if float(frames[i]["joint_step"]) > step_max:
			step_max = float(frames[i]["joint_step"])
			step_bone = String(frames[i]["joint_step_bone"])
		tail_max = maxf(tail_max, float(frames[i].get("tail_world_step", 0.0)))
		var h: Vector3 = frames[i]["head"]
		roll_max = maxf(roll_max, absf(h.z))
		pitches.append(h.y)
		yaw_rms += h.x * h.x
		hip_lo = minf(hip_lo, float(frames[i]["hip_y"]))
		hip_hi = maxf(hip_hi, float(frames[i]["hip_y"]))
	yaw_rms = sqrt(yaw_rms / maxf(float(frames.size() - 1), 1.0))
	var slide: Dictionary = _slide_stats(frames, poses, 0.014 if scn == "run" else STANCE_BAND)
	var lock: Dictionary = _phase_lock(frames, slide["contacts"])
	_note(scn, "moved_m", snappedf(moved, 0.01))
	_note(scn, "still_frames", still_frames)
	_note(scn, "stance_pairs", slide["pairs"])
	_note(scn, "hip_y_span_mm", snappedf((hip_hi - hip_lo) * 1000.0, 0.1))
	_note(scn, "worst_step_bone", step_bone)
	_gate(scn, "slide_frame_mm", slide["frame_mm"], 10.0, true, "mm/frame")
	_gate(scn, "slide_window_mm", slide["window_mm"], 20.0, true, "mm/window")
	# The brief's locomotes=>steps assertion is per STATE: it moved, so its gait must have
	# been engaged over the moving portion (a single ease-in frame is not a moonwalk).
	_gate(scn, "gait_w_mean_while_moving", gw_sum / maxf(float(gw_n), 1.0), 0.30, false, "")
	_gate(scn, "joint_step_max_rad", step_max, 0.35, true, "rad/frame")
	_gate(scn, "tail_world_step_max_rad", tail_max, 0.35, true, "rad/frame")
	_gate(scn, "head_roll_max_deg", roll_max, 3.0, true, "deg")
	var p_min: float = pitches.min()
	var p_max: float = pitches.max()
	_gate(scn, "head_pitch_span_deg", p_max - p_min, 12.0, true, "deg")
	_gate(scn, "head_yaw_rms_deg", yaw_rms, 3.5, true, "deg")
	_note(scn, "phase_lock", lock)
	_gate(scn, "pelvis_lock_std_cycles", float(lock["std"]), 0.10, true, "cycles")

## THE STALK — the state no harness ever measured moving. A stub Node3D in the deck_gull
## group is legal prey (_airborne reads a property it lacks -> false), and the player rides
## abeam so the companion gate (d < RUN_M) holds while the cat creeps.
func _scn_stalk() -> void:
	var scn := "stalk"
	var dir := Vector3(1, 0, 0)
	_cat.global_position = STAGE - dir * 6.0
	_cat.call("_reseat")
	_cat.rotation.y = atan2(dir.x, dir.z) + PI
	_reset_prev()
	var prey := Node3D.new()
	prey.name = "ReviewPreyStub"
	add_child(prey)
	prey.add_to_group("deck_gull")
	# 4.5 m out: _find_prey takes the NEAREST grounded bird, and a real deck gull wandering
	# nearer than the stub turns this scenario into a film of a gull flushing.
	prey.global_position = _cat.global_position + dir * 4.5
	prey.global_position.y = _cat.global_position.y
	_cat.set("_hunt_cd", 0.0)
	_cat.set("_energy", 1.0)
	_cat.set("_zoom_cd", 999.0)
	_cat.set("_play_cd", 999.0)
	_cat.set("_wash_t", 0.0)
	var frames: Array = []
	var poses: Array = []
	for f in range(int(16.0 / DT)):
		_player.global_position = _cat.global_position + Vector3(0, 0, 3.5)
		_step(DT)
		if int(_cat.get("_hunt")) >= 2:
			break                     # the tread; the approach is what this scenario measures
		if String(_cat.get("_pose")) == "stalk" and f > 30:
			frames.append(_sample(90.0))
			poses.append("stalk")
		await get_tree().physics_frame
	_note(scn, "stalk_frames", frames.size())
	_note(scn, "hunt_beat_reached", int(_cat.get("_hunt")))
	_note(scn, "prey_is_stub", _cat.get("_prey") == prey)
	prey.queue_free()
	_cat.call("_end_hunt", false)
	_cat.set("_hunt_cd", 999.0)
	_cat.set("_after_t", 0.0)
	if frames.size() < 60:
		print("FAIL  [%s] the stalk never ran long enough to measure (%d frames)"
			% [scn, frames.size()])
		failures += 1
		return
	var moved: float = (frames[-1]["pos"] as Vector3).distance_to(frames[0]["pos"])
	var gw_sum: float = 0.0
	var gw_n: int = 0
	var step_max: float = 0.0
	var step_bone: String = ""
	for i in range(1, frames.size()):
		var d: float = (frames[i]["pos"] as Vector3).distance_to(frames[i - 1]["pos"])
		if d > 0.004:
			gw_sum += float(frames[i]["gait_w"])
			gw_n += 1
		if float(frames[i]["joint_step"]) > step_max:
			step_max = float(frames[i]["joint_step"])
			step_bone = String(frames[i]["joint_step_bone"])
	var slide: Dictionary = _slide_stats(frames, poses)
	_note(scn, "moved_m", snappedf(moved, 0.01))
	_note(scn, "stance_pairs", slide["pairs"])
	_note(scn, "worst_step_bone", step_bone)
	# THE ASSERTION THAT WOULD HAVE CAUGHT THE MOONWALK: it translated, so it must step.
	if moved > 0.05:
		_gate(scn, "gait_w_mean_while_moving", gw_sum / maxf(float(gw_n), 1.0),
			0.30, false, "")
	_gate(scn, "slide_frame_mm", slide["frame_mm"], 10.0, true, "mm/frame")
	_gate(scn, "slide_window_mm", slide["window_mm"], 20.0, true, "mm/window")
	_gate(scn, "joint_step_max_rad", step_max, 0.35, true, "rad/frame")

## THE CARRY — the other moonwalk state, and the live look-while-walking case (GIFT watches
## the player's face all the way in). The player retreats to hold the approach open.
func _scn_carry() -> void:
	var scn := "carry"
	var dir := Vector3(1, 0, 0)
	_cat.global_position = STAGE - dir * 7.0
	_cat.call("_reseat")
	_cat.rotation.y = atan2(dir.x, dir.z) + PI
	_reset_prev()
	_hold_idlers()
	_cat.set("_carry", "gull_feather")
	var frames: Array = []
	var poses: Array = []
	var settle: int = 45
	for f in range(int(5.0 / DT)):
		_hold_idlers()
		_player.global_position = _cat.global_position + dir * 6.0 + Vector3(0, 0.1, 0)
		_step(DT)
		if f >= settle:
			frames.append(_sample(90.0))
			poses.append(String(_cat.get("_pose")))
		await get_tree().physics_frame
	_cat.set("_carry", "")             # put the world back — no delivery mid-probe
	var moved: float = (frames[-1]["pos"] as Vector3).distance_to(frames[0]["pos"])
	var gw_sum: float = 0.0
	var gw_n: int = 0
	var step_max: float = 0.0
	var step_bone: String = ""
	var roll_max: float = 0.0
	for i in range(1, frames.size()):
		var d: float = (frames[i]["pos"] as Vector3).distance_to(frames[i - 1]["pos"])
		if d > 0.004:
			gw_sum += float(frames[i]["gait_w"])
			gw_n += 1
		if float(frames[i]["joint_step"]) > step_max:
			step_max = float(frames[i]["joint_step"])
			step_bone = String(frames[i]["joint_step_bone"])
		roll_max = maxf(roll_max, absf((frames[i]["head"] as Vector3).z))
	var slide: Dictionary = _slide_stats(frames, poses)
	_note(scn, "moved_m", snappedf(moved, 0.01))
	_note(scn, "pose_seen", poses[poses.size() / 2] if not poses.is_empty() else "?")
	_note(scn, "stance_pairs", slide["pairs"])
	_note(scn, "worst_step_bone", step_bone)
	if moved > 0.05:
		_gate(scn, "gait_w_mean_while_moving", gw_sum / maxf(float(gw_n), 1.0),
			0.30, false, "")
	_gate(scn, "slide_frame_mm", slide["frame_mm"], 10.0, true, "mm/frame")
	_gate(scn, "slide_window_mm", slide["window_mm"], 20.0, true, "mm/window")
	_gate(scn, "joint_step_max_rad", step_max, 0.35, true, "rad/frame")
	_gate(scn, "head_roll_max_deg", roll_max, 3.0, true, "deg")

## Walking straight while the head tracks a world-fixed target 40 degrees off the line —
## the look layer's stabilisation gate. The old layer rotates on raw local axes, which on
## this rig turns a yaw request into roll.
func _scn_lookwalk() -> void:
	var scn := "lookwalk"
	var dir := Vector3(1, 0, 0)
	_cat.global_position = STAGE - dir * 7.0
	_cat.call("_reseat")
	_cat.rotation.y = atan2(dir.x, dir.z) + PI
	_reset_prev()
	_hold_idlers()
	var frames: Array = []
	var poses: Array = []
	for f in range(int(4.0 / DT)):
		_hold_idlers()
		_player.global_position = _cat.global_position + dir * 5.0
		var look_at: Vector3 = _cat.global_position + dir.rotated(Vector3.UP, 0.7) * 4.0 \
			+ Vector3(0, 1.0, 0)
		_cat.call("_watch", look_at, 1.0)
		_step(DT)
		if f >= 50:
			frames.append(_sample(90.0))
			poses.append(String(_cat.get("_pose")))
		await get_tree().physics_frame
	var roll_max: float = 0.0
	var step_max: float = 0.0
	var step_bone: String = ""
	var yaw_mean: float = 0.0
	for i in range(1, frames.size()):
		roll_max = maxf(roll_max, absf((frames[i]["head"] as Vector3).z))
		if float(frames[i]["joint_step"]) > step_max:
			step_max = float(frames[i]["joint_step"])
			step_bone = String(frames[i]["joint_step_bone"])
		yaw_mean += (frames[i]["head"] as Vector3).x
	yaw_mean /= maxf(float(frames.size() - 1), 1.0)
	var slide: Dictionary = _slide_stats(frames, poses)
	_note(scn, "head_yaw_mean_deg", snappedf(yaw_mean, 0.01))
	_note(scn, "worst_step_bone", step_bone)
	_gate(scn, "head_roll_max_deg", roll_max, 3.0, true, "deg")
	# The glance must actually turn the head TOWARD the target (+40 off travel), not away.
	_gate(scn, "head_yaw_toward_target_deg", yaw_mean, 4.0, false, "deg")
	_gate(scn, "slide_frame_mm", slide["frame_mm"], 10.0, true, "mm/frame")
	_gate(scn, "joint_step_max_rad", step_max, 0.35, true, "rad/frame")

## Stationary look calibration: inject a pure yaw look and a pure pitch look, measure what
## the drawn head actually does. Catches axis leaks the walking test dilutes.
func _scn_look_cal() -> void:
	var scn := "look_cal"
	_cat.global_position = STAGE
	_cat.call("_reseat")
	_reset_prev()
	_hold_idlers()
	_player.global_position = _cat.global_position + Vector3(1.6, 0.1, 0)
	# Let it settle to a sit first — DETECTED, not timed: the first cut measured its "base"
	# while the sit (and its head, on the slowest per-bone lead) was still blending in, and
	# the residual settle read as 29 degrees of look-roll that the look never caused.
	for f in range(int(6.0 / DT)):
		_hold_idlers()
		_lock_attention()
		_step(DT)
		if f > 60 and float(_rig.call("settle")) < 0.03:
			break
		await get_tree().physics_frame
	var travel: float = rad_to_deg(_cat.rotation.y - PI)  # its own facing, so yaw_rel ~ 0 base
	for probe in [["yaw", 0.6, 0.0], ["pitch", 0.0, 0.35]]:
		var base: Vector3 = _head_ypr(-travel)   # fresh per probe — the last one leaves state
		var worst_roll: float = 0.0
		var resp := Vector3.ZERO
		for f in range(int(1.2 / DT)):
			_hold_idlers()
			_lock_attention()
			_rig.call("look", float(probe[1]), float(probe[2]), 1.0)
			_step(DT)
			var now: Vector3 = _head_ypr(-travel)
			# The yaw component is a bearing — difference it on the circle or a response a
			# few degrees past the seam prints as ±330.
			resp = Vector3(
				rad_to_deg(angle_difference(deg_to_rad(base.x), deg_to_rad(now.x))),
				now.y - base.y, now.z - base.z)
			worst_roll = maxf(worst_roll, absf(resp.z))
			await get_tree().physics_frame
		_note(scn, String(probe[0]) + "_response_ypr_deg", resp.snappedf(0.01))
		_gate(scn, String(probe[0]) + "_roll_leak_deg", worst_roll, 3.0, true, "deg")
		if String(probe[0]) == "yaw":
			# 0.6 rad commanded at full weight through neck+head weights: expect a
			# same-signed world yaw of at least half the command.
			_gate(scn, "yaw_gain_deg", resp.x, 14.0, false, "deg")
		else:
			_gate(scn, "pitch_gain_deg", resp.y, 6.0, false, "deg")
		for f in range(int(1.5 / DT)):
			_hold_idlers()
			_lock_attention()
			_step(DT)                 # let the look decay before the next probe
			await get_tree().physics_frame

## Sit/stand cycles — transition continuity at a chosen dt.
func _scn_transitions(scn: String, dt: float) -> void:
	_cat.global_position = STAGE
	_cat.call("_reseat")
	_reset_prev()
	_hold_idlers()
	var dir := Vector3(1, 0, 0)
	var step_max: float = 0.0
	var step_bone: String = ""
	var frames_n: int = 0
	for cycle in range(3):
		# Near and still -> SIT.
		_player.global_position = _cat.global_position + dir * 1.6 + Vector3(0, 0.1, 0)
		for f in range(int(2.8 / dt)):
			_hold_idlers()
			_step(dt)
			var s: Dictionary = _sample(90.0)
			if float(s["joint_step"]) > step_max:
				step_max = float(s["joint_step"])
				step_bone = String(s["joint_step_bone"])
			frames_n += 1
			await get_tree().physics_frame
		# Far -> stand, walk.
		for f in range(int(2.2 / dt)):
			_hold_idlers()
			_player.global_position = _cat.global_position + dir * 6.0 + Vector3(0, 0.1, 0)
			_step(dt)
			var s2: Dictionary = _sample(90.0)
			if float(s2["joint_step"]) > step_max:
				step_max = float(s2["joint_step"])
				step_bone = String(s2["joint_step_bone"])
			frames_n += 1
			await get_tree().physics_frame
	_note(scn, "frames", frames_n)
	_note(scn, "worst_step_bone", step_bone)
	# At 1/60 a blend may legitimately move ~0.1 rad/frame; a swap moves the whole pose
	# difference at once. At BIG_DT the same exponential blend legitimately covers ~9x more.
	_gate(scn, "joint_step_max_rad", step_max, 0.35 if dt < 0.05 else 1.0, true, "rad/frame")

## THE SUMMED-DELTA PATH: the same commanded 180-degree turn (and settle-to-sit) driven at
## dt 1/60 and at dt 0.15 must pass through the same states at the same SIM time. Every
## `delta * k` ease fails this; every `1 - exp(-k dt)` ease passes it by construction.
func _scn_bigdt_equiv() -> void:
	var scn := "bigdt"
	var dir := Vector3(1, 0, 0)
	var yaw_at := {}                   ## dt label -> node yaw at ~0.45 s sim time
	var pitch_at := {}                 ## dt label -> drawn body pitch at ~0.45 s
	for path in [["fixed", DT], ["summed", BIG_DT]]:
		var dt: float = float(path[1])
		_cat.global_position = STAGE
		_cat.call("_reseat")
		_cat.rotation.y = atan2(dir.x, dir.z) + PI
		_cat.set("_yaw_prev", _cat.rotation.y)
		_cat.set("_slope", 0.30)       # a pre-loaded slope, so its ease is exercised too
		_reset_prev()
		_hold_idlers()
		# Stand it still facing +X, then put the player dead astern: a 180 commanded turn.
		_player.global_position = _cat.global_position - dir * 5.0
		var t: float = 0.0
		var step_max: float = 0.0
		while t < 0.46:
			_hold_idlers()
			_step(dt)
			t += dt
			var s: Dictionary = _sample(90.0)
			step_max = maxf(step_max, float(s["joint_step"]))
			await get_tree().physics_frame
		yaw_at[path[0]] = _cat.rotation.y
		var body: Node3D = _cat.get("_body")
		pitch_at[path[0]] = body.rotation.x
		_note(scn, String(path[0]) + "_joint_step_max", snappedf(step_max, 0.001))
		if dt > 0.05:
			_gate(scn, "summed_joint_step_max_rad", step_max, 1.0, true, "rad/think")
	var yaw_diff: float = rad_to_deg(absf(angle_difference(
		float(yaw_at["fixed"]), float(yaw_at["summed"]))))
	var pitch_diff: float = rad_to_deg(absf(float(pitch_at["fixed"]) - float(pitch_at["summed"])))
	_note(scn, "yaw_fixed_deg", snappedf(rad_to_deg(float(yaw_at["fixed"])), 0.1))
	_note(scn, "yaw_summed_deg", snappedf(rad_to_deg(float(yaw_at["summed"])), 0.1))
	# The two paths sampled the same trajectory: within a few degrees of each other after
	# half a second of a 180-degree command. Measured on the shipped `clampf(k*delta)` ease
	# the summed path snaps the full 90 while the fixed path reads 80.6 — a 9.4 deg gap —
	# so the gate sits at 6.0: fails the snap, passes an exponential ease with margin.
	_gate(scn, "turn_equivalence_deg", yaw_diff, 6.0, true, "deg")
	_gate(scn, "slope_ease_equivalence_deg", pitch_diff, 2.5, true, "deg")

## SLOPE RETENTION: a cat that stops walking keeps its last _slope for ever, because
## ship_cat only updates it inside _walk_toward while applying it every frame.
##
## The first cut of this scenario built a physical ramp and the cat's own wall-slide logic
## walked it AROUND the ramp — a scenario void, not a measurement. So the frozen state is
## installed directly: _slope is set to 0.30 rad, which is exactly what a real climb leaves
## behind (the bigdt scenario pre-loads the same value through the same variable, and
## _walk_toward writes it from measured rise/run — there is no second pathway). The cat then
## SITS on flat deck through the shipped state machine, and the drawn body must come level.
func _scn_slope_sit() -> void:
	var scn := "slope_sit"
	_cat.global_position = STAGE
	_cat.call("_reseat")
	_reset_prev()
	_hold_idlers()
	# Player near and still: the shipped path into SIT.
	_player.global_position = _cat.global_position + Vector3(1.6, 0.1, 0)
	for f in range(int(1.5 / DT)):
		_hold_idlers()
		_step(DT)
		await get_tree().physics_frame
	_cat.set("_slope", 0.30)
	var pitch_series: Array[float] = []
	for f in range(int(2.5 / DT)):
		_hold_idlers()
		_step(DT)
		var body: Node3D = _cat.get("_body")
		pitch_series.append(rad_to_deg(body.rotation.x))
		await get_tree().physics_frame
	var final_pitch: float = 0.0
	for i in range(maxi(0, pitch_series.size() - 30), pitch_series.size()):
		final_pitch += pitch_series[i]
	final_pitch /= 30.0
	_note(scn, "pose_final", String(_cat.get("_pose")))
	_note(scn, "slope_final_rad", snappedf(float(_cat.get("_slope")), 0.001))
	_gate(scn, "flat_sit_body_pitch_deg", absf(final_pitch), 2.0, true, "deg")

# ---------------------------------------------------------------- output

func _write_out() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var jf := FileAccess.open(OUT_DIR + "/metrics.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(_metrics, "  "))
		jf.close()
	var mf := FileAccess.open(OUT_DIR + "/metrics.md", FileAccess.WRITE)
	if mf != null:
		mf.store_line("# Cat review — §5A numeric gates (raw)")
		mf.store_line("")
		mf.store_line("Every row is a measured number from a headless run of the SHIPPED")
		mf.store_line("ship_cat driven through its real behaviour states. `logged` rows are")
		mf.store_line("evidence, not gates.")
		mf.store_line("")
		for scn in _metrics:
			mf.store_line("## %s" % scn)
			mf.store_line("")
			mf.store_line("| metric | value | gate | verdict |")
			mf.store_line("|---|---|---|---|")
			for name in _metrics[scn]:
				var m: Dictionary = _metrics[scn][name]
				if m["cmp"] == "logged":
					mf.store_line("| %s | %s | — | logged |" % [name, str(m["value"])])
				else:
					mf.store_line("| %s | %.4f | %s %.4f | %s |" % [name, float(m["value"]),
						m["cmp"], float(m["threshold"]), "PASS" if m["pass"] else "FAIL"])
			mf.store_line("")
		mf.close()
	_completed = true
	print("[cat_review] metrics -> %s" % OUT_DIR)
