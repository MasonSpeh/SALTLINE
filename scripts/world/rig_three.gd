class_name RigThree extends RefCounted
## RIG 3 — "THE ANCHORAGE" · residential / luxury. NO DRILLING.
##
## Where the captains and guests stayed. Painted white-and-cream superstructure, big windows,
## a genuinely large helideck cantilevered out over open water, a railed promenade. Corporate,
## once-comfortable, now salt-ruined — the tonal opposite of MARROW, and the contrast is the
## point. It is the TALLEST of the first three rigs (mast at y 44) and the smallest in
## footprint, so the field's skyline steps: broad-and-low, tall-and-narrow, then the drill.
##
## HERO FEATURE — THE TWO-STOREY AQUARIUM in the lunch hall. The mess is a 6.6 m double-height
## room; the tank stands 5.8 m of it, from y 22.4 to y 28.2, and a gallery balcony at y 25.3
## puts the player's eye at its MIDDLE. That is the shot, and the room is built around it.
## This session builds the tank, its plinth, its plant room, its circuit panel and its gantry,
## and publishes the water volume as metadata so the stocking system binds to real numbers
## instead of a second, drifting copy of them.
##
## LOCAL FRAME: origin on mean water at the platform centre, +Y up, +Z "north".
## Placed by rig_field.gd at world (58, 0, 262), bearing +10 deg.

## By path, not by class name: the global class cache lags a new file, and a rig that
## fails to parse is a rig that silently does not exist.
const KIT := preload("res://scripts/world/rig_kit.gd")

# ------------------------------------------------------------------- elevations (metres)

const SUB_TOP: float = 20.90       ## caisson tops, below the deck slab underside (21.0)
const MAIN_Y: float = 22.00        ## main deck / promenade / mess floor
const MAIN_T: float = 1.00
const LOW_Y: float = 1.80          ## the luxury boat landing, low and close to the water
const STOREY: float = 3.30         ## ONE storey module. Every level above is a multiple.
const MEZZ_Y: float = 25.30        ## MAIN_Y + STOREY — the aquarium gallery
const L2_Y: float = 28.60          ## MAIN_Y + 2*STOREY — guest cabins. Mess ceiling.
const L3_Y: float = 31.90          ## MAIN_Y + 3*STOREY — captain's suite, boardroom
const ROOF_Y: float = 35.20        ## MAIN_Y + 4*STOREY — THE OVERVIEW
const MAST_TOP: float = 44.00      ## comms mast: the ANCHORAGE's highest point
const HELI_Y: float = 28.50        ## helideck, 6.5 m clear over the deck it shelters
const ANNEX_ROOF: float = 28.60    ## gym / cinema / medical annexe

## The aquarium, in one place, so nothing re-types it.
const AQ_BASE: float = 22.00       ## plinth base = mess floor
const AQ_PLINTH: float = 0.40      ## machinery plinth under the tank
const AQ_WATER_LO: float = 22.40   ## inside face of the tank floor
const AQ_WATER_HI: float = 28.20   ## still water line — 5.8 m of water, two storeys
const AQ_X0: float = 1.60
const AQ_X1: float = 5.60          ## 4.0 m front-to-back
const AQ_Z0: float = 0.00
const AQ_Z1: float = 9.00          ## 9.0 m of viewing pane
const AQ_GLASS: float = 0.14

# ---------------------------------------------------------------------- plan (metres)

const LEG_HALF: float = 2.50
const LEG_X: Array = [-20.0, 20.0]
const LEG_Z: Array = [-16.0, 16.0]

const DECK := Rect2(-27.0, -21.0, 54.0, 42.0)
## EAST of the arrival lane, deliberately: at its first position (x -13..-5.5) the hole
## sat directly in front of the bridge landing and the probe found the spawn point inside it.
const STAIRWELL := Rect2(8.0, -19.0, 7.5, 8.0)        ## down to the boat landing
const HOTEL := Rect2(-22.0, -6.0, 28.0, 20.0)        ## the white block
const ANNEX := Rect2(10.0, 4.0, 16.0, 14.0)          ## gym, cinema, library, medical
const PROMENADE := Rect2(-33.0, -12.0, 6.0, 24.0)    ## cantilevered west, over open water
const HELI_BASE := Rect2(27.0, -14.0, 11.0, 20.0)    ## cantilevered east, under the pad
const HOTEL_STAIR := Rect2(-27.0, 2.0, 5.0, 9.0)     ## main deck -> roof, 4 flights of 3.3

