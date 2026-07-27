extends Node
## Acceptance test for the owner's "I have never seen this" reports: a crab, breaker
## 4-A's prompt, the rain, and a daylight start. Each of these was reported as simply
## absent from play, so each check here asserts PRESENCE IN THE RUNNING GAME rather
## than the existence of code that ought to produce it.
##
## Run: godot --headless --path . res://tests/ContentProbe.tscn

const WET_Y: float = 2.0
const REACH: float = 2.6         ## InteractionRay.REACH
const RADIUS: float = 0.4
const HEIGHT: float = 1.8
const COL_Y: float = 0.9
const EYE_Y: float = 1.6
const SPEED: float = 3.2
const GRAVITY: float = 9.8

const LOG_PATH: String = "/tmp/content_probe.txt"

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()
var _body: CharacterBody3D
var _step: float = 1.0 / 60.0

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
	# --- clock: the start phase is read BEFORE the world loads, since Main may advance it
	_check("game starts in daylight, not night",
		GameClock.current_phase == GameClock.Phase.DAY,
		"phase=%s" % GameClock.Phase.keys()[GameClock.current_phase])

	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	_step = 1.0 / float(Engine.physics_ticks_per_second)

	_check("still daylight once the world is built",
		GameClock.current_phase == GameClock.Phase.DAY,
		"phase=%s" % GameClock.Phase.keys()[GameClock.current_phase])

	_check_rain()
	_check_crabs()

	var p: Node3D = main.get("player")
	if p != null and p is CollisionObject3D:
		var pc := p as CollisionObject3D
		pc.set_collision_layer_value(1, false)
		pc.set_collision_mask_value(1, false)
		(p as Node3D).global_position = Vector3(0, 400, 0)
	await _check_breaker()

## The rain particles must be IN THE TREE. They were fully built and configured but the
## add_child call had drifted below a return statement, so the node existed only as a
## variable and could never be drawn under any weather condition.
func _check_rain() -> void:
	var rain: GPUParticles3D = null
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var g := n as GPUParticles3D
		if g != null and g.amount >= 1000 and g.draw_pass_1 is QuadMesh:
			rain = g
	_check("rain particles are in the scene tree", rain != null,
		"" if rain == null else "%s, amount=%d, parent=%s"
			% [rain.name, rain.amount, rain.get_parent().name])
	if rain != null:
		_check("rain has a process material and a draw pass",
			rain.process_material != null and rain.draw_pass_1 != null)

## The crab pack hides under water in daylight, clinging spread around the four caisson
## legs (visible by leaning over a rim or diving) — none up on the plating until night.
## Their bodies must also be SEATED near their authored cling bands, not hovering at
## hand-typed heights (the old pack floated 0.6 m off the deck).
##
## The count is read from the SPAWNER, not restated here. This asserted `>= 14` from the
## s14 spec and had been failing since the 2026-07-25 predator pass cut the pack to 6 —
## a stale expectation reporting a bug that did not exist, which is worse than no test.
## It is 8 today; reading BloomFauna.CRAB_COUNT means the next retune does not re-break it.
func _check_crabs() -> void:
	var crabs: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is GiantCrab:
			crabs.append(n)
	var want: int = int(preload("res://scripts/world/bloom_fauna.gd").CRAB_COUNT)
	_check("the full crab pack spawned", crabs.size() >= want,
		"%d crabs (want %d)" % [crabs.size(), want])
	var under: int = 0
	var at_legs: int = 0
	var claws: int = 0
	for c in crabs:
		var pos: Vector3 = (c as Node3D).global_position
		if pos.y < 0.5:
			under += 1
		if absf(absf(pos.x) - 22.0) < 5.0 and absf(absf(pos.z) - 12.0) < 5.0:
			at_legs += 1
		# No procedural limb overlay may be VISIBLE on top of the generated shell —
		# that is what put phantom jaws in front of the crab's own sculpted claws.
		var stray: bool = false
		for leg in (c as GiantCrab)._legs:
			for n in [leg["hip"], leg["knee"]]:
				for m in (n as Node3D).get_children():
					if m is MeshInstance3D and (m as MeshInstance3D).visible:
						stray = true
		if not stray:
			claws += 1
	_check("every crab hides under water in daylight", under == crabs.size(),
		"%d of %d below y0.5" % [under, crabs.size()])
	_check("the pack is spread around the caisson legs", at_legs == crabs.size(),
		"%d of %d within a leg footprint" % [at_legs, crabs.size()])
	_check("no phantom limb geometry floats over the generated shell",
		claws == crabs.size(), "%d of %d clean" % [claws, crabs.size()])

