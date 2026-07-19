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

## The salvage economy. Any prop id with an entry in SalvageTable is streamed in as
## a Salvage station rather than a grabbable MovableProp, so a dead drawer cabinet
## becomes steel plate instead of scenery. Preloaded per the class-cache rule.
const SALVAGE := preload("res://scripts/components/salvage.gd")
const SALVAGE_TABLE := preload("res://scripts/world/salvage_table.gd")
const HARVEST_NODES := preload("res://scripts/world/harvest_nodes.gd")

## Food/drink dressing that reads as real, found food: any of these prop ids, wherever
## it's placed, becomes a Takeable carrying an items.json id, so a player can pick it up
## and eat/drink it. Comfort matters — the galley should feel like people ate here.
## (prop_id -> item_id; the item's name/nourishment live in data/items.json.)
const FOOD_MAP := {
	"croissant": "croissant", "carrot_cake": "carrot_cake", "bananas": "bananas",
	"food_apple_01": "apple", "food_avocado_01": "avocado", "hamburger_buns": "burger_buns",
	"lemon": "lemon", "strawberry_chocolate_cake": "chocolate_cake", "CheeseBox_01": "cheese_wedge",
	"russian_food_cans_01": "ration_tin", "long_life_food": "long_life_ration",
	"wine_bottles_01": "wine_bottle", "plastic_bottle_gallon": "water_jug",
}

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
	# Third pass — small scattered PERSONAL / HOUSEHOLD clutter (wave-4 assets), placed
	# onto real surfaces with _ps (a fixed settle-drop rests them flush; see _ps).
	# Queued LAST so every supporting desk/shelf exists before an item lands on it.
	_scatter_wetdeck()
	_scatter_decka()
	_scatter_deckb()
	_scatter_deckc()
	_scatter_deckd()
	# The wet deck's natural stock — tar seams, barnacle crust, snagged floats,
	# kelp, the fish-cleaning board. Cheap CSG, so it goes up immediately.
	add_child(HARVEST_NODES.new())
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
		if FOOD_MAP.has(id):
			_make_food(id, FOOD_MAP[id], item[1], item[2], item[3])
		elif SALVAGE_TABLE.has_def(id):
			SALVAGE.from_prop(self, id, item[1], item[2], item[3], SALVAGE_TABLE.def(id))
		else:
			var mov: bool = PropLib.is_moveable(id)
			var node: Node3D = PropLib.spawn(id, self, item[1], item[2], item[3], item[4], -1.0, mov)
			# Seat it on whatever is actually beneath it. Every prop height here is a
			# hand-typed number, so any mismatch with the real bench/shelf/deck top left
			# the object hovering — the oil can and gloves by the rigging bench were the
			# first thing a new player saw. The drop is bounded (SNAP_MAX_DROP) so this
			# only corrects near-misses and never drags wall-mounted dressing to the floor.
			if node != null:
				preload("res://scripts/world/surface_snap.gd").attach(
					node, 0, 1.2, SNAP_MAX_DROP)
		i += 1
		if i % PER_FRAME == 0:
			await get_tree().process_frame
	_queue.clear()

## A food/drink prop the player can pick up and eat. The real CC0 food model is the
## world visual on a Takeable that hands its items.json id to the pack; a surface-snap
## rests it flush on whatever counter, table, or shelf is under it (missing model ->
## the labelled fallback crate, still takeable).
func _make_food(prop_id: String, item_id: String, pos: Vector3, yaw: float, sm: float) -> void:
	var t := Takeable.new()
	t.item_id = item_id
	t.display_name = String(PlayerState.items.get(item_id, {}).get("name", item_id))
	add_child(t)
	t.global_position = pos
	t.rotation.y = deg_to_rad(yaw)
	PropLib.spawn(prop_id, t, pos, 0.0, sm)   # the food model, parented as the visual
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var sz: float = maxf(float(PropLib.SIZE_HINT.get(prop_id, 0.3)) * sm, 0.22)
	box.size = Vector3(sz, sz, sz)
	col.shape = box
	col.position.y = sz * 0.5
	t.add_child(col)
	preload("res://scripts/world/surface_snap.gd").attach(t)

# ---- placement helpers ----

