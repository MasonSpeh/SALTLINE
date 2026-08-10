extends Interactable
## THE ANCHORAGE AQUARIUM — the stocking hatch on the tank-top platform.
##
## The player stands at the feeding hatch with a fish selected on the hotbar and presses
## the verb; the fish goes into the tank and starts circling the coral core at its real
## landed size. Two owner rules, enforced here and said out loud:
##   * no single fish longer than 5 ft  -> "This Un's too big to fit."
##   * no more than 50 ft of fish total -> the tank is full.
##
## Lengths come from ItemVisual.fish_instance_length_m — the same weight->length relation
## the dropped-fish renderer uses, so the fish in the tank is exactly the fish you caught.
##
## HONEST LIMIT: stock does not persist through a save yet (filed in KNOWN_ISSUES). The
## marker node in group "aquarium" carries the geometry; this node carries the rules.

const FISH_MODEL := preload("res://scripts/world/fish_model_lib.gd")
const IV := preload("res://scripts/world/item_visual.gd")

const MAX_ONE_M: float = 1.524     ## 5 ft
const MAX_TOTAL_M: float = 15.24   ## 50 ft

## Set by the builder before add_child — the WATER volume, world space.
var tank_centre: Vector3 = Vector3.ZERO
var tank_r: float = 4.5
var water_y0: float = 0.0
var water_y1: float = 1.0

var _stock: Array = []      ## [{"id": String, "kg": float, "len": float}]
var _swimmers: Array = []   ## [{"node": Node3D, "r": float, "h": float, "w": float, "ang": float, "bob": float}]
var _total_m: float = 0.0

func _ready() -> void:
	display_name = "Aquarium Hatch"
	verbs = ["ADD FISH"] as Array[String]
	build_box_visual(Vector3(0.9, 0.5, 0.9), COLOR_OPERABLE, false, false, MatLib.dark_metal())

func get_prompt() -> String:
	return "ADD FISH  Aquarium  (%.0f/%.0f ft stocked)" % [_total_m * 3.281, MAX_TOTAL_M * 3.281]

func interact(_verb: String, _player: Node3D) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var idx: int = PlayerState.selected_hotbar
	if idx < 0 or idx >= PlayerState.hotbar.size() or PlayerState.hotbar[idx] == null:
		if hud != null:
			hud.toast("Hold a fish on the hotbar to add it.")
		return
	var id: String = String(PlayerState.hotbar[idx])
	if not id.begins_with("fish_"):
		if hud != null:
			hud.toast("Only fish go in the tank.")
		return
	var kg: float = float(PlayerState.as_meta(PlayerState.hotbar_meta[idx]).get("kg", 0.0))
	var len_m: float = IV.fish_instance_length_m(id, kg)
	if len_m > MAX_ONE_M:
		if hud != null:
			hud.toast("This Un's too big to fit.")
		return
	if _total_m + len_m > MAX_TOTAL_M:
		if hud != null:
			hud.toast("The tank's full up — %.0f ft of fish already home." % (_total_m * 3.281))
		return
	var got: Dictionary = PlayerState.take_one_at(idx)
	if not bool(got.get("ok", false)):
		return
	_stock.append({"id": id, "kg": kg, "len": len_m})
	_total_m += len_m
	_spawn_swimmer(id, len_m)
	if hud != null:
		hud.toast("She slips in and circles the coral. (%.0f/%.0f ft)" % [_total_m * 3.281, MAX_TOTAL_M * 3.281])
	interacted.emit("ADD FISH")

func _spawn_swimmer(item_id: String, len_m: float) -> void:
	var species: String = FISH_MODEL.species_of(item_id)
	if not FISH_MODEL.has_model(species):
		return
	var body: Node3D = FISH_MODEL.build(species, false, maxf(len_m, 0.15))
	get_parent().add_child(body)
	var n: int = _swimmers.size()
	# Each fish owns a lane: radius between the coral core and the glass, height staggered.
	var lane_r: float = clampf(2.2 + fmod(float(n) * 0.83, 1.0) * (tank_r - 3.0), 2.0, tank_r - 0.7)
	var lane_h: float = lerpf(water_y0 + 1.2, water_y1 - 1.0, fmod(float(n) * 0.37 + 0.15, 1.0))
	_swimmers.append({"node": body, "r": lane_r, "h": lane_h,
		"w": (0.25 + fmod(float(n) * 0.29, 1.0) * 0.2) * (1.0 if n % 2 == 0 else -1.0),
		"ang": fmod(float(n) * 2.4, TAU), "bob": fmod(float(n) * 1.7, TAU)})

func _process(delta: float) -> void:
	for s in _swimmers:
		s["ang"] = fmod(s["ang"] + s["w"] * delta, TAU)
		var a: float = s["ang"]
		var node: Node3D = s["node"]
		var p := Vector3(tank_centre.x + cos(a) * s["r"],
			s["h"] + sin(a * 3.0 + s["bob"]) * 0.25,
			tank_centre.z + sin(a) * s["r"])
		node.global_position = p
		# Face the swim tangent (models face +Z after FishModelLib's facing correction).
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(s["w"])
		node.look_at(p + tangent, Vector3.UP)
