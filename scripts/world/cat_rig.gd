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

## THE BODY'S OWN AXES, in skeleton space — measured, not assumed (tests/BoneDump prints the
## stand mesh's AABB as 1.0 x 0.566 x 0.265, so the nose-to-tail axis is X, up is Y, across
## the body is Z). The node's yaw carries the whole skeleton, so skeleton space IS body space.
const BODY_FWD := Vector3(1, 0, 0)
const BODY_UP := Vector3(0, 1, 0)
const BODY_SIDE := Vector3(0, 0, 1)

## HOW FAR THE DISTAL JOINTS LAG THE PROXIMAL ONE, in cycles. Overlapping action: an animator
## never keys a whole limb on the same frame — the paw follows the wrist follows the elbow, and
## that lag is most of what separates a live limb from a hinged stick. Small on purpose; past
## about 0.06 the paw visibly detaches from the leg.
const DRAG: float = 0.035

## Metres the paw rises at the two ends of its stance sweep — see `_foot_path`.
const STANCE_ARC: float = 0.012

## THE TAIL, AND IT IS NOT WHERE ANY NAMING CONVENTION WOULD PUT IT.
##
## Three sessions have recorded "the tail has no bones — Tripo's template ends at the pelvis",
## and that is true of the template and FALSE of this fit. tests/CatTailDiag assigns every
## vertex to the bone with the largest weight on it and reports where those vertices sit:
##
##   R_ThighTwist01   29363 verts   centroid (-0.246, 0.251, -0.029)   0.237 m BEHIND the hip
##
## A quarter of the whole mesh, centred well behind the pelvis, elevated, spanning 0.434 m
## along the body axis. That is the tail (with the rump). The auto-rig stretched the RIGHT
## THIGH CHAIN backwards to cover it — which is also the long-standing mystery of why this
## rig's right hind bones are a quarter the length of its left ones (`R_Thigh -> R_Calf` 0.086
## against `L_Thigh -> L_Calf` 0.336): the "thigh" is largely the tail root.
##
## Two consequences, one bad and one good. The bad one is that the tail is a CHILD of R_Thigh,
## so it has been dragged through the gait by the right hind leg for as long as the cat has
## walked — a tail that twitches once per stride in lockstep with one foot. The good one is
## that flaw 5 costs one layer here instead of a re-rig.
##
## Named rather than detected because detecting it means reading 115k vertices at load, and
## cat_rig is handed a Skeleton3D and no mesh. If the cat is ever re-rolled or re-rigged, re-run
## tests/CatTailDiag and change this line; a name that no longer exists disables the layer
## rather than crashing.
const TAIL_BONE := "R_ThighTwist01"
## How far the tail may be driven. Deliberately small: the bone owns the rump as well as the
## tail, so a big rotation bends the hindquarters with it. Verified by render, not by taste.
const TAIL_MAX: float = 0.30

## Footfall phase offsets per limb, in cycles. The gait MODE is not a switch: the active
## offsets are themselves eased between these tables as speed crosses the bands, so a cat
## accelerating from amble to gallop re-times its legs continuously instead of stuttering
## between patterns.
## Footfall offsets per gait. Walk is the cat's LATERAL SEQUENCE (LH, LF, RH, RF a quarter
## apart); the gallop is ROTARY — hinds land nearly together, then the fores, with two
## airborne moments between. These are the orders every quadruped-animation reference
## teaches, and the thing the s37 sine gait ignored.
const WALK_OFF := {"lh": 0.00, "lf": 0.25, "rh": 0.50, "rf": 0.75}
const TROT_OFF := {"lh": 0.00, "rf": 0.02, "rh": 0.50, "lf": 0.52}
const GALLOP_OFF := {"lh": 0.00, "rh": 0.12, "rf": 0.55, "lf": 0.67}

## THE LIMB CYCLE, AS AN ANIMATOR KEYS IT — not as a sine. Keys are
## (cycle_t, reach, flex, paw) with touchdown at t=0: plant reaching, rotate back nearly
## straight through stance (duty ~0.62 walking — a leg is on the ground far longer than it
## swings, and 50/50 is exactly what reads as clockwork), toe-off trailing, then the FOLD —
## the knee/elbow flexes to lift the paw, carries it forward folded, and extends again to
## plant. The fold is the whole difference between an animal and a toy horse.
## `reach` +ve is toward the head, `flex` +ve bends the joint, paw follows through. Signs
## are mapped per limb below — this table is semantic.
const CYC_WALK_FORE := [
	[0.00, 0.30, 0.08, -0.12], [0.30, 0.02, 0.03, 0.02], [0.62, -0.30, 0.06, 0.18],
	[0.72, -0.12, 0.60, 0.38], [0.86, 0.24, 0.42, 0.10], [1.00, 0.30, 0.08, -0.12]]
const CYC_WALK_HIND := [
	[0.00, 0.34, 0.06, 0.00], [0.34, 0.02, 0.03, 0.00], [0.62, -0.34, 0.09, 0.10],
	[0.74, -0.12, 0.72, 0.30], [0.88, 0.28, 0.48, 0.08], [1.00, 0.34, 0.06, 0.00]]
## Gallop: shorter stance (duty ~0.38), far bigger reach and fold. The legs GATHER under
## the body and EXTEND — but half of a real gallop lives in the spine engine below.
const CYC_GAL_FORE := [
	[0.00, 0.55, 0.10, -0.15], [0.24, -0.05, 0.06, 0.10], [0.38, -0.55, 0.12, 0.30],
	[0.55, -0.20, 0.85, 0.45], [0.80, 0.45, 0.55, 0.05], [1.00, 0.55, 0.10, -0.15]]
const CYC_GAL_HIND := [
	[0.00, 0.50, 0.08, 0.00], [0.22, -0.05, 0.05, 0.05], [0.38, -0.60, 0.12, 0.15],
	[0.56, -0.25, 0.95, 0.35], [0.82, 0.42, 0.55, 0.05], [1.00, 0.50, 0.08, 0.00]]
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
var _chat_w: float = 0.0
var _groom_style: int = 0
var _shake_w: float = 0.0
## bone index -> its limb's sagittal hinge, in that bone's OWN local frame. Derived from the
## skeleton's geometry in `_measure_gains`; replaces the hand-written local-X + sign map.
var _hinge: Dictionary = {}
## Each bone's global-pose BASIS at rest, cached once. `_mul_body` uses it to turn an intent
## expressed in body axes ("yaw", "roll") into the rotation that bone actually needs — which is
## how the torso layers stop being a guess about which local axis does what.
var _rest_gb: Dictionary = {}
## Turn-in-place: how fast the body is yawing, eased. Drives the step-in-place gait so the cat
## picks its feet up to turn instead of pivoting like a turntable.
var _yaw_rate: float = 0.0
var _turn_phase: float = 0.0
## THE TAIL. `_tail_up` is carriage (+1 straight up in greeting, -1 clamped down), `_tail_sway`
## is how much it moves and `_tail_rate` how fast — a slow arc while walking, a hard fast flick
## while hunting or annoyed. All three are eased, because a tail that snaps between carriages
## is the one part of a cat that must never look digital.
var _tail_up: float = 0.0
var _tail_sway: float = 0.35
var _tail_rate: float = 1.0
var _tail_up_t: float = 0.0
var _tail_sway_t: float = 0.35
var _tail_rate_t: float = 1.0
var _tail: int = -1

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
	# `blade` is the SCAPULA and `toe` the paw's last joint. Both were sitting unused on this
	# skeleton while the gait swung the limb from the humerus alone. A cat's shoulder blade
	# travels further than almost any other mammal's — it rides up above the spine at the top
	# of the reach and is a large part of why a cat reads as a cat and not as a small dog —
	# and a paw that never rolls at the plant is the other half of "toy horse". Both are
	# optional: `_b` returns -1 on a rig that lacks them and `_mul` ignores -1.
	_limb = {
		"lf": {"prox": _b("L_Upperarm"), "dist": _b("L_Forearm"), "paw": _b("L_Hand"),
			"blade": _b("L_Clavicle"), "toe": -1},
		"rf": {"prox": _b("R_Upperarm"), "dist": _b("R_Forearm"), "paw": _b("R_Hand"),
			"blade": _b("R_Clavicle"), "toe": -1},
		"lh": {"prox": _b("L_Thigh"), "dist": _b("L_Calf"), "paw": _b("L_Foot"),
			"blade": -1, "toe": _b("L_ToeBase")},
		"rh": {"prox": _b("R_Thigh"), "dist": _b("R_Calf"), "paw": _b("R_Foot"),
			"blade": -1, "toe": _b("R_ToeBase")},
	}
	_spine = _b("Spine01")
	_spine2 = _b("Spine02")
	_neck = _b("NeckTwist01")
	_head = _b("Head")
	_hip = _b("Hip")
	_tail = _b(TAIL_BONE)
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
	# THE REST BASES ARE CACHED FIRST, because `_build_poses` now needs them: a pose may state
	# an offset in BODY axes (see `_pose_from`), and converting one takes the bone's rest basis.
	_cache_rest_bases()
	_build_poses()
	_measure_gains()
	_prep_ik()

