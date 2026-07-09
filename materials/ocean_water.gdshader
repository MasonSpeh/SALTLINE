shader_type spatial;
// North Atlantic ocean: three summed directional waves displaced in vertex with
// analytic normals, fine scrolling ripples in fragment, fresnel deep/shallow mix,
// foam on crests. `vertex_waves` off = flat far plane (same look, no displacement).
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.1, 0.26, 0.3, 1.0);
uniform vec4 deep_color : source_color = vec4(0.012, 0.045, 0.075, 1.0);
uniform vec4 foam_color : source_color = vec4(0.82, 0.87, 0.88, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.06;
uniform bool vertex_waves = true;

// dir.xy, amplitude, wavelength
const vec2 D1 = vec2(1.0, 0.32);
const vec2 D2 = vec2(-0.62, 1.0);
const vec2 D3 = vec2(0.41, -1.0);
const float A1 = 0.42;
const float A2 = 0.2;
const float A3 = 0.09;
const float L1 = 42.0;
const float L2 = 17.0;
const float L3 = 8.0;

varying vec3 world_pos;

float wphase(vec2 p, vec2 dir, float wavelength, float speed, float t) {
	return dot(normalize(dir), p) * (6.28318 / wavelength) + t * speed;
}

float wave_height(vec2 p, float t) {
	return A1 * sin(wphase(p, D1, L1, 1.05, t))
		+ A2 * sin(wphase(p, D2, L2, 1.6, t))
		+ A3 * sin(wphase(p, D3, L3, 2.3, t));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	vec2 p = world_pos.xz;
	if (vertex_waves) {
		float p1 = wphase(p, D1, L1, 1.05, t);
		float p2 = wphase(p, D2, L2, 1.6, t);
		VERTEX.y += wave_height(p, t);
		// Analytic slope for the two large waves; small wave lives in fragment ripples.
		float k1 = 6.28318 / L1;
		float k2 = 6.28318 / L2;
		vec2 n1 = normalize(D1) * A1 * k1 * cos(p1);
		vec2 n2 = normalize(D2) * A2 * k2 * cos(p2);
		NORMAL = normalize(vec3(-(n1.x + n2.x), 1.0, -(n1.y + n2.y)));
	}
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	// Crest height evaluated per-fragment (correct on the flat far plane too).
	float h_norm = wave_height(p, t) / (A1 + A2 + A3);

	// Fine ripple normal perturbation, two scrolling irregular layers.
	vec2 r1 = vec2(sin(p.x * 1.7 + t * 1.9 + sin(p.y * 1.3 + t)),
			cos(p.y * 1.9 - t * 1.6 + sin(p.x * 1.1)));
	vec2 r2 = vec2(sin(p.x * 4.3 - t * 2.6 + sin(p.y * 2.9)), cos(p.y * 3.7 + t * 2.2 + sin(p.x * 3.1)));
	vec3 ripple = normalize(vec3((r1 + r2 * 0.5).x * 0.08, 1.0, (r1 + r2 * 0.5).y * 0.08));
	NORMAL_MAP = ripple * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 5.0);
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, clamp(h_norm * 0.5 + 0.35, 0.0, 1.0));
	base = mix(base, shallow_color.rgb * 1.25, fresnel * 0.6);

	// Foam only on the tallest, steepest crests — sparse and broken, never a grid.
	float breakup = clamp(0.35 + 0.45 * sin(p.x * 0.61 + p.y * 0.83 + t * 0.7) + 0.3 * r2.x, 0.0, 1.0);
	float crest = smoothstep(0.68, 0.92, h_norm) * breakup;
	base = mix(base, foam_color.rgb, crest * 0.8);

	ALBEDO = base;
	ROUGHNESS = mix(roughness_val, 0.4, crest);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
