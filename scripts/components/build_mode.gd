class_name BuildMode extends Node
## Build mode: press B with a kit in your pack. A ghost of the structure rides your
## aim, snapped to a half-meter grid — green when placeable, red when not.
## R rotates 90°, scroll/Tab cycles kits, LMB places (consumes the kit), B/Esc exits.

const REACH: float = 7.0
const GRID: float = 0.5

var player: CharacterBody3D
var camera: Camera3D
var active: bool = false

var _kit: String = ""
var _ghost: Node3D = null
var _yaw: float = 0.0
var _valid: bool = false
var _place_pos: Vector3

func setup(p: CharacterBody3D, cam: Camera3D) -> void:
	player = p
	camera = cam

func owned_kits() -> Array[String]:
	var out: Array[String] = []
	for kit in Structures.KIT_ORDER:
		if PlayerState.has_item(kit):
			out.append(kit)
	return out

func toggle() -> void:
	if active:
		exit()
		return
	var kits: Array[String] = owned_kits()
	if kits.is_empty():
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Nothing to build — craft a kit at the rigging bench first.")
		return
	if player.carried:
		player.drop_carried()
	active = true
	_kit = kits[0]
	_yaw = 0.0
	_spawn_ghost()
	_hint()

func exit() -> void:
	active = false
	_clear_ghost()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt("")

func _hint() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt_raw("BUILD: %s   [LMB] place  [R] rotate  [Tab] next kit  [B] done"
			% Structures.display_name(_kit))

func _spawn_ghost() -> void:
	_clear_ghost()
	_ghost = Structures.build(_kit, true)
	get_tree().current_scene.add_child(_ghost)

func _clear_ghost() -> void:
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null

func cycle_kit(dir: int = 1) -> void:
	var kits: Array[String] = owned_kits()
	if kits.is_empty():
		exit()
		return
	var idx: int = maxi(kits.find(_kit), 0)
	_kit = kits[wrapi(idx + dir, 0, kits.size())]
	_spawn_ghost()
	_hint()

func _physics_process(_delta: float) -> void:
	if not active or _ghost == null:
		return
	# Aim point: camera ray out to REACH, then drop a vertical ray to find the deck.
	var from: Vector3 = camera.global_position
	var aim: Vector3 = from - camera.global_transform.basis.z * REACH
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(aim + Vector3(0, 3.0, 0), aim + Vector3(0, -8.0, 0))
	q.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	_valid = false
	if hit.has("position") and hit.get("normal", Vector3.UP).y > 0.75:
		var p: Vector3 = hit["position"]
		p.x = snappedf(p.x, GRID)
		p.z = snappedf(p.z, GRID)
		_place_pos = p
		_valid = from.distance_to(p) <= REACH + 2.0
	_ghost.visible = hit.has("position")
	if _ghost.visible:
		_ghost.global_position = _place_pos
		_ghost.rotation.y = _yaw
		_tint_ghost(Color(0.4, 1.0, 0.6) if _valid else Color(1.0, 0.35, 0.3))

func _tint_ghost(color: Color) -> void:
	for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var mat: Material = mesh.surface_get_material(s)
			if mat is StandardMaterial3D:
				var base: Color = (mat as StandardMaterial3D).albedo_color
				(mat as StandardMaterial3D).albedo_color = Color(
					lerpf(base.r, color.r, 0.35), lerpf(base.g, color.g, 0.35),
					lerpf(base.b, color.b, 0.35), base.a)

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				_yaw = wrapf(_yaw + PI * 0.5, 0.0, TAU)
				get_viewport().set_input_as_handled()
			KEY_TAB:
				cycle_kit(1)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				exit()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				place()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				cycle_kit(1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				cycle_kit(-1)
				get_viewport().set_input_as_handled()

func place() -> bool:
	if not _valid or not PlayerState.has_item(_kit):
		return false
	PlayerState.remove_item(_kit)
	var built: Node3D = Structures.build(_kit, false)
	get_tree().current_scene.add_child(built)
	built.global_position = _place_pos
	built.rotation.y = _yaw
	AudioDirector.play_one_shot("clang", _place_pos, -8.0)
	Journal.discover("place_building")
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Built: %s" % Structures.display_name(_kit))
	# Keep building if more kits of any kind remain; else drop out of the mode.
	if owned_kits().is_empty():
		exit()
	else:
		if not PlayerState.has_item(_kit):
			_kit = owned_kits()[0]
			_spawn_ghost()
		_hint()
	return true
