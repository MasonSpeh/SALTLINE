class_name Readable extends Interactable
## READ verb: shows full-screen text from data/readables.json (stand-in for in-world paper).
## Readables carry ALL story for the slice (GDD 5.3).

static var _texts: Dictionary = {}

@export var readable_id: String = ""

func _init() -> void:
	verbs = ["READ"]

static func load_texts() -> void:
	if not _texts.is_empty():
		return
	var f: FileAccess = FileAccess.open("res://data/readables.json", FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_texts = parsed

## Build the in-world object you actually read: a book, a journal, a stack of
## paper, or a poster taped to a bulkhead (see ReadableVisual) instead of the old
## flat white card. `size` is the placement box the world scripts already author —
## it still defines the interaction collider exactly as build_box_visual did, so
## aiming at a readable is unchanged; it only additionally tells the visual which
## way it is being read from (its thinnest axis is the viewing normal).
func build_visual(size: Vector3 = Vector3(0.35, 0.45, 0.06)) -> void:
	load_texts()
	var entry: Dictionary = _texts.get(readable_id, {})
	var declared: String = str(entry.get("type", entry.get("form", "")))
	add_child(preload("res://scripts/world/readable_visual.gd").build(readable_id, size, declared))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	load_texts()
	var entry: Dictionary = _texts.get(readable_id, {"title": display_name, "body": "[PLACEHOLDER-TEXT]"})
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_reading(entry.get("title", display_name), entry.get("body", ""))
	Journal.discover_log(readable_id, entry.get("title", display_name))

static func text_for(id: String) -> Dictionary:
	load_texts()
	return _texts.get(id, {})
