extends Node3D
## FIXER contact sheet — photographs only the kits this pass reworked, so the
## geometry claims can be judged rather than asserted:
##   bedroll_kit      soft silhouette instead of stacked boxes
##   windbreak_kit    canvas that sags instead of a projector screen
##   rain_catcher_kit sagging pitched tarps + a water disc that can move
##   leanto_kit       sagging roof
##   chair_kit        sagging sling
##   planter_kit      tapered curling blades instead of cyan prisms
##   shelf_kit        never photographed by any previous harness
##
## Run WINDOWED (a headless viewport photographs black):
##   godot --path . res://tests/FixerKitShot.tscn

const KITS: Array[String] = [
	"bedroll_kit", "windbreak_kit", "rain_catcher_kit", "leanto_kit",
	"chair_kit", "planter_kit", "shelf_kit",
]

var _cam: Camera3D
var _out: String = "user://fixer_shots"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
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
	var deck := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	pm.material = MatLib.deck_plate()
	deck.mesh = pm
	add_child(deck)
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
	for kit in KITS:
		await _shoot(kit)
	print("shots written to %s" % ProjectSettings.globalize_path(_out))
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
	await get_tree().create_timer(0.4).timeout
	var b: AABB = _bounds(s)
	var focus: Vector3 = b.get_center()
	var span: float = maxf(b.size.length(), 0.8)
	# Low three-quarter: how you actually see a bedroll when you walk up to it.
	_cam.position = focus + Vector3(span * 0.80, span * 0.42, span * 0.92)
	_cam.look_at(focus, Vector3.UP)
	_cam.fov = 55.0
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, kit])
	print("shot %-18s size=(%.2f, %.2f, %.2f) meshes=%d" % [kit, b.size.x, b.size.y, b.size.z,
		s.find_children("*", "MeshInstance3D", true, false).size()])
	s.queue_free()
	await get_tree().process_frame
