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

# Deep-drop rig (the crane hand-line): a straight-down, bait-gated line that pulls the
# big, deep species. Every one of these only ever applies when _deep is true — the plain
# surface rod path is byte-for-byte unchanged.
const DEEP_CAST_LIFT: float = 0.5     # the lead-weighted line plunges; almost no arc
const DEEP_BITE_FACTOR: float = 1.35  # the deep is patient — bites take longer to find the bait
const BARREN_GIVEUP: float = 8.0      # a bare deep hook: how long before you give up on it
## WHY THE DEEP RIG NEEDS ITS OWN RANGE AND SPEED — the "deep rig doesn't cast" bug.
## It is fished off the crane machinery deck, whose plate is at y 34.15, so the lead has to
## fall ~36 m before it ever touches water. At the surface rod's CAST_SPEED of 13 m/s that
## flight is ~35 m out and ~36 m down: about 50 m of line, which blew straight through
## MAX_RANGE (45) at roughly t=2.55 s — and the over-range branch calls _finish("") with an
## EMPTY message. So the line silently vanished mid-air, every single time, and the rig read
## as completely broken. The deep line is long (95 m) and slow off the tip: it is a weighted
## hand-line you drop over the side, not something you whip out over the sea.
## Speed is a second, quieter half of the same bug: too slow off the tip and the lead sinks
## into the machinery deck's own INVISIBLE guard-rail slab (y 33.5..34.8 at ±3.4 m) before it
## is clear of the plate, which reads as "No open water there" while the player is plainly
## aiming at the sea. 7 m/s clears both the rail and the deck edge from anywhere on the plate
## on a roughly level aim, and still falls far more than it flies.
const DEEP_MAX_RANGE: float = 95.0    # enough line to reach the sea from the crane and fight
const DEEP_CAST_SPEED: float = 7.0    # clears the guard, then plunges

# Species, conditions, and weights all live in data/fish.json via FishTable —
# the same table the drop net, the stove, and the Angler's Notes read.
const FISH := preload("res://scripts/world/fish_table.gd")

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
var _deep: bool = false          # this cast is the deep-drop rig, not the surface rod
var _bait_id: String = ""        # bait chosen for the hook this cast ("" = none found)
var _barren: bool = false        # deep line with no bait — nothing down there will take it
var _barren_t: float = 0.0

func setup(player: Node3D, camera: Camera3D) -> void:
	_player = player
	_cast_origin = player.global_position
	_rng.randomize()
	# Which tool cast this line? The deep rig is live only when it's the selected hotbar
	# item; anything else (the plain rod) fishes the surface exactly as before.
	_deep = _is_deep_selected()
	global_position = camera.global_position - camera.global_transform.basis.z * 0.5
	# The deep rig is a weighted hand-line: it barely arcs, it drops. Aim out over the sea
	# from the crane top and the lead takes it straight down into deep water. (It still
	# reuses the in-flight structure-foul raycast, so a drop onto the deck reads "no open
	# water there" — which teaches the player to fish it over the edge.)
	var lift: float = DEEP_CAST_LIFT if _deep else CAST_LIFT
	var speed: float = DEEP_CAST_SPEED if _deep else CAST_SPEED
	_velocity = -camera.global_transform.basis.z * speed + Vector3(0, lift, 0)
	if _deep:
		# Bait is chosen and locked now, at the cast. No bait, no deep bite.
		_bait_id = _find_bait()
		_barren = _bait_id == ""
		_schedule_bite()   # re-roll at deep pace now that _deep is known (_ready ran surface-paced)

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
	# The tip of the actually-held rod visual, wherever the camera is looking — not
	# a fixed world-space offset from the player's feet. That fixed offset never
	# moved with the camera at all, so turning to look around left the line's start
	# point behind while the rod on screen swung with the view: the "glitched away"
	# line. hand_tip_world() reads the held item's live transform instead.
	if _player.has_method("hand_tip_world"):
		return _player.hand_tip_world()
	return _player.global_position + Vector3(0, 1.25, 0)

## The deep-drop rig is live only when its OWN item is the selected hotbar tool. The
## plain fishing_rod is never deep — the surface game stays exactly as it was.
func _is_deep_selected() -> bool:
	var sel: int = PlayerState.selected_hotbar
	if sel < 0 or sel >= PlayerState.HOTBAR_SIZE:
		return false
	var it: Variant = PlayerState.hotbar[sel]
	return it != null and String(it) == "deep_rig_pole"

## Find one bait in the pack: a live snail, or any fish flesh as cut bait (rotten chum
## counts — a bare fish BONE does not). Cheapest-first, so a prize catch is never spent
## baiting the next drop. Returns the item id, or "" when there's none.
func _find_bait() -> String:
	for want in ["snail_live", "fish_rotten"]:
		if PlayerState.has_item(want):
			return want
	for entry in PlayerState.hotbar + PlayerState.inventory:
		if entry != null and _is_cut_bait(String(entry)):
			return String(entry)
	return ""

static func _is_cut_bait(id: String) -> bool:
	return id.begins_with("fish_") and id != "fish_bone" and id != "fish_rotten"

## Plain-words bait name for the water-read prompt.
func _bait_name() -> String:
	if _bait_id == "snail_live":
		return "a live snail"
	if _bait_id == "fish_rotten":
		return "rotten chum"
	return "cut bait"

