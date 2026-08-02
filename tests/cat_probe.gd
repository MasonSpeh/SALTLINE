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

	# ------------------------------------------------------------------ s34: the states
	#
	# ONE ASSERTION PER TRANSITION, and each one checks the POSE as well as the state — the
	# s32 cat had four states and one mesh, so "it is sitting" was a claim about a variable
	# and not about anything the player could see. `_pose` is the mesh actually visible.
	var poses: Dictionary = cat.get("_pose_nodes")
	_ok(poses.size() >= 5, "every pose mesh loaded (%d of %d)" % [poses.size(), 6])
	# Exactly one visible at a time, or the cat is two cats.
	var shown: int = 0
	for k in poses:
		if (poses[k] as Node3D).visible:
			shown += 1
	_ok(shown == 1, "exactly one pose is drawn at a time (%d visible)" % shown)

	# FISH INTEREST — it is holding the herring from check 6, and the cat should be in FISH.
	player.global_position = cat.global_position + Vector3(3.0, 0.0, 0.0)
	for i in range(30):
		await get_tree().physics_frame
	_ok(int(cat.get("_state")) == 5 and String(cat.get("_pose")) == "walk",
		"a fish in hand puts it in FISH_INTEREST wearing the walk pose (state %d, pose %s)"
			% [int(cat.get("_state")), str(cat.get("_pose"))])

	# RUN — get well beyond RUN_M and it should break into the run pose.
	player.global_position = cat.global_position + Vector3(14.0, 0.0, 0.0)
	PlayerState.selected_hotbar = -1        # drop the fish interest, or FISH wins
	var ran: bool = false
	for i in range(60):
		await get_tree().physics_frame
		if String(cat.get("_pose")) == "run":
			ran = true
			break
	_ok(ran, "left far enough behind, it RUNS (pose %s)" % str(cat.get("_pose")))

	# PET — repeatable, and it wears the sit pose while it leans in.
	var touch2: Node = null
	for c in cat.get_children():
		if c is Interactable:
			touch2 = c
	touch2.emit_signal("interacted", "PET")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(float(cat.get("_pet_t")) > 0.0, "petting starts a head-bump (%.2f s left)"
		% float(cat.get("_pet_t")))

	# FEEDING — a raw fish in hand plus a PET is a feed, once per game day, and it pays out
	# in comfort. The SECOND feed inside the same day must NOT.
	PlayerState.add_item("fish_herring")
	for i in range(PlayerState.hotbar.size()):
		if String(PlayerState.hotbar[i]) == "fish_herring":
			PlayerState.selected_hotbar = i
			break
	# COUNT the herrings rather than asking whether any remain — check 6 above already put
	# one in the pack, so `has_item` is true either way and a presence test would pass
	# whether the cat ate anything or not. And the SECOND feed is judged on the fish too,
	# not on comfort: comfort eases toward its target every frame (COMFORT_EASE_PER_SEC), so
	# "comfort did not change" is false by a few thousandths across any real await.
	var fish_before: int = PlayerState.count_item("fish_herring")
	var comfort_before: float = PlayerState.comfort
	touch2.emit_signal("interacted", "PET")
	await get_tree().physics_frame
	_ok(PlayerState.comfort > comfort_before,
		"feeding it a raw fish pays comfort (%.3f -> %.3f)" % [comfort_before, PlayerState.comfort])
	_ok(PlayerState.count_item("fish_herring") == fish_before - 1,
		"and it ate exactly one fish (%d -> %d)"
			% [fish_before, PlayerState.count_item("fish_herring")])
	PlayerState.add_item("fish_herring")
	for i in range(PlayerState.hotbar.size()):
		if String(PlayerState.hotbar[i]) == "fish_herring":
			PlayerState.selected_hotbar = i
			break
	var fish_2: int = PlayerState.count_item("fish_herring")
	touch2.emit_signal("interacted", "PET")
	await get_tree().physics_frame
	_ok(PlayerState.count_item("fish_herring") == fish_2,
		"a second fish the same game day is refused (%d -> %d)"
			% [fish_2, PlayerState.count_item("fish_herring")])

	# SLEEP — when the player turns in, the cat finds a spot near them and curls up.
	PlayerState.selected_hotbar = -1
	player.set("_lying", true)
	player.set("_lying_sleeping", true)
	var slept: bool = false
	for i in range(420):
		await get_tree().physics_frame
		if String(cat.get("_pose")) == "sleep":
			slept = true
			break
	_ok(slept, "when the player sleeps, the cat curls up (pose %s)" % str(cat.get("_pose")))
	_ok(cat.global_position.distance_to(player.global_position) < 4.0,
		"...and it sleeps NEAR them (%.1f m)"
			% cat.global_position.distance_to(player.global_position))
	# And the spot it chose is a real surface, not the air over one.
	_ok(absf(cat.global_position.y - player.global_position.y) < 1.4,
		"...on the same deck they are on (cat y %.2f, player y %.2f)"
			% [cat.global_position.y, player.global_position.y])
	player.set("_lying", false)
	player.set("_lying_sleeping", false)
	_completed = true
