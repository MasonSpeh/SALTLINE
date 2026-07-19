shader_type spatial;
// Full-sky dome shader (was a lattice star field welded to the camera).
// Runs on the existing 1600m star dome in main.gd — draws the ENTIRE sky:
// atmosphere gradient + sun/moon + a proper star field with a magnitude
// distribution, temperature colour, per-star twinkle, atmospheric extinction,
// a structured Milky Way, and drifting high haze/cloud. World-space by
// construction (direction comes from the mesh vertex, not view space), so the
// sky no longer turns with the player's head.
//
// gl_compatibility only: no compute, no depth-texture tricks. `fog_disabled`
// keeps the dome crisp; the shader matches the scene fog at the horizon itself
// (horizon_tint) so the dome meets the sea without a seam.
render_mode unshaded, cull_front, fog_disabled, shadows_disabled, ambient_light_disabled;

// --- driven by SunController (scripts/world/sun_controller.gd) ---
uniform vec3 sun_dir = vec3(0.0, 0.30, 1.0);    // WORLD direction TOWARD the sun
uniform vec3 moon_dir = vec3(0.0, 0.50, -0.8);  // WORLD direction TOWARD the moon
uniform float night_amount : hint_range(0.0, 1.0) = 1.0;  // 0 full day .. 1 full night
uniform float sun_height : hint_range(-1.0, 1.0) = 0.3;   // sin(sun elevation)
uniform float storm : hint_range(0.0, 1.0) = 0.0;         // 0 clear .. 1 squall
uniform float moon_bright : hint_range(0.0, 1.0) = 1.0;   // moon disc visibility
uniform vec3 horizon_tint = vec3(0.08, 0.10, 0.14);       // scene fog colour at the horizon
uniform float star_gain : hint_range(0.0, 3.0) = 1.0;
uniform float sky_spin_rate = 0.0035;   // celestial rotation, rad/s (subtle wheeling)

varying vec3 world_dir;

// ---------- hashing (sin-free: robust on Metal / Apple Silicon) ----------
vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// ---------- value noise + fbm ----------
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}
float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// ---------- Rodrigues rotation (const args fold at compile) ----------
mat3 rot(vec3 ax, float a) {
	ax = normalize(ax);
	float c = cos(a);
	float s = sin(a);
	float ic = 1.0 - c;
	return mat3(
		vec3(c + ax.x * ax.x * ic, ax.x * ax.y * ic - ax.z * s, ax.x * ax.z * ic + ax.y * s),
		vec3(ax.y * ax.x * ic + ax.z * s, c + ax.y * ax.y * ic, ax.y * ax.z * ic - ax.x * s),
		vec3(ax.z * ax.x * ic - ax.y * s, ax.z * ax.y * ic + ax.x * s, c + ax.z * ax.z * ic));
}

// ---------- star temperature -> colour (mostly white, tails blue & amber) ----------
vec3 star_color(float t) {
	vec3 blue = vec3(0.72, 0.82, 1.0);
	vec3 white = vec3(1.0, 1.0, 1.0);
	vec3 amber = vec3(1.0, 0.80, 0.62);
	vec3 red = vec3(1.0, 0.66, 0.52);
	if (t < 0.16) {
		return mix(blue, white, t / 0.16);
	} else if (t < 0.84) {
		return white;
	} else if (t < 0.95) {
		return mix(white, amber, (t - 0.84) / 0.11);
	}
	return mix(amber, red, (t - 0.95) / 0.05);
}

// One star layer. Single-cell lookup with in-cell jitter (the star never crosses
// a cell edge, so no 3x3x3 scan needed and no lattice tell), power-law magnitude,
// per-star twinkle, soft halo for bright ones. Returns colour*luminance.
vec3 star_layer(vec3 sd, float scale, float density, float bpow,
		float radius, float halo_mul, float seed, float tw_amp, float t) {
	vec3 gp = sd * scale;
	vec3 cell = floor(gp);
	vec3 h = hash33(cell + vec3(seed));
	if (h.x < 1.0 - density) {
		return vec3(0.0);
	}
	vec3 f = fract(gp) - 0.5;
	vec3 center = (h - 0.5) * 0.6;               // jitter, kept clear of the edges
	float d = length(f - center);
	float mag = pow(hash13(cell + vec3(seed + 7.31)), bpow);   // power-law brightness
	float core = smoothstep(radius, 0.0, d);
	float halo = smoothstep(radius * 5.0, 0.0, d) * halo_mul;
	float tw = 1.0 - tw_amp + tw_amp * sin(t * (1.5 + h.z * 4.0) + h.y * 6.2831);
	float lum = (core + halo) * mag * tw;
	return star_color(hash13(cell + vec3(seed + 19.13))) * lum;
}

