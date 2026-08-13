class_name StormSystem extends Node3D
## Violent North Atlantic squalls that roll through every now and then: driving
## rain that follows the player, howling wind, a slate-dark sky, and lightning
## with delayed thunder. A storm ramps in, rages for a few minutes, then clears.
## Ties the sky/ambient darkening into SunController and the audio into
## AudioDirector; the rain is a GPU particle emitter parented above the player.

enum StormPhase { CLEAR, RAMP_IN, RAGING, RAMP_OUT }

const RainAudio := preload("res://scripts/world/rain_audio.gd")
const RAIN_SHADER: String = "res://materials/rain_particles.gdshader"

## Solid roofed volumes (world space) baked from the rig geometry: any rain drop
## whose position lands inside one is scaled invisible by the particle shader, so
## rooms stay dry while rain still falls past every window and open edge. Each row
## is [min_x, min_y, min_z, max_x, max_y, max_z]. Box #4 is the whole shadow of the
## topside plate (a single solid 60x40 slab at y17..18): everything under it — wet
## deck, boat approach lanes, the pontoon walkway below — is genuinely roofed, and
## the old SE-strip box covered barely a fifth of it, so rain fell indoors across
## the west half of the rig and dripped through to under the structure.
const COVER_BOXES: Array = [
	[14.9, 2.0, -25.3, 21.1, 4.2, -22.9],   # SPHL pod interior
	[10.0, 2.0, -14.0, 18.0, 5.2, -6.0],    # pump room (flooded)
	[10.0, 2.0, -22.0, 16.0, 5.2, -16.0],   # loot / storage room
	[-30.0, -1.5, -20.0, 30.0, 17.0, 20.0], # EVERYTHING under the topside plate (one solid 60x40 slab at y17..18 roofs its whole shadow, wet deck and pontoon walkway included)
	[21.0, 2.0, -6.0, 31.0, 38.0, 2.0],     # stair tower shaft (widened shell x21..31)
	[24.0, 6.0, 2.0, 31.0, 9.2, 8.8],       # machinery room (annexes end at z8.8 now)
	[21.0, 10.0, 2.0, 28.0, 13.2, 8.8],     # breaker room 4-A
	[20.0, 38.0, -8.0, 32.0, 41.0, 4.0],    # ops lookout
	[-28.0, 18.0, 4.0, -8.0, 21.2, 18.0],   # bunkhouse
	[-2.0, 18.0, 8.0, 14.0, 21.2, 18.0],    # galley
	[18.0, 18.0, 8.0, 28.0, 21.2, 18.0],    # rec room
	[-28.0, 18.0, -18.0, -14.0, 21.2, -6.0],# machine shop
	[-2.0, 21.6, 6.0, 28.0, 24.8, 18.0],    # Deck B quarters
	[4.0, 25.1, 6.0, 28.0, 28.3, 18.0],     # Deck C control
	[8.0, 28.6, 8.0, 28.0, 31.8, 18.0],     # Deck D works
	[23.0, 32.1, 13.0, 27.0, 34.8, 17.5],   # roof bulkhead hut
]

