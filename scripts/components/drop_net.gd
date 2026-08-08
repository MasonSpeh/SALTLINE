class_name DropNet extends Interactable
## The drop net (GDD §5.3, "Drop/Crane net — vertical, from rig decks"): a
## weighted mesh on a winch line. LOWER it off a deck edge, let it soak, HAUL it
## back up. It only catches if the net actually reached water — a net hung over
## deck comes up dry, so placement at an edge is the whole craft of it.

enum NetState { UP_EMPTY, SOAKING, READY }

const DROP_MAX: float = 26.0   # reaches water from the topside deck (18m) with margin
const SOAK_MIN_SEC: float = 70.0
const SOAK_MAX_SEC: float = 115.0

# The catch table lives in data/fish.json (net-flagged species: prawns, crabs,
# flounder, the door-sized halibut) — shared with the rod, stove, and notes.
const FISH := preload("res://scripts/world/fish_table.gd")

var net: Node3D = null            ## assigned by the structure builder
var rope_pivot: Node3D = null     ## hang line pivot; scale.y stretches with the drop
var _state: NetState = NetState.UP_EMPTY
var _soak_left: float = 0.0
var _soak_total: float = 1.0
var _soaked_dark: bool = false    ## any of the soak spent in dusk/night
var _wet: bool = false            ## the net reached water
var _drop_dist: float = 0.0
var _busy: bool = false           ## winch running — no verbs until the tween lands
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	display_name = "Drop Net"
	_rng.randomize()

func available_verbs() -> Array[String]:
	var v: Array[String] = []
	if _busy:
		return v   # the drum is turning — hands off
	match _state:
		NetState.UP_EMPTY:
			v.append("LOWER")
		NetState.SOAKING, NetState.READY:
			v.append("HAUL")   # early haul allowed; a short soak comes up light
	return v

func interact(verb: String, _player: Node3D) -> void:
	match verb:
		"LOWER":
			_lower()
		"HAUL":
			_haul()
	super.interact(verb, _player)

func _process(delta: float) -> void:
	if _state == NetState.SOAKING:
		if BloomFauna.is_dark_phase():
			_soaked_dark = true
		_soak_left -= delta
		if _soak_left <= 0.0:
			_state = NetState.READY

func _lower() -> void:
	if net == null:
		return
	# Drop until water or whatever's below — a raycast tells the net's story.
	var space: PhysicsDirectSpaceState3D = net.get_world_3d().direct_space_state
	var from: Vector3 = net.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -DROP_MAX, 0))
	var hit: Dictionary = space.intersect_ray(q)
	# The net's origin is its TOP ring; the basket hangs ~1.1m below it — stop
	# high enough that the mesh rests ON a deck instead of buried through it.
	var floor_dist: float = DROP_MAX if hit.is_empty() else from.y - float(hit["position"].y) - 1.35
	var water_dist: float = maxf(from.y - 0.4, 0.5)   # sea level ~0
	_drop_dist = minf(floor_dist, water_dist)
	_wet = water_dist <= floor_dist + 0.01
	_busy = true
	var tw: Tween = create_tween()
	tw.tween_property(net, "position:y", net.position.y - _drop_dist, 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if rope_pivot:
		# The pivot's child cylinder is height 1.0, so rope length == scale.y.
		tw.parallel().tween_property(rope_pivot, "scale:y", 1.05 + _drop_dist, 2.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void: _busy = false)
	AudioDirector.play_one_shot("clang", global_position, -18.0)
	_soak_left = _rng.randf_range(SOAK_MIN_SEC, SOAK_MAX_SEC)
	_soak_total = _soak_left
	_soaked_dark = BloomFauna.is_dark_phase()
	_state = NetState.SOAKING
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Net down. Give the sea a while." if _wet else "The net hangs over deck — it won't fish there.")

func _haul() -> void:
	if net == null:
		return
	var soaked: float = 1.0 if _state == NetState.READY \
		else clampf(1.0 - _soak_left / _soak_total, 0.0, 1.0)
	_busy = true
	var tw: Tween = create_tween()
	tw.tween_property(net, "position:y", net.position.y + _drop_dist, 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if rope_pivot:
		tw.parallel().tween_property(rope_pivot, "scale:y", 1.05, 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: _busy = false)
	AudioDirector.play_one_shot("splash", global_position, -12.0)
	_state = NetState.UP_EMPTY
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not _wet:
		if hud:
			hud.toast("The net comes up dry. It needs open water below.")
		return
	if soaked < 0.5:
		if hud:
			hud.toast("Too soon — the mesh comes up empty. Let it soak.")
		return
	# 1-3 fish; the dark hours swim shallower into the mesh. Catches roll from
	# fish.json under the conditions the net actually soaked through.
	var ctx: Dictionary = FISH.context(self, net.global_position)
	if _soaked_dark:
		ctx["phase"] = "night"
	var count: int = 1 + _rng.randi_range(0, 1) + (1 if _soaked_dark else 0)
	if soaked < 1.0:
		count = 1   # an early-but-decent soak still lands something
	var names: Array[String] = []
	for i in range(count):
		var pick: Dictionary = FISH.roll("net", ctx, _rng)
		if pick.is_empty():
			continue
		# Sized species weigh in at the haul, exactly as they do at the rod's rail —
		# the fathom halibut only ever comes up in THIS mesh, so if the net did not
		# roll weights the door-sized fish would be the one species that never had
		# one: it would fillet, drop and render as an average halibut forever.
		#
		# ROLLED BEFORE THE PACK IS TRIED, because add_item now needs the payload to know
		# the slot cannot stack. The old order (add, then roll, then record) worked only
		# because the weight went to a side ledger keyed on the species.
		var nid: String = String(pick["id"])
		var kg: float = FISH.roll_size(nid, _rng)
		if PlayerState.add_item(nid, FISH.catch_meta(nid, kg)):
			if kg > 0.0:
				names.append("%s — %.1f kg%s" % [pick["name"], kg,
					", a trophy" if FISH.is_trophy_size(nid, kg) else ""])
			else:
				names.append(pick["name"])
			Journal.discover(nid)
	Journal.discover("system_drop_net")
	if hud:
		hud.toast("Net comes up: %s" % ", ".join(names) if not names.is_empty() else "Net comes up empty this time.")
