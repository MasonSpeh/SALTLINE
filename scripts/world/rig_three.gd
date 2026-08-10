class_name RigThree extends RefCounted
## RIG 3 — "THE ANCHORAGE" · residential / luxury. NO DRILLING.
##
## The largest structure in the field: an 84 x 60 m main deck on six caissons, two occupied
## decks below it (plant at y 8.8, leisure/pool at 15.4) and towers above. As of this pass
## the ENTIRE MAIN LEVEL IS INDOORS: a one-storey PODIUM covers the deck from x -40..40,
## z -28..22, and the atrium drum stands at its centre as the gathering place. The podium
## roof is a grand TERRACE the two accommodation towers rise from.
##
## THE FLOORPLAN (main level, local coords, drum centre (0, 4), r 16):
##
##   entrance (s door, x -10) -> vestibule/salon -> SOUTH HALL -> drum portals -> ATRIUM
##   DINING HALL: the east wing ground floor, 7.4 m ceiling, its west side an open
##     colonnade aligned with two open drum bays — guests see the tank from every table.
##   KITCHEN: the south-east block, BEHIND the dining hall, service corridor between.
##   RESIDENTIAL HORSESHOE: six suites down the west flank + three across the south, all
##     served by an L-shaped hall that hugs the drum glass (the corridor itself has the
##     view). Private dining/bar north of the main hall; spa block beyond the north portals.
##
## THE DRUM IS PIERCED, NOT SEALED. Eight of its twelve ground-floor bays are open portals
## (E/W/N/S pairs); at G1 the two east bays open too, so the dining hall's view of the tank
## is a two-storey arch. Vertical circulation inside the atrium is a run of CHORD STAIRS
## spanning the void from gallery edge to gallery edge — floor to G1 to G2 to G3 to G4 —
## each flight hanging over the open well with the tank beside it. The old external stair
## core (whose link bridges ran straight through the drum glazing) is gone.
##
## LOCAL FRAME: origin on mean water at platform centre, +Y up, +Z north.
## Placed by rig_field.gd at world (58, 0, 262), bearing +10 deg.

const KIT := preload("res://scripts/world/rig_kit.gd")

# ------------------------------------------------------------------- elevations (metres)

const SUB_TOP: float = 20.90
const LOW_Y: float = 2.20          ## marina deck
const PLANT_Y: float = 8.80        ## machinery deck (open, railed)
const SPA_Y: float = 15.40         ## leisure deck: pool, spa
const MAIN_Y: float = 22.00        ## main level — the indoor floor
const MAIN_T: float = 1.10
const POD_H: float = 4.20          ## podium storey height
const TERRACE: float = MAIN_Y + POD_H          ## 26.20 — the roof terrace
const STOREY: float = 3.70
const G1: float = 25.70            ## atrium galleries
const G2: float = 29.40
const G3: float = 33.10
const G4: float = 36.80
const ATRIUM_ROOF: float = 40.50
const DINE_H: float = 7.40         ## dining hall clear height (double storey)
const DINE_ROOF: float = MAIN_Y + DINE_H       ## 29.40 — east tower springs from here
const W_ROOF: float = TERRACE + STOREY * 3.0   ## 37.30 — west tower roof
const E_ROOF: float = DINE_ROOF + STOREY * 2.0 ## 36.80 — east tower roof
const MAST_TOP: float = 52.00
const HELI_Y: float = 30.00

## THE COLUMN AQUARIUM, in one place, so nothing re-types it.
const TANK_C := Vector2(0.0, 4.0)
const TANK_R: float = 5.40
const TANK_Y0: float = 22.50
const TANK_Y1: float = 39.40

# ---------------------------------------------------------------------- plan (metres)

const LEG_HALF: float = 2.80
const LEG_X: Array = [-28.0, 0.0, 28.0]
const LEG_Z: Array = [-22.0, 22.0]

const DECK := Rect2(-42.0, -30.0, 84.0, 60.0)
const LOWER := Rect2(-34.0, -24.0, 68.0, 48.0)
## Marina stair tower — moved fully OUTSIDE the LOWER footprint (it used to overlap the
## plant and leisure decks by 4 m and its flights ran straight through both slabs).
const STAIRWELL := Rect2(34.5, -6.0, 7.5, 9.0)

const PODIUM := Rect2(-40.0, -28.0, 80.0, 50.0)   ## the indoor main level
const DRUM_C := Vector2(0.0, 4.0)
const DRUM_R: float = 16.00
const GAL_OUT: float = 15.60
const GAL_IN: float = 11.00
const SPUR_IN: float = 6.30
const SPUR_HALF: float = 0.62

const WEST_WING := Rect2(-40.0, -10.0, 22.0, 28.0)  ## tower, springs from TERRACE
const EAST_WING := Rect2(18.0, -10.0, 22.0, 28.0)   ## dining below, tower from DINE_ROOF
const SPA_BLOCK := Rect2(-14.0, 22.0, 28.0, 8.0)    ## pool hall, north of the podium

const PROMENADE := Rect2(-50.0, -14.0, 8.0, 28.0)
const HELI_BASE := Rect2(42.0, -26.0, 10.0, 30.0)
const HELI_C := Vector3(48.0, HELI_Y, -8.0)
const HELI_R: float = 13.00

const BRIDGE_IN := Vector3(-10.0, MAIN_Y, -30.0)
const BRIDGE_OUT := Vector3(8.0, MAIN_Y, 30.0)

## Palette. Cove strips standardise on TWO (colour, energy) pairs — every distinct pair is
## its own material and therefore its own draw chunk.
const COVE := Color(0.42, 0.78, 1.00)
const COVE_E: float = 3.0
const WARM := Color(1.00, 0.88, 0.72)
const WARM_E: float = 2.6
const VELVET := Color(0.13, 0.22, 0.34)     ## upholstery — deep sea blue
const BRASS := Color(0.55, 0.45, 0.22)

static func build(b: KIT.Bake, host: Node3D) -> Dictionary:
	_substructure(b)
	_plant_deck(b)
	_leisure_deck(b)
	_main_deck(b)
	_podium(b)
	_floorplan(b)
	_dining(b)
	_suites(b)
	_atrium(b, host)
	_terrace(b)
	_towers(b)
	_spa(b)
	_helideck(b)
	_marina(b)
	_lights(b, host)
	return {
		"name": "THE ANCHORAGE",
		"bridge_in": BRIDGE_IN,
		"bridge_out": BRIDGE_OUT,
		"deck_y": MAIN_Y,
		"spawn": Vector3(-10.0, MAIN_Y, -25.0),
		"overview": Vector3(29.0, E_ROOF, 4.0),
		"aquarium": {
			"centre": Vector3(TANK_C.x, (TANK_Y0 + TANK_Y1) * 0.5, TANK_C.y),
			"radius": TANK_R - 0.15,
			"height": TANK_Y1 - TANK_Y0,
			"gallery_y": G1,
			"floor_y": MAIN_Y,
		},
		"fishing": [
			{"id": "anchorage_promenade", "at": Vector3(-47.0, MAIN_Y, 0.0), "water": "open"},
			{"id": "anchorage_under_pad", "at": Vector3(47.0, MAIN_Y, -8.0), "water": "open"},
			{"id": "anchorage_marina", "at": Vector3(0.0, LOW_Y, -33.0), "water": "near"},
			{"id": "anchorage_plant_deck", "at": Vector3(-32.0, PLANT_Y, -12.0), "water": "near"},
		],
	}

# ---------------------------------------------------------------- shared wall helpers

## A partition wall along X at fixed z, with door gaps (each 1.1 m + header above 2.1).
static func _wall_x(b: KIT.Bake, x0: float, x1: float, z: float, y: float, h: float,
		doors: Array = [], t: float = 0.18, mat: Material = null) -> void:
	var m: Material = mat if mat != null else MatLib.dirty_white_panel()
	var ds: Array = doors.duplicate()
	ds.sort()
	var cursor: float = x0
	for d in ds:
		if d - 0.55 - cursor > 0.05:
			b.box(Vector3((cursor + d - 0.55) * 0.5, y + h * 0.5, z),
				Vector3(d - 0.55 - cursor, h, t), m, "hull", Vector3.ZERO, true)
		b.box(Vector3(d, y + 2.1 + (h - 2.1) * 0.5, z), Vector3(1.1, h - 2.1, t), m, "hull",
			Vector3.ZERO, true)
		cursor = d + 0.55
	if x1 - cursor > 0.05:
		b.box(Vector3((cursor + x1) * 0.5, y + h * 0.5, z), Vector3(x1 - cursor, h, t), m,
			"hull", Vector3.ZERO, true)

## Same, along Z at fixed x.
static func _wall_z(b: KIT.Bake, z0: float, z1: float, x: float, y: float, h: float,
		doors: Array = [], t: float = 0.18, mat: Material = null) -> void:
	var m: Material = mat if mat != null else MatLib.dirty_white_panel()
	var ds: Array = doors.duplicate()
	ds.sort()
	var cursor: float = z0
	for d in ds:
		if d - 0.55 - cursor > 0.05:
			b.box(Vector3(x, y + h * 0.5, (cursor + d - 0.55) * 0.5),
				Vector3(t, h, d - 0.55 - cursor), m, "hull", Vector3.ZERO, true)
		b.box(Vector3(x, y + 2.1 + (h - 2.1) * 0.5, d), Vector3(t, h - 2.1, 1.1), m, "hull",
			Vector3.ZERO, true)
		cursor = d + 0.55
	if z1 - cursor > 0.05:
		b.box(Vector3(x, y + h * 0.5, (cursor + z1) * 0.5), Vector3(t, h, z1 - cursor), m,
			"hull", Vector3.ZERO, true)

