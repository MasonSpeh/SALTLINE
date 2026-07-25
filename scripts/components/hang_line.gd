class_name HangLine extends Interactable
## A marked drying line: HANG a fish from your pack on it, TAKE it back later.
## Raw fish stays fresh for 4 game hours, then turns (Rotten Fish). Cooked fish
## cures instead — 4 game hours on the line makes Dried Fish, which keeps
## forever with the same nourishment. The rig's larder, strung in the wind.
##
## ONE EXCEPTION, and it is the other half of the deep rig's payoff: a fish big enough to
## carry a fillets range in data/fish.json does NOT turn on the line. A grouper is worth
## the salt, so it CURES straight from raw — 4 hours in the wind and it comes off as 6 to 12
## Dried Fish, by what that particular fish weighed. Cooking it on the stove gives the same
## count as its own species' fillets; this is the cold, fuel-free way to the same payoff.
## Everything smaller behaves exactly as it always has: raw turns, cooked cures, one for one.

const FISH := preload("res://scripts/world/fish_table.gd")
const FRESH_HOURS: float = 4.0
const SLOTS: int = 4

var length_m: float = 2.4
## [{id, age_h, visual, n, cure_n}] — n is how many items TAKE hands back right now (1 until
## it has cured), cure_n is how many it will hand back once it has. A cured big fish is a
## whole handful on one hook; everything else is 1 either way.
var _hung: Array = []
var _game_hour_per_sec: float = 0.0
## Only for weights we never saw landed (a reloaded save, a netted fish) — FishTable.take_size.
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	display_name = "Drying Line"
	_rng.randomize()

func _ready() -> void:
	# A drying line is strung BETWEEN two posts and there is nothing under it by design,
	# so the placement audit must not measure the deck 2 m below it as a missing support.
	add_to_group("placement_exempt")
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

## Anything fishy in the pack qualifies: raw (rots, or CURES if it is a big one), cooked
## (dries), dried (inert). "cooked_fish*" catches the legacy generic meals AND all ~19
## per-species ones — those could not be hung at all before, which made the whole species
## fillet line a dead end on the drying rack.
func _hangable(id: String) -> bool:
	return FISH.cooked_for(id) != "" or id.begins_with("cooked_fish") \
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
	# The weight is claimed HERE, as the fish leaves the pack, not when the cure finishes —
	# it is THIS fish on the hook, and the ledger should not hand its weight to another.
	# It only becomes the number of items the hook gives back once the cure has actually
	# happened (see _process): a big fish taken back off the line still raw is one fish.
	_hung.append({"id": id, "age_h": 0.0, "visual": visual, "n": 1, "cure_n": _cure_yield(id)})
	AudioDirector.play_one_shot("clang", global_position, -22.0)
	Journal.discover("system_preserving")

## Portions this hook will give back once it has cured. One for every ordinary fish; for a
## big species, what that fish's landed weight fillets out into — the same cut the stove
## would have made of it.
func _cure_yield(id: String) -> int:
	if FISH.cooked_for(id) == "":
		return 1   # already cooked / dried / rotten — one item in, one item out
	return int(FISH.take_yield(id, _rng)["n"])

func _take() -> void:
	if _hung.is_empty():
		return
	var entry: Dictionary = _hung.pop_back()
	(entry["visual"] as Node3D).queue_free()
	var id: String = String(entry["id"])
	var want: int = maxi(int(entry.get("n", 1)), 1)
	# A cured grouper is a dozen pieces off one hook, so the pack can run out mid-handful.
	# Anything that won't fit is set down under the line as a real, savable Takeable rather
	# than lost — same rule as the stove.
	var got: int = 0
	var floored: int = 0
	for _i in range(want):
		if PlayerState.add_item(id):
			got += 1
		else:
			var toss := Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
			SaveManager.drop_into_world(id, global_position + Vector3(0, -0.9, 0), toss)
			floored += 1
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		var nm: String = PlayerState.items.get(id, {}).get("name", id)
		if want <= 1:
			hud.toast("Off the line: %s" % nm)
		elif floored == 0:
			hud.toast("Off the line: %d × %s" % [got, nm])
		else:
			hud.toast("Off the line: %d × %s (%d set down — pack's full)" % [got, nm, floored])

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
			# Raw turns — unless it is a big fish, which is worth salting and cures instead.
			next = "dried_fish" if FISH.is_big(id) else "fish_rotten"
		elif id.begins_with("cooked_fish"):
			next = "dried_fish"                      # cooked cures (generic AND per-species)
		if next != "" and next != id:
			entry["id"] = next
			entry["age_h"] = 0.0
			if next == "dried_fish":
				entry["n"] = maxi(int(entry.get("cure_n", 1)), 1)   # a cured big fish is many
			var old: Node3D = entry["visual"]
			var pos: Vector3 = old.position
			old.queue_free()
			var fresh: Node3D = ItemVisual.build(next)
			add_child(fresh)
			fresh.position = pos
			fresh.rotation.z = PI
			entry["visual"] = fresh
