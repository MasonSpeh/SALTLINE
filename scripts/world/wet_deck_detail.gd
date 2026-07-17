extends Node3D
## Water-level overhaul: turns the Z1 wet deck from a bare slab into a working
## pontoon-top machine space, built to offshore reference — boat landing with
## fender frame and tidal ladder, SW mooring station with windlass and stud-link
## chain, west pipe gallery (green seawater main + red fire main), pump skids,
## the under-deck girder ceiling fifteen meters overhead, vents, W.T. hatches,
## bilge gutters, tide-stain bands, escape-route signage, and scattered salvage.
## All coordinates are absolute (the node sits at origin like the other builders).

const WET_Y: float = 2.0
const DECK_Y: float = 18.0

func _ready() -> void:
	_boat_landing()
	_mooring_station()
	_pipe_gallery()
	_pump_skids()
	_under_deck_girders()
	_vents_and_hatches()
	_stair_entry()
	_tide_bands()
	_scatter_items()

# ---------------------------------------------------------------- helpers

func _box(pos: Vector3, size: Vector3, mat: Material, collide: bool = true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.material = mat
	b.use_collision = collide
	add_child(b)
	b.position = pos
	return b

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

func _dtorus(pos: Vector3, inner: float, outer: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.material = mat
	mi.mesh = m
	add_child(mi)
	mi.position = pos
	return mi

func _plabel(text: String, pos: Vector3, yaw_deg: float, font_size: int = 30,
		color: Color = Color(0.82, 0.83, 0.8)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.01
	var _wear: float = clampf((color.r + color.g + color.b) / 3.0, 0.0, 1.0)   # black stencil paint
	var _k: float = lerpf(0.06, 0.17, _wear)
	l.modulate = Color(_k, _k, _k * 1.08, minf(color.a, 0.9))
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	add_child(l)
	l.position = pos
	l.rotation.y = deg_to_rad(yaw_deg)

func _readable(id: String, name_: String, pos: Vector3, size: Vector3 = Vector3(0.35, 0.45, 0.06)) -> Readable:
	var r := Readable.new()
	r.readable_id = id
	r.display_name = name_
	add_child(r)
	r.global_position = pos
	r.build_box_visual(size, Interactable.COLOR_READABLE)
	return r

func _takeable(item: String, name_: String, pos: Vector3) -> Takeable:
	var t := Takeable.new()
	t.item_id = item
	t.display_name = name_
	add_child(t)
	t.global_position = pos
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	col.shape = box
	t.add_child(col)
	col.position.y = 0.2
	t.add_child(ItemVisual.build(item))
	preload("res://scripts/world/surface_snap.gd").attach(t)
	return t

func _crate(items: Array, name_: String, pos: Vector3) -> LootContainer:
	var c := LootContainer.new()
	var typed: Array[String] = []
	for i in items:
		typed.append(str(i))
	c.items = typed
	c.display_name = name_
	add_child(c)
	c.global_position = pos
	c.build_box_visual(Vector3(1.1, 0.8, 0.8), Color(0.5, 0.45, 0.3), false, true)
	preload("res://scripts/world/surface_snap.gd").attach(c)
	return c

# ---------------------------------------------------------------- boat landing

## The dock face the SPHL fetched up against: fender frame stood off the deck
## edge, rubbing strips, a tidal ladder into the swell, lifebuoy, line-thrower.
func _boat_landing() -> void:
	var y: float = WET_Y
	var dark: Material = MatLib.dark_metal()
	var yellow: Material = MatLib.flat(Color(0.75, 0.65, 0.15))
	# The dock landing sits EAST of the SPHL (x 23–28) so the pod's hatch exit at
	# x~20 is clear — the player steps off the gangplank onto open deck, and the
	# fender frame / boarding ladder are a separate dock section beside the pod.
	# Landing frame: two vertical tubes spanning the splash zone, rust below, paint above.
	for fx in [23.5, 27.9]:
		_dcyl(Vector3(fx, y - 1.5, -22.3), 0.2, 3.0, MatLib.rust_steel())
		_dcyl(Vector3(fx, y + 1.5, -22.3), 0.2, 3.0, yellow)
		var strut := _dbox(Vector3(fx, y + 0.5, -22.05), Vector3(0.12, 0.12, 0.7), dark)
		strut.rotation.x = deg_to_rad(35)
	# Horizontal tie tubes.
	for ty in [0.7, 2.4]:
		var tie := _dcyl(Vector3(25.7, y + ty, -22.34), 0.09, 4.4, dark)
		tie.rotation.z = deg_to_rad(90)
	# Rubbing strips down the vessel face.
	for i in range(4):
		_dbox(Vector3(23.9 + i * 1.05, y + 0.9, -22.46), Vector3(0.18, 3.4, 0.09), MatLib.flat(Color(0.12, 0.12, 0.13)))
	# Tidal ladder dropping into the swell — the swimmer's way back up (has collision).
	for side in [-0.22, 0.22]:
		_dbox(Vector3(24.6 + side, y - 0.4, -22.42), Vector3(0.05, 2.6, 0.12), MatLib.galvanized())
	for i in range(8):
		var rung := _dcyl(Vector3(24.6, y - 1.55 + i * 0.31, -22.42), 0.022, 0.44, MatLib.galvanized())
		rung.rotation.z = deg_to_rad(90)
	# Lifebuoy on a bracket post east of the landing.
	_dbox(Vector3(28.4, y + 1.0, -21.85), Vector3(0.1, 2.0, 0.1), dark)
	var ring := _dtorus(Vector3(28.4, y + 1.55, -21.75), 0.3, 0.44, MatLib.flat(Color(0.9, 0.4, 0.08)))
	ring.rotation.x = deg_to_rad(90)
	for q in range(4):
		var patch := _dbox(Vector3(28.4 + 0.36 * cos(q * PI / 2 + PI / 4), y + 1.55 + 0.36 * sin(q * PI / 2 + PI / 4), -21.75),
			Vector3(0.14, 0.14, 0.09), MatLib.flat(Color(0.92, 0.92, 0.9)))
		patch.rotation.z = q * PI / 2 + PI / 4
	_plabel("LIFEBUOY", Vector3(28.4, y + 2.1, -21.79), 180, 14, Color(0.88, 0.88, 0.84))
	# Line-throwing set: the orange box every landing carries.
	_dbox(Vector3(26.7, y + 0.16, -20.5), Vector3(0.5, 0.3, 0.3), MatLib.flat(Color(0.85, 0.45, 0.1)))
	_plabel("LINE THROWER", Vector3(26.7, y + 0.2, -20.34), 180, 10, Color(0.92, 0.92, 0.88))
	# Dock locker — first honest loot of the game, off to the side of the landing.
	_crate(["rope", "flare", "sealed_tin"], "Dock Locker", Vector3(28.6, y + 0.01, -19.6))
	# Inspection tag wired to the frame.
	_readable("fender_tag", "Inspection Tag", Vector3(23.55, y + 1.15, -22.1), Vector3(0.22, 0.3, 0.05))
	# Two dead caged bulkhead lamps on the storeroom's south face.
	for lx in [11.5, 14.5]:
		_dbox(Vector3(lx, y + 3.3, -22.12), Vector3(0.22, 0.3, 0.14), dark)
		_dcyl(Vector3(lx, y + 3.3, -22.2), 0.08, 0.1, MatLib.glass(Color(0.8, 0.85, 0.8)))
		for rib in range(3):
			_dbox(Vector3(lx - 0.08 + rib * 0.08, y + 3.3, -22.21), Vector3(0.02, 0.26, 0.02), dark)

# ---------------------------------------------------------------- mooring station

## SW grating platform hung off the deck edge: chain windlass, stopper, fairlead,
## stud-link chain walking over the edge and down into the dark water.
func _mooring_station() -> void:
	var y: float = WET_Y
	var dark: Material = MatLib.dark_metal()
	var rust: Material = MatLib.rusty_metal()
	# Walkable grating platform + support knees.
	_box(Vector3(10, y - 0.06, -23.5), Vector3(3.6, 0.12, 3.0), MatLib.grating())
	for kx in [8.6, 11.4]:
		var knee := _dbox(Vector3(kx, y - 0.55, -22.55), Vector3(0.14, 0.14, 1.6), rust)
		knee.rotation.x = deg_to_rad(-42)
	# Rails on the three open sides (top, mid, kick — regulation grammar).
	_rail_seg(Vector3(8.25, y, -22.2), Vector3(8.25, y, -24.95))
	_rail_seg(Vector3(8.25, y, -24.95), Vector3(11.75, y, -24.95))
	_rail_seg(Vector3(11.75, y, -24.95), Vector3(11.75, y, -22.2))
	# Windlass: bedplate, pocketed gypsy wheel, motor, brake lever.
	_box(Vector3(10, y + 0.15, -23.8), Vector3(1.6, 0.3, 1.2), dark)
	var wheel := _dcyl(Vector3(10, y + 0.85, -23.8), 0.52, 0.46, dark)
	wheel.rotation.z = deg_to_rad(90)
	for rim_x in [-0.26, 0.26]:
		var rim := _dcyl(Vector3(10 + rim_x, y + 0.85, -23.8), 0.6, 0.06, MatLib.galvanized())
		rim.rotation.z = deg_to_rad(90)
	_dbox(Vector3(10.95, y + 0.62, -23.8), Vector3(0.7, 0.6, 0.6), MatLib.teal_paint())
	var lever := _dbox(Vector3(9.3, y + 0.95, -23.5), Vector3(0.08, 0.7, 0.08), MatLib.red_paint())
	lever.rotation.x = deg_to_rad(-25)
	# Chain stopper between wheel and fairlead.
	_dbox(Vector3(10, y + 0.3, -24.45), Vector3(0.7, 0.35, 0.45), rust)
	# Fairlead fork at the platform edge.
	for fz in [-0.18, 0.18]:
		_dbox(Vector3(10 + fz, y + 0.32, -24.95), Vector3(0.12, 0.5, 0.35), rust)
	var roller := _dcyl(Vector3(10, y + 0.42, -24.95), 0.11, 0.3, MatLib.galvanized())
	roller.rotation.z = deg_to_rad(90)
	# Stud-link chain: oval links alternating flat/upright, over the wheel, through
	# the stopper, down the edge into the sea. Link = 6d x 3.6d per the real ratio.
	var chain_pts := [
		Vector3(10, y + 1.32, -23.8), Vector3(10, y + 1.05, -24.15),
		Vector3(10, y + 0.62, -24.45), Vector3(10, y + 0.52, -24.95),
		Vector3(10, y + 0.1, -25.15), Vector3(10, y - 0.55, -25.25),
		Vector3(10, y - 1.2, -25.3), Vector3(10, y - 1.85, -25.32),
	]
	for i in range(chain_pts.size()):
		var link := _dtorus(chain_pts[i], 0.075, 0.19, rust)
		link.scale = Vector3(0.75, 1.0, 1.35)
		link.rotation.x = deg_to_rad(90)
		if i % 2 == 1:
			link.rotation.z = deg_to_rad(90)
		if i >= 3:
			link.rotation.x = deg_to_rad(55)   # chain tips over the fairlead and hangs
	# The watch log, and the grease gun its last entry never came back to.
	_readable("mooring_log", "Mooring Watch Log", Vector3(10.95, y + 0.95, -23.8), Vector3(0.3, 0.35, 0.05))
	var gun := _dcyl(Vector3(11.6, y + 0.56, -24.85), 0.04, 0.35, MatLib.red_paint())
	gun.rotation.z = deg_to_rad(90)
	# Snap-back warning where the platform meets the deck.
	_plabel("MOORING STATION 4-SW — STAY CLEAR · SNAP-BACK ZONE",
		Vector3(13.0, y + 2.3, -22.14), 180, 20, Color(0.8, 0.68, 0.2))

func _rail_seg(a: Vector3, b: Vector3) -> void:
	var mat: Material = MatLib.rust_steel()
	var mid: Vector3 = (a + b) * 0.5
	var along_x: bool = absf(b.x - a.x) > absf(b.z - a.z)
	var length: float = (b - a).length()
	var size_top := Vector3(length, 0.08, 0.08) if along_x else Vector3(0.08, 0.08, length)
	var size_kick := Vector3(length, 0.14, 0.03) if along_x else Vector3(0.03, 0.14, length)
	_box(mid + Vector3(0, 1.0, 0), size_top, mat, true)
	_dbox(mid + Vector3(0, 0.55, 0), size_top * Vector3(1, 0.75, 0.75) if along_x else size_top * Vector3(0.75, 0.75, 1), mat)
	_dbox(mid + Vector3(0, 0.09, 0), size_kick, mat)
	var n: int = maxi(1, int(length / 1.6))
	for i in range(n + 1):
		_dbox(a.lerp(b, float(i) / n) + Vector3(0, 0.5, 0), Vector3(0.06, 1.0, 0.06), mat)

# ---------------------------------------------------------------- pipe gallery

## West alley between the deck edge and the two rooms: the seawater main (green)
## and fire main (red) run the full length on saddle stands, with flange pairs,
## a valve manifold, and the cable tray feeding the pump room.
func _pipe_gallery() -> void:
	var y: float = WET_Y
	# Main runs.
	var sea := _dcyl(Vector3(9.0, y + 1.0, -14.0), 0.19, 14.0, MatLib.teal_paint())
	sea.rotation.x = deg_to_rad(90)
	var fire := _dcyl(Vector3(9.45, y + 1.55, -14.0), 0.13, 14.0, MatLib.red_paint())
	fire.rotation.x = deg_to_rad(90)
	# Vertical elbows into the deck at both ends.
	for pz in [-21.0, -7.0]:
		_dcyl(Vector3(9.0, y + 0.5, pz), 0.19, 1.0, MatLib.teal_paint())
		_dcyl(Vector3(9.45, y + 0.78, pz), 0.13, 1.55, MatLib.red_paint())
	# Flange pairs — short fat rings at the joints.
	for fz in [-18.0, -13.0, -8.5]:
		for off in [-0.05, 0.05]:
			var f1 := _dcyl(Vector3(9.0, y + 1.0, fz + off), 0.25, 0.06, MatLib.rusty_metal())
			f1.rotation.x = deg_to_rad(90)
			var f2 := _dcyl(Vector3(9.45, y + 1.55, fz + off), 0.18, 0.05, MatLib.rusty_metal())
			f2.rotation.x = deg_to_rad(90)
	# Saddle stands.
	for sz in [-19.5, -15.0, -10.5]:
		_dbox(Vector3(9.2, y + 0.45, sz), Vector3(0.9, 0.1, 0.12), MatLib.rust_steel())
		_dbox(Vector3(9.2, y + 0.2, sz), Vector3(0.12, 0.5, 0.12), MatLib.rust_steel())
	# Valve manifold: red handwheel on the sea main, yellow on the branch.
	var vw := _dtorus(Vector3(9.0, y + 1.62, -13.0), 0.1, 0.24, MatLib.red_paint())
	vw.rotation.x = deg_to_rad(0)
	_dcyl(Vector3(9.0, y + 1.35, -13.0), 0.07, 0.5, MatLib.galvanized())
	var vw2 := _dtorus(Vector3(9.45, y + 2.05, -9.0), 0.08, 0.19, MatLib.flat(Color(0.8, 0.68, 0.2)))
	vw2.rotation.x = deg_to_rad(0)
	_dcyl(Vector3(9.45, y + 1.82, -9.0), 0.06, 0.4, MatLib.galvanized())
	_plabel("SW MAIN — GRAVITY FEED", Vector3(9.6, y + 0.62, -16.5), 90, 13, Color(0.75, 0.78, 0.72))
	# Cable tray along the pump-room west wall, dropping to a junction box.
	for tray_p in [Vector3(9.82, y + 2.55, -10.0)]:
		_dbox(tray_p, Vector3(0.3, 0.04, 7.6), MatLib.galvanized())
		_dbox(tray_p + Vector3(-0.14, 0.07, 0), Vector3(0.03, 0.12, 7.6), MatLib.galvanized())
		_dbox(tray_p + Vector3(0.14, 0.07, 0), Vector3(0.03, 0.12, 7.6), MatLib.galvanized())
	_dbox(Vector3(9.86, y + 1.7, -7.2), Vector3(0.2, 0.5, 0.35), MatLib.dark_metal())
	_dbox(Vector3(9.86, y + 2.2, -7.2), Vector3(0.06, 0.55, 0.06), MatLib.dark_metal())
	# Rope coil dropped on the alley deck.
	var coil := _dtorus(Vector3(9.2, y + 0.07, -20.2), 0.1, 0.3, MatLib.rope_mat())
	coil.rotation.x = deg_to_rad(0)

# ---------------------------------------------------------------- pump skids

## Two skid-mounted pump sets in the north bay: seawater service and the fire
## pump, motors coupled through guarded shafts, gauges dead at zero.
func _pump_skids() -> void:
	var y: float = WET_Y
	var specs := [
		[Vector3(13.5, 0, -3.4), MatLib.teal_paint(), "SW SERVICE PUMP No.1"],
		[Vector3(17.5, 0, -3.4), MatLib.red_paint(), "FIRE PUMP No.2"],
	]
	for s in specs:
		var p: Vector3 = s[0]
		var body: Material = s[1]
		# Skid base + rails.
		_box(Vector3(p.x, y + 0.09, p.z), Vector3(2.4, 0.18, 1.2), MatLib.dark_metal())
		for rz in [-0.5, 0.5]:
			_dbox(Vector3(p.x, y + 0.22, p.z + rz), Vector3(2.4, 0.1, 0.14), MatLib.hazard_stripe())
		# Motor (galvanized cylinder) — coupling guard — pump volute (painted).
		var motor := _dcyl(Vector3(p.x - 0.65, y + 0.62, p.z), 0.3, 0.9, MatLib.galvanized())
		motor.rotation.z = deg_to_rad(90)
		_dbox(Vector3(p.x + 0.05, y + 0.55, p.z), Vector3(0.5, 0.35, 0.45), MatLib.hazard_stripe())
		var volute := _dcyl(Vector3(p.x + 0.72, y + 0.6, p.z), 0.42, 0.5, body)
		volute.rotation.z = deg_to_rad(90)
		# Suction line down through the deck, discharge up.
		_dcyl(Vector3(p.x + 0.72, y + 0.25, p.z + 0.55), 0.16, 0.6, body)
		_dcyl(Vector3(p.x + 0.72, y + 1.15, p.z), 0.13, 0.7, body)
		# Dead gauge, needle at zero.
		var g := _dcyl(Vector3(p.x + 0.72, y + 1.0, p.z - 0.45), 0.1, 0.04, MatLib.flat(Color(0.88, 0.88, 0.82)))
		g.rotation.x = deg_to_rad(90)
		_plabel(s[2], Vector3(p.x, y + 1.35, p.z - 0.62), 180, 14, Color(0.85, 0.85, 0.78))

# ---------------------------------------------------------------- girder ceiling

## The topside slab is fifteen meters overhead: give it bones. A grid of deep
## I-beam girders under the deck, so looking up from the wet deck reads as
## standing inside the machine, not under a lid. (Megalophobia beat.)
func _under_deck_girders() -> void:
	var gy: float = DECK_Y - 0.7
	var mat: Material = MatLib.dark_metal()
	# Transverse runs (along X), split where the SE caisson punches through.
	for gz in [-20.0, -16.0, -8.0]:
		_dbox(Vector3(19.0, gy, gz), Vector3(22.0, 0.55, 0.3), mat)
	_dbox(Vector3(13.25, gy, -12.0), Vector3(10.5, 0.55, 0.3), mat)
	_dbox(Vector3(27.75, gy, -12.0), Vector3(4.5, 0.55, 0.3), mat)
	_dbox(Vector3(14.75, gy, -4.0), Vector3(13.5, 0.55, 0.3), mat)   # stops at the stair tower
	# Longitudinal runs (along Z).
	for gx in [10.0, 15.0]:
		_dbox(Vector3(gx, gy + 0.08, -10.0), Vector3(0.28, 0.4, 24.0), mat)
	_dbox(Vector3(21.0, gy + 0.08, -18.75), Vector3(0.28, 0.4, 6.5), mat)
	_dbox(Vector3(21.0, gy + 0.08, -2.0), Vector3(0.28, 0.4, 8.0), mat)
	_dbox(Vector3(27.0, gy + 0.08, -14.25), Vector3(0.28, 0.4, 15.5), mat)
	# Dead work lamps hanging off the grid on drop rods.
	for lp in [Vector3(12.0, gy - 0.6, -18.0), Vector3(24.0, gy - 0.6, -16.0), Vector3(13.0, gy - 0.6, -6.0)]:
		_dbox(lp + Vector3(0, 0.35, 0), Vector3(0.06, 0.5, 0.06), mat)
		_dbox(lp, Vector3(0.3, 0.22, 0.3), mat)
		_dcyl(lp + Vector3(0, -0.14, 0), 0.1, 0.08, MatLib.glass(Color(0.75, 0.8, 0.75)))

# ---------------------------------------------------------------- vents & hatches

func _vents_and_hatches() -> void:
	var y: float = WET_Y
	# Gooseneck tank vents.
	for vp in [Vector3(12.5, y, -15.0), Vector3(19.2, y, -2.6)]:
		_dcyl(vp + Vector3(0, 0.45, 0), 0.09, 0.9, MatLib.galvanized())
		var bend := _dtorus(vp + Vector3(0, 0.92, 0.09), 0.06, 0.14, MatLib.galvanized())
		bend.rotation.z = deg_to_rad(90)
		_dcyl(vp + Vector3(0, 0.78, 0.2), 0.07, 0.3, MatLib.galvanized())
	# Mushroom vent.
	_dcyl(Vector3(16, y + 0.18, -2.0), 0.2, 0.36, MatLib.galvanized())
	_dcyl(Vector3(16, y + 0.4, -2.0), 0.3, 0.08, MatLib.galvanized())
	# Watertight hatch down to the pontoon spaces: coaming, dogged lid, stencil.
	_box(Vector3(14.8, y + 0.14, -18.2), Vector3(0.95, 0.28, 0.95), MatLib.concrete_floor())
	_dbox(Vector3(14.8, y + 0.32, -18.2), Vector3(0.84, 0.08, 0.84), MatLib.red_paint())
	for d in range(4):
		var dog := _dbox(Vector3(14.8 + 0.38 * cos(d * PI / 2), y + 0.37, -18.2 + 0.38 * sin(d * PI / 2)),
			Vector3(0.16, 0.04, 0.05), MatLib.galvanized())
		dog.rotation.y = d * PI / 2
	_plabel("W.T. HATCH — CHAIN LOCKER 4-SW · KEEP CLOSED", Vector3(14.8, y + 0.55, -17.7), 180, 11, Color(0.88, 0.88, 0.82))
	# Bilge gutters along the deck edges.
	_dbox(Vector3(8.22, y + 0.015, -10.0), Vector3(0.24, 0.03, 23.6), MatLib.dark_metal())
	_dbox(Vector3(12.0, y + 0.015, -21.86), Vector3(7.6, 0.03, 0.24), MatLib.dark_metal())
	# Escape-route signage — photoluminescent green, the offshore lingua franca.
	_plabel("ESCAPE ROUTE → STAIRS", Vector3(18.2, y + 2.0, -10.0), 90, 18, Color(0.55, 0.9, 0.6))
	_plabel("↑ MUSTER STATION B — TOPSIDE", Vector3(21.86, y + 2.0, -2.5), -90, 16, Color(0.55, 0.9, 0.6))
	# Ballast tank stencil on the caisson's west face.
	_plabel("W.B.T. 4-SE", Vector3(18.96, y + 3.5, -12.0), -90, 26, Color(0.7, 0.72, 0.68))

# ---------------------------------------------------------------- stair entry

## Frame the tower door so the way up reads from across the deck.
func _stair_entry() -> void:
	var y: float = WET_Y
	for jx in [22.85, 24.35]:
		_dbox(Vector3(jx, y + 1.15, -6.0), Vector3(0.18, 2.3, 0.32), MatLib.hazard_stripe())
	_dbox(Vector3(23.6, y + 2.4, -6.0), Vector3(1.7, 0.2, 0.32), MatLib.hazard_stripe())
	_box(Vector3(23.6, y + 0.02, -6.65), Vector3(1.5, 0.04, 0.9), MatLib.checker_plate(), false)
	_plabel("STAIRS → TOPSIDE DECK", Vector3(23.6, y + 2.75, -6.18), 180, 20, Color(0.88, 0.88, 0.84))
	# Dead caged lamp over the door.
	_dbox(Vector3(23.6, y + 3.2, -6.22), Vector3(0.22, 0.28, 0.14), MatLib.dark_metal())
	_dcyl(Vector3(23.6, y + 3.2, -6.3), 0.08, 0.1, MatLib.glass(Color(0.8, 0.85, 0.8)))

# ---------------------------------------------------------------- tide bands

## The swell's signature on the concrete: an algae-dark band at the waterline
## of every caisson and along the pontoon shoulders.
func _tide_bands() -> void:
	for leg in [Vector3(-22, 0, -12), Vector3(22, 0, -12), Vector3(-22, 0, 12), Vector3(22, 0, 12)]:
		_dbox(Vector3(leg.x, 0.75, leg.z), Vector3(6.14, 1.15, 6.14), MatLib.tide_band())
	for pz in [-12.0, 12.0]:
		_dbox(Vector3(0, 0.6, pz), Vector3(56.08, 0.55, 8.08), MatLib.tide_band())

# ---------------------------------------------------------------- salvage scatter

## Loose salvage that tells the story of a working deck stopped mid-shift.
func _scatter_items() -> void:
	var y: float = WET_Y
	_takeable("driftwood", "Driftwood", Vector3(26.8, y + 0.05, -21.4))
	# The fishing rod — propped in the storeroom where a rigger left it. The other
	# half of the food economy, waiting behind the first door most players open.
	_takeable("fishing_rod", "Fishing Rod", Vector3(11.0, y + 0.05, -17.2))
	# The Angler's Notes beside it: every species, its hours, its water, its
	# weather — generated from the same table the rod actually rolls against.
	_readable("anglers_notes", "Angler's Notes", Vector3(11.7, y + 0.62, -16.6), Vector3(0.32, 0.4, 0.05))
	# Drying lines: catch goes straight from the water to the wind. Strung by the
	# rigging bench (west of the SPHL exit) and along the loot-room wall — clear of
	# the pod's hatch corridor (x18.6–21.4, z-22.9→-21), and raised above head.
	for spec in [[Vector3(13.0, y + 2.3, -18.2), 2.6], [Vector3(12.0, y + 2.3, -20.5), 3.0]]:
		var line: Interactable = preload("res://scripts/components/hang_line.gd").new()
		line.length_m = spec[1]
		add_child(line)
		line.global_position = spec[0]
	for px in [11.6, 14.4]:
		_dbox(Vector3(px, y + 1.15, -18.2), Vector3(0.08, 2.3, 0.08), MatLib.rust_steel())
	_takeable("life_ring", "Spare Lifebuoy", Vector3(16.4, y + 0.05, -21.2))
	_takeable("tarp", "Folded Tarp", Vector3(23.2, y + 1.3, -21.0))
	_takeable("scrap_metal", "Scrap Plate", Vector3(8.8, y + 0.05, -17.5))
	_takeable("sealed_tin", "Sealed Tin", Vector3(9.1, y + 0.05, -7.6))
	_takeable("kelp_bundle", "Kelp Snag", Vector3(23.0, y + 0.05, -15.8))
	_takeable("canned_food", "Dropped Ration", Vector3(11.3, y + 0.05, -23.1))
	# Oil drums in the NE corner, one tipped mid-pour, spill stain beneath.
	for i in range(3):
		_dcyl(Vector3(27.3 + (i % 2) * 0.9, y + 0.53, -3.3 + (i / 2) * 0.9), 0.4, 1.05, MatLib.rusty_metal())
	var tipped := _dcyl(Vector3(26.3, y + 0.42, -2.2), 0.4, 1.05, MatLib.rusty_metal())
	tipped.rotation.z = deg_to_rad(90)
	tipped.rotation.y = deg_to_rad(20)
	_dbox(Vector3(25.9, y + 0.012, -2.0), Vector3(1.5, 0.02, 1.1), MatLib.flat(Color(0.08, 0.07, 0.06)))
	# Pallet pair against the west edge.
	for py in [0.1, 0.26]:
		_dbox(Vector3(8.9, y + py, -2.5), Vector3(1.2, 0.12, 1.0), MatLib.weathered_wood())
