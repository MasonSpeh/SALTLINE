extends Node3D
## AV2 kit contact sheet — photographs every kit ALONE on a neutral deck so the
## geometry can be judged without the rig's clutter in front of it. Two angles per
## kit: a three-quarter hero view and a low view (how you actually see a bedroll
## or a rug when you walk up to it). Saves /tmp/av2_<kit>.png.
##
## Run WINDOWED (a headless viewport photographs black):
##   godot --path . res://tests/AV2KitShot.tscn

var _cam: Camera3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.52, 0.58)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	for spec in [[Vector3(4, 6, 4), 1.7], [Vector3(-5, 3, -3), 0.6]]:
		var l := DirectionalLight3D.new()
		add_child(l)
		l.position = spec[0]
		l.light_energy = spec[1]
		l.look_at(Vector3.ZERO, Vector3.UP)
	# A patch of deck to stand things on, so scale reads against something.
	var deck := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	pm.material = MatLib.deck_plate()
	deck.mesh = pm
	add_child(deck)
	# A 1.75m human reference post beside every kit — scale is the whole point.
	var ref := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.22
	cm.height = 1.75
	cm.material = MatLib.flat(Color(0.75, 0.3, 0.3))
	ref.mesh = cm
	add_child(ref)
	ref.position = Vector3(-1.9, 0.875, 0)

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	await get_tree().create_timer(0.6).timeout

	for kit in Structures.KIT_ORDER:
		await _shoot(kit)
	get_tree().quit()

func _bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var world: AABB = mi.global_transform * mi.get_aabb()
		acc = world if first else acc.merge(world)
		first = false
	return acc if not first else AABB()

func _shoot(kit: String) -> void:
	var s: Node3D = Structures.build(kit, false)
	add_child(s)
	s.global_position = Vector3.ZERO
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var b: AABB = _bounds(s)
	var focus: Vector3 = b.get_center()
	var span: float = maxf(b.size.length(), 0.8)
	# hero three-quarter
	_cam.position = focus + Vector3(span * 0.95, span * 0.62, span * 1.05)
	_cam.look_at(focus, Vector3.UP)
	_cam.fov = 55.0
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/av2_%s.png" % kit)
	print("shot %-18s size=(%.2f, %.2f, %.2f) meshes=%d" % [kit, b.size.x, b.size.y, b.size.z,
		s.find_children("*", "MeshInstance3D", true, false).size()])
	s.queue_free()
	await get_tree().process_frame
