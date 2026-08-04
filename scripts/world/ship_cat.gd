extends Node3D
## THE SHIP'S CAT — the one animal on this rig that is company rather than weather.
##
## Every other creature here is indifferent to you at best: the crabs want you off their leg,
## the gulls flush, the seal tolerates a pat. The cat is the only one that CHOOSES you, and the
## whole design follows from that one idea:
##
##   FOUND, not spawned at you. It is in the bunkhouse from the first minute of a run, sitting
##   on the deck washing a paw, and it stays there until somebody says hello. Nothing points at
##   it and nothing announces it — you find it or you don't.
##   ONCE, and then for good. There is no befriending minigame and no trust meter. You reach
##   out, it accepts, and that is the last decision either of you makes about it.
##   IT KEEPS ITS OWN COUNSEL. It follows, but at its own pace and its own distance, and it
##   stops to sit when you stop. A pet that teleports to heel is a HUD element with fur.
##   IT WANTS THE FISH. Hold one and it closes in, tail up, and will not be got rid of.
##
## Kinematic and un-navmeshed, like the crab, per the same brief — it walks the deck it is on
## and does not attempt stairs. That is deliberate: a cat that cannot follow you down a ladder
## is a cat, and one that clips through a bunk frame chasing you is a bug.

const ANIM := preload("res://scripts/world/creature_anim.gd")
const KIT := preload("res://scripts/world/creature_kit.gd")
const AIB := preload("res://scripts/world/ai_budget.gd")
const RIG := preload("res://scripts/world/cat_rig.gd")
const MODEL_PATH := "res://assets/models/fauna/ship_cat/ship_cat.glb"

## ONE MESH PER POSE, BUILT ONCE AND TOGGLED — not swapped through ANIM.replace().
##
## The s32 cat was a single standing mesh doing every state, so "sitting" was a static
## standing cat and "asleep" was a static standing cat leaning over. Tripo generated five
## poses in s34 from one coat description (see gen_cat_batch.py) and the states below drive
## them.
##
## WHY NOT `ANIM.replace()` PER TRANSITION, which is what the brief suggested: replace()
## hides every mesh built BEFORE it, which is the documented trap, but the real problem is
## that it re-instantiates the scene and rebuilds every ShaderMaterial on the frame the cat
## changes its mind — several times a minute, next to the player, on the animal whose whole
## job is to not read as a machine. All six are attached once in _ready and the transition
## is a `visible` flip. Godot does not draw a hidden MeshInstance, so the cost of the five
## that are off is their memory, and they share the cached .glb resources.
##
## `stand` is kept because the s32 mesh is the only one authored on all four feet and level,
## which is what the walk cycle's gait bob is tuned against.
## JUMP is APPENDED, never inserted. CatProbe and the close-out harness assert on the
## integer values of these (state 2 is RUN, state 5 is FISH), so inserting anywhere but the
## end silently re-numbers the states out from under every test that names one.
enum State { GROOM, FOLLOW, RUN, SIT, SLEEP, FISH, PET, JUMP }

## s35: THE RIGGED MESHES, where they exist. Same five poses, same look — Tripo rigged the
## ALREADY-SHIPPING meshes off the task ids s34 logged, and the bind pose photographs
## identically to the static original (tests/out/cat_bind). What is new is 41 bones, which
## is the difference between a cat that changes pose and a cat that MOVES.
## The static paths remain the fallback: a missing rigged asset degrades to the s34 look
## rather than to a crash, which is the same contract every generated species here has.
## `run` is cat_run2, NOT cat_run. The s34 run mesh has its head and shoulders turned —
## the owner's "the cat is looking/turning to the left, so the running straight is
## currently crooked". That is a MESH fault and no amount of yaw fixes it: straightening
## the head by rotating the node would aim the body off the line of travel. s36 re-rolled
## the pose with the head, neck, spine and shoulders named explicitly in the prompt
## (tools/gen_cat_s36.py) and measured the result — the across-body extent fell from 0.488
## to 0.387 of the body length, i.e. the animal genuinely got straighter rather than just
## looking it from one angle.
## s37: ONE MESH, ONE SKELETON — the pose-per-mesh design is gone.
##
## Why it had to go: six separate rigged meshes swapped by a `visible` flip meant every
## state change was a whole-body teleport (one frame walking, the next sitting, nothing
## between), and the gait swung limbs on meshes AUTHORED mid-stride, double-posing the
## legs. That is unfixable by tuning — the architecture cannot express a transition.
##
## Now the neutral STANDING mesh is the only body, and every pose (sit, groom, sleep,
## run stance, jump stretch) is a set of joint rotations extracted from the other rigged
## meshes' rest poses (tools/extract_cat_poses.py — same Tripo template, bone-for-bone)
## and BLENDED onto the one skeleton by cat_rig.gd. Transitions are continuous by
## construction. BASE_FALLBACK keeps the s34 static path alive if the rigged stand is
## ever missing: the cat degrades to a statue, never to a crash.
const BASE_RIGGED := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"
const BASE_FALLBACK := "res://assets/models/fauna/_rigged/cat_walk_walk.glb"
const POSE_LIBRARY := "res://assets/models/fauna/_rigged/cat_poses.json"
## Which pose each state wears. Kept as a table rather than a match statement inside the
## per-frame code so a state cannot silently forget to set one.
const STATE_POSE := {
	State.GROOM: "groom",
	State.FOLLOW: "walk",
	State.RUN: "run",
	State.SIT: "sit",
	State.SLEEP: "sleep",
	State.FISH: "walk",
	State.PET: "sit",
	State.JUMP: "jump",
}


## Where it is found. The bunkhouse floor, in the aisle at the west end — off the walking line
## between the door and the bunks, so it reads as a thing that lives here rather than a prop
## dropped in the doorway. The Y is PROBED at spawn, never trusted from this constant.
const HOME := Vector3(-24.6, 18.0, 11.4)

