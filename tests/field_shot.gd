extends Node
## THE FIELD — visual proof. Photographs the new rigs, the bridges and the skyline so the
## structure can be JUDGED AS PICTURES rather than asserted from a probe log.
##
## MUST RUN WINDOWED — `--headless` never draws and every frame comes back black:
##   godot --path . res://tests/FieldShot.tscn -- /tmp/field [--only=<substr>]
##
## TWO TRAPS, BOTH PAID FOR IN THIS REPO, BOTH DESIGNED OUT HERE:
##
##  1. `_place` moves the PLAYER, and the eye rides ~1.6 m above its feet. Every `from`
##     below is therefore a FLOOR position. (beta1_shot's "sphl_interior" spent months
##     photographing an exterior bulkhead partly because of this.)
##  2. **rotation.y = 0 faces −Z.** The first version of this harness hand-typed yaws and
##     every single frame pointed SOUTH, away from a field that runs north — the sea came
##     back empty and it looked exactly like three rigs that had failed to build. So shots
##     are aimed at a WORLD TARGET and the yaw/pitch are derived. There is no yaw literal
##     anywhere in this file, and there should never be one.

var main: Node3D
var _dir: String = "/tmp"
var _only: String = ""

## World anchors, derived once from the rig origins and bearings in rig_field.gd, so the
## frames follow the level design instead of a second hand-copied set of coordinates.
var W: Dictionary = {}

