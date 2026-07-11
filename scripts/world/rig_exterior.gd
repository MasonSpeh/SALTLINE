class_name RigExterior extends Node3D
## Phase 2 — the exterior silhouette pass. Expands the rig's skyline and deck
## clutter into a working offshore platform: the high-iron mast becomes a full
## drilling derrick with a drill floor and pipe deck, a flare boom cantilevers
## off the southwest corner, containers and davits dress the south deck, an
## observation platform hangs off the west edge, and an external switchback
## stair climbs the Stack's west face to the C-deck terrace.

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

func _rail_x(x0: float, x1: float, y: float, z: float) -> void:
	var mat: Material = MatLib.rust_steel()
	_box(Vector3((x0 + x1) * 0.5, y + 0.55, z), Vector3(x1 - x0, 0.1, 0.1), mat)
	var n: int = maxi(2, int((x1 - x0) / 2.2))
	for i in range(n + 1):
		_dbox(Vector3(x0 + (x1 - x0) * i / n, y + 0.28, z), Vector3(0.06, 0.56, 0.06), mat)

func _rail_z(z0: float, z1: float, y: float, x: float) -> void:
	var mat: Material = MatLib.rust_steel()
	_box(Vector3(x, y + 0.55, (z0 + z1) * 0.5), Vector3(0.1, 0.1, z1 - z0), mat)
	var n: int = maxi(2, int((z1 - z0) / 2.2))
	for i in range(n + 1):
		_dbox(Vector3(x, y + 0.28, z0 + (z1 - z0) * i / n), Vector3(0.06, 0.56, 0.06), mat)

