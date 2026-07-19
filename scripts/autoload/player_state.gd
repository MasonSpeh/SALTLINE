extends Node
## Owns survival stats (hunger, thirst, warmth, life) + inventory/hotbar. Depletion rates
## come from data/tuning.json (A1: no magic numbers). Consequences stay soft until life
## bottoms out — then player_died fires and the controller runs a blackout respawn.

signal hunger_changed(value: float)
signal thirst_changed(value: float)
signal warmth_changed(value: float)
signal life_changed(value: float)
signal rest_changed(value: float)
signal comfort_changed(value: float)
signal player_died
signal stat_low(stat_name: String)
signal stat_recovered(stat_name: String)
signal inventory_changed
signal item_eaten(item_id: String)

const LOW_THRESHOLD: float = 0.5
const HOTBAR_SIZE: int = 4
const MAX_BACKPACK: int = 12   ## Minecraft-ish, but a day pack, not a warehouse
## Same-id items pile into one slot up to this many — food, kits, salvage all stack,
## so a night's fishing is one slot instead of sixteen. Tools are the exception (see
## is_stackable): a wrench is a wrench, you carry one.
const MAX_STACK: int = 16
## Worn gear that actually does something. These are the ONLY numbers behind the
## three upgrade crafts — without them the recipes promised mechanics that did not
## exist anywhere in the codebase.
const TOOL_BELT_SLOTS: int = 4        ## canvas pockets: four more things you can carry
const BOOTS_COLD_RELIEF: float = 0.45 ## dry feet: cold bites 45% slower through them

const LIFE_DRAIN_PER_SEC: float = 0.02   ## while starving or parched
const LIFE_REGEN_PER_SEC: float = 0.01   ## while fed, watered, and not too sick

## Rest: the slow tax of being awake. Only sleep pays it back in full; sitting down
## slows the bleed. Low rest is a soft, real cost — you get winded sooner.
const REST_TIRED: float = 0.35           ## below this the stamina ceiling drops
const REST_SIT_RECOVER_MULT: float = 0.5 ## sitting recovers rest at half the drain rate
## Comfort: not a score, a reading. It climbs while you are seated, warm, under cover
## and inside your own camp, and it falls when you are out in a squall with nothing
## over your head. Its only mechanical job is to slow hunger and thirst — the reason
## to build somewhere nice instead of sleeping wherever you fall.
const COMFORT_EASE_PER_SEC: float = 0.09 ## comfort chases its target this fast
const COMFORT_HUNGER_RELIEF: float = 0.4 ## at comfort 1.0, hunger/thirst run 40% slower
const RESTING_DECAY_MULT: float = 0.45   ## seated or asleep: stats decay this much as fast

const COMFORT_SAVE_KEYS: Array[String] = ["rest", "comfort", "camp_found"]

var hunger: float = 1.0 : set = set_hunger
var thirst: float = 1.0 : set = set_thirst
var warmth: float = 1.0 : set = set_warmth
var life: float = 1.0 : set = set_life
var rest: float = 1.0 : set = set_rest
var comfort: float = 0.0 : set = set_comfort
var hotbar: Array = [null, null, null, null]
var inventory: Array = [] ## overflow list beyond the hotbar
## How many sit in each slot. Parallel to hotbar/inventory rather than folded into
## them, so every existing caller that reads `hotbar[i]` / iterates `inventory` still
## sees a plain item id (or null) — the count rides alongside. Counts are only ever
## meaningful where the matching slot holds an id; a null slot's count is ignored.
var hotbar_counts: Array = [1, 1, 1, 1]
var inventory_counts: Array = [] ## parallel to inventory, one int per stack
var selected_hotbar: int = -1  ## last hotbar slot pressed (#1-4)

## Environmental warmth modifier, set by cold/heat zones: -1 cold, 0 neutral, +1 heated.
var warmth_zone: int = 0
var sickness: float = 0.0  ## 0-1, sick reduces stamina; decays over time

