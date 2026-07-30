extends Node3D
## EXTERIOR DRESSING — the west alley (Bay 4) and the machine-shop roof.
##
## Two spaces on this rig read as unfinished from outside: the wide concrete deck
## between the MACHINE SHOP and the BUNKHOUSE, and the machine shop's bare roof slab.
## This pass fills both the way a working rig actually fills them.
##
## GEOMETRY THIS FILE DEPENDS ON (read out of rig_builder.gd, never edited here):
##   machine shop   x -28..-14, z -18..-6, floor 18.0, WALL_H 3.2, WALL_T 0.25
##                  north wall FACE (into the alley)  z = -5.875
##                  roof slab _box((-21, 21.2, -12), (14.5, 0.25, 12.5))
##                  -> roof TOP 21.325, slab x -28.25..-13.75, z -18.25..-5.75
##   bunkhouse      x -28..-8,  z 4..18,  floor 18.0
##                  south wall FACE (into the alley)  z = 3.875
##   topside deck   CSGBox 60 x 1 x 40 centred (0, 17.5, 0) -> deck TOP y 18.0
##
## So the alley is x -28..-14 wall-to-wall (open eastward to x -8 on the dorm side),
## z -5.875..3.875, ~9.75 m deep and 14 m wide. It is a ROUTE, not a storeroom: the
## middle lane z -2.4..+0.4 (2.8 m clear, painted) is kept empty end to end and every
## piece of kit is stood in the south band (against the shop) or the north band
## (against the dorm).
##
## ANCHORING DOCTRINE. Nothing here hangs in air. Deck kit sits on skids, sills,
## pallets or bolted feet at y 18.0; roof kit sits on plinths or bolted baseplates at
## y 21.325; wall kit hangs off visible gusset brackets and standoffs and declares
## itself `placement_exempt` (that group is exactly what PlacementProbe provides for
## genuinely wall-fixed dressing). Lamps live INSIDE their fixtures so LightAnchorProbe
## finds geometry within its 0.45 m radius, and every Label3D is stencil paint sitting
## 1-2 cm off a real concrete or steel face so LabelAnchorProbe can march into backing.
##
## COLLISION. Visuals are plain MeshInstance3D (cheap, and SupportIndex indexes them as
## real support surfaces). Solidity comes from bare StaticBody3D barriers with no mesh —
## invisible to the audits, one body per mass instead of a CSG tree per bolt. This is
## gl_compatibility on a laptop; the roof silhouette is a lot of small boxes already.
##
## Self-contained: it builds itself from _ready and touches no other file.

const SignFit = preload("res://scripts/world/sign_fit.gd")   # by path: class cache lags new files
const LADDER := preload("res://scripts/components/ladder.gd")

const DECK_Y: float = 18.0
const SHOP_WALL_Z: float = -5.875     # machine shop north face

## ============================ LADDER KEEP-OUT (do not dress inside this) ============
## The machine-shop ROOF ACCESS ladder climbs the shop's north face at x -14.8, y 18 ->
## 21.55 (see _roof_ladder). It has now been blocked THREE separate times by wall
## dressing that runs the length of this face and simply carried on straight through the
## climb — most recently the ShopWallTray cable tray (y 20.72) and ShopWallConduit
## (y 20.30), both of which ran east to x -14.3/-14.4 and crossed the rungs dead centre.
##
## ANY new run, tray, conduit, pipe, hose or bracket on the shop north face MUST stop at
## LADDER_KEEP_X0 (coming from the west) or start at LADDER_KEEP_X1 (from the east). The
## band between them is the climber's body plus the safety cage — it stays empty.
const LADDER_KEEP_X0: float = -15.6   ## west edge of the ladder keep-out
const LADDER_KEEP_X1: float = -14.1   ## east edge of the ladder keep-out
const DORM_WALL_Z: float = 3.875      # bunkhouse south face
const WALL_TOP: float = 21.2          # both blocks: 18.0 + WALL_H

const ROOF_Y: float = 21.325          # machine shop roof, walking surface
const ROOF_X0: float = -28.25
const ROOF_X1: float = -13.75
const ROOF_Z0: float = -18.25
const ROOF_Z1: float = -5.75

## The kept-clear walking lane down the middle of the alley.
const LANE_Z0: float = -2.4
const LANE_Z1: float = 0.4

var _rng := RandomNumberGenerator.new()
var _zone: LightZone

func _ready() -> void:
	_rng.seed = 40407
	_zone = LightZone.new()
	_zone.circuit_id = "topside_floodlights"
	_zone.zone_extents = Vector3(22, 6, 11)
	add_child(_zone)
	_zone.global_position = Vector3(-19, DECK_Y + 2.0, -1.0)

	# --- the alley ---
	_deck_paint()
	_shop_wall_line()
	_dorm_wall_line()
	_pipe_rack()
	_drum_bund()
	_cable_drum()
	_gas_bottle_cage()
	_welding_bay()
	_roof_ladder()
	_safety_locker()
	_hose_reel_cabinet()
	_eyewash_station()
	_air_hose_reel()
	_grit_bin()
	_extinguisher_point()
	_tarped_pallets()
	_jockey_skid()
	_cargo_basket()
	_muster_point()

	# --- the machine-shop roof ---
	_roof_handrails()
	_roof_walkway()
	_generator_set()
	_hvac_units()
	_vent_mushrooms()
	_comms_mast()
	_radome()
	_roof_cable_trays()
	_roof_signage()
	_anchor()
	_compact()

## PlacementProbe walks up from each drawn mesh to the outermost node whose PARENT has
## more than CONTAINER_CHILDREN (40) children, and audits that as one placed object. An
## assembly authored with more than 40 parts therefore gets measured bolt by bolt, and a
## cage roof bar reads as "floating" because nothing sits directly under that one bar.
## Bucketing each assembly's parts into sub-groups makes the audit measure the PROP —
## which is the thing that is actually standing on the deck. Every bucket is identity, so
## nothing moves; this is a tree shape change, not a placement change.
const BUCKET: int = 24
const BUCKET_LIMIT: int = 32

## Give every assembly a pivot INSIDE ITSELF.
##
## _asm() adds its node with no position, so an assembly's origin sits at the world origin
## while its parts carry absolute world coordinates — the machine-shop roof kit is authored
## 20m out, the alley props 25m out. That is harmless as long as nobody ever writes a
## rotation to an assembly node. Something does: ambience.gd::_collect_sway walks the live
## scene looking for hanging things to blow about, matches them BY NAME FRAGMENT ("tarp",
## "chain", "flag", ...), and then writes transform.basis on whatever it matched. Rotating a
## node whose geometry is 25m from its own origin does not flap it — it swings the whole
## prop through an arc metres long. The tarped pallet load in the alley was matched on
## "tarp", and in a storm (peak sway ~8 degrees at 25.7m radius) it was thrown about 3.7m
## into the air over the deck, which is the object the owner photographed and took for a
## lifeboat. On the other half of the cycle it sank into the plating.
##
## Re-seating each assembly on the centre of its own geometry makes that impossible: the
## parts move by exactly the amount the origin moves, so nothing shifts by a millimetre,
## but any basis written to the node now pivots the prop in place instead of orbiting it
## around the middle of the map. It also makes the sway collector's own proximity test
## (`global_position.distance_to(player) < 34`) measure the prop rather than the world
## origin, which is what it was always meant to mean.
func _anchor() -> void:
	for child in get_children():
		var a := child as Node3D
		if a == null or a == _zone:
			continue
		var c: Vector3 = Vector3.ZERO
		var box: AABB = _tree_aabb(a)
		if box.size != Vector3.ZERO:
			c = box.get_center()
		else:
			# Stencil-paint assemblies hold nothing but Label3Ds, whose AABB is still empty
			# this early — the glyph mesh is not built until the label has been drawn once.
			# Their part positions are just as good a centre, and without this fallback the
			# two wall-stencil assemblies keep their origin out at the middle of the map.
			var mid: Vector3 = _parts_centre(a)
			if mid == Vector3.INF:
				continue
			c = mid
		for part in a.get_children():
			var p := part as Node3D
			if p != null:
				p.position -= c
		a.position += c

## Midpoint of an assembly's direct parts, for assemblies that draw nothing measurable yet.
## Vector3.INF means it has no positioned parts at all.
func _parts_centre(a: Node3D) -> Vector3:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for part in a.get_children():
		var p := part as Node3D
		if p == null:
			continue
		lo = lo.min(p.position)
		hi = hi.max(p.position)
	if lo == Vector3.INF:
		return Vector3.INF
	return (lo + hi) * 0.5

## Merged world AABB of every visual under `n`. Assemblies are unrotated and unscaled at
## this point, so this is also their local AABB — but go through the transform anyway so a
## part authored with a rotation (tarp skirts, tilted chocks) is measured where it is.
func _tree_aabb(n: Node3D) -> AABB:
	var acc := AABB()
	var first: bool = true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var vi := cur as VisualInstance3D
		if vi == null or vi.get_aabb().size == Vector3.ZERO:
			continue
		var a: AABB = vi.global_transform * vi.get_aabb()
		if first:
			acc = a
			first = false
		else:
			acc = acc.merge(a)
	return acc if not first else AABB()

func _compact() -> void:
	for a in get_children():
		if not (a is Node3D):
			continue
		var kids: Array = a.get_children()
		if kids.size() <= BUCKET_LIMIT:
			continue
		var i: int = 0
		while i < kids.size():
			var g := Node3D.new()
			g.name = "Part%d" % (i / BUCKET)
			a.add_child(g)
			for j in range(i, mini(i + BUCKET, kids.size())):
				var c: Node = kids[j]
				a.remove_child(c)
				g.add_child(c)
			i += BUCKET

# ============================================================ helpers

## An assembly: one prop, one node, so the placement audit measures it as one thing.
func _asm(n: String) -> Node3D:
	var a := Node3D.new()
	a.name = n
	# Declare every assembly to the placement audit. These are plain Node3D groupings of
	# bare MeshInstance3D by design (see the header), and PlacementProbe's "managed" test
	# was `is_in_group("dress_prop") or n is CollisionObject3D` — so the whole of this file
	# fell into the advisory scenery bucket and "FLOATING 0" said nothing whatsoever about
	# the alley and roof dressing. One group call puts it back under audit.
	a.add_to_group("dress_prop")
	add_child(a)
	return a

## Same, but declared wall-fixed — it hangs on brackets and nothing is under it.
func _wall_asm(n: String) -> Node3D:
	var a := _asm(n)
	a.add_to_group("placement_exempt")
	return a

func _bx(p: Node3D, pos: Vector3, size: Vector3, mat: Material,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	p.add_child(mi)
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))
	return mi

## Cylinder. Axis is local Y: along X needs rot.z = 90, along Z needs rot.x = 90.
## r_top < 0 means "same as r" (a plain cylinder); pass a different value for a cone.
func _cy(p: Node3D, pos: Vector3, r: float, h: float, mat: Material,
		rot: Vector3 = Vector3.ZERO, r_top: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if r_top < 0.0 else r_top
	m.height = h
	m.radial_segments = 12
	m.rings = 1
	m.material = mat
	mi.mesh = m
	p.add_child(mi)
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))
	return mi

func _sp(p: Node3D, pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	m.material = mat
	mi.mesh = m
	p.add_child(mi)
	mi.position = pos
	return mi

## Ring — hose coils, ladder cage hoops, bird guards. Lies in XZ unless rotated.
func _ring(p: Node3D, pos: Vector3, inner: float, outer: float, mat: Material,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 16
	m.ring_segments = 8
	m.material = mat
	mi.mesh = m
	p.add_child(mi)
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))
	return mi

