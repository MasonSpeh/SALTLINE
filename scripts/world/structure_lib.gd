class_name StructureLib extends RefCounted
## Shared salvage-language building blocks for player-built structures.
##
## Everything the player builds is made from the SAME small vocabulary: galvanised
## pipe, bolted plate, salt-grey planks, canvas, rope, and — only where light is
## actually involved — the Bloom's teal. These helpers keep all 18 kits speaking it.
##
## GHOST CONTRACT (build_mode._tint_ghost depends on it):
##   Ghost geometry must use FRESH per-call materials assigned to the MESH RESOURCE
##   (never material_override, never a cached MatLib static), because the tinter
##   mutates mesh.surface_get_material() albedo every frame. mat() handles this:
##   ghost=true always returns a brand-new transparent StandardMaterial3D.
##
## ORIGIN CONVENTION: author every structure with its origin at the mounting
## surface (y = 0 at the deck for floor kits; z = 0 at the wall face, +Z pointing
## out of the wall, for wall-mounted kits). build_mode drops the origin on the hit.

const PAL := {
	"steel": Color(0.44, 0.46, 0.50),
	"steel_dark": Color(0.26, 0.27, 0.30),
	"rust": Color(0.46, 0.30, 0.19),
	"pipe": Color(0.40, 0.42, 0.45),
	"bolt": Color(0.40, 0.41, 0.43),
	"wood": Color(0.52, 0.42, 0.30),
	"driftwood": Color(0.55, 0.52, 0.46),
	"canvas": Color(0.62, 0.60, 0.52),
	"canvas_dark": Color(0.40, 0.38, 0.33),
	"rope": Color(0.66, 0.60, 0.45),
	"kelp": Color(0.24, 0.38, 0.28),
	"kelp_dry": Color(0.35, 0.33, 0.21),   ## cured fibre — rope, matting, rugs
	"wool": Color(0.42, 0.24, 0.19),       ## the one warm colour anyone owns out here
	"glow": Color(0.24, 0.92, 0.82),
	"ember": Color(1.00, 0.45, 0.14),
	"soil": Color(0.19, 0.17, 0.13),
	"rubber": Color(0.15, 0.15, 0.16),
	"water": Color(0.30, 0.60, 0.62),
}

## Palette lookup. ghost -> fresh transparent flat material (tint-safe).
## emissive > 0 -> fresh emissive material (never a shared cache entry).
## otherwise -> the textured MatLib surface, so built things wear the rig's grain.
static func mat(kind: String, ghost: bool, emissive: float = 0.0) -> StandardMaterial3D:
	var c: Color = PAL.get(kind, Color(0.5, 0.5, 0.55))
	if ghost:
		var g := StandardMaterial3D.new()
		g.albedo_color = Color(c.r, c.g, c.b, 0.42)
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		g.roughness = 0.8
		return g
	if emissive > 0.0:
		var e := StandardMaterial3D.new()
		e.albedo_color = c
		e.emission_enabled = true
		e.emission = c
		e.emission_energy_multiplier = emissive
		e.roughness = 0.55
		return e
	match kind:
		"steel", "pipe":
			return MatLib.galvanized()
		"steel_dark":
			return MatLib.dark_metal()
		"rust":
			return MatLib.rust_steel()
		"wood":
			return MatLib.wood()
		"driftwood":
			return MatLib.weathered_wood()
		# Nothing out here is new. Canvas was near-white (0.80) and wool was saturated
		# enough to read as candy-pink against the teal ambient; both are pulled down
		# and desaturated so the bedroll looks slept in rather than gift-wrapped.
		"canvas":
			return MatLib.canvas(Color(0.68, 0.65, 0.58))
		"canvas_dark":
			return MatLib.canvas(Color(0.44, 0.42, 0.37))
		"wool":
			return MatLib.canvas(Color(0.44, 0.27, 0.22))
		"kelp_dry":
			return MatLib.canvas(Color(0.44, 0.41, 0.27))
		"rope":
			return MatLib.rope_mat()
	var f := StandardMaterial3D.new()
	f.albedo_color = c
	f.roughness = 0.85
	return f

# ---------------------------------------------------------------- primitives

