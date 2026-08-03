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
	_ok(cat.get("_rig") != null, "the blender exists — one skeleton drives everything")
	_ok(cat.get("_host") != null, "and there is exactly one drawn body")
	if cat.get("_rig") != null:
		_ok(int(cat.get("_rig").call("pose_count")) >= 7,
			"the pose library is complete (%d poses)" % int(cat.get("_rig").call("pose_count")))

	# SIZE CONSISTENCY IS BY CONSTRUCTION NOW — one mesh cannot be two sizes — so what is
	# asserted is that the one body is a sane cat-sized thing at all.
	var host_node: Node3D = cat.get("_host")
	if host_node != null:
		var acc := AABB()
		var first := true
		for n in host_node.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			var b: AABB = mi.global_transform * mi.get_aabb()
			acc = b if first else acc.merge(b)
			first = false
		var span: float = maxf(acc.size.x, maxf(acc.size.y, acc.size.z))
		_ok(span > 0.4 and span < 1.1,
			"the drawn cat is cat-sized (longest extent %.2f m)" % span)

	# CONTINUITY — the assertion the pose-per-mesh design could never pass, and the whole
	# point of s37. Drive the cat through its states and sample a FOREPAW's skeleton-space
	# position every physics frame: a blend moves it a few centimetres a frame; a swap
	# teleports it. The bound is generous (8 cm) precisely so only architecture-level
	# discontinuities can trip it.
	var skel_c: Skeleton3D = null
	for n in host_node.find_children("*", "Skeleton3D", true, false):
		skel_c = n
		break
	_ok(skel_c != null, "the drawn body carries the skeleton")
	if skel_c != null:
		var paw_i: int = skel_c.find_bone("L_Hand")
		var prev_p: Vector3 = skel_c.get_bone_global_pose(paw_i).origin
		var worst_step: float = 0.0
		var steps: int = 0
		# Walk it through: near (sit) -> far (run) -> near again (sit) -> rest long enough
		# to groom. Every hop is a live transition sampled mid-flight.
		for leg in [Vector3(-22.0, 18.1, 12.0), Vector3(-9.5, 18.1, 5.5),
				Vector3(-22.0, 18.1, 12.0)]:
			player.global_position = leg
			for i in range(140):
				await get_tree().physics_frame
				var now_p: Vector3 = skel_c.get_bone_global_pose(paw_i).origin
				worst_step = maxf(worst_step, prev_p.distance_to(now_p))
				prev_p = now_p
				steps += 1
		_ok(steps > 300, "the continuity sweep sampled the paw (%d frames)" % steps)
		_ok(worst_step < 0.08,
			"no pose change ever teleports the body (worst paw step %.1f mm/frame)"
				% (worst_step * 1000.0))

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

	# ------------------------------------------------------------------ the states
	#
	# ONE ASSERTION PER TRANSITION, each checking the POSE TARGET as well as the state —
	# `_pose` is the blender's target, and the blend to it is covered by the continuity
	# sweep above, so together they say "the right pose, reached smoothly".

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
	#
	# PUT THE PLAYER BACK IN THE ROOM FIRST. The wall check above deliberately strands them
	# outside the bunkhouse, and leaving them there makes this test assert that a cat can
	# curl up beside someone it is correctly refusing to walk through a bulkhead to reach —
	# which fails for the right reason and reads like a broken feature.
	PlayerState.selected_hotbar = -1
	player.global_position = Vector3(-22.0, 18.1, 12.0)
	for i in range(30):
		await get_tree().physics_frame
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

	# ------------------------------------------------------- THE ONE THAT WAS MISSING
	#
	# THE CAT'S BODY MUST NEVER BE INSIDE THE RIG. Every check before this asked about the
	# cat's ORIGIN — a point — and the owner photographed the animal embedded in a bulkhead
	# with its head out one face and its body out the other. A point can stop perfectly
	# legally with up to 0.48 m of cat in the concrete, and no assertion here could see it.
	#
	# So: drive the animal hard against the geometry most likely to swallow it — corners,
	# bulkheads, the far side of walls — and sample its BODY VOLUME, not its origin, every
	# few frames. A ray cannot do this: a ray whose origin is already inside a shape does
	# not report that shape, so the moment the bug occurs a raycast test goes silent. This
	# uses the same sphere query the movement code does.
	var chase: Array[Vector3] = [
		Vector3(-27.4, 18.1, 17.4),   # NW corner of the bunkhouse
		Vector3(-8.6, 18.1, 4.6),     # SE corner
		Vector3(-27.4, 18.1, 4.6),    # SW corner
		Vector3(-33.0, 18.1, 11.0),   # through the west wall — must be refused
		Vector3(-18.0, 18.1, 17.8),   # hard against the north wall
		Vector3(-22.0, 18.1, 12.0),   # back to open floor
	]
	var buried_frames: int = 0
	var worst_depth: float = 0.0
	var samples: int = 0
	var sphere := SphereShape3D.new()
	var shq := PhysicsShapeQueryParameters3D.new()
	shq.shape = sphere
	shq.collision_mask = 1
	shq.collide_with_areas = false
	for dest in chase:
		player.global_position = dest
		for i in range(150):
			await get_tree().physics_frame
			if i % 5 != 0:
				continue
			samples += 1
			sphere.radius = float(cat.call("_body_r"))
			shq.exclude = cat.call("_walk_skip")
			shq.transform = Transform3D(Basis.IDENTITY,
				cat.global_position + Vector3(0, sphere.radius + 0.04, 0))
			var pairs: PackedVector3Array = \
				cat.get_world_3d().direct_space_state.collide_shape(shq, 4)
			if pairs.size() >= 2:
				buried_frames += 1
				for k in range(0, pairs.size() - 1, 2):
					worst_depth = maxf(worst_depth, (pairs[k] - pairs[k + 1]).length())
	_ok(samples > 100, "the burial sweep actually sampled the cat (%d samples)" % samples)
	_ok(buried_frames == 0,
		"the cat's BODY was never inside the rig (%d/%d samples buried, worst %.0f mm)"
			% [buried_frames, samples, worst_depth * 1000.0])
	_completed = true
