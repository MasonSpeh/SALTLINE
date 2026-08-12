class_name RigFour extends RefCounted
## RIG 4 — "DEEPWELL" · the Bloom drill. The endgame, and the vanishing point of the field.
##
## A massive drilling platform standing directly over the Bloom fissure, 415 m due north of
## SALTLINE-0 and visible from its deck from hour one. Eight caissons instead of four, a 66 m
## square deck, and a derrick whose crown block sits at **y 96** — rig 1's derrick reaches 52,
## so DEEPWELL is 1.85x the tallest thing that existed before it. That ratio is the whole
## silhouette brief: it must read as the tallest thing in the world by a clear margin.
##
## THE MOON POOL is 12 x 12 m, open through every deck to the sea, and the Bloom light comes
## UP through it — through the grating, along the legs, off the underside of the drill floor.
## Same phenomenon as `underwater_world`'s palette, not a separate effect.
##
## LOCAL FRAME: origin on mean water at the platform centre, +Y up, +Z "north".
## Placed by rig_field.gd at world (0, 0, 415), bearing -6 deg.

## By path, not by class name: the global class cache lags a new file, and a rig that
## fails to parse is a rig that silently does not exist.
const KIT := preload("res://scripts/world/rig_kit.gd")

# ------------------------------------------------------------------- elevations (metres)

const SUB_TOP: float = 18.70      ## caisson tops, under the 1.2 m deck slab (18.8 .. 20.0)
const MAIN_Y: float = 20.00       ## main deck
const MAIN_T: float = 1.20        ## heavier slab than any other rig — it carries a derrick
const CELLAR_Y: float = 24.50     ## BOP deck, under the drill floor, around the moon pool
const DRILL_Y: float = 30.00      ## THE DRILL FLOOR — 10 m of substructure under it
const MONKEY_Y: float = 58.00     ## monkey board, where a derrickhand racks stands of pipe
const CROWN_Y: float = 96.00      ## crown block. The number the whole field is composed around.
const MUD_ROOF: float = 26.00     ## mud pits and shaker house
const LAB_ROOF: float = 26.60     ## core lab + control room, two storeys
const LOW_Y: float = 2.60         ## boat landing / decon deck
const TOWER_RISE: float = 2.90    ## the access tower's flight rise; every landing derives from it
const CELLAR_LOW: float = LOW_Y + TOWER_RISE * 3.0   ## 11.30 — THE PRODUCTION DECK
const MEZZ_Y: float = 23.60       ## outboard catwalk ring, one level over the main deck
const FLARE_ROOT: float = 26.00

# ---------------------------------------------------------------------- plan (metres)

## Eight caissons: 7 m square at the corners, 5 m square mid-side. Heavy, black, over-scaled.
const LEG_CORNER_HALF: float = 3.50
const LEG_MID_HALF: float = 2.50
const LEG_SPAN: float = 24.00

const DECK := Rect2(-33.0, -33.0, 66.0, 66.0)
const MOON := Rect2(-6.0, -6.0, 12.0, 12.0)        ## open to the fissure, through every deck
const SUB := Rect2(-12.0, -12.0, 24.0, 24.0)       ## drill substructure footprint
const CELLAR := Rect2(-27.0, -27.0, 54.0, 54.0)    ## the production level under the main slab

const MUD := Rect2(-31.0, 10.0, 22.0, 14.0)        ## mud pits, shaker house, pump room
const LAB := Rect2(10.0, -26.0, 20.0, 14.0)        ## core sample lab + control room
const AIRLOCK := Rect2(-7.0, -31.0, 12.0, 7.0)     ## containment / decon, at the stair head
const STAIR_TOWER := Rect2(-4.0, -42.0, 8.0, 10.0) ## OUTSIDE the deck: boat landing -> main

const DERRICK_BASE_HALF: float = 10.50
const DERRICK_TOP_HALF: float = 3.40
const DERRICK_BAYS: int = 11

const BRIDGE_IN := Vector3(8.0, MAIN_Y, -33.0)     ## from THE ANCHORAGE. There is no way on.

## The Bloom, as it reads from above: teal, coming up out of the water in the moon pool.
const BLOOM_TEAL := Color(0.24, 0.92, 0.82)

static func build(b: KIT.Bake, host: Node3D) -> Dictionary:
	_substructure(b)
	_main_deck(b)
	_production_deck(b)
	_mezzanine(b)
	_drill_substructure(b)
	_derrick(b)
	_process(b)
	_buildings(b)
	_interiors(b)
	_access(b)
	_bloom(b, host)
	_lights(b, host)
	return {
		"name": "DEEPWELL",
		"bridge_in": BRIDGE_IN,
		"bridge_out": Vector3.ZERO,
		"deck_y": MAIN_Y,
		"spawn": Vector3(8.0, MAIN_Y, -28.0),
		"overview": Vector3(0.0, DRILL_Y, -8.0),   ## ON the drill floor: SUB spans z -12..12
		"fishing": [
			{"id": "deepwell_moon_pool", "at": Vector3(0.0, MAIN_Y, -7.6), "water": "open"},
			{"id": "deepwell_decon", "at": Vector3(0.0, LOW_Y, -44.0), "water": "near"},
			{"id": "deepwell_west_rim", "at": Vector3(-32.0, MAIN_Y, -6.0), "water": "open"},
			{"id": "deepwell_production", "at": Vector3(-26.0, CELLAR_LOW, 10.0), "water": "near"},
		],
	}

# ------------------------------------------------------------------------ substructure

static func _substructure(b: KIT.Bake) -> void:
	# Corners.
	for sx in [-LEG_SPAN, LEG_SPAN]:
		for sz in [-LEG_SPAN, LEG_SPAN]:
			KIT.caisson(b, sx, sz, LEG_CORNER_HALF, SUB_TOP)
	# Mid-sides — the extra four that make DEEPWELL read as a heavier class of platform.
	for p in [Vector2(0, -LEG_SPAN), Vector2(0, LEG_SPAN), Vector2(-LEG_SPAN, 0), Vector2(LEG_SPAN, 0)]:
		KIT.caisson(b, p.x, p.y, LEG_MID_HALF, SUB_TOP)
	# Pontoon ring, not two beams: a square gravity base under all eight.
	for sz in [-LEG_SPAN, LEG_SPAN]:
		KIT.pontoon(b, Vector3(0.0, -1.05, sz), Vector3(58.0, 4.0, 9.0))
	for sx in [-LEG_SPAN, LEG_SPAN]:
		KIT.pontoon(b, Vector3(sx, -1.05, 0.0), Vector3(9.0, 4.0, 40.0))
	var steel: Material = MatLib.dark_metal()
	# Bracing between every adjacent pair of legs, on all four faces.
	for sz in [-LEG_SPAN, LEG_SPAN]:
		for seg in [[-LEG_SPAN, 0.0], [0.0, LEG_SPAN]]:
			b.member(Vector3(seg[0], 1.6, sz), Vector3(seg[1], 13.0, sz), 0.62, steel, "hull")
			b.member(Vector3(seg[1], 1.6, sz), Vector3(seg[0], 13.0, sz), 0.62, steel, "hull")
	for sx in [-LEG_SPAN, LEG_SPAN]:
		for seg in [[-LEG_SPAN, 0.0], [0.0, LEG_SPAN]]:
			b.member(Vector3(sx, 1.6, seg[0]), Vector3(sx, 13.0, seg[1]), 0.62, steel, "hull")
			b.member(Vector3(sx, 13.0, seg[0]), Vector3(sx, 1.6, seg[1]), 0.62, steel, "hull")
	# The deck girder grid. It is 66 m square and it carries a 66 m derrick: it gets a grid.
	for i in range(3):
		var v: float = -LEG_SPAN + i * LEG_SPAN
		b.box(Vector3(0.0, 17.8, v), Vector3(62.0, 1.9, 1.7), steel, "hull")
		b.box(Vector3(v, 17.8, 0.0), Vector3(1.7, 1.9, 62.0), steel, "hull")
	# The conductor guides down the moon pool: four columns dropping into the dark. These are
	# the shape that says "this hole goes somewhere".
	for sx in [-4.2, 4.2]:
		for sz in [-4.2, 4.2]:
			b.cyl(Vector3(sx, 4.0, sz), 0.55, 34.0, MatLib.rust_steel(), "hull")

