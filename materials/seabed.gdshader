shader_type spatial;
// Sea floor: procedural silt / sand with domain-warped megaripples and a faint
// scatter of Bloom flecks. Colour and ripple detail are world-space so a deformed
// grid mesh needs NO UVs and the texture never swims or stretches across the plane.
// Normal is perturbed in WORLD space then pushed to view space, so no tangents are
// needed either. gl_compatibility safe: no depth texture, no derivatives-of-samplers,
// no compute.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 sand_color : source_color = vec3(0.30, 0.31, 0.29);
uniform vec3 silt_color : source_color = vec3(0.15, 0.19, 0.20);
uniform vec3 scour_color : source_color = vec3(0.09, 0.12, 0.13);
uniform vec3 bloom_tint : source_color = vec3(0.16, 0.85, 0.78);
uniform float ripple_freq = 2.6;       // radians per world metre (~2.4 m crests)
uniform float ripple_strength = 0.55;  // normal bump amount
uniform float macro_scale = 0.03;      // silt / sand patch size
uniform float bloom_glow = 0.35;       // driven up at night by the host node

varying vec3 v_world;
varying vec3 v_wn;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return s;
}

// Wavy parallel sand ripples: a dominant band set plus a weaker cross set, both
// domain-warped so crests meander like real megaripples instead of ruling a grid.
float ripple_h(vec2 p) {
	vec2 d1 = normalize(vec2(1.0, 0.34));
	float warp = (fbm(p * 0.13) - 0.5) * 4.0;
	float r = sin(dot(p, d1) * ripple_freq + warp);
	vec2 d2 = normalize(vec2(-0.42, 1.0));
	r += 0.38 * sin(dot(p, d2) * ripple_freq * 1.7 + (fbm(p * 0.22) - 0.5) * 3.0);
	return r;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 wp = v_world.xz;

	// --- ripple normal (world space -> view space, no tangents) ---
	float e = 0.14;
	float h0 = ripple_h(wp);
	float hx = ripple_h(wp + vec2(e, 0.0));
	float hz = ripple_h(wp + vec2(0.0, e));
	vec3 bump = normalize(vec3(-(hx - h0) / e * ripple_strength, 1.0, -(hz - h0) / e * ripple_strength));
	vec3 wn = normalize(mix(normalize(v_wn), bump, 0.85));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// --- albedo: silt / sand patches, darker in scour hollows, ripple shading ---
	float macro = fbm(wp * macro_scale);
	vec3 base = mix(silt_color, sand_color, smoothstep(0.35, 0.72, macro));
	// deep, dark, current-scoured hollows read where the floor drops away
	float low = smoothstep(-19.5, -24.5, v_world.y);   // 1 near the bottom of scour pits
	base = mix(base, scour_color, low * 0.7);
	// crests catch the light, troughs hold shadow
	float rip = ripple_h(wp);
	base *= 0.80 + 0.20 * smoothstep(-1.0, 1.0, rip);
	// scattered grit / shell hash breaks any residual smoothness
	base *= 0.90 + 0.14 * hash(floor(wp * 6.0));

	ALBEDO = base;
	ROUGHNESS = 0.94;
	METALLIC = 0.0;

	// --- sparse Bloom flecks: bioluminescent life bedded in the silt ---
	vec2 cell = floor(wp * 2.5);
	float pick = hash(cell + 3.1);
	float fleck = smoothstep(0.988, 0.997, pick);
	EMISSION = bloom_tint * fleck * bloom_glow;
}
