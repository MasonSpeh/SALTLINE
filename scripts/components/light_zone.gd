class_name LightZone extends Node3D
## A deck zone whose lights come alive when its circuit is powered. Powered zones are
## the night safe area (Rule 7): the crab will not enter, the player is safe inside.

@export var circuit_id: String = "topside_floodlights"
@export var zone_extents: Vector3 = Vector3(20, 6, 14)

var _lights: Array[Light3D] = []

func _ready() -> void:
	add_to_group("light_zones")
	PowerGrid.circuit_powered.connect(_on_powered)
	PowerGrid.circuit_lost.connect(_on_lost)
	for c in get_children():
		if c is Light3D:
			_lights.append(c)
			c.visible = is_lit()   # circuit may already be live (e.g. bloom lamps)

func add_light(l: Light3D) -> void:
	add_child(l)
	_lights.append(l)
	l.visible = is_lit()

func is_lit() -> bool:
	return PowerGrid.is_powered(circuit_id)

func contains(world_point: Vector3) -> bool:
	var local: Vector3 = to_local(world_point)
	return absf(local.x) <= zone_extents.x * 0.5 \
		and absf(local.y) <= zone_extents.y * 0.5 \
		and absf(local.z) <= zone_extents.z * 0.5

func _on_powered(id: String) -> void:
	if id == circuit_id:
		for l in _lights:
			l.visible = true

func _on_lost(id: String) -> void:
	if id == circuit_id:
		for l in _lights:
			l.visible = false

## Global helper: is a world point inside ANY powered light zone?
static func point_is_safe(tree: SceneTree, world_point: Vector3) -> bool:
	for z in tree.get_nodes_in_group("light_zones"):
		if z is LightZone and z.is_lit() and z.contains(world_point):
			return true
	return false
