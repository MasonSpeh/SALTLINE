extends Node
## SPEAR PROBE — does spearfishing actually take the fish you aimed at?
##
## Spearfishing (s27) is the rod's opposite verb: instead of standing on the plating and
## letting FishTable roll an anonymous catch out of the water below, you swim in and pick an
## individual out of a real shoal. That means the thing to test is not "does a roll produce a
## species" (CatchProbe already owns that) but the parts unique to the spear:
##
##   1. the aim query finds a fish that IS in front of the player, and
##   2. refuses one that is not — a thrust at open water must miss;
##   3. taking a fish leaves the pod's population intact (the member arrays are parallel and
##      indexed in lockstep, so a take that removed an entry would silently put one fish on
##      another's swim personality);
##   4. the whole player-facing path — spear in hand, head under the swell, left click —
##      actually banks a fish item;
##   5. the deck behaviour is UNCHANGED: the same spear above water is still the melee swing,
##      because that regression would be invisible until a crab reached someone.
##
## Headless is correct here. The shoals are plain Node3Ds moved analytically by script, so
## every position this reads is real without drawing anything (unlike the MultiMesh transform
## trap in docs/AGENT_TRAPS.md, which is instance data living in the RenderingServer).
##
## Run: godot --headless --path . res://tests/SpearProbe.tscn

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

	# Now freeze it, so a pod cannot swim out from under the query between one call and the next.
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
	_ok(away.is_empty(), "a thrust aimed away from the fish misses")

	# ...and out of reach.
	var far_eye: Vector3 = fish_pos + Vector3(0, 0, 40.0)
	var far: Dictionary = uw.spear_target(far_eye, (fish_pos - far_eye).normalized(), 3.0)
	_ok(far.is_empty(), "a fish 40 m away is out of a 3 m thrust")

	# 3. Taking it must not change the population.
	if not hit.is_empty():
		var taken: Dictionary = uw.take_speared(hit)
		_ok(not taken.is_empty() and String(taken.get("id", "")) == species,
			"take_speared hands back the species (%s)" % String(taken.get("id", "?")))
		var after: int = (school["fish"] as Array).size()
		_ok(after == before, "pod population intact after a take (%d -> %d)" % [before, after])
		# The parallel per-member arrays must still line up with it, or a later frame puts one
		# fish on another's phase/speed.
		for key in ["ph", "spd", "head", "climb"]:
			_ok((school[key] as Array).size() == after,
				"member array '%s' still matches the pod (%d)" % [key, (school[key] as Array).size()])

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

	# Put the player where the fish are. Physics is already off so nothing fights the teleport.
	var live: Node3D = (school["fish"] as Array)[1] if (school["fish"] as Array).size() > 1 else fish
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
	var fish_items_before: int = _fish_items()
	player.set("_attack_cd", 0.0)
	player.call("_melee_attack")
	await get_tree().process_frame
	var gained: int = _fish_items() - fish_items_before
	_ok(gained > 0, "a thrust at a fish banked a fish item (pack gained %d)" % gained)

	# 5. THE DECK BEHAVIOUR MUST NOT HAVE MOVED. Same spear, head in air -> the melee swing,
	# which takes no fish. This is the regression that would otherwise surface as a crab kill
	# that stopped working.
	player.global_position = Vector3(0.0, 30.0, 0.0)
	await get_tree().process_frame
	_ok(not bool(player.call("_head_underwater")), "30 m up reads as out of the water")
	var before_deck: int = _fish_items()
	player.set("_attack_cd", 0.0)
	player.call("_melee_attack")
	await get_tree().process_frame
	_ok(_fish_items() == before_deck, "the same spear on deck is still the melee swing, no catch")

	# scatter_fish has to actually move water, or a miss is silent.
	var probe_pt: Vector3 = (school["centre"] as Vector3)
	var moved: int = uw.scatter_fish(probe_pt, 8.0, 1.5)
	_ok(moved > 0, "a thrust scatters the shoal around it (%d members moved)" % moved)
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
