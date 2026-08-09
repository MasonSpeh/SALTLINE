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

## Move the player like a PLAYER, not like a harness: 0.08 m per physics tick, which at this
## project's 30 Hz is 2.4 m/s — an ordinary walk, and well under the cat's TRAIL_JUMP break.
## Teleporting is what breaks the trail, on purpose, so a scenario that means to exercise it
## has to walk.
func _walk_player(player: Node3D, to: Vector3) -> void:
	while player.global_position.distance_to(to) > 0.08:
		player.global_position = player.global_position.move_toward(to, 0.08)
		await get_tree().physics_frame
	player.global_position = to
	await get_tree().physics_frame

func _run() -> void:
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	_ok(cat != null, "a cat exists on the rig")
	if cat == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)

	# 1. IT IS IN THE STORE ROOM, AND IT IS ON THE FLOOR. The store-room zone is x[10,16]
	# z[-22,-16] at the wet deck (RIG_ATLAS / tools/rig_zones.json), and the spawn Y is probed
	# rather than typed — so assert it landed ON something, not at the authored constant.
	# (It used to be the bunkhouse, topside. Owner: "Have the cat spawn in the 2nd internal
	# room near a light so it is illuminated in the dark" — see ship_cat.HOME for which room
	# and why, and tests/CatSpawnProbe for the floor/clearance/ceiling/illumination gates. The
	# ZONE is asserted here rather than the point, so moving the seat within the room does not
	# break this row.)
	var p: Vector3 = cat.global_position
	_ok(p.x > 10.0 and p.x < 16.0 and p.z > -22.0 and p.z < -16.0,
		"it is in the store room (%.1f, %.1f)" % [p.x, p.z])

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

	# ...AND EVERYTHING BELOW STAGES ON THE BUNKHOUSE DECK, so move it there now that the spawn
	# itself has been judged. The spawn used to BE the bunkhouse, so the rest of this file's
	# waypoints — the continuity sweep's three legs, the wall test at x −33, the doorway
	# crossing at z 10 — are all authored against that room and inherited the staging for free.
	# With the cat spawning on the wet deck (see `ship_cat.HOME`) they are 40 m away and across
	# open water, and the first thing the animal did was follow the player off the pontoon: the
	# rows failed for a real reason that was not the one under test. Staging explicitly is what
	# every other section of this file already does, and it keeps the two concerns apart — the
	# spawn is asserted where the game puts it, the behaviour is measured where it is staged.
	cat.global_position = Vector3(-24.6, 18.0, 11.4)
	cat.call("_reseat")
	player.global_position = Vector3(-22.0, 18.1, 12.0)
	for i in range(20):
		await get_tree().physics_frame

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
		# The bound discriminates TELEPORT from FAST. A gallop is legitimately quick: at
		# 4.4 m/s the cycle runs ~5 Hz and a swinging paw covers ~90-100 mm in one 60 Hz
		# frame — measured 94 mm in this very sweep. A mesh SWAP (the retired design)
		# displaces a paw by the whole pose difference, 300-500 mm, in one frame. 150 mm
		# sits between the two with margin both ways.
		_ok(worst_step < 0.15,
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
	#
	# THE SELF-DIRECTED GAMES ARE HELD OFF, as every reel in cat_film holds them off, because
	# this assertion is about the FOLLOW and the zoomies are a deliberate feature that fires
	# on exactly this trigger — a player who has settled nearby — and orbits them at 2.0-3.4 m,
	# which is more than the 2.5 m this bound allows. Until s48 the check passed only by luck:
	# a wash was guaranteed on arrival and reliably filled the window. Making the wash the
	# random event the owner asked for removed that accident and left the tension visible,
	# which is the honest place for it — the probe now says which behaviour it is judging.
	# `_roam_cd` JOINS THE THREE, and for exactly the same reason they are there. The instinct
	# layer (s54) has two actions that deliberately move the animal off the spot it is on — a
	# mosey and a perch — and both are gated on that one cooldown so a harness that needs the
	# cat to hold still has one number to pin. The STATIONARY instincts are deliberately left
	# running: this check says "it settles rather than circling", and a wash or a stretch that
	# moved the cat two metres would be a bug this bound should catch.
	var before_still: Vector3 = cat.global_position
	for i in range(420):     # past SETTLE_SEC at 60 Hz
		cat.set("_zoom_cd", 999.0)
		cat.set("_play_cd", 999.0)
		cat.set("_hunt_cd", 999.0)
		cat.set("_roam_cd", 999.0)
		await get_tree().physics_frame
	_ok(cat.global_position.distance_to(before_still) < 2.5,
		"it settles rather than circling when the player rests")

	# 5b. STAY MEANS STAY, COME MEANS COME — the owner's follow toggle (s45). Told to
	# stay, it must hold its patch while the player crosses the room; told to come, it
	# must fall back in. Verbs are asserted on the HANDLE (what the crosshair actually
	# reads), and the leash test moves the player well past the old LOST_M distance so
	# "holds its patch" is proven against the strongest pull the follow now has.
	var touch_s: Interactable = null
	for c in cat.get_children():
		if c is Interactable:
			touch_s = c
			break
	touch_s.emit_signal("interacted", "STAY")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(bool(cat.get("_stayed")), "STAY sets the flag")
	_ok("COME" in (cat.call("available_verbs") as Array), "...and the crosshair now offers COME")
	var stay_spot: Vector3 = cat.global_position
	player.global_position = Vector3(-9.5, 18.1, 5.5)
	for i in range(420):
		cat.set("_roam_cd", 999.0)
		await get_tree().physics_frame
	_ok(cat.global_position.distance_to(stay_spot) < 5.0,
		"stayed, it holds its patch while the player walks off (%.1f m from the spot)"
			% cat.global_position.distance_to(stay_spot))
	player.global_position = Vector3(-22.0, 18.1, 12.0)
	for i in range(30):
		await get_tree().physics_frame
	touch_s.emit_signal("interacted", "COME")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(not bool(cat.get("_stayed")), "COME clears the flag")
	# The toggle is the subject, not the hunt scheduler: an unleashed stay-time hunt can
	# leave `_after_t` (the affronted post-miss wash, ~2.7 s) running when COME arrives,
	# and the wash legitimately outranks walking. Clear the residues so the window below
	# measures the FOLLOW, the same isolation every reel applies.
	cat.set("_hunt_cd", 999.0)
	cat.set("_after_t", 0.0)
	cat.set("_wash_t", 0.0)
	cat.set("_zoom_cd", 999.0)
	cat.set("_play_cd", 999.0)
	cat.set("_roam_cd", 999.0)
	var come_start: Vector3 = cat.global_position
	# WALK, DO NOT TELEPORT, and the reason is the feature under test two checks below.
	# A teleport BREAKS the bait trail by design (a >0.9 m jump cannot be a step), so a
	# COME that ends with a teleported player leaves the cat solving the bunkhouse with the
	# detour fan alone — and the trail check itself proves the fan cannot leave the west
	# cabin. This assertion is about the TOGGLE, not about routing, so it should exercise
	# the conditions real play produces: a player who walked there. Its flakiness across
	# sessions was exactly this — pass or fail depending on which side of a divider the cat
	# happened to be standing when the window opened.
	await _walk_player(player, Vector3(-18.0, 18.1, 11.2))
	await _walk_player(player, Vector3(-12.0, 18.1, 10.0))
	for i in range(480):
		cat.set("_roam_cd", 999.0)
		await get_tree().physics_frame
	_ok(cat.global_position.distance_to(come_start) > 1.0
			and cat.global_position.distance_to(player.global_position) < 9.0,
		"...and it follows again (moved %.1f m, now %.1f m from the player; cat %s state %d pose %s stall %.2f)"
			% [cat.global_position.distance_to(come_start),
				cat.global_position.distance_to(player.global_position),
				str(cat.global_position.snappedf(0.1)), int(cat.get("_state")),
				str(cat.get("_pose")), float(cat.get("_detour_stall"))])

	# 5c. THE BAIT TRAIL — the owner's "maneuver with grace around corners and doorways".
	#
	# WHY THIS GEOMETRY AND NOT A SIMPLER ONE. The cat is parked deep in the WEST-SOUTH bunk
	# cabin and the player finishes in the EAST-SOUTH one, so the goal bearing is due EAST —
	# while the only way out of that cabin is the 1.4 m opening at x -24.665, three metres
	# WEST (rig_builder._build_bunkhouse cuts one at the centre of each 6.67 m corridor
	# segment; the dividers at x -21.33 / -14.66 are solid from z4 to z10). Every heading the
	# detour fan will try is inside +-115 deg of the goal, so greedy steering CANNOT find that
	# door: it slides up and down the divider it is pressed against.
	#
	# The player WALKS the route rather than being teleported along it, which is the point —
	# a teleport is what breaks the trail, deliberately, and every other scenario in this file
	# teleports, so the trail is empty for all of them and none of their verdicts move.
	#
	# The cat is STAYED for the walk, so it solves the route from cold afterwards instead of
	# trailing two metres behind the whole way. That also proves the recorder keeps running
	# while the cat is stayed — a COME with a cold trail would be a different feature.
	var trail_doors: Array = [-24.665, -17.995, -11.33]   # cabin openings on z=10
	cat.global_position = Vector3(-23.8, 18.05, 8.6)
	cat.call("_reseat")
	cat.set("_hunt_cd", 999.0)
	cat.set("_zoom_cd", 999.0)
	cat.set("_play_cd", 999.0)
	cat.set("_roam_cd", 999.0)
	cat.set("_after_t", 0.0)
	cat.set("_wash_t", 0.0)
	cat.set("_carry", "")
	player.global_position = Vector3(-23.0, 18.1, 8.8)
	for i in range(20):
		await get_tree().physics_frame
	touch_s.emit_signal("interacted", "STAY")
	for i in range(10):
		await get_tree().physics_frame
	for leg in [Vector3(-24.665, 18.1, 8.8), Vector3(-24.665, 18.1, 11.2),
			Vector3(-11.33, 18.1, 11.2), Vector3(-11.33, 18.1, 8.6),
			Vector3(-10.6, 18.1, 6.9)]:
		await _walk_player(player, leg)
	var crumbs: int = (cat.get("_trail") as PackedVector3Array).size()
	# ~22 m of route at TRAIL_STEP 0.6 is about 36 crumbs, capped at TRAIL_MAX 64. A short
	# trail means the recorder's ground probe or its swim-line guard rejected the deck, not
	# that the cat cannot navigate — which is a different bug, so it gets its own line.
	_ok(crumbs > 20, "the player's walk laid a trail (%d crumbs over ~22 m of route)" % crumbs)
	touch_s.emit_signal("interacted", "COME")
	cat.set("_hunt_cd", 999.0)
	cat.set("_after_t", 0.0)
	cat.set("_wash_t", 0.0)
	cat.set("_zoom_cd", 999.0)
	cat.set("_play_cd", 999.0)
	# THE CROSSING COUNT IS THE ASSERTION, not a timeout. A cat that solves this room has to
	# cross the z=10 wall line twice — out of one cabin and into the other — and both times
	# through an opening. Zero crossings is the pre-trail animal; a crossing anywhere but a
	# door would be the s36 wall-clipping bug back again.
	var prev_c: Vector3 = cat.global_position
	var crossings: int = 0
	var thru_wall: int = 0
	var cat_path: float = 0.0
	for i in range(600):        # 20 s at 30 Hz; the route is ~22 m and it runs at 4.4 m/s
		cat.set("_roam_cd", 999.0)
		await get_tree().physics_frame
		var now_c: Vector3 = cat.global_position
		cat_path += prev_c.distance_to(now_c)
		if (prev_c.z - 10.0) * (now_c.z - 10.0) < 0.0:
			crossings += 1
			var f: float = (10.0 - prev_c.z) / (now_c.z - prev_c.z)
			var xh: float = prev_c.x + (now_c.x - prev_c.x) * f
			var in_door: bool = false
			for dx in trail_doors:
				if absf(xh - float(dx)) < 0.75:
					in_door = true
			if not in_door:
				thru_wall += 1
		prev_c = now_c
	_ok(crossings >= 2,
		"it left one cabin and entered the other (%d crossings of z=10, cat %s, path %.1f m)"
			% [crossings, str(cat.global_position.snappedf(0.1)), cat_path])
	_ok(thru_wall == 0,
		"...and every crossing was through a doorway, never a wall (%d bad of %d)"
			% [thru_wall, crossings])
	_ok(cat.global_position.distance_to(player.global_position) < 3.0
			and cat.global_position.x > -14.5 and cat.global_position.z < 9.87,
		"...and it is in the east cabin with the player (%.1f m away, cat %s)"
			% [cat.global_position.distance_to(player.global_position),
				str(cat.global_position.snappedf(0.1))])
	# PUT THE WORLD BACK. The trap this file already records: a probe that repositions the
	# world and leaves it there makes the NEXT check assert something nobody meant.
	cat.global_position = Vector3(-22.0, 18.05, 11.0)
	cat.call("_reseat")
	player.global_position = Vector3(-22.0, 18.1, 12.0)
	for i in range(30):
		await get_tree().physics_frame

	# 5d. IT ACTUALLY LEAPS — and this is the first assertion in the project's history that
	# has ever watched the cat leave the ground.
	#
	# The leap existed for five sessions and had never fired. Four separate faults stacked,
	# each hiding the next, and every one of them passed whatever test was pointed at it:
	#   * the footfall probe reaches 0.75 m while JUMP_UP is 1.25, so ledges in between
	#     passed UNDER the ray and read as flat deck;
	#   * the ledge probe that fixes that sat AFTER the detour fan, which returns early on
	#     exactly the frames a ledge matters — dead code;
	#   * it then probed one step (26 mm) ahead instead of a body length, landing short of
	#     the lip and finding the deck the cat was already on;
	#   * and `d > FOLLOW_NEAR` measures a THREE-DIMENSIONAL distance, so a player standing
	#     on a 1 m crate 1.35 m away reads 1.87 m — inside the gap — and the animal declared
	#     itself arrived and sat down without ever calling the walk.
	# Then the arc check refused every steep hop, twice over: the flight advanced
	# horizontally at a constant rate (so at 35% of the climb it was inside the crate it was
	# aiming at), and the clearance test asked the WALKING question mid-air, where a rising
	# cat's muzzle is legitimately out over the lip.
	#
	# A CRATE WE BUILD, not a ledge we hunt for. Probing the world for "a surface in the
	# 0.66-1.20 m band" kept returning small props the animal simply walks around, so the
	# test measured the pathfinder and answered differently each run.
	var leap_crate := StaticBody3D.new()
	var leap_cs := CollisionShape3D.new()
	var leap_box := BoxShape3D.new()
	leap_box.size = Vector3(2.4, 1.0, 2.4)
	leap_cs.shape = leap_box
	leap_crate.add_child(leap_cs)
	get_tree().current_scene.add_child(leap_crate)
	leap_crate.global_position = Vector3(5.6, 18.5, -3.0)
	cat.global_position = Vector3(3.0, 18.0, -3.0)
	cat.call("_reseat")
	cat.set("_hunt_cd", 999.0)
	cat.set("_zoom_cd", 999.0)
	cat.set("_play_cd", 999.0)
	cat.set("_wash_t", 0.0)
	cat.set("_stayed", false)
	var leap_y0: float = cat.global_position.y
	var leap_top: float = 0.0
	var leap_flew: bool = false
	for i in range(600):
		player.global_position = Vector3(5.6, 19.2, -3.0)
		# THE PERCH IS A DELIBERATE CLIMB AND THIS CHECK IS ABOUT AN INVOLUNTARY ONE. Held off
		# so "the leap fires at a crate one jump high" cannot be satisfied by the instinct layer
		# choosing to sit on the crate for its own reasons — same isolation, different rung.
		# `_idle_cd` goes with it: once the cat is UP, it is settled beside the player and the
		# whole menu opens, and a checks-out-at-frame-600 assertion should not be sharing its
		# window with a nap or a wash.
		cat.set("_roam_cd", 999.0)
		cat.set("_idle_cd", 999.0)
		await get_tree().physics_frame
		leap_top = maxf(leap_top, cat.global_position.y)
		if float(cat.get("_jump_t")) > 0.0:
			leap_flew = true
	_ok(leap_flew, "the leap actually fires at a crate one jump high")
	_ok(leap_top - leap_y0 > 0.5,
		"...and the body leaves the deck (rose %.2f m)" % (leap_top - leap_y0))
	_ok(cat.global_position.y > leap_y0 + 0.5,
		"...and it ends up ON the crate (y %.2f, deck %.2f)"
			% [cat.global_position.y, leap_y0])

	# 5e. AND IT CAN GET BACK DOWN — the half nobody had ever tested.
	#
	# The check above ends by TELEPORTING the cat off the crate, which is why five sessions of
	# green runs never noticed that the animal it left up there could not have walked off. The
	# descent was refused by construction: `_step_clear` puts the landing sphere 0.157 m above
	# the lower deck immediately beside the crate's vertical face, where it needs `_body_r()`
	# = 0.117 m of clearance and a walk step is 0.0158 m. Refused, deterministically, every
	# frame, for ever. Compounding it, `near_gap` only shrank when the PLAYER was above the
	# cat, so with the cat up and the player down the 3D distance sat inside FOLLOW_NEAR and
	# the animal declared itself arrived and SAT DOWN on the crate.
	#
	# So: player back on the deck, and watch it come off. Both halves are asserted — that it
	# LEAVES (a cat stranded on a workbench is the bug) and that it JUMPS rather than sliding
	# down some seam (`_jump_t` positive on a descending arc).
	#
	# JUDGED WHEN IT HAS LANDED, NOT WHEN IT IS PAST THE LIP. The first cut of this broke out
	# of the loop the frame the cat's y crossed a threshold, which it does IN MID-AIR — it
	# reported 18.19 m for an animal that was still falling, i.e. it would have passed just as
	# happily on a cat that dropped through the deck. Wait for the flight to be over and the
	# wind-up to be clear, then read the settled height.
	player.global_position = Vector3(3.0, 18.1, -3.0)
	var down_from: float = cat.global_position.y
	var down_flew: bool = false
	var down_low: float = down_from
	var down_settled: bool = false
	for i in range(900):
		cat.set("_roam_cd", 999.0)
		cat.set("_idle_cd", 999.0)
		await get_tree().physics_frame
		if float(cat.get("_jump_t")) > 0.0 or float(cat.get("_jump_wind")) > 0.0:
			down_flew = true
			continue
		down_low = minf(down_low, cat.global_position.y)
		if down_flew and cat.global_position.y < leap_y0 + 0.25:
			down_settled = true
			break
	_ok(down_settled and absf(cat.global_position.y - leap_y0) < 0.15,
		"it GETS DOWN off the crate and lands on the deck (%.2f -> %.2f, deck %.2f)"
			% [down_from, cat.global_position.y, leap_y0])
	_ok(down_flew, "...and it jumps down rather than being slid down (a flight fired)")
	_ok(down_low > leap_y0 - 0.20,
		"...and it never went through the deck (lowest settled y %.2f, deck %.2f)"
			% [down_low, leap_y0])
	leap_crate.queue_free()
	await get_tree().physics_frame

	# 5f. A DROP TALLER THAN THE PROBE THAT LOOKS FOR IT.
	#
	# The crate above is 1.0 m, which the footfall ray (0.75 m up, 1.85 m of reach) can still
	# see the deck under. Six metres cannot be seen at all: the ray finds NOTHING, and the old
	# code's answer to nothing was a bare `return` — correct as "a cat does not walk off a
	# rig", fatal as "a cat left up here stays up here for the session". The owner's ask is ten
	# metres; this is six, inside DROP_MAX with room to spare, and it exercises the other of
	# the two routes into the descent.
	var tower := StaticBody3D.new()
	var tcs := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(2.0, 6.0, 2.0)
	tcs.shape = tbox
	tower.add_child(tcs)
	get_tree().current_scene.add_child(tower)
	# Foot on the deck, top SIX metres up: centre = deck + half the height. (The first cut put
	# the centre at deck+3 and the cat at 21.0 — which is INSIDE a box spanning 18..24, and a
	# ray whose origin is inside a shape reports nothing in Godot, so `_reseat` silently left
	# the animal buried and the test measured `_unbury` plus a free fall instead of a jump.)
	tower.global_position = Vector3(5.6, 18.0 + 3.0, -3.0)     # spans y 18..24
	cat.global_position = Vector3(5.6, 24.0, -3.0)
	cat.call("_reseat")
	player.global_position = Vector3(3.0, 18.1, -3.0)
	var tall_from: float = cat.global_position.y
	var tall_flew: bool = false
	var tall_down: bool = false
	for i in range(1200):
		cat.set("_roam_cd", 999.0)
		cat.set("_idle_cd", 999.0)
		await get_tree().physics_frame
		if float(cat.get("_jump_t")) > 0.0 or float(cat.get("_jump_wind")) > 0.0:
			tall_flew = true
			continue
		if tall_flew and cat.global_position.y < 18.3:
			tall_down = true
			break
	_ok(tall_from > 23.5, "the tall-drop cat really started on top (y %.2f)" % tall_from)
	_ok(tall_down and absf(cat.global_position.y - 18.0) < 0.15,
		"it comes down a %.1f m drop the footfall ray cannot even see (%.2f -> %.2f)"
			% [tall_from - 18.0, tall_from, cat.global_position.y])
	_ok(tall_flew, "...as a jump, with an arc (a flight fired)")
	tower.queue_free()
	await get_tree().physics_frame
	cat.global_position = Vector3(-22.0, 18.05, 11.0)
	cat.call("_reseat")
	player.global_position = Vector3(-22.0, 18.1, 12.0)
	for i in range(30):
		await get_tree().physics_frame

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

	# ------------------------------------------------------- 7. THE INSTINCT LAYER (s54)
	#
	# The bottom of the state machine is a WEIGHTED DRAW rather than a rung — see the section
	# at the foot of ship_cat.gd. A stochastic selector is an excellent way to build a flaky
	# probe, and this repo has two on file, so what is asserted here is either (a) exact, on
	# the selector treated as a pure function of the drives, or (b) structural, on wiring that
	# either exists or does not. The DISTRIBUTION over a long live run is measured by
	# tests/CatBehaviourProbe.tscn, which is where a number that can wander belongs.
	PlayerState.selected_hotbar = -1
	player.global_position = Vector3(-22.0, 18.1, 12.0)
	cat.global_position = Vector3(-22.0, 18.05, 11.0)
	cat.call("_reseat")
	cat.set("_stayed", false)
	cat.set("_hunt_cd", 999.0)
	cat.set("_zoom_cd", 999.0)
	cat.set("_play_cd", 999.0)
	cat.set("_after_t", 0.0)
	cat.set("_carry", "")
	cat.set("_wash_t", 0.0)
	# THE SLEEP CHECK ABOVE LEAVES THE ANIMAL ASLEEP, AND WAKING IS A BEAT. `_companion`'s
	# falling edge on `_was_asleep` arms a 1.3-2.4 s STRETCH — rung 2, which outranks
	# everything below the hand — and fast-tracks the zoomies to 2.5 s. Both then fire inside
	# this section: the first cut of 7d reported "state 13 wearing the stretch pose" and 7e's
	# perch never left the deck, and neither was an instinct-layer fault. Flush the beat before
	# measuring anything, and hold the older idlers off while it drains.
	for i in range(150):
		cat.set("_hunt_cd", 999.0)
		cat.set("_zoom_cd", 999.0)
		cat.set("_play_cd", 999.0)
		cat.set("_roam_cd", 999.0)
		cat.set("_idle_cd", 999.0)
		cat.set("_zoom_t", 0.0)
		cat.set("_play_t", 0.0)
		await get_tree().physics_frame
	cat.set("_was_asleep", false)
	cat.set("_stretch_t", 0.0)
	cat.set("_wash_t", 0.0)
	cat.call("_end_idle")

	# 7a. SEEDED MEANS SEEDED. The chooser draws from its OWN generator, exactly once per
	# decision, precisely so that "reseed and take N decisions" is a reproducible sequence —
	# `_rng` is shared with tail flicks and stalk freezes and its Nth draw depends on how many
	# gulls happened to fly past. Compared element by element, not as a histogram: two
	# different orders with the same counts would pass a histogram test and are not the same
	# stream.
	cat.set("_energy", 0.55)
	cat.set("_still", 20.0)
	cat.set("_wash_cd", 0.0)
	cat.set("_shake_cd", 0.0)
	cat.set("_meow_cd", 0.0)
	cat.set("_roam_cd", 0.0)
	var menu: Dictionary = cat.call("_action_weights", true)
	var seq_a: Array = []
	var seq_b: Array = []
	cat.call("set_behaviour_seed", 8675309)
	for i in range(300):
		seq_a.append(String(cat.call("_pick_action", menu)))
	cat.call("set_behaviour_seed", 8675309)
	for i in range(300):
		seq_b.append(String(cat.call("_pick_action", menu)))
	_ok(seq_a == seq_b, "the decision stream is reproducible from its seed (300 draws, in order)")
	var kinds: Dictionary = {}
	for s in seq_a:
		kinds[s] = int(kinds.get(s, 0)) + 1
	var worst_k: String = ""
	var worst_n: int = 0
	for k in kinds:
		if int(kinds[k]) > worst_n:
			worst_n = int(kinds[k])
			worst_k = String(k)
	_ok(kinds.size() >= 8,
		"a settled cat has at least eight things it might do next (%d: %s)"
			% [kinds.size(), str(kinds.keys())])
	_ok(float(worst_n) / 300.0 < 0.30,
		"...and none of them is more than 30%% of the animal (commonest %s at %.1f%%)"
			% [worst_k, 100.0 * float(worst_n) / 300.0])

	# 7b. THE WASH IS OUT OF ITS THREE-SECOND BOX. `_maybe_wash` was called from inside the
	# `else` of `if _still > SETTLE_SEC`, so a bout could only ever start while
	# 3.0 < _still <= 6.0 — and a STAYED cat, whose `_still` never resets, got exactly one
	# window per STAY for the whole session. Asserted at a `_still` that used to be fatal.
	cat.set("_still", 300.0)
	var late: Dictionary = cat.call("_action_weights", true)
	_ok(float(late.get("wash_paw", 0.0)) > 0.0 and float(late.get("scratch_ear", 0.0)) > 0.0,
		"a cat settled for five minutes can still start a wash (paw %.2f, scratch %.2f)"
			% [float(late.get("wash_paw", 0.0)), float(late.get("scratch_ear", 0.0))])
	cat.set("_still", 20.0)

	# 7c. `_tick_energy`'S DEFAULT ARM RECOVERS ENERGY, so a state missing from its match is a
	# cat that RESTS while it works — the trap the brief names by hand. Drive every state
	# through it and assert none of them lands on the fall-through. Measured, not read: the
	# spend is recovered from the energy delta over a one-second tick with the crepuscular
	# pull held off by forcing DAY.
	var phase_was: int = GameClock.current_phase
	GameClock.force_phase(GameClock.Phase.DAY)
	var state_was: int = int(cat.get("_state"))
	var unnamed: Array = []
	for st in range(15):
		cat.call("_enter", st)
		cat.set("_energy", 0.5)
		cat.call("_tick_energy", 1.0)
		var spend: float = 0.5 - float(cat.get("_energy"))
		if absf(spend - (-0.010)) < 1e-6:
			unnamed.append(st)
	_ok(unnamed.is_empty(),
		"every one of the 15 states is named in _tick_energy (unnamed: %s)" % str(unnamed))
	GameClock.force_phase(phase_was)
	cat.call("_enter", state_was)
	cat.set("_energy", 0.55)

	# 7d. THE EAR SCRATCH, WHICH KNOWN_ISSUES RECORDS AS "WRITTEN AND CUT". cat_rig now carries
	# a `groom_scratch` pose with the left hind handed to the bake as a free leg, and wash style
	# 3 selects it — but the only way to reach that style was one face of a die rolled inside
	# the three-second window above, so it had effectively never played. It is a first-class
	# action now; this asserts the whole chain lands: action -> style -> STATE -> the rig's own
	# pose target. (`set_pose` no-ops SILENTLY on a name the library does not have, which is
	# why the target is read back rather than assumed.)
	cat.set("_wash_cd", 0.0)
	cat.set("_wash_t", 0.0)
	cat.set("_idle_cd", 0.0)
	cat.set("_stretch_t", 0.0)
	cat.call("_begin_action", "scratch_ear")
	_ok(int(cat.get("_wash_style")) == 3,
		"the ear scratch picks style 3 (got %d)" % int(cat.get("_wash_style")))
	var scratch_pose: String = ""
	var scratch_state: int = -1
	for i in range(20):
		cat.set("_hunt_cd", 999.0)
		cat.set("_zoom_cd", 999.0)
		cat.set("_play_cd", 999.0)
		cat.set("_stretch_t", 0.0)
		await get_tree().physics_frame
		if cat.get("_rig") != null:
			scratch_pose = String(cat.get("_rig").call("target"))
		scratch_state = int(cat.get("_state"))
	_ok(scratch_state == 0,
		"...it puts the animal in GROOM (state %d)" % scratch_state)
	_ok(scratch_pose == "groom_scratch",
		"...wearing the rig's OWN scratch pose, not the paw-lick body (target %s)" % scratch_pose)
	cat.set("_wash_t", 0.0)
	cat.call("_end_idle")

	# 7e. PERCH — STATE 12, WHICH HAD NEVER BEEN ENTERED IN THIS STATE'S EXISTENCE.
	#
	# It has had a STATE_POSE row, a `_tick_energy` arm and a tail line since it was declared,
	# and `grep "_enter(State.PERCH)"` found nothing: the header's claim that "PERCH is the
	# cat's standing preference for being higher than you" described a behaviour that had never
	# run. A crate we BUILD, for the same reason the leap check builds one — probing the world
	# for "something 0.3-1.25 m tall" returns different props on different runs and then the
	# test measures the level design.
	var perch_crate := StaticBody3D.new()
	var pcs2 := CollisionShape3D.new()
	var pbox2 := BoxShape3D.new()
	pbox2.size = Vector3(1.8, 0.9, 1.8)
	pcs2.shape = pbox2
	perch_crate.add_child(pcs2)
	get_tree().current_scene.add_child(perch_crate)
	# TOP AT 18.90, i.e. inside the LEAP band. It is not a free choice: tests/CatStepScratch
	# measured this animal getting onto nothing at all between 0.20 m and CLIMB_UP (0.62) — the
	# whole "step" band is unclimbable against a vertical face — and onto everything from
	# 0.70 m up, by jumping. A shorter crate here would be testing a locomotion bug, not a perch.
	# ...AND ON THE OPEN DECK, NOT IN THE BUNKHOUSE. Building the crate is only half of "not a
	# ledge we hunt for": the bunkhouse ALSO offers a bunk frame 0.97 m up, which outscored the
	# crate, and which the animal then could not reach (the approach fouls on the bunk's side —
	# the stall detector correctly gave up after 3 s, and the check failed for a true reason
	# that was not the one under test). The spawndeck spot the leap check uses is clear.
	perch_crate.global_position = Vector3(5.0, 18.45, -3.0)
	cat.global_position = Vector3(3.0, 18.0, -3.0)
	cat.call("_reseat")
	player.global_position = Vector3(3.8, 18.1, -2.0)
	cat.set("_roam_cd", 0.0)
	cat.set("_idle_cd", 0.0)
	cat.set("_still", 30.0)
	cat.set("_wash_t", 0.0)
	cat.set("_stretch_t", 0.0)
	cat.set("_was_asleep", false)
	for i in range(10):
		cat.set("_hunt_cd", 999.0)
		cat.set("_zoom_cd", 999.0)
		cat.set("_play_cd", 999.0)
		await get_tree().physics_frame
	var perch_deck: float = 18.0
	cat.call("_begin_action", "perch")
	_ok(String(cat.get("_idle_act")) == "perch",
		"the perch action finds somewhere higher to sit (act %s, aiming at %s)"
			% [str(cat.get("_idle_act")), str((cat.get("_idle_at") as Vector3).snappedf(0.01))])
	var perched_state: bool = false
	var perch_y: float = cat.global_position.y
	# A TRACE, PRINTED ONLY ON A FAILURE. "It did not get up there" is not a diagnosis and this
	# file already records what that costs — CatBehDiag exists because a FAIL with no trace
	# turned a one-line bug into a session.
	var perch_trace: Array = []
	for i in range(600):
		cat.set("_hunt_cd", 999.0)
		cat.set("_zoom_cd", 999.0)
		cat.set("_play_cd", 999.0)
		await get_tree().physics_frame
		perch_y = maxf(perch_y, cat.global_position.y)
		if i % 40 == 0:
			perch_trace.append("t%d st%d act=%s it=%.1f y=%.2f at=%s still=%.1f str=%.1f"
				% [i, int(cat.get("_state")), str(cat.get("_idle_act")),
					float(cat.get("_idle_t")), cat.global_position.y,
					str(cat.global_position.snappedf(0.1)), float(cat.get("_still")),
					float(cat.get("_stretch_t"))])
		if int(cat.get("_state")) == 12:
			perched_state = true
			break
	if not perched_state:
		for t in perch_trace:
			print("      perch trace: %s" % t)
	_ok(perched_state, "...and it gets up there and sits: PERCH, state 12 (state %d, y %.2f)"
		% [int(cat.get("_state")), cat.global_position.y])
	_ok(perch_y > perch_deck + 0.60,
		"...standing higher than the deck it started on (%.2f vs %.2f)" % [perch_y, perch_deck])
	# AND IT COMES BACK DOWN WHEN YOU WALK OFF — the leash, which is the only thing keeping an
	# instinct from outranking the companion contract. Walk the player away and watch it follow.
	cat.set("_roam_cd", 999.0)
	await _walk_player(player, Vector3(0.5, 18.1, -3.0))
	for i in range(300):
		cat.set("_roam_cd", 999.0)
		await get_tree().physics_frame
	_ok(cat.global_position.y < perch_deck + 0.25 and int(cat.get("_state")) != 12,
		"...and a player who walks off takes it straight back off the crate (y %.2f, state %d)"
			% [cat.global_position.y, int(cat.get("_state"))])
	perch_crate.queue_free()
	await get_tree().physics_frame
	# PUT THE WORLD BACK — the trap this file records three times already.
	cat.global_position = Vector3(-22.0, 18.05, 11.0)
	cat.call("_reseat")
	cat.call("_end_idle")
	cat.set("_roam_cd", 999.0)
	player.global_position = Vector3(-22.0, 18.1, 12.0)
	for i in range(30):
		await get_tree().physics_frame

	# 7f. IT DOES NOT SPIN WHILE IT IS SITTING DOWN.
	#
	# Owner, verbatim: "Dont have cat spin when sitting, has to look around, or get up to
	# turn." `_face` lerped `rotation.y` in every state, so a seated cat tracked the player by
	# rotating on the spot at TURN_RATE with four paws welded to the deck — the same turntable
	# the walk was cured of, wearing a different hat.
	#
	# Three separate claims, three separate measurements, because a single "did it turn" gate
	# passes an animal that is frozen as happily as one that behaves:
	#   * a SMALL bearing change is answered by the HEAD and not by the body;
	#   * and the head really does answer it — otherwise "the body did not turn" is satisfied
	#     by a cat that has stopped noticing you, which is worse than the bug;
	#   * a LARGE one gets it up on its feet, through the rig's own rise/sit_pre grammar, and
	#     leaves it facing the new bearing.
	# THE PATH UNDER TEST IS THE PETTED SIT, and it is chosen because it is the one a seated
	# animal actually spins on. `grep _face ship_cat.gd` finds exactly three seated callers —
	# the pre-friend `_groom` greeting, `_on_touched`, and the PET branch of `_companion` — and
	# the settled sit of a friendly cat calls it nowhere at all. Testing the settled sit would
	# therefore have asserted "the body did not turn" about a code path that never turned it:
	# green, vacuous, and blind to the defect the owner reported. PET is also the harder case,
	# because `_idle_attention` returns early while a hand is on the animal, so it is where
	# "the head takes over" has to be true by construction rather than by luck.
	cat.global_position = Vector3(3.0, 18.0, -3.0)
	cat.call("_reseat")
	cat.call("_end_idle")
	cat.set("_stayed", false)
	cat.set("_wash_t", 0.0)
	cat.set("_still", 0.0)
	cat.set("_was_asleep", false)
	cat.set("_restand_cd", 0.0)
	cat.rotation.y = 0.0
	var spin_hold := func() -> void:
		cat.set("_hunt_cd", 999.0)
		cat.set("_zoom_cd", 999.0)
		cat.set("_play_cd", 999.0)
		cat.set("_idle_cd", 999.0)
		cat.set("_roam_cd", 999.0)
		cat.set("_wash_cd", 999.0)
		cat.set("_pet_t", 0.9)       # a hand kept on it, so PET owns the animal throughout
	# The player is placed on a circle round the animal, and the cat is pointed AT them to
	# begin with, so the bearing under test is exactly the angle this test moves them through
	# rather than whatever the previous section left the yaw at. `_face`'s convention is
	# `atan2(to.x, to.z) + PI`, so a player at bearing t sits at yaw t + PI.
	var spin_c: Vector3 = cat.global_position
	var at_bearing := func(t: float) -> Vector3:
		return spin_c + Vector3(sin(t) * 1.4, 0.1, cos(t) * 1.4)
	cat.rotation.y = PI
	player.global_position = at_bearing.call(0.0)
	for i in range(120):
		spin_hold.call()
		await get_tree().physics_frame
	_ok(int(cat.get("_state")) == 6,
		"the cat is seated and being petted before the spin test (state %d)"
			% int(cat.get("_state")))
	# A 40-degree step — inside SEAT_ARC (60), so it must be answered by the neck alone.
	var yaw0: float = cat.rotation.y
	var skel: Skeleton3D = null
	for n in (cat.get("_host") as Node3D).find_children("*", "Skeleton3D", true, false):
		skel = n
		break
	var head_i: int = skel.find_bone("Head") if skel != null else -1
	var head0: Vector3 = Vector3.ZERO
	if head_i >= 0:
		head0 = (skel.global_transform * skel.get_bone_global_pose(head_i)).basis * Vector3(0, 1, 0)
		head0 = cat.global_transform.basis.inverse() * head0    # in the cat's OWN frame
	var body_rate_max: float = 0.0
	var yaw_prev: float = cat.rotation.y
	var near_at: Vector3 = at_bearing.call(0.70)      # 40 deg, inside SEAT_ARC's 60
	for i in range(180):
		spin_hold.call()
		player.global_position = near_at
		await get_tree().physics_frame
		body_rate_max = maxf(body_rate_max,
			absf(angle_difference(yaw_prev, cat.rotation.y)) * 60.0)
		yaw_prev = cat.rotation.y
	var body_turn: float = absf(rad_to_deg(angle_difference(yaw0, cat.rotation.y)))
	var head_turn: float = 0.0
	if head_i >= 0:
		var h1: Vector3 = (skel.global_transform * skel.get_bone_global_pose(head_i)).basis \
			* Vector3(0, 1, 0)
		h1 = cat.global_transform.basis.inverse() * h1
		head_turn = rad_to_deg(Vector2(head0.x, head0.z).angle_to(Vector2(h1.x, h1.z)))
	_ok(body_turn < 5.0,
		"a seated cat does NOT spin to track you (body yaw moved %.1f deg, peak %.1f deg/s)"
			% [body_turn, rad_to_deg(body_rate_max)])
	_ok(absf(head_turn) > 8.0,
		"...it turns its HEAD instead (head yaw in the body frame moved %.1f deg)" % head_turn)
	# ...and now put the player somewhere a neck cannot reach: 150 degrees round.
	cat.set("_restand_cd", 0.0)
	var far_at: Vector3 = at_bearing.call(2.62)       # 150 deg — no neck reaches that
	var rose: bool = false
	var yaw_before: float = cat.rotation.y
	for i in range(420):
		spin_hold.call()
		player.global_position = far_at
		await get_tree().physics_frame
		if float(cat.get("_restand_t")) > 0.0:
			rose = true
	var want_yaw: float = atan2(far_at.x - cat.global_position.x,
		far_at.z - cat.global_position.z) + PI
	_ok(rose, "a bearing a neck cannot reach makes it GET UP to turn (restand fired)")
	_ok(absf(rad_to_deg(angle_difference(yaw_before, cat.rotation.y))) > 60.0
			and absf(rad_to_deg(angle_difference(cat.rotation.y, want_yaw))) < 25.0,
		"...and it ends up facing the new bearing, sitting (turned %.1f deg, off by %.1f, state %d)"
			% [absf(rad_to_deg(angle_difference(yaw_before, cat.rotation.y))),
				absf(rad_to_deg(angle_difference(cat.rotation.y, want_yaw))),
				int(cat.get("_state"))])
	_ok(float(cat.get("_restand_t")) <= 0.0
			and String(cat.get("_rig").get("_target")) == "sit",
		"...and it is back down in the seat it got up from, not left standing (state %d, pose %s)"
			% [int(cat.get("_state")), String(cat.get("_rig").get("_target"))])
	cat.set("_pet_t", 0.0)
	cat.call("_end_idle")
	cat.global_position = Vector3(-22.0, 18.05, 11.0)
	cat.call("_reseat")
	player.global_position = Vector3(-22.0, 18.1, 12.0)
	for i in range(30):
		await get_tree().physics_frame

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

	# ------------------------------------------------------- THE OTHER ONE THAT WAS MISSING
	#
	# THE CAT USED TO WALK ON THE WATER, and `ship_cat.gd` had exactly ONE water-aware line in
	# 2600 (the trail recorder's). `_reseat` had no `else` branch: when its ray found nothing
	# it silently kept the previous height, and over open sea the ray ALWAYS finds nothing —
	# the ocean surface is a shader-displaced visual mesh with no collider. So a cat that left
	# the deck horizontally stood at DECK_Y 18.0 above the swell, permanently frozen, because
	# every recovery path also fails open out there: `_walk_toward` gets an empty deck hit and
	# returns, `_unbury` finds nothing to push out of, and `_reseat` holds the height.
	#
	# MEASURED AGAINST THE SWIM LINE, NOT AGAINST A NUMBER. `Gyre.swim_line` is the same
	# source of truth the player, main.gd and underwater_fx use, and it MOVES — so the
	# boarding lip below is sized from the range this spot's surface actually covers rather
	# than from a hand-typed height, which is the standing rule in this repo.
	var sea := Vector3(0.0, 18.0, 168.0)
	var surf_lo: float = 1e9
	var surf_hi: float = -1e9
	for i in range(24):
		await get_tree().physics_frame
		var s: float = Gyre.swim_line(Vector2(sea.x, sea.z), Gyre.water_time())
		surf_lo = minf(surf_lo, s)
		surf_hi = maxf(surf_hi, s)
	# Prove the spot really is open water before drawing any conclusions from it: nothing
	# solid anywhere under the drop point, which is precisely the condition `_reseat` used to
	# fail open on.
	var vq := PhysicsRayQueryParameters3D.create(sea, sea - Vector3(0, 60.0, 0))
	vq.collision_mask = 1
	vq.collide_with_areas = false
	var empty_below: bool = cat.get_world_3d().direct_space_state.intersect_ray(vq).is_empty()
	_ok(empty_below,
		"the drop point is genuinely open sea (swim line %.2f..%.2f, nothing solid for 60 m below)"
			% [surf_lo, surf_hi])

	# A BOARDING LIP, BUILT rather than hunted for — the same reasoning as the leap crate, and
	# it FLOATS. A fixed height cannot work here and the arithmetic says so: the lip must stand
	# clear of the sea (> swim line + 0.1, or `_find_board` correctly calls it a submerged
	# shelf) AND stay inside one JUMP_UP of a cat riding at swim line - SWIM_SINK, so the swell
	# range has to be under ~1.03 m for any constant to satisfy both. Measured at this spot it
	# is not — a 24-frame sample read 1.17..1.94 and the run then spent minutes at ~0.60. So
	# the dock rides the swell like a real pontoon and the test measures the CAT instead of the
	# sea state it happened to start in.
	const LIP_FREEBOARD: float = 0.7
	var lip_top: float = surf_hi + LIP_FREEBOARD
	var pontoon := StaticBody3D.new()
	var pcs := CollisionShape3D.new()
	var pbox := BoxShape3D.new()
	pbox.size = Vector3(4.0, 0.5, 4.0)
	pcs.shape = pbox
	pontoon.add_child(pcs)
	get_tree().current_scene.add_child(pontoon)
	pontoon.global_position = Vector3(sea.x, lip_top - 0.25, sea.z)
	# Drop it in over open water, 2.6 m clear of the lip, at DECK HEIGHT — which is exactly the
	# state the bug left the animal in.
	# Far enough out that it has to actually SWIM there: the lip's near edge is 2 m from the
	# pontoon's centre, so this is 5 m of open water to cross.
	cat.global_position = Vector3(sea.x, sea.y, sea.z - 7.0)
	player.global_position = Vector3(sea.x, lip_top + 0.1, sea.z)
	cat.set("_hunt_cd", 999.0)
	cat.set("_zoom_cd", 999.0)
	cat.set("_play_cd", 999.0)
	var fell_in: bool = false
	var swam: bool = false
	var swam_frames: int = 0
	var worst_under: float = 0.0      # deepest the BODY ever got below the swim line
	var boarded: bool = false
	var swum_m: float = 0.0
	var last_xz: Vector2 = Vector2(cat.global_position.x, cat.global_position.z)
	for i in range(2400):
		await get_tree().physics_frame
		# The dock rides the swell — see LIP_FREEBOARD. Set from the sea under the PONTOON, not
		# under the cat, because that is what a floating thing does.
		lip_top = Gyre.swim_line(Vector2(sea.x, sea.z), Gyre.water_time()) + LIP_FREEBOARD
		pontoon.global_position = Vector3(sea.x, lip_top - 0.25, sea.z)
		var s2: float = Gyre.swim_line(
			Vector2(cat.global_position.x, cat.global_position.z), Gyre.water_time())
		if int(cat.get("_state")) == 14:
			swum_m += last_xz.distance_to(Vector2(cat.global_position.x, cat.global_position.z))
		last_xz = Vector2(cat.global_position.x, cat.global_position.z)
		if cat.global_position.y < sea.y - 1.0:
			fell_in = true
		if int(cat.get("_state")) == 14:
			swam = true
			swam_frames += 1
			worst_under = maxf(worst_under, s2 - cat.global_position.y)
		# ON THE LIP, NOT OVER IT. Read only on frames the animal is neither winding up nor
		# airborne — the boarding leap passes through exactly this height on its way, so a
		# check that does not exclude the flight photographs the jump and calls it a landing
		# (measured: it reported y 1.63 against a 1.91 lip, i.e. still 0.28 m short and
		# rising).
		if swam and float(cat.get("_jump_t")) <= 0.0 and float(cat.get("_jump_wind")) <= 0.0 \
				and cat.global_position.y > lip_top - 0.10 and int(cat.get("_state")) != 14:
			boarded = true
			break
	_ok(fell_in, "a cat over open sea does NOT stand at deck height (fell to y %.2f from 18.00)"
		% cat.global_position.y)
	_ok(swam and swum_m > 2.0,
		"...it ends up in the water and SWIMS for it (%d frames in SWIM, %.1f m paddled)"
			% [swam_frames, swum_m])
	_ok(worst_under < 0.9,
		"...riding the surface rather than sinking (worst %.2f m under the swim line)"
			% worst_under)
	_ok(boarded, "...and it climbs back out ONTO the lip (settled y %.2f, lip top %.2f)"
		% [cat.global_position.y, lip_top])
	# PUT THE WORLD BACK — the trap this file records twice already.
	pontoon.queue_free()
	await get_tree().physics_frame
	cat.global_position = Vector3(-22.0, 18.05, 11.0)
	cat.call("_reseat")
	player.global_position = Vector3(-22.0, 18.1, 12.0)
	for i in range(20):
		await get_tree().physics_frame
	_completed = true
