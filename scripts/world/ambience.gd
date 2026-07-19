extends Node3D
## AMBIENCE — the rig's continuous sense of place.
##
## Registered as the `Ambience` autoload (see project.godot), so it owns no scene and
## survives respawns. Autoloads sit under the root Window, which is itself a Viewport,
## so this Node3D shares the main scene's World3D — raycasts and spatial audio work
## from here with no reparenting.
##
## NO class_name on purpose: an autoload named `Ambience` plus `class_name Ambience`
## is a hard parse error in Godot 4 ("hides an autoload singleton"). Same reason
## rain_audio.gd has none.
##
## Four jobs:
##   1. BEDS      five looping layers crossfaded from the player's actual situation
##                (height above water, how roofed-in they are, storm, phase).
##   2. EVENTS    randomized hull groans, sheet-metal bangs in a gust, drips under
##                the wet deck. Density scales with the weather.
##   3. FOOTSTEPS material-aware steps, synced to the existing stride accumulator.
##   4. VISUALS   sea spray at the waterline, salt motes indoors, wind sway on
##                hanging things.
##
## READ-ONLY BY DESIGN: this node never writes to another domain's state. It reads
## StormSystem and PlayerController fields and degrades to sane defaults when they
## are missing, so nothing here breaks if those files move underneath it.

# ------------------------------------------------------------------ bed config

const FLOOR_DB: float = -60.0     ## below this we just call it silence
const SMOOTH: float = 3.2         ## per-frame dB lerp rate; tweens click, this does not

## name -> [path, peak_db]. Peaks assume AudioDirector's legacy static wind/sea/hum
## beds are still running underneath (see HAND-OFF note at the bottom of this file).
const BED_DEFS: Dictionary = {
	# Peaks raised ~3 dB now that AudioDirector's flat wind/sea/hum beds are handed
	# over (AudioDirector.AMBIENCE_OWNED) — these no longer sit alongside a second,
	# situation-blind mix, so shelter genuinely silences the wind instead of halving it.
	"wind_open": ["res://audio/wind_open.wav", -6.0],
	"wind_howl": ["res://audio/wind_howl.wav", -9.0],
	"sea_swell": ["res://audio/sea_swell.wav", -6.0],
	"hull_groan": ["res://audio/hull_groan.wav", -12.0],
	"interior_hum": ["res://audio/interior_hum.wav", -21.0],
}

## Upward shelter probe, same idea as StormSystem's but our own cone so we never
## depend on its private state.
const PROBE_OFFSETS: Array[Vector3] = [
	Vector3(0, 0, 0), Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0),
	Vector3(0, 0, 1.5), Vector3(0, 0, -1.5),
]
const PROBE_UP: float = 40.0
const SITUATION_HZ: float = 8.0   ## raycast budget: re-probe 8x/sec, lerp between

var _beds: Dictionary = {}        ## name -> AudioStreamPlayer
var _target_db: Dictionary = {}   ## name -> float

# --------------------------------------------------------------- situation state

var _player: Node3D = null
var _storm_node: Node = null
var _cover: float = 0.0           ## 0 open sky .. 1 fully roofed
var _roof_dist: float = 1.0e9
var _height: float = 2.0          ## metres above the waterline (y=0)
var _storm: float = 0.0           ## 0..1
var _wind: Vector2 = Vector2(1, 0)
var _underwater: bool = false
var _probe_accum: float = 0.0
var _rescan_accum: float = 99.0

# -------------------------------------------------------------------- footsteps

## Surface kind -> the two synthesized variants. Alternated so no two consecutive
## steps are the identical waveform, then pitch-jittered on top.
const STEP_VARIANTS: Dictionary = {
	"grate": ["res://audio/step_grate_a.wav", "res://audio/step_grate_b.wav"],
	"plate": ["res://audio/step_plate_a.wav", "res://audio/step_plate_b.wav"],
	"concrete": ["res://audio/step_concrete_a.wav", "res://audio/step_concrete_b.wav"],
	"wood": ["res://audio/step_wood_a.wav", "res://audio/step_wood_b.wav"],
	"water": ["res://audio/step_water_a.wav", "res://audio/step_water_b.wav"],
	"wet": ["res://audio/step_wet_a.wav", "res://audio/step_wet_b.wav"],
}
const STEP_POOL: int = 8

