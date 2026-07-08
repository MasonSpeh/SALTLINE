class_name WarmthZone extends Area3D
## Volume that modifies PlayerState.warmth_zone while the player is inside:
## mode -1 = cold (flooded room), +1 = heated (space heater, gated on its circuit).

@export var mode: int = -1
@export var requires_circuit: String = ""

var _player_inside: bool = false
var _applied: bool = false

func setup(size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

func _ready() -> void:
	monitoring = true
	body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			_player_inside = true)
	body_exited.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			_player_inside = false)

func _process(_delta: float) -> void:
	var active: bool = requires_circuit == "" or PowerGrid.is_powered(requires_circuit)
	var want: bool = _player_inside and active
	if want != _applied:
		PlayerState.warmth_zone += mode if want else -mode
		_applied = want
