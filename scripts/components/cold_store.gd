class_name ColdStore extends LootContainer
## The dining-hall fridge. OPEN it and you get the ordinary crate ⇄ pack exchange panel
## — the same UI every found locker, job box and stash on the rig uses (see
## loot_container.gd / world_storage.gd) — so there is nothing new to learn and its
## contents save and reload with everything else.
##
## WHAT MAKES IT A FRIDGE, NOT A CUPBOARD, IS THE POWER.
##
##   POWERED   — the compressor runs. Anything inside is held at zero on the spoil
##               clock: put a fish in a cold fridge and it will be exactly as fresh
##               whenever you come back for it. This is the zero-thought preservation
##               option; the drying line is the clever one.
##   UNPOWERED — a dead white box. It will not open at all, and the chill it was
##               holding starts to go: after FRESH_HOURS of warm the raw catch inside
##               turns, exactly as it would on the line (see hang_line.gd, which owns
##               the same clock and the same fish_rotten outcome).
##
## The spoil model is deliberately the drying line's, not a second one: SALTLINE has
## no per-item freshness field, it has a TIMER attached to the place a fish is being
## kept. HangLine ages each hook; this ages the whole cabinet, and only while it is
## warm. Nothing in the pack has ever spoiled and nothing here changes that.

const FISH := preload("res://scripts/world/fish_table.gd")

## The rig's one lighting/services circuit — the same gate the mains lights and the
## range are on, closed by the master breaker in 4-A.
const CIRCUIT: String = "topside_floodlights"

## Game hours a warm fridge takes to turn its contents. Matches HangLine.FRESH_HOURS:
## a fish left out is a fish left out, wherever it was left.
const FRESH_HOURS: float = 4.0

## Game hours this cabinet has spent WARM with something in it. Reset to zero the
## instant power comes back, which is what "the fridge preserves" means mechanically.
var _warm_h: float = 0.0
var _game_hour_per_sec: float = 0.0
var _door_lamp: MeshInstance3D = null

func _init() -> void:
	display_name = "Dining Hall Fridge"
	verbs = ["OPEN"] as Array[String]

func _ready() -> void:
	super()   # LootContainer: join "loot_container", reclaim saved contents
	# LootContainer darkens its own box the first time it is opened — a nice touch on a
	# scrap crate, but the fridge is drawn with MatLib.dirty_white_panel(), and MatLib
	# CACHES its materials, so darkening it would darken every dirty-white panel on the
	# rig. Mark it already-opened so that branch never runs; the hatch sound is played
	# here instead so opening still sounds like opening.
	_opened = true
	# One game hour in real seconds, from the clock's own day plan (hang_line.gd idiom).
	var day_sec: float = 0.0
	for phase in GameClock.phase_durations_minutes:
		day_sec += GameClock.phase_durations_minutes[phase] * 60.0
	_game_hour_per_sec = 24.0 / maxf(day_sec, 1.0)
	# A status lamp on the door face. rig_builder gives this node a 0.9 x 1.9 x 0.9 box
	# standing against the west bulkhead with its door facing the hall (+X), so the lamp
	# rides local +X. Green when the compressor is running, dead otherwise — from the
	# far end of the hall it is how you know whether the power got as far as the kitchen.
	_door_lamp = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.06, 0.12)
	bm.material = MatLib.flat(Color(0.10, 0.11, 0.10))
	_door_lamp.mesh = bm
	_door_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_door_lamp)
	_door_lamp.position = Vector3(0.46, 0.66, -0.24)
	_refresh_lamp()
	PowerGrid.circuit_powered.connect(_on_power_change)
	PowerGrid.circuit_lost.connect(_on_power_change)

func _powered() -> bool:
	return PowerGrid.is_powered(CIRCUIT)

func _on_power_change(id: String) -> void:
	if id == CIRCUIT:
		_refresh_lamp()

func _refresh_lamp() -> void:
	if not is_instance_valid(_door_lamp) or _door_lamp.mesh == null:
		return
	# A fresh material per state, taken from the MatLib cache — never mutated in place.
	(_door_lamp.mesh as BoxMesh).material = MatLib.flat(Color(0.35, 0.95, 0.45), true, 2.0) \
		if _powered() else MatLib.flat(Color(0.10, 0.11, 0.10))

func get_prompt() -> String:
	if not _powered():
		return "OPEN  %s (dead — no power)" % display_name
	return "OPEN  %s (%d cold)" % [display_name, items.size()]

func interact(verb: String, player: Node3D) -> void:
	if verb != "OPEN":
		return
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not _powered():
		# A dead fridge is a sealed box, not a cupboard: refusing to open is the clearest
		# possible statement that the thing runs on the breaker.
		if hud:
			if items.is_empty():
				hud.toast("The fridge is dead — no power on this circuit. The seal has gone stiff.")
			else:
				hud.toast("The fridge is dead — no power. Whatever is in there is going over.")
		return
	AudioDirector.play_one_shot("hatch", global_position, -12.0)
	Journal.discover("system_preserving")
	super.interact(verb, player)   # LootContainer opens the crate ⇄ pack panel

## The warm clock. Only ever advances while the cabinet is unpowered AND has something
## in it; power resets it, which is the whole preservation mechanic in one line.
func _process(delta: float) -> void:
	if items.is_empty():
		_warm_h = 0.0
		return
	if _powered():
		_warm_h = 0.0
		return
	_warm_h += delta * GameClock.time_scale * _game_hour_per_sec
	if _warm_h >= FRESH_HOURS:
		_warm_h = 0.0
		_turn()

## What a warm cabinet does to what is in it: raw catch turns, cooked meals turn, and
## anything already rotten, dried or non-perishable is left exactly as it is.
func _turn() -> void:
	var spoiled: int = 0
	for i in range(items.size()):
		var id: String = String(items[i])
		if _perishable(id):
			items[i] = "fish_rotten"
			spoiled += 1
	if spoiled <= 0:
		return
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Something has turned in the dead fridge.")

## Perishable = a raw catch (it has a cooked form) or a cooked meal. Dried fish keeps
## forever by definition, and fish_rotten cannot get worse.
static func _perishable(id: String) -> bool:
	if id == "dried_fish" or id == "fish_rotten":
		return false
	return FISH.cooked_for(id) != "" or id.begins_with("cooked_fish") or id == "cooked_sea_bird"
