class_name RigBuilder extends Node3D
## Builds the greybox Rig Slipway (GDD 5.1) from code: Z1 Wet Deck, Z2 Stairs,
## Z4 Topside, Z5 High Iron, plus the SPHL, distant imposters, and all interactables.
## Positions are the level design — edit here, not in scattered scenes.

const DECK_Y: float = 18.0        # Topside floor
const WET_Y: float = 2.0          # Wet Deck floor
const WALL_H: float = 3.2
const WALL_T: float = 0.25

var player_spawn: Vector3 = Vector3(20.0, WET_Y + 0.2, -24.7)   # dead ahead of the hatch
var wet_deck_respawn: Vector3 = Vector3(20.0, WET_Y + 0.6, -10.0)
var sphl_hatch: InteractDoor
var sphl_interior: Vector3 = Vector3(16.5, WET_Y + 0.4, -24.0)
var countdown_label: Label3D
var pa_speaker_pos: Vector3 = Vector3(14, 21.0, 7)
var crab_spawn: Vector3 = Vector3(12, WET_Y + 0.6, -20)
var crab_z1_loop: Array = [
	Vector3(11, 2.6, -20), Vector3(28, 2.6, -20), Vector3(28, 2.6, -8), Vector3(11, 2.6, -8),
]
var crab_ascend_path: Array = [
	Vector3(24, 2.6, -4.5), Vector3(23, 2.6, -4.5), Vector3(29, 6.6, -4.5),
	Vector3(29, 6.6, 0.5), Vector3(23, 10.6, 0.5), Vector3(23, 10.6, -4.5),
	Vector3(29, 14.6, -4.5), Vector3(29, 14.6, 0.5), Vector3(23, 18.6, 0.5),
	Vector3(20, 18.6, 0.5),
]
var crab_z4_loop: Array = [
	Vector3(18, 18.6, -10), Vector3(-18, 18.6, -10), Vector3(-18, 18.6, 6), Vector3(18, 18.6, 6),
]
var crab_exit_point: Vector3 = Vector3(26, 2.6, -20)

func _ready() -> void:
	_build_structure()
	_build_wet_deck()
	_build_stair_tower()
	_build_topside()
	_build_high_iron()
	_build_sphl()
	_build_imposters()
	_build_spill_lights()
	_build_access()
	_decorate_interiors()
	_build_env_objects()
	_industrial_dressing()
	# The accommodation stack: Decks B/C/D + roof + comms mast above the topside rooms.
	# Preloaded by path — the global class cache may not know the new file yet.
	add_child(preload("res://scripts/world/rig_superstructure.gd").new())
	# Exterior silhouette: derrick, flare boom, pipe deck, containers, davits,
	# west observation platform, external stair to the Stack.
	add_child(preload("res://scripts/world/rig_exterior.gd").new())

## Daylight spill for interiors (greybox stand-in for door/window light shafts).
## Grouped so SunController scales them with the sun — interiors go dark at night.
func _build_spill_lights() -> void:
	var spots := [
		Vector3(14, 4.5, -10), Vector3(13, 4.5, -19), Vector3(27, 8.5, 6),
		Vector3(25, 12.5, 6), Vector3(6, 20.5, 13), Vector3(23, 20.5, 13),
		Vector3(-18, 20.5, 11), Vector3(-21, 20.5, -12), Vector3(26, 7.0, -2),
		Vector3(26, 15.0, -2), Vector3(-25.5, 20.2, 6.5), Vector3(-12, 20.2, 15.5),
	]
	for s in spots:
		var l := OmniLight3D.new()
		l.light_energy = 0.55
		l.omni_range = 7.0
		l.light_color = Color(0.78, 0.82, 0.86)
		l.add_to_group("spill_lights")
		add_child(l)
		l.global_position = s

# ---------- helpers ----------

func _box(pos: Vector3, size: Vector3, mat: Material, parent: Node3D = self, collide: bool = true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.material = mat
	b.use_collision = collide
	parent.add_child(b)
	b.position = pos
	return b

func _cyl(pos: Vector3, radius: float, height: float, mat: Material, parent: Node3D = self) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = height
	c.material = mat
	c.use_collision = true
	parent.add_child(c)
	c.position = pos
	return c

## Wall between floor points a->b (axis aligned), with optional doorway at door_t (0-1 along wall).
func _wall(a: Vector3, b: Vector3, height: float, mat: Material, door_t: float = -1.0) -> void:
	var dir: Vector3 = b - a
	var length: float = dir.length()
	var mid: Vector3 = (a + b) * 0.5
	var along_x: bool = absf(dir.x) > absf(dir.z)
	if door_t < 0.0:
		var size := Vector3(length, height, WALL_T) if along_x else Vector3(WALL_T, height, length)
		_box(mid + Vector3(0, height * 0.5, 0), size, mat)
		return
	# Split around a 1.4m doorway, 2.2m tall, with lintel above.
	var door_w: float = 1.4
	var door_pos: float = clampf(door_t, 0.1, 0.9) * length
	var seg1: float = door_pos - door_w * 0.5
	var seg2: float = length - door_pos - door_w * 0.5
	var u: Vector3 = dir.normalized()
	if seg1 > 0.05:
		var c1: Vector3 = a + u * (seg1 * 0.5)
		_box(c1 + Vector3(0, height * 0.5, 0),
			Vector3(seg1, height, WALL_T) if along_x else Vector3(WALL_T, height, seg1), mat)
	if seg2 > 0.05:
		var c2: Vector3 = b - u * (seg2 * 0.5)
		_box(c2 + Vector3(0, height * 0.5, 0),
			Vector3(seg2, height, WALL_T) if along_x else Vector3(WALL_T, height, seg2), mat)
	var lintel_h: float = height - 2.2
	if lintel_h > 0.05:
		var cl: Vector3 = a + u * door_pos
		_box(cl + Vector3(0, 2.2 + lintel_h * 0.5, 0),
			Vector3(door_w, lintel_h, WALL_T) if along_x else Vector3(WALL_T, lintel_h, door_w), mat)

func _ramp(from: Vector3, to: Vector3, width: float, mat: Material) -> void:
	var dir: Vector3 = to - from
	var len3d: float = dir.length()
	var b := CSGBox3D.new()
	b.size = Vector3(width, 0.3, len3d)
	b.material = mat
	b.use_collision = true
	add_child(b)
	b.global_position = (from + to) * 0.5
	b.look_at((to + Vector3(0, 0, 0)), Vector3.UP)

func _readable(id: String, name_: String, pos: Vector3, size: Vector3 = Vector3(0.35, 0.45, 0.06)) -> Readable:
	var r := Readable.new()
	r.readable_id = id
	r.display_name = name_
	add_child(r)
	r.global_position = pos
	r.build_box_visual(size, Interactable.COLOR_READABLE)
	return r

func _takeable(item: String, name_: String, pos: Vector3, size: Vector3 = Vector3(0.3, 0.35, 0.3)) -> Takeable:
	var t := Takeable.new()
	t.item_id = item
	t.display_name = name_
	add_child(t)
	t.global_position = pos
	# Collision box for the interaction ray, plus a distinctive item mesh you can read.
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x, 0.4), maxf(size.y, 0.4), maxf(size.z, 0.4))
	col.shape = box
	t.add_child(col)
	col.position.y = box.size.y * 0.5
	t.add_child(ItemVisual.build(item))
	# Adhere to whatever surface is actually below (shelf, counter, deck).
	preload("res://scripts/world/surface_snap.gd").attach(t)
	return t

func _crate(items: Array, name_: String, pos: Vector3) -> LootContainer:
	## pos is FLOOR level — the crate rests on it, collision matching the visual.
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

func _ladder(pos: Vector3, height: float, facing_deg: float, name_: String = "Ladder", exit_fwd: float = 0.8) -> Ladder:
	var l := Ladder.new()
	l.height = height
	l.display_name = name_
	l.exit_forward = exit_fwd
	add_child(l)
	l.global_position = pos
	l.rotation.y = deg_to_rad(facing_deg)
	# Two safety-yellow side rails with rungs stepped up between them — reads as a ladder.
	var rail_mat := MatLib.flat(Interactable.COLOR_TAKEABLE)
	var rung_mat := MatLib.flat(Color(0.75, 0.65, 0.15))
	for side in [-0.24, 0.24]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.09, height, 0.09)
		rm.material = rail_mat
		rail.mesh = rm
		l.add_child(rail)
		rail.position = Vector3(side, height * 0.5, 0)
	var rungs: int = maxi(2, int(height / 0.32))
	for i in range(rungs):
		var rung := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.56, 0.05, 0.05)
		gm.material = rung_mat
		rung.mesh = gm
		l.add_child(rung)
		rung.position = Vector3(0, (i + 0.5) * (height / rungs), 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, height, 0.35)
	shape.shape = box
	l.add_child(shape)
	shape.position = Vector3(0, height * 0.5, 0)
	return l

