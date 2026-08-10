extends Node
## Layered environmental audio beds crossfaded by GameClock phase and PowerGrid state.
## NO MUSIC — canon law. Night rule: one-shot audible range doubles, reverb deepens.
## Assets are synthesized placeholders in res://audio/; the architecture is the point.
##
## THE BUS GRAPH (built in code by _build_buses, see the note there for why not a .tres):
##
##     World ──┐  AudioEffectLowPassFilter -> AudioEffectReverb, both DISABLED topside
##     UI    ──┴──> Master   (bus 0: the pause menu's volume slider, nothing else)
##
## Everything diegetic lives on World and goes through the water; the non-positional
## one-shot path (play_one_shot with Vector3.ZERO) lives on UI and never does. See
## `set_underwater` for the underwater treatment and the hysteresis it uses.

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
## site stays honest. NOTE: "rain" is ALSO silenced in _fade now — scripts/world/rain_audio.gd
## took over rain with cover-aware loops (rain_open/metal/far), so this flat rain bed must stay
## quiet or it doubles up as a harsh wash. It keeps its bed id (StormSystem still calls
## set_storm), but drives to -80 and contributes none; rain_loop.wav is a silent buffer too.
const AMBIENCE_OWNED: Array[String] = ["wind", "sea", "hum"]

const ONE_SHOTS: Dictionary = {
	"thunder": "res://audio/thunder.wav",
	"groan": "res://audio/groan.wav",
	"gull": "res://audio/gull.wav",
	# Takeoff is WINGS ONLY — a flushed bird beats air, it does not announce itself.
	# gull.wav stays for the distant ambient cries (_random_gull) and nothing else.
	"wingbeat": "res://audio/wingbeat.wav",
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
	# The ship's cat (s34). It used to borrow `groan` — the deep-hull one-shot, played
	# quiet, with a comment calling it "the closest thing to a purr". It is not one: a purr
	# is a 25 Hz amplitude modulation on a breathy carrier, not a groan pitched down.
	# tools/gen_cat_audio.py synthesises both of these.
	"purr": "res://audio/purr.wav",
	"cat_chirp": "res://audio/cat_chirp.wav",
	"meow": "res://audio/meow.wav",
	# Ambience events (scripts/world/ambience.gd schedules these).
	"deep_groan": "res://audio/deep_groan.wav",
	"sheet_bang": "res://audio/sheet_bang.wav",
	"drip": "res://audio/drip.wav",
}

## MASTER ONE-SHOT MIX TRIM (dB), applied once at the playback chokepoint (play_one_shot).
## The ~50 call sites across the codebase pass their own volume_db and are owned by other
## files; this table is the single place to keep the whole one-shot layer from spiking when
## the player runs system volume UP, without editing any of them. Attenuate-only (<= 0).
## Absent id => 0. See scratchpad audio_mix_notes.md for the per-sound old->new reasoning.
##   clang  : the metal-break (prying/breaking open) — also dulled + quieted in gen_audio.py.
##   breaker: breaker_panel/cable play it at DEFAULT 0 dB over a near-full-scale sample.
##   pa_crackle/thunder/crab_snap: their loudest call sites pass POSITIVE gain.
const SHOT_TRIM: Dictionary = {
	"clang": -6.0,
	"breaker": -7.0,
	"pa_crackle": -8.0,
	"hiss": -5.0,
	"groan": -5.0,
	"splash": -4.0,
	"thunder": -4.0,
	"hatch": -4.0,
	"crab_snap": -3.0,   # not our sample, but its shark-bite site passes +2 dB; keep it from peaking
}