func _world(origin: Vector3, yaw_deg: float, local: Vector3) -> Vector3:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), origin) * local

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).to_lower()
		elif not a.begins_with("--"):
			_dir = a
	DirAccess.make_dir_recursive_absolute(_dir)
	var F := preload("res://scripts/world/rig_field.gd")
	var m_o: Vector3 = F.MARROW_ORIGIN
	var m_y: float = F.MARROW_YAW
	var a_o: Vector3 = F.ANCHORAGE_ORIGIN
	var a_y: float = F.ANCHORAGE_YAW
	var d_o: Vector3 = F.DEEPWELL_ORIGIN
	var d_y: float = F.DEEPWELL_YAW
	W = {
		"rig1": Vector3(0, 26, 0),
		"m_deck": _world(m_o, m_y, Vector3(0, 14, 0)),
		"m_in": _world(m_o, m_y, Vector3(-2, 14, -24)),
		"m_garden": _world(m_o, m_y, Vector3(-17, 21.2, 11)),
		"m_tower": _world(m_o, m_y, Vector3(-32, 28.4, -4.5)),
		"m_low": _world(m_o, m_y, Vector3(29, 3.2, -19)),
		"m_rack": _world(m_o, m_y, Vector3(-48, 13.2, -14)),
		"m_silo": _world(m_o, m_y, Vector3(34, 20, -6)),
		"m_process": _world(m_o, m_y, Vector3(-20, 6.8, 0)),
		"m_process_far": _world(m_o, m_y, Vector3(14, 8.0, 6)),
		"m_mezz": _world(m_o, m_y, Vector3(-39.6, 17.8, 0)),
		"a_deck": _world(a_o, a_y, Vector3(0, 22, 0)),
		"a_in": _world(a_o, a_y, Vector3(-10, 22, -30)),
		"a_atrium": _world(a_o, a_y, Vector3(0, 22, -9)),
		"a_tank_mid": _world(a_o, a_y, Vector3(0, 31, 4)),
		"a_tank_low": _world(a_o, a_y, Vector3(0, 25, 4)),
		"a_collar": _world(a_o, a_y, Vector3(0, 29.4, -2.6)),
		"a_g3": _world(a_o, a_y, Vector3(-13, 33.1, 4)),
		"a_g4": _world(a_o, a_y, Vector3(0, 36.8, -8)),
		"a_roof_apex": _world(a_o, a_y, Vector3(0, 43, 4)),
		"a_plant": _world(a_o, a_y, Vector3(-26, 8.8, -6)),
		"a_spa": _world(a_o, a_y, Vector3(-22, 15.4, 0)),
		"a_pool": _world(a_o, a_y, Vector3(0, 15.4, 0)),
		"a_pad": _world(a_o, a_y, Vector3(48, 30, -8)),
		"a_prom": _world(a_o, a_y, Vector3(-46, 22, 0)),
		"a_wingroof": _world(a_o, a_y, Vector3(-29, 36.8, 12)),
		"a_lobby": _world(a_o, a_y, Vector3(0, 22, -24)),
		"d_deck": _world(d_o, d_y, Vector3(0, 20, 0)),
		"d_in": _world(d_o, d_y, Vector3(8, 20, -33)),
		"d_crown": _world(d_o, d_y, Vector3(0, 90, 0)),
		"d_floor": _world(d_o, d_y, Vector3(0, 30, -9)),
		"d_pool": _world(d_o, d_y, Vector3(0, 2, 0)),
		"d_prod": _world(d_o, d_y, Vector3(-18, 11.3, 4)),
		"d_ring": _world(d_o, d_y, Vector3(-35.4, 23.6, 0)),
		"d_monkey": _world(d_o, d_y, Vector3(0, 58, -7.6)),
	}
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(9.0).timeout
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false
	var p: Node3D = main.player
	p.set("_fly", true)
	(p as CollisionObject3D).set_collision_layer_value(1, false)
	(p as CollisionObject3D).set_collision_mask_value(1, false)
	GameClock.force_phase(GameClock.Phase.DAY)
	# THE FIELD SHIPS DARK. Its lamps hang off rig 1's main breaker, so a harness that never
	# closes the circuit photographs three unlit platforms and a black atrium — which is what
	# the first pass did. Close it up front; the night section proves the OFF state separately.
	PowerGrid.power_circuit("topside_floodlights")
	await get_tree().create_timer(1.0).timeout
	print("[field-shot] world up, output -> ", _dir)

	# ---- THE SKYLINE: the frame the whole chapter is composed for.
	await _look(Vector3(14.0, 32.1, 17.0), W["d_crown"] * Vector3(1, 0.55, 1), "skyline_from_rig1_stackroof")
	await _look(Vector3(0.0, 80.0, -50.0), W["d_deck"], "skyline_aerial")
	await _look(Vector3(-45.0, 30.0, 70.0), W["m_deck"], "bridge1_midspan")

	# ---- MARROW. Broad and low, and now three decks thick.
	await _look(Vector3(-30.0, 60.0, 90.0), W["m_deck"], "marrow_approach_air")
	await _look(W["m_deck"] + Vector3(4.0, 0.0, -6.0), W["m_garden"], "marrow_deck_west")
	await _look(W["m_deck"] + Vector3(0.0, 0.0, -2.0), W["m_silo"], "marrow_deck_east")
	await _look(W["m_process"], W["m_process_far"], "marrow_process_deck")
	await _look(W["m_process"] + Vector3(0, 3.2, 0), W["m_process_far"] + Vector3(0, 2, 0), "marrow_process_catwalk")
	await _look(W["m_mezz"], W["m_deck"] + Vector3(0, 6, 0), "marrow_mezzanine_ring")
	await _look(W["m_garden"] + Vector3(6.0, 0.0, -7.0), W["m_garden"] + Vector3(-4, 1, 6), "marrow_garden")
	await _look(W["m_tower"], W["a_deck"], "marrow_overview_forward")

	# ---- THE ANCHORAGE, and the atrium it is built around.
	await _look(Vector3(20.0, 60.0, 200.0), W["a_deck"] + Vector3(0, 16, 0), "anchorage_approach_air")
	await _look(W["a_in"] + Vector3(0, 0, -10.0), W["a_deck"] + Vector3(0, 14, 8), "anchorage_bridge_landing")
	await _look(W["a_lobby"], W["a_tank_low"], "anchorage_lobby")
	# THE TANK, from every level it passes through.
	await _look(_world(a_o, a_y, Vector3(0, 22, -7)), W["a_tank_mid"], "atrium_from_floor")
	await _look(_world(a_o, a_y, Vector3(0, 22, -1.5)), _world(a_o, a_y, Vector3(0, 40, 4)), "atrium_tank_base_looking_up")
	await _look(W["a_atrium"] + Vector3(0, 0, -3.0), W["a_roof_apex"], "atrium_looking_up")
	await _look(_world(a_o, a_y, Vector3(0, 29.4, -2.6)), _world(a_o, a_y, Vector3(0, 30.5, 4)), "atrium_tank_from_spur")
	await _look(W["a_g3"], W["a_tank_mid"], "atrium_tank_from_g3")
	await _look(W["a_g4"], W["a_deck"] + Vector3(0, 1, 4), "atrium_from_g4_looking_down")
	await _look(W["a_g4"] + Vector3(0, 0, 2.0), W["a_tank_mid"] + Vector3(0, 6, 0), "atrium_upper_gallery")
	await _look(W["a_spa"], W["a_pool"], "anchorage_pool_hall")
	await _look(W["a_plant"], W["a_plant"] + Vector3(20, 2, 8), "anchorage_plant_deck")
	await _look(W["a_prom"], W["a_deck"] + Vector3(0, 10, 0), "anchorage_promenade")
	await _look(W["a_pad"] + Vector3(0, 0, -8.0), W["a_deck"] + Vector3(0, 14, 6), "anchorage_helideck")
	await _look(W["a_wingroof"], W["a_deck"] + Vector3(0, 20, 4), "anchorage_wing_roof")

	# ---- DEEPWELL. The tallest thing in the world, now with a production level under it.
	await _look(Vector3(0.0, 30.0, 320.0), W["d_crown"], "deepwell_from_the_south")
	await _look(W["d_prod"], W["d_prod"] + Vector3(20, 2, 10), "deepwell_production_deck")
	await _look(W["d_ring"], W["d_crown"], "deepwell_outboard_ring")
	await _look(W["d_deck"] + Vector3(0, 8.0, 0.0), W["d_pool"] + Vector3(0, -14, 0), "deepwell_moon_pool")
	await _look(W["d_floor"], W["d_deck"] + Vector3(0, 14, 6), "deepwell_drill_floor")

	# ---- NIGHT, WITH THE POWER ON. The field is dark until rig 1's breaker closes.
	GameClock.force_phase(GameClock.Phase.NIGHT)
	await get_tree().create_timer(2.0).timeout
	await _look(Vector3(14.0, 32.1, 17.0), W["d_crown"] * Vector3(1, 0.55, 1), "night_skyline_lit")
	await get_tree().create_timer(1.0).timeout
	await _look(Vector3(14.0, 32.1, 17.0), W["d_crown"] * Vector3(1, 0.55, 1), "night_skyline_lit2")
	await _look(Vector3(0.0, 80.0, -50.0), W["d_deck"], "night_aerial")
	await _look(W["m_deck"] + Vector3(4.0, 0.0, -6.0), W["m_garden"], "night_marrow_deck")
	await _look(W["a_atrium"], W["a_tank_mid"], "night_atrium")
	await _look(Vector3(20.0, 60.0, 200.0), W["a_deck"] + Vector3(0, 16, 0), "night_anchorage_air")
	await _look(W["d_deck"] + Vector3(0, 8.0, 0.0), W["d_pool"] + Vector3(0, -14, 0), "night_deepwell_moon_pool")

	print("[field-shot] done")
	get_tree().quit(0)

## Aim from a FLOOR position at a WORLD target. The eye is 1.6 m above `from`, and
## rotation.y = 0 faces −Z, which is why the yaw is atan2(−dx, −dz) and not atan2(dx, dz).
func _look(from: Vector3, at: Vector3, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	var eye: Vector3 = from + Vector3(0, 1.6, 0)
	var d: Vector3 = at - eye
	var horiz: float = Vector2(d.x, d.z).length()
	var p: Node3D = main.player
	p.global_position = from
	p.rotation.y = atan2(-d.x, -d.z)
	p.get_node("Head").rotation.x = atan2(d.y, maxf(horiz, 0.001))
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)
	await get_tree().create_timer(0.75).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/field_%s.png" % [_dir, name_]
	print("[field-shot] %-38s -> err=%d  (from %.1f,%.1f,%.1f at %.1f,%.1f,%.1f)" %
		[name_, img.save_png(path), from.x, from.y, from.z, at.x, at.y, at.z])
