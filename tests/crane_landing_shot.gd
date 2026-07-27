extends Node
## CRANE LANDING SHOT — eyes on the mid landing's new descent hatch and the relocated
## lower mast run. tests/access_probe.gd proves the route works; this is for looking at it,
## because a hatch can be physically perfect and still read as a painted rectangle, and a
## ladder can pass every clearance check and still stand through a brace.
##
## MUST RUN WINDOWED AND ON TOP. Headless saves whatever the compositor last had, which off
## an occluded window is a black or stale frame — a screenshot that looks like evidence and
## is not. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --always-on-top \
##       --resolution 1280x720 tests/CraneLandingShot.tscn
##
## Output goes to $SHOT_OUT if set, else OUT_FALLBACK.
const OUT_FALLBACK := "/tmp/crane_landing_shot"

var main: Node3D

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(3.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	var p: Node3D = main.player
	p._fly = true
	p.set_collision_layer_value(1, false)
	p.set_collision_mask_value(1, false)
	GameClock.force_phase(GameClock.Phase.DAY)

	# Yaw convention (checked against crane_shot.gd's known-good "east looking west" frame):
	# forward is -Z, so yaw 0 looks -Z, yaw 90 looks -X (west), yaw -90 looks +X (east),
	# yaw 180 looks +Z (north). Pitch is the head's x rotation, negative looking down.

	# Standing on the landing where the upper run drops you (x 0.85), looking east down the
	# crossing at the hatch. This is the shot that answers the bug: from here you can SEE
	# the way down. Held 1 m south of the tower axis on purpose — dead level with it the
	# derrick's standing drill string (five 12 m pipes through the landing's middle at
	# x 1.65..2.35) fills the frame and you photograph pipe, not platform.
	await _shot(Vector3(0.85, 27.55, -15.05), -106.7, -21.0, "landing_look_east")
	# The hatch itself from close and above: coaming, hazard outline, grab rail, rungs.
	# Eye 1.3 m over the plate and 1.68 m short of the hatch centre — pitch has to be
	# atan(1.3/1.68) or the frame centre lands on the far rail and misses the hole entirely.
	await _shot(Vector3(3.0, 27.3, -14.0), -90.0, -38.0, "landing_hatch_close")
	# From under the landing looking up the new run — does the ladder stand clear of the
	# mast bracing and the derrick, or through it?
	await _shot(Vector3(7.6, 21.0, -14.0), 90.0, 16.0, "run_from_below")
	# The run's foot on the drill floor: the slot between the rotary block and the rungs.
	await _shot(Vector3(0.5, 19.3, -18.6), -136.5, 20.0, "run_foot_on_deck")
	# East elevation of the whole tower: both runs, offset, landing between them.
	await _shot(Vector3(17.0, 25.0, -14.0), 90.0, 2.0, "tower_east_elevation")
	# The landing crossing from its east end, with the south-rail stencil that names the way
	# down and the rigger's kit left on the west half.
	# Clear of the derrick's south face (z -17.44 at this height) — held inside it the frame
	# is one dark leg and nothing else.
	await _shot(Vector3(5.5, 27.6, -19.8), 169.3, -12.4, "landing_crossing")
	# The hatch from outside the landing's east rail, level with the plate: the opening, its
	# coaming and the rungs standing in it.
	await _shot(Vector3(6.3, 26.9, -14.0), 90.0, -18.0, "hatch_from_east")
	# The landing read from the open deck below, the way a player first sees it.
	await _shot(Vector3(11.0, 19.2, -19.0), 122.0, 20.0, "landing_from_deck")
	# --- machinery deck: the rebuilt slew bearing and the relocated ladder hatch ---
	# The crane head close from the south-west, at head height on the deck: king post, race,
	# house, gantry and boom. If this does not read as a crane the traversal fix cost too much.
	await _shot(Vector3(-3.4, 35.9, -19.6), -136.1, 4.4, "head_from_sw")
	# Standing ON the machinery deck at the mantle spot, looking north up the arrival lane —
	# the walk the probe measures at 2.17 m.
	await _shot(Vector3(-0.4, 35.75, -13.2), 180.0, -20.0, "deck_arrival_north")
	# The bearing itself: race, bolts and king post, from the deck plate outside it.
	await _shot(Vector3(-0.9, 35.0, -16.9), -135.0, -8.3, "slew_bearing")
	# The relocated hatch on the machinery deck, from its north lip.
	await _shot(Vector3(-0.4, 35.6, -12.6), 0.0, -34.0, "deck_hatch")
	get_tree().quit()

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.velocity = Vector3.ZERO
	p.input_locked = true
	await get_tree().create_timer(0.8).timeout
	var dir: String = OS.get_environment("SHOT_OUT")
	if dir.is_empty():
		dir = OUT_FALLBACK
	DirAccess.make_dir_recursive_absolute(dir)
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name_])
	print("saved %s/%s.png" % [dir, name_])
