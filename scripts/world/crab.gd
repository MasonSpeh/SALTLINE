class_name GiantCrab extends Node3D
## The night threat, remade again (s14): a NATURALISTIC giant crab with real crab
## mechanics. TEN of them roost spread around the four caisson legs, clinging to the
## submerged concrete faces by day — visible to anyone who leans over a rim or swims.
## They carry a snail-style surface frame (an `up` normal + per-frame reseat), so they
## stand ON surfaces instead of floating at hand-typed heights, wrap over the deck rim,
## and crawl vertical faces. They move SIDEWAYS — body square across the travel line —
## except when squaring up to the player, claws forward. At night each crab leaves its
## leg, climbs an authored emergence lane over the wet-deck rim, patrols the plating and
## CHASES the player in darkness. A bite costs 0.2 life and shoves. Fightback: melee
## repel() or a held light (flashlight/lantern) for half a second sends it bolting; a
## powered LightZone (lamps, floodlights) it will not enter at all. Visible articulated
## claws ride the generated shell: they breathe open/closed, rear up in a chase, and
## SNAP shut on the bite. At dawn it visibly returns over the rim. Its sound is honest:
## soft chitin taps ONLY while moving, near, and actually visible — silence otherwise.

enum State { ROOST, EMERGE, PATROL, PURSUE, FLEE, GONE }

## Authored routes, injected by the spawner (BloomFauna) — every point is validated
## against the sonar scan of the rig (see s11 crab evidence table).
var roost_loop: Array = []     ## underwater cling loop on a caisson-leg face
var roost_up: Vector3 = Vector3.UP   ## the face normal that loop clings to
var emerge_path: Array = []    ## water -> rim -> deck; walked in reverse to go home
var patrol_loop: Array = []    ## open wet-deck circuit
var spawn_index: int = 0
var patrol_offset: Vector3 = Vector3.ZERO   ## fans the pack out on the shared loop

var state: State = State.ROOST
var _wp_index: int = 0
var patrol_speed: float = 1.6
var pursue_speed: float = 3.8
var detect_radius: float = 6.0
var contact_radius: float = 1.2
var hp: float = 3.0                 ## melee hits it can take before it quits the night

const ROOST_SPEED: float = 0.5      ## slow underwater sidle
const BITE_DAMAGE: float = 0.2      ## PlayerState.life is normalized 0..1 (owner spec: -0.2/hit)
const BITE_COOLDOWN: float = 2.5
const BITE_SHOVE: float = 6.0
const GIVE_UP_DIST: float = 14.0    ## running away works: pursuit breaks beyond this
const SCARE_TIME: float = 0.5       ## seconds of steady beam before it bolts
const EMERGE_STAGGER: float = 4.0   ## seconds between pack members leaving the water —
## ten crabs share six rim-lanes, so the stagger is also what keeps lane-mates from
## climbing through each other: the pack surfaces across ~36 s of nightfall.

var _resume_state: State = State.PATROL
var _recoil: float = 0.0            ## stagger timer after a strike / bite lunge
var _bite_cd: float = 0.0
var _lit_t: float = 0.0             ## how long a player light has been on it
var _scare_cd: float = 0.0          ## re-approach cooldown after a light scare
var _night_wait: float = 0.0        ## emergence stagger countdown
var _beaten: bool = false           ## repelled to zero hp: done for this night
var _fleeing_home: bool = false     ## FLEE reached the water and is walking to roost

# Anatomy / motion.
const KIT := preload("res://scripts/world/creature_kit.gd")
const ANIM := preload("res://scripts/world/creature_anim.gd")
const MOVE := preload("res://scripts/world/fauna_move.gd")
const MODEL_PATH := "res://assets/models/fauna/giant_crab/giant_crab.glb"
const NO_GLOW := Color(0, 0, 0)     ## naturalistic: rim/fresnel glow stays dark
var _model: Node3D
var _mats: Array = []
var _legs: Array = []               ## procedural fallback only
var _claw_arms: Array = []          ## VISIBLE overlay arms riding the generated shell
var _pincers: Array = []            ## the moving jaw pivot of each claw (rotation.x)
var _model_base_y: float = 0.0      ## grounded rest height of the generated mesh
var _gait_t: float = 0.0
var _bob_t: float = 0.0
var _last_pos: Vector3
var _speed: float = 0.0
var _resting_pose: bool = true
var _snap_t: float = 0.0            ## claw-snap timer: bite and threat snips