var _beds: Dictionary = {}       ## name -> AudioStreamPlayer
var _streams: Dictionary = {}    ## name -> AudioStream (one-shots)
var _groan_timer: Timer
var _gull_timer: Timer
var _adopt_timer: Timer
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
const WILDLIFE_MACHINERY: Array[String] = ["gull", "wingbeat", "groan", "scuttle_a", "scuttle_b", "scuttle_c", "crab_snap"]
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
	# Before any player exists — this autoload runs ahead of Ambience (project.godot
	# order) and ahead of every scene, so the buses are there to be named by the time
	# anything asks for one.
	_build_buses()
	for bed_name in BED_DEFS:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		p.bus = BUS_WORLD
		add_child(p)
		_beds[bed_name] = p

	# RainAudio is created by StormSystem when the world builds, i.e. long after us, and
	# a respawn/reload builds another one — so this is a repeating sweep, not a one-shot.
	# It walks ~20 nodes; see _adopt_world_players for what it is fixing and why.
	_adopt_timer = Timer.new()
	_adopt_timer.wait_time = 2.0
	_adopt_timer.timeout.connect(_adopt_world_players)
	add_child(_adopt_timer)
	_adopt_timer.start()
	call_deferred("_adopt_world_players")

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

# ============================================================================= UNDERWATER
#
# THERE WAS NO UNDERWATER TREATMENT BEFORE THIS, and the reason is worth recording because
# it is the shape docs/AGENT_TRAPS.md keeps warning about: `set_underwater` existed, it was
# called, and every line in it was DEAD. All four of its bed ids are in AMBIENCE_OWNED (or
# are "rain"), and `_fade` forces exactly those to -80 dB — so `_fade("sea", -8.0)` set the
# sea bed to SILENCE. The function ran, nothing changed, and the code read as a feature.
#
# What you actually hear under the swell today is Ambience's `sea_swell` (pushed to 1.35
# gain) and `hull_groan` (0.5), plus whatever one-shots fire — all of it unfiltered, i.e.
# byte-identical to the topside mix. Hence a real treatment, on the bus, not on volumes.
#
# LEVELS ARE DELIBERATELY NOT TOUCHED HERE. Ambience already drops wind/interior_hum to its
# floor underwater and RainAudio already mutes, and this file's whole HAND-OVER note at the
# top exists because two systems mixing one bed is how the wind ended up howling indoors.
# So the underwater work here is CHARACTER only: a filter and a room. Nothing ducks.

## Bus names. Everything diegetic goes to World and is filtered; the non-positional
## one-shot path goes to UI and is not. Both send to Master, so the pause menu's volume
## slider (which writes bus 0) still owns the whole output.
const BUS_MASTER: String = "Master"
const BUS_WORLD: String = "World"
const BUS_UI: String = "UI"

## WATER KILLS HIGH FREQUENCY — the single cue that reads as "under". 20500 is the top of
## Godot's cutoff range, i.e. the filter is transparent (and it is also switched OFF
## outright at wet == 0, so topside costs nothing and is bit-identical to before).
const DRY_CUTOFF_HZ: float = 20500.0
## At 12 dB/oct this puts a gull three octaves up (4960 Hz) 36 dB down. 24 dB/oct was
## rejected: -72 dB there leaves the bed with no texture at all, which reads as broken
## rather than as submerged.
const WET_CUTOFF_HZ: float = 620.0
## Reverb wet/dry at full submersion. The water is a close, dark, everywhere room — not a
## hall — so the tail is short and heavily damped (see _build_buses) and `dry` only steps
## back far enough for the tail to be felt.
const WET_REVERB: float = 0.42
const WET_DRY: float = 0.80

