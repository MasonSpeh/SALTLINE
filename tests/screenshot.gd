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
	await _shot(Vector3(23.5, 3.2, -13.5), -125.0, -14.0, GameClock.Phase.DAY, "sl_props")
	# Water-level overhaul vantages.
	await _shot(Vector3(24.0, 3.8, -20.4), 60.0, -8.0, GameClock.Phase.DAY, "sl_sphl_profile")
	await _shot(Vector3(24.5, 3.6, -19.5), 75.0, -6.0, GameClock.Phase.DAY, "sl_dock_landing")
	await _shot(Vector3(14.0, 3.2, -23.4), 84.0, -10.0, GameClock.Phase.DAY, "sl_mooring")
	await _shot(Vector3(8.6, 3.5, -3.5), 2.0, -8.0, GameClock.Phase.DAY, "sl_pipe_alley")
	await _shot(Vector3(18, 3.2, -18), 40.0, 55.0, GameClock.Phase.DAY, "sl_girder_up")
	await _shot(Vector3(15.5, 3.4, -5.2), 180.0, -12.0, GameClock.Phase.DAY, "sl_pump_skids")
	await _shot(Vector3(-23.5, 19.7, -13.5), 210.0, -8.0, GameClock.Phase.DAY, "sl_machine_shop")
	await _shot(Vector3(21.5, 3.4, -18.0), 200.0, -10.0, GameClock.Phase.DAY, "sl_bench_props")
	# Fauna: seal patrol + perched corvid (day), lamp-snail constellations (night).
	await get_tree().create_timer(2.0).timeout   # let the seal reach a nice spot
	await _shot(Vector3(24, 4.0, -22), 160.0, -6.0, GameClock.Phase.DAY, "sl_fauna_seal")
	# The crab, lamp lit, mid-hunt — the night's face.
	GameClock.force_phase(GameClock.Phase.NIGHT)
	await get_tree().create_timer(0.5).timeout
	var crab := preload("res://scripts/world/crab.gd").new()
	main.add_child(crab)
	crab.global_position = Vector3(23.0, 2.0, -18.0)   # open walk lane, clear sightline
	crab.state = crab.State.PURSUE
	crab.pursue_speed = 0.0      # hold the menace pose — no contact blackout mid-shot
	crab.contact_radius = 0.0
	main.player.global_position = Vector3(26.0, 2.2, -18.0)
	await get_tree().create_timer(1.0).timeout
	await _shot(Vector3(26.0, 3.0, -18.0), 90.0, -22.0, GameClock.Phase.NIGHT, "sl_crab_lamp")
	crab.queue_free()
	await _shot(Vector3(2, 3.6, -20), 0.0, -10.0, GameClock.Phase.NIGHT, "sl_jelly_night")
	# Stair verification: tower flight from the wet deck, and the quarters stairs.
	await _shot(Vector3(23.5, 3.4, -1.0), -45.0, 6.0, GameClock.Phase.DAY, "sl_stairs_tower")
	# Below the wave line (fly mode keeps the drown-respawn out of the frame).
	main.player._fly = true
	main.player.set_collision_layer_value(1, false)
	main.player.set_collision_mask_value(1, false)
	# (shot pos is the player's FEET; the camera rides ~1.6m higher — keep deep.)
	await _shot(Vector3(-17.0, -6.0, -8.0), 51.0, 8.0, GameClock.Phase.DAY, "sl_underwater_kelp")
	await _shot(Vector3(0, -8.0, 0), 45.0, 12.0, GameClock.Phase.DAY, "sl_underwater_legs")
	await _shot(Vector3(8, -3.4, -30), 180.0, 6.0, GameClock.Phase.DAY, "sl_underwater_school")
	main.player._fly = false
	main.player.set_collision_layer_value(1, true)
	main.player.set_collision_mask_value(1, true)
	# Fishing beats: the rod in the storeroom, the stove, a cast riding the swell.
	await _shot(Vector3(12.8, 3.4, -18.6), 130.0, -18.0, GameClock.Phase.DAY, "sl_fishing_rod")
	await _shot(Vector3(9.5, 19.6, 14.3), 220.0, -10.0, GameClock.Phase.DAY, "sl_galley_stove")
	if main.player.fishing == null:
		main.player.global_position = Vector3(27.0, 2.2, -20.0)   # east of the pod, open sea south
		main.player.rotation.y = deg_to_rad(0)
		main.player.get_node("Head").rotation.x = deg_to_rad(-10)
		PlayerState.add_item("fishing_rod")
		PlayerState.selected_hotbar = PlayerState.hotbar.find("fishing_rod")
		main.player._start_fishing()
		await get_tree().create_timer(1.6).timeout
		var img2: Image = get_viewport().get_texture().get_image()
		img2.save_png("/tmp/sl_fishing_cast.png")
		print("saved /tmp/sl_fishing_cast.png")
	await _shot(Vector3(28.5, 7.2, -1.5), 40.0, -18.0, GameClock.Phase.DAY, "sl_stairs_tower_up")
	await _shot(Vector3(19, 4.5, -6), 200.0, -16.0, GameClock.Phase.NIGHT, "sl_fauna_snails")
	await _shot(Vector3(-22, 19.2, -3), 235.0, -4.0, GameClock.Phase.DAY, "sl_topside_day")
	await _shot(Vector3(3.5, 35.5, -18), 175.0, -18.0, GameClock.Phase.DAY, "sl_lookout")
	await _shot(Vector3(26.5, 11.2, 4.5), 155.0, -5.0, GameClock.Phase.DAY, "sl_breaker_room")
	# Moved south of the Phase-2 container stack that now owns the old vantage.
	await _shot(Vector3(28, 21.0, -20.5), 90.0, 2.0, GameClock.Phase.DUSK, "sl_dusk_sea", 0.55)
	await _shot(Vector3(28, 21.0, -20.5), 270.0, 2.0, GameClock.Phase.DUSK, "sl_dusk_sea_w", 0.55)
	await _shot(Vector3(20, 3.4, -12), -95.0, -10.0, GameClock.Phase.DAY, "sl_waves_close")
	await _shot(Vector3(2, 19.9, -19), 3.0, -16.0, GameClock.Phase.DAY, "sl_gyre")
	# UI panels: seed some discoveries, then help/journal/inventory.
	for it in ["throwing_hook", "canned_food", "rope", "kelp_bundle"]:
		PlayerState.add_item(it)
	Journal.discover("place_gyre")
	Journal.discover("creature_gull")
	Journal.discover("creature_jelly_drifter")
	Journal.discover_log("sphl_manual", "SPHL OPERATIONS MANUAL — PAGE 12")
	await _ui_shot("help", "sl_ui_help")
	await _ui_shot("journal", "sl_ui_journal")
	await _ui_shot("inventory", "sl_ui_inventory")
	# Bench with a partial recipe laid out.
	PlayerState.add_item("driftwood")
	PlayerState.add_item("tarp")
	main.hud.bench_panel.bench = null
	main.hud.toggle_panel("bench")
	main.hud.bench_panel.lay_item("driftwood")
	main.hud.bench_panel.lay_item("tarp")
	await get_tree().create_timer(0.6).timeout
	var bimg: Image = get_viewport().get_texture().get_image()
	bimg.save_png("/tmp/sl_ui_bench.png")
	print("saved /tmp/sl_ui_bench.png")
	main.hud.toggle_panel("bench")
	# A built homestead: lamp + lean-to + walkway + barricade on the south deck, at night.
	for spec in [["bloom_lamp_kit", Vector3(6, 18.0, -16)], ["leanto_kit", Vector3(3.5, 18.0, -17)],
			["walkway_kit", Vector3(8.5, 18.0, -17.5)], ["barricade_kit", Vector3(4.5, 18.0, -14.2)]]:
		var s: Node3D = Structures.build(spec[0], false)
		main.add_child(s)
		s.global_position = spec[1]
	await _shot(Vector3(12, 19.6, -10), 45.0, -16.0, GameClock.Phase.NIGHT, "sl_built_night")

	# New content: interiors, env objects, wildlife.
	await _shot(Vector3(6, 19.7, 9.5), 180.0, -6.0, GameClock.Phase.DAY, "sl_galley")
	await _shot(Vector3(19.5, 19.7, 9.5), 228.0, -8.0, GameClock.Phase.DAY, "sl_rec_room")
	await _shot(Vector3(-8.6, 19.7, 11), 90.0, -4.0, GameClock.Phase.DAY, "sl_bunkhouse")
	await _shot(Vector3(20.5, 3.8, -15), 210.0, -12.0, GameClock.Phase.DUSK, "sl_firebarrel", 0.6)
	GameClock.force_phase(GameClock.Phase.DUSK)
	await get_tree().create_timer(1.0).timeout
	PowerGrid.power_circuit("topside_floodlights")
	await _shot(Vector3(-8, 19.4, -1), 250.0, -8.0, GameClock.Phase.NIGHT, "sl_night_lit")
	await _shot(Vector3(2, 1.6, -12), 90.0, -2.0, GameClock.Phase.NIGHT, "sl_pontoon_night")
	await _shot(Vector3(-5, 19.8, 19), 180.0, -30.0, GameClock.Phase.NIGHT, "sl_bloom_sea")

	# Accommodation stack: exterior massing, corridors, rooms, roof + mast.
	await _shot(Vector3(44, 23.0, -14), 130.0, 8.0, GameClock.Phase.DUSK, "sl_stack_wide", 0.55)
	await _shot(Vector3(4, 19.7, -2), 190.0, 14.0, GameClock.Phase.DAY, "sl_stack_ramp")
	await _shot(Vector3(25.5, 23.2, 12), 90.0, -4.0, GameClock.Phase.DAY, "sl_deckB_corridor")
	await _shot(Vector3(9.3, 23.2, 7.2), 220.0, -10.0, GameClock.Phase.NIGHT, "sl_cabin_shrine")
	await _shot(Vector3(10, 26.7, 10.3), 53.0, -8.0, GameClock.Phase.DAY, "sl_control_room")
	await _shot(Vector3(7.5, 26.7, 15.2), 220.0, -6.0, GameClock.Phase.DAY, "sl_comms_room")
	await _shot(Vector3(19, 30.2, 15.7), 180.0, -8.0, GameClock.Phase.DAY, "sl_workshop")
	await _shot(Vector3(10, 33.8, 9.5), 229.0, 18.0, GameClock.Phase.DUSK, "sl_roof_mast", 0.55)
	await _shot(Vector3(33, 30.2, 12), 90.0, 2.0, GameClock.Phase.NIGHT, "sl_helipad_night")
	await _shot(Vector3(24.0, 23.2, 15.0), 280.0, -2.0, GameClock.Phase.DAY, "sl_ladder_well")
	await _shot(Vector3(14, 19.7, -4), 47.0, 24.0, GameClock.Phase.DUSK, "sl_derrick", 0.55)
	await _shot(Vector3(-31.5, 19.0, -8.5), 24.0, 24.0, GameClock.Phase.DUSK, "sl_flare_west", 0.55)

	# Storm: force a full squall, let the rain populate, shoot day + lightning.
	if main.get("storm") != null:
		main.storm._phase = 2   # RAGING
		main.storm._timer = 999.0
		main.storm._intensity = 1.0
		main.storm._wind = Vector2(0.8, 0.3)
		main.storm._apply_intensity()
		GameClock.force_phase(GameClock.Phase.DAY)
		main.player.global_position = Vector3(2, 19.7, -2)
		await get_tree().create_timer(2.0).timeout
		main.storm._flash_energy = 6.0   # a strike mid-shot
		await _shot(Vector3(2, 19.7, -2), 200.0, -2.0, GameClock.Phase.DAY, "sl_storm_deck")
		await _shot(Vector3(24, 4.0, -20), 150.0, 4.0, GameClock.Phase.DAY, "sl_storm_wetdeck")
	get_tree().quit()

func _ui_shot(panel: String, name_: String) -> void:
	main.hud.toggle_panel(panel)
	await get_tree().create_timer(0.6).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/%s.png" % name_)
	print("saved /tmp/%s.png" % name_)
	main.hud.toggle_panel(panel)

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, phase: GameClock.Phase, name_: String, frac: float = 0.0) -> void:
	GameClock.force_phase(phase)
	if frac > 0.0:
		GameClock._phase_elapsed_sec = GameClock.phase_durations_minutes[phase] * 60.0 * frac
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
