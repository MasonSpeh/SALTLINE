class_name RigTwo extends RefCounted
## RIG 2 — "MARROW" · industrial / farming.
##
## The working platform: the one that kept the field alive. Broad and low, six caissons in a
## 3x2 grid instead of four in a square, so its silhouette is a long horizontal slab where
## rig 1 is a compact tower and rig 4 is a spire. Grimy, sodium-lit, heavy external pipework.
##
## HERO FEATURE — the rooftop ex-vegetable garden on the mess block, 26 x 18 m at y 21.2:
## raised beds, a collapsed polytunnel, a dead irrigation ring. This session builds the
## STRUCTURE and the bed footprints; the soil-tending state machine is the next pass, and the
## beds are laid out on a grid so it has something honest to bind to.
##
## EVERY ELEVATION IS A NAMED CONSTANT AND NOTHING RE-TYPES ONE. That rule exists because
## three of four kelp stands in s52 were found growing in mid air, all four hand-typed.
##
## LOCAL FRAME: origin on mean water at the platform centre, +Y up, +Z "north".
## Placed by rig_field.gd at world (-62, 0, 148), bearing -16 deg.

## By path, not by class name: the global class cache lags a new file, and a rig that
## fails to parse is a rig that silently does not exist.
const KIT := preload("res://scripts/world/rig_kit.gd")

# ------------------------------------------------------------------- elevations (metres)

const SUB_TOP: float = 12.90      ## caisson tops — BELOW the deck slab's underside (13.0)
const MAIN_Y: float = 14.00       ## main deck walking surface. Rig 1's is 18.0: MARROW sits low.
const MAIN_T: float = 1.00        ## main deck slab thickness -> slab occupies 13.0 .. 14.0
const LOW_Y: float = 3.20         ## pump-intake working deck, near the waterline
const CANTI_Y: float = 13.20      ## the pipe-rack cantilever — a deliberate HALF LEVEL
const BLOCK_H: float = 3.60       ## storey height, mess/accommodation block
const GARDEN_Y: float = 21.20     ## mess block roof = the garden. MAIN_Y + 2 * BLOCK_H
const PLANT_H: float = 7.20       ## the plant hall is one tall storey, not two short ones
const PLANT_ROOF: float = 21.20   ## deliberately EQUAL to GARDEN_Y — one continuous upper level
const HYDRO_H: float = 4.40
const HYDRO_ROOF: float = 18.40   ## the grow house roof sits between the two, breaking the line
const SILO_TOP: float = 24.00     ## three feed silos, 10 m of barrel on the deck
const GANTRY_Y: float = 24.20     ## walkway over the silo tops
const TOWER_TOP: float = 28.40    ## THE OVERVIEW — stair tower head, looking back down the field
const STACK_TIP: float = 36.00    ## vent stack: MARROW's highest fixed point

# ---------------------------------------------------------------------- plan (metres)

## Six caissons, 5.4 m square, in a 3 x 2 grid. Broad: 60 m between the outer leg axes
## against rig 1's 44.
const LEG_HALF: float = 2.70
const LEG_X: Array = [-30.0, 0.0, 30.0]
const LEG_Z: Array = [-18.0, 18.0]

## Main deck: 76 x 48. Rig 1's is 60 x 40.
const DECK := Rect2(-38.0, -24.0, 76.0, 48.0)
## Stair well down to the low deck, cut through the main slab.
const STAIRWELL := Rect2(22.6, -14.4, 7.8, 8.8)
## The switchback tower that fills it, from LOW_Y to MAIN_Y.
const TOWER_LOW := Rect2(23.0, -14.0, 7.0, 8.0)

const LOW_DECK := Rect2(20.0, -24.0, 18.0, 10.0)    ## pump intakes, waterline fishing
const CANTI := Rect2(-53.0, -19.0, 15.0, 10.0)      ## 15 m past the deck rim, 23 m past the legs

