extends Node3D
## RIG REALISM PASS (release dressing) — the working clutter a production platform
## actually carries, laid into the areas the sonar density map measured as EMPTY so the
## whole rig reads evenly dressed instead of busy-in-patches. Inspiration is the real
## thing: pipe racks and cargo baskets on the open working deck, life-raft canisters
## and gooseneck vents along the rims, a windsock, riser clamps up a leg, cable runs
## under the plate, HVAC on the roofs. NOTHING structural changes and every placement
## sits outside the walk lanes (spawn->stairs on the wet deck, the tower door and the
## boarding stairs topside), verified by StairWalkProbe / the power-route guard after.
##
## Empty cells this fills (sonar objects-per-4m-cell, measured 2026-07-24):
##   topside z-12..-4 x-8..+24 (the open working deck), the east rim x26..30,
##   the SE corner z+16.., the west rim x-30..-26 z+2..+10, wet deck x6..9 column,
##   wet deck south rim gaps, the stack roof, and the bare NE leg faces.
## All primitives carry MatLib PBR materials — no flat saturated albedo anywhere,
## per the "only realistic graphics" rule.

const DECK_Y: float = 18.0
const WET_Y: float = 2.0
const ROOF_STACK_Y: float = 32.1

func _ready() -> void:
	_pipe_racks()
	_cargo_baskets()
	_gas_rack()
	_liferaft_stations()
	_goose_vents()
	_windsock()
	_sat_dish()
	_rim_bollards()
	_drum_pallet()
	_nav_beacon_boxes()
	_wet_deck_manifold()
	_wet_deck_cable_tray()
	_wet_deck_vents()
	_leg_risers()
	_underdeck_runs()
	_roof_hvac()

# ---------------------------------------------------------------- topside deck

## Two-tier pipe racks mid-deck — the signature furniture of a working platform.
## The open band z-12..-4 measured near-zero objects across x-8..+24.
func _pipe_racks() -> void:
	for rx in [2.0, 14.0]:
		var a := _asm("PipeRack")
		var steel: Material = MatLib.rust_steel()
		var galv: Material = MatLib.galvanized()
		for ex in [-2.6, 0.0, 2.6]:                       # cradle frames
			_bx(a, Vector3(rx + ex, DECK_Y + 0.5, -9.5), Vector3(0.12, 1.0, 1.5), steel)
			_bx(a, Vector3(rx + ex, DECK_Y + 0.62, -9.5), Vector3(0.12, 0.1, 1.7), steel)
			_bx(a, Vector3(rx + ex, DECK_Y + 1.08, -9.5), Vector3(0.12, 0.1, 1.7), steel)
		for tier in [[0.72, 4], [1.18, 3]]:               # pipes, two tiers
			for i in range(int(tier[1])):
				var r: float = 0.09 + 0.03 * float(i % 2)
				_cy(a, Vector3(rx, DECK_Y + float(tier[0]), -10.1 + float(i) * 0.42),
					r, 6.4, galv if i % 2 == 0 else steel, Vector3(0, 0, 90))

