extends Node3D
## BETA 1.0 FULL RIG RUN-THROUGH — photographs every deck and every fix from this batch,
## so the release candidate is signed off by looking at it rather than by hoping.
##
## Boots the REAL Main scene (not a mock rig) and walks a fixed tour: wet deck, topside
## rooms, stair tower and its annexes, the ops lookout, the crane and its NEW ladder hatch,
## the machine-shop roof ladder that kept getting blocked, the accommodation stack, the
## relocated VSAT, and the water below the wave line.
##
## Conventions inherited from world_shot.gd, all learned the hard way:
##  * FREEZE THE PLAYER — a live CharacterBody3D falls out of wherever you put it.
##  * Wait after moving the camera; presence fades and fauna need a beat to be somewhere.
##  * Fauna WALK/SWIM, so a fixed camera aimed at a spawn point photographs empty water.
##    Subject shots resolve the live creature at capture time and frame it from an offset.
##
## Run WINDOWED: godot --path . res://tests/runthrough_shot.tscn
## Saves /tmp/rt_<name>.png and self-quits.

# name, camera pos, look-at, fov, subject ("" | "ray")
const SHOTS := [
	# --- Z1 wet deck -------------------------------------------------------------------
	["01_spawn",         Vector3(20.0, 3.4, -22.0),  Vector3(17.0, 2.4, -12.0), 75.0, ""],
	["02_wetdeck_pumps", Vector3(11.0, 4.2, -8.0),   Vector3(15.5, 2.6, -3.6),  75.0, ""],
	["03_wetdeck_south", Vector3(26.0, 4.0, -24.0),  Vector3(14.0, 2.4, -18.0), 80.0, ""],
	# --- Z4 topside --------------------------------------------------------------------
	["04_topside_open",  Vector3(-2.0, 21.5, -16.0), Vector3(6.0, 19.0, 2.0),   80.0, ""],
	["05_bunkhouse",     Vector3(-26.0, 19.6, 11.0), Vector3(-14.0, 19.0, 11.0), 75.0, ""],
	["06_bunk_cabin",    Vector3(-19.6, 19.5, 9.4),  Vector3(-20.9, 18.7, 4.6),  70.0, ""],
	["07_galley",        Vector3(2.0, 19.6, 10.0),   Vector3(9.0, 19.0, 16.0),  75.0, ""],
	["08_recroom",       Vector3(19.5, 19.8, 10.5),  Vector3(25.0, 19.2, 14.0), 75.0, ""],
	["09_machineshop",   Vector3(-16.0, 19.6, -8.0), Vector3(-24.0, 19.0, -14.0), 75.0, ""],
	# --- the machine-shop roof ladder (blocked three times; must read CLEAR) -----------
	["10_shop_ladder",   Vector3(-14.8, 19.9, -3.2), Vector3(-14.8, 20.2, -5.7), 55.0, ""],
	["11_shop_ladder_up",Vector3(-13.6, 22.6, -3.9), Vector3(-14.8, 20.6, -5.6), 60.0, ""],
	# --- Z2 stair tower + annexes ------------------------------------------------------
	["12_tower_foot",    Vector3(26.0, 4.4, -4.5),   Vector3(26.0, 10.0, 1.0),  80.0, ""],
	["13_breaker_room",  Vector3(25.0, 11.6, 5.0),   Vector3(23.0, 11.4, 8.4),  70.0, ""],
	["14_ops_lookout",   Vector3(23.0, 39.4, -5.0),  Vector3(29.0, 38.8, 1.0),  80.0, ""],
	# --- the crane: the ladder hatch is the headline fix -------------------------------
	["15_crane_deck",    Vector3(4.4, 35.9, -11.6),  Vector3(-0.4, 34.2, -14.2), 70.0, ""],
	["16_crane_hatch",   Vector3(1.2, 35.6, -14.1),  Vector3(-0.5, 34.1, -14.1), 55.0, ""],
	["17_crane_wide",    Vector3(14.0, 30.0, -26.0), Vector3(2.0, 36.0, -14.0), 70.0, ""],
	# --- accommodation stack + the relocated VSAT --------------------------------------
	["18_deckb_corr",    Vector3(-0.5, 23.0, 12.0),  Vector3(24.0, 22.6, 12.0), 70.0, ""],
	["19_deckb_cabin",   Vector3(3.0, 23.0, 10.2),   Vector3(5.5, 22.2, 7.0),   70.0, ""],
	["20_satdish_roof",  Vector3(-18.0, 23.4, 8.0),  Vector3(-22.0, 22.3, 11.5), 65.0, ""],
	["21_stack_roof",    Vector3(14.0, 34.6, 6.0),   Vector3(24.0, 33.2, 15.0), 80.0, ""],
	# --- exterior silhouette -----------------------------------------------------------
	["22_rig_from_sea",  Vector3(-46.0, 12.0, -44.0), Vector3(0.0, 20.0, -6.0), 70.0, ""],
	# --- below the wave line -----------------------------------------------------------
	["23_underwater",    Vector3(10.0, -6.0, -30.0), Vector3(18.0, -9.0, -14.0), 80.0, ""],
	# Ray shots are luck-of-the-draw for framing (it swims, and the kelp is tall). For the
	# ray, prefer tests/ray_roll.tscn — it logs roll over time, which is what actually
	# proves "level cruise, banks into turns" far better than any single still.
	["24_manta_ray",     Vector3(9.0, 3.0, 9.0),     Vector3(0.0, 0.0, 0.0),    55.0, "ray"],
]

