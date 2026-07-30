shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Vertex-displacement creature motion for STATIC AI-generated meshes.
//
// Meshy (and most text-to-3D services) only auto-rig HUMANOIDS — they run bipedal pose
// estimation and hard-fail on a crab or a whale. So instead of a Skeleton3D, the swim /
// flap / pulse lives here in the vertex stage: cheap, never fights the movement code,
// and driven by the same state machine through `rate` and `amp`.
//
// It re-implements the imported PBR surface (albedo/normal/roughness) so the generated
// textures survive, and adds a fresnel rim glow for the Bloom's bioluminescence.

const float TAU_ = 6.28318530718;
const float PI_ = 3.14159265359;

// --- imported PBR surface -------------------------------------------------------
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform sampler2D normal_tex : hint_normal;
uniform bool use_normal = false;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.6;
// Honored ONLY by the transparent variant creature_swim_glass.gdshader. This base shader
// is OPAQUE and never writes ALPHA, so the uniform does nothing here — it stays declared
// only so CreatureAnim.apply() can push it onto every creature without a missing-param.
// A lamp/rust snail (opacity left at its 1.0 default) therefore renders fully solid; the
// glass snail is the one species that swaps to the glass shader to become see-through.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.0;
// THE metallicRoughness MAP, and the reason it has to be here (s23, measured).
// Godot's glTF importer writes metallicFactor/roughnessFactor into the SCALARS and puts the
// real per-texel values in a TEXTURE. Every Tripo-era asset in this repo ships
// metallicFactor = roughnessFactor = 1.0 — pyramid_snail, herring_gull, ultra_hammerhead,
// all ten trop_*, five deep fish — so a shader that reads only the scalars renders those
// thirteen species as FULLY METALLIC, and a metal with no reflection probe under it is
// black. That is the owner's "the snail is far darker in game than the model is": the model
// viewer samples this map, the shader did not. `orm_rough_mask` / `orm_metal_mask` pick the
// channel off the live material rather than assuming glTF's G/B, so an import that changes
// its mind cannot silently go dark again. use_orm stays false for the older Meshy assets,
// which carry no map and honest 0.0/0.8 scalars — those are byte-identical to before.
uniform sampler2D orm_tex : hint_default_white;
uniform bool use_orm = false;
uniform vec4 orm_rough_mask = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 orm_metal_mask = vec4(0.0, 0.0, 1.0, 0.0);
// Flat self-lighting keyed to the albedo, energy units. 0.0 = off, which is what every
// species that does not ask for it gets. The Bloom's animals are lit by an environment
// that reaches almost none of them (a caisson face at y -15 has no direct light at all),
// so a species that must read at depth gets a little of its own colour back rather than a
// brighter albedo — the same trick reef_fish.gdshader uses, at a gentler exponent.
uniform float body_glow = 0.0;

// --- motion ---------------------------------------------------------------------
// 0 undulate (fish/eel/shark)  1 wing flap (ray)  2 bell pulse (jelly)  3 fast flap (bird)
// 4 legged gait (crab)  5 pedal wave (snails)  6 cirral beat (barnacles)  7 resting swell
// 8 flora sway  9 lobed-fin scull (coelacanth)
uniform int mode = 0;
uniform float amp = 0.06;        // displacement amplitude, local units
uniform float wave_len = 1.6;    // wavelength of the travelling wave along the body
uniform float rate = 2.0;        // cycles per second — drive this from real speed
uniform float phase = 0.0;       // per-instance offset so a school isn't in lockstep
uniform vec3 bounds_min = vec3(-1.0);
uniform vec3 bounds_size = vec3(2.0);
// Authored orientation (set by CreatureAnim.attach from the FACING table). Meshy models
// face the VIEWER (+Z), Godot's forward is -Z — so the node gets yawed 180 and these two
// tell the shader where the head actually is so the wave still runs head -> tail.
uniform int flow_axis = 0;       // 0: body runs along local Z   1: along local X
uniform float flow_flip = 0.0;   // 0: head at min end           1: head at max end
// Which local axis a WING/FLAP beat lifts along. Y for everything authored lying down;
// the mantle ray was authored standing on its tail, so its dorsal-ventral axis — the one
// wings actually beat along — is local Z, and a beat written to Y would shear its wingtips
// fore-and-aft along the body instead of flapping them.
uniform int lift_axis = 0;       // 0: beat along local Y        1: along local Z

// --- bioluminescence ------------------------------------------------------------
uniform vec4 glow_color : source_color = vec4(0.25, 0.95, 0.88, 1.0);
uniform float glow_energy = 0.0;
uniform float rim_power : hint_range(1.0, 8.0) = 3.0;