func _p(id: String, pos: Vector3, yaw: float = 0.0, sm: float = 1.0) -> void:
	_queue.append([id, pos, yaw, sm, false])

func _pc(id: String, pos: Vector3, yaw: float = 0.0, sm: float = 1.0) -> void:
	## Colliding variant for big floor furniture the player should bump.
	_queue.append([id, pos, yaw, sm, true])

## Settle drop applied to every scattered clutter item. The wave-4 _ps coords were
## authored with a ~0.10m hover for the old surface-snap to catch; snap is gone (it
## didn't stick on the frozen MovableProp bodies these items become — hence the
## floating). Prop pivots sit at the model base, so lowering the queued Y by this
## much lands the dominant 0.10-hover flush, keeps the rest within ~0.06 of resting,
## and never sinks a floor item below its deck.
const _PS_SETTLE: float = 0.10
## Largest correction the per-prop surface snap may apply. Big enough to seat anything
## authored a little off its bench or shelf, small enough that a wall clock 1.5m up a
## bulkhead is never mistaken for a floating prop and dragged to the deck.
const SNAP_MAX_DROP: float = 0.55

func _ps(id: String, pos: Vector3, yaw: float = 0.0, sm: float = 1.0) -> void:
	## Scattered clutter. Give pos.y as the authored surface-top + small hover; the
	## _PS_SETTLE drop rests it on the surface, like the hand-placed _p items do.
	_queue.append([id, pos - Vector3(0, _PS_SETTLE, 0), yaw, sm, false])

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
	# On the fitter's bench (rig_builder now builds it; top y+0.95). These used to
	# be authored at y+1.25 with nothing underneath them. The pipe wrench that sat
	# here is now the takeable "wrench" placed with the bench.
	_p("metal_toolbox", Vector3(-19.75, y + 0.95, -11.8), 0)
	_p("small_oil_can_01", Vector3(-20.2, y + 0.95, -11.75), 0)
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
	# The board hangs on the EAST bulkhead (interior face x27.875), facing back
	# across the room with a clear throwing lane. It used to sit at (18.15, 11.0)
	# — dead centre of the west doorway, a dark disc floating in the only way in.
	_p("dartboard", Vector3(27.82, y + 1.8, 15.5), -90)
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
	# The rest of the tool wall, resting on the fitter's bench top (y+0.95). The
	# hammer and combination wrench that lay here are now the takeable
	# "hammer_tool" and "spanner", placed with the bench in rig_builder.
	_p("crowbar_01", Vector3(-20.55, y + 0.95, -12.55), 60)
	_p("bolt_cutters_01", Vector3(-19.05, y + 0.95, -11.7), -40)
	_p("bench_vice_01", Vector3(-18.9, y + 0.95, -12.0), 0)
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
	_p("fancy_picture_frame_01", Vector3(2.2, b + 1.7, 6.2), 0)   # on the pier by the balcony door, off the glass
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

# ============================================================ scatter (wave 4)
# Small personal/household items on real surfaces. _ps = authored surface-top + hover,
# then a fixed settle-drop rests it flush; _p = exact. Matched to each room's use;
# kept off windows, doorways, and the SPHL exit corridor.

