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
##   5. THE PAW'S VERTICAL, ANALYTICALLY — `_foot_path` is a pure function, so its continuity
##      at the two seams is checkable exactly instead of inferred from bones.
##   6. WHAT THE OWNER CAN SEE, drawn — both seam discontinuities, planted-paw travel, arrival
##      speed, the lateral budget, the direct-register gap, and (7) the two rate channels the
##      LOCAL limb ceiling cannot see.
##   7. THE LATERAL BUDGET — which layer owns the side-to-side.
##   8. CROUCH x BOB — who is still lifting the planted paw.
##   9. SWING APEX x FOLD, scored at BOTH ends of the swing. Read the two `disc@` columns
##      together: the apex trades one seam against the other and the total is conserved.
##  10. ONE PLANT, FRAME BY FRAME — commanded path against drawn bone.
##
## Foot-lock here is exact by construction of the harness: the skeleton node never moves, so
## the world paw is `skeleton paw + distance travelled` and a planted paw scores zero.
##
## EVERY PHASE GATE READS THE MIX (`_off_at`, `_duty_at`). Until s54 the shipped walk ran at
## mix 0.00 and this file could hard-code WALK_OFF and WALK_DUTY; it cannot any more, and a
## window gated on the wrong offsets measures the swing and reports it as a skate.

const RIG := preload("res://scripts/world/cat_rig.gd")
## READ THE SHIPPED SPEED, never a copy of it. This scratch printed "walk @ 1.10" for a
## session after ship_cat moved to 1.125 — the same failure mode as the load diagnostic
## that divided by a hard-typed duty for four sessions.
const CAT := preload("res://scripts/world/ship_cat.gd")
const GLB := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"
const FWD := Vector3(1, 0, 0)
const UP := Vector3(0, 1, 0)
const LIMBS := ["lf", "rf", "lh", "rh"]

var _sk: Skeleton3D = null
## THE SHIPPED VALUES OF EVERY KNOB THIS SCRATCH SWEEPS, captured before the first sweep and
## put back after each one. Typing them back by hand is how block 4 came to be measured at a
## crouch it does not ship — a sweep that does not restore turns every later block into a
## measurement of the last row of the previous one.
var _defaults := {}

## The sweep reaches cat_rig's STATIC vars by NAME, and `RIG.set("PELVIS_YAW", x)` does not
## parse: `set()`/`get()` are non-static members of Object, so the parser refuses them on a
## class reference even though the call is fine at runtime. Holding the script in an
## Object-typed handle hides the class identity from the parser and defers the lookup.
## Do NOT "simplify" this back to RIG.set(...) — it fails at PARSE time, and a harness that
## does not parse hangs a windowed Godot forever (docs/AGENT_TRAPS.md).
var _rig_obj: Object = RIG

func _restore() -> void:
	for k in _defaults:
		_rig_obj.set(k, _defaults[k])

