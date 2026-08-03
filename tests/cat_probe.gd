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

	# THE SEAT GAP, MEASURED INDEPENDENTLY — and this assertion is the one that was missing.
	# The old check was `absf(p.y - 18.0) < 1.2` against the literal deck height, which
	# passes for a cat hanging 1.19 m in the air; the real bug was a DETERMINISTIC 0.500 m
	# float (the spawn ray hit the cat's own interaction box, since it set collision_mask 1
	# with no exclusions). A tolerance wider than the defect cannot see the defect.
	#
	# So: cast our own ray, exclude the cat's whole body, and compare. Independent of what
	# _seat() computed — the s34 seal lesson is that a probe re-deriving the game's own
	# number is a tautology that prints +0.0 mm for an animal on the moon.
	var skip: Array[RID] = []
	for c in cat.get_children():
		if c is CollisionObject3D:
			skip.append((c as CollisionObject3D).get_rid())
	var from: Vector3 = p + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 4.0, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = skip
	var hit: Dictionary = cat.get_world_3d().direct_space_state.intersect_ray(q)
	_ok(not hit.is_empty(), "there is a deck under the cat at all")
	if not hit.is_empty():
		var gap: float = p.y - (hit["position"] as Vector3).y
		_ok(absf(gap) < 0.05,
			"it stands ON the deck, not over it (gap %+.1f mm)" % (gap * 1000.0))

	# YOU CAN WALK THROUGH IT. The handle must not be on the layer the player's capsule
	# masks — but it must still be on SOME layer, or the crosshair loses it entirely.
	var handle: Interactable = null
	for c in cat.get_children():
		if c is Interactable:
			handle = c
			break
	_ok(handle != null, "it carries an interaction handle")
	if handle != null:
		_ok((handle.collision_layer & 1) == 0,
			"the player walks through it — handle is off the solid layer (layer bits %d)"
				% handle.collision_layer)
		_ok(handle.collision_layer != 0,
			"...but it is still on a layer the interaction ray masks (bits %d)"
				% handle.collision_layer)

	# IT HAS A SKELETON. The whole point of s35: without a rig this is the s34 cat with
	# extra machinery, and that difference must be visible to a test.
	var rigs: Dictionary = cat.get("_rigs")
	_ok(rigs.size() >= 4, "the pose meshes carry skeletons to drive (%d rigged)" % rigs.size())

	# EVERY POSE IS THE SAME ANIMAL. The owner's "Cat is too small when sitting, and too big
	# when running, all states are currently different sizes."
	#
	# This is measured on the DRAWN geometry, not on the _pose_size table — the table is
	# the thing under test, and a probe that re-read it would be the s34 seal tautology
	# again. Each pose is scaled to a target LONGEST AXIS, and the longest axis means a
	# different part of the animal per pose, so the invariant asserted here is the one that
	# actually corresponds to "the same cat": the world-space extents must all sit inside a
	# band around the walking cat rather than spanning a 1.8x range as they did.
	var nodes: Dictionary = cat.get("_pose_nodes")
	var spans: Dictionary = {}
	for k in nodes:
		var host: Node3D = nodes[k]
		var acc := AABB()
		var first := true
		for n in host.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			var b: AABB = mi.global_transform * mi.get_aabb()
			acc = b if first else acc.merge(b)
			first = false
		if not first:
			spans[k] = maxf(acc.size.x, maxf(acc.size.y, acc.size.z))
	var lo: float = 1e9
	var hi: float = 0.0
	for k in spans:
		lo = minf(lo, spans[k])
		hi = maxf(hi, spans[k])
	var ratio: float = hi / maxf(lo, 0.0001)
	_ok(spans.size() >= 5, "every pose was measurable (%d)" % spans.size())
	# 1.35 rather than 1.0: a curled sleeping cat and a stretched leaping one genuinely do
	# not have the same longest extent, and pretending they should would force the sleeping
	# mesh to be scaled up until it read as a bigger animal. Before this fix the spread was
	# 0.44..0.74 = 1.68x on the TARGETS alone, before the meshes' own differences.
	_ok(ratio <= 1.35,
		"all poses read as one animal (longest extent %.2f..%.2f m, spread %.2fx)"
			% [lo, hi, ratio])

	# IT DOES NOT WALK THROUGH WALLS. Put the player on the far side of a bulkhead and let
	# the cat try to follow: it must NOT end up on the player's side. The bunkhouse's west
	# wall is around x -28 (RIG_ATLAS zone x[-28,-8]), so a player well outside the room is
	# unreachable without passing through it.
	player.set("_lying", false)
	player.set("_lying_sleeping", false)
	PlayerState.selected_hotbar = -1
	player.global_position = Vector3(-33.0, 18.1, 11.0)
	for i in range(240):
		await get_tree().physics_frame
	_ok(cat.global_position.x > -28.5,
		"it did not walk through the bunkhouse wall chasing the player (cat x %.2f)"
			% cat.global_position.x)

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
	var gap2: float = cat.global_position.distance_to(player.global_position)
	_ok(moved > 1.0, "it followed (moved %.1f m)" % moved)
	_ok(gap2 < 8.0, "and it closed on the player (%.1f m away)" % gap2)

	# IT WALKS HEAD-FIRST. The owner's "the cat walks backwards", as a number.
	#
	# Measured the way this repo measures a facing: accumulate the per-frame ALIGNMENT of
	# the head against that frame's velocity and average it. NOT the net displacement over
	# the window — AGENT_TRAPS records that summing displacement over a wandering path
	# reports the direction the lap happened to stop in, which read six species as
	# backwards when none of them were.
	#
	# The head is the node's -Z: CreatureAnim normalises every generated mesh onto Godot's
	# forward, so -Z is the head for every pose the cat can be wearing.
	player.global_position = Vector3(-24.0, 18.1, 12.0)
	var prev: Vector3 = cat.global_position
	var align_sum: float = 0.0
	var align_n: int = 0
	for i in range(180):
		await get_tree().physics_frame
		var now: Vector3 = cat.global_position
		var vel: Vector3 = now - prev
		vel.y = 0.0
		prev = now
		if vel.length() < 0.0005:
			continue
		var head: Vector3 = -cat.global_transform.basis.z
		head.y = 0.0
		if head.length() < 0.0001:
			continue
		align_sum += head.normalized().dot(vel.normalized())
		align_n += 1
	var align: float = align_sum / maxf(float(align_n), 1.0)
	_ok(align_n > 20, "the cat actually moved enough to judge its facing (%d frames)" % align_n)
	_ok(align > 0.6,
		"it walks HEAD-first, not tail-first (head-vs-travel alignment %+.3f over %d frames)"
			% [align, align_n])
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
