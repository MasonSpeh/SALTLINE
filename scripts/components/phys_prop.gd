class_name PhysProp extends RigidBody3D
## Physics-based interactive object that can be picked up, carried, and thrown.

var held_by: Node3D = null

func _ready() -> void:
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.4
	physics_material_override.bounce = 0.3

func _physics_process(_delta: float) -> void:
	if held_by:
		# Follow player's hand (camera + offset)
		var player: Node3D = held_by
		var cam_forward: Vector3 = -player.get_node("Head/Camera3D").global_transform.basis.z
		var cam_right: Vector3 = player.get_node("Head/Camera3D").global_transform.basis.x
		var target: Vector3 = player.global_position + cam_forward * 0.8 + cam_right * 0.3 + Vector3(0, -0.3, 0)
		global_position = global_position.lerp(target, 0.2)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

func get_prompt() -> String:
	return "E — Pick up"
