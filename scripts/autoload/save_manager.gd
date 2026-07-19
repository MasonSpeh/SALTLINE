extends Node
## JSON save/load of world + player state. Single autosave slot; autosaves at dawn/dusk.

const SAVE_PATH: String = "user://saltline_autosave.json"

func _ready() -> void:
	GameClock.dawn.connect(save_game)
	GameClock.dusk.connect(save_game)

func save_game() -> void:
	var data: Dictionary = {
		"hunger": PlayerState.hunger,
		"thirst": PlayerState.thirst,
		"warmth": PlayerState.warmth,
		"life": PlayerState.life,
		"hotbar": PlayerState.hotbar,
		"inventory": PlayerState.inventory,
		"phase": GameClock.current_phase,
		"day_count": GameClock.day_count,
		"powered": PowerGrid.powered_ids(),
		"structures": _structures_payload(),
	}
	# rest / comfort / camp_found live with the stats that feed them.
	data.merge(PlayerState.comfort_payload())
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	PlayerState.hunger = data.get("hunger", 1.0)
	PlayerState.thirst = data.get("thirst", 1.0)
	PlayerState.warmth = data.get("warmth", 1.0)
	PlayerState.life = data.get("life", 1.0)
	PlayerState.hotbar = data.get("hotbar", [null, null, null, null])
	PlayerState.inventory = data.get("inventory", [])
	PlayerState.apply_comfort_payload(data)
	GameClock.day_count = int(data.get("day_count", 0))
	for id in data.get("powered", []):
		PowerGrid.power_circuit(id)
	GameClock.force_phase(int(data.get("phase", GameClock.Phase.DAWN)) as GameClock.Phase)
	restore_structures(data.get("structures", []))
	return true

# --------------------------------------------------------------- base building
# A camp that evaporates when you go to bed is not a camp. Every placed structure
# carries meta "kit" and Structures.build(kit) reconstructs it whole, so kit id
# plus the world transform is the entire save: no per-kit serialisation to drift.

func _structures_payload() -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("built_structures"):
		if not (s is Node3D) or not is_instance_valid(s):
			continue
		var kit: String = String((s as Node3D).get_meta("kit", ""))
		if kit == "":
			continue
		var t: Transform3D = (s as Node3D).global_transform
		out.append({
			"kit": kit,
			# Basis is stored column-major as nine floats — JSON has no Transform3D,
			# and euler angles lose the wall-mount orientations build mode produces.
			"pos": [t.origin.x, t.origin.y, t.origin.z],
			"basis": [
				t.basis.x.x, t.basis.x.y, t.basis.x.z,
				t.basis.y.x, t.basis.y.y, t.basis.y.z,
				t.basis.z.x, t.basis.z.y, t.basis.z.z,
			],
		})
	return out

## Rebuild a saved camp. Clears whatever is standing first so a mid-session load
## cannot double every structure.
func restore_structures(list: Variant) -> int:
	if typeof(list) != TYPE_ARRAY:
		return 0
	var scene: Node = get_tree().current_scene
	if scene == null:
		return 0
	for old in get_tree().get_nodes_in_group("built_structures"):
		if is_instance_valid(old):
			old.queue_free()
	var built: int = 0
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kit: String = String(entry.get("kit", ""))
		if kit == "" or not Structures.KIT_ORDER.has(kit):
			continue
		var node: Node3D = Structures.build(kit, false)
		if node == null:
			continue
		scene.add_child(node)
		node.global_transform = Transform3D(_basis_from(entry.get("basis", [])),
			_vec_from(entry.get("pos", [])))
		built += 1
	return built

func _vec_from(a: Variant) -> Vector3:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 3:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _basis_from(a: Variant) -> Basis:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 9:
		return Basis()
	return Basis(
		Vector3(float(a[0]), float(a[1]), float(a[2])),
		Vector3(float(a[3]), float(a[4]), float(a[5])),
		Vector3(float(a[6]), float(a[7]), float(a[8]))).orthonormalized()
