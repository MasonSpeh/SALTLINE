extends Node
## SPEAR PROBE — does spearfishing actually take the fish you aimed at, and does the water
## react like water?
##
## Spearfishing (s27) is the rod's opposite verb: instead of standing on the plating and
## letting FishTable roll an anonymous catch out of the water below, you swim in and pick an
## individual out of a real shoal. That means the thing to test is not "does a roll produce a
## species" (CatchProbe already owns that) but the parts unique to the spear:
##
##   1. the aim query finds a fish that IS in front of the player, and
##   2. refuses one that is not — a thrust at open water must miss;
##   3. taking a fish leaves the pod's member ARRAYS intact (they are parallel and indexed in
##      lockstep, so a take that removed an entry would silently put one fish on another's
##      swim personality) while removing the FISH — s47: a speared fish must go invisible,
##      become untargetable, and stop being shoved about by scatter_fish;
##   4. the whole player-facing path — spear in hand, head under the swell, left click —
##      actually banks a fish item, and spends the breath a lunge costs;
##   5. THE NERF (s47, owner: "make spearfishing less OP. Fish need to swim away from player
##      when they come too close, or swim away fast whenever spear is used to kill a fish,
##      and then disappear once they have been speared (respawns somewhere else later)"):
##        a. a shoal the player stands next to keeps its distance (the proximity standoff),
##        b. a thrust puts the pod on full alarm and it LEAVES,
##        c. a speared fish comes back, later, somewhere else;
##   6. the deck behaviour is UNCHANGED: the same spear above water is still the melee swing,
##      because that regression would be invisible until a crab reached someone.
##
## Headless is correct here. The shoals are plain Node3Ds moved analytically by script, so
## every position this reads is real without drawing anything (unlike the MultiMesh transform
## trap in docs/AGENT_TRAPS.md, which is instance data living in the RenderingServer).
##
## Run: godot --headless --path . res://tests/SpearProbe.tscn

const AIB := preload("res://scripts/world/ai_budget.gd")

