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

## SETTLE AND FREEZE. Owner spec: three seconds after you let go of something, it stops dead
## and locks into the pose it is in at that moment.
##
## The clamps above fixed the release VELOCITY, but they cannot fix the other half. A block at
## rest on the wet deck is a convex shape sitting on a CSG-baked ConcavePolygonShape3D —
## triangle soup with no interior, with seams where two static colliders present the SAME
## walking plane. A solver asked to re-resolve that contact set every tick, forever, will
## always find something to argue about; a box wide enough to bridge a seam gets pushed by
## both sides of it. That argument, running at 30 Hz under a body that should be doing
## nothing, is what reads as "shaking and moving in circles".
##
## A prop that has come to rest has nothing left to simulate, so stop simulating it: zero the
## velocities and freeze the body STATIC. It holds its pose for good, costs nothing, and —
## being a static collider now — you can stack things on it and stand on it. Grabbing it wakes
## it again (wake_from_settle), so this is a rest state, not a death.
const SETTLE_SEC: float = 3.0         ## seconds after release before the body locks
## A prop thrown over the rail is still in free fall at T+3, and freezing it there hangs a
## crate in the sky above the water. A body still falling re-checks on this interval instead —
## but only for SETTLE_MAX_DEFER more seconds, after which it locks regardless, so "permanent"
## stays true even for something that never lands.
const SETTLE_RECHECK: float = 0.5
const SETTLE_MAX_DEFER: float = 6.0
const SETTLE_FALL_SPEED: float = 3.0  ## m/s downward that still counts as "in the air"

var _was_carried: bool = false
var _settle_timer: Timer = null
var _settle_deferred: float = 0.0

func _ready() -> void:
	physics_material_override = PhysicsMaterial.new()
	# Wet steel plating and a wooden dunnage block do not slide, and they do not bounce.
	# Friction 0.4 let a set-down box skate off across the deck; bounce 0.3 meant it arrived
	# in a series of ever-smaller hops, each one a fresh contact against triangle soup. Both
	# fed the "shaking / moving in circles" report directly, so both come down to values a
	# heavy object on a wet deck would actually show.
	physics_material_override.friction = 0.9
	physics_material_override.bounce = 0.05
	# Residual spin has to bleed off. This was left at the project default (0.1), i.e. a
	# ten-second time constant, so any tumble a prop picked up outlived the interest of
	# whoever was watching it.
	angular_damp = 2.0
	# Likewise for residual travel: without this, a released prop coasts on the project
	# default (0.1) and is still creeping when the settle clock locks it. Deliberately well
	# under MovableProp's 1.5 — a throw still has to read as a throw.
	linear_damp = 0.5
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
	# The settle clock. A Timer NODE rather than a countdown ticked in _physics_process,
	# because MovableProp overrides _physics_process and does not chain to super — a tick
	# living there would silently never run for the furniture, which is most of the props in
	# the game. On physics so the lock lands on a physics frame, with the body's own step.
	_settle_timer = Timer.new()
	_settle_timer.one_shot = true
	_settle_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_settle_timer.timeout.connect(_on_settle_timeout)
	add_child(_settle_timer)

func _physics_process(_delta: float) -> void:
	if held_by:
		if not _was_carried:
			# The not-held -> held edge. A settled prop is frozen STATIC, and a frozen body
			# ignores the linear_velocity the carry servo is about to write, so it has to go
			# live again first. This lives on the edge (not at try_grab) for the same reason
			# end_carry does: there is more than one way to start holding something.
			wake_from_settle()
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
	arm_settle()

## Start the countdown to lock. Called on every release — including the throw, whose impulse
## is applied by player_controller AFTER the drop and so is untouched by this. Calling it
## again simply restarts the clock, which is what a re-grab-and-release should do.
func arm_settle() -> void:
	_settle_deferred = 0.0
	if _settle_timer != null:
		_settle_timer.start(SETTLE_SEC)

## The clock ran out. Lock — unless the body is still falling, in which case look again
## shortly, up to the deferral cap. See SETTLE_RECHECK.
func _on_settle_timeout() -> void:
	if linear_velocity.y < -SETTLE_FALL_SPEED and _settle_deferred < SETTLE_MAX_DEFER:
		_settle_deferred += SETTLE_RECHECK
		_settle_timer.start(SETTLE_RECHECK)
		return
	settle_now()

## Stop dead and lock into the CURRENT position and rotation. The velocities are zeroed
## before the freeze rather than left banked, so a later grab wakes a body that is genuinely
## at rest instead of one that resumes the motion it was locked out of.
func settle_now() -> void:
	if _settle_timer != null:
		_settle_timer.stop()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true

## Back to live physics, and cancel any pending lock. The counterpart to settle_now(): a
## settled prop comes through here before anything is allowed to move it again.
func wake_from_settle() -> void:
	if _settle_timer != null:
		_settle_timer.stop()
	_settle_deferred = 0.0
	freeze = false
	sleeping = false

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