## Written by ComfortFurniture each frame — where comfort is trying to settle (0-1).
var comfort_target: float = 0.0
## True while the player is sat down or asleep: stats ease off, rest creeps back.
var resting: bool = false
## Set once, the first time a real camp is recognised. Persisted.
var camp_found: bool = false

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
	# The comfort layer rides along with the state it feeds. Living here (rather than
	# in the level) means it survives scene reloads and needs no project.godot entry.
	# Deferred load(), never preload(): comfort_furniture.gd names the PlayerState
	# singleton, and that identifier does not exist yet while this autoload is itself
	# being compiled. Preloading it here fails the whole autoload, silently.
	call_deferred("_mount_comfort")

func _mount_comfort() -> void:
	var cf: GDScript = load("res://scripts/components/comfort_furniture.gd")
	if cf:
		add_child(cf.new())

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
	# Comfort eases toward whatever ComfortFurniture is reading off the world; it
	# keeps moving even when depletion is frozen, so the HUD never lies.
	comfort = move_toward(comfort, clampf(comfort_target, 0.0, 1.0), COMFORT_EASE_PER_SEC * delta)
	if not _depleting:
		return
	# A settled camp is a slower burn: comfort buys back a slice of hunger and thirst,
	# and sitting down (or sleeping) slows the whole clock further.
	var ease: float = 1.0 - COMFORT_HUNGER_RELIEF * comfort
	if resting:
		ease *= RESTING_DECAY_MULT
	hunger -= tuning.get("hunger_per_sec", 0.00055) * delta * ease
	thirst -= tuning.get("thirst_per_sec", 0.0011) * delta * ease
	# Rest: awake spends it, sitting still claws a little of it back. Only a night's
	# sleep fills it — see ComfortFurniture's bed flow.
	var rest_rate: float = tuning.get("rest_per_sec_awake", 0.00028)
	rest += (rest_rate * REST_SIT_RECOVER_MULT if resting else -rest_rate) * delta
	var w_rate: float = tuning.get("warmth_per_sec_neutral", 0.0)
	if warmth_zone < 0:
		w_rate = tuning.get("warmth_per_sec_cold", -0.004)
	elif warmth_zone > 0:
		w_rate = tuning.get("warmth_per_sec_heated", 0.02)
	elif GameClock.current_phase == GameClock.Phase.NIGHT:
		w_rate = tuning.get("warmth_per_sec_night", -0.0015)
	# Patched boots only help against LOSING heat — they are insulation, not a fire,
	# so they never slow you warming up at a brazier. The relief fraction is the
	# economy agent's `cold_relief` field on the item, not a hard-coded number, so a
	# tuning pass on the boots needs no code change; BOOTS_COLD_RELIEF is the fallback.
	if w_rate < 0.0 and has_item("patched_boots"):
		var relief: float = float(items.get("patched_boots", {}).get("cold_relief", BOOTS_COLD_RELIEF))
		w_rate *= (1.0 - relief)
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

func set_rest(value: float) -> void:
	rest = clampf(value, 0.0, 1.0)
	rest_changed.emit(rest)

func set_comfort(value: float) -> void:
	comfort = clampf(value, 0.0, 1.0)
	comfort_changed.emit(comfort)

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
	if rest < REST_TIRED:
		mult *= 0.8   # short nights show up in the legs before anywhere else
	return mult

## A full night in a bed you made. Bed.gd owns the wet-deck bunks; this is the shared
## payoff both it and a placed bedroll can call so the numbers never drift apart.
func sleep_recovery() -> void:
	rest = 1.0
	warmth = 1.0
	life = minf(1.0, life + 0.15)
	sickness = 0.0
	hunger = maxf(0.0, hunger - 0.08)
	thirst = maxf(0.0, thirst - 0.10)

# --- persistence -------------------------------------------------------------
# SaveManager owns the payload dict; these two are the whole comfort contribution.
# save_game() merges comfort_payload(); load_game() calls apply_comfort_payload().
# camp_found rides along so the one-time camp acknowledgement stays one-time across
# a reload instead of re-firing every session.

func comfort_payload() -> Dictionary:
	return {"rest": rest, "comfort": comfort, "camp_found": camp_found}

func apply_comfort_payload(data: Dictionary) -> void:
	rest = float(data.get("rest", 1.0))
	comfort = float(data.get("comfort", 0.0))
	comfort_target = comfort
	camp_found = bool(data.get("camp_found", false))