# ---------- structure ----------

func _build_structure() -> void:
	var legs := [Vector3(-22, 0, -12), Vector3(22, 0, -12), Vector3(-22, 0, 12), Vector3(22, 0, 12)]
	for leg_pos in legs:
		# Top ends below the deck slab — coplanar faces z-fight through the floors above.
		# Gravity-base look: smooth aged concrete, like the Troll A caissons.
		_box(leg_pos + Vector3(0, 6.6, 0), Vector3(6, 20.8, 6), MatLib.concrete())
	# Pontoons riding just above the bigger v2 swell (crests reach ~0.9).
	_box(Vector3(0, -1.05, -12), Vector3(56, 4, 8), MatLib.concrete_floor())
	_box(Vector3(0, -1.05, 12), Vector3(56, 4, 8), MatLib.concrete_floor())

# ---------- Z1: Wet Deck ----------

func _build_wet_deck() -> void:
	# Platform slung at the waterline — anti-slip checker plate, not bare deck.
	_box(Vector3(19, WET_Y - 0.25, -10), Vector3(22, 0.5, 24), MatLib.checker_plate())

	# Flooded pump room (knee-deep water, cold zone).
	var pr_mat: Material = MatLib.concrete()
	_wall(Vector3(10, WET_Y, -14), Vector3(18, WET_Y, -14), WALL_H, pr_mat, 0.5)
	_wall(Vector3(10, WET_Y, -6), Vector3(18, WET_Y, -6), WALL_H, pr_mat)
	_wall(Vector3(10, WET_Y, -14), Vector3(10, WET_Y, -6), WALL_H, pr_mat)
	_wall(Vector3(18, WET_Y, -14), Vector3(18, WET_Y, -6), WALL_H, pr_mat)
	_box(Vector3(14, WET_Y + WALL_H, -10), Vector3(8.5, 0.25, 8.5), pr_mat) # roof
	var water := _box(Vector3(14, WET_Y + 0.27, -10), Vector3(7.6, 0.55, 7.6), null, self, false)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.1, 0.2, 0.22, 0.6)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material = wmat
	var cold := WarmthZone.new()
	cold.mode = -1
	cold.setup(Vector3(8, 3, 8))
	add_child(cold)
	cold.global_position = Vector3(14, WET_Y + 1.5, -10)
	_box(Vector3(12, WET_Y + 0.9, -12), Vector3(1.5, 1.8, 1.5), MatLib.dark_metal()) # dead pump
	_readable("pump_room_tag", "Lockout Tag", Vector3(12, WET_Y + 1.4, -11.1), Vector3(0.25, 0.3, 0.05))
	_crate(["canned_food", "flare"], "Sealed Crate", Vector3(16.5, WET_Y + 0.01, -8))

	# Loot room on the south edge.
	var lr_mat: Material = MatLib.concrete()
	_wall(Vector3(10, WET_Y, -16), Vector3(16, WET_Y, -16), WALL_H, lr_mat, 0.5)
	_wall(Vector3(10, WET_Y, -22), Vector3(16, WET_Y, -22), WALL_H, lr_mat)
	_wall(Vector3(10, WET_Y, -22), Vector3(10, WET_Y, -16), WALL_H, lr_mat)
	_wall(Vector3(16, WET_Y, -22), Vector3(16, WET_Y, -16), WALL_H, lr_mat)
	_box(Vector3(13, WET_Y + WALL_H, -19), Vector3(6.5, 0.25, 6.5), lr_mat)
	_crate(["canned_food", "canned_peaches"], "Storage Crate", Vector3(13, WET_Y + 0.01, -20))

	# Tide-line clutter.
	for i in range(5):
		_cyl(Vector3(22 + (i % 3) * 1.4, WET_Y + 0.5, -19 + (i * 1.1)), 0.45, 1.0, MatLib.rust_steel())

	# Exterior ladder: Wet Deck -> Topside (the long, exposed alternative).
	_ladder(Vector3(29.9, WET_Y, -16), DECK_Y - WET_Y, -90.0, "Leg Ladder", 1.2)

# ---------- Z2: The Stairs ----------

func _build_stair_tower() -> void:
	var mat: Material = MatLib.concrete()
	var top_h: float = DECK_Y - WET_Y + 2.8   # walls rise past the deck lip
	# Tower shell x 22..30, z -6..2. Entrance at south (from wet deck), exit at top west.
	_wall(Vector3(22, WET_Y, -6), Vector3(30, WET_Y, -6), top_h, mat, 0.2)
	_wall(Vector3(22, WET_Y, 2), Vector3(30, WET_Y, 2), top_h, mat)
	_wall(Vector3(30, WET_Y, -6), Vector3(30, WET_Y, 2), top_h, mat)
	_wall(Vector3(22, WET_Y, -6), Vector3(22, WET_Y, 2), top_h, mat)
	# Top exit doorway (west wall, deck level): carve with a subtraction-free trick —
	# the west wall above deck is rebuilt as two segments around a gap.
	# (Cheaper: punch a hole via a doorway wall piece at deck height.)
	var hole := CSGBox3D.new()
	hole.size = Vector3(WALL_T + 0.4, 2.3, 1.4)
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	# NOTE: subtraction needs a combiner; simpler — leave west wall solid below deck and
	# add an explicit doorway frame at deck level on the west side:
	hole.queue_free()
	_doorway_west_top(mat)

	# Switchback ramps: 4 runs of 4m rise.
	_ramp(Vector3(23, WET_Y + 0.15, -4.5), Vector3(29, 6.15, -4.5), 2.0, MatLib.deck_plate())
	_ramp(Vector3(29, 6.15, 0.5), Vector3(23, 10.15, 0.5), 2.0, MatLib.deck_plate())
	_ramp(Vector3(23, 10.15, -4.5), Vector3(29, 14.15, -4.5), 2.0, MatLib.deck_plate())
	_ramp(Vector3(29, 14.15, 0.5), Vector3(23, 18.15, 0.5), 2.0, MatLib.deck_plate())
	# Landings.
	_box(Vector3(29, 6.0, -2), Vector3(2.4, 0.3, 7.6), MatLib.deck_plate())
	_box(Vector3(23, 10.0, -2), Vector3(2.4, 0.3, 7.6), MatLib.deck_plate())
	_box(Vector3(29, 14.0, -2), Vector3(2.4, 0.3, 7.6), MatLib.deck_plate())
	_box(Vector3(23, 18.0, -2), Vector3(2.4, 0.3, 7.6), MatLib.deck_plate())

	# Machinery room (y=6) off landing 1 — holds the cable spool.
	_room_north(Vector3(24, 6.0, 2), Vector3(30, 6.0, 10), MatLib.concrete(), 0.75)
	_box(Vector3(27, 6.0 + 0.5, 6), Vector3(2.2, 1.0, 1.2), MatLib.dark_metal()) # dead machinery
	_takeable("cable_spool", "Cable Spool", Vector3(27, 7.01, 6), Vector3(0.5, 0.5, 0.5))

	# Breaker Room 4-A (y=10) off landing 2 — the power puzzle centerpiece.
	_room_north(Vector3(22, 10.0, 2), Vector3(28, 10.0, 10), MatLib.concrete(), 0.25)
	var breaker := BreakerPanel.new()
	breaker.display_name = "Master Breaker 4-A"
	breaker.circuit_id = "topside_floodlights"
	add_child(breaker)
	breaker.global_position = Vector3(23, 11.4, 9.5)
	breaker.build_box_visual(Vector3(1.0, 1.4, 0.3), Interactable.COLOR_OPERABLE)
	_readable("breaker_log", "Maintenance Log", Vector3(24.6, 11.2, 9.55), Vector3(0.35, 0.45, 0.06))
	# The burned cable gap, on the room's east wall run.
	var cable := CableSegment.new()
	cable.display_name = "Burned Cable Gap"
	cable.gap_length = 2.0
	add_child(cable)
	cable.global_position = Vector3(27.6, 10.9, 6)
	cable.build_box_visual(Vector3(0.4, 0.5, 2.2), Color(0.12, 0.08, 0.06))
	breaker.set_cable(cable)
	# Cosmetic cable runs to and from the gap.
	_box(Vector3(27.7, 10.6, 8.4), Vector3(0.12, 0.12, 2.2), MatLib.dark_metal(), self, false)
	_box(Vector3(27.7, 10.6, 3.6), Vector3(0.12, 0.12, 2.2), MatLib.dark_metal(), self, false)

func _doorway_west_top(mat: Material) -> void:
	# The tower's west wall gets an opening at deck level by overlaying jamb boxes that
	# read as a hatch frame; the wall itself is interrupted here (rebuilt as segments).
	# Frame posts:
	_box(Vector3(22, DECK_Y + 1.2, -0.4), Vector3(0.3, 2.4, 0.2), mat)
	_box(Vector3(22, DECK_Y + 1.2, 1.4), Vector3(0.3, 2.4, 0.2), mat)

