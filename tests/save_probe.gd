extends Node3D
## Does the save system actually survive the path a PLAYER takes?
##
## The existing suite's save checks all call GameClock.force_phase(DAY) first, which
## quietly dodges the only phases a save is ever written in: SaveManager autosaves on
## dawn and dusk ONLY, so every real save file carries phase DAWN or DUSK. This probe
## reproduces that path exactly — save at dusk, load at dusk — and then re-reads the
## file off disk to see what is still in it.

const SLOT_PREFIX: String = "save_probe_slot_"

var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	SaveManager.slot_file_prefix = SLOT_PREFIX
	SaveManager.active_slot = 1
	SaveManager.erase_slot(1)
	await get_tree().process_frame
	await _run()
	SaveManager.erase_slot(1)
	print("\n[save_probe] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % msg)
	else:
		_fail += 1
		print("  FAIL  %s" % msg)

## Read the slot file straight off disk — the only honest question is what a NEXT
## boot would find there, not what is in memory.
func _on_disk() -> Dictionary:
	var p: String = SaveManager.slot_path(SaveManager.active_slot)
	if not FileAccess.file_exists(p):
		return {}
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _run() -> void:
	# A camp: two placed structures, exactly as build mode leaves them.
	var a: Node3D = Structures.build("brazier_kit", false)
	add_child(a)
	a.global_position = Vector3(11.0, 19.0, -4.0)
	var b: Node3D = Structures.build("chair_kit", false)
	add_child(b)
	b.global_position = Vector3(12.5, 19.0, -4.0)
	# A crate with something in it.
	var crate := LootContainer.new()
	crate.display_name = "Probe Crate"
	add_child(crate)
	crate.global_position = Vector3(9.0, 19.0, -4.0)
	crate.items = ["rope", "scrap_metal"] as Array[String]
	PlayerState.load_inventory(["hammer", null, null, null], [1], ["rope"], [3])
	await get_tree().process_frame

	# ---- the real autosave path: dusk fires save_game() -----------------------
	GameClock.force_phase(GameClock.Phase.DUSK)
	await get_tree().process_frame
	var written: Dictionary = _on_disk()
	_ok(not written.is_empty(), "dusk autosave writes a file")
	_ok((written.get("structures", []) as Array).size() == 2,
		"the file holds both structures (got %d)" % (written.get("structures", []) as Array).size())
	_ok((written.get("containers", {}) as Dictionary).size() >= 1,
		"the file holds the crate contents")
	_ok(int(written.get("phase", -1)) == GameClock.Phase.DUSK,
		"the saved phase is DUSK — which is what every real save carries")

	# ---- now CONTINUE: load it back ------------------------------------------
	for s in get_tree().get_nodes_in_group("built_structures"):
		s.free()
	crate.items = [] as Array[String]
	_ok(SaveManager.load_game(), "the slot loads")
	await get_tree().process_frame
	_ok(get_tree().get_nodes_in_group("built_structures").size() == 2,
		"both structures are back in the session (got %d)"
			% get_tree().get_nodes_in_group("built_structures").size())
	_ok(crate.items.has("rope"), "the crate contents are back in the session")

	# ---- and what does the NEXT boot find? -----------------------------------
	# This is the question the suite never asked.
	var after: Dictionary = _on_disk()
	var after_structs: int = (after.get("structures", []) as Array).size()
	_ok(after_structs == 2,
		"the file STILL holds the camp after a load (got %d)" % after_structs)
	var after_conts: Dictionary = after.get("containers", {})
	var kept: bool = false
	for k in after_conts:
		if typeof(after_conts[k]) == TYPE_ARRAY and (after_conts[k] as Array).has("rope"):
			kept = true
	_ok(kept, "the file STILL holds the crate contents after a load")
	_ok(int(after.get("phase", -1)) == GameClock.Phase.DUSK,
		"and the file was not re-stamped by a save that should not have run")

	# ---- the pack ------------------------------------------------------------
	PlayerState.load_inventory([null, null, null, null], [], [], [])
	_ok(SaveManager.load_game(), "the slot loads again")
	_ok(PlayerState.hotbar[0] == "hammer", "the hotbar comes back")
	_ok(PlayerState.inventory.has("rope"), "the pack comes back")
	var rope_i: int = PlayerState.inventory.find("rope")
	_ok(rope_i >= 0 and int(PlayerState.inventory_counts[rope_i]) == 3,
		"stack counts come back (got %d)"
			% (int(PlayerState.inventory_counts[rope_i]) if rope_i >= 0 else -1))

	# ---- manual save, mid-DAY, which is the whole point of the pause button ---
	# Nothing had ever written a slot outside dawn/dusk. Prove a save asked for at an
	# arbitrary moment lands, and lands complete.
	GameClock.force_phase(GameClock.Phase.DAY)
	var mover: Node3D = Structures.build("chair_kit", false)
	add_child(mover)
	mover.global_position = Vector3(14.0, 19.0, -4.0)
	await get_tree().process_frame
	_ok(SaveManager.save_game(), "a manual save mid-DAY reports success")
	var manual: Dictionary = _on_disk()
	_ok((manual.get("structures", []) as Array).size() == 3,
		"the manual save holds all three structures (got %d)"
			% (manual.get("structures", []) as Array).size())
	_ok(int(manual.get("phase", -1)) == GameClock.Phase.DAY, "and it records DAY")

	# ---- the player's last location ------------------------------------------
	var stand_in := CharacterBody3D.new()
	stand_in.add_to_group("player")
	add_child(stand_in)
	stand_in.global_position = Vector3(7.5, 19.0, -12.25)
	stand_in.rotation.y = 1.1
	_ok(SaveManager.save_game(), "a save with a player in the tree succeeds")
	stand_in.global_position = Vector3.ZERO
	stand_in.rotation.y = 0.0
	_ok(SaveManager.load_game(), "the slot loads with a position in it")
	_ok(stand_in.global_position.distance_to(Vector3(7.5, 19.0, -12.25)) < 0.05,
		"the player is put back where they saved (at %v)" % stand_in.global_position)
	_ok(absf(stand_in.rotation.y - 1.1) < 0.02, "and facing the way they were")
	stand_in.queue_free()

	# ---- a corrupt save must not take the game down --------------------------
	var bad: FileAccess = FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	bad.store_string("{ this is not json")
	bad.close()
	_ok(not SaveManager.load_game(), "a corrupt save reports failure instead of crashing")
	_ok(not bool(SaveManager.slot_info(1).get("exists", true)),
		"and the menu reads that slot as empty rather than offering a broken Continue")