## Breaker 4-A: walk from the y10 landing, through the annex door, to within the
## interaction ray's reach of the panel — the reported symptom was that no prompt ever
## appeared, which is what an unreachable room looks like from the player's side.
func _check_breaker() -> void:
	var panel: Node3D = null
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is BreakerPanel:
			panel = n
	_check("Master Breaker 4-A exists", panel != null,
		"" if panel == null else str(panel.global_position))
	if panel == null:
		return
	_check("breaker offers OPERATE before power is restored",
		not (panel as Interactable).available_verbs().is_empty(),
		str((panel as Interactable).available_verbs()))

	_body = CharacterBody3D.new()
	_body.collision_layer = 0
	_body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	shape.shape = cap
	_body.add_child(shape)
	shape.position = Vector3(0, COL_Y, 0)
	add_child(_body)

	# Landing (west pocket, y10) -> door apron -> through the doorway -> at the panel.
	var route: Array = [
		Vector3(22.7, 10.15, -1.0),
		Vector3(23.5, 10.15, 1.0),
		Vector3(23.5, 10.15, 3.5),
		Vector3(23.2, 10.15, 7.9),
	]
	_body.global_position = route[0]
	for i in range(30):
		_body.velocity.y -= GRAVITY * _step
		_body.move_and_slide()
		await get_tree().physics_frame

	var reached: int = 0
	for i in range(1, route.size()):
		var target: Vector3 = route[i]
		var best: float = _body.global_position.distance_to(target)
		var stalled: float = 0.0
		while stalled < 2.0:
			var to: Vector3 = target - _body.global_position
			var dir: Vector3 = Vector3(to.x, 0, to.z).normalized()
			_body.velocity.x = dir.x * SPEED
			_body.velocity.z = dir.z * SPEED
			_body.velocity.y = 0.0 if _body.is_on_floor() else _body.velocity.y - GRAVITY * _step
			_body.move_and_slide()
			await get_tree().physics_frame
			var d: float = _body.global_position.distance_to(target)
			if d < best - 0.04:
				best = d
				stalled = 0.0
			else:
				stalled += _step
			if Vector2(to.x, to.z).length() < 0.6 and absf(to.y) < 1.2:
				break
		if _body.global_position.distance_to(target) < 1.2:
			reached += 1
		else:
			_say("      stalled short of %s at %s"
				% [target, _body.global_position.snapped(Vector3.ONE * 0.01)])
			break
	_check("a player can walk from the stair landing into Breaker Room 4-A",
		reached == route.size() - 1, "%d of %d legs" % [reached, route.size() - 1])

	var eye: Vector3 = _body.global_position + Vector3(0, EYE_Y, 0)
	var dist: float = eye.distance_to(panel.global_position)
	_check("the breaker is within the interaction ray's reach", dist <= REACH,
		"%.2fm from the panel (reach %.1fm)" % [dist, REACH])
	# LINE OF SIGHT — the check whose absence let a buried panel pass before: the NE
	# caisson leg rose through the old room and the panel sat whole inside its concrete,
	# while this probe only measured straight-line distance. The eye-to-panel ray must
	# now reach the panel's OWN body, not whatever concrete stands in between.
	var q := PhysicsRayQueryParameters3D.create(eye, panel.global_position)
	q.exclude = [(_body as CollisionObject3D).get_rid()]
	var hit: Dictionary = _body.get_world_3d().direct_space_state.intersect_ray(q)
	_check("the breaker is VISIBLE from where the player stands (nothing in between)",
		not hit.is_empty() and (hit.get("collider") as Node) == panel,
		"ray hit %s" % (hit.get("collider") if not hit.is_empty() else "nothing"))
