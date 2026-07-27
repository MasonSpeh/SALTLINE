class_name KingCrab extends Node3D
## THE KING CRAB (s16) — the boss-tier version of the night threat. There are never more
## than TWO on the rig, and neither of them is guaranteed: each one independently rolls a
## 50% chance, every night, of leaving the deep water to hunt for food. Some nights both
## come. Some nights neither does, and the only sign is a wet drag-mark on the plating in
## the morning.
##
## It is a KING: a five-metre leg span standing nearly two metres tall at the knees —
## taller than you — on eight jointed, individually posed limbs, with two arms that carry
## real pincers. It is SLOWER than an ordinary giant crab and it hits far harder (a third
## of your life a bite, and a shove that puts you on the deck), and it takes a beating
## before it gives up: nine points of damage against the ordinary crab's three. A held
## flashlight does move it, but the bar is more than twice as high, so you have to be
## inside its reach with the beam dead on it to make that trade — and it only backs off a
## couple of metres before it comes on again.
##
## THE ARTICULATION (this codebase's fact #4: the motion shader bends a mesh as a whole
## and there is no skeleton in the glb — Meshy auto-rigs humanoids only). The shell is the
## generated giant_crab mesh, scaled up; every LIMB is built here in code as jointed
## segments, and posed per frame. The gait clock advances with GROUND DISTANCE TRAVELLED,
## not with time, so the legs physically cannot moonwalk: stop the body and the cycle
## stops mid-stride. Fact #2 is why the limbs are built where they are — CreatureAnim
## .replace() hides every MeshInstance3D that already exists on the host, so the limbs are
## constructed AFTER that call, never before.
##
## It shares the crab's rig knowledge rather than copying it: the level tree, the authored
## stair-tower flights, the light-brightness model and the no-go volumes all live in
## crab.gd as statics, so there is exactly one set of coordinates for the whole species.

const CRABS := preload("res://scripts/world/crab.gd")   # by path: class cache lags new files
const KIT := preload("res://scripts/world/creature_kit.gd")
const ANIM := preload("res://scripts/world/creature_anim.gd")
const MOVE := preload("res://scripts/world/fauna_move.gd")
const MODEL_PATH := "res://assets/models/fauna/giant_crab/giant_crab.glb"
const NO_GLOW := Color(0, 0, 0)     ## naturalistic, like its smaller kin: no shine

## Ordinals are deliberately aligned with GiantCrab.State where the meaning matches
## (DEN=ROOST=0, HUNT=PATROL=2, PURSUE=3, RETREAT=FLEE=4, GONE=5, CLIMB=6). While a king
## is up it joins the "giant_crab" group, and soak_test picks an arbitrary member of that
## group and asserts its state reads as FLEE/ROOST/GONE at dawn — so the numbers matching
## is not cosmetic, it is what keeps that assertion true for a king as well as a crab.
enum State { DEN = 0, RISE = 1, HUNT = 2, PURSUE = 3, RETREAT = 4, GONE = 5, CLIMB = 6 }

## Injected by the spawner (BloomFauna).
var den: Vector3 = Vector3(36.0, -8.0, -9.5)   ## deep-water lie-up, well off the rig
var rise_path: Array = []      ## den -> east rim -> wet deck; walked backwards to go home
var spawn_index: int = 0

# ---- size and shape ----------------------------------------------------------------
const SHELL_M: float = 3.0          ## generated shell, longest axis (the ordinary crab: 1.1)
const HIP_OUT: float = 0.62         ## hip sockets, out along the body's X (its left/right)
const HIP_Y: float = 1.15           ## hips sit ON TOP of the carapace — the legs arch over
const KNEE_OUT: float = 1.15
const KNEE_UP: float = 0.75         ## knee apex ~1.9 m: the tallest part of the animal
const FOOT_OUT: float = 0.85
const FOOT_DROP: float = 1.90       ## HIP_Y + KNEE_UP - FOOT_DROP = 0.0 — feet on the deck
const STRIDE: float = 1.15          ## metres of ground per complete leg cycle