func _b(nm: String) -> int:
	return int(_idx.get(nm, -1))

## ---------------------------------------------------------------- body-space rotation
##
## WHICH LOCAL AXIS IS "YAW" IS NOT THE SAME QUESTION ON ANY TWO BONES OF THIS RIG, and every
## time it has been answered by reading the code it has been answered wrong. tests/CatYawDiag
## measures it: +0.2 rad about Spine01's local X pitches the head +11.4 deg; about local Y it
## rolls +10.0 AND yaws +5.5; about local Z it YAWS +10.0 and rolls -5.6. So the breath layer,
## which was written as a chest motion about local Z, was in fact turning the cat's head
## sideways by +/-2.6 deg on every pose it has ever worn — the owner's "it looks to the side
## when walking", measured at +3.4 deg mean off the travel line in tests/CatFilm.
##
## The fix is not a better guess. It is to stop expressing torso motion in bone axes at all:
## say "roll the chest 3 degrees" in the BODY's frame and let this convert it. A layer that
## asks for roll then cannot leak yaw, on this rig or on the next species' rig.
##
## The basis used is the bone's REST global pose, cached once, NOT its live one. That is
## deliberate: feeding a live transform back into the rotation that produces it is the exact
## shape of the two accumulator bugs this file's header is about. A constant map cannot
## accumulate, and the torso never travels far enough from rest for the difference to read.
func _cache_rest_bases() -> void:
	if _sk == null:
		return
	var rest_q := {}
	for i in _rest:
		rest_q[i] = _rest[i]
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	for i in _rest:
		_rest_gb[i] = _sk.get_bone_global_pose(i).basis.orthonormalized()

## Rotate `bone` by `ang` about a BODY axis (BODY_UP = yaw, BODY_FWD = roll, BODY_SIDE = pitch).
func _mul_body(bone: int, body_axis: Vector3, ang: float) -> void:
	if bone < 0 or absf(ang) < 1e-6:
		return
	var gb: Basis = _rest_gb.get(bone, Basis.IDENTITY)
	var local_axis: Vector3 = (gb.inverse() * body_axis).normalized()
	_mul(bone, Quaternion(local_axis, ang))

## ---------------------------------------------------------------- measured limb gains
##
## THE TWO SIDES OF THIS RIG ARE NOT THE SAME LENGTH, and the runtime gait did not know.
##
## tests/BoneDump on cat_stand_idle.glb: L_Thigh->L_Calf is 0.336 m and R_Thigh->R_Calf is
## 0.086 m — the right femur is a QUARTER of the left. (L_Upperarm->L_Forearm 0.178 vs R 0.228,
## and the hands and feet differ too.) It is a documented Tripo defect and the pose bake already
## absorbs it, because IK solves each leg with that leg's own bones. The per-frame gait did not:
## it fed the same `reach` and `flex` in RADIANS to both sides, so tests/CatFilm measured the
## left hind paw lifting 206 mm per stride against the right hind's 28 mm — a 7.5x difference,
## which is a limp, and a limp is most of what "choppy" looks like from the front.
##
## So the tables stop being angles and start being INTENTIONS. Measure, once, how far each paw
## actually travels per radian at its own joints, and scale each limb so all four describe
## matched arcs. Measured on the skeleton itself, in the repo's own idiom — the same method the
## axis atlas and the IK bake use, and the reason none of this is a guess.
## THE SWING AXIS IS NOT local X, AND ON ONE LIMB IT NEVER WAS.
##
## The first cut of this function measured how far each paw travels fore-and-aft per radian
## about `SWING` (local X, the axis the whole gait was written against) and got:
##     lf 0.198   rf 0.005   lh 0.200   rh 0.189   metres per radian.
## Three limbs agree to within 5%. The RIGHT FORELIMB is at one fortieth of the others —
## rotating R_Upperarm about its local X does not swing that leg fore-and-aft at all, because
## the auto-rig fitted that bone's frame turned about 90 degrees from its opposite number. The
## sign map above calls the upperarms "MIRRORED" and flips a sign for it; a mirror would have
## given -0.198, not +0.005. So the right foreleg has been driven about the wrong axis for
## every session this gait has existed, and no amount of tuning the tables could fix it.
##
## The answer is not a fourth guess. A limb is a PLANAR linkage: it swings in the sagittal
## plane containing the shoulder, the paw and the body's fore-aft axis. Rotating a joint about
## the normal `n` of that plane displaces the paw by `theta * (n x r)` — so choose
## `n = normalise(r x BODY_FWD)` and positive theta moves the paw FORWARD, on every limb, with
## a gain of exactly |r|. That is geometry, not a convention: it derives the axis AND the sign
## AND the gain from the rig in front of it, so it is equally correct on the next species'
## skeleton and on a re-export of this one.
func _measure_gains() -> void:
	if not valid():
		return
	var rest_q := {}
	for i in _rest:
		rest_q[i] = _rest[i]
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	# One sagittal plane per limb, shared by every joint in that chain so the leg stays planar.
	for k in _limb:
		var L: Dictionary = _limb[k]
		var prox_o: Vector3 = _sk.get_bone_global_pose(L["prox"]).origin
		var r: Vector3 = _paw_pos(L["paw"]) - prox_o
		var n: Vector3 = r.cross(BODY_FWD)
		n = BODY_SIDE if n.length() < 1e-5 else n.normalized()
		for key in ["prox", "dist", "paw", "blade", "toe"]:
			var b: int = int(L[key])
			if b < 0:
				continue
			_hinge[b] = (_sk.get_bone_global_pose(b).basis.orthonormalized().inverse() * n).normalized()
	var base := {}
	for k in _limb:
		base[k] = _paw_pos(_limb[k]["paw"])
	const D: float = 0.25
	var gr := {}
	var gf := {}
	for k in _limb:
		var L: Dictionary = _limb[k]
		_set_chain(rest_q)
		_sk.set_bone_pose_rotation(L["prox"], _rest[L["prox"]] * Quaternion(_hinge_of(L["prox"]), D))
		gr[k] = absf((_paw_pos(L["paw"]) - base[k]).dot(BODY_FWD)) / D
		# The FOLD's gain is simply the KNEE-TO-PAW LEVER — first order and exact. Perturbing
		# the joint and measuring the paw's HEIGHT change (the first attempt) reads a
		# second-order effect on a leg that hangs straight down, so it scaled with the size of
		# the test rotation and came back as noise: 0.010 on one hind against 0.086 on the
		# other, from bones whose real levers are 0.106 and 0.111.
		gf[k] = maxf(base[k].distance_to(_sk.get_bone_global_pose(L["dist"]).origin), 1e-3)
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	# A RIG REPORT, printed once. These numbers no longer scale anything — the legs are solved
	# to a path in metres now, which makes per-limb gain compensation unnecessary by
	# construction — but they are the cheapest possible check that a re-exported or re-rigged
	# cat still has four comparable legs. A `reach` column with one entry near zero means that
	# limb's hinge derivation has gone wrong, and it is worth knowing at load rather than
	# discovering it in a film three sessions later, which is what happened here.
	print("[cat_rig] limb levers m/rad: reach %s  knee %s"
		% [str(_round_d(gr)), str(_round_d(gf))])

