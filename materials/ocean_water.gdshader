shader_type spatial;
// North Sea swell, v3: SUMMED GERSTNER (trochoidal) waves, not sines.
//
// Why Gerstner: a sine only moves vertices up/down, giving rounded symmetric humps.
// A Gerstner wave also pushes vertices HORIZONTALLY toward the crest, which is the
// physics that piles water into SHARP peaks and BROAD troughs. We sum 11 components
// across three scale bands, each travelling at its own physical phase speed from the
// deep-water dispersion relation (c = sqrt(g/k)), so the bands continuously slip out
// of phase and never march in parallel rows. Long swell is amplitude-modulated by
// slow "wave sets" so crests arrive in groups with lulls between. A mild domain warp
// bends the crest lines so no two are identical. Whitecaps come from the Gerstner
// Jacobian (horizontal folding / steepness), not a height threshold, so foam sits on
// breaking crests instead of drawing contour lines.
//
// gl_compatibility: no compute, no depth texture. Vertex waves on the near mesh;
// `vertex_waves` off leaves a component flat (unused now — the ocean is one radial
// camera-following mesh). Analytic Gerstner normal + Jacobian computed per vertex and
// interpolated. Keep gyre.gd (debris) in sync with the math below.
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.10, 0.22, 0.24, 1.0);
uniform vec4 deep_color : source_color = vec4(0.030, 0.070, 0.082, 1.0);
uniform vec4 foam_color : source_color = vec4(0.90, 0.94, 0.95, 1.0);
uniform vec3 sky_tint : source_color = vec3(0.55, 0.66, 0.78);   // grazing sky reflection colour
// Radiance of the sky the sea is mirroring, driven by SunController: ~1 at midday,
// warm and low at dusk, ~0.06 under stars, halved by overcast. Without this the
// reflection term has no idea whether it is noon or midnight.
uniform float sky_energy : hint_range(0.0, 2.0) = 0.8;
uniform float sea_state : hint_range(0.0, 1.0) = 0.4;   // 0 glassy calm .. 1 full storm
uniform bool vertex_waves = true;
uniform float debug_flat = 0.0;   // TEMP: 1 = unshaded height, to check the geometry

const float G = 9.81;
const int NW = 11;
// Distance band over which vertex displacement fades to flat (see vertex()).
const float FAR_DAMP_NEAR = 180.0;
const float FAR_DAMP_FAR = 620.0;
// Unit heading directions — near-but-not-identical, fanned across ~145 deg so no band
// of parallel crests can form. (cos, sin) of chosen angles.
const vec2 W_DIR[11] = {
	vec2(0.990, 0.139),   // +8   long swell
	vec2(0.995, -0.105),  // -6   long swell
	vec2(0.951, 0.309),   // +18  long swell
	vec2(0.866, 0.500),   // +30  mid wind wave
	vec2(0.940, -0.342),  // -20  mid wind wave
	vec2(0.695, 0.719),   // +46  mid wind wave
	vec2(0.788, -0.616),  // -38  mid wind wave
	vec2(0.500, 0.866),   // +60  chop
	vec2(0.574, -0.819),  // -55  chop
	vec2(0.259, 0.966),   // +75  chop
	vec2(0.342, -0.940)   // -70  chop
};
const float W_LEN[11] = {90.0, 62.0, 48.0, 24.0, 16.0, 11.0, 8.5, 5.5, 3.8, 2.6, 1.7};
// Reference amplitudes (metres) at full sea; scaled down by amp_scale for calmer seas.
// Boosted from a too-timid spectrum: the mid/short bands now carry enough height that
// the near field actually has chop to shade instead of a smooth swell face.
const float W_AMP[11] = {1.40, 1.05, 0.82, 0.52, 0.40, 0.29, 0.22, 0.15, 0.11, 0.078, 0.052};
const float W_STEEP[11] = {0.62, 0.68, 0.72, 0.80, 0.82, 0.85, 0.85, 0.90, 0.90, 0.92, 0.95};
// Two long "wave set" envelopes: slow, large-scale amplitude modulation so swell
// arrives in groups with lulls (heading, spatial wavenumber, temporal rate).
const vec2 SET_DIR_A = vec2(0.97, 0.24);
const vec2 SET_DIR_B = vec2(0.20, -0.98);

