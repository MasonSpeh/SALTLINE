class_name Takeable extends Interactable
## TAKE verb: adds item_id to PlayerState inventory and removes itself from the world.

## By path, not class_name — the global class cache lags for autoload-parsed scripts.
const FISH := preload("res://scripts/world/fish_table.gd")

@export var item_id: String = ""
## The landed weight of THIS fish, for the sized species (fish.json size_kg). 0.0 for
## everything else — a can of peaches has no opinion. Stamped by save_manager._make_drop
## when a sized fish hits the deck (the weight is popped out of FishTable's ledger and
## rides the node instead, which is what lets the body render at its real length), and
## pushed BACK into the ledger below when the fish is taken, so the stove and the drying
## line still fillet the fish that was actually caught.
var size_kg: float = 0.0

func _init() -> void:
	verbs = ["TAKE"]

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	if not PlayerState.add_item(item_id):
		return   # pack full — leave it in the world
	if size_kg > 0.0:
		FISH.record_size(item_id, size_kg)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Took %s" % display_name)
	queue_free()
