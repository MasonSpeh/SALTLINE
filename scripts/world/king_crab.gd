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
## THE ARTICULATION IS THE MESH'S OWN, AND THE CAPSULE OVERLAY IS GONE (owner: "big crab has
## 3-d texture connector tubes visible underneath").
##
## What was drawn: the generated giant_crab shell — a complete crab, eight sculpted legs and
## two sculpted claws — and then, built AFTER `ANIM.replace()` and therefore fully visible,
## a SECOND set of anatomy in bare capsules: eight hip->femur->knee->tibia->dactyl chains
## and two claw arms with prism jaws. 28 `CreatureKit.limb` capsules and 4 prisms, in flat
## untextured `KIT.mat` fills. Sixteen legs and four claws on one animal.
##
## Measured off the GLB (accessor bounds x +-0.949, y +-0.628, z +-0.541; `load_model`
## scales the LONGEST axis to SHELL_M 3.0, so x1.5813): the shell occupies x +-1.501,
## y 0.000..1.986, z +-0.855 above the body origin. Against that —
##   * every tibia ran from (+-1.77, 1.90) to (+-2.62, 0.00): 2.1 m of bare tube, entirely
##     outside the shell's own silhouette, descending past it to the plating. Eight of them.
##     That is the geometry "visible underneath".
##   * the dactyl stubs reached y -0.155 with their radius counted, so at CLEAR 0.14 the toe
##     tips were 15 mm INSIDE the deck — not the "about 3 cm off the plating" the old
##     comment claimed, which had left the capsule radius out of the sum.
##   * the claw shoulders sat at z -1.15 against a shell whose front face is z -0.855, i.e.
##     295 mm clear of the carapace in open air, with the mesh's own sculpted claws directly
##     behind them. That is exactly the bug crab.gd already deleted on the ordinary crab
##     after the owner reported "weird shapes hovering in front of crab claws"; the king was
##     left carrying it because it was the one species whose overlay was load-bearing.
##
## It is not load-bearing. `ANIM.Mode.SCUTTLE` walks the generated mesh's own legs in a
## metachronal wave (that is what the mode is for — crab.gd relies on nothing else), and
## menace is expressed the way the ordinary crab expresses it: the body rears in a chase and
## `_snap_t` drives a hard lurch on the strike. So the whole overlay is deleted.
##
## WHAT THAT COSTS, stated so nobody has to re-derive it: the old silhouette was 5.58 m
## toe-to-toe (the overlay's feet) by 1.986 m tall (the shell). The shell alone is 3.00 m by
## 1.986 m. HEIGHT is unchanged — the animal is still the promised "taller than you" and
## still 2.7x the ordinary crab's 1.1 m — and the span is what went. If the 5 m span is
## wanted back, SHELL_M is the whole lever now that the anatomy is sculpted rather than
## bolted on; at SHELL_M 5.0 the mesh measures 5.00 x 3.31 m, which is a much taller animal
## than the docstring above ever promised. That trade is a look call, not a code change.
##
## It shares the crab's rig knowledge rather than copying it: the level tree, the authored
## stair-tower flights, the light-brightness model and the no-go volumes all live in
## crab.gd as statics, so there is exactly one set of coordinates for the whole species.

const CRABS := preload("res://scripts/world/crab.gd")   # by path: class cache lags new files
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
# Body origin above the seated surface. This used to be 0.14, derived from the capsule
# overlay's dactyl — and derived wrong, since it left the dactyl capsule's own 0.045 radius
# out of the sum and buried the toe tips 15 mm in the plate. With the overlay gone the only
# thing standing on the surface is the generated shell, and `CreatureAnim.ground()` (via
# CRABS.ground_model) already puts that mesh's LOWEST point exactly on the host origin. So
# CLEAR is now nothing but z-fight margin: 30 mm is invisible on a 3 m animal and keeps the
# shell off the plate. Anything larger is a hover, because the mesh is grounded at zero.
const CLEAR: float = 0.03
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
## that second assertion is the guard against the floating-claw-overlay bug. A king
## satisfies the first through `_model`, and satisfies the second trivially now that its
## own capsule overlay is deleted (see the header): there is no procedural geometry on this
## animal at all, so there is nothing to hide and nothing to keep in step with the mesh.
var _legs: Array = []
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
	# THE SHELL, and nothing else. Nothing procedural is built before this call, so
	# replace() has nothing of ours to hide; it attaches the generated mesh and shades it
	# with the motion shader. SCUTTLE walks the mesh's OWN sculpted legs in a metachronal
	# wave — the same mode and the same asset the ordinary crab uses — which is why the
	# capsule overlay this function used to add after the call is gone rather than moved.
	# See the header for the measurement that condemned it.
	var gen: Dictionary = ANIM.replace(self, MODEL_PATH, SHELL_M, ANIM.Mode.SCUTTLE,
		0.05, 0.9, NO_GLOW)
	if not gen.is_empty():
		_model = gen["model"]
		_mats = gen["mats"]
		_model_base_y = CRABS.ground_model(_model)

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
	_resolve_den_face()      # one measurement, retried until the CSG collision has baked
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