func _ready() -> void:
	var root: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(root)
	for n in root.find_children("*", "Skeleton3D", true, false):
		_sk = n
		break
	for k in ["CROUCH_K", "BOB_WALK", "SWING_APEX", "STANCE_CENTRE", "PELVIS_YAW",
			"CHEST_YAW", "PELVIS_ROLL", "CHEST_ROLL", "FOLD_FORE", "FOLD_HIND", "FOLD_APEX"]:
		_defaults[k] = _rig_obj.get(k)
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
			_cell(sk, duty, 1.0)
	_restore()

	print("\n=== 4. SHIPPED SETTINGS =======================================================")
	for row in [["walk", CAT.WALK_SPEED], ["trot", CAT.TROT_SPEED], ["run", CAT.RUN_SPEED]]:
		_walk_block(String(row[0]), float(row[1]))

	print("\n=== 5. THE PAW'S VERTICAL, ANALYTICALLY =======================================")
	_path_block(CAT.WALK_SPEED)
	print("\n=== 6. WHAT THE OWNER CAN SEE (drawn, live walk @ %.3f) =====================" % CAT.WALK_SPEED)
	_owner_block("walk", CAT.WALK_SPEED)
	print("\n=== 7. THE LATERAL BUDGET — who owns the wobble ===============================")
	print("  pelv_yaw chest_yaw | rump_lat  head_lat  sp2_lat  pelv_deg chest_deg"
		+ " | sweep_walk  stride  worst_slide")
	for row in [[0.22, 0.16], [0.0, 0.16], [0.22, 0.0], [0.08, 0.0], [0.0, 0.0]]:
		_lat_row(float(row[0]), float(row[1]))
	_restore()
	print("\n=== 8. CROUCH x BOB — who is still lifting the planted paw =====================")
	print("  crouch bob_mm | hip_mean hip_span | PAW RISE (mid-70%) lf/rf/lh/rh"
		+ " | SOCKET RISE same window | SLIDE mm/f")
	# The full 6x3 grid that chose these two numbers is recorded in cat_rig's CROUCH_K note;
	# what is left here is the shipped cell plus the two neighbours a regression would move to.
	for row in [[0.00, 0.038], [0.75, 0.014], [0.75, 0.038]]:
		_crouch_row(float(row[0]), float(row[1]))
	_restore()
	print("\n=== 9. SWING APEX x FOLD — AND BOTH ENDS OF THE SWING, WHICH IS THE POINT ======")
	# THIS BLOCK USED TO SCORE ONE END. `SWING_APEX` trades the two transitions against each
	# other and the total is roughly conserved, so a row that prints only the touchdown makes
	# every early apex look like a win — s54 nearly shipped 0.15 on exactly that reading, which
	# measures as a 39 mm SNAP off the deck (the lift has to be traversed in `apex * 11` frames,
	# so the apex is bounded from below by the frame rate, not by continuity). `_owner_block`'s
	# feet table prints disc@toeoff beside disc@touchdown; read them together.
	#
	# The fold has its own apex because it moves no IK target (see cat_rig.FOLD_APEX), so the
	# grid is 2-D and the two columns are not interchangeable.
	for row in [[0.30, 0.18, 0.18, 0.15], [0.30, 0.30, 0.42, 0.36],
			[0.15, 0.15, 0.18, 0.15], [0.35, 0.18, 0.22, 0.18]]:
		RIG.SWING_APEX = float(row[0])
		RIG.FOLD_APEX = float(row[1])
		RIG.FOLD_FORE = float(row[2])
		RIG.FOLD_HIND = float(row[3])
		print("  --- SWING_APEX %.2f  FOLD_APEX %.2f  FOLD %.2f/%.2f"
			% [float(row[0]), float(row[1]), float(row[2]), float(row[3])])
		_owner_block("walk", CAT.WALK_SPEED, true)
	_restore()
	print("\n=== 10. ONE PLANT, FRAME BY FRAME ============================================")
	_trace("lf")
	_trace("rh")
	get_tree().quit()

## THE COMMANDED PATH AGAINST THE DRAWN BONE, one limb, one cycle. When the path is
## continuous and the drawn paw is not, the difference is the SOLVE, and this is the only way
## to see which frame it happens on and what the chain was doing at the time.
func _trace(k: String) -> void:
	var rig = RIG.new(_sk, "")
	rig.set_pose("walk", 10.0)
	var dt: float = 1.0 / 60.0
	var L: Dictionary = rig._limb[k]
	var S: Dictionary = rig._ik[k]
	var cmax: float = float(S["cmax"])
	var mixt: float = _mix(CAT.WALK_SPEED)
	var duty: float = _duty_at(rig, "walk", mixt)
	var lift_m: float = lerpf(0.085, 0.125, mixt) * (1.0 if k.ends_with("f") else 0.88)
	var rows: Array = []
	for i in range(600):
		rig.tick(dt, CAT.WALK_SPEED, CAT.WALK_SPEED * dt)
		_sk.force_update_all_bone_transforms()
		if i < 540:
			continue
		var ph: float = fposmod(rig._phase + _off_at(k, mixt), 1.0)
		var paw: Vector3 = _sk.get_bone_global_pose(L["paw"]).origin
		var sock: Vector3 = _sk.get_bone_global_pose(L["prox"]).origin
		rows.append([ph, rig._foot_path(ph, duty,
			lerpf(rig._sweep_walk, rig._sweep_cap, mixt), lift_m).y,
			paw.y, sock.y, (paw - sock).length() / cmax])
	# CONSECUTIVE FRAMES across one plant — sorting by phase interleaves cycles and hides
	# exactly the frame-to-frame step this is looking for.
	print("  %s — ph | path_y_mm  drawn_paw_y_mm(rel)  socket_y_mm(rel)  chain/cmax  d_paw_y" % k)
	var td: int = -1
	for i in range(1, rows.size()):
		if float(rows[i][0]) < float(rows[i - 1][0]):
			td = i
			break
	if td < 0:
		return
	var lo: int = maxi(td - 7, 0)
	var p0: float = float(rows[td][2])
	var s0: float = float(rows[td][3])
	for i in range(lo, mini(td + 5, rows.size())):
		var r: Array = rows[i]
		print("    %.3f | %8.2f %14.2f %16.2f %12.4f %9.2f"
			% [float(r[0]), float(r[1]) * 1000.0, (float(r[2]) - p0) * 1000.0,
				(float(r[3]) - s0) * 1000.0, float(r[4]),
				(float(r[2]) - float(rows[i - 1][2])) * 1000.0 if i > 0 else 0.0])