const MESS := Rect2(-30.0, 2.0, 26.0, 18.0)         ## 2 storeys -> the garden roof
const PLANT := Rect2(2.0, 4.0, 24.0, 15.0)          ## one 7.2 m hall: pumps, workshop, treatment
const HYDRO := Rect2(-24.0, -20.0, 20.0, 12.0)      ## hydroponics + seed store + cold vault

const SILO_X: float = 34.0
const SILO_R: float = 3.00
const SILO_Z: Array = [-14.0, -6.0, 2.0]

const TOWER_HI := Rect2(-37.0, -9.0, 10.0, 9.0)     ## main deck -> TOWER_TOP, 4 flights
const GARDEN_STAIR := Rect2(-37.0, 5.0, 7.0, 5.0)   ## main deck -> garden roof, 2 flights
const PLANT_STAIR := Rect2(10.0, 19.4, 7.0, 4.2)    ## main deck -> plant roof, 2 flights

## Where the bridges meet MARROW, on the deck walking surface at the rim.
const BRIDGE_IN := Vector3(-2.0, MAIN_Y, -24.0)     ## from SALTLINE-0
const BRIDGE_OUT := Vector3(38.0, MAIN_Y, 12.0)     ## to THE ANCHORAGE

## The garden: a 4 x 3 grid of raised beds on the mess roof.
const BED_COLS: int = 4
const BED_ROWS: int = 3
const BED := Vector2(5.0, 4.2)          ## bed footprint
const BED_GAP: Vector2 = Vector2(1.1, 1.4)
const BED_H: float = 0.55

static func build(b: KIT.Bake, host: Node3D) -> Dictionary:
	_substructure(b)
	_main_deck(b)
	_low_deck(b)
	_cantilever(b)
	_buildings(b)
	_garden(b)
	_silos(b)
	_tower(b)
	_machinery(b)
	_links(b)
	_lights(b, host)
	return {
		"name": "MARROW",
		"bridge_in": BRIDGE_IN,
		"bridge_out": BRIDGE_OUT,
		"deck_y": MAIN_Y,
		"spawn": Vector3(-2.0, MAIN_Y, -20.0),
		"overview": Vector3(-32.0, TOWER_TOP, -4.5),
		"fishing": [
			{"id": "marrow_intake", "at": Vector3(29.0, LOW_Y, -23.0), "water": "near"},
			{"id": "marrow_pipe_rack", "at": Vector3(-50.0, CANTI_Y, -14.0), "water": "open"},
			{"id": "marrow_north_rim", "at": Vector3(-16.0, MAIN_Y, 23.4), "water": "open"},
		],
	}

# ------------------------------------------------------------------------ substructure

static func _substructure(b: KIT.Bake) -> void:
	for x in LEG_X:
		for z in LEG_Z:
			KIT.caisson(b, x, z, LEG_HALF, SUB_TOP)
	# Two pontoon beams tying each row, riding just over the v2 swell (crests ~0.9).
	for z in LEG_Z:
		KIT.pontoon(b, Vector3(0.0, -1.05, z), Vector3(74.0, 4.0, 7.5))
	# Cross-brace between the two rows at the mid legs, under the deck — the diagonal you
	# see from a boat and from the bridge on the way in.
	var steel: Material = MatLib.rust_steel()
	for x in LEG_X:
		b.member(Vector3(x - LEG_HALF, 1.6, -18.0 + LEG_HALF), Vector3(x + LEG_HALF, 9.0, 18.0 - LEG_HALF), 0.55, steel, "hull")
		b.member(Vector3(x + LEG_HALF, 1.6, 18.0 - LEG_HALF), Vector3(x - LEG_HALF, 9.0, -18.0 + LEG_HALF), 0.55, steel, "hull")
	# Longitudinal girders under the slab, spanning leg to leg.
	for z in LEG_Z:
		b.box(Vector3(0.0, 12.1, z), Vector3(74.0, 1.6, 1.4), steel, "hull")
	for x in LEG_X:
		b.box(Vector3(x, 12.1, 0.0), Vector3(1.4, 1.6, 40.0), steel, "hull")