## A bone's sagittal hinge in its own local frame, falling back to the historic local-X for
## anything not part of a measured limb chain.
func _hinge_of(bone: int) -> Vector3:
	return _hinge.get(bone, SWING) as Vector3

## ---------------------------------------------------------------- the foot path (runtime IK)
##
## WHY THE LEGS STOPPED BEING DRIVEN AS ANGLES.
##
## With the hinges derived and the amplitudes normalised, the FK gait finally swung all four
## limbs the same distance fore-and-aft — and tests/CatFilm still measured two things it could
## never fix. First, every stance paw SLID at 1.4-1.6 m/s while the body moved at 1.55: the
## paws were not planted at all, they were skating, which is the weightless "moonwalk" read.
## Second, the hind paws' LIFT stayed 6.4x apart (226 mm against 35 mm) even with matched
## fore-aft travel, because the two hind chains sit at different angular positions on their own
## swing circles — the same joint angle traces a mostly-horizontal arc on one side and a
## mostly-vertical one on the other. No amount of per-limb gain can fix that: the fault is that
## a JOINT ANGLE is the wrong thing to author. Where the paw goes is the thing that matters.
##
## So the cycle tables now describe A PATH IN BODY SPACE, and the joints are solved to follow it:
##   STANCE — the paw is on the deck and travels BACKWARD at exactly the speed the body travels
##            FORWARD, so it is stationary in the world. That is foot-lock, and it falls out of
##            the definition rather than being bolted on.
##   SWING  — it lifts, carries forward over an arc, and reaches out to the next plant.
## Both sides are handed the same path relative to their own rest stance, so a rig whose left
## and right bones disagree by a factor of four draws two identical legs.
##
## The solve is ANALYTIC, not CCD. Every limb here is a two-bone chain on a single sagittal
## hinge, so the law of cosines gives both angles in closed form — no iteration, no skeleton
## round-trips, ~20 flops a leg. `_ik_leg`'s hinge-constrained CCD stays where it belongs, at
## pose-BAKE time, where the chain has to reach an arbitrary target from an arbitrary torso.
var _ik: Dictionary = {}
## How far a paw may sweep during stance, metres — the shortest leg's envelope, shared by all
## four. It sets the stride, which is what makes foot-lock exact instead of approximate.
var _sweep_cap: float = 0.24

func _prep_ik() -> void:
	if not valid():
		return
	var rest_q := {}
	for i in _rest:
		rest_q[i] = _rest[i]
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	for k in _limb:
		var L: Dictionary = _limb[k]
		var P: Vector3 = _sk.get_bone_global_pose(L["prox"]).origin
		var D0: Vector3 = _sk.get_bone_global_pose(L["dist"]).origin
		var W0: Vector3 = _paw_pos(L["paw"])
		var n: Vector3 = (W0 - P).cross(BODY_FWD)
		n = BODY_SIDE if n.length() < 1e-5 else n.normalized()
		var a: float = (D0 - P).length()
		var b: float = (W0 - D0).length()
		var c0: float = (W0 - P).length()
		if a < 1e-4 or b < 1e-4 or c0 < 1e-4:
			continue
		var e0: Vector3 = _flat(W0 - P, n)
		# WHICH WAY THE KNEE FOLDS IS MEASURED, NOT ASSUMED — the same discipline the hinge
		# derivation uses, and the reason this works on a rig whose two sides disagree. Rotate
		# the lower bone a little about its own hinge and see whether the chain shortens.
		_set_chain(rest_q)
		_sk.set_bone_pose_rotation(L["dist"], _rest[L["dist"]] * Quaternion(_hinge_of(L["dist"]), 0.2))
		var c_test: float = (_paw_pos(L["paw"]) - P).length()
		_set_chain(rest_q)
		var par: int = _sk.get_bone_parent(L["prox"])
		var par_t: Transform3D = _sk.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
		_ik[k] = {
			"P": P, "n": n, "a": a, "b": b, "c0": c0, "e0": e0, "W0": W0,
			"alpha0": _tri_angle(a, c0, b), "beta0": _tri_angle(a, b, c0),
			# +1 when a positive rotation at the knee FOLDS the leg.
			"knee": -1.0 if c_test > c0 else 1.0,
			# HOW FAR THIS LEG CAN ACTUALLY SWING — roughly 35 degrees either side of the
			# resting leg, which is about a cat's limit. The SHORTEST of the four sets the
			# stride for all of them (see `_sweep_cap`), because letting each limb clamp at
			# its own envelope truncates the two hinds by different amounts and puts the limp
			# straight back.
			"sweep_max": 1.15 * c0,
			# Which side of the chain line the knee sits on, so the thigh's own rotation adds
			# or subtracts the triangle's apex angle.
			"side": 1.0 if _flat(D0 - P, n).cross(e0).dot(n) < 0.0 else -1.0,
			# The socket this leg hangs from, and where it sat at rest — see `_solve_leg`.
			"parent": par,
			"parent_b0": par_t.basis.orthonormalized(),
			"parent_off": par_t.affine_inverse() * P,
		}
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	# The stride the whole animal can hold, set by whichever leg runs out first.
	_sweep_cap = 1e9
	for k in _ik:
		_sweep_cap = minf(_sweep_cap, float(_ik[k]["sweep_max"]))
	if _sweep_cap > 1e8:
		_sweep_cap = 0.24
	print("[cat_rig] foot-lock sweep %.3f m -> stride %.3f m walking, %.3f m at a gallop"
		% [_sweep_cap, _sweep_cap / 0.62, _sweep_cap / 0.38])

## A vector flattened into the plane perpendicular to `n`, normalised.
func _flat(v: Vector3, n: Vector3) -> Vector3:
	var f: Vector3 = v - n * n.dot(v)
	return Vector3(1, 0, 0) if f.length() < 1e-6 else f.normalized()

## The angle opposite side `opp` in a triangle with the other two sides `s1`, `s2`.
func _tri_angle(s1: float, s2: float, opp: float) -> float:
	return acos(clampf((s1 * s1 + s2 * s2 - opp * opp) / maxf(2.0 * s1 * s2, 1e-6), -1.0, 1.0))