# ------------------------------------------------------------------------ substructure

static func _substructure(b: KIT.Bake) -> void:
	for x in LEG_X:
		for z in LEG_Z:
			KIT.caisson(b, x, z, LEG_HALF, SUB_TOP)
	for z in LEG_Z:
		KIT.pontoon(b, Vector3(0.0, -1.05, z), Vector3(70.0, 4.0, 9.0))
	KIT.pontoon(b, Vector3(0.0, -1.05, 0.0), Vector3(9.0, 4.0, 40.0))
	var steel: Material = MatLib.rust_steel()
	for x in LEG_X:
		for seg in [[-22.0, 0.0], [0.0, 22.0]]:
			b.member(Vector3(x, 1.4, seg[0]), Vector3(x, 7.6, seg[1]), 0.5, steel, "hull")
			b.member(Vector3(x, 7.6, seg[0]), Vector3(x, 1.4, seg[1]), 0.5, steel, "hull")
			b.member(Vector3(x, 10.2, seg[0]), Vector3(x, 14.6, seg[1]), 0.42, steel, "hull")
			b.member(Vector3(x, 14.6, seg[0]), Vector3(x, 10.2, seg[1]), 0.42, steel, "hull")
	for z in LEG_Z:
		for seg2 in [[-28.0, 0.0], [0.0, 28.0]]:
			b.member(Vector3(seg2[0], 1.4, z), Vector3(seg2[1], 7.6, z), 0.5, steel, "hull")
			b.member(Vector3(seg2[1], 1.4, z), Vector3(seg2[0], 7.6, z), 0.5, steel, "hull")
			b.member(Vector3(seg2[0], 16.6, z), Vector3(seg2[1], 20.4, z), 0.42, steel, "hull")
	for z in [-22.0, 0.0, 22.0]:
		b.box(Vector3(0.0, 20.0, z), Vector3(78.0, 1.5, 1.4), steel, "hull")
	for x in LEG_X:
		b.box(Vector3(x, 20.0, 0.0), Vector3(1.4, 1.5, 54.0), steel, "hull")
	# Marina stair core: LOW -> MAIN in six flights of 3.30, so its landings fall EXACTLY on
	# the plant deck (8.8) and the leisure deck (15.4).
	KIT.stair_tower(b, STAIRWELL, LOW_Y, MAIN_Y, 3.30, true)

static func _plant_deck(b: KIT.Bake) -> void:
	KIT.deck(b, LOWER, PLANT_Y, 0.32, MatLib.grating())
	KIT.rail_rect(b, LOWER, PLANT_Y, [["e", -6.0, 3.0], ["w", -6.0, 6.0]], 0.3)
	# Apron from the (relocated) stair tower's 8.8 landing onto the deck edge.
	KIT.catwalk(b, Vector3(34.9, PLANT_Y, -1.5), Vector3(33.6, PLANT_Y, -1.5), 2.6, false)
	for i in range(3):
		var x: float = -26.0 + i * 9.0
		KIT.skid(b, Vector3(x, PLANT_Y, -16.0), Vector3(7.0, 3.2, 4.4), 0.0)
		b.cyl(Vector3(x + 2.6, PLANT_Y + 6.4, -16.0), 0.55, 12.0, MatLib.dark_metal(), "hull")
		b.cyl(Vector3(x + 2.6, PLANT_Y + 12.8, -16.0), 0.7, 0.8, MatLib.rust_steel(), "detail")
	KIT.vessel(b, Vector3(-28.0, PLANT_Y, 2.0), 2.1, 7.4, true)
	KIT.vessel(b, Vector3(-21.0, PLANT_Y, 2.0), 2.1, 7.4, true)
	KIT.exchanger_bank(b, Vector3(-13.0, PLANT_Y, 2.0), 3, 8.0, 0.0)
	KIT.vessel(b, Vector3(6.0, PLANT_Y, 6.0), 2.6, 8.6, true)
	for i in range(2):
		KIT.vessel(b, Vector3(16.0 + i * 9.0, PLANT_Y, 16.0), 1.7, 11.0, false, 0.0)
	KIT.manifold(b, Vector3(-2.0, PLANT_Y, -21.0), 9.0, 3.6, 0.0)
	KIT.manifold(b, Vector3(24.0, PLANT_Y, -21.0), 7.0, 3.6, 0.0)
	for z in [-8.0, 10.0]:
		KIT.pipe_rack(b, Vector3(-32.0, PLANT_Y + 4.6, z), Vector3(32.0, PLANT_Y + 4.6, z), 6, 3.4)
	KIT.cable_tray(b, Vector3(-32.0, PLANT_Y + 5.8, -4.0), Vector3(32.0, PLANT_Y + 5.8, -4.0))
	KIT.cable_tray(b, Vector3(-32.0, PLANT_Y + 5.8, 14.0), Vector3(32.0, PLANT_Y + 5.8, 14.0))
	KIT.railed_walk(b, Vector3(-30.0, PLANT_Y + 3.4, -12.0), Vector3(30.0, PLANT_Y + 3.4, -12.0), 1.6,
		[[54.4, 57.6]], [])
	KIT.catwalk(b, Vector3(-30.0, PLANT_Y + 3.4, 8.0), Vector3(30.0, PLANT_Y + 3.4, 8.0), 1.6, true, PLANT_Y)
	KIT.catwalk(b, Vector3(-30.0, PLANT_Y + 3.4, -12.0), Vector3(-30.0, PLANT_Y + 3.4, 8.0), 1.6, true, PLANT_Y)
	# Up onto the overhead route: retargeted so the head lands ON the z -12 catwalk (the old
	# flight ended at z -6, four metres from any deck — a stair to nowhere).
	KIT.stair(b, Vector3(26.0, PLANT_Y, -4.0), Vector3(26.0, PLANT_Y + 3.4, -11.4), 1.5, true, true)
	for i in range(8):
		KIT.lamp_lens(b, Vector3(-28.0 + i * 8.0, PLANT_Y + 5.2, -4.0), WARM, 0.4, 4.5)
		KIT.lamp_lens(b, Vector3(-28.0 + i * 8.0, PLANT_Y + 5.2, 14.0), WARM, 0.4, 4.5)

static func _leisure_deck(b: KIT.Bake) -> void:
	var head: float = MAIN_Y - SPA_Y - 1.4
	var shell: Material = MatLib.dirty_white_panel()
	var pane: Material = MatLib.glass(Color(0.60, 0.76, 0.82))
	var pool := Rect2(-11.0, -8.0, 22.0, 16.0)
	KIT.deck_hole(b, LOWER, pool, SPA_Y, 0.5, MatLib.lino_floor())
	for side in ["s", "n", "w"]:
		KIT._wall_band(b, LOWER, side, SPA_Y, 0.0, 1.05, 0.3, shell)
		KIT._wall_band(b, LOWER, side, SPA_Y, 1.05, head - 0.6, 0.12, pane)
		KIT._wall_band(b, LOWER, side, SPA_Y, head - 0.6, head, 0.3, shell)
	# EAST WALL WITH A DOORWAY at z -6..3 — the stair tower's 15.4 landing arrives here, and
	# the first build walled it off (the leisure deck was reachable only through a wall).
	for seg in [[-24.0, -6.2], [3.2, 24.0]]:
		var sub := Rect2(LOWER.position.x, seg[0], LOWER.size.x, seg[1] - seg[0])
		KIT._wall_band(b, sub, "e", SPA_Y, 0.0, 1.05, 0.3, shell)
		KIT._wall_band(b, sub, "e", SPA_Y, 1.05, head - 0.6, 0.12, pane)
		KIT._wall_band(b, sub, "e", SPA_Y, head - 0.6, head, 0.3, shell)
	var hd := Rect2(LOWER.position.x, -6.2, LOWER.size.x, 9.4)
	KIT._wall_band(b, hd, "e", SPA_Y, 2.3, head, 0.3, shell)
	KIT.catwalk(b, Vector3(34.9, SPA_Y, -1.5), Vector3(33.6, SPA_Y, -1.5), 2.6, false)
	# The pool.
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.22, 0.62, 0.70, 0.55)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.08
	water.emission_enabled = true
	water.emission = Color(0.16, 0.55, 0.62)
	water.emission_energy_multiplier = 0.6
	b.box(Vector3(0.0, SPA_Y - 0.35, 0.0), Vector3(pool.size.x - 0.6, 0.1, pool.size.y - 0.6), water, "glass")
	b.box(Vector3(0.0, SPA_Y - 2.15, 0.0), Vector3(pool.size.x, 0.3, pool.size.y),
		MatLib.kitchen_tile(), "hull", Vector3.ZERO, true)
	for wall in [[Vector3(0, SPA_Y - 1.1, pool.position.y), Vector3(pool.size.x, 2.0, 0.3)],
			[Vector3(0, SPA_Y - 1.1, pool.end.y), Vector3(pool.size.x, 2.0, 0.3)],
			[Vector3(pool.position.x, SPA_Y - 1.1, 0), Vector3(0.3, 2.0, pool.size.y)],
			[Vector3(pool.end.x, SPA_Y - 1.1, 0), Vector3(0.3, 2.0, pool.size.y)]]:
		b.box(wall[0], wall[1], MatLib.kitchen_tile(), "hull", Vector3.ZERO, true)
	KIT.led_cove(b, Vector3(pool.position.x, SPA_Y - 1.95, pool.position.y), Vector3(pool.end.x, SPA_Y - 1.95, pool.position.y), COVE, 0.09, COVE_E)
	KIT.led_cove(b, Vector3(pool.position.x, SPA_Y - 1.95, pool.end.y), Vector3(pool.end.x, SPA_Y - 1.95, pool.end.y), COVE, 0.09, COVE_E)
	KIT.stair(b, Vector3(-8.0, SPA_Y - 2.15, -3.4), Vector3(-8.0, SPA_Y, -7.55), 2.2, false, false)
	for i in range(4):
		var x2: float = 15.0 + i * 4.4
		b.box(Vector3(x2, SPA_Y + head * 0.5, -13.0), Vector3(0.22, head, 10.0), shell, "hull", Vector3.ZERO, true)
	b.box(Vector3(21.6, SPA_Y + head * 0.5, -8.0), Vector3(13.2, head, 0.22), shell, "hull", Vector3.ZERO, true)
	var cy: float = SPA_Y + head - 0.5
	for run in [[Vector3(LOWER.position.x + 0.8, cy, LOWER.position.y + 0.8), Vector3(LOWER.end.x - 0.8, cy, LOWER.position.y + 0.8)],
			[Vector3(LOWER.position.x + 0.8, cy, LOWER.end.y - 0.8), Vector3(LOWER.end.x - 0.8, cy, LOWER.end.y - 0.8)],
			[Vector3(LOWER.position.x + 0.8, cy, LOWER.position.y + 0.8), Vector3(LOWER.position.x + 0.8, cy, LOWER.end.y - 0.8)],
			[Vector3(LOWER.end.x - 0.8, cy, LOWER.position.y + 0.8), Vector3(LOWER.end.x - 0.8, cy, LOWER.end.y - 0.8)]]:
		KIT.led_cove(b, run[0], run[1], WARM, 0.11, WARM_E)
	KIT.led_ring(b, Vector3(0.0, cy, 0.0), 13.0, COVE, 28, 0.1, COVE_E)