const HELI_C := Vector3(30.0, HELI_Y, -4.0)
const HELI_R: float = 12.00                          ## 24 m across. A real S-92 pad is 22.2.

const MESS := Rect2(-8.0, -6.0, 14.0, 20.0)          ## the double-height lunch hall
## Runs right up to the tank's viewing face (x 1.6) — at 5.4 wide it stopped 0.2 m short
## and left a slot between the balcony edge and the glass.
const MEZZ := Rect2(-4.0, -2.0, 5.6, 13.0)           ## gallery balcony facing the tank
const MEZZ_N := Rect2(-4.0, 11.0, 10.0, 2.7)         ## the leg that reaches the stair

const BRIDGE_IN := Vector3(-8.0, MAIN_Y, -21.0)      ## from MARROW
const BRIDGE_OUT := Vector3(6.0, MAIN_Y, 21.0)       ## to DEEPWELL

static func build(b: KIT.Bake, host: Node3D) -> Dictionary:
	_substructure(b)
	_main_deck(b)
	_promenade(b)
	_hotel(b)
	_aquarium(b, host)
	_annex(b)
	_helideck(b)
	_boat_landing(b)
	_lights(b, host)
	return {
		"name": "THE ANCHORAGE",
		"bridge_in": BRIDGE_IN,
		"bridge_out": BRIDGE_OUT,
		"deck_y": MAIN_Y,
		"spawn": Vector3(-8.0, MAIN_Y, -17.0),
		"overview": Vector3(-8.0, ROOF_Y, 4.0),
		"aquarium": {
			"water_min": Vector3(AQ_X0 + AQ_GLASS, AQ_WATER_LO, AQ_Z0 + AQ_GLASS),
			"water_max": Vector3(AQ_X1 - AQ_GLASS, AQ_WATER_HI, AQ_Z1 - AQ_GLASS),
			"view_face": "west",
			"gallery_y": MEZZ_Y,
			"floor_y": MAIN_Y,
		},
		"fishing": [
			{"id": "anchorage_promenade", "at": Vector3(-32.0, MAIN_Y, 0.0), "water": "open"},
			{"id": "anchorage_under_pad", "at": Vector3(35.0, MAIN_Y, -4.0), "water": "open"},
			{"id": "anchorage_davit", "at": Vector3(11.0, LOW_Y, -26.0), "water": "near"},
		],
	}

# ------------------------------------------------------------------------ substructure

static func _substructure(b: KIT.Bake) -> void:
	for x in LEG_X:
		for z in LEG_Z:
			KIT.caisson(b, x, z, LEG_HALF, SUB_TOP)
	for z in LEG_Z:
		KIT.pontoon(b, Vector3(0.0, -1.05, z), Vector3(48.0, 4.0, 8.0))
	var steel: Material = MatLib.rust_steel()
	# X-bracing between the legs on all four faces — the ANCHORAGE is narrow and tall, so
	# its substructure is what stops it reading as a table.
	for x in LEG_X:
		b.member(Vector3(x, 1.4, -13.5), Vector3(x, 14.0, 13.5), 0.5, steel, "hull")
		b.member(Vector3(x, 14.0, -13.5), Vector3(x, 1.4, 13.5), 0.5, steel, "hull")
	for z in LEG_Z:
		b.member(Vector3(-17.5, 1.4, z), Vector3(17.5, 14.0, z), 0.5, steel, "hull")
		b.member(Vector3(-17.5, 14.0, z), Vector3(17.5, 1.4, z), 0.5, steel, "hull")
		b.box(Vector3(0.0, 19.9, z), Vector3(46.0, 1.5, 1.3), steel, "hull")
	for x in LEG_X:
		b.box(Vector3(x, 19.9, 0.0), Vector3(1.3, 1.5, 34.0), steel, "hull")

