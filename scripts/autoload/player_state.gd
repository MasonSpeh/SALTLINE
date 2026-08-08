extends Node
## Owns survival stats (hunger, thirst, warmth, life) + inventory/hotbar. Depletion rates
## come from data/tuning.json (A1: no magic numbers) — hunger and thirst are the one
## exception, and HUNGER_PER_SEC says why. Consequences stay soft until life bottoms out —
## then player_died fires and the controller runs a blackout respawn.

signal hunger_changed(value: float)
signal thirst_changed(value: float)
signal warmth_changed(value: float)
signal life_changed(value: float)
signal oxygen_changed(value: float)
signal rest_changed(value: float)
signal comfort_changed(value: float)
signal player_died
signal stat_low(stat_name: String)
signal stat_recovered(stat_name: String)
signal inventory_changed
signal item_eaten(item_id: String)

const LOW_THRESHOLD: float = 0.5
## Owner call, 2026-07-27: 4 -> 6 hotbar slots and 12 -> 18 base pack slots (both +6). Every
## other place that used to hand-type "[null, null, null, null]" or "[1, 1, 1, 1]" now builds
## off this constant instead (see _new_hotbar()/_new_hotbar_counts() below) — the old literals
## were exactly the kind of silently-stale duplication this codebase's own comments warn
## about elsewhere (e.g. the crab pack count probes), and a second hand-typed 6-long array
## would only have moved the staleness forward instead of fixing it.
const HOTBAR_SIZE: int = 6
const MAX_BACKPACK: int = 18   ## a day pack, not a warehouse — but a bigger one now
## Same-id items pile into one slot up to this many — food, kits, materials and salvage
## all stack, so a night's fishing is one slot instead of sixteen. Held/worn equipment
## is the exception (see EQUIPMENT below): a wrench is a wrench, you carry one.
const MAX_STACK: int = 16
## Worn gear that actually does something. These are the ONLY numbers behind the
## three upgrade crafts — without them the recipes promised mechanics that did not
## exist anywhere in the codebase.
const TOOL_BELT_SLOTS: int = 4        ## canvas pockets: four more things you can carry
const BOOTS_COLD_RELIEF: float = 0.45 ## dry feet: cold bites 45% slower through them

const LIFE_DRAIN_PER_SEC: float = 0.02   ## while starving or parched
const LIFE_REGEN_PER_SEC: float = 0.01   ## while fed, watered, and not too sick

## Hunger and thirst depletion, both cut 15% from the first tuning pass: the survival clock
## was asking for a meal and a drink more often than the rig hands you either one, so it read
## as book-keeping rather than pressure.
##
## Hunger and thirst were cut 15% (2026-07-25) because the survival clock was outrunning the
## exploration. The reduced rates live in data/tuning.json like every other feel-value — these
## constants are only the fallbacks used if the file is missing a key, and they are kept
## numerically IDENTICAL to it so the two can never quietly disagree.
const HUNGER_PER_SEC: float = 0.0004675   ## was 0.00055 (x0.85)
const THIRST_PER_SEC: float = 0.000935    ## was 0.0011  (x0.85)

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
## Breath while submerged. Driven entirely by player_controller (drains under water,
## refills at the surface / on land); NOT part of the depletion clock and NOT saved —
## it always comes back full the moment you're breathing air.
var oxygen: float = 1.0 : set = set_oxygen
var rest: float = 1.0 : set = set_rest
var comfort: float = 0.0 : set = set_comfort
var hotbar: Array = _new_hotbar()
## Overflow slots beyond the hotbar. A SPARSE grid, not a packed list (owner call,
## 2026-07-27c): a cell the player deliberately left empty holds null, so "put this in THAT
## square" can be honoured literally instead of collapsing to the first free slot. Two
## invariants keep that from leaking out to the dozens of `for it in inventory` readers
## elsewhere in the game:
##   · trailing nulls are always trimmed (see _trim_pack), so a pack that empties out is
##     `[]` again and `inventory.size()` never counts phantom tail slots;
##   · a null is only ever an EMPTY square — every reader that compares against an item id
##     simply doesn't match it, and everything in this file that counts, fills or indexes
##     the pack goes through the null-aware helpers below.
var inventory: Array = []
## How many sit in each slot. Parallel to hotbar/inventory rather than folded into
## them, so every existing caller that reads `hotbar[i]` / iterates `inventory` still
## sees a plain item id (or null) — the count rides alongside. Counts are only ever
## meaningful where the matching slot holds an id; a null slot's count is ignored.
var hotbar_counts: Array = _new_hotbar_counts()
var inventory_counts: Array = [] ## parallel to inventory, one int per stack
## WHAT THIS PARTICULAR ONE IS. A third parallel array, for exactly the reason the counts
## are parallel rather than folded into the slots (see above): every one of the ~196 direct
## `hotbar[i]` / `for it in inventory` reads across the scripts and the tests still sees a
## plain item id or a null, and the payload rides alongside.
##
## A slot's meta is a Dictionary of whatever makes THIS instance not interchangeable with
## another of the same id — today only `{"kg": float}`, the weight one big fish was landed
## at (FishTable.catch_meta) — or null for the ordinary case, which is nearly every slot.
##
## THE ONE RULE: a slot carrying a payload stacks to ONE (see is_stackable). Two groupers of
## 41.5 and 12.0 kg are not the same object and cannot share a count. "A big fish gets its
## own slot" is therefore a CONSEQUENCE of carrying a weight, not a second special case
## bolted on beside EQUIPMENT — and a species that carries no weight (a herring, a can of
## peaches) piles to MAX_STACK exactly as it always did.
var hotbar_meta: Array = _new_hotbar_meta()
var inventory_meta: Array = [] ## parallel to inventory, Dictionary|null per slot
## Which hotbar slot is in hand (-1 = empty hands). Written from several places — the
## number keys, the inventory panel's place-into-hotbar, scripted setups — so it carries a
## setter that announces itself rather than making every writer remember to tell the HUD.
## Deliberately fires on EVERY assignment, not just a changed value: pressing the same
## number again is a re-select, and the HUD's name popup is expected to restart on it.
signal hotbar_selection_changed(slot: int)
var selected_hotbar: int = -1 : set = set_selected_hotbar

