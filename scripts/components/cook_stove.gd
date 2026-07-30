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
	# s21 — the reef's mussel beds. Raw they are a mouthful of cold shellfish that makes you
	# ill; boiled they are a real meal. See POT below for why this one is not a sear.
	"mussels": "mussels_boiled",
}

## WHAT GOES IN THE POT INSTEAD OF THE OVEN.
##
## The owner was specific about the mussels: "It needs to be boiled (on pot on top of stove)
## to eat good" — the hob, not the oven interior. Two ways to honour that were on the table
## and this is the one that got built, deliberately:
##
##   * a second interactable POT prop with its own cook cycle was rejected. The interaction
##     ray only ever sees the FIRST collider it hits (interaction_ray.gd), so a pot standing
##     on the range would fight the range for the prompt at exactly the distance a player
##     stands to use either — and it would have to re-implement the power gate, the
##     mid-cook power loss that hands the food back raw, the pack-full spill and the timer,
##     all of which this file already has and all of which are the same for a boil.
##   * so the RANGE keeps the interaction and the pot becomes the range's own geometry
##     (built below, in the stove's local space — the galley dressing used to drop an inert
##     CSG cylinder on the left hob, and that is the object this replaces). What the player
##     sees is genuinely different from a sear: the hob lights, the water in the pot comes up
##     to a rolling boil, steam lifts off it, and the oven window stays cold and dark. The
##     verb reads BOIL, and the toast says boiled.
const POT := {"mussels": true}

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

# ---- the visible pot on the hob (see POT) ----
var _pot_water: MeshInstance3D = null      ## the surface that rises and rolls while boiling
var _pot_water_mat: StandardMaterial3D = null
var _hob_mat: StandardMaterial3D = null    ## the burner ring under the pot
var _steam: Array = []                     ## [MeshInstance3D] wisps lifting off the water
var _boiling: bool = false                 ## true while THIS cook is a boil, not a sear
var _boil_t: float = 0.0                   ## rolling-boil animation clock
## Where the water sits at rest and how far it lifts when it comes to the boil, in the
## stove's local space. The pot is 0.24 tall standing on the hob at local y 0.52.
const POT_LOCAL := Vector3(-0.3, 0.52, -0.3)
const POT_R: float = 0.2
const POT_H: float = 0.24
## How far up the pot the water sits. High, because the cook's eye is only ~0.5 m above the
## rim: at 0.62 the surface was buried in shadow behind the wall of the pot and the boil was
## invisible from the one place the player ever stands.
const WATER_F: float = 0.82

## What a raw item cooks into ("" = not cookable). Fish come from the table; a few
## non-fish foods (gull, cut fillet) are handled here without polluting the fish data.
##
## The result is VALIDATED against the live item list: data/fish.json names a cooked_to
## for every species, but only the species that earned one have a cooked_fish_<species>
## entry in data/items.json — the deep oddities (hagfish, coelacanth and the
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
	_build_pot()
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

