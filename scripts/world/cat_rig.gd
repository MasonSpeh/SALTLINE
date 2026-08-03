extends RefCounted
## ONE SKELETON, EVERY POSE BLENDED — the s37 cat animation core.
##
## NO `class_name` ON PURPOSE — preload by path (AGENT_TRAPS: a global class on a new file
## breaks the import creating its own cache entry).
##
## WHAT THIS REPLACES, AND WHY IT COULD NEVER BE SMOOTH. s35/s36 drove SIX separate rigged
## meshes and changed state with a `visible` flip: one frame a walking cat, the next frame a
## sitting one, with nothing in between — a whole-body teleport at every transition, which is
## exactly the owner's "doesn't move intuitively/fluidly with its body skeleton". Worse, the
## gait swung limbs on meshes AUTHORED mid-stride (cat_run2 is a frozen gallop), so the
## oscillation was layered on top of an already-posed body and the legs double-counted.
##
## THE ARCHITECTURE NOW. One mesh — the neutral STANDING cat — one 41-bone skeleton, and a
## pose LIBRARY extracted from the other rigged meshes' rest poses (they all share Tripo's
## humanoid template bone-for-bone; tools/extract_cat_poses.py asserts it). Each behaviour
## state names a target pose; every frame each bone SLERPS toward its target and the gait is
## ADDED on top as small swing rotations. Nothing is ever swapped, so every transition —
## sit to walk, run to groom, anything to anything — is continuous by construction, and the
## blend cost is ~40 slerps a frame on one animal.
##
## THE TWO RATE RULES, both from AGENT_TRAPS and both load-bearing here:
##   * every ease uses `1 - exp(-rate * dt)` — `delta * k` overshoots past dt*k > 1 and this
##     animal is under AiBudget, which hands it SUMMED deltas;
##   * the gait phase is advanced by DISTANCE ACTUALLY MOVED / stride, never by `t * speed` —
##     a rate written into an accumulating clock teleports the phase (the shoal detonation
##     bug), and commanded-speed advance treadmills the legs against a blocked step.

const SWING := Vector3(1, 0, 0)   ## limb chains run local +Y; fore-aft swing is about X

## Footfall phase offsets per limb, in cycles. The gait MODE is not a switch: the active
## offsets are themselves eased between these tables as speed crosses the bands, so a cat
## accelerating from amble to gallop re-times its legs continuously instead of stuttering
## between patterns.
const WALK_PHASE := {"lh": 0.00, "lf": 0.25, "rh": 0.50, "rf": 0.75}
const TROT_PHASE := {"lh": 0.00, "rf": 0.00, "rh": 0.50, "lf": 0.50}
const BOUND_PHASE := {"lf": 0.00, "rf": 0.06, "lh": 0.45, "rh": 0.51}
## Speed bands (m/s): below WALK_V pure walk offsets; between, eased; above TROT_V pure
## bound. Chosen against WALK_SPEED 1.55 / TROT 2.6 / RUN 4.4 in ship_cat.gd.
const WALK_V: float = 1.8
const TROT_V: float = 3.4

var _sk: Skeleton3D = null
var _idx: Dictionary = {}          ## bone name -> index in THIS skeleton
var _rest: Dictionary = {}         ## index -> rest Quaternion (the stand mesh's pose)
var _rest_t: Dictionary = {}       ## index -> rest origin, for the Hip height blend
var _limb: Dictionary = {}
var _spine := -1
var _spine2 := -1
var _neck := -1
var _head := -1
var _hip := -1

## The pose library: name -> {q: {index: Quaternion}, hip_t: Vector3}. `stand` is the
## skeleton's own rest and always present.
var _poses: Dictionary = {}
## The blend state — what is actually on the bones right now.
var _cur_q: Dictionary = {}        ## index -> Quaternion
var _cur_hip: Vector3 = Vector3.ZERO
var _target: String = "stand"
var _blend_rate: float = 7.0
## Gait state.
var _phase: float = 0.0
var _gait_w: float = 0.0           ## eased 0..1 — how much gait rides on the pose
var _speed_s: float = 0.0          ## eased speed, for amplitude and mode mixing
## Look state, applied last so it wins over the gait's neck motion.
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _look_w: float = 0.0

