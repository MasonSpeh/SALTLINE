class_name RigBuilder extends Node3D
## Builds the greybox Rig Slipway (GDD 5.1) from code: Z1 Wet Deck, Z2 Stairs,
## Z4 Topside, Z5 High Iron, plus the SPHL, distant imposters, and all interactables.
## Positions are the level design — edit here, not in scattered scenes.

const STAIRS := preload("res://scripts/world/stair_kit.gd")   # by path: class cache lags new files

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
	_more_industry()   # triple the piping: valves, gauges, bolted flanges, cable trays, welds
	# _surface_grime() DISABLED: the custom decal-sticker materials (MUL blend + runtime
	# ImageTextures + alpha-scissor transparency) grey the whole viewport on some macOS
	# gl_compatibility drivers even though they render fine on others. Pure polish — off
	# until the materials are reworked with only broadly-supported features.
	# _surface_grime()
	_arrival_dressing()
	_density_a()
	# Water-level overhaul: boat landing, mooring station, pipe gallery, pump
	# skids, girder ceiling, salvage scatter. Preloaded by path (class cache).
	add_child(preload("res://scripts/world/wet_deck_detail.gd").new())
	# Lived-in dressing: glTF furniture/tools/effects stocked through every room.
	add_child(preload("res://scripts/world/interior_props.gd").new())
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

## Square corner columns that swallow the seam where two centred walls meet, so
## corners read as one clean cast pilaster instead of a mitred notch. `corners`
## are floor-level XZ points; the post rises `height` from `y`.
func _corner_posts(corners: Array, y: float, height: float, mat: Material, post: float = 0.42) -> void:
	for c in corners:
		var p: Vector3 = c
		_box(Vector3(p.x, y + height * 0.5, p.z), Vector3(post, height, post), mat)

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

## A crew bunk you can SLEEP in (see bed.gd). Builds its own bedding; `made`
## squares the blanket, otherwise it's thrown back. `yaw` points the head to a wall.
func _bed(pos: Vector3, yaw: float, made: bool, blanket: Color) -> void:
	var b: Interactable = preload("res://scripts/components/bed.gd").new()
	b.set("made", made)
	b.set("blanket_col", blanket)
	add_child(b)
	b.global_position = pos
	b.rotation.y = deg_to_rad(yaw)

func _readable(id: String, name_: String, pos: Vector3, size: Vector3 = Vector3(0.35, 0.45, 0.06)) -> Readable:
	var r := Readable.new()
	r.readable_id = id
	r.display_name = name_
	add_child(r)
	r.global_position = pos
	r.build_visual(size)
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

## A Takeable whose look is built here rather than by ItemVisual — for items whose
## real shape carries the read (the shop's hand tools, the kedge anchor). Same
## collider, adhesion and TAKE behaviour as _takeable(); only the visual differs.
func _takeable_custom(item: String, name_: String, pos: Vector3, visual: Node3D,
		yaw_deg: float = 0.0, reach: float = 0.34) -> Takeable:
	var t := Takeable.new()
	t.item_id = item
	t.display_name = name_
	add_child(t)
	t.global_position = pos
	t.rotation.y = deg_to_rad(yaw_deg)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(reach, maxf(reach * 0.7, 0.25), reach)
	col.shape = box
	t.add_child(col)
	col.position.y = box.size.y * 0.5
	t.add_child(visual)
	preload("res://scripts/world/surface_snap.gd").attach(t)
	return t

## Same, but wearing one of the real glTF shop tools. Falls back to the greybox
## ItemVisual if the model is not on disk, so a missing asset never breaks a room.
func _takeable_model(item: String, model: String, name_: String, pos: Vector3,
		yaw_deg: float = 0.0) -> Takeable:
	var t := _takeable_custom(item, name_, pos, Node3D.new(), 0.0)
	if PropLib.has(model):
		PropLib.spawn(model, t, pos, yaw_deg, 1.0, false, -1.0, false)
	else:
		t.add_child(ItemVisual.build(item))
	return t

# ---- hand-built item shapes (plain meshes: these ride on a Takeable, not CSG) ----

