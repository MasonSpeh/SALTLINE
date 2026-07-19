class_name BuildMode extends Node
## Build mode: press B with a kit in your pack. A ghost of the structure rides your
## aim, snapped to a quarter-meter grid and to the surface you are looking at —
## green when placeable, red when not.
##
##   [LMB]      place (consumes the kit)
##   [Q] / [E]  rotate 45 degrees   [R] rotate 90 degrees
##   [1]..[9]   jump straight to a kit    [Tab] / wheel  next kit
##   [X]        dismantle a structure you built (the kit comes back)
##   [B] / Esc  leave build mode
##
## Wall kits (Structures.WALL_MOUNT) use a camera ray and align their local +Z to
## the wall normal, so a shelf hangs on the bulkhead instead of standing on the
## deck. Flat kits (Structures.TILT_TO_SURFACE) tilt to follow a sloped deck.
##
## Deliberately NOT enforced: overlap. Bases are built by layering — a rug under a
## chair, a bedroll inside a lean-to, a lamp on a walkway — so intersecting
## footprints are allowed on purpose.

const REACH: float = 7.0
const GRID: float = 0.25
const ROT_STEP: float = PI * 0.25   # 45 degrees

var player: CharacterBody3D
var camera: Camera3D
var active: bool = false

var _kit: String = ""
var _ghost: Node3D = null
var _yaw: float = 0.0
var _valid: bool = false
var _place_pos: Vector3
var _place_basis: Basis = Basis()
var _wall_mode: bool = false
var _remove_target: Node3D = null

var _ui: CanvasLayer = null
var _strip: Label = null
var _ui_sig: String = ""

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
	# An empty pack is NOT a reason to keep you out. Build mode is also the only way
	# to take a structure apart, and the moment you most want to move the chair a
	# metre to the left is precisely the moment you have just spent your last kit.
	if kits.is_empty() and not _anything_built():
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Nothing to build — craft a kit at the rigging bench first.")
		return
	if player.carried:
		player.drop_carried()
	active = true
	_kit = kits[0] if not kits.is_empty() else ""
	_yaw = 0.0
	_remove_target = null
	_spawn_ghost()
	_hint()
	_refresh_ui(true)

func _anything_built() -> bool:
	for s in get_tree().get_nodes_in_group("built_structures"):
		if s != _ghost and is_instance_valid(s):
			return true
	return false

func exit() -> void:
	active = false
	_clear_ghost()
	_remove_target = null
	_clear_ui()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt("")

func _exit_tree() -> void:
	_clear_ui()

func _hint() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if _kit == "":
		hud.show_prompt_raw("BUILD  no kits in the pack  ·  [X] dismantle  [B] done")
	else:
		hud.show_prompt_raw("BUILD  [LMB] place  [Q/E] turn  [X] dismantle  [1-9] kit  [B] done")

# ------------------------------------------------------------------ the ghost

## No kit selected means no preview — dismantle-only mode still needs the rest of
## _physics_process to run, so the ghost being null is a legal state, not a bail-out.
func _spawn_ghost() -> void:
	_clear_ghost()
	if _kit == "":
		return
	_ghost = Structures.build(_kit, true)
	get_tree().current_scene.add_child(_ghost)

func _clear_ghost() -> void:
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null

func cycle_kit(dir: int = 1) -> void:
	var kits: Array[String] = owned_kits()
	if kits.is_empty():
		return   # nothing to cycle to; stay in dismantle-only mode
	var idx: int = maxi(kits.find(_kit), 0)
	select_kit(kits[wrapi(idx + dir, 0, kits.size())])

func select_kit(kit: String) -> void:
	if kit == "" or kit == _kit:
		return
	_kit = kit
	_spawn_ghost()
	_hint()
	_refresh_ui(true)

func select_slot(i: int) -> void:
	var kits: Array[String] = owned_kits()
	if i >= 0 and i < kits.size():
		select_kit(kits[i])

func _cam_ray(dist: float) -> Dictionary:
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_transform.basis.z * dist
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q)

