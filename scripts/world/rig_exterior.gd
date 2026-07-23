class_name RigExterior extends Node3D
## Phase 2 — the exterior silhouette pass. Expands the rig's skyline and deck
## clutter into a working offshore platform: the high-iron mast becomes a full
## drilling derrick with a drill floor and pipe deck, a flare boom cantilevers
## off the southwest corner, containers and davits dress the south deck, an
## observation platform hangs off the west edge, and an external switchback
## stair climbs the Stack's west face to the C-deck terrace.

const STAIRS := preload("res://scripts/world/stair_kit.gd")   # by path: class cache lags new files

const DECK_Y: float = 18.0
const C_Y: float = 25.1

func _ready() -> void:
	_derrick()
	_pipe_deck()
	_containers()
	_flare_boom()
	_davits()
	_obs_platform()
	_west_stairs()
	# Place-Codex beacons: the derrick floor and the empty davits file a journal entry
	# the first time the player stands near them (same pattern as the fire barrel).
	_beacon("place_derrick", Vector3(TOWER.x, DECK_Y + 1.0, TOWER.z), 7.0)
	_beacon("place_davits", Vector3(-10.5, DECK_Y + 1.1, -18.8), 6.0)

## Drop an invisible proximity beacon that discovers a place-Codex entry once near.
func _beacon(codex_id: String, pos: Vector3, radius: float) -> void:
	var b: Node3D = preload("res://scripts/world/landmark_beacon.gd").new()
	b.set("codex_id", codex_id)
	b.set("radius", radius)
	add_child(b)
	b.global_position = pos

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

## Align a node's local +Y along a->b, positioned at the midpoint.
func _align_y(node: Node3D, a: Vector3, b: Vector3) -> void:
	node.global_position = (a + b) * 0.5
	var d: Vector3 = (b - a).normalized()
	var up := Vector3(0, 0, 1) if absf(d.y) > 0.99 else Vector3.UP
	node.look_at(node.global_position + d, up)
	node.rotate_object_local(Vector3.RIGHT, -PI / 2)