static func _main_deck(b: KIT.Bake) -> void:
	KIT.deck_hole(b, DECK, STAIRWELL, MAIN_Y, MAIN_T)
	KIT.rail_rect(b, DECK, MAIN_Y, [
		["s", -15.0, -5.0],        # bridge from MARROW
		["n", 3.0, 13.0],          # bridge to DEEPWELL
		["w", -14.0, 14.0],        # onto the promenade
		["e", -20.0, 4.0],         # onto the helideck cantilever
	], 0.4)
	KIT.rail_rect(b, STAIRWELL, MAIN_Y, [["n", 35.5, 41.5]], -0.1)
	KIT.deck(b, PROMENADE, MAIN_Y, 0.45, MatLib.checker_plate())
	KIT.rail_rect(b, PROMENADE, MAIN_Y, [["e", -14.0, 14.0]], 0.2)
	var steel: Material = MatLib.rust_steel()
	for z in [-13.0, -6.5, 0.0, 6.5, 13.0]:
		b.member(Vector3(-49.0, MAIN_Y - 0.45, z), Vector3(-38.0, 16.6, z), 0.36, steel, "hull")
	b.box(Vector3(-46.0, MAIN_Y + 0.03, 0.0), Vector3(7.0, 0.06, 26.0), MatLib.weathered_wood(), "detail")
	for i in range(5):
		var z2: float = -12.0 + i * 6.0
		b.box(Vector3(-47.4, MAIN_Y + 0.45, z2), Vector3(0.6, 0.9, 2.0), MatLib.weathered_wood(), "detail", Vector3.ZERO, true)
		b.cyl(Vector3(-44.2, MAIN_Y + 1.9, z2 + 3.0), 0.1, 3.8, MatLib.galvanized(), "detail")
		KIT.lamp_lens(b, Vector3(-44.2, MAIN_Y + 3.7, z2 + 3.0), WARM, 0.35, 5.0)
	# Entrance mat, outside the podium's south door.
	b.box(Vector3(-10.0, MAIN_Y + 0.03, -29.0), Vector3(8.0, 0.06, 2.0), MatLib.weathered_wood(), "detail")

# ---------------------------------------------------------------------------- THE PODIUM

## The one-storey envelope that makes the main level INDOORS: perimeter walls with a full
## window band, and a roof that is the terrace. The drum rises through a railed square
## light-well; its corners (between square and circle) are glazed as skylights.
static func _podium(b: KIT.Bake) -> void:
	var white: Material = MatLib.dirty_white_panel()
	var glass_mat: Material = MatLib.glass(Color(0.60, 0.74, 0.78))
	var doors: Array = [
		["s", -10.0, 0],   # entrance, off the bridge apron
		["w", 0.0, 0],     # to the promenade
		["e", -6.0, 0],    # dining hall to the helideck rim
		["e", -20.0, 0],   # kitchen service door
		["n", -30.0, 0],   # west rim
		["n", 30.0, 0],    # east rim / back corridor
	]
	for side in ["s", "n", "w", "e"]:
		KIT._block_wall(b, PODIUM, side, MAIN_Y, POD_H, 0.3, white, glass_mat, true, doors, 0)
	# THE TERRACE SLABS. Rects around the drum's square light-well (x -16.4..16.4,
	# z -12.4..20.4), the dining hall's taller volume (x 18..40, z -10..18) and the
	# interior terrace stair (x 26..37, z 18..22).
	var slab: Material = MatLib.deck_plate()
	KIT.deck(b, Rect2(-40.0, -28.0, 23.6, 50.0), TERRACE, 0.4, slab)             # west
	KIT.deck(b, Rect2(-16.4, -28.0, 32.8, 15.6), TERRACE, 0.4, slab)             # south of drum
	KIT.deck(b, Rect2(-16.4, 20.4, 32.8, 1.6), TERRACE, 0.4, slab)               # north sliver
	KIT.deck(b, Rect2(16.4, -28.0, 1.6, 50.0), TERRACE, 0.4, slab)               # east sliver
	KIT.deck(b, Rect2(18.0, -28.0, 22.0, 18.0), TERRACE, 0.4, slab)              # south-east
	KIT.deck(b, Rect2(18.0, 18.0, 8.0, 4.0), TERRACE, 0.4, slab)                 # by the stair
	KIT.deck(b, Rect2(37.0, 18.0, 3.0, 4.0), TERRACE, 0.4, slab)
	# Corner skylights: flat glass panes hugging each square corner, clear of the circle.
	var sky: Material = MatLib.glass(Color(0.70, 0.84, 0.88))
	for c in [[1.0, 1.0], [-1.0, 1.0], [1.0, -1.0], [-1.0, -1.0]]:
		var sx: float = c[0]
		var sz: float = c[1]
		b.box(Vector3(DRUM_C.x + sx * 14.4, TERRACE - 0.12, DRUM_C.y + sz * 14.2), Vector3(3.6, 0.07, 4.0), sky, "glass")
		b.box(Vector3(DRUM_C.x + sx * 11.6, TERRACE - 0.12, DRUM_C.y + sz * 15.3), Vector3(2.2, 0.07, 1.8), sky, "glass")

# --------------------------------------------------------------------- THE FLOORPLAN

## Interior partitions of the main level: the L-shaped hall hugging the drum, the suite
## walls, the vestibule and salon. Room heights run to the terrace slab (3.8 m clear).
static func _floorplan(b: KIT.Bake) -> void:
	var h: float = POD_H - 0.4
	# WEST HALL runs x -24..-16, z -13..14, alongside the drum glass; the NW pocket carries
	# it on to the north vestibule. Suite front wall with six doorways:
	_wall_z(b, -13.0, 22.0, -24.0, MAIN_Y, h, [-9.65, -2.95, 3.75, 10.45, 15.85, 19.95])
	# Suite party walls, west column (x -40..-24).
	for z in [-6.3, 0.4, 7.1, 13.8, 17.9]:
		_wall_x(b, -40.0, -24.0, z, MAIN_Y, h)
	# SOUTH HALL z -13..-9: suite front wall with three doorways, open from x -16 eastward
	# (vestibule + salon flow straight through to the drum portals).
	_wall_x(b, -40.0, -16.0, -13.0, MAIN_Y, h, [-36.0, -28.0, -20.0])
	# South suite party walls.
	for x in [-32.0, -24.0, -16.0]:
		_wall_z(b, -28.0, -13.0, x, MAIN_Y, h)
	# Salon / service split, and the service corridor to the kitchen.
	_wall_z(b, -28.0, -13.0, 16.0, MAIN_Y, h, [-16.0])
	_wall_z(b, -27.5, -14.0, 20.0, MAIN_Y, h, [-20.0])
	_wall_x(b, 20.0, 40.0, -14.0, MAIN_Y, h, [22.0])
	# BACK CORRIDOR north strip (z 18..22, x 18..40) behind the private dining room.
	_wall_x(b, 18.0, 40.0, 18.0, MAIN_Y, h, [24.0])
	# Private dining / bar: x 18..40, z 12..18 — partition off the main dining hall.
	_wall_x(b, 18.0, 40.0, 12.0, MAIN_Y, h, [24.0, 34.0])
	# Hall cove lighting.
	KIT.led_cove(b, Vector3(-23.0, MAIN_Y + h - 0.35, -12.0), Vector3(-23.0, MAIN_Y + h - 0.35, 21.0), COVE, 0.09, COVE_E)
	KIT.led_cove(b, Vector3(-39.0, MAIN_Y + h - 0.35, -12.2), Vector3(17.0, MAIN_Y + h - 0.35, -12.2), COVE, 0.09, COVE_E)
	# Salon: the pre-atrium sitting court (x -4..16, z -28..-13).
	_salon(b)

