extends Node3D
## ULTRA HAMMERHEAD — authored-facing ground truth, measured rather than eyeballed.
##
## SharkProbe answers "what shape is this mesh". This answers the two questions that
## actually decide how it is wired in, and it answers them the only way that has ever
## worked here — with numbers off the running scene, not off a turntable render:
##
##   1. WHICH WAY DOES IT SWIM? The species node is instantiated for real, allowed to
##      patrol for a couple of seconds, and every frame we compare its TRAVEL direction
##      against each of the model node's six local axes in world space. The axis whose
##      dot with travel sits at +1 is the one leading the swim; the axis the nose sits
##      on has to be that one, or the animal is going backwards. Printed per candidate
##      so the FACING_OVERRIDES entry can be read straight off the table.
##   2. HOW BIG IS IT? Post-scale, post-facing world extent along each axis — the number
##      to compare against "a genuinely big animal", instead of trusting that the
##      target_m handed to CreatureAnim.replace() landed on the body's length.
##
## It also fires the two degenerate-vector calls that fauna_move.gd's hot paths can make
## (zero-length normalize, zero-length raycast) with markers around them, so the engine
## error each one produces can be attributed instead of guessed at.
##
## Renders three orthogonal views of the RAW mesh to /tmp/hh_*.png. Run it WITHOUT
## --headless: the headless display server has no renderer and saves black frames.
##   godot --path . res://tests/HammerheadProbe.tscn

const ANIM := preload("res://scripts/world/creature_anim.gd")
const SHARK := preload("res://scripts/world/shark.gd")
const MODEL := "res://assets/models/fauna/ultra_hammerhead/ultra_hammerhead.glb"
const AXES := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN,
	Vector3.BACK, Vector3.FORWARD]
const AXIS_NAMES := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]

var _cam: Camera3D

func _ready() -> void:
	_stage()
	_degenerate_probe()
	await _views()
	await _facing()
	get_tree().quit()

# ------------------------------------------------------------------ degenerate probe
## Fire the two calls fauna_move.gd can make with a zero vector, with markers, so the
## engine error that follows each one can be attributed to a specific call.
func _degenerate_probe() -> void:
	print("[hh] === degenerate-vector attribution ===")
	print("[hh] A> Vector3.ZERO.normalized()")
	var a: Vector3 = Vector3.ZERO.normalized()
	print("[hh] A< returned ", a)
	print("[hh] B> intersect_ray(from == to)")
	var p := Vector3(0.0, 40.0, 0.0)
	var q := PhysicsRayQueryParameters3D.create(p, p)
	var h: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	print("[hh] B< returned ", h)
	print("[hh] C> Vector3(0,0,1).rotated(Vector3.ZERO, 1.0)")
	var c: Vector3 = Vector3(0.0, 0.0, 1.0).rotated(Vector3.ZERO, 1.0)
	print("[hh] C< returned ", c)
	print("[hh] === end attribution ===")

# ------------------------------------------------------------------ raw mesh views
func _views() -> void:
	var model: Node3D = ANIM.load_model(MODEL, 5.0)
	if model == null:
		print("[hh] MISSING ", MODEL)
		return
	add_child(model)
	await get_tree().process_frame
	var box: AABB = _world_bounds(model)
	var c: Vector3 = box.get_center()
	var r: float = maxf(box.size.length() * 0.75, 1.0)
	print("[hh] raw-scaled world AABB pos=%s size=%s" % [str(box.position.snappedf(0.001)), str(box.size.snappedf(0.001))])
	for v in [["sideX", Vector3(r, 0.0, 0.0)], ["top", Vector3(0.0, r, 0.02)],
			["frontZ", Vector3(0.0, 0.0, r)]]:
		_cam.global_position = c + (v[1] as Vector3)
		_cam.look_at(c, Vector3.UP)
		await get_tree().create_timer(0.3).timeout
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("/tmp/hh_raw_%s.png" % v[0])
		print("[hh] view %s -> /tmp/hh_raw_%s.png  (mean luma %.3f)" % [v[0], v[0], _luma(img)])
	model.queue_free()
	await get_tree().process_frame

