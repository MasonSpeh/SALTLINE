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
enum State { GROOM, FOLLOW, RUN, SIT, SLEEP, FISH, PET }

const POSES := {
	"stand": MODEL_PATH,
	"sit": "res://assets/models/fauna/cat_sit/cat_sit.glb",
	"groom": "res://assets/models/fauna/cat_groom/cat_groom.glb",
	"walk": "res://assets/models/fauna/cat_walk/cat_walk.glb",
	"run": "res://assets/models/fauna/cat_run/cat_run.glb",
	"sleep": "res://assets/models/fauna/cat_sleep/cat_sleep.glb",
}
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
const STEP_UP: float = 0.45          ## coamings yes, stairs no

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
var _pose_nodes: Dictionary = {}
var _pose_mats: Dictionary = {}
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
	for key in POSES:
		var host := Node3D.new()
		_body.add_child(host)
		var pg: Dictionary = ANIM.attach(host, POSES[key], _pose_size(key), ANIM.Mode.BREATHE,
			0.05, 1.1, Color(0.9, 0.78, 0.42), 0.0)
		if pg.is_empty():
			host.queue_free()
			continue
		ANIM.ground(host, pg["model"])
		host.visible = false
		_pose_nodes[key] = host
		_pose_mats[key] = pg["mats"]
	var gen: Dictionary = {"mats": _pose_mats.get("stand", [])} if not _pose_nodes.is_empty() else {}
	if not _pose_nodes.is_empty():
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
	_touch.interacted.connect(_on_touched)
	# PROBED, NOT TYPED. HOME's Y is the bunkhouse deck as authored, and every floating-prop
	# bug in this repo came from trusting exactly that kind of constant. Deferred because CSG
	# decks have no collider on the frame they enter the tree (see surface_snap.gd).
	global_position = HOME
	call_deferred("_seat")

func _seat() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world: World3D = get_world_3d()
	if world == null:
		return
	var from: Vector3 = global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 4.0, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
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
	if _fed_wiggle > 0.0:
		_fed_wiggle -= delta * 0.7
		_body.rotation.y = sin(_t * 17.0) * 0.13 * clampf(_fed_wiggle, 0.0, 1.0)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if not friend:
		_groom(delta, player)
		return
	_companion(delta, player)

## Before you find it: sitting where it lives, washing a paw, looking up when you get close.
func _groom(delta: float, player: Node3D) -> void:
	_enter(State.GROOM)
	var d: float = global_position.distance_to(player.global_position)
	if d < GREET_M * 2.5:
		_face(player.global_position, delta)   # it has noticed you
	# The wash: a slow lean and a nod, driven off the shared breathe animation plus a little
	# extra motion so it does not read as a statue from across the room.
	_body.rotation.z = sin(_t * 1.7) * 0.10
	_body.rotation.x = sin(_t * 2.3) * 0.07

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
		var spot: Vector3 = _sleep_spot(ppos)
		if global_position.distance_to(spot) > 0.55:
			_enter(State.FOLLOW)
			_walk_toward(spot, WALK_SPEED, delta, 0.35)
		else:
			_enter(State.SLEEP)
			ANIM.drive(_gen_mats, 0.5, 0.0)
		return

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
	# The tail-tip flick of a cat that is awake and paying attention.
	_body.rotation.y = sin(_t * 0.9) * 0.06

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
	if ground - global_position.y > STEP_UP:
		return          # a stair or a bunk frame: not its problem
	global_position = Vector3(want.x, ground, want.z)
	# Gait: a small vertical lilt and a body roll, scaled to speed. Nothing skeletal — the
	# generated mesh has no rig (Tripo/Meshy auto-rig is humanoid-only), so motion is pose.
	var gait: float = _t * speed * 3.4
	_body.position.y = absf(sin(gait)) * 0.035
	_body.rotation.z = sin(gait * 0.5) * 0.05

func _face(target: Vector3, delta: float) -> void:
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length_squared() < 0.0004:
		return
	var want: float = atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(TURN_RATE * delta, 0.0, 1.0))

## Is there a fish in the player's hand right now? Reads the hotbar the same way the spear
## prompt does, so "holding a fish" means exactly what it means everywhere else.
func _player_holding_fish(_player: Node3D) -> bool:
	var slot: int = PlayerState.selected_hotbar
	if slot < 0 or slot >= PlayerState.HOTBAR_SIZE or PlayerState.hotbar[slot] == null:
		return false
	var id: String = String(PlayerState.hotbar[slot])
	return id.begins_with("fish_") or id.begins_with("cooked_fish_") or id == "dried_fish"

# ------------------------------------------------------------------ poses

## Target longest-axis size per pose, metres. NOT one number for all six: a cat curled
## asleep is a ~0.45 m ball and the same animal at full stride is ~0.75 m nose to tail, so
## normalising every mesh to the same longest axis would shrink the running cat and inflate
## the sleeping one until they read as two different animals. These are the real ratios of
## the same cat in those poses.
func _pose_size(key: String) -> float:
	match key:
		"sleep": return 0.46
		"sit": return 0.44
		"groom": return 0.46
		"run": return 0.74
		"walk": return 0.66
	return 0.55

## Show one pose, hide the rest. The transition is a visibility flip — see POSES for why it
## is not an ANIM.replace().
func _wear(key: String) -> void:
	if key == _pose or not _pose_nodes.has(key):
		return
	for k in _pose_nodes:
		(_pose_nodes[k] as Node3D).visible = (k == key)
	_pose = key
	_gen_mats = _pose_mats.get(key, [])

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
			return p
	return global_position
