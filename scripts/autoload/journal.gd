extends Node
## The survivor's journal: every creature sighted, item handled, log read, and place
## understood gets an entry. Entries carry what a thing IS, what it DOES, and a hint
## at what it might become (crafting). UI lives in HUD; this owns the data.

signal entry_added(id: String, title: String)

var data: Dictionary = {}          ## journal.json: id -> {cat, title, body, hint}
var discovered: Dictionary = {}    ## id -> true, in discovery order (insertion-ordered)
var read_logs: Array[String] = []  ## readable ids, re-readable from the journal
var unseen_count: int = 0          ## badge counter, cleared when the journal opens

## ------------------------------------------------------------------ the catch log
## THE ANGLER'S RECORD. A species entry used to be a fixed paragraph out of journal.json
## that appeared, identical, whoever caught it and however: the journal knew you had met a
## Barrel Grouper and nothing else about the encounter. This is the concrete half — where
## it was taken, how deep, how heavy, in what weather, on what bait — and it goes into the
## SAME entry, in the SAME {cat, title, body, hint} schema the file and hud.gd already use.
## No parallel format and no second list: record_catch() rewrites data[species_id] from the
## authored flavour plus this record, then discovers it exactly like any other entry.
##
## species_id -> {
##   name, flavour,            plain-words name and the species' own flavour line
##   n,                        how many of this species have been landed
##   first: {day, phase, weather, depth, band, kg, bait},
##   best:  {day, phase, depth, kg, bait},   the largest specimen so far
## }
## Every value is a String, float, int or bool, so the whole thing round-trips through JSON.
var catches: Dictionary = {}
## Authored bodies/hints as journal.json wrote them, cached the first time a species entry
## is rewritten. Rebuilding the entry from the ORIGINAL text every time is what stops a
## second catch appending a second copy of the record to the first one's body.
var _authored: Dictionary = {}

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
	_sync_slot()

func discover(id: String) -> void:
	if discovered.has(id) or not data.has(id):
		return
	discovered[id] = true
	unseen_count += 1
	_persist()
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
	_persist()

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

# ==================================================================== the catch log
#
# Called from the rail the moment a fish is actually landed (fishing_rod._land). The FIRST
# of a species writes the entry; every one after only updates the record if it beat it.

## `info` is what the rod already knows at the moment of the landing, all of it optional:
##   name     plain-words species name (data/fish.json)
##   flavour  the species' own note line, used as the entry body when journal.json has
##            no authored paragraph for this species (most of the deep pool has none)
##   kg       landed weight, 0.0 for a species with no size range
##   depth_m  metres down the bait was taken at; < 0 for the surface rod
##   band     plain-words water the bait was in (FishTable.depth_read)
##   phase    dawn | day | dusk | night
##   weather  short conditions read (storm / worklight / calm)
##   bait     plain-words bait name, "" for the unbaited surface rod
func record_catch(species_id: String, info: Dictionary) -> void:
	if species_id == "":
		return
	var day: int = GameClock.day_count + 1
	var kg: float = float(info.get("kg", 0.0))
	var rec: Dictionary = catches.get(species_id, {})
	var fresh: bool = rec.is_empty()
	if fresh:
		rec = {
			"name": String(info.get("name", species_id)),
			"flavour": String(info.get("flavour", "")),
			"n": 0,
			"first": {
				"day": day, "phase": String(info.get("phase", "day")),
				"weather": String(info.get("weather", "")),
				"depth": float(info.get("depth_m", -1.0)),
				"band": String(info.get("band", "")),
				"kg": kg, "bait": String(info.get("bait", "")),
			},
			"best": {"day": day, "phase": String(info.get("phase", "day")),
				"depth": float(info.get("depth_m", -1.0)), "kg": kg,
				"bait": String(info.get("bait", ""))},
		}
	rec["n"] = int(rec.get("n", 0)) + 1
	if kg > float((rec["best"] as Dictionary).get("kg", 0.0)):
		rec["best"] = {"day": day, "phase": String(info.get("phase", "day")),
			"depth": float(info.get("depth_m", -1.0)), "kg": kg,
			"bait": String(info.get("bait", ""))}
	catches[species_id] = rec
	_write_catch_entry(species_id)
	# discover() is a no-op after the first time, so a second grouper updates the record in
	# place and never toasts a "new entry" the player has already read.
	discover(species_id)
	_persist()

## Rebuild data[species_id] from the AUTHORED text plus the record. Runs on every catch and
## on every load, and is idempotent because it always starts from _authored, never from
## whatever the entry was left as last time.
func _write_catch_entry(species_id: String) -> void:
	var rec: Dictionary = catches.get(species_id, {})
	if rec.is_empty():
		return
	if not _authored.has(species_id):
		var src: Dictionary = data.get(species_id, {})
		_authored[species_id] = {
			"title": String(src.get("title", rec.get("name", species_id))),
			"body": String(src.get("body", rec.get("flavour", ""))),
			"hint": String(src.get("hint", "")),
			"cat": String(src.get("cat", "creature")),
		}
	var base: Dictionary = _authored[species_id]
	var first: Dictionary = rec["first"]
	var best: Dictionary = rec["best"]
	var body: String = String(base["body"])
	if body != "":
		body += "\n"
	body += "Landed %s — day %d, %s%s%s%s." % [
		"first" if int(rec.get("n", 1)) <= 1 else "first of %d" % int(rec["n"]),
		int(first["day"]), String(first["phase"]),
		_depth_phrase(float(first["depth"]), String(first["band"])),
		("" if String(first["bait"]) == "" else ", on %s" % String(first["bait"])),
		("" if String(first["weather"]) == "" else ". %s" % String(first["weather"])),
	]
	if float(first["kg"]) > 0.0:
		body += " %.1f kg on the first one." % float(first["kg"])
	var hint: String = String(base["hint"])
	if float(best["kg"]) > 0.0:
		var rest: String = "Best: %.1f kg — day %d, %s%s" % [float(best["kg"]),
			int(best["day"]), String(best["phase"]), _depth_phrase(float(best["depth"]), "")]
		hint = rest if hint == "" else "%s · %s" % [hint, rest]
	data[species_id] = {"cat": String(base["cat"]), "title": String(base["title"]),
		"body": body, "hint": hint}