# ------------------------------------------------------------------- HYSTERESIS, MEASURED
#
# THE WATERLINE MOVES: an 11-band Gerstner swell (Gyre) on top of a 0.70 m tide, and
# main.gd's flag is a bare `cam.y < Gyre.swim_line(...)` re-evaluated every frame. So the
# question "how long does a crossing last" was answered by replaying Gyre's own band table
# off-line — same W_DIR/W_LEN/W_AMP, same _warp and _patchiness, 900 s at 120 Hz:
#
#   camera held at mean water     : 189 crossings / 900 s = one every 4.8 s;
#                                   submerged spans median 2.40 s, p10 0.78 s, 3% < 0.45 s
#   camera at +0.60 m (bobbing)   : submerged spans median 0.96 s, p10 0.28 s, 19% < 0.45 s
#                                   above-water spans  median 6.32 s,           1% < 0.45 s
#   (at the mean line the crossing statistics are identical at sea_state 0.4 and 1.0 —
#    a squall scales the amplitude, it does not move the zero crossings.)
#
# Three things fall out of that, and the third is the one that decided these constants:
#   * THE CROSSFADE IS MOST OF THE HYSTERESIS, NOT THE DWELL. The shortest tenth of genuine
#     submerged spans at the line is 0.78 s — longer than FADE_DOWN — so a real dunk still
#     reaches full wet and the 3% that do not get a partial swell instead of a click. Run
#     against that same signal these dwells reject only 2% of the raw edges: the sea does
#     not flicker, it heaves, and no dwell short enough to keep a dive responsive will
#     "fix" a waterline crossing that genuinely lasts two and a half seconds. Riding the
#     line therefore breathes with the swell, which is what actually happens to your ears.
#   * THE SHORT EXCURSIONS ARE DUNKS, NOT GASPS — 19% of submerged spans are under 0.45 s
#     against 1% of dry ones. So the dwell is asymmetric the way the sea is: quick in, slow
#     out. Entering fast keeps the dive immediate (a brief dunk SHOULD sound wet); leaving
#     slowly bridges the moments a swell top clears your head while you are plainly still
#     in the water, which is the flip that reads as a glitch rather than as a moment.
#   * WHAT THE DWELL IS ACTUALLY FOR is a flag that flips faster than the fade — a stalled
#     frame, a teleport, a respawn at the line, a swimmer thrashing at the surface.
#
# THE RESPONSE TO AN OSCILLATING FLAG WAS SWEPT, NOT ASSUMED (square wave on
# set_underwater, 30 s per point, 60 fps, reading cutoff_hz back off the bus):
#
#   half-period      committed transitions   what the bus does
#   below ENTER_DWELL        0               stays dry; the flicker never lands
#   0.10 .. 0.33 s           1               ONE smooth fade to wet, then latched — the
#                                            0.35 s exit dwell is never satisfied, so
#                                            thrashing at the line picks wet and holds
#   0.34 .. 0.40 s         36..50            stays wet; cutoff breathes 620..2009 Hz at
#                                            0.34 s, 620..4766 Hz at 0.40 s. No click:
#                                            the filter never switches back off
#   0.50 s and slower      tracks            full 620..20500 Hz travel, which is correct —
#                                            at half a second in and out you ARE surfacing
#
# There is no half-period that produces an on/off stutter of the effect itself; the worst
# case is a cutoff that breathes inside the underwater band. Note the first row is a
# property of ENTER_DWELL, not a tuned number: verified at 0.05 s, marginal at exactly
# 0.10 s (it is the threshold), which is why the probe below uses 0.05.
#
# Measured end to end at 60 fps: the filter engages 0.12 s after the flag, diving is 50%
# wet at 0.33 s and fully wet at 0.57 s; surfacing is fully dry at 0.63 s.
const ENTER_DWELL: float = 0.10   ## raw flag must hold this long before we commit to wet
const EXIT_DWELL: float = 0.35    ## ...and this long before we commit back to dry
const FADE_DOWN: float = 0.45     ## seconds from fully dry to fully wet
const FADE_UP: float = 0.30       ## and back — faster, so surfacing is a snap of clarity

var _uw_raw: bool = false         ## last thing main.gd told us, undebounced
var _uw_hold: float = 0.0         ## seconds _uw_raw has held its value
var _wet: float = 0.0             ## 0 topside .. 1 fully submerged; the crossfade itself
var _world_bus: int = -1
var _ui_bus: int = -1
var _lpf: AudioEffectLowPassFilter = null
var _reverb: AudioEffectReverb = null