var _step_streams: Dictionary = {}   ## kind -> Array[AudioStream]
var _step_pool: Array[AudioStreamPlayer3D] = []
var _step_next: int = 0
var _step_flip: Dictionary = {}      ## kind -> 0/1
var _prev_accum: float = 0.0
var _mat_kind: Dictionary = {}       ## Material instance -> kind string (built lazily)
var _mat_ready: bool = false

# ----------------------------------------------------------------- event timers

var _groan_timer: Timer
var _sheet_timer: Timer
var _drip_timer: Timer

# --------------------------------------------------------------------- visuals

var _spray: GPUParticles3D = null
var _motes: GPUParticles3D = null
var _sway: Array = []             ## [{node, basis, phase, amp}]
var _overlays: Array = []         ## [{min, max, kind}] non-colliding finish floors
var _sway_t: float = 0.0

var _rng := RandomNumberGenerator.new()


# ==============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the world keeps breathing behind the pause menu
	_rng.randomize()
	for bed_name: String in BED_DEFS:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = FLOOR_DB
		add_child(p)
		_beds[bed_name] = p
		_target_db[bed_name] = FLOOR_DB
	for i in range(STEP_POOL):
		var sp := AudioStreamPlayer3D.new()
		sp.bus = "Master"
		sp.max_distance = 22.0
		sp.unit_size = 3.0
		add_child(sp)
		_step_pool.append(sp)

	_groan_timer = _make_timer(_on_groan)
	_sheet_timer = _make_timer(_on_sheet)
	_drip_timer = _make_timer(_on_drip)

	call_deferred("_load_audio")
	call_deferred("_build_visuals")
	_schedule(_groan_timer, 26.0)
	_schedule(_sheet_timer, 40.0)
	_schedule(_drip_timer, 9.0)


func _make_timer(cb: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	add_child(t)
	t.timeout.connect(cb)
	return t


func _load_audio() -> void:
	for bed_name: String in BED_DEFS:
		var path: String = BED_DEFS[bed_name][0]
		if not ResourceLoader.exists(path):
			push_warning("Ambience: missing bed %s (run tools/synth_ambience.py)" % path)
			continue
		var stream: AudioStream = _as_loop(path)
		var p: AudioStreamPlayer = _beds[bed_name]
		p.stream = stream
		# Belt and braces: loop_mode handles it, `finished` catches any importer that
		# decided otherwise. This is the pattern rain_audio.gd established.
		p.finished.connect(p.play)
		p.play()
	for kind: String in STEP_VARIANTS:
		var arr: Array = []
		for path: String in STEP_VARIANTS[kind]:
			if ResourceLoader.exists(path):
				arr.append(load(path))
		if not arr.is_empty():
			_step_streams[kind] = arr
		_step_flip[kind] = 0


## Force a seamless loop on an imported WAV. loop_end MUST come from the decoded
## length, not data.size() — these import as QOA-compressed, so the byte count is
## not the frame count. (Same trap rain_audio.gd documents.)
func _as_loop(path: String) -> AudioStream:
	var stream: AudioStream = load(path)
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
	return stream


# ================================================================= per-frame mix

func _process(delta: float) -> void:
	_probe_accum += delta
	if _probe_accum >= 1.0 / SITUATION_HZ:
		_probe_accum = 0.0
		_sample_situation()
		_compute_targets()
	_apply_bed_levels(delta)
	_update_visuals(delta)


func _physics_process(_delta: float) -> void:
	_poll_footsteps()


## Everything the mix reacts to, gathered in one place.
func _sample_situation() -> void:
	_player = _find_player()
	if _player == null:
		for bed_name: String in _target_db:
			_target_db[bed_name] = FLOOR_DB
		return
	var pos: Vector3 = _player.global_position
	_height = pos.y
	_underwater = pos.y < 0.0 or bool(_player.get("swimming"))
	_read_storm()

	# Shelter cone: how much sky is over the player's head, and how far up it is.
	var space := _player.get_world_3d().direct_space_state
	var origin: Vector3 = pos + Vector3(0, 1.6, 0)
	var exclude: Array[RID] = []
	if _player is CollisionObject3D:
		exclude.append((_player as CollisionObject3D).get_rid())
	var hits: int = 0
	var nearest: float = 1.0e9
	for off: Vector3 in PROBE_OFFSETS:
		var from: Vector3 = origin + off
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, PROBE_UP, 0))
		q.collision_mask = 1
		q.exclude = exclude
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			hits += 1
			nearest = minf(nearest, (hit["position"] as Vector3).y - from.y)
	_cover = float(hits) / float(PROBE_OFFSETS.size())
	_roof_dist = nearest


