class_name MatLib extends RefCounted
## Surface materials for the rig. Backed by the CC0 PBR texture library in
## res://assets/textures (ambientCG 1K sets — see LICENSES.md for role table);
## falls back to the original procedural noise surfaces when a set is missing.
## World-space triplanar so CSG/BoxMesh geometry needs no UVs and texture density
## stays uniform across mesh sizes. Palette per canon: gray water / rust orange /
## Bloom teal-and-pearl. Cached — call the getters, never construct twice.

const TEX_ROOT := "res://assets/textures/"

static var _cache: Dictionary = {}

static func _tex(folder: String, map: String) -> Texture2D:
	var path := "%s%s/%s_1K-JPG_%s.jpg" % [TEX_ROOT, folder, folder, map]
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Texture-backed weathered surface. tint multiplies albedo (keep it bright —
## heavy tints crush the maps). uv_scale: texture repeats per world meter.
## local=true switches to object-space triplanar for props that move (world
## triplanar makes texture swim across moving meshes).
static func _pbr(key: String, folder: String, tint: Color = Color.WHITE,
		uv_scale: float = 0.35, roughness: float = 1.0, metallic: float = 0.0,
		fallback_base: Color = Color(0.5, 0.5, 0.5), local: bool = false) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var albedo := _tex(folder, "Color")
	if albedo == null:
		return _surface(key, fallback_base, fallback_base.darkened(0.4), roughness, key.hash() % 997, 0.06, metallic)
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.albedo_color = tint
	var n := _tex(folder, "NormalGL")
	if n != null:
		m.normal_enabled = true
		m.normal_texture = n
	var r := _tex(folder, "Roughness")
	if r != null:
		m.roughness_texture = r
	m.roughness = roughness   # multiplies the map
	var ao := _tex(folder, "AmbientOcclusion")
	if ao != null:
		m.ao_enabled = true
		m.ao_texture = ao
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_world_triplanar = not local
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m

# ---------- structural steel ----------

static func rust_steel() -> StandardMaterial3D:
	## Deep pitted rust — derrick, trusses, anything the salt owns outright.
	return _pbr("rust", "Rust004", Color.WHITE, 0.35, 1.0, 0.0, Color(0.52, 0.3, 0.17))

static func rusty_metal() -> StandardMaterial3D:
	return _pbr("rusty", "Rust007", Color.WHITE, 0.3, 1.0, 0.0, Color(0.45, 0.25, 0.12))

static func painted_steel() -> StandardMaterial3D:
	## Once-white paint peeled to rust — the accommodation block's weather face.
	return _pbr("paint", "PaintedMetal013", Color.WHITE, 0.28, 1.0, 0.0, Color(0.6, 0.66, 0.63))

static func dark_metal() -> StandardMaterial3D:
	## Grungy riveted plate — caissons, machinery, structural dark steel.
	return _pbr("dark", "MetalPlates013", Color.WHITE, 0.32, 1.0, 0.25, Color(0.22, 0.23, 0.26))

static func galvanized() -> StandardMaterial3D:
	return _pbr("galv", "Metal032", Color.WHITE, 0.5, 1.0, 0.55, Color(0.6, 0.63, 0.65))

static func deck_plate() -> StandardMaterial3D:
	## Worn dark treadplate — every main deck underfoot.
	return _pbr("deck", "DiamondPlate008B", Color.WHITE, 0.5, 1.0, 0.2, Color(0.4, 0.41, 0.44))

static func checker_plate() -> StandardMaterial3D:
	## Brighter anti-slip plate for aprons and stair landings.
	return _pbr("checker", "DiamondPlate002", Color.WHITE, 0.6, 1.0, 0.35, Color(0.3, 0.31, 0.34))

static func grating() -> StandardMaterial3D:
	## Open walkway grating (rendered opaque — reads as grate at play distance).
	return _pbr("grating", "MetalWalkway013", Color.WHITE, 0.8, 1.0, 0.3, Color(0.28, 0.29, 0.31))

# ---------- paint & cladding ----------

static func corrugated() -> StandardMaterial3D:
	## Weathered galvanized corrugated sheet — sheds, roofs, hut cladding.
	return _pbr("corr", "CorrugatedSteel005", Color.WHITE, 0.4, 1.0, 0.2, Color(0.55, 0.57, 0.58))

static func corrugated_paint(tint: Color = Color.WHITE) -> StandardMaterial3D:
	## Pale peeling paint over rusted corrugation. Tint for container/hut colors.
	return _pbr("corrp_%s" % tint.to_html(), "CorrugatedSteel007B", tint, 0.4, 1.0, 0.0, Color(0.5, 0.55, 0.55))

static func container(tint: Color) -> StandardMaterial3D:
	## Shipping-container skin: strongly tinted corrugation, salt-faded.
	return _pbr("cont_%s" % tint.to_html(), "CorrugatedSteel005", tint, 0.35, 1.0, 0.1, tint.darkened(0.2))

static func teal_paint() -> StandardMaterial3D:
	## Peeling teal over rust — Bloom palette made metal. Doors, trim, accents.
	return _pbr("teal", "PaintedMetal006", Color.WHITE, 0.3, 1.0, 0.0, Color(0.25, 0.55, 0.48))

static func red_paint() -> StandardMaterial3D:
	## Scratched red — valves, fire points, life-ring brackets.
	return _pbr("red", "PaintedMetal004", Color.WHITE, 0.4, 1.0, 0.0, Color(0.7, 0.15, 0.1))

static func hazard_stripe() -> StandardMaterial3D:
	## Rusted yellow/black chevrons — crane bases, deck edges, watch-your-step.
	return _pbr("hazard", "PaintedMetal016", Color.WHITE, 0.45, 1.0, 0.0, Color(0.75, 0.65, 0.15))

static func sphl_orange() -> StandardMaterial3D:
	## Rescue-orange over scratched paint: the pod that kept its passenger.
	return _pbr("sphl", "PaintedMetal004", Color(1.0, 0.62, 0.3), 0.45, 1.0, 0.0, Color(0.88, 0.44, 0.12))

# ---------- mineral & organic ----------

static func concrete() -> StandardMaterial3D:
	return _pbr("concrete", "Concrete046", Color.WHITE, 0.25, 1.0, 0.0, Color(0.66, 0.65, 0.62))

static func concrete_floor() -> StandardMaterial3D:
	return _pbr("concrete_floor", "Concrete012", Color.WHITE, 0.3, 1.0, 0.0, Color(0.52, 0.52, 0.5))

static func wood() -> StandardMaterial3D:
	return _pbr("wood", "Planks037A", Color.WHITE, 0.4, 1.0, 0.0, Color(0.56, 0.43, 0.28))

static func weathered_wood() -> StandardMaterial3D:
	## Salt-grayed planks — driftwood, pallets, anything long in the spray zone.
	return _pbr("weathered", "Planks037A", Color(0.78, 0.75, 0.7), 0.5, 1.0, 0.0, Color(0.35, 0.28, 0.22))

static func canvas(tint: Color = Color.WHITE) -> StandardMaterial3D:
	## Woven canvas — tarps, lean-tos, bunk fabric.
	return _pbr("canvas_%s" % tint.to_html(), "Fabric062", tint, 0.7, 1.0, 0.0, Color(0.6, 0.58, 0.52))

static func rope_mat() -> StandardMaterial3D:
	return _pbr("rope", "Rope001", Color.WHITE, 1.2, 1.0, 0.0, Color(0.55, 0.48, 0.36), true)

# ---------- interiors (procedural fine-grain kept where it reads best) ----------

static func interior_wall() -> StandardMaterial3D:
	## Crew-space walls: smooth pale panel with faint aging.
	return _pbr("wall", "Concrete046", Color(0.92, 0.9, 0.85), 0.3, 1.0, 0.0, Color(0.8, 0.8, 0.74))

static func dirty_white_panel() -> StandardMaterial3D:
	## Once-white paneling, salt-grimed at the edges.
	return _pbr("panel", "Concrete046", Color(0.87, 0.85, 0.79), 0.35, 1.0, 0.0, Color(0.76, 0.75, 0.71))

static func kitchen_tile() -> StandardMaterial3D:
	return _fine("tile", Color(0.78, 0.8, 0.78), 0.35, 1313, 1.8, 0.1)

static func rubber_floor() -> StandardMaterial3D:
	return _fine("rubber", Color(0.17, 0.18, 0.19), 0.96, 1414, 1.2, 0.09)

static func lino_floor() -> StandardMaterial3D:
	## Warm worn linoleum for cabins and crew spaces.
	return _fine("lino", Color(0.5, 0.43, 0.35), 0.82, 1515, 0.8, 0.07)

static func medical_white() -> StandardMaterial3D:
	return _fine("medical", Color(0.84, 0.86, 0.85), 0.4, 1616, 1.0, 0.08)

# ---------- unlit / special ----------

static func flat(color: Color, emissive: bool = false, energy: float = 1.0) -> StandardMaterial3D:
	var key: String = "flat_%s_%s" % [color.to_html(), emissive]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	_cache[key] = m
	return m

static func glass(tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key: String = "glass_%s" % tint.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.15)
	m.roughness = 0.05
	m.metallic = 0.1
	_cache[key] = m
	return m

static func glowing(color: Color, intensity: float = 2.0) -> StandardMaterial3D:
	var key: String = "glow_%s_%f" % [color.to_html(), intensity]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = intensity
	m.roughness = 0.4
	_cache[key] = m
	return m

# ---------- procedural fallbacks (no texture library present) ----------

static func _noise_tex(seed_val: int, frequency: float, floor_val: float = 0.7, octaves: int = 4) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 256
	tex.height = 256
	# Remap noise into a bright band so multiplied layers weather without crushing albedo.
	var g := Gradient.new()
	g.set_color(0, Color(floor_val, floor_val, floor_val))
	g.set_color(1, Color.WHITE)
	tex.color_ramp = g
	return tex

static func _surface(key: String, base: Color, _tint: Color, roughness: float,
		noise_seed: int, noise_freq: float, metallic: float = 0.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.albedo_texture = _noise_tex(noise_seed, noise_freq, 0.72)
	# Second noise layer multiplies mild grime for a weathered look.
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = _noise_tex(noise_seed + 7, noise_freq * 2.3, 0.82)
	m.roughness = roughness
	m.roughness_texture = _noise_tex(noise_seed + 13, noise_freq * 1.7, 0.5)
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	m.uv2_triplanar = true
	m.uv2_scale = Vector3(0.6, 0.6, 0.6)
	_cache[key] = m
	return m

## Bespoke fine-grain builder: the shared _surface blotch scale reads as mud on
## large planes. keys must be unique per material.
static func _fine(key: String, base: Color, roughness: float, seed_val: int,
		grain_freq: float, patch_freq: float, metallic: float = 0.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.albedo_texture = _noise_tex(seed_val, grain_freq, 0.9, 5)          # tight, low-contrast grain
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = _noise_tex(seed_val + 7, patch_freq, 0.88, 3)      # broad, faint patching
	m.roughness = roughness
	m.roughness_texture = _noise_tex(seed_val + 13, grain_freq * 1.6, 0.55)
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.0, 1.0, 1.0)
	m.uv2_triplanar = true
	m.uv2_scale = Vector3(0.18, 0.18, 0.18)
	_cache[key] = m
	return m
