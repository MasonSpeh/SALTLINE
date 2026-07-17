class_name LamplightCrab extends Node3D
## The night threat (GDD 5.5): one dog-sized crab, simple FSM on authored waypoints.
## Avoids powered LightZones; pursues the player in darkness within detect radius;
## contact = blackout + wake at dawn in the SPHL (handled by Main via EventBus).
## Its audio is the real design — claw-steps audible through decks, long before sight.

enum State { PATROL_Z1, ASCEND, PATROL_TOP, PURSUE, RETREAT, GONE }

var z1_loop: Array = []
var ascend_path: Array = []
var z4_loop: Array = []
var exit_point: Vector3

var state: State = State.PATROL_Z1
var _wp_index: int = 0
var _resume_state: State = State.PATROL_Z1
var patrol_speed: float = 1.6
var pursue_speed: float = 3.8
var detect_radius: float = 6.0
var contact_radius: float = 1.2
var hp: float = 3.0             ## melee hits it can take before it quits the night
var _recoil: float = 0.0        ## stagger timer after a weapon strike
var _contact_fired: bool = false
var _claw_timer: Timer

# Anatomy handles for the gait/menace animation.
const KIT := preload("res://scripts/world/creature_kit.gd")
var _legs: Array = []            ## [{hip: Node3D, knee: Node3D, phase: float, side: float}]
var _claw_arms: Array = []       ## [Node3D] — rise when hunting
var _pincers: Array = []         ## [Node3D] — idle open/close
var _stalks: Array = []          ## eye stalks, tilt toward prey
var _lamp_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _gait_t: float = 0.0
var _last_pos: Vector3

func _ready() -> void:
	patrol_speed = PlayerState.tuning.get("crab_patrol_speed", 1.6)
	pursue_speed = PlayerState.tuning.get("crab_pursue_speed", 3.8)
	detect_radius = PlayerState.tuning.get("crab_detect_radius", 6.0)
	contact_radius = PlayerState.tuning.get("crab_contact_radius", 1.2)
	_build_body()
	_claw_timer = AudioDirector.attach_loop("claw", self, 0.5)
	GameClock.dawn.connect(_on_dawn)
	_last_pos = global_position
	add_to_group("hittable")   # craftable melee weapons can drive it off