## THE FIELD RIGS' COVER, added s65. COVER_BOXES above is rig 1 only, in world space, and
## the three field rigs have had NO entry since they were built in s54 — so rain fell INSIDE
## THE ANCHORAGE's atrium, which is what the owner photographed. It is worse than a missing
## row: the emitter is pinned 16 m above the player (`_follow_player`), so standing on the
## atrium floor at y 22 spawns every drop at y 38 — INSIDE the 18.5 m drum, under a roof at
## 40.5 — and they fall the whole way down past the galleries.
##
## These are RIG-LOCAL boxes. `_push_cover_boxes` transforms each centre by its rig's
## transform and hands the shader the rig's YAW alongside, because all three rigs are rotated
## and an axis-aligned world box round a rotated room either over-covers (blanking rain in
## plain sight outside the windows) or leaks at the corners.
##
## Format: rig id -> [ [min_x, min_y, min_z, max_x, max_y, max_z], ... ]
const FIELD_COVER: Dictionary = {
	"marrow": [
		[-30.0, 14.0, 2.0, -4.0, 21.2, 20.0],      # mess block, both storeys, to the garden roof
		[2.0, 14.0, 4.0, 26.0, 21.2, 19.0],        # plant hall
		[-24.0, 14.0, -20.0, -4.0, 18.4, -8.0],    # hydroponics / bio lab
		[-38.0, 6.8, -24.0, 38.0, 13.8, 24.0],     # the whole process deck, under the main slab
	],
	"anchorage": [
		[-16.0, 22.0, -12.0, 16.0, 41.0, 20.0],    # THE ATRIUM DRUM, floor to glass roof
		[-40.0, 22.0, -28.0, 40.0, 26.4, 22.0],    # the podium: every main-level room
		[18.0, 22.0, -10.0, 40.0, 29.4, 18.0],     # the double-height dining hall
		[-40.0, 26.2, -10.0, -18.0, 37.3, 18.0],   # west tower
		[18.0, 29.4, -10.0, 40.0, 36.8, 18.0],     # east tower
		[-14.0, 22.0, 22.0, 14.0, 29.4, 30.0],     # spa block
		[-34.0, 15.4, -24.0, 34.0, 19.3, 24.0],    # leisure deck / pool hall
		[-34.0, 8.8, -24.0, 34.0, 12.5, 24.0],     # plant deck
	],
	"deepwell": [
		[-31.0, 20.0, 10.0, -9.0, 26.0, 24.0],     # shaker house
		[10.0, 20.0, -26.0, 30.0, 26.6, -12.0],    # core sample lab, both storeys
		[13.0, 26.6, -23.0, 24.0, 29.8, -15.0],    # control room
		[-7.0, 20.0, -31.0, 5.0, 23.2, -24.0],     # decon airlock
		[-27.0, 11.3, -27.0, 27.0, 18.4, 27.0],    # production deck, under the main slab
	],
}

const RAMP_IN_SEC: float = 22.0
const RAMP_OUT_SEC: float = 32.0
const FIRST_DELAY_MIN: float = 45.0     # first squall within the first ~1 min so it's seen early
const FIRST_DELAY_MAX: float = 100.0
const CALM_MIN: float = 220.0           # clear spells between storms (~3.7–7.5 min)
const CALM_MAX: float = 450.0
const RAGE_MIN: float = 90.0            # a storm rages 1.5–3.5 min
const RAGE_MAX: float = 210.0

var sun_ctl: SunController
var _phase: StormPhase = StormPhase.CLEAR
var _timer: float = 0.0
var _intensity: float = 0.0
var _rain: GPUParticles3D
var _rain_shader: ShaderMaterial
var _rain_audio: Node
var _flash: DirectionalLight3D
var _flash_energy: float = 0.0
var _lightning_cd: float = 0.0
var _wind: Vector2 = Vector2(1, 0)
var _rng := RandomNumberGenerator.new()
var _audio_cd: float = 0.0
## Shelter probe results. These no longer gate the rain VISUALS (the particle
## shader's covered-volume AABBs do that, so rain is always visible outdoors and
## through windows) — they only shape the rain AUDIO.
var _roof_dist: float = 1.0e9   ## metres up to the nearest roof overhead (huge = open sky)
var _cover_frac: float = 0.0    ## fraction of the upward probe cone that is roofed
## Sea fog: some squalls leave a bank of it behind as they clear — cold rain on warmer
## water. Rolled when RAGING hands over to RAMP_OUT, held for a few minutes, then lifts.
const FOG_CHANCE: float = 0.55
const FOG_HOLD_MIN: float = 120.0
const FOG_HOLD_MAX: float = 260.0
var _fog: float = 0.0           ## eased 0..1, pushed to SunController like storm
var _fog_hold: float = 0.0      ## seconds of fog bank left