func _vbox(root: Node3D, size: Vector3, mat: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi

func _vcyl(root: Node3D, radius: float, h: float, mat: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = h
	m.material = mat
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi

## A fitter's hand file — wooden handle, ferrule, tapered steel body. Lies flat.
func _file_visual() -> Node3D:
	var root := Node3D.new()
	var steel: Material = MatLib.flat(Color(0.44, 0.45, 0.48))
	var handle: Material = MatLib.flat(Color(0.42, 0.29, 0.17))
	_vcyl(root, 0.017, 0.09, handle, Vector3(-0.135, 0.017, 0), Vector3(0, 0, deg_to_rad(90)))
	_vcyl(root, 0.013, 0.015, MatLib.galvanized(), Vector3(-0.083, 0.017, 0),
		Vector3(0, 0, deg_to_rad(90)))
	_vbox(root, Vector3(0.14, 0.013, 0.026), steel, Vector3(0.0, 0.017, 0))
	_vbox(root, Vector3(0.055, 0.009, 0.017), steel, Vector3(0.096, 0.016, 0))
	return root

## A hacksaw lying on its side — blade, frame back, two uprights, pistol grip.
func _hacksaw_visual() -> Node3D:
	var root := Node3D.new()
	var steel: Material = MatLib.flat(Color(0.46, 0.47, 0.5))
	var frame: Material = MatLib.flat(Color(0.3, 0.32, 0.35))
	_vbox(root, Vector3(0.30, 0.007, 0.024), steel, Vector3(0, 0.009, 0))        # blade
	_vbox(root, Vector3(0.30, 0.017, 0.019), frame, Vector3(0, 0.013, 0.078))    # frame back
	for s in [-1.0, 1.0]:
		_vbox(root, Vector3(0.017, 0.015, 0.078), frame, Vector3(s * 0.145, 0.012, 0.039))
	_vbox(root, Vector3(0.075, 0.03, 0.036), MatLib.flat(Color(0.38, 0.26, 0.15)),
		Vector3(-0.182, 0.017, 0.026))                                           # grip
	return root

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

	# Submerged work plate hung off the south lip on four rods — the drowned staging
	# they used to reach the caisson. It is what the glass snails live on: they were
	# authored "on the submerged plate" at y -1.3 but no such plate existed, so all
	# four spawned inside the pontoon slab. Lean over the south rail and their lit gut
	# coils are the only thing down there.
	_box(Vector3(16.5, -1.45, -20.0), Vector3(11, 0.3, 3.4), MatLib.rust_steel())
	for hx in [12.0, 21.0]:
		for hz in [-19.0, -21.0]:
			_box(Vector3(hx, 0.1, hz), Vector3(0.1, 2.8, 0.1), MatLib.dark_metal(), self, false)

	# Flooded pump room (knee-deep water, cold zone).
	var pr_mat: Material = MatLib.concrete()
	_wall(Vector3(10, WET_Y, -14), Vector3(18, WET_Y, -14), WALL_H, pr_mat, 0.5)
	_wall(Vector3(10, WET_Y, -6), Vector3(18, WET_Y, -6), WALL_H, pr_mat)
	_wall(Vector3(10, WET_Y, -14), Vector3(10, WET_Y, -6), WALL_H, pr_mat)
	_wall(Vector3(18, WET_Y, -14), Vector3(18, WET_Y, -6), WALL_H, pr_mat)
	_corner_posts([Vector3(10, 0, -14), Vector3(18, 0, -14), Vector3(10, 0, -6), Vector3(18, 0, -6)],
		WET_Y, WALL_H, pr_mat)
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
	_corner_posts([Vector3(10, 0, -16), Vector3(16, 0, -16), Vector3(10, 0, -22), Vector3(16, 0, -22)],
		WET_Y, WALL_H, lr_mat)
	_box(Vector3(13, WET_Y + WALL_H, -19), Vector3(6.5, 0.25, 6.5), lr_mat)
	_crate(["canned_food", "canned_peaches"], "Storage Crate", Vector3(13, WET_Y + 0.01, -20))
	# Ship's stores: a small kedge stood in the SW angle, out of the walk line
	# between the door and the crate. ItemVisual already carries a proper kedge
	# (shank/ring/stock/flukes) and it stands upright, which is how one lives in a
	# corner of the stores — so this uses the same shape you see when it is dropped.
	_takeable("mini_anchor", "Kedge Anchor", Vector3(10.75, WET_Y + 0.05, -21.3),
		Vector3(0.35, 0.5, 0.35)).rotation.y = deg_to_rad(25)

	# Tide-line clutter — rusted drums along the SOUTH deck edge, clear of the rigging
	# bench footprint (x24.2..26.1, z-17.15..-17.85) so nothing intersects the workbench.
	for p in [Vector3(20.6, WET_Y + 0.5, -20.4), Vector3(22.1, WET_Y + 0.5, -21.2),
			Vector3(27.2, WET_Y + 0.5, -21.3), Vector3(28.6, WET_Y + 0.5, -20.2),
			Vector3(26.0, WET_Y + 0.5, -21.4)]:
		_cyl(p, 0.45, 1.0, MatLib.rust_steel())

	# Exterior ladder: Wet Deck -> Topside (the long, exposed alternative).
	_ladder(Vector3(29.9, WET_Y, -16), DECK_Y - WET_Y, -90.0, "Leg Ladder", 1.2)

# ---------- Z2: The Stairs ----------

const STAIR_RISE: float = 4.0     # per-flight rise — keeps annex levels at y6 / y10 / y18
const STAIR_RUN: float = 5.0      # per-flight horizontal run (x)
const STAIR_WID: float = 1.8      # flight width (z)
const STAIR_N: int = 9            # flights: y2 -> y38 (topside deck = flight 4 top = y18)
const STAIR_XW: float = 23.5      # west foot/top x  (flights span XW..XE)
const STAIR_XE: float = 28.5      # east foot/top x
const STAIR_ZS: float = -2.9      # south lane — odd flights climb W->E
const STAIR_ZN: float = -1.1      # north lane — even flights climb E->W
const STAIR_PZ0: float = -4.0     # turn-platform south edge
const STAIR_PZ1: float = 2.0      # turn-platform north edge (reaches the annex doors at z2)
const OPS_Y: float = WET_Y + STAIR_N * STAIR_RISE   # 38.0 — the lookout floor

func _build_stair_tower() -> void:
	var mat: Material = MatLib.concrete()
	var deck_mat: Material = MatLib.deck_plate()
	# --- Parametric switchback climbing the full shaft to the OPERATIONS LOOKOUT. ---
	# THE JOIN FIX: every flight tops out flush at the EDGE of its turn platform. Each
	# platform lives in the wall-end POCKET the flight never occupies (x<XW to the west,
	# x>XE to the east), so a flight's last tread meets flat plate at a clean seam instead
	# of a slab cutting through the middle of the run. One flight = one story; repeats up.
	var shell_h: float = OPS_Y - WET_Y
	# Shell x22..30, z-6..2, rising to the ops floor. South wet-deck door; west deck door;
	# north wall carries door gaps to the machinery (y6) + breaker (y10) annex rooms.
	_wall(Vector3(22, WET_Y, -6), Vector3(30, WET_Y, -6), shell_h, mat, 0.2)   # south (wet-deck door)
	_north_wall_with_room_doors(mat, shell_h)                                  # north (+2 room doors)
	_wall(Vector3(30, WET_Y, -6), Vector3(30, WET_Y, 2), shell_h, mat)         # east
	_west_wall_with_deck_door(mat, shell_h)                                    # west (deck door cut in)
	_corner_posts([Vector3(22, 0, -6), Vector3(30, 0, -6), Vector3(22, 0, 2), Vector3(30, 0, 2)],
		WET_Y, shell_h, mat, 0.5)

	# Entry pad from the south wet-deck door to the foot of flight 1 (at XW, z_S).
	_box(Vector3(23.0, WET_Y - 0.1, -4.6), Vector3(3.6, 0.2, 3.4), MatLib.checker_plate())

	# Flights + their turn platforms, generated straight up.
	for k in range(1, STAIR_N + 1):
		var y0: float = WET_Y + (k - 1) * STAIR_RISE
		var y1: float = WET_Y + k * STAIR_RISE
		var odd: bool = (k % 2) == 1
		var foot_x: float = STAIR_XW if odd else STAIR_XE
		var top_x: float = STAIR_XE if odd else STAIR_XW
		var lane_z: float = STAIR_ZS if odd else STAIR_ZN
		STAIRS.flight(self, Vector3(foot_x, y0, lane_z), Vector3(top_x, y1, lane_z), STAIR_WID)
		if k == STAIR_N:
			break   # the top flight lands in the ops-room floor, built below
		# Turn platform in the wall-end pocket the flight tops into (never under the run).
		var px_s: float = (30.0 - STAIR_XE) if top_x == STAIR_XE else (STAIR_XW - 22.0)
		var px_c: float = (STAIR_XE + 30.0) * 0.5 if top_x == STAIR_XE else (22.0 + STAIR_XW) * 0.5
		_box(Vector3(px_c, y1 - 0.15, (STAIR_PZ0 + STAIR_PZ1) * 0.5),
			Vector3(px_s, 0.3, STAIR_PZ1 - STAIR_PZ0), deck_mat)
		# A guard rail along the platform's open (south) edge so the drop is fenced.
		_box(Vector3(px_c, y1 + 0.55, STAIR_PZ0 + 0.06), Vector3(px_s, 0.9, 0.06), MatLib.rust_steel(), self, false)

	# Exterior structure for the tall free-standing shaft above the deck: proud concrete
	# bands wrap the four faces at two heights so it reads as a segmented tower, not a slab.
	for band_y in [DECK_Y + 4.0, DECK_Y + 12.0]:
		_box(Vector3(26, band_y, -6.07), Vector3(8.7, 0.5, 0.14), mat, self, false)   # south face
		_box(Vector3(26, band_y, 2.07), Vector3(8.7, 0.5, 0.14), mat, self, false)    # north face
		_box(Vector3(21.93, band_y, -2), Vector3(0.14, 0.5, 8.3), mat, self, false)   # west face
		_box(Vector3(30.07, band_y, -2), Vector3(0.14, 0.5, 8.3), mat, self, false)   # east face

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
	# E.V.'s last note pinned to the panel — the reward for restoring power, and "made polite".
	_readable("ev_last_splice", "Note on the Panel", Vector3(23.4, 11.5, 9.5), Vector3(0.28, 0.34, 0.03))
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

	# The lookout that the whole climb finally leads to.
	_build_ops_room(OPS_Y)

## West wall of the stair tower (x=22, z -6..2), solid except a deck-level doorway
## at z -0.4..1.4 (y 18..20.4) so the climb spills out onto the topside deck. Cut as
## one CSG subtraction so the opening is a clean hole, not overlaid jamb boxes.
func _west_wall_with_deck_door(mat: Material, shell_h: float) -> void:
	var comb := CSGCombiner3D.new()
	comb.use_collision = true
	add_child(comb)
	var wall := CSGBox3D.new()
	wall.size = Vector3(WALL_T, shell_h, 8.0)          # spans z -6..2
	wall.material = mat
	comb.add_child(wall)
	wall.position = Vector3(22, WET_Y + shell_h * 0.5, -2)
	var door := CSGBox3D.new()
	door.size = Vector3(WALL_T + 0.8, 2.4, 1.8)
	door.operation = CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(door)
	door.position = Vector3(22, DECK_Y + 1.2, 0.5)     # y 18..20.4, z -0.4..1.4
	# Steel jamb frame so the cut edge reads as a real hatch onto the deck.
	var steel: Material = MatLib.rust_steel()
	_box(Vector3(22, DECK_Y + 1.2, -0.5), Vector3(0.32, 2.5, 0.16), steel)
	_box(Vector3(22, DECK_Y + 1.2, 1.5), Vector3(0.32, 2.5, 0.16), steel)
	_box(Vector3(22, DECK_Y + 2.45, 0.5), Vector3(0.32, 0.2, 2.2), steel)

## North shell wall (z=2, x22..30), solid except door gaps onto the machinery room
## (y6, door at x28.5) and the breaker room (y10, door at x23.5). Without these the
## annexes sat behind a solid wall — the breaker puzzle room was unreachable.
func _north_wall_with_room_doors(mat: Material, shell_h: float) -> void:
	var comb := CSGCombiner3D.new()
	comb.use_collision = true
	add_child(comb)
	var wall := CSGBox3D.new()
	wall.size = Vector3(8.0, shell_h, WALL_T)          # spans x22..30
	wall.material = mat
	comb.add_child(wall)
	wall.position = Vector3(26, WET_Y + shell_h * 0.5, 2)
	var steel: Material = MatLib.rust_steel()
	for spec in [[28.5, 6.0], [23.5, 10.0]]:           # [door x, room floor y]
		var d := CSGBox3D.new()
		d.size = Vector3(1.6, 2.4, WALL_T + 0.8)
		d.operation = CSGShape3D.OPERATION_SUBTRACTION
		comb.add_child(d)
		d.position = Vector3(spec[0], spec[1] + 1.2, 2)
		# Steel jamb frame around the opening.
		_box(Vector3(spec[0] - 0.85, spec[1] + 1.2, 2), Vector3(0.16, 2.5, 0.32), steel)
		_box(Vector3(spec[0] + 0.85, spec[1] + 1.2, 2), Vector3(0.16, 2.5, 0.32), steel)
		_box(Vector3(spec[0], spec[1] + 2.45, 2), Vector3(1.8, 0.2, 0.32), steel)

## OPERATIONS LOOKOUT — the glass-walled room capping the tower, with a 360° view of
## the rig, the ocean and the storm. Reached only by the internal stair, which emerges
## through a hole in this floor. Footprint x 20..32, z -8..4 (cantilevers past the
## x22..30 shaft below), so the glass overhangs the deck on every side.
func _build_ops_room(fy: float) -> void:
	var steel: Material = MatLib.rust_steel()
	var concrete: Material = MatLib.concrete()
	var glass: Material = MatLib.glass(Color(0.58, 0.72, 0.82))
	var x0: float = 20.0
	var x1: float = 32.0
	var z0: float = -8.0
	var z1: float = 4.0
	var cx: float = (x0 + x1) * 0.5   # 26
	var cz: float = (z0 + z1) * 0.5   # -2
	var par_h: float = 0.9            # solid waist-high parapet
	var glass_h: float = 1.8          # the big view band
	var hdr_h: float = 0.3            # header beam
	var wt: float = 0.18
	var wall_h: float = par_h + glass_h + hdr_h

	# --- Floor slab, with a hole over the top flight's run (x22.7..28.7, z-4.2..-1.6);
	# the final flight emerges at its EAST end (28.5, -2.9), so you step onto solid floor.
	var fcomb := CSGCombiner3D.new()
	fcomb.use_collision = true
	add_child(fcomb)
	var slab := CSGBox3D.new()
	slab.size = Vector3(x1 - x0 + 0.6, 0.3, z1 - z0 + 0.6)
	slab.material = MatLib.deck_plate()
	fcomb.add_child(slab)
	slab.position = Vector3(cx, fy - 0.15, cz)
	var hole := CSGBox3D.new()
	hole.size = Vector3(6.0, 1.2, 2.6)
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	fcomb.add_child(hole)
	hole.position = Vector3(25.7, fy - 0.15, -2.9)
	# A guard rail around the open sides of the stairwell hole (leaves the east step-off clear).
	_box(Vector3(25.4, fy + 0.55, -1.5), Vector3(5.4, 0.9, 0.06), steel, self, false)   # north lip
	_box(Vector3(22.8, fy + 0.55, -2.9), Vector3(0.06, 0.9, 2.8), steel, self, false)   # west lip

	# --- Walls: solid parapet, huge glass band, header beam; the same on all four sides.
	for zc in [z0, z1]:               # south & north (run along x)
		_box(Vector3(cx, fy + par_h * 0.5, zc), Vector3(x1 - x0, par_h, wt), concrete)
		_box(Vector3(cx, fy + par_h + glass_h * 0.5, zc), Vector3(x1 - x0, glass_h, 0.06), glass)
		_box(Vector3(cx, fy + par_h + glass_h + hdr_h * 0.5, zc), Vector3(x1 - x0, hdr_h, wt), steel)
	for xc in [x0, x1]:               # west & east (run along z)
		_box(Vector3(xc, fy + par_h * 0.5, cz), Vector3(wt, par_h, z1 - z0), concrete)
		_box(Vector3(xc, fy + par_h + glass_h * 0.5, cz), Vector3(0.06, glass_h, z1 - z0), glass)
		_box(Vector3(xc, fy + par_h + glass_h + hdr_h * 0.5, cz), Vector3(wt, hdr_h, z1 - z0), steel)
	# Corner mullions + a couple down each long side so the glass reads as panes.
	_corner_posts([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x0, 0, z1), Vector3(x1, 0, z1)],
		fy, wall_h, steel, 0.26)
	for mx in [23.0, 26.0, 29.0]:
		_box(Vector3(mx, fy + par_h + glass_h * 0.5, z0), Vector3(0.12, glass_h, 0.12), steel)
		_box(Vector3(mx, fy + par_h + glass_h * 0.5, z1), Vector3(0.12, glass_h, 0.12), steel)
	for mz in [-5.0, -2.0, 1.0]:
		_box(Vector3(x0, fy + par_h + glass_h * 0.5, mz), Vector3(0.12, glass_h, 0.12), steel)
		_box(Vector3(x1, fy + par_h + glass_h * 0.5, mz), Vector3(0.12, glass_h, 0.12), steel)

	# --- Roof slab + a small exterior mast with a red beacon (a landmark from below).
	var roof_y: float = fy + wall_h
	_box(Vector3(cx, roof_y + 0.15, cz), Vector3(x1 - x0 + 0.6, 0.3, z1 - z0 + 0.6), concrete)
	_cyl(Vector3(cx, roof_y + 1.4, cz), 0.12, 2.4, steel)
	var beacon := OmniLight3D.new()
	beacon.light_energy = 1.4
	beacon.omni_range = 6.0
	beacon.light_color = Color(1.0, 0.28, 0.22)
	add_child(beacon)
	beacon.global_position = Vector3(cx, roof_y + 2.7, cz)
	_box(Vector3(cx, roof_y + 2.7, cz), Vector3(0.24, 0.24, 0.24), MatLib.flat(Color(1.0, 0.3, 0.24), true, 2.0))

	# --- Interior: a working watch station. Kept clear of the stair hole (x22.7..28.7,
	# z-4.2..-1.6); you emerge at the east end and step onto solid floor.
	# Chart table against the WEST glass.
	_box(Vector3(21.3, fy + 0.86, -1.2), Vector3(1.1, 0.08, 2.0), MatLib.wood())
	for lx in [20.9, 21.7]:
		for lz in [-2.0, -0.4]:
			_box(Vector3(lx, fy + 0.43, lz), Vector3(0.08, 0.86, 0.08), steel)
	_readable("ops_watch_log", "Watch Log", Vector3(21.3, fy + 0.92, -1.6), Vector3(0.3, 0.04, 0.4))
	_takeable("water_ration", "Water Ration", Vector3(21.3, fy + 0.98, -0.4), Vector3(0.16, 0.24, 0.16))
	# Control console along the north glass (z4), angled meter panel with lit dots.
	_box(Vector3(27.5, fy + 0.5, 3.2), Vector3(4.6, 1.0, 0.7), MatLib.dark_metal())
	var panel := _box(Vector3(27.5, fy + 1.15, 3.35), Vector3(4.4, 0.5, 0.1), MatLib.dark_metal())
	panel.rotation.x = deg_to_rad(-32)
	var dot_cols := [Color(0.3, 1.0, 0.4), Color(1.0, 0.7, 0.2), Color(0.3, 0.7, 1.0), Color(1.0, 0.35, 0.3)]
	for i in range(6):
		var col: Color = dot_cols[i % dot_cols.size()]
		var d := _box(Vector3(25.6 + i * 0.75, fy + 1.16, 3.28), Vector3(0.11, 0.11, 0.04),
			MatLib.flat(col, true, 2.4))
		d.rotation.x = deg_to_rad(-32)
	# Radio set on the console + the last-traffic log beside it.
	_box(Vector3(30.4, fy + 1.12, 3.2), Vector3(0.7, 0.4, 0.5), MatLib.rust_steel())
	_box(Vector3(30.4, fy + 1.4, 3.4), Vector3(0.02, 0.02, 0.6), steel)  # antenna whip
	_readable("radio_log", "Radio Log", Vector3(29.4, fy + 0.86, 3.3), Vector3(0.3, 0.04, 0.34))
	# A watch stool, and binoculars on a stand at the south glass looking out to sea.
	_cyl(Vector3(28.0, fy + 0.35, 3.0), 0.22, 0.7, MatLib.rust_steel())
	_cyl(Vector3(26.0, fy + 0.6, -7.2), 0.06, 1.2, steel)
	_box(Vector3(26.0, fy + 1.24, -7.2), Vector3(0.5, 0.18, 0.22), MatLib.dark_metal())
	# Overhead lamp (kept off the stair hole).
	var lamp := OmniLight3D.new()
	lamp.light_energy = 0.7
	lamp.omni_range = 9.0
	lamp.light_color = Color(0.85, 0.87, 0.9)
	lamp.add_to_group("spill_lights")
	add_child(lamp)
	lamp.global_position = Vector3(24.0, roof_y - 0.4, -4.0)

func _room_north(a: Vector3, b: Vector3, mat: Material, door_t: float) -> void:
	## Rectangular room north of the tower: a=(west,floor_y,south) b=(east,floor_y,north).
	var y: float = a.y
	_box(Vector3((a.x + b.x) * 0.5, y - 0.15, (a.z + b.z) * 0.5), Vector3(b.x - a.x + 0.5, 0.3, b.z - a.z + 0.5), MatLib.deck_plate())
	_wall(Vector3(a.x, y, a.z), Vector3(b.x, y, a.z), WALL_H, mat, door_t) # south wall w/ door
	_wall(Vector3(a.x, y, b.z), Vector3(b.x, y, b.z), WALL_H, mat)
	_wall(Vector3(a.x, y, a.z), Vector3(a.x, y, b.z), WALL_H, mat)
	_wall(Vector3(b.x, y, a.z), Vector3(b.x, y, b.z), WALL_H, mat)
	# Corner columns so adjoining walls meet as one clean edge, not a notched seam.
	_corner_posts([Vector3(a.x, 0, a.z), Vector3(b.x, 0, a.z), Vector3(a.x, 0, b.z), Vector3(b.x, 0, b.z)],
		y, WALL_H, mat)
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

	_build_ladder_landing()
	_build_bunkhouse()
	_build_galley()
	_build_rec_room()
	_build_machine_shop()
	_build_floodlights()

	# Scattered deck props.
	for i in range(6):
		_cyl(Vector3(-6 + i * 2.2, DECK_Y + 0.5, -16), 0.45, 1.0, MatLib.rust_steel())
	_box(Vector3(8, DECK_Y + 0.4, -14), Vector3(2.4, 0.8, 1.2), MatLib.wood()) # pallet stack

## A proper landing where the Leg Ladder tops out at (29.9, 18, -16). The east
## perimeter rails skip z-16 entirely, so the ladder used to arrive at a bare,
## unrailed stretch of deck rim — you mantled straight over an open edge with
## nothing to hold and nothing underfoot outboard of you. This is a small grippy
## plate lapped flush onto the deck edge and cantilevered out on two knee braces,
## with a U of railing round the three seaward sides. The deck side (west) is left
## open: that is the way on and off, straight through onto the topside plate.
func _build_ladder_landing() -> void:
	var y: float = DECK_Y
	var lz: float = -16.0                       # the Leg Ladder's z
	var rail: Material = MatLib.rust_steel()
	# Anti-slip plate, top face coplanar with the deck at y18 so the join is flush.
	_box(Vector3(30.6, y - 0.05, lz), Vector3(1.3, 0.1, 1.5), MatLib.checker_plate())
	# Hazard paint along the outboard lip — same yellow as the deck hazard strips.
	_box(Vector3(31.2, y + 0.005, lz), Vector3(0.1, 0.02, 1.5),
		MatLib.flat(Color(0.8, 0.7, 0.1)), self, false)
	# Knee braces: high at the plate's outboard lip, angling down and inboard to
	# tuck under the deck edge — what actually holds a cantilevered landing up.
	for bz in [lz - 0.6, lz + 0.6]:
		var brace := _box(Vector3(30.55, y - 0.42, bz), Vector3(1.35, 0.09, 0.09), rail, self, false)
		brace.rotation.z = deg_to_rad(29.0)
	# Stanchions at the four corners; the deck-side pair frames the way through.
	for c in [Vector2(31.2, lz - 0.65), Vector2(31.2, lz + 0.65),
			Vector2(30.0, lz - 0.65), Vector2(30.0, lz + 0.65)]:
		_box(Vector3(c.x, y + 0.5, c.y), Vector3(0.08, 1.0, 0.08), rail)
	# Top and mid rail on the three seaward sides — solid, so they actually catch you.
	for h in [[0.95, 0.07], [0.5, 0.05]]:
		var ry: float = y + float(h[0])
		var rt: float = float(h[1])
		_box(Vector3(30.6, ry, lz - 0.65), Vector3(1.2, rt, rt), rail)
		_box(Vector3(30.6, ry, lz + 0.65), Vector3(1.2, rt, rt), rail)
		_box(Vector3(31.2, ry, lz), Vector3(rt, rt, 1.3), rail)
	# Toe boards, so nothing kicked off the plate goes straight into the sea.
	_box(Vector3(30.6, y + 0.09, lz - 0.7), Vector3(1.3, 0.18, 0.04), rail, self, false)
	_box(Vector3(30.6, y + 0.09, lz + 0.7), Vector3(1.3, 0.18, 0.04), rail, self, false)
	_box(Vector3(31.25, y + 0.09, lz), Vector3(0.04, 0.18, 1.5), rail, self, false)

func _build_bunkhouse() -> void:
	var mat: Material = MatLib.concrete()
	var y: float = DECK_Y
	# Block shell x -28..-8, z 4..18; corridor z 10..12; entrance east at corridor.
	_wall(Vector3(-28, y, 4), Vector3(-8, y, 4), WALL_H, mat)
	_wall(Vector3(-28, y, 18), Vector3(-8, y, 18), WALL_H, mat)
	_wall(Vector3(-28, y, 4), Vector3(-28, y, 18), WALL_H, mat)
	_wall(Vector3(-8, y, 4), Vector3(-8, y, 18), WALL_H, mat, 0.5) # east entrance into corridor
	_corner_posts([Vector3(-28, 0, 4), Vector3(-8, 0, 4), Vector3(-28, 0, 18), Vector3(-8, 0, 18)],
		y, WALL_H, mat)
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
	# Beds you can turn in on: made (neat) vs thrown-back (someone rose in a hurry).
	# Heads to the wall — south row faces −Z, north row +Z. Each is a Bed you can SLEEP in.
	var bed_specs := [
		[Vector3(-25.5, y, 6.5), 0.0], [Vector3(-18.8, y, 6.5), 0.0], [Vector3(-12.0, y, 6.5), 0.0],
		[Vector3(-25.5, y, 15.5), 180.0], [Vector3(-18.8, y, 15.5), 180.0], [Vector3(-12.0, y, 15.5), 180.0],
	]
	for i in range(bed_specs.size()):
		var p: Vector3 = bed_specs[i][0]
		var blanket_col: Color = Color(0.75, 0.78, 0.8) if i % 2 == 0 else Color(0.55, 0.58, 0.62)
		_bed(p, bed_specs[i][1], i % 2 == 0, blanket_col)
		# Lockers
		_box(p + Vector3(1.2, 0.9, -0.8), Vector3(0.5, 1.8, 0.5), MatLib.painted_steel())
	_readable("crew_letter_1", "Unsent Letter", Vector3(-18.8, y + 0.75, 7.3), Vector3(0.3, 0.05, 0.4))
	# Henrik's photo, taped inside the bunk frame — the boys, the small fish, "three weeks".
	_readable("henrik_photo", "Photograph", Vector3(-18.4, y + 0.9, 6.5), Vector3(0.2, 0.24, 0.02))
	_readable("crew_letter_2", "Note in a Locker", Vector3(-17.6, y + 1.3, 14.7), Vector3(0.28, 0.35, 0.05))

func _build_galley() -> void:
	var mat: Material = MatLib.concrete()
	var y: float = DECK_Y
	_wall(Vector3(-2, y, 8), Vector3(14, y, 8), WALL_H, mat, 0.5)   # south door
	_wall(Vector3(-2, y, 18), Vector3(14, y, 18), WALL_H, mat)
	_wall(Vector3(-2, y, 8), Vector3(-2, y, 18), WALL_H, mat)
	_wall(Vector3(14, y, 8), Vector3(14, y, 18), WALL_H, mat)
	_corner_posts([Vector3(-2, 0, 8), Vector3(14, 0, 8), Vector3(-2, 0, 18), Vector3(14, 0, 18)],
		y, WALL_H, mat)
	_box(Vector3(6, y + WALL_H, 13), Vector3(16.5, 0.25, 10.5), mat)
	_box(Vector3(6, y + 0.035, 13), Vector3(15.5, 0.03, 9.5), MatLib.kitchen_tile(), self, false)
	# Counter along the north wall with food — brushed galley steel, not weather-peel.
	_box(Vector3(6, y + 0.5, 17), Vector3(10, 1.0, 1.2), MatLib.galvanized())
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
	_corner_posts([Vector3(18, 0, 8), Vector3(28, 0, 8), Vector3(18, 0, 18), Vector3(28, 0, 18)],
		y, WALL_H, mat)
	_box(Vector3(23, y + WALL_H, 13), Vector3(10.5, 0.25, 10.5), mat)
	_box(Vector3(23, y + 0.035, 13), Vector3(9.5, 0.03, 9.5), MatLib.rubber_floor(), self, false)
	# Dead TV, couch. (The dartboard is the real glTF one, hung flush on the east
	# bulkhead in interior_props — the flat CSG disc that used to sit here was a
	# second, cruder board competing with it.)
	_box(Vector3(20, y + 1.0, 17.2), Vector3(1.4, 0.9, 0.4), MatLib.dark_metal()) # dead TV
	_box(Vector3(23, y + 0.35, 9.2), Vector3(2.4, 0.7, 1.0), MatLib.canvas(Color(0.45, 0.38, 0.34))) # couch
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
	door.locked = false   # was locked+offset from its opening (looked blocked); now openable
	add_child(door)
	door.global_position = Vector3(-14, y, -15.0)   # centred in the wall opening (z-15.7..-14.3)
	door.build_box_visual(Vector3(0.12, 2.2, 1.3), MatLib.flat(Color(0.4, 0.42, 0.4)).albedo_color)
	_readable("machine_shop_sign", "Posted Notice", Vector3(-13.85, y + 1.5, -10.6), Vector3(0.05, 0.4, 0.3))
	# The raft plans, posted on the shop's outer face below the sealed notice — the escape
	# that the sea would never allow (readable from the accessible side, clear of the pane).
	_readable("raft_plan", "Drafting-Table Sketch", Vector3(-13.85, y + 1.15, -13.5), Vector3(0.05, 0.4, 0.32))
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
	# Osk's watch slate, propped on the drill floor by the finger rack — the night he first saw it.
	_readable("osk_watch_slate", "Night Watch Slate", Vector3(5.8, DECK_Y + 0.62, -15.0), Vector3(0.34, 0.28, 0.04))

# ---------- The SPHL ----------

func _build_sphl() -> void:
	# CLEAN REBUILD (was overlapping capsules/balls that z-fought). One CSG grey
	# pressure-pod shell, visual-only, with a real hatch hole cut in the deck-facing
	# side; inside it an OPAQUE box interior that carries the collision + the wake-up
	# dressing. Player spawns on the interior floor and walks straight out the hatch.
	var grey: Material = MatLib.sphl_grey()
	var hivis: Material = MatLib.sphl_hi_vis()
	var cx: float = 18.0
	var cz: float = -24.0
	var fy: float = WET_Y
	var ix0: float = 14.9
	var ix1: float = 21.1
	var iz_s: float = -25.3
	var iz_n: float = -22.9
	var gap_w: float = 19.2
	var gap_e: float = 20.8
	var wall_cy: float = fy + 1.1
	var wall_h: float = 2.2
	var ceil_y: float = fy + 2.2
	var hull_cy: float = fy + 1.6

	# --- exterior hull: ONE clean CSG shell (no collision, no z-fighting) ---
	var hull := CSGCombiner3D.new()
	hull.use_collision = false
	add_child(hull)
	hull.position = Vector3(cx, hull_cy, cz)
	var body := CSGCylinder3D.new()
	body.radius = 1.55
	body.height = 6.0
	body.material = grey
	body.rotation.z = deg_to_rad(90)
	hull.add_child(body)
	for ex in [-3.0, 3.0]:
		var cap := CSGSphere3D.new()
		cap.radius = 1.55
		cap.material = grey
		hull.add_child(cap)
		cap.position = Vector3(ex, 0, 0)
	var band := CSGCylinder3D.new()
	band.radius = 1.62
	band.height = 0.5
	band.material = hivis
	band.rotation.z = deg_to_rad(90)
	hull.add_child(band)
	# Hatch opening cut in the deck (north/+Z) face, aligned with the interior gap.
	var doorcut := CSGBox3D.new()
	doorcut.operation = CSGShape3D.OPERATION_SUBTRACTION
	doorcut.size = Vector3(gap_e - gap_w + 0.4, wall_h + 0.5, 2.4)
	hull.add_child(doorcut)
	doorcut.position = Vector3((gap_w + gap_e) * 0.5 - cx, wall_cy - hull_cy, (iz_n - cz) + 1.15)

	# Coxswain trunk + glass dome on the crown; two chocks the pod rests in.
	_cyl_nc(Vector3(cx + 1.4, ceil_y + 1.0, cz), 0.46, 0.8, grey)
	_cyl_nc(Vector3(cx + 1.4, ceil_y + 1.45, cz), 0.42, 0.12, MatLib.glass(Color(0.5, 0.6, 0.62)))
	for cxx in [15.9, 20.1]:
		_box(Vector3(cxx, fy + 0.05, cz), Vector3(1.0, 0.3, 2.6), MatLib.rust_steel(), self, false)
	# Stencils on the flank, below the band, clear of the hatch.
	_plabel("SPHL — SALTLINE-0", Vector3(15.4, fy + 1.4, cz - 1.6), 0, 20, Color(0.15, 0.13, 0.12))

	# --- interior: an opaque grey box (collision + what you see from inside) ---
	_box(Vector3(cx, fy - 0.05, cz), Vector3(ix1 - ix0, 0.1, iz_n - iz_s), MatLib.checker_plate())   # floor
	_box(Vector3(cx, ceil_y, cz), Vector3(ix1 - ix0 + 0.2, 0.1, iz_n - iz_s + 0.2), grey, self, false)  # ceiling
	_box(Vector3(cx, wall_cy, iz_s), Vector3(ix1 - ix0, wall_h, 0.15), grey)          # south wall
	_box(Vector3(ix0, wall_cy, cz), Vector3(0.15, wall_h, iz_n - iz_s), grey)         # west wall
	_box(Vector3(ix1, wall_cy, cz), Vector3(0.15, wall_h, iz_n - iz_s), grey)         # east wall
	_box(Vector3((ix0 + gap_w) * 0.5, wall_cy, iz_n), Vector3(gap_w - ix0, wall_h, 0.15), grey)   # N pier W
	_box(Vector3((gap_e + ix1) * 0.5, wall_cy, iz_n), Vector3(ix1 - gap_e, wall_h, 0.15), grey)   # N pier E
	_box(Vector3((gap_w + gap_e) * 0.5, ceil_y - 0.25, iz_n), Vector3(gap_e - gap_w + 0.2, 0.4, 0.16), grey, self, false)  # lintel

	# --- hatch door: hinged at the west jamb, swings clear of the x=20 walk line ---
	sphl_hatch = InteractDoor.new()
	sphl_hatch.display_name = "Hatch"
	sphl_hatch.locked = false
	add_child(sphl_hatch)
	sphl_hatch.global_position = Vector3(gap_w, fy + 0.15, iz_n)
	sphl_hatch.build_box_visual(Vector3(gap_e - gap_w, 1.95, 0.12), MatLib.sphl_hi_vis().albedo_color)
	for c in sphl_hatch.get_children():
		if c is MeshInstance3D or c is CollisionShape3D:
			c.position = Vector3((gap_e - gap_w) * 0.5, 1.0, 0)
	# Gangplank out to the wet deck.
	_box(Vector3((gap_w + gap_e) * 0.5, fy - 0.05, iz_n + 0.85), Vector3(gap_e - gap_w + 0.6, 0.1, 1.9), MatLib.wood())

	# --- interior dressing: red light, pressure readout, wake-up readables on benches ---
	var red := OmniLight3D.new()
	red.light_color = Color(0.9, 0.15, 0.1); red.light_energy = 1.6; red.omni_range = 5.0
	red.light_volumetric_fog_energy = 2.0
	add_child(red); red.global_position = Vector3(16.5, fy + 1.9, cz)
	# Pressure readout, on a real panel. This was a bare green Label3D hanging at
	# the bulkhead: unshaded so it glowed, double_sided so the face you actually
	# woke up looking at from the benches was its MIRRORED back, and yawed -90 so
	# its front pointed into the wall. Now it is a bolted indicator board sunk
	# flush on the forward bulkhead, reading east toward the benches, single-sided
	# so it can never ghost through the steel.
	var board_x: float = ix0 + 0.075                    # interior face of the west wall
	_box(Vector3(board_x + 0.02, fy + 1.55, cz), Vector3(0.04, 0.30, 1.05),
		MatLib.dark_metal(), self, false)               # placard plate
	# Recessed readout face, faintly self-lit. The glass of a powered instrument glows
	# with its text; lighting the panel is what makes the (unshaded) green characters
	# below read as an LCD behind glass rather than as luminous paint floating on a
	# dark plate — the last "glowing free-space text" complaint against this sign.
	var readout := StandardMaterial3D.new()
	readout.albedo_color = Color(0.05, 0.09, 0.07)
	readout.emission_enabled = true
	readout.emission = Color(0.12, 0.5, 0.22)
	readout.emission_energy_multiplier = 0.35
	readout.roughness = 0.25
	_box(Vector3(board_x + 0.045, fy + 1.55, cz), Vector3(0.012, 0.22, 0.92),
		readout, self, false)   # recessed readout face
	for b in [Vector2(0.125, 0.49), Vector2(0.125, -0.49),
			Vector2(-0.125, 0.49), Vector2(-0.125, -0.49)]:
		_cyl_nc(Vector3(board_x + 0.045, fy + 1.55 + b.x, cz + b.y), 0.012, 0.02,
			MatLib.galvanized()).rotation.z = deg_to_rad(90)   # bolt heads
	countdown_label = Label3D.new()
	countdown_label.text = "PRESSURE — EQUALIZED"
	countdown_label.font_size = 40
	countdown_label.pixel_size = 0.002
	countdown_label.modulate = Color(0.3, 0.9, 0.4)
	countdown_label.outline_size = 0
	# Unshaded ON PURPOSE — this one is the pod's own lit readout rather than
	# painted stencil, and the red pod lamp two metres off would otherwise crush a
	# green panel to unreadable black. The board around it is what stops it
	# reading as free-floating text.
	countdown_label.shaded = false
	countdown_label.double_sided = false
	countdown_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(countdown_label)
	countdown_label.global_position = Vector3(board_x + 0.056, fy + 1.55, cz)
	countdown_label.rotation.y = deg_to_rad(90)
	# Bench seats down each side (clear of the x=20 walk line to the hatch).
	for s in [-1.0, 1.0]:
		_box(Vector3(17.1, fy + 0.35, cz + s * 0.95), Vector3(3.6, 0.35, 0.35), grey, self, false)
	_readable("sphl_manual", "Survival Manual", Vector3(15.15, fy + 1.35, cz + 0.9), Vector3(0.3, 0.4, 0.05))
	_readable("pressure_log", "Pressure Log", Vector3(15.15, fy + 1.35, cz - 0.9), Vector3(0.3, 0.4, 0.05))
	_readable("sat_dive_log", "Saturation Log", Vector3(17.1, fy + 0.58, cz + 0.95), Vector3(0.3, 0.03, 0.4))
	_takeable("water_ration", "Water Ration", Vector3(16.3, fy + 0.58, cz - 0.95), Vector3(0.2, 0.25, 0.2))

	_build_sphl_fittings()

## A visual-only rounded body along the X axis (a squashed capsule).
func _capsule_x(pos: Vector3, radius: float, length: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius; cm.height = length; cm.material = mat
	mi.mesh = cm
	add_child(mi)
	mi.position = pos
	mi.rotation.z = deg_to_rad(90)   # long axis -> X
	return mi

## A visual ball (rounded cap), no collision.
func KIT_BALL(pos: Vector3, radius: float, mat: Material, squash: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius; sm.height = radius * 2.0; sm.material = mat
	mi.mesh = sm; add_child(mi); mi.position = pos; mi.scale = squash

## A wall that only collides — a StaticBody box, invisible (the visual hull covers it).
func _col_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size; shape.shape = box
	body.add_child(shape); add_child(body); body.global_position = pos

## External fittings that make the pod read as a real hyperbaric lifeboat.
func _build_sphl_fittings() -> void:
	var y: float = WET_Y
	var dark: Material = MatLib.dark_metal()
	# Stern gear: Kort nozzle, prop, guard hoops (all visual).
	var nozzle := CSGTorus3D.new()
	nozzle.inner_radius = 0.22; nozzle.outer_radius = 0.4
	nozzle.material = dark; nozzle.use_collision = false
	add_child(nozzle); nozzle.position = Vector3(22.8, y + 0.35, -24); nozzle.rotation.z = deg_to_rad(90)
	_cyl_nc(Vector3(22.8, y + 0.35, -24), 0.09, 0.3, MatLib.galvanized()).rotation.z = deg_to_rad(90)
	for h in range(3):
		var hoop := CSGTorus3D.new()
		hoop.inner_radius = 0.42; hoop.outer_radius = 0.5
		hoop.material = MatLib.rust_steel(); hoop.use_collision = false
		add_child(hoop); hoop.position = Vector3(22.6 + h * 0.22, y + 0.35, -24); hoop.rotation.z = deg_to_rad(90)
	# Mooring lines: bow and stern to the dock, well clear of the hatch line and the hull.
	_wire(Vector3(13.4, y + 1.1, -24.6), Vector3(11.8, y + 0.5, -22.8), 0.025, MatLib.rope_mat())
	_wire(Vector3(22.6, y + 1.1, -24.6), Vector3(24.2, y + 0.5, -22.8), 0.025, MatLib.rope_mat())

# ---------- Accessibility: every area reachable ----------

func _build_access() -> void:
	# Wet Deck -> south pontoon (the under-rig walkway: barnacles, eel, jellies up close).
	_ladder(Vector3(7.8, 0.95, -12), 1.2, 90.0, "Pontoon Ladder", 0.9)
	# Sea -> dock: the swimmer's way back up, at the relocated boat landing east
	# of the pod. Starts below the swell so falling in is survivable (GDD §31).
	_ladder(Vector3(24.6, -1.4, -22.42), WET_Y + 1.6, 180.0, "Dock Ladder", 0.9)
	# Wet Deck -> pump room roof (small vantage, stashed crate).
	_ladder(Vector3(18.25, WET_Y, -8), 3.5, -90.0, "Roof Ladder", 1.0)
	_crate(["flare", "canned_peaches"], "Weather Crate", Vector3(14, WET_Y + WALL_H + 0.13, -8.5))
	# (C-deck terrace access is the external west stair — see RigExterior.)
	# Topside -> bunkhouse roof (vent fans, antenna array, and the long view west).
	_ladder(Vector3(-7.75, DECK_Y, 15.5), 3.55, 90.0, "Bunkhouse Roof Ladder", 1.0)
	_readable("roof_mark", "Chalk Tally", Vector3(-18, DECK_Y + WALL_H + 0.4, 8), Vector3(0.4, 0.05, 0.3))
	# Osk's last note, folded under a shell beside his tally — the payoff of his trail.
	_readable("osk_last_note", "Folded Note", Vector3(-17.3, DECK_Y + WALL_H + 0.42, 8.5), Vector3(0.26, 0.05, 0.32))

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
		# The Bed builds its own pillow + blanket; here we add the lived-in extras.
		if i % 2 == 1:
			# Boots kicked off at the foot of the slept-in beds.
			_box(p + Vector3(-0.35, 0.12, 1.3), Vector3(0.14, 0.24, 0.3), MatLib.flat(Color(0.2, 0.16, 0.12)), self, false)
			_box(p + Vector3(-0.15, 0.12, 1.35), Vector3(0.14, 0.24, 0.3), MatLib.flat(Color(0.2, 0.16, 0.12)), self, false)
			# Locker door left hanging open.
			var door := _box(p + Vector3(1.45, 0.9, -0.45), Vector3(0.04, 1.7, 0.45), MatLib.painted_steel(), self, false)
			door.rotation.y = 0.7
		else:
			# A folded towel over the foot rail, a mug on the locker top.
			_box(p + Vector3(0, 0.62, 0.95), Vector3(0.9, 0.06, 0.28), MatLib.canvas(Color(0.7, 0.62, 0.5)), self, false)
			_cyl_nc(p + Vector3(1.2, 1.86, -0.8), 0.07, 0.11, MatLib.flat(Color(0.8, 0.78, 0.72)))
		# A personal photo taped inside each locker, facing the bunk.
		_box(p + Vector3(0.98, 1.35, -0.8), Vector3(0.02, 0.22, 0.3), MatLib.flat(Color(0.55, 0.6, 0.62)), self, false)
	# Corridor light strip (dead — the grid is down; it stays a dark fixture).
	_box(Vector3(-18, y + 3.0, 11), Vector3(16, 0.08, 0.3), MatLib.dark_metal(), self, false)
	# A duffel someone packed and never took, a guitar propped in the corner.
	_box(Vector3(-21.5, y + 0.2, 8.5), Vector3(0.5, 0.4, 0.95), MatLib.flat(Color(0.3, 0.35, 0.28)), self, false)
	var guitar := _box(Vector3(-27.4, y + 0.55, 5.0), Vector3(0.34, 1.05, 0.11), MatLib.wood(), self, false)
	guitar.rotation.z = 0.14
	# Faded poster of somewhere green, and a wall calendar frozen on the last month.
	_box(Vector3(-12.0, y + 1.8, 17.85), Vector3(0.7, 0.9, 0.03), MatLib.flat(Color(0.35, 0.5, 0.4)), self, false)
	_box(Vector3(-22.0, y + 1.7, 17.85), Vector3(0.42, 0.55, 0.02), MatLib.flat(Color(0.86, 0.85, 0.8)), self, false)

func _decorate_galley() -> void:
	var y: float = DECK_Y
	# The stove: a working propane range now — COOK sears raw catch into meals.
	# Preloaded by path — the global class cache may not know the new file yet.
	var stove: Interactable = preload("res://scripts/components/cook_stove.gd").new()
	add_child(stove)
	stove.global_position = Vector3(11.5, y + 0.5, 16.2)
	stove.build_box_visual(Vector3(1.3, 1.0, 1.2), Color(0.16, 0.17, 0.19), false, true)
	# Its bottle: pressure that survived the Flash.
	_cyl_nc(Vector3(12.5, y + 0.45, 17.1), 0.17, 0.9, MatLib.galvanized())
	_plabel("LPG", Vector3(12.5, y + 0.55, 16.92), 180, 10, Color(0.8, 0.3, 0.2))
	_cyl_nc(Vector3(11.2, y + 1.02, 15.9), 0.18, 0.03, MatLib.flat(Color(0.1, 0.1, 0.1)))
	_cyl_nc(Vector3(11.8, y + 1.02, 16.5), 0.18, 0.03, MatLib.flat(Color(0.1, 0.1, 0.1)))
	_cyl_nc(Vector3(11.2, y + 1.15, 15.9), 0.2, 0.24, MatLib.painted_steel())
	# Fridge, door ajar — and still cold inside: STOW fish, it keeps forever.
	var fridge: Interactable = preload("res://scripts/components/cold_store.gd").new()
	add_child(fridge)
	fridge.global_position = Vector3(-1.2, y + 0.95, 15.2)
	fridge.build_box_visual(Vector3(0.9, 1.9, 0.9), Color(0.82, 0.84, 0.82), false, true)
	var fdoor := _box(Vector3(-0.7, y + 0.95, 15.85), Vector3(0.06, 1.85, 0.85), MatLib.flat(Color(0.78, 0.8, 0.78)), self, false)
	fdoor.rotation.y = 0.5
	# Wall shelves with canned rows.
	for sy in [1.6, 2.2]:
		_box(Vector3(-1.6, y + sy, 12.5), Vector3(0.35, 0.06, 3.2), MatLib.wood(), self, false)
		for i in range(5):
			_cyl_nc(Vector3(-1.6, y + sy + 0.12, 11.2 + i * 0.6), 0.09, 0.18, MatLib.flat(Color(0.6, 0.58, 0.5)))
	# Pan rail over the counter — doubles as a drying line for the catch.
	_cyl_nc(Vector3(9.5, y + 2.2, 17.4), 0.02, 3.0, MatLib.dark_metal()).rotation.z = deg_to_rad(90)
	var galley_line: Interactable = preload("res://scripts/components/hang_line.gd").new()
	galley_line.length_m = 2.8
	add_child(galley_line)
	galley_line.global_position = Vector3(9.5, y + 2.35, 17.4)
	for i in range(3):
		_cyl_nc(Vector3(8.3 + i * 1.1, y + 1.95, 17.4), 0.22, 0.04, MatLib.dark_metal())

func _decorate_rec_room() -> void:
	var y: float = DECK_Y
	# Rug, low table, and a card game nobody finished.
	_box(Vector3(23, y + 0.02, 12.5), Vector3(3.4, 0.03, 2.4), MatLib.flat(Color(0.4, 0.2, 0.18)), self, false)
	_box(Vector3(23, y + 0.28, 12.5), Vector3(1.5, 0.08, 0.95), MatLib.wood())
	# Werner & Kristjan's frozen chess game — a score card tucked under the white king.
	_readable("chess_note", "Score Card", Vector3(22.4, y + 0.35, 12.2), Vector3(0.12, 0.02, 0.16))
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
	# Wall clock, stopped at 2:47 — nobody wound it again. A real cased clock hung
	# on the rec room's west bulkhead: the steel rim sits hard on the wall face
	# (x18.125) and the dial, ticks and hands stack forward off it, so it reads as
	# mounted rather than floating a hand's width out in the room.
	var clock_c := Vector3(18.125, y + 2.3, 15.0)
	var clock_face := MatLib.flat(Color(0.9, 0.9, 0.86))
	var clock_ink := MatLib.flat(Color(0.11, 0.11, 0.12))
	_cyl_nc(clock_c + Vector3(0.028, 0, 0), 0.30, 0.055, MatLib.dark_metal()).rotation.z = deg_to_rad(90)
	_cyl_nc(clock_c + Vector3(0.066, 0, 0), 0.26, 0.022, clock_face).rotation.z = deg_to_rad(90)
	# Hour ticks round the dial.
	for i in range(12):
		var a: float = float(i) * TAU / 12.0
		var tick := _box(clock_c + Vector3(0.079, cos(a) * 0.215, -sin(a) * 0.215),
			Vector3(0.009, 0.032, 0.013), clock_ink, self, false)
		tick.rotation.x = -a
	# Hands stopped at 2:47 — hour just past 2, minute a shade before 10.
	for hand in [[83.5, 0.15, 0.022], [282.0, 0.21, 0.016]]:
		var th: float = deg_to_rad(float(hand[0]))
		var length: float = float(hand[1])
		var thick: float = float(hand[2])
		var dir := Vector3(0.0, cos(th), -sin(th))
		var hb := _box(clock_c + Vector3(0.086, 0, 0) + dir * (length * 0.5),
			Vector3(thick, length, thick * 0.6), clock_ink, self, false)
		hb.rotation.x = -th
	_cyl_nc(clock_c + Vector3(0.092, 0, 0), 0.022, 0.02, clock_ink).rotation.z = deg_to_rad(90)

func _decorate_machine_shop() -> void:
	var y: float = DECK_Y
	# Pegboard of tools, visible through the window — the tease continues.
	_box(Vector3(-21, y + 1.9, -17.6), Vector3(3.0, 1.4, 0.06), MatLib.flat(Color(0.75, 0.72, 0.6)), self, false)
	var tool_colors := [Color(0.7, 0.3, 0.2), Color(0.3, 0.4, 0.6), Color(0.5, 0.5, 0.5), Color(0.7, 0.6, 0.2), Color(0.4, 0.4, 0.4), Color(0.6, 0.35, 0.25)]
	for i in range(6):
		_box(Vector3(-22.2 + i * 0.5, y + 1.9 + (0.25 if i % 2 == 0 else -0.2), -17.55),
			Vector3(0.1, 0.4, 0.06), MatLib.flat(tool_colors[i]), self, false)
	# The fitter's bench. The shop's hand tools were authored at y+1.25 with NOTHING
	# under them — a tray of tools hanging in mid air. This is the bench they were
	# always meant to be lying on: timber top at y18.95 (a real 0.95m working
	# height), steel frame, a lower shelf. Tool positions now rest on it.
	var bench_top: float = y + 0.95
	_box(Vector3(-19.85, bench_top - 0.05, -12.05), Vector3(2.7, 0.1, 1.7), MatLib.weathered_wood())
	_box(Vector3(-19.85, y + 0.28, -12.05), Vector3(2.5, 0.05, 1.5), MatLib.dark_metal())  # lower shelf
	for lx in [-21.0, -18.7]:
		for lz in [-12.75, -11.35]:
			_box(Vector3(lx, y + 0.45, lz), Vector3(0.09, 0.9, 0.09), MatLib.dark_metal())
	# Apron rails under the top, so the frame reads as welded rather than floating.
	_box(Vector3(-19.85, y + 0.82, -12.85), Vector3(2.5, 0.07, 0.07), MatLib.dark_metal(), self, false)
	_box(Vector3(-19.85, y + 0.82, -11.25), Vector3(2.5, 0.07, 0.07), MatLib.dark_metal(), self, false)

	# Six hand tools you can actually pocket, left lying where the last shift put
	# them. The glTF shop models carry the look; the item ids are the inventory.
	_takeable_model("wrench", "pipe_wrench", "Pipe Wrench", Vector3(-19.2, bench_top, -12.3), 130)
	_takeable_model("hammer_tool", "cross_pein_hammer", "Hammer", Vector3(-20.0, bench_top, -11.45), 20)
	_takeable_model("spanner", "combination_wrench", "Spanner", Vector3(-19.45, bench_top, -12.62), 100)
	_takeable_model("screwdriver", "screwdriver", "Screwdriver", Vector3(-20.45, bench_top, -12.05), 60)
	# No file or hacksaw in the glTF library, and ItemVisual builds both standing
	# on end (right for a dropped item, wrong for a bench) — so these two are laid
	# down by hand to match the tools already lying around them.
	_takeable_custom("hand_file", "Hand File", Vector3(-18.8, bench_top, -12.4), _file_visual(), -30, 0.3)
	_takeable_custom("hacksaw", "Hacksaw", Vector3(-20.9, bench_top, -11.55), _hacksaw_visual(), 12, 0.38)

	# Parts bins along the wall.
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
	# Off to the WEST of the SPHL hatch (exit corridor is x18.6–21.4) so stepping
	# out of the pod lands the player on clear deck, the bench a few paces to the
	# side rather than dead ahead.
	var bench := CraftBench.new()
	add_child(bench)
	bench.global_position = Vector3(25.0, WET_Y, -17.5)
	bench.build_box_visual(Vector3(1.6, 0.9, 0.7), Color(0.5, 0.42, 0.3), false, true)
	_box(Vector3(25.0, WET_Y + 0.93, -17.5), Vector3(1.7, 0.06, 0.8), MatLib.wood(), self, false)
	# The Rigger's Handbook — chained to the bench, lists every recipe and how the
	# bench works. A lectern stand so it reads as a fixed shop reference, not loot.
	_box(Vector3(26.05, WET_Y + 0.62, -17.5), Vector3(0.35, 0.06, 0.5), MatLib.dark_metal(), self, false).rotation.z = deg_to_rad(-18)
	_box(Vector3(26.05, WET_Y + 0.3, -17.5), Vector3(0.06, 0.6, 0.06), MatLib.dark_metal(), self, false)
	var handbook := _readable("rigger_handbook", "Rigger's Handbook",
		Vector3(26.1, WET_Y + 0.72, -17.5), Vector3(0.32, 0.06, 0.42))
	handbook.rotation.z = deg_to_rad(-18)
	_plabel("RIGGING BENCH", Vector3(25.0, WET_Y + 1.5, -17.9), 180, 16, Color(0.85, 0.82, 0.7))
	_takeable("rope", "Rope Coil", Vector3(17.2, DECK_Y + 0.01, -15.8), Vector3(0.45, 0.3, 0.45))
	_takeable("prybar", "Prybar", Vector3(12.8, WET_Y + 1.81, -12.0), Vector3(0.15, 0.12, 0.9))
	# 1. Oil drums — loose physics props, wet deck and topside.
	for p in [Vector3(23.5, WET_Y + 0.6, -15.5), Vector3(24.4, WET_Y + 0.6, -14.6),
			Vector3(10.5, WET_Y + 0.6, -17.5), Vector3(6.5, DECK_Y + 0.6, -13.2),
			Vector3(-2.5, DECK_Y + 0.6, -17.2)]:
		EnvObjects.oil_drum(self, p)
	# 2. Life rings — mounted FLAT on real wall/rail faces, ring standing proud on a
	# backboard, facing into the open (never edge-on or half-buried).
	EnvObjects.life_ring(self, Vector3(12.0, WET_Y + 1.6, -14.12), 180.0, true)  # pump-room south wall, faces the approach
	EnvObjects.life_ring(self, Vector3(0, DECK_Y + 1.1, -19.9), 0.0)             # south rim, faces inboard (+Z)
	EnvObjects.life_ring(self, Vector3(-20, DECK_Y + 1.1, 19.9), 180.0)          # north rim, faces inboard (-Z)
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
	# Rec room west face, along Z. Shifted NORTH of the doorway: the door opening
	# is z10.3–11.7, and centred on z12 this rail ran z10.5–13.5, barring the way
	# in at waist height. Now z12.5–15.5 — a handhold beside the door, not across it.
	var r2 := _cyl_nc(Vector3(17.82, DECK_Y + 1.1, 14.0), 0.04, 3.0, MatLib.painted_steel())
	r2.rotation.x = deg_to_rad(90)
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

# ---------- Fine surface detail: rust weeps + water washes (sticker quads) ----------

const DECAL := preload("res://scripts/world/detail_decal.gd")

## Localized grime the uniform weathering can't do: rust bleeds streaking down from
## bolt lines and welds, water washes under the deck lip and window band. Sticker
## quads laid just off the concrete faces (Godot's Decal node is dead under
## gl_compatibility). Hand-placed at visible anchors, not sprayed.
func _surface_grime() -> void:
	var rust: Material = MatLib.stain_material("Leaking013A", Color(0.42, 0.24, 0.13), 0.8)
	var rust2: Material = MatLib.stain_material("Leaking017B", Color(0.5, 0.3, 0.16), 0.7)
	var wash: Material = MatLib.grime_mul("Leaking014A")
	var wash2: Material = MatLib.grime_mul("Leaking012C")
	var S := Vector3(0, 0, -1)   # face south (toward the wet deck / approach)
	# Pump-room south face (z=-14). Kept off the doorway (x~13.3-14.7) and the life
	# ring (x12): a weep on each solid pier, a grime wash on the east pier.
	DECAL.sticker(self, rust, Vector3(11.0, WET_Y + 1.9, -13.86), S, Vector2(0.35, 1.3))
	DECAL.sticker(self, rust2, Vector3(17.2, WET_Y + 1.7, -13.86), S, Vector2(0.28, 1.0))
	DECAL.sticker(self, wash, Vector3(16.0, WET_Y + 1.3, -13.86), S, Vector2(1.5, 1.9))
	# Stair-tower south face (z=-6) flanking the hatch-striped doorway.
	DECAL.sticker(self, rust, Vector3(24.0, WET_Y + 2.1, -5.86), S, Vector2(0.32, 1.4))
	DECAL.sticker(self, wash2, Vector3(28.0, WET_Y + 1.5, -5.86), S, Vector2(1.3, 2.0))
	# Loot-room north face (z=-16) — a long weep down the corner.
	DECAL.sticker(self, rust2, Vector3(10.4, WET_Y + 1.8, -16.14), Vector3(0, 0, 1), Vector2(0.3, 1.5))
	# Caisson legs: rust bleeds off the deck connection down the inboard faces (very
	# visible from the wet deck and the sea).
	for leg in [Vector3(-22, 0, -12), Vector3(22, 0, -12), Vector3(-22, 0, 12), Vector3(22, 0, 12)]:
		var nx: float = -sign(leg.x)                 # inboard normal (toward centre)
		var fx: float = leg.x + sign(leg.x) * -3.14  # inboard face
		DECAL.sticker(self, rust, Vector3(fx, DECK_Y - 4.0, leg.z - 1.4), Vector3(nx, 0, 0), Vector2(0.4, 4.5))
		DECAL.sticker(self, rust2, Vector3(fx, DECK_Y - 5.5, leg.z + 1.5), Vector3(nx, 0, 0), Vector2(0.3, 3.5))
		DECAL.sticker(self, wash, Vector3(fx, 3.5, leg.z), Vector3(nx, 0, 0), Vector2(2.4, 2.6))

# ---------- Industrial density pass: triple the piping + valves/gauges/bolts/welds ----------

## Orient a Y-axis primitive so its long axis runs along `axis` ("x"/"y"/"z").
func _orient(mi: Node3D, axis: String) -> void:
	if axis == "x":
		mi.rotation.z = deg_to_rad(90)
	elif axis == "z":
		mi.rotation.x = deg_to_rad(90)

## A ring of bolt heads around a flange face whose normal is `axis`.
func _bolt_ring(pos: Vector3, radius: float, axis: String, count: int, mat: Material) -> void:
	for i in range(count):
		var a: float = TAU * float(i) / float(count)
		var off: Vector3
		if axis == "x":
			off = Vector3(0, cos(a) * radius, sin(a) * radius)
		elif axis == "z":
			off = Vector3(cos(a) * radius, sin(a) * radius, 0)
		else:
			off = Vector3(cos(a) * radius, 0, sin(a) * radius)
		var b := _cyl_nc(pos + off, 0.018, 0.05, mat)
		_orient(b, axis)

## A bolted pipe flange: a thin raised collar with a ring of bolts.
func _flange(pos: Vector3, radius: float, axis: String, mat: Material) -> void:
	var d := _cyl_nc(pos, radius, 0.06, mat)
	_orient(d, axis)
	_bolt_ring(pos, radius * 0.72, axis, 6, MatLib.dark_metal())

## A hand-wheel gate valve straddling a pipe: bonnet body + red spoked wheel.
func _valve_wheel(pos: Vector3, axis: String, mat: Material) -> void:
	var body := _cyl_nc(pos, 0.08, 0.22, mat)
	_orient(body, axis)
	var stem_off: Vector3 = Vector3(0, 0.2, 0) if axis != "y" else Vector3(0.2, 0, 0)
	_cyl_nc(pos + stem_off * 0.6, 0.02, 0.24, MatLib.galvanized()).rotation = _wheel_stem_rot(axis)
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.1; tm.outer_radius = 0.17
	tm.material = MatLib.flat(Color(0.62, 0.14, 0.1))
	wheel.mesh = tm
	add_child(wheel); wheel.position = pos + stem_off
	# Wheel face across the stem; spokes.
	if axis == "y":
		wheel.rotation.z = deg_to_rad(90)
	for s in range(3):
		var spoke := _cyl_nc(pos + stem_off, 0.012, 0.3, MatLib.flat(Color(0.5, 0.12, 0.09)))
		if axis == "y":
			spoke.rotation.z = deg_to_rad(90)
			spoke.rotate_object_local(Vector3.UP, deg_to_rad(60 * s))
		else:
			spoke.rotate(Vector3.FORWARD, deg_to_rad(60 * s))

func _wheel_stem_rot(axis: String) -> Vector3:
	if axis == "y":
		return Vector3(0, 0, deg_to_rad(90))
	return Vector3.ZERO

## A round pressure gauge sitting on a wall/pipe, face normal along `axis`.
func _gauge(pos: Vector3, axis: String) -> void:
	var rim := _cyl_nc(pos, 0.1, 0.05, MatLib.dark_metal())
	_orient(rim, axis)
	var face_off: Vector3 = {"x": Vector3(0.03, 0, 0), "y": Vector3(0, 0.03, 0), "z": Vector3(0, 0, 0.03)}[axis]
	var face := _cyl_nc(pos + face_off, 0.085, 0.02, MatLib.flat(Color(0.9, 0.9, 0.85)))
	_orient(face, axis)
	# Needle (thin dark bar across the face).
	var needle := _box(pos + face_off * 1.2, Vector3(0.07, 0.012, 0.012), MatLib.flat(Color(0.1, 0.1, 0.1)), self, false)
	needle.rotation.z = deg_to_rad(35)

## A weld bead — a thin, slightly-glossy dark seam along a joint.
func _weld(a: Vector3, b: Vector3) -> void:
	_wire(a, b, 0.03, MatLib.flat(Color(0.22, 0.2, 0.19), true, 0.35))

## A fitted pipe run: the pipe, a flange + bolt ring at each end, optional valve
## and gauge partway along. `axis` is the run direction.
func _pipe_fitted(a: Vector3, b: Vector3, radius: float, axis: String, mat: Material,
		valve: bool = false, gauge: bool = false) -> void:
	_wire(a, b, radius, mat)
	_flange(a, radius * 1.5, axis, mat)
	_flange(b, radius * 1.5, axis, mat)
	if valve:
		_valve_wheel(a.lerp(b, 0.5), axis, mat)
	if gauge:
		_gauge(a.lerp(b, 0.32), axis if axis != "y" else "x")

## Everything the working rig would actually be strung with — run AFTER the
## primary dressing so it reads as a plant, not a diagram. Triples the pipe count
## and threads valves, gauges, bolted flanges, cable trays and weld seams
## through the wet deck, the legs, the topside skids and the interior ceilings.
func _more_industry() -> void:
	var pipe: Material = MatLib.rusty_metal()
	var steel: Material = MatLib.rust_steel()
	var dark: Material = MatLib.dark_metal()
	var galv: Material = MatLib.galvanized()

	# --- Wet-deck pipe banks hugging the structure faces (spawn's first view) ---
	# Pump room south face (z=-14.6), three stacked runs with valves + a gauge cluster.
	for spec in [[2.05, 0.13, true], [2.35, 0.1, false], [2.62, 0.08, false]]:
		_pipe_fitted(Vector3(10.2, WET_Y + spec[0], -14.55), Vector3(17.8, WET_Y + spec[0], -14.55),
			spec[1], "x", pipe, spec[2], false)
	_gauge(Vector3(12.5, WET_Y + 2.05, -14.4), "z")
	_gauge(Vector3(13.0, WET_Y + 1.75, -14.4), "z")
	# Pump room east face (x=18.1) — vertical risers dropping to the deck manifold.
	for rz in [-12.5, -10.0, -7.5]:
		_pipe_fitted(Vector3(18.15, WET_Y + 0.2, rz), Vector3(18.15, WET_Y + 2.7, rz), 0.09, "y", pipe, false, false)
		_valve_wheel(Vector3(18.3, WET_Y + 1.3, rz), "y", pipe)
	# A low deck manifold tying the pump-room risers together, gauges on the header.
	_pipe_fitted(Vector3(18.3, WET_Y + 0.3, -13.0), Vector3(18.3, WET_Y + 0.3, -7.0), 0.11, "z", pipe, true, true)
	# Loot room north face (z=-16.1) and stair tower west face (x=21.85).
	for spec2 in [[1.4, 0.09], [1.75, 0.07]]:
		_pipe_fitted(Vector3(10.3, WET_Y + spec2[0], -16.1), Vector3(15.7, WET_Y + spec2[0], -16.1), spec2[1], "x", pipe, false, false)
	for spec3 in [[1.2, 0.1, true], [1.6, 0.08, false], [2.0, 0.06, false]]:
		_pipe_fitted(Vector3(21.85, WET_Y + spec3[0], -5.6), Vector3(21.85, WET_Y + spec3[0], 1.6), spec3[1], "z", pipe, spec3[2], false)
	_gauge(Vector3(21.7, WET_Y + 1.2, -3.0), "x")

	# --- Under-deck: a riser + cable bundle up every leg, tied by a distribution ring ---
	for leg in [Vector3(-22, 0, -12), Vector3(22, 0, -12), Vector3(-22, 0, 12), Vector3(22, 0, 12)]:
		var fx: float = leg.x - sign(leg.x) * 3.15   # inboard face of the caisson
		var fz: float = leg.z - sign(leg.z) * 0.6
		for i in range(3):
			var ox: float = (i - 1) * 0.35
			_wire(Vector3(fx + ox, 0.6, fz), Vector3(fx + ox, DECK_Y - 1.3, fz), 0.08, pipe)
			if i == 1:
				for vy in [4.0, 9.0, 14.0]:
					_valve_wheel(Vector3(fx + ox - sign(leg.x) * 0.22, vy, fz), "y", pipe)
		# Cable tray riding beside the risers.
		_box(Vector3(fx, DECK_Y * 0.5, fz + 0.7), Vector3(0.5, DECK_Y - 2.0, 0.12), dark, self, false)
		for cy in range(6):
			_wire(Vector3(fx - 0.18, 2.0 + cy * 2.4, fz + 0.7), Vector3(fx + 0.18, 2.2 + cy * 2.4, fz + 0.7), 0.02, galv)
		# Bolt rings where the riser passes each X-brace node.
		for by in [1.6, 7.6, 13.6]:
			_bolt_ring(Vector3(fx, by, fz), 0.22, "y", 8, dark)

	# Distribution header under the deck linking the four risers (a big ring main).
	for seg in [[Vector3(-18.85, DECK_Y - 1.5, -11.4), Vector3(18.85, DECK_Y - 1.5, -11.4), "x"],
			[Vector3(-18.85, DECK_Y - 1.5, 11.4), Vector3(18.85, DECK_Y - 1.5, 11.4), "x"],
			[Vector3(-18.85, DECK_Y - 1.5, -11.4), Vector3(-18.85, DECK_Y - 1.5, 11.4), "z"],
			[Vector3(18.85, DECK_Y - 1.5, -11.4), Vector3(18.85, DECK_Y - 1.5, 11.4), "z"]]:
		_pipe_fitted(seg[0], seg[1], 0.12, seg[2], pipe, false, false)
	_valve_wheel(Vector3(0, DECK_Y - 1.5, -11.4), "x", pipe)
	_valve_wheel(Vector3(0, DECK_Y - 1.5, 11.4), "x", pipe)

	# --- Topside skid: a process manifold with a bank of gauges + valves ---
	var sx: float = -4.0
	_box(Vector3(sx, DECK_Y + 0.35, -14.0), Vector3(3.2, 0.7, 1.4), steel)
	for i in range(4):
		var px: float = sx - 1.2 + i * 0.8
		_pipe_fitted(Vector3(px, DECK_Y + 0.7, -14.6), Vector3(px, DECK_Y + 2.4, -14.6), 0.06, "y", pipe, false, false)
		_valve_wheel(Vector3(px, DECK_Y + 1.5, -14.4), "y", pipe)
		_gauge(Vector3(px, DECK_Y + 2.2, -14.35), "z")
	_pipe_fitted(Vector3(sx - 1.4, DECK_Y + 2.4, -14.6), Vector3(sx + 1.4, DECK_Y + 2.4, -14.6), 0.08, "x", pipe, true, false)

	# --- Interior ceiling services: pipe + conduit runs with drops in each room ---
	for run in [[Vector3(-27.5, DECK_Y + 2.7, 8.5), Vector3(-8.5, DECK_Y + 2.7, 8.5), "x"],   # bunkhouse
			[Vector3(-1.5, DECK_Y + 2.7, 12.0), Vector3(13.5, DECK_Y + 2.7, 12.0), "x"],       # galley
			[Vector3(18.5, DECK_Y + 2.7, 12.0), Vector3(27.5, DECK_Y + 2.7, 12.0), "x"]]:      # rec room
		_pipe_fitted(run[0], run[1], 0.06, run[2], pipe, true, true)
		_wire(run[0] + Vector3(0, 0.2, 0.25), run[1] + Vector3(0, 0.2, 0.25), 0.03, dark)  # conduit alongside

	# --- Weld seams along the primary girders + leg-to-deck joints ---
	for gz in [-18.0, -6.0, 6.0, 18.0]:
		_weld(Vector3(-29, DECK_Y - 0.6, gz), Vector3(29, DECK_Y - 0.6, gz))
	for leg2 in [Vector3(-22, 0, -12), Vector3(22, 0, -12), Vector3(-22, 0, 12), Vector3(22, 0, 12)]:
		_weld(leg2 + Vector3(-3.1, DECK_Y - 1.9, 0), leg2 + Vector3(3.1, DECK_Y - 1.9, 0))
		_bolt_ring(leg2 + Vector3(0, DECK_Y - 1.9, 0), 3.0, "y", 12, dark)

## Painted block lettering on a surface (shaded, single-sided — reads as stencil paint).
## pitch_deg tips the paint out of vertical: pass -90 to lay a marking FLAT on decking.
## Without it a stencil authored at floor height renders as an upright sheet standing
## in the plating with half the glyph buried, which is what "LIFEBOAT 2" used to do.
func _plabel(text: String, pos: Vector3, yaw_deg: float, font_size: int = 32,
		color: Color = Color(0.82, 0.83, 0.8), pitch_deg: float = 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	# Scaled down — oversized paint bled across panel joints and door reveals.
	l.font_size = maxi(12, int(font_size * 0.75))
	l.pixel_size = 0.01
	# Black stencil paint. The source color only sets how faded the paint reads
	# (paler args = older, more weathered lettering lifting toward charcoal).
	l.modulate = _paint_black(color)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # paint does not turn to face you
	add_child(l)
	l.position = pos
	l.rotation.y = deg_to_rad(yaw_deg)
	l.rotation.x = deg_to_rad(pitch_deg)

## Weathered black stencil paint. Brighter/more-saturated source colors read as
## slightly more faded (lifted toward charcoal); pale args stay near-black. Alpha
## carries through as paint coverage.
static func _paint_black(src: Color) -> Color:
	var wear: float = clampf((src.r + src.g + src.b) / 3.0, 0.0, 1.0)
	var k: float = lerpf(0.06, 0.17, wear)
	return Color(k, k, k * 1.08, minf(src.a, 0.9))

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
	# Sign plate welded to the barricade on two stubs. The warning used to sit 0.43 m
	# ABOVE the top of the bar, so from the deck it read as text hanging over open sea
	# — the one place on the rig where floating letters were most obvious.
	for sp in [-0.75, 0.75]:
		var stub := _box(bar_pos + perp * sp + Vector3(0, 1.16, 0) - u * 0.1,
			Vector3(0.06, 0.42, 0.06), MatLib.dark_metal(), self, false)
		stub.rotation.y = yaw
	var plate := _box(bar_pos + Vector3(0, 1.45, 0) - u * 0.14,
		Vector3(0.06, 0.44, 2.2), MatLib.flat(Color(0.85, 0.72, 0.1)), self, false)
	plate.rotation.y = yaw
	_plabel("SPAN OUT — SALTLINE-2", bar_pos + Vector3(0, 1.45, 0) - u * 0.18,
		rad_to_deg(yaw) - 90.0, 26, Color(0.2, 0.18, 0.12))   # faces back toward the rig
	# Hazard paint where the bridge leaves the deck.
	_box(Vector3(29.2, DECK_Y + 0.02, 14.0), Vector3(1.6, 0.02, 2.4), MatLib.flat(Color(0.8, 0.7, 0.1)), self, false)

# ---------- Phase 3: the arrival ----------

## You step out of the SPHL at the waterline and the rig should feel impossibly
## large: draft marks climbing the caisson, the rig's name high on the deck rim
## overhead, a warm battery lamp over the dock, chained bollards at the edge.
func _arrival_dressing() -> void:
	var dark: Material = MatLib.dark_metal()
	# Dock apron under the gangplank — checker plate, seated flush.
	_box(Vector3(19.5, WET_Y + 0.015, -21.4), Vector3(4.6, 0.03, 1.4), MatLib.checker_plate(), self, false)
	# Bollards with a slack chain, either side of the gangplank.
	for bx in [17.4, 21.6]:
		_cyl(Vector3(bx, WET_Y + 0.28, -21.7), 0.15, 0.55, MatLib.flat(Color(0.75, 0.65, 0.15)))
	_wire(Vector3(17.4, WET_Y + 0.6, -21.7), Vector3(19.5, WET_Y + 0.42, -21.7), 0.03, dark)
	_wire(Vector3(19.5, WET_Y + 0.42, -21.7), Vector3(21.6, WET_Y + 0.6, -21.7), 0.03, dark)
	# Tire fenders hung on the dock edge.
	for fx in [18.2, 20.8]:
		var tire := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.15
		tm.outer_radius = 0.31
		tm.material = MatLib.flat(Color(0.1, 0.1, 0.11))
		tire.mesh = tm
		add_child(tire)
		tire.position = Vector3(fx, WET_Y + 0.1, -22.05)
		tire.rotation.x = deg_to_rad(90)
	# Draft marks climbing the SE caisson's south face — the scale ruler.
	for i in range(7):
		var m: int = 2 + i * 2
		_plabel("— %d m" % m, Vector3(20.2, 0.4 + m, -15.1), 180, 24, Color(0.9, 0.85, 0.6))
	_plabel("SALTLINE-1 · CAISSON SE-3", Vector3(22, 13.2, -15.12), 180, 42, Color(0.7, 0.6, 0.42))
	# The rig's name on the deck rim girder, read from the dock looking straight up.
	_plabel("S A L T L I N E - 1", Vector3(17, 17.55, -20.3), 180, 110, Color(0.72, 0.6, 0.4))
	# Warm battery lamp on a gooseneck over the dock — the SPHL keeps its own light.
	_box(Vector3(22.4, WET_Y + 1.7, -22.2), Vector3(0.14, 3.4, 0.14), dark)
	_box(Vector3(21.4, WET_Y + 3.38, -22.2), Vector3(2.0, 0.1, 0.1), dark, self, false)
	_box(Vector3(20.5, WET_Y + 3.2, -22.2), Vector3(0.4, 0.25, 0.4), MatLib.flat(Color(0.95, 0.85, 0.6), true, 1.2), self, false)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 0.9
	lamp.omni_range = 9.0
	lamp.light_color = Color(1.0, 0.85, 0.62)
	add_child(lamp)
	lamp.position = Vector3(20.5, WET_Y + 3.0, -22.2)
	# Mooring chain heaped at the caisson's foot.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3131
	for i in range(3):
		var link := MeshInstance3D.new()
		var lm := TorusMesh.new()
		lm.inner_radius = 0.22
		lm.outer_radius = 0.42
		lm.material = MatLib.rusty_metal()
		link.mesh = lm
		add_child(link)
		link.position = Vector3(19.6 + rng.randf_range(-0.4, 0.4), WET_Y + 0.06 + i * 0.1, -14.0 + rng.randf_range(-0.4, 0.4))
		link.rotation.y = rng.randf() * TAU
		link.rotation.x = deg_to_rad(90) + rng.randf_range(-0.2, 0.2)
	# Painted walk lane from the dock toward the stair tower.
	for i in range(4):
		_box(Vector3(21.0 + i * 2.0, WET_Y + 0.02, -19.5 + i * 0.9), Vector3(1.0, 0.01, 0.3),
			MatLib.flat(Color(0.75, 0.65, 0.15)), self, false)

## Deck A + wet deck density: stools, pots, footlockers, hose reels — the
## second half of "double the interior detail".
## Bunting strung across the rec room. The flags used to be five loose rectangles
## floating at a fixed height with nothing holding them up — from the couch they read
## as props stuck in mid-air. Now a real cord runs wall to wall with a catenary sag and
## every pennant hangs FROM it: the cord curve is sampled once and both the cord
## segments and the flag tops are placed on that same curve, so a flag physically
## cannot drift off the line it is tied to. Someone strung this up for a birthday.
func _pennant_string(y: float) -> void:
	var z: float = 12.9
	var x0: float = 18.15                # west wall interior face
	var x1: float = 27.85                # east wall interior face
	var y_end: float = y + 2.95          # eyelets just under the deckhead (y + 3.075)
	var sag: float = 0.34
	var cord_mat: Material = MatLib.flat(Color(0.42, 0.38, 0.32))
	var cols: Array[Color] = [Color(0.7, 0.3, 0.2), Color(0.25, 0.4, 0.6), Color(0.75, 0.65, 0.2)]
	var steps: int = 24
	var pts: Array[Vector3] = []
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		pts.append(Vector3(lerpf(x0, x1, t), y_end - sag * 4.0 * t * (1.0 - t), z))
	for i in range(steps):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := _box((a + b) * 0.5, Vector3(a.distance_to(b) + 0.006, 0.012, 0.012),
			cord_mat, self, false)
		seg.rotation.z = atan2(b.y - a.y, b.x - a.x)
	for e in [pts[0], pts[steps]]:
		_cyl_nc(e, 0.022, 0.06, MatLib.galvanized())   # eyelet screw into the steel
	# Triangular flags, apex down, hinged at the cord: the polygon's origin IS the top
	# edge midpoint, so the flutter rotation pivots there and the top stays tied on.
	for i in range(9):
		var t: float = (float(i) + 0.5) / 9.0
		var tri := CSGPolygon3D.new()
		tri.polygon = PackedVector2Array([Vector2(-0.11, 0.0), Vector2(0.11, 0.0), Vector2(0.0, -0.3)])
		tri.depth = 0.012
		tri.material = MatLib.flat(cols[i % 3])
		tri.use_collision = false
		add_child(tri)
		tri.position = Vector3(lerpf(x0, x1, t), y_end - sag * 4.0 * t * (1.0 - t), z - tri.depth * 0.5)
		tri.rotation.z = 0.09 - float(i % 2) * 0.18

func _density_a() -> void:
	var y: float = DECK_Y
	# Galley: stools at every table, pot stack, menu board, bread crate.
	for tp in [Vector3(2, y, 11), Vector3(8, y, 11), Vector3(2, y, 14.5), Vector3(8, y, 14.5)]:
		for side in [-1.2, 1.2]:
			_box(tp + Vector3(side, 0.24, 0), Vector3(0.4, 0.48, 0.4), MatLib.flat(Color(0.32, 0.34, 0.38)), self, false)
	for i in range(3):
		_cyl_nc(Vector3(10.6, y + 1.06 + i * 0.14, 16.6), 0.16 - i * 0.03, 0.13, MatLib.galvanized())
	_box(Vector3(-1.86, y + 1.9, 12.5), Vector3(0.05, 0.8, 1.2), MatLib.flat(Color(0.2, 0.24, 0.22)), self, false)
	_plabel("GALLEY — LAST MENU: STEW", Vector3(-1.82, y + 1.9, 12.5), 90, 16, Color(0.85, 0.85, 0.78))
	_box(Vector3(0.6, y + 0.2, 16.6), Vector3(0.8, 0.4, 0.55), MatLib.wood(), self, false)
	# Rec room: second couch, low magazine table, pennant string.
	_box(Vector3(26.8, y + 0.35, 10.5), Vector3(1.0, 0.7, 2.2), MatLib.flat(Color(0.3, 0.34, 0.3)))
	_box(Vector3(24.8, y + 0.22, 10.5), Vector3(0.9, 0.06, 0.7), MatLib.wood(), self, false)
	_pennant_string(y)
	# Bunkhouse: footlockers, towel hooks, a dead space heater.
	for p in [Vector3(-25.5, y, 6.5), Vector3(-18.8, y, 6.5), Vector3(-12.0, y, 6.5),
			Vector3(-25.5, y, 15.5), Vector3(-18.8, y, 15.5), Vector3(-12.0, y, 15.5)]:
		_box(p + Vector3(0, 0.2, 1.45), Vector3(0.8, 0.4, 0.45), MatLib.flat(Color(0.35, 0.32, 0.26)))
	for hx in [-24.0, -16.0]:
		_box(Vector3(hx, y + 1.5, 17.83), Vector3(0.35, 0.55, 0.05), MatLib.flat(Color(0.75, 0.72, 0.68)), self, false)
	_box(Vector3(-9.0, y + 0.4, 5.0), Vector3(0.7, 0.8, 0.4), MatLib.flat(Color(0.6, 0.3, 0.16)))
	# Pump room: hose reel drum, spare wheels, toolbox on the dead pump.
	_cyl_nc(Vector3(16.8, WET_Y + 0.7, -7.0), 0.5, 0.4, MatLib.flat(Color(0.62, 0.14, 0.1))).rotation.z = deg_to_rad(90)
	for wz in [-8.2, -9.0]:
		var ww := CSGTorus3D.new()
		ww.inner_radius = 0.1
		ww.outer_radius = 0.2
		ww.material = MatLib.flat(Color(0.62, 0.14, 0.1))
		ww.use_collision = false
		add_child(ww)
		ww.position = Vector3(10.4, WET_Y + 0.2, wz)
	_box(Vector3(11.6, WET_Y + 1.92, -12.6), Vector3(0.5, 0.24, 0.3), MatLib.flat(Color(0.7, 0.45, 0.15)), self, false)
	# Loot room: shelf rack with mixed boxes.
	for sy in [0.6, 1.3]:
		_box(Vector3(10.4, WET_Y + sy, -19.0), Vector3(0.45, 0.06, 2.6), MatLib.wood(), self, false)
		for i in range(3):
			_box(Vector3(10.4, WET_Y + sy + 0.16, -19.8 + i * 0.8), Vector3(0.35, 0.28, 0.5),
				MatLib.flat([Color(0.5, 0.42, 0.3), Color(0.4, 0.45, 0.5)][i % 2]), self, false)