void vertex() {
	vec3 p = VERTEX;
	vec3 n = (p - bounds_min) / max(bounds_size, vec3(0.0001));  // 0..1 along each axis
	float t = TIME * rate + phase;
	// Body coordinates that respect authored orientation: `along` runs 0 at the HEAD to
	// 1 at the tail whichever way the mesh was authored; `across` spans the body.
	float along_raw = (flow_axis == 0) ? n.z : n.x;
	float along = mix(along_raw, 1.0 - along_raw, flow_flip);
	float across = (flow_axis == 0) ? n.x : n.z;

	if (mode == 0) {
		// Fish / eel / shark: lateral wave travelling head -> tail. The quadratic ramp
		// keeps the head steady and puts the swing in the tail, like a real body wave.
		float ramp = along * along;
		float d = sin(t * TAU_ - along * TAU_ / max(wave_len, 0.01)) * amp * ramp;
		if (flow_axis == 0) { p.x += d; } else { p.z += d; }
	} else if (mode == 1) {
		// Ray: wings beat vertically, amplitude growing toward the tips.
		float lat = clamp(abs(across - 0.5) * 2.0, 0.0, 1.0);
		float beat = sin(t * TAU_ - lat * 1.4) * amp * lat * lat;
		if (lift_axis == 0) { p.y += beat; } else { p.z += beat; }
	} else if (mode == 2) {
		// Jelly: the bell squashes and the skirt flares — a swimming pulse.
		float pulse = sin(t * TAU_);
		float h = clamp(n.y, 0.0, 1.0);
		p.y += pulse * amp * h;
		p.xz *= 1.0 + pulse * amp * 0.5 * (1.0 - h);
	} else if (mode == 3) {
		// Bird: fast wingbeat.
		float lat = clamp(abs(across - 0.5) * 2.0, 0.0, 1.0);
		float wb = sin(t * TAU_ * 2.0) * amp * lat * lat;
		if (lift_axis == 0) { p.y += wb; } else { p.z += wb; }
	} else if (mode == 4) {
		// LEGGED GAIT (crab). There are no bones, so "legs" get found geometrically:
		// geometry that sits low in the body AND out to the side. Each one steps on a
		// phase taken from where it sits along the body, which reproduces the metachronal
		// wave an arthropod actually walks with — a sequence running back to front, the
		// two sides half a cycle apart — instead of eight limbs pumping in unison.
		float side = across - 0.5;
		float lat = clamp(abs(side) * 2.0, 0.0, 1.0);    // 0 at the spine, 1 at the tips
		float low = 1.0 - clamp(n.y * 2.2, 0.0, 1.0);    // 1 at the feet, 0 at the shell
		float legness = lat * low;                       // only outer LOW geometry walks
		float seq = along * 2.2 + (side > 0.0 ? PI_ : 0.0);
		float c = t * TAU_ + seq;
		p.y += max(sin(c), 0.0) * amp * legness * 3.0;   // lift on the up-beat only...
		float sw = cos(c) * amp * legness * 1.6;         // ...and swing through the step
		if (flow_axis == 0) { p.z += sw; } else { p.x += sw; }
		p.y += sin(t * TAU_ * 2.0) * amp * 0.25 * (1.0 - low);   // carapace rocks on it
	} else if (mode == 5) {
		// GASTROPOD PEDAL WAVE. A snail does not slide — it squeezes muscular ripples
		// along the sole of its foot, back to front, and rides them. Only the foot
		// participates; the shell just gets carried.
		float foot = 1.0 - clamp(n.y * 3.0, 0.0, 1.0);
		// The wave travels tail -> head (+along phase): direct pedal waves, the kind
		// that push a snail forward.
		float wave = sin(t * TAU_ + along * TAU_ * 1.6);
		p.y += wave * amp * foot;
		float fw = wave * amp * 0.4 * foot;
		if (flow_axis == 0) { p.z += fw; } else { p.x += fw; }
		p.y += sin(t * TAU_) * amp * 0.15 * (1.0 - foot);
	} else if (mode == 6) {
		// BARNACLE CIRRAL BEAT: the feathery legs rake out through the water to strain
		// it, then fold back. Fast out and slow in — that asymmetry is the whole reason
		// it reads as feeding rather than as a wobble.
		float crown = clamp(n.y, 0.0, 1.0);
		crown *= crown;                                   // the apertures, not the base
		float c = sin(t * TAU_);
		float sweep = sign(c) * pow(abs(c), 0.55);        // sharpened reach, easy return
		p.y += sweep * amp * crown;
		vec2 out_dir = vec2(n.x - 0.5, n.z - 0.5);
		if (length(out_dir) > 0.001) {
			p.xz += normalize(out_dir) * sweep * amp * 0.5 * crown;
		}
	} else if (mode == 8) {
		// FLORA SWAY: anchored at the holdfast (n.y = 0), drift grows with height^2.
		// Two incommensurate frequencies so it wanders like current, never a metronome.
		float h = n.y * n.y;
		p.x += (sin(t * TAU_ * 0.35) + 0.45 * sin(t * TAU_ * 0.83 + 1.7)) * amp * h;
		p.z += (cos(t * TAU_ * 0.27 + 0.6) + 0.4 * sin(t * TAU_ * 0.71)) * amp * h * 0.8;
	} else if (mode == 7) {
		// RESTING SWELL — alive, but not going anywhere. Scales about the body centre so
		// a mesh whose pivot sits at its foot doesn't pump itself through the floor.
		vec3 mid = bounds_min + bounds_size * 0.5;
		float s = sin(t * TAU_) * amp;
		p = mid + (p - mid) * (1.0 + s * 0.5);
		p.y += s * 0.3;
	} else if (mode == 9) {
		// LOBED-FIN SCULL — the coelacanth (owner's brief, 2026-07-26: "a very distinctive
		// slow, sculling, almost hovering swim with paired lobed fins that move alternately,
		// like a slow four-legged walk through water"). Mode 0 is wrong for this animal in
		// two ways at once: it bends the WHOLE body like a cod, and it has nothing to say
		// about the four fins, which on a coelacanth are the part everybody recognises.
		// Three effects, layered:
		float side = across - 0.5;
		float lat = clamp(abs(side) * 2.0, 0.0, 1.0);   // 0 at the spine, 1 at the fin tips

		// 1. THE TAIL SCULLS, THE BODY DOES NOT. A coelacanth is a stiff, heavily scaled
		// tube that holds its line and waves the trilobed caudal behind it. Hence a CUBIC
		// ramp instead of mode 0's quadratic (the front two thirds barely register) and a
		// long wavelength — 0.45 of a cycle over the whole body, so it carries less than
		// half a wave and never reads as an eel. Bigger throw than mode 0 (2.2x) because
		// the amplitude that is gone from the body has to show up in the tail or the animal
		// looks dead.
		float ramp = along * along * along;
		float d = sin(t * TAU_ - along * TAU_ * 0.45) * amp * ramp * 2.2;
		if (flow_axis == 0) { p.x += d; } else { p.z += d; }

		// 2. THE PAIRED LOBES ROW, IN DIAGONAL PAIRS. The pectorals and pelvics are limbs,
		// so they get found the same way the crab's legs do (mode 4): geometry that is
		// OUTBOARD and LOW. Both halves of that test are load-bearing. Outboard alone also
		// selects the sides of the HEAD — this mesh's skull is nearly as wide as the fin
		// span — and rowing the head is the one thing that would wreck the shot; low alone
		// takes the median anal fin, which should ride the tail wave, not row. Excluding
		// the first 0.2 of the body keeps the jaw out of it too, so effect 3 owns the head.
		float finness = smoothstep(0.35, 0.90, lat)
			* (1.0 - smoothstep(0.30, 0.55, n.y))
			* smoothstep(0.08, 0.20, along);
		// The gait. Half `rate`, because the row is a slow amble under a tail beating at
		// full speed — the two must NOT lock, or the animal reads as one rigid machine.
		// Phase from the side (the crab's PI flip, discontinuous only at the spine where
		// finness is already 0) plus phase from station along the body: at 2.6*PI the
		// pectorals (along ~0.22) and pelvics (~0.45) come out most of a half-cycle apart,
		// which is the contralateral tetrapod pattern — left-front with right-rear — and
		// the residual gradient inside one fin lets the blade trail its own lobe.
		float c = t * TAU_ * 0.5 + along * PI_ * 2.6 + (side > 0.0 ? PI_ : 0.0);
		p.y += sin(c) * amp * finness * 2.2;                  // the power stroke, vertical
		float row = cos(c) * amp * finness * 1.3;             // ...swung fore-and-aft
		if (flow_axis == 0) { p.z += row; } else { p.x += row; }

		// 3. BREATHING. No bones and no jaw joint, so this is not a hinge — it is a slow
		// swell of the low front of the skull, which on a closed mesh opens the mouth line
		// into a gape, plus an opercular flare a half-cycle later: mouth shuts, gill covers
		// lift. Deliberately slow (0.35x) and small (well under half the fin throw) because
		// the honest version of this is a suggestion of breathing, not an animated jaw.
		float breath = sin(t * TAU_ * 0.35);
		float jaw = (1.0 - smoothstep(0.02, 0.16, along)) * (1.0 - smoothstep(0.30, 0.55, n.y));
		p.y -= max(breath, 0.0) * amp * 0.5 * jaw;
		float oper = smoothstep(0.05, 0.13, along) * (1.0 - smoothstep(0.13, 0.26, along));
		float flare = max(-breath, 0.0) * amp * 0.35 * oper * lat;
		if (flow_axis == 0) { p.x += sign(side) * flare; } else { p.z += sign(side) * flare; }
	}
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
	// Fresnel rim: the Bloom reads as light coming off the edges of the animal.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	vec3 emis = vec3(0.0);
	if (body_glow > 0.001) {
		emis += a.rgb * sqrt(a.rgb) * body_glow;
	}
	if (glow_energy > 0.001) {
		emis += glow_color.rgb * glow_energy * rim;
	}
	if (body_glow > 0.001 || glow_energy > 0.001) {
		EMISSION = emis;
	}
	// OPAQUE base shader: ALPHA is never written, so every creature sharing this shader
	// (crab, gulls, jelly, lamp/rust snails, flora…) renders solid — no transparent pass,
	// no see-through back-faces under cull_disabled. The one species that must read as
	// glass, the glass snail, swaps its surfaces to creature_swim_glass.gdshader (identical
	// motion + PBR, but with depth_prepass_alpha and the alpha thin-out). See GlassSnail.
}
