shader_type spatial;
// cull_disabled because every mesh this shader is used on is glTF `doubleSided: true` — the
// flora are blades and vines, and back-face culling deletes half of every frond. It is also
// the reason coral_fan_a is NOT on this shader (see the note on it in leg_reef.gd): that one
// is a solid lattice with culling on, and a `cull_back` copy of this file is what it wants.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// VERTEX-DISPLACEMENT SWAY FOR THE REEF'S MULTIMESH FLORA.
//
// Nothing on the reef has ever moved. `creature_swim.gdshader` is the house pattern for
// this (mode 8 is literally called FLORA SWAY) but it cannot be used here: it is a
// per-NODE shader that CreatureAnim.attach() hangs on one animal at a time, keyed by
// `bounds_min`/`bounds_size` and a `phase` uniform pushed per instance. The reef is 70+
// MultiMeshes — one material for hundreds of plants — so the phase has to be derived
// inside the shader or every plant in a stand sways in lockstep like one flag.
//
// WHAT IS DIFFERENT FROM creature_swim, AND WHY
//   * PER-INSTANCE PHASE from INSTANCE_ID *and* the instance's world position (see
//     `phase` below). Two sources because they fail differently and fix different things.
//   * ANCHORED AT THE BASE. tools/decimate_reef.py bakes the contract "+Y is growth, base
//     at y = 0", so the height fraction is just VERTEX.y / mesh_h and h^2 pins the
//     holdfast: at the base the displacement is identically zero, so a plant physically
//     cannot detach from the concrete it was raycast onto.
//     s36: THE ANCHOR IS IN MESH LOCAL SPACE, SO TILTING AN INSTANCE CANNOT MOVE IT — the
//     question the owner asked is the next one along, "is the holdfast still where the plant
//     meets the wall". It is, and by more than it was. leg_reef now seats a rooted plant with
//     its cross-axis columns IN THE WALL PLANE (see _add), so a vertex's distance out of the
//     concrete is a function of local Y ALONE and the wall cuts every plant at one height:
//     the recess bite, ~6-10% of the stem. The old rigid tilt cut the mesh diagonally and on
//     a 1.80 m sea grass at 56 deg the up-slope side emerged 56.5% of the way up, where this
//     shader is already moving it 63.7 mm. leg_reef prints both numbers every build.
//   * SWAYS ALONG THE WORLD CURRENT, not along a local axis. leg_reef seats every piece
//     with a RANDOM roll about its growth axis, so a fixed local sway direction would be
//     a random world direction per plant and the stand would read as noise rather than as
//     a current. The set is pulled back into local space by the model matrix (3 dots).
//   * NON-UNIFORM SCALE IS HANDLED IN BOTH DIRECTIONS. A kelp strand here is a sea-grass
//     mesh stretched 1.9x tall and 0.5x wide by its instance transform; that skews the
//     normals (Godot uses mat3(MODEL_MATRIX), not its inverse transpose) and it would
//     shrink the sway in exactly the axis the plant is thinnest in. Both are corrected.
//     s36: AND SO IS SHEAR. A rooted plant's instance basis is no longer orthogonal — see
//     the block above `s2` for which of the reads below that changes and which it does not.
//
// *** THE `rate` TRAP (docs/AGENT_TRAPS.md). ***
// There is deliberately NO rate uniform. Every frequency below is a `const` inside the
// sin(), and the only knobs are AMPLITUDES, which are multipliers outside it. A tuning
// value multiplied by an accumulating clock inside a sine cannot be animated at all —
// writing a new value at second T teleports the wave phase — and this shader is the exact
// shape that invites that mistake (a storm wants stronger current). So the storm hook, if
// one is ever wired, is `sway_amp` / `lean`, and it can be driven every frame safely.

const float TAU_ = 6.28318530718;

// --- imported PBR surface (same contract as creature_swim: the generated maps survive) --
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform sampler2D normal_tex : hint_normal;
uniform bool use_normal = false;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.8;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.0;
// THE metallicRoughness MAP — see the s23 note in creature_swim.gdshader. Godot's glTF
// importer writes metallicFactor/roughnessFactor into the SCALARS (1.0 / 1.0 on every
// Tripo-era asset) and the real per-texel values into a TEXTURE, so a shader that reads
// only the scalars renders those pieces fully metallic, i.e. black under an environment
// with no reflection probe. The three flora meshes this shader was written for are honest
// (metallicFactor 0, roughnessFactor 0.8, no map) and leave `use_orm` false; the coral and
// sponge pieces are NOT, and this is what lets one of them take sway without going dark.
uniform sampler2D orm_tex : hint_default_white;
uniform bool use_orm = false;
uniform vec4 orm_rough_mask = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 orm_metal_mask = vec4(0.0, 0.0, 1.0, 0.0);

// --- the reef's bloom, reproduced exactly ------------------------------------------
// leg_reef gives every StandardMaterial3D piece `emission_texture = albedo_texture`,
// `emission = GLOW_TINT`, `emission_energy_multiplier = GLOW * species`. Godot's default
// emission operator is ADD, whose generated shader is `(emission + emission_tex) * energy`
// — so that is what is written here rather than a multiply. A species must not change
// brightness merely because it changed material class.
uniform vec4 glow_tint : source_color = vec4(0.94, 1.0, 0.99, 1.0);
uniform float glow_energy = 0.0;

