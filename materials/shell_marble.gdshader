shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// GASTROPOD SHELL PATTERNING — backlit marble, spiral banding, and soft flesh.
//
// WHY THIS EXISTS. The lamp snail used to wear a "constellation": seven to eleven
// discrete glowing SPHERES parented to the shell. Two problems with that. It read as
// sparkles stuck onto a dark lump rather than as light living inside a shell, and —
// measured — it was invisible anyway: CreatureAnim.replace() hides every MeshInstance3D
// that existed on the host before the generated mesh lands, and the spots were built
// before the replace() call, so once lamp_snail.glb shipped the whole constellation was
// dead geometry whose materials were still being driven every frame.
//
// So the pattern moved into the surface. This is creature_swim.gdshader's contract kept
// intact (same uniform names, same vertex motion for the modes a gastropod uses, same
// fresnel rim) with a PATTERN LAYER on top, sampled in OBJECT SPACE — not UV. Object
// space is what makes the veins flow around the shell as one continuous marbling across
// however the generator happened to unwrap it, and it costs no texture at all.
//
// Swap a generated model onto this the way GlassSnail swaps to creature_swim_glass:
// ShaderMaterial keeps every parameter across a shader change (matched by name), so the
// baked PBR maps, the authored facing and the pedal motion all carry over.
//
// gl_compatibility SAFETY (this project runs the compatibility renderer):
//   * no derivatives, no texelFetch, no textureLod, no screen/depth texture reads,
//     no arrays of uniforms, no instance uniforms — everything here is GLES3-baseline.
//   * the noise is a multiply/fract hash (Hoskins-style). NO trig in the hash: sin-based
//     hashing is the classic thing that falls apart on mobile/GLES precision.
//   * loops are constant-bound (3 octaves) so they unroll.
//   * budget: worst case is PATTERN_MARBLE at 3 fbm octaves = 24 hash evaluations plus a
//     handful of sin/smoothstep. That is one small creature's worth of arithmetic and no
//     new texture fetches, which is cheaper than the geometry + extra draw calls it
//     replaced.

const float TAU_ = 6.28318530718;

// --- imported PBR surface (identical contract to creature_swim.gdshader) ------------
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform sampler2D normal_tex : hint_normal;
uniform bool use_normal = false;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.45;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.0;
// Declared for parameter compatibility with CreatureAnim.apply()/GlassSnail — this
// shader is OPAQUE and never writes ALPHA, exactly like the base creature shader.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

// --- motion (the gastropod subset of creature_swim's modes) -------------------------
// 5 = PEDAL (muscular foot wave), 7 = BREATHE (resting swell). Anything else is static,
// which is what a mineral shell wants. Kept to two modes deliberately: this shader is
// only ever worn by snails, and every branch here is instructions a shell pays for.
uniform int mode = 5;
uniform float amp = 0.02;
uniform float rate = 0.5;
uniform float phase = 0.0;
uniform vec3 bounds_min = vec3(-1.0);
uniform vec3 bounds_size = vec3(2.0);
// Declared so CreatureAnim.attach()'s facing push finds them (see FACING table).
uniform int flow_axis = 0;
uniform float flow_flip = 1.0;
uniform int lift_axis = 0;
uniform float wave_len = 1.6;

// --- bioluminescent rim (unchanged from the base shader) ----------------------------
uniform vec4 glow_color : source_color = vec4(0.25, 0.95, 0.88, 1.0);
uniform float glow_energy = 0.0;
uniform float rim_power : hint_range(1.0, 8.0) = 3.0;