## Called by main.gd on every change of `cam.global_position.y < Gyre.swim_line(...)` —
## THE one authoritative underwater test in this project. This node does not re-derive it
## (a second depth test is how ambience.gd ended up with its own cruder `pos.y < 0.0`);
## it debounces what it is given and crossfades from it.
func set_underwater(under: bool) -> void:
	if under == _uw_raw:
		return
	_uw_raw = under
	_uw_hold = 0.0

## Commit + crossfade. Early-outs to two compares in the topside steady state, which is
## most of the game.
func _process(delta: float) -> void:
	_uw_hold += delta
	if _uw_raw != _underwater and _uw_hold >= (ENTER_DWELL if _uw_raw else EXIT_DWELL):
		_commit_underwater(_uw_raw)
	var goal: float = 1.0 if _underwater else 0.0
	if _wet == goal:
		return
	_wet = move_toward(_wet, goal, delta / (FADE_DOWN if goal > _wet else FADE_UP))
	_apply_wetness()

## The debounced transition. The bed calls are the ORIGINAL ones and they are still no-ops
## by design (see _fade) — they are kept because `set_storm` gates on `_underwater` and
## must restore the sky's mix on the way up, and because the ids are the contract other
## files call through. What changed is that they now fire on the DEBOUNCED edge, so a
## swimmer at the line no longer spawns a Tween per wave crest.
func _commit_underwater(under: bool) -> void:
	_underwater = under
	if under:
		# Close the 2 s window in which a just-built RainAudio could still be on Master:
		# sweep once more at the exact moment the filter is about to matter.
		_adopt_world_players()
		_fade("wind", -80.0, 0.6)
		_fade("rain", -80.0, 0.6)
		_fade("sea", -8.0, 0.6)    # the water itself, close and everywhere
		_fade("hum", -80.0, 0.6)
	else:
		_fade("sea", -16.0, 0.8)
		_update_hum()
		set_storm(_storm_level)   # restore whatever the sky is doing

## Write the crossfade into the bus. THE CUTOFF IS INTERPOLATED IN LOG SPACE, and that is
## not a flourish: a linear ramp 20500 -> 620 is at 10560 Hz half way through, which is
## still audibly transparent, so the entire audible part of the transition would happen in
## the last handful of frames and read as a hard cut anyway. Geometric interpolation is at
## 3565 Hz at the same instant — i.e. genuinely half way there by ear.
func _apply_wetness() -> void:
	if _world_bus < 0 or _lpf == null:
		return
	var on: bool = _wet > 0.0
	AudioServer.set_bus_effect_enabled(_world_bus, 0, on)
	AudioServer.set_bus_effect_enabled(_world_bus, 1, on)
	if not on:
		# Leave the parameters at their dry ends so a probe reading the bus topside sees
		# the resting state rather than whatever the last frame of the fade wrote.
		_lpf.cutoff_hz = DRY_CUTOFF_HZ
		_reverb.wet = 0.0
		_reverb.dry = 1.0
		return
	var s: float = smoothstep(0.0, 1.0, _wet)   # ease both ends; linear reads as a wipe
	_lpf.cutoff_hz = DRY_CUTOFF_HZ * pow(WET_CUTOFF_HZ / DRY_CUTOFF_HZ, s)
	_reverb.wet = WET_REVERB * s
	_reverb.dry = lerpf(1.0, WET_DRY, s)