## StormSystem exposes only is_storming(). We read the finer private fields when
## they exist and fall back cleanly when they do not — see the HAND-OFF note.
func _read_storm() -> void:
	if _storm_node == null or not is_instance_valid(_storm_node):
		_storm_node = _find_storm()
	if _storm_node == null:
		_storm = 0.0
		return
	var i: Variant = _storm_node.get("_intensity")
	if i is float:
		_storm = clampf(i, 0.0, 1.0)
	elif _storm_node.has_method("is_storming"):
		_storm = 0.6 if _storm_node.call("is_storming") else 0.0
	var w: Variant = _storm_node.get("_wind")
	if w is Vector2 and (w as Vector2).length() > 0.01:
		_wind = (w as Vector2).normalized()


func _compute_targets() -> void:
	if _player == null:
		return
	var night: bool = GameClock.current_phase == GameClock.Phase.NIGHT
	var exposure: float = 1.0 - _cover                             # open sky overhead
	var height_f: float = clampf((_height - 1.0) / 20.0, 0.0, 1.0) # waterline -> topside
	# Never let the ocean vanish completely: even on the topside deck you can hear it
	# working away below you, and total absence reads as a bug.
	var near_sea: float = 0.14 + 0.86 * (1.0 - clampf((_height - 1.0) / 16.0, 0.0, 1.0))
	# Wind through a GAP is loudest at partial cover — a stairwell, a railing run,
	# the slot between two modules. Fully open or fully sealed, it stops whistling.
	var gap: float = 4.0 * _cover * (1.0 - _cover)

	if _underwater:
		# Down here the sky does not exist; the water is close and everywhere.
		_target_db["wind_open"] = FLOOR_DB
		_target_db["wind_howl"] = FLOOR_DB
		_target_db["interior_hum"] = FLOOR_DB
		_target_db["sea_swell"] = _mix("sea_swell", 1.35)
		_target_db["hull_groan"] = _mix("hull_groan", 0.5)
		return

	_target_db["wind_open"] = _mix("wind_open",
		exposure * (0.30 + 0.70 * height_f) * (1.0 + 1.1 * _storm))
	_target_db["wind_howl"] = _mix("wind_howl",
		(0.75 * gap + 0.25 * exposure * height_f) * (0.55 + 0.85 * _storm + 0.35 * height_f))
	_target_db["sea_swell"] = _mix("sea_swell",
		near_sea * (0.55 + 0.45 * exposure) * (0.75 + 0.6 * _storm))
	# The rig complains most when you are inside it, at night, in weather.
	_target_db["hull_groan"] = _mix("hull_groan",
		(0.40 + 0.60 * _cover) * (0.65 + 0.75 * _storm) * (1.25 if night else 0.85))
	# Room tone only once you are genuinely enclosed.
	_target_db["interior_hum"] = _mix("interior_hum",
		clampf((_cover - 0.35) / 0.5, 0.0, 1.0) * (1.0 if _roof_dist < 8.0 else 0.5))