## Solve one leg to put its paw at `target` (skeleton space). Returns [prox, dist] rotations
## about that limb's hinge, RELATIVE TO REST — which is exactly the form the additive layer
## wants, so the result composes onto the blended pose like every other layer here.
func _solve_leg(k: String, target: Vector3) -> Array:
	var S: Dictionary = _ik.get(k, {})
	if S.is_empty():
		return [0.0, 0.0]
	# THE LEG ROOT MOVES, AND THE SOLVE HAS TO KNOW. Half of a gallop is the spine: the back
	# rounds and hollows, the pelvis tucks, the hip bobs — so the shoulder and hip sockets the
	# legs hang from are somewhere different every frame. Solved against the REST socket the
	# targets drift, and because the four sockets drift by different amounts it drew as a limp
	# at speed (hind reach ratio 0.70) on a walk that was already symmetric.
	#
	# So the target is carried back into rest space through the PARENT's motion, and the solve
	# stays in the frame it was measured in. The parent chain is read, never the limb's own
	# bones, so this cannot feed back on itself — a leg's own solve has no influence on where
	# its socket is.
	var P: Vector3 = S["P"]
	var n: Vector3 = S["n"]
	var par: int = int(S["parent"])
	if par >= 0:
		var bp: Transform3D = _sk.get_bone_global_pose(par)
		var r: Basis = bp.basis.orthonormalized() * (S["parent_b0"] as Basis).inverse()
		var p_live: Vector3 = bp * (S["parent_off"] as Vector3)
		target = P + r.inverse() * (target - p_live)
	var a: float = S["a"]
	var b: float = S["b"]
	var v: Vector3 = target - P
	v -= n * n.dot(v)
	# OUT OF REACH IS RESOLVED UPWARD, NOT INWARD.
	#
	# The obvious clamp — scale the target back along its own ray — shortens the stride, and
	# it shortens it by a DIFFERENT amount on each leg because no two chains on this rig are
	# the same length. That is what kept the limp alive at a gallop (hind reach ratio 0.67)
	# after the walk had been made symmetric: the left hind is straight in its bind pose, so
	# it ran out of reach first and quietly gave up 70 mm of stride the right hind kept.
	#
	# A real leg at full stretch does not shorten its stride, it LIFTS ITS PAW. So the target
	# is raised until it is reachable and its fore-aft component is preserved exactly — which
	# keeps both sides covering the same ground, whatever their bones are doing.
	var cmax: float = (a + b) * 0.985
	if v.length() > cmax:
		var up_p: Vector3 = _flat(BODY_UP, n)
		var hb: float = v.dot(up_p)
		var disc: float = hb * hb - (v.length_squared() - cmax * cmax)
		# THE NEAR ROOT, AND ONLY A LITTLE OF IT. Both roots put the paw back on the reach
		# sphere; the far one carries it up past the socket and out the other side, which
		# measured as a 636 mm paw lift on a 0.66 m cat — the leg swinging over its own hip.
		# The near root is the small rise that was wanted, but it is CAPPED: the left hind is
		# straight in its bind pose and so is at its limit almost all the time, and an
		# uncapped rise let it float 143 mm while its opposite number stayed at 43. Past the
		# cap the honest answer is that this leg cannot cover that ground, so fall back to
		# shortening the reach.
		if disc >= 0.0:
			v += up_p * clampf(-hb - sqrt(disc), 0.0, 0.016)
		if v.length() > cmax:
			v = v.normalized() * cmax
	var c: float = clampf(v.length(), absf(a - b) * 1.05 + 1e-3, cmax)
	var e: Vector3 = _flat(v, n)
	var e0: Vector3 = S["e0"]
	var dphi: float = atan2(e0.cross(e).dot(n), e0.dot(e))
	var alpha: float = _tri_angle(a, c, b)
	var beta: float = _tri_angle(a, b, c)
	var prox: float = dphi + float(S["side"]) * (alpha - float(S["alpha0"]))
	var dist: float = float(S["knee"]) * (float(S["beta0"]) - beta)
	return [prox, dist]

## THE FOOT PATH, in metres relative to this limb's own rest stance: [fore-aft, lift].
##
## `duty` is the fraction of the cycle the paw spends on the deck — 0.62 at a walk, 0.38 at a
## gallop, which is the number the old keyframe tables encoded and the thing that stops a gait
## reading as clockwork. `sweep` is how far the paw travels during stance, and it is NOT the
## stride: the body covers `stride` in a whole cycle, so a paw down for `duty` of that cycle
## must travel `stride * duty` backwards to stay put. Getting that product right is the whole
## of foot-lock.
func _foot_path(t: float, duty: float, sweep: float, lift: float) -> Vector2:
	if t < duty:
		# STANCE — a straight line backwards at body speed, on a very shallow arc.
		#
		# The arc is not decoration. This rig's left hind leg is DEAD STRAIGHT in its bind
		# pose (hip-to-paw 0.214 m against bones of 0.144 + 0.070), so the paw sits exactly on
		# the edge of its own reachable set and cannot move horizontally at all without
		# shortening the chain. A flat stance therefore asks for a target the leg cannot hit,
		# the solve clamps it, and — because the two hinds clamp by different amounts — the
		# limp comes back at speed. Twelve millimetres of rise at the ends of the sweep buys
		# the headroom, and it is what a real paw does anyway: it lands toe-first, rolls flat
		# through mid-stance, and pushes off the toes.
		var u: float = t / maxf(duty, 1e-4)
		var e: float = 2.0 * u - 1.0
		return Vector2(sweep * (0.5 - u), STANCE_ARC * e * e)
	# SWING — up fast, forward, and DOWN INTO THE PLANT rather than dropping onto it. The
	# forward travel is eased at both ends (the paw is momentarily still relative to the body
	# at toe-off and at touchdown, which is what a real limb does) while the lift runs on a
	# sine, so the peak of the arc sits mid-swing where it belongs.
	var s: float = (t - duty) / maxf(1.0 - duty, 1e-4)
	var se: float = s * s * (3.0 - 2.0 * s)
	return Vector2(sweep * (se - 0.5), lift * sin(PI * s))

