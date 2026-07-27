extends Node
## Visual check for the item-name popup + outline box, and the popup COOLDOWN added on top
## of it (owner request, 2026-07-27b: "only every 1-2 mins... like the waves"). Spawns two
## Takeables in front of the player one after another: item A should fire the popup, item B
## (looked at immediately after, while still on cooldown) should NOT re-fire it, even though
## its outline box and "[E] TAKE ..." chip both switch over normally.
## Not shipped — a throwaway harness, same spirit as tests/screenshot.gd.

var main: Node3D

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	GameClock.force_phase(GameClock.Phase.DAY)

	var p: Node3D = main.player
	# Clear open air above the sea, well away from any rig geometry, so the raycast has
	# nothing to hit but the item itself — the first attempt sat the item behind a bench
	# and the ray never acquired it.
	p._fly = true
	p.set_collision_layer_value(1, false)
	p.set_collision_mask_value(1, false)
	p.global_position = Vector3(200.0, 60.0, 200.0)
	p.rotation.y = deg_to_rad(0.0)
	p.get_node("Head").rotation.x = deg_to_rad(0.0)
	p.velocity = Vector3.ZERO
	p.input_locked = true

	var cam: Node = p.get_node("Head/Camera3D")
	var ray: Node = null
	for ch in cam.get_children():
		if ch is InteractionRay:
			ray = ch
			break
	var hud: Node = main.hud

	var item_a := Takeable.new()
	item_a.item_id = "water_bottle"
	item_a.display_name = "Water Bottle"
	item_a.build_box_visual(Vector3(0.18, 0.28, 0.18), Color(0.3, 0.6, 0.85))
	main.add_child(item_a)
	# 1.4m straight ahead of the player's facing (-Z at yaw 0), well inside REACH (2.6m),
	# lifted to roughly eye height (camera rides ~1.6m above the feet) so it isn't stuck
	# below frame.
	item_a.global_position = p.global_position + Vector3(0, 1.6, -1.4)

	# Let the ray's initial hatch-hint grace window (PROMPT_GRACE=1.0s from spawn) run out,
	# and let the physics ray catch up to the teleport, before the actual test starts. The
	# hatch was also this ray's first-ever target (during the 2s wait above, facing it at
	# spawn), so it already consumed a popup + started the cooldown — force it back to 0 so
	# item A below gets a clean, deterministic "first fire" for the test.
	await get_tree().create_timer(1.3).timeout
	ray._popup_cd = 0.0
	# item_a has been the ray's target throughout the wait above, so _announced already
	# equals it — force it back to null so the NEXT frame reads as a fresh acquisition,
	# same as if the player had just looked away and back.
	ray._announced = null
	await get_tree().create_timer(0.2).timeout

	print("--- ITEM A: fresh target, cooldown was 0 ---")
	print("popup_cd before: ", ray._popup_cd)
	print("label text: '%s'  alpha: %.2f" % [hud.item_name_label.text, hud.item_name_label.modulate.a])
	_shot("sl_cooldown_a_fires")
	print("popup_cd after A: ", ray._popup_cd, "  (>0 means the cooldown latched)")

	# Swap in item B immediately — well within the 60-120s cooldown A just started.
	var item_b := Takeable.new()
	item_b.item_id = "kelp_bundle"
	item_b.display_name = "Kelp Bundle"
	item_b.build_box_visual(Vector3(0.22, 0.3, 0.16), Color(0.25, 0.5, 0.3))
	main.add_child(item_b)
	item_a.global_position += Vector3(5, 0, 0)   # out of the ray's way
	item_b.global_position = p.global_position + Vector3(0, 1.6, -1.4)
	await get_tree().create_timer(0.8).timeout

	print("--- ITEM B: new target, still on A's cooldown ---")
	print("ray._current display_name: ", ray._current.display_name if ray._current else "null")
	print("chip text: '%s'  prompt_locked: %s  ray._shown: '%s'" %
		[hud.prompt_label.text, hud.prompt_locked, ray._shown])
	print("label text: '%s'  alpha: %.2f  (should still read Water Bottle, not Kelp Bundle)" %
		[hud.item_name_label.text, hud.item_name_label.modulate.a])
	_shot("sl_cooldown_b_suppressed")
	get_tree().quit()

func _shot(name_: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/%s.png" % name_)
	print("saved /tmp/%s.png" % name_)