static func _main_deck(b: KIT.Bake) -> void:
	KIT.deck_hole(b, DECK, MOON, MAIN_Y, MAIN_T)
	KIT.rail_rect(b, DECK, MAIN_Y, [
		["s", 3.0, 13.0],      # the bridge landing — the only way on
		["s", -6.0, 2.0],      # the decon stair head
		["s", 18.0, 25.0],     # mezzanine ring stair
		["w", -12.0, 0.0],     # west rim fishing gap
		["w", -25.0, -17.0],   # mezzanine ring stair
		["e", 17.0, 24.0],     # mezzanine ring stair
		["n", 18.0, 33.0],     # crane slew arc
		["n", -28.0, -18.0],   # mezzanine ring stair
	], 0.4)
	# THE MOON POOL RIM. Heavy guard rail all the way round with ONE deliberate gap at the
	# south face, which is where the player fishes the fissure from.
	KIT.rail_rect(b, MOON, MAIN_Y, [["s", -2.4, 2.4]], -0.35)
	var hazard: Material = MatLib.hazard_stripe()
	b.box(Vector3(0.0, MAIN_Y + 0.03, MOON.position.y - 0.9), Vector3(14.0, 0.06, 1.2), hazard, "detail")
	b.box(Vector3(0.0, MAIN_Y + 0.03, MOON.end.y + 0.9), Vector3(14.0, 0.06, 1.2), hazard, "detail")
	b.box(Vector3(MOON.position.x - 0.9, MAIN_Y + 0.03, 0.0), Vector3(1.2, 0.06, 14.0), hazard, "detail")
	b.box(Vector3(MOON.end.x + 0.9, MAIN_Y + 0.03, 0.0), Vector3(1.2, 0.06, 14.0), hazard, "detail")
	# Grated deck panels around the pool, so the Bloom light comes up THROUGH the floor.
	for i in range(6):
		var t: float = -12.5 + i * 5.0
		b.box(Vector3(t, MAIN_Y - 0.02, -9.5), Vector3(3.6, 0.14, 2.4), MatLib.grating(), "detail")
		b.box(Vector3(t, MAIN_Y - 0.02, 9.5), Vector3(3.6, 0.14, 2.4), MatLib.grating(), "detail")

static func _drill_substructure(b: KIT.Bake) -> void:
	# 10 m of substructure between the main deck and the drill floor, open on all sides so
	# the BOP stack and the moon pool are both visible from the deck. This is the layered
	# under-croft the reference images are all about.
	var steel: Material = MatLib.rust_steel()
	var half: float = SUB.size.x * 0.5
	for sx in [-half, half]:
		for sz in [-half, half]:
			b.box(Vector3(sx, (MAIN_Y + DRILL_Y) * 0.5, sz), Vector3(1.5, DRILL_Y - MAIN_Y, 1.5), steel, "hull", Vector3.ZERO, true)
	# X-bracing on all four faces of the substructure.
	for sz in [-half, half]:
		b.member(Vector3(-half, MAIN_Y, sz), Vector3(half, DRILL_Y, sz), 0.5, steel, "hull")
		b.member(Vector3(half, MAIN_Y, sz), Vector3(-half, DRILL_Y, sz), 0.5, steel, "hull")
	for sx in [-half, half]:
		b.member(Vector3(sx, MAIN_Y, -half), Vector3(sx, DRILL_Y, half), 0.5, steel, "hull")
		b.member(Vector3(sx, DRILL_Y, -half), Vector3(sx, MAIN_Y, half), 0.5, steel, "hull")
	# THE BOP DECK at 24.5 — a ring of grating around the pool with the stack in the middle.
	KIT.deck_hole(b, SUB, MOON.grow(1.4), CELLAR_Y, 0.3, MatLib.grating())
	KIT.rail_rect(b, SUB, CELLAR_Y, [["s", -3.0, 3.0]], 0.15)
	KIT.rail_rect(b, MOON.grow(1.4), CELLAR_Y, [], -0.2)
	# The blowout preventer stack, hung in the moon pool under the rotary.
	for i in range(4):
		var y: float = CELLAR_Y - 1.4 - i * 1.9
		b.cyl(Vector3(0.0, y, 0.0), 1.55 - i * 0.09, 1.7, MatLib.dark_metal(), "hull", Vector3.ZERO, -1.0, 14)
		b.cyl(Vector3(0.0, y + 0.9, 0.0), 1.85 - i * 0.09, 0.28, MatLib.rust_steel(), "detail", Vector3.ZERO, -1.0, 14)
		for a in [0.0, 90.0, 180.0, 270.0]:
			var r: float = deg_to_rad(a + i * 22.0)
			b.cyl(Vector3(cos(r) * 1.9, y, sin(r) * 1.9), 0.34, 0.9, MatLib.red_paint(), "detail",
				Vector3(deg_to_rad(90.0), -r, 0))
	# THE DRILL FLOOR at 30, with the rotary hole in it.
	KIT.deck_hole(b, SUB, MOON.grow(-2.0), DRILL_Y, 0.5, MatLib.checker_plate())
	KIT.rail_rect(b, SUB, DRILL_Y, [["s", -3.0, 3.0], ["w", -3.0, 3.0]], 0.25)
	KIT.rail_rect(b, MOON.grow(-2.0), DRILL_Y, [], -0.3)
	# Rotary table, drawworks, and the pipe ramp off the south edge — the drill floor's
	# furniture, as massing.
	b.cyl(Vector3(0.0, DRILL_Y + 0.22, 0.0), 3.1, 0.44, MatLib.dark_metal(), "hull", Vector3.ZERO, -1.0, 16, true)
	b.box(Vector3(-7.0, DRILL_Y + 1.5, 4.0), Vector3(5.4, 3.0, 4.2), MatLib.rust_steel(), "hull", Vector3.ZERO, true)
	b.cyl(Vector3(-7.0, DRILL_Y + 3.6, 4.0), 1.5, 4.0, MatLib.dark_metal(), "hull", Vector3(0, 0, deg_to_rad(90.0)), -1.0, 14)
	# Driller's cabin, glazed, looking at the rotary.
	b.box(Vector3(8.2, DRILL_Y + 1.5, -6.0), Vector3(3.6, 3.0, 3.0), MatLib.painted_steel(), "hull", Vector3.ZERO, true)
	b.box(Vector3(6.35, DRILL_Y + 1.7, -6.0), Vector3(0.1, 1.6, 2.4), MatLib.glass(Color(0.5, 0.62, 0.62)), "glass")
	# Pipe ramp / V-door down to the main deck, and the racked stands beside it.
	KIT.stair(b, Vector3(0.0, MAIN_Y, -19.9), Vector3(0.0, DRILL_Y, -12.35), 2.4, true, true)
	for i in range(9):
		b.member(Vector3(-10.6 + i * 1.05, MAIN_Y + 0.6, -24.0), Vector3(-10.6 + i * 1.05, DRILL_Y - 0.4, -12.6), 0.28, MatLib.rust_steel(), "detail")