## One cell of the crouch x bob grid. The two knobs are the only things that move the SOCKET
## vertically at a walk, and on a rig whose chains sit at 98-100% of their reach cap a socket
## that rises drags a planted paw up with it — so this grid is the honest way to find out
## which of the two is paying for the foot and which is charging for it.
func _crouch_row(ck: float, bob: float) -> void:
	RIG.CROUCH_K = ck
	RIG.BOB_WALK = bob
	var rig = RIG.new(_sk, "")
	rig.set_pose("walk", 10.0)
	var dt: float = 1.0 / 60.0
	var travelled: float = 0.0
	var F: Array = []
	for i in range(900):
		rig.tick(dt, CAT.WALK_SPEED, CAT.WALK_SPEED * dt)
		travelled += CAT.WALK_SPEED * dt
		_sk.force_update_all_bone_transforms()
		if i >= 240:
			var f := {"travel": travelled, "phase": rig._phase, "paw": {}, "sock": {},
				"hip": _sk.get_bone_global_pose(rig._hip).origin}
			for k in LIMBS:
				f["paw"][k] = _sk.get_bone_global_pose(rig._limb[k]["paw"]).origin
				f["sock"][k] = _sk.get_bone_global_pose(rig._limb[k]["prox"]).origin
			F.append(f)
	var mixc: float = _mix(CAT.WALK_SPEED)
	var duty: float = _duty_at(rig, "walk", mixc)
	var rise := {}
	var srise := {}
	var slide := {}
	for k in LIMBS:
		rise[k] = 0.0
		srise[k] = 0.0
		slide[k] = 0.0
		var a: int = -1
		var runs: Array = []
		for j in range(F.size()):
			var inst: bool = fposmod(float(F[j]["phase"]) + _off_at(k, mixc), 1.0) < duty
			if inst and a < 0:
				a = j
			elif not inst and a >= 0:
				runs.append([a, j - 1])
				a = -1
		for r in runs:
			var lo: int = int(r[0])
			var hi: int = int(r[1])
			if hi - lo + 1 < 5:
				continue
			# THE MIDDLE 70% OF THE CONTACT, the same window the slide is scored over: the
			# engine's phase says a paw is planted a frame or two before the drawn paw has
			# finished arriving (the slew limiter and the DRAG both lag it), so the raw
			# contact window still carries a little of the swing at each end.
			var e: int = int(round(float(hi - lo + 1) * 0.15))
			var ylo: float = 1e9
			var yhi: float = -1e9
			var slo: float = 1e9
			var shi: float = -1e9
			for j in range(lo + e, hi - e + 1):
				ylo = minf(ylo, (F[j]["paw"][k] as Vector3).y)
				yhi = maxf(yhi, (F[j]["paw"][k] as Vector3).y)
				slo = minf(slo, (F[j]["sock"][k] as Vector3).y)
				shi = maxf(shi, (F[j]["sock"][k] as Vector3).y)
			rise[k] = maxf(float(rise[k]), yhi - ylo)
			srise[k] = maxf(float(srise[k]), shi - slo)
			for j in range(lo + e + 1, hi - e + 1):
				var wa: float = (F[j - 1]["paw"][k] as Vector3).dot(FWD) + float(F[j - 1]["travel"])
				var wb: float = (F[j]["paw"][k] as Vector3).dot(FWD) + float(F[j]["travel"])
				slide[k] = maxf(float(slide[k]), absf(wb - wa))
	var hy: Array[float] = []
	for f in F:
		hy.append((f["hip"] as Vector3).y)
	var hmean: float = 0.0
	for v in hy:
		hmean += v
	hmean /= float(hy.size())
	print("  %5.2f %6.1f | %8.1f %6.1f | %6.1f %5.1f %5.1f %5.1f | %5.1f %5.1f %5.1f %5.1f"
		% [ck, bob * 1000.0, (hmean - float(rig._rest_t[rig._hip].y)) * 1000.0,
			(hy.max() - hy.min()) * 1000.0,
			float(rise["lf"]) * 1000.0, float(rise["rf"]) * 1000.0,
			float(rise["lh"]) * 1000.0, float(rise["rh"]) * 1000.0,
			float(srise["lf"]) * 1000.0, float(srise["rf"]) * 1000.0,
			float(srise["lh"]) * 1000.0, float(srise["rh"]) * 1000.0]
		+ " | %5.2f %5.2f %5.2f %5.2f" % [float(slide["lf"]) * 1000.0,
			float(slide["rf"]) * 1000.0, float(slide["lh"]) * 1000.0, float(slide["rh"]) * 1000.0])

