extends Node
## Cover-responsive rain ambience, created and driven by StormSystem.
##
## Three seamless, non-positional loops on the Master bus, crossfaded every frame
## from (a) storm intensity and (b) StormSystem's shelter raycast:
##   open  — full rich downpour when you're out under the open sky
##   metal — bright patter with individual pings under a close thin-steel roof
##   far   — deep muffled distant wash when a huge deck slab is high overhead
## Standing at the open lip of a roofed-but-open-sided space blends open back in;
## going under the waterline mutes the lot. Volumes lerp toward their targets with
## a -60 dB floor so the crossfades never click. This replaces the old harsh rain
## bed (rain_loop.wav is now silent, so AudioDirector's rain bed contributes none).

const OPEN_WAV := "res://audio/rain_open.wav"
const METAL_WAV := "res://audio/rain_metal.wav"
const FAR_WAV := "res://audio/rain_far.wav"

const FLOOR_DB := -60.0
const OPEN_PEAK := -5.0
const METAL_PEAK := -8.0
const FAR_PEAK := -5.0
const SMOOTH := 3.5            # db-lerp responsiveness (per second)
const METAL_MAX_DIST := 4.0   # roof this close reads as bright metal patter
const FAR_MAX_DIST := 12.0    # roof this far reads as fully muffled distant wash

var _open: AudioStreamPlayer
var _metal: AudioStreamPlayer
var _far: AudioStreamPlayer

# Targets pushed by StormSystem.set_state each frame.
var _intensity: float = 0.0
var _roof_dist: float = 1.0e9   # metres up to the nearest overhead roof (huge = open)
var _cover_frac: float = 0.0    # 0 = fully open overhead, 1 = fully roofed
var _muted: bool = false        # underwater

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open = _make(OPEN_WAV)
	_metal = _make(METAL_WAV)
	_far = _make(FAR_WAV)

func _make(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	# World, so rain is muffled from below like everything else (see audio_director).
	p.bus = "World"
	p.volume_db = FLOOR_DB
	add_child(p)
	if ResourceLoader.exists(path):
		var st: AudioStream = load(path)
		if st is AudioStreamWAV:
			# Loop the whole sample seamlessly. loop_end must come from the decoded
			# length, NOT data.size() — the importer stores these QOA-compressed, so
			# byte size bears no fixed relation to the frame count.
			var wav: AudioStreamWAV = st
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
		p.stream = st
		if st:
			# Fallback in case the platform ignores loop_mode: restart on finish.
			p.finished.connect(p.play)
			p.play()
	return p

## StormSystem feeds the mix each frame: storm intensity, the distance up to the
## nearest overhead roof (huge if none), the fraction of the up-cone that is
## roofed, and whether the player is submerged.
func set_state(intensity: float, roof_dist: float, cover_frac: float, muted: bool) -> void:
	_intensity = intensity
	_roof_dist = roof_dist
	_cover_frac = clampf(cover_frac, 0.0, 1.0)
	_muted = muted

func _process(delta: float) -> void:
	var t_open: float = FLOOR_DB
	var t_metal: float = FLOOR_DB
	var t_far: float = FLOOR_DB
	if not _muted and _intensity > 0.02:
		var cov: float = _cover_frac
		# Open downpour ducks as you move under solid cover, but never fully — a
		# little of the surrounding fall always bleeds in past edges and windows.
		var g_open: float = 1.0 - cov * 0.85
		# Close roof -> metal patter; high roof -> far muffled wash; blend between.
		var far_t: float = clampf(
			(_roof_dist - METAL_MAX_DIST) / (FAR_MAX_DIST - METAL_MAX_DIST), 0.0, 1.0)
		var g_metal: float = cov * (1.0 - far_t)
		var g_far: float = cov * far_t
		t_open = _mix_db(g_open, OPEN_PEAK)
		t_metal = _mix_db(g_metal, METAL_PEAK)
		t_far = _mix_db(g_far, FAR_PEAK)
	var a: float = clampf(delta * SMOOTH, 0.0, 1.0)
	if _open:
		_open.volume_db = lerpf(_open.volume_db, t_open, a)
	if _metal:
		_metal.volume_db = lerpf(_metal.volume_db, t_metal, a)
	if _far:
		_far.volume_db = lerpf(_far.volume_db, t_far, a)

## Linear layer gain (scaled by intensity) -> dB with a hard -60 floor.
func _mix_db(gain: float, peak: float) -> float:
	var g: float = clampf(gain, 0.0, 1.0) * clampf(_intensity, 0.0, 1.0)
	if g <= 0.0015:
		return FLOOR_DB
	return maxf(FLOOR_DB, peak + linear_to_db(g))