varying vec3 world_pos;
varying float v_fold;     // Gerstner Jacobian folding -> whitecaps
varying float v_height;   // displaced surface height, for crest/trough tinting
varying float v_up;       // world normal.y, for crest sheen

// -- value noise (hash-based): anti-grid ingredient, used for foam/ripple only ------
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

// Domain warp: bends every wave's crest line so no two are identical straight ridges.
// Must match Gyre._warp() so floating debris rides the same water.
vec2 warp(vec2 p, float t) {
	return p + 3.0 * vec2(sin(p.y * 0.018 + t * 0.05), sin(p.x * 0.015 - t * 0.04));
}

// GUST PATCHINESS — the fix for "the waves all look the same".
//
// The spectrum below already fans 11 trains across 145 degrees, but every one of them ran
// at CONSTANT amplitude everywhere on the sea at once, so the whole visible field had a
// single uniform roughness: the same chop on the same swell in every direction, to the
// horizon. A real sea is patchy at a scale you can see from a deck — wind lays dark
// cat's-paws in bands 50-100 m across and leaves glassy slicks between them, and that
// mottling is most of what makes water look alive rather than tiled.
//
// Three drifting long-period sinusoids (74 / 103 / 170 m, travelling downwind) modulate the
// WIND-WAVE and CHOP bands only. Swell is not wind-driven and must not pulse with the
// gusts, so components 0-2 are left alone. Sinusoids rather than hash noise so gyre.gd can
// mirror it exactly and floating debris keeps riding the same water.
// Must match Gyre._patchiness().
float patchiness(vec2 p, float t) {
	float a = sin(p.x * 0.085 + p.y * 0.031 - t * 0.16);
	float b = sin(p.x * -0.024 + p.y * 0.061 - t * 0.11);
	float c = sin((p.x + p.y) * 0.037 + t * 0.07);
	return mix(0.42, 1.42, clamp(0.5 + 0.26 * a + 0.20 * b + 0.16 * c, 0.0, 1.0));
}

