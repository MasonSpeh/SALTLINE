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
const SL := preload("res://scripts/world/structure_lib.gd")

const KIT_ORDER := [
	# shelter & rest
	"bedroll_kit", "leanto_kit", "windbreak_kit", "rug_kit",
	# light & heat
	"bloom_lamp_kit", "lamp_post_kit", "brazier_kit",
	# work & storage
	"workbench_kit", "locker_kit", "shelf_kit", "drying_rack_kit",
	# water & growing
	"rain_catcher_kit", "planter_kit",
	# structure & ground
	"walkway_kit", "wall_panel_kit", "barricade_kit", "chair_kit", "drop_net_kit",
]

## Kits that may be mounted on a vertical surface (build mode aims a camera ray
## for these and aligns local +Z to the wall normal).
const WALL_MOUNT := ["shelf_kit"]

## Kits that lie flat and should tilt to follow a sloped deck instead of standing
## bolt-upright on it.
const TILT_TO_SURFACE := ["rug_kit", "walkway_kit", "bedroll_kit"]

static func display_name(kit: String) -> String:
	return {
		"bloom_lamp_kit": "Bloom Lamp", "leanto_kit": "Lean-To",
		"walkway_kit": "Plank Walkway", "barricade_kit": "Barricade",
		"drop_net_kit": "Drop Net",
		"bedroll_kit": "Bedroll", "locker_kit": "Job Box", "rain_catcher_kit": "Rain Catcher",
		"brazier_kit": "Brazier", "chair_kit": "Deck Chair", "workbench_kit": "Workbench",
		"drying_rack_kit": "Drying Rack", "planter_kit": "Kelp Planter", "shelf_kit": "Wall Shelf",
		"wall_panel_kit": "Wall Panel", "lamp_post_kit": "Lamp Post",
		"windbreak_kit": "Windbreak", "rug_kit": "Woven Rug",
	}.get(kit, kit)

## Placement thud, per material. A canvas bedroll must not land like a girder.
static func place_sound(kit: String) -> String:
	match kit:
		"bedroll_kit", "rug_kit", "windbreak_kit", "drying_rack_kit", "leanto_kit":
			return "step"
		"chair_kit", "workbench_kit", "walkway_kit", "shelf_kit":
			return "hatch"
	return "clang"

## Rough XZ radius of the built thing — used for aim-assisted dismantling of
## structures that carry no collider (rug, bedroll).
static func footprint(kit: String) -> float:
	match kit:
		"rug_kit", "bedroll_kit":
			return 1.1
		"walkway_kit", "wall_panel_kit", "windbreak_kit", "drying_rack_kit":
			return 1.2
	return 0.8