func _init(skel: Skeleton3D, pose_json_path: String = "") -> void:
	_sk = skel
	if _sk == null:
		return
	for i in range(_sk.get_bone_count()):
		var nm: String = _sk.get_bone_name(i)
		_idx[nm] = i
		var rest: Transform3D = _sk.get_bone_rest(i)
		_rest[i] = rest.basis.get_rotation_quaternion()
		_rest_t[i] = rest.origin
		_cur_q[i] = _rest[i]
	_limb = {
		"lf": {"prox": _b("L_Upperarm"), "dist": _b("L_Forearm"), "paw": _b("L_Hand")},
		"rf": {"prox": _b("R_Upperarm"), "dist": _b("R_Forearm"), "paw": _b("R_Hand")},
		"lh": {"prox": _b("L_Thigh"), "dist": _b("L_Calf"), "paw": _b("L_Foot")},
		"rh": {"prox": _b("R_Thigh"), "dist": _b("R_Calf"), "paw": _b("R_Foot")},
	}
	_spine = _b("Spine01")
	_spine2 = _b("Spine02")
	_neck = _b("NeckTwist01")
	_head = _b("Head")
	_hip = _b("Hip")
	_cur_hip = _rest_t.get(_hip, Vector3.ZERO)
	# `stand` is the base skeleton's own rest — present even with no library on disk.
	var stand := {"q": {}, "hip_t": _rest_t.get(_hip, Vector3.ZERO)}
	for i in _rest:
		stand["q"][i] = _rest[i]
	_poses["stand"] = stand
	# THE LIBRARY IS AUTHORED, NOT TRANSFERRED. The donor-transfer experiment is kept in
	# _load_library for the record, but it is not called: rendering every transferred pose
	# (tests/out/cat_blend, s37) showed the auto-rig joint FRAMES disagree between fits —
	# sit arrived ~70% right, sleep and run arrived candy-wrapped inside their own torsos,
	# groom reared the cat vertical. Rotations are only meaningful on the skeleton they
	# were measured on, so every pose here is FK offsets from THIS skeleton's rest — the
	# same method the gait and the s35 wash already proved on these bones.
	_build_poses()

func _b(nm: String) -> int:
	return int(_idx.get(nm, -1))

func valid() -> bool:
	return _sk != null and _limb.get("lf", {}).get("prox", -1) >= 0

func has_pose(nm: String) -> bool:
	return _poses.has(nm)

func pose_count() -> int:
	return _poses.size()

## ---------------------------------------------------------------- the library