func _scatter_wetdeck() -> void:
	var w: float = WET_Y
	# Rigging bench west third (25,-17.5, top ~2.96) — a working deck bench.
	_ps("garden_gloves_01", Vector3(24.0, w + 1.1, -17.5), 20)
	_ps("fishermans_hat", Vector3(24.3, w + 1.1, -17.1), -30)
	_ps("can_rusted", Vector3(24.6, w + 1.1, -17.9), 0)
	_ps("oil_tin", Vector3(23.7, w + 1.1, -17.8), 40)
	# Pump-room dead-pump top (12,-12, ~3.8) beside the toolbox, and the dry SW corner.
	_ps("russian_food_cans_01", Vector3(12.3, w + 2.0, -12.3), 15)
	_ps("plastic_thermos", Vector3(11.7, w + 2.0, -11.8), -20)
	_ps("plastic_container", Vector3(10.8, w + 0.15, -12.8), 0)
	# Loot-room shelves (10.4,-19, ~2.6/3.3) — a stores room.
	_ps("russian_food_cans_01", Vector3(10.4, w + 0.75, -18.3), 10)
	_ps("pot_enamel_01", Vector3(10.4, w + 0.75, -19.6), -15)
	_ps("can_rusted", Vector3(10.4, w + 1.45, -18.2), 0)
	_ps("wicker_basket_01", Vector3(14.6, w + 0.15, -20.6), 30)
	# SPHL interior — the survivor's few things on the aft benches (all west of x18).
	_ps("modified_thermos", Vector3(16.6, w + 0.75, -24.9), 10)
	_ps("round_spectacles", Vector3(16.0, w + 0.72, -23.1), -20)
	_ps("Camera_01", Vector3(15.8, w + 0.75, -23.2), 40)
	_ps("wooden_bowl_02", Vector3(17.1, w + 0.72, -24.9), 0)
	# Stair-tower machinery room (y6) beside the spool + NW corner.
	_ps("oil_tin", Vector3(27.4, 6.0 + 1.15, 6.2), 20)
	_ps("garden_gloves_01", Vector3(25.0, 6.0 + 0.15, 8.6), -10)
	# Breaker Room 4-A (y10) — utilitarian floor corners.
	_p("clipboard", Vector3(26.6, 10.0 + 0.02, 3.2), 30)
	_ps("can_rusted", Vector3(27.0, 10.0 + 0.15, 8.8), 0)

func _scatter_decka() -> void:
	var y: float = DECK_Y
	# Bunkhouse: a second personal item on each locker top (locker at bedx+1.2, bedz-0.8, ~19.8).
	var beds := [Vector3(-25.5, y, 6.5), Vector3(-18.8, y, 6.5), Vector3(-12.0, y, 6.5),
			Vector3(-25.5, y, 15.5), Vector3(-18.8, y, 15.5), Vector3(-12.0, y, 15.5)]
	var kit := ["cigarette_pack", "vintage_lighter", "cassette_player", "round_spectacles", "postcard_set_01", "cigarette_case"]
	for i in range(beds.size()):
		var p: Vector3 = beds[i]
		_ps(kit[i], p + Vector3(1.2, 2.0, -0.8), i * 37.0)
	# Shared table (-18.5,11, ~18.78) + nightstand (-23.6,11.8) + a book by the armchair.
	_ps("brass_candleholders", Vector3(-18.5, y + 0.95, 11.0), 0)
	_ps("wooden_bowl_01", Vector3(-18.1, y + 0.95, 11.3), 20)
	_ps("standing_picture_frame_01", Vector3(-23.6, y + 0.8, 11.8), 10)
	_ps("book_encyclopedia_set_01", Vector3(-25.0, y + 0.7, 11.5), -15)   # on the armchair arm
	# Galley: dishware + food on counter (z17, ~19.0) and tables; a kettle on the counter.
	_ps("vintage_electric_kettle", Vector3(6.5, y + 1.1, 17.0), 0)
	_ps("carved_wooden_plate", Vector3(7.6, y + 1.1, 17.1), 15)
	_ps("tea_set_01", Vector3(9.0, y + 1.1, 17.0), -10)
	_ps("wooden_cutting_board", Vector3(4.5, y + 1.1, 17.1), 0)
	_ps("hamburger_buns", Vector3(3.2, y + 1.1, 17.0), 20)
	_ps("lemon", Vector3(2.4, y + 1.1, 17.2), 0)
	_ps("wine_bottles_01", Vector3(10.2, y + 1.1, 16.9), 0)
	_ps("metal_jug", Vector3(2.0, y + 0.6, 11.0), 30)        # table (2,11)
	_ps("wooden_bowl_01", Vector3(8.0, y + 0.6, 11.0), 0)     # table (8,11)
	_ps("carved_wooden_plate", Vector3(2.0, y + 0.6, 14.5), -20)
	_ps("strawberry_chocolate_cake", Vector3(8.0, y + 0.6, 14.5), 0)
	_ps("brass_pot_01", Vector3(-1.6, y + 2.3, 12.0), 0)     # top wall shelf
	_ps("pot_enamel_01", Vector3(-1.6, y + 2.3, 13.2), 0)
	# Rec room: toys + clutter (low table 23,12.5 ~18.32; TV stand 26.6,12.5; magazine tbl 24.8,10.5; shelf top 25.5,17.6 ~20.0).
	_ps("mantel_clock_01", Vector3(25.5, y + 2.1, 17.6), 180)
	_ps("brass_candleholders", Vector3(24.8, y + 2.1, 17.6), 0)
	_ps("gaming_console", Vector3(26.6, y + 0.9, 12.5), -90)
	_ps("gamepad", Vector3(26.2, y + 0.9, 12.9), 20)
	_ps("sungka_board", Vector3(23.0, y + 0.44, 12.9), 0)    # on the low table
	_ps("baseball_01", Vector3(22.6, y + 0.44, 12.2), 0)
	_ps("vintage_video_camera", Vector3(24.8, y + 0.4, 10.5), 30)  # magazine table
	_ps("wooden_candlestick", Vector3(20.5, y + 0.9, 9.3), 0)      # by the sofa