# Surface frame — the snail's trick (FaunaMove.SurfaceCrawler was written "so the crab
# can take it later"): carry the face normal the feet are stuck to, move in its tangent
# plane, and reseat against real geometry every frame. This is what killed the float —
# the old crab walked to waypoints hand-typed at y2.6 over a y2.0 deck with no ground
# check anywhere, so the whole pack hovered 0.6 m in the air.
const CLEAR: float = 0.10           ## body-origin height above the seated surface
var up: Vector3 = Vector3.UP
var heading: Vector3 = Vector3.FORWARD
var _seated: bool = false
var _skip: Array = []               ## other animals' collision RIDs — never ground
var _sidle_sign: float = 1.0        ## which side leads the sideways scuttle

# Scuttle audio: one-shots on the footfall cadence, hard-gated on visibility.
const SCUTTLE_SHOTS := ["scuttle_a", "scuttle_b", "scuttle_c"]
const SCUTTLE_DB: float = -20.0
const SCUTTLE_RANGE: float = 10.0
var _step_accum: float = 0.0
var _rng := RandomNumberGenerator.new()

# Unstick guard: authored points are sonar-validated, but props move and players shove.
const STUCK_EPS: float = 0.05
const STUCK_TIME: float = 3.0
var _guard_pos: Vector3
var _guard_t: float = 0.0

func _ready() -> void:
	patrol_speed = PlayerState.tuning.get("crab_patrol_speed", 1.6)
	pursue_speed = PlayerState.tuning.get("crab_pursue_speed", 3.8)
	detect_radius = PlayerState.tuning.get("crab_detect_radius", 6.0)
	contact_radius = PlayerState.tuning.get("crab_contact_radius", 1.2)
	_rng.seed = hash("giant_crab") + spawn_index
	_sidle_sign = 1.0 if (spawn_index % 2) == 0 else -1.0
	up = roost_up
	_build_body()
	add_to_group("hittable")     # craftable melee weapons can drive it off
	add_to_group("giant_crab")
	GameClock.dawn.connect(_on_dawn)
	_last_pos = global_position
	_guard_pos = global_position
	_night_wait = float(spawn_index) * EMERGE_STAGGER
	if not roost_loop.is_empty():
		_wp_index = spawn_index % roost_loop.size()

## ---------- body ----------

