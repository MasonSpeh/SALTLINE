extends Node3D
## In-world verification: boots the REAL Main scene, forces phases/storm, and
## photographs the rig where it actually is — because a contact sheet can't catch a
## backwards swimmer, a floating snail, a blocked doorway, or rain falling indoors.
## Saves /tmp/ws_*.png.
##
## Three things this harness has to get right, all learned the hard way:
##  * The rain emitter FOLLOWS THE PLAYER (StormSystem._follow_player), so a storm
##    shot must teleport the player to the camera or it photographs dry air.
##  * The giant crabs are PERSISTENT (s11): BloomFauna spawns the pack of three once,
##    underwater. Shots are still ordered day-first; at night the crabs climb out on
##    their own emergence stagger, so the night shot may catch them mid-climb.
##  * Fauna WALK. A fixed camera aimed at a spawn point photographs empty deck, so
##    subject shots ("crab"/"snail") resolve the live creature at capture time and
##    frame it from an offset — and print its facing next to its direction of travel,
##    which proves head-first crawl far better than squinting at a still.

const FAUNA := preload("res://scripts/world/bloom_fauna.gd")
const CRAB := preload("res://scripts/world/crab.gd")   # by path: class cache lags renames

var _cam: Camera3D
var _player: Node3D
var _main: Node3D

# name, phase, camera pos, look-at, extra ("storm"), fov
# For subject shots camera pos is used as a CAMERA OFFSET from the live subject and
# look-at as a small aim offset added to the subject's origin.
const SHOTS := [
	# --- day, calm: geometry + props ---
	["recroom_door", "day", Vector3(23.0, 19.6, 11.0), Vector3(18.0, 19.5, 11.0), "", 60.0],
	["recroom_wide", "day", Vector3(25.2, 19.8, 13.0), Vector3(18.1, 19.5, 13.0), "", 70.0],
	# Across the bunting line, not down it — from along X every flag is edge-on and
	# the string reads as a row of floating sticks even when it is correctly hung.
	["recroom_bunting", "day", Vector3(23.0, 20.1, 9.2), Vector3(23.0, 20.65, 12.9), "", 55.0],
	["ladder_landing", "day", Vector3(33.5, 19.6, -12.8), Vector3(30.6, 18.3, -16.0), "", 55.0],
	["readable_book", "day", Vector3(26.1, 3.45, -16.55), Vector3(26.1, 2.78, -17.5), "", 40.0],
	["readable_poster", "day", Vector3(-12.9, 19.5, -10.6), Vector3(-13.85, 19.5, -10.6), "", 45.0],
	["snail_close", "day", Vector3(0.95, 0.55, 0.95), Vector3(0.0, 0.06, 0.0), "snail", 38.0],
	["dock_tools", "day", Vector3(16.8, 3.6, -9.0), Vector3(20.2, 2.0, -12.2), "", 70.0],
	# --- day, storm: rain out, none in ---
	["window_storm", "day", Vector3(12.0, 26.6, 9.6), Vector3(12.0, 26.2, 6.0), "storm", 70.0],
	["deck_storm", "day", Vector3(20.0, 20.2, -10.0), Vector3(12.0, 18.4, -15.0), "storm", 70.0],
	["wetdeck_storm", "day", Vector3(24.0, 4.6, -12.5), Vector3(16.0, 2.2, -17.0), "storm", 70.0],
	# --- night: crabs last, so only one NIGHT transition happens ---
	["night_crabs", "night", Vector3(3.0, 2.0, 3.0), Vector3(0.0, 0.3, 0.0), "crab", 55.0],
]

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	# Let the world assemble + fauna take their first steps.
	await get_tree().create_timer(2.0).timeout
	_player = get_tree().get_first_node_in_group("player")
	# Freeze the player: we drive it as a rain-emitter proxy, and a live
	# CharacterBody3D would just fall out of every position we put it in.
	if _player:
		_player.set_physics_process(false)
		_player.set_process(false)
	var storm: Node = null
	for c in _main.get_children():
		if c is StormSystem:
			storm = c
			break
	var phase: String = ""
	for s in SHOTS:
		if s[1] != phase:
			phase = s[1]
			GameClock.force_phase(GameClock.Phase.NIGHT if phase == "night" else GameClock.Phase.DAY)
			await get_tree().create_timer(0.8).timeout
		var kind: String = s[4]
		var storming: bool = kind == "storm"
		if storm:
			storm.set("_intensity", 1.0 if storming else 0.0)
			storm.set("_phase", 2 if storming else 0)   # RAGING / CLEAR
		var eye: Vector3 = s[2]
		var aim: Vector3 = s[3]
		if kind == "snail" or kind == "crab":
			var subj: Node3D = _find_snail() if kind == "snail" else _find_crab()
			if subj == null:
				print("shot: %s SKIPPED (no subject)" % s[0])
				continue
			var o: Vector3 = subj.global_position
			_describe(s[0], subj)
			eye = o + s[2]
			aim = o + s[3]
		# The rain box rides the player — put them where the lens is.
		if _player and storming:
			_player.global_position = eye
		_cam.global_position = eye
		_cam.look_at(aim, Vector3.UP)
		_cam.fov = s[5]
		_cam.current = true
		await get_tree().create_timer(1.6).timeout   # settle: presence fades, rain falls
		get_viewport().get_texture().get_image().save_png("/tmp/ws_%s.png" % s[0])
		print("shot: ", s[0])
	var crabs: int = get_tree().get_nodes_in_group("giant_crab").size()
	print("crab count at night: ", crabs)
	get_tree().quit()

## Print where a creature is, which way its model points, and — for a rust snail —
## the axis of the graze run it is walking, so "head-first" is a number, not a vibe.
func _describe(shot: String, n: Node3D) -> void:
	var fwd: Vector3 = -n.global_transform.basis.z
	var line := "  %s subject=%s @%s facing=(%.2f, %.2f)" % [shot, n.get_class(), n.global_position, fwd.x, fwd.z]
	var a = n.get("_from")
	var b = n.get("_to")
	if a is Vector3 and b is Vector3:
		var run: Vector3 = ((b as Vector3) - (a as Vector3)).normalized()
		line += " run_axis=(%.2f, %.2f) dot=%.2f" % [run.x, run.z, fwd.dot(run)]
	print(line)

func _find_snail() -> Node3D:
	# The wet-deck plate seam run (x 13->19 at z -18.2) is the one a player walks past.
	return _nearest(FAUNA.RustSnail, Vector3(16.0, 2.06, -18.2))

func _find_crab() -> Node3D:
	return _nearest(CRAB, Vector3(24.0, 2.6, -13.0))   # night patrol circuit centre

func _nearest(type, anchor: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d: float = 1.0e9
	var stack: Array = [_main]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if is_instance_of(n, type):
			var d: float = (n as Node3D).global_position.distance_to(anchor)
			if d < best_d:
				best_d = d
				best = n
	return best
