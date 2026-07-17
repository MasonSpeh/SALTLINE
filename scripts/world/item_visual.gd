class_name ItemVisual extends RefCounted
## Distinctive greybox meshes per item, so a glance tells you what's on the ground.
## Returns a Node3D you parent to a Takeable (or anything). Shapes echo the gyre-debris
## silhouettes for consistency: cans are cylinders, rope is a coil, planks are planks.

## Species tints for the raw-fish family — one silhouette, per-fish colors.
const FISH_TINT := {
	"fish_herring": Color(0.7, 0.85, 0.85), "fish_slate_cod": Color(0.42, 0.45, 0.5),
	"fish_mirrorjack": Color(0.85, 0.88, 0.92), "fish_chimefish": Color(0.75, 0.8, 0.6),
	"fish_sable_hake": Color(0.25, 0.27, 0.32), "fish_barrel_grouper": Color(0.5, 0.38, 0.3),
	"fish_ribbon_eel": Color(0.4, 0.6, 0.62), "fish_copper_sprat": Color(0.75, 0.5, 0.3),
	"fish_silver_ladder": Color(0.8, 0.84, 0.9), "fish_ember_snapper": Color(0.8, 0.4, 0.25),
	"fish_ghost_sole": Color(0.8, 0.82, 0.88), "fish_glasspike": Color(0.7, 0.8, 0.82),
	"fish_lodestone_bream": Color(0.5, 0.52, 0.6), "fish_drum_croaker": Color(0.55, 0.45, 0.4),
	"fish_miller_flounder": Color(0.55, 0.5, 0.42), "fish_fathom_halibut": Color(0.4, 0.42, 0.45),
}
const FISH_SIZE := {
	"fish_barrel_grouper": 1.4, "fish_fathom_halibut": 1.6, "fish_copper_sprat": 0.6,
	"fish_ribbon_eel": 1.2,
}

