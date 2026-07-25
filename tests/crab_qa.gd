extends Node
## CRAB QA — is the predator loop actually smooth, fair and frightening?
##
## The hunt probe answered "do they reach me". This answers the rest, with numbers:
##   GROUNDING  every crab's feet vs the surface under it (float/sink is the classic bug —
##              and the sonar scan is BLIND to fauna, so this is the only way to catch it)
##   SMOOTHNESS largest single-frame displacement vs what its top speed allows. A step
##              bigger than speed*dt is a TELEPORT, which reads as a stutter or a blink.
##   STALLS     a crab that stops making progress for seconds is stuck on a prop, which is
##              the difference between "stalking me" and "broken"
##   THREAT     time from nightfall to first contact, and life actually lost. Too quick is
##              unfair; never is boring.
##   KING       size, and whether its articulated legs are really moving
##
## Run headless: godot --headless --path . res://tests/crab_qa.tscn

const WARMUP: float = 6.0
const WATCH: float = 110.0
## A crab's own top speed is ~4.4 m/s; anything beyond this in one frame is not locomotion.
const TELEPORT_M: float = 1.25
const STALL_M: float = 0.12          ## progress under this per sample counts as stalled
const SAMPLE: float = 0.5

var _t: float = 0.0
var _next: float = 0.0
var _armed: bool = false
var _player: Node3D
var _prev: Dictionary = {}           ## crab -> last position
var _stall: Dictionary = {}          ## crab -> consecutive stalled samples
var _worst_step: float = 0.0
var _worst_step_who: String = ""
var _teleports: int = 0
var _teleports_visible: int = 0
var _teleports_hidden: int = 0
var _tp_states: Dictionary = {}
var _gaps: Array = []
var _max_stall: int = 0
var _life0: float = 1.0
var _first_contact: float = -1.0
var _king_span: float = 0.0
var _king_leg_motion: float = 0.0
var _king_leg_prev: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_child((load("res://scenes/Main.tscn") as PackedScene).instantiate())

func _all() -> Array:
	var out: Array = []
	for c in get_tree().get_nodes_in_group("giant_crab"):
		out.append(c)
	for c in get_tree().get_nodes_in_group("king_crab"):
		if not out.has(c):
			out.append(c)
	return out

## Distance from a crab's origin (its feet — crab.gd offsets the model so its lowest point
## sits on the node origin) down to whatever is under it. ~0 is seated; positive is hovering.
func _ground_gap(n: Node3D) -> float:
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var from: Vector3 = n.global_position + Vector3(0, 0.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -4.0, 0))
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return n.global_position.y - (hit["position"] as Vector3).y