static func _main_deck(b: KIT.Bake) -> void:
	KIT.deck_hole(b, DECK, STAIRWELL, MAIN_Y, MAIN_T)
	# The ANCHORAGE has a CONTINUOUS railed perimeter where MARROW has gaps: it is the rig
	# that had guests on it, and the difference in how it treats a drop is characterisation.
	KIT.rail_rect(b, DECK, MAIN_Y, [
		["s", -13.0, -3.0],       # bridge from MARROW
		["n", 1.0, 11.0],         # bridge to DEEPWELL
		["w", -12.0, 12.0],       # onto the promenade
		["e", -14.0, 6.0],        # onto the helideck cantilever
	], 0.35)
	KIT.rail_rect(b, STAIRWELL, MAIN_Y, [["n", 9.0, 14.0]], -0.1)
	KIT.stair_tower(b, STAIRWELL, LOW_Y, MAIN_Y, 3.37, true)
	# Teak-look decking on the promenade approach and the south arrival apron — the one
	# place on the whole field where somebody chose a surface for how it looked.
	var teak: Material = MatLib.weathered_wood()
	b.box(Vector3(-8.0, MAIN_Y + 0.03, -17.5), Vector3(11.0, 0.06, 6.0), teak, "detail")
	b.box(Vector3(-24.5, MAIN_Y + 0.03, 0.0), Vector3(5.0, 0.06, 22.0), teak, "detail")

static func _promenade(b: KIT.Bake) -> void:
	# THE PROMENADE. 6 m of railed deck cantilevered west past the rim, 24 m long, over open
	# water — the elegant fishing spot the brief asks for, and the reason the west elevation
	# has a shadow line under it.
	KIT.deck(b, PROMENADE, MAIN_Y, 0.45, MatLib.checker_plate())
	KIT.rail_rect(b, PROMENADE, MAIN_Y, [["e", -12.0, 12.0]], 0.2)
	var steel: Material = MatLib.rust_steel()
	for z in [-11.0, -5.5, 0.0, 5.5, 11.0]:
		b.member(Vector3(-32.5, MAIN_Y - 0.45, z), Vector3(-24.0, 16.5, z), 0.34, steel, "hull")
		b.member(Vector3(-27.0, MAIN_Y - 0.45, z), Vector3(-27.0, 20.6, z), 0.24, steel, "hull")
	# Bench-and-lamp rhythm along it. Structure only — the fitting-out pass adds the rest.
	for i in range(5):
		var z: float = -10.0 + i * 5.0
		b.box(Vector3(-30.0, MAIN_Y + 0.45, z), Vector3(0.55, 0.9, 1.8), MatLib.weathered_wood(), "detail", Vector3.ZERO, true)
		b.cyl(Vector3(-28.2, MAIN_Y + 1.7, z + 2.4), 0.09, 3.4, MatLib.galvanized(), "detail")
		b.cyl(Vector3(-28.2, MAIN_Y + 3.5, z + 2.4), 0.28, 0.5, MatLib.glass(Color(0.85, 0.85, 0.7)), "glass")

# ------------------------------------------------------------------------- superstructure