## One row of the lateral budget: build a rig at these girdle amplitudes, walk it, and read
## the side-to-side excursion of the drawn bones against what the girdle bought in stride.
func _lat_row(pelv: float, chest: float) -> void:
	RIG.PELVIS_YAW = pelv
	RIG.CHEST_YAW = chest
	var rig = RIG.new(_sk, "")
	rig.set_pose("walk", 10.0)
	var dt: float = 1.0 / 60.0
	var travelled: float = 0.0
	var F: Array = []
	for i in range(900):
		rig.tick(dt, CAT.WALK_SPEED, CAT.WALK_SPEED * dt)
		travelled += CAT.WALK_SPEED * dt
		_sk.force_update_all_bone_transforms()
		if i >= 240:
			var f := {"travel": travelled, "phase": rig._phase, "paw": {}, "sock": {}}
			for k in LIMBS:
				f["paw"][k] = _sk.get_bone_global_pose(rig._limb[k]["paw"]).origin
				f["sock"][k] = _sk.get_bone_global_pose(rig._limb[k]["prox"]).origin
			f["rump"] = _sk.get_bone_global_pose(rig._tail).origin
			f["head"] = _sk.get_bone_global_pose(rig._head).origin
			f["sp2"] = _sk.get_bone_global_pose(rig._spine2).origin
			F.append(f)
	var out := {}
	for nm in ["rump", "head", "sp2"]:
		var zs: Array[float] = []
		for f in F:
			zs.append((f[nm] as Vector3).z)
		out[nm] = zs.max() - zs.min()
	var deg := {}
	for pair in [["lh", "rh", "p"], ["lf", "rf", "c"]]:
		var ang: Array[float] = []
		for f in F:
			var v: Vector3 = (f["sock"][String(pair[0])] as Vector3) - (f["sock"][String(pair[1])] as Vector3)
			ang.append(atan2(v.x, v.z))
		deg[String(pair[2])] = rad_to_deg(ang.max() - ang.min())
	var mixl: float = _mix(CAT.WALK_SPEED)
	var duty: float = _duty_at(rig, "walk", mixl)
	var worst: float = 0.0
	for k in LIMBS:
		var runs: Array = []
		var a: int = -1
		for j in range(F.size()):
			var inst: bool = fposmod(float(F[j]["phase"]) + _off_at(k, mixl), 1.0) < duty
			if inst and a < 0:
				a = j
			elif not inst and a >= 0:
				runs.append([a, j - 1])
				a = -1
		for r in runs:
			var lo: int = int(r[0])
			var hi: int = int(r[1])
			if hi - lo + 1 < 5:
				continue
			var e: int = int(round(float(hi - lo + 1) * 0.15))
			for j in range(lo + e + 1, hi - e + 1):
				var wa: float = (F[j - 1]["paw"][k] as Vector3).dot(FWD) + float(F[j - 1]["travel"])
				var wb: float = (F[j]["paw"][k] as Vector3).dot(FWD) + float(F[j]["travel"])
				worst = maxf(worst, absf(wb - wa))
	print("  %8.2f %9.2f | %8.2f %9.2f %8.2f %9.2f %9.2f | %10.4f %7.4f %12.3f"
		% [pelv, chest, float(out["rump"]) * 1000.0, float(out["head"]) * 1000.0,
			float(out["sp2"]) * 1000.0, float(deg["p"]), float(deg["c"]),
			rig._sweep_walk, rig._sweep_walk / duty, worst * 1000.0])

