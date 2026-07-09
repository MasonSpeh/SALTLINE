shader_type spatial;
// North Atlantic swell, v2: four directional waves with domain-warped phases so
// crests never line up in rows, hash-noise foam breakup (no grid), noise-varied
// roughness to kill uniform glare. `vertex_waves` off = flat far plane.
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.1, 0.26, 0.3, 1.0);
uniform vec4 deep_color : source_color = vec4(0.012, 0.045, 0.075, 1.0);
uniform vec4 foam_color : source_color = vec4(0.82, 0.87, 0.88, 1.0);
uniform bool vertex_waves = true;

// dir.xy, amplitude, wavelength — wider, bigger, taller than v1.
const vec2 D1 = vec2(1.0, 0.32);
const vec2 D2 = vec2(-0.62, 1.0);
const vec2 D3 = vec2(0.41, -1.0);
const vec2 D4 = vec2(-0.9, -0.44);
const float A1 = 0.5;
const float A2 = 0.25;
const float A3 = 0.12;
const float A4 = 0.3;
const float L1 = 64.0;
const float L2 = 24.0;
const float L3 = 10.0;
const float L4 = 110.0;   // the long ocean swell underneath everything

varying vec3 world_pos;

// -- value noise (hash-based): the anti-grid ingredient --------------------
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x),
			mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.3 + 17.0) * 0.3 + vnoise(p * 5.1 + 47.0) * 0.15;
}

// Domain warp: bends every wave's phase field so no two crests repeat alike.
vec2 warp(vec2 p, float t) {
	return p + 4.0 * vec2(sin(p.y * 0.021 + t * 0.06), sin(p.x * 0.017 - t * 0.05));
}

float wphase(vec2 p, vec2 dir, float wavelength, float speed, float t) {
	return dot(normalize(dir), p) * (6.28318 / wavelength) + t * speed;
}

float wave_height(vec2 raw_p, float t) {
	vec2 p = warp(raw_p, t);
	return A1 * sin(wphase(p, D1, L1, 0.9, t))
		+ A2 * sin(wphase(p, D2, L2, 1.4, t))
		+ A3 * sin(wphase(p, D3, L3, 2.1, t))
		+ A4 * sin(wphase(p, D4, L4, 0.55, t));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	if (vertex_waves) {
		vec2 p = warp(world_pos.xz, t);
		float p1 = wphase(p, D1, L1, 0.9, t);
		float p2 = wphase(p, D2, L2, 1.4, t);
		float p4 = wphase(p, D4, L4, 0.55, t);
		VERTEX.y += wave_height(world_pos.xz, t);
		// Analytic slope for the three large waves; the smallest lives in ripples.
		vec2 n1 = normalize(D1) * A1 * (6.28318 / L1) * cos(p1);
		vec2 n2 = normalize(D2) * A2 * (6.28318 / L2) * cos(p2);
		vec2 n4 = normalize(D4) * A4 * (6.28318 / L4) * cos(p4);
		vec2 slope = n1 + n2 + n4;
		NORMAL = normalize(vec3(-slope.x, 1.0, -slope.y));
	}
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float h_norm = wave_height(p, t) / (A1 + A2 + A3 + A4);

	// Fine ripples: two scrolling irregular layers + a noise layer.
	vec2 r1 = vec2(sin(p.x * 1.7 + t * 1.9 + sin(p.y * 1.3 + t)),
			cos(p.y * 1.9 - t * 1.6 + sin(p.x * 1.1)));
	vec2 r2 = vec2(sin(p.x * 4.3 - t * 2.6 + sin(p.y * 2.9)), cos(p.y * 3.7 + t * 2.2 + sin(p.x * 3.1)));
	float nrip = fbm(p * 0.6 + vec2(t * 0.4, -t * 0.3)) - 0.5;
	vec3 ripple = normalize(vec3((r1 + r2 * 0.5).x * 0.07 + nrip * 0.12, 1.0,
			(r1 + r2 * 0.5).y * 0.07 - nrip * 0.1));
	NORMAL_MAP = ripple * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 5.0);
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, clamp(h_norm * 0.5 + 0.35, 0.0, 1.0));
	base = mix(base, shallow_color.rgb * 1.25, fresnel * 0.6);

	// Foam: tallest crests AND noise-gated, so whitecaps scatter instead of tiling.
	float gate = fbm(p * 0.14 + vec2(t * 0.12, t * 0.07));
	float crest = smoothstep(0.55, 0.9, h_norm) * smoothstep(0.45, 0.75, gate);
	float streaks = smoothstep(0.72, 0.95, fbm(p * 0.45 - vec2(t * 0.2, 0.0))) * 0.25;
	base = mix(base, foam_color.rgb, clamp(crest * 0.85 + streaks, 0.0, 1.0));

	ALBEDO = base;
	// Noise-varied roughness: broad soft sheen, no uniform mirror glare.
	ROUGHNESS = mix(0.1, 0.38, fbm(p * 0.2 + t * 0.05)) + crest * 0.3;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