static func _salon(b: KIT.Bake) -> void:
	var rug: Material = MatLib.canvas(Color(0.30, 0.34, 0.42))
	b.box(Vector3(6.0, MAIN_Y + 0.02, -20.5), Vector3(14.0, 0.04, 9.0), rug, "detail")
	_sofa(b, Vector3(2.0, MAIN_Y, -17.5), 180.0, 2.6)
	_sofa(b, Vector3(10.0, MAIN_Y, -17.5), 180.0, 2.6)
	_sofa(b, Vector3(2.0, MAIN_Y, -23.5), 0.0, 2.6)
	_sofa(b, Vector3(10.0, MAIN_Y, -23.5), 0.0, 2.6)
	for x in [2.0, 10.0]:
		_low_table(b, Vector3(x, MAIN_Y, -20.5), 1.4)
	# Reception desk facing the entrance.
	b.box(Vector3(-10.0, MAIN_Y + 0.55, -22.0), Vector3(4.2, 1.1, 0.9), MatLib.wood(), "hull", Vector3.ZERO, true)
	b.box(Vector3(-10.0, MAIN_Y + 1.12, -22.0), Vector3(4.4, 0.06, 1.0), MatLib.flat(BRASS), "detail")

# ------------------------------------------------------------------------- furniture kit

static func _sofa(b: KIT.Bake, pos: Vector3, yaw_deg: float, len: float = 2.4) -> void:
	var up: Material = MatLib.canvas(VELVET)
	var yaw: float = deg_to_rad(yaw_deg)
	var rot := Vector3(0, yaw, 0)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	b.box(pos + Vector3(0, 0.24, 0), Vector3(len, 0.42, 0.85), up, "hull", rot, true)
	b.box(pos + Vector3(0, 0.62, 0) - fwd * 0.34, Vector3(len, 0.55, 0.2), up, "hull", rot)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	for sgn in [-1.0, 1.0]:
		b.box(pos + side * (sgn * (len * 0.5 - 0.09)) + Vector3(0, 0.5, 0), Vector3(0.18, 0.32, 0.8), up, "detail", rot)
	b.box(pos + Vector3(0, 0.06, 0), Vector3(len - 0.3, 0.12, 0.7), MatLib.flat(BRASS), "detail", rot)

static func _low_table(b: KIT.Bake, pos: Vector3, r: float = 1.0) -> void:
	b.cyl(pos + Vector3(0, 0.42, 0), r * 0.5, 0.05, MatLib.wood(), "detail", Vector3.ZERO, -1.0, 14, true)
	b.cyl(pos + Vector3(0, 0.2, 0), 0.08, 0.4, MatLib.flat(BRASS), "detail")

static func _dining_table(b: KIT.Bake, pos: Vector3, yaw_deg: float) -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var rot := Vector3(0, yaw, 0)
	b.box(pos + Vector3(0, 0.74, 0), Vector3(2.6, 0.07, 1.1), MatLib.wood(), "hull", rot, true)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	for sgn in [-1.0, 1.0]:
		b.box(pos + side * (sgn * 0.9) + Vector3(0, 0.37, 0), Vector3(0.12, 0.74, 0.7),
			MatLib.flat(BRASS), "detail", rot)
	for i in range(3):
		var t: float = -0.85 + i * 0.85
		for sgn2 in [-1.0, 1.0]:
			var cp: Vector3 = pos + side * t + fwd * (sgn2 * 0.85)
			b.box(cp + Vector3(0, 0.24, 0), Vector3(0.45, 0.48, 0.45), MatLib.canvas(VELVET), "detail", rot, true)
			b.box(cp + fwd * (sgn2 * 0.2) + Vector3(0, 0.62, 0), Vector3(0.45, 0.5, 0.08), MatLib.canvas(VELVET), "detail", rot)

static func _bed(b: KIT.Bake, pos: Vector3, yaw_deg: float) -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var rot := Vector3(0, yaw, 0)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))   # foot direction
	b.box(pos + Vector3(0, 0.22, 0), Vector3(1.9, 0.4, 2.2), MatLib.wood(), "hull", rot, true)
	b.box(pos + Vector3(0, 0.52, 0), Vector3(1.8, 0.24, 2.1), MatLib.flat(Color(0.86, 0.85, 0.8)), "hull", rot)
	b.box(pos - fwd * 1.16 + Vector3(0, 0.85, 0), Vector3(1.9, 0.9, 0.12), MatLib.wood(), "detail", rot)
	b.box(pos + fwd * 0.55 + Vector3(0, 0.66, 0), Vector3(1.8, 0.08, 0.9), MatLib.canvas(VELVET), "detail", rot)
	for sgn in [-1.0, 1.0]:
		b.box(pos - fwd * 0.7 + Vector3(cos(yaw), 0, -sin(yaw)) * (sgn * 0.62) + Vector3(0, 0.62, 0),
			Vector3(0.45, 0.09, 0.3), MatLib.flat(Color(0.9, 0.89, 0.85)), "detail", rot)

# ---------------------------------------------------------------------------- THE SUITES

## Nine luxury suites: six down the west flank, three across the south — the residential
## horseshoe. Each has a bed, nightstands, wardrobe, desk, a bathroom pod and a cove line;
## the window band in the podium perimeter is the view out.
static func _suites(b: KIT.Bake) -> void:
	var west_cells: Array = [[-13.0, -6.3], [-6.3, 0.4], [0.4, 7.1], [7.1, 13.8], [13.8, 17.9], [17.9, 22.0]]
	for cell in west_cells:
		var zc: float = (cell[0] + cell[1]) * 0.5
		_suite(b, Vector3(-32.0, MAIN_Y, zc), 90.0, Vector2(cell[1] - cell[0], 16.0))
	var south_cells: Array = [[-40.0, -32.0], [-32.0, -24.0], [-24.0, -16.0]]
	for cell2 in south_cells:
		var xc: float = (cell2[0] + cell2[1]) * 0.5
		_suite(b, Vector3(xc, MAIN_Y, -20.5), 0.0, Vector2(cell2[1] - cell2[0], 15.0))

## `centre` is the room centre; yaw points TOWARD the corridor door; size is (width across,
## depth along the door axis).
static func _suite(b: KIT.Bake, centre: Vector3, yaw_deg: float, size: Vector2) -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	_bed(b, centre - fwd * (size.y * 0.5 - 2.2), yaw_deg)
	b.box(centre + side * (size.x * 0.5 - 0.85) + fwd * 1.2 + Vector3(0, 1.1, 0),
		Vector3(0.6, 2.2, 1.6), MatLib.wood(), "hull", Vector3(0, yaw, 0), true)
	b.box(centre - side * (size.x * 0.5 - 0.95) + fwd * 1.0 + Vector3(0, 0.4, 0),
		Vector3(1.5, 0.8, 0.6), MatLib.wood(), "detail", Vector3(0, yaw, 0), true)
	b.box(centre + Vector3(0, 0.02, 0), Vector3(size.x * 0.55, 0.03, size.y * 0.4),
		MatLib.canvas(Color(0.34, 0.38, 0.46)), "detail", Vector3(0, yaw, 0))
	KIT.lamp_lens(b, centre + Vector3(0, POD_H - 0.75, 0), WARM, 0.3, 4.5)

# ------------------------------------------------------------------------ THE DINING HALL

