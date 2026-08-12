extends Node3D
## FIELD DRESSING — the CC0 glTF prop library, in the three FIELD rigs.
##
## MARROW, THE ANCHORAGE and DEEPWELL were built entirely from RigKit.Bake primitives:
## every "sofa", "bed" and "chair" on them is an untextured box, and DEEPWELL's lab,
## control room and shaker house are empty shells. Rig 1 has had a real prop library since
## s20 (`interior_props.gd`, 222 CC0 models in assets/models) and the field never got it.
## This is that pass. It is the same library, the same loader, the same auto-settle — the
## only new problem is that these rigs stand somewhere else and face somewhere else.
##
## THE ONE THING THIS FILE OWNS: rig-local -> world. Every coordinate in the tables below is
## in the OWNING RIG'S OWN FRAME, exactly like `rig_field._anchorage_supplies()`, so a row
## can be checked against the named constants at the top of rig_two/rig_three/rig_four.gd
## instead of against a world number nobody can verify. `_place()` applies the rig's
## Transform3D to the position and ADDS the rig's bearing to the yaw — forgetting the second
## half is how a room full of furniture ends up correctly positioned and all facing 10
## degrees off the wall it is supposed to back onto.
##
## AUTHORED Y IS THE SUPPORTING SURFACE'S TOP, not the object's origin. SupportIndex settles
## every loose item onto the visual mesh actually beneath it after the world is built, so a
## row only has to be RIGHT IN XZ and roughly right in Y. This is the same contract
## interior_props.gd works under and the reason no Y in this file is a hand-tuned magic
## number. (See support_index.gd for why a physics raycast cannot do this job: most dressing
## geometry here is non-colliding, so a downward ray from a mug on a desk reports the deck
## 80 cm below and rains the desk's contents onto the floor.)
##
## DRAW BUDGET — WHY THESE PROPS DECLARE THEIR OWN RANGE. rig_batcher.gd welds rig 1's loose
## dressing into one mesh per material, but `main.gd` hands it `rig_root = RigBuilder`, so
## the field is outside its scope and every prop here stays its own draw call. Left to
## render_budget.gd's size rule a 2 m sofa would draw out to 200 m — and the rigs are only
## 161/166/164 m apart, so standing on MARROW would submit every chair inside THE ANCHORAGE.
## Interior dressing therefore sets `visibility_range_end` itself; render_budget explicitly
## skips any mesh that already has one (`_sweep`: `or mi.visibility_range_end > 0.0`), so
## this wins without fighting it. Nothing here is visible from a neighbouring rig anyway —
## it is all indoors, and the rigs read as silhouettes at that range.
##
## PHYSICS POSTURE. Big furniture is STATIC (a StaticBody3D box), small clutter is a
## grabbable MovableProp — the split is by size, not by taste. Rig 1 makes almost everything
## draggable, which is right for a working platform you are salvaging; a hotel whose
## armchairs slide across the floor when you brush them reads as a physics demo, and 150
## extra rigid bodies across three rigs is a cost with no picture to show for it.

const PropLibC := preload("res://scripts/world/prop_lib.gd")
const SUPPORT := preload("res://scripts/world/support_index.gd")

## Interior dressing is never read from another platform — see the draw-budget note above.
const INTERIOR_DRAW_M: float = 70.0
const INTERIOR_FADE_M: float = 12.0
## Props on open decks and terraces read from further out, where they are the only thing
## saying "people live here" on an otherwise geometric silhouette.
const EXTERIOR_DRAW_M: float = 120.0

## Anything whose normalized longest axis is under this is small enough to pick up; bigger
## things are furniture and stay where they were put.
const MOVABLE_MAX_M: float = 0.55

## Instancing ~200 glTF scenes in one frame stalls the main thread for seconds — the "Play
## freezes" bug interior_props.gd was restructured to fix. Queue cheaply, instance a few per
## frame, settle once at the end.
const PER_FRAME: int = 4

## rig id -> local->world Transform3D, handed over by rig_field.gd after the rigs are built.
var xforms: Dictionary = {}

var _queue: Array = []          ## [id, world_pos, world_yaw, scale_mul, mode, exterior]
var _placed: Array = []         ## [node, settle: bool]
var placed_count: int = 0
var settle_complete: bool = false
signal settle_done

func _ready() -> void:
	name = "FieldDress"
	for row in MARROW():
		_queue_row("marrow", row)
	for row in ANCHORAGE():
		_queue_row("anchorage", row)
	for row in DEEPWELL():
		_queue_row("deepwell", row)
	_stream()

# ------------------------------------------------------------------------------ placement

