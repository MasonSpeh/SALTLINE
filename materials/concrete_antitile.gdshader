shader_type spatial;
// Anti-tiling world-triplanar concrete — the tower shell's answer to "the pattern
// repeats every 20 m", after two texture options were rejected (Concrete046: measured
// flat, see mat_lib.gd; the s42 rescale+noise layer: rejected on sight). The repeat is
// the TEXTURE'S OWN period showing, so the fix is structural, not another map:
//
//   1. Per-tile stochastic variation. The world-space UV lattice is cut into cells one
//      texture repeat square; each cell turns the projection by a hashed multiple of
//      90 deg and slides it by a hashed fraction. A quarter turn about any lattice point
//      maps a square tiling onto itself, so the interior of every cell stays seamless —
//      and rotate+offset are ISOMETRIES, so texture()'s screen-space derivatives keep
//      their magnitude across a border and the mip level cannot step there (the reason
//      the variation is never a per-cell SCALE). Two identical-looking cells now need a
//      hash collision in both turn and offset, not just adjacency.
//   2. A macro layer: the same albedo resampled at 1/8 frequency (one tile per ~36 m at
//      the shipped 0.22 repeats/m) multiplied in at low strength, so the metre-scale
//      pattern is modulated by a field with no visible period of its own.
//
// SAMPLING COST, counted: every current consumer is an axis-aligned CSG box, so exactly
// one projection plane survives the 0.02 weight cut and a fragment costs
//   2 albedo + 2 normal + 1 roughness + 1 macro = 6 taps.
// The StandardMaterial3D build this replaces pays 12 (BaseMaterial3D's triplanar helper
// samples ALL THREE planes unconditionally for each of albedo/normal/roughness/detail).
// Worst case here is a genuinely curved consumer blending three planes: 5x3+1 = 16.
//
// THE 2-TAP BORDER COMPROMISE: inside the blend band each fragment mixes its own cell's
// tap with the neighbour across the DOMINANT border axis, which is the only one-helper
// scheme where both sides of a border meet at the same 50/50 mix. Where four cells meet
// the dominant axis flips mid-band, so a residual seam segment ~0.18 tile long survives
// near each corner; killing it needs a third tap (+50% cost) and this GPU budget says no.
//
// gl_compatibility constraints respected: texture() with computed UVs only — no
// texelFetch, no textureGrad, no screen/depth textures. The per-plane `if` is uniform
// across every fragment of a flat face (the only geometry this ships on), so the
// implicit-derivative rule inside non-uniform flow is not exercised in practice.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.22;        // repeats per world metre — same meaning as uv1_scale
uniform float blend_sharpness = 4.0;  // triplanar weight power; irrelevant on box faces
uniform float normal_strength = 1.0;
uniform float rough_mult = 1.0;
uniform float macro_scale = 0.125;    // macro layer frequency as a fraction of the base tile
uniform float macro_strength = 0.18;  // multiply-blend weight of the macro layer
// The albedo map's own linear mean (measured off Concrete012_1K-JPG_Color.jpg:
// 0.249/0.216/0.164). Dividing the macro sample by it centres the multiply on 1.0, so
// the layer modulates tone without shifting the tint-solved mean the walls ship at.
uniform vec3 macro_mean = vec3(0.249, 0.216, 0.164);

// The multiply band is clamped so the macro layer can never push the wall outside its
// shipped tone envelope: floor 0.86 is the 14% darkening the s42 noise layer already
// proved unobtrusive, and ceiling 1.11 keeps the map's tinted p99 (0.895 linear, from
// the concrete() tint solve in mat_lib.gd) at or under 1.0 — nothing clips to white.
const vec3 MACRO_FLOOR = vec3(0.86);
const vec3 MACRO_CEIL = vec3(1.11);
const float BORDER_START = 0.32;      // blend band runs 0.32..0.5 of a cell — ~0.8 m at 4.55 m tiles

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Same hash idiom as caustics.gdshader / seabed_rock.gdshader.
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 rot90(vec2 p, int k) {
	if (k == 1) { return vec2(p.y, -p.x); }
	if (k == 2) { return -p; }
	if (k == 3) { return vec2(-p.y, p.x); }
	return p;
}

// A cell's transform: which quarter turn, and what fractional slide.
void cell_xform(vec2 cell, out int k, out vec2 off) {
	float h = hash(cell + vec2(17.13, 51.7));
	k = int(floor(h * 4.0)) % 4;   // % guards the h == 1.0 edge
	off = vec2(hash(cell + vec2(3.7, 29.3)), hash(cell + vec2(9.1, 77.9)));
}