## Box part. Optional euler rotation (radians) — collision follows it, which the
## bare Structures._part could not express.
static func box(root: Node3D, pos: Vector3, size: Vector3, m: Material,
		collide: bool = false, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	mi.mesh = bm
	root.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = size
		shape.shape = b
		body.add_child(shape)
		root.add_child(body)
		body.position = pos
		body.rotation = rot
	return mi

## Cylinder part — pipe, rope drum, lamp lens. top_radius < 0 means "same as
## bottom" (a tube); pass a smaller top_radius for a tapered hood.
static func cyl(root: Node3D, pos: Vector3, radius: float, height: float, m: Material,
		collide: bool = false, rot: Vector3 = Vector3.ZERO, top_radius: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 1
	cm.material = m
	mi.mesh = cm
	root.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = maxf(radius, cm.top_radius)
		cs.height = height
		shape.shape = cs
		body.add_child(shape)
		root.add_child(body)
		body.position = pos
		body.rotation = rot
	return mi

## A taut line (rope, drying line, guy wire) between two local points.
static func line(root: Node3D, a: Vector3, b: Vector3, m: Material, radius: float = 0.018) -> MeshInstance3D:
	var delta: Vector3 = b - a
	var span: float = delta.length()
	if span < 0.001:
		return null
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius
	cm.height = span
	cm.radial_segments = 6
	cm.rings = 1
	cm.material = m
	mi.mesh = cm
	root.add_child(mi)
	var dir: Vector3 = delta / span
	var ref: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var xa: Vector3 = ref.cross(dir).normalized()
	var za: Vector3 = dir.cross(xa).normalized()
	mi.transform = Transform3D(Basis(xa, dir, za), (a + b) * 0.5)
	return mi

## A run of separate planks with saw gaps — reads hand-cut, not extruded.
static func planks(root: Node3D, center: Vector3, length: float, width: float,
		thickness: float, count: int, m: Material, collide: bool = false,
		along_x: bool = true) -> void:
	var span: float = width / float(count)
	for i in range(count):
		var off: float = -width * 0.5 + span * (float(i) + 0.5)
		var jitter: float = (0.004 if i % 2 == 0 else -0.003)
		var sz: Vector3 = Vector3(length, thickness, span * 0.88) if along_x \
			else Vector3(span * 0.88, thickness, length)
		var p: Vector3 = center + (Vector3(0, jitter, off) if along_x else Vector3(off, jitter, 0))
		box(root, p, sz, m, false)
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(length, thickness, width) if along_x else Vector3(width, thickness, length)
		shape.shape = b
		body.add_child(shape)
		root.add_child(body)
		body.position = center

## Four pipe legs + a top rail square. Returns nothing; call before decking it.
static func pipe_frame(root: Node3D, width: float, height: float, depth: float,
		m: Material, collide: bool, leg: float = 0.07) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(root, Vector3(sx * width * 0.5, height * 0.5, sz * depth * 0.5),
				Vector3(leg, height, leg), m, collide)
	var rail: float = leg * 0.8
	for sz2 in [-1.0, 1.0]:
		box(root, Vector3(0, height - leg, sz2 * depth * 0.5),
			Vector3(width + leg, rail, rail), m, false)
	for sx2 in [-1.0, 1.0]:
		box(root, Vector3(sx2 * width * 0.5, height - leg, 0),
			Vector3(rail, rail, depth), m, false)

## An open ring of short segments — a drum rim you can still see down into, which
## a capping cylinder disc would read as a closed lid instead.
static func ring(root: Node3D, y: float, radius: float, thickness: float,
		m: Material, segments: int = 20) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = maxf(radius - thickness * 0.5, 0.005)
	tm.outer_radius = radius + thickness * 0.5
	tm.rings = segments
	tm.ring_segments = 6
	tm.material = m
	mi.mesh = tm
	root.add_child(mi)
	mi.position = Vector3(0, y, 0)
	return mi

## Bolt heads along a line — the detail that sells "somebody made this by hand".
static func bolts(root: Node3D, from_p: Vector3, to_p: Vector3, count: int,
		m: Material, size: float = 0.035) -> void:
	if count <= 0:
		return
	for i in range(count):
		var t: float = 0.0 if count == 1 else float(i) / float(count - 1)
		box(root, from_p.lerp(to_p, t), Vector3(size, size, size), m, false)

## Soft bedding: a rounded, slightly lumpy slab. Everything soft in this game was
## built out of BoxMesh, which is why the bedroll read as a hardcover book on a
## pallet — bedding has no square corners and no flat top. A squashed capsule gives
## a rounded silhouette from every angle for one primitive, and the wobble on the
## scale keeps two of them from looking stamped from the same die.
## `size` is (width X, thickness Y, length Z) in WORLD terms, like box().
static func bedding(root: Node3D, pos: Vector3, size: Vector3, m: Material,
		rot: Vector3 = Vector3.ZERO, lump: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	# CapsuleMesh runs along its local Y. Rotating +90° about X lays local Y down the
	# world Z (the length of the bed); local X stays width; local Z becomes world Y,
	# so squashing local Z is what makes a mattress out of a sausage.
	var radius: float = maxf(size.x, 0.02) * 0.5
	cm.radius = radius
	cm.height = maxf(size.z, radius * 2.0 + 0.001)
	cm.radial_segments = 14
	cm.rings = 4
	cm.material = m
	mi.mesh = cm
	root.add_child(mi)
	mi.position = pos
	var squash: float = maxf(size.y, 0.01) / maxf(size.x, 0.02)
	var basis := Basis.from_euler(rot) * Basis.from_euler(Vector3(deg_to_rad(90.0), 0, 0))
	mi.transform = Transform3D(basis, pos)
	var s := Vector3(1.0, 1.0, squash)
	if lump > 0.0:
		s *= Vector3(1.0 + lump * 0.07, 1.0 - lump * 0.05, 1.0 + lump * 0.10)
	mi.scale = s
	return mi

## A stretched canvas panel that actually SAGS. Every fabric on this rig comes
## through here — windbreak, lean-to roof, rain-catcher tarp, bedroll cover, chair
## sling — and for a long time this returned a 3cm box with razor-square corners,
## which read as a projector screen rather than as cloth lashed at its corners.
##
## The sheet is a subdivided grid pinned at the perimeter and drooping in the
## middle (a separable catenary approximation, near enough at this scale), with a
## little per-vertex ripple so the surface is never a clean mathematical dish and
## the free edges flutter slightly. Generated both-sides — a sagging sheet gets
## looked at from underneath, and flipping cull on the shared canvas material
## would turn every other user of it inside out.
##
## Collision, when asked for, stays a flat box: a 3cm discrepancy against the
## visible droop is invisible in play and keeps the physics cheap.
const CANVAS_SEGS: int = 6      ## grid cells per side; 6 is plenty at these spans
const CANVAS_SAG: float = 0.13  ## droop at the centre, as a fraction of the short side
const CANVAS_THICK: float = 0.022 ## real cloth thickness, so an edge-on sheet still reads

static func canvas_panel(root: Node3D, pos: Vector3, size: Vector2, m: Material,
		rot: Vector3 = Vector3.ZERO, collide: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _canvas_mesh(size, m)
	root.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(size.x, 0.03, size.y)
		shape.shape = b
		body.add_child(shape)
		root.add_child(body)
		body.position = pos
		body.rotation = rot
	return mi

static func _canvas_mesh(size: Vector2, m: Material) -> ArrayMesh:
	var sag: float = minf(size.x, size.y) * CANVAS_SAG
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# Deterministic per-size wobble: the same panel is identical every rebuild, but
	# a windbreak and a bedroll cover do not share a crease pattern.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(size.x * 1000.0), int(size.y * 1000.0)))
	var n: int = CANVAS_SEGS
	for iy in range(n + 1):
		for ix in range(n + 1):
			var u: float = float(ix) / float(n)
			var v: float = float(iy) / float(n)
			# Pinned edges, deepest at the centre.
			var du: float = 1.0 - pow(absf(u * 2.0 - 1.0), 2.0)
			var dv: float = 1.0 - pow(absf(v * 2.0 - 1.0), 2.0)
			var drop: float = -sag * du * dv
			# Ripple: strongest along the free span, never at a lashed corner.
			drop += sin(u * 9.1 + v * 4.3) * sag * 0.10 * du * dv
			drop += rng.randf_range(-0.004, 0.004)
			verts.append(Vector3((u - 0.5) * size.x, drop, (v - 0.5) * size.y))
			uvs.append(Vector2(u, v))
	# Normals from the finished surface, so the droop actually catches the light.
	for iy in range(n + 1):
		for ix in range(n + 1):
			var right: Vector3 = verts[iy * (n + 1) + mini(ix + 1, n)]
			var left: Vector3 = verts[iy * (n + 1) + maxi(ix - 1, 0)]
			var down: Vector3 = verts[mini(iy + 1, n) * (n + 1) + ix]
			var up: Vector3 = verts[maxi(iy - 1, 0) * (n + 1) + ix]
			var tangent: Vector3 = (right - left)
			var bitangent: Vector3 = (down - up)
			if tangent.length() < 0.0001 or bitangent.length() < 0.0001:
				normals.append(Vector3.UP)
			else:
				var nn: Vector3 = bitangent.cross(tangent).normalized()
				normals.append(nn if nn.y >= 0.0 else -nn)
	for iy in range(n):
		for ix in range(n):
			var a: int = iy * (n + 1) + ix
			var b2: int = a + 1
			var c: int = a + (n + 1)
			var d: int = c + 1
			# Winding must agree with the +Y normals computed above, or the sheet is
			# lit from underneath: the tarp tops went black and their undersides
			# caught the sun.
			idx.append_array([a, b2, c, b2, d, c])
	# Back faces: reversed winding, inverted normals, and pushed BACK ALONG THE NORMAL
	# so the sheet has real thickness. A zero-thickness sheet disappears into a line
	# when you see it edge-on — the lean-to roof, which is viewed edge-on from most of
	# the deck, became a pane of glass.
	var base: int = verts.size()
	var back_v := PackedVector3Array()
	var back_n := PackedVector3Array()
	for i in range(verts.size()):
		back_v.append(verts[i] - normals[i] * CANVAS_THICK)
		back_n.append(-normals[i])
	verts.append_array(back_v)
	normals.append_array(back_n)
	uvs.append_array(uvs.duplicate())
	var front_count: int = idx.size()
	for i in range(0, front_count, 3):
		idx.append_array([base + idx[i], base + idx[i + 2], base + idx[i + 1]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, m)
	return mesh

# ------------------------------------------------------------- comfort hooks

## CONTRACT for the comfort domain. Every furniture-ish structure hangs one of
## these markers: a plain Node3D child, in group "comfort_furniture", carrying
##   meta "kind"  -> "bed" | "seat" | "fire" | "storage" | "bench" | "drying"
##                   (extras this domain also emits: "water", "planter")
##   meta "kit"   -> the kit id that built it
##   meta "size"  -> Vector3 interaction volume, sized to sit INSIDE the geometry
##   plus any per-kind extras (e.g. "label" for storage, "span" for drying).
## The marker sits at the natural use point, inside the object, so the comfort
## domain's proxy adds a target rather than an obstacle. It can walk that group
## and attach interactions without ever touching structures.gd.
static func comfort_marker(root: Node3D, kind: String, kit: String, pos: Vector3,
		size: Vector3 = Vector3(0.8, 0.8, 0.8), extras: Dictionary = {}) -> Node3D:
	var n := Node3D.new()
	n.name = "Comfort_" + kind
	root.add_child(n)
	n.position = pos
	n.add_to_group("comfort_furniture")
	n.set_meta("kind", kind)
	n.set_meta("kit", kit)
	n.set_meta("size", size)
	for k in extras:
		n.set_meta(str(k), extras[k])
	return n

# ---------------------------------------------------------------- animation

## Slow, quiet motion for anything hanging in the North Sea wind. Rotation only —
## gl_compatibility has no GPU particles and cloth sim is not on the table.
class Flutter extends Node3D:
	var amplitude: float = 0.07
	var speed: float = 1.6
	var phase: float = 0.0
	var axis: Vector3 = Vector3.RIGHT
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		var s: float = sin(_t * speed + phase) * amplitude \
			+ sin(_t * speed * 2.37 + phase * 1.7) * amplitude * 0.35
		rotation = axis * s

## Ember breathing for the brazier: energy wanders, never strobes.
class Flicker extends Node3D:
	var target: Light3D
	var base_energy: float = 2.2
	var swing: float = 0.35
	var _t: float = 0.0

	func _process(delta: float) -> void:
		if target == null or not is_instance_valid(target):
			return
		_t += delta
		var f: float = sin(_t * 2.3) * 0.6 + sin(_t * 5.7) * 0.3 + sin(_t * 11.3) * 0.1
		target.light_energy = base_energy + f * swing
