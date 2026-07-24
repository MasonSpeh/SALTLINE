extends Node
## Does the pack ACTUALLY come out at night? The owner reported crabs that never
## appear on deck after dark, which no existing test covered: TestRunner forces one
## crab's state directly and ContentProbe only samples the daylight roost, so the whole
## ROOST -> EMERGE -> PATROL journey — the long swim in from the west legs, the climb up
## the rim, the hand-off onto the patrol ring — was never exercised end to end.
##
## Forces NIGHT, runs the world at Engine.time_scale so a couple of minutes of game
## time fit in a short headless run, and reports how many crabs made it onto the
## plating, how far each one got, and where the stragglers are stuck.
##
## Run: godot --headless --path . res://tests/CrabNightProbe.tscn

const WET_Y: float = 2.0
const SIM_SECONDS: float = 300.0     ## game seconds to simulate after nightfall
const TIME_SCALE: float = 6.0        ## wall-clock compression
const LOG_PATH: String = "/tmp/crab_night_probe.txt"

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()

func _ready() -> void:
	await _run()
	_say("---")
	_say("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_say("PASS  " + label + ("  — " + detail if detail != "" else ""))
	else:
		failures += 1
		_say("FAIL  " + label + ("  — " + detail if detail != "" else ""))

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	for i in range(10):
		await get_tree().physics_frame

	var crabs: Array = get_tree().get_nodes_in_group("giant_crab")
	_check("the pack spawned", crabs.size() >= 10, "%d crabs" % crabs.size())
	if crabs.is_empty():
		return

	# Park the player far away and high: PATROL only escalates to PURSUE when the player
	# is near and unlit, and a pursuing crab would skew "did it reach the ring".
	var p: Node3D = main.get("player")
	if p != null and p is CollisionObject3D:
		var pc := p as CollisionObject3D
		pc.set_collision_layer_value(1, false)
		pc.set_collision_mask_value(1, false)
		(p as Node3D).global_position = Vector3(-120, 40, 120)

	var start: Array = []
	for c in crabs:
		start.append((c as Node3D).global_position)

	_say("nightfall — simulating %.0fs of game time at %.0fx" % [SIM_SECONDS, TIME_SCALE])
	GameClock.force_phase(GameClock.Phase.NIGHT)
	Engine.time_scale = TIME_SCALE
	var elapsed: float = 0.0
	var ever_on_deck: Array = []
	for i in range(crabs.size()):
		ever_on_deck.append(false)
	while elapsed < SIM_SECONDS:
		await get_tree().process_frame
		# get_process_delta_time() is ALREADY scaled by Engine.time_scale — multiplying
		# by TIME_SCALE again counted 36x and simulated a sixth of the intended window.
		elapsed += get_process_delta_time()
		for i in range(crabs.size()):
			var c: Node3D = crabs[i]
			if is_instance_valid(c) and c.global_position.y > WET_Y - 0.6:
				ever_on_deck[i] = true
		# Keep it night for the whole run; the real NIGHT phase is 13 minutes but the
		# clock keeps ticking under time_scale and would roll into DAWN mid-probe.
		if GameClock.current_phase != GameClock.Phase.NIGHT:
			GameClock.force_phase(GameClock.Phase.NIGHT)
	Engine.time_scale = 1.0

	var CrabS := preload("res://scripts/world/crab.gd")
	var reached: int = 0
	var on_deck_now: int = 0
	var states := {}
	for i in range(crabs.size()):
		var c: Node3D = crabs[i]
		if not is_instance_valid(c):
			continue
		var st: int = c.state
		var key: String = CrabS.State.keys()[st]
		states[key] = int(states.get(key, 0)) + 1
		if ever_on_deck[i]:
			reached += 1
		if c.global_position.y > WET_Y - 0.6:
			on_deck_now += 1
		_say("   crab %d  %-7s  moved %5.1fm  now %s  y%.2f"
			% [i, key, start[i].distance_to(c.global_position),
				str(c.global_position.snapped(Vector3.ONE * 0.1)), c.global_position.y])
	_say("   states: %s" % str(states))

	_check("every crab surfaced onto the plating during the night",
		reached == crabs.size(), "%d of %d reached the deck" % [reached, crabs.size()])
	_check("crabs are still up and hunting, not sunk back", on_deck_now >= crabs.size() / 2,
		"%d of %d on deck at the end" % [on_deck_now, crabs.size()])
	var hunting: int = int(states.get("PATROL", 0)) + int(states.get("PURSUE", 0))
	_check("the pack is up and hunting (PATROL or PURSUE)", hunting >= crabs.size() - 1,
		str(states))
