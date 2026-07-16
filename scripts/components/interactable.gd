class_name Interactable extends StaticBody3D
## Base for every interactive object (GDD A4). Exports a verb config; the player's
## InteractionRay reads verbs and dispatches interact(). Affordance = color, never outlines.

const COLOR_TAKEABLE := Color(0.85, 0.75, 0.2)   # yellow: takeable/usable
const COLOR_OPERABLE := Color(0.7, 0.15, 0.1)    # red: valve/switch/operable
const COLOR_READABLE := Color(0.92, 0.92, 0.88)  # white: readable

signal interacted(verb: String)

@export var display_name: String = "Object"
@export var verbs: Array[String] = ["USE"]

## Override for state-dependent verb availability. Empty array = no prompt shown.
func available_verbs() -> Array[String]:
	return verbs

func get_prompt() -> String:
	var v: Array[String] = available_verbs()
	if v.is_empty():
		return ""
	return "%s  %s" % [v[0], display_name]

func interact(verb: String, _player: Node3D) -> void:
	interacted.emit(verb)

## Attach a simple colored box mesh + collider — components are greybox by canon.
func build_box_visual(size: Vector3, color: Color, emissive: bool = false, cast_shadow: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	return mi