static func build(item_id: String) -> Node3D:
	var root := Node3D.new()
	match item_id:
		"fish_stone_crab":
			# Wide carapace, two heavy claws.
			_box(root, Vector3(0.3, 0.1, 0.24), Color(0.6, 0.35, 0.25), Vector3(0, 0.08, 0))
			_box(root, Vector3(0.1, 0.06, 0.14), Color(0.65, 0.4, 0.28), Vector3(-0.2, 0.07, 0.1))
			_box(root, Vector3(0.1, 0.06, 0.14), Color(0.65, 0.4, 0.28), Vector3(0.2, 0.07, 0.1))
			return root
		"fish_inkwell_squid":
			# Cone mantle + a skirt of tentacle stubs, faint teal glow.
			var cone := _cyl(root, 0.001, 0.3, Color(0.45, 0.55, 0.6), Vector3(0, 0.24, 0))
			(cone.mesh as CylinderMesh).bottom_radius = 0.09
			for i in range(4):
				_box(root, Vector3(0.03, 0.14, 0.03), Color(0.4, 0.5, 0.55),
					Vector3(cos(i * TAU / 4) * 0.05, 0.05, sin(i * TAU / 4) * 0.05))
			_box(root, Vector3(0.06, 0.06, 0.06), Color(0.2, 0.9, 0.85), Vector3(0, 0.3, 0), true, 0.8)
			return root
		"fish_gutter_prawn":
			var seg := _box(root, Vector3(0.16, 0.05, 0.06), Color(0.75, 0.6, 0.55), Vector3(0, 0.05, 0))
			seg.rotation.z = 0.3
			_box(root, Vector3(0.1, 0.04, 0.05), Color(0.7, 0.55, 0.5), Vector3(0.1, 0.03, 0))
			return root
	if item_id.begins_with("fish_"):
		_fish(root, FISH_TINT.get(item_id, Color(0.6, 0.65, 0.68)), FISH_SIZE.get(item_id, 1.0))
		return root
	match item_id:
		"canned_food":
			_can(root, Color(0.7, 0.72, 0.75), Color(0.6, 0.3, 0.2))
		"canned_peaches":
			_can(root, Color(0.8, 0.78, 0.7), Color(0.95, 0.65, 0.2))
		"sealed_tin":
			var body := _cyl(root, 0.15, 0.16, Color(0.55, 0.6, 0.62), Vector3(0, 0.08, 0))
			body.rotation.x = 0.0
		"water_ration":
			# Foil pouch: a thin, slightly domed flat box.
			_box(root, Vector3(0.22, 0.28, 0.06), Color(0.7, 0.74, 0.78), Vector3(0, 0.14, 0))
			_box(root, Vector3(0.22, 0.05, 0.06), Color(0.4, 0.55, 0.7), Vector3(0, 0.26, 0))
		"cable_spool":
			# Two end discs on a hub.
			for zy in [-0.16, 0.16]:
				var disc := _cyl(root, 0.26, 0.05, Color(0.25, 0.22, 0.2), Vector3(0, 0.26, zy))
				disc.rotation.x = deg_to_rad(90)
			var hub := _cyl(root, 0.14, 0.3, Color(0.35, 0.3, 0.2), Vector3(0, 0.26, 0))
			hub.rotation.x = deg_to_rad(90)
		"prybar":
			# Long iron shaft with a bent claw end.
			_box(root, Vector3(0.05, 0.05, 0.85), Color(0.28, 0.29, 0.32), Vector3(0, 0.1, 0))
			var claw := _box(root, Vector3(0.05, 0.16, 0.05), Color(0.28, 0.29, 0.32), Vector3(0, 0.14, -0.42))
			claw.rotation.x = deg_to_rad(35)
		"rope":
			_torus(root, 0.13, 0.3, Color(0.74, 0.67, 0.5), Vector3(0, 0.14, 0))
		"throwing_hook":
			_torus(root, 0.1, 0.24, Color(0.72, 0.64, 0.46), Vector3(0, 0.12, 0))
			var shank := _box(root, Vector3(0.04, 0.28, 0.04), Color(0.25, 0.26, 0.29), Vector3(0.18, 0.2, 0))
			shank.rotation.z = deg_to_rad(18)
			var barb := _box(root, Vector3(0.04, 0.12, 0.04), Color(0.25, 0.26, 0.29), Vector3(0.26, 0.1, 0))
			barb.rotation.z = deg_to_rad(-55)
		"flare":
			_cyl(root, 0.045, 0.34, Color(0.85, 0.2, 0.16), Vector3(0, 0.17, 0))
			_cyl(root, 0.05, 0.05, Color(0.2, 0.2, 0.22), Vector3(0, 0.35, 0))
		"life_ring":
			var ring := _torus(root, 0.1, 0.32, Color(0.92, 0.55, 0.2), Vector3(0, 0.34, 0))
			ring.rotation.x = deg_to_rad(90)
		"driftwood":
			_box(root, Vector3(0.9, 0.12, 0.28), Color(0.5, 0.4, 0.28), Vector3(0, 0.08, 0))
		"scrap_metal":
			var plate := _box(root, Vector3(0.55, 0.16, 0.42), Color(0.36, 0.37, 0.4), Vector3(0, 0.12, 0))
			plate.rotation.z = 0.25
		"crude_knife":
			# Wrapped grip below a ground-down shard blade.
			_box(root, Vector3(0.05, 0.18, 0.05), Color(0.32, 0.24, 0.16), Vector3(0, 0.09, 0))          # grip
			_box(root, Vector3(0.03, 0.04, 0.11), Color(0.2, 0.15, 0.1), Vector3(0, 0.19, 0))            # guard
			var blade := _box(root, Vector3(0.02, 0.34, 0.08), Color(0.62, 0.64, 0.68), Vector3(0, 0.4, 0.02))
			blade.rotation.x = deg_to_rad(-6)
		"crude_spear":
			# Long driftwood pole, rope lashing, a shard point lashed at the tip.
			var shaft := _box(root, Vector3(0.045, 1.35, 0.045), Color(0.5, 0.4, 0.28), Vector3(0, 0.6, 0))
			shaft.rotation.z = deg_to_rad(10)
			_box(root, Vector3(0.07, 0.09, 0.07), Color(0.72, 0.64, 0.46), Vector3(0.16, 1.05, 0))       # lashing
			var head := _box(root, Vector3(0.03, 0.28, 0.1), Color(0.6, 0.62, 0.66), Vector3(0.2, 1.32, 0))
			head.rotation.z = deg_to_rad(10)
		"tarp":
			_box(root, Vector3(0.5, 0.16, 0.4), Color(0.62, 0.66, 0.6), Vector3(0, 0.1, 0))
			_box(root, Vector3(0.52, 0.06, 0.18), Color(0.55, 0.6, 0.55), Vector3(0, 0.2, 0))
		"kelp_bundle":
			for i in range(4):
				var frond := _box(root, Vector3(0.06, 0.42, 0.03),
					Color(0.3, 0.75, 0.5), Vector3(-0.12 + i * 0.08, 0.22, 0.0), true, 1.4)
				frond.rotation.z = deg_to_rad(-14 + i * 9)
		"bloom_lamp_kit":
			_box(root, Vector3(0.3, 0.3, 0.3), Color(0.3, 0.34, 0.36), Vector3(0, 0.16, 0))
			_box(root, Vector3(0.16, 0.16, 0.16), Color(0.2, 0.9, 0.85), Vector3(0, 0.34, 0), true, 2.2)
		"leanto_kit":
			var roll := _cyl(root, 0.13, 0.5, Color(0.6, 0.64, 0.58), Vector3(0, 0.13, 0))
			roll.rotation.z = deg_to_rad(90)
		"walkway_kit":
			for i in range(3):
				_box(root, Vector3(0.6, 0.06, 0.5), Color(0.5, 0.4, 0.28), Vector3(0, 0.06 + i * 0.08, 0))
		"barricade_kit":
			_box(root, Vector3(0.5, 0.32, 0.12), Color(0.4, 0.36, 0.34), Vector3(0, 0.18, 0))
			_box(root, Vector3(0.08, 0.36, 0.08), Color(0.45, 0.35, 0.22), Vector3(-0.18, 0.18, 0))
			_box(root, Vector3(0.08, 0.36, 0.08), Color(0.45, 0.35, 0.22), Vector3(0.18, 0.18, 0))
		"fishing_rod":
			# Long tapering rod, cork grip, a small reel drum under the seat.
			var shaft := _box(root, Vector3(0.035, 1.5, 0.035), Color(0.45, 0.33, 0.2), Vector3(0, 0.55, 0))
			shaft.rotation.z = deg_to_rad(14)
			_box(root, Vector3(0.06, 0.3, 0.06), Color(0.65, 0.52, 0.35), Vector3(-0.14, 0.12, 0))
			var reel := _cyl(root, 0.07, 0.06, Color(0.25, 0.27, 0.3), Vector3(-0.1, 0.26, 0.05))
			reel.rotation.x = deg_to_rad(90)
		"cooked_fish":
			_box(root, Vector3(0.3, 0.06, 0.16), Color(0.62, 0.45, 0.26), Vector3(0, 0.05, 0))
			_box(root, Vector3(0.24, 0.02, 0.12), Color(0.35, 0.22, 0.12), Vector3(0, 0.09, 0))
		"cooked_fish_prime":
			_box(root, Vector3(0.42, 0.08, 0.2), Color(0.68, 0.48, 0.28), Vector3(0, 0.06, 0))
			_box(root, Vector3(0.34, 0.02, 0.15), Color(0.4, 0.24, 0.12), Vector3(0, 0.11, 0))
		"drop_net_kit":
			# A folded mesh bundle with two weights showing.
			_box(root, Vector3(0.4, 0.2, 0.32), Color(0.68, 0.62, 0.46), Vector3(0, 0.12, 0))
			_box(root, Vector3(0.1, 0.08, 0.1), Color(0.3, 0.31, 0.34), Vector3(-0.12, 0.26, 0.05))
			_box(root, Vector3(0.1, 0.08, 0.1), Color(0.3, 0.31, 0.34), Vector3(0.1, 0.26, -0.06))
		"glow_worm", "glow_worm_cooked":
			# Glowing sphere for raw/cooked worm (slightly different glow in hand)
			_box(root, Vector3(0.25, 0.25, 0.25), Color(0.2, 0.9, 0.85), Vector3(0, 0.125, 0), true, 1.0)
		_:
			_box(root, Vector3(0.28, 0.3, 0.28), Interactable.COLOR_TAKEABLE, Vector3(0, 0.15, 0))
	return root

