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

const DECAL_ROOT := "res://assets/textures/decals/"

static func _decal_tex(folder: String, map: String) -> Texture2D:
	var path := "%s%s/%s_1K-PNG_%s.png" % [DECAL_ROOT, folder, folder, map]
	return load(path) if ResourceLoader.exists(path) else null

## Zero-mask grime / water / soot overlay for a "sticker" quad laid ~1.5cm off a
## surface. The ambientCG Leaking Color map is near-white with dark drip streaks;
## MUL blend makes white a no-op and dark streaks darken the wall behind — no alpha
## channel needed. Decal projectors don't exist under gl_compatibility, so this is
## the replacement. Falls back to a flat grey wash if the texture is missing.
static func grime_mul(folder: String) -> StandardMaterial3D:
	var key := "grime_%s" % folder
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var tex := _decal_tex(folder, "Color")
	if tex:
		m.albedo_texture = tex
	else:
		m.albedo_color = Color(0.4, 0.4, 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_cache[key] = m
	return m

## Tintable alpha-cutout stain: synthesizes opacity = (1 - luminance) from a Leaking
## Color map (dark streak -> opaque, white field -> transparent) so a coloured rust
## bleed is possible (grey water, orange rust). Runs once at 256px, then cached.
static func stain_material(folder: String, tint: Color = Color(0.5, 0.3, 0.18),
		strength: float = 0.85) -> StandardMaterial3D:
	var key := "stain_%s_%s_%.2f" % [folder, tint.to_html(false), strength]
	if _cache.has(key):
		return _cache[key]
	var src := _decal_tex(folder, "Color")
	if src == null:
		return grime_mul(folder)
	var img: Image = src.get_image()
	if img == null:   # VRAM-only compressed texture on some drivers — bail safely
		return grime_mul(folder)
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	for yy in img.get_height():
		for xx in img.get_width():
			var lum: float = img.get_pixel(xx, yy).get_luminance()
			img.set_pixel(xx, yy, Color(tint.r, tint.g, tint.b, (1.0 - lum) * strength))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.roughness = 1.0
	_cache[key] = m
	return m

## True alpha-cutout decal (RoadLines markings, AsphaltDamage scuffs) — paint on a
## transparent background. ambientCG ships a separate Opacity map; merge it into the
## albedo alpha once (cached), then ALPHA_SCISSOR for crisp depth-writing edges.
static func decal_cutout(folder: String, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "decalc_%s_%s" % [folder, tint.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var col := _decal_tex(folder, "Color")
	if col == null:
		return grime_mul(folder)
	var m := StandardMaterial3D.new()
	var op := _decal_tex(folder, "Opacity")
	if op and col.get_image() != null and op.get_image() != null:
		var ci: Image = col.get_image(); ci.resize(512, 512); ci.convert(Image.FORMAT_RGBA8)
		var oi: Image = op.get_image(); oi.resize(512, 512); oi.convert(Image.FORMAT_RGBA8)
		for yy in ci.get_height():
			for xx in ci.get_width():
				var c: Color = ci.get_pixel(xx, yy)
				ci.set_pixel(xx, yy, Color(c.r, c.g, c.b, oi.get_pixel(xx, yy).r))
		m.albedo_texture = ImageTexture.create_from_image(ci)
	else:
		m.albedo_texture = col   # alpha already in the Color map
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.roughness = 0.9
	_cache[key] = m
	return m

## Texture-backed weathered surface. tint multiplies albedo (keep it bright —
## heavy tints crush the maps). Above 1.0 is legal and deliberate where a dark map has to
## hold a pale surface's tone: albedo_color is a `source_color` uniform, so Godot runs it
## through srgb_to_linear, which extrapolates past 1.0 monotonically. Solve the tint against
## the map's LINEAR mean and check the map's 99.9th percentile times that tint stays under
## 1.0, or the highlights flatten into white. See concrete().
##
## uv_scale: texture repeats per world meter (0.45 = one tile per 2.22 m).
##
## local=true switches to object-space triplanar for props that MOVE — a world-space
## projection on a mesh whose transform changes slides the texture across it every frame.
## "Moving" means the node's transform changes at run time. It does NOT mean welded:
## rig_batcher.gd bakes its chunks in world space under an identity holder (main.gd:48
## adds RigBuilder with no transform), so a welded vertex samples the same world position
## it did loose. Verified against the shipping engine too — Godot 4.7's BaseMaterial3D
## emits `uv1_triplanar_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * uv1_scale`, with no
## camera term, and the gl_compatibility scene shader's model_matrix carries no
## camera-relative offset outside USE_DOUBLE_PRECISION builds. None of these surfaces can
## swim with the player; if something on a wall appears to move, it is not this.
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
	##
	## uv scale 0.28 stretched one tile of PaintedMetal013 across 3.6 m, so its peel and
	## staining became metre-scale blotches: on anything small the material read as polished
	## marble or granite rather than paint, which is what made the crane operator's cab
	## photograph as a pale stone cube bolted to the deck. 0.65 repeats every 1.5 m, which is
	## about the scale real peeling paint works at and gives a 2 m cab panel real texture.
	return _pbr("paint", "PaintedMetal013", Color.WHITE, 0.65, 1.0, 0.0, Color(0.6, 0.66, 0.63))

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
	## International-orange GRP over brushed metal wear: the pod that kept its
	## passenger. (Boosted tint over a gray base — the red paint set reads fire-red.)
	return _pbr("sphl", "Metal032", Color(1.5, 0.55, 0.12), 0.45, 1.0, 0.0, Color(0.88, 0.44, 0.12))

static func sphl_grey() -> StandardMaterial3D:
	## Weathered grey survival-craft hull — salt-scoured painted steel, the honest
	## look of a lifeboat that has ridden a lot of sea.
	return _pbr("sphl_grey", "PaintedMetal013", Color(0.62, 0.66, 0.7), 0.32, 1.0, 0.05, Color(0.5, 0.54, 0.58))

## THE HI-VIS BAND, AND WHY IT GLOWED.
##
## Owner report: "remove red lines" — bright neon-red strips seen from inside the pod in
## the cold open. It is the only saturated geometry in that room: the two `_sphl_bench`
## nosings wear it, and so does the hull band the player walks past on the way out.
##
## PaintedMetal004 is the RED paint set: it is what `red_paint()` above is built from, and
## its colour map measures linear (0.932, 0.072, 0.071) mean with a 99.9th percentile of
## (1.000, 0.666, 0.673). Tinting THAT by (1.3, 0.6, 0.2) to reach "orange" multiplies an
## already-saturated red by 1.3, so peak albedo was (1.30, 0.40, 0.13). An albedo over 1.0
## returns more light than falls on it; the pod's red emergency lamp (rig_builder
## `_build_sphl`, Color(0.9, 0.15, 0.1) at energy 1.6, 5 m range) sits two metres from the
## nosings, so the 60 x 40 mm strips clipped to pure red and bloomed. Nothing else in that
## room is saturated, which is why they read as neon piping stuck to grey walls.
##
## `sphl_orange()` above already records the same finding one line at a time ("the red
## paint set reads fire-red") and solves it by boosting a NEUTRAL base. That cannot be done
## on a red base at any tint: the green a hi-vis orange needs is not in the map to scale.
## So the base moves to PaintedMetal013 — the grey paint `sphl_grey()` is already made of,
## which keeps hull and band in one paint family — and the tint is SOLVED, not eyeballed:
## base linear mean (0.4292, 0.3983, 0.3861) x this tint lands on (0.440, 0.165, 0.028), a
## real international-orange a shade brighter than sphl_orange's (0.313, 0.140, 0.036), and
## the map's 99.9th percentile x this tint peaks at (0.964, 0.389, 0.068) — under 1.0 on
## every channel, so no pixel of it can bloom under any light on the rig.
##
## uv 0.32 is `sphl_grey()`'s, not the 0.4 that came off the old base. Both materials are now
## the same map under world-space triplanar, and the band is painted straight onto the hull:
## at matching scale the grain runs continuously across the joint, and at 0.4 the 0.5 m band
## would have carried a fifth of a tile against the hull's third of one.
static func sphl_hi_vis() -> StandardMaterial3D:
	## The one bright band a grey hull still needs by law — retro-orange accent.
	return _pbr("sphl_hivis", "PaintedMetal013", Color(1.025, 0.414, 0.072), 0.32, 1.0, 0.0, Color(0.69, 0.44, 0.20))

# ---------- mineral & organic ----------

## CONCRETE046 IS A BLANK CARD, AND THIS IS THE MATERIAL THE WALLS ARE MADE OF.
## `rig_superstructure.gd:774/799/1017/1144` builds the shaft walls and the accommodation
## block's exterior and room walls out of this, and `rig_builder.gd:696` builds all four
## 6 x 109 m caisson legs out of it — the largest surfaces in the game. Measured over the
## whole 23-set library in res://assets/textures: Concrete046 has an albedo RMS contrast of
## 0.0408 (second flattest of 23; only Metal032 and ContainerSide are lower) and a normal
## map whose mean slope is 0.0158 — 0.9 degrees of relief, i.e. planar. It is a photograph
## of a smooth painted panel, not of concrete.
##
## That is not a tiling or a UV problem and no triplanar work can touch it: the wall in
## /tmp/s34_final/walk_turn.png measures RMS contrast 0.0406 against the source map's
## 0.0408, so the material is reproducing a blank map exactly, to three decimals. The deck
## treadplate in the same frame measures 0.1673.
##
## Concrete012 is already in the project (concrete_floor, tide_band) so nothing new imports.
## Against Concrete046 it is 1.76x the albedo contrast in LINEAR light (0.0869 -> 0.1531)
## and 12.6x the normal relief (0.0158 -> 0.1997 mean slope, 0.9 deg -> 11.5 deg) — under a
## low sun the relief is the bigger half of the win. The tint is NOT art direction: it is
## solved so the linear mean lands on Concrete046's exact shipped tone (0.6093, 0.6165,
## 0.4874), because the complaint is that the wall has no surface, not that it is the wrong
## colour. Above 1.0 for the same reason sphl_orange is; the map's 99.9th percentile times
## this tint is (0.837, 0.895, 0.818) linear, so nothing clips into flat white.
##
## 0.25 put ONE tile across 4.00 m. Same defect painted_steel was fixed for below, never
## applied here: a 3.2 m interior wall carried less than one tile, so what you saw was a
## slice of a single photograph. 0.45 is 2.22 m/tile — form-panel scale, 2.7 tiles across a
## 6 m caisson face, 461 texel/m.
static func concrete() -> StandardMaterial3D:
	return _pbr("concrete", "Concrete012", Color(1.477, 1.577, 1.607), 0.45, 1.0, 0.0,
		Color(0.66, 0.65, 0.62))

## THE TOWER'S CONCRETE — bigger aggregate, and it stops repeating.
##
## Owner: "try a different, larger scale texture (any way to have pattern not visually
## repeat every 20 m?) for the main concrete in the tower. This one isnt my favorite, im
## curious if we have any other options."
##
## THE HONEST ANSWER ON "OTHER OPTIONS": there are exactly two concrete sets in the repo
## and the other one is worse. Concrete046 was measured and abandoned (see the note above
## `concrete()`): albedo RMS 0.0408 and a normal map whose mean slope is 0.9 degrees — it
## is a photograph of a painted panel, not cast concrete, and at tower scale it reads as
## flat grey card. A genuinely different look needs a new texture import, which is an
## asset decision rather than a code one. So this does the two things that ARE available
## and that between them change the character more than a swap would:
##
##  1. SCALE. uv_scale is repeats per world metre, so SMALLER means BIGGER features:
##     0.45 (a tile every 2.22 m) -> 0.22 (every 4.55 m). The aggregate and form-board
##     marks roughly double in size, which is what "larger scale" asks for and also what
##     a 30 m tower shell wants — at 2.2 m the pattern was reading as noise.
##
##  2. THE REPEAT. Doubling the tile would ordinarily make tiling MORE obvious, so a
##     second, very low frequency layer is multiplied over it: a fractal-noise detail map
##     on the uv2 triplanar set at 0.055 repeats/m — one cycle every ~18 m, close to the
##     20 m beat the owner is seeing, and mutually irrational with the 4.55 m base tile so
##     the two never come back into step. It only modulates brightness (BLEND_MODE_MUL,
##     floor 0.86, so at most a 14% darkening), which is enough to break the eye's lock on
##     a repeating rectangle without looking like stains.
##
## This is the idiom `_surface`/`_fine` already use for the procedural materials, applied
## to a photo base — and it stays a StandardMaterial3D, which matters: both batchers
## reject anything else outright (mesh_batcher "shader material" -> _no), so a
## ShaderMaterial here would drop the tower shell and the caisson legs out of batching.
##
## Registered under its OWN cache key, so `concrete()` — which is also the four 109 m
## legs, the ops room and a dozen other surfaces — is untouched and this can be judged on
## the tower alone before spreading.
##
## THE STRUCTURAL ROUTE (owner rejected both texture options — the complaint is the
## repeat itself): materials/concrete_antitile.gdshader keeps this key's maps, tint and
## 0.22 base tile but hashes the world-space tile lattice — every 4.55 m cell gets a
## quarter-turn + fractional slide of its own, blended across cell borders, plus the same
## albedo multiplied back in at 1/8 frequency (one macro cycle per ~36 m, strength 0.18).
## Two cells can now only match by colliding in both turn and offset. Costs 6 texture
## taps/fragment on a flat face against the StandardMaterial3D build's unconditional 12
## (BaseMaterial3D samples all three triplanar planes for every map); the tap arithmetic
## is in the shader header.
##
## The batching warning above is measured to be moot FOR THIS KEY: every consumer is
## rig_builder._build_stair_tower (rig_builder.gd:918) and every piece it builds is
## COLLIDING CSG — which rig_batcher already refuses ("keep colliding structure as-is",
## rig_batcher.gd:230) and mesh_batcher never visits (it walks MeshInstance3D only). The
## shell was never batched, so the ShaderMaterial costs zero draws. The warning stands
## for anyone who hangs this material on a non-colliding dressing mesh — that WOULD fall
## out of the weld.
const TOWER_ANTITILE: bool = true  ## false = the s42 StandardMaterial3D build, for A/B on film

static func concrete_tower() -> Material:
	if _cache.has("concrete_tower"):
		return _cache["concrete_tower"]
	var albedo := _tex("Concrete012", "Color")
	if TOWER_ANTITILE and albedo != null:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://materials/concrete_antitile.gdshader")
		sm.set_shader_parameter("albedo_tex", albedo)
		sm.set_shader_parameter("normal_tex", _tex("Concrete012", "NormalGL"))
		sm.set_shader_parameter("rough_tex", _tex("Concrete012", "Roughness"))
		# Same tint solve and base tile as the s42 build — the A/B compares variation,
		# not tone or scale. macro_mean is the map's own measured linear mean (it centres
		# the macro multiply on 1.0; derivation in the shader).
		sm.set_shader_parameter("tint", Color(1.477, 1.577, 1.607))
		sm.set_shader_parameter("uv_scale", 0.22)
		sm.set_shader_parameter("macro_mean", Vector3(0.249, 0.216, 0.164))
		_cache["concrete_tower"] = sm
		return sm
	# The s42 build: _pbr under a throwaway key so it inherits every map and the world
	# triplanar setup, then re-scaled and given the anti-tiling layer, then re-keyed.
	var m: StandardMaterial3D = _pbr("concrete_tower_base", "Concrete012",
		Color(1.477, 1.577, 1.607), 0.22, 1.0, 0.0, Color(0.66, 0.65, 0.62)).duplicate()
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = _noise_tex(20404, 0.9, 0.86, 3)
	m.uv2_triplanar = true
	m.uv2_world_triplanar = true
	m.uv2_scale = Vector3(0.055, 0.055, 0.055)
	_cache["concrete_tower"] = m
	return m

static func concrete_floor() -> StandardMaterial3D:
	return _pbr("concrete_floor", "Concrete012", Color.WHITE, 0.3, 1.0, 0.0, Color(0.52, 0.52, 0.5))

static func tide_band() -> StandardMaterial3D:
	## Algae-and-weed stain band where the swell breathes on the concrete.
	return _pbr("tide_band", "Concrete012", Color(0.42, 0.5, 0.4), 0.45, 1.0, 0.0, Color(0.3, 0.36, 0.3))

static func wood() -> StandardMaterial3D:
	return _pbr("wood", "Planks037A", Color.WHITE, 0.4, 1.0, 0.0, Color(0.56, 0.43, 0.28))

static func weathered_wood() -> StandardMaterial3D:
	## Salt-grayed planks — driftwood, pallets, anything long in the spray zone.
	return _pbr("weathered", "Planks037A", Color(0.78, 0.75, 0.7), 0.5, 1.0, 0.0, Color(0.35, 0.28, 0.22))

static func canvas(tint: Color = Color.WHITE) -> StandardMaterial3D:
	## Woven canvas — tarps, lean-tos, bunk fabric. Tight uv so the weave reads
	## as texture, not as a picnic-check pattern.
	return _pbr("canvas_%s" % tint.to_html(), "Fabric062", tint, 1.5, 1.0, 0.0, Color(0.6, 0.58, 0.52))

static func rope_mat() -> StandardMaterial3D:
	return _pbr("rope", "Rope001", Color.WHITE, 1.2, 1.0, 0.0, Color(0.55, 0.48, 0.36), true)

# ---------- interiors (procedural fine-grain kept where it reads best) ----------

## The other two Concrete046 surfaces, same defect and same fix as concrete() above — see
## the measurement there. Both tints are solved to hold their SHIPPED linear tone (0.5043,
## 0.4854, 0.3373 and 0.4444, 0.4266, 0.2861), so the crew spaces stay as pale as they are
## today and only gain a surface. Peak x tint is (0.692, 0.705, 0.566) and (0.610, 0.620,
## 0.480) linear — well clear of clipping.
##
## 0.55 = 1.82 m/tile: a 3.2 m interior wall now carries 1.8 tiles instead of 0.94. NOT
## fully solved for dirty_white_panel, which is also hung on small props (the 0.70 m fridge
## carcass at interior_props.gd:1398, a 0.55 m dish) — those still show under half a tile,
## and tightening the tile far enough to fix a fridge would visibly repeat the map on a
## crew divider. Split the prop use onto its own key if it reads wrong up close.
static func interior_wall() -> StandardMaterial3D:
	## Crew-space walls: pale panel with faint aging.
	return _pbr("wall", "Concrete012", Color(1.361, 1.423, 1.371), 0.55, 1.0, 0.0,
		Color(0.8, 0.8, 0.74))

static func dirty_white_panel() -> StandardMaterial3D:
	## Once-white paneling, salt-grimed at the edges.
	return _pbr("panel", "Concrete012", Color(1.288, 1.345, 1.276), 0.55, 1.0, 0.0,
		Color(0.76, 0.75, 0.71))

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
	# Energy MUST be in the cache key: without it, flat(c, true, 0.0) and flat(c, true, 2.2)
	# collided, so a light meant to be dark-until-powered could hand back the bright cached
	# copy (the glowing box the player saw before the breaker was thrown).
	var key: String = "flat_%s_%s_%.2f" % [color.to_html(), emissive, energy]
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
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # was set but never enabled -> rendered opaque
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.2)
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

## A soft round particle mote: billboarded, unshaded, alpha, with a RADIAL falloff so it
## reads as a suspended flake rather than a flat card.
##
## Marine snow / sediment / bubbles were untextured QuadMeshes, which render as hard
## axis-aligned SQUARES — from a metre away the water column looked like it was full of
## confetti. A radial gradient texture costs nothing (one 32 px texture shared by every
## emitter) and needs no shader, so it stays safe on the Compatibility renderer.
static func soft_mote(tint: Color, billboard: bool = true) -> StandardMaterial3D:
	var key := "soft_mote_%s_%s" % [tint.to_html(), billboard]
	if _cache.has(key):
		return _cache[key]
	var grad := Gradient.new()
	# The fade has to be COMPLETE well inside the quad, not at its corner. A linear ramp to
	# the quad edge leaves ~0.5 alpha at the halfway radius, and a marine-snow mote is only
	# a few pixels across on screen — the mip chain then averages that into a flat, uniform
	# patch that fills the whole quad, which is why the water column photographed as hard
	# opaque teal RECTANGLES rather than soft motes. Pull the alpha down fast and reach
	# zero at 0.5 of the fill radius, so the lit part of the sprite is a disc inside a
	# transparent border no filtering can smear back out to the edges.
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# No mip chain: mipmapping a small radial sprite is precisely what flattened it into a
	# uniform square at the distances these are actually seen from.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	else:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED   # flat-on-the-water sprites
	m.vertex_color_use_as_albedo = false
	_cache[key] = m
	return m
