extends Node
## THE REAL SAVE FLOW, run as the app runs it — two separate PROCESSES, like a real quit
## and relaunch. BootSaveProbe already proves the restore code works inside one process;
## the owner still lost everything, so the hole must live in what the app does AROUND that
## code: the start-screen boot, the autoload clock, the slot handshake.
##   Process A:  godot --headless --path . res://tests/SaveFlowProbe.tscn -- phase=a
##   Process B:  godot --headless --path . res://tests/SaveFlowProbe.tscn -- phase=b
func _ready() -> void:
	var mode: String = "a"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("phase="):
			mode = arg.substr(6)
	if mode == "a":
		await _session_a()
	elif mode == "b":
		await _session_b()
	else:
		await _session_c()
	get_tree().quit()

func _slot_dump(tag: String) -> void:
	var p: String = "user://saltline_slot_1.json"
	if not FileAccess.file_exists(p):
		print("[flow] %s: slot1 MISSING" % tag)
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	print("[flow] %s: slot1 hotbar=%s inv=%s phase=%s day=%s" % [tag,
		str(d.get("hotbar")), str(d.get("inventory")), str(d.get("phase")), str(d.get("day_count"))])

func _session_a() -> void:
	SaveManager.begin_new_game(1)
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(8.0).timeout
	PlayerState.add_item("crude_knife")
	PlayerState.add_item("fish_herring")
	PlayerState.add_item("scrap_metal")
	PlayerState.add_item("scrap_metal")
	print("[flow] A live: hotbar=", PlayerState.hotbar)
	var ok: bool = SaveManager.save_game()
	print("[flow] A save_game -> ", ok, " active_slot=", SaveManager.active_slot)
	_slot_dump("A after manual save")

func _session_b() -> void:
	# THE APP'S OWN BOOT: the start screen is the main scene and the autoloads are already
	# ticking. Instantiate the REAL start screen and idle on it, dumping the slot file —
	# if anything writes it while we sit on the menu, that is the wipe.
	_slot_dump("B at launch, before menu")
	var menu = load("res://scenes/StartScreen.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(4.0).timeout
	_slot_dump("B after 4s on the menu")
	# Continue, exactly as the button does it.
	SaveManager.begin_continue(1)
	menu.queue_free()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(10.0).timeout
	print("[flow] B live after Continue: hotbar=", PlayerState.hotbar, " inv=", PlayerState.inventory)
	_slot_dump("B after load settled")

## THE WIPE, RE-ENACTED — and now it must be a no-op. A harness-style boot: Main as a
## CHILD (not the scene root), nobody picks a slot, and the clock is forced through DUSK
## exactly the way the phase-sweeping probes do it. Before the fix this overwrote slot 1
## with an empty world; the assertion is that the file does not change by a byte.
func _session_c() -> void:
	var before: String = FileAccess.get_file_as_string("user://saltline_slot_1.json") \
		if FileAccess.file_exists("user://saltline_slot_1.json") else ""
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(8.0).timeout
	print("[flow] C active_slot=", SaveManager.active_slot, " (must be 0 — probe never chose one)")
	GameClock.force_phase(GameClock.Phase.DUSK)
	GameClock.force_phase(GameClock.Phase.DAWN)
	await get_tree().create_timer(1.0).timeout
	var after: String = FileAccess.get_file_as_string("user://saltline_slot_1.json") \
		if FileAccess.file_exists("user://saltline_slot_1.json") else ""
	var ok: bool = (before == after) and SaveManager.active_slot == 0
	print("[flow] C %s: forced DUSK+DAWN in a slotless harness %s the save file" % [
		"PASS" if ok else "FAIL", "did not touch" if before == after else "REWROTE"])