func _scatter_deckb() -> void:
	var y: float = B_Y
	# Cabins B-01..B-05 — intimate desk/locker clutter (desks 1.8,6.9 & 6.9,8.0 ~22.36; lockers ~23.4).
	_ps("round_spectacles", Vector3(1.8, y + 0.85, 6.9), 20)
	_ps("cigarette_case", Vector3(2.1, y + 0.85, 7.1), -30)
	_ps("seadogs_compass", Vector3(6.9, y + 0.85, 8.0), 0)
	_ps("postcard_set_01", Vector3(6.6, y + 0.85, 7.8), 15)
	_ps("standing_picture_frame_01", Vector3(7.3, y + 1.9, 6.9), 180)   # locker top
	_ps("vintage_oil_lamp", Vector3(2.4, y + 1.9, 10.2), 0)            # locker top (B-01 corridor side)
	_ps("brass_vase_02", Vector3(11.9, y + 0.3, 10.3), 0)             # kelp-shrine table (B-03)
	# Linen store (shelves x27.6, z6.9..9.9) — extra pillows + a spray bottle.
	_ps("throw_pillows_01", Vector3(27.6, y + 1.0, 9.9), 0)
	_ps("all_purpose_cleaner", Vector3(27.6, y + 1.7, 9.6), 20)
	# Wash room: toiletries on the counter ENDS (x-0.5, x3.5 — clear of window centres 0,4), a duck.
	_ps("multi_cleaner_bottle", Vector3(3.5, y + 1.0, 17.3), 0)
	_ps("medical_tape", Vector3(-0.5, y + 1.0, 17.3), 20)
	_ps("rubber_duck_toy", Vector3(-0.3, y + 1.0, 17.5), -40)
	_p("plunger", Vector3(4.6, y + 0.02, 17.6), 0)
	# Crew lounge: cards/snacks on the card table (8.2,14.6 ~22.06) + a projector, a bottle.
	_ps("filmstrip_projector_8mm", Vector3(12.5, y + 1.0, 14.6), 90)
	_ps("wooden_bowl_02", Vector3(8.2, y + 0.5, 14.6), 0)
	_ps("wine_bottles_01", Vector3(8.6, y + 0.5, 14.9), 15)
	_ps("throw_pillows_01", Vector3(7.6, y + 0.6, 14.2), 0)          # on the sofa
	# B-06 desk (18,17.1 ~22.36) + Muster locker top (21,16.8).
	_ps("standing_picture_frame_01", Vector3(18.3, y + 0.85, 17.1), 160)
	_ps("cigarette_pack", Vector3(17.7, y + 0.85, 17.3), 0)
	_ps("Megaphone_01", Vector3(21.0, y + 0.85, 16.8), -20)

