extends Node
## SCRATCH — the gait's arithmetic, measured off the live rig with no world around it.
##
## Everything the stride argument rests on is geometry plus one live walk, so it does not
## need the rig, the deck or a render: instantiate the skeleton, drive cat_rig directly and
## READ THE DRAWN BONES BACK. Blocks:
##
##   1. THE CHAIN per limb — a, b, c0, the two-bone model's reach cap, how much of it the
##      rest pose already spends, and where the socket sits (the lever arm any girdle
##      rotation has to work through).
##   2. GIRDLE GAINS, measured not assumed — metres of fore-aft SOCKET travel per radian of
##      scapula swing, pelvic yaw and thoracic yaw. Same discipline `_prep_ik` uses for the
##      knee's fold direction.
##   3. THE DESIGN SPACE — a grid over sweep_k x duty, each cell a live walk,
##      reporting achieved paw sweep, chain saturation and the in-stance paw slide that is
##      the gate that matters. This is the measurement the "wider stride breaks foot-lock"
##      history was missing: WHY it broke, and what makes it stop breaking.
##   4. A LIVE WALK / TROT / RUN at the shipped settings.
##
## Foot-lock here is exact by construction of the harness: the skeleton node never moves, so
## the world paw is `skeleton paw + distance travelled` and a planted paw scores zero.

const RIG := preload("res://scripts/world/cat_rig.gd")
const GLB := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"
const FWD := Vector3(1, 0, 0)
const UP := Vector3(0, 1, 0)
const LIMBS := ["lf", "rf", "lh", "rh"]

var _sk: Skeleton3D = null

func _ready() -> void:
	var root: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(root)
	for n in root.find_children("*", "Skeleton3D", true, false):
		_sk = n
		break
	var rig = RIG.new(_sk, "")
	print("\n=== 1. THE CHAIN ==============================================================")
	print("  limb      a      b     c0   cmax  c0/cmax  sweep_max   sock_x   sock_y   sock_z"
		+ "     paw_x    paw_y    paw_z")
	for k in LIMBS:
		var S: Dictionary = rig._ik[k]
		var a: float = float(S["a"])
		var b: float = float(S["b"])
		var c0: float = float(S["c0"])
		var cmax: float = (a + b) * 0.985
		var P: Vector3 = S["P"]
		var W: Vector3 = S["W0"]
		print("  %-4s %6.3f %6.3f %6.3f %6.3f  %6.3f   %8.4f  %7.4f  %7.4f  %7.4f  %8.4f %8.4f %8.4f"
			% [k, a, b, c0, cmax, c0 / cmax, float(S["sweep_max"]),
				P.x, P.y, P.z, W.x, W.y, W.z])
	print("  _sweep_cap = %.4f m" % rig._sweep_cap)
	# The arc a straight chain of reach c0 traces while covering `s` of ground, per limb.
	print("  arc a straight chain must trace for a given ground sweep (mm):")
	var hdr: String = "        sweep "
	for s in [0.18, 0.20, 0.22, 0.24, 0.26]:
		hdr += "%8.2f" % s
	print(hdr)
	for k in LIMBS:
		var c0b: float = float(rig._ik[k]["c0"])
		var line: String = "  %-4s        " % k
		for s in [0.18, 0.20, 0.22, 0.24, 0.26]:
			var sn: float = clampf(s * 0.5 / c0b, 0.0, 1.0)
			line += "%8.1f" % (c0b * (1.0 - sqrt(maxf(1.0 - sn * sn, 0.0))) * 1000.0)
		print(line)

	print("\n=== 2. GIRDLE GAINS (m of fore-aft socket travel per rad) =====================")
	for k in ["lf", "rf"]:
		var L: Dictionary = rig._limb[k]
		print("  %s blade swing -> shoulder socket  %+.4f m/rad"
			% [k, _gain(rig, L["blade"], L["prox"], true)])
	for k in ["lh", "rh"]:
		var L2: Dictionary = rig._limb[k]
		print("  %s pelvis yaw  -> hip socket       %+.4f m/rad"
			% [k, _gain(rig, rig._hip, L2["prox"], false)])
	for k in ["lf", "rf"]:
		var L3: Dictionary = rig._limb[k]
		print("  %s chest yaw   -> shoulder socket  %+.4f m/rad"
			% [k, _gain(rig, rig._spine2, L3["prox"], false)])
	rig = null

	print("\n=== 3. DESIGN SPACE (walk @ 0.95 m/s) =========================================")
	print("  sweep_k  duty   arc_mm  stride  cadence   sweep_lf/rf/lh/rh (mm)"
		+ "     worst_sat%  slide_mm/f")
	for sk in [1.00, 1.15]:
		for duty in [0.52, 0.50]:
			_cell(sk, duty, 0.012)
	RIG.STANCE_ARC = 0.012

	print("\n=== 4. SHIPPED SETTINGS =======================================================")
	for row in [["walk", 1.10], ["trot", 1.9], ["run", 4.4]]:
		_walk_block(String(row[0]), float(row[1]))
	get_tree().quit()