## Bare collider — the mass you cannot walk through. No mesh, so it stays out of the
## support index and out of the placement audit's object list; the visible geometry
## above it is what those measure.
func _solid(p: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	p.add_child(b)
	b.position = center
	return b

## Stencil paint. yaw/pitch aim the glyph face: the label's local -Z must point INTO
## whatever it is painted on (yaw 0 = a wall on the label's -Z side, yaw 180 = +Z side,
## pitch -90 = lying on a deck reading east).
##
## `fit` is the panel this marking has to live inside, in metres (x = width, y = height,
## 0 on either axis = unconstrained): the font shrinks until the wording fits. Prefer
## `_placard()` below, which sizes the plate and the text from ONE number and so cannot
## drift apart. See sign_fit.gd for why an eyeballed font size is not good enough.
func _paint(p: Node3D, text: String, pos: Vector3, yaw: float, pitch: float,
		fsize: int, col: Color = Color(0.09, 0.09, 0.1),
		fit: Vector2 = Vector2.ZERO) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = SignFit.fit_size(text, fit.x, fit.y, fsize)
	if fit != Vector2.ZERO:
		l.set_meta("sign_face", fit)   # asserted by tests/label_anchor_probe.gd
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	p.add_child(l)
	l.position = pos
	l.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	return l

## A NAME PLATE AND ITS WORDING, FROM ONE NUMBER. Draws the backing plate at `centre`
## with in-plane size `size` and stencils `text` on the front of it, centred, at the
## largest font size up to `fsize` that fits inside `size` less `MARGIN` on every edge.
##
## Every fixture on this deck used to build the plate and the paint as two independent
## statements — a `_bx(..., Vector3(0.86, 0.24, 0.03), red)` and, two lines later, a
## `_paint(..., 16, ...)` at a hand-nudged offset. Neither one knew the other's size, so
## "FIRE HOSE REEL" rendered 1.21 m wide across an 0.86 m plate (a 41% overhang, in the
## owner's line of sight from the bunkhouse door) and seven other placards were 10-90 mm
## over on one axis or the other. The nudges are the same bug: every one of them pushed
## the wording 20-80 mm ABOVE the plate centre, which is the whole vertical overflow.
##
## `depth` is the plate thickness; `front` is the outward normal (the label sits 20 mm
## proud of the plate face along it, so it renders in front and not z-fighting).
func _placard(p: Node3D, text: String, centre: Vector3, size: Vector2, front: Vector3,
		fsize: int, plate: Material, col: Color = Color(0.10, 0.10, 0.10, 0.95),
		depth: float = 0.025) -> void:
	# A Label3D's visible face is its local +Z, so the yaw that points the wording at the
	# viewer is atan2(n.x, n.z) — derived, not one of the four hand-typed cardinals this
	# file used to carry at every call site.
	var n: Vector3 = front.normalized()
	var yaw: float = rad_to_deg(atan2(n.x, n.z))
	var pitch: float = 0.0
	if absf(n.y) > 0.9:
		# Lying flat (a deck marking or an upward-facing plate): pitch the glyph plane over.
		pitch = -90.0 if n.y > 0.0 else 90.0
		yaw = 0.0
	var box := BoxMesh.new()
	box.size = Vector3(size.x, depth, size.y) if pitch != 0.0 else Vector3(size.x, size.y, depth)
	box.material = plate
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	mi.position = centre
	mi.rotation.y = deg_to_rad(yaw)
	_paint(p, text, centre + n * (depth * 0.5 + 0.02), yaw, pitch, fsize, col,
		size - Vector2(PLACARD_MARGIN, PLACARD_MARGIN) * 2.0)

const PLACARD_MARGIN: float = 0.03   ## clear border kept between wording and plate edge

## Fixture lamp: an OmniLight tucked inside its own housing, on the deck circuit.
func _lamp(world_pos: Vector3, colour: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	_zone.add_light(l)
	l.global_position = world_pos

## Handrail run a->b at a walking surface: stanchions on base plates, top + mid rail,
## toe board, and a barrier so the rail actually stops you.
func _handrail(p: Node3D, a: Vector3, b: Vector3) -> void:
	var steel: Material = MatLib.rust_steel()
	var d: Vector3 = b - a
	var length: float = d.length()
	if length < 0.3:
		return
	var mid: Vector3 = (a + b) * 0.5
	var along_x: bool = absf(d.x) > absf(d.z)
	var n: int = maxi(2, int(round(length / 2.0)) + 1)
	for i in range(n):
		var sp: Vector3 = a.lerp(b, float(i) / float(n - 1))
		_bx(p, sp + Vector3(0, 0.545, 0), Vector3(0.07, 1.09, 0.07), steel)
		_bx(p, sp + Vector3(0, 0.015, 0), Vector3(0.2, 0.03, 0.2), steel)
	for h in [1.07, 0.57]:
		_bx(p, mid + Vector3(0, h, 0),
			Vector3(length, 0.055, 0.055) if along_x else Vector3(0.055, 0.055, length), steel)
	_bx(p, mid + Vector3(0, 0.09, 0),
		Vector3(length, 0.16, 0.03) if along_x else Vector3(0.03, 0.16, length), steel)
	_solid(p, mid + Vector3(0, 0.56, 0),
		Vector3(length, 1.12, 0.1) if along_x else Vector3(0.1, 1.12, length))

## Cable tray on stools between two roof points, at height `lift` above the surface.
func _tray_run(p: Node3D, a: Vector3, b: Vector3, lift: float) -> void:
	var galv: Material = MatLib.galvanized()
	var d: Vector3 = b - a
	var length: float = d.length()
	if length < 0.2:
		return
	var mid: Vector3 = (a + b) * 0.5
	var along_x: bool = absf(d.x) > absf(d.z)
	_bx(p, mid + Vector3(0, lift, 0),
		Vector3(length, 0.05, 0.3) if along_x else Vector3(0.3, 0.05, length), galv)
	for side in [-0.13, 0.13]:
		var off := Vector3(0, lift + 0.06, side) if along_x else Vector3(side, lift + 0.06, 0)
		_bx(p, mid + off,
			Vector3(length, 0.09, 0.03) if along_x else Vector3(0.03, 0.09, length), galv)
	var n: int = maxi(2, int(length / 1.8) + 1)
	for i in range(n):
		var sp: Vector3 = a.lerp(b, float(i) / float(n - 1))
		_bx(p, sp + Vector3(0, lift * 0.5, 0), Vector3(0.07, lift, 0.07), galv)
		_bx(p, sp + Vector3(0, 0.015, 0), Vector3(0.18, 0.03, 0.18), galv)
	# The bundle riding in it.
	for i in range(3):
		var off2: float = -0.09 + i * 0.09
		var c := _cy(p, mid + (Vector3(0, lift + 0.06, off2) if along_x else Vector3(off2, lift + 0.06, 0)),
			0.035, length, MatLib.flat(Color(0.13, 0.13, 0.15)),
			Vector3(0, 0, 90) if along_x else Vector3(90, 0, 0))
		c.name = "Core%d" % i

## Conduit run hugging a wall face, plus its saddle clamps.
func _conduit_x(p: Node3D, x0: float, x1: float, y: float, z: float, r: float) -> void:
	var dark: Material = MatLib.dark_metal()
	var length: float = absf(x1 - x0)
	_cy(p, Vector3((x0 + x1) * 0.5, y, z), r, length, dark, Vector3(0, 0, 90))
	var n: int = maxi(2, int(length / 2.2) + 1)
	for i in range(n):
		var x: float = lerpf(x0, x1, float(i) / float(n - 1))
		_bx(p, Vector3(x, y, z + (0.05 if z < 0.0 else -0.05) * -1.0),
			Vector3(0.07, r * 2.6, 0.1), MatLib.galvanized())

# ============================================================ ALLEY: deck paint

## The alley reads as a route before it reads as a store: a painted lane down the
## middle with dashed edges, a KEEP CLEAR stencil, and hazard chevrons at the two
## things you must not stand in front of (the roof ladder and the muster square).
func _deck_paint() -> void:
	var a := _asm("AlleyDeckPaint")
	a.add_to_group("placement_exempt")
	var yellow: Material = MatLib.flat(Color(0.60, 0.52, 0.13))
	var white: Material = MatLib.flat(Color(0.66, 0.66, 0.62))
	var y: float = DECK_Y + 0.012
	# Dashed lane edges, x -28.4 .. -8.6.
	var x: float = -28.2
	while x < -8.8:
		for lz in [LANE_Z0, LANE_Z1]:
			_bx(a, Vector3(x, y, lz), Vector3(0.8, 0.02, 0.09), yellow)
		x += 1.45
	_paint(a, "KEEP CLEAR", Vector3(-24.4, y + 0.005, -1.0), 0.0, -90.0, 40,
		Color(0.66, 0.58, 0.16, 0.8))
	_paint(a, "BAY 4", Vector3(-13.9, y + 0.005, -1.0), 0.0, -90.0, 44,
		Color(0.66, 0.58, 0.16, 0.8))
	# Chevrons keeping the foot of the roof ladder clear.
	for i in range(5):
		var c := _bx(a, Vector3(-15.9 + i * 0.44, y, -4.35), Vector3(0.13, 0.02, 1.15), yellow)
		c.rotation.y = deg_to_rad(28)
	_bx(a, Vector3(-14.8, y, -3.5), Vector3(2.4, 0.02, 0.07), white)
	# Weathering: the lane is walked, the bands are not. Alpha-blended, because
	# MatLib.flat() never enables transparency — an alpha there renders fully opaque.
	for i in range(14):
		var wx: float = _rng.randf_range(-28.0, -9.0)
		var wz: float = _rng.randf_range(LANE_Z0 + 0.2, LANE_Z1 - 0.2)
		# Stagger each band's height by index: 14 random rectangles at one identical
		# y overlap each other constantly, and every overlap was a coplanar-face
		# z-fight patch flickering in the walk lane. 0.4mm per band is invisible as
		# a step but guarantees no two bands ever share a plane.
		var s := _bx(a, Vector3(wx, DECK_Y + 0.008 + float(i) * 0.0004, wz),
			Vector3(_rng.randf_range(0.5, 1.6), 0.015, _rng.randf_range(0.4, 1.1)),
			_wear_mat())
		s.rotation.y = _rng.randf_range(0.0, TAU)

# ============================================================ ALLEY: wall lines

## Machine-shop face (z -5.875): the alley's power and drainage spine.
func _shop_wall_line() -> void:
	var galv: Material = MatLib.galvanized()
	var dark: Material = MatLib.dark_metal()
	var steel: Material = MatLib.rust_steel()
	var zf: float = SHOP_WALL_Z

	# EVERY run on this face STOPS at LADDER_KEEP_X0 — the roof-access ladder climbs the
	# wall at x -14.8 and this tray/conduit used to run straight through its rungs.
	# Terminating the spine west of the ladder is also how a real platform routes it: the
	# tray dies into a gland plate and the drops carry on below the climb.
	var tray_x1: float = LADDER_KEEP_X0
	var tray_x0: float = -27.7
	var tray_len: float = tray_x1 - tray_x0            # 12.1 m (was 13.4, ending at -14.3)
	var tray_mid: float = (tray_x0 + tray_x1) * 0.5    # -21.65
	var tray := _wall_asm("ShopWallTray")
	# Cable tray high on the wall on real angle brackets.
	_bx(tray, Vector3(tray_mid, DECK_Y + 2.72, zf + 0.22), Vector3(tray_len, 0.05, 0.32), galv)
	for side in [-0.14, 0.14]:
		_bx(tray, Vector3(tray_mid, DECK_Y + 2.77, zf + 0.22 + side), Vector3(tray_len, 0.10, 0.03), galv)
	for i in range(8):
		var bx: float = -27.4 + i * 1.85
		if bx > tray_x1:
			continue                                    # the old i=7 bracket stood at -14.45
		_bx(tray, Vector3(bx, DECK_Y + 2.66, zf + 0.11), Vector3(0.06, 0.06, 0.26), steel)
		var d := _bx(tray, Vector3(bx, DECK_Y + 2.53, zf + 0.30), Vector3(0.05, 0.30, 0.05), steel)
		d.rotation.x = deg_to_rad(-34)
	for i in range(3):
		_cy(tray, Vector3(tray_mid, DECK_Y + 2.78, zf + 0.15 + i * 0.07), 0.03, tray_len,
			MatLib.flat(Color(0.14, 0.13, 0.15)), Vector3(0, 0, 90))
	# Gland plate capping the cut end, so the tray reads as terminated rather than sawn off.
	_bx(tray, Vector3(tray_x1 - 0.04, DECK_Y + 2.74, zf + 0.22), Vector3(0.08, 0.22, 0.36), steel)

	var cond := _wall_asm("ShopWallConduit")
	_conduit_x(cond, -27.4, LADDER_KEEP_X0, DECK_Y + 2.30, zf + 0.08, 0.055)
	_conduit_x(cond, -27.4, -19.0, DECK_Y + 2.12, zf + 0.07, 0.04)
	# Junction boxes with their drops off the tray.
	for jx in [-25.4, -20.6, -16.2]:
		var jb := _wall_asm("ShopJunctionBox")
		_bx(jb, Vector3(jx, DECK_Y + 1.55, zf + 0.10), Vector3(0.30, 0.40, 0.17), dark)
		_bx(jb, Vector3(jx, DECK_Y + 1.55, zf + 0.19), Vector3(0.24, 0.34, 0.02),
			MatLib.flat(Color(0.28, 0.30, 0.30)))
		for cx in [-0.11, 0.11]:
			for cy in [-0.17, 0.17]:
				_cy(jb, Vector3(jx + cx, DECK_Y + 1.55 + cy, zf + 0.20), 0.014, 0.02,
					steel, Vector3(90, 0, 0))
		_cy(jb, Vector3(jx, DECK_Y + 1.95, zf + 0.08), 0.035,
			(DECK_Y + 2.30) - (DECK_Y + 1.75), dark)
		_cy(jb, Vector3(jx, DECK_Y + 1.30, zf + 0.08), 0.035, 0.55, dark)

	# Drain downpipes off the roof lip, with a shoe that spits onto the deck.
	for dx in [-27.6, -17.4]:   # -14.5 ran its clips into the roof ladder's stiles
		var dp := _wall_asm("ShopDownpipe")
		_cy(dp, Vector3(dx, DECK_Y + 1.72, zf + 0.14), 0.085, 3.35, galv)
		for cy in [0.5, 1.7, 2.9]:
			_bx(dp, Vector3(dx, DECK_Y + cy, zf + 0.08), Vector3(0.26, 0.06, 0.10), steel)
		var shoe := _cy(dp, Vector3(dx, DECK_Y + 0.12, zf + 0.26), 0.085, 0.34, galv)
		shoe.rotation.x = deg_to_rad(38)
		_cy(dp, Vector3(dx, DECK_Y + 3.42, zf + 0.14), 0.085, 0.24, galv, Vector3.ZERO, 0.14)
		# Deck gully it drains into.
		_bx(dp, Vector3(dx, DECK_Y + 0.01, zf + 0.55), Vector3(0.5, 0.03, 0.4), MatLib.grating())

	# Bulkhead lamps on real swan-neck brackets.
	for lx in [-24.0, -17.6]:
		var lm := _wall_asm("ShopBulkheadLamp")
		_bx(lm, Vector3(lx, DECK_Y + 2.95, zf + 0.05), Vector3(0.22, 0.28, 0.05), steel)
		_bx(lm, Vector3(lx, DECK_Y + 2.95, zf + 0.20), Vector3(0.07, 0.07, 0.30), steel)
		var body := _cy(lm, Vector3(lx, DECK_Y + 2.86, zf + 0.36), 0.13, 0.22,
			MatLib.flat(Color(0.30, 0.33, 0.32)))
		body.rotation.x = deg_to_rad(90)
		_cy(lm, Vector3(lx, DECK_Y + 2.86, zf + 0.48), 0.115, 0.06,
			MatLib.flat(Color(0.95, 0.92, 0.74), true, 1.4), Vector3(90, 0, 0))
		for i in range(4):
			var g := _bx(lm, Vector3(lx + cos(i * PI / 2.0) * 0.12, DECK_Y + 2.86 + sin(i * PI / 2.0) * 0.12,
				zf + 0.42), Vector3(0.02, 0.02, 0.16), steel)
			g.name = "Cage%d" % i
		_ring(lm, Vector3(lx, DECK_Y + 2.86, zf + 0.50), 0.11, 0.135, steel, Vector3(90, 0, 0))
		_lamp(Vector3(lx, DECK_Y + 2.86, zf + 0.44), Color(1.0, 0.92, 0.74), 3.2, 9.0)

	# Wall extract grille above the welding bay.
	var gr := _wall_asm("ShopExtractGrille")
	_bx(gr, Vector3(-16.6, DECK_Y + 2.05, zf + 0.06), Vector3(0.95, 0.75, 0.12), galv)
	for i in range(6):
		var lv := _bx(gr, Vector3(-16.6, DECK_Y + 1.78 + i * 0.115, zf + 0.13),
			Vector3(0.88, 0.06, 0.09), MatLib.flat(Color(0.42, 0.44, 0.45)))
		lv.rotation.x = deg_to_rad(24)

	# Stencilled paint on the concrete itself.
	var sg := _wall_asm("ShopWallStencils")
	_paint(sg, "BAY 4", Vector3(-24.4, DECK_Y + 1.85, zf + 0.02), 0.0, 0.0, 58,
		Color(0.11, 0.11, 0.12, 0.88))
	_paint(sg, "MACHINE SHOP", Vector3(-24.4, DECK_Y + 1.42, zf + 0.02), 0.0, 0.0, 26,
		Color(0.12, 0.12, 0.13, 0.8))
	_paint(sg, "NO NAKED FLAME", Vector3(-19.4, DECK_Y + 1.62, zf + 0.02), 0.0, 0.0, 16,
		Color(0.13, 0.12, 0.12, 0.8))

## Bunkhouse face (z 3.875). Nothing here fouls the existing grab rail on that wall
## (x -19.5..-16.5 at y 19.1, z 3.82) — that span is deliberately left clear.
func _dorm_wall_line() -> void:
	var galv: Material = MatLib.galvanized()
	var steel: Material = MatLib.rust_steel()
	var dark: Material = MatLib.dark_metal()
	var zf: float = DORM_WALL_Z

	var tray := _wall_asm("DormWallTray")
	_bx(tray, Vector3(-18.5, DECK_Y + 2.78, zf - 0.22), Vector3(18.6, 0.05, 0.32), galv)
	for side in [-0.14, 0.14]:
		_bx(tray, Vector3(-18.5, DECK_Y + 2.83, zf - 0.22 + side), Vector3(18.6, 0.10, 0.03), galv)
	for i in range(10):
		var bx: float = -27.4 + i * 2.05
		_bx(tray, Vector3(bx, DECK_Y + 2.72, zf - 0.11), Vector3(0.06, 0.06, 0.26), steel)
		var d := _bx(tray, Vector3(bx, DECK_Y + 2.59, zf - 0.30), Vector3(0.05, 0.30, 0.05), steel)
		d.rotation.x = deg_to_rad(34)
	for i in range(3):
		_cy(tray, Vector3(-18.5, DECK_Y + 2.84, zf - 0.15 - i * 0.07), 0.03, 18.6,
			MatLib.flat(Color(0.14, 0.13, 0.15)), Vector3(0, 0, 90))

	var cond := _wall_asm("DormWallConduit")
	_conduit_x(cond, -27.5, -9.2, DECK_Y + 2.38, zf - 0.08, 0.055)
	_conduit_x(cond, -27.5, -21.0, DECK_Y + 2.20, zf - 0.07, 0.04)

	# Small distribution board with its isolator handle.
	var db := _wall_asm("DormDistBoard")
	_bx(db, Vector3(-13.2, DECK_Y + 1.60, zf - 0.13), Vector3(0.62, 0.85, 0.22), MatLib.painted_steel())
	_bx(db, Vector3(-13.2, DECK_Y + 1.60, zf - 0.25), Vector3(0.54, 0.77, 0.03), dark)
	_bx(db, Vector3(-12.94, DECK_Y + 1.60, zf - 0.29), Vector3(0.06, 0.16, 0.06),
		MatLib.flat(Color(0.75, 0.15, 0.12)))
	_cy(db, Vector3(-13.2, DECK_Y + 2.32, zf - 0.10), 0.035, 0.28, dark)
	# The board's name plate. "DB-4" at font 20 renders 0.467 m wide and the plate under it
	# was 0.30 — and the wording was authored 0.18 m in FRONT of it besides, so it read as
	# floating white letters wider than the box they belonged to. One call now sizes both.
	_placard(db, "DB-4", Vector3(-13.2, DECK_Y + 2.10, zf - 0.12), Vector2(0.52, 0.18),
		Vector3(0, 0, -1), 20, steel, Color(0.85, 0.85, 0.8, 0.9), 0.05)

	for jx in [-24.6, -16.0]:
		var jb := _wall_asm("DormJunctionBox")
		_bx(jb, Vector3(jx, DECK_Y + 1.62, zf - 0.10), Vector3(0.28, 0.36, 0.17), dark)
		_cy(jb, Vector3(jx, DECK_Y + 2.02, zf - 0.08), 0.035, 0.52, dark)

	for dx in [-27.7, -9.6]:
		var dp := _wall_asm("DormDownpipe")
		_cy(dp, Vector3(dx, DECK_Y + 1.72, zf - 0.14), 0.085, 3.35, galv)
		for cy in [0.5, 1.7, 2.9]:
			_bx(dp, Vector3(dx, DECK_Y + cy, zf - 0.08), Vector3(0.26, 0.06, 0.10), steel)
		var shoe := _cy(dp, Vector3(dx, DECK_Y + 0.12, zf - 0.26), 0.085, 0.34, galv)
		shoe.rotation.x = deg_to_rad(-38)
		_cy(dp, Vector3(dx, DECK_Y + 3.42, zf - 0.14), 0.085, 0.24, galv, Vector3.ZERO, 0.14)
		_bx(dp, Vector3(dx, DECK_Y + 0.01, zf - 0.55), Vector3(0.5, 0.03, 0.4), MatLib.grating())

	for lx in [-25.4, -12.4]:
		var lm := _wall_asm("DormBulkheadLamp")
		_bx(lm, Vector3(lx, DECK_Y + 3.00, zf - 0.05), Vector3(0.22, 0.28, 0.05), steel)
		_bx(lm, Vector3(lx, DECK_Y + 3.00, zf - 0.20), Vector3(0.07, 0.07, 0.30), steel)
		var body := _cy(lm, Vector3(lx, DECK_Y + 2.91, zf - 0.36), 0.13, 0.22,
			MatLib.flat(Color(0.30, 0.33, 0.32)))
		body.rotation.x = deg_to_rad(90)
		_cy(lm, Vector3(lx, DECK_Y + 2.91, zf - 0.48), 0.115, 0.06,
			MatLib.flat(Color(0.95, 0.92, 0.74), true, 1.4), Vector3(90, 0, 0))
		_ring(lm, Vector3(lx, DECK_Y + 2.91, zf - 0.50), 0.11, 0.135, steel, Vector3(90, 0, 0))
		_lamp(Vector3(lx, DECK_Y + 2.91, zf - 0.44), Color(1.0, 0.92, 0.74), 3.2, 9.0)

	var sg := _wall_asm("DormWallStencils")
	_paint(sg, "ACCOMMODATION", Vector3(-22.2, DECK_Y + 2.00, zf - 0.02), 180.0, 0.0, 38,
		Color(0.11, 0.11, 0.12, 0.85))
	_paint(sg, "NO STORAGE AGAINST BULKHEAD", Vector3(-22.2, DECK_Y + 1.66, zf - 0.02),
		180.0, 0.0, 15, Color(0.13, 0.12, 0.12, 0.75))

# ============================================================ ALLEY: south band

## Pipe rack: two welded stands with three bearer tiers and bundled pipe strapped down.
func _pipe_rack() -> void:
	var a := _asm("PipeRack")
	var steel: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	var z: float = -4.85
	for sx in [-26.2, -21.4]:
		_bx(a, Vector3(sx, DECK_Y + 0.06, z), Vector3(0.42, 0.12, 2.1), steel)   # sill on deck
		for pz in [z - 0.9, z + 0.9]:
			_bx(a, Vector3(sx, DECK_Y + 0.95, pz), Vector3(0.11, 1.66, 0.11), steel)
			_bx(a, Vector3(sx, DECK_Y + 0.16, pz), Vector3(0.24, 0.06, 0.24), steel)  # foot plate
		for by in [0.47, 0.92, 1.37]:
			_bx(a, Vector3(sx, DECK_Y + by, z), Vector3(0.15, 0.09, 1.86), steel)
		var brace := _bx(a, Vector3(sx, DECK_Y + 0.95, z), Vector3(0.06, 1.9, 0.06), steel)
		brace.rotation.x = deg_to_rad(43)
	# Pipe: three tiers, thinning as it goes up. Pipes run along X between the stands.
	var pipe_x: float = -23.8
	var pipe_len: float = 6.4
	var tiers := [
		[DECK_Y + 0.635, 0.115, 7, MatLib.rusty_metal()],
		[DECK_Y + 1.075, 0.10, 6, MatLib.galvanized()],
		[DECK_Y + 1.50, 0.075, 5, MatLib.rust_steel()],
	]
	for t in tiers:
		var py: float = t[0]
		var r: float = t[1]
		var count: int = t[2]
		var pm: Material = t[3]
		var span: float = (count - 1) * (r * 2.12)
		for i in range(count):
			var pz: float = z - span * 0.5 + i * (r * 2.12)
			_cy(a, Vector3(pipe_x, py, pz), r, pipe_len, pm, Vector3(0, 0, 90))
			# Painted end caps, so the bundle reads as pipe and not as a fence.
			_cy(a, Vector3(pipe_x + pipe_len * 0.5 + 0.005, py, pz), r * 0.98, 0.02,
				MatLib.flat(Color(0.62, 0.24, 0.14)), Vector3(0, 0, 90))
		# Lashing strap over the tier at both stands.
		for sx2 in [-26.2, -21.4]:
			_bx(a, Vector3(sx2, py + r + 0.02, z), Vector3(0.05, 0.03, span + 0.26),
				MatLib.flat(Color(0.65, 0.45, 0.12)))
	_bx(a, Vector3(-20.3, DECK_Y + 0.9, z - 0.8), Vector3(0.26, 0.18, 0.02),
		MatLib.flat(Color(0.75, 0.72, 0.6)))   # rack tag
	_solid(a, Vector3(pipe_x, DECK_Y + 0.85, z), Vector3(7.2, 1.7, 2.0))

## Spill pallet with drums — the bund that catches what the shop spills.
func _drum_bund() -> void:
	var a := _asm("DrumBund")
	var galv: Material = MatLib.galvanized()
	var yellow: Material = MatLib.flat(Color(0.55, 0.47, 0.16))
	var x: float = -25.6
	var z: float = -3.25
	_bx(a, Vector3(x, DECK_Y + 0.09, z), Vector3(2.1, 0.18, 1.25), yellow)     # bund tray
	for side in [-0.6, 0.6]:
		_bx(a, Vector3(x, DECK_Y + 0.20, z + side), Vector3(2.1, 0.22, 0.06), yellow)
	for side in [-1.02, 1.02]:
		_bx(a, Vector3(x + side, DECK_Y + 0.20, z), Vector3(0.06, 0.22, 1.25), yellow)
	for i in range(4):
		_bx(a, Vector3(x - 0.75 + i * 0.5, DECK_Y + 0.20, z), Vector3(0.08, 0.04, 1.15), galv)
	var cols := [Color(0.32, 0.36, 0.30), Color(0.45, 0.24, 0.14), Color(0.28, 0.31, 0.38)]
	for i in range(3):
		var dx: float = x - 0.66 + i * 0.66
		var dm: Material = MatLib.flat(cols[i])
		_cy(a, Vector3(dx, DECK_Y + 0.66, z), 0.30, 0.86, dm)
		for ry in [0.42, 0.90]:
			_ring(a, Vector3(dx, DECK_Y + ry, z), 0.29, 0.325, MatLib.rust_steel())
		_cy(a, Vector3(dx, DECK_Y + 1.10, z), 0.30, 0.03, MatLib.rusty_metal())
		_cy(a, Vector3(dx + 0.16, DECK_Y + 1.13, z), 0.045, 0.04, galv)
	# Stencilled straight on the drum: a 0.60 m barrel face is all the width there is.
	_paint(a, "WASTE OIL", Vector3(x - 0.66, DECK_Y + 0.72, z - 0.32), 180.0, 0.0, 16,
		Color(0.88, 0.86, 0.8, 0.9), Vector2(0.54, 0.30))
	_solid(a, Vector3(x, DECK_Y + 0.6, z), Vector3(2.1, 1.2, 1.25))

## Big timber cable reel stood on edge against the shop wall.
func _cable_drum() -> void:
	var a := _asm("CableDrum")
	var wood: Material = MatLib.weathered_wood()
	var x: float = -19.9
	var z: float = -3.4
	for side in [-0.32, 0.32]:
		_cy(a, Vector3(x + side, DECK_Y + 0.86, z), 0.85, 0.07, wood, Vector3(0, 0, 90))
		for i in range(4):
			var s := _bx(a, Vector3(x + side * 1.06, DECK_Y + 0.86, z), Vector3(0.03, 1.62, 0.06), wood)
			s.rotation.x = deg_to_rad(i * 45)
	_cy(a, Vector3(x, DECK_Y + 0.86, z), 0.34, 0.58, wood, Vector3(0, 0, 90))
	for i in range(11):
		_ring(a, Vector3(x - 0.26 + i * 0.052, DECK_Y + 0.86, z), 0.36, 0.40,
			MatLib.flat(Color(0.12, 0.12, 0.14)), Vector3(0, 0, 90))
	# Chock blocks so it cannot roll — you never leave a reel free on a rig deck.
	for side in [-0.62, 0.62]:
		var ch := _bx(a, Vector3(x, DECK_Y + 0.09, z + side), Vector3(0.8, 0.18, 0.22), wood)
		ch.rotation.x = deg_to_rad(-side * 34)
	var tail := _cy(a, Vector3(x + 0.55, DECK_Y + 0.35, z - 0.55), 0.045, 1.3,
		MatLib.flat(Color(0.12, 0.12, 0.14)))
	tail.rotation = Vector3(deg_to_rad(72), deg_to_rad(30), 0)
	_solid(a, Vector3(x, DECK_Y + 0.86, z), Vector3(0.8, 1.72, 1.72))

## Caged gas bottles — the one thing that must be racked, chained and labelled.
func _gas_bottle_cage() -> void:
	var a := _asm("GasBottleCage")
	var steel: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	var x: float = -19.4
	var z: float = -4.95
	# Skid base the cage is welded to.
	_bx(a, Vector3(x, DECK_Y + 0.07, z), Vector3(2.0, 0.14, 1.45), MatLib.checker_plate())
	for cx in [-0.95, 0.95]:
		for cz in [-0.68, 0.68]:
			_bx(a, Vector3(x + cx, DECK_Y + 1.06, z + cz), Vector3(0.08, 1.86, 0.08), steel)
			_bx(a, Vector3(x + cx, DECK_Y + 0.16, z + cz), Vector3(0.2, 0.04, 0.2), steel)
	for by in [0.55, 1.15, 1.75, 1.97]:
		_bx(a, Vector3(x, DECK_Y + by, z - 0.68), Vector3(1.98, 0.05, 0.05), steel)
		_bx(a, Vector3(x, DECK_Y + by, z + 0.68), Vector3(1.98, 0.05, 0.05), steel)
		for cx2 in [-0.95, 0.95]:
			_bx(a, Vector3(x + cx2, DECK_Y + by, z), Vector3(0.05, 0.05, 1.4), steel)
	# Mesh infill, coarse enough to read at play distance.
	for i in range(9):
		var mx: float = x - 0.88 + i * 0.22
		_bx(a, Vector3(mx, DECK_Y + 1.06, z - 0.68), Vector3(0.025, 1.7, 0.025), galv)
		_bx(a, Vector3(mx, DECK_Y + 1.06, z + 0.68), Vector3(0.025, 1.7, 0.025), galv)
	# Roof bars.
	for i in range(5):
		_bx(a, Vector3(x - 0.8 + i * 0.4, DECK_Y + 1.99, z), Vector3(0.04, 0.04, 1.4), steel)
	var bottle_cols := [
		Color(0.12, 0.13, 0.14), Color(0.12, 0.13, 0.14),
		Color(0.45, 0.13, 0.10), Color(0.45, 0.13, 0.10),
		Color(0.42, 0.44, 0.46), Color(0.16, 0.34, 0.22),
	]
	for i in range(6):
		var bx2: float = x - 0.72 + (i % 3) * 0.36
		var bz: float = z - 0.3 + float(i / 3) * 0.55
		var bm: Material = MatLib.flat(bottle_cols[i])
		_cy(a, Vector3(bx2, DECK_Y + 0.80, bz), 0.115, 1.32, bm)
		_cy(a, Vector3(bx2, DECK_Y + 1.49, bz), 0.055, 0.10, galv)
		_cy(a, Vector3(bx2, DECK_Y + 1.60, bz), 0.075, 0.13, steel, Vector3.ZERO, 0.09)
	# Retaining chain across the bottles.
	for i in range(2):
		_bx(a, Vector3(x, DECK_Y + 0.95 + i * 0.42, z - 0.30), Vector3(1.4, 0.035, 0.035), galv)
	# Placard on a bolted plate (never bare text on a bar).
	_placard(a, "FLAMMABLE\n   GAS", Vector3(x + 0.45, DECK_Y + 1.45, z - 0.71),
		Vector2(1.04, 0.56), Vector3(0, 0, -1), 16, MatLib.flat(Color(0.80, 0.72, 0.18)),
		Color(0.10, 0.10, 0.10, 0.95), 0.025)
	_solid(a, Vector3(x, DECK_Y + 1.0, z), Vector3(2.0, 2.0, 1.5))

## Welding bay: skid-mounted set, bottle trolley, two screens making a corner you can
## strike an arc inside without blinding whoever walks the lane.
func _welding_bay() -> void:
	var a := _asm("WeldingBay")
	var steel: Material = MatLib.rust_steel()
	var dark: Material = MatLib.dark_metal()
	var x: float = -16.6
	var z: float = -4.55
	# Scorched deck under it.
	_bx(a, Vector3(x, DECK_Y + 0.011, z + 0.5), Vector3(1.9, 0.015, 1.5),
		MatLib.flat(Color(0.17, 0.17, 0.18, 0.7)))
	# The set on its skid.
	_bx(a, Vector3(x, DECK_Y + 0.09, z), Vector3(1.5, 0.18, 1.0), MatLib.checker_plate())
	for cx in [-0.66, 0.66]:
		_bx(a, Vector3(x + cx, DECK_Y + 0.20, z), Vector3(0.1, 0.06, 1.0), steel)
	_bx(a, Vector3(x, DECK_Y + 0.62, z), Vector3(1.15, 0.82, 0.72), MatLib.painted_steel())
	_bx(a, Vector3(x, DECK_Y + 0.62, z + 0.37), Vector3(0.95, 0.62, 0.03), dark)
	for i in range(2):
		_cy(a, Vector3(x - 0.24 + i * 0.48, DECK_Y + 0.78, z + 0.39), 0.075, 0.04, steel,
			Vector3(90, 0, 0))
		_bx(a, Vector3(x - 0.24 + i * 0.48, DECK_Y + 0.78, z + 0.41), Vector3(0.02, 0.10, 0.01),
			MatLib.flat(Color(0.85, 0.83, 0.75)))
	_bx(a, Vector3(x, DECK_Y + 0.50, z + 0.39), Vector3(0.30, 0.10, 0.02),
		MatLib.flat(Color(0.75, 0.18, 0.12)))
	# Vents in the sides.
	for i in range(5):
		_bx(a, Vector3(x - 0.58, DECK_Y + 0.45 + i * 0.085, z), Vector3(0.02, 0.05, 0.55), dark)
	_bx(a, Vector3(x, DECK_Y + 1.06, z), Vector3(0.7, 0.06, 0.5), steel)   # lifting frame
	for cx2 in [-0.32, 0.32]:
		_bx(a, Vector3(x + cx2, DECK_Y + 1.06, z), Vector3(0.05, 0.10, 0.5), steel)
	# Welding lead coiled on the hook.
	for i in range(4):
		_ring(a, Vector3(x - 0.72, DECK_Y + 0.72 - i * 0.045, z - 0.1), 0.15, 0.20,
			MatLib.flat(Color(0.11, 0.11, 0.13)), Vector3(0, 0, 90))
	_bx(a, Vector3(x - 0.62, DECK_Y + 0.90, z - 0.1), Vector3(0.05, 0.20, 0.05), steel)
	var stinger := _cy(a, Vector3(x - 0.95, DECK_Y + 0.22, z - 0.45), 0.03, 1.0,
		MatLib.flat(Color(0.11, 0.11, 0.13)))
	stinger.rotation = Vector3(deg_to_rad(80), deg_to_rad(20), 0)

	# Bottle trolley beside it.
	var tx: float = x + 1.15
	_bx(a, Vector3(tx, DECK_Y + 0.14, z), Vector3(0.52, 0.06, 0.62), steel)
	for cx3 in [-0.20, 0.20]:
		_bx(a, Vector3(tx + cx3, DECK_Y + 0.80, z - 0.24), Vector3(0.05, 1.35, 0.05), steel)
	_bx(a, Vector3(tx, DECK_Y + 1.48, z - 0.24), Vector3(0.45, 0.05, 0.05), steel)
	for cz in [-0.24, 0.24]:
		_cy(a, Vector3(tx - 0.28, DECK_Y + 0.13, z + cz * 0.6), 0.13, 0.06, dark, Vector3(0, 0, 90))
		_cy(a, Vector3(tx + 0.28, DECK_Y + 0.13, z + cz * 0.6), 0.13, 0.06, dark, Vector3(0, 0, 90))
	for i in range(2):
		var col := Color(0.12, 0.13, 0.14) if i == 0 else Color(0.45, 0.13, 0.10)
		_cy(a, Vector3(tx - 0.12 + i * 0.24, DECK_Y + 0.83, z), 0.115, 1.32, MatLib.flat(col))
		_cy(a, Vector3(tx - 0.12 + i * 0.24, DECK_Y + 1.55, z), 0.075, 0.14, steel, Vector3.ZERO, 0.09)
	_bx(a, Vector3(tx, DECK_Y + 1.05, z), Vector3(0.42, 0.04, 0.04),
		MatLib.flat(Color(0.65, 0.45, 0.12)))
	_bx(a, Vector3(tx, DECK_Y + 0.60, z), Vector3(0.42, 0.04, 0.04),
		MatLib.flat(Color(0.65, 0.45, 0.12)))

	# Two screens on castor feet, standing an L round the bay. The side leg is on the WEST
	# flank, not the east: at x + 1.62 it stood 0.32 m off the roof-ladder climb axis
	# (x -14.8), which is inside the LADDER KEEP-OUT band at the top of this file. Measured,
	# a 0.37 m player capsule could only reach 0.31 m of radius for the bottom 1.6 m of that
	# climb, and the ladder's own step-off apron ran straight through the screen. West of the
	# set it clears the gas-bottle cage by 0.28 m and the north screen by 0.23 m, and the
	# lane it actually has to shield — the alley walk at z -2.4..0.4 — is the north one.
	_welding_screen(a, Vector3(x - 0.15, DECK_Y, z + 1.30), 2.0, 0.0)
	_welding_screen(a, Vector3(x - 1.45, DECK_Y, z + 0.45), 1.4, 90.0)
	_solid(a, Vector3(x, DECK_Y + 0.6, z), Vector3(1.5, 1.2, 1.0))
	_solid(a, Vector3(tx, DECK_Y + 0.8, z), Vector3(0.55, 1.6, 0.65))

func _welding_screen(a: Node3D, base: Vector3, width: float, yaw_deg: float) -> void:
	var steel: Material = MatLib.rust_steel()
	var panel: Material = _screen_mat()
	var pivot := Node3D.new()
	a.add_child(pivot)
	pivot.position = base
	pivot.rotation.y = deg_to_rad(yaw_deg)
	var half: float = width * 0.5
	for side in [-half, half]:
		_bx(pivot, Vector3(side, 0.80, 0), Vector3(0.06, 1.60, 0.06), steel)
		_bx(pivot, Vector3(side, 0.05, 0), Vector3(0.30, 0.06, 0.6), steel)   # foot
		for cz in [-0.24, 0.24]:
			_cy(pivot, Vector3(side, 0.045, cz), 0.045, 0.04, MatLib.dark_metal(),
				Vector3(0, 0, 90))
	_bx(pivot, Vector3(0, 1.58, 0), Vector3(width, 0.06, 0.06), steel)
	_bx(pivot, Vector3(0, 0.34, 0), Vector3(width, 0.05, 0.05), steel)
	_bx(pivot, Vector3(0, 1.02, 0), Vector3(width - 0.08, 1.06, 0.02), panel)
	# Curtain rings along the top bar.
	for i in range(int(width / 0.32)):
		_ring(pivot, Vector3(-half + 0.16 + i * 0.32, 1.58, 0), 0.025, 0.045,
			MatLib.galvanized(), Vector3(90, 0, 0))
	_solid(pivot, Vector3(0, 0.82, 0), Vector3(width, 1.64, 0.14))

## Amber welding curtain — translucent PVC. One of the two materials this file adds.
var _screen_cache: StandardMaterial3D

func _screen_mat() -> StandardMaterial3D:
	if _screen_cache != null:
		return _screen_cache
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.66, 0.22, 0.07, 0.30)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.45
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_screen_cache = m
	return m

## Walked-in grime on the deck plate. Alpha-blended on purpose: MatLib.flat() sets an
## albedo alpha but never turns transparency on, so a "faded" colour from there paints
## a solid grey rectangle instead of a scuff.
var _wear_cache: StandardMaterial3D

func _muster_mat() -> StandardMaterial3D:
	if _muster_cache != null:
		return _muster_cache
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.33, 0.24, 0.72)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	_muster_cache = m
	return m

