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

## THE CARRY IS A SERVO, AND A SERVO WITHOUT A CLAMP IS A CATAPULT.
##
## The carry follow commands `linear_velocity = (target - position) * 12`, where `target`
## orbits the player at 1.3 m. That gain has no ceiling, and the error it acts on grows
## without bound whenever the prop cannot reach the target — which is most of the time you
## are actually carrying something: it is resting on the deck, jammed against a bulkhead,
## or lagging a fast turn. A 540 deg/s mouse flick (a normal flick) sweeps the target at
## 12.7 m/s on its own.
##
## The yaw servo has the same shape: `angular_velocity.y = err * 10`, err up to PI.
##
## And RELEASE, in player_controller.drop_carried(), simply nulls `held_by`. It does not
## touch the velocities, so the body keeps whatever the servo was commanding on the last
## held frame. Measured on the wet deck by tests/PropSettleProbe.tscn, releasing a 1.6 kg
## block mid-turn handed it **38.6 m/s and 51 m of travel**, ending 101 m below the rig —
## and the milder versions of the same thing are the reported "boxes shake and move in
## circles when dropped". Nothing about the deck's collision was wrong: the identical
## block dropped from a height on any of eight wet-deck spots (including the coplanar
## collider seams) settles and sleeps with |v| <= 0.002 m/s.
##
## So: clamp the servo to speeds a person could produce, and neutralise its residue on the
## held -> not-held transition. Both live here rather than at the release call site,
## because there is more than one way to stop holding something (drop, throw, die, load a
## save) and only the body knows what the servo left behind.
const CARRY_MAX_SPEED: float = 6.0    ## m/s a carried prop may be driven at
const CARRY_MAX_SPIN: float = 6.0     ## rad/s the yaw servo may command
const RELEASE_MAX_SPEED: float = 2.5  ## m/s a prop may still carry the instant you let go

var _was_carried: bool = false

func _ready() -> void:
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.4
	physics_material_override.bounce = 0.3
	# Residual spin has to bleed off. This was left at the project default (0.1), i.e. a
	# ten-second time constant, so any tumble a prop picked up outlived the interest of
	# whoever was watching it.
	angular_damp = 1.0
	# CONTINUOUS COLLISION, because everything this body can land on is triangle soup.
	# The whole rig is CSGBox3D with `use_collision = true`, and CSG bakes to a
	# ConcavePolygonShape3D — the one shape class with no interior. At 30 Hz a prop that
	# has fallen 1.8 m moves 0.20 m per step, and measured on the real wet deck a 0.26 m
	# block released at head height went STRAIGHT THROUGH 0.5 m of plating and was still
	# falling 250 m down (tests/PropSettleProbe.tscn). Dropped from 0.35 m it lands and
	# sleeps, which is why this never showed up in casual testing. There are single-digit
	# numbers of these bodies in the world, so swept collision is affordable here in a way
	# it would not be on a crowd.
	continuous_cd = true

func _physics_process(_delta: float) -> void:
	if held_by:
		# Float in front of the camera at arm's length, tracking where you look.
		var cam: Camera3D = held_by.get_node("Head/Camera3D")
		var target: Vector3 = cam.global_position - cam.global_transform.basis.z * 1.3
		# Velocity-based follow keeps collisions honest — the prop shoves crates aside,
		# and can't be pushed through walls the way a hard position-set would.
		linear_velocity = carry_velocity(target)
		# The object turns with your gaze — same velocity-based honesty, on the yaw axis.
		carry_yaw_follow(held_by.global_rotation.y)
		_was_carried = true
	else:
		if _was_carried:
			_was_carried = false
			end_carry()
		release_carry_orient()

## The clamped carry servo. Use this instead of writing `(target - pos) * gain` directly.
func carry_velocity(target: Vector3, gain: float = 12.0) -> Vector3:
	return ((target - global_position) * gain).limit_length(CARRY_MAX_SPEED)

## Run ONCE on the held -> not-held edge. Keeps enough motion for a set-down to look like
## a set-down and leaves the throw impulse (applied after the drop) entirely intact, while
## refusing to hand the body the servo's command as though it were momentum.
func end_carry() -> void:
	linear_velocity = linear_velocity.limit_length(RELEASE_MAX_SPEED)
	angular_velocity = Vector3.ZERO

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
		clampf(err * 10.0, -CARRY_MAX_SPIN, CARRY_MAX_SPIN),
		lerpf(angular_velocity.z, 0.0, 0.3))

## Forget the pickup reference so the next grab re-captures a fresh yaw offset from
## wherever the prop happens to be lying.
func release_carry_orient() -> void:
	_carry_active = false

func get_prompt() -> String:
	return "Pick up  %s" % display_name if display_name != "Object" else "Pick up"