func _plabel(text: String, pos: Vector3, yaw_deg: float, font_size: int = 30,
		color: Color = Color(0.82, 0.83, 0.8)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.01
	l.modulate = Color(color.r, color.g, color.b, 0.92)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	add_child(l)
	l.position = pos
	l.rotation.y = deg_to_rad(yaw_deg)

# ---------------------------------------------------------------- derrick

## The existing high-iron mast (x 0..4, z -16..-12, lookout at y 34) grows into a
## full drilling derrick: wider tapering corner legs, dense bracing, a drill-floor
## apron, a standing drill string, and a rotary block. The lookout stays.
func _derrick() -> void:
	var mat: Material = MatLib.rust_steel()
	var base_c := Vector3(2.0, DECK_Y, -15.0)
	var half_base: float = 4.2
	var half_top: float = 2.9
	var top_y: float = DECK_Y + 15.7   # meets just under the lookout platform
	# Four tapering corner legs (collidable at the base run so the player can't clip).
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var a := Vector3(base_c.x + sx * half_base, DECK_Y, base_c.z + sz * half_base * 0.85)
			var b := Vector3(base_c.x + sx * half_top, top_y, base_c.z + sz * half_top * 0.72)
			var leg := CSGBox3D.new()
			leg.size = Vector3(0.28, a.distance_to(b) + 0.2, 0.28)
			leg.material = mat
			leg.use_collision = true
			add_child(leg)
			_align_y(leg, a, b)
	# Ring + X bracing every ~4m on all four faces.
	for i in range(4):
		var t0: float = i / 4.0
		var t1: float = (i + 1) / 4.0
		var y0: float = lerpf(DECK_Y + 0.6, top_y, t0)
		var y1: float = lerpf(DECK_Y + 0.6, top_y, t1)
		var hx0: float = lerpf(half_base, half_top, t0)
		var hx1: float = lerpf(half_base, half_top, t1)
		var hz0: float = hx0 * 0.85 - (hx0 - lerpf(half_base * 0.85, half_top * 0.72, t0))
		hz0 = lerpf(half_base * 0.85, half_top * 0.72, t0)
		var hz1: float = lerpf(half_base * 0.85, half_top * 0.72, t1)
		# Horizontal rings at y1.
		_dbox(Vector3(base_c.x, y1, base_c.z - hz1), Vector3(hx1 * 2, 0.12, 0.12), mat)
		_dbox(Vector3(base_c.x, y1, base_c.z + hz1), Vector3(hx1 * 2, 0.12, 0.12), mat)
		_dbox(Vector3(base_c.x - hx1, y1, base_c.z), Vector3(0.12, 0.12, hz1 * 2), mat)
		_dbox(Vector3(base_c.x + hx1, y1, base_c.z), Vector3(0.12, 0.12, hz1 * 2), mat)
		# Diagonals, south and north faces then east and west.
		_member(Vector3(base_c.x - hx0, y0, base_c.z - hz0), Vector3(base_c.x + hx1, y1, base_c.z - hz1), 0.09, mat)
		_member(Vector3(base_c.x + hx0, y0, base_c.z - hz0), Vector3(base_c.x - hx1, y1, base_c.z - hz1), 0.09, mat)
		_member(Vector3(base_c.x - hx0, y0, base_c.z + hz0), Vector3(base_c.x + hx1, y1, base_c.z + hz1), 0.09, mat)
		_member(Vector3(base_c.x - hx0, y0, base_c.z - hz0), Vector3(base_c.x - hx1, y1, base_c.z + hz1), 0.09, mat)
		_member(Vector3(base_c.x + hx0, y0, base_c.z + hz0), Vector3(base_c.x + hx1, y1, base_c.z - hz1), 0.09, mat)
	# Drill-floor apron: checker plate skirt with kick rails and hazard paint.
	_dbox(Vector3(base_c.x, DECK_Y + 0.03, base_c.z), Vector3(9.4, 0.02, 8.6), MatLib.checker_plate())
	_dbox(Vector3(base_c.x, DECK_Y + 0.05, base_c.z - 4.1), Vector3(9.4, 0.02, 0.5), MatLib.flat(Color(0.8, 0.7, 0.1)))
	# The standing drill string: a clustered stand of pipe rising into the tower.
	for off in [Vector2(0, 0), Vector2(0.35, 0.2), Vector2(-0.3, 0.28), Vector2(0.1, -0.38), Vector2(-0.35, -0.18)]:
		_dcyl(Vector3(base_c.x + off.x, DECK_Y + 6.5, base_c.z + off.y), 0.12, 12.4, MatLib.galvanized())
	# Rotary block at the string's foot — the machine the rig existed for.
	_box(Vector3(base_c.x, DECK_Y + 0.55, base_c.z), Vector3(2.2, 1.1, 2.0), MatLib.dark_metal())
	_dbox(Vector3(base_c.x, DECK_Y + 1.16, base_c.z), Vector3(1.4, 0.12, 1.3), MatLib.checker_plate())
	_plabel("ROTARY — LOCKED OUT", Vector3(base_c.x, DECK_Y + 0.85, base_c.z - 1.02), 0, 22, Color(0.9, 0.75, 0.2))
	# Finger rack of leaned spare pipe against the derrick's east face.
	for i in range(4):
		var lean := _dcyl(Vector3(base_c.x + half_base - 0.4, DECK_Y + 5.4, base_c.z - 2.0 + i * 1.1), 0.1, 11.0, MatLib.galvanized())
		lean.rotation.z = 0.12
		lean.rotation.x = 0.03 * (i - 1.5)
	# Crown cap above the lookout: a small sheave house silhouette.
	_dbox(Vector3(2, DECK_Y + 17.6, -14), Vector3(3.2, 1.2, 2.6), mat)
	_dcyl(Vector3(2, DECK_Y + 18.5, -14), 0.35, 0.5, MatLib.dark_metal())

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
	_plabel("PIPE DECK — SLING LOADS", Vector3(13, DECK_Y + 1.7, -17.5), 0, 22, Color(0.85, 0.8, 0.6))
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
		var hull := _box(Vector3(pos.x, DECK_Y + pos.y + 1.3, pos.z), Vector3(2.44, 2.6, 6.0), MatLib.flat(col))
		hull.rotation.y = yaw
		# Corrugation hint: two recessed strips per long side.
		for side in [-1.24, 1.24]:
			for sy in [0.6, 1.9]:
				var strip := _dbox(Vector3(pos.x + side, DECK_Y + pos.y + sy, pos.z), Vector3(0.04, 0.18, 5.8),
					MatLib.flat(col.darkened(0.25)))
				strip.rotation.y = yaw
		_plabel(s[3], Vector3(pos.x - 1.26, DECK_Y + pos.y + 2.2, pos.z), -90, 22, Color(0.88, 0.88, 0.82))
	# One container stands open with a stash inside — reward for looking.
	var open_pos := Vector3(23.5, DECK_Y, -13.15)
	var door := _box(open_pos + Vector3(-0.9, 1.3, -0.05), Vector3(0.06, 2.5, 1.15), MatLib.flat(Color(0.3, 0.4, 0.48)), false)
	door.rotation.y = 1.25
	var stash := LootContainer.new()
	var items: Array[String] = ["rope", "sealed_tin", "flare"]
	stash.items = items
	stash.display_name = "Container Stash"
	add_child(stash)
	stash.position = Vector3(23.5, DECK_Y + 0.01, -17.8)
	stash.build_box_visual(Vector3(0.9, 0.7, 0.7), Color(0.45, 0.4, 0.3), false, true)

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
	_plabel("FLARE BOOM — NO ENTRY", Vector3(-28, DECK_Y + 1.35, -16.32), 0, 22, Color(0.9, 0.75, 0.2))

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
	_plabel("LIFEBOAT 2", Vector3(-10.5, DECK_Y + 0.04, -17.9), 0, 34, Color(0.75, 0.72, 0.55))
	_plabel("MUSTER — BOAT AWAY", Vector3(-10.5, DECK_Y + 1.5, -19.08), 0, 20, Color(0.9, 0.75, 0.2))

# ---------------------------------------------------------------- observation platform

## Split-level platform cantilevered off the west edge — the long view, and a
## place to watch the mantle ray cross.
func _obs_platform() -> void:
	_box(Vector3(-32, DECK_Y - 0.6, -11), Vector3(4.4, 0.3, 6.4), MatLib.checker_plate())
	_ramp(Vector3(-29.9, DECK_Y + 0.05, -11), Vector3(-31.2, DECK_Y - 0.42, -11), 1.6, MatLib.checker_plate())
	_rail_z(-14.1, -7.9, DECK_Y - 0.6, -34.1)
	_rail_x(-34.1, -29.9, DECK_Y - 0.6, -14.1)
	_rail_x(-34.1, -29.9, DECK_Y - 0.6, -7.9)
	# Angled struts back to the leg.
	for sz in [-13.0, -9.0]:
		_member(Vector3(-33.5, DECK_Y - 0.8, sz), Vector3(-29.5, DECK_Y - 4.5, sz), 0.24, MatLib.rust_steel())
	_box(Vector3(-33.3, DECK_Y - 0.25, -11), Vector3(0.5, 0.4, 2.2), MatLib.wood(), false)   # bench plank
	_plabel("WEST LOOKOUT", Vector3(-30.1, DECK_Y + 1.5, -8.6), 90, 22)

# ---------------------------------------------------------------- west stairs

## External switchback stair up the Stack's west face: deck -> Deck B level ->
## C-deck terrace. Steel stringers, checker treads, full rails.
func _west_stairs() -> void:
	var tread: Material = MatLib.checker_plate()
	var frame: Material = MatLib.rust_steel()
	# Flight 1: south -> north along the wall at x -3.2.
	_ramp(Vector3(-3.2, DECK_Y + 0.1, 8.4), Vector3(-3.2, 21.65, 13.5), 1.4, tread)
	# Mid landing.
	_box(Vector3(-4.1, 21.55, 14.4), Vector3(3.2, 0.25, 1.7), tread)
	# Flight 2: north -> south at x -5.
	_ramp(Vector3(-5.0, 21.75, 13.5), Vector3(-5.0, 25.15, 8.4), 1.4, tread)
	# Top landing bridging into the C-deck terrace edge.
	_box(Vector3(-3.9, 24.95, 7.6), Vector3(3.6, 0.3, 1.6), tread)
	# Support legs down to the deck.
	for p in [Vector3(-4.1, 0, 14.4), Vector3(-5.0, 0, 8.6), Vector3(-3.9, 0, 7.6)]:
		_box(Vector3(p.x, (DECK_Y + 24.8) * 0.5, p.z), Vector3(0.22, 24.8 - DECK_Y, 0.22), frame)
	# Rails on the outer sides.
	_rail_z(8.4, 13.5, 19.9, -3.95)    # flight 1 outer, mid-height approximation
	_rail_z(8.4, 13.5, 23.5, -5.75)    # flight 2 outer
	_rail_x(-5.8, -2.4, 21.55, 15.25)  # mid landing north edge
	_plabel("STAIR W — DECKS B/C", Vector3(-2.4, DECK_Y + 2.2, 7.9), 90, 24, Color(0.9, 0.85, 0.6))
