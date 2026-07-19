extends Node3D
## Underwater verification: boots the REAL Main, drives the PLAYER camera below the
## swell to a set of vantages, and photographs them. It must use the player's own
## camera (not a fresh fly-cam) because main.gd swaps the underwater Environment onto
## THAT camera when it dips under, and underwater_fx grades THAT environment — a
## separate camera would photograph the dry topside sky through clear air.
## Saves PNGs to the session scratchpad (writes elsewhere in /tmp can silently fail).

const OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/87d5de70-f27c-48d3-bab9-cb1e9a8f822d/scratchpad/uw_%s.png"

var _main: Node3D
var _player: Node3D
var _cam: Camera3D
var _storm: Node

# name, phase, eye, aim, storm  (night shot last: if the windowed run loses focus at
# the very end, the daylight shots are already saved)
const SHOTS := [
	# SNELL'S WINDOW. The old vantage sat 1.1 m under the surface and aimed 77 deg up: from
	# there the 96 deg cone overfills a 72 deg frame completely, so the rim — the entire
	# point of the effect — was never in shot and the capture could only ever be a wash of
	# window interior. Drop to 5 m and pitch 45 deg up: at that depth the disc subtends
	# about 11 m across at the surface, comfortably inside the frame, with the dark
	# total-internal-reflection field around it and the rig's legs for scale.
	["surface_up", "day", Vector3(16.0, -5.0, -6.0), Vector3(22.0, 1.0, -6.0), false],
	# Straight up from the same depth: the disc centred, so the rim is a full ring.
	["surface_up_axis", "day", Vector3(16.0, -6.0, -6.0), Vector3(17.6, 1.0, -5.0), false],
	# mid-water beside a leg — light shafts, caustics on the caisson, kelp
	["leg_shafts", "day", Vector3(15.0, -4.2, -6.0), Vector3(22.0, -5.5, -12.0), false],
	# the same mid-water leg shot during a storm — sediment murk, denser snow
	["leg_shafts_storm", "day", Vector3(15.0, -4.2, -6.0), Vector3(22.0, -5.5, -12.0), true],
	# a leg base planting into its scour pit + riprap
	["seabed_scour", "day", Vector3(14.5, -15.5, 3.5), Vector3(22.0, -22.0, 12.0), false],
	# the wreck field + reef communities on the bottom
	["seabed_wreck", "day", Vector3(12.0, -13.5, -30.0), Vector3(-1.0, -21.0, -47.0), false],
	# the reef ridge crown at night — corals, unfurled stars, a grazing nudibranch
	["reef_ridge_night", "night", Vector3(2.5, -10.5, -25.0), Vector3(9.0, -13.0, -30.0), false],
]

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout   # world + reef assemble
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_error("no player")
		get_tree().quit()
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	_cam = _player.get_node_or_null("Head/Camera3D")
	if _cam == null:
		push_error("no player camera")
		get_tree().quit()
		return
	_cam.current = true
	# Hide the HUD overlay so the water fills the frame (HUD is a CanvasLayer).
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	for c in _main.get_children():
		if c is StormSystem:
			_storm = c
			break
	var phase: String = ""
	for s in SHOTS:
		if s[1] != phase:
			phase = s[1]
			GameClock.force_phase(GameClock.Phase.NIGHT if phase == "night" else GameClock.Phase.DAY)
			await get_tree().create_timer(0.7).timeout
		if _storm:
			var storming: bool = s[4]
			_storm.set("_intensity", 1.0 if storming else 0.0)
			_storm.set("_phase", 2 if storming else 0)
		var eye: Vector3 = s[2]
		var aim: Vector3 = s[3]
		_player.global_position = eye        # Snell plane + rain box ride the player
		_cam.global_position = eye
		_cam.look_at(aim, Vector3.UP)
		_cam.fov = 72.0
		# let the env swap in, the grade settle, snow fall, storm ramp
		await get_tree().create_timer(1.5).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(OUT % s[0])
		print("uw shot: ", s[0], "  cam_y=", _cam.global_position.y)
	print("done")
	get_tree().quit()