## The east wing's ground floor, 7.4 m to its ceiling. Its west edge is an open colonnade
## aligned with the drum's two open east bays — the tank is in view from every table.
static func _dining(b: KIT.Bake) -> void:
	var white: Material = MatLib.dirty_white_panel()
	# Ceiling slab (the east tower's floor).
	KIT.deck(b, EAST_WING, DINE_ROOF, 0.4, MatLib.deck_plate())
	# The colonnade: header beam and two columns on the west edge (x 18), fully open below.
	b.box(Vector3(18.0, MAIN_Y + DINE_H - 0.9, 4.0), Vector3(0.5, 1.8, 28.0), white, "hull", Vector3.ZERO, true)
	for z in [-4.0, 12.0]:
		b.box(Vector3(18.0, MAIN_Y + (DINE_H - 1.8) * 0.5, z), Vector3(0.55, DINE_H - 1.8, 0.9), white, "hull", Vector3.ZERO, true)
	# Upper glazing above the podium roofline on the west edge, so the double height reads.
	b.box(Vector3(18.0, TERRACE + 1.5, 4.0), Vector3(0.12, 2.6, 27.0), MatLib.glass(Color(0.62, 0.78, 0.84)), "glass")
	# North/south/east walls above the podium storey (the podium walls carry the lower part).
	for spec in [[Vector3(29.0, TERRACE + 1.6, -9.85), Vector3(22.0, 3.2, 0.3)],
			[Vector3(29.0, TERRACE + 1.6, 17.85), Vector3(22.0, 3.2, 0.3)],
			[Vector3(39.85, TERRACE + 1.6, 4.0), Vector3(0.3, 3.2, 28.0)]]:
		b.box(spec[0], spec[1], white, "hull", Vector3.ZERO, true)
	# Tables: two rows of three, aligned so every seat faces the tank axis.
	for i in range(3):
		var z2: float = -5.0 + i * 8.0
		_dining_table(b, Vector3(24.0, MAIN_Y, z2), 90.0)
		_dining_table(b, Vector3(31.0, MAIN_Y, z2), 90.0)
	# Head table on a low dais at the east end.
	b.box(Vector3(36.6, MAIN_Y + 0.09, 4.0), Vector3(4.5, 0.18, 8.0), MatLib.wood(), "hull", Vector3.ZERO, true)
	_dining_table(b, Vector3(36.6, MAIN_Y + 0.18, 4.0), 0.0)
	# Pendant clusters over each table — the "many lights" of this room.
	for i2 in range(3):
		var z3: float = -5.0 + i2 * 8.0
		for x2 in [24.0, 31.0]:
			b.member(Vector3(x2, MAIN_Y + DINE_H - 0.2, z3), Vector3(x2, MAIN_Y + 3.4, z3), 0.04, MatLib.dark_metal(), "detail")
			KIT.lamp_lens(b, Vector3(x2, MAIN_Y + 3.3, z3), WARM, 0.4, 4.5)
	# Long sideboard and carpet.
	b.box(Vector3(29.0, MAIN_Y + 0.5, -9.2), Vector3(14.0, 1.0, 0.7), MatLib.wood(), "hull", Vector3.ZERO, true)
	b.box(Vector3(27.5, MAIN_Y + 0.02, 3.0), Vector3(17.0, 0.03, 21.0), MatLib.canvas(Color(0.28, 0.32, 0.40)), "detail")
	# Cove at both ceiling edges.
	KIT.led_cove(b, Vector3(19.0, MAIN_Y + DINE_H - 0.5, -9.0), Vector3(19.0, MAIN_Y + DINE_H - 0.5, 17.0), COVE, 0.09, COVE_E)
	KIT.led_cove(b, Vector3(39.0, MAIN_Y + DINE_H - 0.5, -9.0), Vector3(39.0, MAIN_Y + DINE_H - 0.5, 17.0), COVE, 0.09, COVE_E)
	# THE KITCHEN (SE block, behind the dining hall): stainless galley.
	var steelc: Material = MatLib.galvanized()
	for z4 in [-26.6, -15.0]:
		b.box(Vector3(30.0, MAIN_Y + 0.48, z4), Vector3(17.0, 0.96, 0.8), steelc, "hull", Vector3.ZERO, true)
		b.box(Vector3(30.0, MAIN_Y + 0.99, z4), Vector3(17.2, 0.06, 0.9), MatLib.dark_metal(), "detail")
	b.box(Vector3(30.0, MAIN_Y + 0.48, -20.75), Vector3(10.0, 0.96, 1.6), steelc, "hull", Vector3.ZERO, true)
	b.box(Vector3(30.0, MAIN_Y + 2.6, -20.75), Vector3(6.0, 0.8, 2.2), MatLib.dark_metal(), "hull", Vector3.ZERO, true)
	for i3 in range(4):
		KIT.lamp_lens(b, Vector3(24.0 + i3 * 4.0, MAIN_Y + POD_H - 0.75, -20.75), Color(0.88, 0.96, 1.0), 0.35, 4.2)
	# PRIVATE DINING / BAR (x 18..40, z 12..18).
	b.box(Vector3(29.0, MAIN_Y + 0.55, 16.9), Vector3(12.0, 1.1, 0.8), MatLib.wood(), "hull", Vector3.ZERO, true)
	b.box(Vector3(29.0, MAIN_Y + 1.13, 16.9), Vector3(12.2, 0.06, 0.9), MatLib.flat(BRASS), "detail")
	_dining_table(b, Vector3(26.0, MAIN_Y, 14.5), 90.0)
	_dining_table(b, Vector3(34.0, MAIN_Y, 14.5), 90.0)
	KIT.led_cove(b, Vector3(19.0, MAIN_Y + POD_H - 0.6, 17.4), Vector3(39.0, MAIN_Y + POD_H - 0.6, 17.4), WARM, 0.09, WARM_E)

# ---------------------------------------------------------------------------- THE ATRIUM