# ---- behaviour ---------------------------------------------------------------------
const HUNT_SPEED: float = 1.05      ## heavy: slower than the ordinary crab's 1.6 roam
const CHASE_SPEED: float = 3.0      ## slower than your 3.2 walk — it wins by not stopping
const SWIM_SPEED: float = 2.8
const CLIMB_SPEED: float = 1.5
const DETECT: float = 15.0
const HUNT_RADIUS: float = 46.0
const GIVE_UP: float = 34.0
const CONTACT: float = 2.35         ## its reach is its leg span, not its shell
const BITE_DAMAGE: float = 0.34
const BITE_COOLDOWN: float = 2.4
const BITE_SHOVE: float = 11.0
const MAX_HP: float = 9.0           ## the ordinary crab DIES at 6 (crab.gd, 2026-07-26)
const HUNT_CHANCE: float = 0.5      ## owner spec: each king, each night, independently
# The light bar. An ordinary crab breaks off at 2.35 brightness units; a flashlight only
# HAS 4.0 at point blank, so at 3.4 a king gives ground only for a beam held dead on it
# from about a metre and a half — which is inside its own bite reach. Bright light does
# work on a king. Using it costs you something, and it buys a couple of seconds.
const SCARE_BRIGHT: float = 3.4
const SCARE_TIME: float = 1.4       ## and it has to be HELD there, not flicked across it
const BACKOFF_TIME: float = 2.4     ## then it comes on again
const SAME_LEVEL_Y: float = 3.0
const COMMIT_TIME: float = 6.0
# Body origin above the seated surface. Not arbitrary: HIP_Y + KNEE_UP - FOOT_DROP puts the
# ankle exactly on the origin plane and the dactyl reaches 0.11 below it, so 0.14 stands the
# toe tips about 3 cm off the plating — touching, without the capsules z-fighting the deck.
const CLEAR: float = 0.14
## Ground-seat catch-up rate. MUST exceed CHASE_SPEED or the seat lags and teleports.
const SEAT_CATCHUP: float = 8.0
const BODY_R: float = 0.85
const PROBE_H: float = 0.9          ## probes at chest height: it steps over crates and kerbs

var state: State = State.DEN
var hp: float = MAX_HP
var up: Vector3 = Vector3.UP
var heading: Vector3 = Vector3.FORWARD

var _model: Node3D
var _mats: Array = []
## Deliberately EMPTY, and deliberately present. TestRunner's crab-anatomy block walks the
## "giant_crab" group, takes an arbitrary member, and asserts BOTH that it has a body
## (`_model != null or _legs.size() == 8`) and that nothing visible hangs off `_legs` —
## that second assertion is the guard against the old floating-claw-overlay bug. A king
## satisfies the first through `_model` and the second by keeping its real, deliberately
## VISIBLE articulation in `_limbs` instead. Do not move the limbs into `_legs`.
var _legs: Array = []
var _limbs: Array = []              ## the eight jointed walking legs
var _claws: Array = []              ## the two pincer arms
var _model_base_y: float = 0.0

var _level: int = CRABS.L_WATER
var _roam_target: Vector3
var _roam_hold: float = 0.0
var _climb_path: Array = []
var _climb_i: int = 0
var _climb_to: int = CRABS.L_WET
var _descending: bool = false
var _wp_index: int = 0

var _committed: bool = false        ## this night's coin came up hunt
var _wait: float = 0.0              ## how long after dark before it hauls out
var _beaten: bool = false           ## driven off by melee: done until tomorrow night
var _hunting_group: bool = false    ## currently a member of "giant_crab"
var _recoil: float = 0.0
var _bite_cd: float = 0.0
var _lit_t: float = 0.0
var _scare_cd: float = 0.0
var _backoff: float = 0.0
var _commit: float = 0.0
var _sense_cd: float = 0.0          ## brief blindness after a blocked approach — see _pursue

var _gait: float = 0.0              ## in CYCLES, advanced by distance — never by time
var _idle_t: float = 0.0
var _snap_t: float = 0.0
var _speed: float = 0.0
var _last_pos: Vector3
var _beat: float = -1.0
var _seated: bool = false
var _skip: Array = []
var _stalled: float = 0.0
var _step_accum: float = 0.0
var _rng := RandomNumberGenerator.new()

const SCUTTLE_SHOTS := ["scuttle_a", "scuttle_b", "scuttle_c"]
const SCUTTLE_DB: float = -11.0     ## a big animal on steel plate; the crab's is -20
const SCUTTLE_RANGE: float = 18.0

func _ready() -> void:
	_rng.seed = hash("king_crab") + spawn_index
	_build_body()
	add_to_group("hittable")     # melee finds it through this group and calls repel()
	add_to_group("king_crab")
	# NOT "giant_crab" at rest: TestRunner asserts the daylight pack is exactly fourteen,
	# and a king asleep in the deep is not one of the fourteen. It joins the group when it
	# hauls out and leaves again when it goes home — so anything counting the crabs that
	# are actually ON the rig tonight counts it, and the daylight census does not.
	GameClock.night.connect(_on_night)
	GameClock.dawn.connect(_on_dawn)
	global_position = den
	_last_pos = global_position
	_roam_target = den

## ---------- body ----------

