class_name SurfaceSnap extends Node
## One-shot placement corrector — the base-generation fix for floating props.
## Attach to any Node3D: on its first physics tick (once real collision exists)
## it raycasts and ADHERES the parent to a surface, then removes itself.
##   FLOOR — drop onto whatever is below (shelves, counters, decks, machines).
##   WALL  — push back along the parent's -Z onto the nearest wall face.
## Props adhere to surfaces instead of trusting hand-typed coordinates.

enum Mode { FLOOR, WALL }

var mode: int = Mode.FLOOR
var max_dist: float = 3.0
## Refuse to move the parent further than this. Blanket-snapping every prop would drag
## wall clocks, posters and sockets down onto the deck, because the only surface below
## them IS the deck. Bounding the correction means a mug hovering 8cm over a bench gets
## seated, while a poster 1.6m up its bulkhead is recognised as "not a floating prop"
## and left exactly where the dressing code put it.
var max_drop: float = INF

static func attach(target: Node3D, mode_: int = Mode.FLOOR, max_dist_: float = 3.0,
		max_drop_: float = INF) -> void:
	# new() on the script itself — the global class cache may not know this
	# class_name yet, so avoid referring to it by name.
	var s: Node = new()
	s.mode = mode_
	s.max_dist = max_dist_
	s.max_drop = max_drop_
	target.add_child(s)

## IT USED TO TAKE ITS ONE SHOT ON THE FIRST PHYSICS TICK, AND THE FLOOR IS NOT THERE YET.
##
## The decks are CSG, and a CSGShape3D does not have a collider on the frame it enters the
## tree — it bakes one shortly after. So the single raycast this used to fire found nothing,
## the node shrugged, freed itself, and the prop kept a hand-typed position that the snap
## existed to correct. Worse for a RigidBody: with no floor under it yet it simply FELL. That
## is the store-room crate reported at y -0.9, about 3 m under the wet deck (KNOWN_ISSUES,
## found s18) — the corrector and the bug were the same node.
##
## Two changes. It RETRIES until real collision answers, instead of assuming tick one is
## representative; and it HOLDS a rigid parent still while it waits, because a body that
## spends the wait accelerating downward has already lost the position being corrected (at
## 9.8 m/s^2 even half a second is a 1.2 m drop). This is the same reason bloom_fauna's
## _snap_to_deck/_snap_to_perch defer out of _ready().
const RETRY_TICKS: int = 90        ## ~1.5 s at 60 Hz — generous; a hit ends it on tick one
## AND WAIT BEFORE THE FIRST ATTEMPT AT ALL. Retrying only helps when the ray finds NOTHING;
## the store-room crate's ray found something — it passed through a wet deck that had not
## baked its collider yet and hit the structure 3 m below, so the snap "succeeded" onto the
## wrong surface and the correction became the fault. Measured: authored y 2.01 -> seated
## -0.944. Bounding the drop cannot separate these, because legitimate corrections in this
## world run to 1.80 m (a prop authored 1.8 m over the wet deck being seated onto it) — the
## discriminator is not distance, it is whether the deck exists yet.
const WARMUP_TICKS: int = 8
var _ticks: int = 0
var _warm: int = 0
var _frozen: bool = false
var _was_frozen: bool = false

func _physics_process(_delta: float) -> void:
	var parent := get_parent() as Node3D
	if parent == null or not parent.is_inside_tree():
		_thaw(parent)
		queue_free()
		return
	# Hold a rigid parent at its authored height for as long as the search takes. Restored
	# the moment the snap resolves or gives up, so nothing stays frozen.
	var rb := parent as RigidBody3D
	if rb != null and not _frozen:
		_was_frozen = rb.freeze
		rb.freeze = true
		_frozen = true
	if _warm < WARMUP_TICKS:
		_warm += 1
		return
	var space: PhysicsDirectSpaceState3D = parent.get_world_3d().direct_space_state
	var from: Vector3 = parent.global_position + Vector3(0, 0.35, 0)
	var dir: Vector3 = Vector3.DOWN
	if mode == Mode.WALL:
		from = parent.global_position
		dir = -parent.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (max_dist + 0.35))
	# World geometry only, and never another creature: every FaunaTouch is a StaticBody3D on
	# the default layer, so a prop placed near an animal could otherwise be seated on it (the
	# same trap that made ReefProbe report a caisson 606 mm off its own centre line).
	q.collision_mask = 1
	q.collide_with_areas = false
	if parent is CollisionObject3D:
		q.exclude = [(parent as CollisionObject3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		_ticks += 1
		if _ticks < RETRY_TICKS:
			return          # the CSG collider probably has not baked yet — ask again
		# GIVE UP LOUDLY. A silent no-op here is indistinguishable from a successful snap,
		# which is exactly how the crate stayed 3 m under the deck for several sessions.
		push_warning("[SurfaceSnap] %s found no surface within %.2f m of %s after %d ticks — "
			% [parent.name, max_dist, str(parent.global_position), RETRY_TICKS]
			+ "it is keeping its authored position, which may be floating or buried.")
		_thaw(parent)
		queue_free()
		return
	var target: Vector3 = parent.global_position
	if mode == Mode.FLOOR:
		target.y = (hit.position as Vector3).y + 0.01
	else:
		target = (hit.position as Vector3) + (hit.normal as Vector3) * 0.02
	if parent.global_position.distance_to(target) <= max_drop:
		parent.global_position = target
	_thaw(parent)
	queue_free()

## Put a held rigid body back exactly as it was found, so this node never leaves physics state
## behind it. Deferred: unfreezing inside the physics step can drop the restored transform.
func _thaw(parent: Node3D) -> void:
	if not _frozen:
		return
	_frozen = false
	var rb := parent as RigidBody3D
	if rb != null and is_instance_valid(rb):
		rb.set_deferred("freeze", _was_frozen)
