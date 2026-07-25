class_name ItemEffects extends Node
## The consumable effects data/items.json declares that PlayerState.use_hotbar does
## NOT implement: heal (life), cures (sickness), warmth, and returns (the empty vessel
## a drink leaves behind).
##
## use_hotbar owns hunger / thirst / comfort / side_effect and then emits item_eaten.
## This node listens for that one signal and applies the rest, so a bandage, a medkit,
## a bloom tonic and a bottle of rainwater are all used through exactly the same
## "select the slot, press it again" path as a tin of peaches — no new input, no new UI,
## and no change to the survival autoload.
##
## Every field is optional. An item that declares none of them costs nothing here.
##
## MOUNTED BY main.gd, as one explicit line in _ready(). It briefly self-mounted off the
## first call into SalvageTable/Structures instead, which made healing quietly conditional
## on the player having salvaged or built something that session — a real bug waiting on an
## unrelated code path. `ensure()` is kept below because it is idempotent and harmless, but
## the scene is the owner: if you add another entry point, mount it there too rather than
## hanging it off a data-table lookup.

## The one thing `cures` currently knows how to clear.
const SICK: String = "sickness"

## Our own script, by path — NEVER the bare class_name. Godot's global class cache lags
## newly-created class_name files, so `ItemEffects.new()` in here does not resolve on the
## run that first compiles this file (same reason rig_superstructure.gd preloads
## stair_kit.gd by path). load() is a runtime lookup that hits the resource cache, so it
## costs nothing and cannot form a compile-time cycle with itself.
const SELF_PATH: String = "res://scripts/components/item_effects.gd"

static var _mounted: bool = false

## Put the single effects node in the tree if it isn't there yet. Safe to call from
## anywhere, any number of times, including from a static table lookup before the first
## frame — the add is deferred precisely because those lookups run while the world is
## still being built, and add_child() during that is a hard error.
static func ensure() -> void:
	if _mounted:
		return
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var root: Window = (loop as SceneTree).root
	if root == null:
		return
	var script: GDScript = load(SELF_PATH) as GDScript
	if script == null:
		return
	_mounted = true
	root.add_child.call_deferred(script.new())

func _ready() -> void:
	name = "ItemEffects"
	if not PlayerState.item_eaten.is_connected(_on_item_used):
		PlayerState.item_eaten.connect(_on_item_used)

## One consumable has just been spent. Read what it promises and pay it.
func _on_item_used(item_id: String) -> void:
	var def: Dictionary = PlayerState.items.get(item_id, {})
	if def.is_empty():
		return
	var did: bool = false
	var heal: float = float(def.get("heal", 0.0))
	if heal > 0.0:
		PlayerState.life = minf(1.0, PlayerState.life + heal)
		# Not the swallow foley use_hotbar just played: tape off a roll, a seal broken.
		AudioDirector.play_one_shot("hiss", Vector3.ZERO, -22.0)
		did = true
	if String(def.get("cures", "")) == SICK and PlayerState.sickness > 0.0:
		PlayerState.sickness = 0.0
		did = true
	var warm: float = float(def.get("warmth", 0.0))
	if warm > 0.0:
		PlayerState.warmth = minf(1.0, PlayerState.warmth + warm)
		did = true
	# A drink hands the vessel back. add_item() says "Pack is full" itself if it can't.
	var back: String = String(def.get("returns", ""))
	if back != "":
		PlayerState.add_item(back)
	if not did and back == "":
		return
	# use_hotbar's generic "Ate/Drank X. Better." toast fires AFTER this signal, and
	# hud.toast() REPLACES the line rather than queueing it — so ours has to land one
	# call later or it would be the thing that gets overwritten.
	_say.call_deferred(_line(item_id, def, heal, warm, back))

## What the player is told. An item may carry its own `line`; otherwise the effects
## themselves are described, so a new consumable never needs a copy pass to be legible.
func _line(item_id: String, def: Dictionary, heal: float, warm: float, back: String) -> String:
	var own: String = String(def.get("line", ""))
	if own != "":
		return own
	var bits := PackedStringArray()
	if heal > 0.0:
		bits.append("Patched up.")
	if String(def.get("cures", "")) == SICK:
		bits.append("The queasiness lets go.")
	if warm > 0.0:
		bits.append("Warmth crawls back into your hands.")
	if back != "":
		bits.append("You keep the %s." % String(PlayerState.items.get(back, {}).get("name", back)))
	if bits.is_empty():
		bits.append(String(def.get("name", item_id)))
	return " ".join(bits)

func _say(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast(text)
