extends Node
## Owns time-of-day. Emits phase-change signals; all environment systems
## (sun, ambient audio, creature activation) key off these, never their own timers.

enum Phase { DAWN, DAY, DUSK, NIGHT }

signal dawn
signal day
signal dusk
signal night
signal phase_changed(phase: Phase)
signal time_updated(phase_fraction: float) ## 0.0-1.0 fraction through current phase

@export var phase_durations_minutes: Dictionary = {
	Phase.DAWN: 8.0,
	Phase.DAY: 55.0,
	Phase.DUSK: 12.0,
	Phase.NIGHT: 20.0,
}

## Always begins at first light so a full, unhurried day of daylight lies ahead.
var current_phase: Phase = Phase.DAWN
var day_count: int = 0 ## increments each time NIGHT completes (drives the end card)
var time_scale: float = 1.0 ## testing/debug only — accelerates the day, never shipped >1
var _phase_elapsed_sec: float = 0.0
var _running: bool = true

func _process(delta: float) -> void:
	if not _running:
		return
	_phase_elapsed_sec += delta * time_scale
	var duration_sec: float = phase_durations_minutes[current_phase] * 60.0
	time_updated.emit(clampf(_phase_elapsed_sec / duration_sec, 0.0, 1.0))
	if _phase_elapsed_sec >= duration_sec:
		_advance_phase()

func phase_fraction() -> float:
	var duration_sec: float = phase_durations_minutes[current_phase] * 60.0
	return clampf(_phase_elapsed_sec / duration_sec, 0.0, 1.0)

func _advance_phase() -> void:
	if current_phase == Phase.NIGHT:
		day_count += 1
	force_phase(((current_phase + 1) % (Phase.NIGHT + 1)) as Phase)

func force_phase(phase: Phase) -> void:
	_phase_elapsed_sec = 0.0
	current_phase = phase
	phase_changed.emit(current_phase)
	match current_phase:
		Phase.DAWN:
			dawn.emit()
		Phase.DAY:
			day.emit()
		Phase.DUSK:
			dusk.emit()
		Phase.NIGHT:
			night.emit()

func skip_to_next_dawn() -> void:
	## Creature-contact stub: the night ends for you early (GDD 5.5).
	day_count += 1
	force_phase(Phase.DAWN)

func set_running(value: bool) -> void:
	_running = value