// --- motion -------------------------------------------------------------------------
// The mesh's own height along its growth axis, local units — Mesh.get_aabb().size.y,
// pushed by leg_reef._load. NOT 1.0: these meshes are normalised to a 1 m LONGEST axis by
// the placement code's `norm`, not by the decimator, so local space is still the raw glTF
// size (bloom_sea_grass is 1.905 tall).
uniform float mesh_h = 1.0;
// Sway amplitude, and the units are worth stating exactly because they came out of the
// algebra rather than off a slider. The lateral displacement below is
//     (lean + w * sway_amp) * mesh_h * k * aniso
// in LOCAL units, and the instance transform then multiplies it by the local xz scale. Since
// aniso is (y scale / xz scale), the xz scale cancels and what reaches the screen is
//     (lean + w * sway_amp) * <the plant's own drawn world height>
// — so sway_amp is a pure fraction of height, independent of how far a strand is stretched.
// `w` is a two-sine sum peaking at 1.42, so PEAK-TO-PEAK TIP TRAVEL = 2.84 * sway_amp * h.
// 0.09 therefore moves a 7 m kelp tip through ~1.8 m, which is a current you can read from
// 20 m; a third of that is right for a 1 m wall plant. THIS is the animatable knob (see the
// rate trap above) — a storm spends itself here, never on a frequency.
uniform float sway_amp = 0.09;
// The steady downstream bend. A plant in a current is not vertical with a wobble on it —
// it is bent, and it wanders about the bend. Same units as sway_amp.
uniform float lean = 0.05;
// Prevailing set, WORLD space. leg_reef.CURRENT: the gyre eye is at (0,0,-52), so the
// water sets south past the rig and every stand leans the same way the colonies favour.
uniform vec3 current = vec3(0.0, 0.0, -1.0);