static func _atrium(b: KIT.Bake, host: Node3D) -> void:
	var c := Vector3(DRUM_C.x, 0.0, DRUM_C.y)
	var white: Material = MatLib.dirty_white_panel()
	var pane: Material = MatLib.glass(Color(0.62, 0.78, 0.84))
	var chrome: Material = MatLib.galvanized()
	var ribs: int = 12
	for i in range(ribs):
		var a: float = TAU * float(i) / float(ribs)
		var p := Vector3(c.x + cos(a) * DRUM_R, 0, c.z + sin(a) * DRUM_R)
		b.box(Vector3(p.x, (MAIN_Y + ATRIUM_ROOF) * 0.5, p.z),
			Vector3(1.5, ATRIUM_ROOF - MAIN_Y + 1.0, 1.1), white, "hull", Vector3(0, -a, 0), true)
		b.box(Vector3(p.x, (MAIN_Y + ATRIUM_ROOF) * 0.5, p.z),
			Vector3(1.75, ATRIUM_ROOF - MAIN_Y, 0.22), chrome, "detail", Vector3(0, -a, 0))
	# Glazing bands — skipping the PORTAL bays, which is what lets the building breathe:
	# at MAIN eight of twelve bays are open (E/W/N/S pairs), and the two east bays are open
	# at G1 as well so the dining hall gets its two-storey arch onto the tank.
	for lvl in [MAIN_Y, G1, G2, G3, G4]:
		var top: float = minf(lvl + STOREY, ATRIUM_ROOF)
		for i2 in range(ribs):
			if not _is_portal(lvl, i2):
				var a0: float = TAU * (float(i2) + 0.09) / float(ribs)
				var a1: float = TAU * (float(i2) + 0.91) / float(ribs)
				var mid_a: float = (a0 + a1) * 0.5
				var seg: float = 2.0 * DRUM_R * sin((a1 - a0) * 0.5)
				var p2 := Vector3(c.x + cos(mid_a) * DRUM_R, 0, c.z + sin(mid_a) * DRUM_R)
				b.box(Vector3(p2.x, lvl + (top - lvl) * 0.5 + 0.35, p2.z),
					Vector3(0.14, maxf(top - lvl - 0.9, 0.4), seg), pane, "glass", Vector3(0, -mid_a, 0))
				b.collider(Vector3(p2.x, lvl + (top - lvl) * 0.5 + 0.35, p2.z),
					Vector3(0.24, maxf(top - lvl - 0.9, 0.4), seg), Vector3(0, -mid_a, 0))
			# Spandrel bands: skipped over MAIN portals so thresholds are clean floor.
			if absf(lvl - MAIN_Y) < 0.01 and _is_portal(lvl, i2):
				continue
			var a2: float = TAU * (float(i2) + 0.09) / float(ribs)
			var a3: float = TAU * (float(i2) + 0.91) / float(ribs)
			var mid2: float = (a2 + a3) * 0.5
			var seg2: float = 2.0 * DRUM_R * sin((a3 - a2) * 0.5)
			b.box(Vector3(c.x + cos(mid2) * DRUM_R, lvl - 0.42, c.z + sin(mid2) * DRUM_R),
				Vector3(0.44, 0.9, seg2), white, "hull", Vector3(0, -mid2, 0))
	# Glass roof cone.
	KIT.ring_deck(b, Vector3(c.x, ATRIUM_ROOF, c.z), DRUM_R - 1.0, DRUM_R + 0.8, 0.5, MatLib.deck_plate(), 24)
	for i4 in range(24):
		var a4: float = TAU * float(i4) / 24.0
		var a5: float = TAU * float(i4 + 1) / 24.0
		var mid3: float = (a4 + a5) * 0.5
		var rr: float = DRUM_R - 0.8
		b.box(Vector3(c.x + cos(mid3) * rr * 0.5, ATRIUM_ROOF + 1.5, c.z + sin(mid3) * rr * 0.5),
			Vector3(rr, 0.12, 2.0 * rr * 0.5 * sin(PI / 24.0) * 2.2 + 0.35), pane, "glass",
			Vector3(0, -mid3, deg_to_rad(-9.0)))
		b.member(Vector3(c.x + cos(mid3) * rr, ATRIUM_ROOF + 0.6, c.z + sin(mid3) * rr),
			Vector3(c.x, ATRIUM_ROOF + 2.7, c.z), 0.2, chrome, "hull")
	b.cyl(Vector3(c.x, ATRIUM_ROOF + 2.9, c.z), 2.2, 1.0, white, "hull", Vector3.ZERO, 1.4, 24)
	# THE TANK and its saucer.
	KIT.column_tank(b, TANK_C, TANK_R, TANK_Y0, TANK_Y1, 40)
	b.cyl(Vector3(TANK_C.x, MAIN_Y + 0.16, TANK_C.y), 11.4, 0.32, MatLib.lino_floor(), "hull", Vector3.ZERO, -1.0, 32, true)
	b.cyl(Vector3(TANK_C.x, MAIN_Y + 0.62, TANK_C.y), 8.6, 0.6, white, "hull", Vector3.ZERO, -1.0, 32, true)
	KIT.ring_deck(b, Vector3(c.x, MAIN_Y + 0.04, c.z), 11.4, DRUM_R - 0.8, 0.16, MatLib.lino_floor(), 32)
	KIT.led_ring(b, Vector3(TANK_C.x, MAIN_Y + 0.36, TANK_C.y), 11.1, COVE, 32, 0.12, COVE_E)
	KIT.led_ring(b, Vector3(TANK_C.x, MAIN_Y + 1.0, TANK_C.y), 8.8, COVE, 32, 0.1, COVE_E)
	# SITTING AREAS around the tank: four arcs of sofas on the saucer, facing the glass.
	for k in range(4):
		var ka: float = TAU * float(k) / 4.0 + PI * 0.25
		var kc := Vector3(TANK_C.x + cos(ka) * 9.3, 0, TANK_C.y + sin(ka) * 9.3)
		var face: float = rad_to_deg(atan2(TANK_C.x - kc.x, TANK_C.y - kc.z))
		_sofa(b, Vector3(kc.x, MAIN_Y + 0.62, kc.z), face, 3.0)
		var ta := Vector3(TANK_C.x + cos(ka) * 7.6, 0, TANK_C.y + sin(ka) * 7.6)
		_low_table(b, Vector3(ta.x, MAIN_Y + 0.62, ta.z), 1.2)
		var pa := Vector3(TANK_C.x + cos(ka + 0.35) * 10.4, 0, TANK_C.y + sin(ka + 0.35) * 10.4)
		b.cyl(Vector3(pa.x, MAIN_Y + 0.95, pa.z), 0.45, 0.7, MatLib.flat(Color(0.30, 0.30, 0.32)), "detail", Vector3.ZERO, -1.0, 10, true)
		b.cyl(Vector3(pa.x, MAIN_Y + 1.75, pa.z), 0.75, 0.9, MatLib.flat(Color(0.18, 0.34, 0.24)), "detail", Vector3.ZERO, 0.25, 10)
	# THE GALLERIES: rings held back to GAL_IN so the void stays open, plus finished soffits.
	var ring_specs: Array = [[G1, GAL_IN + 0.8], [G2, GAL_IN], [G3, GAL_IN], [G4, GAL_IN + 0.8]]
	for spec in ring_specs:
		var y: float = spec[0]
		var r_in: float = spec[1]
		KIT.ring_deck(b, Vector3(c.x, y, c.z), r_in, GAL_OUT, 0.3, MatLib.dirty_white_panel(), 32)
		KIT.led_ring(b, Vector3(c.x, y - 0.36, c.z), r_in + 0.24, COVE, 32, 0.1, COVE_E)
		KIT.led_ring(b, Vector3(c.x, y - 0.36, c.z), GAL_OUT - 0.35, COVE, 32, 0.1, COVE_E)
		KIT.ring_deck(b, Vector3(c.x, y - 0.44, c.z), r_in + 0.1, GAL_OUT - 0.1, 0.12,
			MatLib.dirty_white_panel(), 32)
	# Inner-edge rails, with ARC GAPS where the chord stairs and spurs arrive/depart — a
	# full circle of balustrade at every level is a fence across every one of them.
	_gapped_rail(b, c, GAL_IN + 0.8 + 0.14, G1, [[234.0, 258.0], [279.0, 304.0]])
	_gapped_rail(b, c, GAL_IN + 0.14, G2, [[329.0, 353.0], [354.0, 19.0], [263.0, 277.0]])
	_gapped_rail(b, c, GAL_IN + 0.14, G3, [[44.0, 68.0], [99.0, 124.0]])
	_gapped_rail(b, c, GAL_IN + 0.8 + 0.14, G4, [[149.0, 173.0], [83.0, 97.0]])
	# THE CHORD STAIRS: floor -> G1 -> G2 -> G3 -> G4, each spanning the void from deck
	# edge to deck edge, hanging beside the tank.
	_chord_stair(b, c, MAIN_Y, G1, 190.0, 250.0, 11.3, GAL_IN + 1.1)
	_chord_stair(b, c, G1, G2, 285.0, 345.0, GAL_IN + 1.1, GAL_IN + 0.3)
	_chord_stair(b, c, G2, G3, 0.0, 60.0, GAL_IN + 0.3, GAL_IN + 0.3)
	_chord_stair(b, c, G3, G4, 105.0, 165.0, GAL_IN + 0.3, GAL_IN + 1.1)
	# THE VIEWING SPURS at G2 (south) and G4 (north), reaching across to the glass.
	for spur in [[G2, deg_to_rad(270.0), GAL_IN], [G4, deg_to_rad(90.0), GAL_IN + 0.8]]:
		var sy: float = spur[0]
		var sa: float = spur[1]
		var rin2: float = spur[2]
		KIT.catwalk(b, Vector3(c.x + cos(sa) * (rin2 + 0.3), sy, c.z + sin(sa) * (rin2 + 0.3)),
			Vector3(TANK_C.x + cos(sa) * (SPUR_IN + 1.2), sy, TANK_C.y + sin(sa) * (SPUR_IN + 1.2)), 2.6, true,
			-1000.0, MatLib.dirty_white_panel(), MatLib.galvanized())
		KIT.ring_deck(b, Vector3(TANK_C.x, sy, TANK_C.y), SPUR_IN - 0.6, SPUR_IN + 1.6, 0.3,
			MatLib.dirty_white_panel(), 32, sa - SPUR_HALF, sa + SPUR_HALF)
		KIT.ring_rail(b, Vector3(TANK_C.x, sy, TANK_C.y), SPUR_IN + 1.5, 32, true, sa - SPUR_HALF, sa + SPUR_HALF)
		KIT.led_ring(b, Vector3(TANK_C.x, sy - 0.36, TANK_C.y), SPUR_IN + 1.5, COVE, 32, 0.1, COVE_E)
	# CHANDELIERS — pulled in to r 7.4..8.6 so they hang in the open well, not through the
	# gallery slabs they used to intersect at r 12.4.
	for i6 in range(7):
		var a6: float = TAU * float(i6) / 7.0 + 0.4
		var rr2: float = 7.4 + fmod(float(i6) * 0.53, 1.0) * 1.2
		var hy: float = ATRIUM_ROOF - 2.6 - fmod(float(i6) * 3.7, 9.0)
		var p3 := Vector3(c.x + cos(a6) * rr2, hy, c.z + sin(a6) * rr2)
		b.member(p3, Vector3(p3.x, ATRIUM_ROOF + 0.4, p3.z), 0.045, MatLib.dark_metal(), "detail")
		for k2 in range(6):
			var t: float = TAU * float(k2) / 6.0 + float(i6)
			var arm := Vector3(cos(t) * 1.2, sin(t * 1.7) * 0.8, sin(t) * 1.2)
			KIT.led_cove(b, p3 - arm, p3 + arm * 0.62, Color(0.88, 0.96, 1.0), 0.075, 4.2)
	# Publish the tank.
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.92, 0.95)
	l.light_energy = 2.4
	l.omni_range = 26.0
	l.shadow_enabled = false
	l.add_to_group("aquarium_lights")
	l.add_to_group("rig_field_floods")
	host.add_child(l)
	l.position = b.to_world(Vector3(TANK_C.x, TANK_Y1 - 1.5, TANK_C.y))
	var marker := Node3D.new()
	marker.name = "AquariumVolume"
	marker.add_to_group("aquarium")
	host.add_child(marker)
	marker.position = b.to_world(Vector3(TANK_C.x, (TANK_Y0 + TANK_Y1) * 0.5, TANK_C.y))
	marker.set_meta("shape", "cylinder")
	marker.set_meta("radius", TANK_R - 0.15)
	marker.set_meta("height", TANK_Y1 - TANK_Y0 - 0.3)
	marker.set_meta("water_size", Vector3((TANK_R - 0.15) * 2.0, TANK_Y1 - TANK_Y0 - 0.3, (TANK_R - 0.15) * 2.0))
	marker.set_meta("circuit", "anchorage_aquarium")
	marker.set_meta("rig", "anchorage")

## Which drum bays are open portals at which level. Bays are indexed by rib: bay i spans
## angles i*30 .. (i+1)*30 degrees. East pair 11/0, north 2/3, west 5/6, south 8/9.
static func _is_portal(lvl: float, bay: int) -> bool:
	if absf(lvl - MAIN_Y) < 0.01:
		return bay in [0, 2, 3, 5, 6, 8, 9, 11]
	if absf(lvl - G1) < 0.01:
		return bay in [0, 11]
	return false

## One chord stair across the atrium void: foot on the lower deck's inner edge, head on the
## upper deck's inner edge, the flight hanging over the well between them.
static func _chord_stair(b: KIT.Bake, c: Vector3, y0: float, y1: float,
		a0_deg: float, a1_deg: float, r0: float, r1: float) -> void:
	var a0: float = deg_to_rad(a0_deg)
	var a1: float = deg_to_rad(a1_deg)
	KIT.stair(b, Vector3(c.x + cos(a0) * r0, y0, c.z + sin(a0) * r0),
		Vector3(c.x + cos(a1) * r1, y1, c.z + sin(a1) * r1), 1.7, true, true)

