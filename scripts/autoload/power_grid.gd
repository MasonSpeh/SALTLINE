extends Node
## Owns the circuit graph state for the rig's electrical systems.
## BreakerPanel/CableSegment/LightZone components read and mutate this via the API below.

signal circuit_powered(id: String)
signal circuit_lost(id: String)

var _powered_circuits: Dictionary = {} ## id: String -> true

func power_circuit(id: String) -> void:
	if _powered_circuits.has(id):
		return
	_powered_circuits[id] = true
	circuit_powered.emit(id)

func lose_circuit(id: String) -> void:
	if not _powered_circuits.has(id):
		return
	_powered_circuits.erase(id)
	circuit_lost.emit(id)

func is_powered(id: String) -> bool:
	return _powered_circuits.has(id)

func powered_ids() -> Array:
	return _powered_circuits.keys()