## ---------- THE DEN FACE: measured once, then held as a plane ----------
##
## OWNER: "standing straight up, but should be sideways clinging to wall". True by
## construction, and the arithmetic is short. BloomFauna authors the dens at
## (+-27.0, -8.0, -9.5 / -12.5); the caisson faces are at |x| 25.00, unbroken from y 1.0 to
## y -23.5 (CrabLifeProbe's own column sweep prints exactly that). So the animal lay up
## 2.00 m out in open water. SEAT_REACH is 0.7, so FaunaMove.seat cast at most 1.19 m along
## -up from the body, found nothing, and returned seated=false — whereupon _seat's own
## fallback eases `up` toward world UP every frame. A boss "resting on the leg foundation"
## was hovering bolt upright beside it, with nothing under its feet at all. (That is also
## the sighting the deleted capsule limbs were hanging in — see the header.)
##
## The pack already solved this and AGENT_TRAPS records the rule: where a surface is
## provably ONE PLANE, hold it analytically and delete the raycast. crab.gd's ROOST branch
## is the reference; this is the same pin for a den.
##
## THE ONE MEASUREMENT IS FAUNA-PROOF THREE WAYS, because every creature on this rig carries
## a solid 0.6-0.85 m FaunaTouch sphere on the default layer and the reef seeds thirteen
## snails onto exactly these faces:
##   * MOVE.kin_bodies(self) excludes every fauna collider under the BloomFauna host;
##   * the hit normal must agree with the expected axis to FACE_DOT — an axis-aligned
##     casting answers, a sphere almost never does (the s21 mussel-bed rule);
##   * and it takes the DEEPEST of FACE_RAYS parallel casts. Anything the skip list missed —
##     a snail, a mussel bed, a coral head, a barnacle crust — is bolted ONTO the concrete
##     and therefore stands PROUD of it, so it can only ever be the shallower answer.
## After that there is no cast at all: immune to whatever the next session bolts on, and it
## cannot let go of the face.
const FACE_DOT: float = 0.985       ## a caisson face is axis-aligned; a touch sphere is not
const FACE_RAYS: int = 5            ## parallel casts across the face, spread FACE_SPREAD
## Spread VERTICALLY, not along z. The face is unbroken over 24.5 m of column (y 1.0 to
## y -23.5) and the dens lie at y -8, so a +-2 m vertical fan is guaranteed to stay on the
## same casting. A horizontal fan is not: den 0 sits at z -9.5 against a leg whose footprint
## ends at z -9, so rays spread in z would walk straight off the end of the concrete.
const FACE_SPREAD: float = 2.0      ## metres above and below the den
const FACE_REACH: float = 9.0       ## start this far outboard and cast in past the face
const FACE_MAX_STANDOFF: float = 5.0  ## a plane further in than this is not this den's leg
## Frames of retries. The CSG caissons bake their collision over the first frames of a boot
## (the s28 store-room lesson: a ray fired too early sails straight through the deck), so a
## single attempt in _ready would silently leave the animal unpinned for the session.
const FACE_TRIES: int = 240
var _den_n: Vector3 = Vector3.ZERO   ## outward normal of the face this den clings to
var _den_d: float = 0.0              ## p.dot(_den_n) ON the concrete — the face plane
var _den_tries: int = 0

