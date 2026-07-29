extends Node3D
## DEGENERATE-INPUT STRESS for scripts/world/fauna_move.gd.
##
## Every entry point in FaunaMove takes direction vectors from a caller's per-frame state —
## a heading, a surface normal, an intended step. Any of those can arrive as the zero vector
## for perfectly ordinary reasons (a creature that has been pushed onto its own target, a
## raycast that came back with a null normal, a paused animal, a frame with delta 0). When
## it does, the arithmetic downstream is asked to normalize nothing, and Godot answers with
## an engine error PER CALL PER FRAME — which is a performance bug, not a cosmetic one: the
## GDScript backtrace attached to each one is built by walking the whole call stack, and a
## measured harness run turned that into 4.4 GB of stderr and a nine-minute world build.
##
## So: call everything with the degenerate inputs, with a marker printed around each call,
## and let the run's own stderr say which ones are unguarded. Zero engine errors between
## the markers is the pass condition, and the return values are asserted too so a "guard"
## that just swallows the call into nonsense fails as well.
##
##   godot --headless --path . res://tests/FaunaDegenerate.tscn

const MOVE := preload("res://scripts/world/fauna_move.gd")

var _fails: int = 0
var _checks: int = 0

func _ready() -> void:
	_floor()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("=== FaunaMove degenerate-input stress ===")
	_zero_step()
	_zero_heading()
	_zero_up()
	_zero_segment()
	_nan_inputs()
	_zero_crawler()
	print("=== %d checks, FAILURES: %d ===" % [_checks, _fails])
	print("Any 'ERROR:' line printed between the >>> markers above is an unguarded call.")
	get_tree().quit()

## hit_normal / resolve / step with a zero intended move. A deck gull whose target is
## exactly under its feet, or any walker on a frame with delta 0.
func _zero_step() -> void:
	var n := _node(Vector3(0.0, 0.6, 0.0))
	print(">>> hit_normal(step_vec = ZERO)")
	_eq("hit_normal zero step", MOVE.hit_normal(n, Vector3.ZERO, 0.4, 0.35), Vector3.ZERO)
	print(">>> resolve(step_vec = ZERO)")
	_eq("resolve zero step", MOVE.resolve(n, Vector3.ZERO, 0.4, 0.35), Vector3.ZERO)
	print(">>> step(step_vec = ZERO)")
	var before: Vector3 = n.global_position
	_eq("step zero step", MOVE.step(n, Vector3.ZERO, 0.4, 0.35), Vector3.ZERO)
	_ok("step zero leaves position", n.global_position.is_equal_approx(before))
	print(">>> hit_normal(step_vec = 1e-9)")
	_eq("hit_normal tiny step", MOVE.hit_normal(n, Vector3(1e-9, 0.0, 0.0), 0.4, 0.35), Vector3.ZERO)
	n.queue_free()

## obstruction with a zero heading — a paused or just-reseated crawler.
func _zero_heading() -> void:
	var n := _node(Vector3(0.0, 0.6, 0.0))
	print(">>> obstruction(heading = ZERO)")
	_ok("obstruction zero heading -> {}",
		MOVE.obstruction(n, n.global_position, Vector3.ZERO, Vector3.UP, 1.0, 0.4, 0.3).is_empty())
	print(">>> obstruction(heading = 1e-9)")
	_ok("obstruction tiny heading -> {}",
		MOVE.obstruction(n, n.global_position, Vector3(0.0, 0.0, 1e-9), Vector3.UP, 1.0, 0.4, 0.3).is_empty())
	print(">>> obstruction(reach = 0)")
	_ok("obstruction zero reach -> {}",
		MOVE.obstruction(n, n.global_position, Vector3.FORWARD, Vector3.UP, 0.0, 0.4, 0.3).is_empty())
	n.queue_free()

