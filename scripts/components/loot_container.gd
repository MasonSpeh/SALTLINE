class_name LootContainer extends Interactable
## OPEN verb: a reusable storage crate. Items stay in `items` until the player
## moves them — opening brings up the HUD's exchange panel (crate ⇄ pack, both
## directions), so crates double as stash boxes. Always re-openable.

@export var items: Array[String] = []

var _opened: bool = false

func _init() -> void:
	verbs = ["OPEN"] as Array[String]
	# available_verbs() is inherited: crates always offer OPEN.

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	if not _opened:
		# First open only: the hatch creak, and the lid stays visibly cracked.
		_opened = true
		AudioDirector.play_one_shot("hatch", global_position)
		for c in get_children():
			if c is MeshInstance3D and c.mesh and c.mesh.material:
				c.mesh.material.albedo_color = c.mesh.material.albedo_color.darkened(0.5)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.open_crate(self)
