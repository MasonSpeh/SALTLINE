class_name CookStove extends Interactable
## The mess-hall range — old propane bottle, mains ignition, honest heat. COOK sears one
## raw fish from the pack into that species' own meal: a Lantern Herring becomes a Cooked
## Lantern Herring, a Barrel Grouper feeds you for days. Bigger fish feed you more.
## A caught sea-bird roasts here too. Eating stays on the hotbar like any food.
##
## "Bigger fish feed you more" is literal for the big deep species: a fish carrying a
## fillets range in data/fish.json comes off the grill as MANY portions, and how many
## depends on what that particular fish weighed when it was landed (FishTable.take_yield).
## A grouper is the point of the deep rig — 6 to 12 fillets off one fish.
##
## COOKING TAKES TIME, AND YOU CAN SEE IT. A cook is no longer an instant swap: the raw
## fish leaves the pack, the oven door lights up (emissive window + a warm OmniLight for
## the duration) and COOK_SECONDS later the meal is handed back. The glow is the whole
## point of the delay — a range you can see working from across the hall is a landmark.
##
## IT RUNS ON THE MAINS. The ignition and the fan are on the same circuit as everything
## else up here, so the range is a dead lump of steel until the breaker in 4-A is closed.
## Lose the circuit mid-cook and the raw fish comes straight back out of the oven.

# What sears into what comes from data/fish.json (cooked_to) via FishTable —
# the stove automatically knows every species the rod and net can land, and each
# now sears to its OWN cooked meal ("Cooked Lantern Herring"), not a generic fillet.
const FISH := preload("res://scripts/world/fish_table.gd")

## The rig's one lighting/services circuit — same gate the interior mains lights use.
const CIRCUIT: String = "topside_floodlights"

## How long one cook takes, in real seconds. Long enough to read as an oven doing work,
## short enough that nobody stands there resenting it.
const COOK_SECONDS: float = 6.0

## Only ever used to roll a landed weight for a fish we never saw caught (a reloaded save,
## a netted halibut) — see FishTable.take_size.
var _rng := RandomNumberGenerator.new()

# Non-fish things the range also cooks — a caught sea-bird off the deck, a cut fillet
# off the cleaning board, and room to grow. Every value here is checked against
# data/items.json at cook time (see _cooked_for), so a typo degrades to the generic
# meal instead of deleting the catch.
const EXTRA_COOK := {
	"raw_sea_bird": "cooked_sea_bird",
	"snail_live": "escargot",
	"raw_fillet": "cooked_fish",
}

## The meal every cookable falls back to when its species has no cooked_fish_<species>
## of its own in data/items.json. It is the one cooked id that has always existed.
const GENERIC_COOKED: String = "cooked_fish"

# ---- cook state ----
var _cooking: bool = false
var _timer: float = 0.0
var _cook_raw: String = ""      ## what went in (handed back if the power drops)
var _cook_out: String = ""      ## what comes out
var _cook_n: int = 1            ## how many portions this fish earned
var _cook_kg: float = 0.0
var _cook_at: Vector3 = Vector3.ZERO   ## where to set surplus down (the cook's feet)

# ---- the visible oven ----
var _glass: StandardMaterial3D = null
var _oven_light: OmniLight3D = null

## What a raw item cooks into ("" = not cookable). Fish come from the table; a few
## non-fish foods (gull, cut fillet) are handled here without polluting the fish data.
##
## The result is VALIDATED against the live item list: data/fish.json names a cooked_to
## for every species, but only the species that earned one have a cooked_fish_<species>
## entry in data/items.json — the deep oddities (hagfish, oarfish, coelacanth and the
## rest) resolve to the generic meal. Anything that resolves to an id the game does not
## actually have falls back to GENERIC_COOKED rather than cooking a fish into nothing.
func _cooked_for(id: String) -> String:
	var c: String = FISH.cooked_for(id)
	if c == "":
		c = String(EXTRA_COOK.get(id, ""))
	if c == "":
		return ""
	if not PlayerState.items.has(c):
		return GENERIC_COOKED if PlayerState.items.has(GENERIC_COOKED) else ""
	return c