static func _derrick(b: KIT.Bake) -> void:
	# THE DRILL. 66 m of tapering lattice off the drill floor, crown at y 96.
	KIT.lattice(b, 0.0, 0.0, DRILL_Y, CROWN_Y, DERRICK_BASE_HALF, DERRICK_TOP_HALF,
		DERRICK_BAYS, 0.85, MatLib.dark_metal(), "hull")
	var steel: Material = MatLib.rust_steel()
	# Monkey board — the platform two thirds up where a derrickhand stood. It breaks the
	# taper, which is what stops a lattice tower reading as a radio mast.
	var mh: float = lerpf(DERRICK_BASE_HALF, DERRICK_TOP_HALF, (MONKEY_Y - DRILL_Y) / (CROWN_Y - DRILL_Y))
	var mrect := Rect2(-mh - 1.2, -mh - 1.2, (mh + 1.2) * 2.0, (mh + 1.2) * 2.0)
	KIT.deck_hole(b, mrect, Rect2(-mh + 1.0, -mh + 1.0, (mh - 1.0) * 2.0, (mh - 1.0) * 2.0),
		MONKEY_Y, 0.2, MatLib.grating())
	KIT.rail_rect(b, mrect, MONKEY_Y, [], 0.15)
	# Fingerboard: the rack of vertical fingers that held stands of drill pipe.
	for i in range(7):
		var x: float = -mh + 0.9 + i * ((mh - 0.9) * 2.0 / 6.0)
		b.member(Vector3(x, MONKEY_Y, -mh + 0.4), Vector3(x, MONKEY_Y, -1.6), 0.14, steel, "detail")
	# CROWN BLOCK: the machine at the top. Sheave frame, sheaves, and the water table.
	var th: float = DERRICK_TOP_HALF
	KIT.deck(b, Rect2(-th - 0.6, -th - 0.6, (th + 0.6) * 2.0, (th + 0.6) * 2.0), CROWN_Y - 3.2, 0.3, MatLib.grating())
	KIT.rail_rect(b, Rect2(-th - 0.6, -th - 0.6, (th + 0.6) * 2.0, (th + 0.6) * 2.0), CROWN_Y - 3.2, [], 0.1)
	for sx in [-th * 0.6, th * 0.6]:
		b.box(Vector3(sx, CROWN_Y - 1.4, 0.0), Vector3(0.5, 2.6, th * 1.7), MatLib.dark_metal(), "hull")
	for i in range(5):
		b.cyl(Vector3(0.0, CROWN_Y - 1.0, -th * 0.7 + i * (th * 0.35)), 1.05, 0.34, steel, "hull",
			Vector3(0, 0, deg_to_rad(90.0)), -1.0, 14)
	b.box(Vector3(0.0, CROWN_Y + 0.6, 0.0), Vector3(th * 1.6, 0.5, th * 1.6), MatLib.rust_steel(), "hull")
	# Aircraft warning light mast — the highest point in the world.
	b.cyl(Vector3(0.0, CROWN_Y + 2.4, 0.0), 0.18, 3.2, steel, "detail")
	b.cyl(Vector3(0.0, CROWN_Y + 4.2, 0.0), 0.38, 0.5, MatLib.glowing(Color(0.9, 0.12, 0.1), 3.0), "hull")
	# Obstruction lights up the derrick. Emissive, "hull", never range-culled: at 415 m these
	# and the Bloom are the only things that say DEEPWELL is still switched on.
	for y in [DRILL_Y + 14.0, MONKEY_Y, MONKEY_Y + 16.0, CROWN_Y - 2.0]:
		var hh: float = lerpf(DERRICK_BASE_HALF, DERRICK_TOP_HALF, clampf((y - DRILL_Y) / (CROWN_Y - DRILL_Y), 0.0, 1.0))
		for sx in [-1.0, 1.0]:
			KIT.lamp_lens(b, Vector3(sx * hh, y, 0.0), Color(0.95, 0.20, 0.14), 0.42, 6.5)
	# THE TRAVELLING BLOCK, hung 40 m up on its fall. The last shift left it in the derrick.
	var tb_y: float = DRILL_Y + 34.0
	for i in range(6):
		b.member(Vector3(-0.9 + i * 0.36, CROWN_Y - 1.6, 0.0), Vector3(-0.9 + i * 0.36, tb_y + 1.6, 0.0), 0.05, MatLib.dark_metal(), "detail")
	b.box(Vector3(0.0, tb_y, 0.0), Vector3(2.4, 3.2, 1.6), MatLib.dark_metal(), "hull")
	b.cyl(Vector3(0.0, tb_y - 2.4, 0.0), 0.5, 2.2, steel, "detail")
	# THE DRILL STRING — the central core, from the travelling block through the rotary and
	# the moon pool, into the water and on down toward the fissure like the conductor stands
	# do. Kelly above the floor, string below, a slow teal collar where the Bloom takes it.
	b.cyl(Vector3(0.0, (tb_y - 2.4 + DRILL_Y) * 0.5, 0.0), 0.32, tb_y - 2.4 - DRILL_Y, MatLib.dark_metal(), "hull")
	b.cyl(Vector3(0.0, (DRILL_Y + 1.0) * 0.5, 0.0), 0.24, DRILL_Y - 1.0, MatLib.rust_steel(), "hull")
	b.cyl(Vector3(0.0, -42.5, 0.0), 0.24, 87.0, MatLib.dark_metal(), "hull")
	b.cyl(Vector3(0.0, -30.0, 0.0), 0.34, 4.0, MatLib.glowing(BLOOM_TEAL, 1.2), "lamp")
	# Standpipe and the kelly hose running up the derrick's south face.
	KIT.pipe_run(b, [Vector3(0.0, DRILL_Y + 1.0, -DERRICK_BASE_HALF + 0.6),
		Vector3(0.0, MONKEY_Y - 4.0, -DERRICK_TOP_HALF - 2.6)], 0.3)

static func _process(b: KIT.Bake) -> void:
	# Mud pits: four open tanks with an agitator on each, plus the shale shakers.
	for i in range(4):
		var x: float = -28.0 + i * 5.4
		b.box(Vector3(x, MAIN_Y + 1.9, 6.0), Vector3(4.8, 3.8, 7.0), MatLib.rust_steel(), "hull", Vector3.ZERO, true)
		b.box(Vector3(x, MAIN_Y + 4.0, 6.0), Vector3(4.4, 0.4, 6.6), MatLib.dark_metal(), "hull")
		b.cyl(Vector3(x, MAIN_Y + 4.9, 6.0), 0.4, 1.6, MatLib.dark_metal(), "detail")
		b.box(Vector3(x, MAIN_Y + 5.9, 6.0), Vector3(1.6, 0.8, 1.2), MatLib.galvanized(), "detail")
	KIT.catwalk(b, Vector3(-30.0, MAIN_Y + 4.4, 2.2), Vector3(-10.0, MAIN_Y + 4.4, 2.2), 1.4, true, MAIN_Y)
	# The mud return line from the moon pool to the shakers.
	KIT.pipe_run(b, [Vector3(-6.4, MAIN_Y + 2.2, 3.0), Vector3(-14.0, MAIN_Y + 2.2, 3.0),
		Vector3(-14.0, MAIN_Y + 4.6, 6.0), Vector3(-20.0, MAIN_Y + 4.6, 8.0)], 0.42)
	# Two pedestal cranes, slewed out over opposite corners.
	KIT.crane(b, Vector3(-29.0, MAIN_Y, -26.0), 14.0, 26.0, 215.0, 22.0)
	KIT.crane(b, Vector3(29.0, MAIN_Y, 26.0), 14.0, 26.0, 40.0, 22.0)
	# THE FLARE BOOM, 46 m out over the north-east quarter, tip at ~y 38.
	KIT.lattice(b, 26.0, 20.0, MAIN_Y, FLARE_ROOT, 2.6, 1.8, 2, 0.4)
	KIT.flare_boom(b, Vector3(26.0, FLARE_ROOT, 20.0), 45.0, 46.0, 15.0)
	# Casing and riser racks on the west deck — long horizontal masses under the derrick.
	for i in range(4):
		b.cyl(Vector3(-22.0, MAIN_Y + 0.9 + (i % 2) * 0.95, -14.0 + i * 1.1), 0.45, 22.0,
			MatLib.rust_steel(), "hull", Vector3(deg_to_rad(90.0), 0, 0), -1.0, 10, true)
	KIT.containers(b, Vector3(20.0, MAIN_Y, 18.0), 3, 2, 12.0,
		[Color(0.30, 0.33, 0.36), Color(0.42, 0.20, 0.16), Color(0.24, 0.30, 0.28)])

static func _buildings(b: KIT.Bake) -> void:
	# Shaker house / pump room over the mud pits' west end.
	KIT.block(b, MUD, MAIN_Y, 1, MUD_ROOF - MAIN_Y, MatLib.corrugated(), {
		"windows": false,
		"doors": [["e", 17.0, 0], ["s", -20.0, 0]],
		"roof_deck": true,
		"roof_gaps": [["e", 14.0, 20.0]],
	})
	# Core sample lab and the control room — the story lives in here. Two storeys, glazed
	# toward the drill floor so the frozen readouts are visible from outside.
	KIT.block(b, LAB, MAIN_Y, 2, 3.30, MatLib.painted_steel(), {
		"windows": true,
		"glass_tint": Color(0.52, 0.62, 0.60),
		"doors": [["w", -19.0, 0], ["w", -19.0, 1], ["n", 20.0, 0]],
		"roof_deck": true,
		"roof_gaps": [["w", -23.0, -16.0]],
	})
	# Containment / decon airlock at the stair head: a small hard box with one door each side.
	KIT.block(b, AIRLOCK, MAIN_Y, 1, 3.20, MatLib.dark_metal(), {
		"windows": false,
		"doors": [["s", -1.0, 0], ["n", -1.0, 0]],
		"roof_deck": false,
	})
	for i in range(3):
		b.cyl(Vector3(AIRLOCK.end.x - 1.2, MAIN_Y + 1.1, AIRLOCK.position.y + 1.4 + i * 1.9), 0.5, 2.2,
			MatLib.hazard_stripe(), "hull", Vector3.ZERO, -1.0, 12, true)
	# Stair from the main deck to the lab roof and on to the mud-house roof.
	# THE CONTROL ROOM. Glazed, on the lab roof, looking straight at the drill floor — this
	# is where the last shift's readouts are frozen mid-alarm.
	KIT.lookout(b, Rect2(LAB.position.x + 3.0, LAB.position.y + 3.0, 11.0, 8.0), LAB_ROOF, 3.2,
		{"door": "w", "door_at": -19.0, "floor": false})
	KIT.stair(b, Vector3(8.0, MAIN_Y, -10.4), Vector3(8.0, 23.3, -14.85), 1.6, true, true)
	# The second flight climbs OUTSIDE the lab's west wall (x 8.6) — at x 10.4 it ascended
	# underneath the very roof slab it serves and popped through it — then aprons in through
	# the roof rail's west gap.
	KIT.stair(b, Vector3(8.6, 23.3, -16.75), Vector3(8.6, LAB_ROOF, -21.75), 1.6, true, true)
	# Landing platform BEYOND the first flight's head, not centred on it — centred, its
	# slab edge overhung the arriving climb.
	b.box(Vector3(8.3, 23.18, -16.1), Vector3(2.6, 0.24, 2.5), MatLib.grating(), "hull", Vector3.ZERO, true)
	# BEYOND the head (z -22.3), not centred on it — centred, its slab overhung the climb.
	KIT.catwalk(b, Vector3(8.6, LAB_ROOF, -22.3), Vector3(10.6, LAB_ROOF, -22.3), 1.2, false)