static func _main_deck(b: KIT.Bake) -> void:
	KIT.deck_hole(b, DECK, STAIRWELL, MAIN_Y, MAIN_T)
	# Perimeter railing. The gaps are the bridge landings, the crane slew arc, the
	# cantilever mouth and one deliberate open corner — rig 1 leaves its corners open on
	# purpose and MARROW keeps that grammar.
	KIT.rail_rect(b, DECK, MAIN_Y, [
		["s", -7.0, 3.0],          # bridge from SALTLINE-0
		["e", 7.0, 17.0],          # bridge to THE ANCHORAGE
		["w", -19.0, -9.0],        # mouth of the pipe-rack cantilever
		["s", 20.0, 38.0],         # over the low deck / stairwell head
		["n", 26.0, 38.0],         # crane slew arc, open to the sea
	], 0.35)
	# Stair-well guard: the hole is a fall hazard, so it gets its own rail with one gap
	# at the head of the flight.
	KIT.rail_rect(b, STAIRWELL, MAIN_Y, [["w", -14.4, -9.0]], -0.1)
	# Deck plating joints and tie-down pads — cheap, and they stop 76 x 48 m of plate
	# reading as one flat sheet.
	var pad: Material = MatLib.hazard_stripe()
	for i in range(9):
		b.box(Vector3(-34.0 + i * 8.5, MAIN_Y + 0.02, -22.4), Vector3(1.6, 0.05, 1.6), pad, "detail")
	for i in range(6):
		b.box(Vector3(36.4, MAIN_Y + 0.02, -20.0 + i * 8.0), Vector3(1.6, 0.05, 1.6), pad, "detail")

static func _low_deck(b: KIT.Bake) -> void:
	# The pump-intake deck, 3.2 m over mean water. This is MARROW's `water: near` fishing
	# spot and its boat access.
	KIT.deck(b, LOW_DECK, LOW_Y, 0.35, MatLib.grating())
	KIT.rail_rect(b, LOW_DECK, LOW_Y, [
		["s", 26.0, 33.0],        # the fishing gap, deliberately open to the water
		["n", 23.0, 30.0],        # stair head
	], 0.2)
	var steel: Material = MatLib.rust_steel()
	# Hangers back up to the main slab: this deck is slung, not stood on legs.
	for hx in [21.5, 27.0, 32.5, 37.0]:
		for hz in [-23.0, -15.0]:
			b.member(Vector3(hx, LOW_Y, hz), Vector3(hx, 13.0, hz), 0.22, steel, "hull")
	# The intakes themselves: four suction caissons dropping into the sea.
	for i in range(4):
		var x: float = 22.5 + i * 4.6
		b.cyl(Vector3(x, LOW_Y - 3.6, -21.0), 0.85, 7.6, MatLib.dark_metal(), "hull")
		b.cyl(Vector3(x, LOW_Y + 1.1, -21.0), 1.0, 2.2, MatLib.rust_steel(), "detail", Vector3.ZERO, 0.7)
		KIT.pipe_run(b, [Vector3(x, LOW_Y + 2.1, -21.0), Vector3(x, LOW_Y + 2.8, -18.5),
			Vector3(x, 12.4, -18.5), Vector3(x, 12.4, -14.0)], 0.3)
	KIT.boat_landing(b, Vector3(36.0, 0.0, -30.0), 0.0, LOW_Y, 1.4, 8.0, 4.0)
	KIT.ladder(b, Vector3(36.0, 1.4, -27.6), LOW_Y, 0.0)
	# Tower down the stair well, low deck to main deck: 3 flights of 3.6.
	KIT.stair_tower(b, TOWER_LOW, LOW_Y, MAIN_Y, 3.6, true)

