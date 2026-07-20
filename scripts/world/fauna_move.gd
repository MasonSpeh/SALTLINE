class_name FaunaMove extends RefCounted
## Shared collision-aware ground step for the rig's walkers — crab, snails, deck gulls.
##
## Every ground creature is a plain Node3D driven by direct global_position assignment:
## the physics world can't push it, so left to itself it walks straight through barrels,
## bulkheads and rails. This probes the intended motion the way a real body would — centre
## plus both shoulders at body height — and when the path is blocked it SLIDES along the
## hit plane so the creature rounds the corner / follows the wall instead of clipping
## through. If it stays boxed in, step() returns a near-zero move and the caller's wander
## logic can turn to a new heading.
##
## Extracted from crab.gd's _resolve_step/_hit_normal so the one pattern lives in one place
## and every walker respects walls the same way the player does.
##
## Preload it (the class cache lags for new class_name scripts):
##   const MOVE := preload("res://scripts/world/fauna_move.gd")
##   var moved: Vector3 = MOVE.step(self, heading * speed * delta, BODY_R, PROBE_H, _skip)

## Apply as much of `step_vec` as the world allows this frame and return what actually
## moved (the move is added to node.global_position). Compare the returned length to
## step_vec's: a large shortfall means the creature is blocked — the caller turns away.
##   node         — the creature (moved by direct assignment)
##   step_vec     — intended motion this frame, already speed*delta scaled (flat in XZ)
##   body_radius  — half-width swept by the shoulder probes
##   probe_height — metres above the node origin to cast from (clears deck lips / cables)
##   exclude      — collision RIDs to ignore (the creature's own touch body, other fauna)
static func step(node: Node3D, step_vec: Vector3, body_radius: float = 0.42,
		probe_height: float = 0.35, exclude: Array[RID] = []) -> Vector3:
	var moved: Vector3 = resolve(node, step_vec, body_radius, probe_height, exclude)
	node.global_position += moved
	return moved

## The part of `step_vec` the creature may travel this frame, without moving it. Blocked
## head-on it projects the step onto the hit plane and slides; fully boxed in it returns
## Vector3.ZERO. Kept horizontal — these are deck walkers, not climbers.
static func resolve(node: Node3D, step_vec: Vector3, body_radius: float = 0.42,
		probe_height: float = 0.35, exclude: Array[RID] = []) -> Vector3:
	var n: Vector3 = hit_normal(node, step_vec, body_radius, probe_height, exclude)
	if n == Vector3.ZERO:
		return step_vec
	var slide: Vector3 = step_vec - n * step_vec.dot(n)
	slide.y = 0.0
	if slide.length() < 0.0001 or hit_normal(node, slide, body_radius, probe_height, exclude) != Vector3.ZERO:
		return Vector3.ZERO
	return slide

## Horizontal blocking normal for `step_vec`, or Vector3.ZERO when the path is clear.
## Sweeps the body width — centre plus both shoulders — at probe_height against world
## geometry (collision mask 1). `exclude` keeps a creature from reading its own touch
## collider, or a passing animal, as a wall.
static func hit_normal(node: Node3D, step_vec: Vector3, body_radius: float = 0.42,
		probe_height: float = 0.35, exclude: Array[RID] = []) -> Vector3:
	var world: World3D = node.get_world_3d()
	if world == null:
		return Vector3.ZERO
	var dir: Vector3 = step_vec.normalized()
	if dir == Vector3.ZERO:
		return Vector3.ZERO
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x) * body_radius   # perpendicular, body width
	var reach: float = step_vec.length() + body_radius
	var base: Vector3 = node.global_position + Vector3(0.0, probe_height, 0.0)
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	for offset in [Vector3.ZERO, side, -side]:
		var from: Vector3 = base + offset
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
		q.collision_mask = 1                     # world geometry only
		q.collide_with_areas = false
		q.exclude = exclude
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			var hn: Vector3 = hit.get("normal", Vector3.ZERO)
			hn.y = 0.0                           # horizontal blocking only: it walks decks
			if hn.length() > 0.01:
				return hn.normalized()
	return Vector3.ZERO