## THE INSIDES OF DEEPWELL. `_buildings()` has raised the shaker house, the core lab, the
## control room and the decon airlock since this rig was first laid out, and every one of
## them has been an EMPTY SHELL ever since — four walls, a floor, a door, nothing on it.
## KNOWN_ISSUES has carried "interiors are empty shells" for the whole field since s54, and
## the control room is described in its own source comment two functions up as "where the
## last shift's readouts are frozen mid-alarm" while containing not one readout.
##
## MATERIAL DISCIPLINE. Every surface below is drawn with a material ALREADY LIVE on this
## rig — rust_steel, dark_metal, grating, painted_steel, galvanized, checker_plate,
## hazard_stripe, red_paint, the flat(0.22,0.20,0.16) earth tint the mud tanks use, and the
## two glowing() instances the crown beacon and the Bloom column already pay for. MatLib
## caches by colour, so re-asking for the same tint hands back the same instance and costs
## no new draw chunk. The field sits at 217/220 total and 150/150 FAR, and a room nobody can
## see from another platform must not spend either. Everything here is therefore in the
## "detail" group, which `Bake.flush` range-culls past DETAIL_DRAW_M and which the far
## budget does not count at all.
##
## THE ALARM IS THE STORY. Two console screens and the mud-log board carry the same
## glowing(0.9,0.12,0.1) red as the crown beacon: the shift left with the well shouting at
## them. It is the only saturated colour in any of these rooms, so it is the thing the eye
## lands on through the control-room glass from the drill floor.
static func _interiors(b: KIT.Bake) -> void:
	_control_room_fit(b)
	_core_lab_fit(b)
	_shaker_house_fit(b)
	_decon_fit(b)
	_drill_floor_dress(b)

## THE CONTROL ROOM, on the lab roof at 26.60, glazed toward the derrick. KIT.lookout laid
## its floor at LAB_ROOF and its door on the WEST side at z -19, so the consoles run down the
## west glass FACING OUT at the drill floor — which is what a driller's cabin is for, and it
## puts the lit screens where they read from outside.
static func _control_room_fit(b: KIT.Bake) -> void:
	var y: float = LAB_ROOF
	var steel: Material = MatLib.dark_metal()
	var galv: Material = MatLib.galvanized()
	var rust: Material = MatLib.rust_steel()
	var alarm: Material = MatLib.glowing(Color(0.95, 0.20, 0.14), 6.5)
	var readout: Material = MatLib.glowing(BLOOM_TEAL, 1.2)
	# The console bank: a plinth, a worktop, a raked fascia of switchgear. Split either side
	# of the door line (z -19) so nothing stands in the doorway.
	for seg in [[-22.4, -19.9], [-18.1, -15.6]]:
		var z0: float = float(seg[0])
		var z1: float = float(seg[1])
		var zc: float = (z0 + z1) * 0.5
		var len: float = z1 - z0
		b.box(Vector3(14.05, y + 0.36, zc), Vector3(0.95, 0.72, len), steel, "detail", Vector3.ZERO, true)
		b.box(Vector3(14.10, y + 0.78, zc), Vector3(1.15, 0.09, len + 0.1), galv, "detail")
		# Raked fascia — the bank of switches, tilted back toward whoever is standing at it.
		b.box(Vector3(14.30, y + 1.05, zc), Vector3(0.5, 0.36, len - 0.1), steel, "detail",
			Vector3(deg_to_rad(-32.0), 0, 0))
		var rows: int = int(len / 0.42)
		for i in range(rows):
			var lz: float = z0 + 0.28 + float(i) * 0.42
			b.box(Vector3(14.18, y + 1.13, lz), Vector3(0.06, 0.05, 0.16), MatLib.red_paint(), "detail")
	# THE SCREEN WALL, above the worktop, canted down at the operator. Two of the five are
	# still lit — the frozen alarm — and the rest are dead glass.
	for i in range(5):
		var sz: float = -21.8 + float(i) * 1.45
		if absf(sz + 19.0) < 0.7:
			continue                        # never across the door line
		var lit: bool = i == 1 or i == 3
		b.box(Vector3(14.55, y + 1.72, sz), Vector3(0.09, 0.62, 1.0), steel, "detail",
			Vector3(deg_to_rad(14.0), 0, 0))
		b.box(Vector3(14.47, y + 1.72, sz), Vector3(0.03, 0.52, 0.88),
			alarm if lit else readout, "lamp", Vector3(deg_to_rad(14.0), 0, 0))
	# Equipment racks down the blind east wall, and the mud-log chart board on the north.
	for i in range(3):
		var rx: float = 21.4 + 0.0
		var rz: float = -21.6 + float(i) * 2.2
		b.box(Vector3(rx, y + 1.0, rz), Vector3(0.72, 2.0, 1.6), steel, "detail", Vector3.ZERO, true)
		for k in range(4):
			b.box(Vector3(rx - 0.38, y + 0.6 + float(k) * 0.36, rz), Vector3(0.03, 0.06, 1.2), galv, "detail")
		b.box(Vector3(rx - 0.38, y + 1.86, rz), Vector3(0.03, 0.05, 0.3), alarm, "lamp")
	b.box(Vector3(19.0, y + 1.85, -15.35), Vector3(2.6, 1.4, 0.08), steel, "detail")
	b.box(Vector3(19.0, y + 1.85, -15.42), Vector3(2.4, 1.2, 0.03), alarm, "lamp")
	# A chair shoved back from the desk, and the overhead cable tray feeding the racks.
	b.cyl(Vector3(16.1, y + 0.24, -20.6), 0.28, 0.06, steel, "detail", Vector3.ZERO, -1.0, 10)
	b.cyl(Vector3(16.1, y + 0.42, -20.6), 0.05, 0.36, galv, "detail")
	b.box(Vector3(16.1, y + 0.64, -20.6), Vector3(0.46, 0.08, 0.46), rust, "detail", Vector3(0, deg_to_rad(24.0), 0), true)
	KIT.cable_tray(b, Vector3(15.4, y + 2.62, -22.2), Vector3(15.4, y + 2.62, -15.8))