func _mix(bed_name: String, gain: float) -> float:
	if gain <= 0.001:
		return FLOOR_DB
	var peak: float = BED_DEFS[bed_name][1]
	return maxf(FLOOR_DB, peak + linear_to_db(clampf(gain, 0.001, 2.0)))


func _apply_bed_levels(delta: float) -> void:
	var a: float = clampf(delta * SMOOTH, 0.0, 1.0)
	for bed_name: String in _beds:
		var p: AudioStreamPlayer = _beds[bed_name]
		p.volume_db = lerpf(p.volume_db, _target_db[bed_name], a)


# ==================================================================== footsteps

## Sync trick: PlayerController integrates distance into `_step_accum` and zeroes it
## when a stride completes. Watching for that reset gives us the exact frame of every
## step with zero edits to player_controller.gd, and keeps our material layer locked
## to its cadence and posture rules instead of drifting against a second accumulator.
func _poll_footsteps() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if bool(_player.get("swimming")):
		_prev_accum = 0.0
		return
	var raw: Variant = _player.get("_step_accum")
	if raw == null:
		return
	var accum: float = float(raw)
	var fired: bool = _prev_accum > 1.0 and accum < _prev_accum * 0.5
	_prev_accum = accum
	if fired:
		_play_footstep()


func _play_footstep() -> void:
	var kind: String = _classify_ground()
	var streams: Array = _step_streams.get(kind, [])
	if streams.is_empty():
		return
	# Posture comes straight from the controller's own stealth curve:
	# 1.0 standing, 0.5 crouched, 0.3 flat on the deck.
	var posture: float = 1.0
	if _player.has_method("detection_factor"):
		posture = float(_player.call("detection_factor"))
	var vol: float = -34.0
	if posture > 0.75:
		vol = -13.0
	elif posture > 0.4:
		vol = -24.0
	# Moving fast lands harder.
	var vel: Variant = _player.get("velocity")
	if vel is Vector3:
		var speed: float = Vector3((vel as Vector3).x, 0.0, (vel as Vector3).z).length()
		vol += clampf((speed - 2.0) * 0.9, 0.0, 3.5)

	var flip: int = int(_step_flip.get(kind, 0))
	_step_flip[kind] = (flip + 1) % streams.size()
	var sp: AudioStreamPlayer3D = _step_pool[_step_next]
	_step_next = (_step_next + 1) % _step_pool.size()
	sp.stream = streams[flip % streams.size()]
	sp.volume_db = vol
	sp.pitch_scale = _rng.randf_range(0.92, 1.09)
	sp.global_position = _player.global_position + Vector3(0, -0.55, 0)
	sp.play()


## What is underfoot? Raycast down, find the surface material, and look it up against
## MatLib's cached singletons — MatLib memoizes by key, so every deck built from
## MatLib.deck_plate() shares one Material instance and reference equality is exact.
func _classify_ground() -> String:
	# Read the player's CURRENT height, not the cached `_height`: the situation probe
	# only runs at SITUATION_HZ while footsteps poll every physics frame, so the cache
	# can be ~125 ms stale — enough to play a splash on the topside deck for the first
	# few steps after a teleport or a respawn.
	var pos: Vector3 = _player.global_position
	# Standing in the shallows reads as water regardless of what the plating is.
	if pos.y < 0.55:
		return "water"
	var space := _player.get_world_3d().direct_space_state
	var from: Vector3 = pos + Vector3(0, 0.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -2.6, 0))
	q.collision_mask = 1
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return _weather("plate")
	# Interior finish floors (lino, galley tile, rubber matting) are built as THIN
	# NON-COLLIDING overlay boxes laid on top of the structural deck, so the ray goes
	# straight through them and every room sounded like bare steel. Test the hit point
	# against their cached footprints first — the finish is what you are walking on.
	var over: String = _overlay_kind(hit["position"])
	if over != "":
		return _weather(over)
	var kind: String = _kind_for(hit.get("collider"))
	return _weather(kind)