func _round_d(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[k] = snappedf(float(d[k]), 0.001)
	return o

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

## SAY WHAT THE TAIL IS DOING. `up` is carriage: +1 is the vertical greeting flag a cat raises
## when it comes to meet someone, 0 is level, -1 is clamped down over the hocks. `sway` is how
## wide it moves and `rate` how fast — the two together are the whole vocabulary, because a
## slow wide arc means content and a hard fast flick means the opposite, and everyone reads
## both without being taught. Eased in `tick`, never snapped.
func tail(up: float, sway: float, rate: float) -> void:
	_tail_up_t = clampf(up, -1.0, 1.0)
	_tail_sway_t = clampf(sway, 0.0, 1.5)
	_tail_rate_t = clampf(rate, 0.0, 14.0)

## WHICH WASH IS IT? A cat does not have one grooming animation, it has a repertoire, and
## running the same paw-lick every time is what makes an idle animal read as a loop. The
## styles differ in which part of the body does the work, so they are legible from across a
## deck without any facial detail:
##   0 PAW    — the classic. Forepaw up to the lowered muzzle, short quick strokes.
##   1 FLANK  — head right round to the shoulder and side, long slow strokes, body curled in.
##   2 CHEST  — head down between the forelegs, small strokes, the most hunched of the three.
##
## THE EAR SCRATCH IS NOT HERE, and it was written and then cut. It is the most recognisable
## grooming action a cat has, and it needs a HIND foot up behind the ear — from a pose whose
## hip is dropped and whose hind legs are already folded underneath, which is what a sit is.
## Driven from there the leg has nowhere to go and it filmed as a twitch rather than a scratch.
## It wants its own authored pose with the hind leg free, which is real pose work; shipping a
## spasm in the meantime is worse than shipping three washes that read.
func groom_style(i: int) -> void:
	_groom_style = clampi(i, 0, 2)
	# The paw-lick needs the pose that holds a forepaw up; the others need the one that does
	# not. Retargeting here rather than at the call site means a caller cannot pick a style
	# and forget the body that goes with it.
	if _target == "groom" or _target == "groom_flat":
		set_pose("groom" if _groom_style == 0 else "groom_flat", _blend_rate)

## A FULL-BODY SHAKE — the wet-dog ripple, which cats do on waking, after rain, and after any
## indignity. Decays like the look, so one call is one shake.
func shake(w: float) -> void:
	_shake_w = maxf(_shake_w, clampf(w, 0.0, 1.0))

## THE CHATTER — the staccato jaw rattle a cat makes at a bird it cannot reach. There is no jaw
## bone on this rig, so it is carried as a fast, tiny head tremor, which is what actually reads
## at game distance anyway. Decays like the look, so it stops unless renewed.
func chatter(w: float) -> void:
	_chat_w = maxf(_chat_w, clampf(w, 0.0, 1.0))

## Point the head. Weight decays in tick, so a glance fades unless renewed.
func look(yaw: float, pitch: float, weight: float) -> void:
	_look_yaw = clampf(yaw, -1.05, 1.05)
	_look_pitch = clampf(pitch, -0.5, 0.5)
	_look_w = maxf(_look_w, clampf(weight, 0.0, 1.0))

## THE ONE WRITER. Called once per frame by ship_cat with:
##   dt     — the (possibly AiBudget-summed) delta
##   speed  — the speed the animal is trying to move at, m/s
##   moved  — metres ACTUALLY covered this frame (drives the phase; a blocked cat's legs stop)
##   yaw_rate — rad/s the BODY is actually turning at, which drives the turn-in-place step
##              cycle. Optional so every existing caller keeps working unchanged.
func tick(dt: float, speed: float, moved: float, yaw_rate: float = 0.0) -> void:
	if not valid():
		return
	var k: float = 1.0 - exp(-_blend_rate * dt)
	var pose: Dictionary = _poses.get(_target, _poses["stand"])
	# 1. Blend every bone toward the target pose — this dict is the ONLY persistent state,
	# and only pose targets ever land in it.
	for i in _cur_q:
		var want: Quaternion = pose["q"].get(i, _rest[i])
		_cur_q[i] = (_cur_q[i] as Quaternion).slerp(want, k)
	_cur_hip = _cur_hip.lerp(pose["hip_t"], k)
	# The frame's write starts as the blended pose; everything after this multiplies into
	# the frame, not into the state.
	_out.clear()
	_out_hip = _cur_hip
	# 2. Gait weight and smoothed speed. The weight fades IN with motion and OUT at rest,
	# so stopping mid-stride eases the legs home instead of snapping them.
	var moving: float = clampf(speed / 0.4, 0.0, 1.0) * clampf(moved / maxf(dt * 0.05, 1e-6), 0.0, 1.0)
	# Gait only makes sense on locomotion poses.
	if _target != "walk" and _target != "run" and _target != "stand":
		moving = 0.0
	_gait_w = lerpf(_gait_w, moving, 1.0 - exp(-8.0 * dt))
	_speed_s = lerpf(_speed_s, speed, 1.0 - exp(-6.0 * dt))
	# 3. Phase from DISTANCE, not time — and the STRIDE COMES OUT OF THE ANIMAL'S OWN LEGS.
	#
	# It used to be `0.52 + speed/4.4 * 0.35`, two hand-picked numbers, and they asked for a
	# stride of 0.64 m from a cat whose hind leg is 0.19 m from hip to paw. A leg that long can
	# sweep about 0.25 m of deck however it is driven, so the other 0.39 m per cycle had to come
	# from somewhere, and it came from the paws SLIDING — 24 to 30 mm every frame, measured, at
	# almost exactly body speed. That is the skating, and no keyframe could have fixed it,
	# because the gait was asking for ground the animal did not have the legs to cover.
	#
	# Now: a paw is down for `duty` of the cycle and can sweep `_sweep_cap` while it is there,
	# so the stride is exactly `_sweep_cap / duty` and foot-lock is a consequence rather than a
	# feature. It falls out at every speed — a shorter duty at a gallop lengthens the stride on
	# its own, which is what a real animal does — and it re-derives itself for any future rig
	# whose legs are a different length.
	var mix: float = clampf((_speed_s - WALK_V) / (TROT_V - WALK_V), 0.0, 1.0)
	var duty: float = lerpf(0.62, 0.38, mix)
	var stride: float = maxf(_sweep_cap, 0.05) / duty
	_phase = fposmod(_phase + moved / stride, 1.0)
	# 3b. TURN IN PLACE IS A GAIT, NOT A TURNTABLE (flaw 4). `_face` lerps the node's yaw with
	# the feet planted, so a cat asked to turn round pivots like a display stand and all four
	# paws skate. A real cat picks its feet up and shuffles them round. When the body is
	# yawing appreciably and going nowhere, run a low quick diagonal-pair step cycle driven by
	# the YAW — the same "phase comes from what the body actually did" rule this file already
	# applies to translation, applied to rotation.
	_yaw_rate = lerpf(_yaw_rate, yaw_rate, 1.0 - exp(-10.0 * dt))
	var turn_w: float = clampf((absf(_yaw_rate) - 0.30) / 1.10, 0.0, 1.0) \
		* clampf(1.0 - _gait_w * 1.6, 0.0, 1.0)
	if _target != "walk" and _target != "run" and _target != "stand":
		turn_w = 0.0
	_turn_phase = fposmod(_turn_phase + absf(_yaw_rate) * dt * 0.42, 1.0)
	# 4. The gait — keyframed limb cycles plus the spine engine, if any of it is live.
	var step_w: float = maxf(_gait_w, turn_w)
	if step_w > 0.003:
		# A turning shuffle is a diagonal-pair pattern that barely reaches at all — it is
		# almost pure lift-and-place. Blend toward that when the turn is what is driving.
		var turning: float = clampf(turn_w / maxf(step_w, 1e-5), 0.0, 1.0)
		var base_ph: float = lerpf(_phase, _turn_phase, turning)
		var amp: float = (0.85 + 0.15 * mix) * step_w
		var reach_k: float = lerpf(1.0, 0.22, turning)
		for limb_key in WALK_OFF:
			# Offsets ease walk -> trot -> gallop so the footfall order re-times
			# continuously as the animal changes pace.
			var off: float
			if mix < 0.5:
				off = lerpf(WALK_OFF[limb_key], TROT_OFF[limb_key], mix * 2.0)
			else:
				off = lerpf(TROT_OFF[limb_key], GALLOP_OFF[limb_key], mix * 2.0 - 1.0)
			off = lerpf(off, TROT_OFF[limb_key], turning)
			var ph: float = fposmod(base_ph + off, 1.0)
			# OVERLAPPING ACTION: the knee, then the paw, then the toe are read a little LATER
			# in the cycle than the shoulder, so the limb unfolds down its own length instead
			# of every joint hitting its key on the same frame. It is the cheapest thing that
			# separates a live limb from a hinged stick.
			var ph_t: float = fposmod(ph - DRAG, 1.0)
			var fore: bool = limb_key.ends_with("f")
			var w: Array = _cyc_eval(CYC_WALK_FORE if fore else CYC_WALK_HIND, ph)
			var g: Array = _cyc_eval(CYC_GAL_FORE if fore else CYC_GAL_HIND, ph)
			var wt: Array = _cyc_eval(CYC_WALK_FORE if fore else CYC_WALK_HIND, ph_t)
			var gt: Array = _cyc_eval(CYC_GAL_FORE if fore else CYC_GAL_HIND, ph_t)
			# The tables now shape the parts of the limb that ARE angles — the scapula's travel
			# and the paw's roll through the plant. Where the paw itself goes is a path, below.
			var reach: float = lerpf(w[0], g[0], mix) * amp * reach_k
			var paw: float = lerpf(wt[2], gt[2], mix) * amp
			var L: Dictionary = _limb[limb_key]
			# THE LEG FOLLOWS A PATH, NOT AN ANGLE (see `_foot_path` / `_solve_leg`). Stated in
			# METRES in the body's own frame and handed to both sides identically, which is why
			# a rig whose left femur is four times its right draws two matching legs; and the
			# stance leg tracks backward at exactly the speed the body goes forward, which is
			# what plants it. The duty factor is the same 0.62-walking / 0.38-galloping the
			# keyed tables carried, and it is what stops a gait reading as clockwork.
			# ONE SWEEP FOR ALL FOUR PAWS. It is set by the SHORTEST limb, because on a rigid
			# body every paw must cover the same ground per cycle or the animal tears itself
			# apart — and because capping each limb at its own envelope is what put the limp
			# back: the two hinds have different geometry, so per-limb clamping truncated them
			# by different amounts and the hind reach ratio went straight back to 1.23.
			var lift_m: float = lerpf(0.034, 0.098, mix) * (1.0 if fore else 0.88)
			var sweep_m: float = _sweep_cap * reach_k
			var pth: Vector2 = _foot_path(ph, duty, sweep_m, lift_m)
			var target: Vector3 = (_ik.get(limb_key, {}).get("W0", Vector3.ZERO) as Vector3) \
				+ BODY_FWD * pth.x + BODY_UP * pth.y
			var sol: Array = _solve_leg(limb_key, target)
			# Eased in by the gait weight so a cat coming to a stop hands its legs back to the
			# blended pose instead of dropping them.
			# THE TAIL IS PARENTED TO THE RIGHT HIND LEG, so whatever the gait does to that
			# thigh is done to the tail as well — a tail that jerks once per stride in lockstep
			# with one foot, which is not a thing any cat does. Cancel it about the same body
			# axis the swing was applied on, so the tail is free to be driven on its own below.
			if limb_key == "rh" and _tail >= 0:
				_mul_body(_tail, (_ik.get("rh", {}).get("n", BODY_SIDE) as Vector3),
					-float(sol[0]) * step_w)
			_mul(L["prox"], Quaternion(_hinge_of(L["prox"]), float(sol[0]) * step_w))
			_mul(L["dist"], Quaternion(_hinge_of(L["dist"]), float(sol[1]) * step_w))
			_mul(L["paw"], Quaternion(_hinge_of(L["paw"]), paw))
			# THE SHOULDER BLADE, which this rig has had all along and nothing has ever moved.
			# A cat's scapula travels further than almost any other mammal's — it rides up over
			# the line of the spine at the top of the reach — and it is why a walking cat's
			# front end flows instead of hinging at the humerus. A third of the reach.
			_mul(L["blade"], Quaternion(_hinge_of(L["blade"]), reach * 0.34))
			# THE TOE. A paw that never rolls through the plant is the other half of the toy
			# horse: contact is heel-ish down, roll forward, push off the toes.
			_mul(L["toe"], Quaternion(_hinge_of(L["toe"]), paw * 0.5))
		# THE SPINE ENGINE — half of a gallop is the back. The body GATHERS (spine rounds,
		# pelvis tucks, hips rise) as the hinds come under, and EXTENDS (back hollows, full
		# stretch) as the fores reach. Scaled by the gallop mix so a walking spine only
		# carries the gentle lateral sway a walking cat has.
		#
		# EVERY TORSO LAYER BELOW IS NOW EXPRESSED IN BODY AXES (see `_mul_body`). Written in
		# bone axes they were a guess, and the guess was wrong: tests/CatYawDiag measures the
		# "sway" axis (local Y) as 66% roll and only 27% of the yaw it was asking for, and the
		# breath axis (local Z) as 87% YAW — which is what turned the cat's head off its line
		# of travel on every pose it has ever worn.
		var body_ph: float = base_ph * TAU
		var ext: float = sin(body_ph)
		var gal: float = mix * _gait_w
		if gal > 0.01:
			_mul_body(_spine, BODY_SIDE, ext * 0.26 * gal)
			_mul_body(_spine2, BODY_SIDE, ext * 0.16 * gal)
			_mul_body(_hip, BODY_SIDE, -ext * 0.22 * gal)
			_mul_body(_neck, BODY_SIDE, -ext * 0.10 * gal)
			_out_hip += Vector3(0, absf(cos(body_ph)) * 0.030 * gal, 0)
		var sway: float = sin(body_ph)
		var walk_w: float = (1.0 - mix) * step_w
		if walk_w > 0.01:
			# THE BODY SNAKES, THE HEAD DOES NOT — the owner's ask, by construction rather
			# than by tuning. A walking cat's trunk really does carry a small lateral S-bend
			# and a weight-shift roll, but its head stays locked on where it is going; cats
			# are among the best head-stabilisers there are. So the two spine yaws are equal
			# and OPPOSITE: the bend is fully visible in the trunk and sums to exactly zero by
			# the time it reaches the neck. The pelvis roll is likewise cancelled at the neck,
			# so the face stays level as well as straight.
			var bend: float = sway * 0.055 * walk_w
			_mul_body(_spine, BODY_UP, bend)
			_mul_body(_spine2, BODY_UP, -bend)
			var roll: float = sway * 0.050 * walk_w
			_mul_body(_hip, BODY_FWD, roll)
			_mul_body(_neck, BODY_FWD, -roll * 0.8)
			_out_hip += Vector3(0, absf(sin(body_ph * 2.0)) * 0.010 * walk_w, 0)
	# 5. Idle life on top of ANY pose: slow breath always; it is what stops a still pose
	# reading as a freeze-frame. Softer while asleep.
	#
	# THE BREATH USED TO TURN THE CAT'S HEAD, and this is the owner's "it looks to the side
	# when walking". It was applied about the spine's local Z at 0.032 rad, and local Z on
	# this rig is 87% YAW (tests/CatYawDiag) — so the face swung +/-2.6 deg off the line of
	# travel every few seconds, in every state, for as long as the cat has existed.
	# tests/CatFilm measured the live walk at +3.4 deg mean and +6.4 worst, never once
	# crossing to the other side. Breathing is the CHEST rising: a pitch, at the ribs,
	# cancelled at the neck so the head is not carried along with it.
	var t: float = Time.get_ticks_msec() / 1000.0
	var slept: bool = _target == "sleep"
	var breath: float = sin(t * (0.8 if slept else 1.6)) * (0.016 if slept else 0.022)
	_mul_body(_spine, BODY_SIDE, breath)
	_mul_body(_spine2, BODY_SIDE, breath * 0.55)
	_mul_body(_neck, BODY_SIDE, -breath * 1.35)
	# 5b. THE TAIL — the loudest thing a cat says and the only channel this body has for it.
	# There is no facial rig, the ears do not move and the pupils are painted on, so carriage
	# and sway carry the entire signal: up and quivering to greet you, out and arcing slowly
	# while it walks, flat and flicking while it hunts, still while it sleeps. Eased hard,
	# because a tail that snaps between carriages is the one part of a cat that must never
	# look digital.
	if _tail >= 0:
		var te: float = 1.0 - exp(-3.5 * dt)
		_tail_up = lerpf(_tail_up, _tail_up_t, te)
		_tail_sway = lerpf(_tail_sway, _tail_sway_t, te)
		_tail_rate = lerpf(_tail_rate, _tail_rate_t, te)
		_mul_body(_tail, BODY_SIDE, -_tail_up * TAIL_MAX)
		_mul_body(_tail, BODY_UP, sin(t * _tail_rate) * _tail_sway * TAIL_MAX)
	if _target == "groom" or _target == "groom_flat":
		# THE WASH, and there is more than one of them. All four ride the blended groom pose
		# rather than replacing it, and all four are expressed in body axes at the torso so
		# none of them can leak a yaw into the head the way the breath layer used to.
		match _groom_style:
			1:
				# FLANK. The head goes right round to the shoulder and the strokes are long
				# and slow; the trunk curls toward the side being worked on.
				var s1: float = sin(t * 2.1)
				_mul_body(_neck, BODY_UP, 0.55 + s1 * 0.16)
				_mul_body(_head, BODY_UP, 0.30)
				_mul_body(_head, BODY_SIDE, -0.22 + s1 * 0.14)
				_mul_body(_spine2, BODY_UP, 0.16)
			2:
				# CHEST. Head straight down between the forelegs, small fast strokes, and the
				# most hunched of the set.
				var s2: float = sin(t * 5.0)
				_mul_body(_neck, BODY_SIDE, -0.42 + s2 * 0.10)
				_mul_body(_head, BODY_SIDE, -0.26 + s2 * 0.12)
				_mul_body(_spine2, BODY_SIDE, -0.12)
			_:
				# PAW. The classic: forepaw up to the lowered muzzle, short quick strokes.
				var stroke: float = sin(t * 4.2)
				_mul(_neck, Quaternion(SWING, -stroke * 0.13))
				_mul(_head, Quaternion(SWING, -stroke * 0.16))
				var L2: Dictionary = _limb["lf"]
				_mul(L2["dist"], Quaternion(SWING, stroke * 0.10))
	# 5b2. THE SHAKE — a fast damped ripple that runs from the shoulders back, which is what a
	# cat does on waking, after rain, and after anything undignified. Rolling the segments in
	# sequence rather than together is the whole effect; in phase it is a wobble, out of phase
	# it is a shake.
	_shake_w = maxf(0.0, _shake_w - dt * 1.4)
	if _shake_w > 0.01:
		var sh: float = _shake_w * _shake_w        # dies away rather than stopping dead
		_mul_body(_neck, BODY_FWD, sin(t * 30.0) * 0.30 * sh)
		_mul_body(_spine2, BODY_FWD, sin(t * 30.0 - 0.7) * 0.24 * sh)
		_mul_body(_spine, BODY_FWD, sin(t * 30.0 - 1.4) * 0.20 * sh)
		_mul_body(_hip, BODY_FWD, sin(t * 30.0 - 2.1) * 0.16 * sh)
	# 5c. The chatter, if a bird is being watched and cannot be had.
	_chat_w = maxf(0.0, _chat_w - dt * 1.2)
	if _chat_w > 0.01:
		_mul_body(_head, BODY_SIDE, sin(t * 34.0) * 0.042 * _chat_w)
		_mul_body(_head, BODY_UP, sin(t * 29.0) * 0.016 * _chat_w)
	# 6. The look, LAST, so attention wins over everything.
	_look_w = maxf(0.0, _look_w - dt * 1.5)
	if _look_w > 0.01 and _target != "sleep":
		var wq := Quaternion(Vector3(0, 1, 0), _look_yaw * 0.55 * _look_w) \
			* Quaternion(SWING, _look_pitch * 0.5 * _look_w)
		_mul(_neck, wq)
		_mul(_head, Quaternion(Vector3(0, 1, 0), _look_yaw * 0.45 * _look_w) \
			* Quaternion(SWING, _look_pitch * 0.5 * _look_w))
	# 7. Write the skeleton, once — the blended state where no layer touched a bone, the
	# composed frame where one did.
	for i in _cur_q:
		_sk.set_bone_pose_rotation(i, _out.get(i, _cur_q[i]))
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _out_hip)

