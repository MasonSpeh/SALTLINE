class_name RigSuperstructure extends Node3D
## The accommodation stack — four decks of live-in rig above the topside rooms,
## crowned by a roof deck and the comms mast. Built entirely in code like RigBuilder;
## positions are level design. Decks (floor surface Y): A = the existing topside rooms
## at 18.0, B quarters 21.6, C control 25.1, D works 28.6, roof 32.1.
##
## Access: exterior ramp from the topside deck up to the Deck B south balcony, the
## external west stair to the C terrace, and a LADDER WELL in the old shaft
## (x 23..27, z 13..17.5) linking B -> C -> D -> roof hut through slab hatches.

const STAIRS := preload("res://scripts/world/stair_kit.gd")   # by path: class cache lags new files

const DECK_Y: float = 18.0
const B_Y: float = 21.6
const C_Y: float = 25.1
const D_Y: float = 28.6
const ROOF_Y: float = 32.1
const WH: float = 3.2          # interior wall height
const WT: float = 0.25         # wall thickness
const RISE: float = 3.5        # floor-to-floor

# Stairwell shaft bounds.
const SX0: float = 23.0
const SX1: float = 27.0
const SZ0: float = 13.0
const SZ1: float = 17.5

func _ready() -> void:
	_supports()
	_deck_b()
	_deck_c()
	_deck_d()
	_roof()
	_mast()
	_exterior_dressing()
	_deck_a_signage()
	_density_pass()

# ============================================================ helpers