## How tall a stack of this item may grow. Tools never stack (a wrench is a wrench);
## everything else piles to MAX_STACK.
func is_stackable(item_id: String) -> bool:
	return items.get(item_id, {}).get("use", "") != "tool"

func _stack_cap(item_id: String) -> int:
	return MAX_STACK if is_stackable(item_id) else 1

func add_item(item_id: String) -> bool:
	var cap: int = _stack_cap(item_id)
	# Top up an existing stack before spending a fresh slot — hotbar first, then pack.
	if cap > 1:
		for i in range(HOTBAR_SIZE):
			if hotbar[i] == item_id and int(hotbar_counts[i]) < cap:
				hotbar_counts[i] = int(hotbar_counts[i]) + 1
				inventory_changed.emit()
				Journal.discover("item_" + item_id)
				return true
		for i in range(inventory.size()):
			if inventory[i] == item_id and int(inventory_counts[i]) < cap:
				inventory_counts[i] = int(inventory_counts[i]) + 1
				inventory_changed.emit()
				Journal.discover("item_" + item_id)
				return true
	# No room in an existing stack — take a fresh slot, hotbar before pack.
	for i in range(HOTBAR_SIZE):
		if hotbar[i] == null:
			hotbar[i] = item_id
			hotbar_counts[i] = 1
			inventory_changed.emit()
			Journal.discover("item_" + item_id)
			return true
	if inventory.size() >= backpack_capacity():
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Pack is full.")
		return false
	inventory.append(item_id)
	inventory_counts.append(1)
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
			# The whole stack moves as a unit, count and all.
			hotbar[i] = inventory[inv_idx]
			hotbar_counts[i] = int(inventory_counts[inv_idx])
			inventory.remove_at(inv_idx)
			inventory_counts.remove_at(inv_idx)
			inventory_changed.emit()
			return true
	return false

func hotbar_to_backpack(slot: int) -> bool:
	if slot < 0 or slot >= HOTBAR_SIZE or hotbar[slot] == null:
		return false
	if inventory.size() >= backpack_capacity():
		return false
	inventory.append(hotbar[slot])
	inventory_counts.append(int(hotbar_counts[slot]))
	hotbar[slot] = null
	hotbar_counts[slot] = 1
	inventory_changed.emit()
	return true

## Remove ONE of item_id — decrements the first stack found (hotbar before pack),
## clearing the slot only when its count hits zero. Signature unchanged: every caller
## that expected "take one away" still gets exactly that.
func remove_item(item_id: String) -> bool:
	var hotbar_idx: int = hotbar.find(item_id)
	if hotbar_idx != -1:
		_dec_hotbar(hotbar_idx)
		inventory_changed.emit()
		return true
	var inv_idx: int = inventory.find(item_id)
	if inv_idx != -1:
		_dec_inventory(inv_idx)
		inventory_changed.emit()
		return true
	return false

## Take one off a hotbar stack; empty the slot (no auto-refill) when it runs out.
func _dec_hotbar(i: int) -> void:
	var c: int = int(hotbar_counts[i]) - 1
	if c <= 0:
		hotbar[i] = null
		hotbar_counts[i] = 1
	else:
		hotbar_counts[i] = c

## Take one off a pack stack; drop the slot entirely when it runs out.
func _dec_inventory(i: int) -> void:
	var c: int = int(inventory_counts[i]) - 1
	if c <= 0:
		inventory.remove_at(i)
		inventory_counts.remove_at(i)
	else:
		inventory_counts[i] = c

func has_item(item_id: String) -> bool:
	return hotbar.has(item_id) or inventory.has(item_id)

## Total across every stack — for callers that need the true item count, not slots.
func count_item(item_id: String) -> int:
	var n: int = 0
	for i in range(HOTBAR_SIZE):
		if hotbar[i] == item_id:
			n += int(hotbar_counts[i])
	for i in range(inventory.size()):
		if inventory[i] == item_id:
			n += int(inventory_counts[i])
	return n

## How many sit in a given hotbar / pack slot (0 for an empty or out-of-range slot).
func hotbar_stack(slot: int) -> int:
	if slot < 0 or slot >= HOTBAR_SIZE or hotbar[slot] == null:
		return 0
	return int(hotbar_counts[slot])