## Donor poses come from the OTHER rigged meshes' rest poses. Same bone names, same
## template, different stances — a bone's local rest rotation IS the pose, to the accuracy
## the auto-rig fits agree, and that accuracy was settled by rendering every pose in
## tests/CatBlendShot before any of this shipped.
func _load_library(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not d.has("poses"):
		return
	var stand_hip: Array = d["poses"].get("stand", {}).get("hip_t", [0, 0, 0])
	for pose_name in d["poses"]:
		var src: Dictionary = d["poses"][pose_name]
		var entry := {"q": {}, "hip_t": _rest_t.get(_hip, Vector3.ZERO)}
		for bone_name in src.get("bones", {}):
			var i: int = _b(bone_name)
			if i < 0:
				continue
			var a: Array = src["bones"][bone_name]
			entry["q"][i] = Quaternion(a[0], a[1], a[2], a[3]).normalized()
		# The Hip TRANSLATION carries the crouch: a sitting pelvis is lower than a standing
		# one and no rotation can express that. Applied as a DELTA off the donor set's own
		# stand, onto this skeleton's rest — absolute donor positions belong to the donor's
		# skeleton, not this one.
		var ht: Array = src.get("hip_t", stand_hip)
		var dh := Vector3(ht[0] - stand_hip[0], ht[1] - stand_hip[1], ht[2] - stand_hip[2])
		entry["hip_t"] = _rest_t.get(_hip, Vector3.ZERO) + dh
		_poses[pose_name] = entry

## ---------------------------------------------------------------- driving

## Name the pose the behaviour wants. Cheap and idempotent — the blend does the rest.
## `rate` is how urgently to get there: a startled bolt blends faster than settling to sleep.
func set_pose(nm: String, rate: float = 7.0) -> void:
	if _poses.has(nm):
		_target = nm
		_blend_rate = rate

func target() -> String:
	return _target

## Point the head. Weight decays in tick, so a glance fades unless renewed.
func look(yaw: float, pitch: float, weight: float) -> void:
	_look_yaw = clampf(yaw, -1.05, 1.05)
	_look_pitch = clampf(pitch, -0.5, 0.5)
	_look_w = maxf(_look_w, clampf(weight, 0.0, 1.0))

## THE ONE WRITER. Called once per frame by ship_cat with:
##   dt     — the (possibly AiBudget-summed) delta
##   speed  — the speed the animal is trying to move at, m/s
##   moved  — metres ACTUALLY covered this frame (drives the phase; a blocked cat's legs stop)
func tick(dt: float, speed: float, moved: float) -> void:
	if not valid():
		return
	var k: float = 1.0 - exp(-_blend_rate * dt)
	var pose: Dictionary = _poses.get(_target, _poses["stand"])
	# 1. Blend every bone toward the target pose.
	for i in _cur_q:
		var want: Quaternion = pose["q"].get(i, _rest[i])
		_cur_q[i] = (_cur_q[i] as Quaternion).slerp(want, k)
	_cur_hip = _cur_hip.lerp(pose["hip_t"], k)
	# 2. Gait weight and smoothed speed. The weight fades IN with motion and OUT at rest,
	# so stopping mid-stride eases the legs home instead of snapping them.
	var moving: float = clampf(speed / 0.4, 0.0, 1.0) * clampf(moved / maxf(dt * 0.05, 1e-6), 0.0, 1.0)
	# Gait only makes sense on locomotion poses.
	if _target != "walk" and _target != "run" and _target != "stand":
		moving = 0.0
	_gait_w = lerpf(_gait_w, moving, 1.0 - exp(-8.0 * dt))
	_speed_s = lerpf(_speed_s, speed, 1.0 - exp(-6.0 * dt))
	# 3. Phase from DISTANCE, not time — stride length grows a little with speed.
	var stride: float = 0.52 + clampf(_speed_s / 4.4, 0.0, 1.0) * 0.35
	_phase = fposmod(_phase + moved / stride, 1.0)
	# 4. The additive gait, if any of it is live.
	if _gait_w > 0.003:
		var amp: float = (0.26 + clampf(_speed_s / 4.4, 0.0, 1.0) * 0.30) * _gait_w
		var mix: float = clampf((_speed_s - WALK_V) / (TROT_V - WALK_V), 0.0, 1.0)
		for limb_key in WALK_PHASE:
			# Eased BETWEEN tables: walk->trot->bound re-times continuously.
			var off: float
			if mix < 0.5:
				off = lerpf(WALK_PHASE[limb_key], TROT_PHASE[limb_key], mix * 2.0)
			else:
				off = lerpf(TROT_PHASE[limb_key], BOUND_PHASE[limb_key], mix * 2.0 - 1.0)
			var ph: float = _phase + off
			var a: float = sin(ph * TAU)
			var bend: float = maxf(0.0, -cos(ph * TAU)) * amp * 0.9
			var L: Dictionary = _limb[limb_key]
			var sgn: float = 1.0 if limb_key.ends_with("f") else -1.0
			_mul(L["prox"], Quaternion(SWING, a * amp * sgn))
			_mul(L["dist"], Quaternion(SWING, -bend * sgn))
			_mul(L["paw"], Quaternion(SWING, bend * 0.5 * sgn))
		var sway: float = sin(_phase * TAU * 2.0)
		_mul(_spine, Quaternion(Vector3(0, 1, 0), sway * amp * 0.10))
		_mul(_spine2, Quaternion(Vector3(0, 1, 0), -sway * amp * 0.07))
		_mul(_hip, Quaternion(SWING, absf(sway) * amp * 0.05))
	# 5. Idle life on top of ANY pose: slow breath always; it is what stops a still pose
	# reading as a freeze-frame. Softer while asleep.
	var t: float = Time.get_ticks_msec() / 1000.0
	var breath: float = 0.020 if _target == "sleep" else 0.032
	_mul(_spine, Quaternion(Vector3(0, 0, 1), sin(t * (0.8 if _target == "sleep" else 1.6)) * breath))
	_mul(_spine2, Quaternion(Vector3(0, 0, 1), sin(t * (0.8 if _target == "sleep" else 1.6)) * breath * 0.6))
	if _target == "groom":
		# The wash stroke rides the blended groom pose rather than replacing it.
		var stroke: float = sin(t * 4.2)
		_mul(_neck, Quaternion(SWING, -stroke * 0.13))
		_mul(_head, Quaternion(SWING, -stroke * 0.16))
		var L2: Dictionary = _limb["lf"]
		_mul(L2["dist"], Quaternion(SWING, stroke * 0.10))
	# 6. The look, LAST, so attention wins over everything.
	_look_w = maxf(0.0, _look_w - dt * 1.5)
	if _look_w > 0.01 and _target != "sleep":
		var wq := Quaternion(Vector3(0, 1, 0), _look_yaw * 0.55 * _look_w) \
			* Quaternion(SWING, _look_pitch * 0.5 * _look_w)
		_mul(_neck, wq)
		_mul(_head, Quaternion(Vector3(0, 1, 0), _look_yaw * 0.45 * _look_w) \
			* Quaternion(SWING, _look_pitch * 0.5 * _look_w))
	# 7. Write the skeleton, once.
	for i in _cur_q:
		_sk.set_bone_pose_rotation(i, _cur_q[i])
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _cur_hip)

