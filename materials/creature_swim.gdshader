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

// --- motion ---------------------------------------------------------------------
// 0 undulate (fish/eel/shark)  1 wing flap (ray)  2 bell pulse (jelly)  3 fast flap (bird)
// 4 legged gait (crab)  5 pedal wave (snails)  6 cirral beat (barnacles)  7 resting swell
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
	}
	VERTEX = p;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * tint;
	ALBEDO = a.rgb;
	ROUGHNESS = roughness_v;
	METALLIC = metallic_v;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	// Fresnel rim: the Bloom reads as light coming off the edges of the animal.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	if (glow_energy > 0.001) {
		EMISSION = glow_color.rgb * glow_energy * rim;
	}
	// OPAQUE base shader: ALPHA is never written, so every creature sharing this shader
	// (crab, gulls, jelly, lamp/rust snails, flora…) renders solid — no transparent pass,
	// no see-through back-faces under cull_disabled. The one species that must read as
	// glass, the glass snail, swaps its surfaces to creature_swim_glass.gdshader (identical
	// motion + PBR, but with depth_prepass_alpha and the alpha thin-out). See GlassSnail.
}