func _build_body() -> void:
	# 1. THE SHELL. Nothing procedural is built before this call, so replace() has nothing
	#    of ours to hide; it attaches the generated mesh and shades it with the motion
	#    shader. A slow SCUTTLE beat: the shader's whole-mesh limb wave is the carapace's
	#    creak, and the real leg motion is the jointed geometry built in step 3.
	var gen: Dictionary = ANIM.replace(self, MODEL_PATH, SHELL_M, ANIM.Mode.SCUTTLE,
		0.05, 0.9, NO_GLOW)
	if not gen.is_empty():
		_model = gen["model"]
		_mats = gen["mats"]
		_model_base_y = CRABS.ground_model(_model)
	# 2. FACT #2, the one that has already cost a session: CreatureAnim.replace() hides
	#    every MeshInstance3D that exists on the host when it runs. Every piece of limb
	#    geometry below is therefore built AFTER it. Built before, it would be created and
	#    then immediately hidden — visible in the scene tree, invisible on screen, and
	#    animated perfectly for nobody.
	# 3. THE LIMBS.
	var chitin: Material = KIT.mat(Color(0.52, 0.20, 0.11), 0.55)   # deep rust-red shell
	var joint: Material = KIT.mat(Color(0.30, 0.13, 0.09), 0.45)    # darker at the joints
	var pale: Material = KIT.mat(Color(0.86, 0.79, 0.64), 0.6)      # bone-pale pincers
	_build_legs(chitin, joint)
	_build_claws(chitin, pale)

## Eight walking legs, four a side, each a hip -> femur -> knee -> tibia -> dactyl chain.
## The femur arches UP and OUT over the carapace and the tibia comes back DOWN outside it,
## which is what makes a king crab read as a king crab: the shell is low and the legs are
## the animal. The rest pose puts every foot exactly on the deck plane (y = 0), so the
## body origin can be seated at CLEAR above the plating and the feet land on it.
func _build_legs(chitin: Material, joint: Material) -> void:
	for i in range(8):
		var side: float = 1.0 if i < 4 else -1.0
		var j: int = i % 4
		var z_along: float = -0.85 + float(j) * 0.57      # front to back along the body
		var femur: Vector3 = Vector3(side * KNEE_OUT, KNEE_UP, 0.0)
		var tibia: Vector3 = Vector3(side * FOOT_OUT, -FOOT_DROP, 0.0)
		var hip := Node3D.new()
		add_child(hip)
		hip.position = Vector3(side * HIP_OUT, HIP_Y, z_along)
		# NO joint-knuckle balls here (there used to be one at every hip and knee: 16
		# total). They were meant to cap the seam where two limb capsules meet at an
		# angle, but because they're built AFTER ANIM.replace() (fact #2 — the limbs
		# have to be, so they stay visible), nothing ever hides them, and in the darker
		# `joint` material they read as a scattered dotted pattern across the whole
		# animal instead of a clean shell. The capsule overlap at each hinge is enough
		# on its own; owner call, 2026-07-25b: remove them.
		KIT.limb(hip, Vector3.ZERO, femur, 0.085, chitin)
		var knee := Node3D.new()
		hip.add_child(knee)
		knee.position = femur
		KIT.limb(knee, Vector3.ZERO, tibia, 0.062, chitin)
		var foot := Node3D.new()
		knee.add_child(foot)
		foot.position = tibia
		KIT.limb(foot, Vector3.ZERO, Vector3(side * 0.17, -0.11, 0.0), 0.045, joint)
		# Metachronal wave: a quarter-cycle apart down each side, and the two sides in
		# antiphase, so four feet are always planted and the animal never floats.
		_limbs.append({"hip": hip, "knee": knee, "foot": foot, "side": side,
			"phase": float(j) * 0.25 + (0.0 if side > 0.0 else 0.5)})

## Two arms, forward and outboard of the shell, each ending in a jaw that really opens.
## Shoulders sit AHEAD of the front hip pair (z -1.15 against the front hip's -0.85) and
## inboard of them, so an arm and a walking leg never grow out of the same socket. Fully
## extended the jaw tips reach about 3 m in front of the body origin — which is deliberate:
## CONTACT is 2.35 m, so the claw arrives on the player at the moment the bite lands
## instead of a hit registering from empty air.
func _build_claws(chitin: Material, pale: Material) -> void:
	for i in range(2):
		var side: float = 1.0 if i == 0 else -1.0
		var arm: Vector3 = Vector3(side * 0.32, -0.12, -0.62)
		var fore: Vector3 = Vector3(side * -0.05, -0.18, -0.60)
		var shoulder := Node3D.new()
		add_child(shoulder)
		shoulder.position = Vector3(side * 0.45, 0.95, -1.15)
		KIT.limb(shoulder, Vector3.ZERO, arm, 0.11, chitin)
		var elbow := Node3D.new()
		shoulder.add_child(elbow)
		elbow.position = arm
		KIT.limb(elbow, Vector3.ZERO, fore, 0.13, chitin)
		var wrist := Node3D.new()
		elbow.add_child(wrist)
		wrist.position = fore
		# Two prism jaws on their own pivots, laid forward (-Z) and hinged in that plane.
		# The base rotation is kept so the per-frame gape is an offset from it and the jaws
		# can never wander off their hinge.
		var jaw_size := Vector3(0.17, 0.66, 0.12)
		var upper: Node3D = KIT.fin(wrist, Vector3.ZERO, jaw_size, pale,
			Vector3(-90, 0, 0), Vector3(0, jaw_size.y * 0.5, 0))
		var lower: Node3D = KIT.fin(wrist, Vector3.ZERO, jaw_size, pale,
			Vector3(-90, 0, 0), Vector3(0, jaw_size.y * 0.5, 0))
		_claws.append({"shoulder": shoulder, "elbow": elbow,
			"upper": upper, "lower": lower, "side": side})