## Inner-edge gallery rail with arc gaps (degrees, [from, to], wrap-aware).
static func _gapped_rail(b: KIT.Bake, c: Vector3, radius: float, y: float, gaps: Array) -> void:
	var segs: int = 48
	var run_start: int = -1
	for i in range(segs + 1):
		var skip: bool = true
		if i < segs:
			var mid: float = fmod((float(i) + 0.5) * 360.0 / float(segs), 360.0)
			skip = false
			for g in gaps:
				var g0: float = fmod(g[0] + 360.0, 360.0)
				var g1: float = fmod(g[1] + 360.0, 360.0)
				if g0 <= g1:
					if mid >= g0 and mid <= g1:
						skip = true
				else:
					if mid >= g0 or mid <= g1:
						skip = true
		if not skip and run_start < 0:
			run_start = i
		elif skip and run_start >= 0:
			KIT.ring_rail(b, Vector3(c.x, y, c.z), radius, segs, true,
				TAU * float(run_start) / float(segs), TAU * float(i) / float(segs))
			run_start = -1

# ----------------------------------------------------------------------------- TERRACE

static func _terrace(b: KIT.Bake) -> void:
	# Perimeter rail, with gaps for the west rim stair and the helideck link.
	KIT.rail_rect(b, PODIUM, TERRACE, [["w", -8.0, -4.0]], 0.25)
	# Rail around the drum's square light-well.
	KIT.rail_rect(b, Rect2(-16.4, -12.4, 32.8, 32.8), TERRACE, [], -0.1)
	# Rails around the interior stair opening (x 26..37, z 18..22).
	KIT.rail_run(b, Vector2(26.4, 18.1), Vector2(37.0, 18.1), TERRACE)
	KIT.rail_run(b, Vector2(37.0, 18.1), Vector2(37.0, 21.9), TERRACE)
	# EXTERIOR STAIR up the west rim: main deck to terrace.
	KIT.stair(b, Vector3(-41.0, MAIN_Y, -16.0), Vector3(-41.0, TERRACE, -6.0), 1.5, true, true)
	KIT.catwalk(b, Vector3(-41.0, TERRACE, -6.0), Vector3(-38.6, TERRACE, -6.0), 1.8, false)
	# INTERIOR STAIR from the back corridor to the terrace (well cut through the roof).
	KIT.stair(b, Vector3(36.0, MAIN_Y, 20.6), Vector3(27.0, TERRACE, 20.6), 1.8, true, true)
	KIT.deck(b, Rect2(26.0, 18.4, 1.2, 3.4), TERRACE, 0.3, MatLib.deck_plate())
	# Terrace furniture: loungers and parasols along the south edge, planters at the drum.
	for i in range(4):
		var x: float = -30.0 + i * 8.0
		b.box(Vector3(x, TERRACE + 0.28, -22.0), Vector3(1.9, 0.35, 0.8), MatLib.canvas(Color(0.72, 0.70, 0.62)), "detail", Vector3(0, 0, deg_to_rad(6.0)), true)
		b.cyl(Vector3(x + 1.4, TERRACE + 1.5, -21.0), 0.06, 3.0, MatLib.galvanized(), "detail")
		b.cyl(Vector3(x + 1.4, TERRACE + 3.1, -21.0), 1.7, 0.35, MatLib.canvas(Color(0.75, 0.72, 0.62)), "detail", Vector3.ZERO, 0.2, 10)
	for a in [30.0, 150.0, 210.0, 330.0]:
		var r: float = deg_to_rad(a)
		var p := Vector3(DRUM_C.x + cos(r) * 18.6, TERRACE, DRUM_C.y + sin(r) * 18.6)
		b.cyl(p + Vector3(0, 0.5, 0), 0.55, 1.0, MatLib.flat(Color(0.30, 0.30, 0.32)), "detail", Vector3.ZERO, -1.0, 10, true)
		b.cyl(p + Vector3(0, 1.6, 0), 0.95, 1.4, MatLib.flat(Color(0.18, 0.34, 0.24)), "detail", Vector3.ZERO, 0.3, 10)
	KIT.led_cove(b, Vector3(PODIUM.position.x + 0.5, TERRACE + 0.85, PODIUM.position.y + 0.5),
		Vector3(PODIUM.end.x - 0.5, TERRACE + 0.85, PODIUM.position.y + 0.5), COVE, 0.09, COVE_E)
	KIT.led_cove(b, Vector3(PODIUM.position.x + 0.5, TERRACE + 0.85, PODIUM.end.y - 0.5),
		Vector3(PODIUM.end.x - 0.5, TERRACE + 0.85, PODIUM.end.y - 0.5), COVE, 0.09, COVE_E)

# ------------------------------------------------------------------------------ TOWERS

static func _towers(b: KIT.Bake) -> void:
	var white: Material = MatLib.dirty_white_panel()
	var frost: Color = Color(0.60, 0.74, 0.78)
	# WEST TOWER: three storeys off the terrace.
	KIT.block(b, WEST_WING, TERRACE, 3, STOREY, white, {
		"windows": true, "glass_tint": frost,
		"doors": [["e", 4.0, 0], ["n", -29.0, 0]],
		"roof_deck": true,
		"roof_gaps": [],
	})
	for k in range(2):
		var y: float = TERRACE + STOREY * (k + 1)
		var bal := Rect2(WEST_WING.position.x - 2.4, WEST_WING.position.y + 2.0, 2.4, WEST_WING.size.y - 4.0)
		KIT.deck(b, bal, y + 0.02, 0.22, MatLib.checker_plate())
		KIT.rail_rect(b, bal, y + 0.02, [["e", bal.position.y, bal.end.y]], 0.1)
		KIT.led_cove(b, Vector3(bal.get_center().x, y - 0.32, bal.position.y),
			Vector3(bal.get_center().x, y - 0.32, bal.end.y), WARM, 0.09, WARM_E)
	KIT.lookout(b, Rect2(WEST_WING.get_center().x - 4.0, WEST_WING.position.y + 2.0, 8.0, 7.0),
		W_ROOF, 3.2, {"door": "n"})
	# EAST TOWER: two storeys off the dining roof.
	KIT.block(b, EAST_WING, DINE_ROOF, 2, STOREY, white, {
		"windows": true, "glass_tint": frost,
		"doors": [["w", 4.0, 0]],
		"roof_deck": true,
		"roof_gaps": [],
	})
	var bal2 := Rect2(EAST_WING.end.x, EAST_WING.position.y + 2.0, 2.4, EAST_WING.size.y - 4.0)
	KIT.deck(b, bal2, DINE_ROOF + STOREY + 0.02, 0.22, MatLib.checker_plate())
	KIT.rail_rect(b, bal2, DINE_ROOF + STOREY + 0.02, [["w", bal2.position.y, bal2.end.y]], 0.1)
	KIT.lookout(b, Rect2(EAST_WING.get_center().x - 4.0, EAST_WING.position.y + 2.0, 8.0, 7.0),
		E_ROOF, 3.2, {"door": "n"})
	# Mast and radome on the east tower roof.
	var mc: Vector2 = EAST_WING.get_center()
	KIT.lattice(b, mc.x + 7.0, mc.y + 9.0, E_ROOF, MAST_TOP, 1.8, 0.6, 5, 0.26, MatLib.galvanized(), "hull")
	b.cyl(Vector3(mc.x + 7.0, MAST_TOP + 1.2, mc.y + 9.0), 1.8, 2.4, white, "hull", Vector3.ZERO, 1.1, 14)
	for i in range(3):
		b.box(Vector3(mc.x + 7.0, E_ROOF + 4.0 + i * 3.4, mc.y + 9.0), Vector3(3.8, 0.12, 0.5),
			MatLib.galvanized(), "detail", Vector3(0, deg_to_rad(40.0 * i), 0))

static func _spa(b: KIT.Bake) -> void:
	KIT.block(b, SPA_BLOCK, MAIN_Y, 2, STOREY, MatLib.dirty_white_panel(), {
		"windows": true, "glass_tint": Color(0.56, 0.76, 0.80),
		"doors": [["s", 0.0, 0], ["n", 6.0, 0]],
		"roof_deck": true,
		"roof_gaps": [],
	})
	for i in range(2):
		var yy: float = MAIN_Y + STOREY * float(i + 1) - 0.5
		KIT.led_cove(b, Vector3(SPA_BLOCK.position.x + 1.0, yy, SPA_BLOCK.position.y + 1.5),
			Vector3(SPA_BLOCK.end.x - 1.0, yy, SPA_BLOCK.position.y + 1.5), WARM, 0.09, WARM_E)

