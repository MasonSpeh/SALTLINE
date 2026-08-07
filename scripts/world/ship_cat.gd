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
## APPENDED, NEVER INSERTED — CatProbe and the close-out harness assert on the INTEGER values
## (state 2 is RUN, state 5 is FISH), so a new state anywhere but the end silently renumbers
## the states out from under every test that names one.
##
## STALK / POUNCE / GIFT are the predatory sequence; PLAY is the same machinery with nothing
## on the end of it; PERCH is the cat's standing preference for being higher than you.
enum State { GROOM, FOLLOW, RUN, SIT, SLEEP, FISH, PET, JUMP,
	STALK, POUNCE, GIFT, PLAY, PERCH, STRETCH }

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
	State.STALK: "stalk",
	State.POUNCE: "jump",
	State.GIFT: "carry",
	State.PLAY: "walk",
	State.PERCH: "sit",
	State.STRETCH: "stretch",
}

# ------------------------------------------------------------------ the hunt
#
## THE PREDATORY SEQUENCE, which is one of the most legible behaviours any animal has and the
## thing people actually mean when they say a cat is a cat. Leyhausen's description of it has
## five beats and every one of them is readable at game distance on a body with no facial rig:
##
##   NOTICE  — the whole animal stops and locks on. Stillness after motion IS the tell.
##   STALK   — low, slow, belly close to the deck, and it FREEZES whenever it thinks it has
##             been seen. The freezing is what separates a stalk from a walk toward something.
##   TREAD   — the plié: hind feet paddle, the rear waggles, and everyone who has ever met a
##             cat knows exactly what is about to happen. This is the single highest-value
##             half-second in the whole sequence and it costs one sine wave.
##   POUNCE  — a real leap, forepaws first, over the existing jump arc.
##   AFTER   — and it MISSES most of the time. A cat that misses sits down at once and washes,
##             with enormous dignity, as though it had meant to do that. That displacement
##             groom is more characterful than a success, and it is why the miss rate here is
##             deliberately high rather than generous.
##
## On a catch it brings the thing to you, because that is what a cat does with a companion.
const HUNT_M: float = 11.0            ## it clocks a bird from here
const HUNT_GIVEUP_M: float = 16.0     ## ...and gives up if the bird gets this far away
const STALK_SPEED: float = 0.62       ## the creep — deliberately well under a walk
const POUNCE_M: float = 1.75          ## close enough to launch
const POUNCE_SEC: float = 0.42
const WIGGLE_SEC: float = 0.9         ## the tread-and-waggle before the launch
const HUNT_CD: float = 24.0           ## after a hunt, it lets the deck settle
## Birds are HARD. A house cat's success rate on birds is well under half, and the misses are
## the better animation anyway — see the displacement wash above.
const CATCH_CHANCE: float = 0.34
const WASH_SEC: float = 4.5           ## how long the "I meant to do that" wash lasts
## The zoomies (FRAP). Real, well documented, and they fire after a sleep and around dusk —
## the crepuscular activity peak every cat owner knows as the evening madness.
const ZOOM_SEC: float = 3.4
const ZOOM_CD: float = 95.0
const PLAY_CD: float = 38.0
const PLAY_SEC: float = 6.0


## Where it is found. The bunkhouse floor, in the aisle at the west end — off the walking line
## between the door and the bunks, so it reads as a thing that lives here rather than a prop
## dropped in the doorway. The Y is PROBED at spawn, never trusted from this constant.
const HOME := Vector3(-24.6, 18.0, 11.4)

const WALK_SPEED: float = 1.55
const TROT_SPEED: float = 2.6        ## when it has fallen behind, or there is fish
const FOLLOW_NEAR: float = 2.2       ## closer than this and it stops walking
const FOLLOW_FAR: float = 14.0       ## further than this and it trots
## (LOST_M is gone: no distance gives up the follow — see the note above the follow
## branch. Parking the cat is the STAY verb's job now, a decision instead of a distance.)
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
## Last frame's node yaw, so the rig can be told how fast the body is really turning.
var _yaw_prev: float = 0.0
## Detour commitment (see _walk_toward's fan): which side it last went around an obstacle,
## and how long that preference lasts. Order-bias only — never a hard constraint.
var _detour_side: float = 0.0
var _detour_t: float = 0.0
## Seconds of fully-refused frames — past 0.35 the animal backs out of the pocket.
var _detour_stall: float = 0.0
## The stair-grade window: rise and run accumulated with ~0.45 m distance decay, so a
## staircase reads as its true grade instead of a once-a-tread flicker.
var _grade_dy: float = 0.0
var _grade_run: float = 0.0
## STAY/COME — the owner's follow toggle. While true the cat holds its own patch (the spot
## it was told to stay at) and lives its own life there; a COME (or any re-greeting after
## time away) releases it.
var _stayed: bool = false
var _stay_spot: Vector3 = Vector3.ZERO
## THE HUNT. `_hunt` is the beat of the predatory sequence, not a boolean: 0 idle, 1 stalking,
## 2 treading (the wiggle), 3 in the air, 4 the aftermath.
var _prey: Node3D = null
var _hunt: int = 0
var _wiggle_t: float = 0.0
var _freeze_t: float = 0.0        ## a stalking cat stops dead whenever it thinks it was seen
var _hunt_cd: float = 8.0
var _after_t: float = 0.0         ## the "I meant to do that" wash after a miss
var _pouncing: bool = false       ## this leap is a pounce, so the landing has to resolve it
var _carry: String = ""           ## what it is bringing you
var _chatter_cd: float = 0.0
## The zoomies, and object play — the other two things a cat does that nothing else on this
## rig does. Both are on cooldowns rather than dice per frame, so they read as events.
var _zoom_t: float = 0.0
var _zoom_cd: float = 30.0
var _zoom_to: Vector3 = Vector3.ZERO
var _play_t: float = 0.0
var _play_cd: float = 20.0
var _play_spot: Vector3 = Vector3.ZERO
## Waking up is a beat of its own: a cat that has been asleep STRETCHES before it walks.
var _stretch_t: float = 0.0
var _was_asleep: bool = false
## ENERGY, 0..1 — the thing that makes one evening different from the next.
##
## Everything the cat does for its own reasons (play, the zoomies, hunting, how long it will
## sit before it lies down) is gated on this rather than on a bare cooldown, so the animal has
## lively spells and lazy ones instead of firing every behaviour on a metronome. It falls with
## exertion, recovers with rest, and is pushed up hard at dawn and dusk — cats are crepuscular
## and the evening madness is the single most predictable thing about them.
var _energy: float = 0.6
## IDLE ATTENTION. A settled cat is not a statue: it looks at things, holds the look for a
## while, and looks somewhere else. `_glance_cd` is when it next picks something.
var _glance_cd: float = 1.0
var _glance_at: Vector3 = Vector3.ZERO
var _glance_hold: float = 0.0
## SELF-GROOMING. `_wash_t` is how long this bout has left and `_wash_style` which of the four
## it is; a cat washing its flank for six seconds and then its ear is a different animal from
## one running the same paw-lick loop for ever.
var _wash_t: float = 0.0
var _wash_style: int = 0
var _wash_cd: float = 12.0
var _shake_cd: float = 25.0
## Small per-frame speed variation, so the walk is not metronomic.
var _pace: float = 1.0
var _pace_cd: float = 0.0
## The occasional seated weight-shift: a settled cat re-plants its weight every ten or
## twenty seconds, irregularly — the difference between an animal at rest and a loop.
var _shift_cd: float = 8.0
var _shift_t: float = 0.0
var _shift_dur: float = 1.0
var _shift_amp: float = 0.0
## The held sleeping spot — picked once when the player turns in, cleared when they rise.
var _sleep_target: Vector3 = Vector3.ZERO
## How long it has been walking at the chosen spot without getting any closer, and the best it
## has managed — a held target it cannot reach is a cat that paces all night (see `_bed_down`).
var _bed_stall: float = 0.0
var _bed_best: float = 1e9
## The leap, in flight: time left, and the two ends of the arc. While `_jump_t` is positive
## the state machine hands the animal over to _fly_jump and nothing else moves it.
var _jump_t: float = 0.0
var _jump_cd: float = 0.0
## The anticipation: a jump is armed, the crouch is held, and the body has NOT left the
## deck yet. §-minimum 8 frames — the loaded spring is the beat that sells the leap, and
## the old jump skipped it entirely (airborne on the frame it decided).
var _jump_wind: float = 0.0
var _jump_from: Vector3 = Vector3.ZERO
var _jump_to: Vector3 = Vector3.ZERO
## THE BAIT TRAIL — the player's recent footsteps, oldest crumb first. Written by
## `_physics_process` (a recording, so it is never decimated) and read by `_trail_goal`.
var _trail: PackedVector3Array = PackedVector3Array()
## Last tick's player position, for the teleport break. INF means nothing sampled yet.
var _trail_prev: Vector3 = Vector3.INF
## True while the cat is steering at a CRUMB rather than at the player, so the follow branch
## knows whether `stop_at` means "short of the player" or "onto the waypoint".
var _trail_live: bool = false
## Seconds pinned on the same crumb — past TRAIL_STALL the thread is walked on anyway.
var _trail_stall: float = 0.0
## The string-pull's throttle, and a LATCH on its verdict: re-deciding a shortcut every frame
## is the same oscillation the detour fan's 0.8 s side commitment exists to stop.
var _pull_cd: float = 0.0
var _pull_free: bool = false
## The turn ease — 1.0 on a straight, TURN_EASE_MIN going into a right-angle doorway.
var _turn_slow: float = 1.0

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
## `verbs` is what the interaction ray reads, and both are set together in _sync_verbs.
func available_verbs() -> Array:
	if not friend:
		return ["SAY HELLO"]
	return ["PET", "COME"] if _stayed else ["PET", "STAY"]

func _sync_verbs() -> void:
	var v: Array[String] = []
	for s in available_verbs():
		v.append(String(s))
	_touch.verbs = v