func _build_body() -> void:
	# Procedural fallback body first (kept invisible under the generated mesh), then the
	# Meshy giant crab swapped in over it. Naturalistic: glow colour black, energy 0.
	var shell: Material = KIT.mat(Color(0.35, 0.42, 0.48), 0.55)      # mottled blue-grey
	var limb: Material = KIT.mat(Color(0.78, 0.32, 0.16), 0.6)       # orange-red chitin
	var pale: Material = KIT.mat(Color(0.85, 0.8, 0.68), 0.7)        # cream underside
	KIT.ball(self, Vector3(0, 0.5, 0), 0.52, shell, Vector3(1.25, 0.55, 1.0))
	KIT.ball(self, Vector3(0, 0.36, 0), 0.44, pale, Vector3(1.05, 0.3, 0.85))
	for i in range(8):
		var side: float = 1.0 if i < 4 else -1.0
		var along: float = -0.38 + (i % 4) * 0.26
		var hip := Node3D.new()
		add_child(hip)
		hip.position = Vector3(along, 0.42, side * 0.5)
		KIT.limb(hip, Vector3.ZERO, Vector3(0, 0.28, side * 0.42), 0.045, limb)
		var knee := Node3D.new()
		hip.add_child(knee)
		knee.position = Vector3(0, 0.28, side * 0.42)
		KIT.limb(knee, Vector3.ZERO, Vector3(0, -0.68, side * 0.22), 0.035, limb)
		_legs.append({"hip": hip, "knee": knee,
			"phase": (i % 4) * PI * 0.5 + (0.0 if side > 0 else PI * 0.25), "side": side})
	# The generated mesh replaces all of that visually. SCUTTLE walks the legs in a
	# metachronal wave; the glow uniform is pinned dark — this crab does not shine.
	var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 1.1, ANIM.Mode.SCUTTLE,
		0.045, 1.4, NO_GLOW)
	if not gen.is_empty():
		_model = gen["model"]
		_mats = gen["mats"]
		_ground_generated()
	# The claws are built AFTER the replace, so they stay VISIBLE riding the generated
	# shell (ANIM.replace hides everything that existed before it ran — which is why the
	# old crab's pincers were dead code the player never saw). Same trick DeckGull uses
	# for its hand-animated legs. Each claw: arm limb -> wrist ball -> a fixed lower jaw
	# and a MOVING upper jaw on its own pivot (_pincers), opened/closed in _animate().
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		add_child(arm)
		arm.position = Vector3(side * 0.30, 0.30, -0.40)
		arm.rotation.y = side * -0.28
		KIT.limb(arm, Vector3.ZERO, Vector3(side * 0.10, -0.04, -0.30), 0.055, limb)
		var wrist := Node3D.new()
		arm.add_child(wrist)
		wrist.position = Vector3(side * 0.10, -0.04, -0.30)
		KIT.ball(wrist, Vector3(0, 0, -0.09), 0.115 if side > 0 else 0.145, pale,
			Vector3(0.75, 0.6, 1.15))   # asymmetric pincers, like the reference
		KIT.fin(wrist, Vector3(0, -0.045, -0.2), Vector3(0.06, 0.05, 0.2), shell,
			Vector3(90, 0, 0))           # fixed lower jaw
		var jaw := Node3D.new()
		wrist.add_child(jaw)
		jaw.position = Vector3(0, 0.02, -0.1)
		KIT.fin(jaw, Vector3(0, 0.0, -0.1), Vector3(0.055, 0.045, 0.17), shell,
			Vector3(-90, 0, 0))          # moving upper jaw
		_claw_arms.append(arm)
		_pincers.append(jaw)

