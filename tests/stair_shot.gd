extends Node
## Focused stair-tower verification: boots Main, flies the camera to key vantages on
## the rebuilt switchback + landings + ops room (now at y38), saves /tmp/st_*.png.

var main: Node3D

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	var p: Node3D = main.player
	p._fly = true
	p.set_collision_layer_value(1, false)
	p.set_collision_mask_value(1, false)
	GameClock.force_phase(GameClock.Phase.DAY)

	# A single flight topping out at its turn platform — the join under scrutiny.
	await _shot(Vector3(24, 8, -1.5), -73.0, -23.0, "st_join_mid")
	# Climbing POV up a flight.
	await _shot(Vector3(24, 2.4, -2.9), -90.0, 26.0, "st_climb_pov")
	# Deck-level turn: flight 4 top -> west platform -> deck door.
	await _shot(Vector3(27, 20, -2.0), 114.0, -22.0, "st_join_deck")
	# The top: flight 9 emerging into the ops-room floor (east end).
	await _shot(Vector3(24, 39.6, -6.0), -124.0, -16.0, "st_ops_top")
	# Inside the ops room, looking out.
	await _shot(Vector3(26, 39.6, 0.0), 0.0, -2.0, "st_ops_interior")
	# Annex access through the new north-wall doors.
	await _shot(Vector3(23.0, 10.7, -1.0), 180.0, 2.0, "st_breaker_access")
	await _shot(Vector3(28.5, 6.7, -1.0), 180.0, 2.0, "st_machinery_access")
	# The whole tower from the sea, and from the deck (is it "a lot higher"?).
	await _shot(Vector3(52, 24, -8.0), 103.0, 16.0, "st_exterior")
	await _shot(Vector3(10, 19, 6.0), -66.0, 30.0, "st_from_deck")
	get_tree().quit()

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.velocity = Vector3.ZERO
	p.input_locked = true
	await get_tree().create_timer(1.0).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/%s.png" % name_)
	print("saved /tmp/%s.png" % name_)