static func build(kit: String, ghost: bool = false) -> Node3D:
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
	var canvas := _mat(Color(0.65, 0.68, 0.62), ghost)
	_part(root, Vector3(-0.9, 0.85, -0.9), Vector3(0.12, 1.7, 0.12), wood, not ghost)
	_part(root, Vector3(0.9, 0.85, -0.9), Vector3(0.12, 1.7, 0.12), wood, not ghost)
	_part(root, Vector3(-0.9, 0.5, 0.9), Vector3(0.12, 1.0, 0.12), wood, not ghost)
	_part(root, Vector3(0.9, 0.5, 0.9), Vector3(0.12, 1.0, 0.12), wood, not ghost)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(2.1, 0.06, 2.3)
	rm.material = canvas
	roof.mesh = rm
	root.add_child(roof)
	roof.position = Vector3(0, 1.35, 0)
	roof.rotation.x = deg_to_rad(-19)
	if not ghost:
		var rbody := StaticBody3D.new()
		var rshape := CollisionShape3D.new()
		var rbox := BoxShape3D.new()
		rbox.size = rm.size
		rshape.shape = rbox
		rbody.add_child(rshape)
		root.add_child(rbody)
		rbody.position = roof.position
		rbody.rotation = roof.rotation
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
	winch.build_box_visual(Vector3(0.6, 0.9, 0.55), Interactable.COLOR_OPERABLE, false, true)
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
	# Ground tarp, then the padded roll on top of it.
	SL.box(root, Vector3(0, 0.015, 0), Vector3(1.16, 0.03, 2.26), dark)
	SL.box(root, Vector3(0, 0.07, 0), Vector3(0.96, 0.10, 2.04), canvas)
	SL.box(root, Vector3(0, 0.12, -0.1), Vector3(0.90, 0.04, 1.7), dark)   # the sleeping face, worn darker
	# The wool blanket, thrown back the way you left it — the one warm colour here.
	SL.box(root, Vector3(0, 0.17, 0.30), Vector3(0.94, 0.10, 0.94), wool)
	SL.box(root, Vector3(0, 0.24, 0.62), Vector3(0.92, 0.06, 0.34), wool)   # turned-back cuff
	SL.box(root, Vector3(0, 0.26, 0.44), Vector3(0.88, 0.03, 0.26), canvas)
	# Pillow: a rolled jacket, not a hotel cushion.
	SL.cyl(root, Vector3(0, 0.19, -0.78), 0.14, 0.52, canvas, false, Vector3(0, 0, deg_to_rad(90)))
	SL.box(root, Vector3(0, 0.24, -0.86), Vector3(0.46, 0.08, 0.22), canvas)
	# The spare bedding still rolled at the foot.
	SL.cyl(root, Vector3(0, 0.18, 1.02), 0.17, 0.94, dark, false, Vector3(0, 0, deg_to_rad(90)))
	SL.line(root, Vector3(-0.30, 0.18, 0.88), Vector3(-0.30, 0.18, 1.16), rope, 0.014)
	SL.line(root, Vector3(0.30, 0.18, 0.88), Vector3(0.30, 0.18, 1.16), rope, 0.014)
	if not ghost:
		var heat := WarmthZone.new()
		heat.mode = 1
		heat.setup(Vector3(1.7, 1.3, 2.6))
		root.add_child(heat)
		heat.position = Vector3(0, 0.6, 0)
		SL.comfort_marker(root, "bed", "bedroll_kit", Vector3(0, 0.16, -0.10), Vector3(0.96, 0.50, 2.00))
	return root

## A steel job-box: hinged lid, hasp, skids to keep it off the wet deck.
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
	if not ghost:
		SL.cyl(root, Vector3(0, 0.74, 0), 0.30, 0.03, SL.mat("water", false, 0.25))
		SL.comfort_marker(root, "water", "rain_catcher_kit", Vector3(0, 0.50, 0), Vector3(0.68, 0.90, 0.68))
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
		f.position = spots[i]
		var h: float = 0.34 + 0.10 * float(i % 3)
		SL.box(f, Vector3(0, h * 0.5, 0), Vector3(0.05, h, 0.02), blade, false,
			Vector3(0, deg_to_rad(24.0 * float(i)), deg_to_rad(6.0 - 3.0 * float(i % 3))))
		SL.box(f, Vector3(0, h + 0.03, 0), Vector3(0.045, 0.08, 0.02), frond)
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

## A real wall section: bolted plate on a pipe frame, braced at the back.
static func wall_panel(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var pipe: Material = SL.mat("pipe", ghost)
	var steel: Material = SL.mat("steel", ghost)
	var dark: Material = SL.mat("steel_dark", ghost)
	var bolt: Material = SL.mat("bolt", ghost)
	SL.box(root, Vector3(0, 0.06, 0), Vector3(2.14, 0.12, 0.22), dark, not ghost)
	for sx in [-1.0, 1.0]:
		SL.cyl(root, Vector3(sx * 0.99, 1.12, 0), 0.055, 2.24, pipe, not ghost)
		# Kicker brace to the deck behind the panel.
		SL.cyl(root, Vector3(sx * 0.99, 0.52, -0.34), 0.035, 1.20, pipe, false,
			Vector3(deg_to_rad(-32), 0, 0))
	SL.box(root, Vector3(0, 1.14, 0), Vector3(1.94, 2.02, 0.07), steel, not ghost)
	# Corrugation ribs, front face.
	for i in range(7):
		var x2: float = -0.81 + 0.27 * float(i)
		SL.box(root, Vector3(x2, 1.14, 0.05), Vector3(0.09, 1.96, 0.03), dark)
	SL.box(root, Vector3(0, 2.24, 0), Vector3(2.18, 0.10, 0.18), dark, not ghost)
	for sx2 in [-0.98, 0.98]:
		SL.bolts(root, Vector3(sx2, 0.22, 0.06), Vector3(sx2, 2.06, 0.06), 7, bolt)
	return root

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