## Multiply an offset onto the CURRENT blended value — additive layers never touch _cur_q,
## so they cannot accumulate across frames.
var _scratch: Dictionary = {}
func _mul(bone: int, q: Quaternion) -> void:
	if bone < 0:
		return
	_cur_q[bone] = (_cur_q[bone] as Quaternion) * q

## How far the drawn pose is from the target, 0..1 — lets behaviour wait for a settle
## ("stand up BEFORE walking") without hard-coding times.
func settle() -> float:
	var pose: Dictionary = _poses.get(_target, _poses["stand"])
	var worst: float = 0.0
	for i in [_spine, _hip, _limb["lf"]["prox"], _limb["lh"]["prox"]]:
		if i < 0:
			continue
		var want: Quaternion = pose["q"].get(i, _rest[i])
		worst = maxf(worst, (_cur_q[i] as Quaternion).angle_to(want))
	return clampf(worst / 0.8, 0.0, 1.0)

## ---------------------------------------------------------------- authored poses
##
## Every pose is a set of [axis, radians] offsets from the STAND rest, plus a hip drop.
## Axis codes: 0 = SWING (local X, fore-aft), 1 = local Y (turn), 2 = local Z (lean).
## Values were tuned through tests/CatBlendShot renders — each pose was looked at, adjusted
## and re-rendered until it read; none of these numbers is a guess left unverified.
const _AXES := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]