func _room_north(a: Vector3, b: Vector3, mat: Material, door_t: float) -> void:
	## Rectangular room north of the tower: a=(west,floor_y,south) b=(east,floor_y,north).
	var y: float = a.y
	_box(Vector3((a.x + b.x) * 0.5, y - 0.15, (a.z + b.z) * 0.5), Vector3(b.x - a.x + 0.5, 0.3, b.z - a.z + 0.5), MatLib.deck_plate())
	_wall(Vector3(a.x, y, a.z), Vector3(b.x, y, a.z), WALL_H, mat, door_t) # south wall w/ door
	_wall(Vector3(a.x, y, b.z), Vector3(b.x, y, b.z), WALL_H, mat)
	_wall(Vector3(a.x, y, a.z), Vector3(a.x, y, b.z), WALL_H, mat)
	_wall(Vector3(b.x, y, a.z), Vector3(b.x, y, b.z), WALL_H, mat)
	_box(Vector3((a.x + b.x) * 0.5, y + WALL_H, (a.z + b.z) * 0.5), Vector3(b.x - a.x + 0.5, 0.25, b.z - a.z + 0.5), mat)

# ---------- Z4: Topside ----------

func _build_topside() -> void:
	# Deck plate with a hole for the stair tower (combiner subtraction).
	var comb := CSGCombiner3D.new()
	comb.use_collision = true
	add_child(comb)
	var deck := CSGBox3D.new()
	deck.size = Vector3(60, 1.0, 40)
	deck.material = MatLib.deck_plate()
	comb.add_child(deck)
	deck.position = Vector3(0, DECK_Y - 0.5, 0)
	var hole := CSGBox3D.new()
	hole.size = Vector3(8.2, 2.0, 8.2)
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(hole)
	hole.position = Vector3(26, DECK_Y - 0.5, -2)

	# Perimeter rails (gaps at corners — the sea is reachable, deliberately).
	var rail_mat: Material = MatLib.rust_steel()
	_box(Vector3(0, DECK_Y + 0.55, -19.8), Vector3(52, 0.12, 0.12), rail_mat)
	_box(Vector3(0, DECK_Y + 0.55, 19.8), Vector3(52, 0.12, 0.12), rail_mat)
	# West rail splits around the observation-platform ramp at z -11.
	_box(Vector3(-29.8, DECK_Y + 0.55, -14.6), Vector3(0.12, 0.12, 4.8), rail_mat)
	_box(Vector3(-29.8, DECK_Y + 0.55, 3.6), Vector3(0.12, 0.12, 26.8), rail_mat)
	# East rail splits around the bridge exit at z 14.
	_box(Vector3(29.8, DECK_Y + 0.55, 7.3), Vector3(0.12, 0.12, 10.6), rail_mat)
	_box(Vector3(29.8, DECK_Y + 0.55, 17.2), Vector3(0.12, 0.12, 3.6), rail_mat)

	_build_bunkhouse()
	_build_galley()
	_build_rec_room()
	_build_machine_shop()
	_build_floodlights()

	# Scattered deck props.
	for i in range(6):
		_cyl(Vector3(-6 + i * 2.2, DECK_Y + 0.5, -16), 0.45, 1.0, MatLib.rust_steel())
	_box(Vector3(8, DECK_Y + 0.4, -14), Vector3(2.4, 0.8, 1.2), MatLib.wood()) # pallet stack

func _build_bunkhouse() -> void:
	var mat: Material = MatLib.concrete()
	var y: float = DECK_Y
	# Block shell x -28..-8, z 4..18; corridor z 10..12; entrance east at corridor.
	_wall(Vector3(-28, y, 4), Vector3(-8, y, 4), WALL_H, mat)
	_wall(Vector3(-28, y, 18), Vector3(-8, y, 18), WALL_H, mat)
	_wall(Vector3(-28, y, 4), Vector3(-28, y, 18), WALL_H, mat)
	_wall(Vector3(-8, y, 4), Vector3(-8, y, 18), WALL_H, mat, 0.5) # east entrance into corridor
	_box(Vector3(-18, y + WALL_H, 11), Vector3(20.5, 0.25, 14.5), mat)
	_box(Vector3(-18, y + 0.035, 11), Vector3(19.5, 0.03, 13.5), MatLib.lino_floor(), self, false)
	# Cabin dividers: south row (z 4..10), north row (z 12..18), corridor between.
	var xs := [-28.0, -21.33, -14.66, -8.0]
	for i in range(3):
		# corridor walls with a door into each cabin
		_wall(Vector3(xs[i], y, 10), Vector3(xs[i + 1], y, 10), WALL_H, mat, 0.5)
		_wall(Vector3(xs[i], y, 12), Vector3(xs[i + 1], y, 12), WALL_H, mat, 0.5)
	for i in range(1, 3):
		_wall(Vector3(xs[i], y, 4), Vector3(xs[i], y, 10), WALL_H, mat)
		_wall(Vector3(xs[i], y, 12), Vector3(xs[i], y, 18), WALL_H, mat)
	# Beds: made (neat) vs unmade (tossed) — the first clue, wordless.
	var bed_positions := [
		Vector3(-25.5, y, 6.5), Vector3(-18.8, y, 6.5), Vector3(-12.0, y, 6.5),
		Vector3(-25.5, y, 15.5), Vector3(-18.8, y, 15.5), Vector3(-12.0, y, 15.5),
	]
	for i in range(bed_positions.size()):
		var p: Vector3 = bed_positions[i]
		_box(p + Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 2.1), MatLib.wood())
		if i % 2 == 0:
			_box(p + Vector3(0, 0.66, 0.2), Vector3(0.95, 0.12, 1.6), MatLib.flat(Color(0.75, 0.78, 0.8))) # made
		else:
			var blanket := _box(p + Vector3(0.2, 0.72, 0.4), Vector3(0.8, 0.18, 0.9), MatLib.flat(Color(0.55, 0.58, 0.62)))
			blanket.rotation.y = 0.4 # unmade
		# Lockers
		_box(p + Vector3(1.2, 0.9, -0.8), Vector3(0.5, 1.8, 0.5), MatLib.painted_steel())
	_readable("crew_letter_1", "Unsent Letter", Vector3(-18.8, y + 0.75, 7.3), Vector3(0.3, 0.05, 0.4))
	_readable("crew_letter_2", "Note in a Locker", Vector3(-17.6, y + 1.3, 14.7), Vector3(0.28, 0.35, 0.05))

func _build_galley() -> void:
	var mat: Material = MatLib.concrete()
	var y: float = DECK_Y
	_wall(Vector3(-2, y, 8), Vector3(14, y, 8), WALL_H, mat, 0.5)   # south door
	_wall(Vector3(-2, y, 18), Vector3(14, y, 18), WALL_H, mat)
	_wall(Vector3(-2, y, 8), Vector3(-2, y, 18), WALL_H, mat)
	_wall(Vector3(14, y, 8), Vector3(14, y, 18), WALL_H, mat)
	_box(Vector3(6, y + WALL_H, 13), Vector3(16.5, 0.25, 10.5), mat)
	_box(Vector3(6, y + 0.035, 13), Vector3(15.5, 0.03, 9.5), MatLib.kitchen_tile(), self, false)
	# Counter along the north wall with food.
	_box(Vector3(6, y + 0.5, 17), Vector3(10, 1.0, 1.2), MatLib.painted_steel())
	_takeable("canned_food", "Canned Food", Vector3(3, y + 1.01, 17), Vector3(0.25, 0.3, 0.25))
	_takeable("canned_food", "Canned Food", Vector3(5, y + 1.01, 17), Vector3(0.25, 0.3, 0.25))
	_takeable("canned_peaches", "Canned Peaches", Vector3(8, y + 1.01, 17), Vector3(0.25, 0.3, 0.25))
	_crate(["canned_food", "canned_food"], "Pantry Crate", Vector3(12.5, y + 0.01, 16.5))
	_readable("rationing_memo", "Operations Memo", Vector3(0.5, y + 1.6, 17.8), Vector3(0.35, 0.45, 0.06))
	# Tables with full coffee cups — the signature image.
	var table_positions := [Vector3(2, y, 11), Vector3(8, y, 11), Vector3(2, y, 14.5), Vector3(8, y, 14.5)]
	for tp in table_positions:
		_box(tp + Vector3(0, 0.45, 0), Vector3(1.8, 0.08, 1.0), MatLib.wood())
		_box(tp + Vector3(0, 0.2, 0), Vector3(0.15, 0.42, 0.15), MatLib.wood())
		for cx in [-0.5, 0.4]:
			var cup := CSGCylinder3D.new()
			cup.radius = 0.06
			cup.height = 0.1
			cup.material = MatLib.flat(Color(0.9, 0.9, 0.88))
			cup.use_collision = false
			add_child(cup)
			cup.position = tp + Vector3(cx, 0.55, 0.15)
	_readable("coffee_note", "Napkin Under a Cup", Vector3(8.6, y + 0.52, 11.3), Vector3(0.25, 0.03, 0.25))

