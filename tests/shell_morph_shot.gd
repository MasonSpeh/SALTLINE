extends Node3D
## IS THE MARBLING REALLY MOVING, AND IS IT REALLY SLOW? — proof for shell_marble.gdshader.
##
## "Make the pattern drift and morph" has two failure modes that look identical in a single
## screenshot: a pattern that is actually frozen, and one churning fast enough to be a lava
## lamp. So this photographs THE SAME SNAIL, from THE SAME CAMERA, in THE SAME LIGHT, at a
## spread of elapsed times, and measures how far the marbling has moved at each.
##
## THE MEASUREMENT IS A PAIRED ONE, and it has to be. A first version simply diffed the
## frames against t=0 and reported a difference that plateaued after twenty seconds — which
## would have meant the morph was far too fast. It was measuring the wrong thing. Two
## things in this shader move on their own clocks and neither is the pattern:
##
##   * the SHIMMER, sin(TIME * 0.8 + ...), a +/-28% brightness breath with a 7.9 s period;
##   * the PEDAL WAVE in vertex(), which displaces the mesh whether or not _process runs,
##     because it reads TIME directly.
##
## Both saturate a raw pixel difference within one of their own cycles and then sit there,
## drowning a morph that is deliberately a hundred times slower.
##
## So at each target time this takes TWO frames one frame apart: the live pattern, and then
## the same pattern with pattern_scroll forced to 0 — which is not a "frozen later state"
## but the t=0 field exactly, since the morph is the pure function mt = TIME * scroll with
## no integrated state. Same instant, same shimmer phase, same pose, same light: the only
## difference between that pair IS the accumulated morph. The pedal wave is switched off
## (mode = 0) on top of that so the silhouettes match to the pixel.
##
## What the numbers should say:
##   * ~0 at +2 s        -> nothing perceptible is happening moment to moment
##   * rising steadily   -> the field is genuinely evolving, not oscillating in place
##   * clearly big at +60 -> look back in a minute and it is a different shell
##
## The clock is REAL WALL TIME, deliberately. TIME in a Godot shader is engine uptime and
## is not something a harness can honestly fast-forward; a scaled clock would prove the
## shader responds to a number, not that the animal reads right at the rate it ships at.
##
## Run WINDOWED — the viewport texture comes back empty headless:
##   godot --path . res://tests/ShellMorphShot.tscn [out_dir]

const DEFAULT_OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/7cb79fc2-367f-4871-ad61-e3f271b05ed7/scratchpad/morph"
## Seconds after the reference frame. 2 s is "glance away and back", 20 s is "walk round
## it", 60 and 120 are "come back later" — the timescale the brief is written in.
const TIMES: Array[float] = [2.0, 20.0, 60.0, 120.0]
const GLOW: float = 1.6      ## a fixed night-ish level, so brightness cannot drift

var _out: String = DEFAULT_OUT
var _cam: Camera3D
var _snail: Node3D
var _mats: Array = []
var _scroll: float = 0.006

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)

	# A black box with one soft key light. No Main.tscn: the rig's floodlights, weather and
	# day cycle are all things that would change between two frames two minutes apart, and
	# every one of them would be charged to the shader.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.42, 0.55)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 0.9
	key.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	add_child(key)

	# The SHIPPING animal, not a mock-up of it: BloomFauna.LampSnail, which is what builds
	# the real generated mesh and dresses it in the real shell material.
	var cls: GDScript = load("res://scripts/world/bloom_fauna.gd")
	_snail = (cls as Object).get("LampSnail").new(0, Vector3.ZERO)
	add_child(_snail)
	await get_tree().create_timer(2.0).timeout
	_snail.global_position = Vector3.ZERO
	_snail.rotation = Vector3.ZERO
	# PIN EVERYTHING THAT IS NOT THE PATTERN: no crawl, no stalk sway, no glow pulse
	# (_process off), no pedal displacement (mode 0), no dimmer drift (fixed vein_energy).
	_snail.set_process(false)
	_mats = _snail.get("_vein_mats")
	for m in _mats:
		var sm: ShaderMaterial = m
		sm.set_shader_parameter("vein_energy", GLOW)
		sm.set_shader_parameter("mode", 0)
		_scroll = float(sm.get_shader_parameter("pattern_scroll"))
	print("[morph] %d shell materials, pattern_scroll = %.4f" % [_mats.size(), _scroll])

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.fov = 34.0
	# Close on the shell, slightly above, so the frame is nearly all marbling. A wide shot
	# would dilute the difference measurement with a lot of unchanging black.
	_cam.global_position = Vector3(0.0, 0.62, 1.15)
	_cam.look_at(Vector3(0.0, 0.30, 0.0), Vector3.UP)
	await get_tree().create_timer(0.6).timeout

	var t0: float = Time.get_ticks_msec() / 1000.0
	await _pair("t000")
	for target in TIMES:
		while (Time.get_ticks_msec() / 1000.0) - t0 < target:
			await get_tree().process_frame
		await _pair("t%03d" % int(target))
	# Pattern modes 1 (spiral bands) and 2 (flesh) are not touched by any of this and are
	# not this harness's job: tests/SnailMarbleShot.tscn is the project's existing look-check
	# for them, and photographs PyramidSnail — which wears both — from four angles.
	print("[morph] done -> %s" % _out)
	get_tree().quit()

## Two frames one frame apart: the live pattern, and the t=0 pattern under identical
## lighting, pose and shimmer phase. `<tag>.png` is the shell as it ships; `<tag>_ref.png`
## is where the marbling started. Their difference is the morph, and nothing else.
func _pair(tag: String) -> void:
	_set_scroll(_scroll)
	await _shot(tag)
	_set_scroll(0.0)
	await _shot(tag + "_ref")
	_set_scroll(_scroll)

func _set_scroll(v: float) -> void:
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("pattern_scroll", v)

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var f: String = "%s/%s.png" % [_out, tag]
	get_viewport().get_texture().get_image().save_png(f)
	print("shot: %s   (uptime %.1f s)" % [f, Time.get_ticks_msec() / 1000.0])