## `Interactable.interacted` carries ONE argument — the verb. It does not pass the player, so
## the player is looked up here; connecting a two-argument handler silently fails to fire at
## all, which is exactly what made the first version of this cat unbefriendable.
func _on_touched(verb: String) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not friend:
		friend = true
		_enter(State.FOLLOW)
		_sync_verbs()
		Journal.discover("creature_ship_cat")
		AudioDirector.play_one_shot("cat_chirp", global_position, -18.0)
		if hud and hud.has_method("toast"):
			hud.toast("The cat looks up, decides about you, and comes along.")
		return
	# THE FOLLOW TOGGLE — the owner's ask, verbatim: the player can tell it to stop
	# following; it then does its own thing; coming back and interacting perks it up and
	# it follows again. STAY anchors it to the spot it was told at (see _stay_behaviour);
	# COME — or, for the player who forgot which verb they left it on, any fresh greeting
	# — releases it with the little perk-up a cat gives someone it decided to keep.
	if verb == "STAY":
		_stayed = true
		_stay_spot = global_position
		_sync_verbs()
		_enter(State.SIT)
		AudioDirector.play_one_shot("cat_chirp", global_position, -22.0)
		if hud and hud.has_method("toast"):
			hud.toast("The cat blinks slowly, and settles in to keep its own counsel.")
		_meow_cd = 4.0
		return
	if verb == "COME":
		_stayed = false
		_sync_verbs()
		_enter(State.FOLLOW)
		_stretch_t = 0.0
		if _rig != null:
			_rig.call("delight", 0.7)      # the perk-up: ears would go up if it had them
			_rig.call("tail_flick", 0.8)
		AudioDirector.play_one_shot("cat_chirp", global_position, -16.0)
		if hud and hud.has_method("toast"):
			hud.toast("The cat perks up and falls in beside you.")
		_meow_cd = 4.0
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
	# Every ease in this file is `1 - exp(-rate * dt)`: this animal runs under AiBudget and
	# is handed SUMMED deltas up to 0.15 s, where `delta * k` overshoots — measured as the
	# whole cat snapping to its turn/lean targets in one think (tests/CatReviewProbe bigdt:
	# the two dt paths disagreed by 19.7 deg on the same half-second of slope ease).
	# THE BODY NODE IS NOT AN ANIMATION CHANNEL — held at rest, permanently, and asserted
	# by tests/CatJointProbe (body_node_rot_max_deg < 1). Thirteen lines in this file used
	# to rotate and lift the whole animal about its own origin to express things a cat
	# expresses with its spine: the owner's "the game rotates the entire cat instead of
	# moving a limb". Every one of them now calls the rig instead (cat_rig section 5f).
	# The ONLY whole-animal transforms left in this file are the ones that are genuinely
	# whole-animal: the steering yaw in `_face`, and the jump arc's translation.
	_body.rotation = Vector3.ZERO
	_body.position = Vector3.ZERO
	if _fed_wiggle > 0.0:
		_fed_wiggle -= delta * 0.7
		if _rig != null:
			_rig.call("delight", clampf(_fed_wiggle, 0.0, 1.0))
	# A SLOPE ONLY EXISTS UNDER A WALKING CAT. _walk_toward is the only writer, so an animal
	# that stopped on a ramp wore the ramp's pitch for ever — sitting, sleeping, being petted
	# — because nothing ever decayed it. Ease it home whenever the body is not travelling.
	if _last_speed < 0.05:
		_slope = lerpf(_slope, 0.0, 1.0 - exp(-4.0 * delta))
	# The lean into a grade is a TRUNK pitch now (cat_rig.slope): the node version tipped
	# the animal as a plank and left its paws intersecting the ramp, because nothing under
	# it re-solved. Pitching the chest lets the four legs solve to the ground they are
	# actually on.
	if _rig != null:
		_rig.call("slope", _slope)
	_focus_w = maxf(0.0, _focus_w - delta * 1.5)
	# BEFORE ANYTHING ELSE DECIDES WHERE TO GO, GET OUT OF WHATEVER WE ARE IN. Unconditional
	# and state-independent on purpose: a predictive gate cannot rescue an animal that is
	# already buried, and every gate in this file is predictive.
	_unbury()
	if _jump_cd > 0.0:
		_jump_cd -= delta
	# THE WIND-UP: crouched, loaded, still on the deck. Owns the animal like the flight
	# does, so nothing walks it off its own launch spot mid-anticipation.
	if _jump_wind > 0.0:
		_jump_wind -= delta
		_last_speed = 0.0
		if _jump_wind <= 0.0:
			_jump_t = JUMP_SEC
			_enter(State.JUMP)
			AudioDirector.play_one_shot("cat_chirp", global_position, -24.0)
		_drive_rig(delta)
		return
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
	var flat: Vector3 = _arc_point(_jump_from, _jump_to, k)
	# Peak height scales with the rise so a small hop does not launch the cat at the
	# deckhead, with a floor so a flat leap still leaves the ground.
	var lift: float = maxf(_jump_to.y - _jump_from.y, 0.0) * 0.35 + 0.14
	var before_fly: Vector3 = global_position
	global_position = flat
	# A LEAP TURNS THE SAFETY NET OFF, AND THAT IS WHY IT NEEDS ONE OF ITS OWN.
	#
	# `_unbury` runs unconditionally every frame precisely because no predictive gate can
	# rescue an animal that is already inside something — but it runs BEFORE this, and this
	# then overwrites the position it just corrected. So for the whole flight the one check
	# that cannot be fooled is disabled, and `_arc_clear`'s four samples are all that stands
	# between the cat and a bulkhead. Four samples are not a proof: the probe kept catching
	# the animal ~750 mm inside the quarters at 90% of an arc whose endpoints tested clear.
	#
	# So the arc gives up the moment it stops being clear, rather than flying on and hoping.
	# The cat drops where it last fitted, which is a slightly disappointing leap and never a
	# cat in a wall.
	if not _step_clear(global_position, (_jump_to - _jump_from).normalized()):
		global_position = before_fly
		_jump_t = 0.0
		_jump_cd = JUMP_CD
		_reseat()
		if _pouncing:
			_resolve_pounce()
		return
	_moved_frame += global_position.distance_to(before_fly)
	_face(_jump_to, delta * 2.0)
	_last_speed = RUN_SPEED
	# THE FLIGHT IS PHASED, NOT A FREEZE-FRAME — the owner's leap, beat for beat: push off
	# the hinds, sprawl through the top, then front feet reaching first into the landing.
	# One static mid-air stretch across the whole arc read as an animal hung from a wire.
	# `play_seq([], pose, rate)` is the grammar-free pose set (the family grammar would
	# route jump -> jump_descend through the sit machinery).
	if _rig != null:
		if k < 0.24:
			_rig.call("play_seq", [], "jump_launch", 16.0)
		elif k < 0.60:
			_rig.call("play_seq", [], "jump", 14.0)
		else:
			_rig.call("play_seq", [], "jump_descend", 14.0)
		# ...AND THE BODY ROTATES THROUGH THE ARCH. The trunk pitch follows the arc's own
		# tangent — nose-up on the way up, level over the top, nose-down into the descent —
		# through the same skeletal slope channel the ramps use, so it is chest-and-pelvis
		# rotation, never the node. The stabiliser keeps the HEAD level on top of it, which
		# is exactly the flat-eyed arc every slow-motion cat jump shows.
		var horiz: float = maxf(Vector2(_jump_to.x - _jump_from.x,
			_jump_to.z - _jump_from.z).length(), 0.2)
		var lift2: float = maxf(_jump_to.y - _jump_from.y, 0.0) * 0.35 + 0.14
		_rig.call("slope", atan2(PI * cos(k * PI) * lift2, horiz) * 0.85)
	if _jump_t <= 0.0:
		global_position = _jump_to
		_jump_cd = JUMP_CD
		_reseat()
		# LAND -> SETTLE: fore-paws-first absorption held a beat, then the state's own pose.
		if _rig != null:
			_rig.call("play_seq", [["jump_land", 0.16, 14.0]],
				String(STATE_POSE.get(_state, "stand")), 8.0)
			_rig.call("tail_flick", 0.8)   # the counterweight swinging through touchdown
		# A POUNCE RESOLVES WHERE IT LANDS, not where it was aimed. Done here rather than in
		# the state machine because the leap deliberately owns the animal until touchdown, so
		# this is the only frame that knows whether the cat is standing on the bird.
		if _pouncing:
			_resolve_pounce()

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
	# The wash itself is entirely skeletal (cat_rig's groom layer drives the neck, head and
	# forepaw); the node sway that used to ride on top of it was the whole animal rocking
	# on its own origin with four paws welded flat, which is what made grooming read oddly.

