extends Node
## Boots the REAL StartScreen as current_scene, presses BEGIN, and watches the
## scene change into Main — the exact path the player crashes on.
func _ready() -> void:
	var ss = load("res://scenes/StartScreen.tscn").instantiate()
	get_tree().root.add_child.call_deferred(ss)
	await get_tree().process_frame
	get_tree().current_scene = ss
	await get_tree().process_frame
	print("BEGINPATH start screen up, pressing BEGIN")
	ss._start_game()
	for i in range(90):
		await get_tree().process_frame
	var cur = get_tree().current_scene
	print("BEGINPATH scene=%s player=%s" % [cur.name if cur else "NULL", cur.get("player") != null if cur else false])
	get_tree().quit()
