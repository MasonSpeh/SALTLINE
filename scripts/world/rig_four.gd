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
const FLARE_ROOT: float = 26.00

# ---------------------------------------------------------------------- plan (metres)

## Eight caissons: 7 m square at the corners, 5 m square mid-side. Heavy, black, over-scaled.
const LEG_CORNER_HALF: float = 3.50
const LEG_MID_HALF: float = 2.50
const LEG_SPAN: float = 24.00

const DECK := Rect2(-33.0, -33.0, 66.0, 66.0)
const MOON := Rect2(-6.0, -6.0, 12.0, 12.0)        ## open to the fissure, through every deck
const SUB := Rect2(-12.0, -12.0, 24.0, 24.0)       ## drill substructure footprint

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
	_drill_substructure(b)
	_derrick(b)
	_process(b)
	_buildings(b)
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
		["w", -12.0, 0.0],     # west rim fishing gap
		["n", 18.0, 33.0],     # crane slew arc
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
	KIT.stair(b, Vector3(0.0, MAIN_Y, -20.0), Vector3(0.0, DRILL_Y, -13.0), 2.4, true, true)
	for i in range(9):
		b.member(Vector3(-10.0 + i * 1.1, MAIN_Y + 0.6, -24.0), Vector3(-10.0 + i * 1.1, DRILL_Y - 0.4, -12.6), 0.28, MatLib.rust_steel(), "detail")

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
	# Standpipe and the kelly hose running up the derrick's south face.
	KIT.pipe_run(b, [Vector3(0.0, DRILL_Y + 1.0, -DERRICK_BASE_HALF + 0.6),
		Vector3(0.0, MONKEY_Y - 4.0, -DERRICK_TOP_HALF - 2.6)], 0.3)

static func _process(b: KIT.Bake) -> void:
	# Mud pits: four open tanks with an agitator on each, plus the shale shakers.
	for i in range(4):
		var x: float = -28.0 + i * 5.4
		b.box(Vector3(x, MAIN_Y + 1.9, 6.0), Vector3(4.8, 3.8, 7.0), MatLib.rust_steel(), "hull", Vector3.ZERO, true)
		b.box(Vector3(x, MAIN_Y + 4.0, 6.0), Vector3(4.4, 0.4, 6.6), MatLib.flat(Color(0.22, 0.20, 0.16)), "hull")
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
		"roof_gaps": [["w", -22.0, -16.0]],
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
	KIT.stair(b, Vector3(8.0, MAIN_Y, -10.4), Vector3(8.0, 23.3, -15.4), 1.6, true, true)
	KIT.stair(b, Vector3(10.4, 23.3, -15.4), Vector3(10.4, LAB_ROOF, -20.4), 1.6, true, true)
	b.box(Vector3(9.2, 23.18, -15.4), Vector3(4.4, 0.24, 2.0), MatLib.grating(), "hull", Vector3.ZERO, true)

static func _access(b: KIT.Bake) -> void:
	# The ONLY way onto DEEPWELL that is not the bridge: a decon landing 2.6 m over the water
	# on the south face, and a stair tower standing OUTSIDE the deck footprint. It is outside
	# because the main slab has one hole in it and that hole is the moon pool.
	KIT.boat_landing(b, Vector3(0.0, 0.0, -46.0), 180.0, MAIN_Y, LOW_Y, 10.0, 6.0)
	KIT.stair_tower(b, STAIR_TOWER, LOW_Y, MAIN_Y, 3.48, true)
	KIT.catwalk(b, Vector3(0.0, LOW_Y, -43.4), Vector3(0.0, LOW_Y, -41.6), 2.4, true)
	KIT.catwalk(b, Vector3(0.0, MAIN_Y, -32.2), Vector3(0.0, MAIN_Y, -31.6), 3.0, false)
	var steel: Material = MatLib.rust_steel()
	# The tower stands on its own two legs down to the pontoon ring.
	for sx in [-3.6, 3.6]:
		for sz in [-41.6, -32.4]:
			b.member(Vector3(sx, LOW_Y - 1.0, sz), Vector3(sx * 0.55, 1.2, minf(sz + 8.0, -25.0)), 0.42, steel, "hull")
	# Perimeter walkway hung outside the deck rim on the west face — an "overpass" that lets
	# the player walk the outside of the platform and look up at the derrick.
	KIT.catwalk(b, Vector3(-34.6, MAIN_Y - 2.6, -24.0), Vector3(-34.6, MAIN_Y - 2.6, 24.0), 1.6, true)
	KIT.stair(b, Vector3(-32.4, MAIN_Y, -22.0), Vector3(-34.6, MAIN_Y - 2.6, -18.0), 1.5, true, true)
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
	var pts: Array = [
		[Vector3(0.0, DRILL_Y + 6.0, 0.0), Color(0.86, 0.90, 0.96), 3.0, 34.0],
		[Vector3(0.0, MONKEY_Y + 2.0, 0.0), Color(0.86, 0.90, 0.96), 2.2, 26.0],
		[Vector3(-20.0, MAIN_Y + 6.0, 8.0), Color(0.95, 0.86, 0.70), 1.8, 22.0],
		[Vector3(18.0, MAIN_Y + 5.0, -18.0), Color(0.95, 0.86, 0.70), 1.8, 22.0],
		[Vector3(0.0, MAIN_Y + 4.0, -30.0), Color(0.90, 0.88, 0.82), 1.6, 18.0],
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