## After: it comes with you, at its own pace, and settles when you do.
func _companion(delta: float, player: Node3D) -> void:
	var ppos: Vector3 = player.global_position
	var d: float = global_position.distance_to(ppos)
	_hunt_cd = maxf(0.0, _hunt_cd - delta)
	_zoom_cd = maxf(0.0, _zoom_cd - delta)
	_play_cd = maxf(0.0, _play_cd - delta)
	_chatter_cd = maxf(0.0, _chatter_cd - delta)
	_wash_cd = maxf(0.0, _wash_cd - delta)
	_shake_cd = maxf(0.0, _shake_cd - delta)
	_tick_energy(delta)
	_idle_attention(delta, ppos, d)

	# WAKING UP IS ITS OWN BEAT. A cat that has been asleep does not stand up and walk: it
	# stretches, at length, and only then is it awake. Held here rather than inside the sleep
	# branch because waking can be caused by anything — the player getting up, a bird, a
	# noise — and the stretch has to happen whatever ended the sleep.
	if _state == State.SLEEP:
		_was_asleep = true
	elif _was_asleep:
		_was_asleep = false
		_stretch_t = _rng.randf_range(1.3, 2.4)
		if _rig != null:
			_rig.call("shake", 1.0)          # the first thing anything does on getting up
		# ...and a cat that has just woken is the likeliest cat in the world to tear off
		# across the deck for no reason at all. A full night's rest is what pays for it.
		if _rng.randf() < 0.30 + _energy * 0.45:
			_zoom_cd = minf(_zoom_cd, 2.5)
	# THE CHATTER. A cat that can see a bird it cannot possibly reach does not give up on it —
	# it fixes on the thing and makes that ridiculous staccato rattle. It is one of the most
	# recognisable things a cat does and it costs almost nothing here, so it rides ALONGSIDE
	# whatever the animal is otherwise doing rather than owning a state: no `return`, no beat
	# in the machine, just a head tremor and a look at a gull that is already in the air.
	if _hunt == 0 and _carry == "" and _chatter_cd <= 0.0:
		for g in get_tree().get_nodes_in_group("deck_gull"):
			var n: Node3D = g as Node3D
			if n == null or not is_instance_valid(n) or not _airborne(n):
				continue
			if global_position.distance_to(n.global_position) > HUNT_M:
				continue
			# A WALKING CAT GLANCES; A SITTING CAT STARES. This watch ran at full weight in
			# every state, and it is not gated by `_hunt_cd` — so with any gull in the air
			# within eleven metres (i.e., most of the time on this deck), the companion
			# walked with its head hauled a full look-clamp toward the bird. That is the
			# owner's eight-times-reported "head defaults to pointing sideways while it
			# walks": not a rig constant, an attention weight no walking animal would hold.
			# Stationary keeps the locked-on stare the chatter deserves; on the move it is
			# a flick of the ears and eyes, and the head stays on the line of travel.
			# Stationary only: a moving cat's chatter-watch is fully suppressed at the
			# rig feed (see _drive_rig) — the 0.22 walking whisper this used to carry was
			# still a visible head-turn, and the owner's rule is absolute.
			_watch(n.global_position, 1.0)
			if _rig != null:
				if _last_speed <= 0.2:
					_rig.call("chatter", 1.0)
				# A bird it cannot have is the single most reliable tail-lash there is.
				if _rng.randf() < delta * 2.2:
					_rig.call("tail_flick", 0.9)
			if _meow_cd <= 0.0:
				AudioDirector.play_one_shot("cat_chirp", global_position, -26.0)
				_meow_cd = 3.0
			_chatter_cd = _rng.randf_range(0.0, 0.35)   # renewed while the bird is still up
			break

	# ...and a hunt is over the moment the player leaves. The gate below only STOPS the hunt
	# branch running at range; without this the animal keeps its prey and its beat and picks
	# the stalk back up mid-crouch whenever the player wanders back, which reads as the cat
	# having been paused rather than having given up.
	# (A STAYED cat's hunt is its own business — the companion leash below only applies
	# while it is actually a companion.)
	if not _stayed and _hunt > 0 and d >= RUN_M:
		_end_hunt(false)

	# IS THE PLAYER RESTING? Not a flag they set — a thing the cat works out by watching. A
	# player who has not moved for SETTLE_SEC is resting whether they meant to or not, which
	# is also true of lying down and sitting, and it means the cat settles when you stop to
	# fish or read rather than only in a bed.
	var moved: float = ppos.distance_to(_last_player_pos)
	_last_player_pos = ppos
	# A STAYED cat does not care whether YOU are moving: its calm is its own, so `_still`
	# accumulates unconditionally and the sit -> doze -> sleep ladder runs on its clock.
	var resting: bool = _stayed or moved < 0.05 * maxf(delta, 0.001) * 60.0
	if bool(player.get("_lying")) or bool(player.get("crouching")):
		resting = true
	_still = (_still + delta) if resting else 0.0

	# BEING PETTED WINS OVER EVERYTHING for a moment: a head-bump you can interrupt is not
	# a head-bump. Short, so it never reads as the cat freezing.
	if _pet_t > 0.0:
		_enter(State.PET)
		_face(ppos, delta)
		# THE PET REACTION, IN THE ANIMAL. This was `_body.rotation.z = k * 0.22` — the
		# entire cat rolled 12.6 degrees onto its side, paws still flat on the deck, which
		# is the owner's "the whole model tilts to the side instead of the cat reacting
		# happy". A real cat arches its back up into the hand and presses its head into
		# it; cat_rig.pet does both, and the tail flag below finishes the reading.
		if _rig != null:
			_rig.call("pet", sin((1.0 - _pet_t / PET_SEC) * PI))
		_stretch_t = 0.0     # a hand on it ends the stretch; nothing outranks being petted
		return

	# THE STRETCH ON WAKING, below the hand but above everything else. Not if you have already
	# walked off, though: a cat that has to catch up does not stop to stretch first, and a
	# companion that does reads as broken rather than as characterful.
	if _stretch_t > 0.0 and d < RUN_M:
		_stretch_t -= delta
		_enter(State.STRETCH)
		_last_speed = 0.0
		_reseat()
		return
	_stretch_t = 0.0

	# STAYED: it was told to keep its own counsel, and it does — on its own patch, on its
	# own clock, with its own hunts. Below the pet and the wake-stretch (a hand on a
	# stayed cat still works) and above everything that follows the player around.
	if _stayed:
		_stay_behaviour(delta, ppos, d)
		return

	# THE FISH. It can smell one in your hands and it does not pretend otherwise: it closes
	# right up, and it will not settle while you are holding it.
	var has_fish: bool = _player_holding_fish(player)
	if has_fish and d < FISH_M:
		_enter(State.FISH)
		# Trailed like the follow is: FISH_M is 9 m and a cat that can smell a fish through a
		# bulkhead should still come round by the door.
		var fish_aim: Vector3 = _trail_goal(ppos, delta)
		_walk_toward(fish_aim, TROT_SPEED * _ease_turn(fish_aim, delta), delta,
			0.05 if _trail_live else 0.9)
		if _meow_cd <= 0.0:
			_meow_cd = _rng.randf_range(4.0, 9.0)
			AudioDirector.play_one_shot("cat_chirp", global_position, -20.0)
		return

	# THE PLAYER TURNING IN OUTRANKS EVERY GAME THE CAT KNOWS, and it has to, because the
	# alternative shipped and CatProbe caught it on the first run: `_still` climbs while the
	# player lies there, both cooldowns expire, and the cat spends the night doing zoomies and
	# pouncing on nothing three metres from the bed while the sleep branch below never gets a
	# frame. That is the same "paces beside the bed all night" the s37 sleep-spot fix cured
	# from a different cause, which is a good reason to keep this test and a better reason to
	# put the check HERE rather than further down where it reads more naturally.
	if _player_asleep(player):
		_bed_down(delta, ppos)
		return
	_sleep_target = Vector3.ZERO

	# THE AFTERMATH OF A MISS — see the sequence's header. It sits down exactly where it
	# failed and washes, with enormous dignity, as though that had been the plan. Held above
	# everything except being petted and being offered a fish, because a cat interrupted
	# mid-excuse is not a cat.
	if _after_t > 0.0:
		_after_t -= delta
		_enter(State.GROOM)
		_last_speed = 0.0
		_reseat()
		return

	# ...AND THE PRIZE. A cat brings what it catches to the people it lives with. It is not a
	# gift in any sense the cat would recognise, but it is the single most cat thing there is,
	# and it is worth the whole hunt.
	if _carry != "":
		_enter(State.GIFT)
		_watch(ppos + Vector3(0, 1.2, 0), 0.8)
		if d > 1.3:
			_walk_toward(ppos, TROT_SPEED, delta, 1.1)
		else:
			_deliver(player)
		return

	# THE HUNT. Only while the player is not being left behind — a companion that abandons you
	# across the rig to stalk a gull is a bug, however true to life.
	if (_hunt > 0 or (_hunt_cd <= 0.0 and _energy > 0.30)) and d < RUN_M:
		if _hunt_step(delta):
			_wash_t = 0.0        # a bird ends a wash mid-stroke, which is the honest order
			return

	# THE ZOOMIES, and object play. Both need the player to be somewhere near and settled,
	# because both read as the cat entertaining itself rather than ignoring you.
	# GATED ON MOOD, not just on a clock. A tired cat does not get the zoomies however long it
	# has been since the last ones, and a cat at dusk with a full tank barely stops. This is
	# what makes two evenings different without a second behaviour tree.
	if _zoom_t > 0.0 or (_zoom_cd <= 0.0 and d < FOLLOW_FAR and _still > 5.0 and _energy > 0.62):
		if _zoomies(delta, ppos):
			return
	if _play_t > 0.0 or (_play_cd <= 0.0 and d < FOLLOW_FAR and _still > SETTLE_SEC * 0.5
			and _energy > 0.34):
		if _play(delta):
			return

	# NO DISTANCE GIVES UP THE FOLLOW ANY MORE. LOST_M (26 m) used to park the animal the
	# moment the player crossed the rig — the owner's ask is the opposite: it knows where
	# you are from anywhere, and if it is following you it WORKS the problem. The detour
	# fan gives it the means (it rounds corners and takes the stairs a tread at a time),
	# and where the rig genuinely cannot be walked — a dive, the boat — it closes to the
	# nearest reachable spot and waits there, which is what a real cat does at the top of
	# a companionway. The player who wants it parked has the STAY verb now, which is a
	# decision, not a distance.
	# THE COMPANIONABLE GAP SHRINKS WHEN YOU ARE STANDING ABOVE IT — and this gate, not the
	# one inside `_walk_toward`, is the one that decides whether the animal moves at all.
	# `d` is a 3D distance, so a player up on a 1.1 m ledge only 1.35 m away measures 1.87 m
	# — inside FOLLOW_NEAR — and the cat declares itself arrived and sits down on the deck
	# below, having never called the walk at all. Every gate in the leap path was verified
	# passing at that exact spot (tests/LeapScratch.tscn) while the shipping loop never
	# reached one of them: the jump was unreachable from the STATE MACHINE, not from the
	# geometry. Both the gate and the stop distance take the same shrunken gap now.
	var near_gap: float = FOLLOW_NEAR
	if ppos.y - global_position.y > CLIMB_UP:
		near_gap = 0.35
	if d > near_gap:
		# ...and it BREAKS INTO A RUN when it has been left behind, which is the one moment a
		# follower reads as an animal rather than a marker: same walk otherwise.
		var running: bool = d > RUN_M
		_enter(State.RUN if running else State.FOLLOW)
		_still = 0.0
		_pace_cd -= delta
		if _pace_cd <= 0.0:
			_pace = _rng.randf_range(0.86, 1.14)
			_pace_cd = _rng.randf_range(0.6, 2.2)
		# BAIT-TRAILED. The goal is a point on the route the player actually walked, not the
		# player — see the trail section. It degrades to `ppos` the moment the trail has
		# nothing usable, so this line is the s45 behaviour whenever there is no route to
		# follow. `stop_at` follows the goal: stopping FOLLOW_NEAR short of a WAYPOINT would
		# park the animal a metre before every corner. The distance that decides whether to
		# walk at all is still `d`, which is measured to the player.
		var aim: Vector3 = _trail_goal(ppos, delta)
		# YOU CANNOT BE "NEAR" SOMEONE WHO IS STANDING ABOVE YOU. `FOLLOW_NEAR` is the
		# companionable gap on level ground, and applied to a player up on a crate it parked
		# the animal 2.2 m out on the deck — where the ledge is still a metre beyond its nose,
		# so the jump probe never fires and the cat simply gives up near the thing it should
		# be hopping onto. Filmed: staged at a real 1.00 m ledge, the cat walked to z 5.80 and
		# stopped dead, 2.2 m short of a lip at z 8.00, for all 270 frames.
		# So when the player is more than a step above, the target is the FOOT of whatever
		# they are on: close right up, let the ledge probe see it, and let the leap decide.
		_walk_toward(aim, (RUN_SPEED if running else (TROT_SPEED if d > FOLLOW_FAR else WALK_SPEED))
			* _pace * _ease_turn(aim, delta), delta, 0.05 if _trail_live else near_gap)
		return
	# A WASH IN PROGRESS FINISHES. Below the hunt on purpose — a bird interrupts a wash, which
	# is exactly what happens — but above settling, so the cat is not yanked out of it by its
	# own idle timer.
	if _self_groom(delta):
		return

	# Within arm's reach of a player who is not going anywhere.
	if _still > SETTLE_SEC:
		_settle(delta)
	else:
		_enter(State.SIT)
		_pose_sit(delta)
		# ...and a settled, unbothered cat washes. This is where most of the animal's screen
		# time actually is, so it is where the variety matters most.
		_maybe_wash(delta)
		# The shake: on waking, and otherwise rarely and at random. It is a whole-body event
		# that costs one line and reads from right across the deck.
		if _shake_cd <= 0.0 and _rng.randf() < delta * 0.25:
			if _rig != null:
				_rig.call("shake", 1.0)
			_shake_cd = _rng.randf_range(40.0, 140.0)

## A STAYED CAT'S OWN LIFE. Everything here already existed as companion behaviour — the
## hunt, the zoomies, the play pounce, the washes, the sit -> doze -> sleep ladder — the
## only new idea is the ANCHOR: games orbit the spot it was told to stay at instead of the
## player, the hunt ignores the companion leash entirely, and anything that carried it off
## its patch (a stalk, a zoomie) strolls back afterwards. A caught feather is still
## brought over — but only when you come near; it does not break a STAY to deliver.
func _stay_behaviour(delta: float, ppos: Vector3, d: float) -> void:
	if _carry != "":
		if d < 6.0:
			_enter(State.GIFT)
			_watch(ppos + Vector3(0, 1.2, 0), 0.8)
			if d > 1.3:
				_walk_toward(ppos, TROT_SPEED, delta, 1.1)
			else:
				var player: Node3D = get_tree().get_first_node_in_group("player")
				if player != null:
					_deliver(player)
		else:
			_enter(State.SIT)
			_pose_sit(delta)
			_watch(ppos + Vector3(0, 1.2, 0), 0.4)
		return
	if _after_t > 0.0:
		_after_t -= delta
		_enter(State.GROOM)
		_last_speed = 0.0
		_reseat()
		return
	if _hunt > 0 or (_hunt_cd <= 0.0 and _energy > 0.30):
		if _hunt_step(delta):
			_wash_t = 0.0
			return
	if _zoom_t > 0.0 or (_zoom_cd <= 0.0 and _still > 5.0 and _energy > 0.62):
		if _zoomies(delta, _stay_spot):
			return
	if _play_t > 0.0 or (_play_cd <= 0.0 and _still > SETTLE_SEC * 0.5 and _energy > 0.34):
		if _play(delta):
			return
	# Wandered off the patch? Stroll home. 4 m of slack, because a cat told to stay in a
	# spot understands the spot to be roughly the size of a room.
	if global_position.distance_to(_stay_spot) > 4.0:
		_enter(State.FOLLOW)
		_walk_toward(_stay_spot, WALK_SPEED, delta, 1.0)
		return
	if _self_groom(delta):
		return
	if _still > SETTLE_SEC:
		_settle(delta)
	else:
		_enter(State.SIT)
		_pose_sit(delta)
		_maybe_wash(delta)
		if _shake_cd <= 0.0 and _rng.randf() < delta * 0.25:
			if _rig != null:
				_rig.call("shake", 1.0)
			_shake_cd = _rng.randf_range(40.0, 140.0)

## THE PLAYER HAS TURNED IN. A cat does not wait out a night standing up: it comes over, finds
## a spot NEAR the bed rather than on the walking line, and curls up there. The spot is PROBED
## (see _sleep_spot) — a hand-typed offset from a bed that another session moves is the whole
## floating-prop family of bugs in this repo.
func _bed_down(delta: float, ppos: Vector3) -> void:
	# THE SPOT IS CHOSEN ONCE AND HELD. _sleep_spot used to be re-run every frame, and its
	# winning candidate depends on the cat's own position — so as the animal walked, the target
	# could flip between two candidates and, in the wrong geometry, oscillate for ever: a cat
	# that paces beside the bed all night instead of lying down (seen as an intermittent probe
	# failure, ~1 run in 5). Hysteresis: keep the chosen spot while the player stays asleep,
	# re-picking only if it drifts out of plausibility.
	##
	## ...AND A HELD TARGET IT CANNOT REACH IS THE SAME BUG WEARING A HAT. The hysteresis above
	## cured the oscillation and replaced it with a cat that walks at one spot for ever: the
	## spot is only re-picked if the PLAYER moves, `_sleep_spot` only proves a thin ray at
	## +0.22 m is clear rather than that the body can walk the whole way, and `_walk_toward`
	## silently refuses a step it cannot take. So the animal closes to whatever the obstruction
	## allows and then stands there pressing into it all night. That is CatProbe's intermittent
	## failure — it fires or does not depending purely on where the cat happened to be standing
	## when the player lay down, which is exactly the shape of a "1 run in 6".
	##
	## The fix is not a longer window. A cat that cannot get to the good spot LIES DOWN WHERE IT
	## IS, which is both what a cat does and a state this machine can always reach.
	if _sleep_target == Vector3.ZERO or ppos.distance_to(_sleep_target) > 3.0:
		_sleep_target = _sleep_spot(ppos)
		_bed_stall = 0.0
		_bed_best = 1e9
	var togo: float = global_position.distance_to(_sleep_target)
	if togo > 0.55:
		# Progress is measured, not assumed: only closing the gap counts as getting there.
		if togo < _bed_best - 0.02:
			_bed_best = togo
			_bed_stall = 0.0
		else:
			_bed_stall += delta
		if _bed_stall > 2.5:
			_sleep_target = global_position
			togo = 0.0
	if togo > 0.55:
		_enter(State.FOLLOW)
		_walk_toward(_sleep_target, WALK_SPEED, delta, 0.35)
	else:
		_enter(State.SLEEP)
		ANIM.drive(_gen_mats, 0.5, 0.0)

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
		ANIM.drive(_gen_mats, 0.5, 0.0)
	else:
		_enter(State.SIT)
		_pose_sit(delta)