## obstruction / seat / surface_hit with a zero up — a frame where the surface normal
## came back null, or a crawler whose frame has been zeroed by a caller.
func _zero_up() -> void:
	var n := _node(Vector3(0.0, 0.6, 0.0))
	print(">>> obstruction(up = ZERO)")
	_ok("obstruction zero up -> {}",
		MOVE.obstruction(n, n.global_position, Vector3.FORWARD, Vector3.ZERO, 1.0, 0.4, 0.3).is_empty())
	print(">>> obstruction(heading parallel to up)")
	_ok("obstruction parallel frame -> {}",
		MOVE.obstruction(n, n.global_position, Vector3.UP, Vector3.UP, 1.0, 0.4, 0.3).is_empty())
	print(">>> surface_hit(up = ZERO)")
	_ok("surface_hit zero up -> {}",
		MOVE.surface_hit(n, n.global_position, Vector3.ZERO, 0.5, 1.0).is_empty())
	print(">>> seat(up = ZERO)")
	var f: Dictionary = MOVE.seat(n, Vector3.ZERO, Vector3.FORWARD, false, 0.016, 0.5, 0.02, 5.0, 2.0)
	_ok("seat zero up returns a usable frame", (f["up"] as Vector3).is_normalized())
	print(">>> seat(heading = ZERO, unseated)")
	var f2: Dictionary = MOVE.seat(n, Vector3.UP, Vector3.ZERO, true, 0.016, 0.5, 0.02, 5.0, 2.0)
	_ok("seat zero heading returns a frame", f2.has("up") and f2.has("heading"))
	n.queue_free()

## swim_clear with a zero-length or degenerate segment — a swimmer already on its target.
func _zero_segment() -> void:
	var n := _node(Vector3(0.0, 3.0, 0.0))
	var p: Vector3 = n.global_position
	print(">>> swim_clear(from == to)")
	var r: Dictionary = MOVE.swim_clear(n, p, p, 0.4)
	_ok("swim_clear zero seg not blocked", not bool(r["blocked"]))
	_ok("swim_clear zero seg holds position", (r["pos"] as Vector3).is_equal_approx(p))
	print(">>> swim_clear(radius = 0, from == to)")
	var r2: Dictionary = MOVE.swim_clear(n, p, p, 0.0)
	_ok("swim_clear zero seg zero radius", not bool(r2["blocked"]))
	print(">>> swim_clear(1e-9 segment)")
	var r3: Dictionary = MOVE.swim_clear(n, p, p + Vector3(1e-9, 0.0, 0.0), 0.4)
	_ok("swim_clear tiny seg not blocked", not bool(r3["blocked"]))
	n.queue_free()

