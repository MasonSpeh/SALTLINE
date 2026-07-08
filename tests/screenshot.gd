extends Node
## Visual verification harness: boots Main windowed, moves the player camera through
## key vantage points across time phases, saves PNGs to /tmp. Not shipped.

var main: Node3D

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	main._countdown = 0.0   # skip cold open lock
	main.hud.fade_rect.color.a = 0.0

	await _shot(Vector3(24, 2.2, -18), -140.0, -5.0, GameClock.Phase.DAWN, "sl_wetdeck_sphl")
	await _shot(Vector3(-22, 19.2, -3), 235.0, -4.0, GameClock.Phase.DAY, "sl_topside_day")
	await _shot(Vector3(3.5, 35.5, -18), 175.0, -18.0, GameClock.Phase.DAY, "sl_lookout")
	await _shot(Vector3(26.5, 11.2, 4.5), 155.0, -5.0, GameClock.Phase.DAY, "sl_breaker_room")
	GameClock.force_phase(GameClock.Phase.DUSK)
	await get_tree().create_timer(1.0).timeout
	PowerGrid.power_circuit("topside_floodlights")
	await _shot(Vector3(-8, 19.4, -1), 250.0, -8.0, GameClock.Phase.NIGHT, "sl_night_lit")
	get_tree().quit()

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, phase: GameClock.Phase, name_: String) -> void:
	GameClock.force_phase(phase)
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.velocity = Vector3.ZERO
	p.input_locked = true
	await get_tree().create_timer(1.2).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/%s.png" % name_)
	print("saved /tmp/%s.png" % name_)
