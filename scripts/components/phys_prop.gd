class_name PhysProp extends RigidBody3D
## Physics-based interactive object that can be picked up, carried, and thrown.

var held_by: Node3D = null
var display_name: String = "Object"   ## shown in the interaction prompt
var buoyant: bool = false             ## floats on the sea when true (buoyancy is v0.2)

func _ready() -> void:
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.4
	physics_material_override.bounce = 0.3

func _physics_process(_delta: float) -> void:
	if held_by:
		# Float in front of the camera at arm's length, tracking where you look.
		var cam: Camera3D = held_by.get_node("Head/Camera3D")
		var target: Vector3 = cam.global_position - cam.global_transform.basis.z * 1.3
		# Velocity-based follow keeps collisions honest — the prop shoves crates aside,
		# and can't be pushed through walls the way a hard position-set would.
		linear_velocity = (target - global_position) * 12.0
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, 0.3)

func get_prompt() -> String:
	return "Pick up  %s" % display_name if display_name != "Object" else "Pick up"