func _physics_process(_delta: float) -> void:
	if not active:
		return
	# Dismantle-only mode: no kit in the pack, so no ghost — but the removal ray must
	# still run, or [X] would silently do nothing while you stare at your own chair.
	if _ghost == null:
		_valid = false
		_wall_mode = false
		_update_remove_target(_cam_ray(REACH))
		_refresh_ui(false)
		return
	var from: Vector3 = camera.global_position
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var cam_hit: Dictionary = _cam_ray(REACH)
	var cam_n: Vector3 = cam_hit.get("normal", Vector3.UP)

	# Wall kits take the surface the camera is actually pointing at, if it is a wall.
	_wall_mode = false
	var hit: Dictionary = {}
	if Structures.WALL_MOUNT.has(_kit) and cam_hit.has("position") and absf(cam_n.y) < 0.55:
		hit = cam_hit
		_wall_mode = true
	else:
		# Everything else: drop a vertical ray at the aim point to find the deck.
		var aim: Vector3 = from - camera.global_transform.basis.z * REACH
		var q := PhysicsRayQueryParameters3D.create(aim + Vector3(0, 3.0, 0), aim + Vector3(0, -8.0, 0))
		q.exclude = [player.get_rid()]
		hit = space.intersect_ray(q)
		if not hit.has("position") and cam_hit.has("position") and cam_n.y > 0.75:
			hit = cam_hit

	_valid = false
	if hit.has("position"):
		var n: Vector3 = hit.get("normal", Vector3.UP)
		var p: Vector3 = hit["position"]
		if _wall_mode:
			p.y = snappedf(p.y, GRID)
			_place_basis = _wall_basis(n)
		else:
			p.x = snappedf(p.x, GRID)
			p.z = snappedf(p.z, GRID)
			_place_basis = _floor_basis(n)
		_place_pos = p
		_valid = from.distance_to(p) <= REACH + 2.0 and (_wall_mode or n.y > 0.75)
	_ghost.visible = hit.has("position")
	if _ghost.visible:
		_ghost.global_transform = Transform3D(_place_basis, _place_pos)
		_tint_ghost(Color(0.4, 1.0, 0.6) if _valid else Color(1.0, 0.35, 0.3))
	_update_remove_target(cam_hit)
	_refresh_ui(false)

## Stand upright on the deck; flat kits lie down along a sloped one.
func _floor_basis(n: Vector3) -> Basis:
	var spin := Basis(Vector3.UP, _yaw)
	if Structures.TILT_TO_SURFACE.has(_kit) and n.dot(Vector3.UP) < 0.999 and n.dot(Vector3.UP) > -0.9:
		return Basis(Quaternion(Vector3.UP, n.normalized())) * spin
	return spin

## Face out of the wall: local +Z is the surface normal, local +Y stays world up.
func _wall_basis(n: Vector3) -> Basis:
	var z_axis: Vector3 = n.normalized()
	var x_axis: Vector3 = Vector3.UP.cross(z_axis)
	if x_axis.length_squared() < 0.001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)

func _tint_ghost(color: Color) -> void:
	for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			var mat: Material = mesh.surface_get_material(s)
			if mat is StandardMaterial3D:
				var base: Color = (mat as StandardMaterial3D).albedo_color
				(mat as StandardMaterial3D).albedo_color = Color(
					lerpf(base.r, color.r, 0.35), lerpf(base.g, color.g, 0.35),
					lerpf(base.b, color.b, 0.35), base.a)

# ------------------------------------------------------------------ dismantle

func _update_remove_target(cam_hit: Dictionary) -> void:
	_remove_target = null
	if cam_hit.has("collider"):
		_remove_target = _owning_structure(cam_hit["collider"])
	if _remove_target != null:
		return
	# Rugs and bedrolls carry no collider on purpose — fall back to proximity.
	var aim: Vector3 = camera.global_position - camera.global_transform.basis.z * REACH
	var probe: Vector3 = _place_pos if _valid else aim
	var best: float = 1e9
	for s in get_tree().get_nodes_in_group("built_structures"):
		var node := s as Node3D
		if node == null or node == _ghost:
			continue
		var kit: String = str(node.get_meta("kit", ""))
		var r: float = Structures.footprint(kit)
		var d: float = Vector2(node.global_position.x - probe.x, node.global_position.z - probe.z).length()
		if d <= r and absf(node.global_position.y - probe.y) < 1.6 and d < best:
			best = d
			_remove_target = node

func _owning_structure(collider: Variant) -> Node3D:
	var cur: Node = collider as Node
	while cur != null:
		if cur is Node3D and cur.is_in_group("built_structures"):
			return cur as Node3D
		cur = cur.get_parent()
	return null