## Struck by a weapon (player_controller._melee_attack). Each hit staggers it and
## breaks off a pursuit; enough damage and it gives up the night and slides off
## the deck. Its lamp flares hurt-red on the blow.
func repel(from_pos: Vector3, damage: float) -> void:
	if state == State.GONE or state == State.RETREAT:
		return
	hp -= damage
	_recoil = 0.4
	# Knock it back a step, away from the strike.
	var away: Vector3 = global_position - from_pos
	away.y = 0.0
	if away.length() > 0.05:
		global_position += away.normalized() * 0.55
		look_at(global_position - away, Vector3.UP)   # face the threat as it backs off
	if _lamp_mat:
		_lamp_mat.emission = Color(1.0, 0.15, 0.1)
		_lamp_mat.emission_energy_multiplier = 4.0
	AudioDirector.play_one_shot("clang", global_position, -6.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hp <= 0.0:
		state = State.RETREAT
		_wp_index = 0
		if hud and hud.has_method("toast"):
			hud.toast("It breaks and drops off the deck. Gone — for tonight.")
	else:
		# Staggered: drop the hunt and think twice before closing again.
		_resume_state = State.PATROL_TOP
		state = State.PURSUE   # keeps facing you, but the recoil holds it off this beat
		if hud and hud.has_method("toast"):
			hud.toast("You beat it back. It recoils, lamp flaring red.")

## Dog-sized shore crab, Bloom-grown: broad chitin carapace, eight articulated
## legs, heavy pincers, stalked eyes — and the lamp, a lure organ on its back
## whose pulse quickens when it hunts. Beautiful in daylight documentary
## footage; terrifying at 2 AM on a dark catwalk (Rule 7, to the letter).
func _build_body() -> void:
	var chitin: Material = KIT.mat(Color(0.24, 0.19, 0.15), 0.5)
	var chitin_dark: Material = KIT.mat(Color(0.16, 0.13, 0.11), 0.55)
	var underside: Material = KIT.mat(Color(0.42, 0.36, 0.28), 0.7)
	# Carapace: a broad flattened dome with a rear flare and a pale belly plate.
	KIT.ball(self, Vector3(0, 0.5, 0), 0.52, chitin, Vector3(1.25, 0.55, 1.0))
	KIT.ball(self, Vector3(0, 0.42, 0.3), 0.4, chitin, Vector3(1.05, 0.45, 0.8))
	KIT.ball(self, Vector3(0, 0.36, 0), 0.44, underside, Vector3(1.05, 0.3, 0.85))
	# Carapace rim spots — the Bloom's fingerprints, dim until the lamp wakes.
	for i in range(6):
		var a: float = -PI * 0.75 + i * (PI * 1.5 / 5.0)
		KIT.glow_spot(self, Vector3(cos(a) * 0.55, 0.62, sin(a) * 0.42), 0.035, Color(0.2, 0.9, 0.85), 0.6)
	# Eight legs: hip pivot -> upper segment -> knee pivot -> lower segment.
	for i in range(8):
		var side: float = 1.0 if i < 4 else -1.0
		var along: float = -0.38 + (i % 4) * 0.26
		var hip := Node3D.new()
		add_child(hip)
		hip.position = Vector3(along, 0.42, side * 0.5)
		KIT.limb(hip, Vector3.ZERO, Vector3(0, 0.28, side * 0.42), 0.045, chitin_dark)
		var knee := Node3D.new()
		hip.add_child(knee)
		knee.position = Vector3(0, 0.28, side * 0.42)
		KIT.limb(knee, Vector3.ZERO, Vector3(0, -0.68, side * 0.22), 0.035, chitin_dark)
		_legs.append({"hip": hip, "knee": knee, "phase": (i % 4) * PI * 0.5 + (0.0 if side > 0 else PI * 0.25), "side": side})
	# Claw arms: shoulder pivots forward, each ending in a two-part pincer.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		add_child(arm)
		arm.position = Vector3(side * 0.34, 0.42, -0.42)
		KIT.limb(arm, Vector3.ZERO, Vector3(side * 0.12, 0.0, -0.34), 0.06, chitin)
		var hand := Node3D.new()
		arm.add_child(hand)
		hand.position = Vector3(side * 0.12, 0.0, -0.34)
		KIT.ball(hand, Vector3(0, 0, -0.1), 0.13, chitin, Vector3(0.8, 0.7, 1.2))
		var upper := KIT.fin(hand, Vector3(0, 0.05, -0.22), Vector3(0.07, 0.05, 0.22), chitin_dark, Vector3(-90, 0, 0))
		var lower := KIT.fin(hand, Vector3(0, -0.05, -0.22), Vector3(0.07, 0.05, 0.18), chitin_dark, Vector3(90, 0, 0))
		_claw_arms.append(arm)
		_pincers.append(upper)
		_pincers.append(lower)
	# Stalked eyes, faint teal — they find you before you find them.
	for side in [-1.0, 1.0]:
		var stalk := Node3D.new()
		add_child(stalk)
		stalk.position = Vector3(side * 0.16, 0.6, -0.4)
		KIT.limb(stalk, Vector3.ZERO, Vector3(0, 0.16, -0.06), 0.02, chitin_dark)
		KIT.glow_spot(stalk, Vector3(0, 0.18, -0.08), 0.045, Color(0.3, 0.95, 0.9), 1.6)
		_stalks.append(stalk)
	# THE LAMP: the lure organ, held over the carapace on a curved stalk.
	var lamp_stalk := Node3D.new()
	add_child(lamp_stalk)
	lamp_stalk.position = Vector3(0, 0.66, 0.05)
	KIT.limb(lamp_stalk, Vector3.ZERO, Vector3(0, 0.3, -0.14), 0.025, chitin_dark)
	_lamp_mat = KIT.glow_spot(lamp_stalk, Vector3(0, 0.34, -0.17), 0.09, Color(0.25, 0.95, 0.88), 1.2)
	_lamp_light = OmniLight3D.new()
	_lamp_light.light_color = Color(0.3, 0.95, 0.88)
	_lamp_light.omni_range = 3.5
	_lamp_light.light_energy = 0.5
	_lamp_light.shadow_enabled = false
	lamp_stalk.add_child(_lamp_light)
	_lamp_light.position = Vector3(0, 0.36, -0.17)

## Gait + menace: legs step at a rate tied to real movement, claws lift and
## pincers work when hunting, and the lamp's pulse quickens from a resting
## heartbeat to a strobe as it closes — the dread telegraph you learn to read.
func _animate(delta: float) -> void:
	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position
	var speed: float = moved / maxf(delta, 0.0001)
	_gait_t += delta * clampf(speed * 3.2, 0.6, 9.0)
	for leg in _legs:
		var swing: float = sin(_gait_t + leg["phase"])
		var lift: float = maxf(sin(_gait_t + leg["phase"] + PI * 0.5), 0.0)
		(leg["hip"] as Node3D).rotation.x = swing * 0.22 * clampf(speed, 0.15, 1.0)
		(leg["knee"] as Node3D).rotation.z = leg["side"] * lift * 0.3 * clampf(speed, 0.15, 1.0)
	var hunting: bool = state == State.PURSUE
	var menace: float = 1.0 if hunting else 0.0
	for arm in _claw_arms:
		(arm as Node3D).rotation.x = lerpf((arm as Node3D).rotation.x, -0.7 * menace + sin(_gait_t * 0.7) * 0.06, delta * 4.0)
	for i in range(_pincers.size()):
		var open: float = (0.35 if hunting else 0.1) * absf(sin(_gait_t * (2.2 if hunting else 0.7) + i))
		(_pincers[i] as Node3D).rotation.x += ((-open if i % 2 == 0 else open) - (_pincers[i] as Node3D).rotation.x) * delta * 6.0
	# The lamp: resting heartbeat on patrol, quickening strobe on the hunt.
	var pulse_rate: float = 6.5 if hunting else 1.4
	var pulse: float = 0.5 + 0.5 * sin(_gait_t * pulse_rate)
	var energy: float = lerpf(0.9, 3.2, menace * 0.7 + pulse * 0.3) * (0.6 + 0.4 * pulse)
	_lamp_mat.emission_energy_multiplier = energy
	_lamp_light.light_energy = 0.35 + energy * 0.25
	# Eye stalks track the prey while hunting.
	var player: Node3D = get_tree().get_first_node_in_group("player")
	for stalk in _stalks:
		var target_tilt: float = 0.0
		if hunting and player:
			target_tilt = clampf((player.global_position.y - global_position.y) * 0.15, -0.3, 0.3)
		(stalk as Node3D).rotation.x = lerpf((stalk as Node3D).rotation.x, target_tilt, delta * 3.0)

func _process(delta: float) -> void:
	_animate(delta)
	# Staggered by a weapon strike: hold this beat, then shake it off.
	if _recoil > 0.0:
		_recoil -= delta
		if _recoil <= 0.0 and _lamp_mat and state != State.GONE:
			_lamp_mat.emission = Color(0.25, 0.95, 0.88)   # lamp back to its cold lure teal
		if state != State.RETREAT and state != State.GONE:
			return
	Journal.discover_if_near(self, "creature_lamplight_crab", 20.0)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	match state:
		State.GONE:
			return
		State.RETREAT:
			_retreat(delta)
			return
		State.PURSUE:
			_pursue(delta, player)
			return
		_:
			pass
	# Detection: darkness only, same layer-ish height, never into powered light.
	if player and GameClock.current_phase == GameClock.Phase.NIGHT:
		var d: float = global_position.distance_to(player.global_position)
		# Crouching halves how far the crab can sense the player (stealth).
		var eff_radius: float = detect_radius
		if player.has_method("detection_factor"):
			eff_radius *= player.detection_factor()
		if d < eff_radius \
				and absf(player.global_position.y - global_position.y) < 2.5 \
				and not LightZone.point_is_safe(get_tree(), player.global_position):
			_resume_state = state
			state = State.PURSUE
			return
	# Patrol schedule ascends over the night (GDD 5.5).
	var f: float = GameClock.phase_fraction()
	match state:
		State.PATROL_Z1:
			_follow_loop(z1_loop, delta)
			if f > 0.35:
				state = State.ASCEND
				_wp_index = 0
		State.ASCEND:
			if _follow_path(ascend_path, delta):
				# Topside reached: patrol it only if it is dark territory (Rule 7).
				if LightZone.point_is_safe(get_tree(), z4_loop[0]):
					state = State.ASCEND    # loiter on the stairs — light holds the deck
					_wp_index = maxi(ascend_path.size() - 4, 0)
				else:
					state = State.PATROL_TOP
					_wp_index = 0
		State.PATROL_TOP:
			_follow_loop(z4_loop, delta)

func _follow_loop(loop: Array, delta: float) -> void:
	if loop.is_empty():
		return
	var target: Vector3 = loop[_wp_index % loop.size()]
	if _step_toward(target, patrol_speed, delta):
		_wp_index = (_wp_index + 1) % loop.size()

func _follow_path(path: Array, delta: float) -> bool:
	if _wp_index >= path.size():
		return true
	if _step_toward(path[_wp_index], patrol_speed, delta):
		_wp_index += 1
	return _wp_index >= path.size()

func _step_toward(target: Vector3, speed: float, delta: float) -> bool:
	var to_target: Vector3 = target - global_position
	if to_target.length() < 0.25:
		return true
	var step: Vector3 = to_target.normalized() * speed * delta
	global_position += step
	if to_target.length_squared() > 0.04:
		look_at(Vector3(target.x, global_position.y, target.z), Vector3.UP)
	return false

func _pursue(delta: float, player: Node3D) -> void:
	if player == null or GameClock.current_phase != GameClock.Phase.NIGHT:
		state = _resume_state
		return
	var p: Vector3 = player.global_position
	# It cannot enter powered light. It never attacks in light. (Canon.)
	if LightZone.point_is_safe(get_tree(), p) or global_position.distance_to(p) > detect_radius * 2.0:
		state = _resume_state
		return
	var target := Vector3(p.x, global_position.y, p.z)
	_step_toward(target, pursue_speed, delta)
	if global_position.distance_to(p) < contact_radius and not _contact_fired:
		_contact_fired = true
		EventBus.creature_contact.emit()
		state = State.RETREAT
		_wp_index = 0

func _on_dawn() -> void:
	if state != State.GONE:
		state = State.RETREAT
		_wp_index = 0

func _retreat(delta: float) -> void:
	# Visible exit: it slides off the Wet Deck edge into the sea (GDD 5.8).
	if _wp_index == 0:
		if _step_toward(exit_point, pursue_speed * 0.8, delta):
			_wp_index = 1
	else:
		global_position.y -= delta * 1.2
		global_position += (global_transform.basis * Vector3(0, 0, -1)) * delta * 0.6
		if global_position.y < -1.5:
			state = State.GONE
			if _claw_timer:
				_claw_timer.stop()
			AudioDirector.play_one_shot("splash", global_position)
			queue_free()