# ---------------------------------------------------------------- surface probes
# The three primitives a SURFACE crawler needs. The walkers above only ever ask "is
# there a wall in front of me, in XZ" — a snail also has to ask "what am I standing on,
# measured along MY up" and "how tall is the thing I just bumped", because its up is
# whatever face it is currently glued to, which is very often not +Y.

## What the world surface under `pos` is, measured along `up`: {} when nothing lies in
## the window, else {"point", "normal"}. The window runs from `lift` along +up down to
## `drop` along -up, so a foot that has drifted slightly INTO the face still resolves.
static func surface_hit(node: Node3D, pos: Vector3, up: Vector3, lift: float,
		drop: float, exclude: Array[RID] = []) -> Dictionary:
	var world: World3D = node.get_world_3d()
	if world == null or up.length() < 0.001:
		return {}
	var u: Vector3 = up.normalized()
	var q := PhysicsRayQueryParameters3D.create(pos + u * lift, pos - u * drop)
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = exclude
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var n: Vector3 = hit.get("normal", u)
	if n.length() < 0.001:
		n = u
	return {"point": hit["position"] as Vector3, "normal": n.normalized()}

## Is `pos` INSIDE world geometry? The one question a raycast cannot answer: Godot's
## convex raycast ignores a shape whose interior the ray starts in, so a probe fired from
## inside a bulkhead sails through it and reports whatever lies BEYOND — which reads a
## 8 m plate as flat deck. A point query is the honest test, and a crawler needs it to
## tell "a kerb I can crest" from "a wall whose top is nowhere near me".
static func point_solid(node: Node3D, pos: Vector3, exclude: Array[RID] = []) -> bool:
	var world: World3D = node.get_world_3d()
	if world == null:
		return false
	var q := PhysicsPointQueryParameters3D.new()
	q.position = pos
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = exclude
	return not world.direct_space_state.intersect_point(q, 1).is_empty()

## The obstruction `reach` metres ahead along `heading`, for a body of `body_radius`
## whose up is `up`: {} when the way is clear, else {"point", "normal", "distance"} for
## the NEAREST of the three body probes (centre + both shoulders). A face within ~45
## degrees of `up` is the surface being crawled (a ramp, a weld seam) and is never
## reported — a crawler follows those, it does not decide about them.
static func obstruction(node: Node3D, pos: Vector3, heading: Vector3, up: Vector3,
		reach: float, body_radius: float, probe_height: float,
		exclude: Array[RID] = []) -> Dictionary:
	var world: World3D = node.get_world_3d()
	if world == null:
		return {}
	var dir: Vector3 = heading.normalized()
	var u: Vector3 = up.normalized()
	if dir.length() < 0.5 or u.length() < 0.5:
		return {}
	var side: Vector3 = u.cross(dir)
	if side.length() < 0.001:
		return {}
	side = side.normalized() * body_radius
	var base: Vector3 = pos + u * probe_height
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var best: Dictionary = {}
	for offset in [Vector3.ZERO, side, -side]:
		var from: Vector3 = base + offset
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
		q.collision_mask = 1
		q.collide_with_areas = false
		q.exclude = exclude
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit.get("normal", Vector3.ZERO)
		if n.length() < 0.01 or n.normalized().dot(u) > 0.7:
			continue                                 # that is the floor we are on, not a wall
		var d: float = (hit["position"] as Vector3).distance_to(from)
		if best.is_empty() or d < float(best["distance"]):
			best = {"point": hit["position"] as Vector3, "normal": n.normalized(), "distance": d}
	return best