static func _hotel(b: KIT.Bake) -> void:
	var cream: Material = MatLib.dirty_white_panel()
	var frost: Color = Color(0.62, 0.70, 0.72)
	# Ground: ONE 6.6 m double-height storey. Its "roof" is the L2 floor slab, so it takes
	# no railing — see KIT.block's roof_rails note.
	KIT.block(b, HOTEL, MAIN_Y, 1, L2_Y - MAIN_Y, cream, {
		"windows": true,
		"glass_tint": frost,
		"doors": [["s", -14.0, 0], ["e", 2.0, 0], ["w", 4.0, 0]],
		"roof_deck": true,
		"roof_rails": false,
	})
	# Guest cabins and the captain's level: two 3.3 m storeys, then the roof.
	KIT.block(b, HOTEL, L2_Y, 2, STOREY, cream, {
		"windows": true,
		"glass_tint": frost,
		"doors": [["w", 4.0, 0], ["w", 4.0, 1]],
		"roof_deck": true,
		"roof_gaps": [["w", 2.0, 7.0]],
	})
	# Balcony band on the west elevation at L2 and L3 — the guest rooms had a view, and the
	# shadow it throws is what separates this block from MARROW's sheds at 160 m.
	for y in [L2_Y, L3_Y]:
		var bal := Rect2(HOTEL.position.x - 2.2, HOTEL.position.y + 2.0, 2.2, HOTEL.size.y - 4.0)
		KIT.deck(b, bal, y + 0.02, 0.22, MatLib.checker_plate())
		KIT.rail_rect(b, bal, y + 0.02, [["e", bal.position.y, bal.end.y]], 0.1)
		for z in [bal.position.y + 1.0, bal.get_center().y, bal.end.y - 1.0]:
			b.member(Vector3(bal.position.x + 0.2, y - 0.2, z), Vector3(HOTEL.position.x + 0.1, y - 2.2, z), 0.16, MatLib.rust_steel(), "detail")
	# The mess hall's own tall glazing on the south gable: a two-storey window wall, cracked.
	b.box(Vector3(MESS.get_center().x, (MAIN_Y + L2_Y) * 0.5, MESS.position.y + 0.1),
		Vector3(MESS.size.x - 2.0, L2_Y - MAIN_Y - 1.4, 0.1), MatLib.glass(frost), "glass")
	for i in range(4):
		b.box(Vector3(MESS.position.x + 2.0 + i * 3.2, (MAIN_Y + L2_Y) * 0.5, MESS.position.y + 0.16),
			Vector3(0.18, L2_Y - MAIN_Y - 1.4, 0.18), MatLib.dark_metal(), "detail")
	# Roof: the OVERVIEW. Comms mast, radome, and a lee behind the stair head.
	var c: Vector2 = HOTEL.get_center()
	KIT.lattice(b, c.x + 6.0, c.y - 4.0, ROOF_Y, MAST_TOP, 1.5, 0.55, 4, 0.22)
	b.cyl(Vector3(c.x + 6.0, MAST_TOP + 1.0, c.y - 4.0), 1.5, 2.0, MatLib.dirty_white_panel(), "hull", Vector3.ZERO, 0.9, 12)
	for i in range(3):
		b.box(Vector3(c.x + 6.0, ROOF_Y + 3.0 + i * 3.0, c.y - 4.0), Vector3(3.4, 0.12, 0.5), MatLib.galvanized(), "detail",
			Vector3(0, deg_to_rad(38.0 * i), 0))
	# Two lifeboat davits on the east roof edge, empty — the boats went.
	for z in [c.y - 6.0, c.y + 5.0]:
		for sgn in [-1.0, 1.0]:
			b.member(Vector3(HOTEL.end.x - 1.0, ROOF_Y, z + sgn * 1.6), Vector3(HOTEL.end.x + 2.6, ROOF_Y + 3.2, z + sgn * 1.6), 0.24, MatLib.rust_steel(), "detail")
		b.member(Vector3(HOTEL.end.x + 2.6, ROOF_Y + 3.2, z - 1.6), Vector3(HOTEL.end.x + 2.6, ROOF_Y + 3.2, z + 1.6), 0.2, MatLib.rust_steel(), "detail")
	# The stair tower on the west face: main deck to roof, landing exactly on every floor.
	KIT.stair_tower(b, HOTEL_STAIR, MAIN_Y, ROOF_Y, STOREY, true)
	# ...and the bridges from its landings into the block, one per level.
	for y in [MEZZ_Y, L2_Y, L3_Y]:
		KIT.catwalk(b, Vector3(HOTEL_STAIR.end.x, y, 6.5), Vector3(HOTEL.position.x - 0.2, y, 6.5), 1.6, true)