func _member(a: Vector3, b: Vector3, thickness: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(thickness, a.distance_to(b), thickness)
	m.material = mat
	mi.mesh = m
	add_child(mi)
	_align_y(mi, a, b)

func _ramp(from: Vector3, to: Vector3, width: float, mat: Material) -> void:
	var b := CSGBox3D.new()
	b.size = Vector3(width, 0.22, from.distance_to(to))
	b.material = mat
	b.use_collision = true
	add_child(b)
	b.global_position = (from + to) * 0.5
	b.look_at(to, Vector3.UP)

## Offshore rail grammar: top rail + mid rail + kick plate at the deck. The mid
## rail and toe board are what make a catwalk read as regulation rig, not fence.
##
## COLLISION is deliberately NOT the visual rail: every bar and post here is visual
## only and the guard the player actually touches is one smooth slab (see
## _rail_slab). These rails used to collide as a single 0.1m bar at waist height with
## open air above and below it, and a 0.4m-radius capsule pressed into that gap
## wedges between the bar and the deck edge with no way to walk out.
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
## not own; every visual it builds is kept and only collision shapes are touched.
##
## 1. THE CURB. StairKit's flat top lip is a plate at full `rise` beginning 0.25m back
##    along the run, where the sloped surface is still 0.25*tan(angle) lower — a 0.15m
##    square step across the top tread of this stair. A capsule of this radius rolls
##    up about 0.117m before the contact normal tips past floor_max_angle and the step
##    reads as a wall, so the climb simply stops there. Sliding the lip past the top of
##    the ramp leaves the join flush to ~0.03m.
## 2. THE RAIL. StairKit's handrail collides as one thin bar at chest height with open
##    air beneath it, so a capsule's waist catches the bar while its feet slide under.
##    We drop that collider and stand a single smooth slab inside the visual rail.
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

## pitch_deg tips the paint out of vertical: pass -90 to lay a marking FLAT on decking.
## Without it a stencil authored at deck height renders as an upright sheet standing in
## the plating with part of the glyph buried below it, not as paint.
func _plabel(text: String, pos: Vector3, yaw_deg: float, font_size: int = 30,
		color: Color = Color(0.82, 0.83, 0.8), pitch_deg: float = 0.0) -> void:
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
	l.rotation.x = deg_to_rad(pitch_deg)

# ---------------------------------------------------------------- derrick

## The outer lattice of the CRANE TOWER — the tapering rusted derrick that wraps the
## high-iron mast, with a drill-floor apron, a standing drill string and a rotary block.
##
## ALIGNMENT. This used to be centred on z=-15 while the mast it wraps (RigBuilder
## CRANE_X/CRANE_Z, its legs on x 0..4 / z -16..-12) is centred on z=-14, and its Z taper
## ran on different factors from its X taper (0.85 at the base, 0.72 at the top). So the
## outer bays sat a metre off the inner ones and shrank at a different rate on the way up:
## from the deck the whole tower read as two structures leaning through each other, which
## is the "structures aren't centered" the owner photographed. Everything here is now
## measured from RigBuilder's tower axis with ONE symmetric half-extent per level, so the
## bays are concentric and the legs converge on a common point.
const TOWER := Vector3(2.0, 0.0, -14.0)   ## the crane tower's axis — shared with RigBuilder
const DERRICK_BAYS: int = 4

func _derrick() -> void:
	var mat: Material = MatLib.rust_steel()
	var base_c := Vector3(TOWER.x, DECK_Y, TOWER.z)
	var half_base: float = 4.2
	var half_top: float = 2.9
	var foot_y: float = DECK_Y + 0.6
	var top_y: float = DECK_Y + 15.7   # meets just under the machinery deck
	# Four tapering corner legs (collidable at the base run so the player can't clip).
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var a := Vector3(base_c.x + sx * half_base, DECK_Y, base_c.z + sz * half_base)
			var b := Vector3(base_c.x + sx * half_top, top_y, base_c.z + sz * half_top)
			var leg := CSGBox3D.new()
			leg.size = Vector3(0.28, a.distance_to(b) + 0.2, 0.28)
			leg.material = mat
			leg.use_collision = true
			add_child(leg)
			_align_y(leg, a, b)
	# Ring + X bracing per bay. Every member now starts and ends ON a leg line at a ring
	# height, so the bracing meets the joints instead of running past them.
	for i in range(DERRICK_BAYS):
		var y0: float = lerpf(foot_y, top_y, float(i) / DERRICK_BAYS)
		var y1: float = lerpf(foot_y, top_y, float(i + 1) / DERRICK_BAYS)
		var h0: float = lerpf(half_base, half_top, float(i) / DERRICK_BAYS)
		var h1: float = lerpf(half_base, half_top, float(i + 1) / DERRICK_BAYS)
		if i == 0:
			_derrick_ring(base_c, y0, h0, mat)   # closes the bottom bay
		_derrick_ring(base_c, y1, h1, mat)
		# A full X on each of the four faces: both diagonals, corner to corner.
		for s in [-1.0, 1.0]:
			# South/north faces (constant z), running in X.
			_member(Vector3(base_c.x - h0, y0, base_c.z + s * h0),
				Vector3(base_c.x + h1, y1, base_c.z + s * h1), 0.09, mat)
			_member(Vector3(base_c.x + h0, y0, base_c.z + s * h0),
				Vector3(base_c.x - h1, y1, base_c.z + s * h1), 0.09, mat)
			# West/east faces (constant x), running in Z.
			_member(Vector3(base_c.x + s * h0, y0, base_c.z - h0),
				Vector3(base_c.x + s * h1, y1, base_c.z + h1), 0.09, mat)
			_member(Vector3(base_c.x + s * h0, y0, base_c.z + h0),
				Vector3(base_c.x + s * h1, y1, base_c.z - h1), 0.09, mat)
	# Drill-floor apron: checker plate skirt with kick rails and hazard paint.
	_dbox(Vector3(base_c.x, DECK_Y + 0.03, base_c.z), Vector3(9.4, 0.02, 8.6), MatLib.checker_plate())
	_dbox(Vector3(base_c.x, DECK_Y + 0.05, base_c.z - 4.1), Vector3(9.4, 0.02, 0.5), MatLib.flat(Color(0.8, 0.7, 0.1)))
	# The standing drill string: a clustered stand of pipe rising into the tower.
	for off in [Vector2(0, 0), Vector2(0.35, 0.2), Vector2(-0.3, 0.28), Vector2(0.1, -0.38), Vector2(-0.35, -0.18)]:
		_dcyl(Vector3(base_c.x + off.x, DECK_Y + 6.5, base_c.z + off.y), 0.12, 12.4, MatLib.galvanized())
	# Rotary block at the string's foot — the machine the rig existed for.
	_box(Vector3(base_c.x, DECK_Y + 0.55, base_c.z), Vector3(2.2, 1.1, 2.0), MatLib.dark_metal())
	_dbox(Vector3(base_c.x, DECK_Y + 1.16, base_c.z), Vector3(1.4, 0.12, 1.3), MatLib.checker_plate())
	# Stencilled on the rotary block's SOUTH face, facing the drill floor you walk in
	# from. Authored at yaw 0 it faced north INTO the block it is painted on, so the
	# lettering hung off the front of the machine with open air behind it.
	_plabel("ROTARY — LOCKED OUT", Vector3(base_c.x, DECK_Y + 0.85, base_c.z - 1.02), 180, 22, Color(0.9, 0.75, 0.2))
	# Finger rack of leaned spare pipe against the derrick's east face.
	for i in range(4):
		var lean := _dcyl(Vector3(base_c.x + half_base - 0.4, DECK_Y + 5.4, base_c.z - 2.0 + i * 1.1), 0.1, 11.0, MatLib.galvanized())
		lean.rotation.z = 0.12
		lean.rotation.x = 0.03 * (i - 1.5)
	# NO crown cap here any more. It used to be a flat 3.2x1.2x2.6 plate floating above
	# the lookout with nothing on it — the "topped by a flat plate with nothing above it"
	# in the owner's photo. The real crane head (slew ring, A-frame, boom out over the
	# water, hoist, hook block, cab) is built on the machinery deck by
	# RigBuilder._build_crane_head(), which owns the tower top.

## One horizontal ring brace at height `y`, half-extent `h`, on all four faces. Each bar
## spans the full face and stops on the leg lines, so the four of them close a square.
func _derrick_ring(c: Vector3, y: float, h: float, mat: Material) -> void:
	_dbox(Vector3(c.x, y, c.z - h), Vector3(h * 2.0, 0.12, 0.12), mat)
	_dbox(Vector3(c.x, y, c.z + h), Vector3(h * 2.0, 0.12, 0.12), mat)
	_dbox(Vector3(c.x - h, y, c.z), Vector3(0.12, 0.12, h * 2.0), mat)
	_dbox(Vector3(c.x + h, y, c.z), Vector3(0.12, 0.12, h * 2.0), mat)

# ---------------------------------------------------------------- pipe deck

## Horizontal drill-pipe stacks on stands beside the crane — the load zone.
func _pipe_deck() -> void:
	var stand: Material = MatLib.dark_metal()
	for sx in [9.0, 13.0, 17.0]:
		_box(Vector3(sx, DECK_Y + 0.25, -18.6), Vector3(0.4, 0.5, 1.8), stand)
	for layer in range(3):
		for i in range(5 - layer):
			var py: float = DECK_Y + 0.62 + layer * 0.24
			var pz: float = -18.6 - 0.45 + (i + layer * 0.5) * 0.24
			var p := _dcyl(Vector3(13.0, py, pz), 0.11, 10.5, MatLib.galvanized())
			p.rotation.z = PI / 2
	# Rack placard on its own stand at the head of the pipe racks. This line used to
	# hang at y+1.7 where the racks top out around y+1.2 — the whole string floated
	# against open sky and ocean with nothing behind it from any angle.
	for px in [10.9, 15.1]:
		_dbox(Vector3(px, DECK_Y + 0.85, -17.52), Vector3(0.07, 1.7, 0.07), MatLib.rust_steel())
	_box(Vector3(13, DECK_Y + 1.42, -17.55), Vector3(4.5, 0.5, 0.07),
		MatLib.painted_steel(), false)
	for bx in [11.02, 14.98]:
		for by in [DECK_Y + 1.26, DECK_Y + 1.58]:
			_dcyl(Vector3(bx, by, -17.5), 0.018, 0.03, MatLib.galvanized()).rotation.x = PI / 2
	_plabel("PIPE DECK — SLING LOADS", Vector3(13, DECK_Y + 1.42, -17.5), 0, 22, Color(0.85, 0.8, 0.6))
	# Bollards and a chain edge along the south rail behind the racks.
	for bx in [8.0, 13.0, 18.0]:
		_box(Vector3(bx, DECK_Y + 0.3, -19.3), Vector3(0.3, 0.6, 0.3), MatLib.flat(Color(0.75, 0.65, 0.15)))

# ---------------------------------------------------------------- containers

func _containers() -> void:
	var specs := [
		[Vector3(23.5, 0.0, -16.2), 0.06, Color(0.32, 0.42, 0.5), "SLN-114"],
		[Vector3(26.6, 0.0, -15.6), -0.03, Color(0.55, 0.3, 0.22), "SLN-098"],
		[Vector3(23.5, 2.62, -16.2), 0.06, Color(0.36, 0.44, 0.3), "SLN-127"],   # stacked
	]
	for s in specs:
		var pos: Vector3 = s[0]
		var yaw: float = s[1]
		var col: Color = s[2]
		# Real corrugated container skin — tint boosted since it multiplies a mid-gray albedo.
		var skin := MatLib.container(Color(col.r * 1.7, col.g * 1.7, col.b * 1.7))
		var hull := _box(Vector3(pos.x, DECK_Y + pos.y + 1.3, pos.z), Vector3(2.44, 2.6, 6.0), skin)
		hull.rotation.y = yaw
		# Door-end frame strips keep the boxes reading as containers, not crates.
		for side in [-1.24, 1.24]:
			for sy in [0.6, 1.9]:
				var strip := _dbox(Vector3(pos.x + side, DECK_Y + pos.y + sy, pos.z), Vector3(0.04, 0.18, 5.8),
					MatLib.container(Color(col.r * 1.2, col.g * 1.2, col.b * 1.2)))
				strip.rotation.y = yaw
		_plabel(s[3], Vector3(pos.x - 1.26, DECK_Y + pos.y + 2.2, pos.z), -90, 22, Color(0.88, 0.88, 0.82))
	# One container stands open with a stash inside — reward for looking.
	var open_pos := Vector3(23.5, DECK_Y, -13.15)
	var door := _box(open_pos + Vector3(-0.9, 1.3, -0.05), Vector3(0.06, 2.5, 1.15), MatLib.container(Color(0.51, 0.68, 0.82)), false)
	door.rotation.y = 1.25
	var stash := LootContainer.new()
	var items: Array[String] = ["rope", "sealed_tin", "flare"]
	stash.items = items
	stash.display_name = "Container Stash"
	add_child(stash)
	stash.position = Vector3(23.5, DECK_Y + 0.01, -17.8)
	stash.build_box_visual(Vector3(0.9, 0.7, 0.7), Color(0.45, 0.4, 0.3), false, true,
		MatLib.weathered_wood())

# ---------------------------------------------------------------- flare boom

## The flare stack: a lattice boom raked out over the sea off the SW corner,
## soot-black at the tip. Cold now — the rig hasn't breathed fire in a long time.
func _flare_boom() -> void:
	var mat: Material = MatLib.rust_steel()
	var base := Vector3(-28.0, DECK_Y + 0.4, -18.0)
	var dir := Vector3(-0.55, 0.66, -0.5).normalized()
	var L: float = 24.0
	var tip: Vector3 = base + dir * L
	# Three chords.
	var perp_a := Vector3(-dir.z, 0, dir.x).normalized() * 0.42
	var perp_b := Vector3(0.2, 0.45, 0.2)
	for off in [perp_a, -perp_a, perp_b]:
		_member(base + off, tip + off * 0.3, 0.13, mat)
	# Lattice ties.
	for i in range(1, 8):
		var t: float = i / 8.0
		var c: Vector3 = base.lerp(tip, t)
		var w: float = lerpf(0.42, 0.14, t)
		_member(c + Vector3(-dir.z, 0, dir.x) * w, c - Vector3(-dir.z, 0, dir.x) * w, 0.07, mat)
	# Soot nozzle.
	var noz := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.34
	nm.bottom_radius = 0.22
	nm.height = 1.1
	nm.material = MatLib.flat(Color(0.08, 0.08, 0.08))
	noz.mesh = nm
	add_child(noz)
	_align_y(noz, tip - dir * 0.6, tip + dir * 0.5)
	# Anchored pedestal + guard fence + warning on deck.
	_box(Vector3(-28.0, DECK_Y + 0.45, -18.0), Vector3(1.6, 0.9, 1.6), MatLib.dark_metal())
	_rail_x(-29.6, -26.4, DECK_Y, -16.4)
	_rail_z(-19.4, -16.4, DECK_Y, -26.4)
	# Warning board on the west bulkhead (a Z-running wall at x=-28, z -18..-6).
	# The line used to be authored at yaw 0, so its text ran along X — straight THROUGH
	# the edge of that wall, which is why half of it landed on steel and half hung over
	# open sea. Turned to yaw 90 the string runs along Z and lies flat on the wall face.
	_box(Vector3(-27.9, DECK_Y + 1.4, -15.0), Vector3(0.06, 0.5, 2.7),
		MatLib.flat(Color(0.85, 0.72, 0.1)), false)
	for bz in [-16.15, -13.85]:
		for by in [DECK_Y + 1.25, DECK_Y + 1.55]:
			_dcyl(Vector3(-27.86, by, bz), 0.018, 0.03, MatLib.galvanized()).rotation.z = PI / 2
	_plabel("FLARE BOOM — NO ENTRY", Vector3(-27.85, DECK_Y + 1.4, -15.0), 90, 22,
		Color(0.2, 0.18, 0.12))

# ---------------------------------------------------------------- davits

## Empty lifeboat davits at the muster edge — Lifeboat 2 got away. You didn't.
func _davits() -> void:
	var mat: Material = MatLib.painted_steel()
	for dx in [-12.0, -9.0]:
		_box(Vector3(dx, DECK_Y + 1.1, -19.2), Vector3(0.2, 2.2, 0.2), mat)
		var arm := _box(Vector3(dx, DECK_Y + 2.5, -19.9), Vector3(0.16, 1.9, 0.16), mat, false)
		arm.rotation.x = deg_to_rad(-48)
		var cable := _dcyl(Vector3(dx, DECK_Y + 1.9, -20.55), 0.02, 1.8, MatLib.dark_metal())
		cable.rotation.x = 0.0
		_dbox(Vector3(dx, DECK_Y + 1.0, -20.55), Vector3(0.18, 0.22, 0.1), MatLib.dark_metal())  # empty hook
	# Empty cradle chocks on deck between the arms.
	for cx in [-11.4, -9.6]:
		var chock := _box(Vector3(cx, DECK_Y + 0.18, -18.7), Vector3(0.3, 0.36, 0.9), MatLib.dark_metal(), false)
		chock.rotation.z = 0.35
	# Berth number painted FLAT on the plating between the arms (pitch -90). Authored
	# upright it stood in the deck like a sign, with a third of the glyph below the
	# plate; laid flat it reads as deck paint to anyone walking south onto the muster.
	_plabel("LIFEBOAT 2", Vector3(-10.5, DECK_Y + 0.012, -17.9), 0, 34,
		Color(0.75, 0.72, 0.55), -90.0)
	# Muster placard on a real bolted plate spanning the two davit posts — the text
	# used to hang in the gap between them with nothing behind it.
	_box(Vector3(-10.5, DECK_Y + 1.5, -19.16), Vector3(2.7, 0.42, 0.06),
		MatLib.dark_metal(), false)
	for bx in [-11.62, -9.38]:
		for by in [DECK_Y + 1.35, DECK_Y + 1.65]:
			_dcyl(Vector3(bx, by, -19.12), 0.018, 0.03, MatLib.galvanized()).rotation.x = PI / 2
	_plabel("MUSTER — BOAT AWAY", Vector3(-10.5, DECK_Y + 1.5, -19.12), 0, 20, Color(0.9, 0.75, 0.2))

# ---------------------------------------------------------------- observation platform

## Split-level platform cantilevered off the west edge — the long view, and a
## place to watch the mantle ray cross.
func _obs_platform() -> void:
	_box(Vector3(-32, DECK_Y - 0.6, -11), Vector3(4.4, 0.3, 6.4), MatLib.checker_plate())
	_stair_run(Vector3(-29.9, DECK_Y, -11), Vector3(-31.2, DECK_Y - 0.45, -11), 1.6)
	_rail_z(-14.1, -7.9, DECK_Y - 0.6, -34.1)
	_rail_x(-34.1, -29.9, DECK_Y - 0.6, -14.1)
	_rail_x(-34.1, -29.9, DECK_Y - 0.6, -7.9)
	# Angled struts back to the leg.
	for sz in [-13.0, -9.0]:
		_member(Vector3(-33.5, DECK_Y - 0.8, sz), Vector3(-29.5, DECK_Y - 4.5, sz), 0.24, MatLib.rust_steel())
	_box(Vector3(-33.3, DECK_Y - 0.25, -11), Vector3(0.5, 0.4, 2.2), MatLib.wood(), false)   # bench plank
	# (The "WEST LOOKOUT" deck stencil was removed: laid flat on the platform plating it
	# read as stray text lying on the ground behind the machine shop, not as signage.)

# ---------------------------------------------------------------- west stairs

## External switchback stair up the Stack's west face: deck -> Deck B level ->
## C-deck terrace. Steel stringers, checker treads, full rails.
func _west_stairs() -> void:
	var tread: Material = MatLib.checker_plate()
	var frame: Material = MatLib.rust_steel()
	# Flight 1: south -> north along the wall at x -3.2 (rail on the outer/west side,
	# which is climb-LEFT going north; the stack wall guards the east side).
	_stair_run(Vector3(-3.2, DECK_Y, 8.4), Vector3(-3.2, 21.68, 13.5), 1.4, true, false)
	# Mid landing (top surface 21.675 — both flights meet it flush).
	#
	# South edge stays at z 13.55, just PAST where flight 1's surface tops out at 13.5:
	# pulled any further south the plate's leading edge stands proud of the still-
	# climbing ramp and becomes exactly the sort of curb this batch removed elsewhere.
	#
	# North edge moved out from 15.25 to 16.2. A switchback landing has to be deep
	# enough to walk AROUND the end of the lower flight's outer handrail, and this one
	# was not: the rail guard reaches z 14.05 and the support leg stood at 14.4, which
	# left roughly 0.35m of clear plate for an 0.8m-wide player. The turn was physically
	# impassable — you arrived at the top of flight 1 and could not reach flight 2.
	_box(Vector3(-4.1, 21.55, 14.875), Vector3(3.2, 0.25, 2.65), tread)
	# Flight 2: north -> south at x -5 (west is climb-RIGHT going south).
	_stair_run(Vector3(-5.0, 21.68, 13.5), Vector3(-5.0, 25.1, 8.4), 1.4, false, true)
	# Top landing bridging into the C-deck terrace edge.
	_box(Vector3(-3.9, 24.95, 7.6), Vector3(3.6, 0.3, 1.6), tread)
	# Support legs down to the deck, along the landings' NORTH edges. The mid-landing
	# leg used to stand at z 14.4 — dead centre of the turn, a 0.22m column with only
	# 0.74m of plate either side of it, so a 0.8m-wide player capsule could not get
	# past it in either direction and the switchback was impassable at the half-way
	# landing. Structure belongs at the edges the rail already occupies.
	for p in [Vector3(-4.1, 0, 16.05), Vector3(-5.4, 0, 8.6), Vector3(-2.6, 0, 8.6)]:
		_box(Vector3(p.x, (DECK_Y + 24.8) * 0.5, p.z), Vector3(0.22, 24.8 - DECK_Y, 0.22), frame)
	# Mid-landing edge rails (the flights carry their own rails now). The west edge is
	# open air above the deck from the top of flight 1 northward, and was unfenced.
	_rail_x(-5.8, -2.4, 21.55, 16.2)
	_rail_z(13.9, 16.2, 21.55, -5.75)
	# Stair sign on a plate bolted to the flight's east stringer. It used to hang at
	# (-2.4, 20.2, 7.9) — two metres up in open air beside the stair, with the Stack's
	# west wall not starting until Deck B height, so nothing was behind it at all.
	_dbox(Vector3(-2.47, DECK_Y + 1.35, 9.3), Vector3(0.05, 0.32, 2.0), MatLib.painted_steel())
	for sz in [8.45, 10.15]:
		for sy in [DECK_Y + 1.24, DECK_Y + 1.46]:
			_dcyl(Vector3(-2.44, sy, sz), 0.018, 0.03, MatLib.galvanized()).rotation.z = PI / 2
	_plabel("STAIR W — DECKS B/C", Vector3(-2.44, DECK_Y + 1.35, 9.3), 90, 20, Color(0.9, 0.85, 0.6))