## THE CORE SAMPLE LAB — two storeys inside LAB. Ground floor is the core store: rack after
## rack of drilled rock, which is the one object on this platform that explains what the
## Bloom is. Upper floor (23.30, reached by the external landing off the west wall, not by
## an internal stair — that is how `_buildings` laid the doors) is the log office.
static func _core_lab_fit(b: KIT.Bake) -> void:
	var steel: Material = MatLib.dark_metal()
	var galv: Material = MatLib.galvanized()
	var rust: Material = MatLib.rust_steel()
	var core_rock: Material = MatLib.flat(Color(0.22, 0.20, 0.16))
	var teal: Material = MatLib.glowing(BLOOM_TEAL, 1.2)
	var y: float = MAIN_Y
	b.box(Vector3(20.0, y + 0.02, -19.0), Vector3(19.3, 0.04, 13.3), MatLib.checker_plate(), "detail", Vector3.ZERO, true)
	b.box(Vector3(20.0, MAIN_Y + 3.32, -19.0), Vector3(19.3, 0.04, 13.3), MatLib.checker_plate(), "detail", Vector3.ZERO, true)
	# CORE RACKS down the south wall (z -25.7 inner face), three tiers, each tier carrying
	# split core in half-round trays. The north door is at x 20 and the west door at z -19,
	# so the racks stop clear of both approach lanes.
	for tier in range(3):
		var ry: float = y + 0.55 + float(tier) * 0.72
		b.box(Vector3(20.0, ry, -25.0), Vector3(15.0, 0.06, 0.86), galv, "detail", Vector3.ZERO, tier == 0)
		for i in range(7):
			var cx: float = 13.2 + float(i) * 2.3
			b.box(Vector3(cx, ry + 0.09, -25.0), Vector3(2.0, 0.12, 0.34), rust, "detail")
			# The core itself: a run of rock cylinders lying in the tray, broken into lengths.
			for k in range(4):
				b.cyl(Vector3(cx - 0.72 + float(k) * 0.48, ry + 0.16, -25.0), 0.055, 0.42,
					core_rock, "detail", Vector3(0, 0, deg_to_rad(90.0)), -1.0, 8)
	for px in [12.6, 20.0, 27.4]:
		b.box(Vector3(px, y + 1.1, -25.0), Vector3(0.1, 2.2, 0.9), steel, "detail", Vector3.ZERO, true)
	# THE PREP BENCH down the east wall: worktop, sink trough, and the specimen cylinders
	# that tie this room to the Bloom coming up the moon pool.
	b.box(Vector3(29.0, y + 0.45, -20.0), Vector3(0.9, 0.9, 9.0), galv, "detail", Vector3.ZERO, true)
	b.box(Vector3(29.0, y + 0.93, -20.0), Vector3(1.0, 0.07, 9.2), steel, "detail")
	b.box(Vector3(29.0, y + 0.86, -23.4), Vector3(0.7, 0.14, 1.2), steel, "detail")
	for i in range(4):
		var sz: float = -17.6 + float(i) * 1.5
		b.cyl(Vector3(28.9, y + 1.32, sz), 0.15, 0.72, MatLib.glass(Color(0.52, 0.62, 0.60)), "glass", Vector3.ZERO, -1.0, 10)
		b.cyl(Vector3(28.9, y + 1.14, sz), 0.13, 0.32, teal, "lamp", Vector3.ZERO, -1.0, 10)
		b.cyl(Vector3(28.9, y + 1.70, sz), 0.16, 0.05, steel, "detail", Vector3.ZERO, -1.0, 10)
	# Sample crates stacked by the north door, and the room's own light.
	for i in range(3):
		b.box(Vector3(15.0 + float(i) * 0.1, y + 0.3 + float(i) * 0.58, -13.6),
			Vector3(1.0, 0.56, 0.8), rust, "detail", Vector3(0, deg_to_rad(6.0 * float(i)), 0), i == 0)
	# ---- THE LOG OFFICE, upper floor at 23.30.
	var uy: float = MAIN_Y + 3.30
	b.box(Vector3(12.4, uy + 0.38, -20.0), Vector3(0.9, 0.76, 4.4), steel, "detail", Vector3.ZERO, true)
	b.box(Vector3(12.4, uy + 0.78, -20.0), Vector3(1.05, 0.06, 4.6), galv, "detail")
	# The chart table: a big raked drafting surface in the middle of the room, which is what
	# a well-log office is actually FOR.
	b.box(Vector3(20.0, uy + 0.42, -19.0), Vector3(2.6, 0.08, 1.5), galv, "detail",
		Vector3(deg_to_rad(-9.0), 0, 0), true)
	for lx in [-1.15, 1.15]:
		for lz in [-0.6, 0.6]:
			b.box(Vector3(20.0 + lx, uy + 0.21, -19.0 + lz), Vector3(0.07, 0.42, 0.07), steel, "detail")
	for i in range(3):
		b.box(Vector3(27.0, uy + 0.55, -22.0 + float(i) * 1.3), Vector3(0.6, 1.1, 1.0), galv, "detail", Vector3.ZERO, true)

## THE SHAKER HOUSE. MUD is 22 x 14 m and 6 m tall with no windows — the loudest, dirtiest
## room on the platform. Three shale shakers screen the returning mud, the pits hold what
## comes off them, and the agitators keep it from setting. Doors are east at z 17 and south
## at x -20, so the middle of the room stays a walking lane between them.
static func _shaker_house_fit(b: KIT.Bake) -> void:
	var steel: Material = MatLib.dark_metal()
	var rust: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	var grate: Material = MatLib.grating()
	var mud: Material = MatLib.flat(Color(0.22, 0.20, 0.16))
	var y: float = MAIN_Y
	# TWO WALKING LANES, AND NOTHING STANDS IN EITHER. The first cut of this room put both
	# mud pits across both doorways — the same defect as s61's sealed tank-farm bund wall,
	# found the same way, by walking a camera in and hitting a wall of steel 2 m inside the
	# door. Interior walls are x -30.72..-9.28 and z 10.28..23.72; the doors are EAST at
	# z 17 and SOUTH at x -20. So:
	#   SOUTH LANE — the full width of the room, z 10.28..14.6, clear from wall to wall.
	#   EAST LANE  — x -11.4..-9.28, the full depth, joining the east door to the south lane.
	# Everything below is placed north and west of those two, and the machinery order is the
	# real one: shakers screen the returns, launders drop them into the pits, the pits feed
	# the suction line back out to the pumps.
	const LANE_Z: float = 14.6      ## south lane ends here
	const LANE_X: float = -11.4     ## east lane starts here
	# THREE SHALE SHAKERS along the west wall, decks raked down toward the pits.
	for i in range(3):
		var sz: float = 16.0 + float(i) * 3.2
		b.box(Vector3(-27.6, y + 1.25, sz), Vector3(4.2, 1.1, 1.9), rust, "detail", Vector3(0, 0, deg_to_rad(-7.0)), true)
		b.box(Vector3(-27.6, y + 1.86, sz), Vector3(4.0, 0.06, 1.7), grate, "detail", Vector3(0, 0, deg_to_rad(-7.0)))
		# Spring mounts under each corner, and the out-of-balance motor that shakes it.
		for lx in [-1.7, 1.7]:
			for lz in [-0.8, 0.8]:
				b.cyl(Vector3(-27.6 + lx, y + 0.35, sz + lz), 0.11, 0.7, galv, "detail", Vector3.ZERO, -1.0, 8)
		b.cyl(Vector3(-27.6, y + 1.55, sz + 1.15), 0.32, 0.8, steel, "detail", Vector3(deg_to_rad(90.0), 0, 0), -1.0, 12)
		# The launder: what comes off the screen falls into the pit.
		b.box(Vector3(-24.6, y + 1.0, sz), Vector3(1.7, 0.4, 1.4), galv, "detail", Vector3(0, 0, deg_to_rad(-11.0)))
	# THE MUD PITS: two open tanks north of the south lane, the surface a still dark plane a
	# little below the rim. 5.0 x 7.6, so pit 2's east wall stops at -11.9, clear of the lane.
	for i in range(2):
		var px: float = -19.4 + float(i) * 6.0
		var z0: float = 15.2
		var z1: float = 22.8
		var zc: float = (z0 + z1) * 0.5
		for pz in [z0, z1]:
			b.box(Vector3(px, y + 0.8, pz), Vector3(5.0, 1.6, 0.16), rust, "detail", Vector3.ZERO, true)
		for sx in [px - 2.5, px + 2.5]:
			b.box(Vector3(sx, y + 0.8, zc), Vector3(0.16, 1.6, z1 - z0), rust, "detail", Vector3.ZERO, true)
		b.box(Vector3(px, y + 1.18, zc), Vector3(4.7, 0.04, z1 - z0 - 0.3), mud, "detail")
		# Agitator: a motor on a bridge over the pit with its shaft down into the mud.
		b.box(Vector3(px, y + 1.72, zc), Vector3(5.2, 0.14, 0.5), galv, "detail")
		b.box(Vector3(px, y + 2.0, zc), Vector3(0.7, 0.5, 0.6), steel, "detail")
		b.cyl(Vector3(px, y + 1.4, zc), 0.07, 1.2, galv, "detail")
	# Suction line off the pits, run down the SOUTH LANE's own wall at knee height and up the
	# east wall — along the lane, never across it.
	KIT.pipe_run(b, [Vector3(-16.0, y + 0.42, 10.9), Vector3(LANE_X + 0.9, y + 0.42, 10.9),
		Vector3(LANE_X + 0.9, y + 2.8, 10.9)], 0.22, rust)
	# The mixing hopper, against the south wall west of the door, with 2 m of lane north of it.
	b.cyl(Vector3(-26.8, y + 3.4, 11.9), 1.0, 1.6, galv, "detail", Vector3.ZERO, 0.25, 12, true)
	b.cyl(Vector3(-26.8, y + 1.9, 11.9), 0.26, 1.5, galv, "detail")
	# Barite sacks on a pallet in the south-east, out of both lanes.
	for i in range(6):
		var bx: float = -14.6 + float(i % 3) * 0.62
		var by: float = y + 0.22 + float(i / 3) * 0.34
		b.box(Vector3(bx, by, 12.1), Vector3(0.58, 0.3, 0.86), MatLib.corrugated(), "detail",
			Vector3(0, deg_to_rad(3.0 * float(i)), 0), true)