func set_selected_hotbar(slot: int) -> void:
	selected_hotbar = slot
	hotbar_selection_changed.emit(slot)

## Environmental warmth modifier, set by cold/heat zones: -1 cold, 0 neutral, +1 heated.
var warmth_zone: int = 0
## How many FLAME heat sources the player is standing in right now — braziers, fire barrels,
## the hearth, the barrel stove, the galley range. A subset of the +1 zones counted above (a
## lean-to and a bedroll warm you but are not fires), maintained by the same additive
## enter/exit contract. Feeds `warmth_fire_rate_mult` in _process.
var warmth_fire: int = 0
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
	hunger -= float(tuning.get("hunger_per_sec", HUNGER_PER_SEC)) * delta * ease
	thirst -= float(tuning.get("thirst_per_sec", THIRST_PER_SEC)) * delta * ease
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
	# STANDING AT A FIRE OR A STOVE WARMS YOU FASTER. Owner, 2026-07-30: "Have warmth increase
	# 30% faster rate when standing by stove/fire." Only the gaining direction is multiplied —
	# a flame you are standing next to cannot make you lose heat more slowly than a cold zone
	# says you do, and the shelter zones (lean-to, bedroll, windbreak) keep the plain rate.
	# The number lives in data/tuning.json with every other feel value, not here.
	if w_rate > 0.0 and warmth_fire > 0:
		w_rate *= float(tuning.get("warmth_fire_rate_mult", 1.30))
	# Patched boots only help against LOSING heat — they are insulation, not a fire,
	# so they never slow you warming up at a brazier. The relief fraction is the
	# economy agent's `cold_relief` field on the item, not a hard-coded number, so a
	# tuning pass on the boots needs no code change; BOOTS_COLD_RELIEF is the fallback.
	if w_rate < 0.0 and has_item("patched_boots"):
		var relief: float = float(items.get("patched_boots", {}).get("cold_relief", BOOTS_COLD_RELIEF))
		w_rate *= (1.0 - relief)
	warmth += w_rate * delta
	sickness = maxf(0.0, sickness - delta * 0.15)  # recover from sickness over time
	# Clamp all drainable stats to valid range so they never drift and degrade speed over time.
	hunger = clampf(hunger, 0.0, 1.0)
	thirst = clampf(thirst, 0.0, 1.0)
	warmth = clampf(warmth, 0.0, 1.0)
	rest = clampf(rest, 0.0, 1.0)
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

func set_oxygen(value: float) -> void:
	oxygen = clampf(value, 0.0, 1.0)
	oxygen_changed.emit(oxygen)

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

## Genuine one-of-a-kind EQUIPMENT — the things you hold, wear or operate. Only these
## refuse to stack. The old rule was `use != "tool"`, but items.json tags every raw
## MATERIAL as a "tool" too (rope, driftwood, scrap_metal, steel_plate, bolt_handful...),
## so the exact things a scavenger hoards sixteen of were the ones locked to one per
## slot. Materials, salvage yields, flares and kits all pile to MAX_STACK now.
const EQUIPMENT := {
	"fishing_rod": true, "prybar": true, "throwing_hook": true,
	"crude_knife": true, "crude_spear": true, "honed_knife": true, "honed_spear": true,
	"wrench": true, "hammer_tool": true, "spanner": true, "screwdriver": true,
	"hand_file": true, "hacksaw": true, "tool_belt": true,
	"storm_lantern": true, "flashlight": true, "patched_boots": true,
	"life_ring": true, "mini_anchor": true, "cable_spool": true,
}