func _overlay_kind(at: Vector3) -> String:
	for o: Dictionary in _overlays:
		var lo: Vector3 = o["min"]
		var hi: Vector3 = o["max"]
		if at.x >= lo.x and at.x <= hi.x and at.z >= lo.z and at.z <= hi.z \
				and absf(at.y - hi.y) < 0.4:
			return o["kind"]
	return ""


## Cache the footprints of those non-colliding finish floors. They are axis-aligned
## CSG boxes, thin and wide, carrying a material we already know how to classify.
func _rescan_overlays() -> void:
	_overlays.clear()
	var scene: Node = get_tree().current_scene
	if scene != null:
		_build_mat_map()
		_collect_overlays(scene, 0)


func _collect_overlays(node: Node, depth: int) -> void:
	if depth > 6 or _overlays.size() >= 64:
		return
	for child: Node in node.get_children():
		var box := child as CSGBox3D
		if box != null and not box.use_collision and box.size.y < 0.25 \
				and box.size.x > 1.5 and box.size.z > 1.5:
			var m: Material = box.material
			if m != null and _mat_kind.has(m):
				var c: Vector3 = box.global_position
				var h: Vector3 = box.size * 0.5
				_overlays.append({"min": c - h, "max": c + h, "kind": _mat_kind[m]})
		_collect_overlays(child, depth + 1)


## Rain turns bare plating into a film of water underfoot. Grating drains, so it
## keeps ringing; concrete and wood just go dull, which the dry samples already do.
func _weather(kind: String) -> String:
	if kind == "plate" and _storm > 0.12 and _cover < 0.45:
		return "wet"
	return kind


func _kind_for(collider: Variant) -> String:
	if collider == null or not (collider is Node):
		return "plate"
	_build_mat_map()
	var mat: Material = _material_of(collider as Node)
	if mat != null and _mat_kind.has(mat):
		return _mat_kind[mat]
	# Fall back to the node name — covers imported prop scenes and anything built
	# outside MatLib.
	var n: String = (collider as Node).name.to_lower()
	for frag: String in ["grat", "walkway", "mesh_deck"]:
		if n.contains(frag):
			return "grate"
	for frag: String in ["wood", "plank", "pallet", "timber"]:
		if n.contains(frag):
			return "wood"
	for frag: String in ["concrete", "cement", "slab", "tile"]:
		if n.contains(frag):
			return "concrete"
	return "plate"


## The rig is built from CSG nodes (which carry `material` directly) and MeshInstance3D
## props (material_override, then the mesh's own surface material). Colliders may be
## the shape node itself or a StaticBody3D wrapper, so check the node, its parent and
## its children.
func _material_of(node: Node) -> Material:
	var candidates: Array[Node] = [node]
	if node.get_parent() != null:
		candidates.append(node.get_parent())
	for c: Node in node.get_children():
		candidates.append(c)
	for c: Node in candidates:
		var m: Variant = c.get("material")          # CSGShape3D
		if m is Material:
			return m as Material
		var mi := c as MeshInstance3D
		if mi != null:
			if mi.material_override != null:
				return mi.material_override
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var sm: Material = mi.mesh.surface_get_material(0)
				if sm != null:
					return sm
	return null