## How submerged the mix currently sounds, 0..1. Read by probes; nothing in the game
## depends on it (the treatment is all on the bus).
##
## HOW TO VERIFY THIS WITHOUT EARS — audio cannot be screenshotted, so a probe reads the
## bus back instead of trusting anything written here. `_wet` is the state; the AudioServer
## is the ground truth, and the two must be checked separately or the test is measuring
## itself (see the s34 seal probe in docs/AGENT_TRAPS.md):
##
##     var w := AudioServer.get_bus_index("World")
##     AudioServer.get_bus_send(w)                        # -> "Master"
##     AudioServer.get_bus_effect_count(w)                # -> 2, and exactly 2 after a reload
##     AudioServer.is_bus_effect_enabled(w, 0)            # false topside, true submerged
##     AudioServer.get_bus_effect(w, 0).cutoff_hz         # 20500 topside -> 620 submerged
##     AudioServer.get_bus_effect(w, 1).wet               # 0.0 topside -> 0.42 submerged
##
## and that the treatment REACHES the world: every AudioStreamPlayer(3D) under /root/Ambience
## and under StormSystem's RainAudio must report bus == "World", not "Master" — that is the
## assertion that would have caught the whole feature being routed around the filter. The
## transition itself is checked by calling AudioDirector.set_underwater(true) and stepping
## frames: cutoff_hz must fall MONOTONICALLY over ~0.57 s rather than jump, and a square
## wave faster than ENTER_DWELL (0.05 s half-period) must leave underwater_wetness() at
## exactly 0.0 with the effect still disabled.
func underwater_wetness() -> float:
	return _wet

# ----------------------------------------------------------------------------- the buses
#
# BUILT IN CODE, NOT AS A default_bus_layout.tres, for the same reason the rig is built in
# code: a .tres bus layout is an opaque table with nowhere to put the reasoning above, it
# cannot be diffed usefully, and it would put the audio contract in a file that nothing
# else in this project's build reads. Everything here is idempotent, so a harness that
# re-enters the autoload or a scene reload cannot stack a second filter on the bus.

func _build_buses() -> void:
	_world_bus = _ensure_bus(BUS_WORLD)
	_ui_bus = _ensure_bus(BUS_UI)
	# Reuse the pair if it is already exactly what we want. The casts do the checking:
	# anything other than [low-pass, reverb] in that order leaves one of them null and
	# falls through to a full rebuild, so a hot-reload cannot stack a second filter on the
	# bus and a half-built bus cannot leave _apply_wetness dereferencing a null.
	_lpf = null
	_reverb = null
	if AudioServer.get_bus_effect_count(_world_bus) == 2:
		_lpf = AudioServer.get_bus_effect(_world_bus, 0) as AudioEffectLowPassFilter
		_reverb = AudioServer.get_bus_effect(_world_bus, 1) as AudioEffectReverb
	if _lpf == null or _reverb == null:
		while AudioServer.get_bus_effect_count(_world_bus) > 0:
			AudioServer.remove_bus_effect(_world_bus, 0)
		# ORDER MATTERS: filter first, then reverb, so the tail is built out of already
		# muffled signal. Reverb-then-filter gives a bright room heard through water,
		# which is the wrong way round — the water IS the room.
		#
		# EVERY LINE HERE OVERRIDES A DEFAULT THAT WOULD HAVE BEEN WRONG, and the defaults
		# were read off the live engine rather than assumed: a fresh
		# AudioEffectLowPassFilter is 2000 Hz (so an un-set filter low-passes the whole
		# game from boot), `db` is FILTER_6DB (-18 dB three octaves up, nowhere near
		# underwater), and a fresh AudioEffectReverb is wet 0.5 (the rig would sit in a
		# room before anyone dived). Nothing here is neutral by omission.
		_lpf = AudioEffectLowPassFilter.new()
		_lpf.db = AudioEffectFilter.FILTER_12DB
		_lpf.resonance = 0.2   # default 0.5 rings at the corner; water does not whistle
		AudioServer.add_bus_effect(_world_bus, _lpf)
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = 0.85       # everywhere at once, no walls to find
		_reverb.damping = 0.75         # dark tail, matching what the filter already did
		_reverb.spread = 1.0
		_reverb.hipass = 0.05
		_reverb.predelay_msec = 20.0   # the medium is ON you: no distance, no slap
		_reverb.predelay_feedback = 0.25
		AudioServer.add_bus_effect(_world_bus, _reverb)
	# The resting state is written in ONE place — here — so "what does the bus look like
	# topside" has a single answer whether the pair was just built or adopted.
	_lpf.cutoff_hz = DRY_CUTOFF_HZ
	_reverb.wet = 0.0
	_reverb.dry = 1.0
	# Topside is the common case and it pays nothing: both effects are switched off at the
	# bus, so the World bus is a straight pass-through until the first dive.
	AudioServer.set_bus_effect_enabled(_world_bus, 0, false)
	AudioServer.set_bus_effect_enabled(_world_bus, 1, false)