func setup(sun_controller: SunController) -> void:
	sun_ctl = sun_controller

func _ready() -> void:
	_rng.randomize()
	_build_rain()
	_build_flash()
	_rain_audio = RainAudio.new()
	add_child(_rain_audio)
	_timer = _rng.randf_range(FIRST_DELAY_MIN, FIRST_DELAY_MAX)
	_wind = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()

## Force a squall now (debug/testing hook).
func trigger_storm() -> void:
	if _phase == StormPhase.CLEAR or _phase == StormPhase.RAMP_OUT:
		_wind = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		_phase = StormPhase.RAMP_IN
		_timer = RAMP_IN_SEC

func is_storming() -> bool:
	return _intensity > 0.25

## How hard it is raining right now, 0..1 — the WHOLE curve, not the squall flag above it.
## A storm ramps in over 22 s and back out over 32 s, and for all of that time there is
## weather in the water that is not yet (or no longer) a squall. is_storming() throws that
## band away; FishTable reads this so the drizzle either side of a gale can be its own
## fishing condition (see FishTable.RAIN_MIN and the `rain` field in data/fish.json).
## (The sea-fog bank a squall leaves behind is already exposed further down as fog_level();
## FishTable reads that one for the `fog` field in data/fish.json.)
func rain_level() -> float:
	return _intensity

# ---------------------------------------------------------------- build

func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	# DENSITY, owner call 2026-08-03: "20% denser". The quantity scaled is the drop COUNT
	# with the emission GEOMETRY held fixed — emit_extents, lifetime and fall_speed are all
	# untouched below, so the swept column (52 x 52 m sheet falling ~47 m) is the same volume
	# it was and 5000 -> 6000 is exactly x1.20 drops per cubic metre as well as x1.20 drops.
	# Those two are only the same number because the volume did not move: shrinking
	# emit_extents would have bought the same density for free and been the wrong answer,
	# because the sheet is 52 m wide precisely so its edge is never in shot.
	_rain.amount = 6000
	_rain.lifetime = 1.3
	_rain.preprocess = 1.3
	_rain.local_coords = false
	# Pin the sim to 30fps + interpolate: the 6000-drop x 16-AABB cull loop no longer
	# re-runs every rendered frame, so rain stops taxing high-refresh framerates. The
	# drops still MOVE every frame (interpolation), so the look is unchanged.
	# NOTE the cost of `amount` is paid in FULL at every non-zero intensity: `amount_ratio`
	# (set in _apply_intensity) throttles how many are EMITTED, and Godot still allocates and
	# processes the whole buffer regardless. So the +1000 slots are a drizzle cost, not just
	# a full-gale one.
	_rain.fixed_fps = 30
	_rain.interpolate = true
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_rain.emitting = false
	# A custom particles shader replaces ParticleProcessMaterial: it falls the drops
	# and culls any that are inside a covered volume, so the rain can emit ALWAYS.
	_rain_shader = ShaderMaterial.new()
	_rain_shader.shader = load(RAIN_SHADER)
	_rain_shader.set_shader_parameter("emit_extents", Vector3(26.0, 0.5, 26.0))
	_rain_shader.set_shader_parameter("fall_speed", 36.0)
	_rain_shader.set_shader_parameter("wind_drift", Vector3.ZERO)
	_push_cover_boxes()
	_rain.process_material = _rain_shader
	# A billboarded drop, shaped by a soft teardrop alpha mask so it reads as a real
	# raindrop — rounded head, tapered tail, no hard rectangle corners — instead of a
	# skinny box. The mask is a tiny generated texture (same trick MatLib.soft_mote uses
	# for marine snow), so there is zero per-frame cost and it is gl_compat-safe.
	var streak := QuadMesh.new()
	# SIZE, owner call 2026-08-03: "25% smaller". Scaled HERE and not in the shader because
	# rain_particles.gdshader's v_wid / v_len are dimensionless MULTIPLIERS on this quad
	# (0.86..1.26 and 0.72..1.42, one shared calibre per drop) — multiplying the base metre
	# size by 0.75 shrinks every drop by exactly 0.75 and leaves that whole distribution and
	# its aspect ratio intact, where re-tuning four shader constants would have had to
	# reproduce it by hand. Was Vector2(0.05, 0.55); drops now measure 0.032..0.047 m wide by
	# 0.30..0.59 m long in world space (billboard_keep_scale keeps these in metres).
	streak.size = Vector2(0.0375, 0.4125)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.78, 0.85, 0.95, 0.34)   # soft: streaks read, don't glare
	smat.albedo_texture = _raindrop_mask()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.billboard_keep_scale = true
	streak.material = smat
	_rain.draw_pass_1 = streak
	add_child(_rain)