## How tall a stack of this item may grow. Three tiers, in order:
##   · a slot carrying a PAYLOAD stacks to one — a 41.5 kg grouper is a specific animal and
##     merging it into a pile would erase which one it was (see hotbar_meta);
##   · EQUIPMENT never stacks (a wrench is a wrench);
##   · everything else — food, drink, kits, materials, flares — piles to MAX_STACK.
## `meta` defaults to null so every existing caller keeps the species-level answer.
func is_stackable(item_id: String, meta: Variant = null) -> bool:
	if not meta_empty(meta):
		return false
	return not EQUIPMENT.has(item_id)

## True when a payload is "nothing at all" — null, an empty dict, or something that is not
## a dict. The one test every meta read goes through, so no caller has to know the shape.
static func meta_empty(m: Variant) -> bool:
	return typeof(m) != TYPE_DICTIONARY or (m as Dictionary).is_empty()

## A payload as a plain Dictionary ({} when there is none). COPIED, never the live slot
## dict: a caller that stores what it was handed must not be able to reach back into the
## pack and rewrite a slot through it.
static func as_meta(m: Variant) -> Dictionary:
	return (m as Dictionary).duplicate(true) if not meta_empty(m) else {}

## What a payload is stored AS in a slot: null when empty, a private copy otherwise. Nulls
## rather than empty dicts so `hotbar_meta` reads the same way `hotbar` does.
static func _store_meta(m: Variant) -> Variant:
	return (m as Dictionary).duplicate(true) if not meta_empty(m) else null

## A freshly emptied hotbar: HOTBAR_SIZE slots, every one null. Array.resize() on a brand
## new array leaves every element null already — spelled out anyway so a reader doesn't
## have to know that.
static func _new_hotbar() -> Array:
	var a: Array = []
	a.resize(HOTBAR_SIZE)
	return a

static func _new_hotbar_counts() -> Array:
	var a: Array = []
	a.resize(HOTBAR_SIZE)
	a.fill(1)
	return a

## Array.resize() leaves every element null, which is exactly "no payload" — spelled out
## the same way _new_hotbar() is so a reader does not have to know that.
static func _new_hotbar_meta() -> Array:
	var a: Array = []
	a.resize(HOTBAR_SIZE)
	return a

func _stack_cap(item_id: String, meta: Variant = null) -> int:
	return MAX_STACK if is_stackable(item_id, meta) else 1

# ---------------------------------------------------------------- pack slots
# The pack is a sparse grid (see `inventory`). These four helpers are the only places that
# know it, so no caller outside this file has to.

## Drop empty tail cells so an emptied pack is `[]` again and `inventory.size()` stays a
## meaningful "how far the grid is used". Called after anything that vacates a cell.
## KEEP THE PAYLOAD ARRAYS THE LENGTH OF THE SLOTS THEY SHADOW.
##
## A short one is a NORMAL state here, not a corruption to assert on: scripted setups and
## the test harnesses append straight into `inventory`/`inventory_counts`
## (tests/test_runner.gd:326 and a dozen more) and know nothing about a third array. Rather
## than chase every one of those — and leave the next one to trip over it — every function
## that indexes a payload fits the arrays first, and a missing entry simply reads as
## "carrying nothing", which is what a hand-placed item is.
func _fit_meta() -> void:
	if hotbar_meta.size() != HOTBAR_SIZE:
		hotbar_meta.resize(HOTBAR_SIZE)
	if inventory_meta.size() != inventory.size():
		inventory_meta.resize(inventory.size())

func _trim_pack() -> void:
	_fit_meta()
	while not inventory.is_empty() and inventory[inventory.size() - 1] == null:
		inventory.remove_at(inventory.size() - 1)
		inventory_counts.remove_at(inventory_counts.size() - 1)
		inventory_meta.remove_at(inventory_meta.size() - 1)

## How many pack cells actually hold something — NOT inventory.size(), which also counts
## the gaps the player left between them.
func pack_used() -> int:
	var n: int = 0
	for it in inventory:
		if it != null:
			n += 1
	return n

## The lowest pack index nothing is sitting in, or -1 when the pack is genuinely full.
## Gaps are filled before the grid is grown, so auto-pickup still packs tight — only a
## deliberate placement puts an item past a hole.
func pack_first_free() -> int:
	for i in range(inventory.size()):
		if inventory[i] == null:
			return i
	if inventory.size() < backpack_capacity():
		return inventory.size()
	return -1

## Write a stack into an EXACT pack index, growing the grid with empty cells if the target
## sits past the end. This is what makes "put it in that square" literal.
func _pack_put(i: int, item_id: Variant, count: int, meta: Variant = null) -> void:
	_fit_meta()
	while inventory.size() <= i:
		inventory.append(null)
		inventory_counts.append(1)
		inventory_meta.append(null)
	inventory[i] = item_id
	inventory_counts[i] = count
	inventory_meta[i] = _store_meta(meta)
	if item_id == null:
		_trim_pack()

