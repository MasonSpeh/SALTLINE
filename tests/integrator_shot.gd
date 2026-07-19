extends Node
## INTEGRATOR VISUAL PROOF — photographs the five things this batch claims to have fixed,
## so they can be judged as pictures rather than trusted from coordinates.
##
##   1. the boarding stairs that used to climb into the balcony soffit (now a railed
##      landing at the balcony's east edge, open air the whole way up)
##   2. the stair-tower ramp/landing join that read as a wall to the character controller
##   3. a living corridor, walkable end to end
##   4. a dressed room, after the feng-shui/settle pass
##   5. a deck marking lying FLAT on the plating instead of standing in it
##
## The HUD is hidden: these are geometry proofs, and the journal toast sits right in the
## middle of the frame.
##
## Windowed — needs a real viewport.
## Run: godot --path . res://tests/IntegratorShot.tscn -- <output_dir> [--only=<substr>]

var main: Node3D
var _dir: String = "/tmp"
var _only: String = ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).to_lower()
		elif not a.begins_with("--"):
			_dir = a
	print("[int] booting, output -> ", _dir, ("" if _only == "" else "  (filter: %s)" % _only))
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	# The dressing streams in over several frames and settles at the end of the stream.
	await get_tree().create_timer(9.0).timeout
	main._countdown = 0.0
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		# HUD is a CanvasLayer, not a CanvasItem — `is CanvasItem` silently missed it and
		# left the journal toast sitting in the middle of every proof shot.
		main.hud.visible = false
	GameClock.force_phase(GameClock.Phase.DAY)
	var p: Node3D = main.player
	p.set("_fly", true)
	(p as CollisionObject3D).set_collision_layer_value(1, false)
	(p as CollisionObject3D).set_collision_mask_value(1, false)
	print("[int] world up")

	# -- 1. BOARDING STAIRS. Run: foot (15.8, 18, 3.4) -> landing top (8.6, 21.6, 3.4);
	# landing x 6.0..8.6; balcony slab x -6..6 at y 21.6, z 2.55..5.75. The old route
	# drove under that slab. Shot side-on from the south, where it is open air.
	await _shot(Vector3(11.0, 20.2, -5.0), 165.0, 2.0, "stair_side")
	# Climbing POV, foot of the flight looking up it (yaw 90 => forward -x). The old
	# route showed diamond-plate soffit here; this one shows sky.
	await _shot(Vector3(16.8, 18.05, 3.4), 90.0, 10.0, "stair_pov_foot")
	# Standing ON the landing, looking down at where it meets the balcony deck (x 6.0).
	await _shot(Vector3(8.3, 21.65, 3.4), 90.0, -20.0, "stair_join_top")

	# -- 2. STAIR TOWER JOIN. Flight 1 climbs (23.5, y2) -> (28.5, y6) in lane z -2.9;
	# its top tread meets the turn platform at x 28.5. That lip is what used to sit
	# ~2.8cm proud and read as a wall at 51 degrees off vertical.
	# Eye sits ~1.7m above the given feet position, so feet are set to put the eye
	# just over the ramp surface at that x.
	await _shot(Vector3(26.6, 4.5, -2.9), -90.0, -14.0, "tower_join_graze")
	await _shot(Vector3(26.3, 5.6, -2.9), -90.0, -24.0, "tower_join_above")
	await _shot(Vector3(24.8, 4.2, -2.9), -90.0, -4.0, "tower_join_context")
	await _shot(Vector3(27.0, 5.2, -1.7), -62.0, -20.0, "tower_join_oblique")

	# -- 3. CORRIDOR, clear (Deck B quarters, z 11..13 at y 21.6).
	await _shot(Vector3(26.0, 21.75, 12.0), 90.0, -4.0, "corridor_b")

	# -- 4. DRESSED ROOMS after the settle pass.
	await _shot(Vector3(19.0, 18.15, 11.2), -106.0, -8.0, "room_rec")
	await _shot(Vector3(6.0, 18.15, 12.0), 180.0, -8.0, "room_galley")
	await _shot(Vector3(19.5, 28.75, 15.9), 155.0, -12.0, "room_workshop")
	await _shot(Vector3(-23.5, 18.15, 14.5), 72.0, -8.0, "room_bunk")

	# -- 5. DECK MARKING FLAT. "LIFEBOAT 2" painted at (-10.5, 18.012, -17.9), pitch -90.
	await _shot(Vector3(-10.5, 18.05, -14.2), 0.0, -26.0, "deck_mark")
	await _shot(Vector3(-8.0, 18.05, -15.0), 22.0, -30.0, "deck_mark_oblique")

	# -- 6. GALLEY WEST BULKHEAD (this batch). Inner face x -1.875, run z 8.125..17.875,
	# composition datum y ~20. Stand east of it (yaw 90 faces -x) for the head-on read of
	# the notice board / pantry shelves / clock / potted plant, no longer overlapping.
	await _shot(Vector3(5.6, 18.2, 12.6), 90.0, 4.0, "galley_wall")
	await _shot(Vector3(6.4, 18.2, 9.6), 108.0, 2.0, "galley_wall_angle")

	# -- 7. RIGGING BENCH + TOOLBOX (this batch). Bench (25.0, 2.0, -17.5), the single
	# toolbox set on the plating at its WEST END (23.9, 2.0, -17.4). Wet deck floor y2.
	# Down the long axis (yaw -90 faces +x): toolbox in the near foreground, bench behind.
	await _shot(Vector3(21.2, 2.05, -17.4), -90.0, -12.0, "bench_toolbox_axis")
	# 3/4 from the SW so the toolbox reads as a separate box beside the bench end.
	await _shot(Vector3(21.3, 2.05, -18.7), -107.0, -15.0, "bench_toolbox")
	print("[int] done")
	get_tree().quit(0)

## pos is FEET; the eye sits ~1.7m above it. Yaw convention: forward = (-sin y, 0, -cos y).
func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/int_%s.png" % [_dir, name_]
	var err: int = img.save_png(path)
	print("[int] saved ", path, " err=", err)
