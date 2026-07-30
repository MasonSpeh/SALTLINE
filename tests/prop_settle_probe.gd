extends Node
## Do dropped props come to rest on the wet deck, or do they shake and circle?
##
## The owner reported boxes "glitching out and shaking / moving in circles when dropped on
## the wetdeck". That is a claim about a RATE, and no probe in this repo measured one — so
## this drops a real `PhysProp` on a spread of wet-deck spots, lets the solver run, and
## then measures, per spot: the residual linear and angular speed over the last second,
## how far the body wandered after it should have been at rest, and whether it ever slept.
##
## Deliberately headless-safe: rigid bodies are real nodes, so the MultiMesh
## identity-transform trap does not apply here.
##
## The spots are not decorative. Each names a specific piece of wet-deck collision:
## open plating, the places where two static colliders present the SAME walking plane,
## and the foot of the stair tower where three of them used to.
##
## Run: godot --headless --path . res://tests/PropSettleProbe.tscn

const WET_Y: float = 2.0
const SETTLE_SEC: float = 5.0      ## time given to come to rest
const WATCH_SEC: float = 1.5       ## window the residual motion is measured over
const REST_V: float = 0.02         ## m/s a body at rest may still show
const REST_W: float = 0.05         ## rad/s ditto
const REST_DRIFT: float = 0.02     ## m it may wander during the watch window

const LOG_PATH: String = "/tmp/prop_settle_probe.txt"

## [name, x, z] — dropped 0.35 m over the plating at each.
const SPOTS := [
	["open plating (mid deck)", 19.0, -10.0],
	["open plating (SW)", 12.0, -18.0],
	["stair entry pad", 23.0, -4.6],
	["foot of tower flight 1", 23.5, -2.9],
	["ready-room arch threshold", 18.0, -10.0],
	["tower bumpout seam (x30)", 29.4, -3.0],
	["wet-deck respawn", 20.0, -19.0],
	["rigging bench area", 25.0, -17.9],
]

## The same plating, from 2.0 m up. A prop reaching the deck at ~6 m/s covers 0.20 m per
## 30 Hz tick, and the wet deck's collision is a CSG-baked ConcavePolygonShape3D — the one
## shape class in Godot with no inside. Discrete detection against triangle soup at that
## step size is exactly where a 0.26 m box goes through 0.5 m of plating.
const HIGH_SPOTS := [
	["high drop (mid deck)", 19.0, -10.0],
	["high drop (SW)", 12.0, -18.0],
	["high drop (respawn)", 20.0, -19.0],
]

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()

func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	if main.get_script() == null:
		_say("FAIL  Main.tscn came back script-less — a parse error upstream. Nothing below is real.")
		failures = 1
		_finish()
		return
	await get_tree().process_frame
	await get_tree().create_timer(5.0).timeout

	var bodies: Array[RigidBody3D] = []
	var names: Array[String] = []
	for s in SPOTS:
		bodies.append(_drop(float(s[1]), float(s[2])))
		names.append(String(s[0]))
	for s in HIGH_SPOTS:
		bodies.append(_drop(float(s[1]), float(s[2]), 2.0))
		names.append(String(s[0]))
	# A PLAIN DROP IS NOT WHAT THE OWNER DID. Every spot above settles instantly; the
	# report is about props "dropped", i.e. CARRIED and then released. The carry loop
	# steers the prop with velocity (`linear_velocity = (target - pos) * 12` and a yaw
	# servo writing `angular_velocity.y = err * 10`), and release only nulls `held_by`.
	# So the body inherits whatever the servo was commanding on the last held frame.
	# These three reproduce that against a real carry, not an approximation of one.
	# All three on OPEN plating well inside the deck (x 8..30, z -22..2) and clear of the
	# ready room (x 10..18, z -14..-6), the stair tower shell (x >= 21) and the pump skids.
	for c in [["released standing still", 19.0, -17.0, 0.0],
			["released looking down", 21.5, -17.0, 0.0],
			["released mid-turn", 24.0, -17.0, 3.0]]:
		bodies.append(await _carry_and_release(float(c[1]), float(c[2]), float(c[3]),
			String(c[0]) == "released looking down"))
		names.append(String(c[0]))
	await get_tree().create_timer(SETTLE_SEC).timeout

	# Watch window: sample every physics frame so a 30 Hz jitter cannot hide between reads.
	var start: Array[Vector3] = []
	var vmax: PackedFloat32Array = PackedFloat32Array()
	var wmax: PackedFloat32Array = PackedFloat32Array()
	var drift: PackedFloat32Array = PackedFloat32Array()
	for b in bodies:
		start.append(b.global_position)
		vmax.append(0.0)
		wmax.append(0.0)
		drift.append(0.0)
	var t: float = 0.0
	while t < WATCH_SEC:
		await get_tree().physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
		for i in range(bodies.size()):
			var b: RigidBody3D = bodies[i]
			vmax[i] = maxf(vmax[i], b.linear_velocity.length())
			wmax[i] = maxf(wmax[i], b.angular_velocity.length())
			drift[i] = maxf(drift[i], b.global_position.distance_to(start[i]))

	_say("PROP SETTLE PROBE — %d drops, %.1fs settle then %.1fs watched at %d Hz"
		% [bodies.size(), SETTLE_SEC, WATCH_SEC, Engine.physics_ticks_per_second])
	_say("%-28s %8s %8s %8s %7s %8s" % ["spot", "|v|max", "|w|max", "drift", "sleep", "rest y"])
	for i in range(bodies.size()):
		var b: RigidBody3D = bodies[i]
		var bad: bool = vmax[i] > REST_V or wmax[i] > REST_W or drift[i] > REST_DRIFT \
			or b.global_position.y < WET_Y - 0.5
		_say("%-28s %8.4f %8.4f %8.4f %7s %8.3f  %s"
			% [names[i], vmax[i], wmax[i], drift[i],
				"yes" if b.sleeping else "NO", b.global_position.y, "<- RESTLESS" if bad else ""])
		if bad:
			failures += 1
	if failures == 0:
		_say("PASS  every dropped prop came to rest (|v| <= %.3f m/s, |w| <= %.3f rad/s, drift <= %.3f m)"
			% [REST_V, REST_W, REST_DRIFT])
	_finish()