static func _aquarium(b: KIT.Bake, host: Node3D) -> void:
	# ---- THE TANK ----------------------------------------------------------------
	# 4.0 (x) x 9.0 (z) x 5.8 (y) of water: 208.8 m3, standing on a 0.4 m machinery plinth
	# in the double-height mess hall. The long face looks WEST across the hall, and the
	# gallery balcony at y 25.3 puts the player's eye halfway up it.
	var cx: float = (AQ_X0 + AQ_X1) * 0.5
	var cz: float = (AQ_Z0 + AQ_Z1) * 0.5
	var sx: float = AQ_X1 - AQ_X0
	var sz: float = AQ_Z1 - AQ_Z0
	var glass: Material = MatLib.glass(Color(0.72, 0.86, 0.88))
	var frame: Material = MatLib.dark_metal()
	var brass: Material = MatLib.flat(Color(0.52, 0.44, 0.24))
	# Plinth: the pump/filter machinery lives in it.
	b.box(Vector3(cx, AQ_BASE + AQ_PLINTH * 0.5, cz), Vector3(sx + 0.5, AQ_PLINTH, sz + 0.5),
		MatLib.dark_metal(), "hull", Vector3.ZERO, true)
	# Tank floor, then four glass walls up to the still line, then 0.35 m of freeboard.
	var wall_h: float = AQ_WATER_HI - AQ_WATER_LO + 0.35
	b.box(Vector3(cx, AQ_WATER_LO - 0.1, cz), Vector3(sx, 0.2, sz), frame, "hull", Vector3.ZERO, true)
	for face in [[Vector3(AQ_X0 + AQ_GLASS * 0.5, 0, cz), Vector3(AQ_GLASS, wall_h, sz)],
			[Vector3(AQ_X1 - AQ_GLASS * 0.5, 0, cz), Vector3(AQ_GLASS, wall_h, sz)],
			[Vector3(cx, 0, AQ_Z0 + AQ_GLASS * 0.5), Vector3(sx, wall_h, AQ_GLASS)],
			[Vector3(cx, 0, AQ_Z1 - AQ_GLASS * 0.5), Vector3(sx, wall_h, AQ_GLASS)]]:
		var p: Vector3 = face[0]
		p.y = AQ_WATER_LO + wall_h * 0.5
		b.box(p, face[1], glass, "glass")
		b.collider(p, face[1])
	# Structural frame: corner posts and three horizontal bands, which is what tells the eye
	# this is 200 tonnes of water and not a shop window.
	for px in [AQ_X0, AQ_X1]:
		for pz in [AQ_Z0, AQ_Z1]:
			b.box(Vector3(px, AQ_WATER_LO + wall_h * 0.5, pz), Vector3(0.3, wall_h + 0.2, 0.3), frame, "hull")
	for y in [AQ_WATER_LO, AQ_WATER_LO + wall_h * 0.5, AQ_WATER_LO + wall_h]:
		for pz in [AQ_Z0, AQ_Z1]:
			b.box(Vector3(cx, y, pz), Vector3(sx + 0.3, 0.22, 0.22), frame, "detail")
		for px in [AQ_X0, AQ_X1]:
			b.box(Vector3(px, y, cz), Vector3(0.22, 0.22, sz + 0.3), frame, "detail")
	# Vertical mullions on the viewing face, every 3 m — the pane is 9 m long.
	for i in range(2):
		b.box(Vector3(AQ_X0, AQ_WATER_LO + wall_h * 0.5, AQ_Z0 + 3.0 * (i + 1)), Vector3(0.26, wall_h, 0.26), brass, "detail")
	# THE WATER. One translucent, faintly emissive volume inside the glass, so the tank reads
	# as full from both levels even before a single fish is in it. Deliberately NOT the ocean
	# shader: this water is still, lit from above, and 5.8 m deep, not 92.
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.20, 0.52, 0.55, 0.46)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.12
	wm.metallic = 0.05
	wm.emission_enabled = true
	wm.emission = Color(0.14, 0.44, 0.46)
	wm.emission_energy_multiplier = 0.35
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	b.box(Vector3(cx, (AQ_WATER_LO + AQ_WATER_HI) * 0.5, cz),
		Vector3(sx - AQ_GLASS * 2.0, AQ_WATER_HI - AQ_WATER_LO, sz - AQ_GLASS * 2.0),
		wm, "glass")
	# Rockwork and a sand bed on the tank floor — hero props are Tripo's job later; this is
	# the massing so the tank is never an empty box.
	var rock: Material = MatLib.flat(Color(0.24, 0.26, 0.25))
	b.box(Vector3(cx, AQ_WATER_LO + 0.12, cz), Vector3(sx - 0.4, 0.24, sz - 0.4), MatLib.flat(Color(0.62, 0.58, 0.48)), "hull")
	for i in range(5):
		var rz: float = AQ_Z0 + 1.1 + i * 1.75
		var rh: float = 0.9 + fmod(float(i) * 0.77, 1.0) * 1.6
		b.box(Vector3(cx + (0.5 if i % 2 else -0.4), AQ_WATER_LO + 0.24 + rh * 0.5, rz),
			Vector3(1.1 + 0.3 * (i % 3), rh, 1.2), rock, "hull",
			Vector3(deg_to_rad(4.0 * i), deg_to_rad(20.0 * i), deg_to_rad(3.0)))
	# ---- THE GALLERY -------------------------------------------------------------
	# A balcony at y 25.3 facing the tank's long pane, open to the hall below on three sides.
	KIT.deck(b, MEZZ, MEZZ_Y, 0.24, MatLib.checker_plate())
	KIT.deck(b, MEZZ_N, MEZZ_Y, 0.24, MatLib.checker_plate())
	KIT.rail_rect(b, MEZZ, MEZZ_Y, [["n", MEZZ.position.x, MEZZ.end.x],
		["e", MEZZ.position.y, MEZZ.end.y]], 0.1)
	KIT.rail_rect(b, MEZZ_N, MEZZ_Y, [["s", MEZZ.position.x, MEZZ.end.x]], 0.1)
	for z in [MEZZ.position.y + 1.0, MEZZ.get_center().y, MEZZ.end.y - 1.0]:
		b.member(Vector3(MEZZ.position.x, MEZZ_Y - 0.24, z), Vector3(MESS.position.x + 0.3, MAIN_Y + 0.4, z), 0.16, MatLib.rust_steel(), "detail")
	# Open stair from the mess floor up to the gallery.
	KIT.stair(b, Vector3(-6.4, MAIN_Y, 12.0), Vector3(-6.4, MEZZ_Y, 6.6), 1.5, true, true)
	# ---- THE GANTRY, THE PLANT AND THE CIRCUIT -----------------------------------
	# A maintenance gantry over the tank top at y 28.55, reached off the gallery's north leg.
	KIT.catwalk(b, Vector3(cx, AQ_WATER_HI + 0.55, AQ_Z0 - 0.9), Vector3(cx, AQ_WATER_HI + 0.55, AQ_Z1 + 0.9), 1.2, true)
	b.box(Vector3(cx, AQ_WATER_HI + 0.42, AQ_Z1 - 1.6), Vector3(1.4, 0.1, 1.4), MatLib.grating(), "detail")
	# Filter house and pump skid NORTH of the tank, plumbed back into it.
	#
	# It used to sit at `MESS.end.x - 1.6` — x 4.4, which is INSIDE the tank's x span of
	# 1.6..5.6. The first render of the gallery shot showed three filter cartridges standing
	# in the water like drums. The mess hall only leaves 0.4 m east of the tank, so the plant
	# goes to its north end, where there is 5 m of room.
	var plant_z: float = AQ_Z1 + 2.2
	b.box(Vector3(3.6, MAIN_Y + 1.3, plant_z), Vector3(3.4, 2.6, 2.0), MatLib.galvanized(), "hull", Vector3.ZERO, true)
	for i in range(3):
		b.cyl(Vector3(2.4 + i * 1.2, MAIN_Y + 3.6, plant_z), 0.42, 1.9, MatLib.dark_metal(), "detail")
	KIT.pipe_run(b, [Vector3(3.6, MAIN_Y + 2.6, plant_z - 1.1), Vector3(3.6, AQ_WATER_HI + 0.2, AQ_Z1 + 0.6),
		Vector3(3.6, AQ_WATER_HI + 0.2, AQ_Z1 - 0.4)], 0.14)
	KIT.pipe_run(b, [Vector3(AQ_X1 + 0.4, AQ_WATER_LO + 0.3, AQ_Z1 - 0.6), Vector3(AQ_X1 + 0.4, AQ_WATER_LO + 0.3, plant_z),
		Vector3(AQ_X1 + 0.4, MAIN_Y + 2.0, plant_z)], 0.18)
	# The breaker panel the player has to find a fuse for, beside the plant.
	b.box(Vector3(1.4, MAIN_Y + 1.5, plant_z - 1.15), Vector3(0.8, 0.9, 0.22), MatLib.painted_steel(), "detail")
	# Tank lighting: the one light in the game that shines DOWN through water. Shadowless.
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.92, 0.95)
	l.light_energy = 1.6
	l.omni_range = 16.0
	l.shadow_enabled = false
	l.add_to_group("aquarium_lights")
	host.add_child(l)
	l.position = b.to_world(Vector3(cx, AQ_WATER_HI - 0.6, cz))
	# Publish the tank so the stocking pass binds to the geometry rather than to a copy of it.
	var marker := Node3D.new()
	marker.name = "AquariumVolume"
	marker.add_to_group("aquarium")
	host.add_child(marker)
	marker.position = b.to_world(Vector3(cx, (AQ_WATER_LO + AQ_WATER_HI) * 0.5, cz))
	marker.set_meta("water_size", Vector3(sx - AQ_GLASS * 2.0, AQ_WATER_HI - AQ_WATER_LO, sz - AQ_GLASS * 2.0))
	marker.set_meta("circuit", "anchorage_aquarium")
	marker.set_meta("rig", "anchorage")

