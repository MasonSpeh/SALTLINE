extends Node3D
## Lived-in dressing pass: stocks every room with the CC0 glTF prop library
## (PropLib) so the rig reads as a place people worked and left mid-shift, not a
## greybox. Props sit on the furniture the builders already placed; most are
## non-colliding so they never trap the player or the crab's path. Coordinates
## trace the room anchors in rig_builder.gd / rig_superstructure.gd.

const DECK_Y: float = 18.0
const WET_Y: float = 2.0
const B_Y: float = 21.6
const C_Y: float = 25.1
const D_Y: float = 28.6

## Instancing ~200 glTF props all at once blocks the main thread for several
## seconds — long enough to freeze the window during the scene change into the
## game (the "Play freezes" bug). So the room functions only QUEUE placements
## (cheap), and _stream() instances them a few per frame after the scene is up.
## The rig comes up instantly and props settle in over ~1-2s.
var _queue: Array = []
const PER_FRAME: int = 5

func _ready() -> void:
	_wet_deck()
	_galley()
	_bunkhouse()
	_rec_room()
	_machine_shop()
	_deck_b_cabins()
	_deck_c_control()
	_deck_d_works()
	# Second pass — roughly doubles the density with the furniture/decor/plant
	# library so every room reads densely inhabited, not just sketched.
	_galley_more()
	_bunkhouse_more()
	_rec_room_more()
	_machine_shop_more()
	_stack_more()
	_stream()   # drain the queue across frames (runs as a coroutine)

## Instance the queued props a handful per frame so no single frame stalls.
## Anything the library considers human-moveable is spawned as a grabbable
## MovableProp (carry/drag/throw); genuinely fixed items keep their old collide
## behavior. Small tabletop items and wall decorations become grabbable too.
func _stream() -> void:
	var i: int = 0
	for item in _queue:
		if not is_instance_valid(self):
			return
		var id: String = item[0]
		var mov: bool = PropLib.is_moveable(id)
		PropLib.spawn(id, self, item[1], item[2], item[3], item[4], -1.0, mov)
		i += 1
		if i % PER_FRAME == 0:
			await get_tree().process_frame
	_queue.clear()

# ---- placement helpers ----

func _p(id: String, pos: Vector3, yaw: float = 0.0, sm: float = 1.0) -> void:
	_queue.append([id, pos, yaw, sm, false])

func _pc(id: String, pos: Vector3, yaw: float = 0.0, sm: float = 1.0) -> void:
	## Colliding variant for big floor furniture the player should bump.
	_queue.append([id, pos, yaw, sm, true])