## Evaluate a limb cycle table at cycle position `t` (0..1). Returns [reach, flex, paw].
##
## THIS WAS THE CHOPPINESS, and it is worth stating precisely because three sessions of tuning
## the numbers could never have found it — the fault was not in any number, it was in what
## happened BETWEEN them.
##
## The previous version eased every segment with `0.5 - 0.5*cos(k*PI)`. That is a smoothstep:
## its derivative is ZERO at both ends. Applied to every segment of a six-key table it does not
## smooth the cycle, it PUNCTUATES it — the paw's velocity is forced to zero at every single
## key, so a limb that should accelerate once, carry, and decelerate into the plant instead
## stops and restarts five times a stride. tests/CatFilm measured it at 4.5 near-stops per gait
## cycle per paw, with peak paw speeds of 3.7 m/s on a cat walking at 1.55. That is the owner's
## "still choppy", exactly, and it is an interpolation artefact rather than a gait fault.
##
## Now: a CYCLIC Catmull-Rom. It still passes through every authored key — the poses an animator
## chose are untouched — but each key's tangent is estimated from its neighbours, so velocity is
## continuous across the whole cycle and the only places the paw actually stops are the places
## the motion genuinely reverses (the plant, the top of the fold). The table WRAPS: the key
## before t=0 is the second-to-last key sitting at t-1, so the plant is smooth across the seam
## instead of being a hard restart every stride.
##
## Tangents are scaled by TAN_K < 1. Full Catmull-Rom overshoots between unevenly spaced keys,
## and an overshoot on `flex` at the plant drives the paw through the deck.
const TAN_K: float = 0.82