## Metres of fore-aft travel at `target` bone's origin per radian applied at `driver`.
func _gain(rig, driver: int, target: int, hinge: bool) -> float:
	if driver < 0 or target < 0:
		return 0.0
	var d: float = 0.12
	var out: Array[float] = []
	for s in [-d, d]:
		for i in rig._rest:
			_sk.set_bone_pose_rotation(i, rig._rest[i])
		var ax: Vector3 = rig._hinge_of(driver) if hinge \
			else ((rig._rest_gb.get(driver, Basis.IDENTITY) as Basis).inverse() * UP).normalized()
		_sk.set_bone_pose_rotation(driver, (rig._rest[driver] as Quaternion) * Quaternion(ax, s))
		_sk.force_update_all_bone_transforms()
		out.append(_sk.get_bone_global_pose(target).origin.dot(FWD))
	for i in rig._rest:
		_sk.set_bone_pose_rotation(i, rig._rest[i])
	return (out[1] - out[0]) / (2.0 * d)

func _cell(sweep_k: float, duty: float, arc: float) -> void:
	RIG.STANCE_ARC = arc
	var rig = RIG.new(_sk, "")
	rig._poses["walk"]["sweep_k"] = sweep_k
	rig._poses["walk"]["duty"] = duty
	var m: Dictionary = _measure(rig, "walk", 0.95, 900)
	var stride: float = float(rig.get("_sweep_walk") if rig.get("_sweep_walk") != null else rig._sweep_cap) * sweep_k / duty
	var sw: String = ""
	var worst_sat: float = 0.0
	var worst_slide: float = 0.0
	for k in LIMBS:
		sw += "%6.1f" % (float(m["sweep"][k]) * 1000.0)
		worst_sat = maxf(worst_sat, float(m["sat"][k]))
		worst_slide = maxf(worst_slide, float(m["slide"][k]))
	print("  %6.2f  %5.2f  %6.1f  %6.4f  %7.3f   %s      %6.1f    %8.3f"
		% [sweep_k, duty, arc * 1000.0, stride, 0.95 / stride, sw,
			worst_sat * 100.0, worst_slide * 1000.0])