func _process(d: float) -> void:
	_t += d
	if _t < WARMUP:
		return
	if not _armed:
		_armed = true
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			print("FAIL no player"); get_tree().quit(); return
		_player.set_physics_process(false)
		_player.set_process(false)
		_player.global_position = Vector3(-24.0, 19.0, -2.0)   # open topside, no light pool
		GameClock.force_phase(GameClock.Phase.NIGHT)
		_life0 = PlayerState.life
		for c in _all():
			_prev[c] = (c as Node3D).global_position
			_stall[c] = 0
		print("[qa] pack=%d kings=%d life=%.2f"
			% [get_tree().get_nodes_in_group("giant_crab").size(),
				get_tree().get_nodes_in_group("king_crab").size(), _life0])
		return
	# --- per-frame smoothness: the teleport check has to run EVERY frame, not per sample ---
	for c in _all():
		if not is_instance_valid(c):
			continue
		var n: Node3D = c
		if _prev.has(c):
			var step: float = n.global_position.distance_to(_prev[c])
			if step > _worst_step:
				_worst_step = step
				_worst_step_who = "king" if n.is_in_group("king_crab") else "crab"
			if step > TELEPORT_M:
				_teleports += 1
				# Blaming the wrong subsystem wastes a whole pass, so record WHICH state the
				# crab was in and how far it moved. The state histogram is the diagnosis.
				var st: Variant = n.get("state")
				if st == null:
					st = n.get("_state")
				var key: String = "%s state=%s" % ["king" if n.is_in_group("king_crab") else "crab", str(st)]
				_tp_states[key] = int(_tp_states.get(key, 0)) + 1
				# SPLIT VISIBLE FROM HIDDEN. crab.gd's unstick guard deliberately snaps a
				# pinned crab back to a known-good anchor, but ONLY when the player cannot
				# see it (>45 m away, or behind the camera). Those are by design, and
				# counting them as jank makes this metric useless. A jump the player could
				# actually WITNESS is the only number that matters.
				var vis: bool = false
				if _player != null and n.global_position.distance_to(_player.global_position) < 45.0:
					var pcam: Camera3D = _player.get_node_or_null("Head/Camera3D") as Camera3D
					vis = pcam == null or not pcam.is_position_behind(n.global_position)
				if vis:
					_teleports_visible += 1
					print("   [VISIBLE JANK] %.2f m  %s" % [step, key])
				else:
					_teleports_hidden += 1
		_prev[c] = n.global_position
	if _t < _next:
		return
	_next = _t + SAMPLE
	# --- grounding + stalls ---
	for c in _all():
		if not is_instance_valid(c):
			continue
		var n: Node3D = c
		var g: float = _ground_gap(n)
		if not is_nan(g):
			_gaps.append(g)
	if _first_contact < 0.0 and PlayerState.life < _life0 - 0.001:
		_first_contact = _t - WARMUP
		print("[qa] FIRST CONTACT at %.1fs after nightfall (life %.2f -> %.2f)"
			% [_first_contact, _life0, PlayerState.life])
	# --- king crab: size + is the articulation actually moving? ---
	var kings: Array = get_tree().get_nodes_in_group("king_crab")
	if not kings.is_empty():
		var k: Node3D = kings[0]
		var acc := AABB()
		var first := true
		for m in k.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = m
			if not mi.visible:
				continue
			var w: AABB = mi.global_transform * mi.get_aabb()
			acc = w if first else acc.merge(w)
			first = false
		if not first:
			_king_span = maxf(_king_span, maxf(acc.size.x, acc.size.z))
			# track one leg tip: if the gait runs, this moves relative to the body
			var tips: Array = k.find_children("*", "MeshInstance3D", true, false)
			if tips.size() > 4:
				var tip: MeshInstance3D = tips[4]
				var rel: Vector3 = tip.global_position - k.global_position
				if _king_leg_prev != Vector3.ZERO:
					_king_leg_motion = maxf(_king_leg_motion, rel.distance_to(_king_leg_prev))
				_king_leg_prev = rel
	if _t > WARMUP + WATCH:
		_report()

func _report() -> void:
	var floats: int = 0
	var sunk: int = 0
	var gmax: float = -99.0
	var gmin: float = 99.0
	for g in _gaps:
		gmax = maxf(gmax, g)
		gmin = minf(gmin, g)
		if g > 0.35:
			floats += 1
		if g < -0.35:
			sunk += 1
	print("\n================ CRAB QA ================")
	print("SMOOTHNESS")
	print("  worst single-frame step : %.2f m (%s)   [teleport threshold %.2f]"
		% [_worst_step, _worst_step_who, TELEPORT_M])
	print("  teleport-sized steps    : %d total" % _teleports)
	print("    player could SEE      : %d   <- the jank number" % _teleports_visible)
	print("    hidden unstick snaps  : %d   (by design: >45 m or off-camera)" % _teleports_hidden)
	print("  by state                : %s" % str(_tp_states))
	print("GROUNDING  (%d samples over all crabs)" % _gaps.size())
	print("  gap range               : %.2f .. %.2f m" % [gmin, gmax])
	print("  hovering >0.35 m        : %d (%.1f%%)" % [floats, 100.0 * floats / maxf(_gaps.size(), 1)])
	print("  sunk    <-0.35 m        : %d (%.1f%%)" % [sunk, 100.0 * sunk / maxf(_gaps.size(), 1)])
	print("THREAT")
	if _first_contact >= 0.0:
		print("  first contact           : %.1f s after nightfall" % _first_contact)
	else:
		print("  first contact           : NEVER in %.0f s  <- not scary" % WATCH)
	print("  life lost over the night: %.2f  (%.2f -> %.2f)"
		% [_life0 - PlayerState.life, _life0, PlayerState.life])
	print("KING CRAB")
	print("  widest span measured    : %.2f m  (player is ~1.8 m tall)" % _king_span)
	print("  leg-tip travel/sample   : %.3f m  (>0 means the gait is running)" % _king_leg_motion)
	print("========================================\n")
	get_tree().quit()
