class_name RigThree extends RefCounted
## RIG 3 — "THE ANCHORAGE" · residential / luxury. NO DRILLING.
##
## Where the captains and guests stayed, and by a long way the largest structure in the
## field: an 84 x 60 m main deck (rig 1's is 60 x 40) carried on six caissons, with two
## occupied decks BELOW it and a five-level superstructure above. It is a resort bolted to a
## jacket, and every level of it is walkable.
##
## HERO FEATURE — THE ATRIUM. A circular glazed drum 32 m across rising 18.5 m from the main
## deck to a glass roof, with a **column aquarium 10.8 m in diameter and 16.9 m tall standing
## dead centre**, running through every gallery. Four ring balconies wrap it: a tight collar
## at G1 that hugs the glass, then wider galleries at G2/G3/G4 reached by radial bridges. You
## meet the tank at the bottom looking up, at your own eye level from the collar, and from
## above at G4. That is the shot the room is built around.
##
## The vocabulary is deliberately the opposite of MARROW's: white curved panels, chrome, blue
## LED cove, teal glass, and light EVERYWHERE once the power is on — cove strips are geometry
## in the "lamp" group, not Light3D, so a hundred metres of them cost nothing per frame.
##
## LOCAL FRAME: origin on mean water at the platform centre, +Y up, +Z "north".
## Placed by rig_field.gd at world (58, 0, 262), bearing +10 deg.

## By path, not by class name: the global class cache lags a new file, and a rig that
## fails to parse is a rig that silently does not exist.
const KIT := preload("res://scripts/world/rig_kit.gd")

# ------------------------------------------------------------------- elevations (metres)

const SUB_TOP: float = 20.90       ## caisson tops, below the main slab's underside (20.9)
const LOW_Y: float = 2.20          ## marina deck / tender landing
const PLANT_Y: float = 8.80        ## lower machinery deck — open, under the hull
const SPA_Y: float = 15.40         ## leisure deck: pool, spa, the big windows
const MAIN_Y: float = 22.00        ## main deck: atrium floor, lobby, promenade
const MAIN_T: float = 1.10
const STOREY: float = 3.70         ## ONE module. Every gallery is a multiple of it.
const G1: float = 25.70            ## collar gallery — hugs the tank
const G2: float = 29.40
const G3: float = 33.10
const G4: float = 36.80            ## upper gallery / suites
const ATRIUM_ROOF: float = 40.50   ## the glass roof over the drum
const WING_ROOF: float = 36.80     ## accommodation wing roof decks
const MAST_TOP: float = 52.00      ## the ANCHORAGE's highest point
const HELI_Y: float = 30.00        ## helideck, 8 m clear over the deck it shelters

## THE COLUMN AQUARIUM, in one place, so nothing re-types it.
const TANK_C := Vector2(0.0, 4.0)
const TANK_R: float = 5.40         ## 10.8 m across
const TANK_Y0: float = 22.50
const TANK_Y1: float = 39.40       ## 16.9 m of water, through four galleries

# ---------------------------------------------------------------------- plan (metres)

const LEG_HALF: float = 2.80
const LEG_X: Array = [-28.0, 0.0, 28.0]
const LEG_Z: Array = [-22.0, 22.0]

const DECK := Rect2(-42.0, -30.0, 84.0, 60.0)     ## 84 x 60 — the biggest deck in the field
const LOWER := Rect2(-34.0, -24.0, 68.0, 48.0)    ## plant deck and leisure deck footprint
const STAIRWELL := Rect2(30.0, -6.0, 8.0, 9.0)    ## LOW_Y -> MAIN_Y, six flights of 3.30
const CORE := Rect2(17.0, 8.0, 8.0, 9.0)          ## MAIN_Y -> ATRIUM_ROOF, five of 3.70

## The atrium drum, and the blocks that hang off it.
const DRUM_C := Vector2(0.0, 4.0)
const DRUM_R: float = 16.00                       ## 32 m across
const GAL_OUT: float = 15.60
## THE VOID STAYS OPEN. The first build wrapped a solid 3.5 m collar round the tank at G1,
## only 3.7 m over the atrium floor — and the render showed exactly what that does: from the
## floor the collar IS a ceiling, and a 16.9 m column of water read as a 3 m drum. Every
## gallery now stops at GAL_IN, leaving a clear cylinder of air 22 m across around the tank
## all the way to the glass roof, and the close-up moment is delivered by two VIEWING SPURS
## that reach in across the void instead of by a ring that fills it.
const GAL_IN: float = 11.00
const SPUR_IN: float = 6.30
const SPUR_HALF: float = 0.62      ## half-angle of the spur's viewing platform, radians

const WEST_WING := Rect2(-40.0, -10.0, 22.0, 28.0)
const EAST_WING := Rect2(18.0, -10.0, 22.0, 28.0)
const LOBBY := Rect2(-14.0, -28.0, 28.0, 12.0)    ## arrival hall, where the bridge lands
const SPA_BLOCK := Rect2(-14.0, 19.0, 28.0, 10.0) ## pool hall / spa, north end

const PROMENADE := Rect2(-50.0, -14.0, 8.0, 28.0) ## cantilevered west, over open water
const HELI_BASE := Rect2(42.0, -20.0, 10.0, 24.0)
const HELI_C := Vector3(48.0, HELI_Y, -8.0)
const HELI_R: float = 13.00                       ## 26 m across the flats

