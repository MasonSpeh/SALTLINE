class_name Structures extends RefCounted
## Player-built structures. Each builder returns a Node3D; pass ghost=true for the
## build-mode preview (transparent, no collision, no lights/zones). The real versions
## plug into the systems the night respects: Bloom lamps make LightZones the crab
## honors, lean-tos and braziers make WarmthZones the cold respects.
##
## Every real build is stamped with meta "kit" (the kit id that made it) and joins
## group "built_structures", so build mode can dismantle it and a future save pass
## can rebuild it. Furniture kits also hang a "comfort_furniture" marker — see
## StructureLib.comfort_marker for that contract.

const BLOOM_CIRCUIT := "bloom_lamps"   ## always-on: bio-light needs no breaker
const FIRE_CIRCUIT := "built_fires"    ## always-on: a lit fire needs no breaker either
const DROP_NET := preload("res://scripts/components/drop_net.gd")   # by path: class cache lags new files
const DOOR := preload("res://scripts/components/door.gd")           # world agent's InteractDoor; by path per HARD RULE
const CATCHER_DOCK := preload("res://scripts/components/rain_catcher.gd")  # by path: class cache lags new files
const ITEM_EFFECTS := preload("res://scripts/components/item_effects.gd")  # by path: class cache lags — see build()
const SL := preload("res://scripts/world/structure_lib.gd")

const KIT_ORDER := [
	# shelter & rest
	"bedroll_kit", "leanto_kit", "windbreak_kit", "rug_kit",
	# light & heat
	"bloom_lamp_kit", "lamp_post_kit", "brazier_kit",
	# work & storage
	"workbench_kit", "storage_bin_kit", "locker_kit", "shelf_kit", "drying_rack_kit",
	# water & growing
	"rain_catcher_kit", "planter_kit",
	# structure & ground
	"walkway_kit", "floor_panel_kit", "wall_panel_kit", "window_panel_kit",
	"door_kit", "barricade_kit", "chair_kit", "drop_net_kit",
]

## Kits that may be mounted on a vertical surface (build mode aims a camera ray
## for these and aligns local +Z to the wall normal).
##
## Deliberately NOT here: wall_panel_kit and window_panel_kit. Both are freestanding
## SECTIONS with their own sill, posts and head — you stand them on the deck to make a
## wall where there wasn't one, exactly like the barricade. A wall-mounted wall panel
## would be a panel glued to the wall it duplicates.
const WALL_MOUNT := ["shelf_kit"]

## Kits that lie flat and should tilt to follow a sloped deck instead of standing
## bolt-upright on it. Deck panels belong here with the walkway: a floor that stands
## bolt-upright on a sloped plate leaves a lip you trip on.
const TILT_TO_SURFACE := ["rug_kit", "walkway_kit", "bedroll_kit", "floor_panel_kit"]

static func display_name(kit: String) -> String:
	return {
		"bloom_lamp_kit": "Bloom Lamp", "leanto_kit": "Lean-To",
		"walkway_kit": "Plank Walkway", "barricade_kit": "Barricade",
		"drop_net_kit": "Drop Net",
		"bedroll_kit": "Bedroll", "storage_bin_kit": "Storage Bin", "locker_kit": "Job Box", "rain_catcher_kit": "Rain Catcher",
		"brazier_kit": "Brazier", "chair_kit": "Deck Chair", "workbench_kit": "Workbench",
		"drying_rack_kit": "Drying Rack", "planter_kit": "Kelp Planter", "shelf_kit": "Wall Shelf",
		"wall_panel_kit": "Wall Panel", "lamp_post_kit": "Lamp Post",
		"windbreak_kit": "Windbreak", "rug_kit": "Woven Rug",
		"door_kit": "Wooden Door",
		"floor_panel_kit": "Deck Panel", "window_panel_kit": "Window Panel",
	}.get(kit, kit)

## Placement thud, per material. A canvas bedroll must not land like a girder.
static func place_sound(kit: String) -> String:
	match kit:
		"bedroll_kit", "rug_kit", "windbreak_kit", "drying_rack_kit", "leanto_kit":
			return "step"
		# floor_panel_kit sits here too: a deck plate dropped into place, not a girder landing.
		"chair_kit", "workbench_kit", "walkway_kit", "shelf_kit", "door_kit", "floor_panel_kit":
			return "hatch"
	return "clang"

## Rough XZ radius of the built thing — used for aim-assisted dismantling of
## structures that carry no collider (rug, bedroll).
static func footprint(kit: String) -> float:
	match kit:
		"rug_kit", "bedroll_kit":
			return 1.1
		# Keep every pattern on ONE line: GDScript cannot parse a match pattern list that
		# wraps onto the next line ("Expected expression for match pattern").
		"walkway_kit", "wall_panel_kit", "window_panel_kit", "windbreak_kit", "drying_rack_kit", "floor_panel_kit":
			return 1.2
	return 0.8

static func build(kit: String, ghost: bool = false) -> Node3D:
	# Belt-and-braces mount for the item-effects domain (heal / cures / returns). main.gd
	# is what actually mounts it; this is just a cheap static bool test once it is up.
	if not ghost:
		ITEM_EFFECTS.ensure()
	var root: Node3D = _build(kit, ghost)
	if not ghost:
		root.set_meta("kit", kit)
		if not root.is_in_group("built_structures"):
			root.add_to_group("built_structures")
	return root

static func _build(kit: String, ghost: bool) -> Node3D:
	match kit:
		"bloom_lamp_kit":
			return bloom_lamp(ghost)
		"leanto_kit":
			return lean_to(ghost)
		"walkway_kit":
			return walkway(ghost)
		"barricade_kit":
			return barricade(ghost)
		"drop_net_kit":
			return drop_net(ghost)
		"bedroll_kit":
			return bedroll(ghost)
		"storage_bin_kit":
			return storage_bin(ghost)
		"locker_kit":
			return locker(ghost)
		"rain_catcher_kit":
			return rain_catcher(ghost)
		"brazier_kit":
			return brazier(ghost)
		"chair_kit":
			return deck_chair(ghost)
		"workbench_kit":
			return workbench(ghost)
		"drying_rack_kit":
			return drying_rack(ghost)
		"planter_kit":
			return planter(ghost)
		"shelf_kit":
			return shelf(ghost)
		"wall_panel_kit":
			return wall_panel(ghost)
		"window_panel_kit":
			return window_panel(ghost)
		"floor_panel_kit":
			return floor_panel(ghost)
		"door_kit":
			return wooden_door(ghost)
		"lamp_post_kit":
			return lamp_post(ghost)
		"windbreak_kit":
			return windbreak(ghost)
		"rug_kit":
			return rug(ghost)
	return Node3D.new()

