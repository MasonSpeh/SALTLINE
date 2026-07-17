class_name LandmarkBeacon extends Node3D
## An invisible proximity beacon that files a place-Codex entry the first time the
## player wanders near a modeled landmark (the empty davits, the derrick floor).
## Same discover_if_near pattern the fire barrel uses — no geometry, just a marker.

var codex_id: String = ""
var radius: float = 8.0

func _process(_delta: float) -> void:
	if codex_id == "":
		set_process(false)
		return
	if Journal.discover_if_near(self, codex_id, radius):
		set_process(false)   # one-shot: stop polling once discovered
