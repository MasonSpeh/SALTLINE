extends Node
## WHICH LAYER TURNS THE CAT'S HEAD, AND ABOUT WHICH AXIS — measured on the bare GLB, with no
## world, no state machine and no camera.
##
## CatFilm measured the symptom on the live animal: walking straight at DEFAULT GAIT the drawn
## face sits +3.4 deg off the travel line on average and swings between +0.5 and +6.4 — never
## once crossing to the other side. The neck and the spine read the SAME number as the head, so
## whatever does it happens at or below Spine01 and is simply inherited upward. This narrows it
## to the two layers cat_rig.tick applies to the spine while walking: the breath and the walk
## sway. Which one, and whether their axes are even the axes they were meant to be, is a
## measurement — and docs/AGENT_TRAPS is explicit that guessing a sign on this rig has already
## cost two rounds of mangled poses.
##
## PART 1 is a spine axis atlas: +0.2 rad about each local axis of Spine01/Spine02 in turn,
## reporting what it does to the HEAD's yaw, pitch and roll. Part 2 ticks the real cat_rig and
## reproduces the film's number without a world, so a fix can be re-measured in seconds.
##
##   godot --headless --path . res://tests/CatYawDiag.tscn

const RIG := preload("res://scripts/world/cat_rig.gd")
const GLB := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"

var _sk: Skeleton3D
## The model's own axes, from tests/BoneDump: the mesh AABB is (1.0, 0.566, 0.265), so the
## nose-to-tail axis is X, up is Y and the across-body axis is Z.
const FWD := Vector3(1, 0, 0)
const UP := Vector3(0, 1, 0)
var _head := -1
var _f_local: Vector3    ## the Head bone's own local vector that points along FWD at rest
var _u_local: Vector3    ## ...and the one that points along UP at rest

func _ready() -> void:
	var scene: PackedScene = load(GLB)
	var root: Node3D = scene.instantiate()
	add_child(root)
	for n in root.find_children("*", "Skeleton3D", true, false):
		_sk = n
		break
	if _sk == null:
		print("no skeleton")
		get_tree().quit(1)
		return
	_head = _sk.find_bone("Head")
	_sk.reset_bone_poses()
	_sk.force_update_all_bone_transforms()
	var b0: Basis = _sk.get_bone_global_pose(_head).basis
	_f_local = (b0.inverse() * FWD).normalized()
	_u_local = (b0.inverse() * UP).normalized()

	print("\n=== PART 1: what each spine axis does to the HEAD (+0.2 rad) ===")
	print("%-10s %-6s %8s %8s %8s" % ["bone", "axis", "yaw", "pitch", "roll"])
	for bn in ["Spine01", "Spine02", "Waist", "Hip", "NeckTwist01"]:
		var bi: int = _sk.find_bone(bn)
		if bi < 0:
			continue
		for ai in range(3):
			_sk.reset_bone_poses()
			var ax := Vector3(1 if ai == 0 else 0, 1 if ai == 1 else 0, 1 if ai == 2 else 0)
			_sk.set_bone_pose_rotation(bi,
				_sk.get_bone_rest(bi).basis.get_rotation_quaternion() * Quaternion(ax, 0.2))
			_sk.force_update_all_bone_transforms()
			var m: Array = _head_angles()
			print("%-10s %-6s %+8.2f %+8.2f %+8.2f"
				% [bn, ["X", "Y", "Z"][ai], m[0], m[1], m[2]])
	print("  -> the axis with the big YAW number is the one that turns the face sideways.")
	print("     cat_rig's breath uses local Z on Spine01/Spine02; its walk sway uses local Y.")

	print("\n=== PART 2: the layers as cat_rig actually applies them, walking ===")
	# The exact quaternions tick() composes at DEFAULT GAIT (mix = 0, so the gallop spine
	# engine is off and walk_w = gait_w = 1): breath about local Z, sway about local Y.
	for probe in [
			["breath peak", {"Spine01": [Vector3(0, 0, 1), 0.032], "Spine02": [Vector3(0, 0, 1), 0.0192]}],
			["sway peak", {"Spine01": [Vector3(0, 1, 0), 0.06], "Spine02": [Vector3(0, 1, 0), -0.045]}],
			["both peak", {}]]:
		_sk.reset_bone_poses()
		var layers: Dictionary = probe[1]
		if layers.is_empty():
			layers = {"Spine01": [Vector3(0, 0, 1), 0.032], "Spine02": [Vector3(0, 0, 1), 0.0192]}
			_apply(layers)
			layers = {"Spine01": [Vector3(0, 1, 0), 0.06], "Spine02": [Vector3(0, 1, 0), -0.045]}
			_apply(layers, false)
		else:
			_apply(layers)
		_sk.force_update_all_bone_transforms()
		var m: Array = _head_angles()
		print("  %-12s head yaw %+7.2f  pitch %+7.2f  roll %+7.2f" % [String(probe[0]), m[0], m[1], m[2]])

	print("\n=== PART 3: the live rig, ticked as the game ticks it, walking straight ===")
	var rig = RIG.new(_sk, "")
	var yaws: Array[float] = []
	var moved: float = 1.55 / 60.0
	for i in range(1200):
		rig.set_pose("walk", 10.0)
		rig.tick(1.0 / 60.0, 1.55, moved)
		_sk.force_update_all_bone_transforms()
		if i > 200:
			yaws.append(_head_angles()[0])
	var mn: float = yaws[0]
	var mx: float = yaws[0]
	var sm: float = 0.0
	for y in yaws:
		mn = minf(mn, y)
		mx = maxf(mx, y)
		sm += y
	print("  head yaw over %d ticks: mean %+.2f  min %+.2f  max %+.2f  (amplitude %.2f)"
		% [yaws.size(), sm / float(yaws.size()), mn, mx, (mx - mn) * 0.5])
	print("  CatFilm measured mean +3.43, min +0.49, max +6.40 on the live animal.")

	_gait_report(rig, 1.55, "WALK (default gait)")
	_gait_report(rig, 4.40, "RUN")
	get_tree().quit()