## ---------- the night coin ----------

## Owner spec: at most two active, and EACH ONE independently has a 50% chance of leaving
## the water to hunt for food each night. The roll is per-king and per-night — there is no
## "one of them always comes".
func _on_night() -> void:
	if state == State.GONE:
		return
	hp = MAX_HP
	_beaten = false
	# Owner spec (2026-07-25b): never on the rig's first night. day_count only ticks up
	# when a NIGHT phase COMPLETES (game_clock.gd _advance_phase), so it still reads 0
	# at the instant this fires for night one — the coin only starts turning from the
	# second night on.
	if GameClock.day_count == 0:
		_committed = false
	else:
		_committed = _rng.randf() < HUNT_CHANCE
	# Staggered so two kings never haul out over the rim shoulder to shoulder.
	_wait = _rng.randf_range(8.0, 90.0) + float(spawn_index) * 25.0

func _on_dawn() -> void:
	_committed = false
	# Not while it is already on its way: _go_home() reloads the current flight from its
	# first waypoint, so calling it again mid-descent would make it walk that flight twice.
	if state != State.DEN and state != State.GONE and state != State.RETREAT:
		_go_home()

func _go_home() -> void:
	_backoff = 0.0
	state = State.RETREAT
	_descending = _level > CRABS.L_WET and _set_link(CRABS.next_toward(_level, CRABS.L_WET))
	if not _descending:
		_wp_index = maxi(rise_path.size() - 1, 0)

## While it is up on the rig it counts as one of the night's crabs; asleep in the deep it
## does not (see the group note in _ready).
func _join_hunt() -> void:
	if _hunting_group:
		return
	_hunting_group = true
	add_to_group("giant_crab")
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("Something came over the rim that is far too big to be one of them.")

func _leave_hunt() -> void:
	if not _hunting_group:
		return
	_hunting_group = false
	remove_from_group("giant_crab")

## ---------- fightback ----------

