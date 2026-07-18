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

// --- imported PBR surface -------------------------------------------------------
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform sampler2D normal_tex : hint_normal;
uniform bool use_normal = false;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.6;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.0;

// --- motion ---------------------------------------------------------------------
// 0 undulate (fish/eel/shark)  1 wing flap (ray)  2 bell pulse (jelly)  3 fast flap (bird)
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
	if (glow_energy > 0.001) {
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
		EMISSION = glow_color.rgb * glow_energy * rim;
	}
}
