extends Node3D
## PROMO PHOTOSHOOT — 20 cinematic environmental frames of SALTLINE-1, shot in the real
## Main scene at authored times of day and weather. Saves 1920x1080 PNGs to /tmp/shoot/.
##
## Run (needs a real rendering context — headless renders blank):
##   godot --path . --resolution 1920x1080 res://tests/PhotoShoot.tscn
##
## Three things this harness has to get right, all inherited from world_shot.gd's
## hard-won notes plus one of its own:
##  * The rain emitter FOLLOWS THE PLAYER (StormSystem._follow_player), so a storm frame
##    must teleport the player to the lens or it photographs dry air.
##  * TIME OF DAY is phase + fraction, not phase alone. SunController maps DAWN f=0 to a
##    sun 8 degrees BELOW the horizon and DAY f=0.5 to 56 degrees up, so golden hour is a
##    specific fraction inside DUSK/DAWN — set GameClock._phase_elapsed_sec, don't just
##    force the phase and hope.
##  * Night frames need POWER. The floodlights and every mains fixture are gated on the
##    "topside_floodlights" circuit the breaker puzzle opens; without it a night shot is
##    a black rectangle with a moon in it.

const OUT_DIR := "/tmp/shoot"
const SETTLE := 1.5          ## seconds after a camera move, so rain fills the frame
const PHASE_SETTLE := 1.2    ## extra beat when the sun has to travel

var _cam: Camera3D
var _player: Node3D
var _main: Node3D
var _storm: Node

# name, phase, fraction-through-phase, eye, aim, fov, flags("storm"/"power")
const SHOTS := [
	# ---------------------------------------------------------------- first light
	["01_arrival_dawn",     "dawn", 0.72, Vector3(78, 9, -58),  Vector3(6, 20, -4),   50.0, ""],
	["02_silhouette_dawn",  "dawn", 0.55, Vector3(-72, 15, 44), Vector3(0, 24, 0),    45.0, ""],
	["03_legs_dawn",        "dawn", 0.85, Vector3(34, 3.2, -44), Vector3(12, 22, -12), 62.0, ""],
	# ---------------------------------------------------------------- full daylight
	["04_broadside_day",    "day",  0.50, Vector3(96, 31, 4),   Vector3(0, 22, 0),    40.0, ""],
	["05_derrick_up",       "day",  0.42, Vector3(1, 19.2, 7),  Vector3(0, 46, -2),   72.0, ""],
	["06_stack_terrace",    "day",  0.38, Vector3(-15, 19.6, -7), Vector3(14, 26, 9), 60.0, ""],
	["07_ops_lookout",      "day",  0.55, Vector3(13, 41, -15), Vector3(26, 39, -2),  55.0, ""],
	["08_from_the_lookout", "day",  0.48, Vector3(25.5, 40, -1.5), Vector3(-6, 20, 7), 74.0, ""],
	["09_stair_tower",      "day",  0.60, Vector3(38, 13, -13), Vector3(26, 22, -2),  55.0, ""],
	["10_wet_deck",         "day",  0.45, Vector3(29, 4.6, -21), Vector3(12, 2.6, -10), 70.0, ""],
	["11_boat_landing",     "day",  0.52, Vector3(27, 5.2, -27), Vector3(16, 2.6, -23), 62.0, ""],
	["12_crane_deck",       "day",  0.35, Vector3(-4, 20.4, -6), Vector3(18, 19, -16), 66.0, ""],
	# ---------------------------------------------------------------- golden hour
	["13_golden_wide",      "dusk", 0.28, Vector3(-84, 21, -52), Vector3(0, 22, 0),   45.0, ""],
	["14_golden_deck",      "dusk", 0.34, Vector3(-21, 19.6, 15), Vector3(16, 22, 1), 65.0, ""],
	# ---------------------------------------------------------------- the squall
	["15_storm_approach",   "day",  0.30, Vector3(72, 17, -47), Vector3(0, 22, 0),    50.0, "storm"],
	["16_storm_deck",       "day",  0.30, Vector3(11, 20.6, -7), Vector3(-15, 19, -15), 70.0, "storm"],
	["17_storm_wet_deck",   "day",  0.30, Vector3(25, 4.9, -13), Vector3(13, 2.4, -19), 72.0, "storm"],
	["18_storm_tower",      "dusk", 0.20, Vector3(40, 21, -15), Vector3(26, 27, -2),  55.0, "storm"],
	# ---------------------------------------------------------------- after dark
	["19_night_lit",        "night", 0.5, Vector3(62, 21, -42), Vector3(0, 20, 0),    50.0, "power"],
	["20_night_storm",      "night", 0.5, Vector3(56, 15, -39), Vector3(0, 21, 0),    50.0, "storm,power"],
]

