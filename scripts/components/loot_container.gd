class_name LootContainer extends Interactable
## OPEN verb: grants its item list to the player, once. Stays as an opened prop after.

@export var items: Array[String] = []

var _opened: bool = false

func _init() -> void:
	verbs = ["OPEN"] as Array[String]

func available_verbs() -> Array[String]:
	var out: Array[String] = []
	if not _opened:
		out.append("OPEN")
	return out

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	_opened = true
	var names: PackedStringArray = []
	for id in items:
		PlayerState.add_item(id)
		names.append(str(id).capitalize())
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Found: %s" % (", ".join(names) if names.size() > 0 else "nothing"))
	AudioDirector.play_one_shot("hatch", global_position)
	for c in get_children():
		if c is MeshInstance3D and c.mesh and c.mesh.material:
			c.mesh.material.albedo_color = c.mesh.material.albedo_color.darkened(0.5)
