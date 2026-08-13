shader_type particles;

// Custom rain for the gl_compatibility (OpenGL) renderer. GPU particles can't
// collide with geometry here, so instead of switching emission off whenever the
// player is under cover — which hid the rain from every window and open deck —
// rain ALWAYS falls during a storm and any drop whose WORLD position lands inside
// a baked "covered volume" AABB is scaled to zero: invisible under solid roofs,
// still visible on open decks, past window openings, and beyond open-sided cover.
//
// Position is driven deterministically from a per-particle age (CUSTOM.w) and a
// stored world birth point (CUSTOM.xyz) rather than engine velocity integration,
// so behaviour is identical regardless of how the compatibility backend handles
// auto-integration; VELOCITY is pinned to zero so nothing perturbs the drop.
// local_coords is false, so TRANSFORM is world space and the AABB test is direct.

uniform vec3 emit_extents = vec3(26.0, 0.5, 26.0);   // half-size of the emission sheet
uniform vec3 wind_drift = vec3(0.0);                 // horizontal m/s, already scaled by intensity
uniform float fall_speed = 36.0;                     // constant downward m/s
// COVERED VOLUMES. 48 slots, not 24: rig 1 alone burned 16, and the three FIELD rigs — which
// had NO cover at all until s65, so rain fell inside THE ANCHORAGE's atrium — need another 17
// between them. Each box is stored as a world-space AABB CENTRED ON THE WORLD CENTRE of the
// room, plus its owning rig's yaw. The field rigs are rotated (-16 / +10 / -6 deg), so an
// axis-aligned test would either over-cover (blanking rain visibly outside the windows) or
// leak at the corners; rotating the drop about the box centre by -yaw tests the box in its
// own frame instead, which is exact. yaw 0 costs one compare and skips the maths.
uniform vec3 box_min[48];
uniform vec3 box_max[48];
uniform float box_yaw[48];
uniform int box_count = 0;

// Self-contained LCG — engine-provided random helpers differ between renderers,
// so the drop scatter is generated here and depends on nothing but NUMBER/RANDOM_SEED.
uint rng_next(inout uint s) {
	s = s * uint(1664525) + uint(1013904223);
	return s;
}

float rnd01(inout uint s) {
	return float(rng_next(s) >> uint(8)) * (1.0 / 16777216.0);
}

void start() {
	uint seed = ((NUMBER + uint(1)) * uint(747796405)) ^ (RANDOM_SEED * uint(2891336453));
	rng_next(seed);                                   // warm up the state
	float rx = rnd01(seed) * 2.0 - 1.0;
	float ry = rnd01(seed) * 2.0 - 1.0;
	float rz = rnd01(seed) * 2.0 - 1.0;
	vec3 local = vec3(rx * emit_extents.x, ry * emit_extents.y, rz * emit_extents.z);
	vec3 birth = (EMISSION_TRANSFORM * vec4(local, 1.0)).xyz;
	CUSTOM = vec4(birth, 0.0);                        // xyz = world birth, w = age
	TRANSFORM[3].xyz = birth;
	TRANSFORM[0].xyz = vec3(1.0, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, 1.0, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, 1.0);
	VELOCITY = vec3(0.0);
	COLOR = vec4(1.0);
}

void process() {
	CUSTOM.w += DELTA;
	float age = CUSTOM.w;
	// Per-drop character, constant over the drop's life (derived from the particle index,
	// not stored — there is no spare CUSTOM channel and these are a few cheap hashes). A
	// real downpour is not a wall of identical ticks: heavier drops fall faster and streak
	// longer, and drops vary in brightness. This variation is what stops the sheet reading
	// as a repeating screen-door pattern.
	uint vs = (NUMBER + uint(7)) * uint(2654435761);
	// One shared "calibre" per drop drives length, width, fall speed AND brightness together,
	// so each streak reads as a coherent drop: a fat near drop is long, wide, fast and bright;
	// a fine far drop is short, thin, slow and faint. The old code drew length / opacity / speed
	// as three INDEPENDENT randoms, which contradicted the note above ("heavier drops fall faster
	// and streak longer") and let a stubby drop fall fast or a long drop crawl. A small extra
	// jitter keeps opacity from locking rigidly to size. Two hashes now instead of three — the
	// per-drop character is a touch cheaper to derive, with no loss of visible variety.
	float m = rnd01(vs);                       // 0..1  drop calibre (drizzle .. fat drop)
	float jitter = rnd01(vs);                  // 0..1  independent opacity flicker
	float v_len = 0.72 + 0.70 * m;             // 0.72 .. 1.42  streak length
	float v_wid = 0.86 + 0.40 * m;             // 0.86 .. 1.26  streak width (calibre)
	float v_spd = 0.84 + 0.34 * m;             // 0.84 .. 1.18  fall speed (mass)
	float v_a = 0.50 + 0.36 * m + 0.14 * jitter; // 0.50 .. 1.00  opacity (mostly calibre)
	vec3 pos = CUSTOM.xyz + wind_drift * age;
	pos.y -= fall_speed * v_spd * age;
	TRANSFORM[3].xyz = pos;
	VELOCITY = vec3(0.0);

	// Scale the drop to zero (invisible) whenever it is inside a covered volume.
	float vis = 1.0;
	for (int k = 0; k < 48; k++) {
		if (k >= box_count) { break; }
		vec3 q = pos;
		float ya = box_yaw[k];
		if (abs(ya) > 0.0001) {
			vec3 bc = (box_min[k] + box_max[k]) * 0.5;
			float cs = cos(-ya);
			float sn = sin(-ya);
			vec2 d = pos.xz - bc.xz;
			q.xz = vec2(d.x * cs - d.y * sn, d.x * sn + d.y * cs) + bc.xz;
		}
		if (all(greaterThanEqual(q, box_min[k])) && all(lessThanEqual(q, box_max[k]))) {
			vis = 0.0;
			break;
		}
	}
	// X/Z hold the drop's slender width (now per-drop, via v_wid); Y carries the streak length.
	// billboard_keep_scale preserves these, so longer/wider drops read as heavier, faster rain.
	//
	// The drop's CROSS-SECTION SHAPE — a soft rounded head tapering to a fine tail, with rounded
	// rather than hard corners — cannot be produced from this file. A `shader_type particles`
	// shader has no fragment stage; it only writes this per-instance transform and colour. Each
	// drop's actual pixels come from the DRAW-PASS material — the untextured StandardMaterial3D
	// on the billboarded QuadMesh built in storm_system.gd::_build_rain — whose alpha is flat
	// across the whole quad, which is exactly why a drop renders as a hard-edged rectangle.
	// Rounding it is a draw-pass change (out of this shader's ownership): give that material a
	// drop-shaped alpha gradient (cf. mat_lib.soft_mote's radial GradientTexture, elongated and
	// tapered) or a tiny spatial fragment shader — smoothstep on UV.x for the cross-axis and on
	// UV.y for the head->tail falloff, matching the streak idiom already in start_screen.gd.
	TRANSFORM[0].xyz = vec3(vis * v_wid, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, vis * v_len, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, vis * v_wid);
	COLOR = vec4(1.0, 1.0, 1.0, vis * v_a);
}
