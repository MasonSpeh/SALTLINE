extends Node3D
## Water-level overhaul: turns the Z1 wet deck from a bare slab into a working
## pontoon-top machine space, built to offshore reference — boat landing with
## fender frame and tidal ladder, SW mooring station with windlass and stud-link
## chain, west pipe gallery (green seawater main + red fire main), pump skids,
## the under-deck girder ceiling fifteen meters overhead, vents, W.T. hatches,
## bilge gutters, tide-stain bands, escape-route signage, and scattered salvage.
## All coordinates are absolute (the node sits at origin like the other builders).

const SignFit = preload("res://scripts/world/sign_fit.gd")   # by path: class cache lags new files
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

## pitch_deg tips the paint out of vertical: pass -90 to lay a marking FLAT on decking,
## rather than standing it up in the plating with half the glyph buried.
## `fit` is the panel this marking has to live inside, in metres (x = width, y = height,
## 0 on either axis = unconstrained): the font shrinks until the wording fits. See
## sign_fit.gd — a hand-picked font size cannot be right for two different words.
func _plabel(text: String, pos: Vector3, yaw_deg: float, font_size: int = 30,
		color: Color = Color(0.82, 0.83, 0.8), pitch_deg: float = 0.0,
		fit: Vector2 = Vector2.ZERO) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = SignFit.fit_size(text, fit.x, fit.y, font_size)
	if fit != Vector2.ZERO:
		l.set_meta("sign_face", fit)   # asserted by tests/label_anchor_probe.gd
	l.pixel_size = 0.01
	var _wear: float = clampf((color.r + color.g + color.b) / 3.0, 0.0, 1.0)   # black stencil paint
	var _k: float = lerpf(0.06, 0.17, _wear)
	l.modulate = Color(_k, _k, _k * 1.08, minf(color.a, 0.9))
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # paint does not turn to face you
	add_child(l)
	l.position = pos
	l.rotation.y = deg_to_rad(yaw_deg)
	l.rotation.x = deg_to_rad(pitch_deg)

## A stencilled sign backed by a bolted plate: draws a dark placard directly behind the
## label's own text face (along its back direction) so the marking reads as printed on a
## real object rather than floating. Pass the same yaw/pitch you would pass _plabel.
func _signplate(text: String, pos: Vector3, yaw_deg: float, font_size: int, color: Color,
		w: float, h: float, pitch_deg: float = 0.0) -> void:
	# SIGNAGE RULE: the passed w/h are MINIMUMS — the plate is grown to fit the text plus
	# margins so the wording never clips or overflows the plate. The extent is MEASURED
	# (sign_fit.gd), not estimated from a per-character average: the old 0.58 em guess ran
	# up to 14% under the truth on real upper-case wording, which is a plate too small.
	var ext: Vector2 = SignFit.extent(text, font_size)
	w = maxf(w, ext.x + 0.12)
	h = maxf(h, ext.y + 0.10)
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	var back: Vector3 = -b.z.normalized()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, 0.03)
	bm.material = MatLib.dark_metal()
	mi.mesh = bm
	add_child(mi)
	mi.position = pos + back * 0.03
	mi.rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)
	_plabel(text, pos, yaw_deg, font_size, color, pitch_deg, Vector2(w, h))

func _readable(id: String, name_: String, pos: Vector3, size: Vector3 = Vector3(0.35, 0.45, 0.06)) -> Readable:
	var r := Readable.new()
	r.readable_id = id
	r.display_name = name_
	add_child(r)
	r.global_position = pos
	r.build_visual(size)
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
	# Rested by the visual-geometry settle pass (see support_index.gd), not by a physics
	# raycast: half this deck's dressing is non-colliding, so a ray reports the plating
	# under a bench rather than the bench.
	t.add_to_group("settle_me")
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
	# A flat untextured tan box reads as an un-authored placeholder beside this rig's
	# textured steel and timber. Loot crates are timber; give them timber.
	c.build_box_visual(Vector3(1.1, 0.8, 0.8), Color(0.5, 0.45, 0.3), false, true,
		MatLib.weathered_wood())
	c.add_to_group("settle_me")
	return c

# ---------------------------------------------------------------- boat landing