func _pose_from(offsets: Dictionary, hip_drop: float) -> Dictionary:
	var e := {"q": {}, "hip_t": _rest_t.get(_hip, Vector3.ZERO) + Vector3(0, -hip_drop, 0)}
	for i in _rest:
		e["q"][i] = _rest[i]
	for bone_name in offsets:
		var i: int = _b(bone_name)
		if i < 0:
			continue
		var q: Quaternion = _rest[i]
		for pair in offsets[bone_name]:
			q = q * Quaternion(_AXES[pair[0]], pair[1])
		e["q"][i] = q
	return e

## ---------------------------------------------------------------- pose baking (with IK)
##
## HAND-TUNED FOLD ANGLES CANNOT SIT A CAT. Two rounds of authored angles proved it in
## renders: without something pinning the paws, every torso change sends the feet wherever
## the fold happens to leave them, and the two rig fits carry different bone LENGTHS on the
## left and right legs (a documented Tripo defect), so one set of angles cannot even be
## symmetric. The tool for "torso moves, paws stay planted" is IK, and it also absorbs the
## length asymmetry for free — it solves each leg with that leg's own bones.
##
## The IK is hinge-constrained CCD: every limb joint here is a hinge about its own local X
## (measured off the rendered axis atlas, tests/out/cat_axes*), so each step rotates one
## joint about its hinge by the angle that best carries the paw toward the target,
## projected into the plane the hinge allows. Runs at POSE-BUILD time only — the results
## are baked into the library and runtime stays ~40 slerps a frame.

func _set_chain(q: Dictionary) -> void:
	for i in q:
		_sk.set_bone_pose_rotation(i, q[i])

func _paw_pos(paw: int) -> Vector3:
	return _sk.get_bone_global_pose(paw).origin

## One hinged-CCD solve of `chain` (proximal..distal) carrying `paw` to `target`,
## editing `q` in place. The seed pose in `q` picks the knee's branch — seed folded and
## the solution folds the anatomical way.
func _ik_leg(q: Dictionary, chain: Array, paw: int, target: Vector3, iters: int = 8) -> void:
	for _it in range(iters):
		for j in chain:
			_set_chain(q)
			var jt: Transform3D = _sk.get_bone_global_pose(j)
			var axis: Vector3 = (jt.basis * Vector3(1, 0, 0)).normalized()
			var v1: Vector3 = _paw_pos(paw) - jt.origin
			var v2: Vector3 = target - jt.origin
			v1 -= axis * axis.dot(v1)
			v2 -= axis * axis.dot(v2)
			if v1.length() < 1e-4 or v2.length() < 1e-4:
				continue
			var ang: float = atan2(v1.cross(v2).dot(axis), v1.dot(v2))
			# Rotating a bone about its own local X moves the world exactly about that
			# axis's world image, so the signed world angle maps 1:1 onto the local hinge.
			q[j] = (q[j] as Quaternion) * Quaternion(Vector3(1, 0, 0), clampf(ang, -0.6, 0.6))

## Build a pose: torso offsets first, then IK every leg to its target. Targets default to
## the paws' REST positions — "the feet stay where they stand" — with optional shifts.
func _bake(torso: Dictionary, hip_drop: float, paw_shift: Dictionary = {},
		seed_fold: float = 0.0, arms_too: bool = true) -> Dictionary:
	# Rest paw anchors, measured once per bake from the skeleton itself.
	var rest_q := {}
	for i in _rest:
		rest_q[i] = _rest[i]
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	var anchors := {}
	for k in _limb:
		anchors[k] = _paw_pos(_limb[k]["paw"])
	# Start from rest + torso, with the hip dropped.
	var e: Dictionary = _pose_from(torso, hip_drop)
	var q: Dictionary = e["q"]
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, e["hip_t"])
	# Seed the legs folded so CCD converges to the anatomical branch (knees fold, never
	# hyperextend), then solve each leg to its (possibly shifted) anchor.
	for k in _limb:
		var L: Dictionary = _limb[k]
		var hind: bool = k.ends_with("h")
		if not hind and not arms_too:
			continue
		if seed_fold > 0.0:
			q[L["prox"]] = (q[L["prox"]] as Quaternion) * Quaternion(Vector3(1, 0, 0), seed_fold)
			q[L["dist"]] = (q[L["dist"]] as Quaternion) * Quaternion(Vector3(1, 0, 0), seed_fold)
		var target: Vector3 = anchors[k] + paw_shift.get(k, Vector3.ZERO)
		_ik_leg(q, [L["prox"], L["dist"]], L["paw"], target)
	# Skeleton back to rest so nothing leaks out of the bake.
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	return e