## A small teardrop alpha texture: pointed tail at the top, rounded fuller head at the
## bottom, soft rounded cross-section. Built once at boot. White RGB (tinted by
## albedo_color); only the alpha channel carries the shape.
func _raindrop_mask() -> ImageTexture:
	var w: int = 24
	var h: int = 96
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v: float = float(y) / float(h - 1)          # 0 = tail (top), 1 = head (bottom)
		# Round BOTH ends (kills the sharp corners) and swell the width toward the head.
		var ends: float = smoothstep(0.0, 0.12, v) * smoothstep(0.0, 0.16, 1.0 - v)
		var half_w: float = 0.5 * lerpf(0.5, 1.0, smoothstep(0.12, 0.72, v))
		for x in w:
			var d: float = absf(float(x) / float(w - 1) - 0.5)
			var cross: float = 1.0 - smoothstep(half_w * 0.55, half_w, d)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(ends * cross, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Bake the roofed volumes into the shader's AABB uniform arrays (capacity 24).
## The boxes are hand-measured approximations of the built geometry, so they get a
## small outward margin sideways and downward to stop drops squeezing through at
## wall edges. Deliberately NOT grown upward: raising a lid above its real roof
## would blank out the rain visibly falling ONTO that roof from outside.
const COVER_MARGIN: float = 0.35

func _push_cover_boxes() -> void:
	var mins := PackedVector3Array()
	var maxs := PackedVector3Array()
	var yaws := PackedFloat32Array()
	var m: float = COVER_MARGIN
	# Rig 1, at the world origin with no rotation. The margin grows the box sideways and
	# downward but never upward, because the top face IS the roof.
	for b: Array in COVER_BOXES:
		mins.append(Vector3(b[0] - m, b[1] - m, b[2] - m))
		maxs.append(Vector3(b[3] + m, b[4], b[5] + m))
		yaws.append(0.0)
	# The field. Each box is authored in its rig's own frame; the CENTRE is transformed to
	# world and the half-extents kept, so the shader can undo the rig's yaw about that centre
	# and test the box square. Reading the origins from rig_field means these cannot drift
	# apart from where the rigs actually stand.
	var F := preload("res://scripts/world/rig_field.gd")
	var rigs: Dictionary = {
		"marrow": [F.MARROW_ORIGIN, F.MARROW_YAW],
		"anchorage": [F.ANCHORAGE_ORIGIN, F.ANCHORAGE_YAW],
		"deepwell": [F.DEEPWELL_ORIGIN, F.DEEPWELL_YAW],
	}
	for rid in FIELD_COVER.keys():
		var spec: Array = rigs[rid]
		var yaw: float = deg_to_rad(float(spec[1]))
		var xf := Transform3D(Basis(Vector3.UP, yaw), spec[0] as Vector3)
		for b2: Array in FIELD_COVER[rid]:
			var lo := Vector3(b2[0] - m, b2[1] - m, b2[2] - m)
			var hi := Vector3(b2[3] + m, b2[4], b2[5] + m)
			var half: Vector3 = (hi - lo) * 0.5
			var centre: Vector3 = xf * ((lo + hi) * 0.5)
			mins.append(centre - half)
			maxs.append(centre + half)
			yaws.append(yaw)
	_rain_shader.set_shader_parameter("box_min", mins)
	_rain_shader.set_shader_parameter("box_max", maxs)
	_rain_shader.set_shader_parameter("box_yaw", yaws)
	_rain_shader.set_shader_parameter("box_count", mins.size())
	print("[storm] %d covered volumes (%d on rig 1, %d across the field)" % [
		mins.size(), COVER_BOXES.size(), mins.size() - COVER_BOXES.size()])

func _build_flash() -> void:
	_flash = DirectionalLight3D.new()
	_flash.light_energy = 0.0
	_flash.light_color = Color(0.82, 0.88, 1.0)
	_flash.rotation_degrees = Vector3(-58, 35, 0)
	_flash.shadow_enabled = false
	add_child(_flash)

# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	_advance_schedule(delta)
	_advance_fog(delta)
	_update_shelter()
	_apply_intensity()
	_follow_player()
	_update_lightning(delta)

## Probe what's overhead — used ONLY to shape the rain audio now that the particle
## shader handles visual shelter. A spread of upward rays (not a single one) so the
## open lip of a roofed-but-open-sided space reads as partly open instead of fully
## sheltered: cover_frac is how much of the cone is roofed, roof_dist how far up the
## nearest slab is (close thin roof = patter, huge slab high above = muffled wash).
const _PROBE_OFFSETS: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0),
	Vector3(0, 0, 2.5), Vector3(0, 0, -2.5),
]