// Sum of Gerstner components at world xz. Returns horizontal+vertical displacement,
// analytic normal, and the Jacobian folding term (>0 where the surface compresses).
void gerstner(vec2 x0, float t, float ss, out vec3 disp, out vec3 nrm, out float fold) {
	vec2 w = warp(x0, t);
	disp = vec3(0.0);
	float nx = 0.0;
	float nz = 0.0;
	float ny = 1.0;
	float jxx = 0.0;
	float jzz = 0.0;
	float jxz = 0.0;
	float amp_scale = 0.18 + 0.92 * ss;              // sea_state -> amplitude
	float steep_scale = 0.35 + 0.65 * ss;            // sea_state -> steepness
	float gust = patchiness(x0, t);                  // wind mottling, wind bands only
	for (int i = 0; i < NW; i++) {
		vec2 dir = W_DIR[i];
		float k = 6.28318530718 / W_LEN[i];
		float omega = sqrt(G * k);                   // deep-water dispersion
		float A = W_AMP[i] * amp_scale;
		// Wave-set modulation on the three long swell trains only.
		if (i < 3) {
			vec2 sd = (i == 1) ? SET_DIR_B : SET_DIR_A;
			float env = dot(sd, x0) * 0.010 - t * (0.045 + 0.02 * float(i));
			A *= 0.55 + 0.45 * sin(env);
		} else {
			A *= gust;                               // wind waves & chop are patchy
		}
		float steepEff = W_STEEP[i] * steep_scale;
		// Q*A and Q*k*A are independent of A (A cancels), so wave-set fades never blow up.
		float qa = steepEff / (k * float(NW));       // == Q * A
		float qwa = steepEff / float(NW);            // == Q * k * A
		float WA = k * A;                            // frequency * amplitude
		float phase = k * dot(dir, w) - omega * t;
		float c = cos(phase);
		float s = sin(phase);
		disp.x += qa * dir.x * c;
		disp.z += qa * dir.y * c;
		disp.y += A * s;
		// GPU-Gems analytic normal accumulation.
		nx -= dir.x * WA * c;
		nz -= dir.y * WA * c;
		ny -= qwa * s;
		// Horizontal Jacobian (steepness / folding) for whitecaps.
		jxx -= dir.x * dir.x * qwa * s;
		jzz -= dir.y * dir.y * qwa * s;
		jxz -= dir.x * dir.y * qwa * s;
	}
	nrm = normalize(vec3(nx, max(ny, 0.02), nz));
	float jdet = (1.0 + jxx) * (1.0 + jzz) - jxz * jxz;
	fold = 1.0 - jdet;                               // >0 compressed crest, ->1 breaking
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (vertex_waves) {
		vec3 disp;
		vec3 nrm;
		float fold;
		gerstner(world_pos.xz, TIME, sea_state, disp, nrm, fold);
		// FAR-FIELD DAMPING. The radial mesh coarsens with radius, so out past a couple of
		// hundred metres one quad spans most of a wavelength and full-amplitude Gerstner
		// displacement aliases into hard rectangular teeth along the horizon. Real distant
		// sea does the opposite: individual crests stop being resolvable and the surface
		// reads as a flat haze band. Fade the displacement out across the same band the
		// fog swallows, and flatten the normal with it so no far crest catches a specular
		// glint the geometry can no longer justify. Gyre (the CPU mirror) is untouched:
		// everything that floats lives inside 40 m of the rig, where damp == 1.
		float cam_dist = length(world_pos.xz - INV_VIEW_MATRIX[3].xz);
		float damp = 1.0 - smoothstep(FAR_DAMP_NEAR, FAR_DAMP_FAR, cam_dist);
		disp *= damp;
		nrm = normalize(mix(vec3(0.0, 1.0, 0.0), nrm, damp));
		fold *= damp;
		// Ocean node is translation-only (camera follow), so world delta == local delta.
		VERTEX += disp;
		world_pos += disp;
		NORMAL = nrm;
		v_fold = fold;
		v_height = disp.y;
		v_up = nrm.y;
	} else {
		NORMAL = vec3(0.0, 1.0, 0.0);
		v_fold = 0.0;
		v_height = 0.0;
		v_up = 1.0;
	}
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float ss = sea_state;

	// Fine sub-vertex ripples as a normal map: two scrolling irregular layers + noise.
	// These carry the glints the 0.5 m mesh quads are too coarse to resolve.
	vec2 r1 = vec2(sin(p.x * 1.7 + t * 1.9 + sin(p.y * 1.3 + t)),
			cos(p.y * 1.9 - t * 1.6 + sin(p.x * 1.1)));
	vec2 r2 = vec2(sin(p.x * 4.3 - t * 2.6 + sin(p.y * 2.9)), cos(p.y * 3.7 + t * 2.2 + sin(p.x * 3.1)));
	float nrip = fbm(p * 0.6 + vec2(t * 0.4, -t * 0.3)) - 0.5;
	float rip_amp = 0.05 + 0.09 * ss;
	vec3 ripple = normalize(vec3((r1 + r2 * 0.5).x * rip_amp + nrip * 0.12, 1.0,
			(r1 + r2 * 0.5).y * rip_amp - nrip * 0.1));
	NORMAL_MAP = ripple * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.9;

	// Base colour by wave HEIGHT: broad troughs stay deep and dark, crests lift toward
	// the lighter shallow tint. This is what makes the swell read as 3-D relief even
	// under flat overcast light, instead of a uniform sheet. Height is normalised by an
	// amplitude that grows with sea_state so the contrast holds from calm to storm.
	float span = 0.9 + 1.6 * ss;
	float hn = clamp(v_height / span * 0.5 + 0.5, 0.0, 1.0);
	// hn*hn collapsed the whole lower half of the wave range onto deep_color, so every
	// trough — which is most of the NEAR field, where you look down at a steep angle and
	// Fresnel gives you no sky either — went to a flat near-black hole a couple of metres
	// in front of the camera. Keep most of the crest/trough contrast but blend in a
	// linear term so troughs stay readable water instead of a void.
	float hcurve = hn * hn * 0.6 + hn * 0.4;
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, hcurve);
	// A little sky light catches the up-facing crest shoulders.
	base += shallow_color.rgb * 0.10 * smoothstep(0.5, 1.0, v_up) * hn;

	// Schlick Fresnel, water F0 = 0.02. At a grazing angle water is a MIRROR — reflectance
	// runs to ~1 — which is why a real sea CONVERGES to the sky's brightness at the
	// horizon instead of meeting it along a hard dark line. The reflection itself is
	// applied as EMISSION below, not mixed into ALBEDO: reflected sky is radiance that
	// arrives regardless of where the sun is, whereas ALBEDO gets multiplied by the
	// (very low, grazing) incoming sunlight. Folding it into ALBEDO and capping it at
	// 0.4 is what rendered this sea as black tar under every sky, day and night alike.
	float cos_v = clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - cos_v, 5.0);
	// A little of the sky's hue still belongs in the body colour (upwelling scatter).
	base = mix(base, sky_tint * 0.5, fres * 0.22);

	// Whitecaps from STEEPNESS (Gerstner Jacobian), noise-gated so they scatter on the
	// breaking crests rather than tracing height contours. Coverage grows with sea_state.
	float fold = clamp(v_fold * (1.2 + 1.6 * ss), 0.0, 3.0);
	float breakup = fbm(p * 0.17 + vec2(t * 0.05, -t * 0.03));
	float thr = mix(0.62, 0.16, ss);
	// v_fold is computed per-VERTEX and interpolated, so thresholding it directly puts
	// the foam edge on the iso-line of a linear interpolant — a dead straight line across
	// every quad. That is what made storm whitecaps read as origami: hard-edged polygons
	// with sharp corners instead of torn foam. `breakup` alone could not hide it, being
	// far lower frequency (~6 m) than the mesh quads. Perturb the fold with fragment-space
	// noise AT the quad scale and just under it, then widen the threshold ramp, so the
	// boundary is decided by the noise and dissolves the triangle edge completely.
	float shred = (fbm(p * 1.6 + vec2(t * 0.35, -t * 0.25)) - 0.5) * 0.42
			+ (fbm(p * 4.5 - vec2(t * 0.60, t * 0.40)) - 0.5) * 0.22;
	fold += shred * (0.35 + 0.65 * ss);
	float caps = smoothstep(thr, thr + 0.46, fold) * smoothstep(0.22, 0.62, breakup);
	// Wind streaks smeared downwind off the caps.
	float streak = smoothstep(0.70, 0.95, fbm(p * 0.42 - vec2(t * 0.18, t * 0.05)));
	float foam = clamp(caps + streak * caps * 0.7 + streak * ss * ss * 0.2, 0.0, 1.0);
	base = mix(base, foam_color.rgb, foam);

	ALBEDO = base;
	// Reflected sky radiance — the term that makes water read as water. Foam is a
	// diffuse scatterer rather than a mirror, so it MASKS the reflection instead of
	// adding to it. Scaled by sky_energy so the sea darkens honestly at night rather
	// than glowing.
	vec3 refl = sky_tint * fres * sky_energy * (1.0 - foam * 0.8);
	// Breaking crests carry their own scattered light: on a storm sea, whitecaps are the
	// brightest thing in frame, and a pure-ALBEDO foam cannot show that when the storm
	// has already crushed the sun to nothing. The floor keeps caps legible on a night
	// sea, where breaking water is the only thing the eye has to read the swell by.
	vec3 foam_lit = foam_color.rgb * foam * max(sky_energy, 0.10) * 0.85;
	// Upwelling subsurface scatter: light that entered the water and came back out. It
	// does NOT depend on the sun's grazing N.L, so it is what keeps the near field —
	// where Fresnel reflection falls to almost nothing — deep sea-green instead of a
	// hole of pure black in the middle of a bright day.
	// Biased off the very bottom of the ramp and strengthened: this is the ONLY light the
	// near field gets (Fresnel -> 0.02 looking straight down), so it alone decides whether
	// the water at your feet is sea or a hole.
	vec3 upwell = mix(deep_color.rgb, shallow_color.rgb, hn * 0.6 + 0.28)
			* sky_energy * 0.85 * (1.0 - fres * 0.7);
	EMISSION = refl + foam_lit + upwell;
	// Water is fairly smooth — a broad-but-not-mirror lobe gives the sun a glitter path
	// across the chop instead of one hard aliasing dot. Foam is genuinely rough.
	ROUGHNESS = mix(0.28, 0.46, fbm(p * 0.2 + t * 0.05)) - fres * 0.10 + foam * 0.45;
	METALLIC = 0.0;
	SPECULAR = 0.5;

	if (debug_flat > 0.5 && debug_flat < 1.5) {
		ALBEDO = vec3(0.0);
		EMISSION = mix(vec3(0.02, 0.05, 0.10), vec3(0.35, 0.7, 0.85), hn);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		METALLIC = 0.0;
	} else if (debug_flat > 1.5) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(clamp(fold, 0.0, 1.0), clamp(caps, 0.0, 1.0), 0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		METALLIC = 0.0;
	}
}