## Offshore cargo baskets — wire-frame crates everything arrives in.
func _cargo_baskets() -> void:
	for spec in [[24.0, -10.0, 12.0], [8.0, -5.0, -25.0]]:
		var a := _asm("CargoBasket")
		a.rotation.y = deg_to_rad(float(spec[2]))
		var steel: Material = MatLib.painted_steel()
		var frame: Material = MatLib.rust_steel()
		a.position = Vector3(float(spec[0]), 0, float(spec[1]))
		_bx(a, Vector3(0, DECK_Y + 0.09, 0), Vector3(2.6, 0.18, 1.3), steel)   # skid base
		for cx in [-1.24, 1.24]:
			for cz in [-0.58, 0.58]:
				_bx(a, Vector3(cx, DECK_Y + 0.75, cz), Vector3(0.09, 1.3, 0.09), frame)
		for h in [0.55, 1.0, 1.38]:                       # rails
			_bx(a, Vector3(0, DECK_Y + h, -0.6), Vector3(2.56, 0.07, 0.07), frame)
			_bx(a, Vector3(0, DECK_Y + h, 0.6), Vector3(2.56, 0.07, 0.07), frame)
			_bx(a, Vector3(-1.26, DECK_Y + h, 0), Vector3(0.07, 0.07, 1.2), frame)
			_bx(a, Vector3(1.26, DECK_Y + h, 0), Vector3(0.07, 0.07, 1.2), frame)
		# Sling set gathered to a master link overhead — how a basket actually waits.
		#
		# 2026-07-27 bug: look_at_from_position() takes GLOBAL points, but this was passing
		# leg.position (LOCAL to `a`, which sits at spec[0]/spec[1] — e.g. (24,-10) or
		# (8,-5), not the origin) as if it were the global start, and an equally local
		# Vector3(cx2, ..., cz2) as the global target. look_at_from_position sets the
		# node's global position outright, so both baskets' four legs snapped to world
		# (~cx2*0.55, DECK_Y+1.95, ~cz2*0.55) — right on top of each other near the map
		# centre — instead of hanging over their own basket. The rest of each basket
		# (skid, frame, rails) uses ordinary local `_bx` positions so it stayed put; only
		# the legs, built with an explicit look_at, drifted. That is the "4 skinny ropes
		# floating mid-deck, nothing else around" report: two baskets' worth of orphaned
		# sling legs, stacked on each other a long way from either basket, with no load
		# and no basket in sight to explain them. Fixed by routing both points through
		# `a.to_global()` so the look-at is computed in world space like everywhere else.
		for cx2 in [-1.24, 1.24]:
			for cz2 in [-0.58, 0.58]:
				var leg := _bx(a, Vector3(cx2 * 0.55, DECK_Y + 1.95, cz2 * 0.55),
					Vector3(0.035, 1.3, 0.035), MatLib.dark_metal())
				leg.look_at_from_position(leg.global_position,
					a.to_global(Vector3(cx2, DECK_Y + 1.42, cz2)), Vector3.UP)
				leg.rotate_object_local(Vector3.RIGHT, PI / 2)

## Bottled-gas rack by the tower — cutting and purging gas lives outdoors in a cage.
func _gas_rack() -> void:
	var a := _asm("GasRack")
	a.position = Vector3(27.0, 0, 5.5)
	var frame: Material = MatLib.painted_steel()
	_bx(a, Vector3(0, DECK_Y + 0.06, 0), Vector3(1.9, 0.12, 0.9), frame)
	for fx in [-0.9, 0.9]:
		_bx(a, Vector3(fx, DECK_Y + 1.0, 0), Vector3(0.08, 1.9, 0.08), frame)
	_bx(a, Vector3(0, DECK_Y + 1.55, 0), Vector3(1.88, 0.08, 0.08), frame)
	_bx(a, Vector3(0, DECK_Y + 0.9, 0), Vector3(1.88, 0.06, 0.06), frame)
	var tanks: Array = [MatLib.rust_steel(), MatLib.galvanized(), MatLib.dark_metal()]
	for i in range(6):
		_cy(a, Vector3(-0.72 + float(i) * 0.29, DECK_Y + 0.85, 0.12 * (1 if i % 2 == 0 else -1)),
			0.125, 1.5, tanks[i % tanks.size()])
		_cy(a, Vector3(-0.72 + float(i) * 0.29, DECK_Y + 1.66, 0.12 * (1 if i % 2 == 0 else -1)),
			0.05, 0.14, MatLib.dark_metal())              # valve caps

## Life-raft canisters on tilted davit cradles along the rims — the white drums every
## platform carries at its muster edges.
func _liferaft_stations() -> void:
	# x -10.0 moved to -5.5: the south-rim canister stood dead centre of the empty davit
	# berth, and RigBuilder.BOAT_BERTH now puts the lifeboat's hull through it (0.19 m of
	# overlap in z, over the canister's whole length). -5.5 is the clear stretch between
	# the boat's east cap (-6.95) and the drill-floor apron (-2.70).
	for spec in [[-5.5, -19.1, 0.0], [12.0, 19.1, 180.0], [-28.8, 6.0, 90.0]]:
		var a := _asm("LifeRaftCanister")
		a.position = Vector3(float(spec[0]), 0, float(spec[1]))
		a.rotation.y = deg_to_rad(float(spec[2]))
		var steel: Material = MatLib.painted_steel()
		_bx(a, Vector3(0, DECK_Y + 0.35, 0), Vector3(1.5, 0.09, 0.7), MatLib.rust_steel())
		for cx in [-0.6, 0.6]:
			_bx(a, Vector3(cx, DECK_Y + 0.18, 0), Vector3(0.08, 0.36, 0.66), MatLib.rust_steel())
		var can := _cy(a, Vector3(0, DECK_Y + 0.66, 0), 0.34, 1.35, MatLib.dirty_white_panel(), Vector3(0, 0, 78))
		can.rotation.z = deg_to_rad(78)
		_cy(a, Vector3(0, DECK_Y + 0.66, 0), 0.345, 0.08, MatLib.dark_metal(), Vector3(0, 0, 78))
		_bx(a, Vector3(0.35, DECK_Y + 1.15, 0.36), Vector3(0.3, 0.2, 0.02), steel)  # instruction plate

