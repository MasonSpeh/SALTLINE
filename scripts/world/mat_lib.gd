class_name MatLib extends RefCounted
## Procedural surface materials for the greybox pass: noise-textured rust, paint, and
## deck plate. Triplanar so CSG needs no UVs. Palette per canon: gray water / rust
## orange / Bloom teal-and-pearl. Cached — call the getters, never construct twice.

static var _cache: Dictionary = {}

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

static func _surface(key: String, base: Color, tint: Color, roughness: float,
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
	# Slight tint variation baked via emission-free albedo mix isn't available;
	# the multiplied detail noise carries the weathering. Tint reserved for future pass.
	_cache[key] = m
	return m

static func rust_steel() -> StandardMaterial3D:
	return _surface("rust", Color(0.52, 0.3, 0.17), Color(0.3, 0.15, 0.08), 0.92, 101, 0.06)

static func painted_steel() -> StandardMaterial3D:
	return _surface("paint", Color(0.6, 0.66, 0.63), Color(0.4, 0.45, 0.42), 0.7, 202, 0.05)

static func deck_plate() -> StandardMaterial3D:
	return _surface("deck", Color(0.4, 0.41, 0.44), Color(0.2, 0.2, 0.22), 0.85, 303, 0.12, 0.3)

static func interior_wall() -> StandardMaterial3D:
	return _surface("wall", Color(0.8, 0.8, 0.74), Color(0.6, 0.6, 0.55), 0.8, 404, 0.04)

static func dark_metal() -> StandardMaterial3D:
	return _surface("dark", Color(0.22, 0.23, 0.26), Color(0.1, 0.1, 0.12), 0.6, 505, 0.08, 0.6)

static func wood() -> StandardMaterial3D:
	return _surface("wood", Color(0.56, 0.43, 0.28), Color(0.35, 0.26, 0.16), 0.9, 606, 0.09)

static func sphl_orange() -> StandardMaterial3D:
	return _surface("sphl", Color(0.88, 0.44, 0.12), Color(0.6, 0.28, 0.07), 0.55, 707, 0.07)

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

static func rusty_metal() -> StandardMaterial3D:
	return _surface("rusty", Color(0.45, 0.25, 0.12), Color(0.25, 0.12, 0.05), 0.85, 102, 0.08)

static func weathered_wood() -> StandardMaterial3D:
	return _surface("weathered", Color(0.35, 0.28, 0.22), Color(0.2, 0.16, 0.12), 0.75, 607, 0.1)