## Every fauna collision body around `host` — a crawler must never read another animal
## (FaunaTouch is a StaticBody3D) as footing or as a wall. Walks up to the node whose
## script file name ends with `root_frag` and collects the colliders beneath it.
static func kin_bodies(host: Node3D, root_frag: String = "bloom_fauna.gd") -> Array[RID]:
	var out: Array[RID] = []
	var root: Node = host
	while root != null:
		var s: Script = root.get_script() as Script
		if s != null and String(s.resource_path).ends_with(root_frag):
			break
		root = root.get_parent()
	if root == null:
		root = host
	for b in root.find_children("*", "CollisionObject3D", true, false):
		out.append((b as CollisionObject3D).get_rid())
	return out

# ------------------------------------------------------------- surface crawler
class SurfaceCrawler extends RefCounted:
	## A GASTROPOD'S MOTION. Everything else on this rig walks a world-space line and
	## treats geometry as a thing to avoid; a snail treats geometry as the thing it
	## travels ON. So this crawler carries a frame — `up` (the face normal its foot is
	## stuck to) and `heading` (a unit tangent IN that face) — and every step is taken
	## in that frame, not in XZ. Consequences, all of them the point of the animal:
	##
	##   * it follows the surface. Ramps, weld seams and curved plate are ridden, not
	##     decided about; the foot is re-seated on the real face every frame.
	##   * meeting an obstruction it DECIDES rather than presses. It measures how tall
	##     the thing is, probes both flanks, and picks: turn left, turn right, or climb.
	##     Flank clearance biases the roll, so it prefers a way that is actually open.
	##   * a SMALL BOUNDARY (<= KERB) is crawled straight OVER — up the near face, across
	##     the top, down the far side — because that is what a snail does with a lip, a
	##     kerb or a pipe. The convex top edge is a frame rotation, not a special case.
	##   * a TALL face is climbed and STUCK TO, body square to the wall. Above CLIMB_MAX
	##     it turns around and heads back down; so does the crest of a face too tall to
	##     have been chosen as a boundary, which keeps a climber on its own patch.
	##   * it can never intersect geometry and never floats: a step is refused before it
	##     is taken if the landing has no footing, and the foot is held FOOT metres off
	##     the face along its normal.
	##
	## Two patch shapes, as before: FREE (wander a disc of `leash` around `home`) and
	## SEAM (patrol a line through `home` along `axis`). Patch steering only applies
	## while the foot is on roughly level plating — a climbing snail is not dragged
	## sideways by its leash halfway up a bulkhead.
	const KERB := 0.4          ## at or under this, a boundary is gone straight over
	const CLIMB_MAX := 6.0     ## metres above the foothold where a climb turns back
	const FOOT := 0.02         ## clearance held between the origin and the face
	const COMMIT := 1.6        ## seconds a fresh decision is protected from patch steering
	## Sum of signed turns taken by consecutive _decide() left/right responses, above
	## which the crawler forces a break for open water instead of following the wall
	## another step. This is the wall-hugging twin of the free-wander leash bug fixed
	## earlier: THAT fix stopped the patch-steering path from orbiting the patch centre,
	## but the wall-RESPONSE path (_decide) has no memory across decisions at all — each
	## turn is locally correct (toward the open flank) yet a curved or circular boundary
	## (a round tank, a small submerged plate) keeps curving into the new heading, so the
	## same rotational sense repeats decision after decision and the SUM walks a full
	## lap. That is what "spins in circles after hitting a wall" actually was: not one
	## bad decision, but an unbounded run of individually-correct ones.
	const WALL_FOLLOW_BREAK := 4.71   ## ~270 degrees

	var home: Vector3           ## centre of the patch it works
	var leash: float            ## metres it may reach from home before turning back
	var speed: float
	var body_radius: float
	var probe_height: float
	var y_fallback: float       ## plane to ride when there is no surface at all
	var axis: Vector3           ## seam direction (unit); ZERO = free disc wander
	var heading: Vector3 = Vector3.FORWARD   ## unit tangent, in the surface plane
	var up: Vector3 = Vector3.UP             ## the face normal the foot is stuck to
	var blocked: bool = false   ## true the frame something turned it (callers react)
	var paused: bool = false
	var climbing: bool = false  ## foot is on a face steeper than ~45 degrees
	var surmount: bool = false  ## the boundary being negotiated is low enough to cross
	var climb_base: float = 0.0 ## world y the current climb started from
	var climb_peak: float = 0.0 ## metres above climb_base reached on this climb
	var choice: String = ""
	var decisions: int = 0      ## count of decisions taken (every write of `choice`)
	var boundary_h: float = -1.0 ## height measured for the last thing bumped (99 == out of reach)     ## last decision: left/right/climb/over/crest/edge/unstick
	var _goal: Vector3
	var _leg: float = 0.0
	var _pause: float = 0.0
	var _still: float = 0.0
	var _commit: float = 0.0
	var _skip: Array[RID] = []
	var _bound: bool = false
	var _grounded: bool = false ## a real face was under the foot last frame
	var _seated: bool = false   ## the first wide grounding probe has run
	var _wall_turn: float = 0.0 ## running signed turn from consecutive wall decisions
	var _rng := RandomNumberGenerator.new()

	func _init(home_: Vector3, leash_: float, speed_: float, seed_: int,
			body_radius_: float, probe_height_: float, y_fallback_: float,
			axis_: Vector3 = Vector3.ZERO) -> void:
		home = home_
		leash = leash_
		speed = speed_
		body_radius = body_radius_
		probe_height = probe_height_
		y_fallback = y_fallback_
		_rng.seed = seed_
		axis = Vector3(axis_.x, 0.0, axis_.z)
		if axis.length() > 0.001:
			axis = axis.normalized()
			_goal = home + axis * leash          # walk out to one end first
			heading = axis
		else:
			var a: float = _rng.randf() * TAU
			heading = Vector3(cos(a), 0.0, sin(a))
			_leg = _rng.randf_range(leash * 0.6, leash * 1.3)

	## Advance one frame: crawl the surface, decide about whatever is in the way, and
	## re-seat the foot on the face. Orientation is the caller's (basis()/orient()).
	func tick(host: Node3D, delta: float) -> void:
		if not _bound:
			_skip = FaunaMove.kin_bodies(host)   # never read another animal as wall/floor
			_bound = true
		blocked = false
		_commit = maxf(_commit - delta, 0.0)
		paused = _pause > 0.0
		if paused:
			_pause -= delta
		else:
			_advance(host, delta)
		_stick(host, delta)

	## Yaw so the yaw-normalised (-Z-forward) model leads its travel; snails add the +PI.
	## Kept for level crawlers; basis() is the full frame once a species may leave level.
	func face_yaw() -> float:
		return atan2(heading.x, heading.z) + PI

	## The full orientation for a body standing on the current face: -Z leads the
	## heading, +Y is the surface normal. A snail on a wall reads as a snail on a wall.
	func basis() -> Basis:
		if absf(heading.dot(up)) > 0.99:
			return Basis()
		return Basis.looking_at(heading, up)

	## The orientation for a body on the current face whose head turns toward `dir` instead
	## of toward its travel — the glass snail looking back at you. `dir` is projected INTO
	## the face, so a curious snail on a wall turns across the wall rather than peeling its
	## foot off it.
	func look_basis(dir: Vector3) -> Basis:
		var t: Vector3 = dir - up * dir.dot(up)
		if t.length() < 0.001:
			return basis()
		return Basis.looking_at(t.normalized(), up)

	## Ease `host` toward basis(). Use instead of assigning rotation.y: a yaw alone keeps
	## the body flat to the world, which draws a snail halfway up a bulkhead lying on its
	## side in mid-air. `roll` adds a body-local twist about the forward axis (the rust
	## snail's rasping rock) without disturbing the surface frame.
	func orient(host: Node3D, delta: float, rate: float = 4.0, roll: float = 0.0) -> void:
		var want: Basis = basis()
		if not is_zero_approx(roll):
			want = want * Basis(Vector3.BACK, roll)
		var have: Basis = host.global_basis.orthonormalized()
		host.global_basis = have.slerp(want, clampf(delta * rate, 0.0, 1.0))

	# ------------------------------------------------------------------ stepping
	func _advance(host: Node3D, delta: float) -> void:
		var level: bool = up.y > 0.7
		climbing = not level
		var step_len: float = speed * delta
		var before: Vector3 = host.global_position
		var reach: float = step_len + body_radius
		var info: Dictionary = FaunaMove.obstruction(host, before, heading, up, reach,
			body_radius, probe_height, _skip)
		if info.is_empty():
			var ahead: Vector3 = before + heading * step_len
			if _has_footing(host, ahead):
				host.global_position = ahead
				# Clear travel forgets the wall-hugging memory — a snail that has actually
				# gotten away from the last wall is no longer at risk of laminating a loop
				# out of it, so let it wall-follow normally again next time it meets one.
				_wall_turn = move_toward(_wall_turn, 0.0, delta * 2.0)
			elif _grounded:
				_edge(host)                       # convex edge: over it, or turn back
			else:
				# No face under the foot AND none under the step: a surface crawler with
				# nothing to crawl on does not sail on through open air. Hold position and
				# let the stall watchdog roll it onto new tangents until it finds footing.
				blocked = true
		else:
			blocked = true
			_decide(host, info)
		var moved: float = host.global_position.distance_to(before)
		# Stall watchdog: a snail that has not made a quarter of its step for over a
		# second is wedged. Kick it onto a fresh tangent instead of letting it press.
		if moved < step_len * 0.25:
			_still += delta
			if _still > 1.1:
				_unstick(host)
				_still = 0.0
		else:
			_still = 0.0
		# Climb ceiling: six metres up a face is as far as it goes before turning back.
		if climbing:
			climb_peak = maxf(climb_peak, host.global_position.y - climb_base)
			if host.global_position.y - climb_base > CLIMB_MAX and heading.y > 0.0:
				heading = -heading
				surmount = false
				blocked = true
				choice = "ceiling"
				_commit = COMMIT
		# Patch steering, only with the foot on level plating and no fresh decision.
		if level and _commit <= 0.0:
			if axis.length() > 0.5:
				_seam_step(host)
			else:
				_free_step(host, moved)

	## Meeting something: measure it, look both ways, then turn left, turn right, or climb.
	func _decide(host: Node3D, info: Dictionary) -> void:
		var n: Vector3 = info["normal"]
		# Arriving at ground more level than the face we are on (the deck at the foot of a
		# wall, the far side of a kerb) is not a decision — it is a landing.
		if n.y > 0.7 and up.y < 0.7:
			_attach(host, n, surmount)
			choice = "land"
			_wall_turn = 0.0
			return
		var h: float = _boundary_height(host, info)
		boundary_h = h
		decisions += 1
		if h >= 0.0 and h <= KERB:
			_attach(host, n, true)                # a lip / kerb / pipe: go straight over
			choice = "over"
			return
		var along: Vector3 = up.cross(n)
		if along.length() < 0.01:
			_attach(host, n, false)
			choice = "climb"
			return
		along = along.normalized()
		var left_clear: bool = _flank_clear(host, along)
		var right_clear: bool = _flank_clear(host, -along)
		var climb_odds: float = 0.25
		if not left_clear and not right_clear:
			climb_odds = 1.0                      # boxed in: up is the only way on
		elif left_clear != right_clear:
			climb_odds = 0.15                     # one flank open: usually take it
		if _rng.randf() < climb_odds:
			_attach(host, n, false)
			choice = "climb"
			return
		var go_left: bool = left_clear if left_clear != right_clear else _rng.randf() < 0.5
		var new_head: Vector3 = along if go_left else -along
		var delta_ang: float = atan2(heading.cross(new_head).dot(up), heading.dot(new_head))
		_wall_turn += delta_ang
		if absf(_wall_turn) > WALL_FOLLOW_BREAK:
			# Enough consecutive turns in the same rotational sense to have walked a lap —
			# stop following this curve and strike for open water instead, exactly the way
			# a strayed free-wander breaks for home rather than skimming the boundary.
			var inward: Vector3 = Vector3(home.x - host.global_position.x, 0.0, home.z - host.global_position.z)
			if inward.length() > 0.01:
				new_head = inward.normalized().rotated(Vector3.UP, _rng.randf_range(-0.3, 0.3))
				new_head = new_head - up * new_head.dot(up)
			_wall_turn = 0.0
			choice = "unwind"
		else:
			choice = "left" if go_left else "right"
		if new_head.length() > 0.001:
			heading = new_head.normalized()
		_leg = _rng.randf_range(leash * 0.6, leash * 1.3)
		_commit = COMMIT
		if _rng.randf() < 0.3:
			_pause = _rng.randf_range(0.4, 1.6)   # a rasp before moving on

	## Move onto the face `n`, keeping the old up as the new forward — which reads as
	## "start climbing" coming off the deck, and "step down onto the deck" off a wall.
	func _attach(host: Node3D, n: Vector3, surmount_: bool) -> void:
		var new_up: Vector3 = n.normalized()
		var new_head: Vector3 = up - new_up * up.dot(new_up)
		if new_head.length() < 0.01:
			new_head = heading - new_up * heading.dot(new_up)
		if new_head.length() < 0.01:
			return                                 # degenerate: leave the frame alone
		if new_up.y <= 0.7 and up.y > 0.7:
			climb_base = host.global_position.y    # a new climb starts here
			climb_peak = 0.0
		up = new_up
		heading = new_head.normalized()
		surmount = surmount_ if new_up.y <= 0.7 else false
		climbing = new_up.y <= 0.7
		_commit = COMMIT
		_grounded = true

	## The far side of an edge. A boundary being surmounted is followed OVER (the frame
	## rotates a quarter turn about the body's right axis and the crawl continues down
	## the far face); anything else — the crest of a tall bulkhead, the lip of a plate,
	## the edge of the deck — turns it back rather than dropping it into open water.
	func _edge(host: Node3D) -> void:
		blocked = true
		if surmount:
			var wrap_up: Vector3 = heading
			var wrap_head: Vector3 = -up
			# Probe for the next face just OVER the edge, not straight along the new up:
			# at the corner the foot is still held FOOT metres off the face it climbed, so
			# it is fractionally OUTBOARD of the lip and a probe from there misses the top
			# entirely and finds the deck below instead. Leading by half a body clears the
			# corner. The _lift()/_drop() window bounds how far a wrap may reach, so a real
			# drop — the edge of the deck, open water — still fails here and turns it back.
			var lead: float = body_radius * 0.5 + FOOT
			var seat: Dictionary = FaunaMove.surface_hit(host,
				host.global_position + wrap_head * lead, wrap_up, _lift(), _drop(), _skip)
			if not seat.is_empty():
				if wrap_up.y <= 0.7 and up.y > 0.7:
					climb_base = host.global_position.y
					climb_peak = 0.0
				up = wrap_up
				heading = wrap_head
				climbing = wrap_up.y <= 0.7
				# Seat the foot on the NEW face in the same frame. Easing across a convex
				# edge leaves the origin at the OLD face's offset — which is a few
				# centimetres INSIDE the corner — for however many frames the rate-limited
				# seat in _stick needs to walk it out, and those frames are spent in solid.
				host.global_position = (seat["point"] as Vector3) + up * FOOT
				choice = "over"
				_commit = COMMIT
				return
		heading = (-heading).rotated(up, _rng.randf_range(-0.4, 0.4)).normalized()
		choice = "crest" if climbing else "edge"
		_leg = _rng.randf_range(leash * 0.5, leash * 1.1)
		_commit = COMMIT

	## Keep the foot ON the face: re-probe along up, re-seat the frame to the real
	## surface normal, and ease the origin to FOOT metres off it. Nothing anywhere at
	## all (a bare probe rig, open water) falls back to the authored plane.
	func _stick(host: Node3D, delta: float) -> void:
		var pos: Vector3 = host.global_position
		var lift: float = _lift()
		var drop: float = _drop()
		if not _seated:
			# First frame: a wide window, so an authored Y that is only roughly right
			# snaps onto the real plating the way surface_y used to seat it.
			lift = 1.2
			drop = 2.5
		var hit: Dictionary = FaunaMove.surface_hit(host, pos, up, lift, drop, _skip)
		if hit.is_empty() and _grounded:
			_edge(host)                            # the face ran out from under the foot
			hit = FaunaMove.surface_hit(host, pos, up, _lift(), _drop(), _skip)
		if hit.is_empty():
			_grounded = false
			_seated = true
			if up.y > 0.9:
				pos.y = y_fallback
				host.global_position = pos
			return
		var n: Vector3 = hit["normal"]
		if n.dot(up) > 0.3:                        # ride slopes and curved plate
			up = up.lerp(n, clampf(delta * 5.0, 0.0, 1.0)).normalized()
			var t: Vector3 = heading - up * heading.dot(up)
			if t.length() > 0.001:
				heading = t.normalized()
		var target: Vector3 = (hit["point"] as Vector3) + up * FOOT
		var to_t: Vector3 = target - pos
		# Snap on the first seating, on a genuine teleport, and — the guarantee that matters
		# — whenever the origin is actually inside solid geometry. Everywhere else the foot
		# eases onto the face so the crawl reads smooth rather than snapping frame to frame.
		if not _seated or to_t.length() > 1.0 or FaunaMove.point_solid(host, pos, _skip):
			pos = target
		else:
			pos += to_t.limit_length(maxf(speed, 0.35) * delta * 3.0)
		host.global_position = pos
		_grounded = true
		_seated = true

	# ------------------------------------------------------------------ measuring
	func _lift() -> float:
		return 0.45 + body_radius * 0.5

	func _drop() -> float:
		return 0.45 + body_radius * 0.5

	## Metres the bumped thing rises above the current foot plane, or 99.0 when its top is
	## out of reach (a bulkhead, a caisson). Two samples are dropped just past the face,
	## from KERB+0.25 above the foot — above anything that counts as a lip.
	##
	## The subtle part is proving a sample DIDN'T land on the obstruction. A ray alone
	## cannot: Godot's convex raycast ignores a shape it starts inside, so a sample fired
	## from inside a bulkhead passes straight through and reports the DECK BEYOND at h~0 —
	## which classified every wall on this rig as a kerb and sent snails climbing them
	## instead of deciding. So each sample is point-tested first (inside solid == its top
	## is above the window == tall), and only a sample that lands ABOVE the foot plane
	## counts as having found a top: one that comes back at foot level overshot a thin
	## boundary and must not be allowed to vote the thing flat.
	func _boundary_height(host: Node3D, info: Dictionary) -> float:
		var pos: Vector3 = host.global_position
		var lateral: Vector3 = (info["point"] as Vector3) - pos
		var tang: Vector3 = lateral - up * lateral.dot(up)
		var top: float = -1.0
		for reach_in in [0.06, 0.18]:
			var from: Vector3 = pos + tang + heading * reach_in + up * (KERB + 0.25)
			if FaunaMove.point_solid(host, from, _skip):
				return 99.0                          # the sample is buried in it: tall
			var q: Dictionary = FaunaMove.surface_hit(host, from, up, 0.0, KERB + 0.45, _skip)
			if q.is_empty():
				return 99.0                          # nothing under the sample at all
			var h: float = ((q["point"] as Vector3) - pos).dot(up)
			if h > KERB:
				return 99.0                          # its top is above the kerb window
			top = maxf(top, h)                       # a foot-level sample contributes nothing
		if top <= 0.01:
			return 99.0                              # never found a top: not a lip, decide
		return top

	## Is there a face under `p` for the foot to land on?
	func _has_footing(host: Node3D, p: Vector3) -> bool:
		return not FaunaMove.surface_hit(host, p, up, _lift(), _drop(), _skip).is_empty()

	## Could the body travel a couple of its own widths along `dir` without meeting
	## something? Biases the left/right/climb roll toward a way that is actually open.
	func _flank_clear(host: Node3D, dir: Vector3) -> bool:
		var reach: float = body_radius * 3.0 + 0.2
		return FaunaMove.obstruction(host, host.global_position, dir, up, reach,
			body_radius * 0.7, probe_height, _skip).is_empty()

	## Wedged (an inside corner, a pipe cluster): swing hard onto a new tangent.
	func _unstick(host: Node3D) -> void:
		var turn: float = _rng.randf_range(PI * 0.45, PI * 0.95) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var t: Vector3 = heading.rotated(up, turn)
		t = t - up * t.dot(up)
		if t.length() > 0.001:
			heading = t.normalized()
		_pause = 0.0
		_leg = _rng.randf_range(leash * 0.5, leash * 1.2)
		_commit = COMMIT
		_wall_turn = 0.0
		blocked = true
		choice = "unstick"

	# ------------------------------------------------------------- patch steering
	## Seam patrol: walk toward the current endpoint, flip to the far one on arrival.
	func _seam_step(host: Node3D) -> void:
		var to_goal: Vector3 = Vector3(_goal.x - host.global_position.x, 0.0, _goal.z - host.global_position.z)
		if to_goal.length() < 0.3 or to_goal.dot(heading) < 0.0:
			_goal = home + home - _goal          # the opposite end of the seam
			var to_new: Vector3 = Vector3(_goal.x - host.global_position.x, 0.0, _goal.z - host.global_position.z)
			if to_new.length() > 0.01:
				heading = to_new.normalized().rotated(Vector3.UP, _rng.randf_range(-0.2, 0.2))
			if _rng.randf() < 0.4:
				_pause = _rng.randf_range(0.6, 1.8)

	## Free disc wander: pull back when it strays past the leash, turn when the current
	## heading has run its length. Blocking is handled by _decide, not here.
	func _free_step(host: Node3D, moved: float) -> void:
		_leg -= moved
		var off: Vector3 = Vector3(host.global_position.x - home.x, 0.0, host.global_position.z - home.z)
		# ONLY a snail travelling OUTWARD has strayed. Testing distance alone re-fired the
		# turn every frame it spent outside the leash — including while it was already on
		# its way back — so it never got to leave the rim. That, plus aiming at the centre
		# from the rim, is a textbook orbit, and it is why snails "just go in circles".
		var outward: bool = off.dot(heading) > 0.0
		var strayed: bool = off.length() > leash and outward
		if not (strayed or _leg <= 0.0):
			return
		var new_head: Vector3 = heading
		if strayed and off.length() > 0.01:
			# Head ACROSS the patch, not back to its middle: aiming at home from the rim
			# skims the boundary, while crossing it puts the animal somewhere genuinely
			# new. Commit to a leg long enough to actually make the traverse.
			new_head = (-off).normalized().rotated(Vector3.UP, _rng.randf_range(-0.45, 0.45))
			new_head = new_head - up * new_head.dot(up)
			if new_head.length() > 0.001:
				heading = new_head.normalized()
			_leg = off.length() + _rng.randf_range(leash * 0.8, leash * 1.5)
			if _rng.randf() < 0.25:
				_pause = _rng.randf_range(0.5, 1.6)
			return
		else:
			new_head = heading.rotated(Vector3.UP, _rng.randf_range(1.2, TAU - 1.2))
		new_head = new_head - up * new_head.dot(up)
		if new_head.length() < 0.001:
			return
		heading = new_head.normalized()
		_leg = _rng.randf_range(leash * 0.6, leash * 1.3)
		if _rng.randf() < 0.3:
			_pause = _rng.randf_range(0.5, 1.8)   # a graze pause
