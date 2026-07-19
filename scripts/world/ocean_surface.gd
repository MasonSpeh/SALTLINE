class_name OceanSurface extends MeshInstance3D
## The sea: ONE camera-following radial mesh whose resolution grades from ~0.4 m
## quads at the player's feet to tens of metres out at the fog horizon. Detail is
## concentrated where the eye actually resolves chop; the old 2 m uniform plane
## physically could not show a 1.5 m wave. Vertices are world-locked (the Gerstner
## displacement in ocean_water.gdshader reads world_pos), and the node snaps its
## follow position to a coarse grid so the mesh is world-static between hops and the
## wave pattern never "swims" across it. No far plane, so no seam and nothing to poke
## through. See _build_ocean() in main.gd for wiring; gyre.gd mirrors the wave math.

const R_MAX: float = 1500.0        # rim inside the 1600 m star dome, lost in fog at the horizon
const ANG: int = 220               # angular segments (azimuthal resolution)
const NEAR_SPACING: float = 0.40   # innermost radial quad size (m)
const SPACING_GROW: float = 1.065  # radial spacing multiplier per ring
## Coarsest radial quad, far out. At 55 m the far field sampled the swell roughly once per
## wavelength, so at full sea state the horizon rendered as a row of dark rectangular teeth
## — a crenellated low-poly skyline exactly where a North Atlantic horizon should be a soft
## haze line. 18 m keeps the outer rings under the shortest long-swell wavelength, and
## ocean_water.gdshader now damps wave amplitude to nothing across the same distance band,
## so the two together flatten the far field into fog instead of aliasing it. The extra
## rings cost ~16k triangles on a mesh that is a single draw call.
const MAX_SPACING: float = 18.0
const FOLLOW_SNAP: float = 0.5     # snap follow pos to this grid (kills swim)

var _mat: ShaderMaterial
var vert_count: int = 0

func get_material_ref() -> ShaderMaterial:
	return _mat

func _ready() -> void:
	add_to_group("ocean_surface")
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://materials/ocean_water.gdshader")
	mesh = _build_mesh()
	material_override = _mat
	# 1500 m of water is not a shadow caster. With the default ON it was drawn into every
	# directional shadow split and stretched the caster bounds across the whole ocean.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Displaced far past its authored bounds and always around the camera: never cull.
	extra_cull_margin = R_MAX
	custom_aabb = AABB(Vector3(-R_MAX, -8.0, -R_MAX), Vector3(R_MAX * 2.0, 16.0, R_MAX * 2.0))

func _build_mesh() -> ArrayMesh:
	# Radii: dense near the camera, geometrically coarser outward, capped.
	var radii := PackedFloat32Array()
	var r: float = 0.0
	var spacing: float = NEAR_SPACING
	while r < R_MAX:
		r += spacing
		radii.append(r)
		spacing = minf(spacing * SPACING_GROW, MAX_SPACING)
	var rings: int = radii.size()

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	# Centre vertex (index 0), then ring by ring, ANG verts each.
	verts.append(Vector3.ZERO)
	norms.append(Vector3.UP)
	uvs.append(Vector2.ZERO)
	for ri in range(rings):
		var rad: float = radii[ri]
		for a in range(ANG):
			var th: float = TAU * float(a) / float(ANG)
			verts.append(Vector3(cos(th) * rad, 0.0, sin(th) * rad))
			norms.append(Vector3.UP)
			uvs.append(Vector2(float(a) / float(ANG), rad / R_MAX))
	vert_count = verts.size()

	var idx := PackedInt32Array()
	# Centre fan to ring 0. Winding: front faces UP (viewed from above the sea).
	var ring0_base: int = 1
	for a in range(ANG):
		var a1: int = (a + 1) % ANG
		idx.append(0)
		idx.append(ring0_base + a)
		idx.append(ring0_base + a1)
	# Quads between consecutive rings.
	for ri in range(rings - 1):
		var inner: int = 1 + ri * ANG
		var outer: int = 1 + (ri + 1) * ANG
		for a in range(ANG):
			var a1: int = (a + 1) % ANG
			var ia: int = inner + a
			var ib: int = inner + a1
			var oa: int = outer + a
			var ob: int = outer + a1
			idx.append(ia)
			idx.append(oa)
			idx.append(ob)
			idx.append(ia)
			idx.append(ob)
			idx.append(ib)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.custom_aabb = AABB(Vector3(-R_MAX, -8.0, -R_MAX), Vector3(R_MAX * 2.0, 16.0, R_MAX * 2.0))
	return am

func _process(_delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	global_position = Vector3(
		snappedf(cp.x, FOLLOW_SNAP),
		0.0,
		snappedf(cp.z, FOLLOW_SNAP))
