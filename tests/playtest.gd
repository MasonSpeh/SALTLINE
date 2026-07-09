extends Node
## Headless playability smoke test: exercises the new player-facing features —
## cold-open skip, objective updates, prop grab/throw, crosshair targeting.

var failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		failures += 1
		printerr("FAIL  ", label)

func _ready() -> void:
	await _run()
	print("---")
	print("PLAYTEST FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout

	# Objective is set during cold open.
	_check(main.hud.objective_label.text.contains("pressure"), "objective shows during cold open")

	# Props spawned on the wet deck.
	var props: Array = []
	for c in main.get_children():
		if c is PhysProp:
			props.append(c)
	_check(props.size() == 3, "three grabbable props spawned (got %d)" % props.size())

	# Skip the cold open early.
	main._end_cold_open()
	await get_tree().process_frame
	_check(not main.rig.sphl_hatch.locked, "cold open skippable — hatch unlocks")
	_check(main.hud.objective_label.text.contains("power"), "objective advances after cold open")

	# Grab a prop and confirm carry state + crosshair prompt.
	var player: Node3D = main.player
	var prop: PhysProp = props[0]
	player.try_grab(prop)
	_check(player.carried == prop, "player can grab a prop")
	_check(prop.held_by == player, "prop knows it is held")
	_check(main.hud.prompt_label.text.contains("throw"), "carry prompt shows throw/drop")

	# Throw it — carry clears, impulse applied.
	player._throw_carried()
	await get_tree().physics_frame
	_check(player.carried == null, "throw releases the prop")
	_check(prop.linear_velocity.length() > 0.5, "thrown prop has velocity")

	# Crosshair targeting toggles with prompts.
	main.hud.set_targeting(true)
	_check(main.hud.crosshair.text == "◎", "crosshair swells when targeting")
	main.hud.set_targeting(false)
	_check(main.hud.crosshair.text == "·", "crosshair resets when not targeting")

	# Powering the circuit updates the objective.
	PowerGrid.power_circuit("topside_floodlights")
	await get_tree().process_frame
	_check(main.hud.objective_label.text.contains("light"), "objective updates on power restored")