func _ensure_bus(bus_name: String) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, BUS_MASTER)
	return idx

## THE WORLD'S BEDS ARE NOT CREATED IN THIS FILE, and the filter is worthless if it does
## not reach them. scripts/world/ambience.gd (5 beds + an 8-deep footstep pool) and
## scripts/world/rain_audio.gd (3 loops) both hard-code `bus = "Master"`, which routes them
## AROUND World — leaving underwater sounding exactly like topside, i.e. exactly the bug
## this whole section exists to fix. The permanent fix is one word in each of those three
## lines (ambience.gd:115 and :122, rain_audio.gd:44 -> BUS_WORLD); they are owned
## elsewhere, so until that lands this adopts anything still pointed at Master.
##
## It only ever moves players that are ON Master, so it is a silent no-op the day those
## lines change, and it cannot fight an owner who has deliberately chosen another bus.
func _adopt_world_players() -> void:
	var amb: Node = get_node_or_null("/root/Ambience")
	if amb != null:
		_adopt_from(amb, 1)          # beds and step pool are direct children
	var scn: Node = get_tree().current_scene
	if scn == null:
		return
	# StormSystem is a direct child of Main and owns RainAudio, whose players are its own
	# children. Found by duck-typing rather than `is StormSystem` so this autoload keeps
	# no compile-time dependency on a world script.
	for c in scn.get_children():
		if c.has_method("is_storming"):
			_adopt_from(c, 2)

func _adopt_from(n: Node, depth: int) -> void:
	for c in n.get_children():
		if c is AudioStreamPlayer:
			if String((c as AudioStreamPlayer).bus) == BUS_MASTER:
				(c as AudioStreamPlayer).bus = BUS_WORLD
		elif c is AudioStreamPlayer3D:
			if String((c as AudioStreamPlayer3D).bus) == BUS_MASTER:
				(c as AudioStreamPlayer3D).bus = BUS_WORLD
		elif depth > 1:
			_adopt_from(c, depth - 1)

func _fade(bed_name: String, target_db: float, duration: float = 2.5) -> void:
	var p: AudioStreamPlayer = _beds.get(bed_name)
	if p == null:
		return
	var want: float = target_db
	# wind/sea/hum -> Ambience; rain -> RainAudio. All four situational beds are mixed
	# elsewhere now, so this node holds their ids but drives them to silence here.
	if AMBIENCE_OWNED.has(bed_name) or bed_name == "rain":
		want = -80.0
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
	# Master mix trim: the single lever that tames every one-shot for volume-up play.
	volume_db += float(SHOT_TRIM.get(shot_name, 0.0))
	if world_pos == Vector3.ZERO:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		# UI bus: this path is the player's own close, non-diegetic sounds and it must NOT
		# go through the water filter. Three call sites use it today — main.gd's airlock
		# hiss, item_effects' hiss, PlayerState's eat — and all three are things you do
		# with your hands, in your own head, on dry land. Move one to a positional call if
		# it ever needs to belong to the world instead.
		p.bus = BUS_UI
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.volume_db = volume_db
		p3.bus = BUS_WORLD   # everything with a position is in the water with you
		p3.max_distance = 40.0 * night_range_multiplier
		p3.unit_size = 6.0 * night_range_multiplier
		get_tree().current_scene.add_child(p3)
		p3.global_position = world_pos
		p3.finished.connect(p3.queue_free)
		p3.play()

## NOTE (s11): attach_loop — the looping claw-step timer emitter — is deleted. Its only
## caller was the old crab, and a repeating creature cue on a timer is exactly the
## design that produced the constant jingling. Creature audio is one-shots, event-driven.
