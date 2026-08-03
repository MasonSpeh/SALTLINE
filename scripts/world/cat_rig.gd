extends RefCounted
## A HAND-WRITTEN QUADRUPED GAIT ON TRIPO'S SKELETON.
##
## NO `class_name` ON PURPOSE — preload by path. docs/AGENT_TRAPS.md: declaring a global
## class on a brand-new file breaks the import that is creating its own cache entry, and
## the failure surfaces as an unrelated "Could not resolve class" on other files.
##
## s35 got Tripo to rig the ship's cat — 41 bones, clean weights, and a bind pose that
## renders identically to the static mesh it was made from. Two things about that rig are
## measured facts and both shape this file:
##
##  1. THE JOINT NAMES ARE HUMANOID. Tripo fitted a biped rig to a quadruped, so the
##     "arms" (Clavicle/Upperarm/Forearm/Hand) are bound to the FRONT legs and the "legs"
##     (Thigh/Calf/Foot/ToeBase) to the HIND legs. That mapping is a gift, not a problem —
##     it is exactly the four limbs a cat gait needs.
##  2. THE BONE LENGTHS ARE ASYMMETRIC, badly. Measured off the rest pose
##     (tests/BoneDump.tscn): L_Calf->L_Foot is 0.156 while R_Calf->R_Foot is 0.569, and
##     the forelimbs disagree the same way. So the retargeted clips Tripo shipped are
##     unusable (they photograph as a wrung-out cat — tests/out/cat_anim), and any pose
##     built on absolute joint POSITIONS would inherit the same asymmetry.
##
## What survives that is FORWARD KINEMATICS on the shoulder/hip joints: rotating a bone
## swings everything weighted to it, and the weights are sane even where the lengths are
## not. So this poses ANGLES only, never positions, and it drives the four limbs from the
## proximal joint with a smaller counter-rotation at the elbow/knee.
##
## The gait itself is the real thing rather than a wave: a cat's walk is a LATERAL
## sequence — left hind, left fore, right hind, right fore, each a quarter cycle apart —
## which is what makes a walking cat read as a cat and not as a pantomime horse. The trot
## pairs diagonals, and the bound throws both fore legs together then both hind.
##
## Everything here is verified by looking: tests/CatGaitShot.tscn photographs the cycle.

## Rotating a bone about the axis PERPENDICULAR to both the body's long axis and world up
## is what swings a limb fore-and-aft. Measured rather than assumed: every limb chain in
## this rig runs down its own local +Y (L_Calf sits at (0,+0.297,0) from L_Thigh, and so on
## for all four), so the swing axis in bone-local space is X.
const SWING := Vector3(1, 0, 0)

## Footfall phase per limb, in cycles. Lateral sequence for the walk.
const WALK_PHASE := {"lh": 0.00, "lf": 0.25, "rh": 0.50, "rf": 0.75}
## Trot: diagonal pairs move together.
const TROT_PHASE := {"lh": 0.00, "rf": 0.00, "rh": 0.50, "lf": 0.50}
## Bound/gallop: both fore, then both hind.
const BOUND_PHASE := {"lf": 0.00, "rf": 0.06, "lh": 0.45, "rh": 0.51}

var _sk: Skeleton3D = null
## limb key -> {prox, dist, paw} bone indices. -1 for anything the rig does not carry.
var _limb: Dictionary = {}
var _spine: int = -1
var _spine2: int = -1
var _neck: int = -1
var _head: int = -1
var _hip: int = -1
## Bone rests, cached: every pose is REST * rotation, never an accumulation, so a dropped
## frame cannot make the animal drift into a knot.
var _rest: Dictionary = {}

func _init(skel: Skeleton3D) -> void:
	_sk = skel
	if _sk == null:
		return
	var idx := {}
	for i in range(_sk.get_bone_count()):
		idx[_sk.get_bone_name(i)] = i
	# Front legs are the rig's "arms", hind legs its "legs" — see the header.
	_limb = {
		"lf": {"prox": idx.get("L_Upperarm", -1), "dist": idx.get("L_Forearm", -1), "paw": idx.get("L_Hand", -1)},
		"rf": {"prox": idx.get("R_Upperarm", -1), "dist": idx.get("R_Forearm", -1), "paw": idx.get("R_Hand", -1)},
		"lh": {"prox": idx.get("L_Thigh", -1), "dist": idx.get("L_Calf", -1), "paw": idx.get("L_Foot", -1)},
		"rh": {"prox": idx.get("R_Thigh", -1), "dist": idx.get("R_Calf", -1), "paw": idx.get("R_Foot", -1)},
	}
	_spine = idx.get("Spine01", -1)
	_spine2 = idx.get("Spine02", -1)
	_neck = idx.get("NeckTwist01", -1)
	_head = idx.get("Head", -1)
	_hip = idx.get("Hip", -1)
	for b in [_spine, _spine2, _neck, _head, _hip]:
		if b >= 0:
			_rest[b] = _sk.get_bone_rest(b)
	for k in _limb:
		for part in ["prox", "dist", "paw"]:
			var b: int = (_limb[k] as Dictionary)[part]
			if b >= 0:
				_rest[b] = _sk.get_bone_rest(b)