static func _annex(b: KIT.Bake) -> void:
	# Gym, cinema/rec, library, medical suite. Lower and squarer than the hotel, so the
	# block silhouette has a step in it instead of one slab.
	KIT.block(b, ANNEX, MAIN_Y, 2, STOREY, MatLib.dirty_white_panel(), {
		"windows": true,
		"glass_tint": Color(0.60, 0.68, 0.70),
		"doors": [["w", 11.0, 0], ["s", 14.0, 0], ["w", 11.0, 1]],
		"roof_deck": true,
		"roof_gaps": [["w", 8.0, 13.0]],
	})
	# Link bridge from the hotel's L2 to the annexe roof — an overpass across the north bay.
	KIT.catwalk(b, Vector3(HOTEL.end.x, L2_Y, 10.0), Vector3(ANNEX.position.x, ANNEX_ROOF, 10.0), 1.8, true, MAIN_Y)
	# A glazed conservatory corner on the annexe roof: the guests' view of the field.
	var cons := Rect2(ANNEX.end.x - 8.0, ANNEX.position.y + 1.0, 7.0, 6.0)
	KIT.block(b, cons, ANNEX_ROOF, 1, 2.9, MatLib.glass(Color(0.66, 0.74, 0.74)), {
		"windows": false,
		"doors": [["w", cons.get_center().y, 0]],
		"roof_deck": false,
	})
	KIT.rail_rect(b, ANNEX, ANNEX_ROOF, [["w", 8.0, 13.0]], 0.25)

