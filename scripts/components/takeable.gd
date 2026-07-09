class_name Takeable extends Interactable
## TAKE verb: adds item_id to PlayerState inventory and removes itself from the world.

@export var item_id: String = ""

func _init() -> void:
	verbs = ["TAKE"]

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	if not PlayerState.add_item(item_id):
		return   # pack full — leave it in the world
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Took %s" % display_name)
	queue_free()