## The dock face the SPHL fetched up against: fender frame stood off the deck
## edge, rubbing strips, a tidal ladder into the swell, lifebuoy, line-thrower.
func _boat_landing() -> void:
	var y: float = WET_Y
	var dark: Material = MatLib.dark_metal()
	# The dock landing sits EAST of the SPHL (x 23–28) so the pod's hatch exit at
	# x~20 is clear — the player steps off the gangplank onto open deck, and the
	# fender frame / boarding ladder are a separate dock section beside the pod.
	#
	# THE FENDER POSTS ARE THE "BLANK YELLOW BLOCK ON THE SPAWNDECK", reported three times.
	# Each was 3.0 m of 0.4 m tube in `MatLib.flat(Color(0.75, 0.65, 0.15))` — one flat
	# untextured fill, no texture, no detail, nothing to interact with. From the wet-deck
	# respawn at (20, 2.6, −19) the near one is 4.9 m away and 43° off axis, where perspective
	# stretches it to ~3.3% of the whole frame: the single most prominent object in the view
	# the player opens their eyes on, and the only unpainted-looking thing in it.
	#
	# It resisted two rounds of searching because `rig_batcher.gd` WELDS all this dressing into
	# `MergedDressing` ArrayMeshes with a shared white-albedo material, so no per-node walk over
	# albedo_color can see it at all — only reading the rendered PIXELS found it
	# (tests/SpawnYellow.tscn). And that colour is `hazard_stripe()`'s own fallback tint, i.e.
	# the fallback was hand-written where the material was meant, exactly as on rig_builder's
	# gangplank bollards.
	#
	# The frame itself is real structure — the tie tubes, rubbing strips and boarding ladder all
	# hang off it — so the posts stay and get their material instead: weathered steel full
	# height, with a hazard-painted visibility band at deck level and a second at the top, a
	# galvanised cap, and a weld collar at the splash line. That is how a real fender post is
	# finished, and there is no flat fill left anywhere on it.
	for fx in [23.5, 27.9]:
		_dcyl(Vector3(fx, y - 1.5, -22.3), 0.2, 3.0, MatLib.rust_steel())
		_dcyl(Vector3(fx, y + 1.5, -22.3), 0.2, 3.0, MatLib.rusty_metal())
		_dcyl(Vector3(fx, y + 0.02, -22.3), 0.212, 0.10, dark)              # weld collar, splash line
		for band in [0.62, 2.62]:
			_dcyl(Vector3(fx, y + band, -22.3), 0.209, 0.44, MatLib.hazard_stripe())
		_dcyl(Vector3(fx, y + 3.02, -22.3), 0.22, 0.05, MatLib.galvanized())  # cap
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
	# Nameplate on the bracket post, below the ring, facing the deck — was floating text
	# above the ring with nothing behind it.
	_signplate("LIFEBUOY", Vector3(28.4, y + 0.95, -21.72), 0, 12, Color(0.88, 0.88, 0.84), 0.8, 0.22)
	# LINE-THROWING SET — and THIS is "the box, near the crate" (owner, 2026-07-29, after the
	# fender posts above were fixed: "did you get the box, near the crate? Its within a few
	# Meters of it"). It was ONE `MatLib.flat(Color(0.85, 0.45, 0.1))` BoxMesh, 0.5 x 0.3 x 0.3,
	# at (26.7, 2.16, −20.5) — 2.69 m from the Dock Locker at (28.6, 2.0, −18.6), on open deck
	# plate, in the walk from the gangplank to the stair tower. Untextured, unlit-looking, hard
	# edged, one colour on all six faces: against a textured tread plate it reads as an
	# un-authored block, which is the same complaint and the same cause as the posts —
	# `MatLib.flat()` used as a paint can when it is documented as being for LIT LENSES.
	#
	# Found the same way the posts were, because a node walk still cannot see it (rig_batcher
	# welds it, and its own material never appears on any MergedDressing chunk): the rendered
	# PIXELS at the crate, then the camera's own projection to name the object —
	# (26.7, 2.16, −20.5) projects to pixel (848, 319) of the frame the blob sits at (830, 310)
	# in, from the vantage 2.4 m east of the crate. See tests/SpawnYellow.tscn.
	#
	# KEPT, not deleted: every boat landing carries a line-throwing appliance, it is labelled,
	# and it belongs beside the ladder and the lifebuoy. So it gets a material and a shape
	# instead. `sphl_orange()` is the rig's own international-orange GRP over brushed metal —
	# the survival-craft material, which is exactly what a rescue appliance is made of — and a
	# proud lid, a seam, two galvanised toggle clasps and a rubber carry handle turn a cuboid
	# into a piece of equipment. No flat fill left on it.
	var lt := Vector3(26.7, y + 0.15, -20.5)
	_dbox(lt, Vector3(0.5, 0.3, 0.3), MatLib.sphl_orange())
	_dbox(lt + Vector3(0, 0.165, 0), Vector3(0.53, 0.04, 0.33), MatLib.sphl_orange())  # proud lid
	_dbox(lt + Vector3(0, 0.14, 0), Vector3(0.51, 0.012, 0.31), dark)                  # lid seam
	for cx in [-0.15, 0.15]:
		_dbox(lt + Vector3(cx, 0.1, 0.153), Vector3(0.07, 0.11, 0.02), MatLib.galvanized())
	var lt_h := _dcyl(lt + Vector3(0, 0.2, 0), 0.014, 0.22, dark)
	lt_h.rotation.z = deg_to_rad(90)                                                   # carry handle
	for hx in [-0.1, 0.1]:
		_dbox(lt + Vector3(hx, 0.19, 0), Vector3(0.02, 0.035, 0.02), MatLib.galvanized())
	_plabel("LINE THROWER", Vector3(26.7, y + 0.2, -20.34), 180, 10, Color(0.92, 0.92, 0.88),
		0.0, Vector2(0.46, 0.12))   # the case lid is 0.53 x 0.30
	# Dock locker — first honest loot of the game, off to the side of the landing.
	#
	# PULLED 1 m INBOARD (z -19.6 -> -18.6). The crate is 1.1 x 0.8 x 0.8 and settles to
	# x 28.05..29.15, z -20.0..-19.2; rig_builder's tide-line drum row puts a 0.45 m
	# rusted drum at (28.6, -20.2), spanning x 28.15..29.05, z -20.65..-19.75. That is
	# 0.90 x 0.80 x 0.25 m of the crate INSIDE the drum — 0.18 m3, by far the largest
	# clip on the wet deck. The drums are a deliberate run along the south deck edge, so
	# the single crate moves rather than the row. At z -18.6 the crate clears the drum by
	# 0.75 m, still stands on deck plate (measured y 2.000 under it, base settles to
	# 2.005) and still sits off to the side of the landing, out of the walk from the
	# gangplank across to the stair tower.
	_crate(["rope", "flare", "sealed_tin"], "Dock Locker", Vector3(28.6, y + 0.01, -18.6))
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
	# THE BRAKE LEVER WAS THE FLOATING BAR. It was authored at a hand-typed y + 0.95 with
	# nothing under it: 80 mm square, 0.7 m long, raked 25 deg, its foot hanging 316 mm
	# clear of the bedplate top — by a wide margin the most isolated object anywhere on
	# the wet deck (the runner-up clears 122 mm), and red, so it read from the whole
	# south dock as a thin bar floating over the mooring platform. Everything below is
	# DERIVED from the bedplate's own top face, so it cannot drift again: pedestal on the
	# plate, ratchet quadrant, pin through it, and the lever hung off the pin.
	var bed_top: float = y + 0.30                       # bedplate: centre y+0.15, 0.30 thick
	var pivot := Vector3(9.3, bed_top + 0.24, -23.5)
	_dbox(Vector3(pivot.x, (bed_top + pivot.y) * 0.5, pivot.z),
		Vector3(0.14, pivot.y - bed_top, 0.20), rust)                        # pedestal
	var quad := _dcyl(pivot + Vector3(0.055, 0, 0), 0.17, 0.025, rust)
	quad.rotation.z = deg_to_rad(90)                                          # ratchet quadrant
	var pin := _dcyl(pivot, 0.032, 0.20, MatLib.galvanized())
	pin.rotation.z = deg_to_rad(90)                                           # pivot pin
	var rake: float = deg_to_rad(-25)
	var arm: Vector3 = Vector3(0, cos(rake), sin(rake))   # the lever's own +Y, once raked
	var lever := _dbox(pivot + arm * 0.29, Vector3(0.08, 0.7, 0.08), MatLib.red_paint())
	lever.rotation.x = rake
	var grip := _dcyl(pivot + arm * 0.60, 0.045, 0.14, dark)
	grip.rotation.x = rake                                                    # hand grip
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
	# A message-in-a-bottle the gyre washed against the dock — survivors from Rig 6, the
	# sea turning every boat back down the line. The world is bigger than this rig.
	_readable("bottle_note", "Note in a Bottle", Vector3(13.6, y + 0.14, -23.7), Vector3(0.1, 0.26, 0.1))
	var gun := _dcyl(Vector3(11.6, y + 0.56, -24.85), 0.04, 0.35, MatLib.red_paint())
	gun.rotation.z = deg_to_rad(90)
	# Snap-back warning where the platform meets the deck.
	_plabel("MOORING STATION 4-SW — STAY CLEAR · SNAP-BACK ZONE",
		Vector3(13.0, y + 2.3, -22.14), 180, 20, Color(0.8, 0.68, 0.2), 0.0,
		Vector2(5.5, 0.0))

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
	# Stencil plate ON the seawater main. It was authored at x 9.3 against a pipe of
	# radius 0.19 on the axis x 9.0 — so the plate's inner face sat at x 9.255 and the
	# pipe's skin at 9.19, leaving a 1.65 x 0.26 m plate hanging 65 mm off the pipe in
	# open air. Derived from the pipe now, and carried on two saddle clips.
	var sea_r: float = 0.19
	var sea_x: float = 9.0
	var plate_x: float = sea_x + sea_r + 0.03    # _signplate seats the plate at pos - 0.03
	_signplate("SW MAIN — GRAVITY FEED", Vector3(plate_x, y + 1.0, -16.5), 90, 12,
		Color(0.75, 0.78, 0.72), 1.5, 0.24)
	for cz2 in [-0.62, 0.62]:
		_dbox(Vector3(sea_x + sea_r * 0.5, y + 1.0, -16.5 + cz2),
			Vector3(sea_r + 0.06, 0.1, 0.05), MatLib.rust_steel())   # saddle clips
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
		# Bolted nameplate on the pump-skid front. An earlier pass moved this in Z onto the
		# skid face but LEFT IT AT y+0.9 — and the only thing at that z is the 0.18 m skid
		# base, so a 1.9 x 0.28 m plate hung 0.58 m clear in open air with nothing behind it.
		# From the north bay it read as a floating railing panel over the deck/leg overlap.
		# Now the skid carries a real END PLATE standing on its own base and the stencil is
		# bolted to the face of that, 1 cm proud so the two never z-fight.
		_box(Vector3(p.x, y + 0.35, p.z - 0.55), Vector3(1.9, 0.34, 0.05), MatLib.painted_steel())
		for bx in [-0.82, 0.82]:                                        # corner bolts
			var bolt := _dcyl(Vector3(p.x + bx, y + 0.35, p.z - 0.59), 0.02, 0.03,
				MatLib.galvanized())
			bolt.rotation.x = deg_to_rad(90)
		_signplate(s[2], Vector3(p.x, y + 0.35, p.z - 0.63), 180, 12, Color(0.85, 0.85, 0.78), 1.9, 0.28)

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
	#
	# THE FIRST ONE WAS STANDING IN THE STORE ROOM'S DOOR LANE. It was at (12.5, -15.0):
	# measured off the live scan it occupies x 12.41..12.59, y 2.00..3.06 — one metre due
	# north of a doorway whose CLEAR opening is x 12.39..13.61, so it stood in the western
	# 0.20 m of the approach and left 12.59..13.61 = 1.02 m of lane, under the 1.09 m
	# (0.74 m capsule + 0.35 m comfort) tests/declutter_probe.gd asks of a route. Being a
	# `_dcyl` it has no collider either, so you walked through it. That doorway is now a
	# deliberate duck-under (rig_builder._loot_door_duck) and a crouched body is exactly as
	# wide as a standing one, so the lane had to come clear.
	#
	# Moved 1.2 m WEST into the alley between the two rooms, where it is still a tank vent
	# on the same service run beside the pipe-rack stand at x 11.0, and where the scan
	# reports a 0.35 m cylinder from y 2.00 to 3.15 hitting NOTHING. Nearest authored fauna
	# home (the DeckGull at 24.0, -15.5) is 12.71 m away — the s33 plan that dropped a prop
	# on a gull is the reason that gets checked rather than assumed.
	for vp in [Vector3(11.3, y, -15.05), Vector3(19.2, y, -2.6)]:
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
	# Terse stencil laid FLAT on the hatch lid, in three short lines that fit the 0.84m
	# lid (the old single-line sign was 3m of text with nothing behind it). The lid backs it.
	_plabel("W.T. HATCH\n4-SW\nKEEP CLOSED", Vector3(14.8, y + 0.37, -18.2), 180, 9, Color(0.88, 0.88, 0.82), -90)
	# Bilge gutters along the deck edges.
	_dbox(Vector3(8.22, y + 0.015, -10.0), Vector3(0.24, 0.03, 23.6), MatLib.dark_metal())
	_dbox(Vector3(12.0, y + 0.015, -21.86), Vector3(7.6, 0.03, 0.24), MatLib.dark_metal())
	# Escape-route signage — photoluminescent green, the offshore lingua franca.
	# It rode the header over the pump room's ready-room ARCHWAY; s36 walled that opening
	# up (owner: "reove the 2nd backdoor"), so it is now painted high on a solid east face.
	# Left at y + 2.85 rather than dropped to eye level on purpose: that clears the top of
	# the three pipe risers on this face (y + 0.2 .. y + 2.7) by 0.15 m, and the sign is
	# read from out on the deck, not from arm's length.
	_plabel("ESCAPE ROUTE → STAIRS", Vector3(18.2, y + 2.85, -10.0), 90, 18, Color(0.55, 0.9, 0.6))
	_plabel("↑ MUSTER STATION B — TOPSIDE", Vector3(21.86, y + 2.0, -2.5), -90, 16, Color(0.55, 0.9, 0.6))
	# Ballast tank stencil on the caisson's west face.
	_plabel("W.B.T. 4-SE", Vector3(18.96, y + 3.5, -12.0), -90, 26, Color(0.7, 0.72, 0.68))

