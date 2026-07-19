shader_type spatial;
// God-rays / crepuscular light shafts descending from the surface. NOT volumetric
// fog (the Compatibility renderer has none) — these are additive crossed quads with a
// scrolling noise mask, brightest just under the surface and fading out with depth.
// Placed as static crossed slabs (an asterisk cross-section) so a shaft always shows
// a lit face from any angle without per-frame billboard math. gl_compatibility safe.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 shaft_color : source_color = vec3(0.30, 0.62, 0.62);
uniform float daylight = 1.0;
uniform float top_y = 0.0;                 // world surface height (set per frame)
uniform float reach = 13.0;                // metres the shaft penetrates
uniform float density : hint_range(0.0, 3.0) = 1.0;

varying vec3 v_world;
varying vec2 v_uv;

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
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p *= 2.05;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
}

void fragment() {
	float d = top_y - v_world.y;                       // depth below the surface
	// Off above the surface, ramp on just under it, fade to nothing by `reach`.
	float belowness = clamp(d, 0.0, reach) / reach;
	float fall = (1.0 - belowness);
	fall *= fall * smoothstep(0.0, 0.6, d);
	// Soft edges across the beam so it reads as a shaft, not a rectangle. Squared for a
	// narrow bright core feathering to nothing at the edges.
	float edge = smoothstep(0.0, 0.48, v_uv.x) * smoothstep(1.0, 0.52, v_uv.x);
	edge *= edge;
	// Scrolling breakup down the beam — high contrast so the shaft dissolves into
	// separate rays instead of reading as a solid slab.
	float n1 = fbm(vec2(v_world.x * 0.28 + v_world.z * 0.19, v_world.y * 0.24 - TIME * 0.42));
	float n2 = fbm(vec2(v_world.x * 0.6 - TIME * 0.2, v_world.z * 0.5 + TIME * 0.15));
	float breakup = clamp((0.15 + 0.85 * n1) * (0.35 + 0.85 * n2), 0.0, 1.0);
	float beam = edge * fall * breakup;
	ALBEDO = shaft_color * beam * density * (0.15 + 0.85 * daylight);
}
