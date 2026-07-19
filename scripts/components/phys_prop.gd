class_name PhysProp extends RigidBody3D
## Physics-based interactive object that can be picked up, carried, and thrown.

var held_by: Node3D = null
var display_name: String = "Object"   ## shown in the interaction prompt
var buoyant: bool = false             ## floats on the sea when true (buoyancy is v0.2)

# Carried-orientation state. At the moment of pickup we remember the offset between
# the prop's yaw and the camera's yaw; from then on the prop is steered to hold that
# same offset, so it turns with your gaze instead of keeping its old world facing.
var _carry_active: bool = false
var _carry_yaw_ref: float = 0.0       ## camera yaw captured at pickup
var _carry_yaw_hold: float = 0.0      ## the prop's own yaw captured at pickup

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
		# The object turns with your gaze — same velocity-based honesty, on the yaw axis.
		carry_yaw_follow(held_by.global_rotation.y)
	else:
		release_carry_orient()

## Turn a carried prop with the player's gaze. Capture the yaw offset between the prop
## and the camera at the moment of pickup, then each frame steer the prop's yaw back to
## that same offset — via ANGULAR VELOCITY, so physics stays honest exactly like the
## linear follow above. A crate grabbed square-on stays square-on as you look around,
## instead of holding its old world facing while your body swings around it. Tumble on
## the other two axes is damped so the prop rides level rather than spinning.
##
## Subclasses that override _physics_process (e.g. MovableProp) should call this in
## place of zeroing angular_velocity, passing held_by.global_rotation.y as the camera
## yaw (the player body IS the yaw pivot; the head only pitches).
func carry_yaw_follow(cam_yaw: float) -> void:
	if not _carry_active:
		_carry_active = true
		_carry_yaw_ref = cam_yaw
		_carry_yaw_hold = global_rotation.y
	# Desired yaw = the pickup facing, rotated by however far the camera yaw has moved
	# since. Wrapping keeps a big turn taking the short way round instead of unwinding.
	var desired: float = _carry_yaw_hold + wrapf(cam_yaw - _carry_yaw_ref, -PI, PI)
	var err: float = wrapf(desired - global_rotation.y, -PI, PI)
	angular_velocity = Vector3(
		lerpf(angular_velocity.x, 0.0, 0.3),
		err * 10.0,
		lerpf(angular_velocity.z, 0.0, 0.3))

## Forget the pickup reference so the next grab re-captures a fresh yaw offset from
## wherever the prop happens to be lying.
func release_carry_orient() -> void:
	_carry_active = false

func get_prompt() -> String:
	return "Pick up  %s" % display_name if display_name != "Object" else "Pick up"