## THE DECON AIRLOCK at the stair head — the room the last shift would have come through.
## Doors face each other (south and north, both at x -1), so the centre line is a walking
## lane and everything stands against the two blind end walls.
static func _decon_fit(b: KIT.Bake) -> void:
	var steel: Material = MatLib.dark_metal()
	var galv: Material = MatLib.galvanized()
	var y: float = MAIN_Y
	b.box(Vector3(-1.0, y + 0.02, -27.5), Vector3(11.3, 0.04, 6.3), MatLib.checker_plate(), "detail", Vector3.ZERO, true)
	# Hazard lane between the two doors — this is a threshold, and it should read as one.
	b.box(Vector3(-1.0, y + 0.03, -27.5), Vector3(1.6, 0.04, 6.6), MatLib.hazard_stripe(), "detail")
	# Lockers down the west end, a bench facing them down the east.
	for i in range(4):
		b.box(Vector3(-5.6, y + 1.0, -29.4 + float(i) * 1.3), Vector3(0.62, 2.0, 1.2), galv, "detail", Vector3.ZERO, true)
		b.box(Vector3(-5.28, y + 1.0, -29.4 + float(i) * 1.3), Vector3(0.03, 1.9, 0.05), steel, "detail")
	b.box(Vector3(3.2, y + 0.44, -27.6), Vector3(0.7, 0.1, 4.4), galv, "detail", Vector3.ZERO, true)
	for lz in [-29.4, -25.8]:
		b.box(Vector3(3.2, y + 0.2, lz), Vector3(0.6, 0.44, 0.08), steel, "detail")
	# The shower: a head on a dropper over a trough drain, and the hose coiled on the wall.
	b.cyl(Vector3(3.4, y + 2.2, -24.9), 0.03, 0.9, galv, "detail")
	b.cyl(Vector3(3.4, y + 1.72, -24.9), 0.17, 0.06, steel, "detail", Vector3.ZERO, -1.0, 10)
	b.box(Vector3(3.4, y + 0.03, -24.9), Vector3(1.0, 0.05, 1.0), MatLib.grating(), "detail")
	b.cyl(Vector3(-6.4, y + 1.5, -25.4), 0.26, 0.16, MatLib.rust_steel(), "detail", Vector3(0, 0, deg_to_rad(90.0)), -1.0, 12)

## THE DRILL FLOOR, dressed. `_drill_substructure` laid the rotary, the drawworks and the
## driller's cabin as MASSING and stopped there, and the frame it produces is a big empty
## plate with a rusty disc in the middle. A drill floor is the densest working surface on a
## rig: this adds the hand tools that live on one, all of them clear of the rotary and of
## the two rail gaps (south and west) that are the way on and off.
static func _drill_floor_dress(b: KIT.Bake) -> void:
	var rust: Material = MatLib.rust_steel()
	var steel: Material = MatLib.dark_metal()
	var y: float = DRILL_Y + 0.25
	# TONGS, hung on their chains off the derrick legs — the shape that says "drill floor".
	for spec in [[-4.6, -6.2, 26.0], [4.6, -6.2, -26.0]]:
		var tx: float = float(spec[0])
		var tz: float = float(spec[1])
		var yaw: float = deg_to_rad(float(spec[2]))
		b.member(Vector3(tx, y + 4.6, tz), Vector3(tx, y + 1.35, tz), 0.035, steel, "detail")
		b.box(Vector3(tx, y + 1.15, tz), Vector3(1.5, 0.16, 0.42), rust, "detail", Vector3(0, yaw, 0), true)
		b.cyl(Vector3(tx + cos(yaw) * 0.62, y + 1.15, tz - sin(yaw) * 0.62), 0.3, 0.2, rust, "detail", Vector3.ZERO, -1.0, 10)
	# Slips and the mud bucket, laid down beside the rotary where they are set aside.
	b.cyl(Vector3(-3.9, y + 0.14, 1.9), 0.34, 0.28, steel, "detail", Vector3.ZERO, 0.6, 10, true)
	b.cyl(Vector3(3.6, y + 0.2, 2.6), 0.32, 0.4, rust, "detail", Vector3.ZERO, -1.0, 10, true)
	# A stand of pipe leaned into the corner, and a tool chest against the drawworks.
	for i in range(3):
		b.cyl(Vector3(9.4 + float(i) * 0.34, y + 2.6, 8.6), 0.09, 5.4, rust, "detail",
			Vector3(deg_to_rad(9.0), 0, deg_to_rad(4.0 + float(i))), -1.0, 8)
	b.box(Vector3(-9.6, y + 0.42, 0.6), Vector3(1.5, 0.84, 0.7), MatLib.red_paint(), "detail", Vector3.ZERO, true)
	b.box(Vector3(-9.6, y + 0.86, 0.6), Vector3(1.55, 0.06, 0.75), steel, "detail")

static func _access(b: KIT.Bake) -> void:
	# The ONLY way onto DEEPWELL that is not the bridge: a decon landing 2.6 m over the water
	# on the south face, and a stair tower standing OUTSIDE the deck footprint. It is outside
	# because the main slab has one hole in it and that hole is the moon pool.
	KIT.boat_landing(b, Vector3(0.0, 0.0, -46.0), 180.0, MAIN_Y, LOW_Y, 10.0, 6.0)
	KIT.stair_tower(b, STAIR_TOWER, LOW_Y, MAIN_Y, TOWER_RISE, true)
	KIT.catwalk(b, Vector3(0.0, LOW_Y, -43.4), Vector3(0.0, LOW_Y, -41.6), 2.4, true)
	KIT.catwalk(b, Vector3(0.0, MAIN_Y, -32.2), Vector3(0.0, MAIN_Y, -31.6), 3.0, false)
	var steel: Material = MatLib.rust_steel()
	# The tower stands on its own two legs down to the pontoon ring.
	for sx in [-3.6, 3.6]:
		for sz in [-41.6, -32.4]:
			b.member(Vector3(sx, LOW_Y - 1.0, sz), Vector3(sx * 0.55, 1.2, minf(sz + 8.0, -25.0)), 0.42, steel, "hull")
	# Perimeter walkway hung outside the deck rim on the west face — an "overpass" that lets
	# the player walk the outside of the platform and look up at the derrick.
	KIT.railed_walk(b, Vector3(-34.6, MAIN_Y - 2.6, -24.0), Vector3(-34.6, MAIN_Y - 2.6, 24.0), 1.6,
		[], [[18.4, 21.6]])
	# Deck-side end flush AT the slab edge (x -32.9): half a metre inboard, the flight's
	# final stretch collided with the deck slab's own side face.
	KIT.stair(b, Vector3(-32.9, MAIN_Y, -8.0), Vector3(-34.6, MAIN_Y - 2.6, -4.0), 1.5, true, true)
	for z in [-22.0, -10.0, 2.0, 14.0, 22.0]:
		b.member(Vector3(-34.6, MAIN_Y - 2.6, z), Vector3(-33.2, MAIN_Y - 0.4, z), 0.18, steel, "detail")