## A table row is [id, local_pos, yaw_deg, scale_mul, mode, exterior?] with everything after
## the position optional. `mode` is "" (auto by size), "fix" (static, never grabbable) or
## "wall" (mounted/hanging: exempt from the settle, since there is nothing under it and
## there is not meant to be).
func _queue_row(rig: String, row: Array) -> void:
	var xf: Transform3D = xforms.get(rig, Transform3D.IDENTITY)
	var id: String = String(row[0])
	var local: Vector3 = row[1]
	var yaw: float = float(row[2]) if row.size() > 2 else 0.0
	var scale_mul: float = float(row[3]) if row.size() > 3 else 1.0
	var mode: String = String(row[4]) if row.size() > 4 else ""
	var exterior: bool = bool(row[5]) if row.size() > 5 else false
	# The rig's bearing has to reach the yaw as well as the position, or every piece of
	# furniture on a rig with a non-zero bearing sits right and faces wrong.
	var rig_yaw: float = rad_to_deg(xf.basis.get_euler().y)
	_queue.append([id, xf * local, yaw + rig_yaw, scale_mul, mode, exterior])

func _stream() -> void:
	var i: int = 0
	for item in _queue:
		if not is_instance_valid(self):
			return
		_spawn(item)
		i += 1
		if i % PER_FRAME == 0:
			await get_tree().process_frame
	_queue.clear()
	await _settle_all()
	if not is_instance_valid(self):
		return
	settle_complete = true
	settle_done.emit()
	print("[field-dress] %d props placed across %d rigs, settled" % [placed_count, xforms.size()])

func _spawn(item: Array) -> void:
	var id: String = item[0]
	var mode: String = item[4]
	var wall: bool = mode == "wall"
	# Size decides whether a thing can be carried; the library's own FIXED list still wins,
	# so a nightstand or a wall lamp stays put whatever its footprint says.
	var hint: float = float(PropLibC.SIZE_HINT.get(id, 0.6)) * float(item[3])
	var movable: bool = (mode == "") and hint <= MOVABLE_MAX_M and PropLibC.is_moveable(id)
	var collide: bool = not movable and not wall
	var node: Node3D = PropLibC.spawn(id, self, item[1], item[2], item[3], collide, -1.0, movable)
	if node == null:
		return
	placed_count += 1
	node.add_to_group("dress_prop")
	if wall:
		node.add_to_group("placement_exempt")
	_range_limit(node, EXTERIOR_DRAW_M if bool(item[5]) else INTERIOR_DRAW_M)
	_placed.append([node, not wall])

## Declare the prop's own draw range so render_budget.gd leaves it alone (it skips any mesh
## that already carries a range). Without this, interior furniture is submitted from the
## next platform along.
func _range_limit(node: Node3D, reach: float) -> void:
	for mi in _meshes(node):
		mi.visibility_range_end = reach
		mi.visibility_range_end_margin = INTERIOR_FADE_M
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.set_meta("budgeted", true)

