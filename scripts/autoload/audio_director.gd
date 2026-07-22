extends Node
## Layered environmental audio beds crossfaded by GameClock phase and PowerGrid state.
## NO MUSIC — canon law. Night rule: one-shot audible range doubles, reverb deepens.
## Assets are synthesized placeholders in res://audio/; the architecture is the point.

const BED_DEFS: Dictionary = {
	"wind": "res://audio/wind_loop.wav",
	"sea": "res://audio/sea_loop.wav",
	"hum": "res://audio/hum_loop.wav",
	"rain": "res://audio/rain_loop.wav",
}
## HANDED OVER TO Ambience. These three beds are now mixed by situation (height above
## the waterline, roof cover, sea distance, storm, phase) in scripts/world/ambience.gd,
## which plays wind_open / wind_howl / sea_swell / hull_groan / interior_hum instead.
## Running the flat versions underneath meant walking indoors ducked the situational
## wind while this one kept howling at full level — exactly the failure the new mix
## exists to remove. Silenced at the single chokepoint (_fade) so every existing call
## site stays honest; "rain" is NOT handed over — it is still this node's to drive.
const AMBIENCE_OWNED: Array[String] = ["wind", "sea", "hum"]

const ONE_SHOTS: Dictionary = {
	"thunder": "res://audio/thunder.wav",
	"groan": "res://audio/groan.wav",
	"gull": "res://audio/gull.wav",
	"pa_crackle": "res://audio/pa_crackle.wav",
	"hiss": "res://audio/hiss.wav",
	"clang": "res://audio/clang.wav",
	"breaker": "res://audio/breaker.wav",
	"hatch": "res://audio/hatch.wav",
	"splash": "res://audio/splash.wav",
	"eat": "res://audio/eat.wav",
	"step": "res://audio/step.wav",
	# Giant crab (s11): soft chitin scuttle taps + the pincer snap. Fired as one-shots
	# by the crab itself, hard-gated on movement + proximity + actual visibility —
	# there is NO ambient or looping claw sound anymore.
	"scuttle_a": "res://audio/scuttle_a.wav",
	"scuttle_b": "res://audio/scuttle_b.wav",
	"scuttle_c": "res://audio/scuttle_c.wav",
	"crab_snap": "res://audio/crab_snap.wav",
	# Ambience events (scripts/world/ambience.gd schedules these).
	"deep_groan": "res://audio/deep_groan.wav",
	"sheet_bang": "res://audio/sheet_bang.wav",
	"drip": "res://audio/drip.wav",
}

var _beds: Dictionary = {}       ## name -> AudioStreamPlayer
var _streams: Dictionary = {}    ## name -> AudioStream (one-shots)
var _groan_timer: Timer
var _gull_timer: Timer
var night_range_multiplier: float = 1.0

## AUDIO OPTIONS (pause menu). The rig was over-stimulating: too many competing sources
## at once. The default mix is now waves, wind, rain and gulls, with everything else
## earning its place — and these two switches let the player mute whole categories.
##
## NOTE there is no music track in SALTLINE ("NO MUSIC — canon law", top of this file), so
## the second switch governs the ATMOSPHERE LAYER — the tonal beds and the randomized
## structural events (hull groans, sheet-metal bangs, drips) that read as scoring.
var wildlife_machinery_on: bool = true
var atmosphere_on: bool = true

## Creature and machinery sources: animal calls and the idle plant hum.
const WILDLIFE_MACHINERY: Array[String] = ["gull", "groan", "scuttle_a", "scuttle_b", "scuttle_c", "crab_snap"]
## The scored-feeling layer: randomized structural events.
const ATMOSPHERE_EVENTS: Array[String] = ["deep_groan", "sheet_bang", "drip"]

## True when this sample is allowed to sound under the current options.
func _shot_allowed(shot_name: String) -> bool:
	if not wildlife_machinery_on and WILDLIFE_MACHINERY.has(shot_name):
		return false
	if not atmosphere_on and ATMOSPHERE_EVENTS.has(shot_name):
		return false
	return true

## Called by the pause menu. Re-mixes the beds the switch owns straight away so the
## change is audible without waiting for the next crossfade.
func set_wildlife_machinery(on: bool) -> void:
	wildlife_machinery_on = on
	_fade("hum", -80.0 if not on else -18.0, 0.6)

func set_atmosphere(on: bool) -> void:
	atmosphere_on = on
	var amb: Node = get_tree().get_first_node_in_group("ambience")
	if amb and amb.has_method("set_atmosphere_enabled"):
		amb.set_atmosphere_enabled(on)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bed_name in BED_DEFS:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		p.bus = "Master"
		add_child(p)
		_beds[bed_name] = p

	_groan_timer = Timer.new()
	_groan_timer.one_shot = true
	add_child(_groan_timer)
	_groan_timer.timeout.connect(_random_groan)
	_gull_timer = Timer.new()
	_gull_timer.one_shot = true
	add_child(_gull_timer)
	_gull_timer.timeout.connect(_random_gull)

	GameClock.phase_changed.connect(_on_phase_changed)
	PowerGrid.circuit_powered.connect(func(_id: String) -> void: _update_hum())
	PowerGrid.circuit_lost.connect(func(_id: String) -> void: _update_hum())
	call_deferred("_load_audio")
	call_deferred("_on_phase_changed", GameClock.current_phase)

