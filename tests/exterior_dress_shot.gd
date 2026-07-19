extends Node3D
## Photographs the west alley (Bay 4) and the machine-shop roof. exterior_dress.gd is
## now wired into rig_builder.gd in production, so this harness just boots the real
## Main and flies a camera around it — no injection (that would double-build the alley).
##
## Run WINDOWED (the viewport texture is empty headless):
##   godot --path . res://tests/ExteriorDressShot.tscn
## PNGs land in the scratchpad as ed_<name>.png.

const OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/87d5de70-f27c-48d3-bab9-cb1e9a8f822d/scratchpad"

# name, eye, aim, fov, night
const SHOTS := [
	["alley_east", Vector3(-9.0, 19.8, -0.9), Vector3(-27.0, 18.9, -1.1), 78.0, false],
	["alley_west", Vector3(-28.8, 19.8, -1.0), Vector3(-11.0, 18.9, -0.8), 78.0, false],
	["alley_south_band", Vector3(-19.0, 19.5, 2.2), Vector3(-19.6, 18.7, -5.2), 74.0, false],
	["alley_north_band", Vector3(-19.4, 19.5, -4.2), Vector3(-19.0, 18.8, 3.6), 74.0, false],
	["alley_weld_bay", Vector3(-13.6, 19.6, -1.6), Vector3(-17.4, 18.8, -4.8), 66.0, false],
	["alley_pipe_rack", Vector3(-21.2, 19.4, -1.8), Vector3(-25.6, 18.7, -5.0), 66.0, false],
	["alley_muster", Vector3(-15.4, 19.9, -1.4), Vector3(-11.4, 18.5, 2.0), 68.0, false],
	["alley_ladder", Vector3(-11.8, 19.9, -2.2), Vector3(-14.9, 20.4, -5.4), 62.0, false],
	["alley_night", Vector3(-9.4, 19.8, -1.0), Vector3(-27.0, 19.0, -1.1), 78.0, true],
	["roof_from_deck", Vector3(-10.0, 19.2, -12.0), Vector3(-22.0, 23.4, -13.5), 62.0, false],
	["roof_low_sw", Vector3(-46.0, 15.0, -34.0), Vector3(-22.5, 23.6, -13.0), 46.0, false],
	["roof_low_nw", Vector3(-52.0, 16.5, 12.0), Vector3(-22.0, 23.4, -12.5), 44.0, false],
	["roof_walk", Vector3(-15.6, 23.3, -6.8), Vector3(-25.0, 22.3, -14.5), 74.0, false],
	["roof_mast", Vector3(-20.0, 22.6, -11.4), Vector3(-26.4, 26.5, -16.4), 66.0, false],
]

var _cam: Camera3D
var _main: Node3D

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.far = 900.0
	print("[eds] world added, waiting")
	await get_tree().create_timer(4.0).timeout
	print("[eds] wait done")
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player:
		player.set_physics_process(false)
		player.set_process(false)
		player.global_position = Vector3(120, 60, 120)   # out of every frame
	# The alley lamps are on the topside floodlight circuit; light it so the night
	# shot shows whether the fixtures actually throw light where they are bolted.
	print("[eds] player parked")
	PowerGrid.power_circuit("topside_floodlights")
	print("[eds] circuit lit")
	var night: bool = false
	GameClock.force_phase(GameClock.Phase.DAY)
	await get_tree().create_timer(0.4).timeout
	print("[eds] entering shot loop")
	for s in SHOTS:
		if bool(s[4]) != night:
			night = bool(s[4])
			GameClock.force_phase(GameClock.Phase.NIGHT if night else GameClock.Phase.DAY)
			await get_tree().create_timer(0.6).timeout
		_cam.global_position = s[1]
		_cam.look_at(s[2], Vector3.UP)
		_cam.fov = s[3]
		_cam.current = true
		await get_tree().create_timer(0.25).timeout
		get_viewport().get_texture().get_image().save_png("%s/ed_%s.png" % [OUT, s[0]])
		print("shot: ", s[0])
	get_tree().quit()
