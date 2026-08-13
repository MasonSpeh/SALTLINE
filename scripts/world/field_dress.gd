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

## MARROW — the industrial / experimental platform. Working-crew props only: this rig's
## exterior massing and materials already read well, so what it lacked was evidence of people.
##
## Every coordinate below is checked against rig_two's own constants. MESS is
## Rect2(-30, 2, 26, 18) with 0.28 walls (interior x -29.72..-4.28, z 2.28..19.72) and doors
## EAST at z 11, SOUTH at x -22, NORTH at x -14 — so those three lanes stay clear. The baked
## furniture from s63's `_mess_interior` is avoided by construction: the long table runs
## x -25..-9 at z 8, the galley counter is at x -29.1 over z 12..18, the seed-store shelves
## stand at x -11 / z 5.5 and the cold vault fills x -8.2..-5.8 / z 16..18.
##
## The GARDEN grid is derived, not copied: `_garden()` lays 4 x 3 beds of BED (5.0 x 4.2) with
## BED_GAP (1.1, 1.4) centred on MESS, which puts bed centres on x -26.15/-20.05/-13.95/-7.85
## and z 5.4/11.0/16.6, and leaves 1.4 m aisles at z 8.2 and 13.8. Everything up there sits in
## an aisle or on the perimeter margin, never on a bed — and nothing growing, because the beds
## are authored dead ("frost-cracked, sea-blasted") and a lush pot plant would contradict the
## one story that room tells.
func MARROW() -> Array:
	return [
		# --- bio lab
		["retro_multimeter", Vector3(-21, 14.99, -18), 20.0, 1.0],
		["magnifying_glass_01", Vector3(-20, 14.99, -17.9), 40.0, 1.0],
		["classic_laptop", Vector3(-18.8, 14.99, -18), 180.0, 1.0],
		["clipboard", Vector3(-17.6, 14.99, -18.1), 65.0, 1.0],
		["binder_notebook", Vector3(-16.6, 14.99, -17.9), 105.0, 1.0],
		["medical_box", Vector3(-13.2, 14.99, -17.9), 200.0, 1.0],
		["old_gas_mask", Vector3(-12, 14.99, -18), 30.0, 1.0],
		["desk_lamp_arm_01", Vector3(-10.6, 14.99, -18.15), 180.0, 1.0],
		["metal_stool_01", Vector3(-18.8, 14, -17), 0.0, 1.0],
		["metal_stool_02", Vector3(-14.4, 14, -17), 25.0, 1.0],
		["cleaner_tin_01", Vector3(-20.5, 14.99, -10.5), 0.0, 1.0],
		["office_notepads", Vector3(-18.4, 14.99, -10.6), 15.0, 1.0],
		["metal_jug", Vector3(-12.5, 14.99, -10.5), 0.0, 1.0],
		["Camera_01", Vector3(-10.2, 14.99, -10.55), 200.0, 1.0],
		["can_rusted", Vector3(-6, 14.73, -14), 0.0, 1.0],
		["russian_food_cans_01", Vector3(-6, 15.53, -11.8), 20.0, 1.0],
		["ammo_box", Vector3(-6, 16.33, -12.8), 0.0, 1.0],
		["steel_frame_shelves_02", Vector3(-22.6, 14, -8.9), 180.0, 1.6],
		["drawer_cabinet", Vector3(-20.5, 14, -8.9), 180.0, 1.1],
		["metal_trash_can", Vector3(-19, 14, -9.1), 0.0, 1.0],
		["korean_fire_extinguisher_01", Vector3(-4.4, 15, -16.5), 270.0, 1.0, "wall"],
		["industrial_wall_lamp", Vector3(-23.6, 16.4, -14), 90.0, 1.2, "wall"],
		# --- bridge-1 landing
		["wooden_crate_01", Vector3(-13.9, 14, -20.3), 10.0, 1.0, "", true],
		["old_military_crate", Vector3(-14.7, 14, -21.3), 200.0, 1.0, "", true],
		["lifebuoy", Vector3(-9, 15.1, -23.7), 0.0, 1.0, "wall", true],
		# --- low deck
		["wooden_crate_01", Vector3(24.6, 3.2, -17), 15.0, 1.0, "", true],
		["Barrel_01", Vector3(30, 3.2, -16.4), 0.0, 1.0, "", true],
		["wicker_basket_02", Vector3(28.6, 3.2, -22.8), 30.0, 1.0, "", true],
		["fishermans_hat", Vector3(27.7, 3.2, -22.85), 15.0, 1.0, "", true],
		# --- mess hall
		["Lantern_01", Vector3(-24.3, 14.74, 8.1), 0.0, 1.0],
		["pot_enamel_01", Vector3(-23.2, 14.74, 7.9), 20.0, 1.0],
		["metal_jug", Vector3(-22.2, 14.74, 8.25), 200.0, 1.0],
		["russian_food_cans_01", Vector3(-19.4, 14.74, 7.85), 15.0, 1.0],
		["plastic_thermos", Vector3(-18.3, 14.74, 8.2), 0.0, 1.0],
		["modified_thermos", Vector3(-17.3, 14.74, 7.85), 120.0, 1.0],
		["carved_wooden_plate", Vector3(-16.2, 14.74, 8.2), 0.0, 1.0],
		["chess_set", Vector3(-13.6, 14.74, 8.05), 25.0, 1.0],
		["boombox", Vector3(-11.6, 14.74, 8.1), 200.0, 1.0],
		["long_life_food", Vector3(-10.3, 14.74, 7.8), 45.0, 1.0],
		["brass_pan_01", Vector3(-29.1, 15.02, 14.1), 30.0, 1.0],
		["wooden_cutting_board", Vector3(-29.1, 15.02, 14.9), 0.0, 1.2],
		["vintage_electric_kettle", Vector3(-29.1, 15.02, 16.1), 210.0, 1.0],
		["brass_pot_02", Vector3(-29.1, 15.02, 16.8), 0.0, 1.0],
		["plastic_bottle_gallon", Vector3(-29.1, 15.02, 17.5), 25.0, 1.0],
		["all_purpose_cleaner", Vector3(-29.15, 15.02, 12.2), 0.0, 1.0],
		["russian_food_cans_01", Vector3(-29.15, 16.13, 14.4), 20.0, 1.0],
		["wicker_basket_02", Vector3(-11.6, 14.48, 5.5), 0.0, 1.0],
		["plastic_container", Vector3(-11.7, 15.18, 5.5), 0.0, 1.0],
		["garden_gloves_01", Vector3(-10.3, 15.18, 5.6), 40.0, 1.0],
		["steel_frame_shelves_01", Vector3(-29.3, 14, 4.6), 90.0, 1.6],
		["hand_truck", Vector3(-6.2, 14, 15.2), 180.0, 1.0],
		["korean_fire_extinguisher_01", Vector3(-4.4, 15, 6), 270.0, 1.0, "wall"],
		["wall_clock", Vector3(-4.4, 16.3, 8.2), 270.0, 1.0, "wall"],
		["watering_can_metal_01", Vector3(-12.7, 14, 4.7), 30.0, 1.0],
		# --- plant hall
		["metal_office_desk", Vector3(25, 14, 6.5), 270.0, 1.35],
		["metal_stool_01", Vector3(23.8, 14, 6.5), 0.0, 1.0],
		["bench_vice_01", Vector3(25, 14.72, 7.35), 0.0, 1.3],
		["binder_notebook", Vector3(25, 14.72, 6.2), 100.0, 1.0],
		["steel_frame_shelves_01", Vector3(25.2, 14, 8.6), 270.0, 1.7],
		["steel_frame_shelves_02", Vector3(25.2, 14, 13.6), 270.0, 1.7],
		["worn_metal_rack", Vector3(25.2, 14, 15.8), 270.0, 1.8],
		["metal_tool_chest", Vector3(2.9, 14, 6), 90.0, 1.1],
		["metal_toolbox", Vector3(3.1, 14, 7), 100.0, 1.0],
		["portable_welding_cart", Vector3(4.6, 14, 6.4), 90.0, 1.0],
		["propane_tank", Vector3(5.6, 14, 5.1), 0.0, 1.4],
		["portable_generator", Vector3(3.2, 14, 8.6), 90.0, 1.0],
		["Barrel_01", Vector3(2.9, 14, 13.5), 0.0, 1.0],
		["Barrel_02", Vector3(2.9, 14, 14.6), 40.0, 1.0],
		["metal_jerrycan", Vector3(4.1, 14, 13.5), 25.0, 1.0],
		["cement_bag", Vector3(3.4, 14, 17.6), 10.0, 1.0],
		["hand_truck", Vector3(5.8, 14, 17.9), 180.0, 1.0],
		["industrial_storage_cart", Vector3(9.4, 14, 17.6), 0.0, 1.1],
		["wooden_military_crate", Vector3(21.8, 14, 17.7), 8.0, 1.0],
		["old_military_crate", Vector3(20.4, 14, 17.8), -12.0, 1.0],
		["korean_fire_extinguisher_01", Vector3(2.4, 15, 12.6), 90.0, 1.0, "wall"],
		["power_box_01", Vector3(2.4, 15.4, 8.2), 90.0, 1.2, "wall"],
		["mounted_fluorescent_lights", Vector3(10, 20.4, 8), 0.0, 1.4, "wall"],
		["mounted_fluorescent_lights", Vector3(18, 20.4, 13.5), 0.0, 1.4, "wall"],
		# --- process deck
		["metal_tool_chest", Vector3(-24, 6.8, 18.6), 180.0, 1.1, "", true],
		["portable_welding_cart", Vector3(-21.5, 6.8, 18.5), 180.0, 1.0, "", true],
		["propane_tank", Vector3(-20.4, 6.8, 18.7), 0.0, 1.4, "", true],
		["Barrel_01", Vector3(-18.5, 6.8, 18.7), 0.0, 1.0, "", true],
		["Barrel_02", Vector3(-17.4, 6.8, 18.8), 40.0, 1.0, "", true],
		["steel_frame_shelves_01", Vector3(-13, 6.8, 18.9), 180.0, 1.7, "", true],
		["hand_truck", Vector3(-8, 6.8, 18.7), 180.0, 1.0, "", true],
		["industrial_storage_cart", Vector3(-5.5, 6.8, 18.6), 180.0, 1.1, "", true],
		["korean_fire_extinguisher_01", Vector3(-11, 6.8, -17), 0.0, 1.0, "", true],
		["metal_toolbox", Vector3(-19.6, 7.12, 12.6), 20.0, 1.0, "", true],
		["lubricant_spray", Vector3(-12.2, 7.12, 12.6), 40.0, 1.0, "", true],
		["pipe_wrench", Vector3(-4.8, 7.12, 12.6), 70.0, 1.0, "", true],
		["plastic_jerrycan", Vector3(16.9, 6.8, -12.4), 30.0, 1.0, "", true],
		# --- roof garden
		["watering_can_metal_01", Vector3(-25.2, 21.84, 4.6), 30.0, 1.2, "", true],
		["garden_gloves_01", Vector3(-24, 21.84, 6.2), 15.0, 1.0, "", true],
		["wicker_basket_01", Vector3(-20.5, 21.84, 5), 0.0, 1.3, "", true],
		["wicker_basket_02", Vector3(-19, 21.84, 5.9), 40.0, 1.2, "", true],
		["ceramic_pot", Vector3(-14.6, 21.84, 4.8), 0.0, 1.2, "", true],
		["fern_02", Vector3(-13.2, 21.84, 6.1), 0.0, 1.6, "", true],
		["fir_sapling", Vector3(-8.6, 21.84, 5.2), 0.0, 1.4, "", true],
		["celandine_01", Vector3(-7, 21.84, 6), 0.0, 1.4, "", true],
		["plastic_broom", Vector3(-29.2, 21.2, 13), 5.0, 1.0, "", true],
		["wooden_bucket_01", Vector3(-29.2, 21.2, 12), 20.0, 1.0, "", true],
		["wooden_bucket_02", Vector3(-29.2, 21.2, 7.9), 60.0, 1.0, "", true],
		["cement_bag", Vector3(-27, 21.2, 2.9), 25.0, 1.0, "", true],
		["wooden_crate_01", Vector3(-11, 21.2, 2.9), 10.0, 1.0, "", true],
		# --- tank farm
		["Barrel_01", Vector3(32, 14, -14.6), 0.0, 1.0, "", true],
		["Barrel_02", Vector3(33.2, 14, -14.7), 35.0, 1.0, "", true],
		["metal_jerrycan", Vector3(34.4, 14, -14.6), 20.0, 1.0, "", true],
		["korean_fire_extinguisher_01", Vector3(31.3, 14, -14.9), 90.0, 1.0, "", true],
		["metal_tool_chest", Vector3(31.6, 14, 14.4), 90.0, 1.1, "", true],
		["old_military_crate", Vector3(32.2, 14, 15.8), 10.0, 1.0, "", true],
	]