var failures: int = 0
var _completed: bool = false
var _main: Node

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	# The schools spawn in underwater_world._ready, but the props/rig stream in for a while
	# after; a few frames is enough for the fish to exist and be seated.
	for i in range(8):
		await get_tree().process_frame
	await _run()
	# A SCRIPT ERROR INSIDE _run() ABANDONS THE COROUTINE AND RETURNS HERE QUIETLY, and the
	# report would then read "FAILURES: 0" over a run that stopped a third of the way through
	# — the exact vacuous pass docs/AGENT_TRAPS.md warns about (it bit this probe on its first
	# run, at a mistyped PlayerState property). _run sets this on its last line; anything else
	# is a failure regardless of what the checks above said.
	if not _completed:
		print("FAIL  the probe ran to completion (it did NOT — see the SCRIPT ERROR above)")
		failures += 1
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _ok(cond: bool, msg: String) -> void:
	print("%s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		failures += 1

## THE WORLD IS STEPPED BY HAND for every dynamic check below, because a headless frame's
## delta is a millisecond or two and the s47 behaviour lives on second-scale time constants
## (SHOAL_ALARM_FALL is 0.40/s, i.e. a 2.5 s memory). `uw.set_process(false)` plus a direct
## `_process(dt)` call is exact, fast, and — crucially — the only way to give the pods a
## KNOWN amount of game time rather than however much the machine happened to deliver.
##
## dt is 0.05 rather than a frame's worth on purpose. `_pod_due` phases pods off
## `Engine.get_process_frames()`, which does NOT advance during a hand-driven loop, so a
## decimated pod would never come due on the frame test alone — but `acc >= AiBudget.MAX_STEP`
## (0.15) always forces one, so a pod here ticks every third call with all 0.15 s handed over.
## That is the accumulator doing exactly the job ai_budget.gd exists to do, and it conserves
## game time by construction; it just means the effective resolution is 0.15 s, not 0.05.
##
## `hold` >= 0 parks the player that many metres from the pod's WANDER position (its centre
## with the flee displacement taken back off) on every call. Without it the shoal's own drift
## carries it out of `skit` inside a few seconds and the alarm decays for reasons that have
## nothing to do with the thing being measured.
func _step(uw: Node, player: Node3D, secs: float, pod: Dictionary = {}, hold: float = -1.0) -> void:
	var dt: float = 0.05
	for i in range(int(round(secs / dt))):
		if hold >= 0.0 and not pod.is_empty():
			var home: Vector3 = (pod["centre"] as Vector3) - (pod["flee"] as Vector3)
			# -1.6 puts the HEAD (and so the camera, and so `_cam_eye`) on the pod's plane.
			player.global_position = home + Vector3(0.0, -1.6, hold)
		uw.call("_process", dt)

## Nearest VISIBLE member of `pod` to `eye`, metres — the number the spear actually cares
## about, since `spear_target` refuses anything hidden.
func _nearest_visible(pod: Dictionary, eye: Vector3) -> float:
	var best: float = 1.0e9
	for f in pod["fish"]:
		if not is_instance_valid(f) or not (f as Node3D).visible:
			continue
		best = minf(best, eye.distance_to((f as Node3D).global_position))
	return best

func _run() -> void:
	var uw: Node = get_tree().get_first_node_in_group("underwater_world")
	if uw == null:
		_ok(false, "underwater_world registered itself in its group")
		return
	_ok(true, "underwater_world found via its group")
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		_ok(false, "player found")
		return

	# GET THE PLAYER UNDER THE WATER BEFORE ANYTHING ELSE, AND LET THE SHOALS SWIM.
	#
	# underwater_world only advances its schools while the subtree is visible, and the cull
	# keys that off the camera — so on a rig where the player spawns topside, every fish is
	# still stacked at the pod root, which never leaves the WORLD ORIGIN. The first version of
	# this probe queried them there: the aim test "passed" against a fish at (0,0,0) and the
	# head-underwater test then failed because a player parked relative to the origin is
	# sitting in the swell rather than beneath it. A fish that has not been seated is not a
	# fish, so drop the camera under and give the pods real frames first.
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector3(0.0, -10.0, 0.0)
	for i in range(14):
		await get_tree().process_frame

	var schools: Array = uw.get("_schools")
	if schools == null or schools.is_empty():
		_ok(false, "schools spawned")
		return
	_ok(true, "schools spawned (%d pods)" % schools.size())
	_ok(uw.visible, "the cull shows the underwater world with the camera under the swell")
	_ok(AIB.enabled, "AI decimation is on, so the hand-driven steps below go through _pod_due")

	# Now freeze it, so a pod cannot swim out from under the query between one call and the
	# next. Everything from here to section 5 is measured on a stopped world; section 5 drives
	# it again by hand (see _step).
	uw.set_process(false)
	uw.visible = true

	# Pick a pod that is in the water right now (species keep active hours), has members, and
	# has actually been SEATED — see above. Asserting the pod is off the origin is what stops
	# this probe passing over an unseated world a second time.
	var target: Dictionary = {}
	for s in schools:
		var root: Node3D = s["root"]
		if not root.visible:
			continue
		var members: Array = s["fish"]
		if members.is_empty():
			continue
		if (members[0] as Node3D).global_position.length() < 1.0:
			continue      # still stacked at the origin — not swimming yet
		target = {"school": s, "fish": members[0]}
		break
	if target.is_empty():
		_ok(false, "found a live, SEATED pod to aim at (all pods still at the origin?)")
		return
	_ok(true, "found a live, seated pod %.1f m off the origin"
		% (target["fish"] as Node3D).global_position.length())
	var fish: Node3D = target["fish"]
	var school: Dictionary = target["school"]
	# THE SANITY GATE, ASSERTED SEPARATELY FROM THE MEMBER POSITION. The member read above and
	# the pod CENTRE are two different values — a pod whose centre is still at its spawn seed
	# would drive every flee measurement in section 5 off a shoal that has never moved, and
	# the arithmetic would look perfectly healthy while measuring nothing.
	var centre0: Vector3 = school["centre"]
	_ok(centre0.length() > 1.0,
		"the pod CENTRE is off the world origin (%.1f m) — flee measurements are real"
		% centre0.length())
	var fish_pos: Vector3 = fish.global_position
	var species: String = String(school["id"])
	var before: int = (school["fish"] as Array).size()

	# Stand off 1.5 m and look straight at it.
	var eye: Vector3 = fish_pos + Vector3(0, 0, 1.5)
	var aim: Vector3 = (fish_pos - eye).normalized()
	var hit: Dictionary = uw.spear_target(eye, aim, 3.0)
	_ok(not hit.is_empty(), "aim query finds a fish 1.5 m ahead (%s)" % species)
	if not hit.is_empty():
		_ok(String(hit["id"]) == species, "it is the pod's own species (%s)" % String(hit["id"]))

	# 2. The same fish, from the same distance, with the aim pointed the other way.
	var away: Dictionary = uw.spear_target(eye, -aim, 3.0)
	# NOT "finds nothing" — "does not find THIS fish". The first version asserted an empty
	# result, which quietly depended on the water behind the camera being empty; s30 added
	# eleven species and a pod drifted into that space, so the check failed over a spear cone
	# that works perfectly. The property being tested is that the cone rejects what is behind
	# you, and a different fish genuinely in range ahead of the reversed aim is a real hit.
	_ok(away.is_empty() or away["node"] != hit.get("node"),
		"a thrust aimed away does not take the fish behind it (%s)"
		% ("nothing in range" if away.is_empty() else "found a different fish"))

	# ...and out of reach.
	var far_eye: Vector3 = fish_pos + Vector3(0, 0, 40.0)
	var far: Dictionary = uw.spear_target(far_eye, (fish_pos - far_eye).normalized(), 3.0)
	_ok(far.is_empty(), "a fish 40 m away is out of a 3 m thrust")

	# 3. TAKING IT MUST REMOVE THE FISH AND NOT THE ARRAY ENTRY.
	#
	# THE FISH THAT GETS SPEARED IS THE ONE `spear_target` PICKED, WHICH IS NOT `members[0]`.
	# The aim above is pointed AT members[0], but the query answers with the nearest member in
	# the cone and a 23-fish sprat pod has several inside 1.5 m — measured, it comes back with
	# a different index most runs. The first version of this section asserted `members[0]` had
	# gone invisible and failed over a despawn that was working perfectly, on a fish it had
	# never speared. Carry the node and index the query actually returned.
	var speared: Node3D = null
	var speared_i: int = -1
	if not hit.is_empty():
		speared = hit["node"]
		speared_i = int(hit["index"])
		var taken: Dictionary = uw.take_speared(hit)
		_ok(not taken.is_empty() and String(taken.get("id", "")) == species,
			"take_speared hands back the species (%s)" % String(taken.get("id", "?")))
		var after: int = (school["fish"] as Array).size()
		_ok(after == before, "pod population intact after a take (%d -> %d)" % [before, after])
		# The parallel per-member arrays must still line up with it, or a later frame puts one
		# fish on another's phase/speed. `seat` and `gone` are in that set too — `gone` is the
		# s47 addition and it is the one this section is about.
		for key in ["ph", "spd", "head", "climb", "seat", "gone"]:
			_ok((school[key] as Array).size() == after,
				"member array '%s' still matches the pod (%d)" % [key, (school[key] as Array).size()])
		# ...and the FISH is out of the water. Before s47 this line re-seated the member at
		# `s["centre"]` — one to three metres down the player's own look vector, inside reach
		# and inside the cone — so the fish just banked was legal again on the next frame.
		_ok(not speared.visible,
			"the speared fish (member %d) is no longer in the water (visible == false)"
			% speared_i)
		var gone_t: float = float((school["gone"] as Array)[speared_i])
		_ok(gone_t >= 45.0 and gone_t <= 100.0,
			"it is away for a real interval (%.1f s, expected 45-100)" % gone_t)
		var again: Dictionary = uw.spear_target(eye, aim, 3.0)
		_ok(again.is_empty() or again["node"] != speared,
			"the same thrust cannot take it a second time (%s)"
			% ("nothing in range" if again.is_empty() else "found a different fish"))
		# scatter_fish had no visibility test at all before s47 — a latent bug that only bites
		# once fish can be hidden, which is exactly what this session made possible.
		var held: Vector3 = speared.global_position
		uw.scatter_fish(held, 8.0, 2.0)
		_ok(speared.global_position.is_equal_approx(held),
			"scatter_fish leaves a speared fish alone instead of shoving it about in the dark")
	if speared == null:
		_ok(false, "a fish was speared, so the despawn/respawn sections have something to read")
		return

	# 4. THE WHOLE PLAYER-FACING PATH. Spear in hand, head under the swell, left click.
	PlayerState.add_item("crude_spear")
	var slot: int = -1
	for i in range(PlayerState.hotbar.size()):
		if String(PlayerState.hotbar[i]) == "crude_spear":
			slot = i
			break
	_ok(slot >= 0, "crude_spear reached the hotbar")
	if slot >= 0:
		PlayerState.selected_hotbar = slot
	_ok(bool(PlayerState.items.get("crude_spear", {}).get("spearfishing", false)),
		"crude_spear is flagged as a spearfishing tool in items.json")

	# Put the player where the fish are. Physics is already off so nothing fights the teleport,
	# which also means the oxygen drain is not running and the breath cost can be read cleanly.
	# Any member still IN the water — not simply `members[1]`, which after s47 may be the one
	# that was just speared and is therefore invisible, untargetable, and a guaranteed miss.
	var live: Node3D = fish
	for f in (school["fish"] as Array):
		if is_instance_valid(f) and (f as Node3D).visible:
			live = f
			break
	_ok(live.visible, "found a member still in the water to thrust at")
	var lp: Vector3 = live.global_position
	player.global_position = lp + Vector3(0, -1.6, 1.6)
	await get_tree().process_frame
	_ok(bool(player.call("_head_underwater")), "the player's head reads as under the swell")

	# Aim the camera at the fish and thrust.
	var cam: Camera3D = player.get_node_or_null("Head/Camera3D")
	if cam == null:
		_ok(false, "player camera found")
		return
	cam.look_at(live.global_position, Vector3.UP)

	# The prompt is the only thing that tells a player this verb exists — it has no binding of
	# its own, it is the melee button behaving sensibly underwater. Force the poll (it is rate
	# limited to SPEAR_PROMPT_HZ) and read what the chip would say.
	player.set("_spear_prompt_t", 0.0)
	player.call("_update_spear_prompt", 0.0)
	var line: String = String(player.call("spear_prompt_text"))
	_ok(line.begins_with("[LMB]") and line.contains("Spear"),
		"looking at a fish with a spear offers the thrust (%s)" % line)

	var fish_items_before: int = _fish_items()
	PlayerState.oxygen = 1.0
	player.set("_attack_cd", 0.0)
	player.call("_melee_attack")
	await get_tree().process_frame
	var gained: int = _fish_items() - fish_items_before
	_ok(gained > 0, "a thrust at a fish banked a fish item (pack gained %d)" % gained)
	# A THRUST COSTS BREATH. Before s47 the only cost of a thrust was the second it took, so a
	# 35 s lungful bought as many fish as you could aim at.
	var spent: float = 1.0 - PlayerState.oxygen
	_ok(spent > 0.001, "the lunge spent breath (%.3f of the bar, ~%.1f s of air)"
		% [spent, spent * 35.0])

	# scatter_fish has to actually move water, or a miss is silent.
	var probe_pt: Vector3 = (school["centre"] as Vector3)
	var moved: int = uw.scatter_fish(probe_pt, 8.0, 1.5)
	_ok(moved > 0, "a thrust scatters the shoal around it (%d members moved)" % moved)

	# ------------------------------------------------------------------ 5. THE s47 NERF
	# Everything above is a stopped world. The flee lives on second-scale easings, so from
	# here the world is driven by hand at a known dt (see _step).
	var skit: float = float(school["skit"])
	_ok(skit > 0.5, "the pod carries a flee radius (skit %.1f m for a %.2f m fish)"
		% [skit, float(school["size"])])

	# 5a. THE PROXIMITY STANDOFF. Reset the alarm the thrust above left behind, then park the
	# player half a skit from the pod's wander position and let it settle.
	school["alarm"] = 0.0
	school["flee"] = Vector3.ZERO
	_step(uw, player, 8.0, school, skit * 0.5)
	_ok(uw.visible, "the hand-driven steps kept the camera under the swell (pods still swam)")
	var alarm_near: float = float(school["alarm"])
	var flee_near: float = (school["flee"] as Vector3).length()
	var eye_near: Vector3 = cam.global_position
	var home_near: Vector3 = (school["centre"] as Vector3) - (school["flee"] as Vector3)
	_ok(alarm_near > 0.05,
		"standing half a skit off raises the pod's alarm (%.3f)" % alarm_near)
	_ok(flee_near > 0.5,
		"...and the pod centre stands off from the eye (flee %.2f m)" % flee_near)
	# The property, stated exactly: the centre the fish orbit is FURTHER from the eye than the
	# wander position they would be orbiting if nobody were there.
	_ok(eye_near.distance_to(school["centre"]) > eye_near.distance_to(home_near),
		"the fled centre is further from the eye than the wander centre (%.2f m vs %.2f m)"
		% [eye_near.distance_to(school["centre"]), eye_near.distance_to(home_near)])
	# ...and the standoff is a NERF, not a wall: proximity alone must leave fish inside a
	# 3.0 m thrust, or spearfishing would be impossible rather than harder.
	var reach_near: float = _nearest_visible(school, eye_near)
	_ok(reach_near < 6.0,
		"proximity alone still leaves the shoal huntable (nearest fish %.2f m from the eye)"
		% reach_near)

	# 5b. A THRUST MAKES THE SHOAL LEAVE. Same player position, one thrust's worth of alarm.
	var centre_before: Vector3 = school["centre"]
	var near_before: float = _nearest_visible(school, eye_near)
	uw.scatter_fish(centre_before, 4.5, 1.4)
	_ok(float(school["alarm"]) > 0.9,
		"a thrust puts the pod on full alarm (%.2f)" % float(school["alarm"]))
	# Hold the player still — the shoal has to be the thing that moves.
	var eye_bolt: Vector3 = cam.global_position
	_step(uw, player, 3.0)
	var near_after: float = _nearest_visible(school, eye_bolt)
	var flee_bolt: float = (school["flee"] as Vector3).length()
	_ok(flee_bolt > flee_near + 1.5,
		"the shoal bolts further than the standoff (flee %.2f m -> %.2f m)"
		% [flee_near, flee_bolt])
	_ok(near_after > near_before,
		"3 s after the thrust the nearest fish is further off (%.2f m -> %.2f m)"
		% [near_before, near_after])
	_ok(near_after > 3.3,
		"...and out of the longest spear's reach of 3.3 m (%.2f m)" % near_after)
	# The flee is HORIZONTAL. The swim loop skips the swell clamp and the pontoon-lid clamp for
	# any pod whose ceiling — derived from band_y and the pod's own vertical octaves — cannot
	# reach them, and a flee with a Y term would make both exemptions wrong.
	_ok(absf((school["flee"] as Vector3).y) < 0.0001,
		"the flee carries no vertical term (y %.6f), so the surface exemptions still hold"
		% (school["flee"] as Vector3).y)

	# 5c. THE SPEARED FISH COMES BACK, LATER, SOMEWHERE ELSE.
	#
	# The 45-100 s interval itself is asserted in section 3; driving 45 s of game time through
	# a hand-stepped world is 900 calls for a number already checked, so the countdown is
	# short-circuited here and what is measured is the REJOIN: visible again, and not where it
	# died. The pod has been swimming (and fleeing) throughout, which is the whole reason the
	# position differs.
	var died_at: Vector3 = speared.global_position
	_ok(not speared.visible, "the speared fish is still out of the water 11 s later")
	(school["gone"] as Array)[speared_i] = 0.30
	_step(uw, player, 1.5)
	_ok(speared.visible, "the countdown brings it back into the water")
	var re_d: float = died_at.distance_to(speared.global_position)
	_ok(re_d > 1.0, "...and it rejoins somewhere else (%.2f m from where it died)" % re_d)
	_ok(float((school["gone"] as Array)[speared_i]) == 0.0,
		"the countdown is cleared, so the member swims normally again")
	# It has to be a legal target again, or a shoal would bleed away over a long session.
	var re_eye: Vector3 = speared.global_position + Vector3(0.0, 0.0, 1.2)
	var re_hit: Dictionary = uw.spear_target(re_eye,
		(speared.global_position - re_eye).normalized(), 3.0)
	_ok(not re_hit.is_empty(), "a rejoined fish is spearable again")

	# 6. THE DECK BEHAVIOUR MUST NOT HAVE MOVED. Same spear, head in air -> the melee swing,
	# which takes no fish. This is the regression that would otherwise surface as a crab kill
	# that stopped working.
	player.global_position = Vector3(0.0, 30.0, 0.0)
	await get_tree().process_frame
	_ok(not bool(player.call("_head_underwater")), "30 m up reads as out of the water")
	player.set("_spear_prompt_t", 0.0)
	player.call("_update_spear_prompt", 0.0)
	_ok(String(player.call("spear_prompt_text")) == "",
		"the spear offers no thrust on deck, so the chip stays with the interaction ray")
	var before_deck: int = _fish_items()
	PlayerState.oxygen = 1.0
	player.set("_attack_cd", 0.0)
	player.call("_melee_attack")
	await get_tree().process_frame
	_ok(_fish_items() == before_deck, "the same spear on deck is still the melee swing, no catch")
	_ok(is_equal_approx(PlayerState.oxygen, 1.0),
		"...and a deck swing spends no breath (%.3f)" % PlayerState.oxygen)
	_completed = true

## Everything in the pack whose id names a fish — the spear banks through PlayerState the same
## way the rod does, so this counts the result rather than trusting the call.
func _fish_items() -> int:
	var n: int = 0
	for id in PlayerState.hotbar:
		if id != null and String(id).begins_with("fish_"):
			n += 1
	for id in PlayerState.inventory:
		if id != null and String(id).begins_with("fish_"):
			n += 1
	return n
