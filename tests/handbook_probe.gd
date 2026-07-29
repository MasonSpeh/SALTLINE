extends Node
## THE CARRYABLE-HANDBOOK PROBE.
##
## The Fisherman's Handbook is the only readable on this rig that is also an inventory
## item, and that means it has a LIFECYCLE no other readable has: read it where it lies,
## pocket it, read it out of the pack, set it down somewhere else, read it there, and have
## all of that survive a save. Each of those is a separate seam and each one is asserted
## here, in that order, against the real scene.
##
## It also guards the thing most likely to rot: the book's text is supposed to document the
## conditions in data/fish.json, so every species in the table has to be named in it. A
## species added later without a handbook line fails this probe rather than shipping as a
## fish the book has never heard of.
##
## Run: godot --headless --path . res://tests/HandbookProbe.tscn

const HANDBOOK := preload("res://scripts/components/handbook.gd")
const FISH := preload("res://scripts/world/fish_table.gd")

var failures: int = 0

func _ready() -> void:
	await _run()
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  " + label)
	else:
		failures += 1
		print("FAIL  " + label)

## Every handbook currently in the world. Walks from the TREE ROOT, not from the game
## scene: SaveManager parents a dropped item to get_tree().current_scene, which in a probe
## is the probe node with the game hanging underneath it — so a search rooted at `main`
## sees the wet-deck copy and misses every copy the player set down.
func _find_handbooks(_root: Node) -> Array:
	var out: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Readable and String(n.get("readable_id")) == HANDBOOK.READABLE_ID:
			out.append(n)
	return out

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in range(4):
		await get_tree().process_frame
	var player: Node3D = main.player
	var hud: Node = get_tree().get_first_node_in_group("hud")

	# ---------------------------------------------------------------- the text
	var entry: Dictionary = Readable.text_for(HANDBOOK.READABLE_ID)
	var body: String = String(entry.get("body", ""))
	_check(String(entry.get("title", "")).contains("HANDBOOK"),
		"the readable is titled as a handbook (got: %s)" % entry.get("title", ""))
	var missing: Array[String] = []
	for fid in FISH.all():
		var nm: String = String((FISH.all()[fid] as Dictionary).get("name", ""))
		if nm != "" and not body.to_upper().contains(nm.to_upper()):
			missing.append(nm)
	_check(missing.is_empty(),
		"every species in fish.json is documented in the handbook%s" % \
			("" if missing.is_empty() else " — MISSING: %s" % ", ".join(missing)))
	# The conditions the roll actually uses have to be teachable from the book alone.
	var taught: Array[String] = ["dawn", "night", "storm", "rain", "fog", "worklight",
		"open water", "shadow", "bait", "48 m"]
	var untaught: Array[String] = []
	for word in taught:
		if not body.to_lower().contains(word.to_lower()):
			untaught.append(word)
	_check(untaught.is_empty(),
		"the handbook explains every condition the table rolls on%s" % \
			("" if untaught.is_empty() else " — not mentioned: %s" % ", ".join(untaught)))

	# ---------------------------------------------------------------- on the wet deck
	var found: Array = _find_handbooks(main)
	_check(found.size() == 1, "exactly one handbook stands in the world at start (found %d)" % found.size())
	if found.is_empty():
		return
	var book: Node3D = found[0]
	_check(book.is_in_group(HANDBOOK.ORIGIN_GROUP), "the wet-deck copy is tagged as the original")
	_check(book.global_position.distance_to(Vector3(11.7, 2.62, -16.6)) < 0.01,
		"it stands in the wet-deck store room where the rods are")
	var verbs: Array[String] = (book as Interactable).available_verbs()
	_check(verbs.size() == 1 and verbs[0] == "READ",
		"its verb is READ — you read it where it lies (got %s)" % str(verbs))
	_check((book as Interactable).get_prompt().contains("[F]"),
		"the prompt names the key that pockets it (got: %s)" % (book as Interactable).get_prompt())
	_check(book.get_child_count() >= 2, "it built a real book visual plus its collider")

	# ---------------------------------------------------------------- read it, pocket it
	while PlayerState.remove_item(HANDBOOK.ITEM_ID):
		pass
	(book as Interactable).interact("READ", player)
	_check(bool(hud.get("reading_open")), "READ opens the reading panel")
	_check(String(hud.reading_body.text).length() > 2000, "the panel is showing the whole handbook")
	_check(HANDBOOK.f_pressed(player), "[F] while it is open is claimed by the handbook")
	_check(PlayerState.count_item(HANDBOOK.ITEM_ID) == 1, "it is now in the pack")
	_check(not bool(hud.get("reading_open")), "pocketing it shuts the book")
	await get_tree().process_frame
	_check(_find_handbooks(main).is_empty(), "and it is gone from the wet deck")

	# ---------------------------------------------------------------- read it from the pack
	var slot: int = PlayerState.hotbar.find(HANDBOOK.ITEM_ID)
	if slot == -1:
		slot = 0
		PlayerState.hotbar[slot] = HANDBOOK.ITEM_ID
	PlayerState.selected_hotbar = slot
	_check(HANDBOOK.f_pressed(player), "[F] with it in hand is claimed by the handbook")
	_check(bool(hud.get("reading_open")), "…and opens it wherever you are standing")
	hud.close_reading()
	# It must not eat [F] when something else is in hand, or the flashlight breaks.
	PlayerState.hotbar[slot] = "flashlight"
	_check(not HANDBOOK.f_pressed(player), "[F] falls through to the torch when the book isn't in hand")
	PlayerState.hotbar[slot] = HANDBOOK.ITEM_ID

	# ---------------------------------------------------------------- set it down elsewhere
	var spot := Vector3(-6.0, 18.05, 12.0)   # up on the topside plate, nowhere near the wet deck
	var dropped: Node3D = SaveManager.drop_into_world(HANDBOOK.ITEM_ID, spot)
	PlayerState.remove_item(HANDBOOK.ITEM_ID)
	await get_tree().process_frame
	_check(dropped is Readable, "a handbook set down in the world is still a READABLE, not a bare Takeable")
	_check(dropped.is_in_group("dropped_item"), "…and is tagged so it saves like any dropped item")
	_check(String(dropped.get("item_id")) == HANDBOOK.ITEM_ID,
		"…and carries the item id the save payload reads")
	var dverbs: Array[String] = (dropped as Interactable).available_verbs()
	_check(dverbs.size() == 1 and dverbs[0] == "READ",
		"…and can be read from where it now sits (got %s)" % str(dverbs))
	(dropped as Interactable).interact("READ", player)
	_check(bool(hud.get("reading_open")), "reading it in its new home works")
	hud.close_reading()
	HANDBOOK._reading = null

	# ---------------------------------------------------------------- through a save
	var payload: Array = SaveManager._dropped_payload()
	var saved: Dictionary = {}
	for row in payload:
		if String((row as Dictionary).get("id", "")) == HANDBOOK.ITEM_ID:
			saved = row
	_check(not saved.is_empty(), "the save payload carries the handbook where it was left")
	# Now do what a load does: the world is rebuilt (so the wet-deck original is back),
	# then the save is applied on top.
	var reborn: Node3D = HANDBOOK.place_origin(main, Vector3(11.7, 2.62, -16.6))
	await get_tree().process_frame
	_check(_find_handbooks(main).size() == 2, "a reload rebuilds the wet-deck copy before the save is read")
	var n: int = SaveManager.restore_dropped(payload)
	_check(n >= 1, "restore_dropped puts it back")
	var freed: int = HANDBOOK.sync_world(get_tree())
	await get_tree().process_frame
	_check(freed == 1, "sync_world deletes the duplicate original")
	var after: Array = _find_handbooks(main)
	_check(after.size() == 1, "exactly one handbook exists after the load (found %d)" % after.size())
	if after.size() == 1:
		_check(after[0].global_position.distance_to(spot) < 0.5,
			"…and it is where the player left it, not back on the wet deck")
	if is_instance_valid(reborn):
		reborn.queue_free()

	# ---------------------------------------------------------------- and in the pack
	PlayerState.add_item(HANDBOOK.ITEM_ID)
	var reborn2: Node3D = HANDBOOK.place_origin(main, Vector3(11.7, 2.62, -16.6))
	await get_tree().process_frame
	_check(HANDBOOK.sync_world(get_tree()) == 1,
		"a handbook carried in the pack also suppresses the wet-deck respawn")
	if is_instance_valid(reborn2):
		reborn2.queue_free()

	# ---------------------------------------------------------------- the inventory visual
	var model: Node3D = PropLib.item_model(HANDBOOK.ITEM_ID)
	_check(model != null, "PropLib resolves real geometry for the handbook item")
	if model != null:
		var meshes: int = model.find_children("*", "MeshInstance3D", true, false).size()
		_check(meshes > 0, "…and it has actual mesh surfaces (%d)" % meshes)
		model.queue_free()
	_check(PlayerState.items.has(HANDBOOK.ITEM_ID), "the handbook is a real entry in data/items.json")
