extends Node
## Windowed verification harness for the redesigned StartScreen: instantiates it, lets the
## fog/rain/beacon/gull animate a moment, grabs a frame at two different clock offsets so
## the beacon sweep + gull land in different places, saves PNGs, quits. Not shipped.

const OUT_DIR: String = "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/798c10cb-cc7b-4118-8ad9-22ffc65cb417/scratchpad"

func _ready() -> void:
	var ss: Control = load("res://scenes/StartScreen.tscn").instantiate()
	add_child(ss)
	await get_tree().create_timer(2.2).timeout
	await _grab("loadscreen_after.png")
	await get_tree().create_timer(2.8).timeout
	await _grab("loadscreen_after_b.png")
	# Force the gull on-screen and catch a beam-toward-viewer sweep for the third frame.
	ss._gull_dir = 1.0
	ss._gull_speed = 26.0
	ss._gull_y = 250.0
	ss._gull_t = 16.0
	await get_tree().create_timer(0.6).timeout
	await _grab("loadscreen_after_c.png")
	get_tree().quit()

func _grab(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s" % [OUT_DIR, name_])
	print("saved %s/%s" % [OUT_DIR, name_])