void vertex() {
	// Dome is centred at model origin -> the vertex ray IS the world sky direction.
	world_dir = (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz;
}

void fragment() {
	vec3 dir = normalize(world_dir);
	float elev = dir.y;                          // sin(elevation): -1 down .. 1 up

	// ---- atmospheric airmass (Kasten & Young) + wavelength extinction ----
	float alt = asin(clamp(elev, -1.0, 1.0));
	float altd = degrees(max(alt, 0.0));
	float airmass = 1.0 / (sin(max(alt, 0.0)) + 0.50572 * pow(altd + 6.07995, -1.6364));
	// blue is scattered out faster -> stars dim AND redden toward the horizon
	vec3 ext = exp(-airmass * vec3(0.013, 0.023, 0.042));
	float tw_amp = 0.14 + 0.42 * clamp((airmass - 1.0) / 8.0, 0.0, 1.0);  // scintillation grows near horizon

	// ---- celestial rotation: the whole star field wheels slowly ----
	vec3 cdir = rot(normalize(vec3(0.15, 0.72, 0.68)), TIME * sky_spin_rate) * dir;

	// ---- star field: bright/sparse -> faint/dense, each layer rotated so no grid aligns ----
	vec3 s0 = rot(vec3(0.2, 0.9, 0.35), 0.7) * cdir;
	vec3 s1 = rot(vec3(0.8, 0.1, 0.55), 1.9) * cdir;
	vec3 s2 = rot(vec3(0.45, 0.4, 0.8), 3.1) * cdir;
	vec3 s3 = rot(vec3(0.6, 0.75, 0.2), 4.4) * cdir;
	vec3 stars = vec3(0.0);
	stars += star_layer(s0, 40.0, 0.05, 7.0, 0.16, 0.30, 3.0, tw_amp, TIME) * 3.2;   // rare, bright, blooms
	stars += star_layer(s1, 105.0, 0.09, 5.0, 0.13, 0.14, 17.0, tw_amp, TIME) * 1.5; // medium
	stars += star_layer(s2, 250.0, 0.13, 4.0, 0.11, 0.05, 41.0, tw_amp, TIME) * 0.85;// faint dust
	stars += star_layer(s3, 520.0, 0.16, 3.5, 0.10, 0.0, 71.0, tw_amp, TIME) * 0.5;  // faintest grain

	// ---- Milky Way: off-axis great circle, fbm clouds, dark dust lanes, granular cores ----
	float gb = dot(cdir, normalize(vec3(0.42, 0.34, 0.84)));   // distance from galactic plane
	float band = smoothstep(0.34, 0.0, abs(gb));
	float mw_cloud = fbm(cdir * 4.5 + 5.0);
	float mw_rift = fbm(cdir * 7.0 + 21.0);
	float mw_gran = fbm(cdir * 26.0);
	float mw = band * (0.35 + 0.75 * mw_cloud);
	mw *= smoothstep(0.62, 0.28, mw_rift);        // dark rifts cut through the band
	mw += band * band * mw_gran * 0.35;           // star-cloud grain
	vec3 mw_col = mix(vec3(0.55, 0.62, 0.82), vec3(0.86, 0.80, 0.70), mw_cloud);
	vec3 milky = mw_col * max(mw, 0.0) * 0.16;

	// ---- night sky base: deep blue, faint airglow lift at the horizon ----
	vec3 night_zen = vec3(0.006, 0.013, 0.032);
	vec3 night_hor = vec3(0.018, 0.032, 0.058);
	vec3 night_sky = mix(night_hor, night_zen, smoothstep(0.0, 0.4, elev));
	// the moon washes the sky a little around it
	float mdot = max(dot(dir, moon_dir), 0.0);
	night_sky += vec3(0.05, 0.06, 0.09) * pow(mdot, 3.0) * moon_bright;

	// ---- day sky: zenith blue -> pale horizon haze, warm scatter toward a low sun ----
	float g = pow(clamp(1.0 - elev, 0.0, 1.0), 1.25);
	vec3 day_zen = vec3(0.10, 0.26, 0.60);
	vec3 day_hor = vec3(0.60, 0.71, 0.82);
	vec3 day_sky = mix(day_zen, day_hor, g);
	float low = 1.0 - clamp(sun_height * 3.0, 0.0, 1.0);      // 1 when the sun is low (dawn/dusk)
	float sdot = max(dot(dir, sun_dir), 0.0);
	day_sky += vec3(1.0, 0.48, 0.22) * pow(sdot, 4.0) * low * 0.9;     // warm glow toward the sun
	day_sky += vec3(1.0, 0.55, 0.30) * g * low * 0.35;                // warm horizon band at dusk
	float day_bright = clamp(sun_height * 1.6 + 0.14, 0.05, 1.0);
	day_sky *= day_bright;

	// sun disc + halo (only above the horizon)
	float sun_up = clamp(sun_height * 6.0 + 0.3, 0.0, 1.0);
	vec3 sun_col = mix(vec3(1.0, 0.55, 0.28), vec3(1.0, 0.98, 0.92), clamp(sun_height * 2.5, 0.0, 1.0));
	float disc = smoothstep(0.9994, 0.99975, sdot);
	float sglow = pow(sdot, 260.0) * 0.6 + pow(sdot, 7.0) * 0.12;
	vec3 sun_c = sun_col * (disc * 7.0 + sglow) * sun_up * (1.0 - storm);

	// ---- high-altitude haze / cloud, slowly drifting (parallax against the stars) ----
	vec3 cloud_p = dir / max(abs(elev) + 0.14, 0.14);
	cloud_p.xz += vec2(TIME * 0.004, TIME * 0.0025);
	float haze = fbm(cloud_p * 1.4);

	// ---- compose day/night ----
	vec3 sky = mix(day_sky + sun_c, night_sky, night_amount);
	// thin day haze brightens the sky subtly where it thickens
	sky += vec3(0.8, 0.85, 0.9) * smoothstep(0.55, 0.95, haze) * 0.12 * (1.0 - night_amount) * day_bright;

	// stars + Milky Way: night only, killed by storm, extinguished toward the horizon
	float above = smoothstep(-0.02, 0.05, elev);
	float star_vis = night_amount * (1.0 - storm) * above;
	sky += (stars * star_gain + milky) * ext * star_vis;

	// moon disc + soft halo, with a crude phase dimming
	float mdisc = smoothstep(0.9990, 0.99965, mdot);
	float mhalo = pow(mdot, 220.0) * 0.35 + pow(mdot, 6.0) * 0.05;
	float phase = clamp(dot(moon_dir, sun_dir) * 0.5 + 0.6, 0.15, 1.0);
	sky += vec3(0.90, 0.93, 1.0) * (mdisc * 4.5 * phase + mhalo) * moon_bright * (1.0 - storm) * above;

	// ---- storm: genuine overcast, structured, starless ----
	vec3 oc_col = vec3(0.26, 0.29, 0.33);
	float oc = fbm(cloud_p * 1.1 + TIME * 0.012);
	vec3 storm_sky = oc_col * (0.65 + 0.55 * oc) * mix(0.55, 1.05, clamp(elev + 0.3, 0.0, 1.0));
	storm_sky *= mix(0.35, 1.0, day_bright + night_amount * 0.15);   // darker at night
	sky = mix(sky, storm_sky, storm);

	// ---- horizon: fade to the scene fog colour so the dome meets the sea seamlessly ----
	float seam = smoothstep(0.09, 0.0, elev);
	sky = mix(sky, horizon_tint, seam * 0.7);
	sky = mix(horizon_tint, sky, above);   // nothing crisp below the horizon line

	// tiny ordered dither breaks 8-bit banding in the smooth gradients
	sky += (hash13(dir * 997.0) - 0.5) * 0.004;

	ALBEDO = max(sky, vec3(0.0));
}