func _pose_sit(delta: float) -> void:
	ANIM.drive(_gen_mats, 1.1, 0.0)
	_last_speed = 0.0
	# A sitting cat is on the deck it sat down on — and the seat ray is the only thing that
	# keeps it there if another session moves that deck.
	_reseat()
	# The small weight-shift of a cat that is awake and paying attention. ASSIGNED, never
	# `+=`: a per-tick += without a delta term reaches equilibrium against _process's ease
	# at rate_ratio * amplitude — measured at 75 DEGREES of body yaw on the live game,
	# which drew the cat walking sideways off its own node. The s36 comment on this line
	# argued += was safer than assignment; the opposite was true.
	#
	# ...and OCCASIONAL, not continuous: the old `sin(_t * 0.9)` swayed the seated animal on
	# a metronome, which is the signature of an idle loop. A real cat re-plants its weight
	# every ten or twenty seconds, irregularly, and is otherwise still (the breath layer
	# carries the rest of "alive").
	_shift_cd -= delta
	if _shift_cd <= 0.0 and _shift_t <= 0.0:
		_shift_dur = _rng.randf_range(0.8, 1.4)
		_shift_t = _shift_dur
		_shift_amp = _rng.randf_range(0.04, 0.08) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_shift_cd = _rng.randf_range(9.0, 22.0)
	if _shift_t > 0.0:
		_shift_t -= delta
		# A PELVIS ROLL, not a node yaw. The node version was measured at a constant
		# 4.67 degrees of whole-body tilt in every state the joint probe sampled — the
		# single most persistent piece of "the game rotates the entire cat".
		if _rig != null:
			_rig.call("weight_shift", (_shift_amp / 0.08)
				* sin(clampf(1.0 - _shift_t / _shift_dur, 0.0, 1.0) * PI))
	elif _rig != null:
		_rig.call("weight_shift", 0.0)

## Walk the deck toward a point, stopping `stop_at` short. Kinematic and deliberately simple:
## it steps up a coaming, refuses anything taller, and re-seats on whatever it is standing on
## so it can never walk off into the air.
func _walk_toward(target: Vector3, speed: float, delta: float, stop_at: float) -> void:
	# A REFUSED STEP MUST REPORT ZERO SPEED, and this is the owner's "the legs went floppy
	# for a bit after the cat got caught in a corner".
	#
	# `_last_speed = speed` is assigned at the BOTTOM of this function, below every early
	# `return`. So a cat whose every candidate step is refused kept its last COMMANDED
	# speed for ever while actually covering no ground — and cat_rig reads the pair: zero
	# distance unloads `_gait_w`, but the stale speed keeps `_speed_s` (and therefore the
	# gait mix) pinned wherever it was. A cat that wedges while running therefore drops
	# into the turn-in-place shuffle — which `_gait_w` falling is exactly what opens —
	# running at GALLOP paw lift and gallop duty, i.e. 80% of the cycle airborne, on an
	# animal going nowhere. Four legs paddling in the air is precisely "floppy".
	_last_speed = 0.0
	_detour_t = maxf(0.0, _detour_t - delta)
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
	# THE LEDGE THE FOOTFALL PROBE CANNOT SEE — and the reason the leap almost never fired.
	#
	# That probe starts at `STEP_UP + 0.3` = 0.75 m above the cat's feet, while `JUMP_UP` is
	# 1.25. Anything between those heights passes UNDER the ray, which then finds the lower
	# deck beyond and reports a rise of zero: the gate below reads "flat ground", the volume
	# check refuses the step because the lip is solid, and the animal walks into the face.
	# The jump could only ever fire in the narrow 0.62-0.75 m band — the owner's "clean up
	# the jump, and make it more frequent".
	#
	# So when the direct step is REFUSED, look higher before giving up. Only then: this ray
	# is the expensive, greedy question and asking it every step is what would make the cat
	# leap at scenery it should walk around.
	#
	# AND IT HAS TO RUN BEFORE THE DETOUR FAN, which is where the first cut of this put it
	# and why it changed nothing: the fan RETURNS when every candidate is refused, so on the
	# exact frames a ledge is worth looking for, control never reached the probe. Filmed at a
	# real 0.85 m ledge — inside the band that was invisible — and the telemetry read y 18.00
	# across all 270 sampled frames, i.e. identical to the pre-fix animal. Dead code passes
	# every test that does not watch the animal.
	if rise <= CLIMB_UP and not _step_clear(Vector3(want.x, ground, want.z), dir) \
			and _jump_t <= 0.0 and _jump_wind <= 0.0 and _jump_cd <= 0.0:
		# LOOK WHERE THE LANDING IS, NOT WHERE THE NEXT FOOTFALL IS — and that is a second
		# thing the first cut got wrong. `want` is ONE STEP ahead (26 mm at a walk), while
		# `_step_clear` refuses the step when the cat's NOSE sphere touches the lip, which is
		# `_body_len()/2 - r + r` = about 0.33 m out. So a ray at `want` comes down a third of
		# a metre SHORT of the ledge, hits the deck the cat is already standing on, and reports
		# a rise of zero — the probe fired, found flat ground, and the animal walked into the
		# face exactly as before. Filmed twice against real 0.85 m and 1.10 m ledges before the
		# telemetry (y pinned at 18.00 across 270 frames) made it obvious.
		#
		# So probe a body-length out, and if a ledge is there, that probed point IS the
		# landing — jumping to `want` would put the cat down in mid-air off the lip.
		var lookahead: Vector3 = global_position + dir * (_body_len() * 0.95)
		var hq := PhysicsRayQueryParameters3D.create(
			lookahead + Vector3(0, JUMP_UP + 0.45, 0), lookahead + Vector3(0, 0.05, 0))
		hq.collision_mask = 1
		hq.collide_with_areas = false
		hq.exclude = _walk_skip()
		var hhit: Dictionary = world.direct_space_state.intersect_ray(hq)
		if not hhit.is_empty():
			var top: float = (hhit["position"] as Vector3).y
			var lift: float = top - global_position.y
			# ONLY CLAIM THE LEDGE IF THE LEAP IS ACTUALLY ON. Raising `rise` past CLIMB_UP
			# hands control to the jump gate below, which RETURNS whether or not it fires —
			# so a ledge the cat may see but not take (out of the reachability ceiling, arc
			# fouled, landing occupied) converted a perfectly ordinary walk-around into a
			# dead stop. Measured: CatHuntProbe's stalk froze 2.26 m short of the bird and
			# never pounced, because a structure near the deck answered this ray and the
			# refused jump ate the frame the detour fan should have had. Prove the whole
			# leap here; anything less and the fan keeps the step, as it did before.
			if lift > CLIMB_UP and lift <= JUMP_UP and _reachable_up(top) \
					and _step_clear(Vector3(lookahead.x, top, lookahead.z), dir) \
					and _arc_clear(Vector3(lookahead.x, top, lookahead.z), dir):
				want = Vector3(lookahead.x, top, lookahead.z)
				ground = top
				rise = lift
	if not _step_clear(Vector3(want.x, ground, want.z), dir):
		# THE DETOUR FAN — navigation for an animal with no navmesh, and the cure for the
		# corner the owner watched it wedge in.
		#
		# The old slide tried exactly the two perpendiculars and remembered nothing: a
		# doorway 30 degrees off the line was invisible (both tangents parallel the wall),
		# and at a concave corner the choice was re-rolled from scratch every frame, so
		# the animal flipped +90/-90/+90 against the pocket for ever — "caught in a
		# corner". Two changes, both cheap:
		#
		#   * A FAN, nearest-the-goal first: ±29, ±52, ±83, ±115 degrees. The first clear
		#     candidate wins, so the cat deviates as little as the geometry allows and can
		#     still take a heading past perpendicular — rounding a corner's far edge needs
		#     one — while anything beyond ±115 stays forbidden (a detour that points back
		#     the way it came is how an animal orbits a pillar).
		#   * COMMITMENT: taking a detour remembers its SIDE for 0.8 s, and the fan tries
		#     that side first at every magnitude while the memory lasts. Deciding is
		#     cheap; re-deciding every frame is what oscillates. The memory only biases
		#     the ORDER — if the committed side closes, the other side still gets tried
		#     the same frame.
		#
		# Cost: only on BLOCKED frames, worst case 8 candidate probes; an unobstructed
		# walk pays nothing.
		var slid := false
		var first: float = _detour_side if (_detour_t > 0.0 and absf(_detour_side) > 0.5) else 1.0
		for mag in [0.5, 0.9, 1.45, 2.0]:
			if slid:
				break
			for side_k in [first, -first]:
				var alt: Vector3 = dir.rotated(Vector3.UP, side_k * float(mag))
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
				_detour_side = signf(side_k)
				_detour_t = 0.8
				slid = true
				break
		if not slid:
			# A DEAD POCKET — the whole fan refused. Greedy steering can walk into a U it
			# cannot steer out of (everything inside ±115° is blocked and the exit is
			# dead astern), which is exactly where the probe's COME test wedged: 0.8 m of
			# progress into a bunk niche and then zero for eight seconds, deterministic.
			# A real animal BACKS OUT. After 0.35 s of fully-refused frames, take the
			# reverse step if it is clear, and flip the committed side — so the next
			# approach rounds the obstacle the other way instead of re-entering the same
			# pocket for ever.
			_detour_stall += delta
			if _detour_stall > 0.35:
				var back: Vector3 = -dir
				var bwant: Vector3 = global_position + back * minf(speed, WALK_SPEED) * delta
				var bq := PhysicsRayQueryParameters3D.create(
					bwant + Vector3(0, STEP_UP + 0.3, 0),
					bwant + Vector3(0, STEP_UP + 0.3, 0) - Vector3(0, STEP_UP + 1.4, 0))
				bq.collision_mask = 1
				bq.collide_with_areas = false
				bq.exclude = _walk_skip()
				var bhit: Dictionary = world.direct_space_state.intersect_ray(bq)
				if not bhit.is_empty():
					var bground: float = (bhit["position"] as Vector3).y
					if absf(bground - global_position.y) <= CLIMB_UP \
							and _step_clear(Vector3(bwant.x, bground, bwant.z), back):
						var before_back: Vector3 = global_position
						global_position = Vector3(bwant.x, bground, bwant.z)
						_moved_frame += global_position.distance_to(before_back)
						_last_speed = minf(speed, WALK_SPEED) * 0.6
						_detour_side = -_detour_side if absf(_detour_side) > 0.5 else 1.0
						_detour_t = 1.2
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
		if rise <= JUMP_UP and _jump_t <= 0.0 and _jump_wind <= 0.0 and _jump_cd <= 0.0 \
				and _reachable_up(ground) \
				and _step_clear(Vector3(want.x, ground, want.z), dir) \
				and _arc_clear(Vector3(want.x, ground, want.z), dir):
			# ...and the ARC has to be clear, not just the ledge. Same hole the pounce had:
			# `_fly_jump` drives the body along the path with no gates of its own, so a leap
			# onto a legal ledge can still pass the animal through whatever is between.
			#
			# ARM the leap rather than taking it: the crouch is held on the deck for the
			# anticipation beat (crouch -> launch -> flight -> land -> settle, a timeline,
			# not a pose), and _process fires the flight when the wind-up elapses.
			_jump_wind = 0.34
			_jump_from = global_position
			_jump_to = Vector3(want.x, ground, want.z)
			if _rig != null:
				_rig.call("play_seq", [["jump_crouch", 0.34, 14.0]], "jump", 10.0)
		return
	# A step was taken — whatever pocket the stall counter was accumulating toward is open.
	_detour_stall = 0.0
	# The slope it is standing on, for the body pitch. Taken from the rise over the step
	# actually taken rather than from a second probe, so it cannot disagree with the move.
	# THE GRADE IS A WINDOW, NOT A STEP (s45c — the owner's "cat should angle up/down when
	# going down stairs"). Per-step atan2 cannot see a staircase: on treads the rise is
	# zero for ~a dozen steps and then a whole tread's drop lands in one 26 mm step
	# (atan2 saturates the clamp for a single frame), so the eased slope averaged to a
	# flicker near zero and the animal descended flights dead level. Accumulate rise and
	# run in a ~0.45 m distance-decayed window instead: on a rig stair that reads the
	# flight's true ~40-degree grade, steady, from the second tread on — and on flat deck
	# it decays to zero the way the old code did.
	var run: float = maxf(step.length(), 0.0001)
	var wf: float = exp(-run / 0.45)
	_grade_dy = _grade_dy * wf + rise
	_grade_run = _grade_run * wf + run
	_slope = lerpf(_slope, clampf(atan2(_grade_dy, maxf(_grade_run, 0.05)), -0.7, 0.7),
		1.0 - exp(-5.0 * delta))
	var before_step: Vector3 = global_position
	global_position = Vector3(want.x, ground, want.z)
	_last_speed = speed
	# The blender's phase runs off DISTANCE ACTUALLY MOVED (see cat_rig.tick) — recorded
	# here, where the movement really happens, so a refused or slid step is felt by the
	# legs instead of them cycling against a wall.
	#
	# THE NODE-LEVEL BOB THAT LIVED HERE IS GONE, AND IT MUST NOT COME BACK. It ran on its
	# own `_gait` accumulator against a constant STRIDE_M (0.62) while the legs plant off
	# cat_rig's `_phase` against a stride derived from the animal's own bones (0.356 m at a
	# walk) — two clocks at nearly 2:1, so the body rose while a foot was mid-swing instead
	# of arcing over the planted one: the floating pelvis. The whole-body vertical now lives
	# in cat_rig.tick on the SAME phase the paws plant from, where drift is impossible.
	_moved_frame += global_position.distance_to(before_step)

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
## ONE FOOTPRINT, CONSTANT, DERIVED — never again measured off the drawn meshes.
##
## The per-pose AABB version wedged the animal by construction, and the s45 COME probe
## caught it red-handed: the collision radius CHANGED WITH THE ANIMATION POSE (groom
## cached 0.100, run fatter), so a spot the cat legally walked into under one pose became
## illegal the moment its state changed — at (-21.9, 18, 12) the detour fan's +0.9
## candidate measured CLEAR at groom's radius and BLOCKED at run's, and the animal stood
## pinned for eight seconds in an open aisle it could plainly leave. Worse, the numbers
## were never the body at all: attach_rigged GROWS every MeshInstance's custom_aabb by
## half a metre for cull safety (a hand-driven skeleton corrupts the automatic bounds),
## and get_aabb() returns that grown box — the "measurement" was debug-box arithmetic
## saturating the clamp. A footprint that breathes cannot navigate; every character
## controller fixes the capsule and animates inside it. Derived from the recorded stand
## mesh proportions (AABB 1.0 x 0.566 x 0.265, tests/BoneDump; nose-to-tail scaled to
## STAND_SIZE_M), plus 30 mm of whisker.
const BODY_ACROSS_RATIO: float = 0.265
func _body_r() -> float:
	return STAND_SIZE_M * BODY_ACROSS_RATIO * 0.5 + 0.03