## Take one item into the pack. `meta` is what THIS one is carrying — {} for nearly
## everything, `{"kg": 41.5}` for a big fish (FishTable.catch_meta). A payload always takes
## a fresh slot, because a slot holding one cannot stack (see is_stackable).
func add_item(item_id: String, meta: Dictionary = {}) -> bool:
	_fit_meta()
	var cap: int = _stack_cap(item_id, meta)
	# Top up an existing stack before spending a fresh slot — hotbar first, then pack.
	# Only ever a stack that carries NO payload: piling a weighed fish onto a plain one
	# would be the silent weight-erasure this whole scheme exists to end.
	if cap > 1:
		for i in range(HOTBAR_SIZE):
			if hotbar[i] == item_id and meta_empty(hotbar_meta[i]) \
					and int(hotbar_counts[i]) < cap:
				hotbar_counts[i] = int(hotbar_counts[i]) + 1
				inventory_changed.emit()
				Journal.discover("item_" + item_id)
				return true
		for i in range(inventory.size()):
			if inventory[i] == item_id and meta_empty(inventory_meta[i]) \
					and int(inventory_counts[i]) < cap:
				inventory_counts[i] = int(inventory_counts[i]) + 1
				inventory_changed.emit()
				Journal.discover("item_" + item_id)
				return true
	# No room in an existing stack — take a fresh slot, hotbar before pack.
	for i in range(HOTBAR_SIZE):
		if hotbar[i] == null:
			hotbar[i] = item_id
			hotbar_counts[i] = 1
			hotbar_meta[i] = _store_meta(meta)
			inventory_changed.emit()
			Journal.discover("item_" + item_id)
			return true
	var free: int = pack_first_free()
	if free == -1:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			# Name the way out. The pack panel is where room gets made now — a full pack
			# used to be a dead end the player had to guess their way out of.
			hud.toast("Pack is full. [I] — click an item, then the empty space, to drop it.")
		return false
	_pack_put(free, item_id, 1, meta)
	inventory_changed.emit()
	Journal.discover("item_" + item_id)
	return true

## Inventory panel moves: click a pack item into a free hotbar slot, or stow a
## hotbar item back into the pack.
func backpack_to_hotbar(inv_idx: int) -> bool:
	_fit_meta()
	if inv_idx < 0 or inv_idx >= inventory.size() or inventory[inv_idx] == null:
		return false
	for i in range(HOTBAR_SIZE):
		if hotbar[i] == null:
			# The whole stack moves as a unit, count, payload and all.
			hotbar[i] = inventory[inv_idx]
			hotbar_counts[i] = int(inventory_counts[inv_idx])
			hotbar_meta[i] = inventory_meta[inv_idx]
			_pack_put(inv_idx, null, 1)
			inventory_changed.emit()
			return true
	return false

## Exchange a pack stack with a hotbar slot — the full-pack answer to backpack_to_hotbar.
## That one needs a FREE hotbar slot and simply returns false with all four occupied, which
## is what forced the player to drop (or stow) something before they could bring a pack item
## to hand. This is an in-place exchange: nothing is created, nothing is destroyed, no
## capacity is consulted, so it cannot fail on a full pack or a full hotbar.
##
## Three cases, all lossless:
##  · empty hotbar slot — the stack simply moves in and the pack slot goes away (inventory is
##    a list, not a fixed grid, so leaving a null in it would draw as a phantom item);
##  · same item both sides — pile them up to the stack cap rather than shuffling two stacks
##    of the same thing back and forth; anything over the cap stays in the pack;
##  · anything else — a straight swap, counts included.
func swap_backpack_hotbar(inv_idx: int, slot: int) -> bool:
	_fit_meta()
	if inv_idx < 0 or inv_idx >= inventory.size() or inventory[inv_idx] == null:
		return false
	if slot < 0 or slot >= HOTBAR_SIZE:
		return false
	var pack_id: String = String(inventory[inv_idx])
	var pack_n: int = int(inventory_counts[inv_idx])
	var pack_m: Variant = inventory_meta[inv_idx]
	var hand_id: Variant = hotbar[slot]
	var hand_n: int = int(hotbar_counts[slot])
	var hand_m: Variant = hotbar_meta[slot]
	# Same id on both sides piles up — but ONLY when neither side carries a payload. Two
	# weighed groupers are two animals and must stay two slots, so they fall through to the
	# plain exchange below instead of being merged into a stack of "2 × grouper, one weight".
	if hand_id != null and String(hand_id) == pack_id \
			and meta_empty(hand_m) and meta_empty(pack_m):
		var room: int = _stack_cap(pack_id) - hand_n
		var moved: int = mini(pack_n, maxi(room, 0))
		if moved > 0:
			hotbar_counts[slot] = hand_n + moved
			if pack_n - moved <= 0:
				_pack_put(inv_idx, null, 1)
			else:
				inventory_counts[inv_idx] = pack_n - moved
			inventory_changed.emit()
		return true   # a topped-out hand stack is a no-op, never a downgrade
	hotbar[slot] = pack_id
	hotbar_counts[slot] = pack_n
	hotbar_meta[slot] = pack_m
	if hand_id == null:
		_pack_put(inv_idx, null, 1)
	else:
		inventory[inv_idx] = hand_id
		inventory_counts[inv_idx] = hand_n
		inventory_meta[inv_idx] = hand_m
	inventory_changed.emit()
	return true