func _build_rec_room() -> void:
	var mat: Material = MatLib.concrete()
	var y: float = DECK_Y
	_wall(Vector3(18, y, 8), Vector3(28, y, 8), WALL_H, mat)
	_wall(Vector3(18, y, 18), Vector3(28, y, 18), WALL_H, mat)
	_wall(Vector3(18, y, 8), Vector3(18, y, 18), WALL_H, mat, 0.3)  # west door
	_wall(Vector3(28, y, 8), Vector3(28, y, 18), WALL_H, mat)
	_box(Vector3(23, y + WALL_H, 13), Vector3(10.5, 0.25, 10.5), mat)
	_box(Vector3(23, y + 0.035, 13), Vector3(9.5, 0.03, 9.5), MatLib.rubber_floor(), self, false)
	# Dartboard, dead TV, couch.
	var dart := CSGCylinder3D.new()
	dart.radius = 0.3
	dart.height = 0.08
	dart.material = MatLib.flat(Color(0.6, 0.25, 0.15))
	dart.use_collision = false
	add_child(dart)
	dart.position = Vector3(27.8, y + 1.7, 13)
	dart.rotation.z = deg_to_rad(90)
	_box(Vector3(20, y + 1.0, 17.2), Vector3(1.4, 0.9, 0.4), MatLib.dark_metal()) # dead TV
	_box(Vector3(23, y + 0.35, 9.2), Vector3(2.4, 0.7, 1.0), MatLib.flat(Color(0.35, 0.3, 0.28))) # couch
	_readable("quiet_rig_note", "Tally Book Page", Vector3(27.7, y + 0.9, 14.2), Vector3(0.3, 0.4, 0.06))

func _build_machine_shop() -> void:
	var mat: Material = MatLib.concrete()
	var y: float = DECK_Y
	# Locked for v0.1 — visible through the window, teasing the future.
	_wall(Vector3(-28, y, -18), Vector3(-14, y, -18), WALL_H, mat)
	_wall(Vector3(-28, y, -6), Vector3(-14, y, -6), WALL_H, mat)
	_wall(Vector3(-28, y, -18), Vector3(-28, y, -6), WALL_H, mat)
	# East wall: solid segments + window pane + locked door.
	_wall(Vector3(-14, y, -18), Vector3(-14, y, -13), WALL_H, mat, 0.6)
	_wall(Vector3(-14, y, -11), Vector3(-14, y, -6), WALL_H, mat)
	var pane := _box(Vector3(-14, y + 1.6, -12), Vector3(0.1, 1.4, 2.0), null)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.75, 0.8, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pane.material = glass
	_box(Vector3(-14, y + 0.4, -12), Vector3(0.15, 0.8, 2.0), mat)   # sill below window
	_box(Vector3(-14, y + 2.7, -12), Vector3(0.15, 1.0, 2.0), mat)   # header above window
	_box(Vector3(-21, y + WALL_H, -12), Vector3(14.5, 0.25, 12.5), mat)
	var door := InteractDoor.new()
	door.display_name = "Machine Shop"
	door.locked = true
	add_child(door)
	door.global_position = Vector3(-14, y, -14.5)
	door.build_box_visual(Vector3(0.12, 2.2, 1.15), MatLib.flat(Color(0.4, 0.42, 0.4)).albedo_color)
	_readable("machine_shop_sign", "Posted Notice", Vector3(-13.85, y + 1.5, -10.6), Vector3(0.05, 0.4, 0.3))
	# Interior tease, visible through the pane: drafting table + half-built raft planks.
	_box(Vector3(-20, y + 0.55, -12), Vector3(2.0, 1.1, 1.2), MatLib.wood())
	_box(Vector3(-24, y + 0.3, -9), Vector3(2.6, 0.2, 1.6), MatLib.wood())
	_box(Vector3(-24, y + 0.5, -9.4), Vector3(2.2, 0.15, 0.6), MatLib.wood())

func _build_floodlights() -> void:
	var zone := LightZone.new()
	zone.circuit_id = "topside_floodlights"
	zone.zone_extents = Vector3(38, 9, 20)
	add_child(zone)
	zone.global_position = Vector3(0, DECK_Y + 2.5, -1)
	for pole_pos in [Vector3(-14, 0, -8), Vector3(14, 0, -8), Vector3(-14, 0, 7), Vector3(14, 0, 7)]:
		var p: Vector3 = Vector3(pole_pos.x, DECK_Y, pole_pos.z)
		_box(p + Vector3(0, 1.75, 0), Vector3(0.25, 3.5, 0.25), MatLib.painted_steel())
		var head := _box(p + Vector3(0, 3.6, 0), Vector3(0.7, 0.4, 0.7), MatLib.flat(Color(0.9, 0.85, 0.7), true, 0.0))
		var spot := SpotLight3D.new()
		spot.spot_range = 18.0
		spot.spot_angle = 55.0
		spot.light_energy = 10.0
		spot.light_volumetric_fog_energy = 2.5   # visible beams in night air
		spot.light_color = Color(1.0, 0.9, 0.7)   # warm light is player-made safety (canon)
		spot.shadow_enabled = true
		zone.add_light(spot)
		spot.global_position = p + Vector3(0, 3.4, 0)
		spot.rotation.x = deg_to_rad(-90)
		# Emissive head turns on with the circuit.
		PowerGrid.circuit_powered.connect(func(id: String) -> void:
			if id == "topside_floodlights" and is_instance_valid(head):
				head.material = MatLib.flat(Color(1.0, 0.95, 0.8), true, 2.0))
	# Space heater near the galley south wall — warmth restored in the powered zone.
	_box(Vector3(11, DECK_Y + 0.5, 6.5), Vector3(0.9, 1.0, 0.5), MatLib.flat(Color(0.65, 0.3, 0.15)))
	var heat := WarmthZone.new()
	heat.mode = 1
	heat.requires_circuit = "topside_floodlights"
	heat.setup(Vector3(7, 3, 6))
	add_child(heat)
	heat.global_position = Vector3(11, DECK_Y + 1.5, 6.5)
	# PA speaker on a pole (the dusk beat).
	_box(Vector3(14, DECK_Y + 3.0, 7.4), Vector3(0.4, 0.3, 0.3), MatLib.dark_metal())

# ---------- Z5: High Iron ----------

func _build_high_iron() -> void:
	var mat: Material = MatLib.rust_steel()
	# Lattice mast posts x 0..4, z -16..-12, rising to the lookout.
	for px in [0.0, 4.0]:
		for pz in [-16.0, -12.0]:
			_box(Vector3(px, DECK_Y + 8, pz), Vector3(0.3, 16, 0.3), mat)
	# Cross-braces every 4m.
	for i in range(4):
		var by: float = DECK_Y + 3 + i * 4
		_box(Vector3(2, by, -16), Vector3(4, 0.2, 0.2), mat)
		_box(Vector3(2, by, -12), Vector3(4, 0.2, 0.2), mat)
	# Lookout platform + rails.
	_box(Vector3(2, DECK_Y + 16, -14), Vector3(6, 0.3, 6), MatLib.deck_plate())
	for r in [[Vector3(2, DECK_Y + 16.6, -11.1), Vector3(6, 0.1, 0.1)], [Vector3(2, DECK_Y + 16.6, -16.9), Vector3(6, 0.1, 0.1)],
			[Vector3(-0.9, DECK_Y + 16.6, -14), Vector3(0.1, 0.1, 6)], [Vector3(4.9, DECK_Y + 16.6, -14), Vector3(0.1, 0.1, 6)]]:
		_box(r[0], r[1], mat)
	_ladder(Vector3(-0.35, DECK_Y, -14), 16.0, 90.0, "Mast Ladder", 1.2)
	_readable("lookout_note", "Weathered Notebook", Vector3(3.4, DECK_Y + 16.5, -14), Vector3(0.3, 0.06, 0.4))

# ---------- The SPHL ----------