## One fish silhouette: tapered capsule body, prism tail, a dot of eye.
static func _fish(root: Node3D, tint: Color, size_mul: float = 1.0) -> void:
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.06 * size_mul
	bm.height = 0.4 * size_mul
	bm.material = MatLib.flat(tint)
	body.mesh = bm
	body.rotation.z = deg_to_rad(90)
	root.add_child(body)
	body.position = Vector3(0, 0.08 * size_mul, 0)
	var tail := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(0.14, 0.02, 0.12) * size_mul
	tm.material = MatLib.flat(tint.darkened(0.25))
	tail.mesh = tm
	tail.rotation.z = deg_to_rad(90)
	root.add_child(tail)
	tail.position = Vector3(0.24 * size_mul, 0.08 * size_mul, 0)
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.015 * size_mul
	em.height = 0.03 * size_mul
	em.material = MatLib.flat(Color(0.05, 0.05, 0.06))
	eye.mesh = em
	root.add_child(eye)
	eye.position = Vector3(-0.15 * size_mul, 0.1 * size_mul, 0.045 * size_mul)

# ---- primitives ----

static func _box(root: Node3D, size: Vector3, color: Color, pos: Vector3,
		emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = MatLib.flat(color, emissive, energy)
	mi.mesh = m
	root.add_child(mi)
	mi.position = pos
	return mi

static func _cyl(root: Node3D, radius: float, h: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = h
	m.material = MatLib.flat(color)
	mi.mesh = m
	root.add_child(mi)
	mi.position = pos
	return mi

static func _can(root: Node3D, metal: Color, label: Color) -> void:
	_cyl(root, 0.11, 0.28, metal, Vector3(0, 0.14, 0))
	_cyl(root, 0.115, 0.14, label, Vector3(0, 0.14, 0))   # label band around the middle

static func _torus(root: Node3D, inner: float, outer: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.material = MatLib.flat(color)
	mi.mesh = m
	root.add_child(mi)
	mi.position = pos
	mi.rotation.x = deg_to_rad(90)
	return mi