var _muster_cache: StandardMaterial3D

func _wear_mat() -> StandardMaterial3D:
	if _wear_cache != null:
		return _wear_cache
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.24, 0.25, 0.26, 0.22)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.85
	m.metallic = 0.0
	_wear_cache = m
	return m

## Caged cat ladder from the alley to the machine-shop roof — the roof kit above has
## to be reachable, or it is scenery. Stands 0.2 m off the wall on four standoffs so
## the roof slab lip does not foul the climb-out.
func _roof_ladder() -> void:
	var a := _asm("ShopRoofLadder")
	var steel: Material = MatLib.rust_steel()
	var x: float = -14.8
	var z: float = -5.55
	var l: Ladder = LADDER.new()
	l.height = 3.55
	l.display_name = "Machine Shop Roof Ladder"
	l.exit_forward = 1.35
	a.add_child(l)
	l.position = Vector3(x, DECK_Y, z)
	# YAW 180 IS LOAD-BEARING, NOT DRESSING. Ladder.face_dir() is the node's local -Z, and
	# PlayerController uses it for BOTH ends of the climb: it latches the capsule at
	# base + face_dir * 0.45 (so face_dir must point at the open air the climber's body
	# occupies) and it mantles off the top toward -face_dir (so the OPPOSITE side must be
	# the ground you step onto). Left unrotated, this ladder's -Z pointed at the shop wall
	# 0.325 m behind it: the latch put the player at z -6.00, INSIDE the north wall
	# (face -5.875, centreline -6.0) — capsule fit measured 0.00 m of radius from y19.5 to
	# y21.0, mathematically buried — and the top mantle threw them to z -4.20, which is
	# 1.55 m past the roof edge over the alley, a 3.95 m fall. Facing +Z puts the latch in
	# the alley (z -5.10, clear) and the mantle at z -6.90, 1.15 m in on the roof slab.
	# The rails, rungs and collider are all symmetric about both axes, so nothing moves.
	l.rotation.y = deg_to_rad(180)
	var rail_mat: Material = MatLib.flat(Interactable.COLOR_TAKEABLE)
	var rung_mat: Material = MatLib.flat(Color(0.75, 0.65, 0.15))
	for side in [-0.24, 0.24]:
		_bx(l, Vector3(side, 1.775, 0), Vector3(0.09, 3.55, 0.09), rail_mat)
	for i in range(11):
		_bx(l, Vector3(0, 0.16 + i * 0.32, 0), Vector3(0.56, 0.05, 0.05), rung_mat)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.7, 3.55, 0.35)
	cs.shape = sh
	l.add_child(cs)
	cs.position = Vector3(0, 1.775, 0)
	# Standoff brackets bolting the stiles back to the concrete.
	for by in [0.45, 1.55, 2.55, 3.35]:
		for side2 in [-0.24, 0.24]:
			_bx(a, Vector3(x + side2, DECK_Y + by, z - 0.16), Vector3(0.06, 0.06, 0.33), steel)
		_bx(a, Vector3(x, DECK_Y + by, z - 0.32), Vector3(0.62, 0.10, 0.04), steel)
	# SAFETY HOOPS DELETED — this is the thing the owner kept photographing.
	#
	# Three 0.8 m closed rings stood 0.42 m proud of the rungs. Geometrically that is a
	# correct cat-ladder cage (the climber goes up inside it) and it was moved out to +0.42
	# precisely so it stopped intersecting the stiles. But from the alley, which is the only
	# place you ever see this ladder from, three dark rings hang across the climb and read as
	# a cable coiled over the rungs — reported as "things blocking this ladder" more than
	# once, most recently with a screenshot and "YES IT IS".
	#
	# A cage is optional dressing on a 3.5 m ladder; an unmistakably climbable ladder is not.
	# The rings and the three cage stringers that carried them are gone. The climb-out grab
	# rails below stay, because those are what you actually haul on at the top.
	# Climb-out grab rails standing proud of the roof edge.
	for side3 in [-0.42, 0.42]:
		_bx(a, Vector3(x + side3, ROOF_Y + 0.55, z - 0.05), Vector3(0.06, 1.1, 0.06), steel)
	_bx(a, Vector3(x, ROOF_Y + 1.08, z - 0.05), Vector3(0.9, 0.055, 0.055), steel)
	for side4 in [-0.42, 0.42]:
		var kb := _bx(a, Vector3(x + side4, ROOF_Y + 0.35, z - 0.26), Vector3(0.05, 0.85, 0.05), steel)
		kb.rotation.x = deg_to_rad(40)   # z-0.26 keeps the brace proud of the wall face
	# Warning plate at eye height on the wall beside the stile.
	_placard(a, "ROOF ACCESS\n  HARNESS", Vector3(x - 0.95, DECK_Y + 1.75, SHOP_WALL_Z + 0.05),
		Vector2(1.06, 0.52), Vector3(0, 0, 1), 16, MatLib.flat(Color(0.80, 0.72, 0.18)),
		Color(0.10, 0.10, 0.10, 0.95), 0.03)

