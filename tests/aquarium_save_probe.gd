extends Node
## THE AQUARIUM STOCK ROUND-TRIP, asserted against the FILE RE-READ OFF DISK — never
## against live memory (the s23 lesson: a load that looked perfect in memory was
## overwriting its own save mid-read). Seeds the tank through the hatch's own restore
## path, saves, proves the slot file carries the fish, empties the live tank, loads,
## and proves the fish came back through SaveManager.
##
##   godot --headless --path . res://tests/AquariumSaveProbe.tscn

var failures: int = 0

func _ok(cond: bool, msg: String) -> void:
	print("%s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		failures += 1

func _ready() -> void:
	SaveManager.begin_new_game(3)
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(9.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)   # DAY is the one phase not wired to autosave
	var h: Node = get_tree().get_first_node_in_group("aquarium_hatch")
	if h == null:
		print("FAIL  found the aquarium hatch")
		print("FAILURES: 1")
		get_tree().quit(1)
		return
	var seed_stock: Array = [{"id": "fish_herring", "kg": 0.35}, {"id": "fish_herring", "kg": 0.6}]
	h.call("restore_stock", seed_stock)
	var live: Array = h.call("stock_payload")
	_ok(live.size() == 2, "the seed itself took (anti-vacuity: %d in tank)" % live.size())
	_ok(SaveManager.save_game(), "save_game wrote")
	# THE FILE, not the memory.
	var raw: String = FileAccess.get_file_as_string("user://saltline_slot_3.json")
	var d: Variant = JSON.parse_string(raw)
	var on_disk: Variant = (d as Dictionary).get("aquarium", null) if typeof(d) == TYPE_DICTIONARY else null
	_ok(typeof(on_disk) == TYPE_ARRAY and (on_disk as Array).size() == 2,
		"slot file carries the stock (%s)" % str(on_disk))
	# Empty the live tank, then load: everything back must have come through the file.
	h.call("restore_stock", [])
	_ok((h.call("stock_payload") as Array).is_empty(), "tank emptied before the load")
	_ok(SaveManager.load_game(), "load_game read")
	await get_tree().physics_frame
	var back: Array = h.call("stock_payload")
	_ok(back.size() == 2, "stock restored through the save (%d back)" % back.size())
	var kgs: Array = []
	for e in back:
		kgs.append(float(e.get("kg", 0.0)))
	kgs.sort()
	# approx, not ==: two floats that PRINT as 0.35 can still differ in the last bit,
	# and Array == compares exactly (the first run failed on exactly that).
	_ok(kgs.size() == 2 and is_equal_approx(kgs[0], 0.35) and is_equal_approx(kgs[1], 0.6),
		"per-fish weight survived the trip (%s)" % str(kgs))
	# And a fish with no size_kg range still OCCUPIES length — the limits were vacuous
	# for 36 species whose instance length reads 0.0 (herring is one of them).
	var lens: Array = []
	for e2 in back:
		lens.append(float(e2.get("len", 0.0)))
	_ok(lens.min() > 0.05, "no zero-length fish in the ledger (%s)" % str(lens))
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
