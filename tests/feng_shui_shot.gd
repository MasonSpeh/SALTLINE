extends Node
## Visual check for the placement pass: photographs the corridors and the rooms whose
## dressing was rearranged, so the layout can be judged as a lived-in space rather than
## trusted from coordinates. Windowed (needs a real viewport).
##
## Run: godot --path . res://tests/FengShuiShot.tscn -- <output_dir>
## Writes <output_dir>/fs_*.png (default /tmp).

var main: Node3D
var _dir: String = "/tmp"

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]
	print("[fs] booting, output -> ", _dir)
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(9.0).timeout   # let the dressing stream in and settle
	print("[fs] world up")
	main._countdown = 0.0
	if main.hud != null and main.hud.fade_rect != null:
		main.hud.fade_rect.color.a = 0.0
	GameClock.force_phase(GameClock.Phase.DAY)
	# Positions are FEET, one deck-plate above the floor, so the eye lands ~1.7m up and
	# stays inside the room. Yaw convention: forward = (-sin(yaw), 0, -cos(yaw)).
	# Corridors first — the complaint that started this pass.
	await _shot(Vector3(-9.5, 18.15, 11.0), 90.0, -6.0, "fs_bunk_corridor")
	await _shot(Vector3(26.0, 21.75, 12.0), 90.0, -4.0, "fs_deckB_corridor")
	await _shot(Vector3(22.0, 28.75, 14.0), 90.0, -4.0, "fs_deckD_corridor")
	# Rooms whose furniture moved.
	await _shot(Vector3(-23.5, 18.15, 14.5), 72.0, -8.0, "fs_bunk_nook")
	await _shot(Vector3(-17.5, 18.15, 16.6), -29.0, -10.0, "fs_bunk_cabin")
	await _shot(Vector3(19.0, 18.15, 11.2), -106.0, -8.0, "fs_rec_room")
	await _shot(Vector3(25.2, 18.15, 15.4), -170.0, -4.0, "fs_rec_shelf")
	await _shot(Vector3(6.0, 18.15, 12.0), 180.0, -8.0, "fs_galley")
	await _shot(Vector3(22.5, 2.15, -16.0), -59.0, -16.0, "fs_wet_bench")
	await _shot(Vector3(19.5, 28.75, 15.9), 155.0, -12.0, "fs_workshop")
	print("[fs] done")
	get_tree().quit(0)

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [_dir, name_]
	var err: int = img.save_png(path)
	print("[fs] saved ", path, " err=", err)
