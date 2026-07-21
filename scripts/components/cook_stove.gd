class_name CookStove extends Interactable
## The galley range — old propane bottle, honest heat. COOK sears one raw fish
## from the pack into that species' own meal: a Lantern Herring becomes a Cooked
## Lantern Herring, a Barrel Grouper feeds you for days. Bigger fish feed you more.
## A caught sea-bird roasts here too. Eating stays on the hotbar like any food.

# What sears into what comes from data/fish.json (cooked_to) via FishTable —
# the stove automatically knows every species the rod and net can land, and each
# now sears to its OWN cooked meal ("Cooked Lantern Herring"), not a generic fillet.
const FISH := preload("res://scripts/world/fish_table.gd")

# Non-fish things the range also cooks — a caught sea-bird off the deck, and room to grow.
const EXTRA_COOK := {
	"raw_sea_bird": "cooked_sea_bird",
}

## What a raw item cooks into ("" = not cookable). Fish come from the table; a few
## non-fish foods (gull) are handled here without polluting the fish data.
func _cooked_for(id: String) -> String:
	var c: String = FISH.cooked_for(id)
	return c if c != "" else String(EXTRA_COOK.get(id, ""))

func _init() -> void:
	display_name = "Galley Stove"
	var v: Array[String] = ["COOK"]
	verbs = v

func interact(verb: String, _player: Node3D) -> void:
	if verb != "COOK":
		return
	var raw: String = _first_raw()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if raw == "":
		if hud:
			hud.toast("Nothing raw to cook. The pan waits.")
		return
	var cooked: String = _cooked_for(raw)
	PlayerState.remove_item(raw)
	# Put the raw fish back if the meal has nowhere to go. Without this check a cook
	# with a full pack silently destroyed the catch and handed back nothing. The re-add
	# always fits — we freed a slot one line above — so the catch cannot fall through.
	if not PlayerState.add_item(cooked):
		PlayerState.add_item(raw)
		if hud:
			hud.toast("No room for the cooked fish — it stays on the grill.")
		return
	AudioDirector.play_one_shot("hiss", global_position, -10.0)
	Journal.discover("system_stove")
	if hud:
		var raw_name: String = PlayerState.items.get(raw, {}).get("name", raw)
		var cooked_name: String = PlayerState.items.get(cooked, {}).get("name", cooked)
		hud.toast("Seared: %s → %s" % [raw_name, cooked_name])
	_flare()
	super.interact(verb, _player)

## Brief burner flare — the pan hisses, the galley glows warm for a moment.
func _flare() -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.25)
	l.light_energy = 1.6
	l.omni_range = 4.0
	l.shadow_enabled = false
	add_child(l)
	l.position = Vector3(0, 0.7, 0)
	var tw: Tween = create_tween()
	tw.tween_property(l, "light_energy", 0.0, 2.2)
	tw.tween_callback(l.queue_free)

func _first_raw() -> String:
	for it in PlayerState.hotbar:
		if it != null and _cooked_for(String(it)) != "":
			return String(it)
	for it in PlayerState.inventory:
		if _cooked_for(String(it)) != "":
			return String(it)
	return ""