func _meshes(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for k in c.get_children():
			stack.append(k)
		if c is GeometryInstance3D:
			out.append(c)
	return out

# -------------------------------------------------------------------------------- settling

## Two passes, for the reason interior_props.gd gives: the index is a snapshot, and pass one
## moves the very surfaces some items were resolved against.
func _settle_all() -> void:
	for _pass in range(2):
		await _settle_pass()

func _settle_pass() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	var index = SUPPORT.new()
	index.build(root)
	var jobs: Array = []
	for rec in _placed:
		if rec[1] and is_instance_valid(rec[0]):
			jobs.append(rec[0])
	# Lowest first, so an item stacked on another lands after the one under it.
	jobs.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	var i: int = 0
	for node in jobs:
		index.settle(node)
		i += 1
		if i % 40 == 0:
			await get_tree().process_frame

# ---------------------------------------------------------------------------------- tables
#
# Coordinates are RIG-LOCAL. Check them against the constants at the top of the owning rig
# script — rig_two.gd (MARROW), rig_three.gd (THE ANCHORAGE), rig_four.gd (DEEPWELL).
# Y is the top of the surface the item belongs on; the settle pass does the rest.

const T2 := preload("res://scripts/world/rig_two.gd")
const T3 := preload("res://scripts/world/rig_three.gd")
const T4 := preload("res://scripts/world/rig_four.gd")

func MARROW() -> Array:
	return []

func ANCHORAGE() -> Array:
	return []

## DEEPWELL — the drilling rig. Every row here is a WORKING object: this platform's story is
## that the last shift walked out mid-alarm, so the dressing is tools set down rather than
## tools put away. Rooms are the four `_interiors()` built in rig_four.gd this session.
func DEEPWELL() -> Array:
	return [
		# --- control room (lookout on lab roof)
		["metal_office_desk", Vector3(23.3, 26.6, -21.2), 90.0, 1.35],
		["metal_office_desk", Vector3(23.3, 26.6, -19.6), 90.0, 1.35],
		["metal_office_desk", Vector3(23.3, 26.6, -18), 90.0, 1.35],
		["metal_stool_01", Vector3(22.2, 26.6, -21.2), 0.0, 1.0],
		["metal_stool_02", Vector3(22.2, 26.6, -19.6), 25.0, 1.0],
		["plastic_monobloc_chair_01", Vector3(22, 26.6, -18), 270.0, 1.0],
		["vintage_radio_transceiver", Vector3(23.35, 27.32, -21.5), 90.0, 1.2],
		["television_02", Vector3(23.35, 27.32, -19.6), 90.0, 1.3],
		["retro_multimeter", Vector3(22.95, 27.32, -20.3), 20.0, 1.0],
		["classic_laptop", Vector3(23.3, 27.32, -18.1), 90.0, 1.0],
		["clipboard", Vector3(23, 27.32, -20.9), 40.0, 1.0],
		["binder_notebook", Vector3(23.15, 27.32, -18.6), 105.0, 1.0],
		["Megaphone_01", Vector3(23.3, 27.32, -21.9), 60.0, 1.0],
		["old_gas_mask", Vector3(22.9, 27.32, -18.9), 15.0, 1.0],
		["desk_lamp_arm_01", Vector3(23.5, 27.32, -20.5), 90.0, 1.0],
		["drawer_cabinet", Vector3(15.5, 26.6, -22.35), 0.0, 1.1],
		["steel_frame_shelves_02", Vector3(18.6, 26.6, -22.4), 0.0, 1.6],
		["worn_metal_rack", Vector3(16, 26.6, -15.6), 180.0, 1.7],
		["metal_trash_can", Vector3(23.3, 26.6, -22.3), 0.0, 1.0],
		# --- core sample lab, ground floor
		["steel_frame_shelves_02", Vector3(12.6, 20, -12.6), 180.0, 1.6],
		["steel_frame_shelves_01", Vector3(15.2, 20, -12.6), 180.0, 1.6],
		["worn_metal_rack", Vector3(17.6, 20, -12.6), 180.0, 1.7],
		["worn_metal_rack", Vector3(23.5, 20, -12.6), 180.0, 1.7],
		["metal_office_desk", Vector3(13.5, 20, -25.2), 0.0, 1.3],
		["metal_office_desk", Vector3(17.2, 20, -25.2), 0.0, 1.3],
		["bench_vice_01", Vector3(13.9, 20.72, -25.2), 0.0, 1.2],
		["spray_paint_bottles", Vector3(17.6, 20.72, -25.2), 0.0, 1.0],
		["metal_stool_01", Vector3(13.5, 20, -24.3), 0.0, 1.0],
		["metal_stool_02", Vector3(17.2, 20, -24.3), 30.0, 1.0],
		["wooden_military_crate", Vector3(29, 20, -24.6), 90.0, 1.0],
		["old_military_crate", Vector3(29, 20, -23), 90.0, 1.0],
		["ammo_box", Vector3(29, 20.55, -23), 100.0, 1.0],
		["cement_bag", Vector3(28.7, 20, -15.2), 20.0, 1.0],
		["industrial_storage_cart", Vector3(24.5, 20, -22.5), 90.0, 1.0],
		["korean_fire_extinguisher_01", Vector3(10.55, 20.9, -20.7), 270.0, 1.0, "wall"],
		["mounted_fluorescent_lights", Vector3(16, 22.9, -18), 0.0, 1.0, "wall"],
		["mounted_fluorescent_lights", Vector3(24, 22.9, -21), 0.0, 1.0, "wall"],
		# --- core sample lab, upper storey
		["metal_office_desk", Vector3(11.3, 23.3, -22), 90.0, 1.3],
		["metal_office_desk", Vector3(11.3, 23.3, -15.8), 90.0, 1.3],
		["television_02", Vector3(11.55, 24.02, -22), 90.0, 1.3],
		["vintage_radio_transceiver", Vector3(11.55, 24.02, -15.8), 90.0, 1.2],
		["plastic_monobloc_chair_01", Vector3(12.5, 23.3, -22), 90.0, 1.0],
		["metal_stool_01", Vector3(12.5, 23.3, -15.8), 0.0, 1.0],
		["old_gas_mask", Vector3(11.6, 24.02, -21.2), 40.0, 1.0],
		["steel_frame_shelves_01", Vector3(16.5, 23.3, -12.6), 180.0, 1.6],
		["worn_metal_rack", Vector3(29, 23.3, -20), 270.0, 1.7],
		["wooden_crate_02", Vector3(28.8, 23.3, -24.4), 90.0, 1.0],
		["plastic_crate_01", Vector3(28.8, 23.3, -23.3), 70.0, 1.0],
		# --- shaker house / pump room
		["Barrel_01", Vector3(-30, 20, 14.5), 0.0, 1.0],
		["Barrel_02", Vector3(-30, 20, 15.7), 40.0, 1.0],
		["cement_bag", Vector3(-30.1, 20, 12.3), 10.0, 1.0],
		["cement_bag", Vector3(-29.4, 20, 12.3), 195.0, 1.0],
		["worn_metal_rack", Vector3(-26, 20, 23.2), 180.0, 1.7],
		["steel_frame_shelves_02", Vector3(-22.8, 20, 23.2), 180.0, 1.6],
		["metal_tool_chest", Vector3(-13.5, 20, 23.2), 180.0, 1.0],
		["portable_welding_cart", Vector3(-11, 20, 21.8), 270.0, 1.0],
		["propane_tank", Vector3(-10.2, 20, 20.2), 0.0, 1.4],
		["hand_truck", Vector3(-30.2, 20, 19.6), 90.0, 1.0],
		["metal_jerrycan", Vector3(-29.9, 20, 17.8), 25.0, 1.0],
		["caged_hanging_light", Vector3(-24, 25.1, 17), 0.0, 3.0, "wall"],
		["caged_hanging_light", Vector3(-16, 25.1, 17), 0.0, 3.0, "wall"],
		["korean_fire_extinguisher_01", Vector3(-9.7, 21, 18.6), 90.0, 1.0, "wall"],
		["power_box_01", Vector3(-9.75, 21.2, 14), 90.0, 1.2, "wall"],
		# --- decon airlock
		["steel_frame_shelves_02", Vector3(-6.2, 20, -29.6), 90.0, 1.6],
		["worn_metal_rack", Vector3(-6.2, 20, -26.2), 90.0, 1.7],
		["life_jacket", Vector3(-6.2, 21, -29.6), 90.0, 1.0, "wall"],
		["old_gas_mask", Vector3(-6.2, 21, -29), 70.0, 1.0, "wall"],
		["garden_gloves_01", Vector3(-6.3, 21, -28.5), 15.0, 1.0, "wall"],
		["rubber_boots", Vector3(-5.7, 20, -30.3), 35.0, 1.0],
		["WetFloorSign_01", Vector3(-4.2, 20, -27.2), 20.0, 1.0],
		["korean_fire_extinguisher_01", Vector3(-6.5, 21, -27.6), 90.0, 1.0, "wall"],
		["industrial_wall_lamp", Vector3(4.55, 22.3, -27.5), 270.0, 1.2, "wall"],
		# --- drill floor
		["metal_tool_chest", Vector3(10.6, 30, 2), 90.0, 1.0],
		["metal_toolbox", Vector3(10.6, 30.9, 2), 100.0, 1.0],
		["Barrel_01", Vector3(10.8, 30, 7.6), 0.0, 1.0],
		["Barrel_02", Vector3(10, 30, 8.6), 30.0, 1.0],
		["old_military_crate", Vector3(7.8, 30, 10.6), 8.0, 1.0],
		["portable_welding_cart", Vector3(-10.4, 30, 9.6), 90.0, 1.0],
		["propane_tank", Vector3(-11, 30, 7.4), 0.0, 1.4],
		["hand_truck", Vector3(11, 30, -2), 0.0, 1.0],
		["korean_fire_extinguisher_01", Vector3(11.15, 31.3, 11.9), 270.0, 1.0, "wall"],
		# --- main deck lay-down (south-east of the V-door)
		["old_military_crate", Vector3(5.2, 20, -18.2), 15.0, 1.0],
		["wooden_military_crate", Vector3(6.4, 20, -18.9), -12.0, 1.0],
		["Barrel_01", Vector3(4.3, 20, -19.6), 0.0, 1.0],
		# --- main deck (shaker house east wall)
		["portable_generator", Vector3(-8.2, 20, 13), 90.0, 1.0],
		# --- main deck (south rail)
		["lifebuoy", Vector3(-8, 21, -32.62), 0.0, 1.0, "wall"],
		# --- production deck
		["Barrel_01", Vector3(8.4, 11.3, -25.6), 0.0, 1.0],
		["Barrel_02", Vector3(9.4, 11.3, -25.6), 35.0, 1.0],
		["metal_jerrycan", Vector3(10.4, 11.3, -25.6), 20.0, 1.0],
		["portable_welding_cart", Vector3(13.6, 11.3, -24.6), 180.0, 1.0],
		["metal_tool_chest", Vector3(16, 11.3, -25.6), 180.0, 1.0],
		["cement_bag", Vector3(7.8, 11.3, 16.4), 10.0, 1.0],
		["steel_frame_shelves_01", Vector3(25.6, 11.3, -19), 270.0, 1.6],
	]
