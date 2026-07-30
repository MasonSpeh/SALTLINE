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

# Tuned to the middle: the original 38-min day felt rushed, the 95-min day dragged
# on forever, so this ~60-min cycle sits between them — a real, unhurried day without
# the endless wait. (DAY still dominates; NIGHT meaningful but not a slog.)
@export var phase_durations_minutes: Dictionary = {
	Phase.DAWN: 5.0,
	Phase.DAY: 34.0,
	Phase.DUSK: 8.0,
	Phase.NIGHT: 13.0,
}

## Begins in DAY, sun already up, so a full unhurried day of daylight lies ahead.
## It used to start at DAWN with the phase fraction at 0, and DAWN starts BEFORE
## sunrise: SunController maps (DAWN, f=0) to a sun elevation of −8° with a full
## night ambient, so the first minutes of a new game were visually night — stars
## out, sun energy clamped to zero. DAY at f=0 puts the sun at 16° and drops the
## night mix to zero immediately, which is what "morning" is supposed to look like.
var current_phase: Phase = Phase.DAY
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

## One in-game day in real seconds, off the clock's own phase plan (60 min as tuned).
## hang_line.gd and BloomFauna.game_hour_per_sec() both derive their own rate from this
## same sum; this is that arithmetic in one place so a system measuring a span in DAYS
## does not have to re-derive it.
func real_sec_per_game_day() -> float:
	var day_sec: float = 0.0
	for phase in phase_durations_minutes:
		day_sec += float(phase_durations_minutes[phase]) * 60.0
	return maxf(day_sec, 1.0)

## How far through the current day it is, in game hours — 0.0 the instant DAWN begins,
## 24.0 as NIGHT ends. Derived from the phase plan, so re-tuning a phase re-bases it.
func hours_into_day() -> float:
	var total: float = 0.0
	var before: float = 0.0
	for phase in phase_durations_minutes:
		var mins: float = float(phase_durations_minutes[phase])
		if int(phase) < int(current_phase):
			before += mins
		total += mins
	if total <= 0.0:
		return 0.0
	var mins_in: float = before + float(phase_durations_minutes[current_phase]) * phase_fraction()
	return 24.0 * mins_in / total

## ABSOLUTE game time in hours since the run began: whole days plus the part-day.
##
## THIS IS WHAT ANYTHING MEASURED IN GAME DAYS MUST KEY OFF, and it is not the same as a
## countdown in real seconds. Sleeping calls skip_to_next_dawn(), which bumps day_count and
## resets the phase — so a night the player slept through costs no real seconds at all but
## is unarguably a day that passed. A five-day regrowth counted in delta would therefore be
## five real HOURS of standing about, and a player who slept five nights would still find
## the patch bare. Monotonic across both a natural phase advance (end of NIGHT is 24.0, and
## the next DAWN is (day+1)*24 + 0.0) and a sleep.
func game_time_hours() -> float:
	return float(day_count) * 24.0 + hours_into_day()

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
