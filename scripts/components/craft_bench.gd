class_name CraftBench extends Interactable
## The rigging bench: OPERATE opens the bench surface (BenchPanel) — lay parts on
## it, see what they want to become, hold to work. Recipes live in data/recipes.json.

func _init() -> void:
	display_name = "Rigging Bench"
	verbs = ["OPERATE"] as Array[String]

func get_prompt() -> String:
	return "OPERATE  Rigging Bench"

func interact(_verb: String, player: Node3D) -> void:
	Journal.discover("place_rigging_bench")
	var hud: Node = player.get_tree().get_first_node_in_group("hud")
	if hud:
		hud.open_bench(self)
	super.interact(_verb, player)
