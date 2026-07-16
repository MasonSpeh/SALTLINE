class_name CreatureKit extends RefCounted
## Shared anatomy for the Bloom's fauna: tapered organic bodies, articulated
## limbs, fins, eyes, glow organs. Every creature builds from the same parts so
## the whole ecosystem reads as one hand's design — pearl and teal, adapted,
## never grotesque (Bloom Rules §3).

static func mat(color: Color, rough: float = 0.65, glow: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

## A scaled sphere — the basic organic lump. squash scales the mesh instance.
static func ball(parent: Node3D, pos: Vector3, radius: float, material: Material,
		squash: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.material = material
	mi.mesh = sm
	parent.add_child(mi)
	mi.position = pos
	mi.scale = squash
	return mi

## A tapered body: spheres shrinking along an axis. Returns the segment nodes
## so callers can sway them (each is parented to the previous for whip motion).
static func spine(parent: Node3D, start: Vector3, step: Vector3, radii: Array,
		material: Material, chained: bool = false) -> Array:
	var out: Array = []
	var holder: Node3D = parent
	var pos: Vector3 = start
	for r in radii:
		var seg := Node3D.new()
		holder.add_child(seg)
		seg.position = pos if not chained or holder == parent else step
		ball(seg, Vector3.ZERO, r, material)
		out.append(seg)
		if chained:
			holder = seg
			pos = step
		else:
			pos += step
	return out

## A fin/fluke/wing section: a thin prism on its own pivot for animation.
static func fin(parent: Node3D, pivot_pos: Vector3, size: Vector3, material: Material,
		rot_deg: Vector3 = Vector3.ZERO, offset: Vector3 = Vector3.ZERO) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = pivot_pos
	pivot.rotation_degrees = rot_deg
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	pm.material = material
	mi.mesh = pm
	pivot.add_child(mi)
	mi.position = offset
	return pivot

## A capsule limb segment between two local points, on a pivot at `a`.
static func limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = a
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = a.distance_to(b) + radius
	cm.material = material
	mi.mesh = cm
	pivot.add_child(mi)
	var rel: Vector3 = b - a
	mi.position = rel * 0.5
	if rel.length() > 0.001:
		mi.look_at_from_position(mi.position, mi.position + rel, Vector3.UP if absf(rel.normalized().y) < 0.98 else Vector3.RIGHT)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return pivot

## An eye: dark iris on a pale ball, optional glow ring for the Bloom-touched.
static func eye(parent: Node3D, pos: Vector3, radius: float, glow: float = 0.0) -> MeshInstance3D:
	var white := ball(parent, pos, radius, mat(Color(0.85, 0.88, 0.86), 0.4, glow * 0.3))
	ball(white, Vector3(0, 0, -radius * 0.55), radius * 0.45, mat(Color(0.05, 0.05, 0.06), 0.3))
	return white

## A bioluminescent organ. Returns the material so callers can pulse it.
static func glow_spot(parent: Node3D, pos: Vector3, radius: float, color: Color,
		energy: float) -> StandardMaterial3D:
	var m := mat(color, 0.5, energy)
	ball(parent, pos, radius, m)
	return m