## Move / swap / merge the contents of ONE unified slot into another, in any direction:
## hotbar<->hotbar, pack<->pack, hotbar<->pack. Unified index = 0..HOTBAR_SIZE-1 for the
## hotbar, then HOTBAR_SIZE + i for pack entry i.
##
## Owner call, 2026-07-25b: this exists because the inventory panel had no way to express
## "put THIS there". A click on a hotbar slot dumped it at the END of the pack, and a click
## on a pack slot swapped it into whatever hotbar slot happened to be equipped — invisible
## state the player never chose. Neither hotbar->hotbar nor pack->pack reordering was
## possible AT ALL. One verb replaces all of it: pick a slot, then click the slot you want
## it in.
##
## Every case is lossless and in-place. Nothing is created or destroyed, so the only way
## this returns false is a move that means nothing (same slot, empty source, an
## out-of-range target, or a merge into a stack that is already at the cap).
##
## `inventory` is a SPARSE grid (owner call, 2026-07-27c — see the `inventory` declaration).
## Before that it was a packed list, and the difference is this whole feature: a drop onto
## any empty pack square had nowhere stable to land, so it appended, and the item appeared in
## the first free slot rather than the one the player clicked ("it refuses and instead always
## drops into the first available slot"). Now the target index is written literally, the grid
## growing empty cells beneath it if it sits past the end, and a vacated cell goes null in
## place so no index after it shifts under the player's hands.
func move_slot(from_u: int, to_u: int) -> bool:
	_fit_meta()
	if from_u == to_u or from_u < 0 or to_u < 0:
		return false
	var from_h: bool = from_u < HOTBAR_SIZE
	var to_h: bool = to_u < HOTBAR_SIZE
	var fi: int = from_u if from_h else from_u - HOTBAR_SIZE
	var ti: int = to_u if to_h else to_u - HOTBAR_SIZE
	# The source has to actually hold something.
	if from_h:
		if fi >= HOTBAR_SIZE or hotbar[fi] == null:
			return false
	elif fi >= inventory.size() or inventory[fi] == null:
		return false
	# The target has to be a slot that exists. For the pack, ANY empty square within capacity
	# is a legal target — including one well past the last occupied cell.
	if to_h:
		if ti >= HOTBAR_SIZE:
			return false
	elif ti >= backpack_capacity():
		return false

	var f_id: String = String(hotbar[fi]) if from_h else String(inventory[fi])
	var f_n: int = int(hotbar_counts[fi]) if from_h else int(inventory_counts[fi])
	var f_m: Variant = hotbar_meta[fi] if from_h else inventory_meta[fi]
	var t_id: String = ""
	var t_n: int = 0
	var t_m: Variant = null
	if to_h:
		if hotbar[ti] != null:
			t_id = String(hotbar[ti])
			t_n = int(hotbar_counts[ti])
			t_m = hotbar_meta[ti]
	elif ti < inventory.size() and inventory[ti] != null:
		t_id = String(inventory[ti])
		t_n = int(inventory_counts[ti])
		t_m = inventory_meta[ti]

	# ---- same thing on both sides: pile it up instead of shuffling two identical stacks.
	# NEITHER side may carry a payload. Dropping a 41.5 kg grouper onto a 12.0 kg one used to
	# be a merge, and a merge is where a weight would silently vanish — two counts can be
	# added, two weights cannot. Payload slots therefore fall through to the exchange below,
	# which is lossless: the two animals swap places and both keep their number.
	if t_id != "" and t_id == f_id and meta_empty(f_m) and meta_empty(t_m):
		var moved: int = mini(f_n, maxi(_stack_cap(f_id) - t_n, 0))
		if moved <= 0:
			return false      # target stack already at the cap: a no-op, not a swap
		if to_h:
			hotbar_counts[ti] = t_n + moved
		else:
			inventory_counts[ti] = t_n + moved
		if f_n - moved <= 0:
			_clear_slot(from_h, fi)
		elif from_h:
			hotbar_counts[fi] = f_n - moved
		else:
			inventory_counts[fi] = f_n - moved
		inventory_changed.emit()
		return true

	# ---- otherwise the two slots exchange contents outright. The target index is written
	# literally in both directions — that is the whole point of the sparse pack. Every write
	# below moves the payload with the count it belongs to; a branch that wrote one without
	# the other would duplicate a weight onto a fish that never had it.
	if to_h:
		hotbar[ti] = f_id
		hotbar_counts[ti] = f_n
		hotbar_meta[ti] = f_m
	else:
		_pack_put(ti, f_id, f_n, f_m)
	if t_id == "":
		_clear_slot(from_h, fi)
	elif from_h:
		hotbar[fi] = t_id
		hotbar_counts[fi] = t_n
		hotbar_meta[fi] = t_m
	else:
		inventory[fi] = t_id
		inventory_counts[fi] = t_n
		inventory_meta[fi] = t_m
	inventory_changed.emit()
	return true