static func _cantilever(b: KIT.Bake) -> void:
	# THE PIPE RACK. 15 m of deck cantilevered west past the rim, 23 m past the nearest leg,
	# at a half level below the main deck — the brief asks for irregular section and this is
	# the cheapest honest way to get it.
	KIT.deck(b, CANTI, CANTI_Y, 0.4, MatLib.grating())
	KIT.rail_rect(b, CANTI, CANTI_Y, [["e", -19.0, -9.0]], 0.2)
	var steel: Material = MatLib.rust_steel()
	# Cantilever brackets back to the deck edge and down to the west leg.
	for z in [-17.5, -14.0, -10.5]:
		b.member(Vector3(-52.0, CANTI_Y - 0.4, z), Vector3(-36.0, 11.0, z), 0.4, steel, "hull")
		b.member(Vector3(-38.0, CANTI_Y - 0.4, z), Vector3(-38.0, 12.6, z), 0.3, steel, "hull")
	b.member(Vector3(-52.0, 11.4, -14.0), Vector3(-31.5, 5.0, -16.0), 0.5, steel, "hull")
	# The rack itself, running the length of the cantilever and on into the plant hall.
	KIT.pipe_rack(b, Vector3(-51.0, CANTI_Y + 1.4, -14.0), Vector3(-6.0, MAIN_Y + 1.6, -14.0), 5, 3.2)
	# Three steps up from the cantilever to the main deck — an 0.8 m half level.
	KIT.stair(b, Vector3(-39.6, CANTI_Y, -14.0), Vector3(-36.4, MAIN_Y, -14.0), 2.4, true, true)

# ------------------------------------------------------------------------- superstructure

static func _buildings(b: KIT.Bake) -> void:
	var hull: Material = MatLib.corrugated_paint(Color(0.66, 0.62, 0.54))
	# 1. THE MESS BLOCK. Two storeys, walk-on roof — the roof IS the garden.
	#    L0 y14.0: mess with the long steel table, galley, cold vault, seed store.
	#    L1 y17.6: crew rooms, fertiliser & chemical store, water treatment.
	KIT.block(b, MESS, MAIN_Y, 2, BLOCK_H, hull, {
		"doors": [["e", 11.0, 0], ["e", 11.0, 1], ["s", -22.0, 0], ["n", -14.0, 0]],
		"roof_deck": true,
		"roof_gaps": [["e", 8.0, 13.0]],   # where the roof catwalk lands
		"glass_tint": Color(0.55, 0.66, 0.62),
	})
	# 2. THE PLANT HALL. One 7.2 m storey — pump hall, machine shop (bigger than rig 1's),
	#    water treatment. Big roller doors, no window band: this is a shed, not a home.
	KIT.block(b, PLANT, MAIN_Y, 1, PLANT_H, MatLib.corrugated(), {
		"windows": false,
		"doors": [["w", 11.0, 0], ["s", 8.0, 0], ["e", 11.0, 0]],
		"roof_deck": true,
		"roof_gaps": [["w", 8.0, 13.0], ["n", 12.0, 17.0]],
	})
	# The roller-door openings read as openings, so they get a lintel band and a track.
	for d in [[Vector2(2.0, 11.0), 90.0], [Vector2(8.0, 4.0), 0.0], [Vector2(26.0, 11.0), 90.0]]:
		var p: Vector2 = d[0]
		b.box(Vector3(p.x, MAIN_Y + KIT.DOOR_H + 0.25, p.y), Vector3(2.6, 0.5, 0.5),
			MatLib.hazard_stripe(), "detail", Vector3(0, deg_to_rad(float(d[1])), 0))
	# 3. THE HYDROPONICS BAY. Low, glazed, its roof a third level between the other two.
	KIT.block(b, HYDRO, MAIN_Y, 1, HYDRO_H, MatLib.dirty_white_panel(), {
		"doors": [["n", -14.0, 0], ["e", -14.0, 0]],
		"roof_deck": true,
		"glass_tint": Color(0.58, 0.70, 0.60),
	})
	# North-light glazing on the hydroponics roof — a sawtooth of glass, which is what makes
	# it read as a grow house from the bridge rather than another shed.
	for i in range(5):
		var z: float = -18.6 + i * 2.6
		b.box(Vector3(-14.0, HYDRO_ROOF + 0.55, z), Vector3(19.0, 1.4, 0.16),
			MatLib.glass(Color(0.6, 0.72, 0.64)), "glass", Vector3(deg_to_rad(28.0), 0, 0))
		b.box(Vector3(-14.0, HYDRO_ROOF + 0.2, z + 0.6), Vector3(19.0, 0.5, 0.14),
			MatLib.rust_steel(), "detail")

