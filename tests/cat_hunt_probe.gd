extends Node
## THE CAT'S NEW BEHAVIOUR, AS ASSERTIONS — the predatory sequence, the gift, the zoomies,
## object play, and the stretch on waking.
##
## Separate from CatProbe on purpose. CatProbe is the stable regression suite for the animal's
## contract (it exists, it befriends, it follows, it never ends up inside the rig) and it is
## the thing run twenty times in a row when something looks intermittent; bolting a fifteen-
## beat hunt onto it would triple that cost and couple two unrelated failure modes. This one
## drives the deck instead of the bunkhouse, because that is where the gulls are.
##
##   godot --headless --path . res://tests/CatHuntProbe.tscn

var failures: int = 0
var _completed: bool = false
var _cat: Node3D
var _player: Node3D

func _ready() -> void:
	add_child(load("res://scenes/Main.tscn").instantiate())
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

## The cat's body volume against the RIG, using the movement code's own sphere query — a ray
## cannot do this (a ray whose origin is already inside a shape reports nothing), which is the
## documented trap that let the s36 cat sit in a bulkhead undetected.
##
## AGAINST THE RIG, and that qualifier is load-bearing here. The first cut excluded only what
## `_walk_skip` excludes, which does not include other animals — so the instant the cat landed
## a successful pounce it was overlapping the gull by 801 mm and the probe reported the cat
## buried in the world. A test that fails when the feature works is worse than no test: the
## whole point of a pounce is to land ON the bird. Every fauna collider is excluded, so what is
## left is steel.
func _fauna_skip() -> Array[RID]:
	var out: Array[RID] = _cat.call("_walk_skip")
	var bf: Node = _cat.get_tree().get_first_node_in_group("bloom_fauna")
	if bf != null:
		for c in bf.find_children("*", "CollisionObject3D", true, false):
			out.append((c as CollisionObject3D).get_rid())
	return out

func _buried() -> float:
	var sphere := SphereShape3D.new()
	sphere.radius = float(_cat.call("_body_r"))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _fauna_skip()
	q.transform = Transform3D(Basis.IDENTITY, _cat.global_position + Vector3(0, sphere.radius + 0.04, 0))
	var pairs: PackedVector3Array = _cat.get_world_3d().direct_space_state.collide_shape(q, 4)
	var worst: float = 0.0
	for i in range(0, pairs.size() - 1, 2):
		worst = maxf(worst, (pairs[i] - pairs[i + 1]).length())
	return worst