## THE POT, on the left hob. Cold it is a dull steel pot of still dark water — the same
## silhouette the galley dressing used to draw with a CSG cylinder, in the same place. Hot it
## is the whole boil: the burner ring under it glows, the water lifts and rolls, and four
## wisps of steam climb off the surface.
##
## Every material here is built by hand rather than through MatLib, for the reason the oven
## glass already documents: MatLib CACHES, and a material this node mutates on every cook
## must not be the resource some other box on the rig is drawn with.
func _build_pot() -> void:
	# The burner ring. Its own material because it lights up.
	_hob_mat = StandardMaterial3D.new()
	_hob_mat.albedo_color = Color(0.09, 0.09, 0.10)
	_hob_mat.roughness = 0.85
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = POT_R + 0.02
	rm.bottom_radius = POT_R + 0.02
	rm.height = 0.02
	rm.material = _hob_mat
	ring.mesh = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position = POT_LOCAL
	# The pot body, sitting on the ring. dark_metal rather than painted_steel: the painted
	# variant photographed as a bucket of set cement on the hob, which is not a stockpot.
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = POT_R
	bm.bottom_radius = POT_R * 0.94
	bm.height = POT_H
	bm.material = MatLib.dark_metal()
	body.mesh = bm
	add_child(body)
	body.position = POT_LOCAL + Vector3(0.0, POT_H * 0.5 + 0.01, 0.0)
	# A rolled rim. Cheap, and it is most of what makes a cylinder read as a cooking pot.
	var rim := MeshInstance3D.new()
	var rimm := TorusMesh.new()
	rimm.inner_radius = POT_R * 0.94
	rimm.outer_radius = POT_R * 1.06
	rimm.material = MatLib.galvanized()
	rim.mesh = rimm
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	rim.position = POT_LOCAL + Vector3(0.0, POT_H + 0.01, 0.0)
	# Two handle lugs, so it reads as a cooking pot rather than a can.
	for sx in [-1.0, 1.0]:
		var lug := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.05, 0.03, 0.08)
		lm.material = MatLib.galvanized()
		lug.mesh = lm
		lug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lug)
		lug.position = POT_LOCAL + Vector3(sx * (POT_R + 0.02), POT_H * 0.82, 0.0)
	# The water. A disc just below the rim; it rises and ripples on the boil.
	_pot_water_mat = StandardMaterial3D.new()
	_pot_water_mat.albedo_color = Color(0.06, 0.08, 0.09)
	_pot_water_mat.roughness = 0.12
	_pot_water_mat.metallic_specular = 0.9
	var wm := CylinderMesh.new()
	wm.top_radius = POT_R * 0.9
	wm.bottom_radius = POT_R * 0.9
	wm.height = 0.012
	wm.material = _pot_water_mat
	_pot_water = MeshInstance3D.new()
	_pot_water.mesh = wm
	_pot_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pot_water)
	_pot_water.position = POT_LOCAL + Vector3(0.0, POT_H * WATER_F, 0.0)
	# Steam. Hidden cold; four thin wisps that climb and fade while it boils.
	for i in range(5):
		var wisp := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.085
		sm.bottom_radius = 0.03
		sm.height = 0.20 + 0.05 * i
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.90, 0.92, 0.94, 0.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.material = mat
		wisp.mesh = sm
		wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wisp.visible = false
		add_child(wisp)
		wisp.position = POT_LOCAL + Vector3(
			cos(i * 1.7) * POT_R * 0.35, POT_H + 0.10 + 0.05 * i, sin(i * 1.7) * POT_R * 0.35)
		_steam.append({"mi": wisp, "mat": mat, "phase": float(i) * 1.37,
			"base_y": wisp.position.y})

func _powered() -> bool:
	return PowerGrid.is_powered(CIRCUIT)

## No verb while the oven is working — the prompt reports the cook instead, so the
## player is never offered a second cook on a range that is already busy.
##
## The verb READS the method: shellfish waiting in the pack offers BOIL, a fish offers COOK.
## Both dispatch the same way (see interact) — this is the prompt telling the truth about
## what is about to happen, not a second interaction.
func available_verbs() -> Array[String]:
	if _cooking:
		return [] as Array[String]
	if POT.has(_first_raw()):
		return ["BOIL"] as Array[String]
	return verbs

## Is the thing that would go in next boiled rather than seared?
func _is_boil(raw: String) -> bool:
	return POT.has(raw)

func get_prompt() -> String:
	if _cooking:
		return "%s…  %s (%ds)" % ["Boiling" if _boiling else "Cooking", display_name,
			int(ceilf(_timer))]
	var v: Array[String] = available_verbs()
	var word: String = v[0] if not v.is_empty() else "COOK"
	if not _powered():
		return "%s  %s (no power)" % [word, display_name]
	return "%s  %s" % [word, display_name]

func interact(verb: String, player: Node3D) -> void:
	if (verb != "COOK" and verb != "BOIL") or _cooking:
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
	_boiling = _is_boil(raw)
	_boil_t = 0.0
	_timer = COOK_SECONDS
	_cook_raw = raw
	_cook_out = cooked
	_cook_n = maxi(int(cut["n"]), 1)
	_cook_kg = float(cut["kg"])
	_cook_at = player.global_position if player != null else global_position
	_set_hot(true)
	AudioDirector.play_one_shot("hiss", global_position, -10.0)
	if hud:
		var raw_name: String = String(PlayerState.items.get(raw, {}).get("name", raw))
		hud.toast(("Into the pot: %s" if _boiling else "On the heat: %s") % raw_name)
	set_process(true)
	super.interact(verb, player)