static func _helideck(b: KIT.Bake) -> void:
	KIT.deck(b, HELI_BASE, MAIN_Y, 0.5, MatLib.checker_plate())
	KIT.rail_rect(b, HELI_BASE, MAIN_Y, [["w", -20.0, 4.0]], 0.2)
	var steel: Material = MatLib.rust_steel()
	for z in [-18.0, -11.0, -4.0, 2.0]:
		b.member(Vector3(HELI_BASE.end.x - 0.5, MAIN_Y - 0.5, z), Vector3(34.0, 16.6, z), 0.42, steel, "hull")
		b.member(Vector3(43.0, MAIN_Y - 0.5, z), Vector3(43.0, 20.4, z), 0.3, steel, "hull")
	KIT.helipad(b, HELI_C, HELI_R, MAIN_Y)
	# THE PAD TOWER. The helideck disc (r 13 from (48, -8)) overhangs its whole support deck,
	# so any straight flight to it climbs UNDERNEATH the pad — the old route was capped by
	# the disc for its entire second flight. A switchback tower beside the south rim tops out
	# at pad height OUTSIDE the disc, and a short apron crosses the rim onto the surface.
	KIT.stair_tower(b, Rect2(44.6, -26.0, 6.8, 4.4), MAIN_Y, HELI_Y, 2.67, true)
	KIT.catwalk(b, Vector3(48.2, HELI_Y, -21.5), Vector3(48.2, HELI_Y, -20.0), 1.6, false)
	for a in [25.0, 100.0, 190.0, 290.0]:
		var r: float = deg_to_rad(a)
		var p := Vector3(HELI_C.x + cos(r) * (HELI_R + 1.3), HELI_Y - 1.2, HELI_C.z + sin(r) * (HELI_R + 1.3))
		b.cyl(p, 0.13, 1.7, MatLib.galvanized(), "detail")
		KIT.lamp_lens(b, p + Vector3(0, 0.95, 0), Color(0.95, 0.92, 0.85), 0.34, 6.0)
	var wp := Vector3(HELI_C.x - HELI_R - 1.8, HELI_Y + 1.5, HELI_C.z + 9.0)
	b.cyl(wp, 0.1, 5.4, MatLib.galvanized(), "detail")
	b.cyl(wp + Vector3(-1.2, 2.5, 0), 0.45, 2.4, MatLib.flat(Color(0.75, 0.28, 0.12)), "detail",
		Vector3(0, 0, deg_to_rad(90.0)), 0.17, 10)

static func _marina(b: KIT.Bake) -> void:
	KIT.boat_landing(b, Vector3(0.0, 0.0, -34.0), 180.0, MAIN_Y, LOW_Y, 12.0, 6.0)
	KIT.catwalk(b, Vector3(0.0, LOW_Y, -31.0), Vector3(0.0, LOW_Y, -26.0), 2.4, true)
	KIT.catwalk(b, Vector3(0.0, LOW_Y, -26.0), Vector3(35.5, LOW_Y, -26.0), 2.0, true)
	KIT.catwalk(b, Vector3(35.5, LOW_Y, -26.0), Vector3(35.5, LOW_Y, -3.0), 2.0, true)
	var steel: Material = MatLib.rust_steel()
	for sgn in [-1.0, 1.0]:
		var x: float = sgn * 3.4
		b.member(Vector3(x, LOW_Y, -32.0), Vector3(x, LOW_Y + 5.0, -32.0), 0.28, steel, "detail")
		b.member(Vector3(x, LOW_Y + 5.0, -32.0), Vector3(x, LOW_Y + 5.6, -36.4), 0.26, steel, "detail")
		b.member(Vector3(x, LOW_Y + 5.6, -36.4), Vector3(x, LOW_Y + 2.8, -36.4), 0.05, MatLib.dark_metal(), "detail")
	b.box(Vector3(0.0, LOW_Y + 2.5, -36.4), Vector3(5.6, 0.3, 1.6), MatLib.weathered_wood(), "detail")
	for i in range(6):
		KIT.lamp_lens(b, Vector3(0.0 + i * 6.5, LOW_Y + 2.6, -26.0), WARM, 0.3, 4.5)

static func _lights(b: KIT.Bake, host: Node3D) -> void:
	# Drum exterior rings above the terrace (the stacked halos seen from the sea).
	for lvl in [G2, G3, G4]:
		KIT.led_ring(b, Vector3(DRUM_C.x, lvl - 0.95, DRUM_C.y), DRUM_R + 0.4, COVE, 36, 0.13, COVE_E)
	KIT.led_ring(b, Vector3(DRUM_C.x, ATRIUM_ROOF + 0.3, DRUM_C.y), DRUM_R + 0.55, COVE, 36, 0.15, 4.0)
	# Deck-edge cove and under-deck cove.
	var y: float = MAIN_Y + 0.9
	for run in [[Vector3(DECK.position.x + 0.5, y, DECK.position.y + 0.5), Vector3(DECK.end.x - 0.5, y, DECK.position.y + 0.5)],
			[Vector3(DECK.position.x + 0.5, y, DECK.end.y - 0.5), Vector3(DECK.end.x - 0.5, y, DECK.end.y - 0.5)],
			[Vector3(DECK.position.x + 0.5, y, DECK.position.y + 0.5), Vector3(DECK.position.x + 0.5, y, DECK.end.y - 0.5)],
			[Vector3(DECK.end.x - 0.5, y, DECK.position.y + 0.5), Vector3(DECK.end.x - 0.5, y, DECK.end.y - 0.5)]]:
		KIT.led_cove(b, run[0], run[1], COVE, 0.1, 2.8)
	for z in [DECK.position.y + 1.5, DECK.end.y - 1.5]:
		KIT.led_cove(b, Vector3(DECK.position.x + 2.0, MAIN_Y - 1.6, z), Vector3(DECK.end.x - 2.0, MAIN_Y - 1.6, z), COVE, 0.14, 2.2)
	# Tower facade cove.
	for spec in [[WEST_WING, TERRACE, 3], [EAST_WING, DINE_ROOF, 2]]:
		var wing: Rect2 = spec[0]
		var base_y: float = spec[1]
		for k in range(int(spec[2])):
			var wy: float = base_y + STOREY * k + 0.4
			KIT.led_cove(b, Vector3(wing.position.x + 0.3, wy, wing.position.y + 0.4),
				Vector3(wing.position.x + 0.3, wy, wing.end.y - 0.4), COVE, 0.1, WARM_E)
			KIT.led_cove(b, Vector3(wing.end.x - 0.3, wy, wing.position.y + 0.4),
				Vector3(wing.end.x - 0.3, wy, wing.end.y - 0.4), COVE, 0.1, WARM_E)
	var mc: Vector2 = EAST_WING.get_center()
	for my in [E_ROOF + 5.0, E_ROOF + 10.0, MAST_TOP - 1.0]:
		KIT.lamp_lens(b, Vector3(mc.x + 7.0, my, mc.y + 9.0), Color(0.95, 0.25, 0.18), 0.42, 6.0)
	# Deck floods.
	for p in [Vector3(-41.0, MAIN_Y, 26.0), Vector3(41.0, MAIN_Y, 26.0),
			Vector3(-41.0, MAIN_Y, -29.0), Vector3(41.0, MAIN_Y, -29.0)]:
		b.cyl(p + Vector3(0, 4.2, 0), 0.16, 8.4, MatLib.galvanized(), "detail")
		b.box(p + Vector3(0, 8.6, 0), Vector3(1.5, 0.5, 0.6), MatLib.dark_metal(), "detail")
		KIT.lamp_lens(b, p + Vector3(0, 8.35, 0), Color(0.92, 0.96, 1.0), 0.62, 5.5)
	var omni_pts: Array = [
		[Vector3(0.0, MAIN_Y + 3.0, 4.0), 2.6, 32.0],           # atrium floor
		[Vector3(-9.0, MAIN_Y + 3.0, 4.0), 2.0, 24.0],
		[Vector3(9.0, MAIN_Y + 3.0, 4.0), 2.0, 24.0],
		[Vector3(0.0, G2 + 1.4, 4.0), 2.2, 28.0],
		[Vector3(0.0, G4 + 1.8, 4.0), 2.2, 28.0],
		[Vector3(0.0, ATRIUM_ROOF - 1.5, 4.0), 2.4, 30.0],
		[Vector3(27.0, MAIN_Y + 4.5, 4.0), 2.2, 26.0],          # dining hall
		[Vector3(30.0, MAIN_Y + 3.0, -20.0), 1.8, 22.0],        # kitchen
		[Vector3(-20.0, MAIN_Y + 3.0, 0.0), 1.8, 24.0],         # west hall
		[Vector3(-6.0, MAIN_Y + 3.0, -20.0), 1.9, 24.0],        # vestibule/salon
		[Vector3(-32.0, MAIN_Y + 3.0, 4.0), 1.6, 22.0],         # suites (spill)
		[Vector3(0.0, TERRACE + 3.5, -18.0), 1.9, 26.0],        # terrace south
		[Vector3(-46.0, MAIN_Y + 3.5, 0.0), 1.7, 22.0],         # promenade
		[Vector3(HELI_C.x, HELI_Y - 1.8, HELI_C.z), 2.0, 26.0],
		[Vector3(0.0, SPA_Y + 2.6, 0.0), 1.8, 26.0],            # pool hall
		[Vector3(-20.0, SPA_Y + 2.6, 0.0), 1.5, 20.0],
		[Vector3(20.0, SPA_Y + 2.6, 0.0), 1.5, 20.0],
		[Vector3(-14.0, PLANT_Y + 3.0, 0.0), 1.6, 22.0],
		[Vector3(14.0, PLANT_Y + 3.0, -8.0), 1.6, 22.0],
		[Vector3(0.0, LOW_Y + 2.4, -32.0), 1.4, 18.0],
		[Vector3(0.0, MAIN_Y + 3.0, 26.0), 1.7, 22.0],          # spa ground
	]
	for p2 in omni_pts:
		var l := OmniLight3D.new()
		l.light_color = Color(0.86, 0.93, 1.0)
		l.light_energy = float(p2[1])
		l.omni_range = float(p2[2])
		l.shadow_enabled = false
		l.add_to_group("rig_field_floods")
		host.add_child(l)
		l.position = b.to_world(p2[0])