func _resolve_den_face() -> void:
	if _den_n != Vector3.ZERO or _den_tries >= FACE_TRIES or not is_inside_tree():
		return
	_den_tries += 1
	# The outward normal comes from the den the spawner injected, not from a coordinate
	# repeated here: both dens lie outboard of a caisson's east/west face, so the sign of
	# their own x IS the normal. This file states none of the rig's numbers (see the header).
	if is_zero_approx(den.x):
		return
	var n := Vector3(signf(den.x), 0.0, 0.0)
	# The same cached list `_seat` uses. Building it walks every CollisionObject3D under the
	# BloomFauna host, so it is built once here and reused rather than rebuilt on each of the
	# up-to-FACE_TRIES retries.
	if _skip.is_empty():
		_skip = MOVE.kin_bodies(self)
	var best: float = INF
	for i in range(FACE_RAYS):
		var t: float = -1.0 + 2.0 * float(i) / float(FACE_RAYS - 1)
		var at: Vector3 = den + Vector3(0.0, t * FACE_SPREAD, 0.0)
		var hit: Dictionary = MOVE.surface_hit(self, at + n * FACE_REACH, n,
			0.0, FACE_REACH * 2.0, _skip)
		if hit.is_empty():
			continue
		if (hit["normal"] as Vector3).dot(n) < FACE_DOT:
			continue
		# Gate EACH ray on a sane stand-off before taking the deepest. Gating only the winner
		# would let one spurious deep hit — a ray that slipped past the leg and answered off
		# something inboard — reject the whole resolution and silently leave the animal
		# unpinned, which is the failure that looks exactly like the bug being fixed.
		var d: float = (hit["point"] as Vector3).dot(n)
		var standoff: float = den.dot(n) - d
		if standoff < 0.0 or standoff > FACE_MAX_STANDOFF:
			continue
		best = minf(best, d)
	if best == INF:
		return       # unresolved: the animal keeps today's open-water behaviour, and retries
	_den_n = n
	_den_d = best

## Where the animal actually lies up. The authored den names a FACE and a DEPTH; this is
## that point pulled onto the measured concrete at the body's own stand-off, so the king
## walks to the wall rather than to a spot 2 m out in front of it. Unresolved, it is the
## authored point unchanged.
func _den_point() -> Vector3:
	if _den_n == Vector3.ZERO:
		return den
	return den + _den_n * ((_den_d + CLEAR) - den.dot(_den_n))

## Resting ON the leg foundation, not swimming (owner call, 2026-07-25b: `den` now sits
## against a caisson's submerged foot instead of out in open water — see bloom_fauna.gd
## _spawn_king_crabs). It settles onto that point once and stays there, motionless, for
## the whole day; the old version drifted a few metres round its lie-up continuously,
## which read as swimming in place rather than a boss lying up at the base of the rig.
func _den(delta: float) -> void:
	_leave_hunt()
	# Settled and motionless, _step_free stops calling _orient — and a body that never
	# orients never takes up the frame the seat is handing it. So square up every frame:
	# on the leg face that is what lays the shell SIDEWAYS along the concrete instead of
	# leaving it standing upright beside it.
	if _step_free(_den_point(), SWIM_SPEED * 0.2, delta):
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
	if _step_free(_den_point(), SWIM_SPEED * 0.8, delta):
		state = State.DEN
		_level = CRABS.L_WATER
		_seated = false
		up = Vector3.UP          # the DEN pin in _seat rolls this onto the face next frame
		_roam_target = _den_point()
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
	# THE DEN IS A PLANE PIN (see THE DEN FACE above), not a raycast. It is what lays the
	# king SIDEWAYS on the caisson instead of standing it upright in the water beside it,
	# and — being analytic — no snail, mussel bed or coral head bolted to that concrete in a
	# later session can ever seat the animal on itself. The correction is eased at
	# SEAT_CATCHUP, never assigned, so nothing blinks even from the authored 2 m stand-off.
	if state == State.DEN and _den_n != Vector3.ZERO:
		up = _den_n
		var flat: Vector3 = heading - _den_n * heading.dot(_den_n)
		heading = flat.normalized() if flat.length() > 0.05 \
			else Vector3.UP.cross(_den_n).normalized()
		_seated = true
		var off: float = (_den_d + CLEAR) - global_position.dot(_den_n)
		global_position += (_den_n * off).limit_length(SEAT_CATCHUP * delta)
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

## The gait now lives entirely on the mesh: `_set_beat` writes the SCUTTLE shader's rate off
## STATE, and the rear/lurch below is written on the model's own transform. The distance-
## driven `_gait` counter that used to phase the capsule legs went with them — the
## anti-moonwalk rule it enforced is not needed for a shader wave that is a creak rather
## than a stride, and keeping a counter nothing reads is how dead code accumulates.
func _animate(delta: float) -> void:
	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position
	_speed = moved / maxf(delta, 0.0001)
	_idle_t += delta
	_snap_t = maxf(_snap_t - delta, 0.0)
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