func _box(pos: Vector3, size: Vector3, mat: Material, collide: bool = true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.material = mat
	b.use_collision = collide
	add_child(b)
	b.position = pos
	return b

## Non-colliding decoration mesh — cheap MeshInstance3D, not CSG.
func _dbox(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	add_child(mi)
	mi.position = pos
	return mi

func _dcyl(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.material = mat
	mi.mesh = m
	add_child(mi)
	mi.position = pos
	return mi

func _cyl(pos: Vector3, radius: float, height: float, mat: Material) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = height
	c.material = mat
	c.use_collision = true
	add_child(c)
	c.position = pos
	return c

## Wall from a to b (axis aligned) with optional doorway at fraction door_t.
func _wall(a: Vector3, b: Vector3, height: float, mat: Material, door_t: float = -1.0) -> void:
	var dir: Vector3 = b - a
	var length: float = dir.length()
	var mid: Vector3 = (a + b) * 0.5
	var along_x: bool = absf(dir.x) > absf(dir.z)
	if door_t < 0.0:
		var size := Vector3(length, height, WT) if along_x else Vector3(WT, height, length)
		_box(mid + Vector3(0, height * 0.5, 0), size, mat)
		return
	var door_w: float = 1.4
	var door_pos: float = clampf(door_t, 0.1, 0.9) * length
	var seg1: float = door_pos - door_w * 0.5
	var seg2: float = length - door_pos - door_w * 0.5
	var u: Vector3 = dir.normalized()
	if seg1 > 0.05:
		var c1: Vector3 = a + u * (seg1 * 0.5)
		_box(c1 + Vector3(0, height * 0.5, 0),
			Vector3(seg1, height, WT) if along_x else Vector3(WT, height, seg1), mat)
	if seg2 > 0.05:
		var c2: Vector3 = b - u * (seg2 * 0.5)
		_box(c2 + Vector3(0, height * 0.5, 0),
			Vector3(seg2, height, WT) if along_x else Vector3(WT, height, seg2), mat)
	var lintel_h: float = height - 2.2
	if lintel_h > 0.05:
		var cl: Vector3 = a + u * door_pos
		_box(cl + Vector3(0, 2.2 + lintel_h * 0.5, 0),
			Vector3(door_w, lintel_h, WT) if along_x else Vector3(WT, lintel_h, door_w), mat)

## Hang a real hinged door at a hinge line (see rig_builder._hang_door for the full note).
func _hang_door(hinge_world: Vector3, leaf_dir: Vector3, wooden: bool,
		leaf_w: float, leaf_h: float, name_: String = "Door") -> InteractDoor:
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.global_position = hinge_world
	pivot.rotation.y = atan2(-leaf_dir.z, leaf_dir.x)
	var door := InteractDoor.new()
	door.wooden = wooden
	door.display_name = name_
	pivot.add_child(door)
	door.build_door(leaf_w, leaf_h)
	return door

## Cut a doorway (as _wall's door_t) and fit it with a framed hinged door whose steel
## liner meets the full 2.2m opening — no dark gap above the frame.
func _fit_door(a: Vector3, b: Vector3, height: float, mat: Material, door_t: float,
		wooden: bool = true, hinge_at_a: bool = true, name_: String = "Door") -> InteractDoor:
	_wall(a, b, height, mat, door_t)
	var dir: Vector3 = b - a
	var length: float = dir.length()
	var along_x: bool = absf(dir.x) > absf(dir.z)
	var u: Vector3 = dir.normalized()
	var door_pos: float = clampf(door_t, 0.1, 0.9) * length
	var center: Vector3 = a + u * door_pos
	const OPEN_W: float = 1.4
	const OPEN_H: float = 2.2
	var half: float = OPEN_W * 0.5
	var steel: Material = MatLib.rust_steel()
	var ja: Vector3 = center - u * half
	var jb: Vector3 = center + u * half
	if along_x:
		_box(Vector3(ja.x, a.y + OPEN_H * 0.5, a.z), Vector3(0.12, OPEN_H, WT + 0.1), steel, false)
		_box(Vector3(jb.x, a.y + OPEN_H * 0.5, a.z), Vector3(0.12, OPEN_H, WT + 0.1), steel, false)
		_box(Vector3(center.x, a.y + OPEN_H + 0.08, a.z), Vector3(OPEN_W + 0.24, 0.16, WT + 0.1), steel, false)
	else:
		_box(Vector3(a.x, a.y + OPEN_H * 0.5, ja.z), Vector3(WT + 0.1, OPEN_H, 0.12), steel, false)
		_box(Vector3(a.x, a.y + OPEN_H * 0.5, jb.z), Vector3(WT + 0.1, OPEN_H, 0.12), steel, false)
		_box(Vector3(a.x, a.y + OPEN_H + 0.08, center.z), Vector3(WT + 0.1, 0.16, OPEN_W + 0.24), steel, false)
	var ld: Vector3 = u if hinge_at_a else -u
	var hinge: Vector3 = center - ld * (half - 0.02)
	return _hang_door(Vector3(hinge.x, a.y, hinge.z), ld, wooden, OPEN_W - 0.06, OPEN_H - 0.08, name_)

func _ramp(from: Vector3, to: Vector3, width: float, mat: Material) -> void:
	var b := CSGBox3D.new()
	b.size = Vector3(width, 0.25, from.distance_to(to))
	b.material = mat
	b.use_collision = true
	add_child(b)
	b.global_position = (from + to) * 0.5
	b.look_at(to, Vector3.UP)

## Offshore rail grammar: top rail + mid rail + kick plate at the deck. The mid
## rail and toe board are what make a catwalk read as regulation rig, not fence.
##
## COLLISION is deliberately NOT the visual rail. Every bar and post here is visual
## only, and the guard the player actually touches is one smooth slab (see
## _rail_slab). The rails used to collide as a single 0.1m bar at waist height with
## open air above and below it: a 0.4m-radius capsule pressed into that gap wedges
## between the bar and the deck edge and cannot be walked out of — the trap that
## cost the owner a restart on the stair rails.
func _rail_x(x0: float, x1: float, y: float, z: float) -> void:
	var mat: Material = MatLib.rust_steel()
	_dbox(Vector3((x0 + x1) * 0.5, y + 0.55, z), Vector3(x1 - x0, 0.1, 0.1), mat)
	_dbox(Vector3((x0 + x1) * 0.5, y + 0.3, z), Vector3(x1 - x0, 0.06, 0.06), mat)
	_dbox(Vector3((x0 + x1) * 0.5, y + 0.07, z), Vector3(x1 - x0, 0.14, 0.03), mat)
	var n: int = maxi(2, int((x1 - x0) / 2.2))
	for i in range(n + 1):
		_dbox(Vector3(x0 + (x1 - x0) * i / n, y + 0.28, z), Vector3(0.06, 0.56, 0.06), mat)
	_rail_slab(Vector3((x0 + x1) * 0.5, y + 0.53, z), Vector3(x1 - x0, 1.2, 0.07))

func _rail_z(z0: float, z1: float, y: float, x: float) -> void:
	var mat: Material = MatLib.rust_steel()
	_dbox(Vector3(x, y + 0.55, (z0 + z1) * 0.5), Vector3(0.1, 0.1, z1 - z0), mat)
	_dbox(Vector3(x, y + 0.3, (z0 + z1) * 0.5), Vector3(0.06, 0.06, z1 - z0), mat)
	_dbox(Vector3(x, y + 0.07, (z0 + z1) * 0.5), Vector3(0.03, 0.14, z1 - z0), mat)
	var n: int = maxi(2, int((z1 - z0) / 2.2))
	for i in range(n + 1):
		_dbox(Vector3(x, y + 0.28, z0 + (z1 - z0) * i / n), Vector3(0.06, 0.56, 0.06), mat)
	_rail_slab(Vector3(x, y + 0.53, (z0 + z1) * 0.5), Vector3(0.07, 1.2, z1 - z0))

## The single smooth guard a railing presents to the player: one full-height box from
## just under the deck line to just over the top bar, with no posts, no gaps and no
## lips to wedge a capsule against. Invisible — the rail's own steel is what you see.
func _rail_slab(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.position = pos

## Build a stair flight with StairKit, then repair the two things in its COLLISION
## that a 0.4m-radius player capsule cannot get past. StairKit is shared code we do
## not own (see the hand-off note in the batch report); every visual it builds is
## kept exactly as-is and only collision shapes are touched.
##
## 1. THE CURB. StairKit's flat top lip is a plate at full `rise` that begins 0.25m
##    back along the run, where the sloped walking surface is still 0.25*tan(angle)
##    lower. That leaves a square step across the top tread: 0.15m on the west stair,
##    0.17m on the tower. A capsule of this radius can only roll up about 0.117m
##    before the contact normal tips past floor_max_angle and the step reads as a
##    wall — which is exactly why the last flight had "a lip you must JUMP over".
##    Sliding the lip past the top of the ramp leaves the join flush to ~0.03m.
## 2. THE RAIL. StairKit's handrail collides as one thin bar at chest height with
##    open air beneath it, so a capsule's waist catches the bar while its feet slide
##    under. We drop that collider and stand a single smooth slab just inside the
##    visual rail instead.
func _stair_run(from: Vector3, to: Vector3, width: float,
		rail_left: bool = false, rail_right: bool = false) -> void:
	if to.y < from.y:
		var swap: Vector3 = from
		from = to
		to = swap
		var flip: bool = rail_left
		rail_left = rail_right
		rail_right = flip
	var delta: Vector3 = to - from
	var rise: float = delta.y
	var run: float = Vector2(delta.x, delta.z).length()
	STAIRS.flight(self, from, to, width, rail_left, rail_right)
	if rise < 0.05 or run < 0.1:
		return   # StairKit bailed out and built nothing; there is no root to patch
	var root := get_child(get_child_count() - 1) as Node3D
	if root == null:
		return
	var slope_len: float = sqrt(rise * rise + run * run)
	var angle: float = atan2(rise, run)
	# StairKit's ramp sits 0.05 low at the foot and is 0.06 thick, so its top surface
	# OVERSHOOTS the landing height by a couple of centimetres at the top of the run.
	# Two centimetres sounds harmless. It is not: a 0.4m-radius capsule climbing a
	# 39-degree slope first touches the landing's leading corner from 0.36m back, where
	# the ramp is a quarter of a metre lower, and that contact is ~51 degrees off
	# vertical — past floor_max_angle, so CharacterBody3D calls it a wall and the climb
	# stops dead one step short of the top. Dropping the ramp by exactly its overshoot
	# makes the walking surface pass through the foot and the top corner, so run and
	# landing meet flush and the corner is no longer something that has to be climbed.
	var overshoot: float = -0.05 + 0.05 * sin(angle) + 0.06 * cos(angle)
	for child in root.get_children():
		var body := child as StaticBody3D
		if body == null:
			continue
		var is_rail: bool = false
		for c in body.get_children():
			if c is MeshInstance3D:
				is_rail = true   # a railed _vbox carries its mesh; the walk body does not
		for c in body.get_children():
			var cs := c as CollisionShape3D
			if cs == null:
				continue
			if is_rail:
				cs.disabled = true
			elif absf(cs.rotation.x) > 0.001:
				cs.position.y -= overshoot   # the sloped walking surface, set flush
			elif cs.position.z > run * 0.5:
				cs.position.z = run + 0.22   # the top lip, slid clear of the slope
	# One smooth guard slab per railed side, inset inside the visual rail and sunk
	# below the treads so there is no foot gap running along the bottom of it.
	for side in [[rail_left, -1.0], [rail_right, 1.0]]:
		if not bool(side[0]):
			continue
		var guard := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.08, 1.6, slope_len + 0.2)
		shape.shape = box
		guard.add_child(shape)
		root.add_child(guard)
		guard.position = Vector3(float(side[1]) * (width * 0.5 + 0.02),
			rise * 0.5 + 0.5, run * 0.5)
		guard.rotation.x = -angle

## Wall sign — reads as PAINTED block lettering, not a lit sign: shaded so it takes
## scene light like the concrete it's stenciled on, slightly weathered alpha.
## yaw_deg: 0 faces +Z, 180 faces -Z, 90 faces +X, -90 faces -X.
## pitch_deg tips the paint out of vertical: pass -90 to lay a marking FLAT on decking,
## which is the only way a stencil authored at floor height reads as paint rather than
## as an upright sheet standing in the plating.
func _label(text: String, pos: Vector3, yaw_deg: float, font_size: int = 48,
		color: Color = Color(0.85, 0.87, 0.84), pitch_deg: float = 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	# Scaled down — oversized paint bled across panel joints and door reveals.
	l.font_size = maxi(12, int(font_size * 0.72))
	l.pixel_size = 0.01
	var _wear: float = clampf((color.r + color.g + color.b) / 3.0, 0.0, 1.0)   # black stencil paint
	var _k: float = lerpf(0.06, 0.17, _wear)
	l.modulate = Color(_k, _k, _k * 1.08, minf(color.a, 0.9))
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false   # paint has no mirrored back face
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # nor does it turn to face you
	add_child(l)
	l.position = pos
	l.rotation.y = deg_to_rad(yaw_deg)
	l.rotation.x = deg_to_rad(pitch_deg)

func _light(pos: Vector3, energy: float = 0.55, range_: float = 7.0) -> void:
	var l := OmniLight3D.new()
	l.light_energy = energy
	l.omni_range = range_
	l.light_color = Color(0.8, 0.83, 0.86)
	l.add_to_group("spill_lights")
	add_child(l)
	l.position = pos
	# Dead ceiling fixture under it.
	_dbox(pos + Vector3(0, 0.35, 0), Vector3(0.7, 0.08, 0.24), MatLib.dark_metal())

## Horizontal pipe along X or Z, with elbow spheres at both ends.
func _pipe(a: Vector3, b: Vector3, radius: float = 0.09) -> void:
	var mid: Vector3 = (a + b) * 0.5
	var p := _dcyl(mid, radius, a.distance_to(b), MatLib.rusty_metal())
	if absf(b.x - a.x) > absf(b.z - a.z):
		p.rotation.z = PI / 2
	else:
		p.rotation.x = PI / 2
	for e in [a, b]:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius * 1.3
		sm.height = radius * 2.6
		sm.material = MatLib.rusty_metal()
		s.mesh = sm
		add_child(s)
		s.position = e

func _valve(pos: Vector3, along_x: bool) -> void:
	## Wheel standing upright, its face across the pipe run.
	var w := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.09
	tm.outer_radius = 0.17
	tm.material = MatLib.flat(Color(0.62, 0.14, 0.1))
	w.mesh = tm
	add_child(w)
	w.position = pos
	if along_x:
		w.rotation.z = PI / 2
	else:
		w.rotation.x = PI / 2

func _extinguisher(pos: Vector3) -> void:
	_dcyl(pos + Vector3(0, 0.26, 0), 0.09, 0.52, MatLib.flat(Color(0.75, 0.12, 0.08)))
	_dbox(pos + Vector3(0, 0.56, 0), Vector3(0.05, 0.1, 0.05), MatLib.dark_metal())

# Window module: shared across all decks so openings stack into vertical columns.
const WIN_SILL: float = 0.95     # opening bottom above floor
const WIN_H: float = 1.45        # opening height
const WIN_W: float = 1.6         # opening width
const WIN_GRID: float = 4.0      # module spacing; centers land on multiples

## A real framed window sitting IN a wall opening: painted-steel frame, a cross
## mullion, and glass that glows warm when the deck is lit / reads cold-dark when
## not. Built identically on both wall faces so it lines up inside and out.
## along_x: wall runs along X at fixed z (pos.z is the wall centreline).
func _window(pos: Vector3, along_x: bool, lit: bool) -> void:
	# See-through glass (was an opaque flat pane — you couldn't look out). The warm
	# lit read is carried by the OmniLight3D spill added below.
	var glass_mat: Material = MatLib.glass(Color(0.95, 0.82, 0.55)) if lit \
		else MatLib.glass(Color(0.42, 0.55, 0.6))
	var frame: Material = MatLib.painted_steel()
	var t: float = WT + 0.06
	if along_x:
		_dbox(pos, Vector3(WIN_W - 0.1, WIN_H - 0.1, WT - 0.02), glass_mat)          # pane
		_dbox(pos, Vector3(0.09, WIN_H + 0.14, t), frame)                             # centre mullion (vert)
		_dbox(pos, Vector3(WIN_W + 0.14, 0.09, t), frame)                            # centre mullion (horiz)
		_dbox(pos + Vector3(0, WIN_H * 0.5 + 0.04, 0), Vector3(WIN_W + 0.2, 0.12, t), frame)  # head
		_dbox(pos + Vector3(0, -WIN_H * 0.5 - 0.04, 0), Vector3(WIN_W + 0.2, 0.14, t), frame)  # sill
		_dbox(pos + Vector3(WIN_W * 0.5 + 0.05, 0, 0), Vector3(0.12, WIN_H + 0.2, t), frame)   # jambs
		_dbox(pos + Vector3(-WIN_W * 0.5 - 0.05, 0, 0), Vector3(0.12, WIN_H + 0.2, t), frame)
	else:
		_dbox(pos, Vector3(WT - 0.02, WIN_H - 0.1, WIN_W - 0.1), glass_mat)
		_dbox(pos, Vector3(t, WIN_H + 0.14, 0.09), frame)
		_dbox(pos, Vector3(t, 0.09, WIN_W + 0.14), frame)
		_dbox(pos + Vector3(0, WIN_H * 0.5 + 0.04, 0), Vector3(t, 0.12, WIN_W + 0.2), frame)
		_dbox(pos + Vector3(0, -WIN_H * 0.5 - 0.04, 0), Vector3(t, 0.14, WIN_W + 0.2), frame)
		_dbox(pos + Vector3(0, 0, WIN_W * 0.5 + 0.05), Vector3(t, WIN_H + 0.2, 0.12), frame)
		_dbox(pos + Vector3(0, 0, -WIN_W * 0.5 - 0.05), Vector3(t, WIN_H + 0.2, 0.12), frame)
	if lit:
		var spill := OmniLight3D.new()
		spill.light_energy = 0.5
		spill.omni_range = 3.2
		spill.light_color = Color(1.0, 0.82, 0.5)
		spill.shadow_enabled = false
		# This stands for warm light coming THROUGH the window opening, not a lamp — its
		# anchor is the window it is offset from, so it joins the sourceless daylight group
		# the LightAnchorProbe exempts (see that probe's header).
		spill.add_to_group("spill_lights")
		add_child(spill)
		spill.position = pos + (Vector3(0, 0, 0.6 * signf(-pos.z + 12.0)) if along_x else Vector3(0.6 * signf(-pos.x + 13.0), 0, 0))

## An exterior wall run (along X at fixed z) with real window openings on the
## shared grid: solid sill band below, lintel band above, piers between windows,
## and a framed glass unit in every opening. door_x (NAN = none) leaves a
## full-height gap for a doorway. Windows land on WIN_GRID multiples inside the
## span so B/C/D stack vertically.
func _ext_win_wall_x(x0: float, x1: float, z: float, floor_y: float, mat: Material,
		lit: bool, door_x: float = NAN) -> void:
	var centers: Array[float] = []
	var g: float = ceil((x0 + 1.2) / WIN_GRID) * WIN_GRID
	while g <= x1 - 1.2:
		if is_nan(door_x) or absf(g - door_x) > 1.8:
			centers.append(g)
		g += WIN_GRID
	# Build occlusion spans: window openings + the door, sorted, to segment bands.
	var gaps: Array = []
	for c in centers:
		gaps.append([c - WIN_W * 0.5, c + WIN_W * 0.5])
	if not is_nan(door_x):
		gaps.append([door_x - 0.75, door_x + 0.75])
	gaps.sort_custom(func(a, b): return a[0] < b[0])
	# Bottom (sill) and top (lintel) bands, segmented only by the door (windows
	# sit above the sill band and below the lintel band, so those are continuous
	# except where the door punches full height).
	var bands := [
		[floor_y + WIN_SILL * 0.5, WIN_SILL],                              # below sill
		[floor_y + WIN_SILL + WIN_H + (WH - WIN_SILL - WIN_H) * 0.5, WH - WIN_SILL - WIN_H],  # lintel
	]
	for band in bands:
		var cy: float = band[0]
		var ch: float = band[1]
		if ch <= 0.02:
			continue
		if is_nan(door_x):
			_box(Vector3((x0 + x1) * 0.5, cy, z), Vector3(x1 - x0, ch, WT), mat)
		else:
			if door_x - 0.75 - x0 > 0.05:
				_box(Vector3((x0 + door_x - 0.75) * 0.5, cy, z), Vector3(door_x - 0.75 - x0, ch, WT), mat)
			if x1 - (door_x + 0.75) > 0.05:
				_box(Vector3((door_x + 0.75 + x1) * 0.5, cy, z), Vector3(x1 - door_x - 0.75, ch, WT), mat)
	# Piers filling the wall band between openings (sill..lintel height).
	var pier_y: float = floor_y + WIN_SILL + WIN_H * 0.5
	var cursor: float = x0
	for gap in gaps:
		if gap[0] - cursor > 0.05:
			_box(Vector3((cursor + gap[0]) * 0.5, pier_y, z), Vector3(gap[0] - cursor, WIN_H, WT), mat)
		cursor = maxf(cursor, gap[1])
	if x1 - cursor > 0.05:
		_box(Vector3((cursor + x1) * 0.5, pier_y, z), Vector3(x1 - cursor, WIN_H, WT), mat)
	# The windows themselves.
	for c in centers:
		_window(Vector3(c, floor_y + WIN_SILL + WIN_H * 0.5, z), true, lit)

func _porthole(pos: Vector3, along_x: bool) -> void:
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.19
	tm.outer_radius = 0.27
	tm.material = MatLib.painted_steel()
	rim.mesh = tm
	add_child(rim)
	rim.position = pos
	rim.rotation.x = PI / 2
	if along_x:
		rim.rotation.z = PI / 2
	var glass := _dbox(pos, Vector3(0.05, 0.38, 0.38) if along_x else Vector3(0.38, 0.38, 0.05),
		MatLib.flat(Color(0.08, 0.14, 0.17)))
	glass.position = pos

func _takeable(item: String, name_: String, pos: Vector3) -> void:
	var t := Takeable.new()
	t.item_id = item
	t.display_name = name_
	add_child(t)
	t.position = pos
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	col.shape = box
	t.add_child(col)
	col.position.y = 0.2
	t.add_child(ItemVisual.build(item))
	preload("res://scripts/world/surface_snap.gd").attach(t)

func _readable(id: String, name_: String, pos: Vector3, size: Vector3 = Vector3(0.32, 0.42, 0.05)) -> void:
	var r := Readable.new()
	r.readable_id = id
	r.display_name = name_
	add_child(r)
	r.position = pos
	r.build_visual(size)

func _crate(items: Array, name_: String, pos: Vector3) -> void:
	var c := LootContainer.new()
	var typed: Array[String] = []
	for i in items:
		typed.append(str(i))
	c.items = typed
	c.display_name = name_
	add_child(c)
	c.position = pos
	c.build_box_visual(Vector3(1.0, 0.75, 0.75), Color(0.5, 0.45, 0.3), false, true)
	preload("res://scripts/world/surface_snap.gd").attach(c)

# ---- furniture kits (decoration-grade: no collision except the big hulls) ----

func _bunk(pos: Vector3, messy: bool) -> void:
	_box(pos + Vector3(0, 0.65, 0), Vector3(0.95, 1.3, 2.05), MatLib.painted_steel())  # frame hull
	for lv in [0.72, 1.38]:
		_dbox(pos + Vector3(0, lv, 0), Vector3(0.9, 0.12, 1.95), MatLib.canvas(Color(0.72, 0.75, 0.77)))
		_dbox(pos + Vector3(0, lv + 0.08, -0.75), Vector3(0.5, 0.08, 0.3), MatLib.canvas(Color(0.88, 0.88, 0.84)))
	if messy:
		var bl := _dbox(pos + Vector3(0.18, 0.84, 0.35), Vector3(0.7, 0.14, 0.8), MatLib.canvas(Color(0.5, 0.54, 0.58)))
		bl.rotation.y = 0.45
	# You can turn in here too — a collision-only Bed wrapping the frame so the
	# interaction ray reads SLEEP at night (bedding is the mesh above).
	var b: Interactable = preload("res://scripts/components/bed.gd").new()
	b.set("build_bedding", false)
	b.set("col_size", Vector3(1.05, 1.42, 2.15))
	add_child(b)
	b.global_position = pos + Vector3(0, 0.65, 0)

func _locker(pos: Vector3, open: bool = false) -> void:
	_box(pos + Vector3(0, 0.9, 0), Vector3(0.55, 1.8, 0.55), MatLib.painted_steel())
	if open:
		var d := _dbox(pos + Vector3(0.35, 0.9, 0.2), Vector3(0.04, 1.7, 0.5), MatLib.painted_steel())
		d.rotation.y = 0.8

func _desk(pos: Vector3, yaw: float = 0.0) -> void:
	var d := _box(pos + Vector3(0, 0.4, 0), Vector3(1.2, 0.8, 0.6), MatLib.wood())
	d.rotation.y = yaw
	var c := _dbox(pos + Vector3(0, 0.25, 0.55), Vector3(0.45, 0.5, 0.45), MatLib.dark_metal())
	c.rotation.y = yaw

func _table(pos: Vector3, size: Vector2 = Vector2(1.6, 0.9)) -> void:
	_box(pos + Vector3(0, 0.46, 0), Vector3(size.x, 0.08, size.y), MatLib.wood())
	_dbox(pos + Vector3(0, 0.2, 0), Vector3(0.14, 0.4, 0.14), MatLib.wood())

func _monitor(pos: Vector3, yaw: float) -> void:
	var m := _dbox(pos, Vector3(0.65, 0.45, 0.09), MatLib.flat(Color(0.06, 0.07, 0.09)))
	m.rotation.y = yaw
	m.rotation.x = -0.12

# ============================================================ structure

## Columns that carry the Deck B slab edges over open topside deck.
func _supports() -> void:
	var mat: Material = MatLib.rust_steel()
	for p in [Vector3(0, 0, 7.2), Vector3(8, 0, 7.2), Vector3(20, 0, 7.2),
			Vector3(16, 0, 8.6), Vector3(16, 0, 16.5)]:   # 10.5 -> 8.6: was blocking the rec-room west door (z11)
		_box(Vector3(p.x, (DECK_Y + B_Y - 0.3) * 0.5, p.z),
			Vector3(0.35, B_Y - 0.3 - DECK_Y, 0.35), mat)

# Ladder-well hatch bounds (NE corner of the shaft) — slabs open only here.
const HX0: float = 25.7
const HX1: float = 27.0
const HZ0: float = 15.8
const HZ1: float = 17.2

## One rung ladder inside the well: floor_y up to the hatch in the slab above.
## Replaces the old crisscrossing ramp flights that clipped through everything.
func _well_ladder(floor_y: float) -> void:
	var l := Ladder.new()
	l.height = RISE
	l.display_name = "Ladder Well"
	l.exit_forward = 1.3   # mantle lands west of the hatch, on solid slab
	add_child(l)
	# Freestanding mid-hatch so the climber's capsule clears the slab opening
	# (climb position = base + face_dir * 0.45 must stay inside the hatch rect).
	l.position = Vector3(25.95, floor_y, 16.5)
	l.rotation.y = deg_to_rad(-90)
	var rail_mat := MatLib.flat(Interactable.COLOR_TAKEABLE)
	var rung_mat := MatLib.flat(Color(0.75, 0.65, 0.15))
	for side in [-0.24, 0.24]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.09, RISE, 0.09)
		rm.material = rail_mat
		rail.mesh = rm
		l.add_child(rail)
		rail.position = Vector3(side, RISE * 0.5, 0)
	var rungs: int = maxi(2, int(RISE / 0.32))
	for i in range(rungs):
		var rung := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.56, 0.05, 0.05)
		gm.material = rung_mat
		rung.mesh = gm
		l.add_child(rung)
		rung.position = Vector3(0, (i + 0.5) * (RISE / rungs), 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, RISE, 0.35)
	shape.shape = box
	l.add_child(shape)
	shape.position = Vector3(0, RISE * 0.5, 0)
	# Hatch guards on the floor ABOVE: full rail on the south edge, west edge gets
	# two stubs with a gate aligned to the ladder — you step up to the rim, aim at
	# the rungs, and E takes you. Nothing seals the hatch off.
	var top: float = floor_y + RISE
	_box(Vector3((HX0 + HX1) * 0.5, top + 0.5, HZ0 - 0.05), Vector3(HX1 - HX0, 1.0, 0.08), MatLib.rust_steel())
	_box(Vector3(HX0 - 0.05, top + 0.5, 15.95), Vector3(0.08, 1.0, 0.3), MatLib.rust_steel())
	_box(Vector3(HX0 - 0.05, top + 0.5, 17.05), Vector3(0.08, 1.0, 0.3), MatLib.rust_steel())
	# Hazard paint on the slab at the gate.
	_dbox(Vector3(HX0 - 0.35, top + 0.02, 16.5), Vector3(0.5, 0.02, 1.0), MatLib.flat(Color(0.8, 0.7, 0.1)))

## Shaft walls for one storey with a doorway. door_side: "south" or "west".
## z0 lets a deck pull the south wall back so it never pinches a corridor
## (C-deck: wall at z 14 aligns with the corridor's north edge).
func _shaft_walls(y: float, h: float, door_side: String, door_t: float = 0.1, z0: float = SZ0) -> void:
	var mat: Material = MatLib.concrete()
	_wall(Vector3(SX0, y, z0), Vector3(SX1, y, z0), h, mat, door_t if door_side == "south" else -1.0)
	_wall(Vector3(SX0, y, SZ1), Vector3(SX1, y, SZ1), h, mat)
	_wall(Vector3(SX0, y, z0), Vector3(SX0, y, SZ1), h, mat, door_t if door_side == "west" else -1.0)
	_wall(Vector3(SX1, y, z0), Vector3(SX1, y, SZ1), h, mat)

## Floor slab covering x0..x1, z0..z1, solid everywhere except the ladder-well
## hatch (HX0..HX1, HZ0..HZ1). The shaft now has a real floor on every deck —
## a small landing room — instead of a full-shaft void full of ramps.
func _slab_with_shaft_hole(y_center: float, x0: float, x1: float, z0: float, z1: float, mat: Material) -> void:
	# West of the hatch.
	_box(Vector3((x0 + HX0) * 0.5, y_center, (z0 + z1) * 0.5), Vector3(HX0 - x0, 0.3, z1 - z0), mat)
	# East of the hatch.
	if x1 > HX1:
		_box(Vector3((HX1 + x1) * 0.5, y_center, (z0 + z1) * 0.5), Vector3(x1 - HX1, 0.3, z1 - z0), mat)
	# South strip beside the hatch.
	if HZ0 > z0:
		_box(Vector3((HX0 + HX1) * 0.5, y_center, (z0 + HZ0) * 0.5), Vector3(HX1 - HX0, 0.3, HZ0 - z0), mat)
	# North sliver beside the hatch.
	if z1 > HZ1:
		_box(Vector3((HX0 + HX1) * 0.5, y_center, (HZ1 + z1) * 0.5), Vector3(HX1 - HX0, 0.3, z1 - HZ1), mat)

# ============================================================ Deck B — quarters

func _deck_b() -> void:
	var wmat: Material = MatLib.concrete()
	var pmat: Material = MatLib.dirty_white_panel()   # crew-space dividers
	var fmat: Material = MatLib.concrete_floor()
	var y: float = B_Y
	# Full slab (stairs start ON this floor, so no shaft hole here).
	_box(Vector3(13, y - 0.15, 12), Vector3(30.5, 0.3, 12.5), fmat)
	# Room floors — quarters get worn lino, the wash room gets tile.
	_dbox(Vector3(13, y + 0.035, 8.5), Vector3(29.5, 0.03, 4.5), MatLib.lino_floor())
	_dbox(Vector3(12.5, y + 0.035, 12), Vector3(28.5, 0.03, 1.6), MatLib.lino_floor())
	_dbox(Vector3(2, y + 0.035, 15.5), Vector3(7.5, 0.03, 4.5), MatLib.kitchen_tile())
	_dbox(Vector3(10, y + 0.035, 15.5), Vector3(7.5, 0.03, 4.5), MatLib.rubber_floor())
	# Perimeter.
	_ext_win_wall_x(-2, 28, 6, y, wmat, true, 0.1)                       # south, balcony door near x 0
	_ext_win_wall_x(-2, 28, 18, y, wmat, true)                          # north
	_wall(Vector3(-2, y, 6), Vector3(-2, y, 18), WH, wmat)
	_wall(Vector3(28, y, 6), Vector3(28, y, 18), WH, wmat)
	# Corridor walls (z 11 and z 13) with a fitted hinged door per room (crew quarters).
	# Cabins are ~5m deep, so an inward swing clears the bunks and desks.
	var south_x := [-2.0, 3.0, 8.0, 13.0, 18.0, 23.0]
	for i in range(5):
		_fit_door(Vector3(south_x[i], y, 11), Vector3(south_x[i + 1], y, 11), WH, pmat, 0.5, true, true, "Cabin B-0%d" % (i + 1))
	_fit_door(Vector3(23, y, 11), Vector3(28, y, 11), WH, pmat, 0.5, true, true, "Linen Store")  # linen store door
	var north_x := [-2.0, 6.0, 14.0, 19.0, 23.0]
	for i in range(4):
		_fit_door(Vector3(north_x[i], y, 13), Vector3(north_x[i + 1], y, 13), WH, pmat, 0.5, true, false, "Cabin")
	# Cabin dividers south (z 6..11) and east room (linen store x 23..28, z 6..11).
	for dx in [3.0, 8.0, 13.0, 18.0, 23.0]:
		_wall(Vector3(dx, y, 6), Vector3(dx, y, 11), WH, pmat)
	# North dividers (z 13..18).
	for dx in [6.0, 14.0, 19.0]:
		_wall(Vector3(dx, y, 13), Vector3(dx, y, 18), WH, pmat)
	_wall(Vector3(23, y, 17.5), Vector3(23, y, 18), WH, wmat)   # sliver by shaft
	# Stairwell shaft + first flight.
	_shaft_walls(y, WH, "south")
	_well_ladder(y)
	_label("DECK B — QUARTERS", Vector3(25, y + 2.55, 12.8), 180, 40, Color(0.9, 0.85, 0.6))

	# ---- south cabins B-01..B-05 ----
	var cabin_x := [0.5, 5.5, 10.5, 15.5, 20.5]   # centers
	for i in range(5):
		var cx: float = cabin_x[i]
		_label("B-0%d" % (i + 1), Vector3(cx - 1.1, y + 2.35, 11.16), 0, 30)
		_light(Vector3(cx, y + 2.85, 8.5), 0.5, 6.0)
	# B-01 tidy: made bunk, squared desk, locker shut.
	_bunk(Vector3(-0.9, y, 7.4), false)
	_desk(Vector3(1.8, y, 6.9))
	_locker(Vector3(2.4, y, 10.2))
	# B-02 lived-in: messy bunk, boots, open locker.
	_bunk(Vector3(4.1, y, 7.4), true)
	_locker(Vector3(7.3, y, 6.9), true)
	for bx in [5.9, 6.25]:
		_dbox(Vector3(bx, y + 0.12, 9.6), Vector3(0.14, 0.24, 0.3), MatLib.flat(Color(0.2, 0.16, 0.12)))
	_takeable("water_ration", "Water Ration", Vector3(6.9, y + 0.81, 8.2))
	_desk(Vector3(6.9, y, 8.0))
	# B-03 the kelp shrine — teal glow, fronds, a note.
	_bunk(Vector3(9.1, y, 7.4), true)
	for i in range(5):
		var frond := _dbox(Vector3(11.4 + i * 0.22, y + 0.55, 10.3), Vector3(0.06, 0.7, 0.03),
			MatLib.flat(Color(0.25, 0.8, 0.6), true, 1.6))
		frond.rotation.z = deg_to_rad(-16 + i * 8)
	_dbox(Vector3(11.9, y + 0.1, 10.3), Vector3(1.4, 0.2, 0.6), MatLib.wood())
	_readable("shrine_note", "Kelp-Wrapped Note", Vector3(11.9, y + 0.21, 9.8), Vector3(0.28, 0.04, 0.34))
	_light(Vector3(11.5, y + 1.2, 10.0), 0.35, 4.0)
	# B-04: two lockers, duffel, pinup poster.
	_bunk(Vector3(14.1, y, 7.4), false)
	_locker(Vector3(17.3, y, 6.9))
	_locker(Vector3(17.3, y, 7.6))
	_dbox(Vector3(15.6, y + 0.2, 9.9), Vector3(0.5, 0.4, 0.9), MatLib.flat(Color(0.3, 0.35, 0.28)))
	_dbox(Vector3(13.16, y + 1.7, 8.5), Vector3(0.03, 0.8, 0.6), MatLib.flat(Color(0.35, 0.5, 0.42)))
	# B-05 ransacked: tipped locker, scattered papers, flipped mattress.
	var tipped := _box(Vector3(20.0, y + 0.3, 8.6), Vector3(0.55, 0.55, 1.8), MatLib.painted_steel())
	tipped.rotation.z = 0.06
	var mat_flip := _dbox(Vector3(21.4, y + 0.25, 7.6), Vector3(0.9, 0.14, 1.9), MatLib.flat(Color(0.66, 0.68, 0.7)))
	mat_flip.rotation.y = 0.5
	mat_flip.rotation.z = 0.18
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	for i in range(8):
		var paper := _dbox(Vector3(19.2 + rng.randf() * 3.2, y + 0.02, 6.8 + rng.randf() * 3.6),
			Vector3(0.22, 0.005, 0.3), MatLib.flat(Color(0.88, 0.88, 0.82)))
		paper.rotation.y = rng.randf() * TAU
	_readable("cabin_b05_scrawl", "Scrawl on the Wall", Vector3(22.84, y + 1.5, 8.8), Vector3(0.05, 0.5, 0.7))

	# ---- linen store (x 23..28, z 6..11) ----
	for sy in [0.6, 1.3, 2.0]:
		_dbox(Vector3(27.6, y + sy, 8.5), Vector3(0.5, 0.06, 4.2), MatLib.wood())
		for i in range(4):
			_dbox(Vector3(27.6, y + sy + 0.14, 6.9 + i * 1.0), Vector3(0.4, 0.22, 0.6),
				MatLib.flat(Color(0.85, 0.86, 0.84)))
	_light(Vector3(25.5, y + 2.85, 8.5), 0.45, 5.0)
	_label("LINEN", Vector3(26.6, y + 2.35, 11.16), 0, 28)

	# ---- north rooms ----
	# Bathroom (x -2..6): sink counter, mirrors, shower stalls.
	_box(Vector3(1.5, y + 0.45, 17.3), Vector3(4.5, 0.9, 0.85), MatLib.painted_steel())
	# Basins + mirrors on the solid pier between the north windows (x0 & x4) so the
	# glass over the counter stays clear.
	for i in range(3):
		_dcyl(Vector3(1.2 + i * 0.8, y + 0.95, 17.3), 0.18, 0.08, MatLib.flat(Color(0.9, 0.92, 0.92)))
		_dbox(Vector3(1.2 + i * 0.8, y + 1.7, 17.83), Vector3(0.6, 0.7, 0.04),
			MatLib.flat(Color(0.62, 0.72, 0.78)))
	for i in range(2):
		_wall(Vector3(-1.4 + i * 1.6, y, 13.6), Vector3(-1.4 + i * 1.6, y, 15.2), 2.2, MatLib.painted_steel())
	_dbox(Vector3(-0.6, y + 2.2, 14.4), Vector3(1.7, 0.06, 1.7), MatLib.painted_steel())
	_light(Vector3(2, y + 2.85, 15.5), 0.5, 6.0)
	_label("WASH ROOM", Vector3(2.0, y + 2.35, 12.84), 180, 28)
	# Lounge / movie room (x 6..14): screen sized to the solid pier between the
	# north-wall windows (centres x8 & x12) so the glass stays clear.
	_dbox(Vector3(10, y + 1.7, 17.85), Vector3(2.1, 1.5, 0.08), MatLib.flat(Color(0.9, 0.9, 0.86)))
	_dbox(Vector3(10, y + 1.7, 17.9), Vector3(2.3, 1.7, 0.05), MatLib.dark_metal())  # screen frame
	for rz in [14.2, 15.4]:
		_box(Vector3(10, y + 0.25, rz), Vector3(5.0, 0.5, 0.55), MatLib.flat(Color(0.32, 0.28, 0.26)))
	_dbox(Vector3(10, y + 1.1, 13.4), Vector3(0.5, 0.35, 0.6), MatLib.dark_metal())
	_dbox(Vector3(10, y + 0.5, 13.4), Vector3(0.3, 0.9, 0.3), MatLib.dark_metal())
	_light(Vector3(10, y + 2.85, 15.5), 0.45, 6.5)
	_label("CREW LOUNGE", Vector3(10, y + 2.35, 12.84), 180, 28)
	# Cabin B-06 (x 14..19) — the one that was slept in last.
	_bunk(Vector3(15.1, y, 16.6), true)
	_desk(Vector3(18.0, y, 17.1))
	_takeable("water_ration", "Water Ration", Vector3(18.0, y + 0.81, 17.0))
	_locker(Vector3(14.7, y, 13.8), true)
	_label("B-06", Vector3(17.6, y + 2.35, 12.84), 180, 30)
	_light(Vector3(16.5, y + 2.85, 15.5), 0.5, 6.0)
	# Muster locker (x 19..23): flares, grab bags, life ring on the wall.
	_crate(["flare", "flare", "life_ring"], "Emergency Locker", Vector3(21, y + 0.01, 16.8))
	for i in range(3):
		_dbox(Vector3(19.6 + i * 1.1, y + 1.5, 17.8), Vector3(0.5, 0.65, 0.3),
			MatLib.flat(Color(0.85, 0.45, 0.1)))
	_extinguisher(Vector3(22.6, y, 13.6))
	_label("MUSTER STORES", Vector3(21, y + 2.35, 12.84), 180, 28)
	_light(Vector3(21, y + 2.85, 15.5), 0.45, 5.5)

	# Corridor dressing: ceiling pipes, cable tray, extinguisher, clock, noticeboard.
	_pipe(Vector3(-1, y + 2.9, 12.35), Vector3(27, y + 2.9, 12.35), 0.08)
	_pipe(Vector3(-1, y + 2.68, 12.35), Vector3(27, y + 2.68, 12.35), 0.05)
	_valve(Vector3(6, y + 2.9, 12.15), true)
	_valve(Vector3(18, y + 2.9, 12.15), true)
	_dbox(Vector3(12, y + 2.95, 11.7), Vector3(22, 0.06, 0.3), MatLib.dark_metal())   # cable tray
	_extinguisher(Vector3(-1.6, y, 11.6))
	# Noticeboard shifted clear of the B-02 door reveal.
	_dbox(Vector3(3.7, y + 2.0, 11.16), Vector3(0.9, 0.65, 0.05), MatLib.flat(Color(0.72, 0.66, 0.5)))
	for i in range(4):
		var pin := _dbox(Vector3(3.4 + (i % 2) * 0.4, y + 2.05 - (i / 2) * 0.28, 11.13),
			Vector3(0.16, 0.2, 0.01), MatLib.flat(Color(0.9, 0.9, 0.8) if i % 2 == 0 else Color(0.85, 0.8, 0.55)))
		pin.rotation.z = 0.1 - (i % 3) * 0.09
	for lx in [2.0, 10.0, 18.0, 25.0]:
		_light(Vector3(lx, y + 2.9, 12.0), 0.5, 6.0)

	# South balcony + access ramp from the topside deck. The slab's north edge meets
	# the Deck B floor slab edge (z 5.75) exactly — no coplanar overlap.
	_box(Vector3(0, y - 0.15, 4.15), Vector3(12, 0.3, 3.2), MatLib.deck_plate())
	_rail_x(-6, 6, y, 2.65)
	_rail_z(2.65, 5.75, y, -6.0)
	# East balcony rail stops short of the stair landing — z 2.6..4.2 is the step-off.
	_rail_z(4.2, 5.75, y, 6.0)
	for sx in [-5.0, 5.0]:
		var strut := _box(Vector3(sx, DECK_Y + 1.7, 4.3), Vector3(0.28, 3.4, 0.28), MatLib.rust_steel())
		strut.rotation.z = 0.0
	_boarding_stairs(y)
	# Painted on the landing's own south fascia — 0.3m of real deck-plate edge behind
	# the glyphs, not the mid-air it used to occupy over the old run.
	_label("QUARTERS ↑", Vector3(7.3, y - 0.15, 2.59), 180, 26, Color(0.9, 0.85, 0.6))

## Companionway from the topside deck up to the Deck B balcony.
##
## It used to run from (7.5, 18) west to (-3.5, 21.6) at z 3.0 — straight in under the
## balcony slab, which spans x -6..6 at y 21.3..21.6. There was no opening in that
## slab, so the climb ended with a 1.8m-tall player driving his head into the
## diamond-plate soffit at about x 3.0, treads meeting steel with nowhere to go.
##
## Cutting a stairwell out of the balcony was not the answer: the run passes under it
## for its whole length, so clearing 2m of headroom would have meant deleting nearly
## all of a 3.2m-deep balcony. Instead the flight is re-routed EAST to top out at the
## balcony's edge on its own landing, in open air the whole way up. The run is also
## stretched (7.2m for 3.6m of rise, ~27°) so the top tread meets the landing flush.
func _boarding_stairs(y: float) -> void:
	var tread: Material = MatLib.deck_plate()
	# Landing at the balcony's east edge, top face flush with the balcony deck at y.
	_box(Vector3(7.3, y - 0.15, 3.4), Vector3(2.6, 0.3, 1.6), tread)
	_rail_x(6.0, 8.6, y, 2.6)
	_rail_x(6.0, 8.6, y, 4.2)
	# Landing legs down to the topside deck.
	for lp in [Vector3(6.2, 0, 2.7), Vector3(6.2, 0, 4.1), Vector3(8.4, 0, 2.7), Vector3(8.4, 0, 4.1)]:
		_box(Vector3(lp.x, (DECK_Y + y - 0.3) * 0.5, lp.z),
			Vector3(0.16, y - 0.3 - DECK_Y, 0.16), MatLib.rust_steel())
	# The flight itself: foot on the open deck at x 15.8, topping out on the landing.
	_stair_run(Vector3(15.8, DECK_Y, 3.4), Vector3(8.6, y, 3.4), 1.6, true, true)
	# Sign plate bolted to the flight's south stringer, where there is real steel
	# behind the lettering (the old placard hung on the stringer of the old route).
	_dbox(Vector3(12.4, DECK_Y + 1.95, 2.54), Vector3(2.2, 0.34, 0.05), MatLib.painted_steel())
	for sx in [11.45, 13.35]:
		for sy in [DECK_Y + 1.83, DECK_Y + 2.07]:
			_dbox(Vector3(sx, sy, 2.51), Vector3(0.04, 0.04, 0.03), MatLib.galvanized())
	_label("B-DECK QUARTERS ↑", Vector3(12.4, DECK_Y + 1.95, 2.51), 180, 26, Color(0.9, 0.85, 0.6))

# ============================================================ Deck C — control

func _deck_c() -> void:
	var wmat: Material = MatLib.concrete()
	var y: float = C_Y
	# Slab: covers B footprint (x -2..28, z 6..18) — the strip west of x4 is the
	# open-air terrace/balcony; shaft gets a hole.
	_slab_with_shaft_hole(y - 0.15, -2, 28, 6, 18, MatLib.concrete_floor())
	# Perimeter (interior starts at x 4).
	_ext_win_wall_x(4, 28, 6, y, wmat, true)                       # south
	_ext_win_wall_x(4, 28, 18, y, wmat, true)                      # north
	_wall(Vector3(4, y, 6), Vector3(4, y, 18), WH, wmat, 0.35)      # west door -> terrace at z ~10
	_wall(Vector3(28, y, 6), Vector3(28, y, 18), WH, wmat)
	# Corridor z 12..14.
	var cs := [4.0, 12.0, 18.0, 23.0]
	for i in range(3):
		_wall(Vector3(cs[i], y, 12), Vector3(cs[i + 1], y, 12), WH, wmat, 0.5)
	_wall(Vector3(23, y, 12), Vector3(28, y, 12), WH, wmat, 0.5)     # east store door
	_wall(Vector3(4, y, 14), Vector3(13, y, 14), WH, wmat, 0.5)      # comms door
	_wall(Vector3(13, y, 14), Vector3(23, y, 14), WH, wmat, 0.5)     # mud log door
	for dx in [12.0, 18.0, 23.0]:
		_wall(Vector3(dx, y, 6), Vector3(dx, y, 12), WH, wmat)
	_wall(Vector3(13, y, 14), Vector3(13, y, 18), WH, wmat)
	_wall(Vector3(23, y, 17.5), Vector3(23, y, 18), WH, wmat)
	# Shaft south wall pulled back to z 14 so the corridor keeps full width
	# past the ladder well (it pinched to 0.75m — unpassable).
	_shaft_walls(y, WH, "south", 0.1, 14.0)
	_well_ladder(y)
	_label("DECK C — CONTROL", Vector3(25, y + 2.55, 13.86), 180, 40, Color(0.9, 0.85, 0.6))

	# Room floors — control level: rubber underfoot, medical white in the bay.
	_dbox(Vector3(8, y + 0.035, 9), Vector3(7.5, 0.03, 5.5), MatLib.rubber_floor())
	_dbox(Vector3(20.5, y + 0.035, 9), Vector3(4.5, 0.03, 5.5), MatLib.medical_white())
	_dbox(Vector3(8.5, y + 0.035, 16), Vector3(8.5, 0.03, 3.5), MatLib.rubber_floor())
	# Control room (x 4..12, z 6..12): console desks, dead monitors, switch wall.
	# The one window in this span is centred at x=8, so the middle console keeps its
	# monitor DOWN on the desk (below the sill) — only the pier desks get a raised
	# monitor on the glass-free wall.
	for i in range(3):
		var dx: float = 5.8 + i * 2.2
		_desk(Vector3(dx, y, 7.4), PI)
		if i == 1:
			_dbox(Vector3(dx, y + 0.86, 7.5), Vector3(0.5, 0.06, 0.28), MatLib.flat(Color(0.1, 0.1, 0.12)))  # keyboard, below sill
		else:
			_monitor(Vector3(dx, y + 1.15, 6.9), 0.0)
	# Switch wall shifted south — it used to span across the terrace doorway gap
	# (a prop with no wall behind it, visually blocking the door).
	_dbox(Vector3(4.16, y + 1.7, 7.9), Vector3(0.06, 1.6, 2.4), MatLib.dark_metal())
	for i in range(12):
		_dbox(Vector3(4.22, y + 1.2 + (i % 4) * 0.35, 7.1 + floori(i / 4.0) * 0.9),
			Vector3(0.05, 0.12, 0.2), MatLib.flat(Color(0.7, 0.2, 0.15) if i % 3 == 0 else Color(0.6, 0.62, 0.6)))
	_label("HIGH VOLTAGE", Vector3(4.24, y + 2.6, 7.9), 90, 26, Color(0.95, 0.75, 0.2))
	_label("CONTROL", Vector3(9.5, y + 2.35, 12.16), 0, 28)
	_readable("toolpusher_log", "Toolpusher's Log", Vector3(8.0, y + 0.85, 7.4), Vector3(0.3, 0.05, 0.4))
	_light(Vector3(8, y + 2.85, 9), 0.5, 7.0)
	# Office (x 12..18): desk, chair, filing cabinets, wall map.
	_desk(Vector3(14.5, y, 7.5), PI * 0.5)
	# The company man's sealed directive on his desk — the reveal ceiling: Platform 7's
	# "yield" was the product, and the line crews were the feed.
	_readable("company_man_memo", "Sealed Directive", Vector3(14.5, y + 0.85, 7.5), Vector3(0.3, 0.05, 0.4))
	for i in range(2):
		_box(Vector3(17.3, y + 0.65, 7.0 + i * 0.9), Vector3(0.5, 1.3, 0.6), MatLib.painted_steel())
	_dbox(Vector3(14.0, y + 1.8, 6.2), Vector3(1.6, 1.0, 0.04), MatLib.flat(Color(0.55, 0.62, 0.58)))  # wall map on the pier, clear of window x16
	_label("RIG OFFICE", Vector3(15.5, y + 2.35, 12.16), 0, 28)
	_light(Vector3(15, y + 2.85, 9), 0.5, 6.0)
	# Med bay (x 18..23): exam bench, cabinets, red cross, water ration.
	_box(Vector3(20.5, y + 0.45, 8.0), Vector3(2.0, 0.9, 0.9), MatLib.flat(Color(0.82, 0.85, 0.84)))
	_dbox(Vector3(22.8, y + 1.5, 7.0), Vector3(0.35, 1.0, 0.8), MatLib.flat(Color(0.9, 0.92, 0.9)))
	_dbox(Vector3(22.82, y + 1.5, 7.0), Vector3(0.03, 0.28, 0.09), MatLib.flat(Color(0.8, 0.15, 0.1)))
	_dbox(Vector3(22.82, y + 1.5, 7.0), Vector3(0.03, 0.09, 0.28), MatLib.flat(Color(0.8, 0.15, 0.1)))
	_takeable("water_ration", "Water Ration", Vector3(19.2, y + 0.91, 8.0))
	_readable("medbay_note", "Sick-Bay Ledger", Vector3(21.4, y + 0.96, 8.0), Vector3(0.3, 0.05, 0.4))
	_label("MED BAY", Vector3(20.5, y + 2.35, 12.16), 0, 28)
	_light(Vector3(20.5, y + 2.85, 9), 0.55, 6.0)
	# East store (x 23..28, z 6..12): shelving + pantry crate.
	for sy in [0.6, 1.4]:
		_dbox(Vector3(27.5, y + sy, 9.0), Vector3(0.5, 0.06, 4.5), MatLib.wood())
	_crate(["sealed_tin", "canned_food"], "Dry Stores Crate", Vector3(25.5, y + 0.01, 7.5))
	_label("STORES", Vector3(25.5, y + 2.35, 12.16), 0, 28)
	_light(Vector3(25.5, y + 2.85, 9), 0.4, 5.0)
	# Comms room (x 4..13, z 14..18): radio desk, rack, headset, the log.
	_desk(Vector3(6.0, y, 16.8), PI)
	_monitor(Vector3(6.0, y + 1.15, 17.3), PI)
	_dbox(Vector3(9.5, y + 1.0, 17.5), Vector3(0.8, 2.0, 0.6), MatLib.dark_metal())
	for i in range(5):
		_dbox(Vector3(9.5, y + 0.4 + i * 0.36, 17.18), Vector3(0.7, 0.08, 0.03),
			MatLib.flat(Color(0.2, 0.9, 0.85) if i == 2 else Color(0.4, 0.42, 0.44)))
	_dcyl(Vector3(6.7, y + 0.88, 16.6), 0.1, 0.05, MatLib.dark_metal())
	_readable("comms_log", "Last Transmission Log", Vector3(5.2, y + 0.85, 16.8), Vector3(0.3, 0.05, 0.4))
	_label("RADIO ROOM", Vector3(8.5, y + 2.35, 14.16), 0, 28)
	_light(Vector3(8, y + 2.85, 16), 0.5, 6.0)
	# Mud logging (x 13..23, z 14..18): instrument racks + paper strips.
	for i in range(3):
		_box(Vector3(14.5 + i * 3.0, y + 0.9, 17.4), Vector3(1.2, 1.8, 0.7), MatLib.dark_metal())
		_dbox(Vector3(14.5 + i * 3.0, y + 1.35, 16.98), Vector3(0.8, 0.5, 0.03),
			MatLib.flat(Color(0.85, 0.86, 0.8)))
	for i in range(4):
		var strip := _dbox(Vector3(14.0 + i * 1.6, y + 1.1, 15.2), Vector3(0.3, 1.4, 0.01),
			MatLib.flat(Color(0.92, 0.92, 0.86)))
		strip.rotation.x = 0.15
	_label("MUD LOG", Vector3(18, y + 2.35, 14.16), 0, 28)
	_light(Vector3(18, y + 2.85, 16), 0.45, 6.5)
	# Corridor dressing.
	_pipe(Vector3(4.5, y + 2.9, 13.0), Vector3(27, y + 2.9, 13.0), 0.07)
	_dbox(Vector3(15, y + 2.95, 13.5), Vector3(22, 0.06, 0.3), MatLib.dark_metal())
	_extinguisher(Vector3(4.4, y, 12.6))
	for lx in [7.0, 15.0, 21.0]:
		_light(Vector3(lx, y + 2.9, 13.0), 0.5, 6.0)
	# West terrace rails — gap at z 6..8.7 where the external stair lands.
	_rail_z(8.7, 18, y, -1.9)
	_rail_x(-2, 4, y, 6.1)
	_rail_x(-2, 4, y, 17.9)

# ============================================================ Deck D — works

func _deck_d() -> void:
	var wmat: Material = MatLib.concrete()
	var y: float = D_Y
	# Slab covers the C footprint; strips west of x8 / south of z8 are open catwalk.
	_slab_with_shaft_hole(y - 0.15, 4, 28, 6, 18, MatLib.concrete_floor())
	# Perimeter (interior x 8..28, z 8..18). South door onto the catwalk strip.
	_ext_win_wall_x(8, 28, 8, y, wmat, true, 11.0)                  # south, catwalk door at x~11
	_ext_win_wall_x(8, 28, 18, y, wmat, true)                      # north
	_wall(Vector3(8, y, 8), Vector3(8, y, 18), WH, wmat)
	_wall(Vector3(28, y, 8), Vector3(28, y, 18), WH, wmat, 0.3)     # east door -> helipad platform
	# Two room bands around corridor z 13..15.
	_wall(Vector3(8, y, 13), Vector3(15.5, y, 13), WH, wmat, 0.5)    # gym door
	_wall(Vector3(15.5, y, 13), Vector3(23, y, 13), WH, wmat, 0.5)   # laundry door
	_wall(Vector3(8, y, 15), Vector3(15.5, y, 15), WH, wmat, 0.5)    # storage door
	_wall(Vector3(15.5, y, 15), Vector3(23, y, 15), WH, wmat, 0.5)   # workshop door
	_wall(Vector3(15.5, y, 8), Vector3(15.5, y, 13), WH, wmat)
	_wall(Vector3(15.5, y, 15), Vector3(15.5, y, 18), WH, wmat)
	_wall(Vector3(23, y, 8), Vector3(23, y, 13), WH, wmat, 0.5)      # laundry -> east vestibule
	_shaft_walls(y, WH, "west", 0.22)
	_well_ladder(y)
	# Both of these used to hang in mid-air in the east vestibule and at the open east
	# end of the corridor. Put on real wall: the platform arrow beside the x=23 door
	# (clear of its reveal at z 10.5), the deck name on the corridor's south wall.
	_label("PLATFORM →", Vector3(23.16, y + 1.9, 11.8), 90, 24, Color(0.9, 0.85, 0.6))
	_label("DECK D — WORKS", Vector3(9.5, y + 2.55, 13.16), 0, 26, Color(0.9, 0.85, 0.6))

	# Room floors — works level: rubber in the gym, tile in the laundry.
	_dbox(Vector3(11.5, y + 0.035, 10.5), Vector3(7.0, 0.03, 4.5), MatLib.rubber_floor())
	_dbox(Vector3(19, y + 0.035, 10.5), Vector3(7.0, 0.03, 4.5), MatLib.kitchen_tile())
	# Gym (x 8..15.5, z 8..13): weight bench, bar + plates, mat.
	_box(Vector3(10.5, y + 0.3, 10.0), Vector3(0.6, 0.6, 1.6), MatLib.flat(Color(0.3, 0.3, 0.34)))
	var bar := _dcyl(Vector3(10.5, y + 1.0, 9.4), 0.03, 2.0, MatLib.dark_metal())
	bar.rotation.z = PI / 2
	for side in [-0.85, 0.85]:
		_dcyl(Vector3(10.5 + side, y + 1.0, 9.4), 0.22, 0.06, MatLib.dark_metal()).rotation.z = PI / 2
	_dbox(Vector3(13, y + 0.02, 10.5), Vector3(1.8, 0.03, 1.2), MatLib.flat(Color(0.25, 0.35, 0.45)))
	_label("GYM", Vector3(11.5, y + 2.35, 13.16), 0, 28)
	_light(Vector3(11.5, y + 2.85, 10.5), 0.45, 6.5)
	# Laundry (x 15.5..23, z 8..13): washers, hanging line with sheets.
	for i in range(3):
		_box(Vector3(17.0 + i * 1.5, y + 0.5, 8.8), Vector3(1.1, 1.0, 0.9), MatLib.painted_steel())
		_dcyl(Vector3(17.0 + i * 1.5, y + 0.55, 9.28), 0.28, 0.04, MatLib.flat(Color(0.15, 0.17, 0.2))).rotation.x = PI / 2
	var line := _dcyl(Vector3(19, y + 2.1, 11.8), 0.015, 6.0, MatLib.dark_metal())
	line.rotation.z = PI / 2
	for i in range(3):
		_dbox(Vector3(17.2 + i * 1.7, y + 1.55, 11.8), Vector3(1.0, 1.1, 0.02),
			MatLib.flat(Color(0.85, 0.86, 0.84)))
	_label("LAUNDRY", Vector3(19, y + 2.35, 13.16), 0, 28)
	_light(Vector3(19, y + 2.85, 10.5), 0.45, 6.0)
	# Storage (x 8..15.5, z 15..18): crate stacks and the hidden stash nook.
	for i in range(4):
		_box(Vector3(9.2 + (i % 2) * 1.3, y + 0.4 + floori(i / 2.0) * 0.8, 17.0), Vector3(1.1, 0.8, 0.9), MatLib.wood())
	_crate(["driftwood", "scrap_metal"], "Parts Crate", Vector3(13.5, y + 0.01, 17.0))
	# The nook: crouch behind the stack for the good stuff.
	_crate(["sealed_tin", "water_ration", "flare"], "Stashed Footlocker", Vector3(8.9, y + 0.01, 15.6))
	_label("STORES", Vector3(11.5, y + 2.35, 14.84), 180, 28)
	_light(Vector3(11.5, y + 2.85, 16.5), 0.4, 5.5)
	# Workshop (x 15.5..23, z 15..18): SECOND CRAFT BENCH + pegboard.
	var bench := CraftBench.new()
	add_child(bench)
	bench.position = Vector3(19, y, 17.0)
	bench.build_box_visual(Vector3(1.6, 0.9, 0.7), Color(0.5, 0.42, 0.3), false, true)
	_dbox(Vector3(19, y + 0.93, 17.0), Vector3(1.7, 0.06, 0.8), MatLib.wood())
	# Pegboard on the pier between the x16 and x20 windows. Window openings are
	# WIN_W wide on the WIN_GRID, so that pier is x 16.8..19.2 and the board's own
	# face is x 16.85..19.15; its back sits flush on the wall's inner skin (z 17.875).
	const PEG_X: float = 18.0
	const PEG_W: float = 2.3
	const PEG_Z: float = 18.0 - WT * 0.5 - 0.025      # board centre, back flush to the wall
	_dbox(Vector3(PEG_X, y + 1.9, PEG_Z), Vector3(PEG_W, 1.2, 0.05),
		MatLib.flat(Color(0.75, 0.72, 0.6)))
	var tool_colors := [Color(0.7, 0.3, 0.2), Color(0.3, 0.4, 0.6), Color(0.5, 0.5, 0.5), Color(0.7, 0.6, 0.2)]
	for i in range(4):
		# Spread across the board's OWN face and hung on its front skin. These used to
		# march east from x 18.1 in 0.6m steps, which put the last two at x 19.3 and
		# 19.9 — past the board, past the pier, hanging in the x20 window opening with
		# open sea behind them.
		_dbox(Vector3(PEG_X + (float(i) - 1.5) * 0.55,
				y + 1.9 + (0.2 if i % 2 == 0 else -0.15), PEG_Z - 0.05),
			Vector3(0.1, 0.38, 0.05), MatLib.flat(tool_colors[i]))
	_takeable("prybar", "Spare Prybar", Vector3(21.8, y + 0.01, 16.2))
	_label("WORKSHOP — RIGGING BENCH", Vector3(19, y + 2.35, 14.84), 180, 26, Color(0.9, 0.85, 0.6))
	_light(Vector3(19, y + 2.85, 16.5), 0.5, 6.0)
	# Corridor dressing.
	_pipe(Vector3(8.5, y + 2.9, 14.0), Vector3(23, y + 2.9, 14.0), 0.07)
	_valve(Vector3(14, y + 2.9, 13.8), true)
	_extinguisher(Vector3(8.4, y, 13.6))
	for lx in [10.0, 16.0, 21.5]:
		_light(Vector3(lx, y + 2.9, 14.0), 0.5, 6.0)
	# Open catwalk strips (x 4..8 and z 6..8) — rails on the exposed edges.
	_rail_z(6, 18, y, 4.1)
	_rail_x(4, 28, y, 6.1)
	_label("NO NAKED FLAME", Vector3(9, y + 1.9, 7.84), 180, 26, Color(0.95, 0.75, 0.2))

	# East helipad-style platform (x 28..36, z 8..16) with angled struts.
	_box(Vector3(32, y - 0.15, 12), Vector3(8, 0.3, 8), MatLib.deck_plate())
	_rail_x(28, 36, y, 8.1)
	_rail_x(28, 36, y, 15.9)
	_rail_z(8.1, 15.9, y, 35.9)
	_dbox(Vector3(32, y + 0.02, 12), Vector3(4.5, 0.02, 4.5), MatLib.flat(Color(0.75, 0.7, 0.2)))
	# Painted "H" on the pad (flat boxes, not a floating glyph).
	for hx in [-0.9, 0.9]:
		_dbox(Vector3(32 + hx, y + 0.035, 12), Vector3(0.4, 0.01, 2.6), MatLib.flat(Color(0.15, 0.15, 0.15)))
	_dbox(Vector3(32, y + 0.035, 12), Vector3(1.4, 0.01, 0.4), MatLib.flat(Color(0.15, 0.15, 0.15)))
	for sz in [9.5, 14.5]:
		var strut := _box(Vector3(30.5, y - 2.2, sz), Vector3(0.3, 5.4, 0.3), MatLib.rust_steel())
		strut.rotation.z = 0.72

# ============================================================ roof + mast

func _roof() -> void:
	var y: float = ROOF_Y
	_slab_with_shaft_hole(y - 0.15, 8, 28, 8, 18, MatLib.deck_plate())
	# Bulkhead hut over the shaft with the exit door.
	_shaft_walls(y, 2.6, "west")
	_box(Vector3((SX0 + SX1) * 0.5, y + 2.72, (SZ0 + SZ1) * 0.5), Vector3(SX1 - SX0 + 0.5, 0.25, SZ1 - SZ0 + 0.5), MatLib.concrete())
	_label("ROOF — MAST DECK", Vector3(SX0 - 0.16, y + 2.3, 15.2), -90, 30, Color(0.9, 0.85, 0.6))
	# Perimeter rails.
	_rail_x(8, 28, y, 8.1)
	_rail_x(8, 28, y, 17.9)
	_rail_z(8.1, 17.9, y, 8.1)
	_rail_z(8.1, 13.0, y, 27.9)
	# Generator set: hull, exhaust, fuel drum, cable run to a junction box.
	_box(Vector3(11, y + 0.6, 15.5), Vector3(2.2, 1.2, 1.3), MatLib.dark_metal())
	_dcyl(Vector3(10.4, y + 1.7, 15.2), 0.09, 1.0, MatLib.rusty_metal())
	_cyl(Vector3(13.0, y + 0.5, 15.8), 0.42, 1.0, MatLib.rust_steel())
	_pipe(Vector3(12.1, y + 0.5, 15.5), Vector3(12.8, y + 0.5, 15.7), 0.05)
	_dbox(Vector3(11, y + 0.15, 13.8), Vector3(0.1, 0.1, 2.2), MatLib.dark_metal())
	_readable("generator_tag", "Generator Fault Tag", Vector3(12.15, y + 0.9, 15.5), Vector3(0.22, 0.28, 0.04))
	# Vent hoods.
	for vp in [Vector3(9.5, y, 10.0), Vector3(14.5, y, 9.6), Vector3(20.5, y, 10.2)]:
		_box(vp + Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.9), MatLib.painted_steel())
		_dbox(vp + Vector3(0, 1.12, 0.2), Vector3(1.0, 0.25, 1.3), MatLib.painted_steel())
	# Satellite dish on a pedestal.
	_box(Vector3(25.5, y + 0.5, 10.5), Vector3(0.4, 1.0, 0.4), MatLib.painted_steel())
	var dish := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 1.1
	dm.height = 0.6
	dm.is_hemisphere = true
	dm.material = MatLib.painted_steel()
	dish.mesh = dm
	add_child(dish)
	dish.position = Vector3(25.5, y + 1.3, 10.5)
	dish.rotation.x = deg_to_rad(-55)
	# Whip antennae.
	for wp in [Vector3(9.0, y, 17.2), Vector3(27.2, y, 17.2)]:
		_dcyl(wp + Vector3(0, 1.6, 0), 0.025, 3.2, MatLib.dark_metal())

func _mast() -> void:
	## The rig's landmark: a tapering lattice comms tower on the roof, ~19m tall,
	## guyed to the deck corners, red beacon pulsing at the crown.
	var mat: Material = MatLib.rust_steel()
	var base := Vector3(14.0, ROOF_Y, 13.0)
	var h: float = 19.0
	var half0: float = 1.5
	var half1: float = 0.45
	var segs: int = 5
	for i in range(segs):
		var y0: float = base.y + h * i / segs
		var y1: float = base.y + h * (i + 1) / segs
		var r0: float = lerpf(half0, half1, float(i) / segs)
		var r1: float = lerpf(half0, half1, float(i + 1) / segs)
		# Four legs, tilted inward per segment.
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				var a := Vector3(base.x + sx * r0, y0, base.z + sz * r0)
				var b := Vector3(base.x + sx * r1, y1, base.z + sz * r1)
				var leg := CSGBox3D.new()
				leg.size = Vector3(0.16, a.distance_to(b) + 0.2, 0.16)
				leg.material = mat
				leg.use_collision = i == 0
				add_child(leg)
				_align_y(leg, a, b)
		# Horizontal ring braces.
		_dbox(Vector3(base.x, y1, base.z - r1), Vector3(r1 * 2, 0.1, 0.1), mat)
		_dbox(Vector3(base.x, y1, base.z + r1), Vector3(r1 * 2, 0.1, 0.1), mat)
		_dbox(Vector3(base.x - r1, y1, base.z), Vector3(0.1, 0.1, r1 * 2), mat)
		_dbox(Vector3(base.x + r1, y1, base.z), Vector3(0.1, 0.1, r1 * 2), mat)
		# Diagonal cross braces (cheap X per face, decoration only).
		var db := _dbox(Vector3(base.x, (y0 + y1) * 0.5, base.z - (r0 + r1) * 0.5),
			Vector3(r0 + r1, 0.07, 0.07), mat)
		db.rotation.z = 0.6
		var db2 := _dbox(Vector3(base.x, (y0 + y1) * 0.5, base.z + (r0 + r1) * 0.5),
			Vector3(r0 + r1, 0.07, 0.07), mat)
		db2.rotation.z = -0.6
	# Dishes bolted at height.
	var dish_mi := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.55
	mm.height = 0.3
	mm.is_hemisphere = true
	mm.material = MatLib.painted_steel()
	dish_mi.mesh = mm
	add_child(dish_mi)
	dish_mi.position = base + Vector3(1.0, 9.0, 0)
	dish_mi.rotation.z = deg_to_rad(75)
	# Guy wires to the roof corners.
	var top := base + Vector3(0, h, 0)
	for anchor in [Vector3(9, ROOF_Y, 9), Vector3(27, ROOF_Y, 9), Vector3(9, ROOF_Y, 17.5)]:
		var wire := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.02
		cm.height = top.distance_to(anchor)
		cm.material = MatLib.dark_metal()
		wire.mesh = cm
		add_child(wire)
		_align_y(wire, top, anchor)
	add_child(Beacon.new(top + Vector3(0, 0.4, 0)))

## Position node at the midpoint of a->b and align its local +Y axis along the span.
func _align_y(node: Node3D, a: Vector3, b: Vector3) -> void:
	node.global_position = (a + b) * 0.5
	var d: Vector3 = (b - a).normalized()
	var up := Vector3(0, 0, 1) if absf(d.y) > 0.99 else Vector3.UP
	node.look_at(node.global_position + d, up)
	node.rotate_object_local(Vector3.RIGHT, -PI / 2)

## Slow-pulsing red aviation beacon at the mast crown.
class Beacon extends Node3D:
	var _t: float = 0.0
	var _light: OmniLight3D
	var _mat: StandardMaterial3D
	var _pos: Vector3

	func _init(pos: Vector3) -> void:
		_pos = pos

	func _ready() -> void:
		position = _pos
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.9, 0.1, 0.08)
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.12, 0.08)
		_mat.emission_energy_multiplier = 2.0
		sm.material = _mat
		mi.mesh = sm
		add_child(mi)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.15, 0.1)
		_light.omni_range = 14.0
		add_child(_light)

	func _process(delta: float) -> void:
		_t += delta
		var pulse: float = maxf(0.0, sin(_t * 1.6))
		pulse = pulse * pulse
		_mat.emission_energy_multiplier = 0.4 + pulse * 3.2
		_light.light_energy = pulse * 2.4