const WALK_SPEED: float = 1.55
const TROT_SPEED: float = 2.6        ## when it has fallen behind, or there is fish
const FOLLOW_NEAR: float = 2.2       ## closer than this and it stops walking
const FOLLOW_FAR: float = 14.0       ## further than this and it trots
const LOST_M: float = 26.0           ## past this it gives up and settles where it is
const GREET_M: float = 2.4           ## how close you must come to say hello
const FISH_M: float = 9.0            ## it can smell a fish in your hands from here
const TURN_RATE: float = 6.0
## Further behind than this and the walk becomes a run.
const RUN_M: float = 8.0
const RUN_SPEED: float = 4.4
## How long the head-bump lean lasts when you pet it.
const PET_SEC: float = 1.1
## Feeding it a raw fish is worth this much comfort, once per game day. Small on purpose —
## it is a moment with an animal, not a food source.
const FED_COMFORT: float = 0.12
const FED_REST: float = 0.06
const STEP_UP: float = 0.45          ## the probe's own reach above the next footfall
## HOW HIGH A STEP IT WILL TAKE. Was STEP_UP, i.e. "coamings yes, stairs no" — the cat
## could not follow the player off the deck they met on, which reads as a pet that gives up
## rather than as a cat. A rig stair tread is well inside this, so it climbs one tread at a
## time; a bunk frame or a wall is still refused.
const CLIMB_UP: float = 0.62
## Taller than CLIMB_UP and up to this, the cat JUMPS instead of refusing. A real cat
## clears five times its shoulder height; this is deliberately far short of that, because
## the failure mode of a generous number is an animal that leaps onto things the level
## design assumed were out of reach.
const JUMP_UP: float = 1.25
const JUMP_SEC: float = 0.52
## Stops a cat that lands just under another lip from jumping every frame forever.
const JUMP_CD: float = 0.9
## Metres of ground covered per stride cycle. The gait's cycle rate is speed / this, which
## is what keeps the paws from skating at one speed and mincing at another.
const STRIDE_M: float = 0.62
## The stand mesh's longest-axis target, hull-volume-equalised against walk@0.66 (s36's
## sizing method, one entry now that there is one mesh). Recomputed if the base mesh is
## ever re-rolled: tools/extract_cat_poses.py prints the reminder.
const STAND_SIZE_M: float = 0.66   ## nose-to-tail parity with the walk mesh's 0.66

## Seconds of stillness from the player before the cat decides this is a rest, not a pause.
const SETTLE_SEC: float = 6.0
## ...and how long it then sits before lying down properly.
const DOZE_SEC: float = 22.0

var friend: bool = false
var _state: int = State.GROOM
var _t: float = 0.0
var _still: float = 0.0
var _last_player_pos: Vector3 = Vector3.ZERO
var _gen_mats: Array = []
var _body: Node3D
## pose key -> the Node3D holding that mesh, and its ShaderMaterials.
## THE one drawn body. Kept as a single node rather than a dictionary of them because a
## dictionary of bodies is what made transitions teleports.
var _host: Node3D = null
var _pose: String = ""
## Petting: how long the head-bump lean lasts, and when the next purr is allowed.
var _pet_t: float = 0.0
## Feeding: the absolute GAME HOUR the cat was last fed, so "once per game day" survives a
## night's sleep. Measured in game hours rather than delta seconds for the reason
## KNOWN_ISSUES records about the mussel beds: sleeping advances the calendar and no real
## time passes, so a countdown in seconds sits through five slept nights unchanged.
var _fed_game_h: float = -1000.0
## Counts down after a feed — the happy wiggle, the seal's _pet_bump idea on a cat.
var _fed_wiggle: float = 0.0
var _touch: Interactable
var _ai_acc: float = 0.0
var _rng := RandomNumberGenerator.new()
var _meow_cd: float = 0.0
var _seated_y: float = 0.0
## pose key -> CatRig, for the poses whose GLB carried a skin. Empty for any that fell back
## to the static mesh, and every call site tolerates a missing entry.
var _rig = null   ## the cat_rig.gd blender driving _host's skeleton
## The gait's own phase, in cycles, INTEGRATED rather than derived from `_t * speed`.
## docs/AGENT_TRAPS.md is explicit about why: a tuning value multiplied by an accumulating
## clock inside a sine cannot be animated at all — changing speed at second T teleports the
## wave phase, which is what made a shoal detonate at the first touch of alarm. Integrating
## the paced time makes a speed change continuous by construction.
var _gait: float = 0.0
## What the cat is currently paying attention to, in world space, and how strongly. This is
## the "every state should have a focus" the owner asked for: the head tracks it even when
## the body does not turn.
var _focus: Vector3 = Vector3.ZERO
var _focus_w: float = 0.0
## Signed slope of the ground under the last step, radians. Drives the body pitch so the cat
## leans into a climb and noses down a descent instead of staying level through both.
var _slope: float = 0.0
## The speed the last step was actually taken at, so the gait picks its footfall pattern
## from what the body did rather than from what a state hoped it would do.
var _last_speed: float = 0.0
## Metres the body ACTUALLY covered this frame — the blender's gait phase runs off this,
## never off commanded speed, so a blocked cat's legs stop instead of treadmilling.
var _moved_frame: float = 0.0
## The held sleeping spot — picked once when the player turns in, cleared when they rise.
var _sleep_target: Vector3 = Vector3.ZERO
## The leap, in flight: time left, and the two ends of the arc. While `_jump_t` is positive
## the state machine hands the animal over to _fly_jump and nothing else moves it.
var _jump_t: float = 0.0
var _jump_cd: float = 0.0
var _body_r_cache: Dictionary = {}
var _jump_from: Vector3 = Vector3.ZERO
var _jump_to: Vector3 = Vector3.ZERO