## ---------------------------------------------------------------- s53 instruments
##
## THE FOOT PATH'S OWN ARITHMETIC, before any solver touches it. `_foot_path` is a pure
## function, so its continuity is checkable exactly rather than inferred from drawn bones:
## sample it either side of both transitions and print the STEP. A path that teleports the
## paw cannot be fixed downstream, and a drawn measurement mixes it with the IK's own
## clamping — so both are measured, here and in block 6.
func _path_block(speed: float) -> void:
	var rig = RIG.new(_sk, "")
	var mixp: float = _mix(speed)
	var duty: float = lerpf(_wd(), _gd(), mixp)
	var sweep_env: float = lerpf(float(rig._sweep_walk), float(rig._sweep_cap), mixp)
	var stride: float = sweep_env / duty
	var cad: float = speed / stride
	var dph: float = cad / 60.0                    # cycles per frame at 60 Hz
	print("  stride %.4f m  cadence %.3f /s  phase step %.4f cyc/frame  duty %.2f"
		% [stride, cad, dph, duty])
	print("  limb  body_drop   (unused)  lift  | step@toeoff  step@touchdown | vy@touchdown"
		+ "  vy@toeoff |  WORLD vx@td  vx@off   (mm, mm/frame)")
	for k in LIMBS:
		var fore: bool = k.ends_with("f")
		var lift_m: float = lerpf(0.085, 0.125, mixp) * (1.0 if fore else 0.88)
		var eps: float = 1e-5
		var y_pre_off: float = rig._foot_path(duty - eps, duty, sweep_env, lift_m).y
		var y_post_off: float = rig._foot_path(duty + eps, duty, sweep_env, lift_m).y
		var y_pre_td: float = rig._foot_path(1.0 - eps, duty, sweep_env, lift_m).y
		var y_post_td: float = rig._foot_path(0.0, duty, sweep_env, lift_m).y
		# Vertical AND fore-aft speed one frame either side of the plant, in mm per rendered
		# frame. The fore-aft one is measured IN THE WORLD (body-relative plus the body's own
		# travel), because a paw that is still relative to the BODY at touchdown is travelling
		# forward at body speed when it lands, which is a scuff.
		var vy_td: float = (rig._foot_path(1.0 - eps, duty, sweep_env, lift_m).y
			- rig._foot_path(1.0 - dph, duty, sweep_env, lift_m).y)
		var vy_off: float = (rig._foot_path(duty + dph, duty, sweep_env, lift_m).y
			- rig._foot_path(duty + eps, duty, sweep_env, lift_m).y)
		var body_step: float = stride * dph
		var vx_td: float = (rig._foot_path(1.0 - eps, duty, sweep_env, lift_m).x
			- rig._foot_path(1.0 - dph, duty, sweep_env, lift_m).x) + body_step
		var vx_off: float = (rig._foot_path(duty + dph, duty, sweep_env, lift_m).x
			- rig._foot_path(duty + eps, duty, sweep_env, lift_m).x) + body_step
		print("  %-4s  %7.1f  %8.1f %6.1f  | %10.1f  %14.1f | %12.2f %10.2f | %8.2f %8.2f"
			% [k, rig._body_drop(sweep_env) * 1000.0, 0.0, lift_m * 1000.0,
				(y_post_off - y_pre_off) * 1000.0, (y_post_td - y_pre_td) * 1000.0,
				vy_td * 1000.0, vy_off * 1000.0, vx_td * 1000.0, vx_off * 1000.0])
	# HOW MUCH HEADROOM THE BODY WOULD HAVE TO FIND to let every paw stay flat. Per limb and
	# per instant: g_k = socket height above the paw MINUS the height a chain of cmax can hold
	# at this instant's fore-aft offset. The body must drop by the MAX over the limbs that are
	# in stance; how that max varies over a cycle decides whether it is a DC crouch or a ripple.
	print("  BODY-DROP DEMAND (mm) if the stance path is flat — per limb over its own stance,"
		+ " and the whole-animal max:")
	var n: int = 240
	var hmax: Array[float] = []
	var per := {}
	for k in LIMBS:
		per[k] = [0.0, 0.0]
	for i in range(n):
		var ph0: float = float(i) / float(n)
		var worst: float = 0.0
		for k in LIMBS:
			var S: Dictionary = rig._ik[k]
			var ph: float = fposmod(ph0 + _off_at(k, mixp), 1.0)
			if ph >= duty:
				continue
			var u: float = ph / duty
			var x: float = float(S["d_fw"]) + sweep_env * (0.5 - u)
			var cmax: float = float(S["cmax"])
			var rad: float = cmax * cmax - x * x
			var g: float = -float(S["d_up"]) - (sqrt(rad) if rad > 0.0 else 0.0)
			g = maxf(g, 0.0)
			per[k][1] = maxf(float(per[k][1]), g)
			worst = maxf(worst, g)
		hmax.append(worst)
	var hsum: float = 0.0
	for v in hmax:
		hsum += v
	for k in LIMBS:
		print("    %-4s peak %6.1f" % [k, float(per[k][1]) * 1000.0])
	print("    whole animal: min %.1f  mean %.1f  max %.1f mm  (ripple %.1f mm)"
		% [hmax.min() * 1000.0, hsum / float(hmax.size()) * 1000.0, hmax.max() * 1000.0,
			(hmax.max() - hmax.min()) * 1000.0])
	# ...and the SHAPE of it, because a demand that ripples fast has to be paid as a constant
	# and one that ripples once a cycle can ride the bob. lh is excluded from the second row:
	# its chain cannot span its own stance at ANY body height (see its peak above), so paying
	# it would drive the animal into the deck for nothing.
	var curve: Array[float] = []
	var curve3: Array[float] = []
	for i in range(24):
		var ph0: float = float(i) / 24.0
		var w4: float = 0.0
		var w3: float = 0.0
		for k in LIMBS:
			var S: Dictionary = rig._ik[k]
			var ph: float = fposmod(ph0 + _off_at(k, mixp), 1.0)
			if ph >= duty:
				continue
			var u: float = ph / duty
			var x: float = float(S["d_fw"]) + sweep_env * (0.5 - u)
			var cm: float = float(S["cmax"])
			var rd: float = cm * cm - x * x
			var g: float = maxf(-float(S["d_up"]) - (sqrt(rd) if rd > 0.0 else 0.0), 0.0)
			w4 = maxf(w4, g)
			if k != "lh":
				w3 = maxf(w3, g)
		curve.append(w4)
		curve3.append(w3)
	var l4: String = "    all four (mm): "
	var l3: String = "    minus lh  (mm): "
	for i in range(24):
		l4 += "%5.0f" % (curve[i] * 1000.0)
		l3 += "%5.0f" % (curve3[i] * 1000.0)
	print(l4)
	print(l3)
	print("    minus lh: min %.1f  max %.1f  ripple %.1f mm"
		% [curve3.min() * 1000.0, curve3.max() * 1000.0,
			(curve3.max() - curve3.min()) * 1000.0])
	# ...and how tall the animal is, so a drop can be judged as a fraction rather than a number.
	var rest_q2 := {}
	for i in rig._rest:
		rest_q2[i] = rig._rest[i]
	rig._set_chain(rest_q2)
	_sk.force_update_all_bone_transforms()
	var paw_y: float = 1e9
	for k in LIMBS:
		paw_y = minf(paw_y, _sk.get_bone_global_pose(rig._limb[k]["paw"]).origin.y)
	print("    hip stands %.1f mm above the rest paws; withers (Spine02) %.1f mm"
		% [(_sk.get_bone_global_pose(rig._hip).origin.y - paw_y) * 1000.0,
			(_sk.get_bone_global_pose(rig._spine2).origin.y - paw_y) * 1000.0])