# ============================================================ ALLEY: north band

func _safety_locker() -> void:
	var a := _asm("SafetyLocker")
	var steel: Material = MatLib.rust_steel()
	var x: float = -27.2
	var z: float = 3.35
	_bx(a, Vector3(x, DECK_Y + 0.05, z), Vector3(1.1, 0.10, 0.62), steel)   # plinth kerb
	_bx(a, Vector3(x, DECK_Y + 1.05, z), Vector3(1.0, 1.90, 0.52),
		MatLib.corrugated_paint(Color(0.85, 0.74, 0.18)))
	for cx in [-0.24, 0.24]:
		_bx(a, Vector3(x + cx, DECK_Y + 1.05, z - 0.27), Vector3(0.46, 1.80, 0.02),
			MatLib.flat(Color(0.72, 0.63, 0.16)))
		for hy in [0.45, 1.05, 1.65]:
			_bx(a, Vector3(x + cx * 2.0, DECK_Y + hy, z - 0.27), Vector3(0.05, 0.13, 0.05), steel)
	_bx(a, Vector3(x - 0.02, DECK_Y + 1.05, z - 0.30), Vector3(0.10, 0.16, 0.06), steel)  # handles
	_bx(a, Vector3(x + 0.02, DECK_Y + 1.05, z - 0.30), Vector3(0.10, 0.16, 0.06), steel)
	_bx(a, Vector3(x, DECK_Y + 2.02, z), Vector3(1.04, 0.06, 0.56), steel)   # rain hood
	# (Removed the "SAFETY EQUIPMENT" label plate + text per playtest — the cabinet stays,
	# unlabelled, so it just reads as a weathered locker instead of a signed sign.)
	_solid(a, Vector3(x, DECK_Y + 1.0, z), Vector3(1.1, 2.0, 0.62))