# ============================================================ exterior dressing

func _exterior_dressing() -> void:
	# South/north windows are now real framed openings in the perimeter walls
	# (see _ext_win_wall_x in each deck) — they stack into vertical columns and
	# glow from interior spill. Deck B's west gable wall keeps portholes.
	_porthole(Vector3(-2.13, B_Y + 1.7, 9.0), false)
	_porthole(Vector3(-2.13, B_Y + 1.7, 15.0), false)
	# Big faded rig name on the Deck C south face.
	# On the solid SILL band below the Deck C windows (y C_Y+0.5, inside floor..floor+0.95),
	# smaller so the glyphs clear the opening bottom — was centred over the glass.
	_label("S A L T L I N E - 1", Vector3(16, C_Y + 0.5, 5.8), 180, 84, Color(0.75, 0.62, 0.4, 0.85))
	# External pipe drops tying the stack into the old rig below.
	_pipe(Vector3(-1.5, DECK_Y + 0.3, 6.6), Vector3(-1.5, B_Y + 2.8, 6.6), 0.12)
	_pipe(Vector3(28.4, DECK_Y + 0.3, 10.0), Vector3(28.4, D_Y + 2.0, 10.0), 0.1)
	_pipe(Vector3(28.4, B_Y + 0.6, 10.0), Vector3(28.4, B_Y + 0.6, 16.0), 0.08)
	_valve(Vector3(28.4, B_Y + 0.6, 12.0), false)
	# Exterior cross-brace framing on the south face — metal skeleton look.
	for spec in [[B_Y, -2.0], [C_Y, 4.0], [D_Y, 8.0]]:
		var fy: float = spec[0]
		var fx0: float = spec[1]
		# On the solid LINTEL band above the glass (y fy+2.8, band floor+2.4..floor+3.2),
		# barely tilted so the long bar doesn't dip into the window tops — was crossing them.
		var brace := _dbox(Vector3((fx0 + 28.0) * 0.5, fy + 2.8, 5.75), Vector3(28.0 - fx0, 0.14, 0.1), MatLib.rust_steel())
		brace.rotation.z = 0.015
	# Corner trim columns.
	for cx in [-2.0, 28.0]:
		_dbox(Vector3(cx, (B_Y + ROOF_Y) * 0.5, 6.0), Vector3(0.35, ROOF_Y - B_Y, 0.35), MatLib.rust_steel())
		_dbox(Vector3(cx, (B_Y + ROOF_Y) * 0.5 - 1.75, 18.0), Vector3(0.35, ROOF_Y - B_Y - 3.5, 0.35), MatLib.rust_steel())