## Would the cat's BODY fit at `at`? A sphere query rather than a ray, so a step that leaves
## the origin outside a wall but the flank inside it is refused. Tested at the body centre
## and again at the nose, which is the one place a width-sized disc cannot see.
## `nose` FALSE tests the BODY ONLY — for points the animal is FLYING through rather than
## standing at. The nose probe exists because a WALKING cat's origin can be clear while its
## head is buried in a bulkhead; applied mid-leap it double-counts, because a cat rising
## beside a crate legitimately has its muzzle out over the crate top. With it on, every
## tight vertical hop refused itself: measured at a 1.0 m crate directly ahead, reach and
## landing both clear and `_arc_clear` FALSE on every frame, because the nose sphere 0.2 m
## ahead of a body climbing past the lip is inside the lip. The landing sample still asks
## the full question — that is where the animal has to stand and walk away.
func _step_clear(at: Vector3, dir: Vector3, extra_skip: Array = [], nose: bool = true) -> bool:
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
	var skip: Array[RID] = _walk_skip()
	for e in extra_skip:
		if e is RID:
			skip.append(e as RID)
	q.exclude = skip
	# `_body_r` is a half-width; the nose reaches roughly a body length ahead of centre, so
	# probe there too or the animal walks its head into a bulkhead and stops with the face
	# buried while its centre is legally clear.
	var lead: float = _body_len() * 0.5 - r
	var probes: Array = [at + Vector3(0, r + 0.04, 0)]
	if nose:
		probes.append(at + dir * maxf(lead, 0.0) + Vector3(0, r + 0.04, 0))
	for probe in probes:
		q.transform = Transform3D(Basis.IDENTITY, probe)
		if not world.direct_space_state.intersect_shape(q, 1).is_empty():
			return false
	return true

## Fixed for the same reason as _body_r: the live-AABB version read the grown cull boxes
## and swung with the pose. The animal is STAND_SIZE_M long; that is what the nose probe
## should reach for, in every pose, for ever.
func _body_len() -> float:
	return STAND_SIZE_M

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

## ---------------------------------------------------------------- persistence
##
## THE CAT HAD NO SAVE SECTION AT ALL, and the design's very first promise is the one that
## broke: "FOUND, not spawned at you... ONCE, and then for good. There is no befriending
## minigame and no trust meter. You reach out, it accepts, and that is the last decision
## either of you makes about it." `friend` was a plain var, so every reload made the animal
## a stranger again — the player had to re-befriend the cat every session, and the toast
## that is meant to happen once in a run happened every time they loaded.
##
## Saved here rather than left to a generic walker because these are DECISIONS the player
## made (met it, told it to stay, fed it today), not world geometry that gets rebuilt.
## `_stay_spot` rides along because a STAY that forgets WHERE is a different instruction on
## reload, and `_fed_game_h` because it is measured in absolute game hours precisely so it
## survives a slept night — surviving a save is the same requirement.
##
## Deliberately NOT saved: the behaviour state, the hunt beat, the pose, the trail. Those
## are momentary and the animal should wake up doing whatever its situation calls for; a
## restored mid-pounce would be a bug, not a feature.
func save_state() -> Dictionary:
	return {
		"friend": friend,
		"stayed": _stayed,
		"stay_spot": [_stay_spot.x, _stay_spot.y, _stay_spot.z],
		"fed_game_h": _fed_game_h,
		"energy": _energy,
	}

## Restore, defensively — every field optional, every type checked. A save written before
## this existed simply leaves the cat as it spawns, which is the old behaviour exactly.
func restore_state(d: Variant) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	var s: Dictionary = d
	friend = bool(s.get("friend", false))
	_stayed = bool(s.get("stayed", false))
	var sp: Variant = s.get("stay_spot", null)
	if sp is Array and (sp as Array).size() == 3:
		_stay_spot = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
	_fed_game_h = float(s.get("fed_game_h", -1000.0))
	_energy = clampf(float(s.get("energy", 0.6)), 0.0, 1.0)
	# The handle's verbs are the player-visible half of `friend` and `_stayed`, and they are
	# set at interaction time — so a restored cat that skipped the interaction would offer
	# SAY HELLO to someone it already knows.
	if _touch != null:
		_sync_verbs()
	# A cat restored as a friend is a companion, not the stranger `_ready` left grooming.
	_enter(State.SIT if _stayed else State.FOLLOW) if friend else _enter(State.GROOM)

## ONE POINT ON THE LEAP ARC — used by BOTH the flight and the clearance check, because
## these were two copies of the same formula and a check that models a different path from
## the one flown is worse than no check at all.
##
## THE HORIZONTAL LAGS ON A STEEP LEAP, and that is the difference between a cat and a
## trebuchet. A constant-rate horizontal over a symmetric parabola is fine for a long flat
## bound and wrong for the commonest jump there is — onto something directly in front of
## you: at 35% of a 1.0 m rise over a 0.63 m run the animal is only 0.35 m up and already
## a third of the way in, i.e. INSIDE the crate it is trying to land on. Measured exactly
## that way (tests/LeapScratch.tscn: reach true, top clear true, arc FALSE, every frame) —
## the leap was refusing itself on a path no cat would take. A real cat rises almost
## vertically off the hocks and translates late, so the horizontal is eased by an exponent
## that grows with the rise-over-run: flat leaps keep their old linear travel exactly.
func _arc_point(from: Vector3, to: Vector3, k: float) -> Vector3:
	var rise: float = to.y - from.y
	var run: float = Vector2(to.x - from.x, to.z - from.z).length()
	var steep: float = clampf(rise / maxf(run, 0.05), 0.0, 2.0)
	var kh: float = pow(k, 1.0 + steep)
	var lift: float = maxf(rise, 0.0) * 0.35 + 0.14
	return Vector3(
		lerpf(from.x, to.x, kh),
		lerpf(from.y, to.y, k) + sin(k * PI) * lift,
		lerpf(from.z, to.z, kh))

## MAY THE CAT LEAP UP TO `top`, OR WOULD IT STRAND ITSELF THERE?
##
## THIS IS THE RULE THE PREVIOUS ATTEMPT LACKED, and its absence is why that attempt was
## reverted. s38 made high ledges visible to the jump gate (the same fix that sits above
## this) and CatHuntProbe immediately caught the animal at y 20.26 — 2.26 m above the deck,
## having climbed a STAIRCASE OF LEDGES, one legal 0.6-1.2 m hop at a time, each one fine
## on its own, with no way back down. `JUMP_UP`'s own comment warns about exactly that:
## "an animal that leaps onto things the level design assumed were out of reach".
##
## A longer ray cannot fix it because the fault is not perception, it is the lack of a
## stopping condition. The condition that works is the companion contract itself: this cat
## follows a person, that person is standing on a deck the level design says is walkable,
## and no cat needs to be more than one leap above the human it is following. So the ceiling
## is the PLAYER's own height plus one jump. It is free (no query), it cannot be climbed
## incrementally (every hop is measured against the same absolute reference, not against the
## last one), and it self-releases the moment the player goes up too — follow someone up the
## stair tower and the cat may hop the crates on that deck, exactly as it should.
##
## Down is never gated: falling back to the deck is what `_walk_toward`'s own probe does,
## and an animal that may descend can always undo a mistake.
func _reachable_up(top: float) -> bool:
	var player: Node3D = AIB.player(self)
	if player == null:
		# No one to follow, no reason to climb. Refusing is the safe half of the branch:
		# the animal simply walks round whatever it is, which is what it did before leaps
		# existed at all.
		return false
	return top <= player.global_position.y + JUMP_UP

# ------------------------------------------------------------------ the bait trail

## THE PLAYER'S OWN FOOTSTEPS, WHICH ARE THE ONLY NAVIGATION DATA THIS GAME HAS THAT IS
## GUARANTEED CORRECT.
##
## Steering at where the player IS draws a straight line, and a straight line across this rig
## goes through steel. The detour fan then has to solve — greedily, one 0.05 m step at a time,
## with every candidate confined to +-115 deg of "toward the player" — a routing problem the
## human already solved with their feet. It cannot, and the failure is not subtle: from the
## west bunk cabin the only opening is at x -24.665 (rig_builder._build_bunkhouse cuts a 1.4 m
## hole at the centre of each 6.67 m corridor segment; the dividers at x -21.33 / -14.66 are
## solid from z4 to z10), so a cat whose player walked EAST must first travel three metres
## WEST. No heading in the fan points there. It slides up and down the divider until something
## else interrupts it.
##
## So the cat follows the TRAIL. Every crumb is a place a body already stood, at a height a
## body already reached, joined to the next by a step a body actually took — a proof of
## walkability nothing in this file could synthesise, laid down for free by the player as they
## walk. Doorways, corners and stair flights come out right because the human routed through
## them, not because the cat understands them.
##
## THE TRAIL IS A HINT, NEVER A RAIL. Anything that makes it unavailable — a fresh session, a
## teleport, a player who swam off, a cat a harness moved across the rig — falls straight back
## to the direct line and the detour fan, i.e. exactly the animal that shipped in s45. There is
## no state in which this can stall it.
const TRAIL_STEP: float = 0.6      ## metres of PLAYER travel between crumbs
## 64 crumbs is 38 m of PATH, and path is the quantity that matters: the follow distances are
## straight-line (FOLLOW_NEAR 2.2, RUN_M 8, FOLLOW_FAR 14) while a route through these rooms
## runs two to three times its own chord. 768 bytes.
const TRAIL_MAX: int = 64
## A move no walking body could make in one physics tick. Physics runs at 30 Hz here, so a
## sprinting player (SPRINT_SPEED 5.0) covers 0.167 m; past 0.9 m the two positions are not
## joined by a step and the segment between them is a line through whatever stood in the way.
## One rule, and it covers every teleport in the game: _respawn, the death respawn, the ladder
## top, and the harnesses — CatProbe teleports the player a dozen times, so the trail is empty
## for every one of its existing checks and none of them change behaviour.
const TRAIL_JUMP: float = 0.9
## "I am standing on this crumb." Above the worst distance one think can cover (RUN_SPEED 4.4
## x AiBudget.MAX_STEP 0.15 = 0.66 m), so a running cat cannot overshoot the whole radius and
## be dragged backwards onto a crumb it has already passed.
const JOIN_NEAR: float = 1.0
## ...and how far off the thread it may be and still walk back to it. Beyond this the trail is
## not a route to anywhere useful and the direct line is honest.
const JOIN_FAR: float = 5.0
## Seconds pinned on one crumb before the thread is walked on regardless — the anti-wedge for
## a crumb the cat can see but cannot stand on (the player squeezed past furniture it cannot).
const TRAIL_STALL: float = 0.9
const PULL_M: float = 3.0          ## how long a shortcut may be, and therefore proven
const PULL_SEC: float = 0.25       ## how often the shortcut tests run
const PULL_TRIES: int = 2          ## crumbs that may be skipped per test
const SEG_SAMPLE_M: float = 0.35   ## roughly what one _step_clear (centre + nose) covers
const LOOK_M: float = 0.8          ## the lookahead blend distance
## The slow into a hard turn. A real cat does not take a doorway at a trot; TURN_EASE_RAD is
## the yaw error at which the ease bottoms out (1.6 rad = 92 deg, i.e. a square corner), and
## the floor is a slow, never a stop.
const TURN_EASE_RAD: float = 1.6
const TURN_EASE_MIN: float = 0.45
const TURN_EASE_RATE: float = 6.0
## ...AND A DEADZONE, WITHOUT WHICH THIS IS A TAX RATHER THAN A CHARACTER BEAT. The first
## cut ramped straight from zero error, so an ordinary 0.2 rad steering correction — which
## happens continuously while following a moving target — cost 12% of speed, permanently,
## on every straight. Measured: the settle and COME checks in CatProbe both went red purely
## from the compounded slowdown. A real cat does not brake for a ten-degree correction; it
## brakes for a doorway. Full speed inside 20 deg, ramping to the floor at the square corner.
const TURN_EASE_DEAD: float = 0.35