func _build_sphl() -> void:
	var comb := CSGCombiner3D.new()
	comb.use_collision = true
	add_child(comb)
	var hull := CSGBox3D.new()
	hull.size = Vector3(7, 3.0, 2.8)
	hull.material = MatLib.sphl_orange()
	comb.add_child(hull)
	hull.position = Vector3(18, WET_Y + 1.3, -24)
	var interior := CSGBox3D.new()
	interior.size = Vector3(6.2, 2.3, 2.2)
	interior.operation = CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(interior)
	interior.position = Vector3(18, WET_Y + 1.35, -24)
	var hatch_hole := CSGBox3D.new()
	hatch_hole.size = Vector3(1.2, 2.0, 0.8)
	hatch_hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(hatch_hole)
	hatch_hole.position = Vector3(20, WET_Y + 1.25, -22.8)
	# Hatch door (locked until the countdown ends).
	sphl_hatch = InteractDoor.new()
	sphl_hatch.display_name = "Hatch"
	sphl_hatch.locked = false   # openable on the first E press — no forced cold-open wait
	add_child(sphl_hatch)
	sphl_hatch.global_position = Vector3(19.42, WET_Y + 0.25, -22.75)
	sphl_hatch.build_box_visual(Vector3(1.16, 2.0, 0.15), MatLib.sphl_orange().albedo_color)
	for c in sphl_hatch.get_children():
		if c is MeshInstance3D or c is CollisionShape3D:
			c.position = Vector3(0.58, 1.0, 0)   # hinge at edge
	# Gangplank to the wet deck.
	_box(Vector3(20, WET_Y + 0.02, -22.4), Vector3(1.3, 0.12, 1.6), MatLib.wood())
	# Interior: red emergency light, countdown readout, two readables, water ration.
	var red := OmniLight3D.new()
	red.light_color = Color(0.9, 0.15, 0.1)
	red.light_energy = 1.6
	red.omni_range = 5.0
	red.light_volumetric_fog_energy = 2.0
	add_child(red)
	red.global_position = Vector3(17, WET_Y + 2.2, -24)
	countdown_label = Label3D.new()
	countdown_label.text = "PRESSURE — EQUALIZED"
	countdown_label.font_size = 40
	countdown_label.pixel_size = 0.004
	countdown_label.modulate = Color(0.3, 0.9, 0.4)
	add_child(countdown_label)
	countdown_label.global_position = Vector3(15.05, WET_Y + 1.6, -24)
	countdown_label.rotation.y = deg_to_rad(-90)
	_readable("sphl_manual", "Survival Manual", Vector3(16, WET_Y + 1.4, -23.05), Vector3(0.3, 0.4, 0.05))
	_readable("pressure_log", "Pressure Log", Vector3(18.5, WET_Y + 1.4, -24.95), Vector3(0.3, 0.4, 0.05))
	_takeable("water_ration", "Water Ration", Vector3(17, WET_Y + 0.45, -24.6), Vector3(0.2, 0.25, 0.2))
	# Mooring cradle under the pod.
	_box(Vector3(18, WET_Y - 0.6, -23.2), Vector3(1.0, 1.2, 0.4), MatLib.rust_steel())
	_box(Vector3(18, WET_Y - 0.6, -24.8), Vector3(1.0, 1.2, 0.4), MatLib.rust_steel())

# ---------- Accessibility: every area reachable ----------

func _build_access() -> void:
	# Wet Deck -> south pontoon (the under-rig walkway: barnacles, eel, jellies up close).
	_ladder(Vector3(7.8, 0.95, -12), 1.2, 90.0, "Pontoon Ladder", 0.9)
	# Wet Deck -> pump room roof (small vantage, stashed crate).
	_ladder(Vector3(18.25, WET_Y, -8), 3.5, -90.0, "Roof Ladder", 1.0)
	_crate(["flare", "canned_peaches"], "Weather Crate", Vector3(14, WET_Y + WALL_H + 0.13, -8.5))
	# (C-deck terrace access is the external west stair — see RigExterior.)
	# Topside -> bunkhouse roof (vent fans, antenna array, and the long view west).
	_ladder(Vector3(-7.75, DECK_Y, 15.5), 3.55, 90.0, "Bunkhouse Roof Ladder", 1.0)
	_readable("roof_mark", "Chalk Tally", Vector3(-18, DECK_Y + WALL_H + 0.4, 8), Vector3(0.4, 0.05, 0.3))

# ---------- Interior decoration (GDD room dressing) ----------

func _cyl_nc(pos: Vector3, radius: float, height: float, mat: Material) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = height
	c.material = mat
	c.use_collision = false
	add_child(c)
	c.position = pos
	return c

func _decorate_interiors() -> void:
	_decorate_bunkhouse()
	_decorate_galley()
	_decorate_rec_room()
	_decorate_machine_shop()
	_decorate_pump_room()
	_decorate_sphl()
	_decorate_electrical()
	_add_wall_details()  # pipes, labels, signs, conduit

func _decorate_bunkhouse() -> void:
	var y: float = DECK_Y
	var bed_positions := [
		Vector3(-25.5, y, 6.5), Vector3(-18.8, y, 6.5), Vector3(-12.0, y, 6.5),
		Vector3(-25.5, y, 15.5), Vector3(-18.8, y, 15.5), Vector3(-12.0, y, 15.5),
	]
	for i in range(bed_positions.size()):
		var p: Vector3 = bed_positions[i]
		# Pillow at the head of every bed.
		_box(p + Vector3(0, 0.68, -0.8), Vector3(0.55, 0.1, 0.35), MatLib.flat(Color(0.88, 0.88, 0.84)), self, false)
		if i % 2 == 1:
			# Boots kicked off at the foot of the slept-in beds.
			_box(p + Vector3(-0.35, 0.12, 1.3), Vector3(0.14, 0.24, 0.3), MatLib.flat(Color(0.2, 0.16, 0.12)), self, false)
			_box(p + Vector3(-0.15, 0.12, 1.35), Vector3(0.14, 0.24, 0.3), MatLib.flat(Color(0.2, 0.16, 0.12)), self, false)
			# Locker door left hanging open.
			var door := _box(p + Vector3(1.45, 0.9, -0.45), Vector3(0.04, 1.7, 0.45), MatLib.painted_steel(), self, false)
			door.rotation.y = 0.7
	# Corridor light strip (dead — the grid is down; it stays a dark fixture).
	_box(Vector3(-18, y + 3.0, 11), Vector3(16, 0.08, 0.3), MatLib.dark_metal(), self, false)
	# A duffel someone packed and never took.
	_box(Vector3(-21.5, y + 0.2, 8.5), Vector3(0.5, 0.4, 0.95), MatLib.flat(Color(0.3, 0.35, 0.28)), self, false)
	# Faded poster of somewhere green.
	_box(Vector3(-12.0, y + 1.8, 17.85), Vector3(0.7, 0.9, 0.03), MatLib.flat(Color(0.35, 0.5, 0.4)), self, false)

func _decorate_galley() -> void:
	var y: float = DECK_Y
	# Stove with two burners and one pot still on the heat that never came.
	_box(Vector3(11.5, y + 0.5, 16.2), Vector3(1.3, 1.0, 1.2), MatLib.dark_metal())
	_cyl_nc(Vector3(11.2, y + 1.02, 15.9), 0.18, 0.03, MatLib.flat(Color(0.1, 0.1, 0.1)))
	_cyl_nc(Vector3(11.8, y + 1.02, 16.5), 0.18, 0.03, MatLib.flat(Color(0.1, 0.1, 0.1)))
	_cyl_nc(Vector3(11.2, y + 1.15, 15.9), 0.2, 0.24, MatLib.painted_steel())
	# Fridge, door ajar.
	_box(Vector3(-1.2, y + 0.95, 15.2), Vector3(0.9, 1.9, 0.9), MatLib.flat(Color(0.82, 0.84, 0.82)))
	var fdoor := _box(Vector3(-0.7, y + 0.95, 15.85), Vector3(0.06, 1.85, 0.85), MatLib.flat(Color(0.78, 0.8, 0.78)), self, false)
	fdoor.rotation.y = 0.5
	# Wall shelves with canned rows.
	for sy in [1.6, 2.2]:
		_box(Vector3(-1.6, y + sy, 12.5), Vector3(0.35, 0.06, 3.2), MatLib.wood(), self, false)
		for i in range(5):
			_cyl_nc(Vector3(-1.6, y + sy + 0.12, 11.2 + i * 0.6), 0.09, 0.18, MatLib.flat(Color(0.6, 0.58, 0.5)))
	# Pan rail over the counter.
	_cyl_nc(Vector3(9.5, y + 2.2, 17.4), 0.02, 3.0, MatLib.dark_metal()).rotation.z = deg_to_rad(90)
	for i in range(3):
		_cyl_nc(Vector3(8.3 + i * 1.1, y + 1.95, 17.4), 0.22, 0.04, MatLib.dark_metal())