## Gooseneck deck vents — the question-mark pipes that breathe the tanks below.
func _goose_vents() -> void:
	for spec in [[12.0, -14.5, DECK_Y], [26.0, -14.0, DECK_Y], [-6.0, 16.6, DECK_Y]]:
		var a := _asm("GooseVent")
		a.position = Vector3(float(spec[0]), 0, float(spec[1]))
		var y: float = float(spec[2])
		var galv: Material = MatLib.galvanized()
		_cy(a, Vector3(0, y + 0.06, 0), 0.3, 0.12, MatLib.rust_steel())
		_cy(a, Vector3(0, y + 0.8, 0), 0.11, 1.5, galv)
		_cy(a, Vector3(0.14, y + 1.62, 0), 0.11, 0.36, galv, Vector3(0, 0, 62))
		_cy(a, Vector3(0.34, y + 1.56, 0), 0.105, 0.3, galv, Vector3(0, 0, 118))
		_cy(a, Vector3(0.43, y + 1.42, 0), 0.115, 0.1, MatLib.dark_metal(), Vector3(0, 0, 118))

## The windsock — nothing says "offshore installation" faster, and the SE corner the
## helicopters would care about measured empty.
func _windsock() -> void:
	var a := _asm("Windsock")
	a.position = Vector3(26.0, 0, 18.4)
	var steel: Material = MatLib.galvanized()
	_cy(a, Vector3(0, DECK_Y + 2.6, 0), 0.06, 5.2, steel)
	_bx(a, Vector3(0, DECK_Y + 0.35, 0), Vector3(0.5, 0.7, 0.5), MatLib.rust_steel())
	_cy(a, Vector3(0, DECK_Y + 5.28, 0), 0.025, 0.9, steel, Vector3(0, 0, 90))
	# The sock: safety orange is a REAL windsock's colour — textured, not flat.
	var sock := _cy(a, Vector3(0.85, DECK_Y + 5.28, 0), 0.16, 1.15, MatLib.red_paint(), Vector3(0, 0, 90), 0.07)
	sock.rotation.z = deg_to_rad(90)

## Small dish + bracket on the BUNKHOUSE roof, aimed at the horizon like a real VSAT.
## It used to sit at (4, ·, 12) "on the galley roof" — but the accommodation stack (Deck
## B) was later built on top of the galley at y21.6, so this VSAT ended up poking up
## through the Deck B floor, standing in the corridor right in front of cabin B-02. The
## bunkhouse roof (x-28..-8, top y21.33) is genuine open sky — same plate the comms
## antenna and vent fans already stand on — so the dish reads correctly up there.
func _sat_dish() -> void:
	var a := _asm("SatDish")
	a.position = Vector3(-22.0, 0, 11.5)
	var y: float = 21.33   # bunkhouse roof top surface (DECK_Y 18 + WALL_H 3.2 + 0.13)
	_bx(a, Vector3(0, y + 0.25, 0), Vector3(0.7, 0.5, 0.7), MatLib.painted_steel())
	_cy(a, Vector3(0, y + 0.75, 0), 0.05, 0.6, MatLib.galvanized())
	var dish := _cy(a, Vector3(0.1, y + 1.1, 0), 0.55, 0.1, MatLib.dirty_white_panel(), Vector3.ZERO, 0.18)
	dish.rotation.z = deg_to_rad(52)
	_cy(a, Vector3(0.38, y + 1.22, 0), 0.02, 0.5, MatLib.dark_metal(), Vector3(0, 0, 128))

## Mooring bollards on the east rim — double-bitt castings clear of the tower hole.
func _rim_bollards() -> void:
	for bz in [-8.5, 4.5]:
		var a := _asm("Bollard")
		a.position = Vector3(29.5, 0, bz)
		var iron: Material = MatLib.dark_metal()
		_bx(a, Vector3(0, DECK_Y + 0.09, 0), Vector3(0.9, 0.18, 0.55), iron)
		for bx in [-0.22, 0.22]:
			_cy(a, Vector3(bx, DECK_Y + 0.42, 0), 0.13, 0.5, iron)
			_cy(a, Vector3(bx, DECK_Y + 0.66, 0), 0.17, 0.1, iron)