## THE SIX THINGS THE OWNER CAN SEE, drawn — read off the bones after a live walk, so the IK,
## the clamps, the slew limiter and every torso layer are all in the number.
func _owner_block(pose_name: String, speed: float, feet_only: bool = false) -> void:
	var rig = RIG.new(_sk, "")
	rig.set_pose(pose_name, 10.0)
	var dt: float = 1.0 / 60.0
	var mixo: float = _mix(speed)
	var duty: float = _duty_at(rig, pose_name, mixo)
	var travelled: float = 0.0
	var F: Array = []
	var prev_q := {}
	var step_max: float = 0.0
	var step_bone: String = ""
	# THE CHANNELS THE LIMB RATE CEILING CANNOT SEE — the coverage gap KNOWN_ISSUES left open.
	# `LIMB_MAX_RATE` is applied `if _rom.has(i)`, i.e. to the four limbs only, so the tail bone
	# (which also carries the rump) had no ceiling of any kind and CatReviewProbe's
	# tail_world_step gate was failing on it before this session. And the ceiling is on the
	# LOCAL pose, while what the eye sees at the end of a chain is the WORLD orientation — the
	# sum of every parent's motion. Both are printed so neither can go quiet again.
	var tail_i: int = rig._tail
	var tail_prev := Quaternion.IDENTITY
	var tail_step: float = 0.0
	var wmax: float = 0.0
	var wbone: String = ""
	var wprev := {}
	for i in range(900):
		rig.tick(dt, speed, speed * dt)
		travelled += speed * dt
		_sk.force_update_all_bone_transforms()
		if i >= 240:
			var f := {"phase": rig._phase, "travel": travelled, "paw": {}, "sock": {}}
			for k in LIMBS:
				f["paw"][k] = _sk.get_bone_global_pose(rig._limb[k]["paw"]).origin
				f["sock"][k] = _sk.get_bone_global_pose(rig._limb[k]["prox"]).origin
			f["hip"] = _sk.get_bone_global_pose(rig._hip).origin
			f["spine2"] = _sk.get_bone_global_pose(rig._spine2).origin
			f["head"] = _sk.get_bone_global_pose(rig._head).origin
			f["rump"] = _sk.get_bone_global_pose(rig._tail).origin if rig._tail >= 0 \
				else _sk.get_bone_global_pose(rig._hip).origin
			F.append(f)
			if tail_i >= 0:
				var tq: Quaternion = _sk.get_bone_global_pose(tail_i).basis.get_rotation_quaternion()
				if i > 240:
					tail_step = maxf(tail_step, tail_prev.angle_to(tq))
				tail_prev = tq
			for kk in LIMBS:
				for nm2 in ["prox", "dist", "paw", "toe"]:
					var bw: int = int(rig._limb[kk][nm2])
					if bw < 0:
						continue
					var gq: Quaternion = _sk.get_bone_global_pose(bw).basis.get_rotation_quaternion()
					if wprev.has(bw):
						var ws: float = (wprev[bw] as Quaternion).angle_to(gq)
						if ws > wmax:
							wmax = ws
							wbone = _sk.get_bone_name(bw)
					wprev[bw] = gq
			for bi in range(_sk.get_bone_count()):
				var q: Quaternion = _sk.get_bone_pose_rotation(bi)
				if prev_q.has(bi):
					var st: float = (prev_q[bi] as Quaternion).angle_to(q)
					if st > step_max:
						step_max = st
						step_bone = _sk.get_bone_name(bi)
				prev_q[bi] = q
	# 1-3: the paw's vertical, at and around the two transitions.
	print("  (1,2,3) PAW VERTICAL — drawn, mm. disc = the one-frame step across the transition")
	print("  limb  disc@toeoff  disc@touchdown | rise_full rise_mid70 slide_mm/f"
		+ " | vy_touchdown  vy_typ_swing")
	for k in LIMBS:
		var off: float = _off_at(k, mixo)
		var d_off: float = 0.0
		var d_td: float = 0.0
		var vy_td: float = 0.0
		var vy_all: Array[float] = []
		var rise: float = 0.0
		var rise_mid: float = 0.0
		var slide: float = 0.0
		var runs: Array = []
		var a: int = -1
		for j in range(F.size()):
			var inst: bool = fposmod(float(F[j]["phase"]) + off, 1.0) < duty
			if inst and a < 0:
				a = j
			elif not inst and a >= 0:
				runs.append([a, j - 1])
				a = -1
		for r in runs:
			var lo: int = int(r[0])
			var hi: int = int(r[1])
			if hi - lo + 1 < 5:
				continue
			var e: int = int(round(float(hi - lo + 1) * 0.15))
			var ylo: float = 1e9
			var yhi: float = -1e9
			var ylo2: float = 1e9
			var yhi2: float = -1e9
			for j in range(lo, hi + 1):
				var yv: float = (F[j]["paw"][k] as Vector3).y
				ylo = minf(ylo, yv)
				yhi = maxf(yhi, yv)
				if j >= lo + e and j <= hi - e:
					ylo2 = minf(ylo2, yv)
					yhi2 = maxf(yhi2, yv)
			rise = maxf(rise, yhi - ylo)
			rise_mid = maxf(rise_mid, yhi2 - ylo2)
			for j in range(lo + e + 1, hi - e + 1):
				var wa: float = (F[j - 1]["paw"][k] as Vector3).dot(FWD) + float(F[j - 1]["travel"])
				var wb: float = (F[j]["paw"][k] as Vector3).dot(FWD) + float(F[j]["travel"])
				slide = maxf(slide, absf(wb - wa))
			# TOUCHDOWN is the first frame of this contact; the step INTO it and the step
			# before that are the two numbers the owner's "slap" is made of.
			if lo >= 2:
				d_td = maxf(d_td, absf((F[lo]["paw"][k] as Vector3).y - (F[lo - 1]["paw"][k] as Vector3).y))
				vy_td = maxf(vy_td, absf((F[lo - 1]["paw"][k] as Vector3).y - (F[lo - 2]["paw"][k] as Vector3).y))
			if hi + 1 < F.size():
				d_off = maxf(d_off, absf((F[hi + 1]["paw"][k] as Vector3).y - (F[hi]["paw"][k] as Vector3).y))
		# ...against the typical mid-swing frame, so a step can be read as a step.
		for j in range(1, F.size()):
			var ph: float = fposmod(float(F[j]["phase"]) + off, 1.0)
			if ph > duty + (1.0 - duty) * 0.3 and ph < duty + (1.0 - duty) * 0.7:
				vy_all.append(absf((F[j]["paw"][k] as Vector3).y - (F[j - 1]["paw"][k] as Vector3).y))
		vy_all.sort()
		var typ: float = vy_all[vy_all.size() / 2] if not vy_all.is_empty() else 0.0
		print("  %-4s %11.1f %15.1f | %6.1f %6.1f %11.3f | %12.1f %13.1f"
			% [k, d_off * 1000.0, d_td * 1000.0, rise * 1000.0, rise_mid * 1000.0,
				slide * 1000.0, vy_td * 1000.0, typ * 1000.0])
	if feet_only:
		return
	# 4: the wobble. Lateral excursion of the drawn bones, and the drawn girdle yaw angles.
	print("  (4) LATERAL — peak-to-peak excursion across the run, mm, and drawn girdle yaw, deg")
	for nm in ["hip", "spine2", "head", "rump"]:
		var zs: Array[float] = []
		for f in F:
			zs.append((f[nm] as Vector3).dot(Vector3(0, 0, 1)))
		print("    %-8s lateral %6.2f mm" % [nm, (zs.max() - zs.min()) * 1000.0])
	for pair in [["lh", "rh", "pelvis"], ["lf", "rf", "chest"]]:
		var ang: Array[float] = []
		var lat: Array[float] = []
		for f in F:
			var v: Vector3 = (f["sock"][String(pair[0])] as Vector3) - (f["sock"][String(pair[1])] as Vector3)
			ang.append(atan2(v.x, v.z))
			lat.append(((f["sock"][String(pair[0])] as Vector3)
				+ (f["sock"][String(pair[1])] as Vector3)).z * 0.5)
		print("    %-8s girdle yaw %6.2f deg p-p   socket-midpoint lateral %6.2f mm"
			% [String(pair[2]), rad_to_deg(ang.max() - ang.min()), (lat.max() - lat.min()) * 1000.0])
	# 5: direct registering — where the hind paw lands against where the fore paw left.
	print("  (5) DIRECT REGISTER — hind touchdown vs same-side fore lift-off, mm of fore-aft gap")
	for side in [["lh", "lf"], ["rh", "rf"]]:
		var hk: String = String(side[0])
		var fk: String = String(side[1])
		var lifts: Array = []
		for j in range(1, F.size()):
			var was: bool = fposmod(float(F[j - 1]["phase"]) + _off_at(fk, mixo), 1.0) < duty
			var now: bool = fposmod(float(F[j]["phase"]) + _off_at(fk, mixo), 1.0) < duty
			if was and not now:
				lifts.append([j - 1, (F[j - 1]["paw"][fk] as Vector3).dot(FWD)
					+ float(F[j - 1]["travel"])])
		var gaps: Array[float] = []
		for j in range(1, F.size()):
			var was2: bool = fposmod(float(F[j - 1]["phase"]) + _off_at(hk, mixo), 1.0) < duty
			var now2: bool = fposmod(float(F[j]["phase"]) + _off_at(hk, mixo), 1.0) < duty
			if now2 and not was2:
				var xh: float = (F[j]["paw"][hk] as Vector3).dot(FWD) + float(F[j]["travel"])
				var best: float = 1e9
				for l in lifts:
					if int(l[0]) < j and absf(xh - float(l[1])) < absf(best):
						best = xh - float(l[1])
				if absf(best) < 1e8:
					gaps.append(best)
		var mean: float = 0.0
		for g in gaps:
			mean += g
		if not gaps.is_empty():
			mean /= float(gaps.size())
		print("    %s lands %+7.1f mm from where %s left  (n=%d)"
			% [hk, mean * 1000.0, fk, gaps.size()])
	# 6: the two gates that must not regress, plus the body's own vertical.
	var hy: Array[float] = []
	for f in F:
		hy.append((f["hip"] as Vector3).y)
	print("  (6) worst joint step %.4f rad/frame (%s)   hip_y span %.1f mm"
		% [step_max, step_bone, (hy.max() - hy.min()) * 1000.0])
	print("  (7) UNCAPPED / WORLD-SPACE RATES — tail world step %.4f rad/frame (gate 0.35);"
		% tail_step + "  worst limb WORLD step %.4f rad/frame (%s), against a %.4f LOCAL cap"
		% [wmax, wbone, RIG.LIMB_MAX_RATE / 60.0])

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
	RIG.CROUCH_K = arc
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
			var inst: bool = fposmod(float(frames[j]["phase"]) + _off_at(k, mixm), 1.0) < dutym
			if inst and a2 < 0:
				a2 = j
			elif not inst and a2 >= 0:
				runs2.append([a2, j - 1])
				a2 = -1
		for r2 in runs2:
			var lo2: int = int(r2[0])
			var hi2: int = int(r2[1])
			var n2: int = hi2 - lo2 + 1
			# 3, NOT 5. At GALLOP_DUTY 0.20 and 4.9 strides a second a contact is 2.5 frames
			# long, so a 5-frame minimum rejected every one of them and the run printed a
			# beautiful 0.000 over 0 frames — the vacuous pass this repo has a trap about. The
			# frame COUNT is printed next to every figure for the same reason.
			if n2 < 3:
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

