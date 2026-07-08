extends Node
## JSON save/load of world + player state. Single autosave slot; autosaves at dawn/dusk.

const SAVE_PATH: String = "user://saltline_autosave.json"

func _ready() -> void:
	GameClock.dawn.connect(save_game)
	GameClock.dusk.connect(save_game)

func save_game() -> void:
	var data: Dictionary = {
		"hunger": PlayerState.hunger,
		"warmth": PlayerState.warmth,
		"hotbar": PlayerState.hotbar,
		"inventory": PlayerState.inventory,
		"phase": GameClock.current_phase,
		"day_count": GameClock.day_count,
		"powered": PowerGrid.powered_ids(),
	}
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
	PlayerState.warmth = data.get("warmth", 1.0)
	PlayerState.hotbar = data.get("hotbar", [null, null, null, null])
	PlayerState.inventory = data.get("inventory", [])
	GameClock.day_count = int(data.get("day_count", 0))
	for id in data.get("powered", []):
		PowerGrid.power_circuit(id)
	GameClock.force_phase(int(data.get("phase", GameClock.Phase.DAWN)) as GameClock.Phase)
	return true