## Built on the first footstep, not in _ready: touching MatLib pulls its PBR textures
## in, and boot is busy enough already.
func _build_mat_map() -> void:
	if _mat_ready:
		return
	_mat_ready = true
	var groups: Dictionary = {
		"grate": [MatLib.grating(), MatLib.checker_plate()],
		"plate": [MatLib.deck_plate(), MatLib.rust_steel(), MatLib.dark_metal(),
			MatLib.painted_steel(), MatLib.galvanized(), MatLib.corrugated(),
			MatLib.rusty_metal()],
		"concrete": [MatLib.concrete(), MatLib.concrete_floor(), MatLib.tide_band(),
			MatLib.kitchen_tile(), MatLib.medical_white(), MatLib.rubber_floor(),
			MatLib.lino_floor()],
		"wood": [MatLib.wood(), MatLib.weathered_wood()],
	}
	for kind: String in groups:
		for m: Material in groups[kind]:
			if m != null:
				_mat_kind[m] = kind


# ======================================================================= events

func _schedule(t: Timer, mean_sec: float) -> void:
	t.wait_time = maxf(2.0, _rng.randf_range(mean_sec * 0.5, mean_sec * 1.5))
	t.start()


## Somewhere in the structure, steel gives up a little. Denser at night and in weather.
func _on_groan() -> void:
	if _player != null and not _underwater:
		var off := Vector3(_rng.randf_range(-22, 22), _rng.randf_range(-10, 5),
			_rng.randf_range(-22, 22))
		AudioDirector.play_one_shot("deep_groan", _player.global_position + off,
			lerpf(-16.0, -6.0, _storm))
	var night: bool = GameClock.current_phase == GameClock.Phase.NIGHT
	_schedule(_groan_timer, lerpf(40.0, 15.0, _storm) * (0.7 if night else 1.0))


## A loose sheet of cladding somewhere out on the deck, caught by a gust. Only when
## there is actually sky and wind — you never hear it sealed inside a module.
func _on_sheet() -> void:
	var exposed: bool = _cover < 0.6
	if _player != null and not _underwater and exposed and (_storm > 0.1 or _height > 10.0):
		var off := Vector3(_rng.randf_range(-26, 26), _rng.randf_range(-3, 9),
			_rng.randf_range(-26, 26))
		AudioDirector.play_one_shot("sheet_bang", _player.global_position + off,
			lerpf(-20.0, -8.0, _storm))
	_schedule(_sheet_timer, lerpf(55.0, 12.0, _storm))


## Under the wet deck: water finding its way down through the structure. Close, small,
## and constant — the sound of the place being damp rather than being weathered.
func _on_drip() -> void:
	var under_deck: bool = _height > -0.5 and _height < 7.0 and _cover > 0.4
	if _player != null and not _underwater and under_deck:
		var off := Vector3(_rng.randf_range(-7, 7), _rng.randf_range(-1, 3),
			_rng.randf_range(-7, 7))
		AudioDirector.play_one_shot("drip", _player.global_position + off,
			_rng.randf_range(-24.0, -15.0))
	_schedule(_drip_timer, lerpf(11.0, 4.0, _storm))


# ====================================================================== visuals

func _build_visuals() -> void:
	_spray = _make_particles(_spray_process(), Color(0.80, 0.93, 0.95, 0.5), 0.16, 2.6, 900)
	_motes = _make_particles(_motes_process(), Color(0.86, 0.88, 0.80, 0.30), 0.022, 9.0, 220)


func _make_particles(proc: ParticleProcessMaterial, tint: Color, size: float,
		life: float, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.process_material = proc
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -12, -30), Vector3(60, 30, 60))
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_color = tint
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	# WITHOUT THIS the quad is a flat opaque square. The process material's colour
	# ramp fades alpha over the particle's LIFETIME, not across its surface, so every
	# droplet stayed a hard-edged 35cm box with crisp corners for its whole life —
	# unmissable against the sea. The radial falloff is what makes it a droplet.
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = false
	add_child(p)
	return p


## Soft round particle sprite, built once and shared. A radial alpha falloff costs
## nothing under gl_compatibility and is the whole difference between "spray" and
## "squares". Slightly hot in the middle so a droplet still has a glint.
static var _dot_tex: GradientTexture2D = null

