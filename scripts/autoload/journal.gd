extends Node
## The survivor's journal: every creature sighted, item handled, log read, and place
## understood gets an entry. Entries carry what a thing IS, what it DOES, and a hint
## at what it might become (crafting). UI lives in HUD; this owns the data.

signal entry_added(id: String, title: String)

var data: Dictionary = {}          ## journal.json: id -> {cat, title, body, hint}
var discovered: Dictionary = {}    ## id -> true, in discovery order (insertion-ordered)
var read_logs: Array[String] = []  ## readable ids, re-readable from the journal
var unseen_count: int = 0          ## badge counter, cleared when the journal opens

## Reading is progression: finishing a whole thread of scattered notes unlocks a
## synthesis Codex entry that says what the pieces MEAN. The 22 notes stop being
## trivia and become an understood story. Each key is a Codex id in journal.json;
## its value is the set of readable ids that must all be read.
const NOTE_SETS := {
	"codex_what_osk_chose": ["osk_watch_slate", "coffee_note", "shrine_note", "osk_last_note"],
	"codex_down_the_line": ["rationing_memo", "quiet_rig_note", "lookout_note", "breaker_log"],
	"codex_the_flash": ["toolpusher_log", "comms_log", "medbay_note"],
}

func _ready() -> void:
	var f: FileAccess = FileAccess.open("res://data/journal.json", FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	# Signal-driven discoveries that need no call site:
	PowerGrid.circuit_powered.connect(func(_id: String) -> void: discover("place_power"))
	# (crab discovery is driven directly by GiantCrab via Journal.discover_if_near — the old
	# EventBus.creature_contact signal was retired with the s11 crab remake.)
	EventBus.cold_open_finished.connect(func() -> void: discover("place_sphl"))

func discover(id: String) -> void:
	if discovered.has(id) or not data.has(id):
		return
	discovered[id] = true
	unseen_count += 1
	var title: String = data[id].get("title", id)
	entry_added.emit(id, title)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Journal — %s" % title)

func discover_log(readable_id: String, title: String) -> void:
	if read_logs.has(readable_id):
		return
	read_logs.append(readable_id)
	unseen_count += 1
	entry_added.emit("log_" + readable_id, title)
	_check_note_sets()

## When the last note of a thread is read, its synthesis Codex entry unlocks.
func _check_note_sets() -> void:
	for syn in NOTE_SETS:
		if discovered.has(syn):
			continue
		var complete: bool = true
		for need in NOTE_SETS[syn]:
			if not read_logs.has(need):
				complete = false
				break
		if complete:
			var hud: Node = get_tree().get_first_node_in_group("hud")
			if hud:
				hud.toast("The pieces line up.")
			discover(syn)
			# Reading the corporate thread also fixes the far platform on the map.
			if syn == "codex_down_the_line":
				discover("place_quiet_rig")

## Static-ish helper for creatures/places: discover when the player first gets close.
func discover_if_near(node: Node3D, id: String, radius: float) -> bool:
	if discovered.has(id):
		return true
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player and node.visible and player.global_position.distance_to(node.global_position) < radius:
		discover(id)
		return true
	return false

func mark_seen() -> void:
	unseen_count = 0

func entries_by_category(cat: String) -> Array:
	var out: Array = []
	for id in discovered:
		if data.get(id, {}).get("cat", "") == cat:
			out.append(id)
	return out

## Item lookup used by the inventory info line.
func item_info(item_id: String) -> Dictionary:
	return data.get("item_" + item_id, {})