## RECORDING IS NOT THINKING, SO IT DOES NOT GO THROUGH AiBudget.
##
## The whole of this animal's decision-making runs decimated on summed deltas, which is
## correct — but a decimated RECORDER samples the player up to 0.15 s apart, and 0.15 s of a
## sprint is 0.9 m. That is longer than the crumb spacing, which means two consecutive crumbs
## could straddle a doorway with the segment between them running through the jamb: the trail
## would be recording a route the player never took. Physics ticks are fixed and never summed
## (the s38 shutter trap cannot reach them either), so the sampling here is 0.167 m at the
## worst, whatever the frame rate is doing.
##
## Cost is one distance compare per tick, plus one ray every 0.6 m of player travel — about
## four rays a second at a walk.
func _physics_process(_delta: float) -> void:
	var player: Node3D = AIB.player(self)
	if player == null:
		_trail_prev = Vector3.INF
		return
	var p: Vector3 = player.global_position
	var prev: Vector3 = _trail_prev
	_trail_prev = p
	if prev == Vector3.INF:
		return
	if p.distance_squared_to(prev) > TRAIL_JUMP * TRAIL_JUMP:
		_trail.clear()
		return
	if _trail.size() > 0 \
			and p.distance_squared_to(_trail[_trail.size() - 1]) < TRAIL_STEP * TRAIL_STEP:
		return
	var world: World3D = get_world_3d()
	if world == null:
		return
	# A CRUMB IS A FOOTFALL, NOT A POSITION. Probed rather than taken from the player's origin
	# for two reasons: it puts the crumb on the deck, where the cat's own origin lives (see
	# _reseat), so the two are comparable; and the probe IS the walkability gate — no deck
	# within reach means the player is swimming, falling, flying or halfway up a ladder, and
	# none of those are places a cat can be baited to.
	var from: Vector3 = p + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 1.6, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _walk_skip()
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var foot: Vector3 = hit["position"]
	# ...AND IT MUST BE OUT OF THE SEA. A submerged surface passes the probe perfectly well —
	# the boat landing sits at y -3..1 — so the ray alone would happily bait the cat into the
	# water off the end of a dive. Same swim line the player, main.gd and underwater_fx test
	# against, so "the cat will not follow you in" means what it means everywhere else.
	if foot.y < Gyre.swim_line(Vector2(foot.x, foot.z), Gyre.water_time()) + 0.1:
		return
	if _trail.size() > 0 \
			and _trail[_trail.size() - 1].distance_squared_to(foot) > TRAIL_JUMP * TRAIL_JUMP:
		_trail.clear()
	_trail.push_back(foot)
	while _trail.size() > TRAIL_MAX:
		_trail.remove_at(0)

## Where to steer THIS frame: a point on the player's route, or the player themselves when the
## trail has nothing better to say. Never returns something that cannot be walked at.
func _trail_goal(ppos: Vector3, delta: float) -> Vector3:
	_trail_live = false
	_pull_cd -= delta
	var n: int = _trail.size()
	if n < 2:
		# One crumb is a spot, not a route — and steering at a spot the cat is already on is
		# the one way this could stall the animal.
		_trail_stall = 0.0
		return ppos
	# 1. WHERE ON THE THREAD AM I? Free — distance compares, no physics. Scanned NEWEST first,
	# which is how "a cat does not retrace a loop you walked" falls out for nothing: where the
	# route doubles back past itself, the later pass wins and the loop is never re-walked.
	var join: int = -1
	for i in range(n - 1, -1, -1):
		if global_position.distance_squared_to(_trail[i]) <= JOIN_NEAR * JOIN_NEAR:
			join = i
			break
	if join < 0:
		# Off the thread — after a COME, a harness move, or a spell blocked. Rejoin at the
		# NEAREST crumb, deliberately not the newest: at five metres "newest" is an unproven
		# shortcut through a bulkhead, which is the bug this whole section exists to fix.
		var best: float = JOIN_FAR * JOIN_FAR
		for i in range(n - 1, -1, -1):
			var dd: float = global_position.distance_squared_to(_trail[i])
			if dd < best:
				best = dd
				join = i
	if join < 0:
		_trail_stall = 0.0
		return ppos
	if join > 0:
		_trail = _trail.slice(join)
		_trail_stall = 0.0
	else:
		_trail_stall += delta
		if _trail_stall > TRAIL_STALL and _trail.size() > 1:
			# A crumb the player reached and the cat cannot (squeezed past a chair leg, say).
			# Walking the thread on is bounded and always makes progress; standing on it is
			# the wedge.
			_trail.remove_at(0)
			_trail_stall = 0.0
	# 2. THE STRING-PULL — the only physics this costs, throttled and LATCHED. Latched because
	# a shortcut re-decided every frame is the same flip-flop the fan's side commitment cures:
	# the aim point would alternate between the player and a crumb at frame rate.
	if global_position.distance_to(ppos) > PULL_M:
		_pull_free = false
	if _pull_cd <= 0.0:
		_pull_cd = PULL_SEC
		_pull_free = global_position.distance_to(ppos) <= PULL_M and _seg_clear(ppos)
		if not _pull_free:
			for _k in range(PULL_TRIES):
				if _trail.size() < 2 or global_position.distance_to(_trail[1]) > PULL_M \
						or not _seg_clear(_trail[1]):
					break
				_trail.remove_at(0)
				_trail_stall = 0.0
	if _pull_free or _trail.size() < 2:
		return ppos
	# 3. THE AIM POINT, WHICH IS WHY IT ROUNDS A CORNER INSTEAD OF CLIPPING IT. Slid along the
	# segment between the crumb it is on and the next one as it closes, so the animal is always
	# chasing a point a little further round the turn than itself and starts turning early.
	# It cannot aim into geometry: a point between two crumbs 0.6 m apart is ON the path the
	# player walked, by construction.
	_trail_live = true
	var c0: Vector3 = _trail[0]
	return c0.lerp(_trail[1],
		clampf(1.0 - global_position.distance_to(c0) / LOOK_M, 0.0, 1.0))

## Could the cat WALK the straight line from here to `to`? The crumbs prove the route the
## player took; this proves a shortcut ACROSS it.
##
## SAMPLED ON THE GROUND, NOT ON THE CHORD, and that distinction is the whole of stairs. A
## staircase surface is a zigzag of treads and risers, so the straight line between two points
## on it passes through the NOSING of every tread between them — a chord test calls every
## flight on this rig a wall, and the cat would refuse to string-pull up a stair it is standing
## on. Each sample is instead dropped onto whatever deck is under it with the same probe (and
## the same 1.1 m of downward reach) `_walk_toward` uses, and handed to the same `_step_clear`
## volume query, so a line this accepts is a line that function can actually walk. A sample
## more than CLIMB_UP above the last is refused, which is "one tread yes, a bulkhead no" — and
## it is also what stops a shortcut cutting through a stairwell wall between two crumbs on
## different flights, because the deck under the middle of that line is a whole storey off.
func _seg_clear(to: Vector3) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var flat: Vector3 = to - global_position
	flat.y = 0.0
	var span: float = flat.length()
	if span < 0.01:
		return true
	var dir: Vector3 = flat / span
	# Bounded twice over: PULL_M caps the span, and this caps the samples whatever that becomes.
	var steps: int = mini(int(ceil(span / SEG_SAMPLE_M)), 12)
	var skip: Array[RID] = _walk_skip()
	var last_y: float = global_position.y
	for i in range(1, steps + 1):
		var at: Vector3 = global_position + dir * (span * float(i) / float(steps))
		var from: Vector3 = Vector3(at.x, last_y + CLIMB_UP + 0.3, at.z)
		var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, CLIMB_UP + 1.4, 0))
		q.collision_mask = 1
		q.collide_with_areas = false
		q.exclude = skip
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return false
		var g: float = (hit["position"] as Vector3).y
		if g - last_y > CLIMB_UP:
			return false
		if not _step_clear(Vector3(at.x, g, at.z), dir):
			return false
		last_y = g
	return true

## A REAL CAT SLOWS INTO A DOORWAY. Multiplied into the commanded speed rather than applied
## inside `_walk_toward`, so the stalk, the zoomies and the play pounce keep their own pacing.
## `1 - exp(-rate * dt)` because this animal is handed SUMMED deltas up to 0.15 s and the
## clamped form snaps — the standing rule for every ease in this file.
func _ease_turn(aim: Vector3, delta: float) -> float:
	var to: Vector3 = aim - global_position
	to.y = 0.0
	var want: float = 1.0
	if to.length_squared() > 0.0004:
		var turn: float = absf(wrapf(atan2(to.x, to.z) + PI - rotation.y, -PI, PI))
		want = clampf(1.0 - maxf(turn - TURN_EASE_DEAD, 0.0)
			/ maxf(TURN_EASE_RAD - TURN_EASE_DEAD, 1e-3), TURN_EASE_MIN, 1.0)
	_turn_slow = lerpf(_turn_slow, want, 1.0 - exp(-TURN_EASE_RATE * delta))
	return _turn_slow

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
	# THE OTHER ANIMALS, BY TAG — NOT BY SUBTREE, AND THAT DISTINCTION IS THE WHOLE FIX.
	#
	# What used to sit here read `fauna_bodies`, a STATIC FUNCTION on bloom_fauna, through
	# `Object.get()`, which returns null for a method name: the branch added nothing from s36
	# until this replaced it. The repair that looks obvious — walk the bloom_fauna subtree and
	# skip every CollisionObject3D under it — was written, measured and removed, because that
	# subtree carries the corvids' nest (a real LootContainer collider) as well as the animals.
	#
	# `BloomFauna.CREATURE_GROUP` is the tag that pass asked for, applied where each creature
	# collider is BUILT — FaunaTouch._init, and GlowWorm, which is its own Interactable — so
	# no scenery can be in it however the subtree is rearranged, and the animals parented
	# OUTSIDE bloom_fauna (leg_reef's thirteen climbing snails, which the subtree walk could
	# never reach — the s21 crab-stood-on-a-snail trap) are in it anyway.
	for n in get_tree().get_nodes_in_group(BloomFauna.CREATURE_GROUP):
		var body := n as CollisionObject3D
		if body == null or body == _touch:
			continue
		skip.append(body.get_rid())
	return skip

func _face(target: Vector3, delta: float) -> void:
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length_squared() < 0.0004:
		return
	var want: float = atan2(to.x, to.z) + PI
	# `1 - exp` rather than `clampf(k * delta)`: under an AiBudget-summed 0.15 s think the
	# clamped form covered 90% of a commanded half-turn in ONE frame (measured: the summed
	# path snapped the full 90 deg while the fixed path read 80.6 over the same sim time).
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-TURN_RATE * delta))

## Is there a fish in the player's hand right now? Reads the hotbar the same way the spear
## prompt does, so "holding a fish" means exactly what it means everywhere else.
func _player_holding_fish(_player: Node3D) -> bool:
	var slot: int = PlayerState.selected_hotbar
	if slot < 0 or slot >= PlayerState.HOTBAR_SIZE or PlayerState.hotbar[slot] == null:
		return false
	var id: String = String(PlayerState.hotbar[slot])
	return id.begins_with("fish_") or id.begins_with("cooked_fish_") or id == "dried_fish"

# ------------------------------------------------------------------ mood and idle life

## ENERGY DRIFTS, and that is what stops the cat being a machine with cooldowns.
##
## Sleeping and sitting put it back; running, hunting and playing spend it. On top of that a
## crepuscular bump: cats are dawn-and-dusk animals and their evening burst is the most
## reliable thing they do, so the same cat is a different companion at 06:00 and at 14:00
## without a single behaviour having been rewritten.
func _tick_energy(delta: float) -> void:
	var spend: float = 0.0
	match _state:
		State.RUN, State.POUNCE, State.PLAY:
			spend = 0.085
		State.STALK, State.FOLLOW, State.GIFT:
			spend = 0.030
		State.SLEEP:
			spend = -0.075
		State.SIT, State.GROOM, State.PERCH, State.STRETCH:
			spend = -0.030
		_:
			spend = -0.010
	# The crepuscular pull. GameClock's phase is the cheapest honest source for it, and the
	# push is toward a HIGH target rather than a flat add so a tired cat still needs its rest.
	var ph: int = GameClock.current_phase
	var crepuscular: bool = ph == GameClock.Phase.DAWN or ph == GameClock.Phase.DUSK
	if crepuscular:
		_energy = lerpf(_energy, 1.0, 1.0 - exp(-0.09 * delta))
	_energy = clampf(_energy - spend * delta, 0.0, 1.0)