static func _soft_dot() -> GradientTexture2D:
	if _dot_tex != null:
		return _dot_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.42, Color(1, 1, 1, 0.72))
	g.add_point(0.78, Color(1, 1, 1, 0.10))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_dot_tex = t
	return _dot_tex


## Spray thrown off the swell against the legs: a wide flat band at the waterline,
## kicked upward and blown downwind. No collision — gl_compatibility has no GPU
## particle collision, so it is placed analytically and simply never reaches geometry.
func _spray_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(22.0, 0.4, 22.0)
	m.direction = Vector3(0, 1, 0)
	m.spread = 32.0
	m.initial_velocity_min = 1.6
	m.initial_velocity_max = 5.2
	m.gravity = Vector3(0, -5.0, 0)
	m.damping_min = 0.6
	m.damping_max = 1.8
	m.scale_min = 0.5
	m.scale_max = 2.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.95, 0.97, 0.0))
	ramp.set_color(1, Color(0.70, 0.88, 0.92, 0.0))
	ramp.add_point(0.22, Color(0.92, 0.98, 1.0, 0.85))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	return m


## Salt and dust hanging in the air of a closed room. Very slow, very faint — you only
## catch it when a lamp is behind it. (Real light shafts are impossible here:
## volumetric fog and light_volumetric_fog_energy are dead code on gl_compatibility.)
func _motes_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(7.0, 2.4, 7.0)
	m.direction = Vector3(0, -1, 0)
	m.spread = 80.0
	m.initial_velocity_min = 0.01
	m.initial_velocity_max = 0.09
	m.gravity = Vector3(0, -0.045, 0)
	m.damping_min = 0.0
	m.damping_max = 0.25
	m.scale_min = 0.4
	m.scale_max = 1.6
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.16
	m.turbulence_noise_scale = 2.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 0.9, 0.85, 0.0))
	ramp.set_color(1, Color(0.9, 0.9, 0.85, 0.0))
	ramp.add_point(0.3, Color(0.95, 0.95, 0.88, 0.5))
	ramp.add_point(0.7, Color(0.95, 0.95, 0.88, 0.5))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	return m


func _update_visuals(delta: float) -> void:
	_sway_t += delta
	if _player == null:
		if _spray != null:
			_spray.emitting = false
		if _motes != null:
			_motes.emitting = false
		return
	var pos: Vector3 = _player.global_position

	if _spray != null:
		# Only worth drawing when the player is low enough to see the waterline.
		var want: float = clampf((14.0 - _height) / 12.0, 0.0, 1.0) * (0.15 + 0.85 * _storm)
		if _underwater:
			want = 0.0
		_spray.emitting = want > 0.02
		_spray.amount_ratio = want
		_spray.global_position = Vector3(pos.x, 0.6, pos.z)

	if _motes != null:
		var indoor: float = clampf((_cover - 0.5) / 0.4, 0.0, 1.0)
		_motes.emitting = indoor > 0.05 and not _underwater
		_motes.amount_ratio = indoor * 0.8
		_motes.global_position = pos + Vector3(0, 1.4, 0)

	_rescan_accum += delta
	if _rescan_accum > 6.0:
		_rescan_accum = 0.0
		_rescan_sway(pos)
		_rescan_overlays()
	_animate_sway()