static func _garden(b: KIT.Bake) -> void:
	# THE ROOFTOP EX-VEGETABLE GARDEN — 26 x 18 m on the mess roof at y 21.2.
	#
	# Twelve raised beds on a 4 x 3 grid, a dead irrigation ring feeding them, and a
	# collapsed polytunnel over the two northern rows. The beds are laid out from constants
	# so the soil-tending pass can walk the same grid and bind state to each bed without a
	# second, drifting copy of these positions.
	var c: Vector2 = MESS.get_center()
	var span_x: float = BED_COLS * BED.x + (BED_COLS - 1) * BED_GAP.x
	var span_z: float = BED_ROWS * BED.y + (BED_ROWS - 1) * BED_GAP.y
	var x0: float = c.x - span_x * 0.5
	var z0: float = c.y - span_z * 0.5
	var timber: Material = MatLib.weathered_wood()
	var soil: Material = MatLib.flat(Color(0.19, 0.17, 0.13))
	for row in range(BED_ROWS):
		for col in range(BED_COLS):
			var bx: float = x0 + col * (BED.x + BED_GAP.x) + BED.x * 0.5
			var bz: float = z0 + row * (BED.y + BED_GAP.y) + BED.y * 0.5
			# Kerb: four planks on edge, so the bed reads as built rather than extruded.
			for s in [[Vector3(bx, GARDEN_Y + BED_H * 0.5, bz - BED.y * 0.5), Vector3(BED.x, BED_H, 0.14)],
					[Vector3(bx, GARDEN_Y + BED_H * 0.5, bz + BED.y * 0.5), Vector3(BED.x, BED_H, 0.14)],
					[Vector3(bx - BED.x * 0.5, GARDEN_Y + BED_H * 0.5, bz), Vector3(0.14, BED_H, BED.y)],
					[Vector3(bx + BED.x * 0.5, GARDEN_Y + BED_H * 0.5, bz), Vector3(0.14, BED_H, BED.y)]]:
				b.box(s[0], s[1], timber, "hull", Vector3.ZERO, true)
			# The soil itself, 8 cm below the kerb top: frost-cracked, sea-blasted, dead.
			b.box(Vector3(bx, GARDEN_Y + BED_H - 0.12, bz), Vector3(BED.x - 0.3, 0.42, BED.y - 0.3),
				soil, "hull", Vector3.ZERO, true)
	# The dead irrigation ring: a header main round the beds with dropper tees, valves shut.
	var ring: Array = [
		Vector3(x0 - 0.8, GARDEN_Y + 0.12, z0 - 0.9),
		Vector3(x0 + span_x + 0.8, GARDEN_Y + 0.12, z0 - 0.9),
		Vector3(x0 + span_x + 0.8, GARDEN_Y + 0.12, z0 + span_z + 0.9),
		Vector3(x0 - 0.8, GARDEN_Y + 0.12, z0 + span_z + 0.9),
		Vector3(x0 - 0.8, GARDEN_Y + 0.12, z0 - 0.9)]
	KIT.pipe_run(b, ring, 0.09, MatLib.galvanized())
	# THE COLLAPSED POLYTUNNEL over the north two rows: hoops still standing at the south
	# end, folded and down at the north. This is the shape that tells the story.
	var t_z0: float = z0 + (BED.y + BED_GAP.y)
	for i in range(8):
		var hz: float = t_z0 - 0.6 + i * 1.55
		var fall: float = clampf((float(i) - 3.0) / 4.0, 0.0, 1.0)   # intact -> collapsed
		var h: float = lerpf(3.1, 0.55, fall)
		var lean: float = fall * 0.9
		var segs: int = 7
		for k in range(segs):
			var a0: float = PI * float(k) / float(segs)
			var a1: float = PI * float(k + 1) / float(segs)
			var r: float = span_x * 0.5 + 0.6
			var p0 := Vector3(c.x - cos(a0) * r, GARDEN_Y + sin(a0) * h, hz + sin(a0) * lean)
			var p1 := Vector3(c.x - cos(a1) * r, GARDEN_Y + sin(a1) * h, hz + sin(a1) * lean)
			b.member(p0, p1, 0.075, MatLib.galvanized(), "detail")
	# Torn sheeting still lashed to the standing end.
	for i in range(3):
		b.box(Vector3(c.x - 4.0 + i * 4.2, GARDEN_Y + 2.6 - i * 0.35, t_z0 - 0.2 + i * 1.4),
			Vector3(3.8, 0.05, 2.4), MatLib.canvas(Color(0.70, 0.69, 0.62)), "detail",
			Vector3(deg_to_rad(12.0 + i * 9.0), deg_to_rad(4.0 * i), 0))
	# Compost bays and a water butt in the lee of the stair head.
	for i in range(3):
		b.box(Vector3(MESS.position.x + 2.6 + i * 2.4, GARDEN_Y + 0.6, MESS.end.y - 2.0),
			Vector3(2.2, 1.2, 2.2), MatLib.weathered_wood(), "hull", Vector3.ZERO, true)
	b.cyl(Vector3(MESS.end.x - 3.0, GARDEN_Y + 1.35, MESS.end.y - 3.0), 1.3, 2.7,
		MatLib.rust_steel(), "hull", Vector3.ZERO, -1.0, 12, true)