## An upright drum pair on a drip pallet — mid-deck consumables staging.
func _drum_pallet() -> void:
	var a := _asm("DrumPallet")
	a.position = Vector3(17.5, 0, -11.5)
	a.rotation.y = deg_to_rad(18)
	_bx(a, Vector3(0, DECK_Y + 0.07, 0), Vector3(1.7, 0.14, 1.1), MatLib.painted_steel())
	_bx(a, Vector3(0, DECK_Y + 0.16, 0), Vector3(1.6, 0.04, 1.0), MatLib.dark_metal())
	_cy(a, Vector3(-0.38, DECK_Y + 0.62, 0.02), 0.31, 0.9, MatLib.rust_steel())
	_cy(a, Vector3(0.42, DECK_Y + 0.62, -0.05), 0.31, 0.9, MatLib.galvanized())
	_cy(a, Vector3(0.42, DECK_Y + 1.09, -0.05), 0.05, 0.06, MatLib.dark_metal())

## Solar navigation-light boxes on two deck corners — the quiet yellow eyes a rig
## shows shipping. Lens is emissive glass, not a light: zero light-budget cost.
func _nav_beacon_boxes() -> void:
	for spec in [[29.4, 19.4, 0.0], [-29.4, -19.4, 180.0]]:
		var a := _asm("NavBeacon")
		a.position = Vector3(float(spec[0]), 0, float(spec[1]))
		a.rotation.y = deg_to_rad(float(spec[2]))
		_cy(a, Vector3(0, DECK_Y + 0.55, 0), 0.05, 1.1, MatLib.galvanized())
		_bx(a, Vector3(0, DECK_Y + 1.2, 0), Vector3(0.3, 0.3, 0.3), MatLib.painted_steel())
		_bx(a, Vector3(0, DECK_Y + 1.42, 0), Vector3(0.34, 0.05, 0.34), MatLib.dark_metal())
		_cy(a, Vector3(0, DECK_Y + 1.52, 0), 0.09, 0.16,
			MatLib.glowing(Color(0.95, 0.8, 0.3), 1.4))

# ---------------------------------------------------------------- wet deck

## Valve manifold on the pump-room east wall — where the pipe gallery would tie in.
func _wet_deck_manifold() -> void:
	var a := _wall_asm("WetManifold")
	a.position = Vector3(18.35, 0, -10.5)
	var steel: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	_bx(a, Vector3(0, WET_Y + 1.15, 0), Vector3(0.16, 1.3, 2.1), steel)
	for i in range(3):
		var vz: float = -0.7 + float(i) * 0.7
		_cy(a, Vector3(0.2, WET_Y + 1.15, vz), 0.09, 0.5, galv, Vector3(0, 0, 90))
		_cy(a, Vector3(0.42, WET_Y + 1.15, vz), 0.16, 0.07, MatLib.red_paint(), Vector3(0, 0, 90))
		_cy(a, Vector3(0.1, WET_Y + 0.5, vz), 0.09, 1.1, galv)

## An elevated cable tray running the empty west strip — the run from the pump room
## toward the boat landing that a real installation would never leave bare.
func _wet_deck_cable_tray() -> void:
	var a := _asm("WetCableTray")
	var steel: Material = MatLib.galvanized()
	var dark: Material = MatLib.dark_metal()
	for pz in [-9.0, -13.0, -17.0]:
		_bx(a, Vector3(7.2, WET_Y + 1.4, pz), Vector3(0.08, 2.8, 0.08), steel)
	_bx(a, Vector3(7.2, WET_Y + 2.82, -13.0), Vector3(0.42, 0.06, 8.6), steel)
	for lx in [-0.16, 0.16]:
		_bx(a, Vector3(7.2 + lx, WET_Y + 2.9, -13.0), Vector3(0.05, 0.1, 8.6), steel)
	for i in range(3):
		_cy(a, Vector3(7.13 + float(i) * 0.07, WET_Y + 2.88, -13.0), 0.028, 8.5, dark, Vector3(90, 0, 0))

