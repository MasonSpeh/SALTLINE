class_name FishingRod extends Node3D
## Rod fishing: select the rod in the hotbar, LMB casts a float onto open water.
## Wait through the drift (nibbles lie), STRIKE on the plunge, then fight the fish
## on the line — hold LMB to reel while the tension bar allows, ease off when it
## screams. Species run by time of day; the deep night holds the strange ones.
## The rod object lives only while a cast is out; the player owns one per session.

enum State { CASTING, DRIFT, BITE, FIGHT, DONE }

const CAST_SPEED: float = 13.0
const CAST_LIFT: float = 4.0
const GRAVITY: float = 9.8
const MAX_RANGE: float = 45.0
const BITE_WINDOW: float = 1.3
const CANCEL_DISTANCE: float = 6.0     # walk away and the line comes in
const REEL_RATE: float = 0.14         # progress/sec while reeling
const TENSION_DECAY: float = 0.8

## Species: phase-weighted table. `fight` scales how long it takes to land,
## `pull` how hard it fights (tension pressure and line taken while resting).
const SPECIES := [
	{"id": "fish_herring", "name": "Lantern Herring", "fight": 0.8, "pull": 0.65,
		"w": {"day": 30, "dawn": 28, "dusk": 26, "night": 24}},
	{"id": "fish_slate_cod", "name": "Slate Cod", "fight": 1.25, "pull": 0.9,
		"w": {"day": 26, "dawn": 10, "dusk": 10, "night": 5}},
	{"id": "fish_mirrorjack", "name": "Mirrorjack", "fight": 1.0, "pull": 1.35,
		"w": {"day": 5, "dawn": 24, "dusk": 22, "night": 3}},
	{"id": "fish_chimefish", "name": "Chimefish", "fight": 0.9, "pull": 0.8,
		"w": {"day": 10, "dawn": 8, "dusk": 8, "night": 7}},
	{"id": "fish_sable_hake", "name": "Sable Hake", "fight": 1.1, "pull": 1.0,
		"w": {"day": 2, "dawn": 5, "dusk": 13, "night": 28}},
	{"id": "fish_barrel_grouper", "name": "Barrel Grouper", "fight": 2.3, "pull": 1.7,
		"w": {"day": 3, "dawn": 4, "dusk": 4, "night": 5}},
	{"id": "fish_ribbon_eel", "name": "Ribbon Eel", "fight": 1.5, "pull": 1.4,
		"w": {"day": 0, "dawn": 2, "dusk": 5, "night": 11}},
	{"id": "the_looker", "name": "The Looker", "fight": 1.3, "pull": 1.1,
		"w": {"day": 1, "dawn": 1, "dusk": 1, "night": 2}},
]

var _player: Node3D
var _state: State = State.CASTING
var _velocity: Vector3
var _bite_timer: float = 0.0
var _bite_window: float = 0.0
var _nibbles: int = 0
var _fish: Dictionary = {}
var _tension: float = 0.3
var _progress: float = 0.35
var _fight_t: float = 0.0
var _reeling: bool = false
var _bob: Node3D
var _dip: float = 0.0                 # visual bobber dip (nibbles and bites)
var _line: MeshInstance3D
var _line_mesh: CylinderMesh
var _cast_origin: Vector3
var _rng := RandomNumberGenerator.new()

func setup(player: Node3D, camera: Camera3D) -> void:
	_player = player
	_cast_origin = player.global_position
	_rng.randomize()
	global_position = camera.global_position - camera.global_transform.basis.z * 0.5
	_velocity = -camera.global_transform.basis.z * CAST_SPEED + Vector3(0, CAST_LIFT, 0)

func _ready() -> void:
	# The float: red cap over white body — the classic, visible at range.
	_bob = Node3D.new()
	add_child(_bob)
	var top := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.09
	tm.height = 0.18
	tm.material = MatLib.flat(Color(0.85, 0.15, 0.1))
	top.mesh = tm
	top.position.y = 0.08
	_bob.add_child(top)
	var bot := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.08
	bm.height = 0.16
	bm.material = MatLib.flat(Color(0.9, 0.9, 0.86))
	bot.mesh = bm
	bot.position.y = -0.05
	_bob.add_child(bot)
	# Line: one thin cylinder from the rod hand to the float, restretched per frame.
	_line_mesh = CylinderMesh.new()
	_line_mesh.top_radius = 0.006
	_line_mesh.bottom_radius = 0.006
	_line_mesh.height = 1.0
	_line_mesh.material = MatLib.flat(Color(0.85, 0.88, 0.9))
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	_line.top_level = true
	add_child(_line)
	_schedule_bite()

func _hand_pos() -> Vector3:
	return _player.global_position + Vector3(0, 1.25, 0)

func _phase_key() -> String:
	match GameClock.current_phase:
		GameClock.Phase.DAWN: return "dawn"
		GameClock.Phase.DUSK: return "dusk"
		GameClock.Phase.NIGHT: return "night"
		_: return "day"