func _load_audio() -> void:
	for bed_name in BED_DEFS:
		if ResourceLoader.exists(BED_DEFS[bed_name]):
			var stream: AudioStream = load(BED_DEFS[bed_name])
			_beds[bed_name].stream = stream
			if stream:
				_beds[bed_name].finished.connect(_beds[bed_name].play)
				_beds[bed_name].play()
	for shot_name in ONE_SHOTS:
		if ResourceLoader.exists(ONE_SHOTS[shot_name]):
			_streams[shot_name] = load(ONE_SHOTS[shot_name])

func _on_phase_changed(phase: GameClock.Phase) -> void:
	var is_night: bool = phase == GameClock.Phase.NIGHT
	var is_dusk: bool = phase == GameClock.Phase.DUSK
	var is_day: bool = phase == GameClock.Phase.DAY
	night_range_multiplier = 2.0 if is_night else 1.0
	# Beds: wind always; sea constant; groans denser toward and through the night.
	_fade("wind", -14.0 if not is_night else -10.0)
	_fade("sea", -16.0)
	_update_hum()
	_schedule(_groan_timer, 20.0 if is_night else (32.0 if is_dusk else 50.0))
	if is_day or phase == GameClock.Phase.DAWN:
		_schedule(_gull_timer, 12.0)
	else:
		_gull_timer.stop()
	# NOTE (s11): the old "distant claw ticks from below" generator is GONE. It fired
	# claw.wav every 12-18 s all dusk and night regardless of any crab's state — the
	# "constant jingling". Crab audio now comes only from the crabs themselves, and
	# only when one is moving, near, and visible.

func _update_hum() -> void:
	var any_power: bool = not PowerGrid.powered_ids().is_empty()
	_fade("hum", -18.0 if any_power else -80.0)

## Storm intensity 0..1 — fades the rain bed up and howls the wind. Called by the
## StormSystem as a squall rolls in and out.
func set_storm(intensity: float) -> void:
	_storm_level = intensity
	if _underwater:
		return   # the surface can rage; down here it's all pressure and hush
	_fade("rain", lerpf(-80.0, -4.0, intensity), 1.5)
	var base_wind: float = -14.0 if GameClock.current_phase != GameClock.Phase.NIGHT else -10.0
	_fade("wind", lerpf(base_wind, -2.0, intensity), 1.5)

var _underwater: bool = false
var _storm_level: float = 0.0

## Below the wave line the topside world goes distant: wind and rain vanish, the
## sea becomes a low pressure-hush all around.
func set_underwater(under: bool) -> void:
	_underwater = under
	if under:
		_fade("wind", -80.0, 0.6)
		_fade("rain", -80.0, 0.6)
		_fade("sea", -8.0, 0.6)    # the water itself, close and everywhere
		_fade("hum", -80.0, 0.6)
	else:
		_fade("sea", -16.0, 0.8)
		_update_hum()
		set_storm(_storm_level)   # restore whatever the sky is doing

func _fade(bed_name: String, target_db: float, duration: float = 2.5) -> void:
	var p: AudioStreamPlayer = _beds.get(bed_name)
	if p == null:
		return
	var want: float = target_db
	if AMBIENCE_OWNED.has(bed_name):
		want = -80.0   # see AMBIENCE_OWNED: Ambience carries these now
	var tw: Tween = create_tween()
	tw.tween_property(p, "volume_db", want, duration)

func _schedule(t: Timer, mean_sec: float) -> void:
	t.wait_time = maxf(2.0, randf_range(mean_sec * 0.5, mean_sec * 1.5))
	t.start()

func _random_groan() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player:
		var offset := Vector3(randf_range(-25, 25), randf_range(-8, 4), randf_range(-25, 25))
		play_one_shot("groan", player.global_position + offset)
	_schedule(_groan_timer, 20.0 if GameClock.current_phase == GameClock.Phase.NIGHT else 50.0)

func _random_gull() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player:
		var offset := Vector3(randf_range(-30, 30), randf_range(5, 15), randf_range(-30, 30))
		play_one_shot("gull", player.global_position + offset)
	_schedule(_gull_timer, 12.0)

## Spatialized one-shot. Zero position = non-positional (UI-ish sounds like eating).
func play_one_shot(shot_name: String, world_pos: Vector3, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(shot_name)
	if stream == null or not _shot_allowed(shot_name):
		return
	if world_pos == Vector3.ZERO:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.volume_db = volume_db
		p3.max_distance = 40.0 * night_range_multiplier
		p3.unit_size = 6.0 * night_range_multiplier
		get_tree().current_scene.add_child(p3)
		p3.global_position = world_pos
		p3.finished.connect(p3.queue_free)
		p3.play()

## NOTE (s11): attach_loop — the looping claw-step timer emitter — is deleted. Its only
## caller was the old crab, and a repeating creature cue on a timer is exactly the
## design that produced the constant jingling. Creature audio is one-shots, event-driven.
