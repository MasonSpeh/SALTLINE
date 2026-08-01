class_name MovableProp extends PhysProp
## Any human-moveable object — a chair, a bucket, a lantern, a picture off the
## wall. Rests frozen (a solid static collider you can stand on / put things on)
## until you grab it; then it wakes into physics so you can carry it, drag it, or
## throw it, and settles back to rest when you let go. Extends PhysProp so the
## interaction ray and the player's grab/throw already handle it.
##
## Light things lift to arm's length (carry). Heavy things stay low and follow
## sluggishly along the ground (drag). Mass is set from the model's size.

var heavy: bool = false          ## drag along the floor instead of lifting
var _was_held: bool = false

func _ready() -> void:
	super._ready()
	# Rest as a static collider — no simulation cost, and it holds its placed pose
	# (a chair stays a chair, a shelf-top mug stays put) until someone grabs it.
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	can_sleep = true
	# Gentle damping so a dropped prop settles quickly instead of skating.
	linear_damp = 1.5
	angular_damp = 2.0

func _physics_process(_delta: float) -> void:
	if held_by:
		if not _was_held:
			wake_from_settle()      # unfreeze + cancel any pending settle lock
			_was_held = true
		var cam: Camera3D = held_by.get_node("Head/Camera3D")
		if heavy:
			# Drag: a low hold point in front of the feet, sluggish, gravity-held.
			var fwd: Vector3 = -cam.global_transform.basis.z
			fwd.y = 0.0
			var floor_y: float = held_by.global_position.y + 0.3
			var target: Vector3 = held_by.global_position + fwd.normalized() * 1.7
			target.y = floor_y
			var to: Vector3 = target - global_position
			linear_velocity = Vector3(to.x * 5.0, minf(to.y * 5.0, 2.0),
				to.z * 5.0).limit_length(CARRY_MAX_SPEED)
			angular_velocity = angular_velocity.lerp(Vector3.ZERO, 0.25)
		else:
			# Carry: float at arm's length, tracking the look direction — and turn WITH
			# the gaze via the base carry_yaw_follow (velocity-honest yaw), so a chair
			# grabbed square-on stays square-on as you look around instead of holding its
			# old world facing. (This overrides _physics_process, so per phys_prop's
			# subclass contract we call carry_yaw_follow in place of zeroing angular_velocity.)
			var target: Vector3 = cam.global_position - cam.global_transform.basis.z * 1.35
			linear_velocity = carry_velocity(target)
			carry_yaw_follow(held_by.global_rotation.y)
	elif _was_held:
		_was_held = false           # released — runs live, then locks (PhysProp.SETTLE_SEC)
		end_carry()                 # drop the carry servo's command + arm the settle clock
		release_carry_orient()      # forget the pickup yaw so the next grab re-captures

func get_prompt() -> String:
	var verb: String = "Drag" if heavy else "Grab"
	return "%s  %s" % [verb, display_name] if display_name != "Object" else verb