static func _helideck(b: KIT.Bake) -> void:
	# The cantilever platform under the pad: 11 x 20 m of deck hung off the east rim. This is
	# the sheltered fishing spot, and the reason the pad has anything to stand on.
	KIT.deck(b, HELI_BASE, MAIN_Y, 0.5, MatLib.checker_plate())
	KIT.rail_rect(b, HELI_BASE, MAIN_Y, [["w", -14.0, 6.0]], 0.2)
	var steel: Material = MatLib.rust_steel()
	for z in [-12.5, -7.0, -1.0, 4.5]:
		b.member(Vector3(HELI_BASE.end.x - 0.5, MAIN_Y - 0.5, z), Vector3(21.0, 16.0, z), 0.4, steel, "hull")
		b.member(Vector3(27.5, MAIN_Y - 0.5, z), Vector3(27.5, 20.6, z), 0.3, steel, "hull")
	# THE HELIDECK. 24 m across the flats — genuinely large, as asked.
	KIT.helipad(b, HELI_C, HELI_R, MAIN_Y)
	# Access: two flights from the cantilever deck up to the pad's south edge.
	KIT.stair(b, Vector3(33.0, MAIN_Y, -13.0), Vector3(33.0, 25.25, -8.0), 1.6, true, true)
	KIT.stair(b, Vector3(34.8, 25.25, -8.0), Vector3(34.8, HELI_Y, -13.0), 1.6, true, true)
	b.box(Vector3(33.9, 25.13, -8.0), Vector3(3.4, 0.24, 2.2), MatLib.grating(), "hull", Vector3.ZERO, true)
	# Floodlight masts and the windsock, on the pad's perimeter but below its surface, which
	# is where they go on a real helideck so nothing stands proud of the landing plane.
	for a in [30.0, 150.0, 250.0, 330.0]:
		var r: float = deg_to_rad(a)
		var p := Vector3(HELI_C.x + cos(r) * (HELI_R + 1.2), HELI_Y - 1.1, HELI_C.z + sin(r) * (HELI_R + 1.2))
		b.cyl(p, 0.12, 1.6, MatLib.galvanized(), "detail")
		b.box(p + Vector3(0, 0.9, 0), Vector3(0.6, 0.3, 0.4), MatLib.dark_metal(), "detail")
	var wp := Vector3(HELI_C.x - HELI_R - 1.6, HELI_Y + 1.4, HELI_C.z + 8.0)
	b.cyl(wp, 0.09, 5.0, MatLib.galvanized(), "detail")
	b.cyl(wp + Vector3(-1.1, 2.3, 0), 0.42, 2.2, MatLib.flat(Color(0.75, 0.28, 0.12)), "detail",
		Vector3(0, 0, deg_to_rad(90.0)), 0.16, 10)