func valid() -> bool:
	return _sk != null and _limb.get("lf", {}).get("prox", -1) >= 0

## Put every driven bone back on its rest — the base every pose is built from.
func rest_pose() -> void:
	if _sk == null:
		return
	for b in _rest:
		_sk.set_bone_pose_rotation(b, (_rest[b] as Transform3D).basis.get_rotation_quaternion())

func _rot(bone: int, radians: float, axis: Vector3 = SWING) -> void:
	if bone < 0 or not _rest.has(bone):
		return
	var rest: Transform3D = _rest[bone]
	var q: Quaternion = rest.basis.get_rotation_quaternion() * Quaternion(axis.normalized(), radians)
	_sk.set_bone_pose_rotation(bone, q)

## THE GAIT. `phase` is the cycle position in turns (it accumulates outside, so a change of
## speed cannot teleport the wave — the trap AGENT_TRAPS records about `t * pace`).
## `swing` is the stride amplitude in radians, `mode` picks the footfall sequence.
func walk(phase: float, swing: float = 0.42, mode: String = "walk") -> void:
	if not valid():
		return
	var table: Dictionary = WALK_PHASE
	if mode == "trot":
		table = TROT_PHASE
	elif mode == "bound":
		table = BOUND_PHASE
	for k in table:
		var ph: float = phase + float(table[k])
		var a: float = sin(ph * TAU)
		# The knee/elbow leads the shoulder by a quarter cycle and bends only ONE WAY — a
		# leg that hyperextends backwards is the tell of a limb driven by a bare sine.
		var bend: float = maxf(0.0, -cos(ph * TAU)) * swing * 0.9
		var L: Dictionary = _limb[k]
		# Hind legs swing opposite the fore on the same side, or the animal paces.
		var sgn: float = 1.0 if k.ends_with("f") else -1.0
		_rot(L["prox"], a * swing * sgn)
		_rot(L["dist"], -bend * sgn)
		_rot(L["paw"], bend * 0.5 * sgn)
	# The spine tells you it is an animal: a small lateral sway against the stride, and the
	# hips rising as the diagonal pair passes under.
	var s: float = sin(phase * TAU * 2.0)
	_rot(_spine, s * swing * 0.10, Vector3(0, 1, 0))
	_rot(_spine2, -s * swing * 0.07, Vector3(0, 1, 0))
	_rot(_hip, absf(s) * swing * 0.05)

## Standing still, but alive: the slow breath, and the head drifting.
func idle(t: float, breath: float = 1.0) -> void:
	if not valid():
		return
	rest_pose()
	var b: float = sin(t * 1.6) * 0.035 * breath
	_rot(_spine, b, Vector3(0, 0, 1))
	_rot(_spine2, b * 0.6, Vector3(0, 0, 1))
	_rot(_neck, sin(t * 0.7) * 0.06, Vector3(0, 1, 0))

## Asleep: barely anything, which is the point — a slow shallow breath and nothing else.
func sleep(t: float) -> void:
	if not valid():
		return
	rest_pose()
	var b: float = sin(t * 0.8) * 0.022
	_rot(_spine, b, Vector3(0, 0, 1))
	_rot(_spine2, b * 0.7, Vector3(0, 0, 1))

## Washing: the head dips to the raised forepaw and works, which is the one motion that
## makes a cat unmistakably a cat.
func groom(t: float) -> void:
	if not valid():
		return
	rest_pose()
	var lick: float = sin(t * 3.1)
	var raise_paw: float = 0.55 + sin(t * 0.6) * 0.12
	var L: Dictionary = _limb["lf"]
	_rot(L["prox"], -raise_paw)
	_rot(L["dist"], raise_paw * 0.8)
	_rot(_neck, -0.30 - lick * 0.10)
	_rot(_head, -0.18 - lick * 0.12)
	_rot(_spine2, 0.06, Vector3(0, 1, 0))

## Turn the head toward something without turning the animal — the "focus" every state is
## supposed to have. `yaw`/`pitch` are radians in the body's frame, clamped to what a neck
## can actually do so the head can never end up on backwards.
func look(yaw: float, pitch: float = 0.0) -> void:
	if not valid():
		return
	var y: float = clampf(yaw, -1.05, 1.05)
	var p: float = clampf(pitch, -0.5, 0.5)
	if _neck >= 0 and _rest.has(_neck):
		var rest: Transform3D = _rest[_neck]
		var q: Quaternion = rest.basis.get_rotation_quaternion() \
			* Quaternion(Vector3(0, 1, 0), y * 0.55) * Quaternion(SWING, p * 0.5)
		_sk.set_bone_pose_rotation(_neck, q)
	if _head >= 0 and _rest.has(_head):
		var rest2: Transform3D = _rest[_head]
		var q2: Quaternion = rest2.basis.get_rotation_quaternion() \
			* Quaternion(Vector3(0, 1, 0), y * 0.45) * Quaternion(SWING, p * 0.5)
		_sk.set_bone_pose_rotation(_head, q2)
