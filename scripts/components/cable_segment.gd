class_name CableSegment extends Interactable
## CONNECT verb: a visibly burned cable gap. Consumes the cable spool item and bridges
## the gap (visual + logical). BreakerPanel checks `connected` before it will operate.

@export var required_item: String = "cable_spool"
@export var gap_length: float = 2.0

var connected: bool = false

func _init() -> void:
	verbs = ["CONNECT"] as Array[String]

func available_verbs() -> Array[String]:
	var out: Array[String] = []
	if not connected:
		out.append("CONNECT")
	return out

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not PlayerState.has_item(required_item):
		if hud:
			hud.toast("The line is burned through. You need a cable spool.")
		return
	PlayerState.remove_item(required_item)
	connected = true
	# Visual: lay a fresh cable across the gap.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, gap_length)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.12)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	if hud:
		hud.toast("Cable spliced. The line is whole again.")
	AudioDirector.play_one_shot("breaker", global_position)