static func _boat_landing(b: KIT.Bake) -> void:
	# The low luxury landing with its davit, 1.8 m over mean water on the south face.
	KIT.boat_landing(b, Vector3(11.75, 0.0, -25.0), 180.0, MAIN_Y, LOW_Y, 9.0, 5.0)
	KIT.catwalk(b, Vector3(11.75, LOW_Y, -22.6), Vector3(11.75, LOW_Y, -18.6), 2.2, true)
	var steel: Material = MatLib.rust_steel()
	# The davit: a curved arm that once swung a launch out. Empty cradle, still rigged.
	for sgn in [-1.0, 1.0]:
		var x: float = 11.75 + sgn * 2.6
		b.member(Vector3(x, LOW_Y, -23.0), Vector3(x, LOW_Y + 4.4, -23.0), 0.26, steel, "detail")
		b.member(Vector3(x, LOW_Y + 4.4, -23.0), Vector3(x, LOW_Y + 5.0, -26.4), 0.24, steel, "detail")
		b.member(Vector3(x, LOW_Y + 5.0, -26.4), Vector3(x, LOW_Y + 2.6, -26.4), 0.05, MatLib.dark_metal(), "detail")
	b.box(Vector3(11.75, LOW_Y + 2.3, -26.4), Vector3(4.4, 0.3, 1.4), MatLib.weathered_wood(), "detail")

static func _lights(b: KIT.Bake, host: Node3D) -> void:
	# Cool white, not sodium: the ANCHORAGE was lit like a hotel, and the difference in
	# colour temperature between rigs 2 and 3 is legible from a bridge at night.
	var pts: Array = [
		Vector3(-30.0, MAIN_Y + 4.0, 0.0), Vector3(-8.0, MAIN_Y + 4.0, -18.0),
		Vector3(HELI_C.x, HELI_Y - 1.6, HELI_C.z), Vector3(6.0, MAIN_Y + 4.0, 18.0),
		Vector3(HOTEL.get_center().x, ROOF_Y + 1.4, HOTEL.get_center().y),
	]
	for p in pts:
		KIT.lamp_lens(b, p, Color(0.92, 0.96, 1.0), 0.6, 5.5)
		var l := OmniLight3D.new()
		l.light_color = Color(0.86, 0.92, 1.0)
		l.light_energy = 1.9
		l.omni_range = 24.0
		l.shadow_enabled = false
		l.add_to_group("rig_field_floods")
		host.add_child(l)
		l.position = b.to_world(p)
	# Navigation lights up the mast, so the ANCHORAGE is a shape at night from both sides.
	for y in [ROOF_Y + 3.0, ROOF_Y + 6.0, MAST_TOP - 1.0]:
		KIT.lamp_lens(b, Vector3(HOTEL.get_center().x + 6.0, y, HOTEL.get_center().y - 4.0),
			Color(0.95, 0.25, 0.18), 0.4, 6.0)
