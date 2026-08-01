extends Node
## Windowed verification harness for the pause menu's new SAVE GAME control: builds the
## menu on its own (no rig — the panel is self-contained), opens it, presses Save, and
## grabs a frame of the result line. Not shipped.

const OUT_DIR: String = "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/15ed8fd9-cd5e-4dfc-a7e9-dd06f6024b19/scratchpad"

func _ready() -> void:
	SaveManager.slot_file_prefix = "pause_shot_slot_"
	SaveManager.active_slot = 2
	var menu := PauseMenu.new()
	add_child(menu)
	await get_tree().process_frame
	menu.toggle()
	await get_tree().create_timer(0.4).timeout
	await _grab("pause_menu_idle.png")
	# The button's own handler, so the shot proves the wiring and not a mock.
	menu._save_now()
	await get_tree().create_timer(0.3).timeout
	await _grab("pause_menu_saved.png")
	print("[pause_shot] note reads: %s" % menu._save_note.text)
	print("[pause_shot] slot on disk: %s" % str(SaveManager.slot_info(2)))
	SaveManager.erase_slot(2)
	get_tree().quit()

func _grab(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s" % [OUT_DIR, name_])
	print("saved %s/%s" % [OUT_DIR, name_])