func _run() -> void:
	_cat = get_tree().get_first_node_in_group("ship_cat")
	_player = get_tree().get_first_node_in_group("player")
	_ok(_cat != null and _player != null, "there is a cat and a player")
	if _cat == null or _player == null:
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	for c in _cat.get_children():
		if c is Interactable:
			(c as Interactable).interact("SAY HELLO", _player)

	# THE BIRDS ARE FINDABLE. The hunt looks its prey up by group, so an ungrouped gull is a
	# cat that never hunts — and nothing else in the suite would notice.
	var gulls: Array = get_tree().get_nodes_in_group("deck_gull")
	_ok(gulls.size() >= 2, "the deck gulls are in a group the cat can find (%d)" % gulls.size())
	var gull: Node3D = null
	for g in gulls:
		if (g as Node3D).global_position.y > 17.0:
			gull = g
			break
	_ok(gull != null, "at least one gull is up on the topside deck where the cat lives")
	if gull == null:
		_completed = true
		return

	# ---- THE PREDATORY SEQUENCE. Put the cat six metres off with the player alongside, and
	# watch which states it visits on its own. Nothing is forced: `_find_prey` has to see the
	# bird, the stalk has to close, and the tread has to fire the leap.
	# STAGE IT SOMEWHERE THE CAT CAN ACTUALLY STALK FROM, and prove that before asserting on
	# the behaviour. The first cut dropped the animal at one hard-coded bearing 6 m out; it
	# landed on a different deck level, `_find_prey`'s CLIMB_UP check correctly refused a bird
	# it could not reach, and the probe reported "it does not stalk" about a cat that was
	# behaving perfectly. A staging failure that reads as a behaviour failure is worse than no
	# test at all, so the bearing is chosen by trying several and the height is ASSERTED.
	var placed := false
	for bearing in [Vector3(1, 0, 0.4), Vector3(-1, 0, 0.4), Vector3(0.4, 0, 1),
			Vector3(0.4, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var dir: Vector3 = (bearing as Vector3).normalized()
		_cat.global_position = gull.global_position + dir * 4.5
		_cat.call("_reseat")
		await get_tree().physics_frame
		if absf(_cat.global_position.y - gull.global_position.y) < 0.6 \
				and bool(_cat.call("_step_clear", _cat.global_position, dir)):
			_player.global_position = _cat.global_position + dir * 1.5
			placed = true
			break
	_ok(placed, "the cat can be staged on the gull's own deck, 4.5 m off (cat y %.2f, gull y %.2f)"
		% [_cat.global_position.y, gull.global_position.y])
	if not placed:
		_completed = true
		return
	_cat.set("_hunt_cd", 0.0)
	_cat.set("_play_cd", 999.0)      # so a PLAY pounce cannot be mistaken for a hunt one
	_cat.set("_zoom_cd", 999.0)
	var seen := {}
	var worst_bury: float = 0.0
	var worst_at: String = "-"
	var stalked_slowly: bool = false
	var min_gap: float = 1e9
	# WATCHED DURING THE SWEEP, not after it. The aftermath is a few seconds long and the
	# pounce can land at any point in a 45-second window, so polling for it afterwards asks
	# whether the cat is STILL washing — which it usually is not, and the first cut of this
	# failed for exactly that reason while the behaviour was working perfectly.
	var resolved: bool = false
	for i in range(1400):
		await get_tree().physics_frame
		seen[int(_cat.get("_state"))] = true
		var b: float = _buried()
		if b > worst_bury:
			worst_bury = b
			worst_at = "%s state=%d hunt=%d jump=%.2f" % [
				str(_cat.global_position.snappedf(0.01)), int(_cat.get("_state")),
				int(_cat.get("_hunt")), float(_cat.get("_jump_t"))]
		if String(_cat.get("_carry")) != "" or float(_cat.get("_after_t")) > 0.0:
			resolved = true
		if int(_cat.get("_hunt")) == 1:
			# A stalk is SLOWER than a walk. If it closes at follow speed it is not a stalk,
			# it is the cat walking at a bird with a different pose on.
			stalked_slowly = stalked_slowly or float(_cat.get("_last_speed")) <= 0.9
		min_gap = minf(min_gap, _cat.global_position.distance_to(gull.global_position))
	_ok(seen.has(8), "it STALKS the gull (state 8) — the sequence starts on its own")
	_ok(stalked_slowly, "...and the stalk is a creep, not a walk (speed <= 0.9 m/s at some point)")
	_ok(min_gap < 2.6, "...it actually closed on the bird (nearest %.2f m)" % min_gap)
	_ok(seen.has(9), "it POUNCES (state 9) — the tread fires a real leap")
	_ok(worst_bury <= 0.0005,
		"a hunt never puts the cat inside the rig (worst overlap %.0f mm at %s)"
			% [worst_bury * 1000.0, worst_at])

	# ---- THE AFTERMATH. It either caught something (and is carrying it) or it missed (and is
	# washing). Both are correct; having done NEITHER is not, and that is the assertion.
	_ok(resolved, "a resolved hunt leaves it either carrying a prize or washing off the miss")

	# ---- THE GIFT. Force the carry so this is deterministic — the catch is a 1-in-3 roll and
	# a probe that depends on dice is a probe that fails one run in three.
	var fish_before: int = PlayerState.count_item("gull_feather")
	_cat.set("_after_t", 0.0)
	_cat.set("_carry", "gull_feather")
	_player.global_position = _cat.global_position + Vector3(3.0, 0.0, 0.0)
	var gifted: bool = false
	for i in range(300):
		await get_tree().physics_frame
		if PlayerState.count_item("gull_feather") > fish_before:
			gifted = true
			break
	_ok(gifted, "it brings what it caught to the player and puts it down")
	_ok(String(_cat.get("_carry")) == "", "...and stops carrying it once delivered")

	# ---- THE STRETCH ON WAKING. Sleep it, wake it, and it must stretch before it walks —
	# not stand straight up like a machine coming out of standby.
	_cat.set("_carry", "")
	_player.global_position = _cat.global_position + Vector3(1.2, 0.0, 0.0)
	_player.set("_lying", true)
	_player.set("_lying_sleeping", true)
	var slept: bool = false
	for i in range(500):
		await get_tree().physics_frame
		if String(_cat.get("_pose")) == "sleep":
			slept = true
			break
	_ok(slept, "it curls up when the player turns in (pose %s)" % str(_cat.get("_pose")))
	_player.set("_lying", false)
	_player.set("_lying_sleeping", false)
	var stretched: bool = false
	for i in range(200):
		await get_tree().physics_frame
		if String(_cat.get("_pose")) == "stretch":
			stretched = true
			break
	_ok(stretched, "and it STRETCHES on waking rather than standing straight up")

	# ---- THE ZOOMIES STAY NEAR YOU. A burst that random-walks off across the rig is a cat
	# leaving, and "it settles rather than circling when you rest" is a contract this animal
	# has kept since s34.
	_cat.set("_zoom_cd", 0.0)
	_cat.set("_still", 9.0)
	_cat.set("_hunt_cd", 999.0)
	_cat.set("_play_cd", 999.0)
	var far: float = 0.0
	for i in range(600):
		await get_tree().physics_frame
		far = maxf(far, _cat.global_position.distance_to(_player.global_position))
		worst_bury = maxf(worst_bury, _buried())
	_ok(far < 7.0, "the zoomies orbit the player rather than leaving (furthest %.1f m)" % far)
	_ok(worst_bury <= 0.0005,
		"and nothing in the new behaviour ever buries the cat (worst %.0f mm)" % (worst_bury * 1000.0))
	_completed = true
