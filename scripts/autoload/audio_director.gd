extends Node
## Layered environmental audio beds crossfaded by GameClock phase and PowerGrid state.
## NO MUSIC — canon law. Night rule: one-shot audible range doubles, reverb deepens.
## Assets are synthesized placeholders in res://audio/; the architecture is the point.

const BED_DEFS: Dictionary = {
	"wind": "res://audio/wind_loop.wav",
	"sea": "res://audio/sea_loop.wav",
	"hum": "res://audio/hum_loop.wav",
}
const ONE_SHOTS: Dictionary = {
	"groan": "res://audio/groan.wav",
	"gull": "res://audio/gull.wav",
	"claw": "res://audio/claw.wav",
	"pa_crackle": "res://audio/pa_crackle.wav",
	"hiss": "res://audio/hiss.wav",
	"clang": "res://audio/clang.wav",
	"breaker": "res://audio/breaker.wav",
	"hatch": "res://audio/hatch.wav",
	"splash": "res://audio/splash.wav",
	"eat": "res://audio/eat.wav",
}

var _beds: Dictionary = {}       ## name -> AudioStreamPlayer
var _streams: Dictionary = {}    ## name -> AudioStream (one-shots)
var _groan_timer: Timer
var _gull_timer: Timer
var night_range_multiplier: float = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bed_name in BED_DEFS:
		var stream: AudioStream = load(BED_DEFS[bed_name]) if ResourceLoader.exists(BED_DEFS[bed_name]) else null
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = -80.0
		p.bus = "Master"
		add_child(p)
		if stream:
			p.finished.connect(p.play) # seamless-enough looping for noise beds
			p.play()
		_beds[bed_name] = p
	for shot_name in ONE_SHOTS:
		if ResourceLoader.exists(ONE_SHOTS[shot_name]):
			_streams[shot_name] = load(ONE_SHOTS[shot_name])

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
	_on_phase_changed(GameClock.current_phase)

func _on_phase_changed(phase: GameClock.Phase) -> void:
	var is_night: bool = phase == GameClock.Phase.NIGHT
	var is_day: bool = phase == GameClock.Phase.DAY
	night_range_multiplier = 2.0 if is_night else 1.0
	# Beds: wind always; sea louder low/dawn; groans denser at night.
	_fade("wind", -14.0 if not is_night else -10.0)
	_fade("sea", -16.0)
	_update_hum()
	_schedule(_groan_timer, 20.0 if is_night else 50.0)
	if is_day or phase == GameClock.Phase.DAWN:
		_schedule(_gull_timer, 12.0)
	else:
		_gull_timer.stop()

func _update_hum() -> void:
	var any_power: bool = not PowerGrid.powered_ids().is_empty()
	_fade("hum", -18.0 if any_power else -80.0)

func _fade(bed_name: String, target_db: float, duration: float = 2.5) -> void:
	var p: AudioStreamPlayer = _beds.get(bed_name)
	if p:
		var tw: Tween = create_tween()
		tw.tween_property(p, "volume_db", target_db, duration)

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
	if stream == null:
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

## Looping spatial emitter attached to a moving node (crab claw-steps).
func attach_loop(shot_name: String, parent: Node3D, interval: float) -> Timer:
	var t := Timer.new()
	t.wait_time = interval
	parent.add_child(t)
	t.timeout.connect(func() -> void:
		if is_instance_valid(parent):
			play_one_shot(shot_name, parent.global_position, -4.0))
	t.start()
	return t