static func _bloom(b: KIT.Bake, host: Node3D) -> void:
	# THE FISSURE, as it reads from the platform. The light comes UP: off the water inside the
	# moon pool, up the conductor guides, onto the underside of the drill floor. It is the same
	# teal as underwater_world's Bloom palette, deliberately — this is one phenomenon, not two.
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(BLOOM_TEAL.r, BLOOM_TEAL.g, BLOOM_TEAL.b, 0.55)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.emission_enabled = true
	glow.emission = BLOOM_TEAL
	glow.emission_energy_multiplier = 2.2
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A still, luminous sheet just above the swell inside the pool. Above the ocean surface's
	# crests (which reach ~0.9) so the two never fight for the same depth.
	b.box(Vector3(0.0, 1.15, 0.0), Vector3(MOON.size.x - 0.6, 0.05, MOON.size.y - 0.6), glow, "glass")
	# And a deeper, dimmer one, so looking down the shaft reads as depth rather than a lid.
	var deep := StandardMaterial3D.new()
	deep.albedo_color = Color(BLOOM_TEAL.r * 0.5, BLOOM_TEAL.g * 0.7, BLOOM_TEAL.b * 0.7, 0.30)
	deep.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	deep.emission_enabled = true
	deep.emission = BLOOM_TEAL * 0.6
	deep.emission_energy_multiplier = 1.1
	deep.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	deep.cull_mode = BaseMaterial3D.CULL_DISABLED
	b.box(Vector3(0.0, -9.0, 0.0), Vector3(MOON.size.x - 1.6, 0.05, MOON.size.y - 1.6), deep, "glass")
	# Two lights: one in the pool throwing teal up onto the substructure, one under the deck.
	for spec in [[Vector3(0.0, 3.0, 0.0), 3.4, 30.0], [Vector3(0.0, 14.0, 0.0), 2.0, 22.0]]:
		var l := OmniLight3D.new()
		l.light_color = BLOOM_TEAL
		l.light_energy = float(spec[1])
		l.omni_range = float(spec[2])
		l.shadow_enabled = false
		l.add_to_group("bloom_lights")
		host.add_child(l)
		l.position = b.to_world(spec[0])

static func _lights(b: KIT.Bake, host: Node3D) -> void:
	# DEEPWELL's own lighting is cold and sparse — it is a machine, not a home. The derrick
	# gets the only real brightness, because that is where the eye must go from 415 m.
	# Deck-edge and under-deck cove — cold white, and sparse: DEEPWELL is a machine, not a
	# home, and the contrast against MARROW's sodium is legible from a bridge at night.
	var cold := Color(0.72, 0.86, 1.0)
	# Segmented around every rail gap — no glowing bar across the bridge or the stairs.
	var cy2: float = MAIN_Y + 0.85
	var s0: float = DECK.position.y + 0.8
	var n0: float = DECK.end.y - 0.8
	var w0: float = DECK.position.x + 0.8
	var e0: float = DECK.end.x - 0.8
	for seg in [[Vector3(w0, cy2, s0), Vector3(-6.0, cy2, s0)], [Vector3(2.0, cy2, s0), Vector3(3.0, cy2, s0)],
			[Vector3(13.0, cy2, s0), Vector3(18.0, cy2, s0)], [Vector3(25.0, cy2, s0), Vector3(e0, cy2, s0)],
			[Vector3(w0, cy2, n0), Vector3(-28.0, cy2, n0)], [Vector3(-18.0, cy2, n0), Vector3(18.0, cy2, n0)],
			[Vector3(w0, cy2, s0), Vector3(w0, cy2, -25.0)], [Vector3(w0, cy2, -17.0), Vector3(w0, cy2, -12.0)],
			[Vector3(w0, cy2, 0.0), Vector3(w0, cy2, n0)],
			[Vector3(e0, cy2, s0), Vector3(e0, cy2, 17.0)], [Vector3(e0, cy2, 24.0), Vector3(e0, cy2, n0)]]:
		KIT.led_cove(b, seg[0], seg[1], cold, 0.12, 2.6)
	# The moon-pool rim, lit from the deck so the shaft reads as a lit hole rather than a void.
	KIT.led_cove(b, Vector3(MOON.position.x - 0.4, MAIN_Y + 0.5, MOON.position.y - 0.4), Vector3(MOON.end.x + 0.4, MAIN_Y + 0.5, MOON.position.y - 0.4), cold, 0.1, 3.0)
	KIT.led_cove(b, Vector3(MOON.position.x - 0.4, MAIN_Y + 0.5, MOON.end.y + 0.4), Vector3(MOON.end.x + 0.4, MAIN_Y + 0.5, MOON.end.y + 0.4), cold, 0.1, 3.0)
	KIT.led_cove(b, Vector3(MOON.position.x - 0.4, MAIN_Y + 0.5, MOON.position.y - 0.4), Vector3(MOON.position.x - 0.4, MAIN_Y + 0.5, MOON.end.y + 0.4), cold, 0.1, 3.0)
	KIT.led_cove(b, Vector3(MOON.end.x + 0.4, MAIN_Y + 0.5, MOON.position.y - 0.4), Vector3(MOON.end.x + 0.4, MAIN_Y + 0.5, MOON.end.y + 0.4), cold, 0.1, 3.0)
	# The derrick, lit up its own legs so it is a lit tower and not a black one.
	for k in range(6):
		var dy: float = DRILL_Y + 4.0 + k * 10.0
		var hh: float = lerpf(DERRICK_BASE_HALF, DERRICK_TOP_HALF, clampf((dy - DRILL_Y) / (CROWN_Y - DRILL_Y), 0.0, 1.0))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				KIT.lamp_lens(b, Vector3(sx * hh, dy, sz * hh), Color(0.90, 0.94, 1.0), 0.3, 5.0)
	var pts: Array = [
		[Vector3(0.0, DRILL_Y + 6.0, 0.0), Color(0.86, 0.90, 0.96), 3.0, 34.0],
		[Vector3(0.0, MONKEY_Y + 2.0, 0.0), Color(0.86, 0.90, 0.96), 2.2, 26.0],
		[Vector3(-20.0, MAIN_Y + 6.0, 8.0), Color(0.95, 0.86, 0.70), 1.8, 22.0],
		[Vector3(18.0, MAIN_Y + 5.0, -18.0), Color(0.95, 0.86, 0.70), 1.8, 22.0],
		[Vector3(0.0, MAIN_Y + 4.0, -30.0), Color(0.90, 0.88, 0.82), 1.6, 18.0],
		[Vector3(-16.0, CELLAR_LOW + 3.4, -12.0), Color(0.96, 0.90, 0.78), 1.8, 24.0],
		[Vector3(16.0, CELLAR_LOW + 3.4, 10.0), Color(0.96, 0.90, 0.78), 1.8, 24.0],
		[Vector3(0.0, CELLAR_LOW + 3.4, 20.0), Color(0.96, 0.90, 0.78), 1.6, 22.0],
		[Vector3(-30.0, MAIN_Y + 4.0, 16.0), Color(0.88, 0.90, 0.96), 1.7, 24.0],
		[Vector3(20.0, LAB_ROOF + 2.0, -20.0), Color(0.88, 0.92, 1.0), 1.6, 22.0],
		[Vector3(0.0, CELLAR_Y + 2.0, -10.0), Color(0.90, 0.92, 0.98), 1.8, 22.0],
		# s64 — THE INTERIORS. Each of these rooms was an empty shell until this session and
		# none of them contained a light: the core lab's only nearby omni sat at y 25, ABOVE
		# its own 23.30 ceiling, which is why the first render of the core racks came back
		# almost black. A lamp_lens is emissive geometry and illuminates nothing; it is this
		# table, which pairs each lens with an OmniLight3D, that actually lights a room.
		# Ranges are sized to the room rather than to the deck.
		[Vector3(17.0, MAIN_Y + 2.9, -21.0), Color(0.88, 0.92, 1.0), 2.6, 19.0],    # core lab, west half
		[Vector3(25.0, MAIN_Y + 2.9, -17.0), Color(0.88, 0.92, 1.0), 2.3, 18.0],    # core lab, east half
		[Vector3(20.0, MAIN_Y + 5.9, -19.0), Color(0.88, 0.92, 1.0), 2.3, 17.0],    # the log office
		[Vector3(-20.0, MAIN_Y + 4.2, 16.0), Color(0.95, 0.86, 0.70), 1.9, 18.0],   # shaker house
		[Vector3(-27.0, MAIN_Y + 4.2, 13.0), Color(0.95, 0.86, 0.70), 1.5, 14.0],   # over the shakers
		[Vector3(-1.0, MAIN_Y + 2.4, -27.5), Color(0.90, 0.88, 0.82), 1.4, 11.0],   # decon airlock
	]
	for p in pts:
		KIT.lamp_lens(b, p[0], p[1], 0.7, 6.0)
		var l := OmniLight3D.new()
		l.light_color = p[1]
		l.light_energy = float(p[2])
		l.omni_range = float(p[3])
		l.shadow_enabled = false
		l.add_to_group("rig_field_floods")
		host.add_child(l)
		l.position = b.to_world(p[0])


# ---------------------------------------------------------------- THE PRODUCTION DECK