const BRIDGE_IN := Vector3(-10.0, MAIN_Y, -30.0)  ## from MARROW
const BRIDGE_OUT := Vector3(8.0, MAIN_Y, 30.0)    ## to DEEPWELL

## The one palette decision that separates this rig from the other three.
## The atrium's own surfaces. A rusted grating walkway inside a white drum was the loudest
## wrong note in the first render of this room; every deck and beam in here is named here.
const ATRIUM_DECK_TINT := Color(0.86, 0.88, 0.90)
const COVE := Color(0.42, 0.78, 1.00)
const COVE_WARM := Color(1.00, 0.88, 0.72)

static func build(b: KIT.Bake, host: Node3D) -> Dictionary:
	_substructure(b)
	_plant_deck(b)
	_leisure_deck(b)
	_main_deck(b)
	_atrium(b, host)
	_wings(b)
	_lobby_and_spa(b)
	_helideck(b)
	_marina(b)
	_lights(b, host)
	return {
		"name": "THE ANCHORAGE",
		"bridge_in": BRIDGE_IN,
		"bridge_out": BRIDGE_OUT,
		"deck_y": MAIN_Y,
		"spawn": Vector3(-4.0, MAIN_Y, -24.0),   ## in the arrival hall, clear of its stair
		"overview": Vector3(29.0, WING_ROOF, 4.0),
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

# ------------------------------------------------------------------------ substructure

static func _substructure(b: KIT.Bake) -> void:
	for x in LEG_X:
		for z in LEG_Z:
			KIT.caisson(b, x, z, LEG_HALF, SUB_TOP)
	for z in LEG_Z:
		KIT.pontoon(b, Vector3(0.0, -1.05, z), Vector3(70.0, 4.0, 9.0))
	KIT.pontoon(b, Vector3(0.0, -1.05, 0.0), Vector3(9.0, 4.0, 40.0))
	var steel: Material = MatLib.rust_steel()
	# Three tiers of bracing between the legs. THE ANCHORAGE is tall and it has to look
	# carried, not balanced.
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
	# Deck girder grid under the main slab.
	for z in [-22.0, 0.0, 22.0]:
		b.box(Vector3(0.0, 20.0, z), Vector3(78.0, 1.5, 1.4), steel, "hull")
	for x in LEG_X:
		b.box(Vector3(x, 20.0, 0.0), Vector3(1.4, 1.5, 54.0), steel, "hull")
	# The stair core from the marina to the main deck: six flights of 3.30, so its landings
	# fall EXACTLY on the plant deck (8.8) and the leisure deck (15.4). Nothing is re-typed.
	KIT.stair_tower(b, STAIRWELL, LOW_Y, MAIN_Y, 3.30, true)

static func _plant_deck(b: KIT.Bake) -> void:
	# THE PLANT DECK, y 8.8. Open to the sea on all sides (railed), decked in grating, and
	# packed: this is where the rig's water, power and air came from, and it is the level
	# that stops the ANCHORAGE reading as a table with a hotel on it.
	KIT.deck(b, LOWER, PLANT_Y, 0.32, MatLib.grating())
	KIT.rail_rect(b, LOWER, PLANT_Y, [["e", -6.0, 3.0], ["w", -6.0, 6.0]], 0.3)
	# Three generator sets on plinths, with exhaust risers going up past the deck above.
	for i in range(3):
		var x: float = -26.0 + i * 9.0
		KIT.skid(b, Vector3(x, PLANT_Y, -16.0), Vector3(7.0, 3.2, 4.4), 0.0)
		b.cyl(Vector3(x + 2.6, PLANT_Y + 6.4, -16.0), 0.55, 12.0, MatLib.dark_metal(), "hull")
		b.cyl(Vector3(x + 2.6, PLANT_Y + 12.8, -16.0), 0.7, 0.8, MatLib.rust_steel(), "detail")
	# Water treatment: vertical vessels, an exchanger bank, horizontal surge drums.
	KIT.vessel(b, Vector3(-28.0, PLANT_Y, 2.0), 2.1, 7.4, true)
	KIT.vessel(b, Vector3(-21.0, PLANT_Y, 2.0), 2.1, 7.4, true)
	KIT.exchanger_bank(b, Vector3(-13.0, PLANT_Y, 2.0), 3, 8.0, 0.0)
	KIT.vessel(b, Vector3(6.0, PLANT_Y, 6.0), 2.6, 8.6, true)
	for i in range(2):
		KIT.vessel(b, Vector3(16.0 + i * 9.0, PLANT_Y, 16.0), 1.7, 11.0, false, 0.0)
	KIT.manifold(b, Vector3(-2.0, PLANT_Y, -21.0), 9.0, 3.6, 0.0)
	KIT.manifold(b, Vector3(24.0, PLANT_Y, -21.0), 7.0, 3.6, 0.0)
	# Pipe galleries and cable trays the length of the deck, under the main slab.
	for z in [-8.0, 10.0]:
		KIT.pipe_rack(b, Vector3(-32.0, PLANT_Y + 4.6, z), Vector3(32.0, PLANT_Y + 4.6, z), 6, 3.4)
	KIT.cable_tray(b, Vector3(-32.0, PLANT_Y + 5.8, -4.0), Vector3(32.0, PLANT_Y + 5.8, -4.0))
	KIT.cable_tray(b, Vector3(-32.0, PLANT_Y + 5.8, 14.0), Vector3(32.0, PLANT_Y + 5.8, 14.0))
	# An overhead route through the machinery.
	for z2 in [-12.0, 8.0]:
		KIT.catwalk(b, Vector3(-30.0, PLANT_Y + 3.4, z2), Vector3(30.0, PLANT_Y + 3.4, z2), 1.6, true, PLANT_Y)
	KIT.catwalk(b, Vector3(-30.0, PLANT_Y + 3.4, -12.0), Vector3(-30.0, PLANT_Y + 3.4, 8.0), 1.6, true, PLANT_Y)
	KIT.stair(b, Vector3(26.0, PLANT_Y, -12.0), Vector3(26.0, PLANT_Y + 3.4, -6.0), 1.6, true, true)
	for i in range(8):
		KIT.lamp_lens(b, Vector3(-28.0 + i * 8.0, PLANT_Y + 5.2, -4.0), Color(1.0, 0.93, 0.80), 0.4, 4.5)
		KIT.lamp_lens(b, Vector3(-28.0 + i * 8.0, PLANT_Y + 5.2, 14.0), Color(1.0, 0.93, 0.80), 0.4, 4.5)

static func _leisure_deck(b: KIT.Bake) -> void:
	# THE LEISURE DECK, y 15.4 — enclosed, warm, and the one place on the field with a
	# swimming pool. The deck the third reference image is about.
	var head: float = MAIN_Y - SPA_Y - 1.4      # clear room height under the main slab
	var shell: Material = MatLib.dirty_white_panel()
	var pane: Material = MatLib.glass(Color(0.60, 0.76, 0.82))
	var pool := Rect2(-11.0, -8.0, 22.0, 16.0)
	KIT.deck_hole(b, LOWER, pool, SPA_Y, 0.5, MatLib.lino_floor())
	for side in ["s", "n", "w", "e"]:
		KIT._wall_band(b, LOWER, side, SPA_Y, 0.0, 1.05, 0.3, shell)
		KIT._wall_band(b, LOWER, side, SPA_Y, 1.05, head - 0.6, 0.12, pane)
		KIT._wall_band(b, LOWER, side, SPA_Y, head - 0.6, head, 0.3, shell)
	# THE POOL: a sunken tank in the middle of the deck.
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
	KIT.led_cove(b, Vector3(pool.position.x, SPA_Y - 1.95, pool.position.y), Vector3(pool.end.x, SPA_Y - 1.95, pool.position.y), COVE)
	KIT.led_cove(b, Vector3(pool.position.x, SPA_Y - 1.95, pool.end.y), Vector3(pool.end.x, SPA_Y - 1.95, pool.end.y), COVE)
	KIT.stair(b, Vector3(-8.0, SPA_Y - 2.15, -6.2), Vector3(-8.0, SPA_Y, -10.4), 2.2, false, false)
	# Spa cabins and a gym along the east end, as partitions with doorways between them.
	for i in range(4):
		var x2: float = 15.0 + i * 4.4
		b.box(Vector3(x2, SPA_Y + head * 0.5, -13.0), Vector3(0.22, head, 10.0), shell, "hull", Vector3.ZERO, true)
	b.box(Vector3(21.6, SPA_Y + head * 0.5, -8.0), Vector3(13.2, head, 0.22), shell, "hull", Vector3.ZERO, true)
	# Cove round the whole ceiling perimeter — this is where most of the "many lights" live.
	var cy: float = SPA_Y + head - 0.5
	for run in [[Vector3(LOWER.position.x + 0.8, cy, LOWER.position.y + 0.8), Vector3(LOWER.end.x - 0.8, cy, LOWER.position.y + 0.8)],
			[Vector3(LOWER.position.x + 0.8, cy, LOWER.end.y - 0.8), Vector3(LOWER.end.x - 0.8, cy, LOWER.end.y - 0.8)],
			[Vector3(LOWER.position.x + 0.8, cy, LOWER.position.y + 0.8), Vector3(LOWER.position.x + 0.8, cy, LOWER.end.y - 0.8)],
			[Vector3(LOWER.end.x - 0.8, cy, LOWER.position.y + 0.8), Vector3(LOWER.end.x - 0.8, cy, LOWER.end.y - 0.8)]]:
		KIT.led_cove(b, run[0], run[1], COVE_WARM, 0.11, 2.6)
	KIT.led_ring(b, Vector3(0.0, cy, 0.0), 13.0, COVE, 28, 0.1, 3.0)

static func _main_deck(b: KIT.Bake) -> void:
	KIT.deck_hole(b, DECK, STAIRWELL, MAIN_Y, MAIN_T)
	KIT.rail_rect(b, DECK, MAIN_Y, [
		["s", -15.0, -5.0],        # bridge from MARROW
		["n", 3.0, 13.0],          # bridge to DEEPWELL
		["w", -14.0, 14.0],        # onto the promenade
		["e", -20.0, 4.0],         # onto the helideck cantilever
	], 0.4)
	KIT.rail_rect(b, STAIRWELL, MAIN_Y, [["n", 31.0, 36.0]], -0.1)
	# THE PROMENADE, cantilevered 8 m west over open water.
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
		KIT.lamp_lens(b, Vector3(-44.2, MAIN_Y + 3.7, z2 + 3.0), COVE_WARM, 0.35, 5.0)
	b.box(Vector3(-10.0, MAIN_Y + 0.03, -25.0), Vector3(12.0, 0.06, 9.0), MatLib.weathered_wood(), "detail")

# --------------------------------------------------------------------------- THE ATRIUM

static func _atrium(b: KIT.Bake, host: Node3D) -> void:
	var c := Vector3(DRUM_C.x, 0.0, DRUM_C.y)
	var white: Material = MatLib.dirty_white_panel()
	var pane: Material = MatLib.glass(Color(0.62, 0.78, 0.84))
	var chrome: Material = MatLib.galvanized()
	# ---- THE DRUM SHELL: twelve curved ribs from deck to roof ring, glazed between.
	var ribs: int = 12
	for i in range(ribs):
		var a: float = TAU * float(i) / float(ribs)
		var p := Vector3(c.x + cos(a) * DRUM_R, 0, c.z + sin(a) * DRUM_R)
		b.box(Vector3(p.x, (MAIN_Y + ATRIUM_ROOF) * 0.5, p.z),
			Vector3(1.5, ATRIUM_ROOF - MAIN_Y + 1.0, 1.1), white, "hull", Vector3(0, -a, 0), true)
		b.box(Vector3(p.x, (MAIN_Y + ATRIUM_ROOF) * 0.5, p.z),
			Vector3(1.75, ATRIUM_ROOF - MAIN_Y, 0.22), chrome, "detail", Vector3(0, -a, 0))
	for lvl in [MAIN_Y, G1, G2, G3, G4]:
		var top: float = minf(lvl + STOREY, ATRIUM_ROOF)
		for i2 in range(ribs):
			var a0: float = TAU * (float(i2) + 0.09) / float(ribs)
			var a1: float = TAU * (float(i2) + 0.91) / float(ribs)
			var mid_a: float = (a0 + a1) * 0.5
			var seg: float = 2.0 * DRUM_R * sin((a1 - a0) * 0.5)
			var p2 := Vector3(c.x + cos(mid_a) * DRUM_R, 0, c.z + sin(mid_a) * DRUM_R)
			b.box(Vector3(p2.x, lvl + (top - lvl) * 0.5 + 0.35, p2.z),
				Vector3(0.14, maxf(top - lvl - 0.9, 0.4), seg), pane, "glass", Vector3(0, -mid_a, 0))
			b.collider(Vector3(p2.x, lvl + (top - lvl) * 0.5 + 0.35, p2.z),
				Vector3(0.24, maxf(top - lvl - 0.9, 0.4), seg), Vector3(0, -mid_a, 0))
			b.box(Vector3(p2.x, lvl - 0.42, p2.z), Vector3(0.44, 0.9, seg), white, "hull", Vector3(0, -mid_a, 0))
	# ---- THE GLASS ROOF: a shallow cone of radial panes on a ring beam.
	KIT.ring_deck(b, Vector3(c.x, ATRIUM_ROOF, c.z), DRUM_R - 1.0, DRUM_R + 0.8, 0.5, MatLib.deck_plate(), 24)
	for i3 in range(24):
		var a2: float = TAU * float(i3) / 24.0
		var a3: float = TAU * float(i3 + 1) / 24.0
		var mid2: float = (a2 + a3) * 0.5
		var rr: float = DRUM_R - 0.8
		b.box(Vector3(c.x + cos(mid2) * rr * 0.5, ATRIUM_ROOF + 1.5, c.z + sin(mid2) * rr * 0.5),
			Vector3(rr, 0.12, 2.0 * rr * 0.5 * sin(PI / 24.0) * 2.2 + 0.35), pane, "glass",
			Vector3(0, -mid2, deg_to_rad(-9.0)))
		b.member(Vector3(c.x + cos(mid2) * rr, ATRIUM_ROOF + 0.6, c.z + sin(mid2) * rr),
			Vector3(c.x, ATRIUM_ROOF + 2.7, c.z), 0.2, chrome, "hull")
	b.cyl(Vector3(c.x, ATRIUM_ROOF + 2.9, c.z), 2.2, 1.0, white, "hull", Vector3.ZERO, 1.4, 24)
	# ---- THE TANK, and the stepped saucer at its foot.
	KIT.column_tank(b, TANK_C, TANK_R, TANK_Y0, TANK_Y1, 40)
	b.cyl(Vector3(TANK_C.x, MAIN_Y + 0.16, TANK_C.y), 11.4, 0.32, MatLib.lino_floor(), "hull", Vector3.ZERO, -1.0, 32, true)
	KIT.ring_deck(b, Vector3(c.x, MAIN_Y + 0.04, c.z), 11.4, DRUM_R - 0.8, 0.16, MatLib.lino_floor(), 32)
	b.cyl(Vector3(TANK_C.x, MAIN_Y + 0.62, TANK_C.y), 8.6, 0.6, white, "hull", Vector3.ZERO, -1.0, 32, true)
	KIT.led_ring(b, Vector3(TANK_C.x, MAIN_Y + 0.36, TANK_C.y), 11.1, COVE, 32, 0.12, 3.6)
	KIT.led_ring(b, Vector3(TANK_C.x, MAIN_Y + 1.0, TANK_C.y), 8.8, COVE, 32, 0.1, 2.6)
	# ---- THE GALLERIES. Four rings, every one of them held back to GAL_IN so the tank is
	# never capped, plus two spurs that reach in to touch it.
	for spec in [[G1, GAL_IN + 0.8], [G2, GAL_IN], [G3, GAL_IN], [G4, GAL_IN + 0.8]]:
		var y: float = spec[0]
		var r_in: float = spec[1]
		KIT.ring_deck(b, Vector3(c.x, y, c.z), r_in, GAL_OUT, 0.3, MatLib.dirty_white_panel(), 32)
		KIT.ring_rail(b, Vector3(c.x, y, c.z), r_in + 0.14, 32)
		KIT.led_ring(b, Vector3(c.x, y - 0.36, c.z), r_in + 0.24, COVE, 32, 0.1, 3.2)
		KIT.led_ring(b, Vector3(c.x, y - 0.36, c.z), GAL_OUT - 0.35, COVE, 32, 0.1, 2.4)
		# Finished soffit: the underside of a gallery is a CEILING to whoever is below it.
		KIT.ring_deck(b, Vector3(c.x, y - 0.44, c.z), r_in + 0.1, GAL_OUT - 0.1, 0.12,
			MatLib.dirty_white_panel(), 32)
	# THE VIEWING SPURS: G2 from the south, G4 from the north, each a walkway out across the
	# void ending in a curved platform hard against the glass. This is where the player's eye
	# is at the tank's own middle, and it is the shot the whole room exists for.
	for spur in [[G2, deg_to_rad(270.0)], [G4, deg_to_rad(90.0)]]:
		var sy: float = spur[0]
		var sa: float = spur[1]
		KIT.catwalk(b, Vector3(c.x + cos(sa) * (GAL_IN + 0.3), sy, c.z + sin(sa) * (GAL_IN + 0.3)),
			Vector3(TANK_C.x + cos(sa) * (SPUR_IN + 1.2), sy, TANK_C.y + sin(sa) * (SPUR_IN + 1.2)), 2.6, true,
			-1000.0, MatLib.dirty_white_panel(), MatLib.galvanized())
		KIT.ring_deck(b, Vector3(TANK_C.x, sy, TANK_C.y), SPUR_IN - 0.6, SPUR_IN + 1.6, 0.3,
			MatLib.dirty_white_panel(), 32, sa - SPUR_HALF, sa + SPUR_HALF)
		KIT.ring_rail(b, Vector3(TANK_C.x, sy, TANK_C.y), SPUR_IN + 1.5, 32, true, sa - SPUR_HALF, sa + SPUR_HALF)
		KIT.led_ring(b, Vector3(TANK_C.x, sy - 0.36, TANK_C.y), SPUR_IN + 1.5, COVE, 32, 0.1, 3.4)
		KIT.led_ring(b, Vector3(TANK_C.x, sy - 0.36, TANK_C.y), SPUR_IN - 0.5, COVE, 32, 0.1, 3.4)
	# ---- The atrium stair core, and its landings into every gallery.
	KIT.stair_tower(b, CORE, MAIN_Y, ATRIUM_ROOF, STOREY, true)
	for y2 in [G1, G2, G3, G4]:
		KIT.catwalk(b, Vector3(CORE.position.x - 0.2, y2, CORE.get_center().y),
			Vector3(c.x + cos(deg_to_rad(24.0)) * (GAL_OUT - 0.4), y2, c.z + sin(deg_to_rad(24.0)) * (GAL_OUT - 0.4)), 2.2, true,
			-1000.0, MatLib.dirty_white_panel(), MatLib.galvanized())
	# A sweeping open stair curving round the tank from the atrium floor to the collar.
	for i5 in range(3):
		var s0: float = deg_to_rad(198.0 + i5 * 27.0)
		var s1: float = deg_to_rad(225.0 + i5 * 27.0)
		var r0: float = 10.6
		KIT.stair(b, Vector3(TANK_C.x + cos(s0) * r0, MAIN_Y + 0.32 + i5 * 1.13, TANK_C.y + sin(s0) * r0),
			Vector3(TANK_C.x + cos(s1) * r0, MAIN_Y + 1.45 + i5 * 1.13, TANK_C.y + sin(s1) * r0), 2.2, true, true)
	KIT.stair(b, Vector3(TANK_C.x + cos(deg_to_rad(279.0)) * 10.6, MAIN_Y + 3.71, TANK_C.y + sin(deg_to_rad(279.0)) * 10.6),
		Vector3(c.x + cos(deg_to_rad(310.0)) * (GAL_IN + 1.6), G1, c.z + sin(deg_to_rad(310.0)) * (GAL_IN + 1.6)), 2.2, true, true)
	# ---- THE CHANDELIERS: angular clusters of emissive tubes on a wire, in the void.
	for i6 in range(7):
		var a4: float = TAU * float(i6) / 7.0 + 0.4
		var rr2: float = 12.6 - fmod(float(i6) * 2.3, 3.0)
		var hy: float = ATRIUM_ROOF - 2.6 - fmod(float(i6) * 3.7, 9.0)
		var p3 := Vector3(c.x + cos(a4) * rr2, hy, c.z + sin(a4) * rr2)
		b.member(p3, Vector3(p3.x, ATRIUM_ROOF + 0.4, p3.z), 0.045, MatLib.dark_metal(), "detail")
		for k in range(6):
			var t: float = TAU * float(k) / 6.0 + float(i6)
			var arm := Vector3(cos(t) * 1.6, sin(t * 1.7) * 0.95, sin(t) * 1.6)
			KIT.led_cove(b, p3 - arm, p3 + arm * 0.62, Color(0.88, 0.96, 1.0), 0.075, 4.2)
	# ---- Publish the tank so the stocking pass binds to geometry, not to a copy of it.
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

# ------------------------------------------------------------------------------ the wings

static func _wings(b: KIT.Bake) -> void:
	var white: Material = MatLib.dirty_white_panel()
	var frost: Color = Color(0.60, 0.74, 0.78)
	for wing in [WEST_WING, EAST_WING]:
		var outward: bool = wing.position.x < 0.0
		KIT.block(b, wing, MAIN_Y, 4, STOREY, white, {
			"windows": true,
			"glass_tint": frost,
			"doors": [["n", wing.get_center().x, 0], ["s", wing.get_center().x, 0],
				["e" if outward else "w", 4.0, 0], ["e" if outward else "w", 4.0, 1],
				["e" if outward else "w", 4.0, 2], ["e" if outward else "w", 4.0, 3]],
			"roof_deck": true,
			"roof_gaps": [["n", wing.get_center().x - 3.0, wing.get_center().x + 3.0]],
		})
		# A balcony band on the outboard elevation at every guest level.
		for k in range(3):
			var y: float = MAIN_Y + STOREY * (k + 1)
			var bal := Rect2(wing.position.x - 2.4 if outward else wing.end.x,
				wing.position.y + 2.0, 2.4, wing.size.y - 4.0)
			KIT.deck(b, bal, y + 0.02, 0.22, MatLib.checker_plate())
			KIT.rail_rect(b, bal, y + 0.02, [["e" if outward else "w", bal.position.y, bal.end.y]], 0.1)
			KIT.led_cove(b, Vector3(bal.get_center().x, y - 0.32, bal.position.y),
				Vector3(bal.get_center().x, y - 0.32, bal.end.y), COVE_WARM, 0.09, 2.6)
			for zz in [bal.position.y + 1.0, bal.get_center().y, bal.end.y - 1.0]:
				b.member(Vector3(bal.get_center().x, y - 0.2, zz),
					Vector3(wing.get_center().x + (wing.size.x * 0.5 - 0.2) * (-1.0 if outward else 1.0), y - 2.3, zz),
					0.16, MatLib.rust_steel(), "detail")
		# Link bridges from the wing into the atrium drum at four levels.
		var link_x: float = wing.end.x if outward else wing.position.x
		var drum_x: float = -DRUM_R + 0.4 if outward else DRUM_R - 0.4
		for y2 in [MAIN_Y, G1, G2, G3]:
			KIT.catwalk(b, Vector3(link_x, y2, 4.0), Vector3(drum_x, y2, 4.0), 2.6, true, -1000.0,
				MatLib.dirty_white_panel(), MatLib.galvanized())
		# Roof: an observation deck with a glazed lookout cabin.
		var look := Rect2(wing.get_center().x - 4.0, wing.position.y + 2.0, 8.0, 7.0)
		KIT.lookout(b, look, WING_ROOF, 3.2)
		KIT.stair(b, Vector3(wing.get_center().x + 6.0, WING_ROOF, wing.end.y - 2.0),
			Vector3(wing.get_center().x + 6.0, WING_ROOF + 3.6, wing.end.y - 7.4), 1.6, true, true)
	# Comms mast and radome on the east wing roof.
	var mc: Vector2 = EAST_WING.get_center()
	KIT.lattice(b, mc.x + 7.0, mc.y + 9.0, WING_ROOF, MAST_TOP, 1.8, 0.6, 5, 0.26, MatLib.galvanized(), "hull")
	b.cyl(Vector3(mc.x + 7.0, MAST_TOP + 1.2, mc.y + 9.0), 1.8, 2.4, MatLib.dirty_white_panel(), "hull", Vector3.ZERO, 1.1, 14)
	for i in range(3):
		b.box(Vector3(mc.x + 7.0, WING_ROOF + 4.0 + i * 3.4, mc.y + 9.0), Vector3(3.8, 0.12, 0.5),
			MatLib.galvanized(), "detail", Vector3(0, deg_to_rad(40.0 * i), 0))

static func _lobby_and_spa(b: KIT.Bake) -> void:
	var white: Material = MatLib.dirty_white_panel()
	# THE ARRIVAL HALL, where the bridge from MARROW puts you: double height, glazed south
	# wall, opening straight through into the atrium.
	KIT.block(b, LOBBY, MAIN_Y, 2, STOREY, white, {
		"windows": true,
		"glass_tint": Color(0.58, 0.74, 0.80),
		"doors": [["s", -10.0, 0], ["n", 0.0, 0], ["n", 0.0, 1]],
		"roof_deck": true,
		"roof_gaps": [["n", -4.0, 4.0]],
	})
	KIT.catwalk(b, Vector3(0.0, MAIN_Y, LOBBY.end.y - 0.2), Vector3(0.0, MAIN_Y, -DRUM_R + 4.8), 4.0, false, -1000.0,
		MatLib.lino_floor(), MatLib.galvanized())
	KIT.led_cove(b, Vector3(LOBBY.position.x + 1.0, MAIN_Y + STOREY - 0.5, LOBBY.position.y + 0.6),
		Vector3(LOBBY.end.x - 1.0, MAIN_Y + STOREY - 0.5, LOBBY.position.y + 0.6), COVE)
	KIT.led_cove(b, Vector3(LOBBY.position.x + 1.0, MAIN_Y + STOREY * 2.0 - 0.5, LOBBY.position.y + 0.6),
		Vector3(LOBBY.end.x - 1.0, MAIN_Y + STOREY * 2.0 - 0.5, LOBBY.position.y + 0.6), COVE)
	KIT.stair(b, Vector3(-11.0, MAIN_Y, -26.4), Vector3(-11.0, MAIN_Y + STOREY, -20.6), 2.0, true, true)
	# THE POOL HALL / SPA at the north end.
	KIT.block(b, SPA_BLOCK, MAIN_Y, 2, STOREY, white, {
		"windows": true,
		"glass_tint": Color(0.56, 0.76, 0.80),
		"doors": [["s", 0.0, 0], ["n", 6.0, 0]],
		"roof_deck": true,
		"roof_gaps": [["s", -4.0, 4.0]],
	})
	KIT.catwalk(b, Vector3(0.0, MAIN_Y, SPA_BLOCK.position.y + 0.2), Vector3(0.0, MAIN_Y, DRUM_R - 4.8), 4.0, false, -1000.0,
		MatLib.lino_floor(), MatLib.galvanized())
	for i in range(2):
		var yy: float = MAIN_Y + STOREY * float(i + 1) - 0.5
		KIT.led_cove(b, Vector3(SPA_BLOCK.position.x + 1.0, yy, SPA_BLOCK.position.y + 1.5),
			Vector3(SPA_BLOCK.end.x - 1.0, yy, SPA_BLOCK.position.y + 1.5), COVE_WARM)
		KIT.led_cove(b, Vector3(SPA_BLOCK.position.x + 1.0, yy, SPA_BLOCK.end.y - 1.5),
			Vector3(SPA_BLOCK.end.x - 1.0, yy, SPA_BLOCK.end.y - 1.5), COVE_WARM)

static func _helideck(b: KIT.Bake) -> void:
	KIT.deck(b, HELI_BASE, MAIN_Y, 0.5, MatLib.checker_plate())
	KIT.rail_rect(b, HELI_BASE, MAIN_Y, [["w", -20.0, 4.0]], 0.2)
	var steel: Material = MatLib.rust_steel()
	for z in [-18.0, -11.0, -4.0, 2.0]:
		b.member(Vector3(HELI_BASE.end.x - 0.5, MAIN_Y - 0.5, z), Vector3(34.0, 16.6, z), 0.42, steel, "hull")
		b.member(Vector3(43.0, MAIN_Y - 0.5, z), Vector3(43.0, 20.4, z), 0.3, steel, "hull")
	KIT.helipad(b, HELI_C, HELI_R, MAIN_Y)
	KIT.stair(b, Vector3(45.0, MAIN_Y, -18.0), Vector3(45.0, 26.0, -12.0), 1.8, true, true)
	b.box(Vector3(46.2, 25.88, -12.0), Vector3(4.2, 0.24, 2.4), MatLib.grating(), "hull", Vector3.ZERO, true)
	KIT.stair(b, Vector3(47.4, 26.0, -12.0), Vector3(47.4, HELI_Y, -18.0), 1.8, true, true)
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
	KIT.catwalk(b, Vector3(0.0, LOW_Y, -26.0), Vector3(33.0, LOW_Y, -26.0), 2.0, true)
	KIT.catwalk(b, Vector3(33.0, LOW_Y, -26.0), Vector3(33.0, LOW_Y, -2.0), 2.0, true)
	var steel: Material = MatLib.rust_steel()
	for sgn in [-1.0, 1.0]:
		var x: float = sgn * 3.4
		b.member(Vector3(x, LOW_Y, -32.0), Vector3(x, LOW_Y + 5.0, -32.0), 0.28, steel, "detail")
		b.member(Vector3(x, LOW_Y + 5.0, -32.0), Vector3(x, LOW_Y + 5.6, -36.4), 0.26, steel, "detail")
		b.member(Vector3(x, LOW_Y + 5.6, -36.4), Vector3(x, LOW_Y + 2.8, -36.4), 0.05, MatLib.dark_metal(), "detail")
	b.box(Vector3(0.0, LOW_Y + 2.5, -36.4), Vector3(5.6, 0.3, 1.6), MatLib.weathered_wood(), "detail")
	for i in range(6):
		KIT.lamp_lens(b, Vector3(0.0 + i * 6.0, LOW_Y + 2.6, -26.0), COVE_WARM, 0.3, 4.5)

static func _lights(b: KIT.Bake, host: Node3D) -> void:
	# COVE FIRST, LIGHTS SECOND. Every strip below is geometry in the "lamp" group — no
	# per-frame cost, no shadow atlas — and it is what the rig LOOKS like from 165 m away.
	# Only the sixteen OmniLight3Ds after it actually illuminate anything, and none casts.
	var y: float = MAIN_Y + 0.9
	for run in [[Vector3(DECK.position.x + 0.5, y, DECK.position.y + 0.5), Vector3(DECK.end.x - 0.5, y, DECK.position.y + 0.5)],
			[Vector3(DECK.position.x + 0.5, y, DECK.end.y - 0.5), Vector3(DECK.end.x - 0.5, y, DECK.end.y - 0.5)],
			[Vector3(DECK.position.x + 0.5, y, DECK.position.y + 0.5), Vector3(DECK.position.x + 0.5, y, DECK.end.y - 0.5)],
			[Vector3(DECK.end.x - 0.5, y, DECK.position.y + 0.5), Vector3(DECK.end.x - 0.5, y, DECK.end.y - 0.5)]]:
		KIT.led_cove(b, run[0], run[1], COVE, 0.1, 2.8)
	# A cove line at every floor of the drum — from outside, stacked rings of light.
	for lvl in [MAIN_Y, G1, G2, G3, G4]:
		KIT.led_ring(b, Vector3(DRUM_C.x, lvl - 0.95, DRUM_C.y), DRUM_R + 0.4, COVE, 36, 0.13, 3.4)
	KIT.led_ring(b, Vector3(DRUM_C.x, ATRIUM_ROOF + 0.3, DRUM_C.y), DRUM_R + 0.55, COVE, 36, 0.15, 4.0)
	for z in [DECK.position.y + 1.5, DECK.end.y - 1.5]:
		KIT.led_cove(b, Vector3(DECK.position.x + 2.0, MAIN_Y - 1.6, z), Vector3(DECK.end.x - 2.0, MAIN_Y - 1.6, z), COVE, 0.14, 2.2)
	for wing in [WEST_WING, EAST_WING]:
		for k in range(4):
			var wy: float = MAIN_Y + STOREY * k + 0.4
			KIT.led_cove(b, Vector3(wing.position.x + 0.3, wy, wing.position.y + 0.4),
				Vector3(wing.position.x + 0.3, wy, wing.end.y - 0.4), COVE, 0.1, 2.6)
			KIT.led_cove(b, Vector3(wing.end.x - 0.3, wy, wing.position.y + 0.4),
				Vector3(wing.end.x - 0.3, wy, wing.end.y - 0.4), COVE, 0.1, 2.6)
	var mc: Vector2 = EAST_WING.get_center()
	for my in [WING_ROOF + 5.0, WING_ROOF + 10.0, MAST_TOP - 1.0]:
		KIT.lamp_lens(b, Vector3(mc.x + 7.0, my, mc.y + 9.0), Color(0.95, 0.25, 0.18), 0.42, 6.0)
	for p in [Vector3(-38.0, MAIN_Y, 26.0), Vector3(38.0, MAIN_Y, 26.0),
			Vector3(-38.0, MAIN_Y, -26.0), Vector3(38.0, MAIN_Y, -26.0), Vector3(0.0, MAIN_Y, -28.0)]:
		b.cyl(p + Vector3(0, 4.2, 0), 0.16, 8.4, MatLib.galvanized(), "detail")
		b.box(p + Vector3(0, 8.6, 0), Vector3(1.5, 0.5, 0.6), MatLib.dark_metal(), "detail")
		KIT.lamp_lens(b, p + Vector3(0, 8.35, 0), Color(0.92, 0.96, 1.0), 0.62, 5.5)
	var omni_pts: Array = [
		[Vector3(0.0, MAIN_Y + 3.0, 4.0), 2.6, 32.0],
		[Vector3(-9.0, MAIN_Y + 3.0, 4.0), 2.0, 24.0],
		[Vector3(9.0, MAIN_Y + 3.0, 4.0), 2.0, 24.0],
		[Vector3(0.0, G1 + 1.4, 4.0), 2.0, 26.0],
		[Vector3(0.0, G2 + 1.4, 4.0), 2.2, 28.0],
		[Vector3(0.0, G3 + 1.4, 4.0), 2.0, 26.0],
		[Vector3(0.0, G4 + 1.8, 4.0), 2.2, 28.0],
		[Vector3(0.0, ATRIUM_ROOF - 1.5, 4.0), 2.4, 30.0],
		[Vector3(-30.0, MAIN_Y + 4.0, 4.0), 1.8, 24.0],
		[Vector3(30.0, MAIN_Y + 4.0, 4.0), 1.8, 24.0],
		[Vector3(0.0, MAIN_Y + 3.0, -22.0), 1.9, 24.0],
		[Vector3(0.0, MAIN_Y + 3.0, 24.0), 1.9, 24.0],
		[Vector3(-46.0, MAIN_Y + 3.5, 0.0), 1.7, 22.0],
		[Vector3(HELI_C.x, HELI_Y - 1.8, HELI_C.z), 2.0, 26.0],
		[Vector3(0.0, SPA_Y + 2.6, 0.0), 1.8, 26.0],
		[Vector3(-20.0, SPA_Y + 2.6, 0.0), 1.5, 20.0],
		[Vector3(20.0, SPA_Y + 2.6, 0.0), 1.5, 20.0],
		[Vector3(-14.0, PLANT_Y + 3.0, 0.0), 1.6, 22.0],
		[Vector3(14.0, PLANT_Y + 3.0, -8.0), 1.6, 22.0],
		[Vector3(0.0, LOW_Y + 2.4, -32.0), 1.4, 18.0],
		[Vector3(29.0, WING_ROOF + 2.0, 4.0), 1.5, 20.0],
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
