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
