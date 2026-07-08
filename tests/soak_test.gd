extends Node
## Full-playthrough soak (Phase 5 gate): runs the ENTIRE day loop at 20x clock speed —
## cold open -> day (power puzzle solved) -> dusk -> night (crab) -> dawn -> end card.
## Real duration ~2.5 min. Run: godot --headless res://tests/SoakTest.tscn

var failures: int = 0
var events: Dictionary = {}

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		failures += 1
		printerr("FAIL  ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep asserting after the end-card pause
	await _run()
	print("---")
	print("SOAK FAILURES: ", failures)
	get_tree().paused = false
	get_tree().quit(1 if failures > 0 else 0)

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	GameClock.time_scale = 20.0
	for sig in ["dawn", "day", "dusk", "night"]:
		GameClock.connect(sig, func() -> void: events[sig] = true)

	# Cold open at real speed would take 90s; compress it.
	main._countdown = 1.0
	await get_tree().create_timer(1.5).timeout
	_check(not main.rig.sphl_hatch.locked, "cold open completed, hatch unlocked")

	# Wait for DAY, then solve the power puzzle the way a player would.
	await _wait_for_phase(GameClock.Phase.DAY, 30.0)
	_check(events.get("day", false), "day phase reached")
	var player: Node3D = main.player
	var cable: CableSegment = null
	var breaker: BreakerPanel = null
	for c in main.rig.get_children():
		if c is CableSegment:
			cable = c
		elif c is BreakerPanel:
			breaker = c
	PlayerState.add_item("cable_spool")
	cable.interact("CONNECT", player)
	breaker.interact("OPERATE", player)
	_check(PowerGrid.is_powered("topside_floodlights"), "power puzzle solved during day")

	# Park the player in the lit safe zone and let the night happen.
	player.global_position = Vector3(0, 19.4, 0)
	await _wait_for_phase(GameClock.Phase.NIGHT, 120.0)
	_check(events.get("dusk", false), "dusk fired (PA beat path)")
	await get_tree().create_timer(0.5).timeout
	var crab: LamplightCrab = null
	for c in main.get_children():
		if c is LamplightCrab:
			crab = c
	_check(crab != null, "crab spawned at night")
	_check(LightZone.point_is_safe(get_tree(), player.global_position), "player safe in lit zone")

	# Ride out the night to the second dawn.
	await _wait_for_phase(GameClock.Phase.DAWN, 120.0)
	_check(GameClock.day_count >= 1, "night completed -> day_count advanced")
	_check(main._ending, "end sequence armed at dawn")
	if crab:
		await get_tree().create_timer(1.0).timeout
		_check(crab.state == LamplightCrab.State.RETREAT or not is_instance_valid(crab),
			"crab retreating (or gone) at dawn")

	# The 30s of peace runs on real time; then the card.
	await get_tree().create_timer(31.5).timeout
	_check(main.hud.end_card.visible, "end card shown after 30s of peace")
	_check(get_tree().paused, "world paused behind the card")
	_check(FileAccess.file_exists("user://saltline_autosave.json"), "autosave written")

func _wait_for_phase(phase: GameClock.Phase, timeout_sec: float) -> void:
	var elapsed: float = 0.0
	while GameClock.current_phase != phase and elapsed < timeout_sec:
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25
	if GameClock.current_phase != phase:
		failures += 1
		printerr("FAIL  timeout waiting for phase ", GameClock.Phase.keys()[phase])
