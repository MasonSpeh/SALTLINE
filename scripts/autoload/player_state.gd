extends Node
## Owns survival stats (hunger, thirst, warmth, life) + inventory/hotbar. Depletion rates
## come from data/tuning.json (A1: no magic numbers). Consequences stay soft until life
## bottoms out — then player_died fires and the controller runs a blackout respawn.

signal hunger_changed(value: float)
signal thirst_changed(value: float)
signal warmth_changed(value: float)
signal life_changed(value: float)
signal player_died
signal stat_low(stat_name: String)
signal stat_recovered(stat_name: String)
signal inventory_changed
signal item_eaten(item_id: String)

const LOW_THRESHOLD: float = 0.5
const HOTBAR_SIZE: int = 4
const MAX_BACKPACK: int = 12   ## Minecraft-ish, but a day pack, not a warehouse

const LIFE_DRAIN_PER_SEC: float = 0.02   ## while starving or parched
const LIFE_REGEN_PER_SEC: float = 0.01   ## while fed, watered, and not too sick

var hunger: float = 1.0 : set = set_hunger
var thirst: float = 1.0 : set = set_thirst
var warmth: float = 1.0 : set = set_warmth
var life: float = 1.0 : set = set_life
var hotbar: Array = [null, null, null, null]
var inventory: Array = [] ## overflow list beyond the hotbar
var selected_hotbar: int = -1  ## last hotbar slot pressed (#1-4)

## Environmental warmth modifier, set by cold/heat zones: -1 cold, 0 neutral, +1 heated.
var warmth_zone: int = 0
var sickness: float = 0.0  ## 0-1, sick reduces stamina; decays over time

var tuning: Dictionary = {}
var items: Dictionary = {}

var _hunger_was_low: bool = false
var _thirst_was_low: bool = false
var _warmth_was_low: bool = false
var _depleting: bool = true
var _died: bool = false   ## player_died fires once; reset when life climbs back above zero

func _ready() -> void:
	tuning = _load_json("res://data/tuning.json")
	items = _load_json("res://data/items.json")
	EventBus.creature_contact.connect(_on_creature_contact)

func _on_creature_contact() -> void:
	life -= 0.2

func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}

func _process(delta: float) -> void:
	if not _depleting:
		return
	hunger -= tuning.get("hunger_per_sec", 0.00055) * delta
	thirst -= tuning.get("thirst_per_sec", 0.0011) * delta
	var w_rate: float = tuning.get("warmth_per_sec_neutral", 0.0)
	if warmth_zone < 0:
		w_rate = tuning.get("warmth_per_sec_cold", -0.004)
	elif warmth_zone > 0:
		w_rate = tuning.get("warmth_per_sec_heated", 0.02)
	elif GameClock.current_phase == GameClock.Phase.NIGHT:
		w_rate = tuning.get("warmth_per_sec_night", -0.0015)
	warmth += w_rate * delta
	sickness = maxf(0.0, sickness - delta * 0.15)  # recover from sickness over time
	# Life: starving or parched wears you down; fed + watered + mostly-well heals you.
	if hunger <= 0.0 or thirst <= 0.0:
		life -= LIFE_DRAIN_PER_SEC * delta
	elif hunger > 0.5 and thirst > 0.5 and sickness < 0.25:
		life += LIFE_REGEN_PER_SEC * delta

func set_depleting(v: bool) -> void:
	_depleting = v

func set_hunger(value: float) -> void:
	hunger = clampf(value, 0.0, 1.0)
	hunger_changed.emit(hunger)
	_check_threshold("hunger", hunger, _hunger_was_low)

func set_thirst(value: float) -> void:
	thirst = clampf(value, 0.0, 1.0)
	thirst_changed.emit(thirst)
	_check_threshold("thirst", thirst, _thirst_was_low)

func set_warmth(value: float) -> void:
	warmth = clampf(value, 0.0, 1.0)
	warmth_changed.emit(warmth)
	_check_threshold("warmth", warmth, _warmth_was_low)

func set_life(value: float) -> void:
	life = clampf(value, 0.0, 1.0)
	life_changed.emit(life)
	if life <= 0.0:
		if not _died:
			_died = true
			player_died.emit()
	else:
		_died = false   # revive (respawn restores life) re-arms the death signal