func _walk_block(pose_name: String, speed: float) -> void:
	var rig = RIG.new(_sk, "")
	var m: Dictionary = _measure(rig, pose_name, speed, 900)
	var mix: float = clampf((speed - RIG.WALK_V) / (RIG.TROT_V - RIG.WALK_V), 0.0, 1.0)
	var duty: float = lerpf(_wd(), _gd(), mix)
	var stride: float = lerpf(float(rig.get("_sweep_walk") if rig.get("_sweep_walk") != null else rig._sweep_cap), rig._sweep_cap, mix) / duty
	print("\n  --- %s @ %.2f m/s   duty %.3f  sweep_cap %.4f  stride %.4f m  cadence %.3f /s"
		% [pose_name, speed, duty, rig._sweep_cap, stride, speed / stride])
	print("  limb   paw_sweep  sock_sweep  leg_demand  sat%%  lift_mm | PHASE-GATED STANCE:"
		+ "  rise_mm  slide_mm/f  frames")
	for k in LIMBS:
		print("  %-4s   %8.4f   %9.4f   %9.4f  %5.1f  %6.1f |                    %7.1f   %9.3f  %6d"
			% [k, float(m["sweep"][k]), float(m["sock"][k]), float(m["demand"][k]),
				float(m["sat"][k]) * 100.0, float(m["lift"][k]) * 1000.0,
				float(m["st_rise"][k]) * 1000.0, float(m["st_slide"][k]) * 1000.0,
				int(m["st_n"][k])])
	print("  hip_y span %.1f mm   worst joint step %.4f rad/frame (%s)"
		% [float(m["hip_span"]) * 1000.0, float(m["step"]), String(m["step_bone"])])