func inventory_stack(idx: int) -> int:
	if idx < 0 or idx >= inventory.size():
		return 0
	return int(inventory_counts[idx])

## Drop-one plumbing for the HUD: pull a single item off a unified slot index
## (0..HOTBAR_SIZE-1 = hotbar, then the pack). Returns the id removed, or "".
func take_one_from_slot(unified_idx: int) -> String:
	if unified_idx < 0:
		return ""
	if unified_idx < HOTBAR_SIZE:
		var id: Variant = hotbar[unified_idx]
		if id == null:
			return ""
		_dec_hotbar(unified_idx)
		inventory_changed.emit()
		return String(id)
	var inv_i: int = unified_idx - HOTBAR_SIZE
	if inv_i >= inventory.size():
		return ""
	var iid: String = String(inventory[inv_i])
	_dec_inventory(inv_i)
	inventory_changed.emit()
	return iid

## Wholesale load of saved inventory, counts included. Tolerates old saves (no counts
## arrays): a missing/short counts array defaults every occupied slot to one. Called by
## SaveManager so hotbar/inventory and their counts can never drift out of length.
func load_inventory(hb: Variant, hb_counts: Variant, inv: Variant, inv_counts: Variant) -> void:
	hotbar = [null, null, null, null]
	hotbar_counts = [1, 1, 1, 1]
	if hb is Array:
		for i in range(mini((hb as Array).size(), HOTBAR_SIZE)):
			var v: Variant = (hb as Array)[i]
			hotbar[i] = String(v) if v != null else null
	inventory = []
	inventory_counts = []
	if inv is Array:
		for v in (inv as Array):
			if v == null:
				continue
			inventory.append(String(v))
			inventory_counts.append(1)
	# Overlay saved counts where present, clamped to each item's stack cap.
	if hb_counts is Array:
		for i in range(mini((hb_counts as Array).size(), HOTBAR_SIZE)):
			if hotbar[i] != null:
				hotbar_counts[i] = clampi(int((hb_counts as Array)[i]), 1, _stack_cap(hotbar[i]))
	if inv_counts is Array:
		for i in range(mini((inv_counts as Array).size(), inventory.size())):
			inventory_counts[i] = clampi(int((inv_counts as Array)[i]), 1, _stack_cap(inventory[i]))
	inventory_changed.emit()

## An upgraded tool does everything the crude one did. Without this the honed knife
## was a trap: its recipe EATS the crude knife, but every knife gate in the game
## (kelp fiber, foam block, filleting, the cleaning board, soft salvage, the float
## and kelp harvests) named "crude_knife" literally, so "upgrading" strictly removed
## capability. Read by BOTH tool checks — Salvage._has_any for world gates and
## BenchPanel.tool_ready for recipes — so an upgrade can never orphan a verb again.
const TOOL_SUPERSEDES: Dictionary = {
	"crude_knife": ["honed_knife"],
	"crude_spear": ["honed_spear"],
}

## How much the pack holds RIGHT NOW. The tool belt is worn, not spent: carrying it
## costs a slot and gives back more than it takes. Everything that asks "is there
## room" must come through here — MAX_BACKPACK is the bare-back number only.
func backpack_capacity() -> int:
	var belt: int = 0
	if has_item("tool_belt"):
		# Honour the economy agent's `pack_slots` field; TOOL_BELT_SLOTS is the fallback.
		belt = int(items.get("tool_belt", {}).get("pack_slots", TOOL_BELT_SLOTS))
	return MAX_BACKPACK + belt

## True if the player is carrying this tool, or anything that supersedes it.
func has_tool(tool_id: String) -> bool:
	if has_item(tool_id):
		return true
	for better: String in TOOL_SUPERSEDES.get(tool_id, []):
		if has_item(better):
			return true
	return false

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
		# Eat one off the stack. Only when the slot truly empties does it get refilled
		# from the pack — a stack of five cans keeps five slots' worth in one slot.
		var remaining: int = int(hotbar_counts[slot]) - 1
		if remaining > 0:
			hotbar_counts[slot] = remaining
		else:
			hotbar[slot] = null
			hotbar_counts[slot] = 1
			if not inventory.is_empty():
				hotbar[slot] = inventory.pop_front()
				hotbar_counts[slot] = int(inventory_counts.pop_front())
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