func _scatter_deckc() -> void:
	var y: float = C_Y
	# Control room desks (5.8/8.0/10.2, 7.4 ~25.86) — the x8 desk stays clear-ish (window x8 on z6 wall, 1.4m off — fine).
	_ps("stationery_supplies", Vector3(5.8, y + 0.8, 7.4), 0)
	_ps("modified_thermos", Vector3(6.2, y + 0.8, 7.6), 20)
	_ps("vintage_stapler", Vector3(10.2, y + 0.8, 7.4), -15)
	_ps("round_spectacles", Vector3(9.9, y + 0.8, 7.6), 0)
	# Rig office desk (14.5,7.5 ~25.9) — a lamp, a clock, ledgers.
	_ps("desk_lamp_arm_01", Vector3(14.2, y + 0.8, 7.5), 30)
	_ps("wall_clock", Vector3(14.7, y + 0.8, 7.7), 0)
	_ps("stationery_supplies", Vector3(14.8, y + 0.8, 7.3), -20)
	_ps("modified_thermos", Vector3(17.3, y + 1.4, 7.0), 0)        # filing-cabinet top
	# Med bay exam bench (20.5,8.0 ~26.0) + supply shelves (21.8,11.6).
	_ps("medical_tape", Vector3(20.5, y + 1.0, 8.0), 0)
	_ps("multi_cleaner_bottle", Vector3(20.9, y + 1.0, 8.2), 20)
	_ps("wall_clock", Vector3(21.8, y + 1.85, 11.6), 90)
	# East dry store shelves (27.5,9.0 ~25.7/26.5) — line them with stores.
	_ps("russian_food_cans_01", Vector3(27.5, y + 0.7, 8.4), 0)
	_ps("pot_enamel_01", Vector3(27.5, y + 0.7, 9.6), 0)
	_ps("CheeseBox_01", Vector3(27.5, y + 1.5, 8.6), 0)
	_ps("jug_01", Vector3(27.5, y + 1.5, 9.5), 0)
	# Comms desk (6.0,16.8 ~25.9) — a mic, a log, a mug, cigarettes.
	_ps("Megaphone_01", Vector3(6.0, y + 0.8, 16.8), 180)
	_ps("cigarette_pack", Vector3(5.5, y + 0.8, 16.5), 20)
	_ps("magnifying_glass_01", Vector3(6.5, y + 0.8, 17.1), -30)
	# Mud logging instrument racks (14.5/17.5/20.5, 17.4 ~26.9) + office desk (20,16.4).
	_ps("stationery_supplies", Vector3(20.0, y + 0.8, 16.4), 0)
	_ps("magnifying_glass_01", Vector3(17.5, y + 1.85, 17.4), 40)

func _scatter_deckd() -> void:
	var y: float = D_Y
	# Gym benches (10.5,10.0 & 13.8,9.2 ~29.2) + floor.
	_ps("garden_gloves_01", Vector3(10.5, y + 0.75, 10.0), 20)
	_ps("plastic_bottle_gallon", Vector3(13.8, y + 0.75, 9.2), 0)
	_ps("baseball_bat", Vector3(14.6, y + 0.1, 8.7), 70)
	# Laundry: folding table (21.5,11.5 ~29.06) + washer tops (17/18.5/20, 8.8).
	_ps("throw_pillows_01", Vector3(21.5, y + 0.55, 11.5), 0)       # folded coveralls stand-in
	_ps("bleach_bottle", Vector3(17.0, y + 0.6, 8.8), 0)
	_ps("multi_cleaner_bottle", Vector3(20.0, y + 0.6, 8.8), 20)
	_p("plastic_broom", Vector3(15.9, y + 0.02, 12.6), 10)
	# Storage/stash nook: crate tops (9.2..10.5,17.0 ~29.4/30.2) + the crouch nook secret (8.9,15.6).
	_ps("vintage_oil_lamp", Vector3(9.8, y + 0.9, 17.0), 0)
	_ps("wicker_basket_02", Vector3(10.2, y + 1.7, 17.0), 30)
	_ps("standing_picture_frame_01", Vector3(8.9, y + 0.1, 15.6), 20)   # personal item in the secret nook
	# Workshop bench (19,17.0 ~29.53), west span — scattered tools; shelf ends.
	_ps("flathead_screwdriver", Vector3(17.6, y + 1.0, 17.0), 40)
	_ps("pliers", Vector3(18.1, y + 1.0, 17.2), -30)
	_ps("measuring_tape_01", Vector3(18.4, y + 1.0, 16.8), 0)
	_ps("lubricant_spray", Vector3(17.9, y + 1.0, 17.3), 10)
	_ps("spray_paint_bottles", Vector3(22.4, y + 1.3, 16.9), 0)      # shelf
	# Roof / mast deck — minimal, weather-tough, near the centre.
	_ps("metal_detector", Vector3(11.0, y + 0.9, 15.2), 40)          # forgotten on the generator hull
	_ps("watering_can_metal_01", Vector3(26.8, y + 0.1, 9.0), 0)     # NE corner inside the rails
