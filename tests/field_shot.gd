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
		"a_deck": _world(a_o, a_y, Vector3(0, 22, 0)),
		"a_in": _world(a_o, a_y, Vector3(-8, 22, -21)),
		"a_tank": _world(a_o, a_y, Vector3(3.6, 25.3, 4.5)),
		"a_mess": _world(a_o, a_y, Vector3(-5, 22, 4)),
		"a_gallery": _world(a_o, a_y, Vector3(-2, 25.3, 4)),
		"a_pad": _world(a_o, a_y, Vector3(30, 28.5, -4)),
		"a_under_pad": _world(a_o, a_y, Vector3(33, 22, -4)),
		"a_prom": _world(a_o, a_y, Vector3(-30, 22, 0)),
		"a_roof": _world(a_o, a_y, Vector3(-8, 35.2, 4)),
		"d_deck": _world(d_o, d_y, Vector3(0, 20, 0)),
		"d_in": _world(d_o, d_y, Vector3(8, 20, -33)),
		"d_crown": _world(d_o, d_y, Vector3(0, 90, 0)),
		"d_floor": _world(d_o, d_y, Vector3(0, 30, -9)),
		"d_pool": _world(d_o, d_y, Vector3(0, 2, 0)),
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
	await get_tree().process_frame
	print("[field-shot] world up, output -> ", _dir)

	# ---- THE SKYLINE: the frame the whole chapter is composed for.
	await _look(Vector3(14.0, 32.1, 17.0), W["d_crown"] * Vector3(1, 0.55, 1), "skyline_from_rig1_stackroof")
	await _look(Vector3(0.0, 70.0, -40.0), W["d_deck"], "skyline_aerial")
	await _look(Vector3(-24.0, 18.0, 18.0), W["m_deck"], "skyline_from_rig1_deck")
	await _look(Vector3(-28.0, 18.0, 19.0), W["m_in"], "bridge1_head")
	await _look(Vector3(-45.0, 30.0, 70.0), W["m_deck"], "bridge1_midspan")

	# ---- MARROW. Broad and low; the garden is the thing to look at.
	await _look(Vector3(-30.0, 55.0, 95.0), W["m_deck"], "marrow_approach_air")
	await _look(W["m_in"] + Vector3(0, 0, -6.0), W["m_garden"], "marrow_bridge_landing")
	await _look(W["m_deck"] + Vector3(4.0, 0.0, -6.0), W["m_garden"], "marrow_deck_west")
	await _look(W["m_deck"] + Vector3(0.0, 0.0, -2.0), W["m_silo"], "marrow_deck_east")
	await _look(W["m_garden"] + Vector3(6.0, 0.0, -7.0), W["m_garden"] + Vector3(-4, 1, 6), "marrow_garden")
	await _look(W["m_garden"] + Vector3(-2.0, 0.0, 9.0), W["m_garden"], "marrow_garden_tunnel")
	await _look(W["m_tower"], W["rig1"], "marrow_overview_back_to_rig1")
	await _look(W["m_tower"], W["a_deck"], "marrow_overview_forward")
	await _look(W["m_low"] + Vector3(2.0, 0.0, 4.0), W["m_low"] + Vector3(-4, -2, -8), "marrow_low_deck")
	await _look(W["m_rack"] + Vector3(6.0, 0.0, 4.0), W["m_rack"] + Vector3(-8, -1, -5), "marrow_pipe_rack")

	# ---- THE ANCHORAGE. White, tall, the helideck cantilevered over open water.
	await _look(Vector3(20.0, 55.0, 205.0), W["a_deck"], "anchorage_approach_air")
	await _look(W["a_in"] + Vector3(0, 0, -8.0), W["a_deck"] + Vector3(0, 8, 6), "anchorage_bridge_landing")
	await _look(W["a_deck"] + Vector3(-16.0, 0.0, -8.0), W["a_deck"] + Vector3(0, 8, 6), "anchorage_deck")
	# THE AQUARIUM, from the mess floor looking up, and from the gallery at its middle.
	await _look(W["a_mess"] + Vector3(-2.0, 0.0, 0.0), W["a_tank"] + Vector3(0, 2.0, 0), "aquarium_from_floor")
	await _look(W["a_gallery"], W["a_tank"], "aquarium_from_gallery")
	await _look(W["a_prom"] + Vector3(-1.0, 0.0, 3.0), W["a_deck"] + Vector3(0, 6, 0), "anchorage_promenade")
	await _look(W["a_pad"] + Vector3(0, 0, -6.0), W["a_deck"] + Vector3(0, 8, 4), "anchorage_helideck")
	await _look(W["a_under_pad"] + Vector3(-6.0, 0, 0), W["a_under_pad"] + Vector3(12, 4, -2), "anchorage_under_helideck")
	await _look(W["a_roof"], W["rig1"], "anchorage_roof_back_down_the_field")
	await _look(W["a_roof"], W["d_crown"], "anchorage_roof_forward_to_deepwell")

	# ---- DEEPWELL. The tallest thing in the world, and it has to read as that.
	await _look(Vector3(0.0, 30.0, 320.0), W["d_crown"], "deepwell_from_the_south")
	await _look(W["d_in"] + Vector3(0, 0, -10.0), W["d_crown"], "deepwell_bridge_landing")
	await _look(W["d_deck"] + Vector3(0, 0, -16.0), W["d_crown"], "deepwell_derrick_up")
	await _look(W["d_deck"] + Vector3(0, 8.0, 0.0), W["d_pool"] + Vector3(0, -14, 0), "deepwell_moon_pool")
	await _look(W["d_floor"], W["d_deck"] + Vector3(0, 14, 6), "deepwell_drill_floor")
	await _look(Vector3(-52.0, 22.0, 415.0), W["d_crown"], "deepwell_west_flank")
	await _look(W["d_monkey"], W["a_deck"], "deepwell_monkey_board_view")

	# ---- NIGHT. The floodlights are what makes the field read as four inhabited things.
	GameClock.force_phase(GameClock.Phase.NIGHT)
	await get_tree().create_timer(2.0).timeout
	await _look(Vector3(14.0, 32.1, 17.0), W["d_crown"] * Vector3(1, 0.55, 1), "night_skyline_from_rig1")
	await _look(W["m_deck"] + Vector3(4.0, 0.0, -6.0), W["m_garden"], "night_marrow_deck")
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
