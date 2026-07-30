class_name StairKit extends RefCounted
## Real industrial stairs to replace the greybox ramps: checker-plate treads on
## angled steel stringers, correct riser/tread proportions, optional handrails.
## The walking surface is a single smooth INVISIBLE ramp collider under the
## stepped visuals — steps read as steps, but the capsule glides like a ramp, so
## no step-stutter and no seam catches (the "glitchy ramp" fix).

const RISER_TARGET: float = 0.19     # ideal riser height (m); step count derives from this
const TREAD_THICK: float = 0.06
const STRINGER_H: float = 0.30

## Build one flight from `from` (walk-on floor point) to `to` (walk-off floor
## point). Handles any horizontal direction and descending runs (swaps ends).
## rail_left/rail_right are relative to the direction of climb.
static func flight(parent: Node3D, from: Vector3, to: Vector3, width: float,
		rail_left: bool = false, rail_right: bool = false) -> void:
	if to.y < from.y:
		var tmp := from
		from = to
		to = tmp
		var swap := rail_left
		rail_left = rail_right
		rail_right = swap
	var delta: Vector3 = to - from
	var rise: float = delta.y
	var run: float = Vector2(delta.x, delta.z).length()
	if rise < 0.05 or run < 0.1:
		return
	var steps: int = maxi(2, roundi(rise / RISER_TARGET))
	var riser: float = rise / steps
	var tread_d: float = run / steps
	var angle: float = atan2(rise, run)

	# Container: local +Z is the direction of climb.
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = from
	root.rotation.y = atan2(delta.x, delta.z)

	var tread_mat: Material = MatLib.checker_plate()
	var steel: Material = MatLib.rust_steel()

	# Treads: visual only (the ramp collider is the walking surface). A small
	# nosing overlap keeps the front edges reading as one continuous stair.
	for i in range(steps):
		_vbox(root, Vector3(0, (i + 1) * riser - TREAD_THICK * 0.5, (i + 0.5) * tread_d),
			Vector3(width, TREAD_THICK, tread_d + 0.04), tread_mat)
		# Half-height riser plate — industrial stairs read open below, plated above.
		_vbox(root, Vector3(0, (i + 0.72) * riser, i * tread_d + 0.02),
			Vector3(width - 0.04, riser * 0.55, 0.03), steel)

	# Stringers: angled steel channels carrying the treads on both sides.
	var slope_len: float = sqrt(rise * rise + run * run)
	for side in [-1.0, 1.0]:
		var stringer := _vbox(root, Vector3(side * (width * 0.5 + 0.03), rise * 0.5 - 0.08, run * 0.5),
			Vector3(0.06, STRINGER_H, slope_len + 0.3), steel)
		stringer.rotation.x = -angle

	# The real walking surface: one smooth invisible ramp + tiny flat lips at the
	# ends so the capsule never catches on the floor/landing seams.
	#
	# FLUSH IS SOLVED HERE, ONCE, IN CLOSED FORM. A box of half-thickness `h` pitched by
	# `angle` has its TOP face pass through the box centre's height plus h/cos(angle) —
	# not plus h — so a ramp centred at `rise/2 - h` overshoots the floor at both ends by
	# `h/cos(angle) - h`. Every caller used to correct that with its own copy of
	# `-0.05 + 0.05*sin + 0.06*cos`, which is a different number: it is short of the truth
	# for every flight shallower than 39.8 deg, i.e. for all thirteen flights in the game,
	# leaving the ramp 1.3 mm (tower) to 9.6 mm (obs platform) BELOW its landing. The
	# landing's leading edge therefore stood proud, and a 0.37 m capsule meets a 1.3 mm
	# proud edge with a contact normal 42.8 deg off vertical — inside `floor_max_angle`
	# (46 deg), so it is not a wall, it is a floor that costs you a physics tick. At 30 Hz
	# and 3.2 m/s one lost tick is a 107 mm hitch: exactly the reported "slows you down".
	#
	# Deriving it once and building it right means no caller has to know any of this.
	const RAMP_HALF: float = 0.06
	var body := StaticBody3D.new()
	root.add_child(body)
	var ramp := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(width, RAMP_HALF * 2.0, slope_len + 0.1)
	ramp.shape = rbox
	body.add_child(ramp)
	ramp.position = Vector3(0, rise * 0.5 - RAMP_HALF / cos(angle), run * 0.5)
	ramp.rotation.x = -angle
	# ONE END LIP, AT THE FOOT ONLY, AND SUNK.
	#
	# There used to be two, and BOTH of them were the reported catch. A lip is a flat
	# 0.4 m plate at the height of the surface it joins, so any part of it that lies over
	# the SLOPE is a curb standing `0.4 * tan(angle)` above the run — 0.31 m on the tower
	# flights. That is why the callers used to slide the top one forward to `run + 0.22`;
	# but forward is inside the landing slab, where it became a second static body
	# presenting the landing's own walking plane, coplanar to the millimetre, exactly
	# under the capsule's transition. (Jolt's enhanced internal edge removal does not
	# reach it: that suppresses internal edges WITHIN one shape, and these are two.)
	#
	# With the ramp built flush, the top lip has no job left: the ramp's top surface
	# passes through (run, rise), which is the landing slab's own leading edge, so the two
	# already form one continuous surface. It is gone. Measured across 0.9 m of every
	# junction on the rig at 10 mm, the worst step is now under 2 mm.
	#
	# The foot lip stays as a floor of last resort — sunk `LIP_SINK` so the deck slab wins
	# the contact — and is pulled forward to sit UNDER the run rather than in front of it,
	# where it would have been the same curb pointing the other way.
	const LIP_SINK: float = 0.006
	var flat := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(width, 0.12, 0.4)
	flat.shape = fbox
	body.add_child(flat)
	flat.position = Vector3(0, -RAMP_HALF - LIP_SINK, 0.20)

	# Handrails: posts off the stringer, sloped top rail (collides — a real guard).
	for side_flag in [[rail_left, -1.0], [rail_right, 1.0]]:
		if not side_flag[0]:
			continue
		var s: float = side_flag[1]
		var rail := _vbox(root, Vector3(s * (width * 0.5 + 0.05), rise * 0.5 + 0.95, run * 0.5),
			Vector3(0.07, 0.07, slope_len + 0.2), steel, true)
		rail.rotation.x = -angle
		var n_posts: int = maxi(2, int(run / 1.4))
		for i in range(n_posts + 1):
			var t: float = float(i) / n_posts
			_vbox(root, Vector3(s * (width * 0.5 + 0.05), t * rise + 0.5, t * run),
				Vector3(0.05, 1.0, 0.05), steel)

## Visual box helper in the flight's local space; collide=true wraps a StaticBody3D.
static func _vbox(root: Node3D, pos: Vector3, size: Vector3, mat: Material,
		collide: bool = false) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	if not collide:
		root.add_child(mi)
		mi.position = pos
		return mi
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_child(mi)
	root.add_child(body)
	body.position = pos
	return body