func _finish() -> void:
	_say("---")
	_say("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Carry a prop for a second against a stand-in holder that has the `Head/Camera3D` the
## carry loop reads, then release it exactly the way `drop_carried()` does — by nulling
## `held_by` and touching nothing else. `yaw_rate` turns the holder while carrying, which
## is what loads up the yaw servo's error term.
func _carry_and_release(x: float, z: float, yaw_rate: float, look_down: bool) -> RigidBody3D:
	var holder := Node3D.new()
	var head := Node3D.new()
	head.name = "Head"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	head.add_child(cam)
	holder.add_child(head)
	add_child(holder)
	holder.global_position = Vector3(x, WET_Y + 0.2, z + 1.6)
	head.position = Vector3(0, 1.6, 0)
	if look_down:
		cam.rotation.x = deg_to_rad(-62.0)   # the angle you actually set a crate down at
	var p: RigidBody3D = _drop(x, z)
	await get_tree().create_timer(0.6).timeout
	p.set("held_by", holder)
	var t: float = 0.0
	while t < 1.0:
		await get_tree().physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
		holder.rotation.y += deg_to_rad(yaw_rate) * 6.0 / float(Engine.physics_ticks_per_second)
	# The number that proves the clamp: what the body is holding the instant it stops
	# being held. This is what player_controller.drop_carried() hands to the solver.
	var v0: Vector3 = p.linear_velocity
	var w0: Vector3 = p.angular_velocity
	var held_at: Vector3 = p.global_position
	p.set("held_by", null)
	await get_tree().physics_frame
	var trace: PackedStringArray = PackedStringArray()
	for k in range(8):
		await get_tree().create_timer(0.15).timeout
		trace.append("%.2f" % p.global_position.y)
	_say("  trace @ (%.1f,%.1f) held_at=%s y after release: %s"
		% [x, z, str(held_at.snappedf(0.01)), " ".join(trace)])
	_say("  release @ (%.1f, %.1f): commanded |v| %.2f m/s, |w| %.2f rad/s  ->  handed off |v| %.2f, |w| %.2f"
		% [x, z, v0.length(), w0.length(), p.linear_velocity.length(), p.angular_velocity.length()])
	return p

## One dunnage-block-sized PhysProp, dropped 0.35 m over the plating — the same class,
## mass and shape main.gd scatters on the wet deck.
func _drop(x: float, z: float, height: float = 0.35) -> RigidBody3D:
	var p := PhysProp.new()
	p.mass = 1.6
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.26, 0.42)
	mi.mesh = bm
	p.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	p.add_child(cs)
	add_child(p)
	p.global_position = Vector3(x, WET_Y + height, z)
	return p