## THE FOOTFALL OFFSET AND THE DUTY THE ENGINE IS ACTUALLY USING AT THIS SPEED — not WALK_OFF
## and not WALK_DUTY.
##
## This scratch read `RIG.WALK_OFF[k]` and `WALK_DUTY` everywhere, which was harmless for as
## long as `mix` was 0.00 at the shipped walk and 0.06 at the shipped trot. s54 re-sited the
## speed bands (see cat_rig.WALK_V), so the walk now runs at mix 0.038 and the trot at 0.675 —
## and a stance window gated on WALK_OFF while `tick` has eased a third of the way toward
## TROT_OFF sits up to 0.09 of a cycle away from the contact. Every per-limb number then
## becomes a measurement of the SWING. Caught by a 54 mm/frame "in-stance slide" on a limb
## whose real figure is 0.26.
func _mix(speed: float) -> float:
	return clampf((speed - RIG.WALK_V) / (RIG.TROT_V - RIG.WALK_V), 0.0, 1.0)

func _off_at(k: String, mix: float) -> float:
	if mix < 0.5:
		return lerpf(float(RIG.WALK_OFF[k]), float(RIG.TROT_OFF[k]), mix * 2.0)
	return lerpf(float(RIG.TROT_OFF[k]), float(RIG.GALLOP_OFF[k]), mix * 2.0 - 1.0)

func _duty_at(rig, pose_name: String, mix: float) -> float:
	return float((rig._poses.get(pose_name, {}) as Dictionary).get("duty",
		lerpf(_wd(), _gd(), mix)))

## The two duties, so this scratch can be pointed at a pre-s52 cat_rig for an A/B.
func _wd() -> float:
	return 0.52 if "WALK_DUTY" in RIG else 0.55
func _gd() -> float:
	return 0.20
