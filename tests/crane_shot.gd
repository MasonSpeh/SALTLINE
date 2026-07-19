extends Node
## Crane-tower + doorframe verification: boots Main, flies the camera to vantages on the
## rebuilt crane (bays, boom over water, cab, findables) and two repaired doorframes,
## saves PNGs to the scratchpad.

const OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/87d5de70-f27c-48d3-bab9-cb1e9a8f822d/scratchpad"

var main: Node3D

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.5).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	var p: Node3D = main.player
	p._fly = true
	p.set_collision_layer_value(1, false)
	p.set_collision_mask_value(1, false)
	GameClock.force_phase(GameClock.Phase.DAY)

	# Crane read from the open topside deck: tower rising, boom raked out over water.
	await _shot(Vector3(20, 19.4, 2), 48.0, 27.0, "cr_from_deck")
	# From the water off the SE, looking NW at the tower and the boom over the sea.
	await _shot(Vector3(26, 20, -48), 135.0, 24.0, "cr_from_water")
	# Side elevation: are the bays concentric and the legs converging? (east looking west)
	await _shot(Vector3(30, 32, -14), 90.0, -4.0, "cr_bays_side")
	# The crane head close: king post, gantry, boom heel, cab, pendants.
	await _shot(Vector3(16, 37, -24), 125.0, 4.0, "cr_head")
	# Hook block hanging over the water at the boom tip.
	await _shot(Vector3(18, 31, -42), 111.0, -6.0, "cr_hook")
	# Machinery deck: the cab (glazed west face + door) and the boom-heel findables.
	await _shot(Vector3(-3, 36, -10), -54.0, -4.0, "cr_deck_findables")
	# Mid landing on the climb, with its kit.
	await _shot(Vector3(-5, 27, -14), -90.0, -6.0, "cr_landing")
	# DOORFRAMES head-on — the two annex doors that carried the floating-head bug.
	await _shot(Vector3(28.5, 6.95, -1.2), 180.0, 1.0, "df_machinery")
	await _shot(Vector3(23.5, 10.95, -1.2), 180.0, 1.0, "df_breaker")
	# A stack cabin door, head-on from the corridor (the systematic fix everywhere).
	await _shot(Vector3(0.5, 22.5, 12.6), 0.0, 0.0, "df_cabin")
	get_tree().quit()

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.velocity = Vector3.ZERO
	p.input_locked = true
	await get_tree().create_timer(0.8).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name_])
	print("saved %s.png" % name_)