func _ready() -> void:
	_rng.seed = 5150
	add_to_group("ship_cat")
	_body = Node3D.new()
	add_child(_body)
	# Every pose, attached once, all hidden but the first. Each one carries its own facing
	# (cat_sit and cat_groom are authored along +X, the rest along +Z — measured s34, see
	# CreatureAnim.FACING_OVERRIDES) and each is GROUNDED so its paws sit on the deck rather
	# than its origin: the five poses have wildly different heights, and a curled sleeping
	# cat centred like a standing one floats.
	# ONE host, ONE skeleton. attach_rigged keeps the imported PBR materials and stops
	# Tripo's baked clip; the pose library and every transition live in cat_rig.gd.
	var host := Node3D.new()
	_body.add_child(host)
	var pg: Dictionary = ANIM.attach_rigged(host, BASE_RIGGED, _pose_size("stand"))
	if pg.is_empty() or pg.get("skeleton") == null:
		if not pg.is_empty():
			(pg["model"] as Node3D).queue_free()
		pg = ANIM.attach_rigged(host, BASE_FALLBACK, _pose_size("stand"))
	var skel: Skeleton3D = pg.get("skeleton") as Skeleton3D if not pg.is_empty() else null
	if skel != null:
		_rig = RIG.new(skel, POSE_LIBRARY)
		if _rig != null and not _rig.valid():
			_rig = null
	if not pg.is_empty():
		ANIM.ground(host, pg["model"])
		_host = host
	else:
		host.queue_free()
	var gen: Dictionary = {"mats": []} if _host != null else {}
	if _rig != null:
		_wear("groom")
	if gen.is_empty():
		# No mesh on disk yet: a placeholder that still reads as a small four-legged animal,
		# so the behaviour can be played and tested before the asset lands.
		var m: Material = BloomFauna.glow_mat(Color(0.42, 0.40, 0.38), 0.0)
		KIT.ball(_body, Vector3(0, 0.20, 0), 0.22, m, Vector3(1.0, 0.9, 2.0))    # body
		KIT.ball(_body, Vector3(0, 0.30, -0.24), 0.13, m)                        # head
	else:
		_gen_mats = gen["mats"]
	# The interaction handle. Same contract every other creature uses, so the crosshair, the
	# prompt chip and the interaction ray all find it with no special cases.
	_touch = Interactable.new()
	_touch.display_name = "Ship's Cat"
	# The VERBS LIVE ON THE INTERACTABLE, not on this node. interaction_ray reads
	# `available_verbs()` off the collider it hit, which is the Interactable child — a method
	# of the same name on the parent is never consulted, so the prompt would have read the
	# base class's default "USE" while this script thought it was offering a greeting.
	_touch.verbs = ["SAY HELLO"] as Array[String]
	add_child(_touch)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.5, 0.7)
	col.shape = box
	col.position.y = 0.25
	_touch.add_child(col)
	# YOU CAN WALK THROUGH THE CAT. An Interactable is a StaticBody3D and nothing here ever
	# set its layer, so it sat on the default layer 1 — the layer the player's own capsule
	# masks — and a 0.6 x 0.5 x 0.7 solid box stood in the middle of the bunkhouse aisle.
	# Being physically stopped by a cat reads as a bug in a way that being stopped by a
	# crate does not, and the owner asked for it explicitly.
	#
	# It moves to layer 3 rather than to NO layer, because the layer is how the game finds
	# it: InteractionRay casts against a mask, and bloom_fauna's existing lever
	# (`collision_layer = 1 if solid else 0`) would make the animal unpettable as well as
	# unblocking. Layer 3 was unused by anything in this project, and InteractionRay now
	# masks 1 | 3 — so the cat is reachable by the crosshair and invisible to the capsule.
	#
	# The seat ray is a separate matter and stays excluded by RID (see _reseat): the cat
	# must not stand on itself even on a layer the player ignores.
	_touch.collision_layer = InteractionRay.INTERACT_LAYER
	_touch.collision_mask = 0
	_touch.interacted.connect(_on_touched)
	# PROBED, NOT TYPED. HOME's Y is the bunkhouse deck as authored, and every floating-prop
	# bug in this repo came from trusting exactly that kind of constant. Deferred because CSG
	# decks have no collider on the frame they enter the tree (see surface_snap.gd).
	global_position = HOME
	call_deferred("_seat")

## THE SEAT RAY MUST EXCLUDE THE CAT'S OWN HANDLE, and for two sessions it did not.
##
## `_touch` is an Interactable, i.e. a StaticBody3D on the default layer, carrying a
## 0.6 x 0.5 x 0.7 box centred 0.25 m above the feet. This ray drops from +1.2 with
## `collision_mask = 1` and no exclusions, so the FIRST thing it hit was the top face of
## that box at +0.50 — and the cat was then "seated" exactly 0.500 m in the air, every
## time, deterministically. That is the owner's "cat is found floating".
##
## The reason it looked intermittent — "floating UNTIL the player says hello" — is that the
## other two rays in this file already exclude the handle (`_walk_toward` and
## `_sleep_spot`), so the moment the cat took its first step it re-seated itself correctly
## and the bug vanished. Befriending it was never the cure; walking was.
func _seat() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_reseat()