func _hose_reel_cabinet() -> void:
	var a := _wall_asm("FireHoseReelCabinet")
	var steel: Material = MatLib.rust_steel()
	var red: Material = MatLib.red_paint()
	var x: float = -25.2
	var z: float = DORM_WALL_Z - 0.24
	# Two bolted gusset brackets carry the box off the concrete.
	for side in [-0.42, 0.42]:
		_bx(a, Vector3(x + side, DECK_Y + 0.72, DORM_WALL_Z - 0.03), Vector3(0.06, 0.30, 0.05), steel)
		_bx(a, Vector3(x + side, DECK_Y + 0.86, z), Vector3(0.05, 0.05, 0.46), steel)
		var g := _bx(a, Vector3(x + side, DECK_Y + 0.74, z + 0.05), Vector3(0.04, 0.5, 0.04), steel)
		g.rotation.x = deg_to_rad(-38)
	_bx(a, Vector3(x, DECK_Y + 1.42, z), Vector3(1.0, 1.05, 0.44), red)
	_bx(a, Vector3(x, DECK_Y + 1.42, z - 0.23), Vector3(0.86, 0.90, 0.02),
		MatLib.glass(Color(0.65, 0.75, 0.78)))
	_bx(a, Vector3(x, DECK_Y + 1.42, z - 0.225), Vector3(0.94, 0.98, 0.015), red)
	# Reel visible behind the glass.
	_cy(a, Vector3(x, DECK_Y + 1.42, z), 0.30, 0.30, MatLib.flat(Color(0.55, 0.12, 0.10)),
		Vector3(90, 0, 0))
	for i in range(4):
		_ring(a, Vector3(x, DECK_Y + 1.42, z - 0.02 - i * 0.04), 0.30 + i * 0.02, 0.34 + i * 0.02,
			MatLib.flat(Color(0.22, 0.22, 0.24)), Vector3(90, 0, 0))
	_cy(a, Vector3(x - 0.30, DECK_Y + 1.04, z - 0.20), 0.035, 0.34, MatLib.galvanized())
	_bx(a, Vector3(x, DECK_Y + 1.96, z + 0.02), Vector3(1.06, 0.06, 0.48), steel)  # hood
	_placard(a, "FIRE HOSE REEL", Vector3(x, DECK_Y + 2.05, DORM_WALL_Z - 0.03),
		Vector2(1.0, 0.28), Vector3(0, 0, -1), 16, MatLib.flat(Color(0.72, 0.15, 0.12)),
		Color(0.94, 0.92, 0.88, 0.95), 0.03)
	_solid(a, Vector3(x, DECK_Y + 1.42, z), Vector3(1.0, 1.05, 0.46))

func _eyewash_station() -> void:
	var a := _asm("EyewashStation")
	var steel: Material = MatLib.rust_steel()
	var green: Material = MatLib.flat(Color(0.14, 0.42, 0.24))
	var x: float = -23.1
	var z: float = 3.2
	_bx(a, Vector3(x, DECK_Y + 0.04, z), Vector3(0.5, 0.08, 0.5), steel)   # bolted base plate
	for cx in [-0.17, 0.17]:
		for cz in [-0.17, 0.17]:
			_cy(a, Vector3(x + cx, DECK_Y + 0.10, z + cz), 0.022, 0.06, MatLib.galvanized())
	_cy(a, Vector3(x, DECK_Y + 0.58, z), 0.055, 1.0, green)
	_cy(a, Vector3(x, DECK_Y + 1.14, z), 0.26, 0.10, MatLib.flat(Color(0.86, 0.87, 0.84)),
		Vector3.ZERO, 0.30)
	for cx2 in [-0.10, 0.10]:
		_cy(a, Vector3(x + cx2, DECK_Y + 1.22, z), 0.028, 0.09, MatLib.galvanized())
		_cy(a, Vector3(x + cx2, DECK_Y + 1.27, z), 0.045, 0.03, green)
	# Push paddle on its arm.
	_bx(a, Vector3(x, DECK_Y + 1.02, z - 0.22), Vector3(0.24, 0.05, 0.16), green)
	_bx(a, Vector3(x, DECK_Y + 1.02, z - 0.11), Vector3(0.05, 0.05, 0.14), steel)
	# Supply line up from the deck gland.
	_cy(a, Vector3(x + 0.12, DECK_Y + 0.5, z + 0.14), 0.028, 1.0, MatLib.galvanized())
	# Sign on the post — a real plate, not floating paint.
	_bx(a, Vector3(x, DECK_Y + 1.78, z + 0.01), Vector3(0.94, 0.42, 0.03), green)
	_paint(a, "EYEWASH", Vector3(x, DECK_Y + 1.80, z - 0.01), 180.0, 0.0, 16,
		Color(0.94, 0.94, 0.90, 0.95))
	_cy(a, Vector3(x, DECK_Y + 1.48, z), 0.045, 0.70, green)
	_solid(a, Vector3(x, DECK_Y + 0.9, z), Vector3(0.5, 1.8, 0.5))

func _air_hose_reel() -> void:
	var a := _wall_asm("AirHoseReel")
	var steel: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	var x: float = -21.0
	var z: float = DORM_WALL_Z - 0.36
	# Bracket frame lagged to the wall.
	_bx(a, Vector3(x, DECK_Y + 1.55, DORM_WALL_Z - 0.03), Vector3(0.7, 0.5, 0.05), steel)
	for side in [-0.28, 0.28]:
		_bx(a, Vector3(x + side, DECK_Y + 1.55, z + 0.16), Vector3(0.06, 0.06, 0.36), steel)
		var g := _bx(a, Vector3(x + side, DECK_Y + 1.36, z + 0.20), Vector3(0.05, 0.5, 0.05), steel)
		g.rotation.x = deg_to_rad(-40)
	for cx in [-0.16, 0.16]:
		for cy in [-0.18, 0.18]:
			_cy(a, Vector3(x + cx, DECK_Y + 1.55 + cy, DORM_WALL_Z - 0.06), 0.018, 0.03, galv,
				Vector3(90, 0, 0))
	# Drum and coiled hose.
	_cy(a, Vector3(x, DECK_Y + 1.55, z), 0.16, 0.30, MatLib.flat(Color(0.28, 0.42, 0.30)),
		Vector3(90, 0, 0))
	for i in range(5):
		_ring(a, Vector3(x, DECK_Y + 1.55, z), 0.18 + i * 0.045, 0.215 + i * 0.045,
			MatLib.flat(Color(0.13, 0.14, 0.15)), Vector3(90, 0, 0))
	for side2 in [-0.16, 0.16]:
		_cy(a, Vector3(x, DECK_Y + 1.55, z + side2), 0.40, 0.03,
			MatLib.flat(Color(0.30, 0.44, 0.32)), Vector3(90, 0, 0))
	_bx(a, Vector3(x + 0.44, DECK_Y + 1.55, z), Vector3(0.09, 0.09, 0.20), steel)   # crank boss
	_cy(a, Vector3(x + 0.44, DECK_Y + 1.34, z - 0.10), 0.02, 0.42, galv)
	# The tail hanging down to a hook, with its nozzle.
	var tail := _cy(a, Vector3(x - 0.30, DECK_Y + 0.90, z - 0.06), 0.035, 1.3,
		MatLib.flat(Color(0.13, 0.14, 0.15)))
	tail.rotation.z = deg_to_rad(12)
	_cy(a, Vector3(x - 0.36, DECK_Y + 0.28, z - 0.06), 0.045, 0.22, galv)
	_bx(a, Vector3(x - 0.36, DECK_Y + 0.62, DORM_WALL_Z - 0.05), Vector3(0.06, 0.06, 0.14), steel)

func _grit_bin() -> void:
	var a := _asm("GritBin")
	var steel: Material = MatLib.rust_steel()
	var yellow: Material = MatLib.corrugated_paint(Color(0.82, 0.70, 0.16))
	var x: float = -15.0
	var z: float = 3.05
	_bx(a, Vector3(x, DECK_Y + 0.06, z), Vector3(1.5, 0.12, 1.0), steel)  # bearers
	_bx(a, Vector3(x, DECK_Y + 0.52, z), Vector3(1.42, 0.80, 0.92), yellow)
	# Sloped lid, hinged at the back.
	var lid := _bx(a, Vector3(x, DECK_Y + 0.99, z - 0.03), Vector3(1.5, 0.07, 1.02),
		MatLib.flat(Color(0.72, 0.62, 0.14)))
	lid.rotation.x = deg_to_rad(-7)
	for cx in [-0.5, 0.5]:
		_bx(a, Vector3(x + cx, DECK_Y + 0.98, z + 0.46), Vector3(0.14, 0.07, 0.10), steel)
	_bx(a, Vector3(x, DECK_Y + 0.96, z - 0.49), Vector3(0.26, 0.07, 0.06), steel)   # lid handle
	for cx2 in [-0.6, 0.6]:
		_bx(a, Vector3(x + cx2, DECK_Y + 0.52, z), Vector3(0.05, 0.78, 0.94), steel)
	_paint(a, "GRIT", Vector3(x, DECK_Y + 0.58, z - 0.47), 180.0, 0.0, 16,
		Color(0.10, 0.10, 0.10, 0.9))
	# The scoop lives in the bin, handle out.
	var sc := _cy(a, Vector3(x + 0.5, DECK_Y + 1.22, z + 0.1), 0.025, 0.85,
		MatLib.weathered_wood())
	sc.rotation = Vector3(deg_to_rad(66), 0, deg_to_rad(14))
	_bx(a, Vector3(x + 0.62, DECK_Y + 0.94, z + 0.28), Vector3(0.2, 0.14, 0.24),
		MatLib.galvanized())
	_solid(a, Vector3(x, DECK_Y + 0.52, z), Vector3(1.5, 1.05, 1.02))

func _extinguisher_point() -> void:
	var a := _asm("FirePoint")
	var steel: Material = MatLib.rust_steel()
	var red: Material = MatLib.red_paint()
	var x: float = -12.3
	var z: float = 3.25
	_bx(a, Vector3(x, DECK_Y + 0.04, z), Vector3(0.9, 0.08, 0.5), steel)   # bolted base
	for cx in [-0.36, 0.36]:
		_bx(a, Vector3(x + cx, DECK_Y + 0.72, z), Vector3(0.07, 1.36, 0.07), steel)
	_bx(a, Vector3(x, DECK_Y + 1.40, z), Vector3(0.86, 0.06, 0.06), steel)
	_bx(a, Vector3(x, DECK_Y + 0.62, z + 0.06), Vector3(0.86, 0.05, 0.05), steel)
	_bx(a, Vector3(x, DECK_Y + 1.02, z + 0.17), Vector3(0.9, 0.72, 0.03), red)  # backboard
	for i in range(2):
		var ex: float = x - 0.24 + i * 0.48
		_cy(a, Vector3(ex, DECK_Y + 0.48, z), 0.10, 0.62, red)
		_cy(a, Vector3(ex, DECK_Y + 0.82, z), 0.035, 0.10, MatLib.galvanized())
		_cy(a, Vector3(ex, DECK_Y + 0.90, z), 0.055, 0.07, MatLib.dark_metal())
		_bx(a, Vector3(ex, DECK_Y + 0.55, z), Vector3(0.14, 0.08, 0.22), steel)   # strap
	# First-aid box on the same frame.
	_bx(a, Vector3(x, DECK_Y + 1.62, z), Vector3(0.42, 0.34, 0.20),
		MatLib.flat(Color(0.90, 0.90, 0.86)))
	_bx(a, Vector3(x, DECK_Y + 1.62, z - 0.11), Vector3(0.24, 0.08, 0.02),
		MatLib.flat(Color(0.16, 0.48, 0.26)))
	_bx(a, Vector3(x, DECK_Y + 1.62, z - 0.11), Vector3(0.08, 0.24, 0.02),
		MatLib.flat(Color(0.16, 0.48, 0.26)))
	_placard(a, "FIRE POINT 4", Vector3(x, DECK_Y + 1.92, z), Vector2(0.9, 0.28),
		Vector3(0, 0, -1), 16, red, Color(0.94, 0.92, 0.88, 0.95), 0.03)
	_solid(a, Vector3(x, DECK_Y + 0.9, z), Vector3(0.9, 1.9, 0.5))

## Deck cargo: two pallets, a couple of crates and a drum under a weathered tarpaulin,
## strapped down to D-rings bolted through the plating.
##
## NAME MATTERS HERE. ambience.gd's wind-sway collector classifies props by name fragment
## and "tarp" is on its list, so this assembly used to be picked up and rotated as though
## it were a loose sheet hanging in the wind. It is the opposite of that: it is a LASHED
## load, roped down at eight points to rings bolted through the deck, and the correct
## amount for it to move is none. _anchor() stops a stray rotation from throwing it across
## the sky, but it should not be classified as flapping fabric in the first place — hence
## a name that describes the load rather than the sheet over it.
func _tarped_pallets() -> void:
	var a := _asm("LashedPalletLoad")
	var wood: Material = MatLib.weathered_wood()
	var tarp: Material = MatLib.canvas(Color(0.30, 0.36, 0.33))
	var x: float = -25.6
	var z: float = 1.85
	# Two pallets, the lower one built plank by plank so the load reads as stacked.
	for lvl in range(2):
		var py: float = DECK_Y + 0.075 + lvl * 0.15
		for i in range(3):
			_bx(a, Vector3(x, py - 0.045, z - 0.55 + i * 0.55), Vector3(2.2, 0.06, 0.14), wood)
		for i in range(7):
			_bx(a, Vector3(x - 0.95 + i * 0.32, py + 0.03, z), Vector3(0.22, 0.03, 1.4), wood)
	# The load: crates and a small drum.
	_bx(a, Vector3(x - 0.5, DECK_Y + 0.60, z - 0.2), Vector3(1.0, 0.60, 0.85), wood)
	_bx(a, Vector3(x + 0.55, DECK_Y + 0.52, z + 0.15), Vector3(0.85, 0.44, 0.9), wood)
	_cy(a, Vector3(x + 0.6, DECK_Y + 1.02, z + 0.15), 0.24, 0.56,
		MatLib.flat(Color(0.35, 0.30, 0.24)))
	# Tarp over it: a shell plus four skirt panels, weathered and NOT symmetrical.
	_bx(a, Vector3(x, DECK_Y + 0.96, z), Vector3(2.34, 0.06, 1.56), tarp)
	var s1 := _bx(a, Vector3(x, DECK_Y + 0.62, z - 0.82), Vector3(2.34, 0.75, 0.05), tarp)
	s1.rotation.x = deg_to_rad(-9)
	var s2 := _bx(a, Vector3(x, DECK_Y + 0.62, z + 0.82), Vector3(2.34, 0.75, 0.05), tarp)
	s2.rotation.x = deg_to_rad(7)
	var s3 := _bx(a, Vector3(x - 1.20, DECK_Y + 0.62, z), Vector3(0.05, 0.75, 1.60), tarp)
	s3.rotation.z = deg_to_rad(8)
	var s4 := _bx(a, Vector3(x + 1.20, DECK_Y + 0.66, z), Vector3(0.05, 0.68, 1.60), tarp)
	s4.rotation.z = deg_to_rad(-11)
	# Lashings from the tarp eyelets to D-rings bolted through the deck.
	for i in range(4):
		var sx: float = x - 0.85 + i * 0.57
		for side in [-1.0, 1.0]:
			var rope := _cy(a, Vector3(sx, DECK_Y + 0.34, z + side * 0.92), 0.018, 0.85,
				MatLib.rope_mat())
			rope.rotation.x = deg_to_rad(side * 18)
			_ring(a, Vector3(sx, DECK_Y + 0.03, z + side * 1.05), 0.045, 0.075,
				MatLib.rust_steel())
			_bx(a, Vector3(sx, DECK_Y + 0.01, z + side * 1.05), Vector3(0.14, 0.02, 0.14),
				MatLib.rust_steel())
	_solid(a, Vector3(x, DECK_Y + 0.55, z), Vector3(2.4, 1.1, 1.7))