## Seat the generated mesh's FEET at the node origin. The glb's own origin sits inside
## the body, which was a second, independent source of hover on top of the waypoint bug.
func _ground_generated() -> void:
	var lowest: float = INF
	var stack: Array = [_model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var aabb: AABB = mi.get_aabb()
		for k in range(8):
			var corner: Vector3 = aabb.get_endpoint(k)
			var local: Vector3 = _model.global_transform.affine_inverse() \
				* (mi.global_transform * corner)
			lowest = minf(lowest, local.y)
	if lowest < INF:
		_model.position.y -= lowest * _model.scale.y
	_model_base_y = _model.position.y

## ---------- fightback ----------

## Struck by a melee weapon (player_controller._melee_attack). Each hit staggers it;
## enough damage and it gives up the night and goes back over the rim into the sea.
func repel(from_pos: Vector3, damage: float) -> void:
	if state == State.GONE or state == State.FLEE:
		return
	hp -= damage
	_recoil = 0.4
	_snap_t = maxf(_snap_t, 0.35)   # claws snip back at whatever hit it
	var away: Vector3 = global_position - from_pos
	away.y = 0.0
	if away.length() > 0.05:
		global_position += away.normalized() * 0.55
		_face_toward(from_pos)      # squares up to its attacker, claws forward
	AudioDirector.play_one_shot("clang", global_position, -6.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hp <= 0.0:
		_beaten = true
		_start_flee()
		if hud and hud.has_method("toast"):
			hud.toast("It breaks off and drops over the rim. Gone — for tonight.")
	else:
		_resume_state = State.PATROL
		state = State.PURSUE     # faces you down, but the recoil holds it off this beat
		if hud and hud.has_method("toast"):
			hud.toast("You beat it back. It rears, claws high.")

## A held light shone on it: recoil and bolt for the water (re-approach on a cooldown).
func _light_scare() -> void:
	_lit_t = 0.0
	_scare_cd = _rng.randf_range(20.0, 40.0)
	_recoil = 0.3
	_start_flee()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("It flinches from the light and bolts for the water.")

func _start_flee() -> void:
	state = State.FLEE
	_fleeing_home = false
	_wp_index = maxi(emerge_path.size() - 1, 0)   # walk the emergence path backwards

## ---------- the bite ----------

func _try_bite(player: Node3D) -> void:
	if _bite_cd > 0.0:
		return
	_bite_cd = BITE_COOLDOWN
	_recoil = 0.5   # the lunge spends the crab for a beat — no stun-lock
	_snap_t = 0.6   # the claws slam shut with the hit
	PlayerState.life -= BITE_DAMAGE
	AudioDirector.play_one_shot("crab_snap", global_position, -6.0)
	# Shove: horizontal knockback away from the crab, with a little lift.
	if player is CharacterBody3D:
		var dir: Vector3 = player.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			(player as CharacterBody3D).velocity += dir.normalized() * BITE_SHOVE + Vector3.UP * 2.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("The claw catches you — get clear!")

## ---------- state machine ----------

func _process(delta: float) -> void:
	_animate(delta)
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_scare_cd = maxf(_scare_cd - delta, 0.0)
	if _recoil > 0.0:
		_recoil -= delta
		if state != State.FLEE:
			_seat(delta)
			return
	Journal.discover_if_near(self, "creature_lamplight_crab", 20.0)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	_check_light_scare(delta, player)
	_unstick_guard(delta)
	match state:
		State.GONE:
			return
		State.ROOST:
			_roost(delta)
		State.EMERGE:
			_emerge(delta)
		State.PATROL:
			_patrol(delta, player)
		State.PURSUE:
			_pursue(delta, player)
		State.FLEE:
			_flee(delta)
	_seat(delta)

## Day home: a slow sidle around the underwater cling loop on its leg face. At night,
## after this crab's stagger slot, it heads for its emergence lane — unless beaten or
## freshly scared.
func _roost(delta: float) -> void:
	_follow_loop_free(roost_loop, ROOST_SPEED, delta)
	if GameClock.current_phase == GameClock.Phase.NIGHT and not _beaten and _scare_cd <= 0.0:
		_night_wait -= delta
		if _night_wait <= 0.0:
			state = State.EMERGE
			_wp_index = 0

## The visible climb: water -> rim -> deck, no teleporting. Direct motion along the
## authored, sonar-validated lane; the surface frame grabs the deck at the lip.
func _emerge(delta: float) -> void:
	if GameClock.current_phase != GameClock.Phase.NIGHT:
		_start_flee()
		return
	if _follow_path_free(emerge_path, patrol_speed * 0.9, delta):
		state = State.PATROL
		_wp_index = _nearest_index(patrol_loop)

func _patrol(delta: float, player: Node3D) -> void:
	if GameClock.current_phase != GameClock.Phase.NIGHT:
		_start_flee()    # dawn: visibly go home over the rim
		return
	_follow_loop_deck(patrol_loop, patrol_speed, delta)
	# Detection: darkness only, same level, never into powered light. Crouching halves
	# how far it can sense you.
	if player == null:
		return
	var eff_radius: float = detect_radius
	if player.has_method("detection_factor"):
		eff_radius *= player.detection_factor()
	if global_position.distance_to(player.global_position) < eff_radius \
			and absf(player.global_position.y - global_position.y) < 2.5 \
			and not LightZone.point_is_safe(get_tree(), player.global_position):
		_resume_state = State.PATROL
		state = State.PURSUE

func _pursue(delta: float, player: Node3D) -> void:
	if player == null or GameClock.current_phase != GameClock.Phase.NIGHT:
		_start_flee()
		return
	var p: Vector3 = player.global_position
	# It cannot enter powered light, and it gives up a chase you outrun.
	if LightZone.point_is_safe(get_tree(), p) or global_position.distance_to(p) > GIVE_UP_DIST:
		state = _resume_state
		return
	_step_deck(Vector3(p.x, global_position.y, p.z), pursue_speed, delta, p)
	# Threat snips: the claws clack while it closes, before any contact.
	if _snap_t <= 0.0 and _rng.randf() < delta * 0.7:
		_snap_t = 0.3
	if global_position.distance_to(p) < contact_radius:
		_try_bite(player)

## Retreat to the water (dawn, a scare, or a beating), then sidle home to the roost.
func _flee(delta: float) -> void:
	if not _fleeing_home:
		# Walk the emergence path backwards: deck -> rim -> water.
		if _wp_index < 0 or emerge_path.is_empty():
			_fleeing_home = true
			return
		if _step_free(emerge_path[_wp_index], pursue_speed * 0.8, delta):
			_wp_index -= 1
			if _wp_index < 0:
				_fleeing_home = true
				AudioDirector.play_one_shot("splash", global_position, -8.0)
	else:
		var home: Vector3 = roost_loop[0] if not roost_loop.is_empty() else global_position
		if _step_free(home, ROOST_SPEED * 2.0, delta):
			state = State.ROOST
			_wp_index = 0
			up = roost_up            # back on its leg face: cling frame restored
			_seated = false
			_night_wait = float(spawn_index) * EMERGE_STAGGER

func _on_dawn() -> void:
	_beaten = false
	_night_wait = float(spawn_index) * EMERGE_STAGGER
	if state == State.PATROL or state == State.PURSUE or state == State.EMERGE:
		_start_flee()

## ---------- light scare ----------

func _check_light_scare(delta: float, player: Node3D) -> void:
	if state != State.PATROL and state != State.PURSUE and state != State.EMERGE:
		_lit_t = 0.0
		return
	if player and player.has_method("light_aimed_at") \
			and player.light_aimed_at(global_position + Vector3(0, 0.3, 0)):
		_lit_t += delta
		if _lit_t >= SCARE_TIME:
			_light_scare()
	else:
		_lit_t = 0.0

## ---------- movement: the surface frame ----------

## Deck states use the shared wall-respecting probe step (it cannot clip crates or
## bulkheads); water/climb states move directly along authored, sonar-validated points.
## Either way the SEAT pass afterwards pins the feet to real geometry along `up`.
const BODY_R: float = 0.42
const PROBE_H: float = 0.35
const STALL_GIVE_UP: float = 2.5
var _stalled: float = 0.0

## Square up to a point (attacker, prey): claws toward it, in the seated face's plane.
func _face_toward(target: Vector3) -> void:
	_orient(1.0, target)

## Orientation. With no focus the crab travels SIDEWAYS — body square across the
## heading, alternating which side leads — because that is what a crab is. With a focus
## (the player, an attacker) the body faces it claws-first while still moving.
func _orient(delta: float, focus: Variant = null) -> void:
	var fwd: Vector3
	if focus != null:
		fwd = (focus as Vector3) - global_position
	else:
		fwd = heading.rotated(up, _sidle_sign * PI * 0.5)
	fwd = fwd - up * fwd.dot(up)
	if fwd.length() < 0.01:
		return
	var want := Basis.looking_at(fwd.normalized(), up)
	global_basis = global_basis.orthonormalized().slerp(want, clampf(delta * 6.0, 0.0, 1.0))

## One movement step toward `target`. Seated, motion is confined to the surface's
## tangent plane and arrival is measured IN that plane (authored waypoint heights are
## advisory — the seat owns the real height). Unseated (open water), motion is free 3D.
func _step_move(target: Vector3, speed: float, delta: float, probe: bool,
		focus: Variant = null) -> bool:
	var to_t: Vector3 = target - global_position
	var arrive: Vector3 = to_t
	if _seated:
		arrive = to_t - up * to_t.dot(up)
	if arrive.length() < (0.3 if _seated else 0.25):
		_stalled = 0.0
		return true
	var dir: Vector3 = to_t
	if _seated:
		dir = dir - up * dir.dot(up)
		if dir.length() < 0.05:
			dir = to_t          # target is off this face (leaving a roost): go direct
	dir = dir.normalized()
	heading = dir
	var step: Vector3 = dir * speed * delta
	if probe and up.y > 0.7:
		var moved: Vector3 = MOVE.step(self, step, BODY_R, PROBE_H)
		if moved.length() < step.length() * 0.25:
			_stalled += delta
			if _stalled > STALL_GIVE_UP:
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

## The reseat — run after every state tick. Cast along -up for footing; ease `up` onto
## the found normal (rides sloped plate and curved faces); wrap over a convex edge the
## way the snail crawler does (deck rim -> rim face) by trying the old heading as the
## new up; with no footing at all, it is swimming — ease upright and let the authored
## points carry it.
func _seat(delta: float) -> void:
	if _skip.is_empty():
		_skip = MOVE.kin_bodies(self)
	var lift: float = 0.55
	var drop: float = 0.95
	if not _seated:
		lift = 0.9
		drop = 1.6
	var hit: Dictionary = MOVE.surface_hit(self, global_position, up, lift, drop, _skip)
	if hit.is_empty() and _seated:
		var wrap_up: Vector3 = heading
		if wrap_up.length() > 0.5:
			var h2: Dictionary = MOVE.surface_hit(self, global_position, wrap_up,
				0.7, 1.2, _skip)
			if not h2.is_empty():
				var old_up: Vector3 = up
				up = wrap_up.normalized()
				heading = -old_up
				hit = h2
	if hit.is_empty():
		_seated = false
		up = up.lerp(Vector3.UP, clampf(delta * 2.5, 0.0, 1.0)).normalized()
		return
	var n: Vector3 = hit["normal"]
	if n.dot(up) > 0.2:
		up = up.lerp(n, clampf(delta * 7.0, 0.0, 1.0)).normalized()
	var target: Vector3 = (hit["point"] as Vector3) + up * CLEAR
	var to_t: Vector3 = target - global_position
	if not _seated or to_t.length() > 1.3:
		global_position = target
	else:
		global_position += to_t.limit_length(3.0 * delta)
	_seated = true

func _follow_loop_free(loop: Array, speed: float, delta: float) -> void:
	if loop.is_empty():
		return
	if _step_free(loop[_wp_index % loop.size()], speed, delta):
		_wp_index = (_wp_index + 1) % loop.size()
		if _rng.randf() < 0.35:
			_sidle_sign = -_sidle_sign   # crabs swap their leading side
func _follow_loop_deck(loop: Array, speed: float, delta: float) -> void:
	if loop.is_empty():
		return
	if _step_deck(loop[_wp_index % loop.size()] + patrol_offset, speed, delta):
		_wp_index = (_wp_index + 1) % loop.size()
		if _rng.randf() < 0.35:
			_sidle_sign = -_sidle_sign

func _follow_path_free(path: Array, speed: float, delta: float) -> bool:
	if _wp_index >= path.size():
		return true
	if _step_free(path[_wp_index], speed, delta):
		_wp_index += 1
	return _wp_index >= path.size()

func _nearest_index(points: Array) -> int:
	var best: int = 0
	var best_d: float = INF
	for i in range(points.size()):
		var d: float = global_position.distance_to(points[i])
		if d < best_d:
			best_d = d
			best = i
	return best

## Runtime unstick: authored points are validated, but if the crab is pinned mid-hunt
## or mid-climb (shoved into a prop, geometry edit), relocate it to the nearest valid
## authored waypoint rather than let it grind forever.
func _unstick_guard(delta: float) -> void:
	if state != State.PURSUE and state != State.EMERGE and state != State.PATROL:
		_guard_pos = global_position
		_guard_t = 0.0
		return
	if global_position.distance_to(_guard_pos) < STUCK_EPS:
		_guard_t += delta
		if _guard_t >= STUCK_TIME:
			var pool: Array = emerge_path if state == State.EMERGE else patrol_loop
			if not pool.is_empty():
				global_position = pool[_nearest_index(pool)]
				_seated = false
				up = Vector3.UP
			_guard_t = 0.0
			_guard_pos = global_position
	else:
		_guard_pos = global_position
		_guard_t = 0.0

## ---------- animation ----------

## Gait is driven by REAL ground speed (no moonwalking): still = BREATHE, a slow
## resting swell; moving = SCUTTLE at a rate locked to how fast it actually travels.
## The claw overlay runs on top in every case: an idle open/close breathing, arms
## reared while pursuing, and _snap_t slamming the jaws shut on a bite or threat snip.
func _animate(delta: float) -> void:
	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position
	_speed = moved / maxf(delta, 0.0001)
	_gait_t += delta * clampf(_speed * 3.2, 0.6, 9.0)
	_bob_t += delta
	if _model:
		if _speed > 0.1:
			_model.position.y = _model_base_y \
				+ sin(_bob_t * 9.0) * 0.018 * clampf(_speed, 0.2, 1.5)
			_model.rotation.z = sin(_bob_t * 4.5) * 0.035
		else:
			_model.position.y = lerpf(_model.position.y, _model_base_y, delta * 3.0)
			_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 2.0)
		var resting: bool = _speed < 0.15
		if resting != _resting_pose:
			_resting_pose = resting
			for m in _mats:
				(m as ShaderMaterial).set_shader_parameter("mode",
					ANIM.Mode.BREATHE if resting else ANIM.Mode.SCUTTLE)
		if resting:
			ANIM.drive(_mats, 0.45, 0.0, 0.02)
		else:
			ANIM.drive(_mats, clampf(_speed * 1.15, 0.6, 4.2), 0.0,
				lerpf(0.03, 0.055, clampf(_speed * 0.5, 0.0, 1.0)))
	else:
		# Primitive fallback: procedural gait.
		for leg in _legs:
			var swing: float = sin(_gait_t + leg["phase"])
			var lift: float = maxf(sin(_gait_t + leg["phase"] + PI * 0.5), 0.0)
			(leg["hip"] as Node3D).rotation.x = swing * 0.22 * clampf(_speed, 0.15, 1.0)
			(leg["knee"] as Node3D).rotation.z = leg["side"] * lift * 0.3 * clampf(_speed, 0.15, 1.0)
	# Claws — always live, both bodies.
	_snap_t = maxf(_snap_t - delta, 0.0)
	var menace: float = 1.0 if state == State.PURSUE else 0.0
	for i in range(_claw_arms.size()):
		var arm := _claw_arms[i] as Node3D
		arm.rotation.x = lerpf(arm.rotation.x,
			-0.55 * menace + sin(_bob_t * 1.3 + float(i) * 2.1) * 0.07, delta * 5.0)
	for i in range(_pincers.size()):
		var jaw := _pincers[i] as Node3D
		var gape: float = 0.18 + 0.10 * sin(_bob_t * (0.8 + 0.2 * float(i)) + float(i) * 2.6) \
			+ 0.35 * menace
		if _snap_t > 0.0:
			gape = 0.55 * absf(sin(_snap_t * 24.0))   # fast snips slamming shut
		jaw.rotation.x = lerpf(jaw.rotation.x, -gape,
			clampf(delta * (14.0 if _snap_t > 0.0 else 6.0), 0.0, 1.0))

## ---------- audio: the jingle is dead ----------

## Soft chitin taps on the footfall cadence, and ONLY when every gate holds:
## moving, within 10 m, inside the camera frustum, and unoccluded. Any gate false ->
## complete silence. One-shots, never a loop; nothing plays on a timer.
func _physics_process(delta: float) -> void:
	if _speed > 0.3 and _audio_gate_open():
		_step_accum += delta * clampf(_speed * 1.8, 0.9, 6.0)
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
	var ear: Vector3 = global_position + Vector3(0, 0.35, 0)
	if not cam.is_position_in_frustum(ear):
		return false
	# Occlusion: a clear line from the camera to the crab, or it stays silent.
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, ear)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