## Empty one slot. Both grids go null in place; the pack then trims any empty tail, so
## indices the player can still see never shift under them but an emptied pack is still `[]`.
func _clear_slot(is_hotbar: bool, i: int) -> void:
	_fit_meta()
	if is_hotbar:
		hotbar[i] = null
		hotbar_counts[i] = 1
		hotbar_meta[i] = null
	else:
		_pack_put(i, null, 1)

func hotbar_to_backpack(slot: int) -> bool:
	_fit_meta()
	if slot < 0 or slot >= HOTBAR_SIZE or hotbar[slot] == null:
		return false
	var free: int = pack_first_free()
	if free == -1:
		return false
	_pack_put(free, hotbar[slot], int(hotbar_counts[slot]), hotbar_meta[slot])
	hotbar[slot] = null
	hotbar_counts[slot] = 1
	hotbar_meta[slot] = null
	inventory_changed.emit()
	return true

## Remove ONE of item_id — decrements the first stack found (hotbar before pack),
## clearing the slot only when its count hits zero. Signature unchanged: every caller
## that expected "take one away" still gets exactly that.
##
## IT THROWS THE PAYLOAD AWAY, which is right for a caller that does not care (laying a
## rope on the bench) and wrong for anything that then has to know what the fish weighed.
## Those use remove_one_of() / take_one_at() instead — see them.
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

## Take one off a hotbar stack; empty the slot (no auto-refill) when it runs out. A payload
## slot always holds exactly one, so it is always the emptying branch that runs — and the
## payload goes with the item rather than being left behind for whatever lands there next.
func _dec_hotbar(i: int) -> void:
	_fit_meta()
	var c: int = int(hotbar_counts[i]) - 1
	if c <= 0:
		hotbar[i] = null
		hotbar_counts[i] = 1
		hotbar_meta[i] = null
	else:
		hotbar_counts[i] = c

## Take one off a pack stack; empty the square when it runs out (and let _trim_pack collapse
## the grid if that square was the last one in use).
func _dec_inventory(i: int) -> void:
	var c: int = int(inventory_counts[i]) - 1
	if c <= 0:
		_pack_put(i, null, 1)
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
	if idx < 0 or idx >= inventory.size() or inventory[idx] == null:
		return 0
	return int(inventory_counts[idx])

## Drop-one plumbing for the HUD: pull a single item off a unified slot index
## (0..HOTBAR_SIZE-1 = hotbar, then the pack). Returns the id removed, or "".
##
## KEPT AS IT WAS, and now a thin skin over take_one_at() — a caller that only wants to know
## WHAT it removed should not have to unpack a dictionary to find out.
func take_one_from_slot(unified_idx: int) -> String:
	return String(take_one_at(unified_idx).get("id", ""))

# ------------------------------------------------------------------ slots, by index
# A unified slot index is 0..HOTBAR_SIZE-1 for the hotbar and HOTBAR_SIZE + i for pack
# entry i — the same numbering move_slot() and the inventory panel already speak. These
# are what let a consumer act on the fish the player POINTED AT instead of "the first
# stack found", which is the whole defect the size ledger's own header admitted to.

## What one unified slot holds; "" for empty or out of range.
func slot_id(unified_idx: int) -> String:
	if unified_idx < 0:
		return ""
	if unified_idx < HOTBAR_SIZE:
		return String(hotbar[unified_idx]) if hotbar[unified_idx] != null else ""
	var i: int = unified_idx - HOTBAR_SIZE
	if i >= inventory.size() or inventory[i] == null:
		return ""
	return String(inventory[i])

## What that slot's contents are CARRYING; {} when it is an ordinary item.
func slot_meta(unified_idx: int) -> Dictionary:
	_fit_meta()
	if unified_idx < 0:
		return {}
	if unified_idx < HOTBAR_SIZE:
		return as_meta(hotbar_meta[unified_idx]) if hotbar[unified_idx] != null else {}
	var i: int = unified_idx - HOTBAR_SIZE
	if i >= inventory.size() or i >= inventory_meta.size() or inventory[i] == null:
		return {}
	return as_meta(inventory_meta[i])

## The landed weight on a slot, or 0.0 — the one number every fish path actually wants.
func slot_kg(unified_idx: int) -> float:
	return float(slot_meta(unified_idx).get("kg", 0.0))