// Everything one projection plane contributes: stochastic 2-tap albedo, the matching
// 2-tap normal — each tap's tangent vector un-turned by its own cell's k so the relief
// stays glued to the aggregate it was rotated with — and 1-tap roughness (tap A only:
// the map is low-contrast and a roughness pop inside the albedo blend band does not
// read; the tap saved is 17% of the fragment).
void plane_sample(vec2 uv, out vec3 alb, out vec3 nrm, out float rgh) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	vec2 d = f - 0.5;
	vec2 ad = abs(d);
	vec2 nshift = (ad.x > ad.y)
		? vec2(d.x >= 0.0 ? 1.0 : -1.0, 0.0)
		: vec2(0.0, d.y >= 0.0 ? 1.0 : -1.0);
	int ka;
	vec2 offa;
	cell_xform(cell, ka, offa);
	int kb;
	vec2 offb;
	cell_xform(cell + nshift, kb, offb);
	vec2 uva = rot90(uv, ka) + offa;
	vec2 uvb = rot90(uv, kb) + offb;
	float wb = smoothstep(BORDER_START, 0.5, max(ad.x, ad.y)) * 0.5;
	alb = mix(texture(albedo_tex, uva).rgb, texture(albedo_tex, uvb).rgb, wb);
	// Decode xy ONLY and rebuild z. The map imports with compress/normal_map=1, i.e.
	// two-channel RGTC in VRAM — the sampled .b is not the z component, and the engine's
	// own NORMAL_MAP path reconstructs z from xy for exactly this reason. Rotation
	// preserves |xy|, so rebuilding once after the mix is exact.
	vec2 nxa = texture(normal_tex, uva).rg * 2.0 - 1.0;
	vec2 nxb = texture(normal_tex, uvb).rg * 2.0 - 1.0;
	nxa = rot90(nxa, (4 - ka) % 4);
	nxb = rot90(nxb, (4 - kb) % 4);
	vec2 nxy = mix(nxa, nxb, wb);
	nrm = vec3(nxy, sqrt(max(0.0, 1.0 - dot(nxy, nxy))));
	rgh = texture(rough_tex, uva).r;
}

void fragment() {
	vec3 n = normalize(v_wn);
	vec3 bw = pow(abs(n), vec3(blend_sharpness));
	bw /= (bw.x + bw.y + bw.z);
	// The projection triple BaseMaterial3D generates for world triplanar, including its
	// y flip and the X plane's mirrored u — so at turn k=0 this shader reproduces the old
	// material's exact mapping, and the A/B compares the variation, not a reorientation.
	vec3 p = v_world * uv_scale;
	p.y = -p.y;
	vec2 uvx = vec2(-p.z, p.y);
	vec2 uvy = p.xz;
	vec2 uvz = p.xy;

	float sx = n.x >= 0.0 ? 1.0 : -1.0;   // sign(): 0 at 0 would zero a normal
	float sy = n.y >= 0.0 ? 1.0 : -1.0;
	float sz = n.z >= 0.0 ? 1.0 : -1.0;
	vec3 alb = vec3(0.0);
	vec3 wn = vec3(0.0);
	float rgh = 0.0;
	float wsum = 0.0;
	// On a box face exactly one weight is 1 and the other two branches never run.
	if (bw.x > 0.02) {
		vec3 a;
		vec3 t;
		float r;
		plane_sample(uvx, a, t, r);
		alb += a * bw.x;
		wn += vec3(sx * t.z, -t.y, -t.x) * bw.x;   // uvx: u = -z, v = -y
		rgh += r * bw.x;
		wsum += bw.x;
	}
	if (bw.y > 0.02) {
		vec3 a;
		vec3 t;
		float r;
		plane_sample(uvy, a, t, r);
		alb += a * bw.y;
		wn += vec3(t.x, sy * t.z, t.y) * bw.y;     // uvy: u = +x, v = +z
		rgh += r * bw.y;
		wsum += bw.y;
	}
	if (bw.z > 0.02) {
		vec3 a;
		vec3 t;
		float r;
		plane_sample(uvz, a, t, r);
		alb += a * bw.z;
		wn += vec3(t.x, -t.y, sz * t.z) * bw.z;    // uvz: u = +x, v = -y
		rgh += r * bw.z;
		wsum += bw.z;
	}
	alb /= wsum;   // renormalise after the 0.02 cut
	rgh /= wsum;

	// MACRO layer, dominant plane only: at 1/8 frequency a plane switch lands exactly on
	// a 90-degree geometric edge, where a few-percent tone step cannot read.
	vec2 uvm = (bw.x >= max(bw.y, bw.z)) ? uvx : ((bw.y >= bw.z) ? uvy : uvz);
	vec3 macro_rgb = texture(albedo_tex, uvm * macro_scale + vec2(0.377, 0.113)).rgb;
	vec3 mul = clamp(mix(vec3(1.0), macro_rgb / macro_mean, macro_strength),
		MACRO_FLOOR, MACRO_CEIL);

	ALBEDO = tint.rgb * alb * mul;
	ROUGHNESS = clamp(rgh * rough_mult, 0.0, 1.0);
	METALLIC = 0.0;
	vec3 wnn = normalize(mix(n, normalize(wn), normal_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(wnn, 0.0)).xyz);
}