## Same contract as GiantCrab.repel, so player_controller._melee_attack drives it without
## knowing the difference. Three times the health, and it barely moves when it is hit —
## a shove that pushes an ordinary crab back half a metre moves this one a hand's width.
func repel(from_pos: Vector3, damage: float) -> void:
	if state == State.GONE or state == State.RETREAT or state == State.DEN:
		return
	hp -= damage
	_recoil = 0.3
	_snap_t = maxf(_snap_t, 0.45)
	var away: Vector3 = global_position - from_pos
	away.y = 0.0
	if away.length() > 0.05:
		global_position += away.normalized() * 0.15
		_face(from_pos)
	AudioDirector.play_one_shot("clang", global_position, -3.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hp <= 0.0:
		_beaten = true
		_committed = false
		_go_home()
		if hud and hud.has_method("toast"):
			hud.toast("The big one turns, drags itself to the rim, and is gone under.")
	else:
		state = State.PURSUE
		_commit = COMMIT_TIME
		if hud and hud.has_method("toast"):
			hud.toast("It hardly feels it. The claws come up.")

func _try_bite(player: Node3D) -> void:
	if _bite_cd > 0.0:
		return
	_bite_cd = BITE_COOLDOWN
	_recoil = 0.55
	_snap_t = 0.7
	PlayerState.life -= BITE_DAMAGE
	AudioDirector.play_one_shot("crab_snap", global_position, 0.0)
	if player is CharacterBody3D:
		var dir: Vector3 = player.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			(player as CharacterBody3D).velocity += dir.normalized() * BITE_SHOVE + Vector3.UP * 3.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("The big claw closes on you and throws you down the deck.")

## ---------- state machine ----------

func _process(delta: float) -> void:
	_animate(delta)
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_scare_cd = maxf(_scare_cd - delta, 0.0)
	_sense_cd = maxf(_sense_cd - delta, 0.0)
	if _recoil > 0.0:
		_recoil -= delta
		if state != State.RETREAT:
			_seat(delta)
			return
	Journal.discover_if_near(self, "creature_lamplight_crab", 26.0)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	_check_light(delta, player)
	match state:
		State.GONE:
			return
		State.DEN:
			_den(delta)
		State.RISE:
			_rise(delta)
		State.HUNT:
			_hunt(delta, player)
		State.CLIMB:
			_climb(delta)
		State.PURSUE:
			_pursue(delta, player)
		State.RETREAT:
			_retreat(delta)
	_seat(delta)

## Resting on the leg foundation, not swimming (owner call, 2026-07-25b: `den` now sits
## against the SE leg's submerged foot instead of out in open water — see bloom_fauna.gd
## _spawn_king_crabs). It settles onto that point once and stays there, motionless, for
## the whole day; the old version drifted a few metres round its lie-up continuously,
## which read as swimming in place rather than a boss lying up at the base of the rig.
func _den(delta: float) -> void:
	_leave_hunt()
	# Settled and motionless, _step_free stops calling _orient — and a body that never
	# orients never takes up the frame the seat is handing it. So square up every frame:
	# on the leg foundation that is what lays the shell down along the concrete instead of
	# leaving it standing upright with its feet in the slope.
	if _step_free(den, SWIM_SPEED * 0.2, delta):
		_orient(delta)
	if _committed and not _beaten and GameClock.current_phase == GameClock.Phase.NIGHT:
		_wait -= delta
		if _wait <= 0.0:
			state = State.RISE
			_wp_index = 0

## The haul-out, along the authored lane: deep water -> the east rim -> over the lip onto
## the wet deck. Direct motion, no teleporting, the same grammar the pack's climb uses.
func _rise(delta: float) -> void:
	if GameClock.current_phase != GameClock.Phase.NIGHT:
		_go_home()
		return
	if _wp_index >= rise_path.size():
		_arrive_on_deck()
		return
	if _step_free(rise_path[_wp_index], SWIM_SPEED, delta):
		_wp_index += 1
		if _wp_index >= rise_path.size():
			_arrive_on_deck()

func _arrive_on_deck() -> void:
	_level = CRABS.L_WET
	_seated = false
	_join_hunt()
	AudioDirector.play_one_shot("splash", global_position, -2.0)
	state = State.HUNT
	_roam_target = _pick_roam()
	_roam_hold = 0.0

## Up on the plating: roam, and hunt across the whole rig the same way the pack does.
func _hunt(delta: float, player: Node3D) -> void:
	if GameClock.current_phase != GameClock.Phase.NIGHT:
		_go_home()
		return
	if _backoff > 0.0:
		_back_off(delta, player)
		return
	# Self-heal the level: shot scripts stage members of the "giant_crab" group by writing
	# `state` and `global_position` directly, which would otherwise leave a king standing on
	# plating while it still believes it is in the water (and so has nowhere to roam).
	if _level == CRABS.L_WATER and global_position.y > 1.0:
		_level = CRABS.level_for(global_position)
		_roam_target = _pick_roam()
	if _sense(player):
		return
	if _roam_hold > 0.0:
		_roam_hold -= delta
		_orient(delta)      # standing still on sloped plate, it still settles onto the face
		return
	if _step_deck(_roam_target, HUNT_SPEED, delta):
		_roam_target = _pick_roam()
		_roam_hold = _rng.randf_range(0.8, 3.4)

func _sense(player: Node3D) -> bool:
	if player == null or _scare_cd > 0.0 or _sense_cd > 0.0:
		return false
	var p: Vector3 = player.global_position
	var flat: float = Vector2(p.x - global_position.x, p.z - global_position.z).length()
	var eff: float = DETECT
	if player.has_method("detection_factor"):
		eff *= player.detection_factor()
	if absf(p.y - global_position.y) < SAME_LEVEL_Y and flat < eff:
		state = State.PURSUE
		_commit = COMMIT_TIME
		return true
	if flat < HUNT_RADIUS:
		var want: int = CRABS.level_for(p)
		if want != _level and _begin_climb(want):
			return true
	return false

func _pursue(delta: float, player: Node3D) -> void:
	if player == null or GameClock.current_phase != GameClock.Phase.NIGHT:
		_go_home()
		return
	if _backoff > 0.0:
		_back_off(delta, player)
		return
	var p: Vector3 = player.global_position
	if absf(p.y - global_position.y) > SAME_LEVEL_Y:
		var want: int = CRABS.level_for(p)
		if want != _level and _begin_climb(want):
			return
	var d: float = global_position.distance_to(p)
	if d > GIVE_UP:
		_commit -= delta
		if _commit <= 0.0:
			state = State.HUNT
			_roam_target = _pick_roam()
			return
	else:
		_commit = COMMIT_TIME
	# A true return means EITHER "arrived" OR "boxed in and gave up" (the probe step reports
	# both the same way). Arriving is the whole point; still being far away means a bulkhead
	# or a crate stack is in the line of approach, so it stops grinding on it and roams a
	# beat, which picks a new line instead of pressing a wall until dawn.
	if _step_deck(Vector3(p.x, global_position.y, p.z), CHASE_SPEED, delta, p) \
			and d > CONTACT * 1.6:
		state = State.HUNT
		_roam_target = _pick_roam()
		_roam_hold = 0.4
		_sense_cd = 2.5
		return
	if _snap_t <= 0.0 and _rng.randf() < delta * 1.1:
		_snap_t = 0.4          # it clacks the whole way in
	if d < CONTACT:
		_try_bite(player)

## Pushed out of a beam. It gives ground — a couple of metres, no more — and returns.
func _back_off(delta: float, player: Node3D) -> void:
	_backoff -= delta
	if player != null:
		var away: Vector3 = global_position - player.global_position
		away.y = 0.0
		if away.length() > 0.05:
			_step_deck(global_position + away.normalized() * 3.0, CHASE_SPEED * 0.7, delta)
	if _backoff <= 0.0:
		state = State.HUNT
		_roam_target = _pick_roam()
		_roam_hold = 0.0

## Home: down whatever flights it climbed, then back over the rim and under.
func _retreat(delta: float) -> void:
	if _descending:
		_walk_link(delta, CLIMB_SPEED * 1.2)
		if _climb_i >= _climb_path.size():
			_level = _climb_to
			_seated = false
			_descending = _level > CRABS.L_WET \
				and _set_link(CRABS.next_toward(_level, CRABS.L_WET))
			if not _descending:
				_wp_index = maxi(rise_path.size() - 1, 0)
		return
	_leave_hunt()
	if _wp_index >= 0 and not rise_path.is_empty():
		if _step_free(rise_path[_wp_index], SWIM_SPEED, delta):
			_wp_index -= 1
		return
	if _step_free(den, SWIM_SPEED * 0.8, delta):
		state = State.DEN
		_level = CRABS.L_WATER
		_seated = false
		up = Vector3.UP
		_roam_target = den
		_roam_hold = 0.0

## ---------- climbing: the crab's own flights ----------

func _set_link(next: int) -> bool:
	var path: Array = CRABS.link_path(_level, next)
	if path.is_empty():
		return false
	_climb_path = path
	_climb_i = 0
	_climb_to = next
	_stalled = 0.0
	_seated = false    # unseat NOW: a seated first step would cancel the flight's rise
	return true

func _begin_climb(target: int) -> bool:
	if target == _level or not _set_link(CRABS.next_toward(_level, target)):
		return false
	state = State.CLIMB
	return true

func _walk_link(delta: float, speed: float) -> void:
	if _climb_i >= _climb_path.size():
		return
	var target: Vector3 = _climb_path[_climb_i]
	var dir: Vector3 = target - global_position
	if dir.length() > 0.05:
		up = up.lerp(CRABS.slope_up(dir.normalized(), up),
			clampf(delta * 3.0, 0.0, 1.0)).normalized()
	if _step_free(target, speed, delta):
		_climb_i += 1

func _climb(delta: float) -> void:
	_walk_link(delta, CLIMB_SPEED)
	if _climb_i < _climb_path.size():
		return
	_level = _climb_to
	_climb_path = []
	_seated = false
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null and GameClock.current_phase == GameClock.Phase.NIGHT:
		var want: int = CRABS.level_for(player.global_position)
		if want != _level and _begin_climb(want):
			return
	state = State.HUNT
	_roam_target = _pick_roam()
	_roam_hold = 0.0

func _pick_roam() -> Vector3:
	var p: Vector3 = CRABS.roam_point(_level, _rng)
	return global_position if p == Vector3.ZERO else p

## ---------- light ----------

func _check_light(delta: float, player: Node3D) -> void:
	if state != State.HUNT and state != State.PURSUE:
		_lit_t = 0.0
		return
	# The eye line of a two-metre animal, not a knee-high one.
	if CRABS.light_pressure_at(get_tree(), player, global_position + Vector3(0, 1.2, 0)) \
			>= SCARE_BRIGHT:
		_lit_t += delta
		if _lit_t >= SCARE_TIME:
			_lit_t = 0.0
			_backoff = BACKOFF_TIME
			_scare_cd = _rng.randf_range(5.0, 9.0)
			_snap_t = maxf(_snap_t, 0.4)
			var hud: Node = get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("toast"):
				hud.toast("The beam stops it — for a moment. It gives a little ground.")
	else:
		_lit_t = maxf(_lit_t - delta * 2.0, 0.0)

## ---------- movement ----------

func _face(target: Vector3) -> void:
	_orient(1.0, target)

## It squares up like its smaller kin: sideways when travelling, claws-forward at a focus.
func _orient(delta: float, focus: Variant = null) -> void:
	var fwd: Vector3
	if focus != null:
		fwd = (focus as Vector3) - global_position
	else:
		fwd = heading.rotated(up, PI * 0.5)
	fwd = fwd - up * fwd.dot(up)
	if fwd.length() < 0.01:
		return
	var want := Basis.looking_at(fwd.normalized(), up)
	# Slower to turn than an ordinary crab: mass has to come round.
	global_basis = global_basis.orthonormalized().slerp(want, clampf(delta * 3.0, 0.0, 1.0))

func _step_move(target: Vector3, speed: float, delta: float, probe: bool,
		focus: Variant = null) -> bool:
	var to_t: Vector3 = target - global_position
	var arrive: Vector3 = to_t
	if _seated:
		arrive = to_t - up * to_t.dot(up)
	if arrive.length() < (0.6 if _seated else 0.4):    # a big animal arrives sooner
		_stalled = 0.0
		return true
	var dir: Vector3 = to_t
	if _seated:
		dir = dir - up * dir.dot(up)
		if dir.length() < 0.05:
			dir = to_t
	dir = dir.normalized()
	heading = dir
	var step: Vector3 = dir * speed * delta
	if probe and up.y > 0.7:
		# It honours the same no-go volumes as the pack: a powered LightZone or a burning
		# flare is a wall it slides along rather than a place it walks into.
		if CRABS.light_blocked(get_tree(), global_position + step):
			var side: Vector3 = up.cross(dir).normalized() * speed * delta
			if CRABS.light_blocked(get_tree(), global_position + side):
				side = -side
			if CRABS.light_blocked(get_tree(), global_position + side):
				_orient(delta, focus)
				return false
			step = side
		var moved: Vector3 = MOVE.step(self, step, BODY_R, PROBE_H)
		if moved.length() < step.length() * 0.25:
			_stalled += delta
			if _stalled > 2.5:
				_stalled = 0.0
				return true
		else:
			_stalled = 0.0
	else:
		global_position += step.limit_length(to_t.length())
	_orient(delta, focus)
	return false

func _step_deck(target: Vector3, speed: float, delta: float,
		focus: Variant = null) -> bool:
	return _step_move(target, speed, delta, true, focus)

func _step_free(target: Vector3, speed: float, delta: float) -> bool:
	return _step_move(target, speed, delta, false)

## The footing window and the roll-onto-a-new-normal rate, both scaled up from the
## ordinary crab's 0.55 / 7.0: a bigger animal reads its face from further out and takes
## longer to come over onto it.
const SEAT_REACH: float = 0.7
const SEAT_EASE: float = 6.0

## THE SURFACE FRAME (2026-07-25). A king used to seat only while it was HUNTing or
## PURSUing on the plating, so anywhere else it stood bolt upright in world space: lying
## up against the SE leg's foundation it floated off the sloped concrete, and out on a
## brace or at the edge of the plating it clipped through the face instead of lying on
## it. It now carries the SAME frame its smaller kin does — FaunaMove.seat, one
## implementation for both — so a king standing on a leg, on a sloped brace or over a
## deck rim lies PARALLEL to that surface, at its own scale: a wider footing window
## (reach 0.7 against the crab's 0.55) and a slower roll onto a new normal, because five
## metres and a quarter-tonne of animal does not snap onto a new face the way a small one
## does.
##
## Still NOT seated for a climb or an open-water transit: a flight owns its own `up` (the
## slope), and a swimming king that stays stuck to a face just slides along it — the
## projection in _step_move cancels the component pointing away from the wall, which is
## the bug that once stranded the pack flat against the concrete.
func _seat(delta: float) -> void:
	if state == State.CLIMB or (state == State.RETREAT and _descending):
		_seated = false
		return
	if state == State.RISE or state == State.RETREAT:
		_seated = false
		up = up.lerp(Vector3.UP, clampf(delta * 2.5, 0.0, 1.0)).normalized()
		return
	if _skip.is_empty():
		_skip = MOVE.kin_bodies(self)
	var frame: Dictionary = MOVE.seat(self, up, heading, _seated, delta,
		SEAT_REACH, CLEAR, SEAT_EASE, SEAT_CATCHUP, _skip)
	up = frame["up"]
	heading = frame["heading"]
	_seated = frame["seated"]
	if not _seated:
		# Nothing under it: it is in the water off the rig, so ease upright and let the
		# authored den / rise points carry it.
		up = up.lerp(Vector3.UP, clampf(delta * 2.5, 0.0, 1.0)).normalized()

## ---------- articulation ----------

## The gait clock. THIS is the anti-moonwalk rule: _gait advances by metres of ground
## actually covered divided by STRIDE, so it is impossible for the legs to cycle while the
## body is stationary, or to cycle at the wrong rate while it is moving. Amplitude fades
## with speed on top of that, so a standing king settles into a rest pose instead of
## marching in place.
func _animate(delta: float) -> void:
	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position
	_speed = moved / maxf(delta, 0.0001)
	_gait = fmod(_gait + moved / STRIDE, 1.0)
	_idle_t += delta
	_snap_t = maxf(_snap_t - delta, 0.0)
	var drive: float = clampf(_speed / CHASE_SPEED, 0.0, 1.0)
	_pose_legs(delta, drive)
	_pose_claws(delta)
	if _model:
		# The shell itself: a slow creak of the carapace, a rear in a chase, a lurch on the
		# strike. Written on the model's own transform so nothing can detach from it.
		var menace: float = 1.0 if state == State.PURSUE else 0.0
		var rear: float = -0.16 * menace
		if _snap_t > 0.0:
			rear += 0.22 * sin(_snap_t * 22.0)
		_model.rotation.x = lerpf(_model.rotation.x, rear,
			clampf(delta * (12.0 if _snap_t > 0.0 else 3.5), 0.0, 1.0))
		_model.position.y = lerpf(_model.position.y,
			_model_base_y + 0.06 * menace + sin(_idle_t * 1.1) * 0.02, delta * 3.0)
		# Three discrete beats on the carapace shader, tied to STATE and not to speed.
		var want_beat: float = 0.55
		if state == State.PURSUE:
			want_beat = 1.9
		elif _speed > 0.25:
			want_beat = 1.05
		_set_beat(want_beat)

## Sideways walking, which is what a crab actually does: the propulsive stroke is the leg
## EXTENDING and FLEXING along the body's own left-right axis, not swinging fore and aft.
## So `reach` (a cosine) drives hip elevation and knee flex together — the foot goes out,
## plants, is dragged in as the body passes over it — while `lift` (the quarter-cycle
## offset sine) takes it off the plating for the return. Four feet are down at all times.
func _pose_legs(delta: float, drive: float) -> void:
	for leg in _limbs:
		var side: float = leg["side"]
		var ph: float = _gait + float(leg["phase"])
		var reach: float = cos(TAU * ph)
		var lift: float = maxf(sin(TAU * ph), 0.0)
		# At rest the whole chain eases to a wide, planted stance with only a slow swell in
		# it — a stopped animal is still breathing, but it is not stepping.
		var idle: float = sin(_idle_t * 0.9 + float(leg["phase"]) * TAU) * 0.022
		var hip_z: float = side * ((0.30 * lift + 0.12 * reach) * drive + idle)
		var knee_z: float = -side * ((0.42 * reach + 0.26 * lift) * drive + idle * 0.5)
		var foot_z: float = side * (0.20 * lift * drive)
		var t: float = clampf(delta * 14.0, 0.0, 1.0)
		var hip := leg["hip"] as Node3D
		var knee := leg["knee"] as Node3D
		var foot := leg["foot"] as Node3D
		hip.rotation.z = lerpf(hip.rotation.z, hip_z, t)
		knee.rotation.z = lerpf(knee.rotation.z, knee_z, t)
		foot.rotation.z = lerpf(foot.rotation.z, foot_z, t)

## The arms. Idling they hang and breathe; hunting they come up and the jaws hold open;
## _snap_t slams them shut — the same timer the bite and the melee riposte set.
func _pose_claws(delta: float) -> void:
	var reared: bool = state == State.PURSUE
	var t: float = clampf(delta * 8.0, 0.0, 1.0)
	for claw in _claws:
		var side: float = claw["side"]
		var sh := claw["shoulder"] as Node3D
		var el := claw["elbow"] as Node3D
		var want_sh: float = -side * (0.40 if reared else 0.06)
		var want_el: float = -side * (0.30 if reared else 0.10)
		sh.rotation.z = lerpf(sh.rotation.z, want_sh + side * sin(_idle_t * 1.3) * 0.03, t)
		el.rotation.z = lerpf(el.rotation.z, want_el, t)
		# Gape: wide while it threatens, shut hard on the strike.
		var gape: float = 16.0 if reared else 7.0
		gape += sin(_idle_t * 2.1 + side) * 2.5
		if _snap_t > 0.0:
			gape = 1.0
		var up_jaw := claw["upper"] as Node3D
		var lo_jaw := claw["lower"] as Node3D
		var snap_t: float = clampf(delta * (26.0 if _snap_t > 0.0 else 7.0), 0.0, 1.0)
		up_jaw.rotation_degrees.x = lerpf(up_jaw.rotation_degrees.x, -90.0 - gape, snap_t)
		lo_jaw.rotation_degrees.x = lerpf(lo_jaw.rotation_degrees.x, -90.0 + gape, snap_t)

## The motion shader computes t = TIME * rate + phase, so a new rate written at second T
## teleports the wave's phase by T * delta_rate — at ten minutes in, a small nudge is
## dozens of cycles. There are exactly three rates, each written once on its state change.
## The limbs are where this animal's motion actually lives; the shader is only the creak.
func _set_beat(rate: float) -> void:
	if is_equal_approx(rate, _beat):
		return
	_beat = rate
	ANIM.drive(_mats, rate, 0.0, 0.05)

## ---------- audio ----------

## Same honesty gate as the pack — moving, near, framed, unoccluded — but a slower, much
## heavier footfall, because a five-metre animal on steel plate is not a scuttle.
func _physics_process(delta: float) -> void:
	if _speed > 0.25 and _audio_gate_open():
		_step_accum += delta * clampf(_speed * 0.9, 0.4, 2.4)
		if _step_accum >= 1.0:
			_step_accum = fmod(_step_accum, 1.0)
			AudioDirector.play_one_shot(SCUTTLE_SHOTS[_rng.randi() % SCUTTLE_SHOTS.size()],
				global_position, SCUTTLE_DB)
	else:
		_step_accum = 0.0

func _audio_gate_open() -> bool:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	if global_position.distance_to(player.global_position) > SCUTTLE_RANGE:
		return false
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false
	var ear: Vector3 = global_position + Vector3(0, 1.2, 0)
	if not cam.is_position_in_frustum(ear):
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, ear)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