## Find things that ought to move in wind. Nothing in the world is tagged for this,
## so we discover by type (HangLine) and by name fragment, and we only ever write
## `transform.basis` on nodes we found ourselves — no other script is touched.
func _rescan_sway(around: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	_sway.clear()
	_collect_sway(scene, around, 0)


## UNAMBIGUOUS markers only. An earlier, looser list ("cable", "line", "wire",
## "canvas", "lamp", "antenna") matched sub-meshes deep inside imported prop scenes —
## it was rotating picture-frame canvases, a desk radio's antenna and the cables of a
## multimeter lying on a bench. A prop that sits on a table must never sway, so the
## match has to name the hanging itself, not a part that happens to be cable-shaped.
const SWAY_NAMES: Array[String] = [
	"hanging", "chain", "windsock", "flag", "banner", "tarp", "drying",
]

func _collect_sway(node: Node, around: Vector3, depth: int) -> void:
	if depth > 6 or _sway.size() >= 24:
		return
	for child: Node in node.get_children():
		var n3 := child as Node3D
		if n3 != null and _is_swayable(n3) and n3.global_position.distance_to(around) < 34.0:
			_sway.append({
				"node": n3,
				"basis": n3.transform.basis,
				"phase": _rng.randf_range(0.0, TAU),
				"amp": _rng.randf_range(0.6, 1.4),
			})
		else:
			_collect_sway(child, around, depth + 1)


## preload rather than the bare class_name: the global class cache lags behind new
## scripts on this project, and a missed identifier here is a parse error at boot.
const HANG_LINE := preload("res://scripts/components/hang_line.gd")

func _is_swayable(n3: Node3D) -> bool:
	if n3.get_script() == HANG_LINE:
		return true
	var name_l: String = n3.name.to_lower()
	for frag: String in SWAY_NAMES:
		if name_l.contains(frag):
			return true
	return false


## Small-amplitude pendulum about the rest pose, driven along the storm's wind vector
## with a second faster term so it never reads as a clean sine.
func _animate_sway() -> void:
	if _sway.is_empty():
		return
	var strength: float = (0.10 + 0.90 * _storm) * (0.35 + 0.65 * clampf(_height / 18.0, 0.0, 1.0))
	for entry: Dictionary in _sway:
		# Validity BEFORE the typed local: assigning a freed instance to a `Node3D`
		# throws on the assignment itself, so the guard below it never gets to run.
		# Dismantling one swaying structure used to spew this every frame until the
		# next _rescan_sway.
		if not is_instance_valid(entry["node"]):
			continue
		var n3: Node3D = entry["node"]
		var ph: float = entry["phase"]
		var amp: float = entry["amp"] * strength
		var swing: float = (sin(_sway_t * 1.35 + ph) * 0.75
			+ sin(_sway_t * 3.1 + ph * 2.3) * 0.25)
		var a: float = deg_to_rad(6.0) * amp * swing
		var base: Basis = entry["basis"]
		# Lean downwind, in the plane of the wind.
		n3.transform.basis = base.rotated(Vector3(0, 0, 1), a * _wind.x) \
			.rotated(Vector3(1, 0, 0), a * _wind.y)


# ======================================================================= lookup

func _find_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group("player") as Node3D


## Recursive, not just direct children: StormSystem is a child of Main, but Main is not
## always the current scene (test harnesses instance it under their own root, and the
## game boots through StartScreen first). A shallow search silently finds nothing and
## the whole mix flatlines at storm=0.
func _find_storm() -> Node:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	return _search_storm(scene, 0)


func _search_storm(node: Node, depth: int) -> Node:
	if depth > 4:
		return null
	for child: Node in node.get_children():
		if child.has_method("is_storming"):
			return child
		var found: Node = _search_storm(child, depth + 1)
		if found != null:
			return found
	return null


# ------------------------------------------------------------------- HAND-OFFS
#
# 1. DONE. AudioDirector's legacy wind/sea/hum beds are handed over — see
#    AudioDirector.AMBIENCE_OWNED, which pins them to -80 dB at the _fade chokepoint.
#    BED_DEFS peaks above were raised ~3 dB to take over the level. AudioDirector
#    still owns "rain"; do not claim it here without moving rain_audio.gd too.
#
# 2. DONE. player_controller.gd no longer fires the generic "step" one-shot. It still
#    resets `_step_accum`, which is the only thing we actually trigger off.
#
# 3. StormSystem has no public `intensity()` / `wind_vector()`. We read `_intensity`
#    and `_wind` defensively and fall back to is_storming(). Public getters would be
#    cleaner; adding them requires no change here (the `get()` calls keep working).
