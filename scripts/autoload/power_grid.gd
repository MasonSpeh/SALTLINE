extends Node
## Owns the circuit graph state for the rig's electrical systems.
## BreakerPanel/CableSegment/LightZone components read and mutate this via the API below.

signal circuit_powered(id: String)
signal circuit_lost(id: String)

var _powered_circuits: Dictionary = {} ## id: String -> true

## Lag-spike fix: closing the topside breaker used to fire ~70 lights (some
## shadow-casting) and ~70 fresh Material allocations synchronously inside this one
## emit() — one frame doing a whole rig's worth of light-engine + resource work at
## once. Callers now hand their per-light "turn on" work to queue_light() instead of
## running it inline in their circuit_powered.connect() closures; this drains a few
## per tick on a short timer so the rig visibly wakes up over about half a second
## instead of spiking a single frame.
var _stagger_queue: Array[Callable] = []
var _stagger_draining: bool = false
const STAGGER_PER_TICK: int = 4
const STAGGER_INTERVAL: float = 0.03

func power_circuit(id: String) -> void:
	if _powered_circuits.has(id):
		return
	_powered_circuits[id] = true
	circuit_powered.emit(id)

## Defer one light's "wake up" work (visibility + material swap) so a whole rig's
## worth of them do not land in the same frame. Safe to call from a circuit_powered
## handler for a light that is being newly built (not yet in the tree edge case
## doesn't apply here — callers always add_child() first).
func queue_light(cb: Callable) -> void:
	_stagger_queue.append(cb)
	if not _stagger_draining:
		_stagger_draining = true
		_drain_stagger()

func _drain_stagger() -> void:
	var n: int = 0
	while n < STAGGER_PER_TICK and not _stagger_queue.is_empty():
		var cb: Callable = _stagger_queue.pop_front()
		if cb.is_valid():
			cb.call()
		n += 1
	if _stagger_queue.is_empty():
		_stagger_draining = false
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree:
		tree.create_timer(STAGGER_INTERVAL).timeout.connect(_drain_stagger)
	else:
		_drain_stagger()

func lose_circuit(id: String) -> void:
	if not _powered_circuits.has(id):
		return
	_powered_circuits.erase(id)
	circuit_lost.emit(id)

func is_powered(id: String) -> bool:
	return _powered_circuits.has(id)

func powered_ids() -> Array:
	return _powered_circuits.keys()
