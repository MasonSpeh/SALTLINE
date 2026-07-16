class_name CookStove extends Interactable
## The galley range — old propane bottle, honest heat. COOK sears one raw fish
## from the pack into a real meal: small fish become Seared Fish, the big deep
## species render a Prime Fillet. Eating stays on the hotbar like any food.

const RAW_TO_COOKED := {
	"fish_herring": "cooked_fish",
	"fish_slate_cod": "cooked_fish",
	"fish_mirrorjack": "cooked_fish",
	"fish_chimefish": "cooked_fish",
	"fish_sable_hake": "cooked_fish",
	"fish_barrel_grouper": "cooked_fish_prime",
	"fish_ribbon_eel": "cooked_fish_prime",
}

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
	PlayerState.remove_item(raw)
	var cooked: String = RAW_TO_COOKED[raw]
	PlayerState.add_item(cooked)
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
		if it != null and RAW_TO_COOKED.has(String(it)):
			return String(it)
	for it in PlayerState.inventory:
		if RAW_TO_COOKED.has(String(it)):
			return String(it)
	return ""
