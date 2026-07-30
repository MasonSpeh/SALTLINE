class_name WarmthZone extends Area3D
## Volume that modifies PlayerState.warmth_zone while the player is inside:
## mode -1 = cold (flooded room), +1 = heated (space heater, gated on its circuit).

@export var mode: int = -1
@export var requires_circuit: String = ""
## Is this heat a FLAME — a brazier, a fire barrel, a hearth, a stove — rather than shelter?
## Owner, 2026-07-30: "Have warmth increase 30% faster rate when standing by stove/fire."
## Defaults TRUE because every mode +1 zone in the game IS a fire or a stove except the three
## on structures.gd's lean-to, bedroll and windbreak, which are insulation and opt out. Ignored
## entirely for cold zones (mode -1).
@export var fire: bool = true

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
		# Both counters are ADDITIVE and are unwound the same way, so overlapping fires (a
		# brazier inside a lean-to) count once each and leaving either one does not zero the
		# other. `_exit_tree` gives the same guarantee when a lit fire is picked up or freed.
		if fire and mode > 0:
			PlayerState.warmth_fire += 1 if want else -1
		_applied = want

## A zone freed (or a fire banked) while the player is standing in it never fires body_exited,
## so it hands its contribution back here — the same contract comfort_furniture's Hearth
## already relied on for warmth_zone.
func _exit_tree() -> void:
	if not _applied:
		return
	_applied = false
	PlayerState.warmth_zone -= mode
	if fire and mode > 0:
		PlayerState.warmth_fire -= 1
