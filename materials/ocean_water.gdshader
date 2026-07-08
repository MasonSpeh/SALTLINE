shader_type spatial;
// Placeholder scrolling "normal map" ocean shader — procedural, no texture assets required.
// Replaced by a real asset-driven shader once art passes greybox (GDD §2, §6 Phase 0).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.05, 0.15, 0.2, 1.0);
uniform vec4 water_color_deep : source_color = vec4(0.02, 0.05, 0.08, 1.0);
uniform float wave_speed = 0.15;
uniform float wave_scale = 8.0;
uniform float wave_height = 0.05;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.15;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float wave = sin((world_pos.x + t * 10.0) * 0.2) * wave_height
		+ cos((world_pos.z + t * 7.0) * 0.25) * wave_height;
	VERTEX.y += wave;
}

void fragment() {
	vec2 uv1 = UV * wave_scale + vec2(TIME * wave_speed, TIME * wave_speed * 0.6);
	vec2 uv2 = UV * wave_scale * 1.7 - vec2(TIME * wave_speed * 0.7, TIME * wave_speed * 0.3);
	float n1 = sin(uv1.x * 6.283) * cos(uv1.y * 6.283);
	float n2 = sin(uv2.x * 6.283 + 1.5) * cos(uv2.y * 6.283 + 1.5);
	vec3 fake_normal = normalize(vec3(n1 * 0.3, 1.0, n2 * 0.3));
	NORMAL_MAP = fake_normal * 0.5 + 0.5;
	ALBEDO = mix(water_color_deep.rgb, water_color.rgb, 0.5 + 0.5 * n1);
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
}