func _decorate_rec_room() -> void:
	var y: float = DECK_Y
	# Rug, low table, and a card game nobody finished.
	_box(Vector3(23, y + 0.02, 12.5), Vector3(3.4, 0.03, 2.4), MatLib.flat(Color(0.4, 0.2, 0.18)), self, false)
	_box(Vector3(23, y + 0.28, 12.5), Vector3(1.5, 0.08, 0.95), MatLib.wood())
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in range(7):
		var card := _box(Vector3(23 + rng.randf_range(-0.6, 0.6), y + 0.34, 12.5 + rng.randf_range(-0.35, 0.35)),
			Vector3(0.12, 0.005, 0.18), MatLib.flat(Color(0.92, 0.92, 0.88)), self, false)
		card.rotation.y = rng.randf_range(0, TAU)
	# Bookshelf with two rows.
	_box(Vector3(25.5, y + 1.0, 17.6), Vector3(1.8, 2.0, 0.35), MatLib.wood())
	for row in [0.6, 1.5]:
		for i in range(6):
			_box(Vector3(24.85 + i * 0.24, y + row + 0.25, 17.55), Vector3(0.16, 0.5, 0.24),
				MatLib.flat(Color(0.25 + (i % 3) * 0.12, 0.22, 0.3 - (i % 2) * 0.08)), self, false)
	# Wall clock, stopped at 2:47 — nobody wound it again.
	_cyl_nc(Vector3(18.2, y + 2.3, 15), 0.28, 0.05, MatLib.flat(Color(0.9, 0.9, 0.86))).rotation.z = deg_to_rad(90)
	var hand_h := _box(Vector3(18.26, y + 2.34, 15.04), Vector3(0.02, 0.12, 0.02), MatLib.flat(Color(0.1, 0.1, 0.1)), self, false)
	hand_h.rotation.x = deg_to_rad(52)
	var hand_m := _box(Vector3(18.26, y + 2.3, 14.92), Vector3(0.02, 0.2, 0.02), MatLib.flat(Color(0.1, 0.1, 0.1)), self, false)
	hand_m.rotation.x = deg_to_rad(-64)

func _decorate_machine_shop() -> void:
	var y: float = DECK_Y
	# Pegboard of tools, visible through the window — the tease continues.
	_box(Vector3(-21, y + 1.9, -17.6), Vector3(3.0, 1.4, 0.06), MatLib.flat(Color(0.75, 0.72, 0.6)), self, false)
	var tool_colors := [Color(0.7, 0.3, 0.2), Color(0.3, 0.4, 0.6), Color(0.5, 0.5, 0.5), Color(0.7, 0.6, 0.2), Color(0.4, 0.4, 0.4), Color(0.6, 0.35, 0.25)]
	for i in range(6):
		_box(Vector3(-22.2 + i * 0.5, y + 1.9 + (0.25 if i % 2 == 0 else -0.2), -17.55),
			Vector3(0.1, 0.4, 0.06), MatLib.flat(tool_colors[i]), self, false)
	# Vise on the drafting table; parts bins along the wall.
	_box(Vector3(-19.6, y + 1.2, -12), Vector3(0.35, 0.25, 0.3), MatLib.dark_metal(), self, false)
	for i in range(3):
		_box(Vector3(-26.5, y + 0.2, -14.5 + i * 1.4), Vector3(0.8, 0.4, 1.0),
			MatLib.flat([Color(0.55, 0.25, 0.2), Color(0.25, 0.35, 0.5), Color(0.45, 0.45, 0.4)][i]))

func _decorate_pump_room() -> void:
	var y: float = WET_Y
	# Pipe runs along the north wall, one valve wheel each.
	for py in [2.6, 3.2]:
		var pipe := _cyl_nc(Vector3(14, y + py, -6.5), 0.12, 7.0, MatLib.rusty_metal())
		pipe.rotation.z = deg_to_rad(90)
	for vx in [12.0, 16.0]:
		var wheel := CSGTorus3D.new()
		wheel.inner_radius = 0.12
		wheel.outer_radius = 0.22
		wheel.material = MatLib.flat(Color(0.6, 0.15, 0.1))
		wheel.use_collision = false
		add_child(wheel)
		wheel.position = Vector3(vx, y + 2.6, -6.75)
		wheel.rotation.x = deg_to_rad(90)
	# Gauges on the dead pump — needles all at zero.
	for gx in [11.6, 12.4]:
		_cyl_nc(Vector3(gx, y + 1.9, -11.2), 0.11, 0.04, MatLib.flat(Color(0.88, 0.88, 0.82))).rotation.x = deg_to_rad(90)

func _decorate_sphl() -> void:
	var y: float = WET_Y
	# Bench seats, a first-aid box, an overhead grab rail — the pod you woke up in.
	_box(Vector3(17.0, y + 0.42, -24.8), Vector3(3.5, 0.45, 0.45), MatLib.flat(Color(0.75, 0.4, 0.15)))
	_box(Vector3(16.0, y + 0.42, -23.2), Vector3(1.8, 0.45, 0.45), MatLib.flat(Color(0.75, 0.4, 0.15)))
	_box(Vector3(15.05, y + 1.3, -23.6), Vector3(0.12, 0.4, 0.5), MatLib.flat(Color(0.92, 0.92, 0.9)), self, false)
	_box(Vector3(15.12, y + 1.3, -23.6), Vector3(0.02, 0.26, 0.08), MatLib.flat(Color(0.8, 0.15, 0.1)), self, false)
	_box(Vector3(15.12, y + 1.3, -23.6), Vector3(0.02, 0.08, 0.26), MatLib.flat(Color(0.8, 0.15, 0.1)), self, false)
	_cyl_nc(Vector3(17.5, y + 2.05, -24), 0.03, 4.0, MatLib.painted_steel()).rotation.z = deg_to_rad(90)

func _decorate_electrical() -> void:
	# Breaker Room 4-A: conduit drop and a hazard strip underfoot.
	_box(Vector3(23, 10.35, 9.55), Vector3(0.08, 0.7, 0.08), MatLib.dark_metal(), self, false)
	_box(Vector3(23, 10.02, 9.0), Vector3(1.6, 0.02, 0.8), MatLib.flat(Color(0.8, 0.7, 0.1)), self, false)
	# Machinery room: pipe run + a gauge on the dead machine.
	var pipe := _cyl_nc(Vector3(29.6, 8.2, 6), 0.1, 7.0, MatLib.rusty_metal())
	pipe.rotation.x = deg_to_rad(90)
	_cyl_nc(Vector3(27, 7.1, 5.35), 0.1, 0.04, MatLib.flat(Color(0.88, 0.88, 0.82))).rotation.x = deg_to_rad(90)

# ---------- Environmental objects ----------

func _build_env_objects() -> void:
	# Rigging bench + hook ingredients: rope by the crane, prybar in the pump room.
	var bench := CraftBench.new()
	add_child(bench)
	bench.global_position = Vector3(19.5, WET_Y, -19.5)
	bench.build_box_visual(Vector3(1.6, 0.9, 0.7), Color(0.5, 0.42, 0.3), false, true)
	_box(Vector3(19.5, WET_Y + 0.93, -19.5), Vector3(1.7, 0.06, 0.8), MatLib.wood(), self, false)
	_takeable("rope", "Rope Coil", Vector3(17.2, DECK_Y + 0.01, -15.8), Vector3(0.45, 0.3, 0.45))
	_takeable("prybar", "Prybar", Vector3(12.8, WET_Y + 1.81, -12.0), Vector3(0.15, 0.12, 0.9))
	# 1. Oil drums — loose physics props, wet deck and topside.
	for p in [Vector3(23.5, WET_Y + 0.6, -15.5), Vector3(24.4, WET_Y + 0.6, -14.6),
			Vector3(10.5, WET_Y + 0.6, -17.5), Vector3(6.5, DECK_Y + 0.6, -13.2),
			Vector3(-2.5, DECK_Y + 0.6, -17.2)]:
		EnvObjects.oil_drum(self, p)
	# 2. Life rings — one takeable by the SPHL, cosmetic ones on the topside rails.
	EnvObjects.life_ring(self, Vector3(16.1, WET_Y + 1.4, -20.5), true)
	EnvObjects.life_ring(self, Vector3(0, DECK_Y + 1.1, -19.75))
	EnvObjects.life_ring(self, Vector3(-20, DECK_Y + 1.1, 19.75))
	# 3. Fire barrel — warmth you don't need the grid for, out on the wet deck.
	var barrel := EnvObjects.FireBarrel.new()
	add_child(barrel)
	barrel.global_position = Vector3(23, WET_Y + 0.01, -11)
	# 4. Crane — hook swinging slow over the south deck.
	var crane := EnvObjects.CraneHook.new()
	add_child(crane)
	crane.global_position = Vector3(18, DECK_Y, -17)
	crane.rotation.y = deg_to_rad(180)
	# 5. Antenna array with the blinking beacon, on the galley roof.
	var antenna := EnvObjects.AntennaArray.new()
	add_child(antenna)
	antenna.global_position = Vector3(-16, DECK_Y + WALL_H + 0.15, 8)   # bunkhouse roof (open sky)
	# 6. Vent fans on the bunkhouse roof (the galley roof is enclosed by Deck B now).
	for p in [Vector3(-24, DECK_Y + WALL_H + 0.15, 8), Vector3(-14, DECK_Y + WALL_H + 0.15, 14),
			Vector3(-20, DECK_Y + WALL_H + 0.15, 14)]:
		var fan := EnvObjects.VentFan.new()
		add_child(fan)
		fan.global_position = p

