extends Node
## Diagnostic for a single reported stair jam: name the collider the capsule is
## actually wedged against, in a form that identifies WHICH builder made it.
##
## StairWalkProbe reports a stall as an auto-generated node path (@StaticBody3D@262),
## which says nothing about whether the blocker is StairKit's walking ramp, its top
## lip, a stringer, or one of RigBuilder's guard slabs. This walks the same capsule
## up the same flight and, at the stall, dumps every collider within a metre: its
## shape, its size, its world transform, and the surface normal it presents.
##
## Run: godot --headless --path . res://tests/StairJamProbe.tscn

const RADIUS: float = 0.4
const HEIGHT: float = 1.8
const COL_Y: float = 0.9
const SPEED: float = 3.2
const GRAVITY: float = 9.8

## Flight 1 of the central tower: foot (23.5, 2, -2.9) -> top (28.5, 6, -2.9).
const FOOT := Vector3(23.5, 2.05, -2.9)
const TOP := Vector3(28.5, 6.05, -2.9)

const LOG_PATH: String = "/tmp/stair_jam_probe.txt"

var _body: CharacterBody3D
var _lines: PackedStringArray = PackedStringArray()

func _ready() -> void:
	await _run()
	get_tree().quit(0)

func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	for i in range(10):
		await get_tree().physics_frame

	var p: Node3D = main.get("player")
	if p != null and p is CollisionObject3D:
		var pc := p as CollisionObject3D
		pc.set_collision_layer_value(1, false)
		pc.set_collision_mask_value(1, false)
		(p as Node3D).global_position = Vector3(0, 400, 0)

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
	_body.global_position = FOOT

	_say("floor_max_angle = %.2f deg" % rad_to_deg(_body.floor_max_angle))
	_say("flight 1 slope   = %.2f deg" % rad_to_deg(atan2(4.0, 5.0)))
	_say("climbing %s -> %s" % [FOOT, TOP])

	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	var best: float = _body.global_position.distance_to(TOP)
	var stalled: float = 0.0
	var t: float = 0.0
	while t < 30.0:
		var to_top: Vector3 = TOP - _body.global_position
		var dir: Vector3 = Vector3(to_top.x, 0, to_top.z).normalized()
		_body.velocity.x = dir.x * SPEED
		_body.velocity.z = dir.z * SPEED
		_body.velocity.y = 0.0 if _body.is_on_floor() else _body.velocity.y - GRAVITY * step
		_body.move_and_slide()
		await get_tree().physics_frame
		t += step
		var d: float = _body.global_position.distance_to(TOP)
		if d < best - 0.04:
			best = d
			stalled = 0.0
		else:
			stalled += step
		if d < 0.7:
			_say("REACHED the top — no jam on this flight.")
			return
		if stalled > 1.5:
			_report_jam()
			return
	_say("timed out without reaching the top or stalling cleanly")

func _report_jam() -> void:
	var pos: Vector3 = _body.global_position
	_say("")
	_say("JAMMED at %s  (on_floor=%s on_wall=%s)"
		% [pos, _body.is_on_floor(), _body.is_on_wall()])
	_say("  floor normal: %s   wall normal: %s"
		% [_body.get_floor_normal(), _body.get_wall_normal()])
	for i in range(_body.get_slide_collision_count()):
		var c := _body.get_slide_collision(i)
		_say("  slide %d: normal=%s  collider=%s"
			% [i, c.get_normal(), _describe(c.get_collider())])
	_say("")
	_say("colliders within 1.2m of the capsule:")
	for body in _nearby(pos, 1.2):
		_say("  " + _describe(body))
		for c in (body as Node).get_children():
			var cs := c as CollisionShape3D
			if cs == null:
				continue
			var sz: String = "?"
			if cs.shape is BoxShape3D:
				sz = str((cs.shape as BoxShape3D).size)
			_say("      shape %s size=%s  world_y=%.3f  rot_x=%.2f deg  disabled=%s"
				% [cs.shape.get_class(), sz, cs.global_position.y,
					rad_to_deg(cs.global_transform.basis.get_euler().x), cs.disabled])

## Walk the whole tree rather than using a physics query: a shape query returns the
## same anonymous RIDs the stall report already gave us, and what we need is the
## node identity and its ancestry.
func _nearby(pos: Vector3, r: float) -> Array:
	var out: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var sb := n as StaticBody3D
		if sb == null:
			continue
		for c in sb.get_children():
			var cs := c as CollisionShape3D
			if cs == null or cs.disabled:
				continue
			if cs.global_position.distance_to(pos) <= r + 3.0:
				out.append(sb)
				break
	return out

## Identity that survives auto-generated names: the chain of parents plus whatever
## script built it, and whether the body carries a mesh (StairKit's railed _vbox does,
## its walking body does not — that is the exact test _stair_run uses).
func _describe(o: Object) -> String:
	var n := o as Node
	if n == null:
		return str(o)
	var chain: String = ""
	var cur: Node = n
	for i in range(4):
		if cur == null:
			break
		chain = cur.name + ("/" + chain if chain != "" else "")
		cur = cur.get_parent()
	var has_mesh: bool = false
	for c in n.get_children():
		if c is MeshInstance3D:
			has_mesh = true
	var scr: String = ""
	var owner_script: Variant = n.get_script()
	if owner_script != null:
		scr = " script=" + str(owner_script.resource_path).get_file()
	var par_script: String = ""
	if n.get_parent() != null and n.get_parent().get_script() != null:
		par_script = " parent_script=" + str(n.get_parent().get_script().resource_path).get_file()
	return "%s  carries_mesh=%s%s%s" % [chain, has_mesh, scr, par_script]