## THE ANCHORAGE — the luxury rig, and the one the owner cares most about.
func ANCHORAGE() -> Array:
	var rows: Array = [
		# --- THE ATRIUM. Rewritten s65 after the owner's "remove the BS statues everywhere
		#     random", which was exactly right. The three bronzes stood at r 13.80 — the MIDDLE
		#     of the 3.8 m ambulatory, the hotel's main circulation loop — on no plinth, with no
		#     fourth to complete the 4-fold pattern they half-implied, and SCALED x2.5 from the
		#     0.6 m SHELF ORNAMENTS they are on rig 1 into 1.5 m floor sculptures solid enough
		#     to walk into. A sculpture belongs on a piece of furniture against something.
		#
		#     So each one now stands on a console or a cabinet backed to one of the four glazed
		#     PIERS (bays 1/4/7/10 at 45/135/225/315 deg, r 14.2 — the dead arcs between the
		#     portal pairs, which is the one place round this ring where furniture does not
		#     block a doorway), at its true size, facing the water. The 315 deg bay gets the
		#     deco cabinet and the whale, because that is the quadrant the old set of three
		#     left empty and it is why they read as random.
		["chinese_cabinet", Vector3(10.04, 22.04, -6.04), 315.0, 1.0, "fix"],
		["bronze_whale_statue", Vector3(10.04, 23.06, -6.04), 300.0, 1.0],
		["vintage_oil_lamp", Vector3(9.15, 23.06, -6.9), 320.0, 1.0],
		["brass_candleholders", Vector3(10.95, 23.06, -5.2), 300.0, 1.0],
		["WoodenTable_03", Vector3(10.04, 22.04, 14.04), 225.0, 1.0, "fix"],
		["bronze_shark_statue", Vector3(10.04, 22.82, 14.04), 215.0, 1.0],
		["ceramic_vase_03", Vector3(9.25, 22.82, 13.3), 20.0, 1.0],
		["WoodenTable_03", Vector3(-10.04, 22.04, 14.04), 135.0, 1.0, "fix"],
		["bronze_ray_statue", Vector3(-10.04, 22.82, 14.04), 145.0, 1.0],
		["WoodenTable_03", Vector3(-10.04, 22.04, -6.04), 45.0, 1.0, "fix"],
		["antique_ceramic_vase_01", Vector3(-10.04, 22.82, -6.04), 30.0, 1.2],
		["calathea_orbifolia_01", Vector3(-11.1, 22.04, -7.1), 0.0, 1.9, "fix"],
		["calathea_orbifolia_01", Vector3(11.1, 22.04, 15.1), 0.0, 1.9, "fix"],
		#     The four saucer-arc plants, replacing the baked card-cutout planters that stood
		#     at r 10.4. Real models, on the lower tier (top MAIN_Y+0.32), one per quadrant.
		["calathea_orbifolia_01", Vector3(7.55, 22.32, 11.55), 0.0, 2.0, "fix"],
		["fern_02", Vector3(-7.55, 22.32, 11.55), 0.0, 1.9, "fix"],
		["calathea_orbifolia_01", Vector3(-7.55, 22.32, -3.55), 0.0, 2.0, "fix"],
		["anthurium_botany_01", Vector3(7.55, 22.32, -3.55), 0.0, 1.8, "fix"],
		#     THE FOUR SITTING GROUPS. Five of their eight baked surfaces carried nothing at
		#     all. Y is +0.34 on the old rows because the saucer's furniture was 0.30 m SUNK
		#     into the plinth until this session — Bake.cyl positions by CENTRE, so the saucer
		#     top is MAIN_Y+0.92 and everything on it had been authored to MAIN_Y+0.62.
		["book_encyclopedia_set_01", Vector3(5.37, 23.40, 9.37), 45.0, 1.0],
		["brass_vase_01", Vector3(-5.37, 23.40, 9.37), 0.0, 1.3],
		["tea_set_01", Vector3(5.37, 23.40, -1.37), 30.0, 1.0],
		["brass_pot_01", Vector3(-5.37, 23.40, -1.37), 200.0, 1.0],
		["throw_pillows_01", Vector3(6.0, 23.43, -2.2), 315.0, 1.0],
		["throw_pillows_01", Vector3(5.9, 23.43, 9.9), 225.0, 1.0],
		["throw_pillows_01", Vector3(-5.9, 23.43, 9.9), 135.0, 1.0],
		["throw_pillows_01", Vector3(-5.9, 23.43, -2.2), 45.0, 1.0],
		# --- dining hall
		["brass_candleholders", Vector3(24, 22.78, -5), 0.0, 1.2],
		["wine_bottles_01", Vector3(23.8, 22.78, -4.2), 40.0, 1.0],
		["tea_set_01", Vector3(24, 22.78, 3), 200.0, 1.0],
		["wine_bottles_01", Vector3(24.2, 22.78, 11.4), 15.0, 1.0],
		["tea_set_01", Vector3(31, 22.78, -5), 110.0, 1.0],
		["ceramic_vase_04", Vector3(31, 22.78, 3), 0.0, 1.1],
		["brass_candleholders", Vector3(31, 22.78, 11), 0.0, 1.2],
		["antique_ceramic_vase_01", Vector3(29, 23, -9.2), 0.0, 1.4],
		["brass_pot_01", Vector3(25, 23, -9.2), 25.0, 1.2],
		["strawberry_chocolate_cake", Vector3(36.6, 22.96, 4), 0.0, 1.2],
		["calathea_orbifolia_01", Vector3(38.9, 22, -8.6), 0.0, 2.4],
		# --- east tower games room
		["small_wooden_table_01", Vector3(34, 29.44, 8), 0.0, 1.1],
		["WoodenChair_01", Vector3(33, 29.44, 8), 90.0, 1.0],
		["WoodenChair_01", Vector3(35, 29.44, 8), 270.0, 1.0],
		["sungka_board", Vector3(34, 30.16, 8), 0.0, 1.0],
		["throw_pillows_01", Vector3(24, 29.85, -2.15), 0.0, 1.0],
		["bar_chair_round_01", Vector3(38.6, 29.44, 10), 270.0, 1.0],
		# --- food court
		["wicker_basket_02", Vector3(1.1, 23.06, -14), 0.0, 1.0],
		["hamburger_buns", Vector3(7, 23.06, -14), 0.0, 1.0],
		["bananas", Vector3(12.5, 23.06, -14), 0.0, 1.0],
		["ceramic_vase_01", Vector3(12.7, 22.45, -9), 0.0, 1.0],
		# --- kitchen
		["brass_pot_02", Vector3(23.5, 23.02, -26.6), 0.0, 1.2],
		["brass_pan_01", Vector3(26, 23.02, -26.6), 30.0, 1.0],
		["vintage_electric_kettle", Vector3(28.5, 23.02, -26.6), 200.0, 1.0],
		["wooden_cutting_board", Vector3(31, 23.02, -15), 0.0, 1.2],
		["wooden_bowl_01", Vector3(29, 22.96, -20.7), 0.0, 1.0],
		["steel_frame_shelves_01", Vector3(20.7, 22, -18), 90.0, 1.0],
		# --- pool hall (leisure deck)
		["lifebuoy", Vector3(-33.72, 16.1, 0), 90.0, 1.0, "wall"],
		["fern_02", Vector3(13, 15.4, -9.5), 0.0, 2.2],
		["wine_bottles_01", Vector3(23.2, 16.56, 20), 0.0, 1.0],
		# --- private dining / bar
		["bar_chair_round_01", Vector3(28, 22, 16.05), 0.0, 1.0],
		["bar_chair_round_01", Vector3(30, 22, 16.05), 0.0, 1.0],
		["bar_chair_round_01", Vector3(32, 22, 16.05), 0.0, 1.0],
		["wine_bottles_01", Vector3(25, 23.16, 16.9), 0.0, 1.0],
		# --- roof terrace
		["WoodenTable_02", Vector3(-30, 26.2, -16), 0.0, 1.1, "", true],
		["WoodenChair_01", Vector3(-30, 26.2, -17.1), 0.0, 1.0, "", true],
		["WoodenChair_01", Vector3(-30, 26.2, -14.9), 180.0, 1.0, "", true],
		["fir_sapling", Vector3(20.6, 26.2, -26.4), 0.0, 1.6, "", true],
		# --- salon
		["ArmChair_01", Vector3(-0.4, 22.06, -20.5), 90.0, 1.0],
		["ArmChair_01", Vector3(4.4, 22.06, -20.5), 270.0, 1.0],
		["ArmChair_01", Vector3(7.6, 22.06, -20.5), 90.0, 1.0],
		["ArmChair_01", Vector3(12.4, 22.06, -20.5), 270.0, 1.0],
		["throw_pillows_01", Vector3(1, 22.45, -17.45), 180.0, 1.0],
		["throw_pillows_01", Vector3(9.2, 22.45, -23.6), 0.0, 1.0],
		["tea_set_01", Vector3(2, 22.45, -20.5), 30.0, 1.0],
		# --- south hall
		["fancy_picture_frame_02", Vector3(-34, 23.9, -12.86), 0.0, 1.4, "wall"],
		["korean_fire_extinguisher_01", Vector3(-26, 22.04, -12.6), 0.0, 1.0],
		# --- spa treatment room
		["chinese_tea_table", Vector3(-11.5, 22.04, 26), 0.0, 1.0],
		["ceramic_vase_03", Vector3(-11.5, 22.5, 26), 0.0, 1.0],
		["chinese_stool", Vector3(-7.6, 22.04, 24.3), 90.0, 1.0],
		["wicker_basket_01", Vector3(-12.9, 23.8, 23.2), 0.0, 1.1],
		["fern_02", Vector3(-13, 22.04, 29.1), 0.0, 1.6],
		# --- vestibule / reception
		["brass_vase_01", Vector3(-11.4, 23.15, -22), 0.0, 1.2],
		["desk_lamp_arm_01", Vector3(-10.6, 23.15, -22.25), 200.0, 1.0],
		["stationery_supplies", Vector3(-9.6, 23.15, -22.25), 15.0, 1.0],
		["mantel_clock_01", Vector3(-8.6, 23.15, -22), 180.0, 1.0],
		["calathea_orbifolia_01", Vector3(-12.6, 22.04, -27.1), 20.0, 2.2],
		["calathea_orbifolia_01", Vector3(-7.4, 22.04, -27.1), 200.0, 2.2],
		# --- west hall
		["WoodenTable_03", Vector3(-23.5, 22.04, -6.3), 90.0, 1.0],
		["antique_ceramic_vase_01", Vector3(-23.5, 22.79, -6.3), 0.0, 1.3],
		["WoodenTable_03", Vector3(-23.5, 22.04, 7.1), 90.0, 1.0],
		["marble_bust_01", Vector3(-23.5, 22.79, 7.1), 200.0, 1.0],
		["calathea_orbifolia_01", Vector3(-18.7, 22.04, 9.6), 0.0, 2.0],
		# --- west tower library
		["book_encyclopedia_set_01", Vector3(-39.32, 26.96, 0.8), 90.0, 1.2],
		["book_encyclopedia_set_01", Vector3(-39.32, 27.58, 3.6), 90.0, 1.2],
		["ArmChair_01", Vector3(-26, 26.24, 4), 270.0, 1.0],
		["ArmChair_01", Vector3(-32, 26.24, 4), 90.0, 1.0],
		["chess_set", Vector3(-29.3, 26.65, 3.8), 20.0, 1.0],
		["calathea_orbifolia_01", Vector3(-19.6, 26.24, 16.4), 0.0, 2.2],
	]
	_suite_rows(rows)
	return rows