// --- the pattern layer ---------------------------------------------------------------
// 0 MARBLE  wavy domain-warped veins of light through a darker shell body (lamp snail)
// 1 SPIRAL  hard black/white bands winding up a cone (pyramid snail)
// 2 FLESH   soft mottled tissue with a warm translucent-looking rim (snail bodies)
uniform int pattern_mode = 0;
uniform vec4 base_color : source_color = vec4(0.09, 0.26, 0.27, 1.0);  // shell body
uniform vec4 vein_color : source_color = vec4(0.35, 1.0, 0.92, 1.0);   // the lit ribbons
// THE DIMMER. Gameplay drives this from code every frame: 0.0 for the unlit daytime
// state, full at night, knocked down while the shell is recharging after a harvest.
// It is the direct replacement for the old per-spot emission_energy_multiplier.
uniform float vein_energy = 0.0;
uniform float vein_width : hint_range(0.02, 0.9) = 0.34;   // how broad a ribbon runs
uniform float vein_sharp : hint_range(0.0, 0.99) = 0.72;   // 1 = knife edge, 0 = smoke
uniform float pattern_scale = 3.2;      // veins per unit of normalised body
uniform float pattern_scroll = 0.03;    // slow drift through the marbling (0 = frozen)
uniform float warp_strength = 1.5;      // domain warp: 0 = stripes, high = liquid marble
// Where on the body the pattern lives, along normalised height. The lamp snail's
// generated mesh is ONE surface covering shell AND foot, so the shell pattern is masked
// off the soft tissue rather than smeared over the whole animal.
uniform float mask_lo = 0.22;
uniform float mask_hi = 0.46;
// How far to wash the colour out of the BAKED skin before base_color tints it. The lamp
// snail's generated texture has decorative yellow spots painted into it — the old
// constellation, baked — and at full saturation they fight the veining as olive blotches.
// 1.0 = pure luminance, which lets base_color decide the shell's colour outright.
uniform float base_desat : hint_range(0.0, 1.0) = 0.0;
// How much of the baked skin survives at all. 0 = the shell is pure shader (base_color +
// veins), which is the only way to get rid of the generator's baked-in star decals
// completely — desaturating them still leaves them as light/dark stars. The lamp snail's
// generated texture IS the old constellation, painted on, so it goes.
uniform float skin_mix : hint_range(0.0, 1.0) = 1.0;
// SPIRAL mode. Keep band_turns a whole number: the angular term is an atan, so only an
// integer number of turns closes seamlessly across the -PI/+PI cut.
uniform vec4 band_dark : source_color = vec4(0.03, 0.03, 0.04, 1.0);
uniform vec4 band_light : source_color = vec4(0.95, 0.94, 0.90, 1.0);
uniform float band_turns = 3.0;         // stripe advance per revolution
uniform float band_freq = 7.0;          // stripe advance up the shell
uniform float band_edge : hint_range(0.01, 0.6) = 0.12;

varying vec3 v_obj;   // normalised object-space position, 0..1 over the body bounds

// --- noise ----------------------------------------------------------------------------
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// Three octaves. More than that stops reading as marble and starts reading as grain.
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// One vein ribbon. `s` is a scalar field; the veins are its zero crossings, so warping
// `s` with noise is what turns parallel stripes into flowing marble. 1 - |sin| peaks
// along the crossing, and the smoothstep window narrows it to a ribbon.
float ribbon(float s, float width, float sharp) {
	float ridge = 1.0 - abs(sin(s * 3.14159265));
	float lo = 1.0 - clamp(width, 0.02, 0.95);
	float hi = lo + clamp(width, 0.02, 0.95) * (1.0 - clamp(sharp, 0.0, 0.99)) + 0.004;
	return smoothstep(lo, hi, ridge);
}

