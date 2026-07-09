shader_type spatial;
render_mode unshaded, cull_front;

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 2.0;

// 3D value noise for natural star distribution
vec3 random3(vec3 p) {
	return fract(sin(vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	)) * 43758.5453);
}

void fragment() {
	vec3 dir = normalize(VERTEX);
	float lat = atan(dir.y, length(dir.xz));
	float lon = atan(dir.z, dir.x);
	
	// Star field with multi-octave noise
	vec3 star_pos = dir * 128.0;
	vec3 seed = floor(star_pos);
	vec3 frac = fract(star_pos);
	
	float stars = 0.0;
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			for (int k = -1; k <= 1; k++) {
				vec3 offset = vec3(float(i), float(j), float(k));
				vec3 rand = random3(seed + offset);
				float dist = length(frac - rand);
				stars += smoothstep(0.1, 0.0, dist) * rand.z;
			}
		}
	}
	stars = clamp(stars, 0.0, 1.0);
	
	// Twinkling effect
	float twinkle = 0.7 + 0.3 * sin(TIME * twinkle_speed + stars * 6.28);
	stars *= twinkle;
	
	// Milky way band: brighter in the galactic plane
	float milky_way = smoothstep(0.3, 0.0, abs(lat)) * 0.15;
	
	// Deep blue-black night sky
	vec3 sky_color = mix(
		vec3(0.01, 0.02, 0.05),
		vec3(0.02, 0.03, 0.08),
		smoothstep(-1.57, 1.57, lat)
	);
	
	vec3 final = sky_color + (vec3(0.9, 0.95, 1.0) * stars + milky_way) * intensity;
	ALBEDO = final;
}