func _process(delta: float) -> void:
	if not _cooking:
		set_process(false)
		return
	if _boiling:
		_roll_boil(delta)
	_timer -= delta
	if _timer <= 0.0:
		_finish()

## The rolling boil. The water lifts a centimetre, jitters, and four wisps of steam climb and
## fade off it — a range you can see working from across the hall is the whole point of the
## cook taking time at all (see COOK_SECONDS).
func _roll_boil(delta: float) -> void:
	_boil_t += delta
	if is_instance_valid(_pot_water):
		_pot_water.position.y = POT_LOCAL.y + POT_H * WATER_F \
			+ 0.010 + 0.004 * sin(_boil_t * 9.0)
		var wobble: float = 0.985 + 0.015 * sin(_boil_t * 13.0)
		_pot_water.scale = Vector3(wobble, 1.0, 2.0 - wobble)
	for w in _steam:
		var mi: MeshInstance3D = w["mi"]
		if not is_instance_valid(mi):
			continue
		# Each wisp runs its own 1.6 s climb, offset so they do not pulse in unison.
		var t: float = fposmod(_boil_t * 0.62 + float(w["phase"]), 1.0)
		mi.visible = true
		mi.position.y = float(w["base_y"]) + t * 0.30
		mi.scale = Vector3.ONE * (0.5 + t * 0.9)
		(w["mat"] as StandardMaterial3D).albedo_color.a = 0.50 * sin(t * PI)

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
		hud.toast("The range dies mid-cook. You pull it back out raw.")

func _finish() -> void:
	var cooked: String = _cook_out
	var raw: String = _cook_raw
	var want: int = _cook_n
	var kg: float = _cook_kg
	var feet: Vector3 = _cook_at
	var was_boil: bool = _boiling      # _clear() drops it, and the toast below needs it
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
			if was_boil:
				hud.toast("Boiled: %s → %s. The shells came open." % [raw_name, cooked_name])
			else:
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
	_boiling = false

## The visible half of a cook, and it is NOT THE SAME for the two methods — that difference
## is the whole of the owner's "on a pot on top of the stove".
##
## A sear lights the OVEN: the window goes from cold glass to self-lit ember and the lamp
## behind it throws warm light across the mess floor. A boil lights the HOB instead: the
## burner ring under the pot comes up red, the water rises and rolls (_roll_boil), steam
## climbs off it, and the oven door stays cold and dark because nothing is in it.
func _set_hot(hot: bool) -> void:
	var oven: bool = hot and not _boiling
	if is_instance_valid(_oven_light):
		_oven_light.visible = hot          # one lamp does for either; it lights the range
		_oven_light.position = Vector3(0.0, -0.05, -0.45) if oven \
			else POT_LOCAL + Vector3(0.0, 0.1, 0.0)
		_oven_light.light_energy = 1.7 if oven else 1.1
	if _glass != null:
		if oven:
			_glass.albedo_color = Color(1.0, 0.55, 0.18)
			_glass.emission_enabled = true
			_glass.emission = Color(1.0, 0.52, 0.16)
			_glass.emission_energy_multiplier = 2.4
		else:
			_glass.albedo_color = Color(0.07, 0.06, 0.055)
			_glass.emission_enabled = false
	var boil: bool = hot and _boiling
	if _hob_mat != null:
		if boil:
			_hob_mat.albedo_color = Color(0.42, 0.13, 0.06)
			_hob_mat.emission_enabled = true
			_hob_mat.emission = Color(1.0, 0.38, 0.14)
			_hob_mat.emission_energy_multiplier = 1.1
		else:
			_hob_mat.albedo_color = Color(0.09, 0.09, 0.10)
			_hob_mat.emission_enabled = false
	if _pot_water_mat != null:
		_pot_water_mat.albedo_color = Color(0.14, 0.13, 0.11) if boil \
			else Color(0.06, 0.08, 0.09)
	if not boil:
		if is_instance_valid(_pot_water):
			_pot_water.position.y = POT_LOCAL.y + POT_H * WATER_F
			_pot_water.scale = Vector3.ONE
		for w in _steam:
			if is_instance_valid(w["mi"]):
				(w["mi"] as MeshInstance3D).visible = false

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