## Jockey/pump skid — a lift-in package with a certified four-point lift.
func _jockey_skid() -> void:
	var a := _asm("JockeySkid")
	var steel: Material = MatLib.rust_steel()
	var dark: Material = MatLib.dark_metal()
	var galv: Material = MatLib.galvanized()
	var x: float = -20.4
	var z: float = 1.85
	# Skid runners and cross members.
	for cz in [-0.68, 0.68]:
		_bx(a, Vector3(x, DECK_Y + 0.12, z + cz), Vector3(2.7, 0.24, 0.16), steel)
		_bx(a, Vector3(x, DECK_Y + 0.02, z + cz), Vector3(2.7, 0.04, 0.24), steel)
	for i in range(4):
		_bx(a, Vector3(x - 1.05 + i * 0.7, DECK_Y + 0.20, z), Vector3(0.14, 0.10, 1.36), steel)
	_bx(a, Vector3(x, DECK_Y + 0.27, z), Vector3(2.6, 0.05, 1.3), MatLib.checker_plate())
	# Drip tray under the pump end.
	_bx(a, Vector3(x - 0.6, DECK_Y + 0.31, z), Vector3(1.3, 0.05, 1.1),
		MatLib.flat(Color(0.26, 0.24, 0.20)))
	# Motor and pump, coupled.
	_cy(a, Vector3(x + 0.42, DECK_Y + 0.66, z), 0.28, 1.0, MatLib.flat(Color(0.22, 0.35, 0.30)),
		Vector3(0, 0, 90))
	for i in range(9):
		_ring(a, Vector3(x + 0.05 + i * 0.09, DECK_Y + 0.66, z), 0.28, 0.31,
			MatLib.flat(Color(0.20, 0.32, 0.27)), Vector3(0, 0, 90))
	_bx(a, Vector3(x + 0.42, DECK_Y + 0.30, z), Vector3(1.0, 0.10, 0.5), steel)
	_bx(a, Vector3(x - 0.15, DECK_Y + 0.62, z), Vector3(0.24, 0.20, 0.20), dark)   # coupling guard
	_cy(a, Vector3(x - 0.62, DECK_Y + 0.62, z), 0.26, 0.62, dark, Vector3(0, 0, 90))
	_cy(a, Vector3(x - 0.62, DECK_Y + 0.62, z), 0.30, 0.06, steel, Vector3(0, 0, 90))
	# Suction/discharge pipework with flanges and a hand valve.
	_cy(a, Vector3(x - 0.62, DECK_Y + 0.95, z), 0.09, 0.42, galv)
	_cy(a, Vector3(x - 0.62, DECK_Y + 1.16, z - 0.30), 0.09, 0.62, galv, Vector3(90, 0, 0))
	_cy(a, Vector3(x - 0.62, DECK_Y + 1.16, z), 0.13, 0.04, steel)
	_cy(a, Vector3(x - 0.62, DECK_Y + 1.16, z - 0.62), 0.13, 0.04, steel, Vector3(90, 0, 0))
	_ring(a, Vector3(x - 0.62, DECK_Y + 1.34, z - 0.30), 0.10, 0.17,
		MatLib.flat(Color(0.62, 0.16, 0.12)))
	_cy(a, Vector3(x - 0.62, DECK_Y + 1.26, z - 0.30), 0.03, 0.18, steel)
	_cy(a, Vector3(x - 1.05, DECK_Y + 0.62, z + 0.4), 0.075, 0.6, galv, Vector3(0, 0, 90))
	# Local control box.
	_bx(a, Vector3(x + 1.05, DECK_Y + 0.72, z + 0.4), Vector3(0.34, 0.44, 0.22),
		MatLib.painted_steel())
	_bx(a, Vector3(x + 1.05, DECK_Y + 0.72, z + 0.28), Vector3(0.28, 0.36, 0.02), dark)
	_cy(a, Vector3(x + 1.05, DECK_Y + 0.80, z + 0.26), 0.035, 0.02,
		MatLib.flat(Color(0.20, 0.75, 0.35)))
	for cx in [-0.06, 0.06]:
		_bx(a, Vector3(x + 1.05 + cx, DECK_Y + 0.62, z + 0.26), Vector3(0.04, 0.06, 0.03),
			MatLib.flat(Color(0.75, 0.16, 0.12)))
	_bx(a, Vector3(x + 1.05, DECK_Y + 0.40, z + 0.4), Vector3(0.08, 0.42, 0.08), steel)
	# Four lifting eyes and the skid plate.
	for cx2 in [-1.2, 1.2]:
		for cz2 in [-0.68, 0.68]:
			_bx(a, Vector3(x + cx2, DECK_Y + 0.30, z + cz2), Vector3(0.05, 0.16, 0.12), steel)
			_ring(a, Vector3(x + cx2, DECK_Y + 0.38, z + cz2), 0.045, 0.075, steel,
				Vector3(0, 0, 90))
	_placard(a, "P-04", Vector3(x + 0.42, DECK_Y + 0.98, z - 0.20), Vector2(0.40, 0.28),
		Vector3(0, 0, -1), 14, MatLib.flat(Color(0.78, 0.76, 0.70)),
		Color(0.12, 0.12, 0.12, 0.95), 0.02)
	_solid(a, Vector3(x, DECK_Y + 0.55, z), Vector3(2.7, 1.1, 1.45))

## Lashed cargo basket — the thing that came aboard by crane and never went back.
func _cargo_basket() -> void:
	var a := _asm("CargoBasket")
	var steel: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	var x: float = -17.1
	var z: float = 2.25
	var hw: float = 1.3     # half length (X)
	var hd: float = 0.85    # half depth (Z)
	# Skid runners with the rubber fenders round the rim.
	for cz in [-hd, hd]:
		_bx(a, Vector3(x, DECK_Y + 0.09, z + cz), Vector3(2.6, 0.18, 0.16), steel)
	_bx(a, Vector3(x, DECK_Y + 0.20, z), Vector3(2.6, 0.05, 1.7), MatLib.checker_plate())
	for cx in [-hw, hw]:
		for cz2 in [-hd, hd]:
			_bx(a, Vector3(x + cx, DECK_Y + 0.75, z + cz2), Vector3(0.09, 1.30, 0.09), steel)
	for by in [0.55, 1.02, 1.36]:
		_bx(a, Vector3(x, DECK_Y + by, z - hd), Vector3(2.6, 0.05, 0.05), steel)
		_bx(a, Vector3(x, DECK_Y + by, z + hd), Vector3(2.6, 0.05, 0.05), steel)
		for cx2 in [-hw, hw]:
			_bx(a, Vector3(x + cx2, DECK_Y + by, z), Vector3(0.05, 0.05, 1.7), steel)
	for i in range(11):
		var mx: float = x - 1.2 + i * 0.24
		_bx(a, Vector3(mx, DECK_Y + 0.78, z - hd), Vector3(0.025, 1.2, 0.025), galv)
		_bx(a, Vector3(mx, DECK_Y + 0.78, z + hd), Vector3(0.025, 1.2, 0.025), galv)
	# Rubber fender round the top rail.
	_bx(a, Vector3(x, DECK_Y + 1.42, z - hd), Vector3(2.68, 0.10, 0.12),
		MatLib.flat(Color(0.14, 0.14, 0.15)))
	_bx(a, Vector3(x, DECK_Y + 1.42, z + hd), Vector3(2.68, 0.10, 0.12),
		MatLib.flat(Color(0.14, 0.14, 0.15)))
	# Contents: timber, a rope coil, two small drums, a bundle of scaffold tube.
	for i in range(4):
		_bx(a, Vector3(x - 0.5, DECK_Y + 0.28 + i * 0.09, z - 0.3),
			Vector3(2.0, 0.08, 0.9), MatLib.weathered_wood())
	for i in range(3):
		_cy(a, Vector3(x + 0.55, DECK_Y + 0.34 + i * 0.11, z + 0.35), 0.30, 0.10,
			MatLib.rope_mat())
	for i in range(2):
		_cy(a, Vector3(x - 1.0 + i * 0.45, DECK_Y + 0.55, z + 0.42), 0.19, 0.60,
			MatLib.flat(Color(0.33, 0.36, 0.30)))
	for i in range(5):
		_cy(a, Vector3(x + 0.3, DECK_Y + 0.72 + (i % 2) * 0.09, z - 0.55 + i * 0.11), 0.045, 2.0,
			galv, Vector3(0, 0, 90))
	# Four-leg sling gathered at a master link, hooked over the corner eyes.
	for cx3 in [-hw, hw]:
		for cz3 in [-hd, hd]:
			_ring(a, Vector3(x + cx3, DECK_Y + 1.44, z + cz3), 0.05, 0.085, steel,
				Vector3(0, 0, 90))
			var leg := _cy(a, Vector3(x + cx3 * 0.5, DECK_Y + 1.78, z + cz3 * 0.5), 0.022, 1.15,
				MatLib.flat(Color(0.30, 0.31, 0.33)))
			leg.rotation = Vector3(atan2(cz3 * 0.5, 0.68) * -1.0, 0.0, atan2(cx3 * 0.5, 0.68))
	_ring(a, Vector3(x, DECK_Y + 2.14, z), 0.09, 0.15, steel, Vector3(90, 0, 0))
	# Lashed down to deck D-rings — nothing on this rig is left un-lashed.
	for cx4 in [-1.05, 1.05]:
		for cz4 in [-1.0, 1.0]:
			var strap := _bx(a, Vector3(x + cx4 * 1.06, DECK_Y + 0.55, z + cz4 * 1.02),
				Vector3(0.05, 1.15, 0.05), MatLib.flat(Color(0.68, 0.48, 0.12)))
			strap.rotation.x = deg_to_rad(-cz4 * 16)
			strap.rotation.z = deg_to_rad(cx4 * 8)
			_ring(a, Vector3(x + cx4 * 1.12, DECK_Y + 0.03, z + cz4 * 1.12), 0.045, 0.075, steel)
			_bx(a, Vector3(x + cx4 * 1.12, DECK_Y + 0.01, z + cz4 * 1.12),
				Vector3(0.14, 0.02, 0.14), steel)
	_placard(a, "BASKET 07\n1250 kg", Vector3(x + 0.9, DECK_Y + 1.10, z - hd - 0.06),
		Vector2(0.78, 0.46), Vector3(0, 0, -1), 13, MatLib.flat(Color(0.80, 0.78, 0.70)),
		Color(0.11, 0.11, 0.11, 0.95), 0.02)
	_solid(a, Vector3(x, DECK_Y + 0.75, z), Vector3(2.7, 1.5, 1.8))

## The mustering point: painted square, sign post, tally board.
func _muster_point() -> void:
	var a := _asm("MusterPoint")
	var steel: Material = MatLib.rust_steel()
	var green: Material = MatLib.flat(Color(0.20, 0.34, 0.25))
	var deck_green: Material = _muster_mat()
	var white: Material = MatLib.flat(Color(0.62, 0.63, 0.59))
	var x: float = -11.2
	var z: float = 1.85
	var y: float = DECK_Y + 0.013
	_bx(a, Vector3(x, y, z), Vector3(2.7, 0.02, 2.7), deck_green)
	for side in [-1.3, 1.3]:
		_bx(a, Vector3(x + side, y + 0.003, z), Vector3(0.09, 0.02, 2.7), white)
		_bx(a, Vector3(x, y + 0.003, z + side), Vector3(2.7, 0.02, 0.09), white)
	# The paint is walked off in the middle, like every muster square on every rig.
	for i in range(5):
		var w := _bx(a, Vector3(x + _rng.randf_range(-0.9, 0.9), y + 0.006,
			z + _rng.randf_range(-0.9, 0.9)),
			Vector3(_rng.randf_range(0.4, 0.9), 0.015, _rng.randf_range(0.3, 0.8)), _wear_mat())
		w.rotation.y = _rng.randf_range(0.0, TAU)
	_paint(a, "MUSTER B", Vector3(x, y + 0.008, z + 0.85), 0.0, -90.0, 32,
		Color(0.86, 0.88, 0.84, 0.85), Vector2(2.4, 0.6))
	# Sign post on a bolted base plate.
	var px: float = x + 1.35
	var pz: float = z + 1.35
	_bx(a, Vector3(px, DECK_Y + 0.03, pz), Vector3(0.34, 0.06, 0.34), steel)
	for cx in [-0.11, 0.11]:
		for cz in [-0.11, 0.11]:
			_cy(a, Vector3(px + cx, DECK_Y + 0.08, pz + cz), 0.02, 0.06, MatLib.galvanized())
	_cy(a, Vector3(px, DECK_Y + 1.15, pz), 0.05, 2.24, MatLib.flat(Color(0.55, 0.57, 0.56)))
	_bx(a, Vector3(px, DECK_Y + 1.95, pz - 0.03), Vector3(0.78, 0.56, 0.04), green)
	_bx(a, Vector3(px, DECK_Y + 1.95, pz - 0.055), Vector3(0.70, 0.48, 0.01), white)
	_bx(a, Vector3(px, DECK_Y + 1.95, pz - 0.06), Vector3(0.64, 0.42, 0.005), green)
	_paint(a, "MUSTER\nSTATION B", Vector3(px, DECK_Y + 2.06, pz - 0.07), 180.0, 0.0, 16,
		Color(0.93, 0.94, 0.90, 0.95), Vector2(0.58, 0.37))   # inner green field is 0.64 x 0.42
	# Tally board below it, with the hooks the tags hang on.
	_bx(a, Vector3(px, DECK_Y + 1.35, pz - 0.03), Vector3(0.62, 0.44, 0.04),
		MatLib.flat(Color(0.42, 0.36, 0.26)))
	for i in range(6):
		var hx: float = px - 0.24 + (i % 3) * 0.24
		var hy: float = DECK_Y + 1.46 - float(i / 3) * 0.18
		_cy(a, Vector3(hx, hy, pz - 0.07), 0.008, 0.05, MatLib.galvanized(), Vector3(90, 0, 0))
		if i != 2 and i != 4:
			_bx(a, Vector3(hx, hy - 0.06, pz - 0.075), Vector3(0.05, 0.08, 0.006),
				MatLib.flat(Color(0.82, 0.80, 0.72)))
	_solid(a, Vector3(px, DECK_Y + 1.1, pz), Vector3(0.16, 2.2, 0.16))

