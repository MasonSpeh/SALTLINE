shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;
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
// 1.0 = solid (everyone). Below 1.0 turns the body see-through — see fragment().
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

// --- bioluminescence ------------------------------------------------------------
uniform vec4 glow_color : source_color = vec4(0.25, 0.95, 0.88, 1.0);
uniform float glow_energy = 0.0;
uniform float rim_power : hint_range(1.0, 8.0) = 3.0;

void vertex() {
	vec3 p = VERTEX;
	vec3 n = (p - bounds_min) / max(bounds_size, vec3(0.0001));  // 0..1 along each axis
	float t = TIME * rate + phase;

	if (mode == 0) {
		// Fish / eel / shark: lateral wave travelling head -> tail. The quadratic ramp
		// keeps the head steady and puts the swing in the tail, like a real body wave.
		float along = clamp(n.z, 0.0, 1.0);
		float ramp = along * along;
		p.x += sin(t * TAU_ - along * TAU_ / max(wave_len, 0.01)) * amp * ramp;
	} else if (mode == 1) {
		// Ray: wings beat vertically, amplitude growing toward the tips.
		float lat = clamp(abs(n.x - 0.5) * 2.0, 0.0, 1.0);
		p.y += sin(t * TAU_ - lat * 1.4) * amp * lat * lat;
	} else if (mode == 2) {
		// Jelly: the bell squashes and the skirt flares — a swimming pulse.
		float pulse = sin(t * TAU_);
		float h = clamp(n.y, 0.0, 1.0);
		p.y += pulse * amp * h;
		p.xz *= 1.0 + pulse * amp * 0.5 * (1.0 - h);
	} else if (mode == 3) {
		// Bird: fast wingbeat.
		float lat = clamp(abs(n.x - 0.5) * 2.0, 0.0, 1.0);
		p.y += sin(t * TAU_ * 2.0) * amp * lat * lat;
	} else if (mode == 4) {
		// LEGGED GAIT (crab). There are no bones, so "legs" get found geometrically:
		// geometry that sits low in the body AND out to the side. Each one steps on a
		// phase taken from where it sits along the body, which reproduces the metachronal
		// wave an arthropod actually walks with — a sequence running back to front, the
		// two sides half a cycle apart — instead of eight limbs pumping in unison.
		float side = n.x - 0.5;
		float lat = clamp(abs(side) * 2.0, 0.0, 1.0);    // 0 at the spine, 1 at the tips
		float low = 1.0 - clamp(n.y * 2.2, 0.0, 1.0);    // 1 at the feet, 0 at the shell
		float legness = lat * low;                       // only outer LOW geometry walks
		float seq = n.z * 2.2 + (side > 0.0 ? PI_ : 0.0);
		float c = t * TAU_ + seq;
		p.y += max(sin(c), 0.0) * amp * legness * 3.0;   // lift on the up-beat only...
		p.z += cos(c) * amp * legness * 1.6;             // ...and swing through the step
		p.y += sin(t * TAU_ * 2.0) * amp * 0.25 * (1.0 - low);   // carapace rocks on it
	} else if (mode == 5) {
		// GASTROPOD PEDAL WAVE. A snail does not slide — it squeezes muscular ripples
		// along the sole of its foot, back to front, and rides them. Only the foot
		// participates; the shell just gets carried.
		float foot = 1.0 - clamp(n.y * 3.0, 0.0, 1.0);
		float wave = sin(t * TAU_ - n.z * TAU_ * 1.6);
		p.y += wave * amp * foot;
		p.z += wave * amp * 0.4 * foot;
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
	// Translucency (glass snail, jellies). The generators bake OPAQUE albedo no matter
	// how hard the prompt asks for glass, so see-through has to happen here. Edges stay
	// solid and the face thins out — which is how real glass reads, and it lets the lit
	// organs inside the shell show through.
	if (opacity < 0.999) {
		ALPHA = mix(opacity, 1.0, rim);
	}
}