## A SETTLED CAT IS NOT A STATUE. It looks at things: at you, at a bird, at a noise, at
## nothing in particular, and it holds each look for a while before picking another. This is
## the cheapest aliveness there is and it runs ALONGSIDE whatever the animal is otherwise
## doing — no state, no `return`, so it never competes with the behaviour tree.
##
## Deliberately not a random head-jitter. A glance that lands on something and STAYS there
## reads as attention; one that wanders continuously reads as a broken servo.
func _idle_attention(delta: float, ppos: Vector3, d: float) -> void:
	# The hunt, the gift and being petted all aim the head themselves and outrank this.
	if _hunt > 0 or _carry != "" or _pet_t > 0.0 or _state == State.SLEEP:
		return
	# AND NOT WHILE SHE IS WALKING, which is a standing instruction rather than a preference.
	# The owner's requirement is that from head on, at default gait, the face points dead
	# straight — that is what the s38 work on the breath layer was for, measured down from
	# +3.43 deg off the travel line to +0.91. An idle glance layer is free to turn the head up
	# to a radian, so letting it run during FOLLOW would hand all of that straight back for
	# the sake of an idle flourish. A settled cat looks around; a walking one looks where she
	# is going.
	if _last_speed > 0.2 or _state in [State.FOLLOW, State.RUN, State.STALK, State.POUNCE,
			State.PLAY, State.GIFT, State.JUMP]:
		_glance_hold = 0.0
		return
	if _glance_hold > 0.0:
		_glance_hold -= delta
		_watch(_glance_at, 0.85)
		return
	_glance_cd -= delta
	if _glance_cd > 0.0:
		return
	# Pick something worth looking at, weighted by what a cat would actually care about.
	var roll: float = _rng.randf()
	var picked := false
	if roll < 0.34 and d < FISH_M:
		_glance_at = ppos + Vector3(0, 1.2, 0)      # you, most often
		picked = true
	elif roll < 0.60:
		# The nearest bird, if there is one. Birds beat everything except you.
		var best_d: float = HUNT_M * 1.6
		for g in get_tree().get_nodes_in_group("deck_gull"):
			var n: Node3D = g as Node3D
			if n == null or not is_instance_valid(n):
				continue
			var gd: float = global_position.distance_to(n.global_position)
			if gd < best_d:
				best_d = gd
				_glance_at = n.global_position + Vector3(0, 0.1, 0)
				picked = true
	if not picked:
		# ...or nothing in particular, which is most of what a cat looks at. Off to one side
		# and roughly level, because a cat scanning a deck is not studying its own feet.
		var a: float = rotation.y + _rng.randf_range(-2.2, 2.2)
		_glance_at = global_position + Vector3(sin(a), 0, cos(a)) * _rng.randf_range(3.0, 9.0) \
			+ Vector3(0, _rng.randf_range(-0.1, 1.1), 0)
	_glance_hold = _rng.randf_range(0.7, 2.6)
	_glance_cd = _rng.randf_range(1.1, 4.5)

## A WASH IS A BOUT, NOT A LOOP. It runs for a few seconds in ONE style and stops, and the
## next one is a different style — which is the difference between a cat grooming and an
## idle animation playing. Returns true while it owns the animal.
func _self_groom(delta: float) -> bool:
	if _wash_t <= 0.0:
		return false
	_wash_t -= delta
	_enter(State.GROOM)
	if _rig != null:
		_rig.call("groom_style", _wash_style)
	_last_speed = 0.0
	_reseat()
	if _wash_t <= 0.0:
		# Longer bouts earn a longer break, so it never reads as a rota.
		_wash_cd = _rng.randf_range(14.0, 48.0)
	return true

## Start one, if the mood is right. Cats groom when settled and unbothered, and after
## anything that ruffled them.
## A WASH IS A RANDOM EVENT, NOT A GREETING — the owner's "it shouldn't lick itself EVERY
## time right after stopping".
##
## `_wash_cd` counts down in `_companion` on EVERY frame, whatever the animal is doing — so
## it runs out while the cat is walking, and this function was then reached, ready, on the
## first settled frame after the player stopped. The cooldown was doing its job perfectly and
## the job was the wrong one: it made a wash *inevitable on arrival* rather than occasional.
## Two gates fix it without touching the pacing:
##   * a SETTLING DELAY — a cat that has just stopped looks around first; it does not sit
##     down and immediately start washing. `_still` is already the seconds-since-the-player-
##     moved counter the settle ladder uses;
##   * a POISSON ROLL rather than a threshold, so once eligible a bout starts at a rate
##     (about one in seven seconds) instead of the instant the clock allows it. Two stops in
##     a row now look different from each other, which is the whole point.
const WASH_SETTLE_S: float = 3.0     ## seconds settled before a wash is even considered
const WASH_RATE: float = 0.145       ## per second, once eligible — about one in seven
func _maybe_wash(delta: float) -> void:
	if _wash_cd > 0.0 or _wash_t > 0.0:
		return
	if _still < WASH_SETTLE_S:
		return
	if _rng.randf() > WASH_RATE * maxf(delta, 0.0):
		return
	if _rig != null:
		_rig.call("tail_flick", 0.45)   # the small settling flick as it starts a wash
	_wash_style = [0, 0, 0, 1, 1, 2, 3][_rng.randi_range(0, 6)]
	# The ear scratch is short and furious; a flank wash is long and unhurried.
	# The ear scratch is short and furious — 2.8 s against the flank wash's seven.
	_wash_t = {0: 4.5, 1: 7.0, 2: 5.0, 3: 2.8}.get(_wash_style, 4.0) * _rng.randf_range(0.7, 1.4)

# ------------------------------------------------------------------ the predatory sequence

## Is this bird already in the air? A gull in flight is not prey, and `_flushing` is DeckGull's
## own flag for it (< 0 grounded, >= 0 seconds airborne).
func _airborne(n: Node3D) -> bool:
	# THE FLAG, AND THEN THE GEOMETRY. `_flushing` is one species' one state variable, and
	# trusting it alone let the cat stalk — and once, pounce at — a bird that was plainly
	# in the air but not in that state (circling, or another species spelling its state
	# differently). Altitude cannot be argued with: anything holding itself more than a
	# body-height above the cat's own deck is not stalkable prey, whatever its flags say.
	# (A bird perched on a crate trips this too, which is correct twice over — the cat
	# cannot reach it, and chattering at it instead is exactly what a cat would do.)
	var f = n.get("_flushing")
	if f != null and float(f) >= 0.0:
		return true
	return n.global_position.y - global_position.y > 0.35

## The nearest gull on this deck that is on the ground and worth stalking. Birds in the air
## are not prey, they are frustration — see the chatter.
func _find_prey() -> Node3D:
	var best: Node3D = null
	var best_d: float = HUNT_M
	for g in get_tree().get_nodes_in_group("deck_gull"):
		var n: Node3D = g as Node3D
		if n == null or not is_instance_valid(n):
			continue
		# A bird already in the air, or one on another deck, is not a stalk.
		#
		# `get()` on a property a node does not have returns null, and `float(null)` is a hard
		# runtime error — so this is asked defensively rather than assumed. Only DeckGull is in
		# this group today; the group is the seam another species will be added at, and a crash
		# in the cat because a new bird spelled its state differently is a bad way to find out.
		if _airborne(n):
			continue
		if absf(n.global_position.y - global_position.y) > CLIMB_UP:
			continue
		var dd: float = global_position.distance_to(n.global_position)
		if dd < best_d:
			best_d = dd
			best = n
	return best

## One beat of the hunt. Returns true while the hunt owns the animal.
func _hunt_step(delta: float) -> bool:
	if _hunt == 0:
		_prey = _find_prey()
		if _prey == null:
			return false
		_hunt = 1
		_freeze_t = 0.0
	# The bird left, flew, or was freed. A cat that keeps stalking an empty patch of deck is
	# the "drone" read this whole file exists to avoid.
	if _prey == null or not is_instance_valid(_prey) or _airborne(_prey):
		_end_hunt(false)
		return false
	var target: Vector3 = _prey.global_position
	var pd: float = global_position.distance_to(target)
	if pd > HUNT_GIVEUP_M:
		_end_hunt(false)
		return false
	# The head is on the bird throughout, whatever the body is doing. This is the tell that
	# makes the whole sequence legible from across a deck.
	_watch(target + Vector3(0, 0.12, 0), 1.0)
	match _hunt:
		1:
			# THE STALK. Low, slow, and it FREEZES — the freezing is the difference between a
			# stalk and simply walking at something. A cat holds still when it thinks the prey
			# has clocked it, and the pauses are what make the approach read as intent.
			_enter(State.STALK)
			if _freeze_t > 0.0:
				_freeze_t -= delta
				_last_speed = 0.0
				_reseat()
				_face(target, delta * 1.5)
			else:
				_walk_toward(target, STALK_SPEED, delta, POUNCE_M * 0.85)
				if _rng.randf() < delta * 0.85:
					_freeze_t = _rng.randf_range(0.3, 1.1)
					# The tip lashes hardest at the freezes — a stalking cat holds its
					# body dead still and its tail does not get the message.
					if _rig != null:
						_rig.call("tail_flick", 1.0)
			if pd <= POUNCE_M:
				_hunt = 2
				_wiggle_t = WIGGLE_SEC
		2:
			# THE TREAD. Hind feet paddling, the rear waggling, the whole animal winding up.
			# Everyone who has met a cat knows precisely what happens next, and it costs one
			# sine wave.
			_enter(State.STALK)
			_face(target, delta * 3.0)
			_last_speed = 0.0
			_reseat()
			_wiggle_t -= delta
			var k: float = clampf(_wiggle_t / WIGGLE_SEC, 0.0, 1.0)
			# The waggle is the PELVIS. Swinging the node took the shoulders and the head
			# with it, which is the wrong end of the animal: the tread is hind feet
			# paddling under a still, locked-on front.
			if _rig != null:
				_rig.call("wiggle", 1.0 - k * 0.35)
			if _wiggle_t <= 0.0:
				_launch_pounce(target)
		_:
			pass
	return true

func _launch_pounce(target: Vector3) -> void:
	# A LEAP MUST STILL FIT WHERE IT LANDS. `_fly_jump` drives the body along its arc directly,
	# with none of `_walk_toward`'s deck probe or volume check — the leap deliberately owns the
	# animal — so the only place a pounce can be made safe is before it starts. Without this
	# CatProbe's burial sweep caught the cat 229 mm inside the bunkhouse geometry twice in one
	# run: a hunt that ends with the animal in a bulkhead is worse than a hunt that never fires.
	var over: Vector3 = target - global_position
	over.y = 0.0
	if over.length() < 0.05:
		_end_hunt(false)
		return
	var dir: Vector3 = over.normalized()
	# THE BIRD IS NOT AN OBSTACLE — the whole point is to land on it. DeckGull carries a grab
	# collider on the solid layer, so the clearance test refused every single pounce and the
	# hunt stalled at the tread for ever: the cat crouched, waggled, and never jumped, which is
	# a far worse behaviour than not hunting at all. (The general fix — `_walk_skip` skipping
	# all other fauna — is filed in KNOWN_ISSUES; the branch that claims to do it reads a
	# STATIC FUNCTION as if it were a property and has been adding nothing for two sessions.)
	var prey_skip: Array = []
	if _prey != null and is_instance_valid(_prey):
		for c in _prey.find_children("*", "CollisionObject3D", true, false):
			prey_skip.append((c as CollisionObject3D).get_rid())
		if _prey is CollisionObject3D:
			prey_skip.append((_prey as CollisionObject3D).get_rid())
	var land: Vector3 = global_position + over * _rng.randf_range(0.94, 1.12)
	land.y = target.y
	if not _arc_clear(land, dir, prey_skip):
		# Try landing short before giving up — a cat crowded by furniture takes the shorter
		# leap rather than not leaping.
		land = global_position + over * 0.6
		land.y = target.y
		if not _arc_clear(land, dir, prey_skip):
			# It wound up and could not go. That still has to READ, so it gets the same
			# affronted wash a miss gets rather than silently forgetting the whole thing.
			_after_t = WASH_SEC * 0.6
			_end_hunt(false)
			return
	_hunt = 3
	_pouncing = true
	_enter(State.POUNCE)
	# The tread was the long anticipation; the launch still GATHERS for a tenth of a second
	# — the spring compressing — before the flight stretch.
	if _rig != null:
		_rig.call("play_seq", [["jump_crouch", 0.10, 16.0]], "jump", 10.0)
	_jump_t = POUNCE_SEC
	_jump_from = global_position
	# Land ON the bird's patch of deck, not on the bird — the seat ray sorts the height out,
	# and a pounce that overshoots by a body length looks more like a cat than one that
	# arrives dead centre every time.
	_jump_to = land
	# THE BIRD REACTS TO THE LEAP, NOT TO BEING LANDED ON. Flushing only at touchdown left
	# the gull standing oblivious through the whole 0.4 s flight and then teleporting into
	# panic on the exact frame the cat arrived — the owner's "no physics/interaction, not
	# realistic". A real bird explodes upward the instant the cat leaves the deck, so the
	# flush fires HERE, and the catch (in _resolve_pounce) is now a race the cat usually
	# loses: it connects only if the bird is still inside the first wingbeats when the paws
	# arrive. Most pounces become a burst of gull with the cat landing in its wake — which
	# is what nine out of ten real pounces on birds look like.
	if _prey != null and is_instance_valid(_prey) and _prey.has_method("_flush"):
		_prey.call("_flush", self)
	AudioDirector.play_one_shot("cat_chirp", global_position, -22.0)

