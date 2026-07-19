shader_type spatial;
// THE SURFACE FROM BELOW — the single biggest "I am really underwater" cue.
//
// A large horizontal plane held just under the swell, over the player. Looking up
// through it you get Snell's window: a bright rippling mirror-like disc straight
// overhead (the ~96 deg cone the whole sky is refracted into) that darkens toward
// horizontal, where the underside of the water turns to total internal reflection of
// the dark deep. The sun/moon smears through it near the vertical. gl_compatibility
// safe: unshaded, procedural noise only, no depth texture, no runtime textures.
render_mode unshaded, cull_disabled, specular_disabled, shadows_disabled;

uniform vec3 window_color : source_color = vec3(0.42, 0.72, 0.74);
uniform vec3 horizon_color : source_color = vec3(0.015, 0.07, 0.09);
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.78);
uniform vec3 sun_dir = vec3(0.3, 0.85, 0.2);   // world direction toward the sun/moon
uniform float daylight = 1.0;                  // 0 night .. 1 midday, set per frame
uniform float ripple : hint_range(0.0, 2.0) = 1.0;

varying vec3 v_world;

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
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 ray = normalize(v_world - cam);        // camera -> point on the underside
	float up = clamp(ray.y, 0.0, 1.0);          // 1 looking straight up, 0 horizontal

	// Rippling: two scrolling noise fields shove the effective viewing angle around,
	// so the window edge shimmers like a real disturbed surface instead of a hard ring.
	// Frequency matters more than it looks: at 0.16 the features were ~6 m across, and
	// from a metre under the surface you only see a few metres of plane, so the whole
	// window sat inside ONE noise cell and rendered as a smooth featureless glow. Pull
	// the scale up (sub-metre ripple) and let it actually bite on the window edge.
	vec2 rp = v_world.xz * 0.85;
	float n1 = fbm(rp + vec2(TIME * 0.22, TIME * 0.17));
	float n2 = fbm(rp * 2.3 - vec2(TIME * 0.13, TIME * 0.28));
	float shimmer = (n1 + n2 - 1.0);            // ~ -0.5 .. 0.5
	float upw = clamp(up + shimmer * 0.30 * ripple, 0.0, 1.0);

	// Snell's window: a crisp bright refraction disc, collapsing to the dark mirrored
	// deep toward the horizontal. Sharper edge so it reads as a rippling window even
	// just under the surface, where the disc fills most of the view.
	float window = smoothstep(0.50, 0.74, upw);
	vec3 col = mix(horizon_color, window_color, window);
	col += window_color * window * 0.12;   // lift the disc so it glows

	// Sun / moon smeared through the window, biased to the sun's azimuth and the
	// steep-up centre of the cone.
	vec2 rd = normalize(vec2(ray.x, ray.z) + vec2(0.0001));
	vec2 sd = normalize(vec2(sun_dir.x, sun_dir.z) + vec2(0.0001));
	float sa = clamp(dot(rd, sd), 0.0, 1.0);
	// Looking straight up, ray.xz collapses to zero and its normalize() flips around
	// wildly from fragment to fragment — which drew a hard white WEDGE across the middle
	// of the window. There is no meaningful azimuth at the zenith, so fade the bearing
	// term out as the ray approaches vertical.
	float hmag = length(vec2(ray.x, ray.z));
	sa = mix(1.0, sa, smoothstep(0.02, 0.28, hmag));
	float smear = window * pow(sa, 3.0) * smoothstep(0.55, 0.97, upw);
	col += sun_color * smear * (0.30 * (0.35 + 0.65 * daylight));

	// Rippled glints breaking up the disc surface.
	float glint = smoothstep(0.70, 0.99, upw) * smoothstep(0.55, 0.95, n2);
	col += window_color * glint * 0.22;

	col *= (0.08 + 0.92 * daylight);
	// These terms are additive on an UNSHADED surface, so at the centre of the disc they
	// summed well past 1.0: the window blew out to a flat white hole that swallowed its
	// own ripple and then bloomed through the glow pass. A soft knee keeps the disc the
	// brightest thing in frame while preserving the structure inside it.
	col = col / (1.0 + col * 0.38);
	ALBEDO = col;
}
