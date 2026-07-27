class_name RainCatcherDock extends Interactable
## The bottling point of a player-built Rain Catcher: a caged cradle out front, under
## its own branch downspout, that holds ONE vessel.
##
##   DOCK  — cradle empty, a vessel in the pack            [E]
##   SWAP  — a vessel in the cradle AND one in the pack: they trade places
##   TAKE  — a vessel in the cradle and nothing to trade for it
##
## A docked EMPTY vessel fills while rain is actually reaching it and turns into the
## full, drinkable item. Which items are vessels, what they fill into, how long they take
## and which silhouette they wear is DATA — items.json "vessel" / "fills_to" /
## "fill_hours" / "vessel_kind" — so another canteen is an items.json entry, not code.
##
## The two fill gates are both READ-ONLY reads of the storm:
##   * intensity — StormSystem publishes only is_storming(), so the finer private field
##     is read defensively the way ambience.gd and comfort_furniture.gd already read it,
##     with the public bool as the fallback. Drizzle does not count: this is a squall
##     catcher, and a bottle that fills on a clear day is a bottle nobody builds for.
##   * shelter — StormSystem.COVER_BOXES, the SAME roofed volumes the rain particle
##     shader culls drops against. A cradle inside one gets nothing, and SAYS so, rather
##     than leaving the player waiting on a catcher bolted under a deck plate.

const SL := preload("res://scripts/world/structure_lib.gd")
const EFFECTS := preload("res://scripts/components/item_effects.gd")

const NOTIFY_RANGE: float = 9.0   ## only announce "it's full" to someone who could hear it
const COVER_RECHECK_SEC: float = 5.0

var docked: String = ""            ## item id sitting in the cradle ("" = empty)
var _fill_h: float = 0.0           ## game hours of rain caught by the docked vessel
var _hour_per_sec: float = 0.0     ## game hours per real second, from the clock's own day plan
var _visual: Node3D = null         ## the vessel standing in the cradle
var _water: Node3D = null          ## pivot at its floor; scaling Y raises the surface
var _storm: Node = null
var _sought: bool = false
var _covered: bool = false
var _cover_t: float = 0.0          ## re-probe the roof rarely; a placed catcher does not move

func _init() -> void:
	display_name = "Rain Catcher"
	verbs = ["DOCK"] as Array[String]

func _ready() -> void:
	# The item-effects domain rides along on whatever the world touches first; a catcher
	# built in a bare probe scene may be the only thing there is.
	EFFECTS.ensure()
	var day_sec: float = 0.0
	for phase in GameClock.phase_durations_minutes:
		day_sec += GameClock.phase_durations_minutes[phase] * 60.0
	_hour_per_sec = 24.0 / maxf(day_sec, 1.0)
	# One small collider hugging the cradle mouth. The tray and cage themselves are drawn
	# by structures.gd, so the build-mode ghost shows them too.
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.28, 0.40, 0.28)
	cs.shape = box
	add_child(cs)
	cs.position = Vector3(0, 0.16, 0)

# ============================================================ vessel bookkeeping

## items.json is the register of what can stand in the cradle.
func _def(id: String) -> Dictionary:
	return PlayerState.items.get(id, {})

func _is_vessel(id: String) -> bool:
	return bool(_def(id).get("vessel", false))

## What an empty vessel becomes once it is full ("" = already full, or not a vessel).
func _fills_to(id: String) -> String:
	return String(_def(id).get("fills_to", ""))

func _fill_hours(id: String) -> float:
	return maxf(float(_def(id).get("fill_hours", 2.0)), 0.05)

func _name_of(id: String) -> String:
	return String(_def(id).get("name", id))

## The vessel the player would hand over: what's in the hand first, then the belt, then
## the pack — the same order HangLine picks a fish in.
func _player_vessel() -> String:
	var sel: int = PlayerState.selected_hotbar
	if sel >= 0 and sel < PlayerState.HOTBAR_SIZE and PlayerState.hotbar[sel] != null \
			and _is_vessel(String(PlayerState.hotbar[sel])):
		return String(PlayerState.hotbar[sel])
	for it in PlayerState.hotbar:
		if it != null and _is_vessel(String(it)):
			return String(it)
	for it in PlayerState.inventory:
		if _is_vessel(String(it)):
			return String(it)
	return ""