void vertex() {
	vec3 p = VERTEX;
	vec3 n = (p - bounds_min) / max(bounds_size, vec3(0.0001));
	v_obj = n;
	float t = TIME * rate + phase;
	float along_raw = (flow_axis == 0) ? n.z : n.x;
	float along = mix(along_raw, 1.0 - along_raw, flow_flip);

	if (mode == 5) {
		// GASTROPOD PEDAL WAVE — same maths as creature_swim mode 5: muscular ripples
		// squeezed along the sole, tail to head. Only the foot participates.
		float foot = 1.0 - clamp(n.y * 3.0, 0.0, 1.0);
		float wave = sin(t * TAU_ + along * TAU_ * 1.6);
		p.y += wave * amp * foot;
		float fw = wave * amp * 0.4 * foot;
		if (flow_axis == 0) { p.z += fw; } else { p.x += fw; }
		p.y += sin(t * TAU_) * amp * 0.15 * (1.0 - foot);
	} else if (mode == 7) {
		// RESTING SWELL, about the body centre so a foot-pivoted mesh doesn't pump
		// itself through the plating.
		vec3 mid = bounds_min + bounds_size * 0.5;
		float s = sin(t * TAU_) * amp;
		p = mid + (p - mid) * (1.0 + s * 0.5);
		p.y += s * 0.3;
	}
	VERTEX = p;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * tint;
	vec3 albedo = a.rgb;
	vec3 emit = vec3(0.0);
	ROUGHNESS = roughness_v;
	METALLIC = metallic_v;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	if (pattern_mode == 0) {
		// ---- MARBLE: backlit nacre. Domain-warp a linear field with fbm, then take two
		// ribbon families off it at different projections so the veining branches and
		// crosses the way real marble does instead of running as one combed direction.
		vec3 q = v_obj * pattern_scale;
		float w = fbm(q + vec3(0.0, TIME * pattern_scroll, 0.0));
		float s1 = (q.x + q.y * 1.6 + q.z * 0.7) + w * warp_strength * 4.0;
		float s2 = (q.z * 1.3 - q.x * 0.5 + q.y * 0.9) * 0.7 + w * warp_strength * 5.5;
		float vein = max(ribbon(s1, vein_width, vein_sharp),
						 ribbon(s2, vein_width * 0.8, vein_sharp) * 0.75);
		// THE HALO. A ribbon on its own reads as a drawn line — a topographic contour
		// stuck on the shell. What makes it read as light coming from INSIDE the shell is
		// a second, much broader and much softer ribbon on the same field: the vein is the
		// hot core, the halo is the shell material around it glowing through.
		float wide = clamp(vein_width * 2.4, 0.0, 0.95);
		float halo = max(ribbon(s1, wide, vein_sharp * 0.15),
						 ribbon(s2, wide * 0.85, vein_sharp * 0.15) * 0.7);
		// Shell only — the soft foot underneath keeps the baked skin.
		float shell = smoothstep(mask_lo, mask_hi, v_obj.y);
		vein *= shell;
		halo *= shell;
		// A slow spatial shimmer so the whole shell doesn't breathe as one flat lamp.
		// Code owns the level (vein_energy); this only varies it across the surface.
		float shimmer = 0.72 + 0.28 * sin(TIME * 0.8 + w * 9.0);
		vein *= shimmer;
		halo *= shimmer;
		vec3 skin = mix(albedo, vec3(dot(albedo, vec3(0.299, 0.587, 0.114))), base_desat);
		skin = mix(vec3(1.0), skin, skin_mix);
		albedo = mix(skin * base_color.rgb, vein_color.rgb * 0.8,
				clamp(vein * 0.9 + halo * 0.3, 0.0, 1.0)
				* clamp(vein_energy * 0.4 + 0.45, 0.0, 0.92));
		emit = vein_color.rgb * vein_energy * (vein + halo * 0.32);
	} else if (pattern_mode == 1) {
		// ---- SPIRAL BANDS: a marine textile-cone. Stripe coordinate = turns around the
		// axis + advance up it, which is a helix; the fbm term only roughens the edges so
		// the graphic stays graphic but never looks machined.
		vec2 d = v_obj.xz - vec2(0.5);
		float ang = atan(d.y, d.x) / TAU_;
		float w = fbm(v_obj * pattern_scale * 2.0);
		float s = ang * band_turns + v_obj.y * band_freq + (w - 0.5) * 0.5;
		float stripe = smoothstep(-band_edge, band_edge, sin(s * TAU_));
		albedo = mix(band_dark.rgb, band_light.rgb, stripe);
		// Mineral sheen: the pale bands are nacre, the dark ones matte.
		ROUGHNESS = mix(roughness_v, roughness_v * 0.45, stripe);
		emit = vein_color.rgb * vein_energy * stripe * rim;
	} else {
		// ---- FLESH: soft mottled tissue. The compatibility renderer has no subsurface
		// scattering, so the "light getting through it" is faked the only honest way —
		// a warm emissive term that lives at the grazing angles, where a translucent
		// body really does let light out.
		float m = fbm(v_obj * pattern_scale * 2.4);
		albedo = mix(base_color.rgb, vein_color.rgb, clamp(m * 0.75, 0.0, 1.0)) * a.rgb;
		emit = vein_color.rgb * vein_energy * (0.10 + 0.6 * rim);
	}

	if (glow_energy > 0.001) {
		emit += glow_color.rgb * glow_energy * rim;
	}
	ALBEDO = albedo;
	EMISSION = emit;
}