# ---------------------------------------------------------------- stair entry

## Frame the tower door so the way up reads from across the deck.
func _stair_entry() -> void:
	var y: float = WET_Y
	# The real doorway this frames is cut by _wall()/DOORFRAME.build in rig_builder.gd
	# at door_h = min(OPEN_H, shell_h) = 2.2m, so its cased top sits at y+2.2. These
	# hazard jambs were authored 2.3m tall (top at y+2.3) with the lintel starting
	# there — 0.1m (DOORFRAME.HEAD) too high, leaving a gap between the real frame's
	# head and the underside of the striped lintel above it. Both are shifted down
	# by that same 0.1m so the striping actually cases the opening instead of
	# floating over it.
	const GAP_FIX: float = -0.1
	for jx in [22.85, 24.35]:
		_dbox(Vector3(jx, y + 1.15 + GAP_FIX, -6.0), Vector3(0.18, 2.3, 0.32), MatLib.hazard_stripe())
	_dbox(Vector3(23.6, y + 2.4 + GAP_FIX, -6.0), Vector3(1.7, 0.2, 0.32), MatLib.hazard_stripe())
	_box(Vector3(23.6, y + 0.02, -6.65), Vector3(1.5, 0.04, 0.9), MatLib.checker_plate(), false)
	_plabel("STAIRS → TOPSIDE DECK", Vector3(23.6, y + 2.75 + GAP_FIX, -6.18), 180, 20, Color(0.88, 0.88, 0.84))
	# Dead caged lamp over the door.
	_dbox(Vector3(23.6, y + 3.2, -6.22), Vector3(0.22, 0.28, 0.14), MatLib.dark_metal())
	_dcyl(Vector3(23.6, y + 3.2, -6.3), 0.08, 0.1, MatLib.glass(Color(0.8, 0.85, 0.8)))
	# POWER WAYFINDING (players kept reaching nightfall never knowing the deck
	# lights had to be restored, or that the way up is this same door). The tower
	# door is the one funnel every player passes; the power story and the route
	# up are posted right on it. (These render as weathered charcoal stencil, not amber:
	# _plabel paints every label through _paint_black — the amber source only sets how
	# faded the lettering reads. Wayfinding here is by content and placement, not colour.)
	_plabel("MAIN POWER OFF", Vector3(26.8, y + 2.55 + GAP_FIX, -6.13), 180, 17, Color(0.95, 0.72, 0.2))
	_plabel("BREAKER ROOM 4-A - TOWER LVL 2", Vector3(26.8, y + 2.15 + GAP_FIX, -6.13), 180, 12, Color(0.95, 0.72, 0.2))
	# Steel notice board bolted beside the door, facing the deck - the full story.
	_dbox(Vector3(27.9, y + 1.5, -6.12), Vector3(0.62, 0.82, 0.05), MatLib.galvanized())
	_readable("breaker_notice", "Station Notice - Main Power", Vector3(27.9, y + 1.5, -6.16), Vector3(0.5, 0.66, 0.04))
	# THE FEED-CABLE SPOOL — moved here from the stair-tower machinery room so the player
	# finds it down low, near spawn, and carries it UP to Breaker 4-A.
	#
	# It was at (15.4, -9.6), which cleared the pump and the door and still sat IN THE
	# ARCHWAY LANE — a takeable on the floor of the one crossing the room had. It moved into
	# the SE corner bay, which rig_builder._pump_room_plant keeps clear of the walk. s36
	# walled that archway up and there is only the south door now, so the spool is no longer
	# the first lit thing seen from the arch — it is 1.14 m east of the door lane's edge, on
	# the plating just inside the threshold, which is the same job done from one opening.
	_takeable("cable_spool", "Cable Spool", Vector3(16.0, y + 0.05, -13.1))

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
	# A working flashlight on the dock crate by the pod, where the player lands — the
	# wet deck is the first dark space they cross, so the torch meets them there. Select
	# it in the hotbar and press F to click the beam on/off. More are stashed in the
	# dark rooms (pump room, store room, machine shop) below.
	_takeable("flashlight", "Flashlight", Vector3(18.4, y + 0.05, -22.4))
	# The fishing rod — propped in the storeroom where a rigger left it. The other
	# half of the food economy, waiting behind the first door most players open.
	_takeable("fishing_rod", "Fishing Rod", Vector3(11.0, y + 0.05, -17.2))
	# A second rod and a prybar, PROPPED against the store-room east wall beside the tool
	# chest — a tidy tool corner on the walk from the respawn. They used to stand in the
	# open at (17.6/22.4, -18.6), and a free-standing rod with nothing under or behind it
	# reads as a floating glitch (owner report: "standing up with no support in middle of
	# wetdeck"). The rod's visual leans 14° toward -x, so based 0.4m off the wall face
	# (x16.125) its tip grazes the wall and it reads as leant, not levitating.
	# The rod that used to stand here is GONE (owner, 2026-07-30: "remove the fishing rod found
	# right away… the player should have to find that one, or the one in the rec room,
	# encourages exploration before fishing"). It was on the open plate outside the store-room
	# east wall, i.e. on the walk from the respawn — the first thing found and the whole food
	# economy handed over before the player had opened a door. The prybar stays: it was not
	# what the owner named, and it is what opens the doors the other two rods are behind.
	_takeable("prybar", "Prybar", Vector3(16.3, y + 0.05, -17.1))
	# The Fisherman's Handbook beside it: every species, its hours, its weather tier, its
	# water, its depth and what it wants on the hook — read against the same table the rod
	# actually rolls. Unlike every other readable on this rig it is a real object: [E] reads
	# it where it lies, [F] pockets it, and it can be set down at whatever rail you fish.
	# See scripts/components/handbook.gd.
	# SEATED ON THE PLATE, not floating over it. This was y + 0.62 with nothing underneath —
	# the one Readable in the world that BOTH auto-correctors decline: it has no SurfaceSnap,
	# and it is not in the "settle_me" group, so neither the snap pass nor SupportIndex ever
	# looked at it. + 0.21 puts the propped book's underside on the wet-deck plate at y 2.0,
	# which is what SupportIndex.settle() independently measured for this XZ.
	preload("res://scripts/components/handbook.gd").place_origin(self, Vector3(11.7, y + 0.21, -16.6))
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
	# Kelp belongs in the wet ground the sea actually reaches, not on the main walking
	# lane — it used to sit in the middle of the entry platform (x23, z-15.8, right on
	# the walk between the SPHL and the stair tower). Moved south of the loot room's
	# back wall (z-22), the open wet patch behind the Z1 buildings, so it reads as
	# something the current left behind rather than deck litter underfoot.
	_takeable("kelp_bundle", "Kelp Snag", Vector3(14.0, y + 0.05, -23.4))
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
