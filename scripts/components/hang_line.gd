class_name HangLine extends Interactable
## A marked drying line: HANG a fish from your pack on it, TAKE it back later.
## Raw fish stays fresh for 4 game hours, then turns (Rotten Fish). Cooked fish
## cures instead — 4 game hours on the line makes Dried Fish, which keeps
## forever with the same nourishment. The rig's larder, strung in the wind.

const FISH := preload("res://scripts/world/fish_table.gd")
const FRESH_HOURS: float = 4.0
const SLOTS: int = 4

var length_m: float = 2.4
var _hung: Array = []          ## [{id, age_h, visual}]
var _game_hour_per_sec: float = 0.0

func _init() -> void:
	display_name = "Drying Line"

func _ready() -> void:
	# One game hour in real seconds, from the clock's own day plan.
	var day_sec: float = 0.0
	for phase in GameClock.phase_durations_minutes:
		day_sec += GameClock.phase_durations_minutes[phase] * 60.0
	_game_hour_per_sec = 24.0 / maxf(day_sec, 1.0)
	# The line itself + interaction body.
	var rope := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.02
	rm.bottom_radius = 0.02
	rm.height = length_m
	rm.material = MatLib.rope_mat()
	rope.mesh = rm
	rope.rotation.z = deg_to_rad(90)
	add_child(rope)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length_m, 0.28, 0.3)
	col.shape = box
	add_child(col)
	# A few empty hooks so the line reads as usable before anything hangs.
	for i in range(SLOTS):
		var hook := MeshInstance3D.new()
		var hm := TorusMesh.new()
		hm.inner_radius = 0.025
		hm.outer_radius = 0.05
		hm.material = MatLib.galvanized()
		hook.mesh = hm
		hook.position = Vector3(_slot_x(i), -0.08, 0)
		add_child(hook)

func _slot_x(i: int) -> float:
	return -length_m * 0.5 + length_m * (float(i) + 0.5) / SLOTS

func available_verbs() -> Array[String]:
	var v: Array[String] = []
	if _hung.size() < SLOTS and _player_fish() != "":
		v.append("HANG")
	if not _hung.is_empty():
		v.append("TAKE")
	return v

func get_prompt() -> String:
	var v: Array[String] = available_verbs()
	if v.is_empty():
		return ""
	return "%s  %s (%d hung)" % [v[0], display_name, _hung.size()]

func interact(verb: String, _player: Node3D) -> void:
	match verb:
		"HANG":
			_hang()
		"TAKE":
			_take()
	super.interact(verb, _player)

## Anything fishy in the pack qualifies: raw (rots), cooked (dries), dried (inert).
func _hangable(id: String) -> bool:
	return FISH.cooked_for(id) != "" or id == "cooked_fish" or id == "cooked_fish_prime" \
		or id == "dried_fish" or id == "fish_rotten"

func _player_fish() -> String:
	var sel: int = PlayerState.selected_hotbar
	if sel >= 0 and sel < PlayerState.HOTBAR_SIZE and PlayerState.hotbar[sel] != null \
			and _hangable(String(PlayerState.hotbar[sel])):
		return String(PlayerState.hotbar[sel])   # hang what's in your hand first
	for it in PlayerState.hotbar:
		if it != null and _hangable(String(it)):
			return String(it)
	for it in PlayerState.inventory:
		if _hangable(String(it)):
			return String(it)
	return ""

func _hang() -> void:
	var id: String = _player_fish()
	if id == "" or _hung.size() >= SLOTS:
		return
	PlayerState.remove_item(id)
	var visual: Node3D = ItemVisual.build(id)
	add_child(visual)
	visual.position = Vector3(_slot_x(_hung.size()), -0.55, 0)
	visual.rotation.z = PI   # hung by the tail
	_hung.append({"id": id, "age_h": 0.0, "visual": visual})
	AudioDirector.play_one_shot("clang", global_position, -22.0)
	Journal.discover("system_preserving")

func _take() -> void:
	if _hung.is_empty():
		return
	var entry: Dictionary = _hung.pop_back()
	(entry["visual"] as Node3D).queue_free()
	PlayerState.add_item(entry["id"])
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Off the line: %s" % PlayerState.items.get(entry["id"], {}).get("name", entry["id"]))

func _process(delta: float) -> void:
	if _hung.is_empty():
		return
	var dh: float = delta * GameClock.time_scale * _game_hour_per_sec
	for entry in _hung:
		entry["age_h"] += dh
		if entry["age_h"] < FRESH_HOURS:
			continue
		var id: String = entry["id"]
		var next: String = ""
		if FISH.cooked_for(id) != "":
			next = "fish_rotten"                     # raw turns
		elif id == "cooked_fish" or id == "cooked_fish_prime":
			next = "dried_fish"                      # cooked cures
		if next != "" and next != id:
			entry["id"] = next
			entry["age_h"] = 0.0
			var old: Node3D = entry["visual"]
			var pos: Vector3 = old.position
			old.queue_free()
			var fresh: Node3D = ItemVisual.build(next)
			add_child(fresh)
			fresh.position = pos
			fresh.rotation.z = PI
			entry["visual"] = fresh