## Take a structure apart and get the kit back. Building a home means moving
## things until they are right.
func dismantle() -> bool:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if _remove_target == null or not is_instance_valid(_remove_target):
		if hud:
			hud.toast("Nothing of yours to take apart there.")
		return false
	var kit: String = str(_remove_target.get_meta("kit", ""))
	if kit == "":
		if hud:
			hud.toast("That was bolted down long before you got here.")
		return false
	if not PlayerState.add_item(kit):
		return false   # add_item already said the pack is full
	var where: Vector3 = _remove_target.global_position
	_remove_target.queue_free()
	_remove_target = null
	AudioDirector.play_one_shot(Structures.place_sound(kit), where, -10.0)
	if hud:
		hud.toast("Dismantled: %s" % Structures.display_name(kit))
	if _kit == "" and not owned_kits().is_empty():
		select_kit(owned_kits()[0])
	return true

# ----------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_9:
			select_slot(key - KEY_1)
			get_viewport().set_input_as_handled()
			return
		match key:
			KEY_E:
				_rotate(ROT_STEP)
				get_viewport().set_input_as_handled()
			KEY_Q:
				_rotate(-ROT_STEP)
				get_viewport().set_input_as_handled()
			KEY_R:
				_rotate(PI * 0.5)
				get_viewport().set_input_as_handled()
			KEY_X:
				dismantle()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				cycle_kit(1)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				exit()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				place()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				cycle_kit(1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				cycle_kit(-1)
				get_viewport().set_input_as_handled()

func _rotate(amount: float) -> void:
	_yaw = wrapf(_yaw + amount, 0.0, TAU)
	_refresh_ui(true)

# ----------------------------------------------------------------------- place

func place() -> bool:
	if not _valid or not PlayerState.has_item(_kit):
		return false
	PlayerState.remove_item(_kit)
	var built: Node3D = Structures.build(_kit, false)
	get_tree().current_scene.add_child(built)
	built.global_transform = Transform3D(_place_basis.orthonormalized(), _place_pos)
	AudioDirector.play_one_shot(Structures.place_sound(_kit), _place_pos, -8.0)
	Journal.discover("place_building")
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Built: %s" % Structures.display_name(_kit))
	# Out of kits does not mean out of build mode: what you just put down is the
	# thing you are most likely to want to nudge, turn, or take straight back up.
	if owned_kits().is_empty():
		_kit = ""
		_clear_ghost()
	elif not PlayerState.has_item(_kit):
		_kit = owned_kits()[0]
		_spawn_ghost()
	_hint()
	_refresh_ui(true)
	return true

# -------------------------------------------------------------- the kit strip

func _ensure_ui() -> void:
	if _ui != null and is_instance_valid(_ui):
		return
	_ui = CanvasLayer.new()
	_ui.layer = 4
	add_child(_ui)
	_strip = Label.new()
	_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_strip.offset_top = -104.0
	_strip.offset_bottom = -44.0
	_strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_theme_font_size_override("font_size", 13)
	_strip.add_theme_color_override("font_color", Color(0.86, 0.88, 0.86, 0.95))
	_strip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_strip.add_theme_constant_override("outline_size", 5)
	_strip.add_theme_constant_override("line_spacing", 4)
	_ui.add_child(_strip)

func _clear_ui() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null
	_strip = null
	_ui_sig = ""

## Rebuilt only when something visible actually changed — this runs every frame.
func _refresh_ui(force: bool) -> void:
	if not active:
		return
	var kits: Array[String] = owned_kits()
	var sig: String = "%s|%d|%d|%d|%s|%d" % [_kit, kits.size(), int(_valid),
		int(round(rad_to_deg(_yaw))), str(_remove_target != null), int(_wall_mode)]
	if not force and sig == _ui_sig:
		return
	_ui_sig = sig
	_ensure_ui()
	if _strip == null:
		return
	var parts := PackedStringArray()
	for i in range(kits.size()):
		var label: String = Structures.display_name(kits[i])
		if kits[i] == _kit:
			parts.append("▸ %s ◂" % label.to_upper())
		elif i < 9:
			parts.append("%d %s" % [i + 1, label])
		else:
			parts.append(label)
	var status: String
	if _kit == "":
		parts.append("pack empty — nothing left to build")
		status = "aim at something you built"
	elif _wall_mode:
		status = "wall-mounted" if _valid else "no wall in reach"
	else:
		status = "%d°" % int(round(rad_to_deg(_yaw)))
		status += ("   ready" if _valid else "   no footing there")
	if _remove_target != null:
		status += "   ·   [X] dismantle %s" % Structures.display_name(
			str(_remove_target.get_meta("kit", "structure")))
	_strip.text = "   ".join(parts) + "\n" + status