var _cam: Camera3D
var _player: Node3D
var _main: Node3D

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	# Let the dressing stream in and the settle pass run before photographing anything —
	# shooting at t=2s catches props still mid-air on their way to the deck.
	await get_tree().create_timer(9.0).timeout
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.set_physics_process(false)
		_player.set_process(false)
	GameClock.force_phase(GameClock.Phase.DAY)
	await get_tree().create_timer(0.8).timeout
	for s in SHOTS:
		var eye: Vector3 = s[1]
		var aim: Vector3 = s[2]
		if String(s[4]) == "ray":
			var subj: Node3D = _find_ray()
			if subj == null:
				print("shot %s SKIPPED (no ray found)" % s[0])
				continue
			var o: Vector3 = subj.global_position
			eye = o + s[1]
			aim = o + s[2]
			print("   ray at %s  roll=%.2f rad" % [str(o.snappedf(0.01)),
				_model_roll(subj)])
		_cam.global_position = eye
		_cam.look_at(aim, Vector3.UP)
		_cam.fov = float(s[3])
		_cam.current = true
		await get_tree().create_timer(0.9).timeout
		get_viewport().get_texture().get_image().save_png("/tmp/rt_%s.png" % s[0])
		print("shot: %s" % s[0])
	print("\n[runthrough] %d shots written to /tmp/rt_*.png" % SHOTS.size())
	get_tree().quit()

## The underwater gliding rays live under the UnderwaterWorld node as GliderRay instances.
func _find_ray() -> Node3D:
	# MATCH ON FIELDS, NOT ON THE SCRIPT PATH. GliderRay is an INNER class of
	# underwater_world.gd, and an inner class's resource_path is not the owning file's path
	# (it is empty, or suffixed), so filtering by path found nothing and the shot was skipped.
	# `_roll` + `_band_y` together are unique to the glider ray — DeepGiant has _band_y only.
	for n in _main.find_children("*", "Node3D", true, false):
		if n.get("_roll") != null and n.get("_band_y") != null and n.get("_turn_smooth") != null:
			return n as Node3D
	return null

## Bank angle of the ray's model — proves the wings are LEVEL on a straight and rolled in a
## turn, rather than pinned at the old constant lean.
func _model_roll(subj: Node3D) -> float:
	for c in subj.get_children():
		if c is Node3D:
			return (c as Node3D).rotation.z
	return 0.0
