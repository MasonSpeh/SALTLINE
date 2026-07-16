class_name ColdStore extends Interactable
## The galley fridge, still holding a chill: STOW fish and it stays fresh
## forever; TAKE hands it back. The zero-thought preservation option — the
## drying line is the clever one.

const FISH := preload("res://scripts/world/fish_table.gd")

var _stored: Array[String] = []

func _init() -> void:
	display_name = "Galley Fridge"

func _storable(id: String) -> bool:
	return FISH.cooked_for(id) != "" or id in ["cooked_fish", "cooked_fish_prime", "dried_fish"]

func _player_fish() -> String:
	for it in PlayerState.hotbar:
		if it != null and _storable(String(it)):
			return String(it)
	for it in PlayerState.inventory:
		if _storable(String(it)):
			return String(it)
	return ""

func available_verbs() -> Array[String]:
	var v: Array[String] = []
	if _player_fish() != "":
		v.append("STOW")
	if not _stored.is_empty():
		v.append("TAKE")
	return v

func get_prompt() -> String:
	var v: Array[String] = available_verbs()
	if v.is_empty():
		return ""
	return "%s  %s (%d cold)" % [v[0], display_name, _stored.size()]

func interact(verb: String, _player: Node3D) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	match verb:
		"STOW":
			var id: String = _player_fish()
			if id != "":
				PlayerState.remove_item(id)
				_stored.append(id)
				Journal.discover("system_preserving")
				if hud:
					hud.toast("Cold-stored: %s" % PlayerState.items.get(id, {}).get("name", id))
		"TAKE":
			if not _stored.is_empty():
				var id: String = _stored.pop_back()
				PlayerState.add_item(id)
				if hud:
					hud.toast("From the fridge: %s" % PlayerState.items.get(id, {}).get("name", id))
	super.interact(verb, _player)