func _update_shelter() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		_roof_dist = 1.0e9
		_cover_frac = 0.0
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var head: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	var exclude: Array[RID] = []
	if player is CollisionObject3D:
		exclude = [(player as CollisionObject3D).get_rid()]
	var hits: int = 0
	var nearest: float = 1.0e9
	for off: Vector3 in _PROBE_OFFSETS:
		var from: Vector3 = head + off
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 40.0, 0))
		query.collision_mask = 1
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			hits += 1
			nearest = minf(nearest, (hit["position"] as Vector3).y - from.y)
	_cover_frac = float(hits) / float(_PROBE_OFFSETS.size())
	_roof_dist = nearest

func _advance_schedule(delta: float) -> void:
	_timer -= delta
	match _phase:
		StormPhase.CLEAR:
			_intensity = move_toward(_intensity, 0.0, delta * 0.3)
			if _timer <= 0.0:
				_phase = StormPhase.RAMP_IN
				_timer = RAMP_IN_SEC
				_wind = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		StormPhase.RAMP_IN:
			_intensity = move_toward(_intensity, 1.0, delta / RAMP_IN_SEC)
			if _timer <= 0.0:
				_phase = StormPhase.RAGING
				_timer = _rng.randf_range(RAGE_MIN, RAGE_MAX)
		StormPhase.RAGING:
			_intensity = move_toward(_intensity, 1.0, delta * 0.5)
			# The wind wanders during the storm so the rain angle shifts.
			_wind = (_wind + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * delta * 0.15).normalized()
			if _timer <= 0.0:
				_phase = StormPhase.RAMP_OUT
				_timer = RAMP_OUT_SEC
				if _rng.randf() < FOG_CHANCE:
					_fog_hold = _rng.randf_range(FOG_HOLD_MIN, FOG_HOLD_MAX)
		StormPhase.RAMP_OUT:
			_intensity = move_toward(_intensity, 0.0, delta / RAMP_OUT_SEC)
			if _timer <= 0.0:
				_phase = StormPhase.CLEAR
				_timer = _rng.randf_range(CALM_MIN, CALM_MAX)