## PART 4: the two numbers a windowed film costs four minutes to produce, in ten seconds.
##
## Everything that matters about a gait's mechanics is measurable with no world at all: tick
## the rig, advance a notional body at the commanded speed, and add the two together to get
## each paw's WORLD track. A planted paw is then one whose world position does not move while
## it is down — and a limp is two paws on the same axle that do not describe the same arc.
##
## Both were measured on the live animal first (tests/CatFilm + tools/film_stats.py) so this
## harness could be checked against reality rather than trusted; it reproduces the film's
## numbers closely enough to iterate against, and the film stays the thing that settles it.
func _gait_report(rig, speed: float, label: String) -> void:
	var paws := {"lf": "L_Hand", "rf": "R_Hand", "lh": "L_Foot", "rh": "R_Foot"}
	var track := {}
	for k in paws:
		track[k] = []
	var dt: float = 1.0 / 60.0
	var moved: float = speed * dt
	var body: float = 0.0
	rig.set_pose("run" if speed > 3.0 else "walk", 10.0)
	for i in range(700):
		rig.tick(dt, speed, moved)
		_sk.force_update_all_bone_transforms()
		body += moved
		if i < 300:
			continue      # let the gait weight and the pose blend settle first
		for k in paws:
			var p: Vector3 = _sk.get_bone_global_pose(_sk.find_bone(paws[k])).origin
			(track[k] as Array).append(Vector3(p.x + body, p.y, p.z))
	print("\n=== PART 4: %s — paw tracks (skeleton + notional body travel) ===" % label)
	print("  %-4s %10s %10s %12s %12s" % ["paw", "lift mm", "reach mm", "stance mm/f", "stance m/s"])
	var lifts := {}
	var reaches := {}
	for k in paws:
		var tr: Array = track[k]
		var ys: Array[float] = []
		for p in tr:
			ys.append((p as Vector3).y)
		var lo: float = ys.min()
		var hi: float = ys.max()
		lifts[k] = hi - lo
		# Reach is measured in BODY space, so it is the arc the limb describes rather than the
		# ground the animal covered.
		var xs: Array[float] = []
		for j in range(tr.size()):
			xs.append((tr[j] as Vector3).x - moved * float(j))
		reaches[k] = xs.max() - xs.min()
		# STANCE SLIDE: how far the paw moves in the WORLD while it is in the bottom 30% of
		# its own lift range. On a planted foot this is near zero. The old FK gait measured
		# 24-30 mm/frame here — the paw was travelling at essentially body speed the whole
		# time, which is the weightless "skating" read.
		var gate: float = lo + (hi - lo) * 0.30
		var slide: float = 0.0
		var n: int = 0
		for j in range(1, tr.size()):
			if ys[j] <= gate and ys[j - 1] <= gate:
				slide += (tr[j] as Vector3).distance_to(tr[j - 1] as Vector3)
				n += 1
		var per: float = (slide / float(n)) if n > 0 else 0.0
		print("  %-4s %10.1f %10.1f %12.1f %12.2f"
			% [k, float(lifts[k]) * 1000.0, float(reaches[k]) * 1000.0, per * 1000.0, per / dt])
	for pair in [["lf", "rf", "fore"], ["lh", "rh", "hind"]]:
		var rl: float = float(lifts[pair[0]])
		var rr: float = maxf(float(lifts[pair[1]]), 1e-6)
		var xl: float = float(reaches[pair[0]])
		var xr: float = maxf(float(reaches[pair[1]]), 1e-6)
		print("  %-5s L/R lift ratio %.2f   reach ratio %.2f%s"
			% [pair[2], rl / rr, xl / xr,
				"   <== LIMP" if (rl / rr > 1.35 or rl / rr < 0.74 or xl / xr > 1.35 or xl / xr < 0.74) else ""])

func _apply(layers: Dictionary, reset_first: bool = true) -> void:
	for bn in layers:
		var bi: int = _sk.find_bone(bn)
		if bi < 0:
			continue
		var base: Quaternion = _sk.get_bone_pose_rotation(bi) if not reset_first \
			else _sk.get_bone_rest(bi).basis.get_rotation_quaternion()
		_sk.set_bone_pose_rotation(bi, base * Quaternion(layers[bn][0], layers[bn][1]))

## Head yaw / pitch / roll in degrees, relative to the rest pose, in the model's own frame.
func _head_angles() -> Array:
	var b: Basis = _sk.get_bone_global_pose(_head).basis
	var f: Vector3 = (b * _f_local).normalized()
	var u: Vector3 = (b * _u_local).normalized()
	var yaw: float = rad_to_deg(atan2(-f.z, f.x))          # about model up (+Y)
	var pitch: float = rad_to_deg(asin(clampf(f.y, -1.0, 1.0)))
	# Roll: how far the head's own up has tipped across the body, measured in the plane
	# perpendicular to its forward.
	var side: Vector3 = FWD.cross(UP).normalized()
	var roll: float = rad_to_deg(asin(clampf(u.dot(side), -1.0, 1.0)))
	return [yaw, pitch, roll]