## Two more gooseneck vents on the wet-deck south rim gaps.
func _wet_deck_vents() -> void:
	for vx in [16.4, 25.2]:
		var a := _asm("WetGooseVent")
		a.position = Vector3(vx, 0, -21.8)
		var galv: Material = MatLib.galvanized()
		_cy(a, Vector3(0, WET_Y + 0.05, 0), 0.26, 0.1, MatLib.rust_steel())
		_cy(a, Vector3(0, WET_Y + 0.65, 0), 0.1, 1.2, galv)
		_cy(a, Vector3(0.12, WET_Y + 1.32, 0), 0.1, 0.3, galv, Vector3(0, 0, 62))
		_cy(a, Vector3(0.28, WET_Y + 1.26, 0), 0.095, 0.26, galv, Vector3(0, 0, 118))

# ------------------------------------------------------- legs / under-deck / roofs

## Riser pipes clamped up the NE leg's east face — bare concrete on a production
## platform is where the risers run.
func _leg_risers() -> void:
	var a := _wall_asm("LegRisers")
	var galv: Material = MatLib.galvanized()
	var steel: Material = MatLib.rust_steel()
	for spec in [[11.0, 0.16], [12.0, 0.12], [13.2, 0.2]]:
		_cy(a, Vector3(25.28, 8.5, float(spec[0])), float(spec[1]), 17.0, galv)
	for cy in [3.0, 8.0, 13.0]:                            # clamp bands
		_bx(a, Vector3(25.28, cy, 12.1), Vector3(0.14, 0.3, 2.9), steel)

## Twin service runs slung under the topside plate — pipe and power crossing the void
## between the tower and the machine shop, silhouetted from the wet deck below.
func _underdeck_runs() -> void:
	var a := _wall_asm("UnderdeckRuns")
	var dark: Material = MatLib.dark_metal()
	var galv: Material = MatLib.galvanized()
	_cy(a, Vector3(3.0, 16.62, -6.3), 0.11, 33.0, galv, Vector3(0, 0, 90))
	_cy(a, Vector3(3.0, 16.66, -5.85), 0.07, 33.0, dark, Vector3(0, 0, 90))
	for hx in [-11.0, -3.0, 5.0, 13.0]:                    # hanger straps
		_bx(a, Vector3(hx, 16.82, -6.05), Vector3(0.08, 0.3, 0.75), MatLib.rust_steel())

## HVAC set on the accommodation-stack roof: unit, ducting, intake hood.
func _roof_hvac() -> void:
	var a := _asm("RoofHVAC")
	a.position = Vector3(12.0, 0, 11.5)
	var y: float = ROOF_STACK_Y + 0.15
	var panel: Material = MatLib.dirty_white_panel()
	var galv: Material = MatLib.galvanized()
	_bx(a, Vector3(0, y + 0.5, 0), Vector3(1.7, 1.0, 1.1), panel)
	_bx(a, Vector3(0, y + 1.03, 0), Vector3(1.74, 0.06, 1.14), MatLib.dark_metal())
	_cy(a, Vector3(0.45, y + 1.12, 0.25), 0.3, 0.12, MatLib.dark_metal())   # fan cowl
	_bx(a, Vector3(1.3, y + 0.35, 0), Vector3(0.9, 0.45, 0.45), galv)       # duct out
	_bx(a, Vector3(1.85, y + 0.6, 0), Vector3(0.45, 0.95, 0.45), galv)      # riser elbow
	_bx(a, Vector3(1.85, y + 1.18, 0), Vector3(0.6, 0.22, 0.6), galv)       # intake hood

# ============================================================ helpers
# Same conventions as exterior_dress.gd: assemblies are one Node3D in "dress_prop"
# (audited), wall/hung assemblies also "placement_exempt".

func _asm(n: String) -> Node3D:
	var a := Node3D.new()
	a.name = n
	a.add_to_group("dress_prop")
	add_child(a)
	return a

func _wall_asm(n: String) -> Node3D:
	var a := _asm(n)
	a.add_to_group("placement_exempt")
	return a

func _bx(p: Node3D, pos: Vector3, size: Vector3, mat: Material,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	p.add_child(mi)
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))
	return mi

func _cy(p: Node3D, pos: Vector3, r: float, h: float, mat: Material,
		rot: Vector3 = Vector3.ZERO, r_top: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if r_top < 0.0 else r_top
	m.height = h
	m.radial_segments = 12
	m.rings = 1
	m.material = mat
	mi.mesh = m
	p.add_child(mi)
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))
	return mi