## The fog bank breathes on its own clock: builds while the rain is still ramping out,
## sits, then lifts slowly — fog that snaps off with the last raindrop reads as a
## graphics setting, not weather.
func _advance_fog(delta: float) -> void:
	_fog_hold = maxf(_fog_hold - delta, 0.0)
	var target: float = 1.0 if _fog_hold > 0.0 else 0.0
	_fog = move_toward(_fog, target, delta * (0.05 if target > _fog else 0.02))
	if sun_ctl:
		sun_ctl.set_fog(_fog)

func fog_level() -> float:
	return _fog

func _apply_intensity() -> void:
	var i: float = _intensity
	# Rain ALWAYS falls during a storm regardless of where the player is standing —
	# the shader's covered-volume AABBs keep it out of rooms, so it stays visible
	# through every window and across every open deck.
	_rain.emitting = i > 0.02
	_rain.amount_ratio = clampf(i, 0.0, 1.0)
	# Slant the rain with the wind (stronger tilt at full storm).
	_rain_shader.set_shader_parameter("wind_drift", Vector3(_wind.x, 0.0, _wind.y) * 11.0 * i)
	if sun_ctl:
		sun_ctl.set_storm(i)
	_feed_rain_audio(i)
	# Audio follows intensity, but re-fading every frame thrashes tweens — throttle.
	_audio_cd -= get_process_delta_time()
	if _audio_cd <= 0.0:
		AudioDirector.set_storm(i)
		_audio_cd = 0.4

## Push the mix state to the rain beds every frame — rain_audio.gd does its own
## smoothing, so this is cheap and stays glitch-free while the player walks in and
## out of cover. Below the waterline the downpour drops away entirely.
func _feed_rain_audio(i: float) -> void:
	if _rain_audio == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var submerged: bool = player != null and player.global_position.y < 0.0
	_rain_audio.set_state(i, _roof_dist, _cover_frac, submerged)

func _follow_player() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# Rain box sits above the player, nudged upwind so it sweeps across the view.
	_rain.global_position = player.global_position + Vector3(-_wind.x * 6.0, 16.0, -_wind.y * 6.0)
	# ...but never render it below the waterline. The streaks are billboarded quads that
	# know nothing about where the sea is, so diving during a squall put white rain
	# falling straight through the water column around you. The rain AUDIO already ducked
	# when submerged; the visuals never did. Same waterline test main.gd swaps the
	# underwater environment on, so the two agree frame for frame.
	var cam: Camera3D = player.get_node_or_null("Head/Camera3D")
	var eye: Vector3 = cam.global_position if cam != null else player.global_position
	_rain.visible = eye.y > Gyre.swim_line(Vector2(eye.x, eye.z), Gyre.water_time())

func _update_lightning(delta: float) -> void:
	# Decay the last flash toward dark, fast.
	_flash_energy = move_toward(_flash_energy, 0.0, delta * 22.0)
	_flash.light_energy = _flash_energy
	if _intensity < 0.4:
		return
	_lightning_cd -= delta
	if _lightning_cd <= 0.0:
		_strike()
		_lightning_cd = _rng.randf_range(5.0, 15.0) * (1.5 - _intensity)

func _strike() -> void:
	# A sharp flash with a quick secondary flicker, then thunder after the light
	# has travelled — closer strikes flash brighter and rumble sooner.
	var near: float = _rng.randf()          # 0 = distant, 1 = right overhead
	_flash_energy = lerpf(1.6, 4.5, near)
	var t2 := get_tree().create_timer(0.09)
	t2.timeout.connect(func() -> void: _flash_energy = lerpf(1.0, 3.0, near))
	var delay: float = lerpf(2.6, 0.3, near)
	var vol: float = lerpf(-16.0, 2.0, near)
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		var player: Node3D = get_tree().get_first_node_in_group("player")
		var pos: Vector3 = player.global_position if player else Vector3.ZERO
		AudioDirector.play_one_shot("thunder", pos + Vector3(0, 30, 0), vol))