func _all_nodes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

func _phase_id(name_: String) -> int:
	match name_:
		"dawn": return GameClock.Phase.DAWN
		"day": return GameClock.Phase.DAY
		"dusk": return GameClock.Phase.DUSK
		_: return GameClock.Phase.NIGHT

## Put the clock at an exact point INSIDE a phase. GameClock emits time_updated with
## _phase_elapsed_sec / duration every frame, and SunController drives elevation, ambient
## colour, star fade and moon from that fraction — so this is the whole time-of-day dial.
func _set_time(phase_name: String, frac: float) -> void:
	var ph: int = _phase_id(phase_name)
	GameClock.force_phase(ph)
	var dur: float = float(GameClock.phase_durations_minutes[ph]) * 60.0
	GameClock.set("_phase_elapsed_sec", clampf(frac, 0.0, 0.999) * dur)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Pin the frame size. Left to the OS the window gets retina-scaled mid-run and the
	# last frames came out 2880x1800 while the rest were 1920x1080.
	get_viewport().size = Vector2i(1920, 1080)
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_cam = Camera3D.new()
	_cam.far = 4000.0            # the far shots look back at the rig from ~100 m out
	add_child(_cam)
	_cam.current = true
	# Let the world assemble: props stream in over ~1 s, CSG cooks, fauna take a step.
	await get_tree().create_timer(5.0).timeout

	_player = get_tree().get_first_node_in_group("player")
	if _player:
		# Frozen: we drive it as the rain emitter's anchor, and a live CharacterBody3D
		# would fall out of every position we put it in.
		_player.set_physics_process(false)
		_player.set_process(false)
		if _player is CollisionObject3D:
			(_player as CollisionObject3D).set_collision_layer_value(1, false)
	for c in _main.get_children():
		if c is StormSystem:
			_storm = c
			break
	# The HUD is a promo shoot's worst enemy — stat bars, the hotbar, the objective line
	# and the journal button over every frame. HUD extends CanvasLayer, which is NOT a
	# CanvasItem, so a `is CanvasItem` guard silently skips it and photographs the lot.
	# Hide the layer itself, and belt-and-braces any CanvasItem layers too.
	for hud in get_tree().get_nodes_in_group("hud"):
		if hud is CanvasLayer:
			(hud as CanvasLayer).visible = false
		elif hud is CanvasItem:
			(hud as CanvasItem).visible = false
	for n in _all_nodes(get_tree().root):
		if n is CanvasLayer and n != get_viewport():
			(n as CanvasLayer).visible = false

	var shot_no: int = 0
	var last_phase: String = ""
	for s in SHOTS:
		shot_no += 1
		var flags: String = String(s[6])
		var storming: bool = flags.contains("storm")
		var powered: bool = flags.contains("power")

		# Power gates the floodlights, the mains fixtures and the deck's LightZones.
		if powered:
			PowerGrid.power_circuit("topside_floodlights")
		else:
			PowerGrid.lose_circuit("topside_floodlights")

		_set_time(String(s[1]), float(s[2]))
		if String(s[1]) != last_phase:
			last_phase = String(s[1])
			await get_tree().create_timer(PHASE_SETTLE).timeout

		if _storm:
			# RAGING(2) / CLEAR(0) — set directly so the squall is at full strength for
			# the frame instead of ramping in over its authored 22 s.
			_storm.set("_intensity", 1.0 if storming else 0.0)
			_storm.set("_phase", 2 if storming else 0)

		var eye: Vector3 = s[3]
		var aim: Vector3 = s[4]
		if _player and storming:
			_player.global_position = eye     # the rain box rides the player
		_cam.global_position = eye
		_cam.look_at(aim, Vector3.UP)
		_cam.fov = float(s[5])
		_cam.current = true
		await get_tree().create_timer(SETTLE).timeout

		var img: Image = get_viewport().get_texture().get_image()
		var path: String = "%s/%s.png" % [OUT_DIR, String(s[0])]
		img.save_png(path)
		print("[%2d/20] %-20s %s  %s%s" % [shot_no, String(s[0]), String(s[1]),
			"storm " if storming else "", "lit" if powered else ""])
	print("photoshoot complete -> %s" % OUT_DIR)
	get_tree().quit()
