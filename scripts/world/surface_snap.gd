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

static func attach(target: Node3D, mode_: int = Mode.FLOOR, max_dist_: float = 3.0) -> void:
	# new() on the script itself — the global class cache may not know this
	# class_name yet, so avoid referring to it by name.
	var s: Node = new()
	s.mode = mode_
	s.max_dist = max_dist_
	target.add_child(s)

func _physics_process(_delta: float) -> void:
	var parent := get_parent() as Node3D
	if parent == null or not parent.is_inside_tree():
		queue_free()
		return
	var space: PhysicsDirectSpaceState3D = parent.get_world_3d().direct_space_state
	var from: Vector3 = parent.global_position + Vector3(0, 0.35, 0)
	var dir: Vector3 = Vector3.DOWN
	if mode == Mode.WALL:
		from = parent.global_position
		dir = -parent.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (max_dist + 0.35))
	if parent is CollisionObject3D:
		q.exclude = [(parent as CollisionObject3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if not hit.is_empty():
		if mode == Mode.FLOOR:
			parent.global_position.y = (hit.position as Vector3).y + 0.01
		else:
			parent.global_position = (hit.position as Vector3) + (hit.normal as Vector3) * 0.02
	queue_free()
