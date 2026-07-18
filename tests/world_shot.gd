extends Node3D
## In-world verification: boots the REAL Main scene, forces phases/storm, and
## photographs the fauna where they actually live — because the contact sheet can't
## catch a backwards swimmer, a floating snail, or rain indoors. Saves /tmp/ws_*.png.

var _cam: Camera3D

# name, phase ("day"/"night"), camera pos, look-at, extra ("storm" forces rain,
# "indoor" moves the camera under the deckhead to prove the rain stays out)
const SHOTS := [
	["underwater2", "day", Vector3(24.0, -1.6, -7.5), Vector3(19.2, -3.2, -12.0), ""],
	["leg_dusk", "night", Vector3(22.6, 2.6, -14.8), Vector3(19.4, 0.6, -11.9), ""],
	["dock_tools", "day", Vector3(16.8, 3.6, -9.0), Vector3(20.2, 2.0, -12.2), ""],
]

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	# Let the world assemble + fauna take their first steps.
	await get_tree().create_timer(2.0).timeout
	var storm: Node = null
	for c in main.get_children():
		if c is StormSystem:
			storm = c
			break
	for s in SHOTS:
		GameClock.force_phase(GameClock.Phase.NIGHT if s[1] == "night" else GameClock.Phase.DAY)
		if storm:
			storm.set("_intensity", 1.0 if s[4] == "storm" else 0.0)
			storm.set("_phase", 2 if s[4] == "storm" else 0)   # RAGING / CLEAR
		_cam.global_position = s[2]
		_cam.look_at(s[3], Vector3.UP)
		_cam.current = true
		await get_tree().create_timer(1.4).timeout   # settle: presence fades, rain falls
		get_viewport().get_texture().get_image().save_png("/tmp/ws_%s.png" % s[0])
		print("shot: ", s[0])
	get_tree().quit()
