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
uniform vec3 box_min[24];                            // covered-volume AABBs (world space)
uniform vec3 box_max[24];
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
	float v_len = 0.68 + 0.72 * rnd01(vs);     // 0.68 .. 1.40  streak length
	float v_a = 0.45 + 0.55 * rnd01(vs);       // 0.45 .. 1.00  opacity
	float v_spd = 0.84 + 0.34 * rnd01(vs);     // 0.84 .. 1.18  fall speed (drop mass)
	vec3 pos = CUSTOM.xyz + wind_drift * age;
	pos.y -= fall_speed * v_spd * age;
	TRANSFORM[3].xyz = pos;
	VELOCITY = vec3(0.0);

	// Scale the drop to zero (invisible) whenever it is inside a covered volume.
	float vis = 1.0;
	for (int k = 0; k < 24; k++) {
		if (k >= box_count) { break; }
		if (all(greaterThanEqual(pos, box_min[k])) && all(lessThanEqual(pos, box_max[k]))) {
			vis = 0.0;
			break;
		}
	}
	// X/Z hold the drop's slender width; Y carries the per-drop streak length. billboard
	// mode keeps these scales (billboard_keep_scale), so longer drops read as faster rain.
	TRANSFORM[0].xyz = vec3(vis, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, vis * v_len, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, vis);
	COLOR = vec4(1.0, 1.0, 1.0, vis * v_a);
}