## IS THE WHOLE LEAP CLEAR, not just where it ends?
##
## Checking only the landing point is the obvious thing and it is not enough: the probe caught
## the cat 797 mm inside the quarters bulkhead at NINETY PER CENT of an arc whose destination
## tested perfectly clear. A gull standing a body-length from a wall is a completely ordinary
## thing for a gull to do, and the leap at it passes through the steel on the way in. `_fly_jump`
## drives the body along the arc directly with no gates of its own, so every point of that arc
## has to be proven here, before the animal commits to any of it.
func _arc_clear(to: Vector3, dir: Vector3, extra_skip: Array = []) -> bool:
	var from: Vector3 = global_position
	for k in [0.35, 0.6, 0.8, 1.0]:
		var at: Vector3 = _arc_point(from, to, k)
		if not _step_clear(at, dir, extra_skip, k >= 1.0):
			return false
	return true

## Did it get there? Called on the frame the leap lands.
func _resolve_pounce() -> void:
	_pouncing = false
	var caught: bool = false
	if _prey != null and is_instance_valid(_prey):
		var pd: float = global_position.distance_to(_prey.global_position)
		# THE CATCH IS GATED BY GEOMETRY, NOT BY A FLAG. The bird was flushed at launch, so
		# by touchdown its `_flushing` flag is always set — the question is whether it is
		# still LOW: inside the first wingbeats, under half a metre off the deck, within a
		# paw's reach. A bird that is properly airborne cannot be caught, full stop — which
		# also closes the owner's "jumped on a bird that was just flying around": however
		# the flags read, altitude says no.
		var prey_alt: float = _prey.global_position.y - global_position.y
		caught = pd < 1.15 and prey_alt < 0.45 and _rng.randf() < CATCH_CHANCE
		# The bird goes either way — it is not eaten and it is not deleted. The flush at
		# launch already sent it; this repeat is harmless insurance for the paths that
		# reach here without one (an aborted arc mid-flight).
		if _prey.has_method("_flush"):
			_prey.call("_flush", self)
	if caught:
		_carry = "gull_feather"
		AudioDirector.play_one_shot("cat_chirp", global_position, -14.0)
	else:
		# THE WASH. It missed, and it would like everyone to understand that it was not
		# trying. This is a real displacement behaviour and it is better animation than the
		# success is.
		_after_t = WASH_SEC
	_end_hunt(caught)

func _end_hunt(_caught: bool) -> void:
	_hunt = 0
	_prey = null
	_wiggle_t = 0.0
	_freeze_t = 0.0
	_hunt_cd = HUNT_CD * _rng.randf_range(0.7, 1.4)

## Drop what it is carrying at your feet.
func _deliver(player: Node3D) -> void:
	_face(player.global_position, 1.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if PlayerState.add_item(_carry):
		Journal.discover("cat_gift")
		PlayerState.comfort = clampf(PlayerState.comfort + 0.05, 0.0, 1.0)
		if hud and hud.has_method("toast"):
			hud.toast("The cat puts a gull feather down in front of you, and waits.")
	elif hud and hud.has_method("toast"):
		hud.toast("The cat tries to give you a feather. Your pack is full.")
	AudioDirector.play_one_shot("cat_chirp", global_position, -18.0)
	_carry = ""
	_meow_cd = 4.0

# ------------------------------------------------------------------ play and the zoomies

## FRAP — the evening madness. A short, pointless, flat-out burst across the deck, which is
## the one thing a cat does that no amount of following and sitting can imply.
func _zoomies(delta: float, ppos: Vector3) -> bool:
	if _zoom_t <= 0.0:
		_zoom_t = ZOOM_SEC
		_zoom_to = Vector3.ZERO
	_zoom_t -= delta
	if _zoom_t <= 0.0:
		_zoom_cd = ZOOM_CD * _rng.randf_range(0.7, 1.5)
		return false
	# A new heading every so often, which is what makes it read as madness rather than as
	# going somewhere. Drawn around the PLAYER rather than around the cat: a burst that
	# random-walks off the deck is a cat leaving, and "it settles rather than circling when
	# you rest" is a contract this animal has kept since s34. Orbiting keeps both.
	if _zoom_to == Vector3.ZERO or global_position.distance_to(_zoom_to) < 1.0:
		var a: float = _rng.randf() * TAU
		_zoom_to = ppos + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(2.0, 3.4)
		_zoom_to.y = global_position.y
	_enter(State.RUN)
	_still = 0.0
	_walk_toward(_zoom_to, RUN_SPEED, delta, 0.4)
	return true

## OBJECT PLAY. It picks a spot on the deck, stalks it exactly as if it were alive, pounces on
## nothing at all, and does it again. The cat knows there is nothing there; that has never
## stopped one yet.
func _play(delta: float) -> bool:
	if _play_t <= 0.0:
		_play_t = PLAY_SEC
		_play_spot = Vector3.ZERO
	_play_t -= delta
	if _play_t <= 0.0:
		_play_cd = PLAY_CD * _rng.randf_range(0.7, 1.5)
		return false
	if _play_spot == Vector3.ZERO or global_position.distance_to(_play_spot) < 0.7:
		# PROBED, like everything else that names a position in this file. A spot drawn blind
		# lands inside a bunk frame about as often as not in the room the cat lives in, and
		# then the pounce that follows puts the animal in the steel.
		_play_spot = Vector3.ZERO
		for _try in range(6):
			var a: float = _rng.randf() * TAU
			var cand: Vector3 = global_position \
				+ Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(1.6, 3.4)
			cand.y = global_position.y
			if _step_clear(cand, (cand - global_position).normalized()):
				_play_spot = cand
				break
		if _play_spot == Vector3.ZERO:
			_play_t = 0.0
			_play_cd = PLAY_CD * _rng.randf_range(0.7, 1.5)
			return false
		_wiggle_t = WIGGLE_SEC * 0.6
	_enter(State.PLAY)
	_watch(_play_spot, 1.0)
	if _wiggle_t > 0.0 and global_position.distance_to(_play_spot) < POUNCE_M:
		_wiggle_t -= delta
		_face(_play_spot, delta * 3.0)
		_last_speed = 0.0
		if _rig != null:
			_rig.call("wiggle", 0.85)
		if _wiggle_t <= 0.0 and _jump_t <= 0.0 and _jump_cd <= 0.0 \
				and _step_clear(_play_spot, (_play_spot - global_position).normalized()):
			_jump_t = POUNCE_SEC
			_jump_from = global_position
			_jump_to = _play_spot
			_enter(State.POUNCE)
	else:
		_walk_toward(_play_spot, TROT_SPEED, delta, POUNCE_M * 0.8)
	return true

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
	# THE OWNER'S STANDING RULE, made structural at the ONE place looks reach the rig:
	# "the cat always looks straight while walking/running; when she pauses to sit, then
	# she looks around everywhere and does cat things." Above a threshold between the
	# stalk (0.62 — which keeps its locked-on creep, the whole tell of a stalk) and the
	# walk (1.55), NO look of any kind reaches the head: not a glance, not a chatter
	# whisper, not a gift-carry gaze. Suppressed HERE rather than at each caller so no
	# future behaviour can re-introduce a mid-stride head-turn — the ninth report of this
	# defect was caused by exactly such a caller nobody had gated.
	if _focus_w > 0.01 and _last_speed < 0.8:
		var to: Vector3 = _focus - global_position
		if to.length_squared() > 0.0004:
			# Into the BODY's frame: the neck yaw is relative to where the animal is facing,
			# so a cat walking north looking east is +90, not a world bearing.
			var want: float = atan2(to.x, to.z) + PI
			var rel: float = wrapf(want - rotation.y, -PI, PI)
			var pitch: float = atan2(to.y - 0.25, Vector2(to.x, to.z).length())
			_rig.look(rel, clampf(pitch, -0.5, 0.5), _focus_w)
	# WHAT THE TAIL IS SAYING, per state. This is the body language the owner asked for and
	# the only channel this mesh has: no facial rig, no ears, painted-on pupils. Carriage and
	# sway do all of it, and every one of these is a real signal a cat owner reads without
	# being taught — the vertical flag on approach, the slow wide arc of an unbothered animal,
	# the flat hard flick of one that is hunting, the quiver of one that has just been fed.
	#   tail(up, sway, rate): up +1 straight up / -1 clamped down, sway width, rate speed.
	match _state:
		State.STALK:
			_rig.tail(-0.85, 0.30, 9.0)      # flat to the deck, tip going hard
		State.POUNCE:
			_rig.tail(-0.4, 0.05, 2.0)       # committed: everything points one way
		State.RUN:
			_rig.tail(0.15, 0.20, 3.0)       # streamed out behind for balance
		State.GIFT:
			_rig.tail(0.95, 0.14, 7.0)       # up and pleased with itself
		State.PET, State.FISH:
			_rig.tail(1.0, 0.10, 8.0)        # the greeting flag, quivering
		State.SLEEP:
			_rig.tail(-0.5, 0.02, 0.4)       # wrapped in and still
		State.GROOM, State.SIT, State.PERCH:
			_rig.tail(-0.2, 0.16, 0.9)       # settled, an idle sweep along the deck
		State.PLAY:
			_rig.tail(-0.3, 0.34, 6.0)
		_:
			# FOLLOW and the rest: a cat walking to someone it likes carries its tail UP, and
			# it is the single most reliable "this animal is pleased to be here" there is.
			_rig.tail(0.55 if _fed_wiggle > 0.0 else 0.35, 0.28, 1.6)
	if _fed_wiggle > 0.0:
		_rig.tail(1.0, 0.10, 11.0)           # the delight quiver, briefly, over everything
	# HOW FAST THE BODY IS ACTUALLY TURNING, measured off the node rather than commanded. The
	# rig needs it for the turn-in-place step cycle (flaw 4): asked to face a new bearing while
	# standing still, `_face` used to swivel the whole animal with all four paws welded to the
	# deck. Measured here, where the yaw really changes, for the same reason `_moved_frame` is
	# measured where the movement really happens.
	var yaw_rate: float = wrapf(rotation.y - _yaw_prev, -PI, PI) / maxf(delta, 1e-4)
	_yaw_prev = rotation.y
	_rig.tick(delta, _last_speed, _moved_frame, yaw_rate)
	_moved_frame = 0.0

## Point the cat's ATTENTION at something without turning it. Weight decays, so a glance
## fades unless whatever caused it keeps calling.
func _watch(at: Vector3, weight: float = 1.0) -> void:
	var w: float = clampf(weight, 0.0, 1.0)
	# THE TARGET FOLLOWS THE STRONGEST CLAIM, NOT THE LATEST. Two watchers calling every
	# frame — a held glance and the chatter, say — used to alternate `_focus` A/B/A/B at
	# frame rate, and the drawn head SAWED between them: the single largest discontinuity
	# the review probe found anywhere in the walk (~0.8 rad/frame at the neck). A new
	# target must now outrank the current claim, renew it, or wait out its decay.
	if w > _focus_w + 0.001 or _focus_w <= 0.01 or at.distance_to(_focus) < 0.4:
		_focus = at
	_focus_w = maxf(_focus_w, w)

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
		# A stalk SETTLES into itself — a cat sinking into a crouch is the slowest thing it
		# does, and snapping into the pose throws the whole tell away. Everything that is a
		# burst of motion blends fast; everything that is a decision blends slowly.
		var rate: float = 10.0 if key in ["run", "jump", "walk", "carry"] else \
			(3.2 if key == "stalk" else 5.0)
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
