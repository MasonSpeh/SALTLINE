class_name CraftBench extends Interactable
## The rigging bench: OPERATE with rope + prybar in your pack to lash up the
## throwing hook. One recipe for now; the pattern generalizes later.

const NEEDS := ["rope", "prybar"]
const MAKES := "throwing_hook"

func _init() -> void:
	display_name = "Rigging Bench"
	verbs = ["OPERATE"] as Array[String]

func get_prompt() -> String:
	if PlayerState.has_item(MAKES):
		return ""
	return "OPERATE  Rigging Bench — hook needs rope + prybar"

func available_verbs() -> Array[String]:
	if PlayerState.has_item(MAKES):
		return [] as Array[String]
	return verbs

func interact(_verb: String, player: Node3D) -> void:
	var hud: Node = player.get_tree().get_first_node_in_group("hud")
	var missing: Array[String] = []
	for item in NEEDS:
		if not PlayerState.has_item(item):
			missing.append(item)
	if missing.is_empty():
		for item in NEEDS:
			PlayerState.remove_item(item)
		PlayerState.add_item(MAKES)
		AudioDirector.play_one_shot("breaker", global_position, -4.0)
		if hud:
			hud.toast("Throwing hook rigged. [F] to throw it at what drifts.")
	elif hud:
		hud.toast("Needs: %s" % ", ".join(missing).replace("_", " "))
	super.interact(_verb, player)