## THE NINE SUITES, DERIVED — not hand-typed. rig_three's `_suites()` places each room from a
## table of cell boundaries and `_suite()` puts the bed, wardrobe and desk at offsets measured
## from the room centre in the room's OWN fwd/side frame. Hand-copying nine rooms' worth of
## world coordinates out of that would be fifty-four numbers that silently rot the first time
## a cell boundary moves — which is exactly the failure the s56 cat spawn paid for ("HOME was
## hand-typed as x -18.0 and the real derivation is x -20.685", written in the same commit as
## the never-hand-type warning). So this walks the SAME cell tables and the SAME offset
## algebra, and every prop is positioned relative to the bed it belongs to.
##
## The suites are also the emptiest rooms on the rig: before this each held a bed slab, a
## wardrobe box, a desk box and a rug, and nothing else — no nightstand, no lamp, no chair,
## no art. NINE IDENTICAL ROOMS IS ITS OWN DEFECT, so the mix is keyed off the suite index:
## every room gets the same furniture GRAMMAR (bed dressed, something to sit in, something
## growing, something on the wall) and a different vocabulary.
func _suite_rows(rows: Array) -> void:
	var cells: Array = []
	# NOTE THE FIRST WEST CELL IS ABSENT. rig_three's `_suites()` opens its west flank at
	# z -13, but `_ceilings()` runs the SOUTH HALL corridor across z -12.9..-9.1 at the same
	# x — so suite W1's cell [-13, -6.3] overlaps the corridor, and `_suite()` stands W1's
	# BED at z -9.65, in the hall. Dressing it would only put a nightstand and a reading
	# chair in a public corridor on top of that. Left undressed and filed in KNOWN_ISSUES
	# rather than papered over: the fix is a floorplan call (shorten the west column or move
	# the hall), and that is the owner's to make, not a dressing pass's.
	for c in [[-6.3, 0.4], [0.4, 7.1], [7.1, 13.8], [13.8, 17.9], [17.9, 22.0]]:
		cells.append([Vector3(-32.0, T3.MAIN_Y, (c[0] + c[1]) * 0.5), 90.0, Vector2(c[1] - c[0], 16.0)])
	for c2 in [[-40.0, -32.0], [-32.0, -24.0], [-24.0, -16.0]]:
		cells.append([Vector3((c2[0] + c2[1]) * 0.5, T3.MAIN_Y, -20.5), 0.0, Vector2(c2[1] - c2[0], 15.0)])
	# Per-suite vocabulary. Same grammar, different words, so no two rooms read the same.
	var lamps := ["desk_lamp_arm_01", "vintage_oil_lamp", "Lantern_01"]
	var seats := ["ArmChair_01", "GreenChair_01", "Rockingchair_01", "Ottoman_01"]
	var plants := ["calathea_orbifolia_01", "anthurium_botany_01", "fern_02", "ceramic_pot"]
	var arts := ["fancy_picture_frame_01", "fancy_picture_frame_02", "hanging_picture_frame_01",
		"standing_picture_frame_01"]
	var nightstand_top := ["alarm_clock_01", "brass_vase_01", "ceramic_vase_02", "book_encyclopedia_set_01"]
	var extras := ["wicker_basket_01", "throw_pillows_01", "wooden_bowl_01", "postcard_set_01",
		"round_spectacles", "chess_set", "tea_set_01", "brass_candleholders", "wine_bottles_01"]
	for i in range(cells.size()):
		var centre: Vector3 = cells[i][0]
		var yaw: float = cells[i][1]
		var size: Vector2 = cells[i][2]
		var r: float = deg_to_rad(yaw)
		var fwd := Vector3(sin(r), 0, cos(r))            # toward the corridor door
		var side := Vector3(cos(r), 0, -sin(r))
		var half: float = size.x * 0.5
		# The bed, exactly where _suite() puts it. Everything else hangs off this.
		var bed: Vector3 = centre - fwd * (size.y * 0.5 - 2.2)
		# NIGHTSTAND against the head wall beside the bed, and something on it. The bed is
		# 1.9 across, so 1.35 clears its side by 0.4.
		var ns_side: float = 1.0 if i % 2 == 0 else -1.0
		var ns: Vector3 = bed + side * (1.35 * ns_side)
		rows.append(["ClassicNightstand_01", ns, yaw, 1.0, "fix"])
		rows.append([nightstand_top[i % nightstand_top.size()], ns + Vector3(0, 0.62, 0), yaw + 20.0, 1.0])
		rows.append([lamps[i % lamps.size()], ns + side * (0.18 * ns_side) + Vector3(0, 0.62, 0), yaw + 200.0, 1.0])
		# A SECOND nightstand only where the room is wide enough to carry one (the two narrow
		# 4.1 m cells at the north end of the west flank would put it through the wall).
		if half > 2.6:
			rows.append(["ClassicNightstand_01", bed - side * (1.35 * ns_side), yaw, 1.0, "fix"])
		# SOMETHING TO SIT IN, in the far corner from the wardrobe, angled into the room.
		rows.append([seats[i % seats.size()],
			centre - fwd * (size.y * 0.5 - 1.5) + side * ((half - 0.95) * -ns_side), yaw + 35.0 * ns_side, 1.0, "fix"])
		# A TRUNK at the foot of the bed — the one piece of luggage that says a guest is in.
		rows.append(["wooden_crate_01", bed + fwd * 1.75, yaw + 8.0, 1.0, "fix"])
		# SOMETHING GROWING, by the window band on the corridor side.
		rows.append([plants[i % plants.size()],
			centre + fwd * (size.y * 0.5 - 1.2) + side * ((half - 0.7) * ns_side), yaw, 1.0, "fix"])
		# ART on the head wall, flush. "wall" mode: there is nothing under it and the settle
		# pass must not go looking for something.
		rows.append([arts[i % arts.size()],
			centre - fwd * (size.y * 0.5 - 0.22) + Vector3(0, 1.65, 0), yaw, 1.0, "wall"])
		# And one personal object on the desk, which _suite() puts on the far side.
		var desk: Vector3 = centre - side * (half - 0.95) + fwd * 1.0
		rows.append([extras[i % extras.size()], desk + Vector3(0, 0.82, 0), yaw + 130.0, 1.0])

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
