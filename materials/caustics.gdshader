shader_type spatial;
// Animated caustics — the rippling net of focused sunlight the surface throws onto
// whatever is near it. Wrapped on the upper rig legs and thrown on the under-deck
// steel, they only exist in the top few metres (sunlight can't focus caustics in the
// dark deep). Additive, procedural, world-space so the pattern never swims with the
// mesh. gl_compatibility safe.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 caustic_color : source_color = vec3(0.38, 0.80, 0.74);
uniform float daylight = 1.0;
uniform float top_y = 0.0;
uniform float reach = 6.0;
uniform float scale = 0.7;
uniform float strength : hint_range(0.0, 3.0) = 1.0;

// THE RIDGE SUM IS A HUMP, NOT A FLOOR WITH SPIKES — measured off this exact function at
// the shipped scale (0.85) over a real caisson face, four times, 360k samples: mean 0.661,
// median 0.670, p99 0.924. An exponent applied to that cannot produce "near black except
// filaments", and it did not: pow(v, 5.5) left median 0.110 with 54.0% of the quad above a
// tenth of peak. Cut the hump off BELOW the ridge tips first, then shape, then put the peak
// back with the gain, so the filaments keep their brightness while the DC that painted the
// panel goes. See caustic().
const float RIDGE_FLOOR = 0.68;
const float RIDGE_SHAPE = 2.2;
const float RIDGE_GAIN = 1.175;

varying vec3 v_world;
// THE SURFACE'S OWN NORMAL, IN WORLD SPACE. Godot's fragment-stage `NORMAL` is in VIEW space,
// so branching on it below picked the projection plane by where the CAMERA was rather than by
// which way the face pointed. Same idiom as seabed_rock.gdshader:16 and seabed.gdshader:20,
// which build this varying for exactly this reason.
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

// Layered ridged noise -> thin bright caustic filaments that braid and drift.
float caustic(vec2 p, float t) {
	float v = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 q = p + vec2(sin(t * 0.31 + fi * 1.7), cos(t * 0.27 + fi * 1.3)) * 0.6;
		float n = vnoise(q * (1.5 + fi * 0.4) + t * 0.12);
		v += 1.0 - abs(n * 2.0 - 1.0);      // ridge
	}
	v /= 3.0;
	// THE "LIT BOX" IS THIS LINE, and it outlived both of the fixes aimed at it. s31 fixed
	// the branch below (real, and it worked — the stripes are gone), but the quads still
	// photograph as a hard-edged teal panel sleeved over the leg in /tmp/s34_final/two_legs.png,
	// captured AFTER that fix. An additive quad that is lit over half its area IS a panel,
	// however good its pattern is. Measured, same 360k samples, shipped -> this:
	//     median        0.110 -> 0.000
	//     lit fraction  54.0% -> 19.7%   (above a tenth of peak)
	//     mean          0.157 -> 0.065
	//     p99           0.649 -> 0.649   (filament brightness deliberately unchanged)
	// The edge feather below was never the problem: an 0.84 m feather on a wash reads as a
	// hard border because the wash is what draws the border.
	float f = clamp((v - RIDGE_FLOOR) / (1.0 - RIDGE_FLOOR), 0.0, 1.0);
	return clamp(pow(f, RIDGE_SHAPE) * RIDGE_GAIN, 0.0, 1.0);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// `top_y` IS THE STILL-WATER LINE, AND THIS COMMENT USED TO SAY THE OPPOSITE.
	//
	// It described a real shipped bug — underwater_fx wrote `Gyre.swim_line(player.xz)`
	// into the one shared material all 16 quads use, so the caustic band on every caisson
	// rode the player's own Gerstner phase and slid up and down pillars 40 m away as they
	// swam. That was fixed in s35: the write is now `Gyre.tide()` (underwater_fx.gd, in
	// the per-frame caustic loop), which is observer-independent.
	//
	// The comment was left describing the broken version, and it has since sent two
	// separate investigations of "moving lines on the concrete" down this dead end. If you
	// are here chasing that symptom: caustics are gated to underwater only (the caustic
	// root is hidden above `surf + 1.5`) and exist on the four caisson legs alone, so they
	// cannot be responsible for anything seen topside or on the tower.
	float d = top_y - v_world.y;
	float belowness = clamp(d, 0.0, reach) / reach;
	float fall = (1.0 - belowness);
	fall *= fall * smoothstep(0.0, 0.4, d);

	// Project into the surface's OWN plane. These quads are VERTICAL (they lie on the
	// caisson faces), so sampling world XZ held one axis constant across the entire face
	// and the "caustic net" degenerated into vertical stripes that never moved down the
	// leg — which is what made the four quads read as the flat panels of a glass box
	// rather than light playing on steel. Pick the two in-plane axes from the normal.
	// WORLD normal, not the view-space one. This selector is what the comment above describes,
	// and it never worked: fragment `NORMAL` is VIEW space, so the branch was chosen by the
	// camera. Pitch down past ~45 deg while looking at a leg — from the pontoon walkway, the
	// tidal ladder, or in the water — and `an.y` wins, taking the `v_world.xz` branch on a
	// VERTICAL face. There world z (or x) is constant across the whole quad, so the 2-D
	// caustic net collapses to iso-lines of a single axis, i.e. vertical stripes; and
	// `caustic()` translates its noise field by `t * 0.12` every frame, so those stripes crawl
	// sideways at a constant 0.06-0.09 m/s for ever. That is the "vertical lines all moving to
	// the left constantly" on the foundation pillars.
	vec3 an = abs(normalize(v_wn));
	vec2 pp;
	if (an.y > max(an.x, an.z)) {
		pp = v_world.xz;                 // horizontal face: the classic floor projection
	} else if (an.x > an.z) {
		pp = vec2(v_world.z, v_world.y); // faces +/-X
	} else {
		pp = vec2(v_world.x, v_world.y); // faces +/-Z
	}
	float c = caustic(pp * scale, TIME);

	// Feather every quad to nothing at its own border. Without this the fade is purely
	// depth-based, so whenever the swell lifted top_y the pattern was still faintly lit
	// where the mesh simply STOPS, drawing a hard rectangular seam around the leg.
	vec2 e = smoothstep(vec2(0.0), vec2(0.14), UV) * smoothstep(vec2(0.0), vec2(0.14), 1.0 - UV);
	float edge = e.x * e.y;

	ALBEDO = caustic_color * c * fall * edge * strength * (0.12 + 0.88 * daylight);
}