## NON-FINITE inputs. These are the nastiest class, because EVERY comparison against a NaN
## is false — so `if dist < 0.0001` and `if dir.length() < 0.5` do not fire for them and a
## NaN sails through guards that look like they cover it, straight into the physics server.
func _nan_inputs() -> void:
	var n := _node(Vector3(0.0, 3.0, 0.0))
	var nan := Vector3(NAN, NAN, NAN)
	var inf := Vector3(INF, 0.0, 0.0)
	print(">>> raw Vector3(NAN).normalized()")
	var _v: Vector3 = nan.normalized()
	print(">>> raw intersect_ray(NAN endpoints)")
	var _h: Dictionary = get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3.ZERO, nan))
	print(">>> swim_clear(to = NAN)")
	var r: Dictionary = MOVE.swim_clear(n, n.global_position, nan, 0.4)
	# `blocked` is the CORRECT answer here, not a failure: there is no reachable target, and
	# blocked is the one signal every caller already handles by picking a fresh heading. The
	# thing that must never happen is the old behaviour — returning the NaN as the animal's
	# new position, which turned one bad frame into a permanently lost creature.
	_ok("swim_clear NaN target reports blocked", bool(r["blocked"]))
	_ok("swim_clear NaN target returns a finite pos", (r["pos"] as Vector3).is_finite())
	print(">>> swim_clear(from = NAN)")
	var r2: Dictionary = MOVE.swim_clear(n, nan, n.global_position, 0.4)
	_ok("swim_clear NaN origin returns a finite pos", (r2["pos"] as Vector3).is_finite())
	print(">>> swim_clear(to = INF)")
	var r3: Dictionary = MOVE.swim_clear(n, n.global_position, inf, 0.4)
	_ok("swim_clear INF target returns a finite pos", (r3["pos"] as Vector3).is_finite())
	print(">>> obstruction(heading = NAN)")
	_ok("obstruction NaN heading -> {}",
		MOVE.obstruction(n, n.global_position, nan, Vector3.UP, 1.0, 0.4, 0.3).is_empty())
	print(">>> obstruction(up = NAN)")
	_ok("obstruction NaN up -> {}",
		MOVE.obstruction(n, n.global_position, Vector3.FORWARD, nan, 1.0, 0.4, 0.3).is_empty())
	print(">>> obstruction(pos = NAN)")
	_ok("obstruction NaN pos -> {}",
		MOVE.obstruction(n, nan, Vector3.FORWARD, Vector3.UP, 1.0, 0.4, 0.3).is_empty())
	print(">>> hit_normal(step_vec = NAN)")
	_eq("hit_normal NaN step", MOVE.hit_normal(n, nan, 0.4, 0.35), Vector3.ZERO)
	print(">>> surface_hit(up = NAN)")
	_ok("surface_hit NaN up -> {}",
		MOVE.surface_hit(n, n.global_position, nan, 0.5, 1.0).is_empty())
	n.queue_free()

## A whole SurfaceCrawler driven with a zeroed frame, which is what a caller that has just
## reseated or scaled a heading to nothing hands it.
func _zero_crawler() -> void:
	var n := _node(Vector3(0.0, 0.6, 0.0))
	var c := MOVE.SurfaceCrawler.new(n.global_position, 3.0, 0.4, 11, 0.25, 0.2, 0.0)
	print(">>> SurfaceCrawler.tick with heading = ZERO")
	c.heading = Vector3.ZERO
	c.tick(n, 0.016)
	_ok("crawler recovers a heading", c.heading.length() > 0.001)
	print(">>> SurfaceCrawler.tick with up = ZERO")
	c.up = Vector3.ZERO
	c.tick(n, 0.016)
	_ok("crawler recovers an up", c.up.length() > 0.001)
	print(">>> SurfaceCrawler.tick with both ZERO")
	c.heading = Vector3.ZERO
	c.up = Vector3.ZERO
	c.tick(n, 0.016)
	_ok("crawler recovers both", c.up.length() > 0.001 and c.heading.length() > 0.001)
	print(">>> SurfaceCrawler.basis()/look_basis() on a degenerate frame")
	c.heading = Vector3.UP
	c.up = Vector3.UP
	var _b: Basis = c.basis()
	var _l: Basis = c.look_basis(Vector3.ZERO)
	_ok("degenerate basis survived", true)
	print(">>> 300 ticks of a zero-delta crawler")
	for i in range(300):
		c.tick(n, 0.0)
	_ok("zero-delta ticks survived", c.up.length() > 0.001)
	n.queue_free()

# ---------------------------------------------------------------- harness
func _node(at: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	return n

func _floor() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	cs.shape = box
	body.add_child(cs)
	body.global_position = Vector3(0.0, -0.5, 0.0)
	# A wall to bump, so the decision paths are exercised and not just the clear ones.
	var wall := StaticBody3D.new()
	add_child(wall)
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(0.5, 4.0, 20.0)
	ws.shape = wb
	wall.add_child(ws)
	wall.global_position = Vector3(2.0, 2.0, 0.0)

func _ok(what: String, cond: bool) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("FAIL: ", what)

func _eq(what: String, got: Vector3, want: Vector3) -> void:
	_ok("%s (got %s want %s)" % [what, str(got), str(want)], got.is_equal_approx(want))