# ------------------------------------------------------------------ facing / size
## Instantiate the real species node, let it patrol, and correlate travel with the model
## node's local axes. `nose along <axis>` is then read off whichever axis rides at +1.
func _facing() -> void:
	var host := Node3D.new()
	add_child(host)
	var shark: Node3D = SHARK.new(0)
	host.add_child(shark)
	await get_tree().process_frame
	var model: Node3D = _generated(shark)
	if model == null:
		print("[hh] FACING: no generated model under the shark — asset missing or not imported")
		return
	print("[hh] model node rotation_degrees=%s scale=%s"
		% [str(model.rotation_degrees.snappedf(0.01)), str(model.scale.snappedf(0.0001))])
	var local: AABB = _local_bounds(model)
	var world_size: Vector3 = local.size * model.scale.x
	print("[hh] mesh local AABB size=%s  ->  world size=%s  (longest %.3f m)"
		% [str(local.size.snappedf(0.0001)), str(world_size.snappedf(0.001)),
			maxf(world_size.x, maxf(world_size.y, world_size.z))])
	var box: AABB = _world_bounds(model)
	print("[hh] in-world AABB (post facing+scale) size=%s" % str(box.size.snappedf(0.001)))

	# Patrol for a while, correlating travel with each candidate model axis.
	var sums := PackedFloat32Array()
	sums.resize(AXES.size())
	var host_fwd: float = 0.0
	var samples: int = 0
	var prev: Vector3 = shark.global_position
	for i in range(240):
		await get_tree().process_frame
		var now: Vector3 = shark.global_position
		var travel: Vector3 = now - prev
		prev = now
		if travel.length() < 0.0005:
			continue
		var t: Vector3 = travel.normalized()
		var mb: Basis = model.global_transform.basis.orthonormalized()
		for a in range(AXES.size()):
			sums[a] += (mb * (AXES[a] as Vector3)).normalized().dot(t)
		host_fwd += (shark.global_transform.basis.orthonormalized() * Vector3.FORWARD).dot(t)
		samples += 1
	if samples == 0:
		print("[hh] FACING: the shark never moved — cannot measure")
		return
	print("[hh] --- travel vs model-node local axes (%d samples) ---" % samples)
	for a in range(AXES.size()):
		print("[hh]   model %s . travel = %+.4f" % [AXIS_NAMES[a], sums[a] / float(samples)])
	print("[hh]   host  -Z . travel = %+.4f   (shark.gd's own yaw convention)" % (host_fwd / float(samples)))
	print("[hh] READ: whichever local axis the NOSE lies on must be the one at +1.000")
	host.queue_free()

# ------------------------------------------------------------------ helpers
func _generated(host: Node3D) -> Node3D:
	# CreatureAnim.attach() adds the model as the last child of the species node.
	for i in range(host.get_child_count() - 1, -1, -1):
		var c: Node = host.get_child(i)
		if c is Node3D and not (c is MeshInstance3D) \
				and (c as Node3D).find_children("*", "MeshInstance3D", true, false).size() > 0:
			return c as Node3D
	return null

func _world_bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var w: AABB = mi.global_transform * mi.get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	return acc

## Bounds in the MODEL node's own (unrotated, unscaled) frame — the mesh's authored box.
func _local_bounds(model: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	var inv: Transform3D = model.global_transform.affine_inverse()
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		acc = b if first else acc.merge(b)
		first = false
	return acc

func _luma(img: Image) -> float:
	var small: Image = img.duplicate()
	small.resize(48, 27, Image.INTERPOLATE_BILINEAR)
	var sum: float = 0.0
	for y in range(small.get_height()):
		for x in range(small.get_width()):
			sum += small.get_pixel(x, y).get_luminance()
	return sum / float(small.get_width() * small.get_height())

func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.08, 0.10)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)
	var l := DirectionalLight3D.new()
	add_child(l)
	l.position = Vector3(6.0, 8.0, 4.0)
	l.light_energy = 1.5
	l.look_at(Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.far = 400.0