void vertex() {
	// PER-INSTANCE PHASE, from two sources because they do different jobs.
	// INSTANCE_ID hashed is the SCATTER — without it every plant sharing this material sways
	// in lockstep and the bed reads as one flag. It is deliberately not given the full turn:
	// at 0.55 of a cycle it decorrelates neighbours without swamping the second term.
	// The instance's WORLD POSITION is the DRIFT, and it is the part a counter cannot give —
	// 0.31 rad/m means two plants a metre apart are a sixth of a wave out of step, so the
	// motion reads as a swell passing THROUGH the stand rather than as 300 private wobbles.
	// It is also the insurance: if a backend ever hands this a constant INSTANCE_ID, the
	// field still varies instead of failing silently into lockstep.
	vec3 wp = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(float(INSTANCE_ID) * 12.9898 + dot(wp, vec3(0.113, 0.071, 0.149)))
		* 43758.5453) * TAU_ * 0.55;
	phase += dot(wp, vec3(0.31, 0.0, 0.27));

	// The model matrix' columns: orientation * scale.
	//
	// s36 — THEY ARE NO LONGER ALWAYS ORTHOGONAL, and this file used to assume they were.
	// leg_reef seats a ROOTED plant (the wall plants and the kelp) with its two cross-axis
	// columns lying in the WALL PLANE and only its +Y column on the diagonal, so the holdfast
	// stays flat on the concrete while the stem leans out of it. That is a shear: cx and cz
	// are still orthonormal to each other, but cy is up to the lean angle away from their
	// normal. Everything below that reads the columns has been checked against it:
	//   * s2 is still EXACTLY the squared scale — all three columns are built from unit
	//     vectors before scaled_local, sheared or not;
	//   * the current transform is still exact where it is used. cl.y is discarded, and cx/cz
	//     ARE orthonormal, so (cl.x, 0, cl.z) mapped back through the basis is precisely the
	//     projection of `current` onto the wall plane — which is where a plant on a wall can
	//     sway anyway;
	//   * the normal correction was the one that broke, and it is fixed properly below rather
	//     than approximated.
	vec3 cx = MODEL_MATRIX[0].xyz;
	vec3 cy = MODEL_MATRIX[1].xyz;
	vec3 cz = MODEL_MATRIX[2].xyz;
	vec3 s2 = max(vec3(dot(cx, cx), dot(cy, cy), dot(cz, cz)), vec3(1e-8));

	// The current, in this instance's local space, flattened onto the plane the plant
	// sways ACROSS. Dropping the growth-axis component matters: a plant leaning 40 deg off
	// a wall has a real component of the current running up its own length, and pumping
	// that would telescope the mesh instead of bending it.
	vec3 cl = vec3(dot(cx, current), dot(cy, current), dot(cz, current)) / s2;
	cl.y = 0.0;
	float cll = length(cl);
	vec3 down = (cll > 1e-4) ? cl / cll : vec3(1.0, 0.0, 0.0);
	vec3 side = vec3(-down.z, 0.0, down.x);

	// ANISOTROPY. A kelp strand is a sea-grass mesh at scale (0.5, 1.9, 0.5): a fixed
	// local displacement would come out five times smaller in world units than the same
	// displacement on an unstretched plant of the same drawn height. Sway is a property of
	// how TALL the plant is, so the lateral throw is divided back through the xz scale.
	float aniso = sqrt(s2.y) / sqrt(max(0.5 * (s2.x + s2.z), 1e-8));

	// Anchored at the holdfast and growing with height^2 — the quadratic is what keeps the
	// base rigid while the tip carries all the travel, the way a stipe actually bends.
	float h = clamp(VERTEX.y / max(mesh_h, 1e-4), 0.0, 1.0);
	float k = h * h;

	// Two incommensurate frequencies so it wanders like water rather than ticking like a
	// metronome, plus a slower cross-set component: the tip traces a lazy figure of eight,
	// which is what stops a stand of them looking like windscreen wipers.
	float w = sin(TIME * 0.63 + phase) + 0.42 * sin(TIME * 1.51 + phase * 1.7);
	float x = cos(TIME * 0.47 + phase * 0.8);

	vec3 p = VERTEX;
	p += down * ((lean + w * sway_amp) * mesh_h * k * aniso);
	p += side * (x * sway_amp * 0.55 * mesh_h * k * aniso);
	VERTEX = p;

	// NORMALS UNDER NON-UNIFORM SCALE *AND* SHEAR. Godot transforms normals with
	// mat3(MODEL_MATRIX), not its inverse transpose, so a (0.5, 1.9, 0.5) instance tilts every
	// normal toward vertical and the plant lights as though it were facing the surface. What
	// has to be written here is therefore (M^T M)^-1 * NORMAL: the engine's own M then turns
	// that into M^-T * NORMAL, which is the correct transform.
	//
	// This used to be written `NORMAL / s2`, which is (M^T M)^-1 ONLY when the columns are
	// mutually perpendicular — true of every coral here and false of a rooted plant, whose
	// +Y column is up to the lean angle off the plane of the other two. On a 45 deg plant the
	// worst case is a surface facing along its own stem, which lit as though it faced 45 deg
	// out of the wall. So the general form is used instead. It is three cross products and
	// four dots, it needs no inverse() builtin, and for a diagonal Gram it reduces ALGEBRAICALLY
	// to the old line — g0=(a,0,0), g1=(0,b,0), g2=(0,0,c) gives (bc*Nx, ca*Ny, ab*Nz)/abc,
	// i.e. NORMAL / s2 exactly — so nothing that was already right has changed.
	// The Gram matrix is scaled to put its largest entry at 1 before the adjugate is taken.
	// Its entries are squared world scales, so on a 0.35 m anemone (scale 0.18) the adjugate
	// would otherwise land around 1e-3 and its SQUARE around 1e-6 — under a mediump float's
	// smallest normal. The answer is only defined up to a positive factor anyway, because
	// normalize() removes it, so scaling costs nothing and takes the precision question away.
	float gs = 1.0 / max(max(s2.x, s2.y), s2.z);
	vec3 g0 = vec3(s2.x, dot(cx, cy), dot(cx, cz)) * gs;
	vec3 g1 = vec3(dot(cx, cy), s2.y, dot(cy, cz)) * gs;
	vec3 g2 = vec3(dot(cx, cz), dot(cy, cz), s2.z) * gs;
	vec3 a0 = cross(g1, g2);
	vec3 a1 = cross(g2, g0);
	vec3 a2 = cross(g0, g1);
	// the determinant is a POSITIVE scale factor — a Gram matrix is positive definite for any
	// basis that is not degenerate — and normalize() removes it, so it is never divided out.
	// The guard is for the degenerate case only: a zero-scale instance would otherwise hand
	// normalize() a zero vector, and this repo has spent 5.4 GB of stderr on a NaN before.
	vec3 nb = vec3(dot(a0, NORMAL), dot(a1, NORMAL), dot(a2, NORMAL));
	NORMAL = dot(nb, nb) > 1e-12 ? normalize(nb) : NORMAL;
	// The bend is not folded into the normal. It is a shear of at most ~20 deg at the tip
	// of a soft-lit plant 15 m under an opaque sea; the tangent-frame correction costs a
	// second displacement evaluation per vertex and would not be visible through the fog
	// grade. Recorded so the next person does not think it was missed.
}

void fragment() {
	// COLOR carries the MultiMesh per-instance colour (leg_reef sets `use_colors` and
	// tints every piece between the species' a/b pair). Reading it here is also what makes
	// the engine multiply the instance colour into it in the first place — the vertex
	// stage only does that when the shader declares COLOR used.
	vec4 a = texture(albedo_tex, UV) * tint * COLOR;
	ALBEDO = a.rgb;
	ROUGHNESS = roughness_v;
	METALLIC = metallic_v;
	if (use_orm) {
		vec4 orm = texture(orm_tex, UV);
		ROUGHNESS = roughness_v * dot(orm, orm_rough_mask);
		METALLIC = metallic_v * dot(orm, orm_metal_mask);
	}
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	if (glow_energy > 0.001) {
		EMISSION = (glow_tint.rgb + a.rgb) * glow_energy;
	}
}
