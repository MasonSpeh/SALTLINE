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
const MOVE := preload("res://scripts/world/fauna_move.gd")
## A crab that got above this has been ON the topside plate (y18) — the only way up there
## from the water without a stair is its own caisson leg.
const CLIMBED_Y: float = 16.0
const BODY_R: float = 0.45           ## the crab's body radius, plus a little
const DECK_TOP: float = 18.0

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

## THE SUPPORT ROUTES, AGAINST THE REAL RIG. Every waypoint of every authored leg climb
## (BloomFauna._crab_leg_climbs) has to be in free space, and every landing has to be the
## topside plate with a crab-sized volume clear above it. The routes were picked off a
## sphere-cast sweep of the deck in the first place — the deck a metre either side of those
## lanes is containers, rails and hut walls — so this re-runs that measurement rather than
## trusting a comment: a future dressing pass that drops a crate on a landing fails here
## instead of quietly stranding half the pack on a rail.
func _check_leg_routes(crabs: Array) -> void:
	if crabs.is_empty():
		return
	var host: Node3D = crabs[0]
	var world: World3D = host.get_world_3d()
	if world == null:
		return
	var skip: Array[RID] = MOVE.kin_bodies(host)
	var sph := SphereShape3D.new()
	sph.radius = BODY_R
	var buried: int = 0
	var bad_land: Array[String] = []
	var routed: int = 0
	for c in crabs:
		var route: Array = c.leg_climb
		if route.is_empty():
			continue
		routed += 1
		for wp in route:
			if MOVE.point_solid(host, wp as Vector3, skip):
				buried += 1
		var land: Vector3 = route[route.size() - 1]
		# Plate under the landing...
		var q := PhysicsRayQueryParameters3D.create(land + Vector3(0, 0.8, 0),
			land - Vector3(0, 1.5, 0))
		q.exclude = skip
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - DECK_TOP) > 0.2:
			bad_land.append("crab %d: no plate under %s" % [int(c.spawn_index), str(land)])
			continue
		# ...and room for the animal standing on it. The probe sphere is lifted clear of the
		# plate itself, or the deck it is meant to be standing on reads as the obstruction.
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = sph
		sq.transform = Transform3D(Basis(), land + Vector3(0, BODY_R + 0.15, 0))
		sq.exclude = skip
		if not world.direct_space_state.intersect_shape(sq, 1).is_empty():
			bad_land.append("crab %d: landing blocked at %s" % [int(c.spawn_index), str(land)])
	_check("support routes authored", routed > 0, "%d of %d crabs have one" % [routed, crabs.size()])
	_check("no support-climb waypoint is inside the rig", buried == 0,
		"%d buried waypoints" % buried)
	_check("every support climb lands on clear topside plate", bad_land.is_empty(),
		str(bad_land))

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	for i in range(10):
		await get_tree().physics_frame

	var crabs: Array = get_tree().get_nodes_in_group("giant_crab")
	# Was `>= 10`. The pack was cut to bloom_fauna.gd CRAB_COUNT = 6 in the 2026-07-25
	# predator pass; read the count from the spawner rather than restating it here, so a
	# future retune of the pack size does not fail this probe for no reason.
	var want: int = int(preload("res://scripts/world/bloom_fauna.gd").CRAB_COUNT)
	_check("the pack spawned", crabs.size() >= want, "%d crabs (want %d)" % [crabs.size(), want])
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

	_check_leg_routes(crabs)

	var start: Array = []
	for c in crabs:
		start.append((c as Node3D).global_position)

	_say("nightfall — simulating %.0fs of game time at %.0fx" % [SIM_SECONDS, TIME_SCALE])
	GameClock.force_phase(GameClock.Phase.NIGHT)
	# EVERY crab is sent up, deliberately. crab.gd SURFACE_CHANCE means each one privately
	# rolls whether to come out at all, and the flag is written by the GameClock.night
	# handler — so the probe overrides it AFTER forcing the phase. This is not the probe
	# ignoring the coin: it is the probe refusing to be a coin flip. What is under test here
	# is the JOURNEY (roost -> support/rim -> plating), and a run where half the pack
	# legitimately stayed home tests half of it, at random, differently every time. The coin
	# itself is exercised in TestRunner, where it can be asserted instead of tolerated.
	for c in crabs:
		c._surface_tonight = true
	Engine.time_scale = TIME_SCALE
	var elapsed: float = 0.0
	var ever_on_deck: Array = []
	var peak_y: Array = []
	for i in range(crabs.size()):
		ever_on_deck.append(false)
		peak_y.append(-99.0)
	while elapsed < SIM_SECONDS:
		await get_tree().process_frame
		# get_process_delta_time() is ALREADY scaled by Engine.time_scale — multiplying
		# by TIME_SCALE again counted 36x and simulated a sixth of the intended window.
		elapsed += get_process_delta_time()
		for i in range(crabs.size()):
			var c: Node3D = crabs[i]
			if not is_instance_valid(c):
				continue
			if c.global_position.y > WET_Y - 0.6:
				ever_on_deck[i] = true
			# The high-water mark is what proves a support climb happened. Where the crab
			# ENDS the night does not: once it is topside it hunts like any other crab, and
			# a player on a lower deck will walk it straight back down the stair tower.
			peak_y[i] = maxf(peak_y[i], c.global_position.y)
		# Keep it night for the whole run; the real NIGHT phase is 13 minutes but the
		# clock keeps ticking under time_scale and would roll into DAWN mid-probe.
		if GameClock.current_phase != GameClock.Phase.NIGHT:
			GameClock.force_phase(GameClock.Phase.NIGHT)
			for c in crabs:
				c._surface_tonight = true
	Engine.time_scale = 1.0

	var CrabS := preload("res://scripts/world/crab.gd")
	var reached: int = 0
	var on_deck_now: int = 0
	var states := {}
	# Every crab was forced up (see the override at nightfall), so every crab is a riser and
	# every one of them is held to the whole journey.
	var risers: int = 0
	var leg_crabs: int = 0
	var leg_climbed: int = 0
	for i in range(crabs.size()):
		var c: Node3D = crabs[i]
		if not is_instance_valid(c):
			continue
		var st: int = c.state
		var key: String = CrabS.State.keys()[st]
		states[key] = int(states.get(key, 0)) + 1
		if not bool(c._surface_tonight):
			continue
		risers += 1
		if ever_on_deck[i]:
			reached += 1
		if c.global_position.y > WET_Y - 0.6:
			on_deck_now += 1
		# Crabs with an authored support route have to have USED it: nothing else on this
		# rig lifts an animal from the water to the topside plate inside one night.
		var has_route: bool = not (c.leg_climb as Array).is_empty()
		if has_route:
			leg_crabs += 1
			if peak_y[i] >= CLIMBED_Y:
				leg_climbed += 1
		_say("   crab %d  %-7s  moved %5.1fm  now %s  y%.2f  peak y%.2f%s"
			% [i, key, start[i].distance_to(c.global_position),
				str(c.global_position.snapped(Vector3.ONE * 0.1)), c.global_position.y,
				peak_y[i], "  [support route]" if has_route else ""])
	_say("   states: %s" % str(states))

	_say("   %d of %d crabs rolled to surface tonight" % [risers, crabs.size()])
	_check("every crab that rolled to surface reached the plating",
		reached == risers, "%d of %d risers reached the deck" % [reached, risers])
	_check("every crab on a climbable caisson went UP ITS SUPPORT", leg_climbed == leg_crabs,
		"%d of %d leg-route crabs got above y%.0f" % [leg_climbed, leg_crabs, CLIMBED_Y])
	_check("some of the pack climbs the supports at all", leg_crabs > 0,
		"%d of %d crabs carry a support route" % [leg_crabs, crabs.size()])
	_check("risers are still up and hunting, not sunk back", on_deck_now >= risers / 2,
		"%d of %d on deck at the end" % [on_deck_now, risers])
	var hunting: int = int(states.get("PATROL", 0)) + int(states.get("PURSUE", 0))
	_check("the risers are up and hunting (PATROL or PURSUE)", hunting >= risers - 1,
		str(states))