func _check_threshold(stat_name: String, value: float, was_low: bool) -> void:
	var is_low: bool = value < LOW_THRESHOLD
	if is_low and not was_low:
		stat_low.emit(stat_name)
	elif not is_low and was_low:
		stat_recovered.emit(stat_name)
	match stat_name:
		"hunger":
			_hunger_was_low = is_low
		"thirst":
			_thirst_was_low = is_low
		"warmth":
			_warmth_was_low = is_low

## Stamina ceiling reduction when stats are low or player is sick.
func stamina_ceiling_multiplier() -> float:
	var mult: float = 1.0
	if hunger < LOW_THRESHOLD:
		mult *= 0.75
	if thirst < LOW_THRESHOLD:
		mult *= 0.75
	if warmth < LOW_THRESHOLD:
		mult *= 0.75
	if sickness > 0.5:
		mult *= 0.5
	return mult

func add_item(item_id: String) -> bool:
	for i in range(HOTBAR_SIZE):
		if hotbar[i] == null:
			hotbar[i] = item_id
			inventory_changed.emit()
			Journal.discover("item_" + item_id)
			return true
	if inventory.size() >= MAX_BACKPACK:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Pack is full.")
		return false
	inventory.append(item_id)
	inventory_changed.emit()
	Journal.discover("item_" + item_id)
	return true

## Inventory panel moves: click a pack item into a free hotbar slot, or stow a
## hotbar item back into the pack.
func backpack_to_hotbar(inv_idx: int) -> bool:
	if inv_idx < 0 or inv_idx >= inventory.size():
		return false
	for i in range(HOTBAR_SIZE):
		if hotbar[i] == null:
			hotbar[i] = inventory[inv_idx]
			inventory.remove_at(inv_idx)
			inventory_changed.emit()
			return true
	return false

func hotbar_to_backpack(slot: int) -> bool:
	if slot < 0 or slot >= HOTBAR_SIZE or hotbar[slot] == null:
		return false
	if inventory.size() >= MAX_BACKPACK:
		return false
	inventory.append(hotbar[slot])
	hotbar[slot] = null
	inventory_changed.emit()
	return true

func remove_item(item_id: String) -> bool:
	var hotbar_idx: int = hotbar.find(item_id)
	if hotbar_idx != -1:
		hotbar[hotbar_idx] = null
		inventory_changed.emit()
		return true
	var inv_idx: int = inventory.find(item_id)
	if inv_idx != -1:
		inventory.remove_at(inv_idx)
		inventory_changed.emit()
		return true
	return false

func has_item(item_id: String) -> bool:
	return hotbar.has(item_id) or inventory.has(item_id)

## USE the item in a hotbar slot (consumables only; tools are passive keys for verbs).
## "eat" restores hunger, "drink" restores thirst; a def carrying BOTH hunger and
## thirst fields applies both regardless of which verb it uses.
func use_hotbar(slot: int) -> void:
	if slot < 0 or slot >= HOTBAR_SIZE or hotbar[slot] == null:
		return
	selected_hotbar = slot
	var id: String = hotbar[slot]
	var def: Dictionary = items.get(id, {})
	var use: String = def.get("use", "")
	if use == "eat" or use == "drink":
		if use == "eat":
			hunger += def.get("hunger", 0.35)
			if def.has("thirst"):
				thirst += def.get("thirst", 0.0)
		else:
			thirst += def.get("thirst", 0.4)
			if def.has("hunger"):
				hunger += def.get("hunger", 0.0)
		# Apply side effects (raw glow worm causes sickness)
		if def.get("side_effect", "") == "sick":
			sickness = 0.8
		hotbar[slot] = null
		# Pull an overflow item into the freed slot.
		if not inventory.is_empty():
			hotbar[slot] = inventory.pop_front()
		inventory_changed.emit()
		item_eaten.emit(id)
		AudioDirector.play_one_shot("eat", Vector3.ZERO)
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			var msg: String = def.get("name", id)
			if def.get("side_effect", "") == "sick":
				hud.toast("%s tasted... wrong. Feeling queasy." % msg)
			elif use == "drink":
				hud.toast("Drank %s. Better." % msg)
			else:
				hud.toast("Ate %s. Better." % msg)