# ---------- Horizon ----------

func _build_imposters() -> void:
	# The rig line, receding — bridges visibly more broken with distance (GDD 5.1 Z5).
	var mat: Material = MatLib.flat(Color(0.16, 0.19, 0.23))
	var line_positions := [
		Vector3(300, 0, 80), Vector3(520, 0, 145), Vector3(780, 0, 215),
		Vector3(1080, 0, 290), Vector3(1420, 0, 370), Vector3(1800, 0, 460),
	]
	var prev: Vector3 = Vector3(0, 0, 0)
	for i in range(line_positions.size()):
		var p: Vector3 = line_positions[i]
		var hull := CSGBox3D.new()
		hull.size = Vector3(56, 14, 34)
		hull.material = mat
		hull.use_collision = false
		add_child(hull)
		hull.position = p + Vector3(0, 11, 0)
		var tower := CSGBox3D.new()
		tower.size = Vector3(8, 26, 8)
		tower.material = mat
		tower.use_collision = false
		add_child(tower)
		tower.position = p + Vector3(-12, 30, 4)
		# Bridge stubs toward the previous rig: shorter (more broken) with distance.
		var frac: float = maxf(0.08, 0.5 - i * 0.08)
		var gap_dir: Vector3 = (p - prev)
		var stub_len: float = gap_dir.length() * frac
		var u: Vector3 = gap_dir.normalized()
		if i == 0:
			# The near span is REAL: walkable off the deck edge, torn off over the sea.
			# (It used to be a collisionless 155m scenery slab the player fell through.)
			_build_broken_bridge(u)
		else:
			var stub_a := CSGBox3D.new()
			stub_a.size = Vector3(stub_len, 1.5, 2.5)
			stub_a.material = mat
			stub_a.use_collision = false
			add_child(stub_a)
			stub_a.position = prev + u * (stub_len * 0.5) + Vector3(0, 15, 0)
			stub_a.rotation.y = -atan2(u.z, u.x)
		var stub_b := CSGBox3D.new()
		stub_b.size = Vector3(stub_len, 1.5, 2.5)
		stub_b.material = mat
		stub_b.use_collision = false
		add_child(stub_b)
		stub_b.position = p - u * (stub_len * 0.5) + Vector3(0, 15, 0)
		stub_b.rotation.y = -atan2(u.z, u.x)
		prev = p

func _add_wall_details() -> void:
	# Conduit runs hugging REAL wall faces. Cylinder axis is local Y: along X needs
	# rotation.z = 90deg, along Z needs rotation.x = 90deg.
	# Galley south exterior face (wall at z=8, face at z 7.875).
	var c1 := _cyl_nc(Vector3(6, DECK_Y + 2.6, 7.8), 0.06, 14.0, MatLib.dark_metal())
	c1.rotation.z = deg_to_rad(90)
	# Rec room west exterior face (wall at x=18, face at x 17.875).
	var c2 := _cyl_nc(Vector3(17.8, DECK_Y + 2.6, 13), 0.06, 8.0, MatLib.dark_metal())
	c2.rotation.x = deg_to_rad(90)
	# Pump room north exterior face (wall at z=-6, face at z -5.875).
	var c3 := _cyl_nc(Vector3(14, WET_Y + 2.7, -5.82), 0.06, 7.0, MatLib.dark_metal())
	c3.rotation.z = deg_to_rad(90)
	# Junction drops at the conduit ends.
	for dp in [Vector3(-0.9, DECK_Y + 1.6, 7.8), Vector3(12.9, DECK_Y + 1.6, 7.8)]:
		_box(dp, Vector3(0.1, 2.0, 0.1), MatLib.dark_metal(), self, false)

	# Pressure gauges flat against verified wall faces (flat face = cylinder axis
	# pierces the wall: axis along Z -> rotation.x, axis along X -> rotation.z).
	var g1 := _cyl_nc(Vector3(13, WET_Y + 1.9, -5.85), 0.12, 0.05, MatLib.flat(Color(0.88, 0.88, 0.82)))
	g1.rotation.x = deg_to_rad(90)   # pump room north face
	var g2 := _cyl_nc(Vector3(21.85, DECK_Y + 1.7, -1.5), 0.12, 0.05, MatLib.flat(Color(0.88, 0.88, 0.82)))
	g2.rotation.z = deg_to_rad(90)   # stair tower west face
	var g3 := _cyl_nc(Vector3(-13.85, DECK_Y + 1.9, -8.5), 0.12, 0.05, MatLib.flat(Color(0.88, 0.88, 0.82)))
	g3.rotation.z = deg_to_rad(90)   # machine shop east face

	# Hazard strips painted on real floors: stair tower entrance + pump room door.
	_box(Vector3(26, WET_Y + 0.02, -6.8), Vector3(2.2, 0.02, 1.0), MatLib.flat(Color(0.8, 0.7, 0.1)), self, false)
	_box(Vector3(14, WET_Y + 0.02, -14.7), Vector3(1.6, 0.02, 0.9), MatLib.flat(Color(0.8, 0.7, 0.1)), self, false)

	# Painted directional arrows on the wet deck (toward the stair tower).
	_box(Vector3(16, WET_Y + 0.03, -18), Vector3(0.6, 0.01, 0.3), MatLib.flat(Color(0.3, 0.6, 0.9)), self, false)
	_box(Vector3(20, WET_Y + 0.03, -15), Vector3(0.3, 0.01, 0.6), MatLib.flat(Color(0.3, 0.6, 0.9)), self, false)

	# Grab rails running ALONG their walls (cylinder axis along the wall direction).
	var r1 := _cyl_nc(Vector3(6, DECK_Y + 1.1, 7.82), 0.04, 3.0, MatLib.painted_steel())
	r1.rotation.z = deg_to_rad(90)   # galley south face, along X
	var r2 := _cyl_nc(Vector3(17.82, DECK_Y + 1.1, 12), 0.04, 3.0, MatLib.painted_steel())
	r2.rotation.x = deg_to_rad(90)   # rec room west face, along Z
	var r3 := _cyl_nc(Vector3(-18, DECK_Y + 1.1, 3.82), 0.04, 3.0, MatLib.painted_steel())
	r3.rotation.z = deg_to_rad(90)   # bunkhouse south face, along X

	# Maintenance plaques flush on wall faces (thin axis = wall normal).
	_box(Vector3(15, WET_Y + 2.2, -5.86), Vector3(0.4, 0.25, 0.03), MatLib.flat(Color(0.15, 0.15, 0.15)), self, false)
	_box(Vector3(24.8, 11.6, 9.86), Vector3(0.5, 0.3, 0.03), MatLib.flat(Color(0.15, 0.15, 0.15)), self, false)
	_box(Vector3(21.86, DECK_Y + 2.2, 0.5), Vector3(0.03, 0.15, 0.8), MatLib.flat(Color(0.15, 0.15, 0.15)), self, false)

# ---------- Industrial dressing: beams, pipes, wiring ----------

## Straight structural member between two points (decoration — MeshInstance, no collision).
func _beam(a: Vector3, b: Vector3, thickness: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thickness, a.distance_to(b), thickness)
	bm.material = mat
	mi.mesh = bm
	add_child(mi)
	mi.global_position = (a + b) * 0.5
	var d: Vector3 = (b - a).normalized()
	var up := Vector3(0, 0, 1) if absf(d.y) > 0.99 else Vector3.UP
	mi.look_at(mi.global_position + d, up)
	mi.rotate_object_local(Vector3.RIGHT, -PI / 2)