## Put the cat on whatever is under it, right now. Called at spawn and then every frame it
## is NOT walking — because `_walk_toward` is the only thing that used to re-ground it, so
## a cat that stands still on a deck another session moves would hang in the air until it
## happened to take a step.
func _reseat() -> void:
	var world: World3D = get_world_3d()
	if world == null:
		return
	var from: Vector3 = global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 4.0, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = [_touch.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position.y = (hit["position"] as Vector3).y
	_seated_y = global_position.y

## Kept for probes and for anything that asks the CAT rather than its handle; the handle's own
## `verbs` is what the interaction ray reads, and both are set together in _on_touched.
func available_verbs() -> Array:
	return ["PET"] if friend else ["SAY HELLO"]

## `Interactable.interacted` carries ONE argument — the verb. It does not pass the player, so
## the player is looked up here; connecting a two-argument handler silently fails to fire at
## all, which is exactly what made the first version of this cat unbefriendable.
func _on_touched(_verb: String) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not friend:
		friend = true
		_enter(State.FOLLOW)
		_touch.verbs = ["PET"] as Array[String]
		Journal.discover("creature_ship_cat")
		AudioDirector.play_one_shot("cat_chirp", global_position, -18.0)
		if hud and hud.has_method("toast"):
			hud.toast("The cat looks up, decides about you, and comes along.")
		return
	# PETTING IS REPEATABLE, which is the whole point of it — the s32 cat offered PET and
	# then did nothing observable, so there was no reason to press it twice.
	_pet_t = PET_SEC
	AudioDirector.play_one_shot("purr", global_position, -14.0)
	if player != null and is_instance_valid(player):
		_face(player.global_position, 1.0)
	# ...and if you are holding a raw fish when you do it, that is FEEDING it. Once per game
	# DAY, counted in absolute game hours: sleeping advances the calendar without any real
	# time passing, so a cooldown in seconds would sit through a slept night untouched
	# (KNOWN_ISSUES records the same trap costing the mussel beds a regrowth cycle).
	var now_h: float = GameClock.game_time_hours()
	if _player_holding_fish(player) and now_h - _fed_game_h >= 24.0:
		var slot: int = PlayerState.selected_hotbar
		var fish_id: String = String(PlayerState.hotbar[slot])
		if PlayerState.remove_item(fish_id):
			_fed_game_h = now_h
			_fed_wiggle = 1.0
			PlayerState.comfort = clampf(PlayerState.comfort + FED_COMFORT, 0.0, 1.0)
			PlayerState.rest = clampf(PlayerState.rest + FED_REST, 0.0, 1.0)
			AudioDirector.play_one_shot("eat", global_position, -16.0)
			if hud and hud.has_method("toast"):
				hud.toast("The cat takes the fish, and is briefly very pleased with you.")
			_meow_cd = 2.0
			return
	if hud and hud.has_method("toast"):
		hud.toast("The cat leans into your hand.")
	_meow_cd = 6.0

func _process(delta: float) -> void:
	# Four-line AiBudget prologue — mandatory for anything new that runs per frame here, and
	# it hands back the SUM of the frames it skipped so the animal covers the same ground per
	# second rather than moving at 1/N speed (ai_budget.gd explains the trap).
	_ai_acc += delta
	if not AIB.due(self, _ai_acc):
		return
	delta = _ai_acc
	_ai_acc = 0.0
	_t += delta
	if _meow_cd > 0.0:
		_meow_cd -= delta
	if _pet_t > 0.0:
		_pet_t -= delta
	# EVERY FRAME STARTS FROM A CLEAN BODY, and this is the whole of "it does not walk
	# straight". `_groom` wrote `_body.rotation.x` and `_pose_sit` wrote `_body.rotation.y`,
	# and NOTHING ever cleared either — only roll was eased home. So the cat picked up a few
	# degrees of permanent pitch the moment you met it, and a yaw skew off its direction of
	# travel every time it sat down, and carried both for the rest of the session. Each
	# state now writes the offsets it wants onto a body that is already neutral.
	_body.rotation.x = lerpf(_body.rotation.x, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	_body.rotation.y = lerpf(_body.rotation.y, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	if _fed_wiggle > 0.0:
		_fed_wiggle -= delta * 0.7
		_body.rotation.y = sin(_t * 17.0) * 0.13 * clampf(_fed_wiggle, 0.0, 1.0)
	# The lean into a slope, eased so a step onto a stair tread is not a snap.
	_body.rotation.x += -_slope * 0.55
	_focus_w = maxf(0.0, _focus_w - delta * 1.5)
	# BEFORE ANYTHING ELSE DECIDES WHERE TO GO, GET OUT OF WHATEVER WE ARE IN. Unconditional
	# and state-independent on purpose: a predictive gate cannot rescue an animal that is
	# already buried, and every gate in this file is predictive.
	_unbury()
	if _jump_cd > 0.0:
		_jump_cd -= delta
	# A LEAP OWNS THE ANIMAL UNTIL IT LANDS. Taken before the state machine, so nothing
	# downstream can re-seat the cat onto the deck it just left — which is what would
	# otherwise cancel the jump on its first airborne frame.
	if _jump_t > 0.0:
		_fly_jump(delta)
		_drive_rig(delta)
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if not friend:
		_groom(delta, player)
		_drive_rig(delta)
		return
	_companion(delta, player)
	_drive_rig(delta)

## The arc. A jump is not a lerp: a straight line between two points reads as an animal
## being slid up a ramp. The horizontal runs linearly and the vertical carries a parabola
## over the top, so the cat rises clear of the lip it is clearing and comes down onto it.
func _fly_jump(delta: float) -> void:
	_jump_t -= delta
	var k: float = clampf(1.0 - _jump_t / JUMP_SEC, 0.0, 1.0)
	var flat: Vector3 = _jump_from.lerp(_jump_to, k)
	# Peak height scales with the rise so a small hop does not launch the cat at the
	# deckhead, with a floor so a flat leap still leaves the ground.
	var lift: float = maxf(_jump_to.y - _jump_from.y, 0.0) * 0.35 + 0.14
	var before_fly: Vector3 = global_position
	global_position = Vector3(flat.x, flat.y + sin(k * PI) * lift, flat.z)
	_moved_frame += global_position.distance_to(before_fly)
	_face(_jump_to, delta * 2.0)
	_last_speed = RUN_SPEED
	if _jump_t <= 0.0:
		global_position = _jump_to
		_jump_cd = JUMP_CD
		_reseat()

## Before you find it: sitting where it lives, washing a paw, looking up when you get close.
func _groom(delta: float, player: Node3D) -> void:
	_enter(State.GROOM)
	# It has not moved, so it must still be on the deck — the seat ray is the only thing
	# that grounds a cat that never walks, and before s35 it ran exactly once, at spawn,
	# against its own collider.
	_reseat()
	_last_speed = 0.0
	var d: float = global_position.distance_to(player.global_position)
	if d < GREET_M * 2.5:
		_face(player.global_position, delta)   # it has noticed you
		_watch(player.global_position + Vector3(0, 1.2, 0), 1.0)
	elif d < FISH_M * 2.0:
		# Further off it does not turn, but it does LOOK — a cat clocks you from across a
		# room without getting up, and this is the cheapest thing that says it is alive.
		_watch(player.global_position + Vector3(0, 1.2, 0), 0.55)
	# The wash: a slow lean and a nod on top of the skeletal groom, so the body moves with
	# the head rather than the head alone.
	_body.rotation.z = sin(_t * 1.7) * 0.10
	_body.rotation.x += sin(_t * 2.3) * 0.07

## After: it comes with you, at its own pace, and settles when you do.
func _companion(delta: float, player: Node3D) -> void:
	var ppos: Vector3 = player.global_position
	var d: float = global_position.distance_to(ppos)

	# IS THE PLAYER RESTING? Not a flag they set — a thing the cat works out by watching. A
	# player who has not moved for SETTLE_SEC is resting whether they meant to or not, which
	# is also true of lying down and sitting, and it means the cat settles when you stop to
	# fish or read rather than only in a bed.
	var moved: float = ppos.distance_to(_last_player_pos)
	_last_player_pos = ppos
	var resting: bool = moved < 0.05 * maxf(delta, 0.001) * 60.0
	if bool(player.get("_lying")) or bool(player.get("crouching")):
		resting = true
	_still = (_still + delta) if resting else 0.0

	# BEING PETTED WINS OVER EVERYTHING for a moment: a head-bump you can interrupt is not
	# a head-bump. Short, so it never reads as the cat freezing.
	if _pet_t > 0.0:
		_enter(State.PET)
		_face(ppos, delta)
		# The lean into the hand, and back out of it.
		var k: float = sin((1.0 - _pet_t / PET_SEC) * PI)
		_body.rotation.z = k * 0.22
		_body.position.y = k * 0.04
		return

	# THE FISH. It can smell one in your hands and it does not pretend otherwise: it closes
	# right up, and it will not settle while you are holding it.
	var has_fish: bool = _player_holding_fish(player)
	if has_fish and d < FISH_M:
		_enter(State.FISH)
		_walk_toward(ppos, TROT_SPEED, delta, 0.9)
		if _meow_cd <= 0.0:
			_meow_cd = _rng.randf_range(4.0, 9.0)
			AudioDirector.play_one_shot("cat_chirp", global_position, -20.0)
		return

	if d > LOST_M:
		# Too far to bother. It stops where it is and waits to be come back for, rather than
		# sprinting across the rig — which would read as a drone, not an animal.
		_settle(delta)
		return
	if d > FOLLOW_NEAR:
		# ...and it BREAKS INTO A RUN when it has been left behind, which is the one moment a
		# follower reads as an animal rather than a marker: same walk otherwise.
		var running: bool = d > RUN_M
		_enter(State.RUN if running else State.FOLLOW)
		_still = 0.0
		_walk_toward(ppos, RUN_SPEED if running else (TROT_SPEED if d > FOLLOW_FAR else WALK_SPEED),
			delta, FOLLOW_NEAR)
		return
	# THE PLAYER HAS TURNED IN. A cat does not wait out a night standing up: it comes over,
	# finds a spot NEAR the bed rather than on the walking line, and curls up there. The spot
	# is PROBED (see _sleep_spot) — a hand-typed offset from a bed that another session moves
	# is the whole floating-prop family of bugs in this repo.
	if _player_asleep(player):
		# THE SPOT IS CHOSEN ONCE AND HELD. _sleep_spot used to be re-run every frame, and
		# its winning candidate depends on the cat's own position — so as the animal walked,
		# the target could flip between two candidates and, in the wrong geometry, oscillate
		# for ever: a cat that paces beside the bed all night instead of lying down (seen as
		# an intermittent probe failure, ~1 run in 5). Hysteresis: keep the chosen spot while
		# the player stays asleep, re-picking only if it drifts out of plausibility.
		if _sleep_target == Vector3.ZERO or ppos.distance_to(_sleep_target) > 3.0:
			_sleep_target = _sleep_spot(ppos)
		if global_position.distance_to(_sleep_target) > 0.55:
			_enter(State.FOLLOW)
			_walk_toward(_sleep_target, WALK_SPEED, delta, 0.35)
		else:
			_enter(State.SLEEP)
			ANIM.drive(_gen_mats, 0.5, 0.0)
		return
	_sleep_target = Vector3.ZERO

	# Within arm's reach of a player who is not going anywhere.
	if _still > SETTLE_SEC:
		_settle(delta)
	else:
		_enter(State.SIT)
		_pose_sit(delta)

## Is the player actually turned in? `_lying_sleeping` is the flag player_controller sets
## while the S-to-dawn fade runs; `_lying` is merely lying down. A cat curls up when you go
## to bed, not when you lie on the floor for a second.
func _player_asleep(player: Node3D) -> bool:
	return bool(player.get("_lying_sleeping")) or bool(player.get("_lying"))

func _settle(delta: float) -> void:
	if _still > SETTLE_SEC + DOZE_SEC:
		_enter(State.SLEEP)
		# Curled and breathing, nose tucked. The body sinks a little and the breathe rate
		# halves — the same trick the denned glow worm uses to read as asleep.
		# The curled mesh does the shape; this is only the breathing slowing down. The old
		# code rolled the body 0.55 rad to fake "lying down" with a standing mesh, which is
		# exactly what having a sleep pose removes the need for.
		_body.rotation.z = lerpf(_body.rotation.z, 0.0, delta * 2.0)
		_body.position.y = lerpf(_body.position.y, 0.0, delta * 2.0)
		ANIM.drive(_gen_mats, 0.5, 0.0)
	else:
		_enter(State.SIT)
		_pose_sit(delta)

func _pose_sit(delta: float) -> void:
	_body.rotation.z = lerpf(_body.rotation.z, 0.0, delta * 3.0)
	_body.position.y = lerpf(_body.position.y, 0.0, delta * 3.0)
	ANIM.drive(_gen_mats, 1.1, 0.0)
	_last_speed = 0.0
	# A sitting cat is on the deck it sat down on — and the seat ray is the only thing that
	# keeps it there if another session moves that deck.
	_reseat()
	# The small weight-shift of a cat that is awake and paying attention. This is ADDED to
	# a body that _process has already eased back to neutral; it used to be ASSIGNED, and
	# because nothing ever cleared it the skew rode along into the next walk.
	_body.rotation.y += sin(_t * 0.9) * 0.06

## Walk the deck toward a point, stopping `stop_at` short. Kinematic and deliberately simple:
## it steps up a coaming, refuses anything taller, and re-seats on whatever it is standing on
## so it can never walk off into the air.
func _walk_toward(target: Vector3, speed: float, delta: float, stop_at: float) -> void:
	var to: Vector3 = target - global_position
	to.y = 0.0
	var dist: float = to.length()
	if dist <= stop_at or dist < 0.01:
		return
	var dir: Vector3 = to / dist
	_face(target, delta)
	var step: Vector3 = dir * speed * delta
	var want: Vector3 = global_position + step
	var world: World3D = get_world_3d()
	if world == null:
		return
	# Probe the deck under the next footfall. No hit means the step would walk it off an edge,
	# so it simply does not take it — a cat does not fall off a rig.
	var from: Vector3 = want + Vector3(0, STEP_UP + 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, STEP_UP + 1.4, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = [_touch.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var ground: float = (hit["position"] as Vector3).y
	var rise: float = ground - global_position.y
	# IS THERE A WALL IN THE WAY? The owner's "Cat glitches through walls".
	#
	# Every probe above asks about the FLOOR — "is there deck under the next footfall, and
	# is the step up small enough". None asked whether anything stands BETWEEN the cat and
	# that footfall, so a bulkhead with sound deck on both sides answered every question
	# correctly and the animal walked straight through it. The bunkhouse is full of exactly
	# that geometry.
	#
	# DOES THE BODY FIT WHERE THE FEET ARE GOING? Not a ray — see _step_clear. A ray from
	# the origin let the animal stop with up to 0.48 m of itself inside a bulkhead, which is
	# the state the owner photographed. The destination is tested as a VOLUME.
	#
	# AND IF IT DOES NOT FIT, SLIDE — do not stop dead. A companion that refuses a blocked
	# step just stands there vibrating against the obstruction, which is the "glitchy" read
	# even though nothing is intersecting: the first cut of this check did exactly that and
	# left the cat unable to close the last half-metre to its own sleeping spot. Real
	# movement code slides along what it touches, so this tries the direct line first and
	# then the two tangents, taking whichever still carries it toward the target.
	var moved_dir: Vector3 = dir
	if not _step_clear(Vector3(want.x, ground, want.z), dir):
		var slid := false
		for side in [1.0, -1.0]:
			var alt: Vector3 = dir.rotated(Vector3.UP, side * PI * 0.5)
			# Only a slide that still makes progress — a tangent pointing back the way we
			# came is how an animal ends up orbiting a pillar for ever.
			if alt.dot(dir) < -0.1:
				continue
			var awant: Vector3 = global_position + alt * speed * delta
			var aq := PhysicsRayQueryParameters3D.create(
				awant + Vector3(0, STEP_UP + 0.3, 0),
				awant + Vector3(0, STEP_UP + 0.3, 0) - Vector3(0, STEP_UP + 1.4, 0))
			aq.collision_mask = 1
			aq.collide_with_areas = false
			aq.exclude = _walk_skip()
			var ahit: Dictionary = world.direct_space_state.intersect_ray(aq)
			if ahit.is_empty():
				continue
			var aground: float = (ahit["position"] as Vector3).y
			if absf(aground - global_position.y) > CLIMB_UP:
				continue
			if not _step_clear(Vector3(awant.x, aground, awant.z), alt):
				continue
			want = awant
			ground = aground
			rise = aground - global_position.y
			moved_dir = alt
			slid = true
			break
		if not slid:
			return
	# STAIRS. The old rule was "coamings yes, stairs no" (STEP_UP 0.45) and the cat simply
	# refused anything taller — which is why it could not follow you off the deck it met you
	# on. A rig stair tread rises STAIR_RISE per step, well inside CLIMB_UP, so the animal
	# takes them one tread at a time like everything else does; what it still refuses is a
	# wall or a bunk frame.
	# A RISE TOO TALL TO STEP IS A RISE TO JUMP. Between CLIMB_UP and JUMP_UP the cat leaves
	# the ground properly — which is what the jump mesh is for, and it is also the honest
	# answer to a follower that used to give up at every crate and coaming it could plainly
	# get onto. Above JUMP_UP it still refuses: a cat does not scale a bulkhead.
	if rise > CLIMB_UP:
		if rise <= JUMP_UP and _jump_t <= 0.0 and _jump_cd <= 0.0:
			_jump_t = JUMP_SEC
			_jump_from = global_position
			_jump_to = Vector3(want.x, ground, want.z)
			_enter(State.JUMP)
			AudioDirector.play_one_shot("cat_chirp", global_position, -24.0)
		return
	# The slope it is standing on, for the body pitch. Taken from the rise over the step
	# actually taken rather than from a second probe, so it cannot disagree with the move.
	var run: float = maxf(step.length(), 0.0001)
	_slope = lerpf(_slope, clampf(atan2(rise, run), -0.7, 0.7), clampf(delta * 5.0, 0.0, 1.0))
	var before_step: Vector3 = global_position
	global_position = Vector3(want.x, ground, want.z)
	_last_speed = speed
	# The blender's phase runs off DISTANCE ACTUALLY MOVED (see cat_rig.tick) — recorded
	# here, where the movement really happens, so a refused or slid step is felt by the
	# legs instead of them cycling against a wall.
	_moved_frame += global_position.distance_to(before_step)
	_gait = fposmod(_gait + global_position.distance_to(before_step) / STRIDE_M, 1.0)
	# A small vertical lilt — the whole-body rise and fall the legs alone do not carry,
	# since the rig has no root motion. Phase-locked to the same distance the legs use.
	_body.position.y = absf(sin(_gait * TAU)) * 0.030
	_body.rotation.z = sin(_gait * TAU * 0.5) * 0.045

## `+ PI` IS THE WHOLE OF "THE CAT WALKS BACKWARDS", and it was the only call site in the
## repo missing it.
##
## `atan2(d.x, d.z)` is the yaw that puts a node's LOCAL +Z on the target. Godot's forward
## is -Z, and CreatureAnim normalises every generated mesh so its head sits on the host's
## -Z (the blanket 180 yaw). So without the half turn the cat aimed its TAIL at wherever it
## was going. Every sibling — fauna_move.gd:511, bloom_fauna.gd:2927/2969/4423/4455 — adds
## it, one of them with the comment "this turns the head toward the player instead of
## pointing its tail at them".
##
## Confirmed three ways rather than reasoned once: the algebra above; tools/measure_facing.py
## reading +Z off cat_walk/cat_run/cat_sleep with both statistics agreeing, so no mesh error
## cancels it; and the rendered side view in tests/out/cat_bind.
## THE CAT IS A VOLUME, NOT A POINT — and until s36 every check in this file forgot that.
##
## `_walk_toward` probed the deck with a ray from the ORIGIN and tested for walls with a ray
## from the ORIGIN, so the origin could stop perfectly legally with half the animal inside
## the concrete. Measured off the drawn meshes, the horizontal half-diagonal runs 0.35-0.48 m
## across the pose set: that is how much cat a point-check is allowed to leave in a wall, and
## it is what the owner photographed — a cat embedded in a bulkhead with its head out one
## face and its body out the other.
##
## Radius is the body's half-WIDTH rather than that half-diagonal, and measured from the
## pose actually being drawn rather than typed: a cat is not a sphere, and a disc the size
## of its length could not fit through a doorway it walks through nose-first every day.
## The nose is covered separately by testing the far end of the body too (see _step_clear).
func _body_r() -> float:
	if _host == null:
		return 0.18
	if _body_r_cache.has(_pose):
		return _body_r_cache[_pose]
	var host: Node3D = _host
	var acc := AABB()
	var first := true
	for n in host.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var b: AABB = mi.global_transform * mi.get_aabb()
		acc = b if first else acc.merge(b)
		first = false
	# The SMALLER horizontal extent is the body's width whatever way the animal is facing.
	var r: float = 0.18 if first else clampf(minf(acc.size.x, acc.size.z) * 0.5, 0.10, 0.26)
	_body_r_cache[_pose] = r
	return r

## Would the cat's BODY fit at `at`? A sphere query rather than a ray, so a step that leaves
## the origin outside a wall but the flank inside it is refused. Tested at the body centre
## and again at the nose, which is the one place a width-sized disc cannot see.
func _step_clear(at: Vector3, dir: Vector3) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var r: float = _body_r()
	var sphere := SphereShape3D.new()
	sphere.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _walk_skip()
	# `_body_r` is a half-width; the nose reaches roughly a body length ahead of centre, so
	# probe there too or the animal walks its head into a bulkhead and stops with the face
	# buried while its centre is legally clear.
	var lead: float = _body_len() * 0.5 - r
	for probe in [at + Vector3(0, r + 0.04, 0),
			at + dir * maxf(lead, 0.0) + Vector3(0, r + 0.04, 0)]:
		q.transform = Transform3D(Basis.IDENTITY, probe)
		if not world.direct_space_state.intersect_shape(q, 1).is_empty():
			return false
	return true

func _body_len() -> float:
	if _host == null:
		return 0.6
	var host: Node3D = _host
	var acc := AABB()
	var first := true
	for n in host.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var b: AABB = mi.global_transform * mi.get_aabb()
		acc = b if first else acc.merge(b)
		first = false
	return 0.6 if first else maxf(acc.size.x, acc.size.z)

## THE SAFETY NET, and the reason this can be called "no glitches" rather than "fewer".
##
## Every gate above is predictive — it refuses a step that WOULD bury the animal. None of
## them can rescue a cat that is already buried, and a raycast fundamentally cannot: a ray
## whose origin lies inside a shape does not report that shape in Godot, so once the animal
## is in the concrete the entire detection scheme goes silent and it stays there for the
## session. That is what shipped, and it is why the owner's frame exists.
##
## So this runs every frame regardless of state: sweep the body sphere, take the deepest
## contact, and push straight back out along the contact normal. It cannot be defeated by a
## new movement path, by another session moving a wall onto the cat, or by a spawn point
## that turns out to be inside geometry.
func _unbury() -> void:
	var world: World3D = get_world_3d()
	if world == null:
		return
	var r: float = _body_r()
	var sphere := SphereShape3D.new()
	sphere.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _walk_skip()
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, r + 0.04, 0))
	var pairs: PackedVector3Array = world.direct_space_state.collide_shape(q, 8)
	if pairs.size() < 2:
		return
	# collide_shape returns [point_on_us, point_on_them, ...]. The vector between the pair
	# IS the overlap; take the deepest and step out along it.
	var push := Vector3.ZERO
	var worst: float = 0.0
	for i in range(0, pairs.size() - 1, 2):
		var sep: Vector3 = pairs[i] - pairs[i + 1]
		if sep.length() > worst:
			worst = sep.length()
			push = sep
	if worst <= 0.0005:
		return
	push.y = 0.0
	if push.length() < 0.0005:
		return
	global_position += push.normalized() * (worst + 0.02)
	_reseat()

## Everything the cat's WALL ray must not mistake for a wall: its own handle, the player,
## and every other animal's touch sphere. Rebuilt each call rather than cached, because
## fauna are spawned and freed through the session and a stale RID is a silent hole in the
## skip list — the cost is a handful of group lookups on an animal that already raycasts
## twice a step.
func _walk_skip() -> Array[RID]:
	var skip: Array[RID] = [_touch.get_rid()]
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player):
		if player is CollisionObject3D:
			skip.append((player as CollisionObject3D).get_rid())
		for c in player.find_children("*", "CollisionObject3D", true, false):
			skip.append((c as CollisionObject3D).get_rid())
	var bf: Node = get_tree().get_first_node_in_group("bloom_fauna")
	if bf != null and bf.get("fauna_bodies") != null:
		for r in (bf.get("fauna_bodies") as Array):
			if r is RID:
				skip.append(r)
	return skip

func _face(target: Vector3, delta: float) -> void:
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length_squared() < 0.0004:
		return
	var want: float = atan2(to.x, to.z) + PI
	rotation.y = lerp_angle(rotation.y, want, clampf(TURN_RATE * delta, 0.0, 1.0))

## Is there a fish in the player's hand right now? Reads the hotbar the same way the spear
## prompt does, so "holding a fish" means exactly what it means everywhere else.
func _player_holding_fish(_player: Node3D) -> bool:
	var slot: int = PlayerState.selected_hotbar
	if slot < 0 or slot >= PlayerState.HOTBAR_SIZE or PlayerState.hotbar[slot] == null:
		return false
	var id: String = String(PlayerState.hotbar[slot])
	return id.begins_with("fish_") or id.begins_with("cooked_fish_") or id == "dried_fish"

# ------------------------------------------------------------------ the rig

## POSE THE SKELETON FOR WHATEVER THE CAT IS DOING. One call at the end of the frame, after
## the state machine has decided, so there is exactly one writer and a state cannot forget.
##
## Every state gets its own motion AND its own focus, which is the owner's "every state
## should have a focus": the head tracks what the animal cares about even when the body is
## pointing somewhere else, and that is most of the difference between an animal and a prop.
## One call per frame, AFTER the state machine has decided. The state machine's whole
## output is a POSE NAME (set in _enter via the STATE_POSE table) plus the distance the
## body actually covered; the blender does everything else — the pose blend, the gait, the
## breathing, the look. There is no per-state animation code left to disagree with itself.
func _drive_rig(delta: float) -> void:
	if _rig == null:
		return
	# The head, first, so tick applies it this frame: attention wins over the gait's neck.
	if _focus_w > 0.01:
		var to: Vector3 = _focus - global_position
		if to.length_squared() > 0.0004:
			# Into the BODY's frame: the neck yaw is relative to where the animal is facing,
			# so a cat walking north looking east is +90, not a world bearing.
			var want: float = atan2(to.x, to.z) + PI
			var rel: float = wrapf(want - rotation.y, -PI, PI)
			var pitch: float = atan2(to.y - 0.25, Vector2(to.x, to.z).length())
			_rig.look(rel, clampf(pitch, -0.5, 0.5), _focus_w)
	_rig.tick(delta, _last_speed, _moved_frame)
	_moved_frame = 0.0

## Point the cat's ATTENTION at something without turning it. Weight decays, so a glance
## fades unless whatever caused it keeps calling.
func _watch(at: Vector3, weight: float = 1.0) -> void:
	_focus = at
	_focus_w = maxf(_focus_w, clampf(weight, 0.0, 1.0))

# ------------------------------------------------------------------ poses

## Target longest-axis size per pose, metres. NOT one number for all six: a cat curled
## asleep is a ~0.45 m ball and the same animal at full stride is ~0.75 m nose to tail, so
## normalising every mesh to the same longest axis would shrink the running cat and inflate
## the sleeping one until they read as two different animals. These are the real ratios of
## the same cat in those poses.
## MEASURED, NOT AUTHORED — and the previous numbers were the owner's "too small when
## sitting, too big when running, all states are currently different sizes".
##
## The bug is in the QUANTITY being normalised. `load_model` scales a mesh so its LONGEST
## AXIS equals this number, and the longest axis means a different part of the animal in
## every pose: nose-to-tail on a walking cat, but roughly height on a sitting one and
## roughly width on a curled one. Handing all of them one hand-picked length therefore
## guarantees they read as different-sized animals — it normalises the wrong thing.
##
## What is actually invariant is the CAT. Its body does not shrink when it sits down. So
## these are derived by equalising CONVEX HULL VOLUME across the pose set and anchoring on
## the walk mesh at 0.66 m, which is the one that already looked right. The hull rather
## than the raw volume because not one of the seven meshes is watertight (checked), and
## `Mesh.volume` on a non-watertight mesh is meaningless.
##
## The two biggest corrections fall out as +79% on sit and -9% on run — which are exactly
## the owner's two complaints, in the right directions. That agreement is the reason to
## trust the method rather than the individual numbers.
## ONE mesh now, so ONE number — and size consistency across states is by construction,
## which retires the s36 hull-volume table this replaces. The value is that table's method
## applied to the stand mesh: equal convex-hull volume with the walk mesh anchored at
## 0.66 m (computed offline; see the s37 DEVLOG entry).
func _pose_size(_key: String) -> float:
	return STAND_SIZE_M

## Show one pose, hide the rest. The transition is a visibility flip — see POSES for why it
## is not an ANIM.replace().
func _wear(key: String) -> void:
	if key == _pose:
		return
	_pose = key
	if _rig != null:
		# Settling into rest is gentle; being startled into motion is not. The rate is the
		# only thing that differs between "eases down to sleep" and "bolts upright".
		var rate: float = 10.0 if key in ["run", "jump", "walk"] else 5.0
		_rig.set_pose(key, rate)

## The pose a state wears, applied every time the state is set so a transition cannot be
## made without one.
func _enter(st: int) -> void:
	# THE ONLY PLACE `_state` IS ASSIGNED. Two sites were still writing it directly after the
	# s34 pass and the close-out screenshots caught it: the cat photographed as state 3 (SIT)
	# wearing the WALK mesh, which is the exact class of bug the pose table exists to stop —
	# a state that is true in a variable and false on screen. `grep "_state = " ship_cat.gd`
	# should only ever find this line.
	_state = st
	_wear(String(STATE_POSE.get(st, "stand")))

## Somewhere to curl up NEAR the player, probed rather than typed. Returns the point, or
## the cat's own position if nothing suitable is under it — a cat that cannot find a spot
## sleeps where it is standing, which is also what a cat does.
func _sleep_spot(near: Vector3) -> Vector3:
	var world: World3D = get_world_3d()
	if world == null:
		return global_position
	# Ring of candidates around the player, nearest first — the foot of the bed, the edge of
	# the chair, the warm spot by whatever they are sitting at.
	for r in [0.9, 1.4, 2.0]:
		for i in range(8):
			var a: float = TAU * float(i) / 8.0
			var at: Vector3 = near + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var from: Vector3 = at + Vector3(0, 1.4, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 3.0, 0))
			q.collision_mask = 1
			q.collide_with_areas = false
			q.exclude = [_touch.get_rid()]
			var hit: Dictionary = world.direct_space_state.intersect_ray(q)
			if hit.is_empty():
				continue
			var p: Vector3 = hit["position"]
			# Only a surface at about the height the cat is already on — it will not climb
			# onto a bunk or drop off a deck to go to sleep.
			if absf(p.y - global_position.y) > STEP_UP:
				continue
			# ...AND IT MUST BE ABLE TO WALK THERE. Until s36 this returned any surface it
			# could SEE, which was fine only because the cat could walk through whatever
			# stood in the way. Now that it cannot, an unreachable spot is a cat treading
			# water for ever: the ring is drawn around the PLAYER, the bunkhouse is full of
			# bunk frames, so a candidate behind one is easy to draw and impossible to reach.
			# Caught by the close-out pass — the cat held FOLLOW at one spot through four
			# frames while the player lay down 1.5 m away.
			var wq := PhysicsRayQueryParameters3D.create(
				global_position + Vector3(0, 0.22, 0), p + Vector3(0, 0.22, 0))
			wq.collision_mask = 1
			wq.collide_with_areas = false
			wq.exclude = _walk_skip()
			if not world.direct_space_state.intersect_ray(wq).is_empty():
				continue
			# ...and the BODY has to fit where it lies down. A spot the cat can see and walk
			# to can still be a spot it cannot occupy — a 0.9 m ring drawn round a player
			# standing against a bulkhead puts half its candidates inside the steel.
			if not _step_clear(p, (p - global_position).normalized()):
				continue
			return p
	return global_position