func _init() -> void:
	display_name = "Dining Hall Range"
	var v: Array[String] = ["COOK"]
	verbs = v
	_rng.randomize()

func _ready() -> void:
	# The oven front. rig_builder gives this node a 1.3 x 1.0 x 1.2 box visual centred on
	# the origin, standing against the servery counter with its face toward the hall (-Z),
	# so the door lives on the local -Z face at z -0.6. Built here rather than there so the
	# glass the cook lights up and the lamp behind it stay with the component that drives them.
	var steel: Material = MatLib.dark_metal()
	_panel(Vector3(0.0, -0.14, -0.612), Vector3(1.08, 0.60, 0.03), steel)          # door
	_panel(Vector3(0.0, 0.20, -0.628), Vector3(1.00, 0.05, 0.06), MatLib.galvanized())  # handle
	for hy in [-0.40, 0.10]:                                                        # hinges
		_panel(Vector3(-0.52, hy, -0.628), Vector3(0.05, 0.10, 0.05), MatLib.galvanized())
	# The window. Cold it is near-black glass; a cook swaps it for a self-lit ember orange.
	# Built by hand rather than through MatLib.flat(): MatLib CACHES its materials, and a
	# material this node mutates every cook must not be the same resource some other box
	# on the rig is drawn with.
	_glass = StandardMaterial3D.new()
	_glass.roughness = 0.35
	_glass.albedo_color = Color(0.07, 0.06, 0.055)
	_panel(Vector3(0.0, -0.16, -0.632), Vector3(0.80, 0.34, 0.02), _glass)
	# The heat itself. Dead until a cook starts, killed the moment it ends.
	_oven_light = OmniLight3D.new()
	_oven_light.light_color = Color(1.0, 0.58, 0.22)
	_oven_light.light_energy = 1.7
	_oven_light.omni_range = 4.5
	_oven_light.shadow_enabled = false
	_oven_light.visible = false
	add_child(_oven_light)
	_oven_light.position = Vector3(0.0, -0.05, -0.45)
	set_process(false)
	# A range is a fixture bolted to the deck with an oven door on its front face; the
	# placement audit must not go hunting for a surface under its trim.
	add_to_group("placement_exempt")
	# Nothing about the range should stop working when the lights go out mid-cook without
	# the player being told why — that is what _lost_power says.
	PowerGrid.circuit_lost.connect(_on_circuit_lost)