static func _mat(color: Color, ghost: bool, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ghost:
		m.albedo_color = Color(color.r, color.g, color.b, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		m.albedo_color = color
		if emissive > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = emissive
	m.roughness = 0.8
	return m

static func _part(root: Node3D, pos: Vector3, size: Vector3, mat: Material, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	root.add_child(mi)
	mi.position = pos
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		root.add_child(body)
		body.position = pos

## ============================================================ the first five

## Kelp-light on a scrap pole. The real one registers a LightZone on an always-on
## circuit — player-made safety, straight from canon.
static func bloom_lamp(ghost: bool) -> Node3D:
	var root: Node3D
	if ghost:
		root = Node3D.new()
	else:
		var zone := LightZone.new()
		zone.circuit_id = BLOOM_CIRCUIT
		zone.zone_extents = Vector3(7.0, 4.0, 7.0)
		root = zone
	var wood := _mat(Color(0.35, 0.36, 0.4), ghost)
	_part(root, Vector3(0, 0.75, 0), Vector3(0.14, 1.5, 0.14), wood, not ghost)
	_part(root, Vector3(0, 0.06, 0), Vector3(0.5, 0.12, 0.5), wood, not ghost)
	var head_mat := _mat(Color(0.2, 0.9, 0.85), ghost, 2.4)
	_part(root, Vector3(0, 1.62, 0), Vector3(0.3, 0.34, 0.3), head_mat, false)
	if not ghost:
		var light := OmniLight3D.new()
		light.light_color = Color(0.35, 0.95, 0.9)
		light.omni_range = 7.5
		light.light_energy = 2.4
		light.light_volumetric_fog_energy = 1.4
		light.shadow_enabled = true
		(root as LightZone).add_light(light)
		light.position = Vector3(0, 1.65, 0)
		PowerGrid.power_circuit(BLOOM_CIRCUIT)   # bio-light: lit the moment it exists
	return root

## Tarp roof over a driftwood frame; the real one carries a WarmthZone.
static func lean_to(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var wood := _mat(Color(0.5, 0.4, 0.28), ghost)
	_part(root, Vector3(-0.9, 0.85, -0.9), Vector3(0.12, 1.7, 0.12), wood, not ghost)
	_part(root, Vector3(0.9, 0.85, -0.9), Vector3(0.12, 1.7, 0.12), wood, not ghost)
	_part(root, Vector3(-0.9, 0.5, 0.9), Vector3(0.12, 1.0, 0.12), wood, not ghost)
	_part(root, Vector3(0.9, 0.5, 0.9), Vector3(0.12, 1.0, 0.12), wood, not ghost)
	# The roof is a TARP, not a plank. This kit predates StructureLib and kept a flat
	# 6cm BoxMesh in a washed-out grey, which from anywhere on the deck read as a pane
	# of glass balanced on four sticks — for the one structure you are meant to sleep
	# under. A sagging canvas panel in the real canvas material fixes it in one line.
	var roof_pos := Vector3(0, 1.35, 0)
	# +19, not -19: the tall posts are at z -0.9 and the short pair at z +0.9, so the
	# roof must be HIGH at the back. The old sign pitched it the wrong way — invisible
	# while the roof was a symmetrical flat slab, obvious the moment it became a tarp
	# lashed to a ridge pole.
	var roof_rot := Vector3(deg_to_rad(19), 0, 0)
	var roof_size := Vector2(2.1, 2.3)
	SL.canvas_panel(root, roof_pos, roof_size, SL.mat("canvas", ghost), roof_rot, not ghost)
	# A ridge pole along the high edge, which is what a tarp is actually lashed to.
	SL.cyl(root, Vector3(0, 1.72, -0.9), 0.045, 2.0, wood, false, Vector3(0, 0, deg_to_rad(90)))
	var lash: Material = SL.mat("rope", ghost)
	for sx in [-0.9, 0.9]:
		SL.line(root, Vector3(sx, 1.74, -0.86), Vector3(sx, 1.60, -0.94), lash, 0.012)
	if not ghost:
		var heat := WarmthZone.new()
		heat.mode = 1
		heat.setup(Vector3(2.4, 2.2, 2.6))
		root.add_child(heat)
		heat.position = Vector3(0, 1.0, 0)
	return root

## A lashed plank section: walkable, bridges gaps.
static func walkway(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var wood := _mat(Color(0.52, 0.42, 0.3), ghost)
	_part(root, Vector3(0, 0.08, 0), Vector3(2.2, 0.14, 1.0), wood, not ghost)
	_part(root, Vector3(0, 0.17, -0.42), Vector3(2.2, 0.05, 0.1), _mat(Color(0.4, 0.32, 0.22), ghost), false)
	_part(root, Vector3(0, 0.17, 0.42), Vector3(2.2, 0.05, 0.1), _mat(Color(0.4, 0.32, 0.22), ghost), false)
	return root

## Winch frame + weighted mesh: LOWER off a deck edge, soak, HAUL fish back up.
## The DropNet interactable is the winch pedestal; the net hangs from the boom.
static func drop_net(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var steel := _mat(Color(0.45, 0.32, 0.22), ghost)
	var cord := _mat(Color(0.68, 0.62, 0.46), ghost)
	# A-frame posts + outward boom.
	_part(root, Vector3(-0.5, 1.1, 0), Vector3(0.12, 2.2, 0.12), steel, not ghost)
	_part(root, Vector3(0.5, 1.1, 0), Vector3(0.12, 2.2, 0.12), steel, not ghost)
	_part(root, Vector3(0, 2.2, 0.7), Vector3(0.14, 0.14, 2.4), steel, false)
	# The net: an open mesh basket hung out at the boom tip.
	var net := Node3D.new()
	root.add_child(net)
	net.position = Vector3(0, 1.15, 1.85)
	for ring_y in [0.0, -0.55, -1.05]:
		_part(net, Vector3(0, ring_y, 0), Vector3(1.1, 0.04, 1.1), cord, false)
	for cx in [-0.55, 0.55]:
		for cz in [-0.55, 0.55]:
			_part(net, Vector3(cx, -0.5, cz), Vector3(0.035, 1.1, 0.035), cord, false)
	for wx in [-0.4, 0.4]:
		_part(net, Vector3(wx, -1.12, 0), Vector3(0.12, 0.1, 0.12), steel, false)   # weights
	# The net basket is SOLID — one box collider on the world layer covering the bag, so
	# nothing (fish, the player, any FaunaMove creature) passes through the mesh. Parented
	# to `net` so it rides the winch's raise/lower tween. Skipped for the build-mode ghost.
	if not ghost:
		var net_body := StaticBody3D.new()
		var net_shape := CollisionShape3D.new()
		var net_box := BoxShape3D.new()
		net_box.size = Vector3(1.15, 1.25, 1.15)
		net_shape.shape = net_box
		net_body.add_child(net_shape)
		net.add_child(net_body)
		net_body.position = Vector3(0, -0.5, 0)
	# Hang line from the boom tip (stretches with the drop).
	var rope_pivot := Node3D.new()
	root.add_child(rope_pivot)
	rope_pivot.position = Vector3(0, 2.2, 1.85)
	var rope := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.025
	rm.bottom_radius = 0.025
	rm.height = 1.0
	rm.material = cord
	rope.mesh = rm
	rope_pivot.add_child(rope)
	rope.position.y = -0.5
	rope_pivot.scale.y = 1.05
	if ghost:
		return root
	# The winch pedestal is the thing you operate.
	var winch: Interactable = DROP_NET.new()
	root.add_child(winch)
	winch.position = Vector3(0, 0.45, -0.55)
	winch.build_box_visual(Vector3(0.6, 0.9, 0.55), Interactable.COLOR_OPERABLE, false, true,
		MatLib.painted_steel())   # textured, not a flat red placeholder slab
	winch.net = net
	winch.rope_pivot = rope_pivot
	return root

## Waist-high scrap wall.
static func barricade(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var plate := _mat(Color(0.38, 0.4, 0.44), ghost)
	var wood := _mat(Color(0.5, 0.4, 0.28), ghost)
	_part(root, Vector3(0, 0.55, 0), Vector3(1.7, 1.1, 0.12), plate, not ghost)
	_part(root, Vector3(-0.7, 0.4, 0.25), Vector3(0.1, 0.8, 0.6), wood, not ghost)
	_part(root, Vector3(0.7, 0.4, 0.25), Vector3(0.1, 0.8, 0.6), wood, not ghost)
	return root

## ========================================================== the thirteen new
## Origin is the deck under the object (y = 0) unless noted. Nothing here
## collides that the player would rather walk over: bedrolls and rugs are
## walkable, benches and lockers are not.

## Canvas unrolled on the deck, a folded blanket at the foot, a lashed pillow.
## The single most important object in the game: it is where a shift ends.
static func bedroll(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var canvas: Material = SL.mat("canvas", ghost)
	var dark: Material = SL.mat("canvas_dark", ghost)
	var wool: Material = SL.mat("wool", ghost)
	var rope: Material = SL.mat("rope", ghost)
	# NOTHING SOFT HERE IS A BOX. This was a stack of hard-edged slabs that read as a
	# closed hardcover book on a pallet — the worst thing in a batch named after it.
	# Ground sheet: FLAT, not sagging. Canvas lying on deck plating has nothing to
	# droop into (a canvas_panel here sinks its sag straight through the floor); the
	# sag belongs to fabric that is stretched between two points.
	SL.box(root, Vector3(0, 0.012, 0), Vector3(1.20, 0.024, 2.34), dark)
	# The mattress: one rounded form, the length of a person.
	SL.bedding(root, Vector3(0, 0.10, -0.12), Vector3(0.92, 0.18, 1.96), canvas, Vector3.ZERO, 0.4)
	# The sleeping face, worn darker where you actually lie.
	SL.bedding(root, Vector3(0, 0.16, -0.20), Vector3(0.74, 0.06, 1.46), dark, Vector3.ZERO, 0.2)
	# The wool blanket: three folds lying ACROSS the bed at slightly different heights
	# and angles. One lump would read as a plate; folds read as something thrown back.
	for i in range(3):
		var fi: float = float(i)
		SL.bedding(root, Vector3(0.02 - 0.015 * fi, 0.20 + 0.014 * fi, 0.18 + 0.17 * fi),
			Vector3(0.34 - 0.02 * fi, 0.15 - 0.012 * fi, 0.90 - 0.03 * fi), wool,
			Vector3(deg_to_rad(-4.0 + 3.0 * fi), deg_to_rad(90.0 + 2.5 * fi), 0),
			0.6 + 0.2 * fi)
	# The turned-back corner of the top sheet, caught under the blanket.
	SL.bedding(root, Vector3(0.05, 0.26, 0.72), Vector3(0.20, 0.05, 0.74), canvas,
		Vector3(deg_to_rad(-10.0), deg_to_rad(86.0), 0), 0.3)
	# Pillow: a rolled jacket, not a hotel cushion.
	SL.bedding(root, Vector3(0, 0.21, -0.82), Vector3(0.30, 0.20, 0.52), canvas,
		Vector3(0, deg_to_rad(94.0), 0), 0.7)
	# The spare bedding still rolled at the foot, lashed with two turns of line.
	SL.cyl(root, Vector3(0, 0.15, 1.06), 0.13, 0.86, dark, false, Vector3(0, 0, deg_to_rad(90)))
	SL.line(root, Vector3(-0.27, 0.15, 0.94), Vector3(-0.27, 0.15, 1.18), rope, 0.014)
	SL.line(root, Vector3(0.27, 0.15, 0.94), Vector3(0.27, 0.15, 1.18), rope, 0.014)
	if not ghost:
		var heat := WarmthZone.new()
		heat.mode = 1
		heat.setup(Vector3(1.7, 1.3, 2.6))
		root.add_child(heat)
		heat.position = Vector3(0, 0.6, 0)
		SL.comfort_marker(root, "bed", "bedroll_kit", Vector3(0, 0.16, -0.10), Vector3(0.96, 0.50, 2.00))
	return root

## A steel job-box: hinged lid, hasp, skids to keep it off the wet deck.
## A crate knocked together from salvaged deck planks on a scrap-steel frame — the
## early-game stash, before you have the plate and bolts for a proper job box. Same
## storage contract as the locker (comfort_marker "storage" -> LootContainer), so it
## uses the crate/pack exchange panel with no new UI.
static func storage_bin(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var wood: Material = SL.mat("wood", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	# Two skids so it sits off the wet plating, like everything else out here.
	for sz in [-1.0, 1.0]:
		SL.box(root, Vector3(0, 0.04, sz * 0.24), Vector3(0.92, 0.08, 0.10), wood, not ghost)
	# Body: four plank walls around an open box, with a visible gap between courses.
	var h: float = 0.52
	for iz in [-1.0, 1.0]:
		for course in range(3):
			SL.box(root, Vector3(0, 0.14 + course * 0.17, iz * 0.27),
				Vector3(0.90, 0.15, 0.035), wood, not ghost and course == 0)
	for ix in [-1.0, 1.0]:
		for course in range(3):
			SL.box(root, Vector3(ix * 0.45, 0.14 + course * 0.17, 0),
				Vector3(0.035, 0.15, 0.54), wood, not ghost and course == 0)
	# Corner angle-iron: the scrap metal half of the recipe, doing visible work.
	for cx in [-0.45, 0.45]:
		for cz in [-0.27, 0.27]:
			SL.box(root, Vector3(cx, 0.30, cz), Vector3(0.05, 0.50, 0.05), dark)
	# Floor slats, a plank lid resting slightly askew, and a rope handle.
	SL.box(root, Vector3(0, 0.10, 0), Vector3(0.88, 0.03, 0.52), wood, not ghost)
	SL.box(root, Vector3(0.02, 0.60, 0), Vector3(0.94, 0.05, 0.58), wood, not ghost)
	SL.bolts(root, Vector3(-0.40, 0.30, 0.28), Vector3(0.40, 0.30, 0.28), 4, bolt)
	if not ghost:
		SL.comfort_marker(root, "storage", "storage_bin_kit", Vector3(0, 0.34, 0),
			Vector3(0.90, 0.52, 0.54), {"label": "Storage Bin"})
	return root

static func locker(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var steel: Material = SL.mat("steel", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	for sz in [-1.0, 1.0]:
		SL.box(root, Vector3(0, 0.045, sz * 0.22), Vector3(1.04, 0.09, 0.10), dark, not ghost)
	SL.box(root, Vector3(0, 0.44, 0), Vector3(1.00, 0.70, 0.56), steel, not ghost)
	# Stiffening ribs on the front face.
	for rx in [-0.28, 0.28]:
		SL.box(root, Vector3(rx, 0.44, 0.29), Vector3(0.06, 0.62, 0.03), dark)
	# Lid + hinge barrels + lip.
	SL.box(root, Vector3(0, 0.82, 0), Vector3(1.06, 0.08, 0.60), dark, not ghost)
	SL.box(root, Vector3(0, 0.76, 0.30), Vector3(1.06, 0.05, 0.05), steel)
	for hx in [-0.32, 0.32]:
		SL.cyl(root, Vector3(hx, 0.82, -0.29), 0.035, 0.16, bolt, false, Vector3(0, 0, deg_to_rad(90)))
	# Hasp and padlock — closed, because everything out here gets taken.
	SL.box(root, Vector3(0, 0.72, 0.30), Vector3(0.12, 0.18, 0.03), bolt)
	SL.box(root, Vector3(0, 0.62, 0.32), Vector3(0.07, 0.10, 0.05), dark)
	SL.bolts(root, Vector3(-0.44, 0.75, 0.29), Vector3(0.44, 0.75, 0.29), 5, bolt)
	SL.bolts(root, Vector3(-0.44, 0.15, 0.29), Vector3(0.44, 0.15, 0.29), 5, bolt)
	if not ghost:
		SL.comfort_marker(root, "storage", "locker_kit", Vector3(0, 0.46, 0), Vector3(1.00, 0.70, 0.56),
			{"label": "Job Box"})
	return root

## Tarp funnel on a pipe frame, draining down a spout into a drum. Free water,
## every time it rains — the first thing anyone builds twice.
static func rain_catcher(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var pipe: Material = SL.mat("pipe", ghost)
	var canvas: Material = SL.mat("canvas", ghost)
	var rust: Material = SL.mat("rust", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	SL.pipe_frame(root, 1.18, 1.62, 1.18, pipe, not ghost, 0.07)
	# Four canvas panels pitched inward: outer edges up, centre low.
	var tilt: float = deg_to_rad(26.0)
	SL.canvas_panel(root, Vector3(0, 1.62, 0.38), Vector2(1.46, 0.98), canvas, Vector3(-tilt, 0, 0))
	SL.canvas_panel(root, Vector3(0, 1.62, -0.38), Vector2(1.46, 0.98), canvas, Vector3(tilt, 0, 0))
	SL.canvas_panel(root, Vector3(0.38, 1.58, 0), Vector2(0.98, 1.46), canvas, Vector3(0, 0, tilt))
	SL.canvas_panel(root, Vector3(-0.38, 1.58, 0), Vector2(0.98, 1.46), canvas, Vector3(0, 0, -tilt))
	# Grommet lashings at the four corners.
	var rope: Material = SL.mat("rope", ghost)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			SL.line(root, Vector3(sx * 0.62, 1.74, sz * 0.62), Vector3(sx * 0.59, 1.55, sz * 0.59), rope, 0.012)
	# Spout down the middle into the drum.
	SL.cyl(root, Vector3(0, 1.24, 0), 0.05, 0.5, pipe)
	SL.cyl(root, Vector3(0, 0.46, 0), 0.34, 0.92, rust, not ghost)
	SL.ring(root, 0.90, 0.355, 0.05, dark)
	SL.ring(root, 0.16, 0.355, 0.05, dark)
	# ---- the bottling branch. The drum is the reservoir you DRINK from; this is the tap
	# you fill a bottle at. It is plumbed VISIBLY — tee, run, drop, nozzle — because a
	# bottle standing on its own beside a barrel is a mystery, and a bottle standing in a
	# cage under a dripping nozzle explains itself from across the deck.
	var bolt: Material = SL.mat("bolt", ghost)
	SL.cyl(root, Vector3(0, 1.06, 0), 0.038, 0.10, pipe)                                   # tee body
	SL.cyl(root, Vector3(0, 1.06, 0.44), 0.030, 0.88, pipe, false, Vector3(deg_to_rad(90), 0, 0))
	SL.cyl(root, Vector3(0, 0.94, 0.86), 0.030, 0.28, pipe)                                # the drop
	SL.cyl(root, Vector3(0, 0.785, 0.86), 0.042, 0.05, dark, false, Vector3.ZERO, 0.016)   # drip nozzle
	# Cradle: deck pad, stanchion, a tray, and a four-post cage so a full bottle can't
	# walk off it in a blow. Only the pad and the stanchion collide — the tray and cage
	# sit inside the dock's own interaction box, and a second collider in there would
	# steal the ray that has to reach the cradle.
	SL.box(root, Vector3(0, 0.02, 0.86), Vector3(0.24, 0.04, 0.24), dark, not ghost)
	SL.cyl(root, Vector3(0, 0.20, 0.86), 0.030, 0.36, pipe)
	SL.box(root, Vector3(0, 0.38, 0.86), Vector3(0.28, 0.03, 0.28), dark)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			SL.box(root, Vector3(cx * 0.115, 0.50, 0.86 + cz * 0.115),
				Vector3(0.018, 0.24, 0.018), bolt)
	for sz2 in [-1.0, 1.0]:
		SL.box(root, Vector3(0, 0.60, 0.86 + sz2 * 0.115), Vector3(0.25, 0.016, 0.016), bolt)
	SL.bolts(root, Vector3(-0.09, 0.40, 0.86), Vector3(0.09, 0.40, 0.86), 2, bolt, 0.028)
	if not ghost:
		# NAMED: RainButt._find_water matches on the name to raise and lower the level.
		# StructureLib's primitives leave Godot's "@MeshInstance3D@37" auto-names, which
		# match nothing — an unnamed disc here is a water line frozen forever.
		var water: MeshInstance3D = SL.cyl(root, Vector3(0, 0.74, 0), 0.30, 0.03,
			SL.mat("water", false, 0.25))
		water.name = "WaterLevel"
		SL.comfort_marker(root, "water", "rain_catcher_kit", Vector3(0, 0.50, 0), Vector3(0.68, 0.90, 0.68))
		# The cradle you dock a bottle in. Its own component, so the water-farm loop
		# (DOCK / SWAP / TAKE and the fill clock) lives nowhere near the geometry.
		var dock: Interactable = CATCHER_DOCK.new()
		root.add_child(dock)
		dock.position = Vector3(0, 0.40, 0.86)
	return root

## A cut-down drum with punched vents and a bed of embers. Light, heat, and the
## reason anyone sits down out here after dark.
static func brazier(ghost: bool) -> Node3D:
	var root: Node3D
	if ghost:
		root = Node3D.new()
	else:
		var zone := LightZone.new()
		zone.circuit_id = FIRE_CIRCUIT
		zone.zone_extents = Vector3(6.0, 4.0, 6.0)
		root = zone
	var rust: Material = SL.mat("rust", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var pipe: Material = SL.mat("pipe", ghost)
	# Three welded legs.
	for i in range(3):
		var a: float = TAU * float(i) / 3.0
		SL.cyl(root, Vector3(cos(a) * 0.26, 0.18, sin(a) * 0.26), 0.035, 0.36, pipe, not ghost)
	SL.cyl(root, Vector3(0, 0.62, 0), 0.33, 0.54, rust, not ghost)
	# Open rims, not capping discs — you must be able to see the fire in there.
	SL.ring(root, 0.89, 0.345, 0.05, dark)
	SL.ring(root, 0.37, 0.345, 0.05, dark)
	# Punched vents around the base of the fire chamber, glowing from within.
	var vent: Material = SL.mat("ember", ghost, 0.9)
	for i in range(8):
		var a2: float = TAU * float(i) / 8.0
		SL.box(root, Vector3(cos(a2) * 0.335, 0.50, sin(a2) * 0.335),
			Vector3(0.08, 0.10, 0.02), vent, false, Vector3(0, -a2, 0))
	# Fuel: driftwood over an ember bed.
	var wood: Material = SL.mat("driftwood", ghost)
	SL.cyl(root, Vector3(0, 0.74, 0), 0.28, 0.05, SL.mat("ember", ghost, 2.8))
	SL.cyl(root, Vector3(-0.04, 0.82, 0.02), 0.05, 0.42, wood, false, Vector3(deg_to_rad(8), deg_to_rad(30), deg_to_rad(74)))
	SL.cyl(root, Vector3(0.05, 0.86, -0.03), 0.045, 0.38, wood, false, Vector3(deg_to_rad(-6), deg_to_rad(-40), deg_to_rad(68)))
	if not ghost:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.58, 0.24)
		light.omni_range = 6.5
		light.light_energy = 2.2
		light.light_volumetric_fog_energy = 1.6
		light.shadow_enabled = true
		(root as LightZone).add_light(light)
		light.position = Vector3(0, 0.95, 0)
		var flick := SL.Flicker.new()
		flick.target = light
		flick.base_energy = 2.2
		flick.swing = 0.38
		root.add_child(flick)
		var heat := WarmthZone.new()
		heat.mode = 1
		heat.setup(Vector3(3.4, 2.6, 3.4))
		root.add_child(heat)
		heat.position = Vector3(0, 1.0, 0)
		PowerGrid.power_circuit(FIRE_CIRCUIT)   # a lit fire answers to no breaker
		SL.comfort_marker(root, "fire", "brazier_kit", Vector3(0, 0.66, 0), Vector3(0.70, 0.62, 0.70))
	return root

## Driftwood frame, canvas sling. Somewhere to sit and watch the water.
static func deck_chair(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var wood: Material = SL.mat("driftwood", ghost)
	var canvas: Material = SL.mat("canvas", ghost)
	var rope: Material = SL.mat("rope", ghost)
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.32
		SL.box(root, Vector3(x, 0.21, 0.28), Vector3(0.07, 0.42, 0.07), wood, not ghost,
			Vector3(deg_to_rad(-7), 0, 0))
		SL.box(root, Vector3(x, 0.30, -0.28), Vector3(0.07, 0.60, 0.07), wood, not ghost,
			Vector3(deg_to_rad(6), 0, 0))
		SL.box(root, Vector3(x, 0.44, 0.0), Vector3(0.06, 0.06, 0.80), wood, false,
			Vector3(deg_to_rad(-4), 0, 0))
		# Back stile, raked.
		SL.box(root, Vector3(x, 0.72, -0.40), Vector3(0.06, 0.62, 0.06), wood, false,
			Vector3(deg_to_rad(20), 0, 0))
	# Seat sling and back sling.
	SL.canvas_panel(root, Vector3(0, 0.42, 0.06), Vector2(0.62, 0.66), canvas, Vector3(deg_to_rad(-5), 0, 0), not ghost)
	SL.canvas_panel(root, Vector3(0, 0.70, -0.33), Vector2(0.62, 0.56), canvas, Vector3(deg_to_rad(70), 0, 0))
	SL.box(root, Vector3(0, 0.96, -0.44), Vector3(0.74, 0.06, 0.06), wood)
	SL.box(root, Vector3(0, 0.20, 0.36), Vector3(0.74, 0.05, 0.05), wood)
	# Lashings where the canvas wraps the rails.
	for sx2 in [-1.0, 1.0]:
		SL.line(root, Vector3(sx2 * 0.30, 0.47, 0.06), Vector3(sx2 * 0.34, 0.38, 0.06), rope, 0.012)
	if not ghost:
		SL.comfort_marker(root, "seat", "chair_kit", Vector3(0, 0.46, 0.04), Vector3(0.62, 0.50, 0.70))
	return root

## Plank top on a pipe frame with a vise stub bolted at the end.
static func workbench(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var pipe: Material = SL.mat("pipe", ghost)
	var wood: Material = SL.mat("wood", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	SL.pipe_frame(root, 1.66, 0.90, 0.62, pipe, not ghost, 0.07)
	# Lower shelf and the top itself.
	SL.planks(root, Vector3(0, 0.30, 0), 1.62, 0.58, 0.04, 4, wood)
	SL.planks(root, Vector3(0, 0.94, 0), 1.80, 0.72, 0.09, 5, wood, not ghost)
	SL.box(root, Vector3(0, 0.87, 0.34), Vector3(1.80, 0.06, 0.05), dark)   # front edge strap
	SL.bolts(root, Vector3(-0.8, 0.90, 0.36), Vector3(0.8, 0.90, 0.36), 7, bolt, 0.03)
	# Vise: body, fixed jaw, screw handle.
	SL.box(root, Vector3(0.68, 1.06, 0.22), Vector3(0.22, 0.16, 0.18), dark, not ghost)
	SL.box(root, Vector3(0.68, 1.09, 0.34), Vector3(0.24, 0.12, 0.05), dark)
	SL.cyl(root, Vector3(0.68, 1.08, 0.06), 0.022, 0.34, bolt, false, Vector3(0, 0, deg_to_rad(90)))
	SL.box(root, Vector3(0.86, 1.08, 0.06), Vector3(0.04, 0.05, 0.05), dark)
	if not ghost:
		SL.comfort_marker(root, "bench", "workbench_kit", Vector3(0, 0.92, 0), Vector3(1.78, 0.28, 0.70))
	return root

## Pipe uprights, three taut lines, hooks, and whatever is drying on it today.
static func drying_rack(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var pipe: Material = SL.mat("pipe", ghost)
	var rope: Material = SL.mat("rope", ghost)
	var canvas: Material = SL.mat("canvas", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.92
		SL.cyl(root, Vector3(x, 0.90, 0), 0.045, 1.80, pipe, not ghost)
		SL.box(root, Vector3(x, 0.04, 0), Vector3(0.20, 0.08, 0.56), SL.mat("steel_dark", ghost), not ghost)
		SL.bolts(root, Vector3(x, 0.06, -0.22), Vector3(x, 0.06, 0.22), 3, bolt, 0.03)
	SL.cyl(root, Vector3(0, 1.78, 0), 0.04, 1.90, pipe, false, Vector3(0, 0, deg_to_rad(90)))
	# Three lines at different heights, staggered front to back.
	var line_y := [1.58, 1.32, 1.06]
	var line_z := [0.0, 0.18, -0.18]
	for i in range(3):
		SL.line(root, Vector3(-0.90, line_y[i], line_z[i]), Vector3(0.90, line_y[i], line_z[i]), rope, 0.016)
	# Hooks over the top line.
	for hx in [-0.55, -0.18, 0.24, 0.62]:
		SL.box(root, Vector3(hx, 1.53, 0.0), Vector3(0.02, 0.10, 0.02), bolt)
		SL.box(root, Vector3(hx, 1.48, 0.03), Vector3(0.02, 0.02, 0.06), bolt)
	# Things hanging: two cloths and a strip of kelp, all moving in the wind.
	var hang_defs := [
		{"x": -0.55, "y": 1.53, "z": 0.0, "w": 0.28, "h": 0.52, "m": canvas},
		{"x": 0.24, "y": 1.53, "z": 0.0, "w": 0.22, "h": 0.44, "m": canvas},
		{"x": -0.18, "y": 1.27, "z": 0.18, "w": 0.14, "h": 0.60, "m": SL.mat("kelp", ghost, 0.0 if ghost else 0.6)},
	]
	for i in range(hang_defs.size()):
		var d: Dictionary = hang_defs[i]
		var f := SL.Flutter.new()
		f.amplitude = 0.09
		f.speed = 1.3 + 0.2 * float(i)
		f.phase = float(i) * 1.9
		f.axis = Vector3.RIGHT
		root.add_child(f)
		f.position = Vector3(d["x"], d["y"], d["z"])
		SL.box(f, Vector3(0, -float(d["h"]) * 0.5, 0), Vector3(float(d["w"]), float(d["h"]), 0.02), d["m"])
	if not ghost:
		SL.comfort_marker(root, "drying", "drying_rack_kit", Vector3(0, 1.06, -0.18), Vector3(1.80, 0.20, 0.12),
			{"span": 1.8})
	return root

## A steel tray of kelp mush with young fronds already coming up in it. Slow food,
## and the only green thing on the rig that is yours.
static func planter(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var steel: Material = SL.mat("rust", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var soil: Material = SL.mat("soil", ghost)
	for sz in [-1.0, 1.0]:
		SL.box(root, Vector3(0, 0.03, sz * 0.20), Vector3(1.02, 0.06, 0.10), dark, not ghost)
	SL.box(root, Vector3(0, 0.20, 0), Vector3(1.04, 0.26, 0.62), steel, not ghost)
	SL.box(root, Vector3(0, 0.34, 0), Vector3(1.08, 0.04, 0.66), dark)
	SL.box(root, Vector3(0, 0.31, 0), Vector3(0.94, 0.06, 0.52), soil)
	# Young fronds, swaying. Bloom-teal at the tips only — it is alive, not lit.
	var frond: Material = SL.mat("glow", ghost, 0.0 if ghost else 1.1)
	var blade: Material = SL.mat("kelp", ghost, 0.0 if ghost else 0.4)
	var spots := [
		Vector3(-0.34, 0.34, -0.12), Vector3(-0.14, 0.34, 0.14), Vector3(0.04, 0.34, -0.10),
		Vector3(0.22, 0.34, 0.12), Vector3(0.38, 0.34, -0.06), Vector3(-0.24, 0.34, 0.06),
	]
	for i in range(spots.size()):
		var f := SL.Flutter.new()
		f.amplitude = 0.05
		f.speed = 0.9 + 0.15 * float(i)
		f.phase = float(i) * 1.3
		f.axis = Vector3(0.6, 0, 0.4).normalized()
		root.add_child(f)
		# NAMED: Planter._collect_blades matches on the name to scale growth. The
		# FLUTTER is the blade, not the box inside it — scaling here lifts the frond
		# and its glowing tip together, from the soil line, as one plant.
		f.name = "Blade%d" % i
		f.position = spots[i]
		var h: float = 0.34 + 0.10 * float(i % 3)
		var yaw: float = deg_to_rad(24.0 * float(i))
		var lean: float = deg_to_rad(6.0 - 3.0 * float(i % 3))
		# A kelp blade is not a rectangular prism. Three tapering segments that curl a
		# little more the higher they get: wide and upright at the holdfast, narrow and
		# leaning at the tip. Same triangle count, reads as a plant instead of a peg.
		var segs: int = 3
		var y: float = 0.0
		for s in range(segs):
			var t: float = float(s) / float(segs)
			var seg_h: float = h / float(segs)
			var w: float = lerpf(0.055, 0.022, t)
			SL.box(f, Vector3(sin(t * 1.6) * 0.02, y + seg_h * 0.5, 0),
				Vector3(w, seg_h * 1.06, 0.014), blade, false,
				Vector3(0, yaw, lean * (1.0 + t * 2.2)))
			y += seg_h
		# The glowing tip: small, tapered, and the only saturated thing on the plant.
		SL.cyl(f, Vector3(sin(1.6) * 0.02, y + 0.035, 0), 0.016, 0.075, frond,
			false, Vector3(0, yaw, lean * 3.2), 0.002)
	if not ghost:
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.35, 0.95, 0.88)
		glow.omni_range = 2.6
		glow.light_energy = 0.55
		glow.light_volumetric_fog_energy = 0.6
		root.add_child(glow)
		glow.position = Vector3(0, 0.55, 0)   # too faint for safety: no LightZone
		SL.comfort_marker(root, "planter", "planter_kit", Vector3(0, 0.22, 0), Vector3(1.04, 0.26, 0.62))
	return root

## WALL-MOUNTED. Origin sits on the wall face, local +Z points out of the wall.
## Two salvaged planks on bent-strap brackets.
static func shelf(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var wood: Material = SL.mat("wood", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	for level in [0.0, 0.46]:
		SL.box(root, Vector3(0, level - 0.04, 0.03), Vector3(1.20, 0.06, 0.05), dark)   # wall cleat
		SL.planks(root, Vector3(0, level + 0.02, 0.18), 1.20, 0.30, 0.05, 2, wood, not ghost)
		SL.box(root, Vector3(0, level + 0.07, 0.32), Vector3(1.20, 0.05, 0.03), dark)   # fiddle rail
		for sx in [-1.0, 1.0]:
			var x: float = sx * 0.50
			SL.box(root, Vector3(x, level - 0.14, 0.03), Vector3(0.04, 0.28, 0.05), dark)
			SL.box(root, Vector3(x, level - 0.10, 0.14), Vector3(0.04, 0.26, 0.04), dark,
				false, Vector3(deg_to_rad(-45), 0, 0))
			SL.bolts(root, Vector3(x, level - 0.26, 0.02), Vector3(x, level - 0.04, 0.02), 2, bolt, 0.03)
	return root

## A real wall section: bolted plate on a flush stile-and-rail frame, standing on its
## own sill.
##
## DE-PIPED. This kit used to carry two round pipe posts standing proud of BOTH faces
## and — much worse — a pair of kicker braces raking 0.6 m out of the back of it at
## deck level. You could not stand a wall against anything, walking past one caught
## your shins, and from inside a room the thing read as scaffolding rather than as a
## wall. The frame is now flat bar, the same 0.09 the plate is thick, so the silhouette
## from either side is a panel and nothing else. Just the wall.
static func wall_panel(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var pipe: Material = SL.mat("pipe", ghost)
	var steel: Material = SL.mat("steel", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	SL.box(root, Vector3(0, 0.06, 0), Vector3(2.14, 0.12, 0.16), dark, not ghost)
	SL.box(root, Vector3(0, 1.14, 0), Vector3(1.94, 2.02, 0.07), steel, not ghost)
	# Edge stiles: the recipe's length of pipe, hammered out into bar stock and set flush
	# with the plate instead of left standing off the face.
	for sx in [-1.0, 1.0]:
		SL.box(root, Vector3(sx * 0.94, 1.14, 0), Vector3(0.10, 2.06, 0.09), pipe, not ghost)
	# Corrugation ribs, front face.
	for i in range(7):
		var x2: float = -0.81 + 0.27 * float(i)
		SL.box(root, Vector3(x2, 1.14, 0.05), Vector3(0.09, 1.96, 0.03), dark)
	SL.box(root, Vector3(0, 2.24, 0), Vector3(2.18, 0.10, 0.13), dark, not ghost)
	for sx2 in [-0.98, 0.98]:
		SL.bolts(root, Vector3(sx2, 0.22, 0.06), Vector3(sx2, 2.06, 0.06), 7, bolt)
	return root

## The same section with a light in it: salvaged panes bedded into a bolted surround, so
## a room you walled in still has weather in it. Same envelope, sill and head as the wall
## panel — stand the two in a row and the courses line up.
static func window_panel(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var pipe: Material = SL.mat("pipe", ghost)
	var steel: Material = SL.mat("steel", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	# GHOST CONTRACT: build_mode._tint_ghost mutates a mesh material's albedo in place,
	# and MatLib.glass hands back a CACHED material shared with every window on the rig —
	# tinting that would stain the lot. SL.mat(_, true) is always a fresh copy.
	var pane: Material = SL.mat("water", true) if ghost else MatLib.glass(Color(0.55, 0.68, 0.72))
	# Sill, head, flush edge stiles: identical to wall_panel so the two read as a set.
	SL.box(root, Vector3(0, 0.06, 0), Vector3(2.14, 0.12, 0.16), dark, not ghost)
	SL.box(root, Vector3(0, 2.24, 0), Vector3(2.18, 0.10, 0.13), dark, not ghost)
	for sx in [-1.0, 1.0]:
		SL.box(root, Vector3(sx * 0.94, 1.14, 0), Vector3(0.10, 2.06, 0.09), pipe, not ghost)
	# The plate, in four pieces around a 1.10 x 0.70 opening (x -0.55..0.55, y 1.20..1.90).
	SL.box(root, Vector3(0, 0.665, 0), Vector3(1.94, 1.07, 0.07), steel, not ghost)   # below
	SL.box(root, Vector3(0, 2.025, 0), Vector3(1.94, 0.25, 0.07), steel, not ghost)   # above
	for sx2 in [-1.0, 1.0]:
		SL.box(root, Vector3(sx2 * 0.76, 1.55, 0), Vector3(0.42, 0.70, 0.07), steel, not ghost)
	# Corrugation ribs on the solid lower field only — you do not rib a window.
	for i in range(7):
		var x3: float = -0.81 + 0.27 * float(i)
		SL.box(root, Vector3(x3, 0.66, 0.05), Vector3(0.09, 1.02, 0.03), dark)
	# The glazing: two panes with a centre mullion, because nobody salvages one sheet this
	# big intact. Thick enough to carry a real collider — a window you can walk through is
	# not a window.
	for px in [-1.0, 1.0]:
		SL.box(root, Vector3(px * 0.275, 1.55, 0), Vector3(0.52, 0.68, 0.03), pane, not ghost)
	SL.box(root, Vector3(0, 1.55, 0), Vector3(0.05, 0.72, 0.08), dark, not ghost)
	# Glazing surround: rebate all round, a drip ledge under the opening, and the storm bar
	# somebody bolted diagonally across the glass after the first bad night.
	for oy in [1.18, 1.92]:
		SL.box(root, Vector3(0, oy, 0.03), Vector3(1.18, 0.06, 0.05), dark)
	for ox in [-1.0, 1.0]:
		SL.box(root, Vector3(ox * 0.58, 1.55, 0.03), Vector3(0.06, 0.76, 0.05), dark)
	SL.box(root, Vector3(0, 1.14, 0.10), Vector3(1.26, 0.04, 0.14), dark)             # drip ledge
	SL.box(root, Vector3(0, 1.55, 0.06), Vector3(1.32, 0.06, 0.03), dark, false,
		Vector3(0, 0, deg_to_rad(-29.0)))                                            # storm bar
	SL.bolts(root, Vector3(-0.55, 1.14, 0.07), Vector3(0.55, 1.14, 0.07), 5, bolt, 0.03)
	for sx3 in [-0.98, 0.98]:
		SL.bolts(root, Vector3(sx3, 0.22, 0.06), Vector3(sx3, 2.06, 0.06), 7, bolt)
	return root

## A section of real deck: checker plate on an angle-iron frame, to lay over a hole, a
## gap between two structures, or nothing at all. Origin at deck level like the walkway,
## and it TILTS to follow a sloped plate (TILT_TO_SURFACE) so it never leaves a lip to
## catch a boot. Only the tread collides; the frame under it is dressing.
static func floor_panel(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var dark: Material = SL.mat("steel_dark", ghost)
	var pipe: Material = SL.mat("pipe", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	# Real checker plate for the built panel; a fresh tint-safe stand-in for the ghost
	# (see the GHOST CONTRACT note in window_panel).
	var tread: Material = SL.mat("steel", true) if ghost else MatLib.checker_plate()
	const W: float = 2.0
	# Perimeter angle-iron, so the panel has a visible edge instead of reading as a decal
	# painted on the deck.
	for sz in [-1.0, 1.0]:
		SL.box(root, Vector3(0, 0.05, sz * (W * 0.5 - 0.04)), Vector3(W, 0.10, 0.08), dark)
	for sx in [-1.0, 1.0]:
		SL.box(root, Vector3(sx * (W * 0.5 - 0.04), 0.05, 0), Vector3(0.08, 0.10, W - 0.16), dark)
	# Two joists across the middle of the span — the reason you can stand on it.
	for jz in [-0.62, 0.62]:
		SL.box(root, Vector3(0, 0.05, jz), Vector3(W - 0.16, 0.09, 0.07), pipe)
	SL.box(root, Vector3(0, 0.125, 0), Vector3(W, 0.05, W), tread, not ghost)
	# Two lifting slots and a bolt at each corner: a panel somebody unbolted from
	# somewhere else and carried here.
	for lx in [-0.5, 0.5]:
		SL.box(root, Vector3(lx, 0.152, 0), Vector3(0.16, 0.012, 0.05), dark)
	for bx in [-1.0, 1.0]:
		for bz in [-1.0, 1.0]:
			SL.box(root, Vector3(bx * 0.90, 0.152, bz * 0.90), Vector3(0.05, 0.02, 0.05), bolt)
	return root

## A ledged-and-braced plank door hung in a driftwood frame. The leaf IS the world
## agent's InteractDoor (OPEN/CLOSE, swings on its own origin), hinged at the LEFT
## jamb; the toggle-able collider it carries is what blocks the doorway when shut and
## drops while it stands open. The ghost preview draws the same leaf closed, no body.
static func wooden_door(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var wood: Material = SL.mat("wood", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	# Frame: two jambs + a header lintel. No sill — a threshold you trip on out here
	# is worse than none, and the doorway has to stay walkable.
	const FRAME_H: float = 2.06
	for sx in [-1.0, 1.0]:
		SL.box(root, Vector3(sx * 0.55, FRAME_H * 0.5, 0), Vector3(0.10, FRAME_H, 0.18), wood, not ghost)
	SL.box(root, Vector3(0, FRAME_H + 0.02, 0), Vector3(1.24, 0.14, 0.18), wood, not ghost)
	# Hinge at the left jamb inner face; the leaf hangs off it, extending in +X.
	const HINGE_X: float = -0.50
	const LEAF_W: float = 0.94
	const LEAF_H: float = 1.94
	var pivot: Node3D
	if ghost:
		pivot = Node3D.new()
	else:
		var d: InteractDoor = DOOR.new()
		d.display_name = "Wooden Door"
		pivot = d
	root.add_child(pivot)
	pivot.position = Vector3(HINGE_X, 0.0, 0.0)
	_door_leaf(pivot, LEAF_W, LEAF_H, wood, dark, bolt)
	if not ghost:
		# The one collider the door toggles: a slab filling the opening, offset to the
		# leaf centre so it sits IN the doorway rather than on the hinge line. Must be a
		# DIRECT child of the InteractDoor — that is what door.gd._set_collision walks.
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(LEAF_W, LEAF_H, 0.06)
		cs.shape = box
		pivot.add_child(cs)
		cs.position = Vector3(LEAF_W * 0.5, 0.05 + LEAF_H * 0.5, 0.0)
	return root

## The plank leaf, drawn onto `parent` with its hinge edge at the parent origin and
## the leaf running out in +X. Vertical boards, two back battens and a diagonal brace,
## hinge barrels at the hinge edge, a stub handle at the swinging edge.
static func _door_leaf(parent: Node3D, w: float, h: float,
		wood: Material, dark: Material, bolt: Material) -> void:
	var gy: float = 0.05                 # deck gap under the leaf
	var cy: float = gy + h * 0.5
	# Four vertical boards with saw gaps, side by side across the width.
	var bw: float = (w - 0.06) / 4.0
	for i in range(4):
		var bx: float = 0.06 + bw * (float(i) + 0.5)
		SL.box(parent, Vector3(bx, cy, 0), Vector3(bw * 0.9, h, 0.05), wood)
	# Two ledger battens across the back.
	for by in [cy - h * 0.32, cy + h * 0.32]:
		SL.box(parent, Vector3(w * 0.5, by, -0.045), Vector3(w * 0.9, 0.11, 0.03), dark)
	# Diagonal brace, hinge-low to latch-high — the "braced" half of the name.
	SL.box(parent, Vector3(w * 0.5, cy, -0.05), Vector3(w * 1.02, 0.09, 0.025), dark,
		false, Vector3(0, 0, deg_to_rad(-52.0)))
	# Hinge barrels + their bolt line, at the hinge edge.
	for hy in [cy - h * 0.34, cy + h * 0.34]:
		SL.cyl(parent, Vector3(0.04, hy, 0.03), 0.03, 0.16, dark)
	SL.bolts(parent, Vector3(0.11, cy - h * 0.34, 0.04), Vector3(0.11, cy + h * 0.34, 0.04), 4, bolt, 0.028)
	# Latch handle at the swinging edge.
	SL.cyl(parent, Vector3(w - 0.08, cy, 0.06), 0.02, 0.14, bolt, false, Vector3(deg_to_rad(90), 0, 0))

## A pipe mast with a glow-mucus lamp head in a bent-steel hood. Taller reach and
## a wider safe circle than the little bloom lamp — this is the one you plant at
## the door of a place you intend to keep.
static func lamp_post(ghost: bool) -> Node3D:
	var root: Node3D
	if ghost:
		root = Node3D.new()
	else:
		var zone := LightZone.new()
		zone.circuit_id = BLOOM_CIRCUIT
		zone.zone_extents = Vector3(9.0, 6.0, 9.0)
		root = zone
	var pipe: Material = SL.mat("pipe", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	SL.box(root, Vector3(0, 0.04, 0), Vector3(0.46, 0.08, 0.46), dark, not ghost)
	SL.bolts(root, Vector3(-0.18, 0.09, -0.18), Vector3(0.18, 0.09, -0.18), 2, bolt)
	SL.bolts(root, Vector3(-0.18, 0.09, 0.18), Vector3(0.18, 0.09, 0.18), 2, bolt)
	SL.cyl(root, Vector3(0, 1.36, 0), 0.055, 2.60, pipe, not ghost)
	# Gusset collar partway up — salvage never comes in one length.
	SL.cyl(root, Vector3(0, 1.30, 0), 0.075, 0.10, dark)
	# Hood and lens.
	SL.cyl(root, Vector3(0, 2.74, 0), 0.24, 0.20, dark, false, Vector3.ZERO, 0.07)
	var lens: Material = SL.mat("glow", ghost, 0.0 if ghost else 3.0)
	SL.cyl(root, Vector3(0, 2.52, 0), 0.15, 0.24, lens)
	# Mucus runs down the mast where it has leaked and dried.
	SL.box(root, Vector3(0.06, 2.30, 0.0), Vector3(0.03, 0.16, 0.03), lens)
	SL.box(root, Vector3(-0.05, 2.18, 0.03), Vector3(0.025, 0.10, 0.025), lens)
	if not ghost:
		var light := OmniLight3D.new()
		light.light_color = Color(0.35, 0.95, 0.9)
		light.omni_range = 9.0
		light.light_energy = 2.8
		light.light_volumetric_fog_energy = 1.5
		light.shadow_enabled = true
		(root as LightZone).add_light(light)
		light.position = Vector3(0, 2.52, 0)
		PowerGrid.power_circuit(BLOOM_CIRCUIT)
	return root

## Taut tarp between two pipe uprights, guyed to the deck, bottom edge loose so
## the wind can find it. Stand behind it and the cold eases off.
static func windbreak(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var pipe: Material = SL.mat("pipe", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var canvas: Material = SL.mat("canvas", ghost)
	var rope: Material = SL.mat("rope", ghost)
	for sx in [-1.0, 1.0]:
		var x: float = sx * 1.14
		SL.cyl(root, Vector3(x, 1.00, 0), 0.055, 2.00, pipe, not ghost)
		SL.box(root, Vector3(x, 0.04, 0), Vector3(0.26, 0.08, 0.26), dark, not ghost)
		SL.line(root, Vector3(x, 1.92, 0), Vector3(x * 1.42, 0.06, 0.52), rope, 0.014)
		SL.line(root, Vector3(x, 1.92, 0), Vector3(x * 1.42, 0.06, -0.52), rope, 0.014)
	SL.box(root, Vector3(0, 1.22, 0), Vector3(2.24, 1.42, 0.04), canvas, not ghost)
	SL.box(root, Vector3(0, 1.95, 0), Vector3(2.30, 0.08, 0.06), dark)   # head rope batten
	# Grommet lashings up both edges.
	for sx2 in [-1.09, 1.09]:
		SL.bolts(root, Vector3(sx2, 0.60, 0.03), Vector3(sx2, 1.86, 0.03), 5, SL.mat("bolt", ghost), 0.03)
	# The loose bottom edge, flapping.
	var flap := SL.Flutter.new()
	flap.amplitude = 0.11
	flap.speed = 1.9
	flap.axis = Vector3.RIGHT
	root.add_child(flap)
	flap.position = Vector3(0, 0.52, 0)
	SL.box(flap, Vector3(0, -0.17, 0), Vector3(2.20, 0.36, 0.03), canvas)
	if not ghost:
		var heat := WarmthZone.new()
		heat.mode = 1
		heat.setup(Vector3(2.6, 2.2, 1.8))
		root.add_child(heat)
		heat.position = Vector3(0, 1.0, 0.7)
	return root

## A mat woven out of kelp fibre. Does nothing. Changes everything: it is the
## difference between standing on a deck and standing in a room.
static func rug(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var warp: Material = SL.mat("kelp_dry", ghost)
	var weft: Material = SL.mat("rope", ghost)
	var edge: Material = SL.mat("canvas_dark", ghost)
	SL.box(root, Vector3(0, 0.012, 0), Vector3(1.70, 0.024, 1.16), warp)
	for i in range(7):
		var z: float = -0.46 + 0.155 * float(i)
		SL.box(root, Vector3(0, 0.026, z), Vector3(1.62, 0.008, 0.075), weft if i % 2 == 0 else warp)
	# Bound edges.
	for sz in [-1.0, 1.0]:
		SL.box(root, Vector3(0, 0.028, sz * 0.56), Vector3(1.70, 0.014, 0.05), edge)
	for sx in [-1.0, 1.0]:
		SL.box(root, Vector3(sx * 0.83, 0.028, 0), Vector3(0.05, 0.014, 1.16), edge)
		# Fringe.
		for i2 in range(7):
			SL.box(root, Vector3(sx * 0.90, 0.010, -0.45 + 0.15 * float(i2)),
				Vector3(0.10, 0.006, 0.03), warp)
	return root