func _schedule_bite() -> void:
	# Dawn/dusk feed faster; a couple of teaser nibbles arrive first.
	var mean: float = 9.0 if _phase_key() in ["dawn", "dusk"] else 14.0
	_bite_timer = _rng.randf_range(mean * 0.45, mean * 1.5)
	_nibbles = _rng.randi_range(0, 2)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		queue_free()
		return
	if _player.ui_locked or (_player.get("build") and _player.build.active):
		_finish("")
		return
	var t: float = Gyre.water_time()
	match _state:
		State.CASTING:
			var prev: Vector3 = global_position
			_velocity.y -= GRAVITY * delta
			global_position += _velocity * delta
			# Hitting deck/structure mid-flight is a fouled cast — clatter and done.
			var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(prev, global_position)
			q.exclude = [_player.get_rid()]
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				AudioDirector.play_one_shot("clang", global_position, -20.0)
				_finish("No open water there.")
				return
			var water_y: float = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85
			if global_position.y <= water_y + 0.02:
				global_position.y = water_y + 0.02
				AudioDirector.play_one_shot("splash", global_position, -14.0)
				_state = State.DRIFT
				_prompt("Line's out — watch the float.")
			elif global_position.distance_to(_hand_pos()) > MAX_RANGE:
				_finish("")
				return
		State.DRIFT:
			_ride_water(t, delta)
			_bite_timer -= delta
			if _bite_timer <= 0.0:
				if _nibbles > 0:
					_nibbles -= 1
					_dip = 0.16   # a lying little tug
					AudioDirector.play_one_shot("splash", global_position, -26.0)
					_bite_timer = _rng.randf_range(1.8, 5.0)
				else:
					_state = State.BITE
					_bite_window = BITE_WINDOW
					_dip = 0.45
					AudioDirector.play_one_shot("splash", global_position, -8.0)
					_prompt("!!!  [LMB] STRIKE")
		State.BITE:
			_ride_water(t, delta)
			_bite_window -= delta
			if _bite_window <= 0.0:
				_state = State.DRIFT
				_prompt("It let go. The float settles.")
				_schedule_bite()
		State.FIGHT:
			_fight(delta, t)
		State.DONE:
			return
	# Walked off mid-cast: the line comes in on its own.
	if _state != State.DONE and _player.global_position.distance_to(_cast_origin) > CANCEL_DISTANCE:
		_finish("")
		return
	_dip = move_toward(_dip, 0.0, delta * 0.8)
	_update_line()

func _ride_water(t: float, _delta: float) -> void:
	global_position.y = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85 + 0.02 - _dip

func _hook() -> void:
	# Roll the species now — the fight character comes from what took the bait.
	var key: String = _phase_key()
	var total: int = 0
	for s in SPECIES:
		total += s["w"][key]
	var roll: int = _rng.randi_range(1, maxi(total, 1))
	_fish = SPECIES[0]
	for s in SPECIES:
		roll -= s["w"][key]
		if roll <= 0:
			_fish = s
			break
	_state = State.FIGHT
	_tension = 0.3
	_progress = 0.35
	_fight_t = 0.0
	Journal.discover("system_fishing")

func _fight(delta: float, t: float) -> void:
	_fight_t += delta
	var pull: float = _fish["pull"]
	# The fish surges in waves — reel the lulls, respect the surges.
	var surge: float = 0.5 + 0.5 * sin(_fight_t * (1.1 + pull * 0.5))
	if _reeling:
		_progress += (REEL_RATE / _fish["fight"]) * delta
		_tension += (0.28 + surge * pull * 0.55) * delta
	else:
		_tension -= TENSION_DECAY * delta
		_progress -= surge * pull * 0.035 * delta
	_tension = clampf(_tension, 0.0, 1.2)
	_progress = clampf(_progress, 0.0, 1.0)
	# The float drags toward the fish's runs.
	global_position.y = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85 - 0.2 * surge
	if _tension >= 1.0:
		AudioDirector.play_one_shot("claw", _hand_pos(), -16.0)
		_finish("The line parts. Gone.")
		return
	if _progress <= 0.0:
		_finish("It spat the hook and ran.")
		return
	if _progress >= 1.0:
		_land()
		return
	_prompt("FIGHT  [hold LMB] reel   line %s   strain %s" % [_bar(_progress), _bar(_tension)])

static func _bar(v: float) -> String:
	var n: int = clampi(int(v * 8.0), 0, 8)
	return "▮".repeat(n) + "▯".repeat(8 - n)

func _land() -> void:
	AudioDirector.play_one_shot("splash", global_position, -6.0)
	if _fish["id"] == "the_looker":
		# Canon: it is never kept. The catch is the moment.
		Journal.discover("fish_the_looker")
		_finish("It surfaces — and looks back at you. Your hands open on their own.")
		return
	Journal.discover(_fish["id"])
	if PlayerState.add_item(_fish["id"]):
		_finish("Caught: %s" % _fish["name"])
	else:
		_finish("Pack's full — the %s slips back." % _fish["name"])

func _prompt(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt_raw(text)

func _finish(msg: String) -> void:
	_state = State.DONE
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt("")
		if msg != "":
			hud.toast(msg)
	if _player and _player.has_method("fishing_done"):
		_player.fishing_done()
	queue_free()

func _update_line() -> void:
	var a: Vector3 = _hand_pos()
	var b: Vector3 = global_position + Vector3(0, 0.05, 0)
	var mid: Vector3 = (a + b) * 0.5
	if _state != State.FIGHT:
		mid.y -= minf(a.distance_to(b) * 0.05, 0.9)   # slack sag
	var dist: float = a.distance_to(b)
	_line_mesh.height = dist
	_line.global_position = mid
	if dist > 0.01:
		_line.look_at(b, Vector3.UP)
		_line.rotate_object_local(Vector3.RIGHT, PI * 0.5)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	match _state:
		State.BITE:
			if event.pressed:
				_hook()
				get_viewport().set_input_as_handled()
		State.FIGHT:
			_reeling = event.pressed
			get_viewport().set_input_as_handled()
		State.DRIFT:
			if event.pressed:
				_finish("")   # reel in early
				get_viewport().set_input_as_handled()
