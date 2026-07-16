class_name Structures extends RefCounted
## Player-built structures. Each builder returns a Node3D; pass ghost=true for the
## build-mode preview (transparent, no collision, no lights/zones). The real versions
## plug into the systems the night respects: Bloom lamps make LightZones the crab
## honors, lean-tos make WarmthZones the cold respects.

const BLOOM_CIRCUIT := "bloom_lamps"   ## always-on: bio-light needs no breaker
const DROP_NET := preload("res://scripts/components/drop_net.gd")   # by path: class cache lags new files

const KIT_ORDER := ["bloom_lamp_kit", "leanto_kit", "walkway_kit", "barricade_kit", "drop_net_kit"]

static func display_name(kit: String) -> String:
	return {
		"bloom_lamp_kit": "Bloom Lamp", "leanto_kit": "Lean-To",
		"walkway_kit": "Plank Walkway", "barricade_kit": "Barricade",
		"drop_net_kit": "Drop Net",
	}.get(kit, kit)

static func build(kit: String, ghost: bool = false) -> Node3D:
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
	if not ghost:
		root.add_to_group("built_structures")   # ghosts are previews, not real structures
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
	if not ghost:
		root.add_to_group("built_structures")   # ghosts are previews, not real structures
	return root

## A lashed plank section: walkable, bridges gaps.
static func walkway(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var wood := _mat(Color(0.52, 0.42, 0.3), ghost)
	_part(root, Vector3(0, 0.08, 0), Vector3(2.2, 0.14, 1.0), wood, not ghost)
	_part(root, Vector3(0, 0.17, -0.42), Vector3(2.2, 0.05, 0.1), _mat(Color(0.4, 0.32, 0.22), ghost), false)
	_part(root, Vector3(0, 0.17, 0.42), Vector3(2.2, 0.05, 0.1), _mat(Color(0.4, 0.32, 0.22), ghost), false)
	if not ghost:
		root.add_to_group("built_structures")   # ghosts are previews, not real structures
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
	root.add_to_group("built_structures")
	return root

## Waist-high scrap wall.
static func barricade(ghost: bool) -> Node3D:
	var root := Node3D.new()
	var plate := _mat(Color(0.38, 0.4, 0.44), ghost)
	var wood := _mat(Color(0.5, 0.4, 0.28), ghost)
	_part(root, Vector3(0, 0.55, 0), Vector3(1.7, 1.1, 0.12), plate, not ghost)
	_part(root, Vector3(-0.7, 0.4, 0.25), Vector3(0.1, 0.8, 0.6), wood, not ghost)
	_part(root, Vector3(0.7, 0.4, 0.25), Vector3(0.1, 0.8, 0.6), wood, not ghost)
	if not ghost:
		root.add_to_group("built_structures")   # ghosts are previews, not real structures
	return root
