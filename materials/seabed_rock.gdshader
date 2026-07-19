shader_type spatial;
// Submerged rock: boulders, riprap armour, reef outcrops, wreck encrustation.
// Fully procedural, world-space TRIPLANAR so a boulder's vertical faces never
// stretch. A teal Bloom crust settles on the up-facing rock and glows faintly —
// the sea reclaiming the steel and stone. gl_compatibility safe.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 rock_lo : source_color = vec3(0.08, 0.10, 0.11);
uniform vec3 rock_hi : source_color = vec3(0.23, 0.25, 0.25);
uniform vec3 crust_tint : source_color = vec3(0.13, 0.42, 0.36);
uniform float tex_scale = 0.55;    // features per world metre
uniform float crust_amount = 0.4;
uniform float crust_glow = 0.14;

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
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wn);
	vec3 bw = abs(n);
	bw /= (bw.x + bw.y + bw.z);
	vec2 uvx = v_world.zy * tex_scale;
	vec2 uvy = v_world.xz * tex_scale;
	vec2 uvz = v_world.xy * tex_scale;
	float nz = fbm(uvx) * bw.x + fbm(uvy) * bw.y + fbm(uvz) * bw.z;

	vec3 base = mix(rock_lo, rock_hi, smoothstep(0.32, 0.78, nz));

	// Bloom crust favours the up-facing rock (where larvae settle) and pools in
	// broad patches; a little settles everywhere the sea can reach.
	float up = clamp(n.y, 0.0, 1.0);
	float patch = smoothstep(0.42, 0.82, fbm(uvy * 1.6 + 11.0));
	float crust = crust_amount * (0.35 + 0.65 * up) * patch;

	ALBEDO = mix(base, crust_tint, crust);
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
	EMISSION = crust_tint * crust * crust_glow;
}