static func _silos(b: KIT.Bake) -> void:
	# Three feed / grain silos, 10 m of barrel with a conical roof, tied by a gantry.
	var shell: Material = MatLib.galvanized()
	for z in SILO_Z:
		b.cyl(Vector3(SILO_X, (MAIN_Y + SILO_TOP) * 0.5, z), SILO_R, SILO_TOP - MAIN_Y, shell,
			"hull", Vector3.ZERO, -1.0, 14, true)
		b.cyl(Vector3(SILO_X, SILO_TOP + 0.9, z), SILO_R, 1.8, MatLib.rust_steel(), "hull",
			Vector3.ZERO, 0.35, 14)
		# Hopper cone at the bottom and the discharge chute onto the deck.
		b.cyl(Vector3(SILO_X, MAIN_Y + 1.2, z), SILO_R * 0.98, 2.4, shell, "hull", Vector3.ZERO, 0.5, 14)
		b.cyl(Vector3(SILO_X, MAIN_Y + 0.45, z), 0.45, 1.0, MatLib.rust_steel(), "detail")
		# Ring stiffeners — the detail that makes a cylinder read as a tank.
		for k in range(4):
			b.cyl(Vector3(SILO_X, MAIN_Y + 3.0 + k * 2.2, z), SILO_R + 0.07, 0.16, MatLib.rust_steel(), "detail", Vector3.ZERO, -1.0, 14)
	# The gantry over the tops, and the fill line running to it from the plant hall.
	KIT.catwalk(b, Vector3(SILO_X, GANTRY_Y, SILO_Z[0] - 3.4), Vector3(SILO_X, GANTRY_Y, SILO_Z[2] + 3.4), 1.6, true)
	KIT.pipe_run(b, [Vector3(20.0, PLANT_ROOF + 1.2, 10.0), Vector3(SILO_X, PLANT_ROOF + 1.2, 10.0),
		Vector3(SILO_X, GANTRY_Y + 1.6, 10.0), Vector3(SILO_X, GANTRY_Y + 1.6, SILO_Z[2])], 0.26)
	# Stair up from the plant roof to the gantry: 8 m of run for 3 m of rise, 20.6 deg.
	KIT.stair(b, Vector3(26.0, PLANT_ROOF, SILO_Z[2] + 3.0), Vector3(33.0, GANTRY_Y, SILO_Z[2] + 3.0), 1.6, true, true)