## A small warm point light (jar lamp / worklight glow) — sparingly, for mood.
func _lamp(pos: Vector3, color: Color = Color(1.0, 0.82, 0.5), energy: float = 0.6, rng: float = 4.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos

# ---- wet deck: the rigging bench & dock storeroom ----

func _wet_deck() -> void:
	var y: float = WET_Y
	# Around the rigging bench (now at 16.2, -18, off the SPHL exit): toolbox, tool
	# chest, oil cans — all follow the bench so nothing floats or blocks the hatch.
	_p("metal_toolbox", Vector3(25.0, y + 0.96, -17.5), -90)
	_pc("metal_tool_chest", Vector3(26.7, y, -17.8), -90)
	_p("small_oil_can_01", Vector3(24.2, y + 0.96, -17.3), 40)
	_p("pipe_wrench", Vector3(25.4, y + 0.97, -17.6), 200)
	# Jerry cans and a bucket by the storeroom wall.
	_pc("metal_jerrycan", Vector3(11.6, y, -21.4), 25)
	_pc("plastic_jerrycan", Vector3(12.2, y, -21.5), -40)
	_p("wooden_bucket_01", Vector3(12.9, y, -21.3), 0)
	# A caged worklight glowing over the bench — the one warm point down here.
	_p("caged_hanging_light", Vector3(25.0, y + 2.4, -17.5))
	_lamp(Vector3(25.0, y + 2.2, -17.5), Color(1.0, 0.8, 0.55), 0.7, 5.0)
	# Fire extinguisher bracketed by the stair door; a stack of ration tins.
	_p("korean_fire_extinguisher_01", Vector3(24.6, y + 0.55, -6.3), 180, 1.1)
	_p("long_life_food", Vector3(24.2, y + 0.02, -16.9), 20)

# ---- galley ----

func _galley() -> void:
	var y: float = DECK_Y
	# Counter run at z17 (top ~y+1.0): kettle, thermoses, food cans, a boombox.
	_p("vintage_electric_kettle", Vector3(3.4, y + 1.01, 17.0), 180)
	_p("modified_thermos", Vector3(4.3, y + 1.01, 17.0), 150)
	_p("plastic_thermos", Vector3(5.1, y + 1.01, 17.0), -120)
	_p("russian_food_cans_01", Vector3(6.6, y + 1.01, 17.1), 10)
	_p("boombox", Vector3(9.0, y + 1.02, 17.1), 200)
	# Ration tins stacked on the wall shelves (z 11-13, x -1.6).
	_p("long_life_food", Vector3(-1.5, y + 1.75, 12.4), 90)
	_p("cleaner_tin_01", Vector3(-1.5, y + 2.35, 12.0), 90)
	# A monobloc chair pushed back from a table, a thermos left on it.
	_pc("plastic_monobloc_chair_01", Vector3(2.9, y, 11.0), 30)
	_p("modified_thermos", Vector3(8.0, y + 0.52, 11.0), 60)
	_p("russian_food_cans_01", Vector3(2.0, y + 0.52, 14.5), -30)
	# A trash can by the fridge, overflowing a little.
	_pc("metal_trash_can", Vector3(0.2, y, 16.6), 0)

# ---- bunkhouse ----

func _bunkhouse() -> void:
	var y: float = DECK_Y
	# Personal effects on footlockers at the foot of the beds.
	var beds := [Vector3(-25.5, y, 6.5), Vector3(-18.8, y, 6.5), Vector3(-12.0, y, 6.5),
			Vector3(-25.5, y, 15.5), Vector3(-18.8, y, 15.5), Vector3(-12.0, y, 15.5)]
	var deck := ["binder_notebook", "vintage_flashlight", "modified_thermos",
			"office_notepads", "plastic_thermos", "old_gas_mask"]
	for i in range(beds.size()):
		var p: Vector3 = beds[i]
		_p(deck[i], p + Vector3(0.0, 0.42, 1.45), i * 47.0)
	# A shared table between the rows with a lantern and a radio.
	_pc("small_wooden_table_01", Vector3(-18.5, y, 11.0), 0)
	_p("Lantern_01", Vector3(-18.5, y + 0.78, 11.0), 0)
	_lamp(Vector3(-18.5, y + 0.95, 11.0), Color(1.0, 0.85, 0.55), 0.55, 4.5)
	_p("vintage_radio_transceiver", Vector3(-17.7, y + 0.78, 11.2), 200)
	# A duffel and a folding stool by the door.
	_pc("folding_wooden_stool", Vector3(-22.0, y, 9.0), 20)
	# Life jacket hung on the wall.
	_p("life_jacket", Vector3(-9.3, y + 1.4, 6.2), -90)

# ---- rec room ----

func _rec_room() -> void:
	var y: float = DECK_Y
	# The low table (23,12.5): a boombox, bottles, an ashtray of cards already there.
	_p("boombox", Vector3(22.3, y + 0.33, 12.5), 30)
	_p("plastic_thermos", Vector3(23.6, y + 0.33, 12.2), -40)
	# A television on a stand against the east wall.
	_pc("television_02", Vector3(26.6, y + 0.5, 12.5), -90)
	_pc("small_wooden_table_01", Vector3(26.6, y, 12.5), -90)
	# A worn chair and a stool around it.
	_pc("painted_wooden_chair_01", Vector3(20.8, y, 11.0), 120)
	_pc("metal_stool_02", Vector3(24.5, y, 14.2), -60)
	# A bookshelf's worth of extra books + a lantern for reading.
	_p("Lantern_01", Vector3(25.5, y + 1.55, 17.3), 0)
	_lamp(Vector3(25.5, y + 1.75, 17.0), Color(1.0, 0.83, 0.52), 0.4, 3.5)

# ---- machine shop ----

func _machine_shop() -> void:
	var y: float = DECK_Y
	# The shop is the tool jackpot — chest, cart, welding rig, drums, jerry cans.
	_pc("metal_tool_chest", Vector3(-25.5, y, -12.5), 90)
	_pc("tool_cart", Vector3(-22.5, y, -13.5), 0)
	_pc("portable_welding_cart", Vector3(-25.5, y, -16.5), 20)
	_pc("drawer_cabinet", Vector3(-26.6, y, -14.8), 90)
	_pc("Barrel_01", Vector3(-20.5, y, -17.0), 0)
	_pc("barrel_03", Vector3(-21.4, y, -16.6), 0)
	_pc("metal_jerrycan_green", Vector3(-19.5, y, -16.6), 60)
	_p("metal_toolbox", Vector3(-19.6, y + 1.25, -12.0), 0)
	_p("pipe_wrench", Vector3(-19.2, y + 1.26, -12.3), 130)
	_p("small_oil_can_01", Vector3(-20.2, y + 1.25, -11.7), 0)
	# Modular pipes racked against the wall; a hand truck parked.
	_pc("hand_truck", Vector3(-23.5, y, -11.4), 100)
	_p("portable_searchlight", Vector3(-26.4, y + 0.9, -12.5), 40)
	# Worklight over the bench.
	_p("industrial_wall_lamp", Vector3(-19.6, y + 2.3, -12.4), 0)
	_lamp(Vector3(-19.6, y + 2.1, -12.2), Color(1.0, 0.85, 0.6), 0.6, 5.0)

# ---- Deck B: crew cabins ----

func _deck_b_cabins() -> void:
	var y: float = B_Y
	# Desks sit through the cabins; give each a little life. Desk tops ~y+0.75.
	var desks := [Vector3(1.8, y, 6.9), Vector3(6.9, y, 8.0), Vector3(18.0, y, 17.1)]
	var items := [["office_notepads","modified_thermos"], ["binder_notebook","vintage_flashlight"],
			["retro_multimeter","plastic_thermos"]]
	for i in range(desks.size()):
		var d: Vector3 = desks[i]
		_p(items[i][0], d + Vector3(-0.2, 0.76, 0.0), 15 + i * 40)
		_p(items[i][1], d + Vector3(0.25, 0.76, 0.05), -30 - i * 25)
	# A stool at one desk; a duffel; a wall flashlight.
	_pc("metal_stool_01", Vector3(2.4, y, 7.6), 0)
	_p("vintage_flashlight", Vector3(20.5, y + 0.42, 7.4), 45)

# ---- Deck C: control / mud logging ----

func _deck_c_control() -> void:
	var y: float = C_Y
	# The control desks (5.8 + i*2.2, 7.4) already carry monitors; add operator kit.
	for i in range(3):
		var d := Vector3(5.8 + i * 2.2, y, 7.4)
		_p("retro_multimeter", d + Vector3(-0.3, 0.76, 0.35), 180)
		_p(["modified_thermos", "office_notepads", "plastic_thermos"][i], d + Vector3(0.35, 0.76, 0.3), 160)
	# The prize: a working-looking radio transceiver on the mud-log bench (x13..23,z14..18).
	_pc("metal_office_desk", Vector3(20.0, y, 16.4), 180)
	_p("vintage_radio_transceiver", Vector3(20.0, y + 0.77, 16.4), 180)
	_lamp(Vector3(20.0, y + 1.1, 16.4), Color(0.5, 0.9, 0.7), 0.35, 3.0)   # cold instrument glow
	_p("binder_notebook", Vector3(18.8, y + 0.77, 16.2), -20)
	_pc("metal_stool_02", Vector3(20.0, y, 15.3), 0)
	# Power panel + fire extinguisher on the bulkhead.
	_p("power_box_01", Vector3(22.7, y + 1.4, 14.2), -90, 1.2)
	_p("korean_fire_extinguisher_01", Vector3(13.4, y + 0.55, 14.4), 90, 1.1)

# ---- Deck D: works / gym / workshop ----

func _deck_d_works() -> void:
	var y: float = D_Y
	# Workshop band (x15.5..23, z15..18): shelves stocked, a generator, jerry cans.
	_pc("steel_frame_shelves_01", Vector3(22.4, y, 16.6), -90)
	_p("cleaner_tin_01", Vector3(22.2, y + 0.55, 16.2), 0)
	_p("oil_tin", Vector3(22.2, y + 0.55, 17.0), 0)
	_p("small_lpg_tank", Vector3(22.2, y + 1.15, 16.6), 0)
	_pc("portable_generator", Vector3(17.0, y, 16.8), 40)
	_pc("metal_jerrycan", Vector3(16.0, y, 17.2), -20)
	_pc("propane_tank", Vector3(16.6, y, 15.6), 0)
	# Gym band (x8..15.5, z13..15): a day bed / bench, a bucket.
	_pc("worn_metal_rack", Vector3(9.0, y, 14.0), 90)
	_p("industrial_pipe_lamp", Vector3(19.0, y + 2.4, 16.5), 0)
	_lamp(Vector3(19.0, y + 2.2, 16.5), Color(1.0, 0.85, 0.6), 0.5, 5.0)

# ============================================================ second pass (2x)

func _galley_more() -> void:
	var y: float = DECK_Y
	# Food and comfort on the mess tables — the meal that never got eaten.
	_p("carrot_cake", Vector3(2.4, y + 0.52, 11.0), 0)
	_p("croissant", Vector3(8.4, y + 0.52, 14.5), 40)
	_p("bananas", Vector3(1.6, y + 0.52, 14.5), 0)
	_p("brass_pot_01", Vector3(11.8, y + 1.05, 16.2), 0)     # on the stove
	_p("brass_pan_01", Vector3(11.2, y + 1.05, 15.9), 30)
	# Chairs actually pulled up to the tables.
	for tp in [Vector3(2, y, 11), Vector3(8, y, 11), Vector3(2, y, 14.5), Vector3(8, y, 14.5)]:
		_pc("WoodenChair_01", tp + Vector3(0, 0, -1.0), 0)
		_pc("WoodenChair_01", tp + Vector3(0, 0, 1.0), 180)
	# A potted plant by the door, a wall clock, a coffee thermos row.
	_pc("ceramic_pot", Vector3(-1.4, y, 9.0), 0)
	_p("calathea_orbifolia_01", Vector3(-1.4, y + 0.3, 9.0), 0)
	_p("alarm_clock_01", Vector3(-1.55, y + 2.0, 13.5), 90)
	_p("plastic_thermos", Vector3(6.0, y + 1.01, 17.0), -60)

func _bunkhouse_more() -> void:
	var y: float = DECK_Y
	# A corner sitting nook: armchair, side table, lamp, a book left open.
	_pc("ArmChair_01", Vector3(-25.0, y, 11.5), 60)
	_pc("ClassicNightstand_01", Vector3(-23.6, y, 11.8), 0)
	_p("book_encyclopedia_set_01", Vector3(-23.6, y + 0.6, 11.8), 0)
	_p("Lantern_01", Vector3(-15.5, y + 0.78, 11.0), 0)
	# Plants and pictures make the barracks a home.
	_pc("fern_02", Vector3(-11.5, y, 8.5), 0)
	_p("fancy_picture_frame_01", Vector3(-25.9, y + 1.7, 10.0), 90)
	_p("fancy_picture_frame_02", Vector3(-9.15, y + 1.7, 13.0), -90)
	# More personal effects at the bed heads.
	var beds := [Vector3(-25.5, y, 6.5), Vector3(-18.8, y, 6.5), Vector3(-12.0, y, 6.5),
			Vector3(-25.5, y, 15.5), Vector3(-18.8, y, 15.5), Vector3(-12.0, y, 15.5)]
	var extra := ["ceramic_vase_01", "food_apple_01", "cassette_player",
			"decorative_book_set_01", "binoculars", "brass_goblets"]
	for i in range(beds.size()):
		_p(extra[i], beds[i] + Vector3(0.55, 0.68, -0.8), i * 33.0)

func _rec_room_more() -> void:
	var y: float = DECK_Y
	# The rec room earns its name: dartboard, chess mid-game, a real sofa.
	_p("dartboard", Vector3(18.15, y + 1.8, 11.0), 90)
	_p("chess_set", Vector3(23.0, y + 0.34, 12.5), 20)      # on the low table
	_pc("Sofa_01", Vector3(20.5, y, 9.3), 0)
	_pc("Ottoman_01", Vector3(22.0, y, 10.2), 0)
	# A bronze Bloom-creature statue on the shelf — someone was already a believer.
	_p("bronze_whale_statue", Vector3(19.4, y + 1.05, 17.5), -20)
	_pc("fir_sapling", Vector3(26.6, y, 8.6), 0)
	_p("classic_laptop", Vector3(24.8, y + 0.28, 10.5), 200)
	_p("food_avocado_01", Vector3(23.5, y + 0.34, 12.9), 0)

func _machine_shop_more() -> void:
	var y: float = DECK_Y
	# The rest of the tool wall: hand tools scattered on and around the bench.
	_p("crowbar_01", Vector3(-20.6, y + 1.25, -12.4), 60)
	_p("bolt_cutters_01", Vector3(-19.0, y + 1.25, -11.6), -40)
	_p("cross_pein_hammer", Vector3(-20.0, y + 1.26, -11.5), 20)
	_p("combination_wrench", Vector3(-19.4, y + 1.26, -12.6), 100)
	_p("bench_vice_01", Vector3(-18.9, y + 1.2, -12.0), 0)
	# More drums and a jerry can cluster; a shelf of tins.
	_pc("Barrel_02", Vector3(-26.6, y, -17.2), 0)
	_pc("metal_jerrycan", Vector3(-20.2, y, -16.2), -30)
	_pc("steel_frame_shelves_02", Vector3(-26.6, y, -13.0), 90)
	_p("oil_tin", Vector3(-26.4, y + 0.6, -13.0), 0)
	_p("cleaner_tin_01", Vector3(-26.4, y + 1.2, -13.0), 0)
	_p("can_rusted", Vector3(-26.4, y + 0.6, -13.5), 0)

func _stack_more() -> void:
	# Deck B cabins: plants and pictures.
	var b: float = B_Y
	_p("fancy_picture_frame_01", Vector3(0.5, b + 1.7, 6.2), 0)
	_p("celandine_01", Vector3(6.9, b + 0.76, 7.6), 0)
	_p("ceramic_vase_02", Vector3(18.0, b + 0.76, 17.4), 0)
	_pc("chinese_stool", Vector3(15.5, b, 16.0), 0)
	# Deck C control: a plant, a laptop, a chair, an alarm clock.
	var c: float = C_Y
	_pc("fern_02", Vector3(5.0, c, 16.5), 0)
	_p("classic_laptop", Vector3(6.0, c + 0.76, 7.4), 180)
	_p("alarm_clock_01", Vector3(20.6, c + 0.77, 16.4), 160)
	_pc("bar_chair_round_01", Vector3(7.0, c, 8.4), 0)
	# Deck D works: more tools + a bronze ray statue tucked on a shelf.
	var d: float = D_Y
	_p("adjustable_wrench", Vector3(22.2, d + 1.15, 17.2), 40)
	_p("bronze_ray_statue", Vector3(22.2, d + 1.7, 16.6), 0)
	_pc("Shelf_01", Vector3(9.0, d, 16.0), 90)
	_p("brass_vase_01", Vector3(9.0, d + 1.0, 16.0), 0)