## Wayfinding for the existing topside rooms (Deck A) + the crafting loop.
func _deck_a_signage() -> void:
	_label("GALLEY", Vector3(6.6, DECK_Y + 2.4, 7.84), 180, 34)
	_label("REC ROOM", Vector3(17.84, DECK_Y + 2.4, 10.5), -90, 30)
	_label("MUSTER STATION →", Vector3(9, DECK_Y + 1.9, 7.84), 180, 28, Color(0.95, 0.75, 0.2))
	_label("RIGGING BENCH — WET DECK ↓", Vector3(21.9, DECK_Y + 2.5, -0.9), 90, 24, Color(0.9, 0.85, 0.6))
	# The B-deck placard used to be bolted to the boarding stair's stringer here, at
	# x 2.06. That stair has been re-routed east (it climbed into the balcony soffit
	# on this line — see _boarding_stairs), so the plate and its lettering moved with
	# it onto the new stringer at x 12.4. Nothing is left standing here on purpose:
	# a sign board with no stair behind it is the floating-label bug in another form.

# ============================================================ density pass

## Doubles the lived-in clutter, room by room. Everything wall-flush or
## floor-seated, kept clear of every doorway reveal.
func _density_pass() -> void:
	var y: float = B_Y
	# --- Cabins: mugs, under-bunk boxes, wall hooks with slickers, bedside rugs.
	var cabin_x := [0.5, 5.5, 10.5, 15.5, 20.5]
	for i in range(5):
		var cx: float = cabin_x[i]
		_dcyl(Vector3(cx + 1.3, y + 0.86, 6.95), 0.05, 0.09, MatLib.flat(Color(0.9, 0.9, 0.86)))
		_dbox(Vector3(cx - 0.9, y + 0.14, 8.3), Vector3(0.55, 0.28, 0.4), MatLib.flat(Color(0.35, 0.3, 0.24)))
		_dbox(Vector3(cx - 1.3, y + 0.02, 7.4), Vector3(0.7, 0.015, 1.1), MatLib.flat(Color(0.42, 0.3, 0.24)))
		var hook_col := Color(0.85, 0.55, 0.15) if i % 2 == 0 else Color(0.3, 0.4, 0.5)
		# Coat-hook board snapped to the solid pier by each cabin door — cabins sit on
		# a 5m pitch, windows on 4m, so a fixed offset would land two boards on glass.
		var hook_x: float = [-1.6, 2.8, 9.4, 13.4, 18.4][i]
		_dbox(Vector3(hook_x, y + 1.5, 6.2), Vector3(0.4, 0.75, 0.1), MatLib.flat(hook_col))
	# Corridor scuff strip + a second pipe + junction boxes.
	_dbox(Vector3(12.5, y + 0.045, 12), Vector3(28, 0.01, 0.5), MatLib.flat(Color(0.4, 0.4, 0.4)))
	_pipe(Vector3(-1, y + 2.5, 12.35), Vector3(27, y + 2.5, 12.35), 0.04)
	for jx in [3.0, 13.0, 21.0]:
		_dbox(Vector3(jx, y + 2.3, 11.16), Vector3(0.3, 0.4, 0.12), MatLib.dark_metal())
	# Lounge: card table with stools and scattered hands.
	_table(Vector3(8.2, y, 14.6), Vector2(1.1, 1.1))
	for a in range(4):
		_dbox(Vector3(8.2 + cos(a * PI / 2) * 0.9, y + 0.22, 14.6 + sin(a * PI / 2) * 0.9),
			Vector3(0.38, 0.44, 0.38), MatLib.flat(Color(0.3, 0.32, 0.35)))
	var crng := RandomNumberGenerator.new()
	crng.seed = 909
	for c in range(6):
		var card := _dbox(Vector3(8.2 + crng.randf_range(-0.4, 0.4), y + 0.52, 14.6 + crng.randf_range(-0.4, 0.4)),
			Vector3(0.11, 0.004, 0.16), MatLib.flat(Color(0.92, 0.92, 0.88)))
		card.rotation.y = crng.randf() * TAU
	# Wash room: towel dispensers on the pier east of window x4, a bucket, duckboards.
	for tx in [5.1, 5.6]:
		_dbox(Vector3(tx, y + 1.4, 17.83), Vector3(0.3, 0.5, 0.05), MatLib.flat(Color(0.8, 0.82, 0.8)))
	_dcyl(Vector3(-1.2, y + 0.15, 16.6), 0.16, 0.3, MatLib.galvanized())
	_dbox(Vector3(0.5, y + 0.02, 14.4), Vector3(1.6, 0.03, 0.8), MatLib.wood())

	# --- Deck C additions.
	y = C_Y
	# Control: wall charts, binder shelf, coffee ring desk clutter.
	# Wall charts on the solid piers either side of the window at x8 — the big one
	# on the wide west pier (x4..7.2), the small one on the pier east of the glass.
	_dbox(Vector3(5.9, y + 1.9, 6.2), Vector3(1.4, 0.9, 0.04), MatLib.flat(Color(0.6, 0.66, 0.62)))
	_dbox(Vector3(10.4, y + 1.9, 6.2), Vector3(0.9, 0.9, 0.04), MatLib.flat(Color(0.68, 0.62, 0.5)))
	_dbox(Vector3(11.6, y + 1.2, 8.5), Vector3(0.35, 0.06, 1.8), MatLib.wood())
	for b in range(5):
		_dbox(Vector3(11.6, y + 1.38, 7.9 + b * 0.28), Vector3(0.28, 0.3, 0.08),
			MatLib.flat([Color(0.5, 0.3, 0.25), Color(0.3, 0.4, 0.55), Color(0.45, 0.45, 0.4)][b % 3]))
	_dcyl(Vector3(6.3, y + 0.86, 7.3), 0.05, 0.09, MatLib.flat(Color(0.88, 0.88, 0.84)))
	# Med bay: cot, IV stand, supply shelf.
	_box(Vector3(19.0, y + 0.3, 10.8), Vector3(0.85, 0.6, 1.9), MatLib.flat(Color(0.75, 0.78, 0.76)))
	_dcyl(Vector3(19.9, y + 1.0, 11.4), 0.03, 2.0, MatLib.galvanized())
	_dbox(Vector3(19.9, y + 2.05, 11.4), Vector3(0.3, 0.1, 0.06), MatLib.flat(Color(0.85, 0.86, 0.84)))
	for sy in [1.1, 1.7]:
		_dbox(Vector3(21.8, y + sy, 11.6), Vector3(1.6, 0.05, 0.35), MatLib.flat(Color(0.85, 0.87, 0.85)))
	# Comms: headset, clipboard, tape reels on the rack.
	_dcyl(Vector3(6.9, y + 0.9, 16.4), 0.09, 0.06, MatLib.dark_metal())
	_dbox(Vector3(5.4, y + 0.88, 17.2), Vector3(0.26, 0.02, 0.36), MatLib.flat(Color(0.8, 0.76, 0.62)))
	for r in range(2):
		_dcyl(Vector3(9.15, y + 1.5 + r * 0.4, 17.5), 0.14, 0.05, MatLib.flat(Color(0.25, 0.26, 0.3))).rotation.x = PI / 2
	# Corridor: second extinguisher + pipe valve + floor arrows.
	_extinguisher(Vector3(26.6, y, 12.6))
	_valve(Vector3(16, y + 2.9, 12.8), true)
	_dbox(Vector3(12, y + 0.045, 13), Vector3(0.6, 0.01, 0.3), MatLib.flat(Color(0.3, 0.6, 0.9)))

	# --- Deck D additions.
	y = D_Y
	# Gym: kettlebells, second bench, wall mirror.
	for k in range(3):
		var kb := MeshInstance3D.new()
		var km := SphereMesh.new()
		km.radius = 0.11 + k * 0.03
		km.height = km.radius * 2
		km.material = MatLib.dark_metal()
		kb.mesh = km
		add_child(kb)
		kb.position = Vector3(9.2 + k * 0.5, y + km.radius, 12.3)
	_box(Vector3(13.8, y + 0.3, 9.2), Vector3(0.6, 0.6, 1.6), MatLib.flat(Color(0.3, 0.3, 0.34)))
	_dbox(Vector3(8.16, y + 1.6, 10.5), Vector3(0.04, 1.3, 2.2), MatLib.flat(Color(0.62, 0.72, 0.78)))
	# Laundry: baskets, detergent row, folding table.
	for bx in [16.2, 17.4]:
		_dcyl(Vector3(bx, y + 0.22, 11.9), 0.26, 0.44, MatLib.flat(Color(0.55, 0.58, 0.6)))
	for d in range(4):
		_dbox(Vector3(20.8 + d * 0.35, y + 1.13, 8.6), Vector3(0.22, 0.34, 0.14),
			MatLib.flat([Color(0.85, 0.5, 0.2), Color(0.3, 0.55, 0.75)][d % 2]))
	_dbox(Vector3(20.8, y + 1.09, 8.6), Vector3(2.0, 0.06, 0.5), MatLib.wood())
	_table(Vector3(21.5, y, 11.5), Vector2(1.6, 0.8))
	# Storage: barrel, rope coils, tarp-covered stack.
	_cyl(Vector3(14.6, y + 0.5, 16.8), 0.42, 1.0, MatLib.rust_steel())
	var coil := MeshInstance3D.new()
	var cm := TorusMesh.new()
	cm.inner_radius = 0.14
	cm.outer_radius = 0.3
	cm.material = MatLib.flat(Color(0.72, 0.65, 0.48))
	coil.mesh = cm
	add_child(coil)
	coil.position = Vector3(10.6, y + 0.08, 15.7)
	_box(Vector3(12.6, y + 0.5, 16.9), Vector3(1.5, 1.0, 1.1), MatLib.flat(Color(0.55, 0.6, 0.55)))
	# Landing rooms: cable tray + drip bucket, per deck.
	for ly in [B_Y, C_Y, D_Y]:
		_dbox(Vector3(25, ly + 2.9, 15.0), Vector3(3.4, 0.06, 0.25), MatLib.dark_metal())
		_dcyl(Vector3(24.0, ly + 0.14, 16.9), 0.14, 0.28, MatLib.galvanized())