func _cyc_eval(tab: Array, t: float) -> Array:
	# The tables repeat their first key at t=1, so the distinct keys are 0..n-2 and the wrap
	# neighbours come from that range.
	var n: int = tab.size()
	var last: int = n - 1
	var seg: int = 0
	for i in range(last):
		if t <= float(tab[i + 1][0]):
			seg = i
			break
		seg = last - 1
	var p1: Array = tab[seg]
	var p2: Array = tab[seg + 1]
	var t1: float = float(p1[0])
	var t2: float = float(p2[0])
	# Wrapped neighbours, with their times shifted into this segment's own frame so the
	# tangents are correct across the seam rather than merely continuous-looking.
	var i0: int = seg - 1
	var t0: float = 0.0
	var p0: Array
	if i0 < 0:
		p0 = tab[last - 1]
		t0 = float(p0[0]) - 1.0
	else:
		p0 = tab[i0]
		t0 = float(p0[0])
	var i3: int = seg + 2
	var t3: float = 0.0
	var p3: Array
	if i3 > last:
		p3 = tab[1]
		t3 = float(p3[0]) + 1.0
	else:
		p3 = tab[i3]
		t3 = float(p3[0])
	var span: float = t2 - t1
	var k: float = 0.0 if span <= 1e-6 else clampf((t - t1) / span, 0.0, 1.0)
	var k2: float = k * k
	var k3: float = k2 * k
	# Cubic Hermite basis.
	var h00: float = 2.0 * k3 - 3.0 * k2 + 1.0
	var h10: float = k3 - 2.0 * k2 + k
	var h01: float = -2.0 * k3 + 3.0 * k2
	var h11: float = k3 - k2
	var out: Array = [0.0, 0.0, 0.0]
	for c in range(1, 4):
		var v0: float = float(p0[c])
		var v1: float = float(p1[c])
		var v2: float = float(p2[c])
		var v3: float = float(p3[c])
		# Non-uniform Catmull-Rom tangents: the secant through the neighbours, in this
		# segment's parameter units.
		var m1: float = TAN_K * (v2 - v0) / maxf(t2 - t0, 1e-6) * span
		var m2: float = TAN_K * (v3 - v1) / maxf(t3 - t1, 1e-6) * span
		out[c - 1] = h00 * v1 + h10 * m1 + h01 * v2 + h11 * m2
	return out