# ============================================================ ROOF: machine shop

## Handrail round the whole roof edge, with a gap at the ladder climb-out (x -15.8..-14.2
## on the north run) so you can actually step off the rungs.
func _roof_handrails() -> void:
	var a := _asm("RoofHandrail")
	var x0: float = ROOF_X0 + 0.25
	var x1: float = ROOF_X1 - 0.25
	var z0: float = ROOF_Z0 + 0.25
	var z1: float = ROOF_Z1 - 0.30
	_handrail(a, Vector3(x0, ROOF_Y, z0), Vector3(x1, ROOF_Y, z0))          # south
	_handrail(a, Vector3(x0, ROOF_Y, z0), Vector3(x0, ROOF_Y, z1))          # west
	_handrail(a, Vector3(x1, ROOF_Y, z0), Vector3(x1, ROOF_Y, z1))          # east
	_handrail(a, Vector3(x0, ROOF_Y, z1), Vector3(-15.8, ROOF_Y, z1))       # north, west of gap
	# East of the gap is only 0.3 m — a single stanchion, not a run.
	_bx(a, Vector3(-14.2, ROOF_Y + 0.545, z1), Vector3(0.07, 1.09, 0.07), MatLib.rust_steel())
	_bx(a, Vector3(-14.2, ROOF_Y + 0.015, z1), Vector3(0.2, 0.03, 0.2), MatLib.rust_steel())
	_bx(a, Vector3(-14.5, ROOF_Y + 1.07, z1), Vector3(0.65, 0.055, 0.055), MatLib.rust_steel())
	# Hazard paint at the climb-out.
	for i in range(4):
		var c := _bx(a, Vector3(-16.0 + i * 0.5, ROOF_Y + 0.012, z1 + 0.30),
			Vector3(0.18, 0.02, 0.9), MatLib.flat(Color(0.72, 0.62, 0.12)))
		c.rotation.y = deg_to_rad(30)
	# Lightning-protection tape round the parapet line.
	_bx(a, Vector3((x0 + x1) * 0.5, ROOF_Y + 0.02, z0 - 0.12), Vector3(x1 - x0, 0.02, 0.05),
		MatLib.flat(Color(0.62, 0.55, 0.32)))
	_bx(a, Vector3(x0 - 0.12, ROOF_Y + 0.02, (z0 + z1) * 0.5), Vector3(0.05, 0.02, z1 - z0),
		MatLib.flat(Color(0.62, 0.55, 0.32)))

## Grating walkway linking the climb-out to every plant item — nobody walks on a roof
## membrane, they walk on the strip somebody laid for them.
func _roof_walkway() -> void:
	var a := _asm("RoofWalkway")
	var grate: Material = MatLib.grating()
	var steel: Material = MatLib.rust_steel()
	# Main run east-west just inboard of the north edge.
	_bx(a, Vector3(-20.4, ROOF_Y + 0.14, -7.30), Vector3(12.4, 0.06, 1.0), grate)
	# Spur running south to the generator.
	_bx(a, Vector3(-24.6, ROOF_Y + 0.14, -12.4), Vector3(1.0, 0.06, 9.2), grate)
	# Bearers under both.
	for i in range(8):
		_bx(a, Vector3(-26.2 + i * 1.7, ROOF_Y + 0.055, -7.30), Vector3(0.1, 0.11, 1.0), steel)
	for i in range(6):
		_bx(a, Vector3(-24.6, ROOF_Y + 0.055, -16.6 + i * 1.7), Vector3(1.0, 0.11, 0.1), steel)
	# Kerb edging, so the strip reads as a laid walkway rather than a painted rectangle.
	for side in [-0.53, 0.53]:
		_bx(a, Vector3(-20.4, ROOF_Y + 0.16, -7.30 + side), Vector3(12.4, 0.10, 0.04), steel)
		_bx(a, Vector3(-24.6 + side, ROOF_Y + 0.16, -12.4), Vector3(0.04, 0.10, 9.2), steel)

## Diesel gen-set in an acoustic housing with a real exhaust route.
func _generator_set() -> void:
	var a := _asm("RoofGeneratorSet")
	var steel: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	var housing_mat: Material = MatLib.corrugated_paint(Color(0.62, 0.66, 0.62))
	var x: float = -21.0
	var z: float = -15.1
	# Concrete plinth, then anti-vibration mounts, then the package.
	var plinth_top: float = ROOF_Y + 0.35
	_bx(a, Vector3(x, ROOF_Y + 0.175, z), Vector3(4.6, 0.35, 2.4), MatLib.concrete())
	_bx(a, Vector3(x, plinth_top + 0.02, z), Vector3(4.4, 0.04, 2.2), MatLib.checker_plate())
	for cx in [-1.9, 1.9]:
		for cz in [-0.9, 0.9]:
			_cy(a, Vector3(x + cx, plinth_top + 0.10, z + cz), 0.09, 0.16,
				MatLib.flat(Color(0.16, 0.16, 0.18)))
			_bx(a, Vector3(x + cx, plinth_top + 0.19, z + cz), Vector3(0.26, 0.03, 0.26), steel)
	var base: float = plinth_top + 0.21
	_bx(a, Vector3(x, base + 1.05, z), Vector3(4.2, 2.1, 2.0), housing_mat)
	_bx(a, Vector3(x, base + 2.13, z), Vector3(4.3, 0.08, 2.1), steel)          # capping
	# Acoustic louvres on both long faces.
	for cz2 in [-1.01, 1.01]:
		for i in range(9):
			var lv := _bx(a, Vector3(x - 1.55 + i * 0.39, base + 1.35, z + cz2),
				Vector3(0.33, 0.34, 0.05), MatLib.flat(Color(0.34, 0.37, 0.36)))
			lv.rotation.x = deg_to_rad(18 * signf(cz2))
	# Access door with hinges, handle and a lock hasp.
	_bx(a, Vector3(x + 2.11, base + 1.0, z - 0.5), Vector3(0.03, 1.75, 0.85), MatLib.painted_steel())
	for hy in [0.45, 1.55]:
		_bx(a, Vector3(x + 2.13, base + hy, z - 0.90), Vector3(0.05, 0.12, 0.06), steel)
	_bx(a, Vector3(x + 2.15, base + 1.0, z - 0.16), Vector3(0.05, 0.20, 0.05), steel)
	# Control panel with a live readout.
	_bx(a, Vector3(x + 2.12, base + 1.35, z + 0.72), Vector3(0.05, 0.60, 0.80), MatLib.dark_metal())
	_bx(a, Vector3(x + 2.15, base + 1.50, z + 0.72), Vector3(0.02, 0.18, 0.44),
		MatLib.flat(Color(0.12, 0.30, 0.18)))
	for i in range(3):
		_cy(a, Vector3(x + 2.15, base + 1.18, z + 0.50 + i * 0.22), 0.035, 0.02,
			MatLib.flat(Color(0.72, 0.62, 0.14)), Vector3(0, 0, 90))
	# Lifting lugs on the roof of the package.
	for cx2 in [-1.7, 1.7]:
		for cz3 in [-0.75, 0.75]:
			_bx(a, Vector3(x + cx2, base + 2.24, z + cz3), Vector3(0.06, 0.16, 0.14), steel)
			_ring(a, Vector3(x + cx2, base + 2.31, z + cz3), 0.04, 0.07, steel, Vector3(0, 0, 90))
	# Exhaust: bellows off the package, a lagged riser, a stack, a rain cap, a stay.
	var sx: float = x + 1.55
	var sz: float = z - 0.6
	_cy(a, Vector3(sx, base + 2.28, sz), 0.17, 0.30, MatLib.dark_metal())
	for i in range(3):
		_ring(a, Vector3(sx, base + 2.20 + i * 0.10, sz), 0.17, 0.22, galv)
	_cy(a, Vector3(sx, base + 3.10, sz), 0.23, 1.35, MatLib.flat(Color(0.72, 0.72, 0.68)))
	for i in range(4):
		_ring(a, Vector3(sx, base + 2.55 + i * 0.36, sz), 0.23, 0.255, galv)
	_cy(a, Vector3(sx, base + 4.55, sz), 0.155, 1.55, MatLib.flat(Color(0.30, 0.26, 0.24)))
	_cy(a, Vector3(sx, base + 5.36, sz), 0.20, 0.06, steel)
	_cy(a, Vector3(sx, base + 5.50, sz), 0.24, 0.22, steel, Vector3.ZERO, 0.06)   # rain cap
	for i in range(3):
		var cs := _bx(a, Vector3(sx, base + 5.42, sz), Vector3(0.03, 0.20, 0.03), steel)
		cs.rotation.y = deg_to_rad(i * 60)
	var stay := _bx(a, Vector3(sx - 0.55, base + 3.60, sz), Vector3(1.15, 0.05, 0.05), steel)
	stay.rotation.z = deg_to_rad(-24)
	_bx(a, Vector3(sx - 1.1, base + 3.35, sz), Vector3(0.14, 0.5, 0.05), steel)
	# Day tank on its own stand, piped to the package.
	var tx: float = x - 2.75
	_bx(a, Vector3(tx, ROOF_Y + 0.06, z + 0.4), Vector3(1.0, 0.12, 1.0), steel)
	for cx3 in [-0.36, 0.36]:
		for cz4 in [-0.36, 0.36]:
			_bx(a, Vector3(tx + cx3, ROOF_Y + 0.45, z + 0.4 + cz4), Vector3(0.07, 0.66, 0.07), steel)
	_cy(a, Vector3(tx, ROOF_Y + 1.20, z + 0.4), 0.42, 1.15, MatLib.flat(Color(0.34, 0.40, 0.36)))
	_cy(a, Vector3(tx, ROOF_Y + 1.80, z + 0.4), 0.42, 0.05, steel)
	_cy(a, Vector3(tx + 0.2, ROOF_Y + 1.88, z + 0.4), 0.06, 0.12, galv)
	_cy(a, Vector3(tx + 0.9, ROOF_Y + 0.95, z + 0.4), 0.055, 1.1, galv, Vector3(0, 0, 90))
	_cy(a, Vector3(tx + 1.42, ROOF_Y + 1.25, z + 0.4), 0.055, 0.65, galv)
	_bx(a, Vector3(tx, ROOF_Y + 1.35, z - 0.44), Vector3(0.58, 0.28, 0.02),
		MatLib.flat(Color(0.80, 0.78, 0.70)))
	_paint(a, "DIESEL", Vector3(tx, ROOF_Y + 1.37, z - 0.46), 180.0, 0.0, 15,
		Color(0.11, 0.11, 0.11, 0.95))
	# Package placard.
	_bx(a, Vector3(x - 1.0, base + 1.75, z + 1.02), Vector3(1.34, 0.32, 0.02),
		MatLib.flat(Color(0.80, 0.78, 0.70)))
	_paint(a, "GEN SET 2  85 kVA", Vector3(x - 1.0, base + 1.77, z + 1.04), 0.0, 0.0, 14,
		Color(0.11, 0.11, 0.11, 0.95))
	_solid(a, Vector3(x, base + 1.05, z), Vector3(4.2, 2.3, 2.0))
	_solid(a, Vector3(tx, ROOF_Y + 1.2, z + 0.4), Vector3(0.9, 2.4, 0.9))

## Two extract/HVAC packages on plinths, ducted together.
func _hvac_units() -> void:
	var a := _asm("RoofHVAC")
	var steel: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	var panel: Material = MatLib.corrugated_paint(Color(0.66, 0.68, 0.66))
	# --- big supply unit ---
	var x: float = -25.6
	var z: float = -10.6
	_bx(a, Vector3(x, ROOF_Y + 0.15, z), Vector3(2.8, 0.30, 2.2), MatLib.concrete())
	var b1: float = ROOF_Y + 0.30
	_bx(a, Vector3(x, b1 + 0.62, z), Vector3(2.5, 1.24, 1.9), panel)
	_bx(a, Vector3(x, b1 + 1.27, z), Vector3(2.6, 0.06, 2.0), steel)
	for i in range(7):
		var lv := _bx(a, Vector3(x - 1.26, b1 + 0.30 + i * 0.13, z),
			Vector3(0.04, 0.11, 1.5), MatLib.flat(Color(0.36, 0.38, 0.38)))
		lv.rotation.z = deg_to_rad(16)
	_bx(a, Vector3(x + 1.26, b1 + 0.62, z), Vector3(0.04, 0.9, 1.2), MatLib.dark_metal())
	# Cowl, fan and bird guard on top.
	_cy(a, Vector3(x - 0.45, b1 + 1.52, z), 0.58, 0.44, galv)
	_cy(a, Vector3(x - 0.45, b1 + 1.76, z), 0.62, 0.06, steel)
	for i in range(5):
		var bl := _bx(a, Vector3(x - 0.45, b1 + 1.62, z), Vector3(0.46, 0.03, 0.14), galv)
		bl.rotation.y = deg_to_rad(i * 36)
		bl.rotation.z = deg_to_rad(24)
	for i in range(6):
		var gd := _bx(a, Vector3(x - 0.45, b1 + 1.79, z), Vector3(1.16, 0.02, 0.02), steel)
		gd.rotation.y = deg_to_rad(i * 30)
	_ring(a, Vector3(x - 0.45, b1 + 1.79, z), 0.55, 0.60, steel)
	# Vibration mounts and hold-down bolts.
	for cx in [-1.1, 1.1]:
		for cz in [-0.8, 0.8]:
			_cy(a, Vector3(x + cx, b1 + 0.05, z + cz), 0.07, 0.10,
				MatLib.flat(Color(0.16, 0.16, 0.18)))
	# --- smaller extract unit ---
	var x2: float = -25.6
	var z2: float = -8.35
	_bx(a, Vector3(x2, ROOF_Y + 0.13, z2), Vector3(1.9, 0.26, 1.6), MatLib.concrete())
	var b2: float = ROOF_Y + 0.26
	_bx(a, Vector3(x2, b2 + 0.48, z2), Vector3(1.6, 0.96, 1.35), panel)
	_bx(a, Vector3(x2, b2 + 0.99, z2), Vector3(1.7, 0.06, 1.45), steel)
	_cy(a, Vector3(x2, b2 + 1.22, z2), 0.40, 0.40, galv)
	_cy(a, Vector3(x2, b2 + 1.44, z2), 0.44, 0.05, steel)
	_ring(a, Vector3(x2, b2 + 1.47, z2), 0.38, 0.43, steel)
	# Duct linking the two, on a stool.
	_bx(a, Vector3(x2, b2 + 0.62, z2 - 1.02), Vector3(0.7, 0.55, 0.70), galv)
	_bx(a, Vector3(x2, b2 + 0.62, z2 - 1.75), Vector3(0.7, 0.55, 0.80), galv)
	for i in range(3):
		_bx(a, Vector3(x2, b2 + 0.62, z2 - 1.30 - i * 0.30), Vector3(0.76, 0.61, 0.04), steel)
	_bx(a, Vector3(x2, ROOF_Y + 0.18, z2 - 1.5), Vector3(0.10, 0.36, 0.10), steel)
	_bx(a, Vector3(x2, ROOF_Y + 0.02, z2 - 1.5), Vector3(0.28, 0.04, 0.28), steel)
	_bx(a, Vector3(x2 + 0.9, b2 + 0.48, z2 + 0.02), Vector3(0.34, 0.24, 0.02),
		MatLib.flat(Color(0.80, 0.78, 0.70)))
	_paint(a, "EF-2", Vector3(x2 + 0.9, b2 + 0.50, z2 + 0.04), 0.0, 0.0, 14,
		Color(0.11, 0.11, 0.11, 0.95))
	_solid(a, Vector3(x, b1 + 0.65, z), Vector3(2.6, 1.5, 2.0))
	_solid(a, Vector3(x2, b2 + 0.5, z2), Vector3(1.7, 1.2, 1.45))