func _schedule_bite() -> void:
	# The water read drives the wait: storms are a frenzy, feeding hours are
	# brisk, dead calm afternoons make you earn it. Nibbles lie first.
	var ctx: Dictionary = FISH.context(self, global_position)
	var mean: float = 12.0 * FISH.bite_pace(ctx)
	if _deep:
		mean *= DEEP_BITE_FACTOR   # the deep is patient
	_bite_timer = _rng.randf_range(mean * 0.45, mean * 1.5)
	_nibbles = _rng.randi_range(0, 2)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		queue_free()
		return
	if _player.ui_locked or _player.input_locked or (_player.get("build") and _player.build.active):
		_finish("")   # panels, blackouts, and build mode all reel the line in
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
				_finish("The lead clatters off the steel — stand at the rail and drop it over the side." \
					if _deep else "No open water there.")
				return
			var water_y: float = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85
			if global_position.y <= water_y + 0.02:
				global_position.y = water_y + 0.02
				AudioDirector.play_one_shot("splash", global_position, -14.0)
				_state = State.DRIFT
				if _deep:
					if _barren:
						_prompt("The weight plunges into the dark — but the hook's bare.")
					else:
						_prompt("The weight takes it down — deep water, %s on the hook." % _bait_name())
				else:
					# The water read: teach the variables by naming them every cast.
					_prompt("Line's out — %s" % FISH.summary(FISH.context(self, global_position)))
			elif global_position.distance_to(_hand_pos()) > (DEEP_MAX_RANGE if _deep else MAX_RANGE):
				# Say something rather than letting the line evaporate: a silent _finish("")
				# here is exactly what made the deep rig look like it did nothing at all.
				_finish("Out of line — drop it over the side, into open water." if _deep else "")
				return
		State.DRIFT:
			_ride_water(t, delta)
			if _barren:
				# A bare deep hook: the dark won't answer. A beat to feel it, then reel in.
				_barren_t += delta
				if _barren_t >= BARREN_GIVEUP:
					_finish("Bare hook — the deep won't rise to nothing. Bait the line.")
					return
			else:
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
	# Roll the species now, from the live conditions at THIS float, THIS moment — the
	# fight character comes from what took the bait. The deep rig draws its OWN pool
	# (deep-flagged, bigger species) and spends a bait; the surface rod rolls "rod" as before.
	var kind: String = "deep" if _deep else "rod"
	_fish = FISH.roll(kind, FISH.context(self, global_position), _rng)
	if _fish.is_empty():
		_finish("Whatever it was, it's gone.")
		return
	if _deep:
		# The bait's taken — spend one. (Re-found fresh in case the pack shifted.)
		var spent: String = _find_bait()
		if spent != "":
			PlayerState.remove_item(spent)
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
		AudioDirector.play_one_shot("scuttle_a", _hand_pos(), -16.0)   # dry snap of parting line
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
	if _fish.get("release", false):
		# Canon: it is never kept. The catch is the moment.
		Journal.discover("fish_the_looker")
		_finish("It surfaces — and looks back at you. Your hands open on their own.")
		return
	Journal.discover(_fish["id"])
	if PlayerState.add_item(_fish["id"]):
		_fly_catch_to_player()
		_finish("Caught: %s" % _fish["name"])
	else:
		_finish("Pack's full — the %s slips back." % _fish["name"])

## The visual payoff: the fish arcs out of the water into your hands, flashing
## and flipping, then vanishes into the pack. Owned by the scene, so it plays
## out even though the rod frees itself immediately after.
func _fly_catch_to_player() -> void:
	var fish_visual: Node3D = ItemVisual.build(_fish["id"])
	get_tree().current_scene.add_child(fish_visual)
	fish_visual.global_position = global_position
	var dest: Vector3 = _player.global_position + Vector3(0, 1.1, 0)
	var apex: Vector3 = (global_position + dest) * 0.5 + Vector3(0, 2.6, 0)
	var tw: Tween = fish_visual.create_tween()
	tw.tween_property(fish_visual, "global_position", apex, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fish_visual, "global_position", dest, 0.26) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(fish_visual, "rotation:x", TAU * 1.5, 0.26)
	tw.tween_callback(fish_visual.queue_free)

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

## Stretch the line mesh exactly from the rod tip (a) to the float (b). MUST land on
## BOTH points exactly, every frame, wherever the bob drifts to — that was the bug:
## the old version shifted the cylinder's PIVOT down for a slack "sag" look, then called
## look_at(b) FROM that shifted pivot. look_at only orients toward b; it does not correct
## for the pivot having moved, so the far half of the cylinder (extending the opposite way
## from the same shifted point) missed the true `a` by roughly twice the sag offset — a
## fixed, cosmetic, unrelated-to-anchoring line that read as "the line just lies near the
## water", never actually reaching the rod. This builds the segment directly from a
## transform basis (StructureLib.line()'s technique): dist is the true a-b span, mid is the
## true a-b midpoint, and the basis's Y axis (a CylinderMesh's own length axis) is set to
## point exactly along a->b, so the two ends of the cylinder are ALWAYS exactly a and b —
## no reorientation step that can drift off either endpoint.
func _update_line() -> void:
	var a: Vector3 = _hand_pos()
	var b: Vector3 = global_position + Vector3(0, 0.05, 0)
	var delta: Vector3 = b - a
	var dist: float = delta.length()
	_line_mesh.height = dist
	_line.global_position = (a + b) * 0.5
	if dist > 0.001:
		var dir: Vector3 = delta / dist
		var ref: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		var xa: Vector3 = ref.cross(dir).normalized()
		var za: Vector3 = dir.cross(xa).normalized()
		_line.global_transform = Transform3D(Basis(xa, dir, za), _line.global_position)

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