## Straight cable / pipe between two points (decoration — MeshInstance, no collision).
func _wire(a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = a.distance_to(b)
	cm.material = mat
	mi.mesh = cm
	add_child(mi)
	mi.global_position = (a + b) * 0.5
	var d: Vector3 = (b - a).normalized()
	var up := Vector3(0, 0, 1) if absf(d.y) > 0.99 else Vector3.UP
	mi.look_at(mi.global_position + d, up)
	mi.rotate_object_local(Vector3.RIGHT, -PI / 2)

## The steel skeleton pass: girders under the deck, X-braces between the legs,
## riser pipes, cable runs between the floodlight poles, ceiling beams indoors.
func _industrial_dressing() -> void:
	var steel: Material = MatLib.rust_steel()
	var dark: Material = MatLib.dark_metal()
	var pipe_mat: Material = MatLib.rusty_metal()
	# Under-deck girders carrying the topside plate (seen from the wet deck / sea).
	for gz in [-18.0, -6.0, 6.0, 18.0]:
		_beam(Vector3(-29, DECK_Y - 0.85, gz), Vector3(29, DECK_Y - 0.85, gz), 0.5, steel)
	for gx in [-24.0, -12.0, 0.0, 12.0]:
		_beam(Vector3(gx, DECK_Y - 1.15, -19), Vector3(gx, DECK_Y - 1.15, 19), 0.4, steel)
	# Rim girder around the topside deck edge.
	_beam(Vector3(-30, DECK_Y - 0.5, -19.9), Vector3(30, DECK_Y - 0.5, -19.9), 0.7, dark)
	_beam(Vector3(-30, DECK_Y - 0.5, 19.9), Vector3(30, DECK_Y - 0.5, 19.9), 0.7, dark)
	_beam(Vector3(-29.9, DECK_Y - 0.5, -19), Vector3(-29.9, DECK_Y - 0.5, 19), 0.7, dark)
	_beam(Vector3(29.9, DECK_Y - 0.5, -19), Vector3(29.9, DECK_Y - 0.5, 19), 0.7, dark)
	# X-braces between the concrete legs, both long faces — the truss the sea sees.
	for bz in [-12.0, 12.0]:
		_beam(Vector3(-19, 1.6, bz), Vector3(19, 13.6, bz), 0.42, steel)
		_beam(Vector3(19, 1.6, bz), Vector3(-19, 13.6, bz), 0.42, steel)
	# Riser pipes up the east leg faces, elbowing sideways under the deck.
	for rz in [-10.4, 10.4]:
		_wire(Vector3(25.3, 0.5, rz), Vector3(25.3, DECK_Y - 1.2, rz), 0.14, pipe_mat)
		_wire(Vector3(25.3, DECK_Y - 1.2, rz), Vector3(20.0, DECK_Y - 1.2, rz), 0.11, pipe_mat)
	# Wet-deck pipe rack along the pump room south face (overhead, out of head reach).
	for px in [11.0, 14.5, 17.5]:
		_box(Vector3(px, WET_Y + 1.45, -14.6), Vector3(0.12, 2.9, 0.12), dark, self, false)
	_wire(Vector3(10.5, WET_Y + 2.65, -14.6), Vector3(18.0, WET_Y + 2.65, -14.6), 0.1, pipe_mat)
	_wire(Vector3(10.5, WET_Y + 2.4, -14.6), Vector3(18.0, WET_Y + 2.4, -14.6), 0.07, pipe_mat)
	# Power story in copper and rubber: a cable drop climbs the stair tower's west
	# face from the wet deck to the breaker floor, then wiring hops pole to pole.
	_wire(Vector3(21.85, WET_Y + 0.4, 1.4), Vector3(21.85, 19.4, 1.4), 0.05, dark)
	_box(Vector3(21.82, 6.4, 1.4), Vector3(0.14, 0.5, 0.35), dark, self, false)   # junction boxes
	_box(Vector3(21.82, 10.4, 1.4), Vector3(0.14, 0.5, 0.35), dark, self, false)
	_wire(Vector3(21.9, 19.4, 1.4), Vector3(14, DECK_Y + 3.5, 7), 0.025, dark)
	_wire(Vector3(-14, DECK_Y + 3.5, -8), Vector3(14, DECK_Y + 3.5, -8), 0.022, dark)
	_wire(Vector3(-14, DECK_Y + 3.5, 7), Vector3(14, DECK_Y + 3.5, 7), 0.022, dark)
	_wire(Vector3(-14, DECK_Y + 3.5, -8), Vector3(-14, DECK_Y + 3.5, 7), 0.022, dark)
	_wire(Vector3(14, DECK_Y + 3.5, -8), Vector3(14, DECK_Y + 3.5, 7), 0.022, dark)
	_wire(Vector3(13.8, DECK_Y + 3.5, 7), Vector3(11.5, DECK_Y + 1.1, 7.8), 0.025, dark)  # feed to the heater wall
	# Ceiling beams inside the Deck A rooms — the rooms wear their structure.
	for bz in [10.5, 15.5]:
		_beam(Vector3(-1.8, DECK_Y + 2.95, bz), Vector3(13.8, DECK_Y + 2.95, bz), 0.26, dark)   # galley
		_beam(Vector3(18.2, DECK_Y + 2.95, bz), Vector3(27.8, DECK_Y + 2.95, bz), 0.26, dark)   # rec room
	for bz in [7.0, 15.0]:
		_beam(Vector3(-27.8, DECK_Y + 2.95, bz), Vector3(-8.2, DECK_Y + 2.95, bz), 0.26, dark)  # bunkhouse
	# Vertical conduit drops where the overhead lines meet the room walls.
	for dp in [Vector3(-1.85, DECK_Y + 1.5, 10.5), Vector3(17.9, DECK_Y + 1.5, 15.5)]:
		_box(dp, Vector3(0.09, 3.0, 0.09), dark, self, false)

## Painted block lettering on a surface (shaded, single-sided — reads as stencil paint).
func _plabel(text: String, pos: Vector3, yaw_deg: float, font_size: int = 32,
		color: Color = Color(0.82, 0.83, 0.8)) -> void:
	var l := Label3D.new()
	l.text = text
	# Scaled down — oversized paint bled across panel joints and door reveals.
	l.font_size = maxi(12, int(font_size * 0.75))
	l.pixel_size = 0.01
	l.modulate = Color(color.r, color.g, color.b, 0.92)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	add_child(l)
	l.position = pos
	l.rotation.y = deg_to_rad(yaw_deg)

## The failed span toward SALTLINE-2: five solid sections off the deck's east edge,
## railed, then torn steel and a long drop. A vista, a warning, and a promise.
func _build_broken_bridge(u: Vector3) -> void:
	var yaw: float = -atan2(u.z, u.x)
	var perp := Vector3(-u.z, 0, u.x)
	var start := Vector3(29.9, DECK_Y, 14.0)
	var deck_mat: Material = MatLib.checker_plate()
	var steel: Material = MatLib.rust_steel()
	var sections: int = 5
	for i in range(sections):
		var mid: Vector3 = start + u * ((i + 0.5) * 6.0)
		var sec := _box(mid + Vector3(0, -0.15, 0), Vector3(6.15, 0.3, 2.4), deck_mat)
		sec.rotation.y = yaw
		# Rails both sides — the last section's rails are torn away.
		if i < sections - 1:
			for side in [-1.05, 1.05]:
				var r := _box(mid + perp * side + Vector3(0, 0.55, 0), Vector3(6.15, 0.1, 0.08), steel)
				r.rotation.y = yaw
				var post := _box(mid + perp * side + Vector3(0, 0.28, 0), Vector3(0.07, 0.56, 0.07), steel, self, false)
				post.rotation.y = yaw
		# Under-truss chords.
		var chord := _box(mid + Vector3(0, -0.65, 0), Vector3(6.15, 0.25, 0.25), steel, self, false)
		chord.rotation.y = yaw
	# Torn end: jagged plate fingers dropping off, one bent rail.
	var edge: Vector3 = start + u * (sections * 6.0)
	for spec in [[0.9, -0.35, 0.25], [-0.2, -0.6, 0.45], [-0.9, -0.9, 0.7]]:
		var finger := _box(edge + perp * spec[0] + u * 0.7 + Vector3(0, spec[1], 0),
			Vector3(1.6, 0.22, 0.6), deck_mat, self, false)
		finger.rotation.y = yaw
		finger.rotation.z = spec[2]
	var bent := _box(edge + perp * 1.05 + Vector3(0, 0.1, 0), Vector3(2.0, 0.09, 0.08), steel, self, false)
	bent.rotation.y = yaw
	bent.rotation.z = -0.9
	# Hazard barricade two sections before the drop, with painted warning.
	var bar_pos: Vector3 = start + u * 21.0
	var bar := _box(bar_pos + Vector3(0, 0.95, 0), Vector3(0.14, 0.14, 2.3), MatLib.flat(Color(0.85, 0.72, 0.1)))
	bar.rotation.y = yaw
	for side in [-0.8, 0.8]:
		var leg := _box(bar_pos + perp * side + Vector3(0, 0.45, 0), Vector3(0.1, 0.9, 0.1), MatLib.dark_metal(), self, false)
		leg.rotation.y = yaw
	_plabel("SPAN OUT — SALTLINE-2", bar_pos + Vector3(0, 1.45, 0) - u * 0.12,
		rad_to_deg(yaw) - 90.0, 26, Color(0.9, 0.75, 0.2))   # faces back toward the rig
	# Hazard paint where the bridge leaves the deck.
	_box(Vector3(29.2, DECK_Y + 0.02, 14.0), Vector3(1.6, 0.02, 2.4), MatLib.flat(Color(0.8, 0.7, 0.1)), self, false)