static func _tower(b: KIT.Bake) -> void:
	# THE OVERVIEW. A stair tower on the west shoulder from the main deck to y 28.4, with the
	# vent stack rising out of it — the place you climb to look back down the field at
	# SALTLINE-0, and forward at the drill.
	KIT.stair_tower(b, TOWER_HI, MAIN_Y, TOWER_TOP, 3.6, true)
	var c: Vector2 = TOWER_HI.get_center()
	# Head platform, one metre wider than the tower on every side.
	var head := Rect2(TOWER_HI.position.x - 1.0, TOWER_HI.position.y - 1.0,
		TOWER_HI.size.x + 2.0, TOWER_HI.size.y + 2.0)
	KIT.deck(b, head, TOWER_TOP, 0.24, MatLib.grating())
	KIT.rail_rect(b, head, TOWER_TOP, [], 0.2)
	# The vent stack, offset so it never stands in the view it exists to frame.
	b.cyl(Vector3(c.x + 3.4, (TOWER_TOP + STACK_TIP) * 0.5, c.y - 2.6), 1.15, STACK_TIP - TOWER_TOP,
		MatLib.dark_metal(), "hull", Vector3.ZERO, 0.95, 12, true)
	b.cyl(Vector3(c.x + 3.4, STACK_TIP + 0.4, c.y - 2.6), 1.35, 0.8, MatLib.rust_steel(), "detail", Vector3.ZERO, 1.1)
	for i in range(3):
		b.cyl(Vector3(c.x + 3.4, TOWER_TOP + 2.4 + i * 2.6, c.y - 2.6), 1.3, 0.2, MatLib.rust_steel(), "detail")
	# Obstruction light on the stack head — MARROW's one night marker above deck level.
	KIT.lamp_lens(b, Vector3(c.x + 3.4, STACK_TIP + 1.1, c.y - 2.6), Color(0.95, 0.22, 0.16), 0.45, 6.0)
	# Guys off the stack head to the deck — the lines that read from 160 m away.
	for a in [40.0, 160.0, 280.0]:
		var r: float = deg_to_rad(a)
		b.member(Vector3(c.x + 3.4, STACK_TIP - 1.5, c.y - 2.6),
			Vector3(c.x + 3.4 + cos(r) * 14.0, MAIN_Y + 0.4, c.y - 2.6 + sin(r) * 14.0), 0.06,
			MatLib.dark_metal(), "detail")
	# Garden stair: main deck to the roof, two flights on the mess block's west face.
	KIT.stair_tower(b, GARDEN_STAIR, MAIN_Y, GARDEN_Y, 3.6, true)
	# Plant-hall roof stair, on its north face.
	KIT.stair_tower(b, PLANT_STAIR, MAIN_Y, PLANT_ROOF, 3.6, true)

static func _machinery(b: KIT.Bake) -> void:
	# Cargo crane on the north-east shoulder, slewed out over the sea.
	KIT.crane(b, Vector3(33.0, MAIN_Y, 20.0), 13.0, 22.0, 34.0, 24.0)
	# Container stacks in the north bay — the thing that gives a deck human scale.
	KIT.containers(b, Vector3(-20.0, MAIN_Y, 22.0), 4, 2, 8.0)
	KIT.containers(b, Vector3(6.0, MAIN_Y, -21.0), 3, 2, -6.0)
	# Deck-level process: pumps, skids, a header, all boxes with pipework between them.
	var steel: Material = MatLib.rust_steel()
	for i in range(4):
		var x: float = -8.0 + i * 5.2
		b.box(Vector3(x, MAIN_Y + 1.1, -6.0), Vector3(3.4, 2.2, 2.6), MatLib.dark_metal(), "hull", Vector3.ZERO, true)
		b.cyl(Vector3(x - 0.8, MAIN_Y + 2.9, -6.0), 0.7, 1.6, steel, "detail")
		KIT.pipe_run(b, [Vector3(x, MAIN_Y + 2.2, -4.7), Vector3(x, MAIN_Y + 3.4, -3.0),
			Vector3(x, MAIN_Y + 3.4, 1.0)], 0.22)
	KIT.pipe_run(b, [Vector3(-10.0, MAIN_Y + 3.4, 1.0), Vector3(12.0, MAIN_Y + 3.4, 1.0),
		Vector3(12.0, MAIN_Y + 3.4, 4.0)], 0.34)
	# Horizontal storage tanks on saddles — fuel, fertiliser, brine.
	for i in range(3):
		var z: float = -20.0 + i * 5.0
		b.cyl(Vector3(-2.5, MAIN_Y + 1.8, z), 1.75, 9.0, MatLib.galvanized(), "hull",
			Vector3(0, 0, deg_to_rad(90.0)), -1.0, 14, true)
		for sx in [-3.2, 3.2]:
			b.box(Vector3(-2.5 + sx, MAIN_Y + 0.4, z), Vector3(0.5, 0.8, 3.4), steel, "detail")
	# Cable trays and conduit down the plant hall's west wall.
	KIT.pipe_run(b, [Vector3(1.5, MAIN_Y + 4.6, 5.0), Vector3(1.5, MAIN_Y + 4.6, 18.0)], 0.18)
	KIT.pipe_run(b, [Vector3(1.5, MAIN_Y + 5.2, 5.0), Vector3(1.5, MAIN_Y + 5.2, 18.0)], 0.14)