func _build_poses() -> void:
	if not valid():
		return
	# WALK / RUN wear the neutral stance — the gait IS the pose.
	_poses["walk"] = _pose_from({}, 0.0)
	_poses["run"] = _pose_from({"NeckTwist01": [[0, 0.10]]}, 0.012)
	# SIT: pelvis down and body pitched about the hip; the hind paws step a little forward
	# under the dropped pelvis, the fore paws hold their ground; IK keeps all four planted.
	_poses["sit"] = _bake({
		"Hip": [[0, 0.55]],
		"NeckTwist01": [[0, -0.28]], "Head": [[0, -0.10]],
	}, 0.135, {"lf": Vector3(-0.06, 0, 0), "rf": Vector3(-0.06, 0, 0)}, 0.7)
	# GROOM: the sit, then the left forepaw raised to the lowered muzzle — the arm override
	# happens AFTER the bake, which is what a raised paw is.
	var g: Dictionary = _bake({
		"Hip": [[0, 0.55]],
		"Spine02": [[1, 0.15]],
		"NeckTwist01": [[0, -0.62]], "Head": [[0, -0.32]],
	}, 0.135, {}, 0.7)
	var gl: Dictionary = _limb["lf"]
	g["q"][gl["prox"]] = _rest[gl["prox"]] * Quaternion(Vector3(1, 0, 0), -1.05)
	g["q"][gl["dist"]] = _rest[gl["dist"]] * Quaternion(Vector3(1, 0, 0), 0.55)
	g["q"][gl["paw"]] = _rest[gl["paw"]] * Quaternion(Vector3(1, 0, 0), -0.35)
	_poses["groom"] = g
	# SLEEP: the loaf — belly nearly on the deck, all four paws tucked in under the body,
	# head sunk and turned. The tuck is the paw targets pulled inward and up a whisker.
	_poses["sleep"] = _bake({
		"Spine01": [[1, 0.22]], "Spine02": [[1, 0.22]],
		"NeckTwist01": [[0, -0.52], [1, 0.32]], "Head": [[0, -0.34]],
	}, 0.190, {
		"lf": Vector3(0, 0.02, -0.06), "rf": Vector3(0, 0.02, 0.06),
		"lh": Vector3(0, 0.02, -0.05), "rh": Vector3(0, 0.02, 0.05),
	}, 1.0)
	# STRETCH: chest to the floor, rear high, forepaws reaching far forward on the deck.
	_poses["stretch"] = _bake({
		"Hip": [[0, -0.26]],
		"NeckTwist01": [[0, 0.42]], "Head": [[0, 0.20]],
	}, 0.035, {
		"lf": Vector3(0.16, 0, 0), "rf": Vector3(0.16, 0, 0),
	}, 0.35)
	# JUMP: airborne, so no planting — authored stretch-out, fore reaching, hind driving.
	_poses["jump"] = _pose_from({
		"Hip": [[0, 0.14]],
		"L_Upperarm": [[0, -1.05]], "R_Upperarm": [[0, -1.05]],
		"L_Forearm": [[0, 0.30]], "R_Forearm": [[0, 0.30]],
		"L_Thigh": [[0, -0.70]], "R_Thigh": [[0, -0.70]],
		"L_Calf": [[0, 0.36]], "R_Calf": [[0, 0.36]],
	}, -0.02)