# ============================================================ interaction

func available_verbs() -> Array[String]:
	var mine: String = _player_vessel()
	if docked == "":
		# An EMPTY verb list means InteractionRay shows no prompt at all, and a player with
		# no bottle would then walk past a cage under a dripping nozzle learning nothing.
		# LOOK is the same discoverability escape hatch Salvage.available_verbs uses for a
		# prop you lack the tool for: the station still speaks, it just can't be worked.
		return (["DOCK"] as Array[String]) if mine != "" else (["LOOK"] as Array[String])
	if mine != "":
		return ["SWAP"] as Array[String]
	return ["TAKE"] as Array[String]

func get_prompt() -> String:
	var v: Array[String] = available_verbs()
	if v[0] == "LOOK":
		return "%s — empty cradle. A bottle or a flask stands in here and the rain fills it." % display_name
	if docked == "":
		return "DOCK  %s  ·  cradle empty" % _name_of(_player_vessel())
	return "%s  %s  ·  %s" % [v[0], _name_of(docked), _state_line()]

## The honest read on what the cradle is doing. This one line is the whole tutorial for
## the station — including the failure case, which is the one worth explaining.
func _state_line() -> String:
	if _fills_to(docked) == "":
		return "full"
	var pct: int = int(round(100.0 * clampf(_fill_h / _fill_hours(docked), 0.0, 1.0)))
	if _covered:
		return "%d%% — nothing but steel overhead. It needs open sky." % pct
	if _rain_intensity() <= 0.0:
		return "%d%% — waiting on rain" % pct
	return "%d%% — filling" % pct

func interact(verb: String, player: Node3D) -> void:
	match verb:
		"DOCK":
			_dock(_player_vessel())
		"SWAP":
			_swap(_player_vessel())
		"TAKE":
			_take()
		"LOOK":
			_toast("Nothing to stand in it. A salvaged bottle or a crew thermos will do — "
				+ "the rigging bench makes both, and every desk on this rig has a flask on it.")
	super.interact(verb, player)

func _dock(id: String) -> void:
	if id == "" or docked != "":
		return
	PlayerState.remove_item(id)
	docked = id
	_fill_h = 0.0
	_refresh_visual()
	AudioDirector.play_one_shot("clang", global_position, -24.0)
	_toast("Set the %s in the cradle." % _name_of(id))

## The verb this station exists for: what's in your hand goes in, what was in the cradle
## comes out, one press. Full bottle out, empty one in, walk away.
func _swap(id: String) -> void:
	if id == "" or docked == "":
		return
	var out: String = docked
	if not PlayerState.add_item(out):
		return   # add_item already said the pack is full; never strand the vessel
	PlayerState.remove_item(id)
	docked = id
	_fill_h = 0.0
	_refresh_visual()
	AudioDirector.play_one_shot("clang", global_position, -24.0)
	_toast("Swapped: %s out, %s in." % [_name_of(out), _name_of(id)])

func _take() -> void:
	if docked == "":
		return
	if not PlayerState.add_item(docked):
		return
	var out: String = docked
	docked = ""
	_fill_h = 0.0
	_refresh_visual()
	_toast("Off the catcher: %s" % _name_of(out))