## y 11.30 — a full level between the pontoons and the main slab, wrapped round the moon
## pool. Its elevation is the FOURTH LANDING of the access tower (LOW_Y + 3 * TOWER_RISE),
## so the way down already exists and the number cannot drift.
##
## This is where a drilling platform keeps the things that are too heavy and too loud to be
## anywhere else: mud pumps, the cement unit, bulk tanks, the pipe galleries that feed the
## drill floor 19 m above.
static func _production_deck(b: KIT.Bake) -> void:
	KIT.deck_hole(b, CELLAR, MOON.grow(2.0), CELLAR_LOW, 0.36, MatLib.grating())
	KIT.rail_rect(b, CELLAR, CELLAR_LOW, [["s", -4.0, 4.0], ["w", -6.0, 6.0]], 0.35)
	KIT.rail_rect(b, MOON.grow(2.0), CELLAR_LOW, [], -0.25)
	var steel: Material = MatLib.rust_steel()
	for x in [-24.0, -8.0, 8.0, 24.0]:
		for z in [-24.0, 24.0]:
			b.member(Vector3(x, CELLAR_LOW, z), Vector3(x, 18.4, z), 0.3, steel, "hull")
	# MUD PUMPS: three enormous skids in a row, the loudest machines on any rig.
	for i in range(3):
		KIT.skid(b, Vector3(-22.0 + i * 8.0, CELLAR_LOW, -20.0), Vector3(7.4, 3.4, 4.6), 0.0)
	# Bulk cement and barite silos, vertical, feeding the mixing unit.
	for i2 in range(4):
		KIT.vessel(b, Vector3(-24.0 + i2 * 6.4, CELLAR_LOW, 18.0), 2.4, 6.6, true)
	KIT.skid(b, Vector3(4.0, CELLAR_LOW, 18.0), Vector3(6.0, 3.0, 4.0), 0.0)
	# Horizontal bulk tanks and an exchanger bank on the east side.
	for i3 in range(2):
		KIT.vessel(b, Vector3(20.0, CELLAR_LOW, -6.0 + i3 * 10.0), 2.0, 12.0, false, 90.0)
	KIT.exchanger_bank(b, Vector3(-20.0, CELLAR_LOW, 2.0), 3, 8.0, 90.0)
	KIT.manifold(b, Vector3(0.0, CELLAR_LOW, -25.0), 12.0, 3.6, 0.0)
	KIT.manifold(b, Vector3(-25.0, CELLAR_LOW, -8.0), 8.0, 3.4, 90.0)
	# Pipe galleries and trays right round the pool, plus an overhead route.
	for z2 in [-16.0, 14.0]:
		KIT.pipe_rack(b, Vector3(-25.0, CELLAR_LOW + 4.6, z2), Vector3(25.0, CELLAR_LOW + 4.6, z2), 6, 3.4)
	KIT.cable_tray(b, Vector3(-25.0, CELLAR_LOW + 5.6, -11.0), Vector3(25.0, CELLAR_LOW + 5.6, -11.0))
	KIT.cable_tray(b, Vector3(-25.0, CELLAR_LOW + 5.6, 9.0), Vector3(25.0, CELLAR_LOW + 5.6, 9.0))
	KIT.railed_walk(b, Vector3(-24.0, CELLAR_LOW + 3.3, -16.0), Vector3(24.0, CELLAR_LOW + 3.3, -16.0), 1.6,
		[[4.4, 7.6]], [])
	KIT.catwalk(b, Vector3(-24.0, CELLAR_LOW + 3.3, 14.0), Vector3(24.0, CELLAR_LOW + 3.3, 14.0), 1.6, true, CELLAR_LOW)
	KIT.catwalk(b, Vector3(-24.0, CELLAR_LOW + 3.3, -16.0), Vector3(-24.0, CELLAR_LOW + 3.3, 14.0), 1.6, true, CELLAR_LOW)
	KIT.catwalk(b, Vector3(24.0, CELLAR_LOW + 3.3, -16.0), Vector3(24.0, CELLAR_LOW + 3.3, 14.0), 1.6, true, CELLAR_LOW)
	# Head ON the z -16 catwalk — the old flight ended at z -10, in mid-air.
	KIT.stair(b, Vector3(-18.0, CELLAR_LOW, -9.0), Vector3(-18.0, CELLAR_LOW + 3.3, -15.4), 1.5, true, true)
	# The link from the access tower's fourth landing onto this deck.
	KIT.catwalk(b, Vector3(0.0, CELLAR_LOW, -32.0), Vector3(0.0, CELLAR_LOW, -26.6), 2.6, true)
	# Standpipe risers up to the drill floor.
	for x2 in [-6.6, 6.6]:
		KIT.pipe_run(b, [Vector3(x2, CELLAR_LOW + 1.0, -8.5), Vector3(x2, DRILL_Y - 0.8, -8.5)], 0.3)
	for i4 in range(9):
		KIT.lamp_lens(b, Vector3(-24.0 + i4 * 6.0, CELLAR_LOW + 5.2, -11.0), Color(0.96, 0.88, 0.72), 0.42, 4.5)
		KIT.lamp_lens(b, Vector3(-24.0 + i4 * 6.0, CELLAR_LOW + 5.2, 9.0), Color(0.96, 0.88, 0.72), 0.42, 4.5)

## An OUTBOARD CATWALK RING at y 23.6, hung off the main deck's rim all the way round, with
## four stairs onto it. It is the route that lets a player walk the outside of the platform
## and look up the derrick — and it is what gives DEEPWELL a second silhouette line.
static func _mezzanine(b: KIT.Bake) -> void:
	var o: float = 2.4
	var x0: float = DECK.position.x - o
	var x1: float = DECK.end.x + o
	var z0: float = DECK.position.y - o
	var z1: float = DECK.end.y + o
	# railed_walk with inner-rail gaps at the four stair arrivals (outer rails solid).
	KIT.railed_walk(b, Vector3(x0, MEZZ_Y, z0), Vector3(x1, MEZZ_Y, z0), 1.8, [[59.8, 63.0]], [])
	KIT.railed_walk(b, Vector3(x0, MEZZ_Y, z1), Vector3(x1, MEZZ_Y, z1), 1.8, [], [[7.8, 11.0]])
	KIT.railed_walk(b, Vector3(x0, MEZZ_Y, z0), Vector3(x0, MEZZ_Y, z1), 1.8, [], [[7.8, 11.0]])
	KIT.railed_walk(b, Vector3(x1, MEZZ_Y, z0), Vector3(x1, MEZZ_Y, z1), 1.8, [[59.8, 63.0]], [])
	var steel: Material = MatLib.rust_steel()
	for t in [-28.0, -14.0, 0.0, 14.0, 28.0]:
		for side in [[Vector3(x0, MEZZ_Y, t), Vector3(DECK.position.x + 0.6, MAIN_Y + 0.2, t)],
				[Vector3(x1, MEZZ_Y, t), Vector3(DECK.end.x - 0.6, MAIN_Y + 0.2, t)],
				[Vector3(t, MEZZ_Y, z0), Vector3(t, MAIN_Y + 0.2, DECK.position.y + 0.6)],
				[Vector3(t, MEZZ_Y, z1), Vector3(t, MAIN_Y + 0.2, DECK.end.y - 0.6)]]:
			b.member(side[0], side[1], 0.2, steel, "detail")
	for spec in [[Vector3(DECK.position.x + 1.4, MAIN_Y, -20.0), Vector3(x0 + 0.85, MEZZ_Y, -26.0)],
			[Vector3(DECK.end.x - 1.4, MAIN_Y, 20.0), Vector3(x1 - 0.85, MEZZ_Y, 26.0)],
			[Vector3(-20.0, MAIN_Y, DECK.end.y - 1.4), Vector3(-26.0, MEZZ_Y, z1 - 0.85)],
			[Vector3(20.0, MAIN_Y, DECK.position.y + 1.4), Vector3(26.0, MEZZ_Y, z0 + 0.85)]]:
		KIT.stair(b, spec[0], spec[1], 1.6, true, true)
	for i in range(16):
		var t2: float = float(i) / 15.0
		KIT.lamp_lens(b, Vector3(lerpf(x0, x1, t2), MEZZ_Y + 1.4, z0), Color(0.94, 0.90, 0.82), 0.34, 4.5)
		KIT.lamp_lens(b, Vector3(lerpf(x0, x1, t2), MEZZ_Y + 1.4, z1), Color(0.94, 0.90, 0.82), 0.34, 4.5)
		KIT.lamp_lens(b, Vector3(x0, MEZZ_Y + 1.4, lerpf(z0, z1, t2)), Color(0.94, 0.90, 0.82), 0.34, 4.5)
		KIT.lamp_lens(b, Vector3(x1, MEZZ_Y + 1.4, lerpf(z0, z1, t2)), Color(0.94, 0.90, 0.82), 0.34, 4.5)