func slot_count(unified_idx: int) -> int:
	if unified_idx < 0:
		return 0
	if unified_idx < HOTBAR_SIZE:
		return hotbar_stack(unified_idx)
	return inventory_stack(unified_idx - HOTBAR_SIZE)

## Every unified slot holding this id, hotbar first then pack, in the order the player
## sees them.
func slots_of(item_id: String) -> Array[int]:
	var out: Array[int] = []
	for i in range(HOTBAR_SIZE):
		if hotbar[i] == item_id:
			out.append(i)
	for i in range(inventory.size()):
		if inventory[i] == item_id:
			out.append(HOTBAR_SIZE + i)
	return out

## WHICH one of several identical-looking stacks a by-id caller should act on. -1 = none.
##   "first"    — hotbar before pack, exactly the order remove_item() has always used;
##   "plain"    — the first stack carrying NO payload, so a bulk crate-stow of "3 × rope"
##                cannot reach past them and post the one weighed fish;
##   "smallest" — the lightest instance. THE TROPHY RULE: anything that eats a fish it was
##                not pointed at (the bench's family tokens) must eat the small one.
##   "largest"  — the heaviest, for symmetry; nothing uses it yet.
## "plain" and "smallest"/"largest" fall back to "first" when nothing better exists.
func find_slot_of(item_id: String, pick: String = "first") -> int:
	var slots: Array[int] = slots_of(item_id)
	if slots.is_empty():
		return -1
	match pick:
		"plain":
			for u in slots:
				if slot_meta(u).is_empty():
					return u
		"smallest", "largest":
			var best: int = slots[0]
			var best_kg: float = slot_kg(best)
			for u in slots:
				var kg: float = slot_kg(u)
				if (kg < best_kg) if pick == "smallest" else (kg > best_kg):
					best = u
					best_kg = kg
			return best
	return slots[0]

## Take ONE item out of an exact slot and hand back what it was carrying.
## {"ok": bool, "id": String, "meta": Dictionary} — `meta` is {} for ordinary items, and
## for a big fish it is the payload of THAT fish, not of the oldest one on a species queue.
func take_one_at(unified_idx: int) -> Dictionary:
	_fit_meta()
	var miss: Dictionary = {"ok": false, "id": "", "meta": {}}
	if unified_idx < 0:
		return miss
	if unified_idx < HOTBAR_SIZE:
		if hotbar[unified_idx] == null:
			return miss
		var out: Dictionary = {"ok": true, "id": String(hotbar[unified_idx]),
			"meta": as_meta(hotbar_meta[unified_idx])}
		_dec_hotbar(unified_idx)
		inventory_changed.emit()
		return out
	var inv_i: int = unified_idx - HOTBAR_SIZE
	if inv_i >= inventory.size() or inventory[inv_i] == null:
		return miss
	var got: Dictionary = {"ok": true, "id": String(inventory[inv_i]),
		"meta": as_meta(inventory_meta[inv_i]) if inv_i < inventory_meta.size() else {}}
	_dec_inventory(inv_i)
	inventory_changed.emit()
	return got

## REMOVE ONE, AND TELL ME WHAT IT WAS. The by-id counterpart of take_one_at, and the
## replacement for every `remove_item(id)` that then had to guess the weight off a species
## queue. Same default order remove_item uses; `pick` chooses between duplicates (see
## find_slot_of). {"ok": bool, "id": String, "meta": Dictionary}.
func remove_one_of(item_id: String, pick: String = "first") -> Dictionary:
	return take_one_at(find_slot_of(item_id, pick))

