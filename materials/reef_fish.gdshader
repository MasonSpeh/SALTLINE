shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// The tropical reef fish, and ONLY them (scripts/world/reef_fish.gd).
//
// WHY THIS EXISTS RATHER THAN JUST USING creature_swim.gdshader.
// It is that shader's mode-0 body wave — same maths, same uniform names, so CreatureAnim
// builds these materials and `drive()` keeps working — plus ONE addition that the reef fish
// cannot do without: BODY emission keyed to the albedo map.
//
// creature_swim emits a fresnel RIM only: `glow_color * glow_energy * pow(1 - N·V, 3)`. On a
// fish seen broadside that is ~0 everywhere except the silhouette edge, so a clownfish's
// bands, a blue tang's blue and an emperor angel's stripes all render as one dark shape.
// Measured by looking: at 5-20 m down underwater_fx's grade the first pass of these fish came
// back as small black specks against coral that was reading beautifully — because leg_reef
// gives the coral exactly this treatment (emission_texture = albedo_texture at 1.35 energy)
// and the fish had nothing. A reef fish that is not its colour is not a reef fish.
//
// It is a separate FILE rather than a mode or a uniform on creature_swim because that shader
// is shared by every animal in the game — crab, gulls, jelly, snails, sharks, flora — and a
// change there is a change to all of them, in files another session owns. Swapping the shader
// on 118 ShaderMaterials this file made itself costs nothing and risks nothing.

const float TAU_ = 6.28318530718;

// --- imported PBR surface (names match creature_swim so CreatureAnim.apply fills them) ---
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform sampler2D normal_tex : hint_normal;
uniform bool use_normal = false;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.6;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.0;
// The metallicRoughness map — see the long note in creature_swim.gdshader. All ten trop_*
// assets are Tripo-era and ship metallicFactor = roughnessFactor = 1.0, so before this the
// LIT half of every reef fish was a black mirror and the only thing you could see was the
// body_glow below. Names match creature_swim so the shader swap in reef_fish.gd still
// carries every parameter across.
uniform sampler2D orm_tex : hint_default_white;
uniform bool use_orm = false;
uniform vec4 orm_rough_mask = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 orm_metal_mask = vec4(0.0, 0.0, 1.0, 0.0);
// Declared but unused: this shader is OPAQUE, exactly like creature_swim. It stays so that
// CreatureAnim.apply can push its whole parameter set without a missing-uniform.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform int mode = 0;
uniform int lift_axis = 0;

// --- motion (creature_swim mode 0, unchanged) ---------------------------------------------
uniform float amp = 0.06;
uniform float wave_len = 1.6;
uniform float rate = 2.0;
uniform float phase = 0.0;
uniform vec3 bounds_min = vec3(-1.0);
uniform vec3 bounds_size = vec3(2.0);
uniform int flow_axis = 0;        // 0: body runs along local Z   1: along local X
uniform float flow_flip = 0.0;    // 0: head at min end           1: head at max end

// --- how the fish reads through the water -------------------------------------------------
// BODY: the albedo lit by itself. This is the one thing creature_swim does not have.
// DRIVEN AT 0.0 since the owner's 2026-08-06 no-glow call (reef_fish.gd writes BODY_GLOW
// onto every material it builds, so this default is only ever seen by a material nothing
// wrote). The mechanism stays because the flare plumbing does; the light is off.
uniform float body_glow : hint_range(0.0, 3.0) = 0.9;
// RIM: the Bloom edge light, in the species' own signature colour. Kept because the flare on
// a startled shoal is driven through it (reef_fish.gd pushes glow_energy up with `alarm`).
uniform vec4 glow_color : source_color = vec4(0.25, 0.95, 0.88, 1.0);
uniform float glow_energy = 0.0;
// Broader than creature_swim's 3.0: on a 22 cm fish a tight rim is a couple of pixels.
uniform float rim_power : hint_range(1.0, 8.0) = 2.0;

void vertex() {
	vec3 p = VERTEX;
	vec3 n = (p - bounds_min) / max(bounds_size, vec3(0.0001));
	float t = TIME * rate + phase;
	float along_raw = (flow_axis == 0) ? n.z : n.x;
	float along = mix(along_raw, 1.0 - along_raw, flow_flip);
	// Lateral wave travelling head -> tail. The quadratic ramp holds the head steady and puts
	// the swing in the tail, which is what a real body wave does.
	float ramp = along * along;
	float d = sin(t * TAU_ - along * TAU_ / max(wave_len, 0.01)) * amp * ramp;
	if (flow_axis == 0) { p.x += d; } else { p.z += d; }
	VERTEX = p;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * tint;
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
	// The fish's own colour, self-lit, so the pattern survives the depth grade. The exponent is
	// the whole tuning: LINEAR (what leg_reef's coral gets) washes the animal into one pale
	// blob and loses the pattern, and SQUARED left the mid-tones so dark that a shoal of
	// anthias read as grey flecks against coral that was emitting linearly at 1.35. 1.5 keeps
	// the bright markings — a clownfish's white bands, a tang's yellow tail — carrying the
	// read, while the fish still sits just under the reef it lives on. Judged by looking.
	vec3 body = a.rgb * sqrt(a.rgb) * body_glow;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = body + glow_color.rgb * glow_energy * rim;
}