## Mushroom vents on kerbs — the small punctuation between the big packages.
func _vent_mushrooms() -> void:
	var a := _asm("RoofVents")
	var galv: Material = MatLib.galvanized()
	var steel: Material = MatLib.rust_steel()
	var spots := [
		Vector3(-18.2, 0, -16.4), Vector3(-16.6, 0, -13.4),
		Vector3(-18.6, 0, -10.6), Vector3(-21.4, 0, -8.9),
	]
	var scale_by := [1.0, 0.82, 0.95, 0.72]
	for i in range(spots.size()):
		var p: Vector3 = spots[i]
		var s: float = scale_by[i]
		_cy(a, Vector3(p.x, ROOF_Y + 0.09, p.z), 0.44 * s, 0.18, MatLib.concrete())
		_cy(a, Vector3(p.x, ROOF_Y + 0.20, p.z), 0.40 * s, 0.06, steel)
		_cy(a, Vector3(p.x, ROOF_Y + 0.48, p.z), 0.28 * s, 0.52, galv)
		_cy(a, Vector3(p.x, ROOF_Y + 0.80, p.z), 0.52 * s, 0.14, galv)
		_cy(a, Vector3(p.x, ROOF_Y + 0.92, p.z), 0.52 * s, 0.20, galv, Vector3.ZERO, 0.10 * s)
		for j in range(4):
			var st := _bx(a, Vector3(p.x, ROOF_Y + 0.72, p.z), Vector3(0.03, 0.22, 0.03), steel)
			st.rotation.y = deg_to_rad(j * 45)
		_solid(a, Vector3(p.x, ROOF_Y + 0.5, p.z), Vector3(0.9 * s, 1.0, 0.9 * s))

## Comms mast: lattice on a bolted baseplate, guyed, carrying whips, a dipole, a dish
## and the aviation warning light. This is the shape the rig reads by from the water.
func _comms_mast() -> void:
	var a := _asm("RoofCommsMast")
	var steel: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	var x: float = -26.4
	var z: float = -16.6
	var base_y: float = ROOF_Y
	# Plinth + baseplate + holding-down bolts.
	_bx(a, Vector3(x, base_y + 0.14, z), Vector3(1.4, 0.28, 1.4), MatLib.concrete())
	_bx(a, Vector3(x, base_y + 0.31, z), Vector3(1.0, 0.06, 1.0), steel)
	for cx in [-0.38, 0.38]:
		for cz in [-0.38, 0.38]:
			_cy(a, Vector3(x + cx, base_y + 0.39, z + cz), 0.028, 0.12, galv)
			_cy(a, Vector3(x + cx, base_y + 0.46, z + cz), 0.045, 0.04, steel)
	# Lattice: four legs, X-braced.
	var mast_h: float = 9.0
	var foot: float = base_y + 0.34
	var half: float = 0.24
	for cx2 in [-half, half]:
		for cz2 in [-half, half]:
			_bx(a, Vector3(x + cx2, foot + mast_h * 0.5, z + cz2),
				Vector3(0.06, mast_h, 0.06), steel)
	var bays: int = 9
	for i in range(bays):
		var y0: float = foot + i * (mast_h / bays)
		var y1: float = y0 + mast_h / bays
		var ym: float = (y0 + y1) * 0.5
		var diag: float = sqrt(pow(mast_h / bays, 2.0) + pow(half * 2.0, 2.0))
		var ang: float = rad_to_deg(atan2(half * 2.0, mast_h / bays))
		# Girts.
		for cz3 in [-half, half]:
			_bx(a, Vector3(x, y1, z + cz3), Vector3(half * 2.0, 0.04, 0.04), steel)
		for cx3 in [-half, half]:
			_bx(a, Vector3(x + cx3, y1, z), Vector3(0.04, 0.04, half * 2.0), steel)
		# Diagonals on the two faces you see from the deck.
		var d1 := _bx(a, Vector3(x, ym, z - half), Vector3(0.035, diag, 0.035), steel)
		d1.rotation.z = deg_to_rad(ang if i % 2 == 0 else -ang)
		var d2 := _bx(a, Vector3(x + half, ym, z), Vector3(0.035, diag, 0.035), steel)
		d2.rotation.x = deg_to_rad(-ang if i % 2 == 0 else ang)
	var top: float = foot + mast_h
	_bx(a, Vector3(x, top + 0.03, z), Vector3(0.60, 0.06, 0.60), steel)
	# Guy wires to three bolted anchor eyes on the roof.
	var guy_y: float = foot + mast_h * 0.72
	for i in range(3):
		var ang2: float = deg_to_rad(90.0 + i * 120.0)
		var ax: float = x + cos(ang2) * 1.95
		var az: float = z + sin(ang2) * 1.95
		_bx(a, Vector3(ax, base_y + 0.02, az), Vector3(0.28, 0.04, 0.28), steel)
		_ring(a, Vector3(ax, base_y + 0.12, az), 0.045, 0.075, steel, Vector3(0, 0, 90))
		_bx(a, Vector3(ax, base_y + 0.09, az), Vector3(0.07, 0.14, 0.07), steel)
		var mid := Vector3((ax + x) * 0.5, (base_y + 0.12 + guy_y) * 0.5, (az + z) * 0.5)
		var len_g: float = Vector3(ax - x, base_y + 0.12 - guy_y, az - z).length()
		var w := _cy(a, mid, 0.016, len_g, MatLib.flat(Color(0.42, 0.44, 0.45)))
		w.look_at_from_position(mid, Vector3(x, guy_y, z), Vector3.UP)
		w.rotate_object_local(Vector3(1, 0, 0), deg_to_rad(90))
		# Turnbuckle down at the anchor.
		var tb := _cy(a, mid.lerp(Vector3(ax, base_y + 0.12, az), 0.78), 0.045, 0.28, galv)
		tb.rotation = w.rotation
	# Whip antennas on standoff brackets.
	for i in range(3):
		var wy: float = foot + 6.4 + i * 0.75
		var side: float = -half - 0.22 if i % 2 == 0 else half + 0.22
		_bx(a, Vector3(x + side * 0.5, wy, z), Vector3(absf(side), 0.05, 0.05), steel)
		_bx(a, Vector3(x + side, wy, z), Vector3(0.08, 0.14, 0.08), MatLib.dark_metal())
		var whip := _cy(a, Vector3(x + side, wy + 1.35, z), 0.018, 2.6,
			MatLib.flat(Color(0.82, 0.80, 0.74)))
		whip.rotation.z = deg_to_rad(-4.0 if i % 2 == 0 else 4.0)
	# Dipole: crossbar with two elements.
	var dy: float = foot + 8.3
	_bx(a, Vector3(x, dy, z), Vector3(2.6, 0.05, 0.05), steel)
	for side2 in [-1.15, 1.15]:
		_bx(a, Vector3(x + side2, dy, z), Vector3(0.08, 0.12, 0.08), MatLib.dark_metal())
		_cy(a, Vector3(x + side2, dy + 0.62, z), 0.016, 1.15, galv)
		_cy(a, Vector3(x + side2, dy - 0.55, z), 0.016, 1.0, galv)
	# Small dish on an arm, looking west-southwest.
	var qy: float = foot + 4.6
	_bx(a, Vector3(x - half - 0.35, qy, z), Vector3(0.7, 0.06, 0.06), steel)
	_bx(a, Vector3(x - half - 0.62, qy - 0.18, z), Vector3(0.08, 0.36, 0.08), steel)
	var dish := _cy(a, Vector3(x - 1.35, qy, z + 0.22), 0.62, 0.20,
		MatLib.flat(Color(0.78, 0.78, 0.74)), Vector3.ZERO, 0.14)
	dish.rotation = Vector3(deg_to_rad(-72), deg_to_rad(28), 0)
	for i in range(3):
		var st2 := _bx(a, Vector3(x - 1.52, qy + 0.06, z + 0.30), Vector3(0.02, 0.52, 0.02), steel)
		st2.rotation = Vector3(deg_to_rad(-72 + i * 12), deg_to_rad(28), deg_to_rad(-14 + i * 14))
	_cy(a, Vector3(x - 1.66, qy + 0.14, z + 0.36), 0.055, 0.16, MatLib.dark_metal())
	# Cable bundle down the mast into a gland box on the roof.
	_cy(a, Vector3(x + half + 0.06, foot + 4.4, z - half - 0.06), 0.05, 8.6,
		MatLib.flat(Color(0.13, 0.13, 0.15)))
	_bx(a, Vector3(x + half + 0.06, base_y + 0.30, z - half - 0.06), Vector3(0.28, 0.42, 0.24),
		MatLib.dark_metal())
	# Aviation warning light, inside its own lens.
	_cy(a, Vector3(x, top + 0.16, z), 0.11, 0.20, MatLib.dark_metal())
	_sp(a, Vector3(x, top + 0.31, z), 0.11, MatLib.glowing(Color(0.85, 0.13, 0.10), 2.6))
	for i in range(3):
		var cg := _bx(a, Vector3(x, top + 0.31, z), Vector3(0.02, 0.26, 0.02), steel)
		cg.rotation.y = deg_to_rad(i * 60)
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.24, 0.16)
	beacon.light_energy = 1.6
	beacon.omni_range = 7.0
	beacon.shadow_enabled = false
	a.add_child(beacon)
	beacon.position = Vector3(x, top + 0.31, z)
	_solid(a, Vector3(x, foot + mast_h * 0.5, z), Vector3(0.56, mast_h, 0.56))

## Satcom radome on a bolted tripod.
func _radome() -> void:
	var a := _asm("RoofRadome")
	var steel: Material = MatLib.rust_steel()
	var x: float = -16.4
	var z: float = -9.6
	# Triangular base frame bolted down.
	for i in range(3):
		var ang: float = deg_to_rad(90.0 + i * 120.0)
		var ang2: float = deg_to_rad(90.0 + (i + 1) * 120.0)
		var p1 := Vector3(x + cos(ang) * 0.62, ROOF_Y + 0.05, z + sin(ang) * 0.62)
		var p2 := Vector3(x + cos(ang2) * 0.62, ROOF_Y + 0.05, z + sin(ang2) * 0.62)
		var mid: Vector3 = (p1 + p2) * 0.5
		var seg := _bx(a, mid, Vector3(0.07, 0.07, p1.distance_to(p2)), steel)
		seg.rotation.y = atan2(p2.x - p1.x, p2.z - p1.z)
		_bx(a, p1 + Vector3(0, -0.03, 0), Vector3(0.24, 0.04, 0.24), steel)
		# Leg raking inward to the collar.
		var leg := _bx(a, p1.lerp(Vector3(x, ROOF_Y + 1.02, z), 0.5),
			Vector3(0.07, p1.distance_to(Vector3(x, ROOF_Y + 1.02, z)), 0.07), steel)
		leg.look_at_from_position(leg.position, Vector3(x, ROOF_Y + 1.02, z), Vector3.UP)
		leg.rotate_object_local(Vector3(1, 0, 0), deg_to_rad(90))
	_cy(a, Vector3(x, ROOF_Y + 1.08, z), 0.38, 0.20, MatLib.dark_metal())
	_cy(a, Vector3(x, ROOF_Y + 1.20, z), 0.44, 0.08, steel)
	var dome := _sp(a, Vector3(x, ROOF_Y + 1.30, z), 0.56, MatLib.flat(Color(0.78, 0.78, 0.74)))
	dome.scale = Vector3(1.0, 0.94, 1.0)
	_ring(a, Vector3(x, ROOF_Y + 1.30, z), 0.55, 0.60, MatLib.flat(Color(0.56, 0.56, 0.53)))
	_bx(a, Vector3(x + 0.42, ROOF_Y + 1.10, z + 0.34), Vector3(0.22, 0.26, 0.16),
		MatLib.dark_metal())
	_cy(a, Vector3(x + 0.42, ROOF_Y + 0.56, z + 0.34), 0.045, 1.0,
		MatLib.flat(Color(0.13, 0.13, 0.15)))
	_placard(a, "SATCOM", Vector3(x, ROOF_Y + 0.86, z - 0.48), Vector2(0.62, 0.26),
		Vector3(0, 0, -1), 13, MatLib.flat(Color(0.80, 0.78, 0.70)),
		Color(0.11, 0.11, 0.11, 0.95), 0.02)
	_solid(a, Vector3(x, ROOF_Y + 0.95, z), Vector3(1.3, 1.9, 1.3))

## Trays tying the roof plant back to the mast base — plant that isn't wired is a model.
func _roof_cable_trays() -> void:
	var a := _asm("RoofCableTrays")
	_tray_run(a, Vector3(-26.3, ROOF_Y, -15.4), Vector3(-23.1, ROOF_Y, -15.4), 0.42)
	_tray_run(a, Vector3(-23.1, ROOF_Y, -15.4), Vector3(-23.1, ROOF_Y, -9.6), 0.42)
	_tray_run(a, Vector3(-23.1, ROOF_Y, -9.6), Vector3(-16.4, ROOF_Y, -9.6), 0.42)
	_tray_run(a, Vector3(-24.4, ROOF_Y, -9.6), Vector3(-24.4, ROOF_Y, -8.4), 0.42)

func _roof_signage() -> void:
	var a := _asm("RoofSignage")
	var steel: Material = MatLib.rust_steel()
	var x: float = -17.6
	var z: float = -6.5
	_bx(a, Vector3(x, ROOF_Y + 0.03, z), Vector3(0.3, 0.06, 0.3), steel)
	_cy(a, Vector3(x, ROOF_Y + 0.80, z), 0.04, 1.5, MatLib.flat(Color(0.55, 0.57, 0.56)))
	# (Removed the "FALL HAZARD / CLIP ON" sign board + text per playtest — it cluttered
	# the roof-ladder head; the slim stanchion stays as a plain fall-arrest post.)
	_solid(a, Vector3(x, ROOF_Y + 0.8, z), Vector3(0.12, 1.6, 0.12))