## ", 34 m down in the black" / ", 34 m down" / "" — the surface rod passes a negative
## depth because it fishes the skin of the water and has no number worth printing.
func _depth_phrase(depth_m: float, band: String) -> String:
	if depth_m < 0.0:
		return ""
	if band == "":
		return ", %d m down" % int(depth_m)
	return ", %d m down in %s" % [int(depth_m), band]

# ==================================================================== persistence
#
# save_manager.gd does not carry the journal (it saves the player, the world and the
# snails, and nothing here), and it is owned elsewhere — so the journal keeps its own
# small file BESIDE the slot it belongs to, named off SaveManager.slot_file_prefix so the
# test suite's throwaway stem carries over and the real saves are never touched.
#
# THE SLOT FILE IS THE AUTHORITY on whether this sidecar is still true. begin_new_game()
# erases the slot, so "the slot file has gone" is exactly the signal that this journal
# belongs to a run that no longer exists — it is dropped and the sidecar deleted. A load
# MERGES rather than replaces (union of discoveries, best-of on the catch records), so a
# resync can never throw away something discovered since the last write.

const SYNC_SEC: float = 1.5   ## how often the active slot is re-checked (a file stat)

var _synced_slot: int = -1
var _synced_exists: bool = false
var _sync_t: float = 0.0

func _process(delta: float) -> void:
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = SYNC_SEC
		_sync_slot()

func _sidecar_path() -> String:
	return "user://%sjournal_%d.json" % [SaveManager.slot_file_prefix, SaveManager.active_slot]

## Follow the active slot: adopt its journal when one appears, drop ours when the slot is
## wiped out from under us.
func _sync_slot() -> void:
	var slot: int = SaveManager.active_slot
	var exists: bool = FileAccess.file_exists(SaveManager.slot_path(slot))
	if slot == _synced_slot and exists == _synced_exists:
		return
	var first: bool = _synced_slot < 0
	var switched: bool = not first and slot != _synced_slot
	# The slot's save file disappearing under us is begin_new_game(): this run is over.
	# (Its APPEARING is only the first autosave of the run we are already in — that one
	# must NOT clear anything, it just re-reads a sidecar we wrote ourselves.)
	var wiped: bool = not first and not switched and _synced_exists and not exists
	_synced_slot = slot
	_synced_exists = exists
	if switched or wiped:
		_clear_run()
	if exists:
		_load_sidecar()
	else:
		_delete_sidecar()   # nothing to inherit in this slot; drop any stale sidecar

func _clear_run() -> void:
	for id in catches:
		if _authored.has(id):
			data[id] = (_authored[id] as Dictionary).duplicate()
	catches.clear()
	discovered.clear()
	read_logs.clear()
	unseen_count = 0

func _delete_sidecar() -> void:
	var path: String = _sidecar_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _persist() -> void:
	if _synced_slot < 0:
		_synced_slot = SaveManager.active_slot
	var f: FileAccess = FileAccess.open(_sidecar_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(payload()))
	f.close()

## The journal as plain JSON-safe data. Shaped like PlayerState.comfort_payload() /
## FAUNA.snail_payload() so save_manager can adopt it as a one-liner whenever it wants to.
func payload() -> Dictionary:
	return {"journal_discovered": discovered.keys(), "journal_logs": read_logs,
		"journal_catches": catches}

## Merge a payload in. Never destructive: discoveries union, a catch record keeps whichever
## copy landed the heavier fish.
func restore(d: Dictionary) -> void:
	for id in d.get("journal_discovered", []):
		var key: String = String(id)
		if data.has(key):
			discovered[key] = true
	for rid in d.get("journal_logs", []):
		var log_id: String = String(rid)
		if not read_logs.has(log_id):
			read_logs.append(log_id)
	var saved: Dictionary = d.get("journal_catches", {}) if typeof(d.get("journal_catches")) == TYPE_DICTIONARY else {}
	for id in saved:
		var rec: Variant = saved[id]
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var mine: Dictionary = catches.get(id, {})
		if mine.is_empty() or float((mine["best"] as Dictionary).get("kg", 0.0)) \
				< float(((rec as Dictionary).get("best", {}) as Dictionary).get("kg", 0.0)):
			catches[id] = rec
		_write_catch_entry(String(id))
		discovered[String(id)] = true
	_check_note_sets()

func _load_sidecar() -> void:
	var path: String = _sidecar_path()
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		restore(parsed)