static func _links(b: KIT.Bake) -> void:
	# THE OVERPASSES. Rig 1 has none of these; the brief asks for "lots of overviews,
	# overpasses, irregular design", and a rig reads as a machine when you can walk over it.
	# 1. Garden roof to plant-hall roof — the two upper levels are the same height on purpose.
	KIT.catwalk(b, Vector3(-4.0, GARDEN_Y, 11.0), Vector3(2.0, PLANT_ROOF, 11.0), 2.0, true)
	# 2. The long diagonal: garden roof to the crane pedestal, 36 m across the north bay,
	#    hung from nothing and standing on posts to the deck.
	KIT.catwalk(b, Vector3(-4.0, GARDEN_Y, 17.0), Vector3(29.0, PLANT_ROOF, 21.5), 1.8, true, MAIN_Y)
	# 3. Hydroponics roof to the main deck, a short flight rather than a catwalk.
	KIT.stair(b, Vector3(-4.0, MAIN_Y, -18.0), Vector3(-4.0, HYDRO_ROOF, -12.0), 1.8, true, true)
	KIT.catwalk(b, Vector3(-5.0, HYDRO_ROOF, -14.0), Vector3(-14.0, HYDRO_ROOF, -14.0), 1.6, true)
	# 4. Plant roof to the mess block's upper storey door — the "half level" link.
	KIT.catwalk(b, Vector3(2.0, PLANT_ROOF, 6.5), Vector3(-3.72, MAIN_Y + BLOCK_H + 0.0, 6.5), 1.6, true, MAIN_Y)

static func _lights(b: KIT.Bake, host: Node3D) -> void:
	# Sodium floodlight masts. Shadows OFF, deliberately: render_budget caps the whole game
	# at two shadow-casting positional lights and those slots belong to wherever the player
	# actually is. A neighbour rig's floods are silhouette and glow, not shadow.
	var mast_pts: Array = [
		Vector3(-36.0, MAIN_Y, 22.0), Vector3(36.0, MAIN_Y, -22.0),
		Vector3(-36.0, MAIN_Y, -22.0), Vector3(0.0, GARDEN_Y, 1.0),
		Vector3(20.0, MAIN_Y, -22.0),
	]
	for p in mast_pts:
		b.cyl(p + Vector3(0, 4.0, 0), 0.16, 8.0, MatLib.galvanized(), "detail")
		b.box(p + Vector3(0, 8.3, 0), Vector3(1.4, 0.5, 0.6), MatLib.dark_metal(), "detail")
		KIT.lamp_lens(b, p + Vector3(0, 8.05, 0), Color(1.0, 0.72, 0.34), 0.62, 5.5)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.46)     # sodium
		l.light_energy = 2.2
		l.omni_range = 22.0
		l.shadow_enabled = false
		l.add_to_group("rig_field_floods")
		host.add_child(l)
		l.position = b.to_world(p + Vector3(0, 8.1, 0))