## Wholesale load of saved inventory — counts and payloads included. Tolerates old saves
## (no counts arrays, no meta arrays): a missing/short array defaults every occupied slot
## to one, carrying nothing. Called by SaveManager so hotbar/inventory and their two
## parallel arrays can never drift out of length.
## Returns the SURPLUS it could not seat: `[{"id": String, "meta": Dictionary}]`, one entry
## per item, empty in every ordinary case. See _seat_surplus for why that can happen at all
## and why it is returned rather than clamped away.
func load_inventory(hb: Variant, hb_counts: Variant, inv: Variant, inv_counts: Variant,
		hb_meta: Variant = [], inv_meta: Variant = []) -> Array:
	hotbar = _new_hotbar()
	hotbar_counts = _new_hotbar_counts()
	hotbar_meta = _new_hotbar_meta()
	if hb is Array:
		for i in range(mini((hb as Array).size(), HOTBAR_SIZE)):
			var v: Variant = (hb as Array)[i]
			hotbar[i] = String(v) if v != null else null
	inventory = []
	inventory_counts = []
	inventory_meta = []
	if inv is Array:
		# Nulls are KEPT now, not skipped: the pack is a sparse grid, so a saved gap between
		# two items is part of how the player arranged their pack and has to come back where
		# they left it. The on-disk shape is unchanged — still a plain array of ids, with a
		# JSON null wherever a square is empty — so old saves (which simply have no nulls in
		# them) load exactly as they always did.
		for v in (inv as Array):
			inventory.append(String(v) if v != null else null)
			inventory_counts.append(1)
			inventory_meta.append(null)
	_trim_pack()
	# PAYLOADS BEFORE COUNTS, and that order is load-bearing: the cap a count is clamped to
	# depends on whether the slot carries one (is_stackable). Read the other way round, a
	# weighed grouper would be clamped against MAX_STACK and the split below would never fire.
	if hb_meta is Array:
		for i in range(mini((hb_meta as Array).size(), HOTBAR_SIZE)):
			if hotbar[i] != null:
				hotbar_meta[i] = _store_meta((hb_meta as Array)[i])
	if inv_meta is Array:
		for i in range(mini((inv_meta as Array).size(), inventory.size())):
			if inventory[i] != null:
				inventory_meta[i] = _store_meta((inv_meta as Array)[i])
	# Overlay saved counts, capped at what the slot may legally hold — and the excess is
	# PEELED OFF, not clamped away.
	#
	# THE SHARPEST EDGE IN THIS WHOLE FEATURE lived on the old `clampi(..., 1, cap)` here.
	# The moment a big fish's cap dropped from 16 to 1, an existing save holding "5 ×
	# grouper" in one square would have loaded as ONE grouper: four fish deleted, silently,
	# with no error and nothing in the log. A clamp is the right shape for a corrupt number
	# and exactly the wrong shape for a stack that was legal when it was written.
	var over: Array = []
	if hb_counts is Array:
		for i in range(mini((hb_counts as Array).size(), HOTBAR_SIZE)):
			if hotbar[i] == null:
				continue
			var want: int = maxi(int((hb_counts as Array)[i]), 1)
			var cap: int = _stack_cap(hotbar[i], hotbar_meta[i])
			hotbar_counts[i] = mini(want, cap)
			for _k in range(want - cap):
				over.append({"id": String(hotbar[i]), "meta": as_meta(hotbar_meta[i])})
	if inv_counts is Array:
		for i in range(mini((inv_counts as Array).size(), inventory.size())):
			if inventory[i] == null:
				continue
			var iwant: int = maxi(int((inv_counts as Array)[i]), 1)
			var icap: int = _stack_cap(inventory[i], inventory_meta[i])
			inventory_counts[i] = mini(iwant, icap)
			for _k in range(iwant - icap):
				over.append({"id": String(inventory[i]), "meta": as_meta(inventory_meta[i])})
	var spilled: Array = _seat_surplus(over)
	inventory_changed.emit()
	return spilled

## Find real slots for items peeled off an over-cap stack. Hotbar holes first, then pack
## holes, then the pack's growable tail — the same order add_item() fills, but WITHOUT its
## stack-merging step, because a peeled item is only ever peeled because it could not share
## a slot. Whatever still has nowhere to go is handed back to the caller; SaveManager sets
## it down on the deck (see load_game), which is this codebase's standing answer to "the
## pack is full and the item must not vanish" — the same one the stove, the drying line and
## the rod's full-pack spill already give.
func _seat_surplus(items_over: Array) -> Array:
	_fit_meta()
	var left: Array = []
	for entry in items_over:
		var id: String = String((entry as Dictionary).get("id", ""))
		if id == "":
			continue
		var meta: Dictionary = as_meta((entry as Dictionary).get("meta", {}))
		var placed: bool = false
		for i in range(HOTBAR_SIZE):
			if hotbar[i] == null:
				hotbar[i] = id
				hotbar_counts[i] = 1
				hotbar_meta[i] = _store_meta(meta)
				placed = true
				break
		if placed:
			continue
		var free: int = pack_first_free()
		if free == -1:
			left.append({"id": id, "meta": meta})
			continue
		_pack_put(free, id, 1, meta)
	return left

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
		_fit_meta()
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
		# A few cooked meals (escargot) also settle the nerves a little — the same
		# comfort stat ComfortFurniture drives, just nudged directly.
		if def.has("comfort"):
			comfort += def.get("comfort", 0.0)
		# Eat one off the stack. Only when the slot truly empties does it get refilled
		# from the pack — a stack of five cans keeps five slots' worth in one slot.
		var remaining: int = int(hotbar_counts[slot]) - 1
		if remaining > 0:
			hotbar_counts[slot] = remaining
		else:
			hotbar[slot] = null
			hotbar_counts[slot] = 1
			hotbar_meta[slot] = null
			# Refill the hand from the pack's first OCCUPIED square (the grid is sparse now,
			# so the front cell may legitimately be an empty one the player left). The
			# payload comes with it — a stack that refills into the hand is the same objects
			# in a different square.
			for i in range(inventory.size()):
				if inventory[i] == null:
					continue
				hotbar[slot] = inventory[i]
				hotbar_counts[slot] = int(inventory_counts[i])
				hotbar_meta[slot] = inventory_meta[i]
				_pack_put(i, null, 1)
				break
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