## THE FRAME'S OUTPUT, composed fresh every tick: _out starts as a copy of the blended
## pose state and the additive layers (gait, breath, strokes, look) multiply into _OUT,
## never into _cur_q. The first version multiplied into _cur_q itself — the persistent
## state — so every per-frame additive ACCUMULATED: the skeleton settled ~30 deg from any
## target (measured off the live game: Hip 31.5 deg, Spine01 29.8 deg from rest while
## "walking"), which drew as a permanently reared, twisted animal. The comment on that
## version claimed additives could not accumulate; the code did the opposite. Kept as the
## sharpest example this repo has of a comment asserting what the code must do instead of
## what it does.
var _out: Dictionary = {}
var _out_hip: Vector3 = Vector3.ZERO
func _mul(bone: int, q: Quaternion) -> void:
	if bone < 0:
		return
	_out[bone] = (_out.get(bone, _cur_q[bone]) as Quaternion) * q

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
## Axis codes 0/1/2 are the bone's own local X/Y/Z. Codes 3/4/5 are the BODY's pitch / yaw /
## roll, converted through that bone's rest basis — and on any bone whose local frame is not
## aligned with the body, those are the only ones that mean what they say.
##
## THE HIP IS SUCH A BONE, AND IT COST THE SIT POSE. `sit` asked for 0.58 rad about the Hip's
## local X, meaning "pitch the body up about the pelvis". tests/CatYawDiag measures what Hip
## local X actually does, per 0.2 rad: roll +8.03, pitch +5.18, yaw -5.92. It is not a pitch
## axis at all — it is mostly ROLL. At 0.58 rad that is roughly 23 degrees of roll and 17 of
## yaw, and the rear-view reel shows the result exactly: a cat that appears to have fallen
## over on its side with its head twisted up, which is the owner's "the hind legs trail
## instead of tucking" seen from the one angle that reveals it. Compare Spine01, where local X
## IS a clean pitch (+11.43, with 0.3 of yaw) — which is why the same idiom worked everywhere
## else and hid this.
##
## Same root cause as the breath layer turning the head: a bone axis is not an intention.
const _AXES := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
const _BODY_AXES := [Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0)]  ## pitch, yaw, roll

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
			var code: int = int(pair[0])
			var ax: Vector3
			if code < 3:
				ax = _AXES[code]
			else:
				ax = ((_rest_gb.get(i, Basis.IDENTITY) as Basis).inverse()
					* _BODY_AXES[code - 3]).normalized()
			q = q * Quaternion(ax, pair[1])
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
	# The neck counters only PART of the body pitch: countering all of it (the first cut,
	# -0.28) buried the head inside the body silhouette and the sit read as a sprawl from
	# behind — a sitting cat's head must stand clearly ABOVE its shoulders.
	_poses["sit"] = _bake({
		"Hip": [[3, 0.58]],
		"NeckTwist01": [[0, -0.06]], "Head": [[0, 0.04]],
	}, 0.118, {"lf": Vector3(-0.06, 0, 0), "rf": Vector3(-0.06, 0, 0),
		"lh": Vector3(0.13, 0, 0), "rh": Vector3(0.13, 0, 0)}, 0.7)
	# GROOM: the sit, then the left forepaw raised to the lowered muzzle — the arm override
	# happens AFTER the bake, which is what a raised paw is.
	var g: Dictionary = _bake({
		"Hip": [[3, 0.58]],
		"Spine02": [[1, 0.15]],
		"NeckTwist01": [[0, -0.55]], "Head": [[0, -0.28]],
	}, 0.118, {}, 0.7)
	var gl: Dictionary = _limb["lf"]
	g["q"][gl["prox"]] = _rest[gl["prox"]] * Quaternion(Vector3(1, 0, 0), -1.05)
	g["q"][gl["dist"]] = _rest[gl["dist"]] * Quaternion(Vector3(1, 0, 0), 0.55)
	g["q"][gl["paw"]] = _rest[gl["paw"]] * Quaternion(Vector3(1, 0, 0), -0.35)
	_poses["groom"] = g
	# ...AND THE SAME SIT WITHOUT THE RAISED PAW. The forepaw held up to the muzzle belongs to
	# the paw-lick and to nothing else, but it was baked into the one groom pose, so every
	# other wash style inherited it: the flank wash filmed as a cat washing its shoulder while
	# holding a paw in the air for no reason. Styles that work with the head alone get this
	# one instead (see `groom_style`).
	_poses["groom_flat"] = _bake({
		"Hip": [[3, 0.58]],
		"Spine02": [[1, 0.15]],
		"NeckTwist01": [[0, -0.55]], "Head": [[0, -0.28]],
	}, 0.118, {}, 0.7)
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
		"Hip": [[3, -0.26]],
		"NeckTwist01": [[0, 0.42]], "Head": [[0, 0.20]],
	}, 0.035, {
		"lf": Vector3(0.16, 0, 0), "rf": Vector3(0.16, 0, 0),
	}, 0.35)
	# STALK: the creep. Belly close to the deck, elbows and hocks folded so the whole animal
	# drops without the paws leaving the ground, shoulders high over a lowered chest, head
	# pushed FORWARD and held level — a stalking cat keeps its eyes on the line of the prey
	# however low the rest of it gets, and a stalk whose head droops with the body reads as a
	# sick animal rather than a hunting one. The forepaws creep a little further under the
	# chest, which is what gathers it for the launch.
	_poses["stalk"] = _bake({
		"NeckTwist01": [[0, -0.16]], "Head": [[0, 0.20]],
	}, 0.112, {"lf": Vector3(0.035, 0, 0), "rf": Vector3(0.035, 0, 0)}, 0.85)
	# CARRY: the walk with the head and neck lifted — a cat bringing something back holds it
	# clear of its own feet, and the raised head is the whole read at a distance.
	_poses["carry"] = _pose_from({
		"NeckTwist01": [[0, 0.24]], "Head": [[0, -0.10]],
	}, 0.0)
	# JUMP: airborne, so no planting — authored stretch-out, fore reaching, hind driving.
	_poses["jump"] = _pose_from({
		"Hip": [[3, 0.14]],
		"L_Upperarm": [[0, -1.05]], "R_Upperarm": [[0, -1.05]],
		"L_Forearm": [[0, 0.30]], "R_Forearm": [[0, 0.30]],
		"L_Thigh": [[0, -0.70]], "R_Thigh": [[0, -0.70]],
		"L_Calf": [[0, 0.36]], "R_Calf": [[0, 0.36]],
	}, -0.02)