func _toast(msg: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast(msg)

# ============================================================ the fill loop

func _process(delta: float) -> void:
	if not _sought:
		_sought = true
		_storm = _find_storm()
	# The roof over a placed catcher never changes, so this is a cheap sanity re-probe,
	# not a per-frame test.
	_cover_t -= delta
	if _cover_t <= 0.0:
		_cover_t = COVER_RECHECK_SEC
		_covered = _under_cover(global_position)
	if docked == "" or _fills_to(docked) == "" or _covered:
		return
	var i: float = _rain_intensity()
	if i <= 0.0:
		return
	_fill_h += delta * GameClock.time_scale * _hour_per_sec * i
	_apply_level()
	if _fill_h >= _fill_hours(docked):
		_brim_over()

## The vessel is full: it becomes the drinkable item, in place, whether or not anyone
## was standing here when the last of the rain went in.
func _brim_over() -> void:
	var full: String = _fills_to(docked)
	docked = full
	_fill_h = 0.0
	_refresh_visual()
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null and player.global_position.distance_to(global_position) < NOTIFY_RANGE:
		AudioDirector.play_one_shot("hiss", global_position, -20.0)
		_toast("The catcher tops off: %s." % _name_of(full))

## Storm intensity 0..1, or 0 when there is no squall on.
func _rain_intensity() -> float:
	if not is_instance_valid(_storm):
		return 0.0
	var i: Variant = _storm.get("_intensity")
	if typeof(i) == TYPE_FLOAT:
		return clampf(float(i), 0.0, 1.0)
	if _storm.has_method("is_storming"):
		return 1.0 if bool(_storm.call("is_storming")) else 0.0
	return 0.0

## StormSystem is a child of Main, which is not our ancestor once the kit is placed under
## a structures root — so search from the tree root, the way ambience.gd does.
func _find_storm() -> Node:
	var stack: Array = [get_tree().root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is StormSystem:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

## Is this point inside one of the roofed volumes the rain shader culls drops against?
## Mirrors StormSystem._push_cover_boxes exactly: the margin grows the box sideways and
## downward but never upward, because the top face IS the roof.
func _under_cover(p: Vector3) -> bool:
	var m: float = StormSystem.COVER_MARGIN
	for b: Array in StormSystem.COVER_BOXES:
		if p.x >= float(b[0]) - m and p.x <= float(b[3]) + m \
				and p.y >= float(b[1]) - m and p.y <= float(b[4]) \
				and p.z >= float(b[2]) - m and p.z <= float(b[5]) + m:
			return true
	return false

# ============================================================ what stands in the cradle

## Rebuild the vessel in the cradle from scratch — it only ever changes on a dock, a
## swap, a take, or the moment it brims over.
func _refresh_visual() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null
	_water = null
	if docked == "":
		return
	_visual = Node3D.new()
	add_child(_visual)
	_visual.position = Vector3(0, 0.02, 0)
	if String(_def(docked).get("vessel_kind", "bottle")) == "flask":
		_build_flask(_visual)
	else:
		_build_bottle(_visual)
	_apply_level()

## Raise the water surface to the fill fraction. A vessel with no `fills_to` is already
## full, so it reads full even though its clock has been reset.
func _apply_level() -> void:
	if _water == null or not is_instance_valid(_water):
		return
	var f: float = 1.0
	if _fills_to(docked) != "":
		f = clampf(_fill_h / _fill_hours(docked), 0.03, 1.0)
	_water.scale = Vector3(1.0, f, 1.0)

## A salvaged glass bottle: shoulder, tapered neck, driftwood bung, a rope collar where
## a hand goes, and the water on its own pivot so the rising line reads through the glass.
##
## The geometry moved to ItemVisual.vessel_bottle on 2026-07-26, when the pack started
## showing items instead of naming them: bottle_empty and bottle_water were anonymous cubes
## in the inventory while THIS bottle stood in the cradle beside them. One builder now
## serves both, and the cradle always gets the water column (the level starts at 3%).
func _build_bottle(root: Node3D) -> void:
	_water = ItemVisual.vessel_bottle(root, true)

## A crew vacuum flask: dented galvanised shell, dark screw cap, canvas carry straps.
## Opaque on purpose — the prompt carries the level for this one, because a steel flask
## with a visible water line would be a lie about what a thermos is. Hence `false`: the
## packed thermos_water shows its cap off as a brimming cup, but a docked one never has to.
func _build_flask(root: Node3D) -> void:
	ItemVisual.vessel_flask(root, false)
