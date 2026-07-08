class_name Ladder extends Interactable
## CLIMB verb: designated climb node (GDD A5 — mantle/climb only at ladders).
## Player attaches to the ladder line and moves along it; exits at either end.

@export var height: float = 4.0        ## climbable rise from base (local y=0) upward
@export var exit_forward: float = 0.6  ## how far to push the player off at the top

func _init() -> void:
	verbs = ["CLIMB"]

func bottom_point() -> Vector3:
	return global_position

func top_point() -> Vector3:
	return global_position + global_transform.basis.y * height

## Outward direction the player should face while climbing (ladder's -Z is the wall side).
func face_dir() -> Vector3:
	return -global_transform.basis.z

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	if player and player.has_method("start_climb"):
		player.start_climb(self)