## One live gait run; returns per-limb achieved sweep / socket sweep / saturation / slide /
## lift plus the hip bob span and the worst per-frame LOCAL joint step.
func _measure(rig, pose_name: String, speed: float, n: int) -> Dictionary:
	rig.set_pose(pose_name, 10.0)
	var dt: float = 1.0 / 60.0
	var travelled: float = 0.0
	var frames: Array = []
	var prev_q: Dictionary = {}
	var step_max: float = 0.0
	var step_bone: String = ""
	for i in range(n):
		rig.tick(dt, speed, speed * dt)
		travelled += speed * dt
		_sk.force_update_all_bone_transforms()
		if i < 240:
			continue
		var f: Dictionary = {"paw": {}, "sock": {}, "travel": travelled,
			"phase": rig._phase, "hip_y": _sk.get_bone_global_pose(rig._hip).origin.y}
		for k in LIMBS:
			var L: Dictionary = rig._limb[k]
			f["paw"][k] = _sk.get_bone_global_pose(L["paw"]).origin
			f["sock"][k] = _sk.get_bone_global_pose(L["prox"]).origin
		frames.append(f)
		for bi in range(_sk.get_bone_count()):
			var q: Quaternion = _sk.get_bone_pose_rotation(bi)
			if prev_q.has(bi):
				var st: float = (prev_q[bi] as Quaternion).angle_to(q)
				if st > step_max:
					step_max = st
					step_bone = _sk.get_bone_name(bi)
			prev_q[bi] = q
	var mixm: float = clampf((speed - RIG.WALK_V) / (RIG.TROT_V - RIG.WALK_V), 0.0, 1.0)
	var dutym: float = float((rig._poses.get(pose_name, {}) as Dictionary).get("duty",
		lerpf(_wd(), _gd(), mixm)))
	var out := {"sweep": {}, "sock": {}, "sat": {}, "slide": {}, "lift": {}, "demand": {},
		"st_rise": {}, "st_slide": {}, "st_n": {},
		"step": step_max, "step_bone": step_bone}
	for k in LIMBS:
		var S: Dictionary = rig._ik[k]
		var cmax: float = (float(S["a"]) + float(S["b"])) * 0.985
		var px: Array[float] = []
		var sx: Array[float] = []
		var dx: Array[float] = []
		var ys: Array[float] = []
		var ch: float = 0.0
		for f in frames:
			px.append((f["paw"][k] as Vector3).dot(FWD))
			sx.append((f["sock"][k] as Vector3).dot(FWD))
			dx.append(((f["paw"][k] as Vector3) - (f["sock"][k] as Vector3)).dot(FWD))
			ys.append((f["paw"][k] as Vector3).y)
			ch = maxf(ch, ((f["paw"][k] as Vector3) - (f["sock"][k] as Vector3)).length())
		var y_min: float = ys.min()
		var slide: float = 0.0
		var run_a: int = -1
		for j in range(frames.size()):
			var st: bool = ys[j] < y_min + 0.006
			if st and run_a < 0:
				run_a = j
			elif not st and run_a >= 0:
				slide = maxf(slide, _drift(frames, k, run_a, j - 1))
				run_a = -1
		if run_a >= 0:
			slide = maxf(slide, _drift(frames, k, run_a, frames.size() - 1))
		out["sweep"][k] = px.max() - px.min()
		# THE LEG'S OWN JOB: how much fore-aft travel the two-bone chain has to produce once
		# the girdle has moved the socket. Smaller than `paw_sweep` exactly when the girdle
		# is pulling in the right direction — which is the only honest test of its phase.
		out["demand"][k] = dx.max() - dx.min()
		out["sock"][k] = sx.max() - sx.min()
		out["sat"][k] = ch / cmax
		out["slide"][k] = slide
		out["lift"][k] = ys.max() - y_min
		# STANCE FROM THE GAIT'S OWN CLOCK, NOT FROM THE PAW'S HEIGHT. A height-band detector
		# reports a beautiful zero the moment the paw stops being flat — the window empties and
		# there is nothing left to measure, which is how a change that lifts the paw off the
		# deck can look like a change that fixed foot-lock. The phase says exactly when the
		# engine believes this paw is planted: `fposmod(phase + WALK_OFF[k], 1) < duty`. Drift
		# is scored over the middle 70% of each contact so touchdown and toe-off do not count.
		var st_rise: float = 0.0
		var st_slide: float = 0.0
		var st_n: int = 0
		var runs2: Array = []
		var a2: int = -1
		for j in range(frames.size()):
			var inst: bool = fposmod(float(frames[j]["phase"]) + float(RIG.WALK_OFF[k]), 1.0) < dutym
			if inst and a2 < 0:
				a2 = j
			elif not inst and a2 >= 0:
				runs2.append([a2, j - 1])
				a2 = -1
		for r2 in runs2:
			var lo2: int = int(r2[0])
			var hi2: int = int(r2[1])
			var n2: int = hi2 - lo2 + 1
			if n2 < 5:
				continue
			var e2: int = int(round(float(n2) * 0.15))
			var ylo: float = 1e9
			var yhi: float = -1e9
			for j in range(lo2, hi2 + 1):
				var yv: float = (frames[j]["paw"][k] as Vector3).y
				ylo = minf(ylo, yv)
				yhi = maxf(yhi, yv)
			st_rise = maxf(st_rise, yhi - ylo)
			for j in range(lo2 + e2 + 1, hi2 - e2 + 1):
				var wa: float = (frames[j - 1]["paw"][k] as Vector3).dot(FWD) + float(frames[j - 1]["travel"])
				var wb: float = (frames[j]["paw"][k] as Vector3).dot(FWD) + float(frames[j]["travel"])
				st_slide = maxf(st_slide, absf(wb - wa))
				st_n += 1
		out["st_rise"][k] = st_rise
		out["st_slide"][k] = st_slide
		out["st_n"][k] = st_n
	var hy: Array[float] = []
	for f in frames:
		hy.append(float(f["hip_y"]))
	out["hip_span"] = hy.max() - hy.min()
	return out

func _drift(frames: Array, k: String, a: int, b: int) -> float:
	var worst: float = 0.0
	for j in range(a + 2, b):
		var w0: float = (frames[j - 1]["paw"][k] as Vector3).dot(FWD) + float(frames[j - 1]["travel"])
		var w1: float = (frames[j]["paw"][k] as Vector3).dot(FWD) + float(frames[j]["travel"])
		worst = maxf(worst, absf(w1 - w0))
	return worst

## The two duties, so this scratch can be pointed at a pre-s52 cat_rig for an A/B.
func _wd() -> float:
	return 0.52 if "WALK_DUTY" in RIG else 0.55
func _gd() -> float:
	return 0.20
