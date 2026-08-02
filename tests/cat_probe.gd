extends Node
## SHIP CAT PROBE — is there actually a cat, does it become a friend, and does it come along?
##
## Headless is correct: this is transforms and state, nothing is drawn.
##   godot --headless --path . res://tests/CatProbe.tscn

var failures: int = 0
var _completed: bool = false

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(6.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	await _run()
	if not _completed:
		print("FAIL  the probe ran to completion (it did NOT — see the SCRIPT ERROR above)")
		failures += 1
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _ok(c: bool, m: String) -> void:
	print("%s  %s" % ["PASS" if c else "FAIL", m])
	if not c:
		failures += 1

func _run() -> void:
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	_ok(cat != null, "a cat exists on the rig")
	if cat == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)

	# 1. IT IS IN THE BUNKHOUSE, AND IT IS ON THE FLOOR. The bunkhouse zone is
	# x[-28,-8] z[4,18] at deck y18 (RIG_ATLAS), and the spawn Y is probed rather than typed —
	# so assert it landed ON something, not at the authored constant.
	var p: Vector3 = cat.global_position
	_ok(p.x > -28.0 and p.x < -8.0 and p.z > 4.0 and p.z < 18.0,
		"it is in the bunkhouse (%.1f, %.1f)" % [p.x, p.z])
	_ok(absf(p.y - 18.0) < 1.2, "it is seated on the bunkhouse deck (y %.2f)" % p.y)

	# 2. IT IS NOT YOUR FRIEND YET, and it offers to be.
	_ok(not bool(cat.get("friend")), "it starts as a stranger")
	var verbs: Array = cat.call("available_verbs")
	_ok(verbs.size() > 0 and String(verbs[0]) == "SAY HELLO",
		"the crosshair offers SAY HELLO (%s)" % str(verbs))
	# ...and the RAY reads the handle, not the cat, so assert the handle carries it too.
	var handle_verbs: Array = []
	for c in cat.get_children():
		if c is Interactable:
			handle_verbs = (c as Interactable).available_verbs()
	_ok(handle_verbs.size() > 0 and String(handle_verbs[0]) == "SAY HELLO",
		"the interaction handle offers it too — what the ray actually reads (%s)" % str(handle_verbs))

	# 3. SAYING HELLO IS THE WHOLE BEFRIENDING. One interaction, permanent.
	var touch: Node = null
	for c in cat.get_children():
		if c is Interactable:
			touch = c
			break
	_ok(touch != null, "it carries an interaction handle like every other creature")
	if touch == null:
		return
	(touch as Interactable).interact("SAY HELLO", player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(bool(cat.get("friend")), "saying hello makes it a friend")
	_ok(Journal.discovered.has("creature_ship_cat"), "the journal records the cat")
	_ok(String((cat.call("available_verbs") as Array)[0]) == "PET", "and now it can be petted")

	# 4. IT FOLLOWS. Put the player across the room and let it walk.
	var start: Vector3 = cat.global_position
	player.global_position = Vector3(-12.0, 18.1, 10.0)
	for i in range(200):
		await get_tree().physics_frame
	var moved: float = cat.global_position.distance_to(start)
	var gap: float = cat.global_position.distance_to(player.global_position)
	_ok(moved > 1.0, "it followed (moved %.1f m)" % moved)
	_ok(gap < 8.0, "and it closed on the player (%.1f m away)" % gap)
	# It must not have walked off the deck chasing him.
	_ok(absf(cat.global_position.y - 18.0) < 1.2,
		"it stayed on the deck while following (y %.2f)" % cat.global_position.y)

	# 5. IT SETTLES WHEN YOU DO. Stand still and it should stop walking and sit.
	var before_still: Vector3 = cat.global_position
	for i in range(420):     # past SETTLE_SEC at 60 Hz
		await get_tree().physics_frame
	_ok(cat.global_position.distance_to(before_still) < 2.5,
		"it settles rather than circling when the player rests")

	# 6. IT WANTS THE FISH. A fish in hand pulls it in closer than its normal follow distance.
	PlayerState.add_item("fish_herring")
	for i in range(PlayerState.hotbar.size()):
		if String(PlayerState.hotbar[i]) == "fish_herring":
			PlayerState.selected_hotbar = i
			break
	_ok(bool(cat.call("_player_holding_fish", player)), "it can tell you are holding a fish")
	_completed = true
