shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// A FISH FOR THE SEVEN UNTEXTURED MESHES.
//
// s15 left seven species as Meshy PREVIEW meshes: correct geometry, glTF primitives with
// NO material node at all (verified by parsing the GLBs — 0 materials, 0 textures, 0
// images; POSITION/NORMAL/TEXCOORD_0 and no COLOR_0). fish_model_lib._skin() covered that
// by writing one flat albedo, which stopped them rendering chalk-white and produced the
// owner's report instead: "it shouldnt be just 1 color".
//
// WHY THE COUNTERSHADE IS DRIVEN OFF THE WORLD NORMAL AND NOT A BODY AXIS.
// The obvious build is a gradient along the mesh's dorsoventral axis. Measured, the seven
// do not agree on which axis that is: pollock/garfish/wrasse/mackerel are width-X and
// depth-Z, pipefish/dogfish are the other way round, and the anchor ray is dorsoventrally
// FLATTENED so its thinnest axis is the one the others use for width. Worse, nothing in
// the geometry says which END of that axis is the back — a sign error paints a pale spine
// and a dark belly, which reads as a dead fish. World up has neither problem and is right
// in the hand, on the deck, and on the drying line without a per-species table.
//
// Three cues, in order of how much work they do:
//   countershading — dark back, pale belly. The single strongest "this is a fish" signal.
//   mottle         — body-locked value noise, so the break-up sticks to the animal rather
//                    than swimming over it as the fish turns.
//   sheen          — a fresnel rim, because a wet fish is silver at grazing angles.

uniform vec3 base_tint : source_color = vec3(0.5, 0.5, 0.5);
uniform float back_dark  = 0.45;   // how far the dorsal side crushes toward black
uniform float belly_pale = 0.85;   // how far the ventral side lifts toward white
uniform float mottle_amt = 0.18;   // albedo swing from the noise
uniform float mottle_freq = 5.5;   // patches per body length
uniform float sheen = 0.35;        // fresnel rim strength
uniform float sear = 0.0;          // 0 raw, 1 cooked (see fish_model_lib._char)

varying vec3 body_pos;

void vertex() {
	body_pos = VERTEX;
}

// -- cheap 3D value noise ------------------------------------------------------
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = mix(
		mix(mix(hash13(i + vec3(0, 0, 0)), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
	return n;
}

void fragment() {
	// NORMAL is view space; INV_VIEW_MATRIX takes it back to world so "up" is really up.
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// -- countershading ---------------------------------------------------------
	// Biased so the transition sits a little below the equator: real fish carry the dark
	// well down the flank and the pale is a narrow belly, not a bottom half.
	float up = smoothstep(-0.55, 0.45, wn.y);
	vec3 back  = base_tint * back_dark;
	vec3 belly = mix(base_tint, vec3(1.0), belly_pale);
	vec3 col = mix(belly, back, up);

	// -- mottle -----------------------------------------------------------------
	// Two octaves: broad blotches plus a finer speckle that reads as scale.
	float n = vnoise(body_pos * mottle_freq) * 0.66
			+ vnoise(body_pos * mottle_freq * 2.7) * 0.34;
	col *= 1.0 + (n - 0.5) * 2.0 * mottle_amt;

	// A darker saddle band along the back only — mottle is mostly a dorsal feature.
	col *= 1.0 - up * (n - 0.5) * 0.35;

	// -- searing ----------------------------------------------------------------
	// Cooked crushes to a char grey-brown and flattens the countershade, because a fish
	// off the pan is browned all over. Same crush factors _char() uses on textured fish.
	col = mix(col, vec3(dot(col, vec3(0.34, 0.32, 0.28))) * vec3(0.42, 0.34, 0.28), sear);

	ALBEDO = col;

	// Wet, not glossy: the belly is smoother than the back, and cooking dulls both.
	ROUGHNESS = mix(mix(0.42, 0.62, up), 0.88, sear);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.18, sear);

	// -- sheen ------------------------------------------------------------------
	// Fresnel rim, killed by searing. This is what stops a matte body reading as clay.
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.2);
	RIM = sheen * (1.0 - sear);
	RIM_TINT = 0.35;
	ALBEDO += vec3(fres * sheen * 0.22 * (1.0 - sear));
}