## One piece of oven trim: drawn, never collided (the interactable's own box already
## carries the collider) and never shadow-casting.
func _panel(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = pos
	return mi

func _powered() -> bool:
	return PowerGrid.is_powered(CIRCUIT)

## No verb while the oven is working — the prompt reports the cook instead, so the
## player is never offered a second cook on a range that is already busy.
func available_verbs() -> Array[String]:
	if _cooking:
		return [] as Array[String]
	return verbs

func get_prompt() -> String:
	if _cooking:
		return "Cooking…  %s (%ds)" % [display_name, int(ceilf(_timer))]
	if not _powered():
		return "COOK  %s (no power)" % display_name
	return super.get_prompt()

func interact(verb: String, player: Node3D) -> void:
	if verb != "COOK" or _cooking:
		return
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not _powered():
		if hud:
			hud.toast("The range is dead. Nothing on this circuit runs until 4-A is closed.")
		return
	var raw: String = _first_raw()
	if raw == "":
		if hud:
			hud.toast("Nothing raw to cook. The pan waits.")
		return
	var cooked: String = _cooked_for(raw)
	if cooked == "":
		if hud:
			hud.toast("Nothing raw to cook. The pan waits.")
		return
	# How much fish is on the board. Asked once, HERE, as the fish goes in — the weight
	# belongs to this fish and the ledger must not hand it to another while it cooks.
	var cut: Dictionary = FISH.take_yield(raw, _rng)
	PlayerState.remove_item(raw)
	_cooking = true
	_timer = COOK_SECONDS
	_cook_raw = raw
	_cook_out = cooked
	_cook_n = maxi(int(cut["n"]), 1)
	_cook_kg = float(cut["kg"])
	_cook_at = player.global_position if player != null else global_position
	_set_hot(true)
	AudioDirector.play_one_shot("hiss", global_position, -10.0)
	if hud:
		hud.toast("On the heat: %s" % PlayerState.items.get(raw, {}).get("name", raw))
	set_process(true)
	super.interact(verb, player)

func _process(delta: float) -> void:
	if not _cooking:
		set_process(false)
		return
	_timer -= delta
	if _timer <= 0.0:
		_finish()

## Power cut mid-cook: the oven goes cold and the fish comes back out raw rather than
## silently evaporating in a dead box.
func _on_circuit_lost(id: String) -> void:
	if id != CIRCUIT or not _cooking:
		return
	var raw: String = _cook_raw
	_clear()
	if not PlayerState.add_item(raw):
		SaveManager.drop_into_world(raw, _cook_at, Vector3.ZERO)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("The range dies mid-cook. You pull the fish back out raw.")

func _finish() -> void:
	var cooked: String = _cook_out
	var raw: String = _cook_raw
	var want: int = _cook_n
	var kg: float = _cook_kg
	var feet: Vector3 = _cook_at
	_clear()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	# The rest of the fish. add_item takes one at a time and refuses when the pack is full
	# (a species stacks to PlayerState.MAX_STACK = 16, so a whole grouper fits one slot when
	# there is a slot), so the surplus is SET DOWN on the deck as a real, savable
	# Takeable — twelve fillets must never cost the player eleven of them.
	var packed: int = 0
	var floored: int = 0
	for _i in range(want):
		if PlayerState.add_item(cooked):
			packed += 1
		else:
			var toss := Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
			SaveManager.drop_into_world(cooked, feet, toss)
			floored += 1
	AudioDirector.play_one_shot("hiss", global_position, -10.0)
	Journal.discover("system_stove")
	if hud:
		var raw_name: String = PlayerState.items.get(raw, {}).get("name", raw)
		var cooked_name: String = PlayerState.items.get(cooked, {}).get("name", cooked)
		if want <= 1:
			hud.toast("Seared: %s → %s" % [raw_name, cooked_name])
		else:
			var tail: String = "" if floored == 0 else " (%d set down — pack's full)" % floored
			hud.toast("Broke down a %.1f kg %s: %d × %s%s" % [kg, raw_name, packed + floored, cooked_name, tail])

func _clear() -> void:
	_cooking = false
	_timer = 0.0
	_cook_raw = ""
	_cook_out = ""
	_cook_n = 1
	_cook_kg = 0.0
	set_process(false)
	_set_hot(false)

## The visible half of a cook: the oven window goes from cold glass to self-lit ember,
## and the lamp behind it throws warm light out across the mess floor.
func _set_hot(hot: bool) -> void:
	if is_instance_valid(_oven_light):
		_oven_light.visible = hot
	if _glass != null:
		if hot:
			_glass.albedo_color = Color(1.0, 0.55, 0.18)
			_glass.emission_enabled = true
			_glass.emission = Color(1.0, 0.52, 0.16)
			_glass.emission_energy_multiplier = 2.4
		else:
			_glass.albedo_color = Color(0.07, 0.06, 0.055)
			_glass.emission_enabled = false

func _first_raw() -> String:
	# What is in your hand first, then the rest of the belt, then the pack — the same
	# order the drying line uses, so "cook the fish I'm holding" always does that.
	var sel: int = PlayerState.selected_hotbar
	if sel >= 0 and sel < PlayerState.HOTBAR_SIZE and PlayerState.hotbar[sel] != null \
			and _cooked_for(String(PlayerState.hotbar[sel])) != "":
		return String(PlayerState.hotbar[sel])
	for it in PlayerState.hotbar:
		if it != null and _cooked_for(String(it)) != "":
			return String(it)
	# The pack is a SPARSE array — a deliberately-empty square holds null, and interior
	# holes persist — so it needs the same null guard the belt does. Without it a cook
	# with a gap in the pack calls String(null) on the hole.
	for it in PlayerState.inventory:
		if it != null and _cooked_for(String(it)) != "":
			return String(it)
	return ""
