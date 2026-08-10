extends Node3D
## Lived-in dressing pass: stocks every room with the CC0 glTF prop library
## (PropLib) so the rig reads as a place people worked and left mid-shift, not a
## greybox. Coordinates trace the room anchors in rig_builder.gd / rig_superstructure.gd.
##
## PLACEMENT DOCTRINE (the feng shui pass):
##  - Furniture backs onto walls; only the galley mess tables, the rec-room low table and
##    the crew-lounge benches sit out in the room, with chairs round them and walking room.
##  - CORRIDORS ARE FOR WALKING. Nothing loose stands in a hallway; a corridor may keep
##    wall-line fittings only, and at least 1.2m of clear width.
##  - Small items sit ON surfaces — desks, counters, shelves, lockers, footlockers — never
##    on the floor in the middle of a living space.
##  - Hanging things (clocks, boards, frames, extinguishers, lamps) mount flush to walls
##    at believable heights and are declared with _pw so nothing tries to drop them.
##  - Every room gets a different mix, so quarters read individually lived-in.
##
## AUTO-SETTLE: authored Y is the intended surface top; the real resting height comes from
## SupportIndex, which resolves the surface under each item from VISUAL geometry after the
## whole world is built (see support_index.gd for why a physics raycast cannot do this).
## So a coordinate here only has to be RIGHT IN XZ and roughly right in Y.

const SignFit = preload("res://scripts/world/sign_fit.gd")   # by path: class cache lags new files
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
const SETTLE_PER_FRAME: int = 80

## Everything spawned, with the flag saying whether it should be rested on a surface.
## Wall-mounted and hanging dressing is recorded too, but only to be exempted.
var _placed: Array = []   # [node, settle: bool]

## Fired once every prop has streamed in AND settled onto its surface. RigBatcher waits
## for this before it merges dressing geometry: SupportIndex resolves the surface under
## each item from VISUAL meshes, so the merge must not run until the last item has landed.
signal settle_done
var settle_complete: bool = false

## Resolves what an object is standing on from drawn geometry rather than colliders.
const SUPPORT := preload("res://scripts/world/support_index.gd")

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
	_dining_hall()
	_bunkhouse()
	_rec_room()
	_machine_shop()
	_breaker_room()
	_deck_b_cabins()
	_deck_c_control()
	_deck_d_works()
	# Second pass — roughly doubles the density with the furniture/decor/plant
	# library so every room reads densely inhabited, not just sketched.
	_dining_hall_more()
	_dining_hall_kitchen()
	_bunkhouse_more()
	_rec_room_more()
	_machine_shop_more()
	_stack_more()
	# Third pass — small scattered PERSONAL / HOUSEHOLD clutter, placed on real surfaces.
	# Queued LAST so every supporting desk/shelf exists before an item lands on it.
	_scatter_wetdeck()
	_scatter_decka()
	_scatter_deckb()
	_scatter_deckc()
	_scatter_deckd()
	# The wet deck's natural stock — tar seams, barnacle crust, snagged floats,
	# kelp, the fish-cleaning board. Cheap CSG, so it goes up immediately.
	add_child(HARVEST_NODES.new())
	# Pull the dining hall's stray fittings into the composition documented above the
	# dining-hall section, and retire the room's old name. Safe to run here: rig_builder
	# calls _density_a() (which authors them) BEFORE it adds this node, so they exist.
	_dining_hall_layout()
	# Same contract for Breaker Room 4-A: rig_builder paints two wall stencils across the
	# panel and hangs the doorway sign inside its own frame. See _breaker_room_layout().
	_breaker_room_layout()
	# Same deal for the rec room: rig_builder authors a rug, two legless table tops,
	# a mid-air TV and a flat-colour bench block in there, and _decorate_rec_room() /
	# _density_a() both run before this node is added. See _rec_room_layout().
	_rec_room_layout()
	_stream()   # drain the queue across frames, then settle (runs as a coroutine)

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
		var wall: bool = item[5]
		var node: Node3D = null
		if FOOD_MAP.has(id):
			node = _make_food(id, FOOD_MAP[id], item[1], item[2], item[3])
		elif SALVAGE_TABLE.has_def(id):
			node = SALVAGE.from_prop(self, id, item[1], item[2], item[3], SALVAGE_TABLE.def(id))
		else:
			var mov: bool = PropLib.is_moveable(id)
			node = PropLib.spawn(id, self, item[1], item[2], item[3], item[4], -1.0, mov)
		_register(node, wall)
		i += 1
		if i % PER_FRAME == 0:
			await get_tree().process_frame
	_queue.clear()
	await _settle_all()
	if is_instance_valid(self):
		settle_complete = true
		settle_done.emit()

## Tag a spawned prop so the placement probe (and anything else) can tell dressing from
## structure, and so declared wall/hanging fittings are never pulled down onto a surface.
func _register(node: Node3D, wall: bool) -> void:
	if node == null:
		return
	node.add_to_group("dress_prop")
	if wall:
		node.add_to_group("placement_exempt")
	_placed.append([node, not wall])

## THE AUTO-SETTLE. Runs once, after every prop in the world exists, and rests each
## loose item on the visual surface actually beneath it. This is the root fix for the
## floating-prop class of bug: authored coordinates only have to be right in XZ.
##
## It deliberately does NOT use physics. Most dressing furniture here is drawn with
## non-colliding geometry, so a downward ray from a mug on a desk reports the deck 80cm
## below and snapping to it rains desk and shelf items onto the floor — that was tried,
## measured worse, and reverted. SupportIndex reads the same geometry the player sees.
func _settle_all() -> void:
	# Two passes. The index is a snapshot, and a pass shifts the very surfaces some items
	# were resolved against (a crate rises, so what stood on it should rise with it); the
	# second pass, over a freshly built index, catches the stragglers that leaves.
	for _pass in range(2):
		await _settle_pass()

func _settle_pass() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	var index = SUPPORT.new()
	index.build(root)
	# Lowest first, so an item stacked on another lands after the one under it.
	var jobs: Array = []
	var seen: Dictionary = {}
	for rec in _placed:
		if rec[1]:
			_add_job(jobs, seen, rec[0], false)
	# Pickups and props placed by the OTHER builders get the same treatment — a takeable
	# hanging in mid air is the same bug wherever it was authored. There we have no _pw
	# declaration to go on, so flat panels (wall-taped notes, scrawls, posted notices) are
	# recognised by shape and left alone.
	for n in _sweep(root):
		_add_job(jobs, seen, n, true)
	jobs.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	var i: int = 0
	var moved: int = 0
	for j in jobs:
		if absf(index.settle(j[1], j[2])) > 0.0:
			moved += 1
		i += 1
		if i % SETTLE_PER_FRAME == 0:
			await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		print("[settle] surfaces=%d  candidates=%d  corrected=%d" % [index.surface_count(), jobs.size(), moved])

func _add_job(jobs: Array, seen: Dictionary, n: Node3D, check_panel: bool) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return
	if seen.has(n.get_instance_id()) or n.is_in_group("placement_exempt"):
		return
	var a: AABB = SUPPORT.world_aabb_of_tree(n)
	if a.size == Vector3.ZERO or (check_panel and SUPPORT.is_wall_panel(a)):
		return
	seen[n.get_instance_id()] = true
	jobs.append([a.position.y, n, a])

## Everything else in the world worth resting on a surface: every pickup, container and
## readable, plus anything that opted in with the "settle_me" group.
func _sweep(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Takeable or n is LootContainer or n is Readable or n.is_in_group("settle_me"):
			if n is Node3D:
				out.append(n)
	return out

## A food/drink prop the player can pick up and eat. The real CC0 food model is the
## world visual on a Takeable that hands its items.json id to the pack; the settle pass
## rests it flush on whatever counter, table, or shelf is under it (missing model ->
## the labelled fallback crate, still takeable).
func _make_food(prop_id: String, item_id: String, pos: Vector3, yaw: float, sm: float) -> Node3D:
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
	return t

# ---- placement helpers ----
# Queue entry: [id, pos, yaw, scale, collide, wall_mounted]

func _p(id: String, pos: Vector3, yaw: float = 0.0, sm: float = 1.0) -> void:
	## A prop that rests on whatever is under it. pos.y is the surface top it belongs on.
	_queue.append([id, pos, yaw, sm, false, false])

func _pc(id: String, pos: Vector3, yaw: float = 0.0, sm: float = 1.0) -> void:
	## Colliding variant for big floor furniture the player should bump.
	_queue.append([id, pos, yaw, sm, true, false])

func _pw(id: String, pos: Vector3, yaw: float = 0.0, sm: float = 1.0) -> void:
	## WALL-MOUNTED or HANGING: a clock, frame, board, bracketed extinguisher, hung lamp.
	## Exempt from the settle — there is nothing under it and there is not meant to be.
	_queue.append([id, pos, yaw, sm, false, true])

## A small warm point light (jar lamp / worklight glow) — sparingly, for mood.
func _lamp(pos: Vector3, color: Color = Color(1.0, 0.82, 0.5), energy: float = 0.6, rng: float = 4.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos

## A MAINS ceiling fixture: dead in the blackout, warm once the master breaker in 4-A is
## closed. Same fixture and the same gate as rig_builder._mains_light (flush plate,
## housing, lens, an omni hung just under it, staggered through PowerGrid.queue_light so
## a whole rig's worth of lights never wake in one frame) — restated here rather than
## called across files because rig_builder's copy is private to that node. `pos` is the
## CEILING UNDERSIDE: the plate bolts to it and everything else hangs below.
func _mains_lamp(pos: Vector3, energy: float, rng: float) -> void:
	var dark: Material = MatLib.dark_metal()
	_wall_mesh(pos + Vector3(0, -0.03, 0), Vector3(0.52, 0.06, 0.26), dark)   # flush ceiling plate
	_wall_mesh(pos + Vector3(0, -0.13, 0), Vector3(0.5, 0.14, 0.22), dark)    # housing
	var lens: MeshInstance3D = _wall_mesh(pos + Vector3(0, -0.22, 0), Vector3(0.44, 0.06, 0.16),
		MatLib.flat(Color(0.85, 0.82, 0.72)))                                 # dark lens
	var lamp := OmniLight3D.new()
	lamp.omni_range = rng
	lamp.light_energy = energy
	lamp.light_color = Color(1.0, 0.93, 0.78)
	lamp.shadow_enabled = false
	lamp.visible = false                       # dead until the breaker closes
	add_child(lamp)
	lamp.global_position = pos - Vector3(0, 0.32, 0)
	lamp.add_to_group("interior_mains")
	PowerGrid.circuit_powered.connect(func(id: String) -> void:
		if id == "topside_floodlights" and is_instance_valid(lamp):
			PowerGrid.queue_light(func() -> void:
				if is_instance_valid(lamp):
					lamp.visible = true
					if is_instance_valid(lens):
						(lens.mesh as BoxMesh).material = MatLib.flat(Color(1.0, 0.96, 0.85), true, 2.0)))
	PowerGrid.circuit_lost.connect(func(id: String) -> void:
		if id == "topside_floodlights" and is_instance_valid(lamp):
			lamp.visible = false
			if is_instance_valid(lens):
				(lens.mesh as BoxMesh).material = MatLib.flat(Color(0.85, 0.82, 0.72)))

# ---- wet deck: the rigging bench & dock storeroom ----
# The rigging CraftBench sits at (25.0, 2.0, -17.5) with a 1.6 x 0.9 x 0.7 hull CENTRED on
# the deck, so its working top is y+0.45 and its footprint is x 24.2..25.8, z -17.85..-17.15.
# Everything laid on it has to be inside that rectangle or it hangs over bare deck — which
# is exactly what the gloves, hat, tin and oil can used to do.

func _wet_deck() -> void:
	var y: float = WET_Y
	var bench: float = y + 0.75   # bench top is y+0.45; the settle drops the rest
	# The bench top carries only what a job leaves out: the oil can and the wrench.
	# THE TOOLBOX IS NOT ON THE BENCH (owner playtest note) — see below.
	_p("small_oil_can_01", Vector3(25.5, bench, -17.72), 40)
	_p("pipe_wrench", Vector3(25.3, bench, -17.3), 200)
	# Tool chest parked against the storeroom's EAST face (x 16.125 + half depth),
	# drawers opening toward the bench walk. It used to float at x 26.7 — 10m of open
	# deck from the wall this comment always claimed it was against (sonar audit).
	_pc("metal_tool_chest", Vector3(16.35, y, -17.8), 90)
	# THE TOOLBOX: set down on the plating at the bench's WEST END, mid-job, long axis
	# along Z so it hugs the end face. Bench footprint is x 24.2..26.1, z -17.85..-17.15,
	# and the only two free flanks are the ends: the bench's SOUTH skirt carries the
	# painted "RIGGING BENCH" stencil (rig_builder, z -17.86) and its NORTH face has the
	# gooseneck worklight stanchion planted at x 25.0, so a box on either long side
	# either buries the paint or fouls the light. The west end leaves >1.5m of clear
	# plating on the walk line down to the SPHL gangplank (x 19.2..20.8, z -22.9).
	# Auto-settle drops it onto the deck plate.
	_pc("metal_toolbox", Vector3(23.9, y, -17.4), -90)
	# Jerry cans and a bucket by the storeroom wall.
	_pc("metal_jerrycan", Vector3(11.6, y, -21.4), 25)
	_pc("plastic_jerrycan", Vector3(12.2, y, -21.5), -40)
	_p("wooden_bucket_01", Vector3(12.9, y, -21.3), 0)
	# The bench worklight is a real anchored gooseneck fixture built in rig_builder
	# (_worklight_gooseneck), not a lamp hung from thin air over open deck.
	# Fire extinguisher bracketed by the stair door; a case of rations against the wall.
	_pw("korean_fire_extinguisher_01", Vector3(24.6, y + 0.55, -6.3), 180, 1.1)
	_p("long_life_food", Vector3(11.0, y + 0.02, -21.3), 20)

	# ---- THE PUMP ROOM, dressed as a pump room ----
	#
	# Owner, s36: "the pumproom is still awful, unfitting furniture". It was true and it was
	# ours: s35 read the room as a ready room somebody had moved into and gave it a VICTORIAN
	# DAY BED and a FOLDING WOODEN STOOL — the two most domestic pieces in the whole library
	# — in the one room on the rig whose entire subject is machinery. The premise those were
	# authored on ("the respawn point wakes up facing the east archway") was already false
	# when it was written: `wet_deck_respawn` reads (20.0, WET_Y + 0.6, -19.0), out on the
	# open deck by the SPHL dock, and s36 walled the archway up.
	#
	# The NORTH BAY is now plant stores, laid west-to-east along the north wall (interior
	# face z -6.125) with the gaps written down. rig_builder's dead pump moved into the NW
	# corner (PUMP_C, x 10.25..11.75 by z -7.95..-6.45) in the same pass, so it opens the
	# row; every piece after it is smaller than what it replaced or stands where the scan
	# already reported clear.
	#
	#   dead pump   x 10.25..11.75  z -7.95..-6.45   (rig_builder, not ours)
	#   lube drum   x 12.25..13.15  z -7.20..-6.30   0.50 m clear of the pump
	#   -- THE DOOR LANE, x 13.39..14.61, LEFT EMPTY TO THE NORTH WALL --
	#   works stool x 15.60..16.20  z -7.20..-6.60   0.99 m east of the lane
	#   tool cart   x 16.45..17.35  z -7.30..-6.40   0.25 m clear of the stool,
	#                                                0.53 m clear of the east wall
	# and the Sealed Crate (rig_builder, x 15.95..17.05, z -8.40..-7.60) keeps 0.40 m to the
	# stool and 0.30 m to the cart. The spares rack is deliberately NOT in this row: on the
	# north wall it would have to stand somewhere in x 13.15..15.60, and a 1.0 m rack there
	# lands on the door axis — which is exactly what the vintage day bed was doing (x
	# 13.35..15.25 off the live scan, i.e. straddling the lane and closing it to 0.00 m at
	# the north wall). It goes on the east wall instead, in the stores bay.
	_pc("Barrel_01", Vector3(12.7, y, -6.75), 0)                 # lube drum, on the silt drift
	# The stool is METAL now and it keeps s35's coordinates, which is deliberate: those were
	# measured off the live scan to clear the Sealed Crate by 0.36 m (KNOWN_ISSUES' open s18
	# intersection lives in this room), and metal_stool_01 is 0.60 m against the wooden
	# stool's 0.50, so the clearance it inherits is 0.31 m rather than a new guess.
	_pc("metal_stool_01", Vector3(15.9, y, -6.9), 30)
	_pc("tool_cart", Vector3(16.9, y, -6.85), 180)               # NE corner, out of the lane
	# Spares rack on the east wall (interior face x 17.875), in the bay the plan already
	# reserves for stores. x 17.45..17.85, z -10.00..-9.00: 0.60 m clear of the Sealed
	# Crate, 2.20 m from the lifebuoy's bracket, and 3.39 m of open floor west of it. That
	# wall was the ready-room archway until s36 walled it up, which is what freed it.
	_pc("steel_frame_shelves_01", Vector3(17.65, y, -9.5), -90)
	# THE BOLT CUTTERS, off the machine-shop bench (owner: spread the tools out). Seized bolts
	# are pipework's problem, the rack was standing empty, and a cutter STANDS — this prop's
	# mesh is 0.6 m tall on its long axis, so a rack is the one place upright reads right.
	# TWO measured numbers, not one: the same prop id on Deck D was measured with its top at
	# y+1.0 (see _deck_d_works), and this prop's ORIGIN sits 0.65 m ABOVE its mesh base — off
	# the sonar scan, where an authored y 18.96 put the mesh at 18.31..18.91. Authoring at the
	# surface top is therefore the bug, not the fix: it drops the base 0.65 m under the top,
	# support_top's rise allowance (base + half-height) can no longer see that surface, and
	# the settle picks whatever is BELOW it. That is exactly what had happened on the shop
	# bench — both this and the crowbar were standing on the bench's LOWER SHELF (top 18.305)
	# with their heads through the work top. +1.65 = rack top +1.0 plus the 0.65 offset, so
	# the base starts on the boards and the settle only has to nudge it.
	_p("bolt_cutters_01", Vector3(17.65, y + 1.65, -9.5), -90)
	_pc("worn_metal_rack", Vector3(10.38, y, -8.6), -90)         # rack flush on the west wall (face x 10.125)
	_p("medical_tape", Vector3(10.38, y + 1.3, -8.5), 30)        # first-aid on the rack shelf
	# Authored onto the rack shelf, but SupportIndex never sees the GLB's thin shelf
	# boards, so settle dropped it to the deck INSIDE the rack frame — a tote visibly
	# clipping through both rack rails (sonar overlap: 76% of its volume inside the
	# rack's AABB). On the deck beside the rack it settles clean. A can of oil rather than
	# a household tote: same 0.30 m size hint, so the clearance is unchanged.
	_p("oil_tin", Vector3(10.42, y + 0.02, -9.5), -37)
	_p("vintage_flashlight", Vector3(13.3, y + 0.02, -7.6), 70)  # set down on the deck mid-job
	_pw("lifebuoy", Vector3(17.82, y + 1.7, -12.2), -90, 1.1)    # east wall, faces the door
	_pw("life_jacket", Vector3(12.6, y + 1.5, -6.24), 180)       # on the north bulkhead, over the drum
	# The room light used to be a bare OmniLight floating 1m off the wall above the
	# cot — warm light from empty air. Now a pipe lamp on the north wall carries it.
	_pw("industrial_pipe_lamp", Vector3(14.3, y + 2.15, -6.3), 180)
	_lamp(Vector3(14.3, y + 1.95, -6.75), Color(1.0, 0.83, 0.5), 0.55, 4.5)

# ============================================================ THE DINING HALL
#
# (The room the rest of the codebase still calls the "galley" — see _dining_hall_layout()
# for the rename. Everything a PLAYER reads says Dining Hall.)
#
# THE ROOM, measured: interior x -1.875..13.875, z 8.125..17.875 — 15.75 x 9.75m, the
# biggest enclosed space on the rig. Kitchen-tile floor top y+0.05 (the overlay spans
# y+0.02..y+0.05, so anything standing on the deck seats its base at y+0.05, NOT y).
# Deckhead underside y+3.075; ceiling beams at y+2.95 on z 10.5 / 15.5; the service pipe
# run is on z 12.0 at y+2.7 — nothing of ours goes above y+2.6 except the extract duct,
# which is threaded between the beams on purpose. THE DOOR is in the south wall at x 6.
#
# FIXED FURNITURE (rig_builder's, not ours to author — only to compose around):
#   servery counter  x 1..11, z 16.4..17.6, top y+1.0
#   the range        x 10.85..12.15, z 15.6..16.8, top y+1.0   (CookStove)
#   the fridge       x -1.65..-0.75, z 14.75..15.65             (ColdStore)
#   pantry shelves   x -1.6, tops y+1.63 / y+2.23, z 10.9..14.1, cans on z 11.2/11.8/
#                    12.4/13.0/13.6 — leave those gaps alone
#   pan rail         x 8..11 at y+2.2, z 17.4, with the drying line just above it
#   FOUR MESS TABLES top y+0.49, 1.8 (x) x 1.0 (z), at (2,11) (8,11) (2,14.5) (8,14.5)
#
# THE COMPOSITION. The four fixed tables are already a 2 x 2 grid on x 2 / 8 and z 11 /
# 14.5, so the room is laid out AS that grid rather than against it:
#
#   THE AISLE. The south door at x 6 opens onto a 4.4m clear run straight up the middle
#   of the hall to the servery — x 2.77..7.23 has nothing in it at any point, because the
#   east chairs of the west tables stop at x 2.77 and the west chairs of the east tables
#   start at x 7.23. That aisle is the room: you walk in and see the whole kitchen.
#   THE CROSS LANE. Between the two table rows, z 12.15..13.35 — 1.2m, the minimum walk
#   width this file's placement doctrine allows — runs east-west from the pantry shelves
#   to the prep counter.
#   THE SEATING. Four chairs a table, one consistent set (painted_wooden_chair_01, the
#   same piece the rec room's conversation square uses; the old WoodenChair_01 run and
#   rig_builder's flat grey stool blocks are both gone — see _dining_hall_layout).
#   SOUTH ROW tables seat two a side, long-side only. NORTH ROW tables seat two on their
#   SOUTH side and one at each END — nobody sits with their back 60cm off the servery,
#   and it keeps a 1.4m service lane along the whole counter run.
#   THE KITCHEN is an L: rig_builder's servery counter along the north wall, and a new
#   prep counter down the east wall (x 12.675..13.825, z 11.7..15.1) with the coffee urn
#   and the pot rail on it. Wall shelves, the sink, the dish rack, the extract hood over
#   the range and the dry-goods rail all hang off those two runs.
#   LIGHT. Three mains fixtures on z 13 at x 1.8 / 6 / 10.2 (rig_builder owns the middle
#   one) — the hall used to have a single hot spot over the aisle with both ends of a
#   15.75m room in shadow. All three are on the same breaker.
#
# THE WEST BULKHEAD. Its inner face is x = -1.875 (wall centreline x -2, WALL_T 0.25) and
# it runs z 8.125..17.875. See _dining_hall_layout() for the composition; the zones it
# reserves are:
#   z  8.3..8.9   deck corner: the potted plant
#   z  8.95..10.15, y+1.38..y+2.18   the chalk/notice board (clear wall, nothing on it)
#   z  9.55, y+2.65                  the mess clock, centred over the board
#   z 10.5                           structural conduit drop (rig_builder) — leave alone
#   z 10.9..14.1, y+1.6 / y+2.2      the two pantry shelves and their can rows
#   z 11.85..13.35, y+2.65           the PAINTED stencil, on bare plate above the shelves
#   z 14.75..15.65                   the fridge
# The y+2.65 line is a deliberate datum: clock and paint share it, everything else sits
# below, so the wall reads as composed rather than piled.

## Repair the dining hall's stacked fittings, retire its old name, and clear out the
## seating the owner rejected.
##
## FOUR separate faults live in rig_builder and all four are fixed here rather than there:
##
##  1. THE BOARD AND THE STENCIL ARE AUTHORED AT THE SAME SPOT. _density_a() puts both at
##     (-1.86 / -1.82, DECK_Y+1.9, 12.5) — dead centre of the pantry-shelf run. The result
##     the owner photographed: painted lettering silk-screened across a dark notice board,
##     both shelves and both rows of cans cutting straight through the pair of them.
##  2. THE ROOM IS CALLED THE GALLEY. Two things say so where a player can read them: the
##     bulkhead stencil, and the display name on the south door ("OPEN Galley"). Both are
##     renamed to Dining Hall. (Nothing else in the room is user-visibly named — the range
##     and the fridge carry their own names, set in cook_stove.gd / cold_store.gd.)
##  3. EIGHT FLAT GREY STOOL BLOCKS. _density_a() drops a 0.4 x 0.48 x 0.4 untextured box
##     at each table's two ends as "stools at every table". They are the chairs the owner
##     asked to be rid of: a saturated flat albedo cube reads as a placeholder next to this
##     rig's textured steel and timber, and they stand exactly where the north tables' end
##     chairs belong. Freed, not moved — the real seating is authored in _dining_hall().
##
## Nothing here re-authors dressing; it moves, renames or removes existing nodes. This
## file editing other builders' output at runtime is an established pattern (see
## _settle_pass, which sweeps the whole tree). Every lookup is gated on an exact signature
## — position, size, text, display name — so if rig_builder is ever fixed at source this
## silently no-ops instead of fighting it. FOLD INTO rig_builder.gd AND DELETE FROM HERE
## when that file is next opened.
func _dining_hall_layout() -> void:
	var y: float = DECK_Y
	var host: Node = get_parent()
	if host == null:
		return
	# Table centres, so the grey stool blocks can be matched by where they stand.
	var tables := [Vector3(2, y, 11), Vector3(8, y, 11), Vector3(2, y, 14.5), Vector3(8, y, 14.5)]
	var junk: Array = []
	for n in host.get_children():
		if n is CSGBox3D:
			var b := n as CSGBox3D
			# The notice board: 0.05 x 0.8 x 1.2 slab buried in the shelf run.
			# Rehung on the clear south panel, back flush to the wall face (x -1.875).
			if b.size.is_equal_approx(Vector3(0.05, 0.8, 1.2)) \
					and b.position.distance_to(Vector3(-1.86, y + 1.9, 12.5)) < 0.05:
				b.position = Vector3(-1.85, y + 1.78, 9.55)
			# The eight flat-colour stool blocks, matched on size AND on standing at a
			# table end. Deleted: they are the seating this pass replaces.
			elif b.size.is_equal_approx(Vector3(0.4, 0.48, 0.4)):
				for tp in tables:
					if b.position.distance_to(tp + Vector3(-1.2, 0.24, 0)) < 0.05 \
							or b.position.distance_to(tp + Vector3(1.2, 0.24, 0)) < 0.05:
						junk.append(b)
						break
		# The stencil is PAINT. It moves up onto the bare plate above the shelves, on the
		# y+2.65 datum: clear of the upper shelf (top y+2.23, cans to y+2.41) and clear
		# of the ceiling beam that lands at y+2.82. 0.01 proud of the wall so it does not
		# z-fight the plate it is painted on. And it stops calling the room the galley.
		elif n is Label3D and (n as Label3D).text.contains("LAST MENU"):
			(n as Label3D).text = "DINING HALL — LAST MENU: STEW"
			n.position = Vector3(-1.865, y + 2.65, 12.6)
		# The south door's interaction prompt is the other place the old name is read.
		# The leaf hangs under a pivot Node3D (rig_builder._hang_door), so it is a
		# GRANDCHILD of the host — check the node and one level under it.
		elif n is InteractDoor:
			_rename_door(n as InteractDoor)
		else:
			for c in n.get_children():
				if c is InteractDoor:
					_rename_door(c as InteractDoor)
	for b in junk:
		(b as Node).queue_free()
	_galley_board_dressing()

func _rename_door(d: InteractDoor) -> void:
	if d.display_name == "Galley":
		d.display_name = "Dining Hall"

## Put something ON the notice board, and give the bare north end of the bulkhead a fitting.
##
## Moving the board out of the shelf pile-up fixed the overlap but left the wall SPACED
## rather than composed: the board photographed as a completely blank black rectangle with
## no notices, no paper and no pins — which reads as an unfinished placeholder, or worse, a
## hole cut in the bulkhead — and the whole north half of the plate was bare concrete.
##
## Board face is x -1.822 (slab centre -1.85, 0.05 thick), spanning z 8.95..10.15 and
## y+1.38..y+2.18. Everything below is hung a few millimetres proud of that face.
func _galley_board_dressing() -> void:
	var y: float = DECK_Y
	var face: float = -1.822
	var paper: Material = MatLib.flat(Color(0.86, 0.84, 0.76))
	var aged: Material = MatLib.flat(Color(0.78, 0.73, 0.58))
	var pin: Material = MatLib.flat(Color(0.72, 0.16, 0.12))
	# The duty rota, dead centre and squarely pinned: the one sheet that is still legible.
	_wall_mesh(Vector3(face - 0.004, y + 1.86, 9.55), Vector3(0.006, 0.42, 0.30), paper)
	for pz in [9.42, 9.68]:
		_wall_mesh(Vector3(face - 0.010, y + 2.04, pz), Vector3(0.012, 0.022, 0.022), pin)
	# Ruled lines on the rota, so it is a document rather than a white rectangle.
	for i in range(5):
		_wall_mesh(Vector3(face - 0.008, y + 1.98 - i * 0.055, 9.55),
			Vector3(0.004, 0.006, 0.24), MatLib.flat(Color(0.34, 0.33, 0.30)))
	# A smaller memo overlapping its corner, hung on ONE pin and curled off the board —
	# the detail that says paper has been here a long time in damp air.
	var memo: MeshInstance3D = _wall_mesh(Vector3(face - 0.014, y + 1.62, 9.94),
		Vector3(0.006, 0.24, 0.17), aged)
	memo.rotation.x = deg_to_rad(6.0)
	memo.rotation.z = deg_to_rad(-9.0)
	_wall_mesh(Vector3(face - 0.018, y + 1.71, 9.94), Vector3(0.012, 0.022, 0.022), pin)
	# A curled photograph high on the left, and a torn-off corner nobody took down.
	var photo: MeshInstance3D = _wall_mesh(Vector3(face - 0.012, y + 2.02, 9.13),
		Vector3(0.006, 0.15, 0.20), MatLib.flat(Color(0.42, 0.46, 0.44)))
	photo.rotation.z = deg_to_rad(4.0)
	_wall_mesh(Vector3(face - 0.016, y + 2.09, 9.13), Vector3(0.012, 0.020, 0.020), pin)
	_wall_mesh(Vector3(face - 0.008, y + 1.47, 9.20), Vector3(0.005, 0.09, 0.07), aged)
	# THE BARE NORTH PLATE (z 15.9..17.6): a fire blanket in its tab-pull pouch over a
	# stencilled panel. Standard galley kit, and the one thing that belongs on the wall
	# beside a range and a fridge.
	var pouch_z: float = 16.65
	_wall_mesh(Vector3(-1.845, y + 1.72, pouch_z), Vector3(0.10, 0.34, 0.26),
		MatLib.flat(Color(0.62, 0.13, 0.10)))
	_wall_mesh(Vector3(-1.795, y + 1.55, pouch_z), Vector3(0.02, 0.10, 0.05),
		MatLib.flat(Color(0.90, 0.88, 0.82)))   # the pull tab hanging out of the pouch
	_wall_mesh(Vector3(-1.868, y + 2.06, pouch_z), Vector3(0.006, 0.16, 0.30),
		MatLib.flat(Color(0.80, 0.78, 0.70)))   # instruction placard above it

## A bulkhead-mounted mesh: no collision, no shadow, and declared wall-fixed so the
## placement audit does not go looking for a floor under it.
func _wall_mesh(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.add_to_group("placement_exempt")
	return mi

## Stencilled paint on a surface — the same fitting rig_builder._plabel makes, restated
## here because that one is private to that node. Single-sided, unshaded by billboarding,
## and weathered toward charcoal the way every painted marking on this rig is: the source
## colour only says how FADED the lettering reads, never what colour it is.
## yaw 0 faces +Z, 180 faces -Z (this file's convention throughout).
func _paint(text: String, pos: Vector3, yaw: float, font_size: int = 12,
		wear: float = 0.6) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = maxi(12, int(font_size * 0.75))
	l.pixel_size = 0.01
	var k: float = lerpf(0.06, 0.17, clampf(wear, 0.0, 1.0))
	l.modulate = Color(k, k, k * 1.08, 0.9)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(l)
	l.global_position = pos
	l.rotation.y = deg_to_rad(yaw)
	l.add_to_group("placement_exempt")
	return l

## Built-in joinery: a carcass the player actually bumps into. Same shape as _wall_mesh
## but a colliding CSGBox3D, because a credenza you can walk through is scenery, not
## furniture. Exempt from the settle for the same reason a wall is — it IS the surface.
func _carcass(pos: Vector3, size: Vector3, mat: Material) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.material = mat
	b.use_collision = true
	add_child(b)
	b.global_position = pos
	b.add_to_group("placement_exempt")
	return b

## The four fixed mess-table centres. Restated NOWHERE else in this file — every chair,
## every tray and every mug in the hall is placed as an offset from one of these, so the
## seating cannot drift away from the tables it belongs to.
const MESS_TABLES := [Vector3(2, 0, 11), Vector3(8, 0, 11), Vector3(2, 0, 14.5), Vector3(8, 0, 14.5)]

func _dining_hall() -> void:
	var y: float = DECK_Y
	var counter: float = y + 1.2       # counter top is y+1.0
	_p("vintage_electric_kettle", Vector3(3.4, counter, 17.0), 180)
	_p("modified_thermos", Vector3(4.3, counter, 17.0), 150)
	_p("plastic_thermos", Vector3(5.1, counter, 17.0), -120)
	_p("russian_food_cans_01", Vector3(6.6, counter, 17.1), 10)
	_p("boombox", Vector3(9.0, counter, 17.1), 200)
	# Ration tins ON the wall shelves (tops y+1.63 / y+2.23), standing in the gaps BETWEEN
	# the can rows rather than half-off the shelf ends: the cans are r0.09 at z 11.2 /
	# 11.8 / 12.4 / 13.0 / 13.6, so the clear slots are centred 11.5 / 12.1 / 12.7 / 13.3
	# and are 0.42m wide. x -1.58 puts them mid-depth on the 0.35-deep boards.
	_p("long_life_food", Vector3(-1.58, y + 1.80, 12.1), 90)
	_p("cleaner_tin_01", Vector3(-1.58, y + 2.40, 13.3), 90)
	_p("modified_thermos", Vector3(8.5, y + 0.7, 11.3), 60)
	_p("russian_food_cans_01", Vector3(2.5, y + 0.7, 14.15), -30)
	# A trash can by the fridge, overflowing a little.
	_pc("metal_trash_can", Vector3(0.2, y, 16.6), 0)
	_mess_seating(y)

## THE SEATING. Sixteen chairs, one set, four to a table, squared to the table grid.
##
## The old arrangement was two WoodenChair_01 a table on the long sides plus eight flat
## grey blocks at the ends (rig_builder's, freed in _dining_hall_layout) — a mix of two
## kinds of seat, none of which the owner wanted, and eight of which were untextured
## primitives. This is one piece throughout: painted_wooden_chair_01, the same chair the
## rec room's conversation square is built from, which is the best-looking seat in the
## library and reads as furniture a supply boat landed rather than deck kit.
##
## Yaw convention (this file's, matching the rec room): 0 faces +Z, 90 faces +X.
##
## SOUTH ROW (z 11) seats two a side on the long faces. NORTH ROW (z 14.5) seats two on
## its SOUTH face and one at each END: the counter run is at z 16.4, and a chair on the
## north face would put a diner's back 0.7m off the servery and pinch the service lane
## to nothing. Ends instead — same chair count, and the lane along the whole counter
## stays 1.4m.
##
## Clearances this produces, all measured off a ~0.5m-square chair footprint:
##   the aisle from the south door:  x 2.77..7.23  = 4.46m clear, floor to servery
##   between the two table rows:     z 12.15..13.35 = 1.20m, the doctrine minimum
##   between the end chairs mid-room: x 3.53..6.47 = 2.94m
##   along the servery counter:      z 15.0..16.4  = 1.40m
func _mess_seating(y: float) -> void:
	var chair: String = "painted_wooden_chair_01"
	for tp in MESS_TABLES:
		var t := Vector3(tp.x, y, tp.z)
		# The south face of every table: two chairs, tucked to the long edge.
		for dx in [-0.52, 0.52]:
			_pc(chair, t + Vector3(dx, 0, -0.90), 0)
		if is_equal_approx(tp.z, 11.0):
			# South row — the north face is open floor, so it seats two there as well.
			for dx in [-0.52, 0.52]:
				_pc(chair, t + Vector3(dx, 0, 0.90), 180)
		else:
			# North row — the ends, so nobody sits with their back to the servery.
			_pc(chair, t + Vector3(-1.28, 0, 0.0), 90)
			_pc(chair, t + Vector3(1.28, 0, 0.0), -90)

# ---- bunkhouse ----
# Six bunks at z 6.5 (south row) / z 15.5 (north row), x -25.5 / -18.8 / -12.0.
#
# THE WARDROBE LOCKERS ARE ON THE HEAD WALL, NOT BESIDE THE BUNK. This comment used to
# say "a steel locker at bed + (1.2, *, -0.8)" and every locker-top coordinate in this
# file was derived from that offset. rig_builder._build_bunkhouse moved them: they are
# built by _wardrobe_locker at (bed.x + 1.15, y + 0.9, LOCK_Z) with LOCK_Z 4.55 for the
# south row and 17.45 for the north, because the old -0.8 z offset put the north-row
# lockers a metre out into the room. The visual is a 0.5 x 1.8 x 0.5 box centred on
# y+0.9, so the carcass runs y..y+1.8 and its resting plane measures y+1.86 (the lid
# stands a little proud) — that is LOCK_TOP below. A bed-relative z offset here is now
# a floating-prop bug, so every locker-top item anchors to (bed.x + 1.15, LOCK_Z).
#
# The FLOOR is not y either: the bunkhouse lino overlay spans y+0.02..y+0.05, so anything
# standing on the deck seats its base at y+0.05.
#
# THE CORRIDOR IS z 10..12 AND STAYS EMPTY — the sitting nook and the shared table that
# used to stand in it are now inside cabins.

## Bunk and locker anchors come from the SHARED layout module, not from a second copy of
## the numbers. Restating them here is exactly how six locker-top items ended up hovering
## where the lockers used to be, and lining the bunks up against the cabin walls would have
## broken the same six placements again. See bunk_layout.gd.
const BUNKS := preload("res://scripts/world/bunk_layout.gd")   # by path: class cache lags new files

## The locker top serving a given bunk. The top is 0.5m square, so items must land well
## inside +-0.25 of this in x and z — SurfaceSnap probes a single ray straight down from
## the ORIGIN, so an anchor near the edge misses the top and the item drops to the deck.
func _locker_top(bed: Vector3) -> Vector3:
	return BUNKS.locker_top(bed)

func _bunkhouse() -> void:
	var y: float = DECK_Y
	# Six single cabins (2 rows x 3): A/B/C west-to-east, south row (z4..10) and north
	# row (z12..18). Each has its bunk on the WEST side against the head wall and a
	# head-wall wardrobe (both built in rig_builder). This pass gives every cabin one
	# distinct, wall-aligned piece on the EAST side against the divider it shares — so
	# each reads as a different crew member's room, and nothing stands free in the middle.
	# East-divider interior faces: A x-21.455 · B x-14.785 · C x-8.125.
	var beds: Array = BUNKS.beds()   # shared with rig_builder — never restate these

	# --- A-S · the fitter: a work desk squared to the east divider, tools laid out. ---
	_pc("metal_office_desk", Vector3(-21.85, y, 6.6), -90)
	_pc("metal_stool_01", Vector3(-22.95, y, 6.6), 0)
	_p("retro_multimeter", Vector3(-21.95, y + 0.83, 6.35), 20)
	_p("binder_notebook", Vector3(-21.75, y + 0.83, 6.95), -25)

	# --- B-S · the cook's mate: a side table with the kettle he brewed on. ---
	_pc("small_wooden_table_01", Vector3(-15.15, y, 6.6), -90)
	_pc("folding_wooden_stool", Vector3(-16.25, y, 6.7), 15)
	_p("vintage_electric_kettle", Vector3(-15.2, y + 0.5, 6.35), 30)
	_p("modified_thermos", Vector3(-15.0, y + 0.5, 6.95), -40)

	# --- C-S · the young hand: a plant in the head/east corner, a stool and cassettes. ---
	_pc("fern_02", Vector3(-8.6, y, 5.0), 0)
	_pc("chinese_stool", Vector3(-8.55, y, 7.4), 0)
	_p("cassette_player", Vector3(-8.55, y + 0.46, 7.4), 30)

	# --- A-N · the reader: armchair angled to the corner, nightstand and books beside. ---
	# Sonar-measured nightstand top: x -21.982..-21.618, z 14.457..14.943, surface y+0.655.
	# The lantern used to sit at z 14.25 — 0.21m clear of the stand's front edge — so it
	# settled onto the deck while its lamp stayed up at y+1.0, which is the "floating fire"
	# beside the armchair. The book set anchors at its WEST end and runs +0.34m east, so
	# anchoring it at the stand's centre hung nine of its volumes over the far edge (sonar:
	# gap 0.61m). Both now sit inside the measured top, and the lamp sits INSIDE the lantern
	# body (top y+1.005) so the glow has a visible source. The book anchor keeps ~2cm of
	# margin from the stand's west edge because SurfaceSnap probes a single ray straight
	# down from the ORIGIN — an anchor flush to the edge can miss the top and drop the set.
	_pc("ArmChair_01", Vector3(-21.95, y, 13.3), 215)
	_pc("ClassicNightstand_01", Vector3(-21.8, y, 14.7), -90)
	_p("book_encyclopedia_set_01", Vector3(-21.96, y + 0.72, 14.80), 0)
	_p("Lantern_01", Vector3(-21.80, y + 0.72, 14.58), 0)
	_lamp(Vector3(-21.80, y + 0.95, 14.58), Color(1.0, 0.85, 0.55), 0.5, 4.0)

	# --- B-N · the radio op: the set squared on a table against the east divider. ---
	# ...and the ship's cat asleep on this cabin's bunk (ship_cat.HOME, derived from
	# bunk_layout). "Found near a light so she is illuminated in the dark" moved rooms with
	# her in s55 and nothing brought a light along: the reader's lantern next door is
	# BEHIND the cabin divider (CatSpawnProbe measured 0.000 lux at the mattress). A second
	# lantern on this bunk's own locker lid gives the sleeping cat her glow — locker centre
	# from bunk_layout, lamp INSIDE the lantern body like the reader's (source visible).
	# At the lid's BUNK-SIDE CORNER, not its centre: from the centre the sight line to the
	# mattress dips under the lid edge while still over the locker's own footprint, so the
	# locker eclipses its own lamp (measured — lux 0.000 on the first try).
	var cat_bed: Vector3 = BUNKS.bed_pos(1, false)
	var cat_lock: Vector3 = BUNKS.locker_top(cat_bed)
	_p("Lantern_01", Vector3(cat_lock.x - 0.14, cat_lock.y + 0.01, cat_lock.z - 0.14), 0)
	_lamp(Vector3(cat_lock.x - 0.14, cat_lock.y + 0.26, cat_lock.z - 0.14), Color(1.0, 0.85, 0.55), 0.5, 4.5)
	_pc("small_wooden_table_01", Vector3(-15.15, y, 15.0), -90)
	_pc("WoodenChair_01", Vector3(-16.3, y, 15.0), 90)
	_p("vintage_radio_transceiver", Vector3(-15.1, y + 0.5, 15.0), 200)

	# --- C-N · the bosun: a sea chest against the divider, kit stowed on the lid. ---
	_pc("drawer_cabinet", Vector3(-8.5, y, 15.0), -90)
	_p("binoculars", Vector3(-8.55, y + 0.95, 15.25), 20)
	_p("old_gas_mask", Vector3(-8.55, y + 0.95, 14.7), -30)

	# Each crew member's one keepsake on their head-wall wardrobe top, anchored through
	# _locker_top() so it tracks the real locker instead of a stale bed-relative offset.
	# Set slightly west/south of centre; _scatter_decka() puts the second item on the
	# opposite quarter of the same 0.5m square top, so the two never fight for the ray.
	# NOTE "decorative_book_set_01" was a phantom id — there is no such model in
	# assets/models, so PropLib handed back its labelled fallback CRATE and cabin C-S has
	# been showing a plain wooden box on the locker where a stack of books belongs.
	# book_encyclopedia_set_01 is the real set (the one bunk A-N already uses).
	var lock := ["ceramic_vase_01", "food_apple_01", "book_encyclopedia_set_01",
			"brass_goblets", "plastic_thermos", "round_spectacles"]
	for i in range(beds.size()):
		var lt: Vector3 = _locker_top(beds[i])
		_p(lock[i], lt + Vector3(-0.11, 0.09, -0.10), i * 33.0)
	# Corridor (z10..12) keeps only wall-hung items, between the cabin doors and clear of
	# the 1.2m walk lane: a fire point and a framed photo. Life jacket by the C-S door.
	_pw("korean_fire_extinguisher_01", Vector3(-15.0, y + 0.9, 10.2), 180, 1.1)
	_pw("fancy_picture_frame_02", Vector3(-21.0, y + 1.6, 11.8), 0)
	_pw("life_jacket", Vector3(-8.25, y + 1.5, 6.2), -90)

# ============================================================ rec room
#
# THE ROOM, measured (sonar): interior x 18.125..27.875, z 8.125..17.875 — 9.75m square.
# Floor working surface y+0.05 (the rubber overlay spans y+0.02..y+0.05, so anything
# standing on the deck seats its base at y+0.05, NOT y). Deckhead underside y+3.075;
# ceiling beams at y+2.95, service pipes at y+2.7, the pennant cord on z 12.9 — nothing
# of ours goes above y+2.6. THE WEST DOOR is the opening z 10.3..11.7 in the x18 wall.
#
# FIXED FURNITURE (built in rig_builder, not ours to author — only to compose around):
#   couch          x 21.8..24.2, z 8.7..9.7, seat top y+0.70
#   low table top  x 22.25..23.75, z 12.03..12.98, top y+0.32   (legged by _rec_room_layout)
#   floor rug      x 21.3..24.7, z 11.3..13.7                   (raised by _rec_room_layout)
#   bookshelf      x 24.6..26.4, z 17.43..17.78, top y+2.00
#   dead TV        1.4 x 0.9 x 0.4 slab                         (seated by _rec_room_layout)
#   east bench     1.0 x 0.7 x 2.2 block                        (re-faced by _rec_room_layout)
#   magazine table 0.9 x 0.7 top                                (legged by _rec_room_layout)
#   cased wall clock on the WEST bulkhead at x18.125, y+2.30, z 15.0
#   floor lamp (26.6, 9.2), fishing rod (27.0, 9.5), tally-book readable (27.7, 14.2)
#
# THE COMPOSITION. Two datums do all the work: the room's north-south SPINE at x 23 and
# the conversation square at z 12.5. Everything is squared to one or the other, and the
# heavy masses are paired across the spine so the room reads composed from the doorway
# rather than scattered:
#
#   NORTH WALL (the media + library wall, all on the spine)
#       media credenza centre x 20.5  |  screen x 23.0  |  bookshelf centre x 25.5
#       — the two 1.8-2.3m masses sit at exactly +-2.5m from the screen, and a matched
#         pair of potted plants flanks the screen at +-1.05m.
#   CENTRE (the conversation square) — the low table on the spine at z 12.5 with a
#       MIRRORED pair of chairs at x 21.5 / x 24.5, both facing it. The rug's footprint
#       is the square: its edges land within 45mm of the outside of both chairs.
#   SOUTH WALL (the lounge) — the fixed couch centred on the spine, the glTF sofa run
#       up flush beside it on the SAME back line (z 8.70) so the two read as one bench
#       seat, the ottoman centred on the couch as a footstool, and a potted plant in
#       each corner.
#   WEST WALL (the reading run) — a matched pair of armchairs flanking a lamp table,
#       centred under the stopped clock at z 15.0.
#   EAST WALL (the dart wall) — board, timber surround, score slate, and a real oche
#       batten on the deck 2.37m off the board face. The north-east quarter is left
#       DELIBERATELY EMPTY: it is the throwing space.
#
#   CIRCULATION. The walk lane in from the west door is x 18.1..21.7, z 9.7..12.0 and
#   nothing stands in it: the sofa stops at z 9.54, the extinguisher is wall-bracketed,
#   the ottoman starts at x 22.65, the square's west chair starts at z 12.2. The lane
#   opens into the middle of the room, with the lounge to the south and the media wall
#   ahead — which is why the room reads as somewhere you walk INTO rather than around.

func _rec_room() -> void:
	var y: float = DECK_Y
	var low: float = y + 0.55        # low table top is y+0.32; the settle drops the rest

	# ---- THE CONVERSATION SQUARE (centre of the room, on the spine) ----
	# A MIRRORED pair of chairs facing the low table across it. Both sit 0.505m clear of
	# the table edge and land inside the rug, so the group reads as one deliberate square
	# rather than as two chairs that happen to be near a table.
	_pc("painted_wooden_chair_01", Vector3(21.50, y, 12.50), 90)    # west arm, faces east
	_pc("painted_wooden_chair_01", Vector3(24.50, y, 12.50), -90)   # east arm, faces west
	# The table top itself carries the frozen chess game (rig_builder) — ours adds only
	# what a hand puts down beside it, all inside x 22.25..23.75 / z 12.03..12.98.
	_p("plastic_thermos", Vector3(22.45, low, 12.25), -40)
	_p("food_avocado_01", Vector3(23.55, low, 12.80), 0)

	# ---- THE LOUNGE (south wall, back line z 8.70) ----
	# The glTF sofa run up flush against the fixed couch's west end (21.8) and squared to
	# the SAME back line, so the pair reads as one continuous bench seat under the wall.
	_pc("Sofa_01", Vector3(20.75, y, 9.12), 0)                      # x 19.75..21.75
	_pc("Ottoman_01", Vector3(23.00, y, 10.35), 0)                  # footstool, on the spine
	_p("throw_pillows_01", Vector3(23.85, y + 0.75, 9.35), 20)      # on the fixed couch
	_p("throw_pillows_01", Vector3(20.20, y + 0.60, 9.20), -25)     # on the sofa
	_p("classic_laptop", Vector3(22.40, y + 0.75, 9.35), 200)       # left open on the couch
	# Corner plants, one each side — the pair that squares the south end off. The SE
	# sapling is rig_builder's; this is its mate in the SW corner, potted the same way
	# the galley plant is (pot on the deck, foliage settled onto the pot).
	_pc("ceramic_pot", Vector3(18.75, y, 8.75), 0)
	_p("calathea_orbifolia_01", Vector3(18.75, y + 0.60, 8.75), 0)

	# ---- THE WEST WALL: the reading run, centred under the stopped clock (z 15.0) ----
	# Two armchairs angled in toward the room with a lamp table between them. The clock
	# rig_builder hung at y+2.30 lands dead centre over the table, which is what makes
	# this wall read as arranged rather than lined up.
	_pc("ArmChair_01", Vector3(18.95, y, 13.60), 75)
	_pc("ArmChair_01", Vector3(18.95, y, 16.40), 105)
	# Nightstand top measures x 18.138..18.502, z 14.757..15.243 with its surface at y+0.655
	# (sonar, from the identical piece in bunk A-N). Both items sit well inside that.
	_pc("ClassicNightstand_01", Vector3(18.32, y, 15.00), 90)       # back flush on x 18.125
	_p("vintage_oil_lamp", Vector3(18.30, y + 0.72, 15.16), 0)
	_p("postcard_set_01", Vector3(18.30, y + 0.72, 14.84), -12)
	_lamp(Vector3(18.42, y + 0.95, 15.10), Color(1.0, 0.84, 0.54), 0.45, 4.0)
	# Fire point on the clear pier between the door reveal (z 11.7) and the south armchair
	# (z 13.15) — bracketed 0.115 proud of the wall face, settle-exempt.
	_pw("korean_fire_extinguisher_01", Vector3(18.24, y + 0.95, 12.20), 90, 1.1)

## Repair the rec room's FIXED furniture, and build the joinery the composition needs.
##
## Five things in this room are authored in rig_builder (_decorate_rec_room and _density_a)
## and every one of them is broken in the same family of ways the sonar scan keeps finding:
##
##  1. THE LOW TABLE IS A TOP WITH NO LEGS. A 1.5 x 0.08 x 0.95 slab at y+0.28 with 0.19m
##     of clear air under it (scan: gap 0.19, nothing to either side) — the whole chess
##     game, the score card and the scattered hand of cards ride a plank hovering over the
##     deck. This is the floating table the owner photographed.
##  2. THE MAGAZINE TABLE IS THE SAME BUG AGAIN — a 0.9 x 0.06 x 0.7 top at y+0.22, gap
##     0.14. Two legless tops in one room is why the room reads unfinished.
##  3. THE RUG NEVER RENDERS. Authored at y+0.02 with a 0.03 thickness, i.e. y18.005..18.035
##     — entirely INSIDE the rubber floor overlay (y18.02..18.05) that is laid on top of it.
##     Same bug as the five Deck B cabin rugs and the Deck D exercise mat.
##  4. THE DEAD TV FLOATS. A 1.4 x 0.9 x 0.4 slab whose base sits 0.50m off the deck and
##     0.475m clear of the bulkhead behind it — supported by nothing, mounted to nothing.
##  5. THE EAST BENCH IS A FLAT-COLOUR PLACEHOLDER standing 0.575m off the wall it is
##     supposed to be built into — a solid green block in the middle of the east side.
##
## Nothing here re-authors that furniture; this only moves existing nodes into the
## composition and builds the missing joinery under them. Every lookup is gated on an exact
## signature (size + position), so if rig_builder is ever fixed at source this silently
## no-ops instead of fighting it — the same contract as _dining_hall_layout(), and the
## same hand-off note: FOLD INTO rig_builder.gd AND DELETE FROM HERE when that file is
## next opened. Legs are derived from each top's OWN measured underside, so they follow the
## slab rather than restating its height as a second literal.
func _rec_room_layout() -> void:
	var y: float = DECK_Y
	var deck: float = y + 0.05        # rubber overlay top — what furniture actually stands on
	var host: Node = get_parent()
	if host == null:
		return
	# The credenza goes in whether or not the TV lookup matches: it is our own joinery and
	# the north wall's composition (and the boombox and console that ride its top) depends
	# on it. Back face on the bulkhead plane, 2.30 wide so it pairs with the 1.8m bookshelf
	# across the screen. Plinth / carcass / top / doors / handles — real joinery, so it
	# reads as built-in rather than as a box pushed against a wall.
	var cx: float = 20.50
	var cz: float = 17.645            # centre of a 0.42-deep carcass whose back is on 17.855
	_carcass(Vector3(cx, y + 0.105, cz), Vector3(2.16, 0.11, 0.34), MatLib.dark_metal())
	_carcass(Vector3(cx, y + 0.410, cz), Vector3(2.30, 0.50, 0.42), MatLib.wood())
	var cred_top: float = y + 0.71    # 0.05 slab centred y+0.685 -> top face y+0.71
	_carcass(Vector3(cx, y + 0.685, 17.635), Vector3(2.38, 0.05, 0.48), MatLib.weathered_wood())
	for dx in [-0.57, 0.57]:
		_wall_mesh(Vector3(cx + dx, y + 0.41, 17.420), Vector3(1.10, 0.42, 0.03), MatLib.painted_steel())
	for hx in [-0.10, 0.10]:
		_wall_mesh(Vector3(cx + hx, y + 0.41, 17.360), Vector3(0.04, 0.04, 0.09), MatLib.galvanized())

	for n in host.get_children():
		if not (n is CSGBox3D):
			continue
		var b := n as CSGBox3D
		# 1. The low table: legs and side rails from the deck up to its measured underside.
		if b.size.is_equal_approx(Vector3(1.5, 0.08, 0.95)) \
				and b.position.distance_to(Vector3(23.0, y + 0.28, 12.5)) < 0.05:
			_table_legs(b, deck, 0.10, 0.62, 0.36)
		# 2. The magazine table: legged the same way, and lifted to a real 0.34 top so it
		#    works as the side table in front of the east bench instead of a floor plank.
		#    Re-centred on the bench it serves (bench centre z 11.10) with 0.83m of legroom.
		elif b.size.is_equal_approx(Vector3(0.9, 0.06, 0.7)) \
				and b.position.distance_to(Vector3(24.8, y + 0.22, 10.5)) < 0.05:
			b.position = Vector3(25.60, y + 0.31, 11.10)
			_table_legs(b, deck, 0.07, 0.36, 0.26)
		# 3. The rug, lifted out of the floor overlay so it lands ON the deck. Its footprint
		#    (x 21.3..24.7, z 11.3..13.7) IS the conversation square: the mirrored chairs at
		#    x 21.5 / 24.5 land within 45mm of its edges, which is what ties the group.
		elif b.size.is_equal_approx(Vector3(3.4, 0.03, 2.4)) \
				and b.position.distance_to(Vector3(23.0, y + 0.02, 12.5)) < 0.05:
			b.position = Vector3(23.0, y + 0.065, 12.5)
		# 4. The dead TV, set down on the credenza top and pushed back flush to the
		#    bulkhead (0.4 deep, back on 17.85). Centred at x 20.5 so it is exactly 2.5m
		#    west of the screen on the spine, mirroring the bookshelf 2.5m east of it.
		elif b.size.is_equal_approx(Vector3(1.4, 0.9, 0.4)) \
				and b.position.distance_to(Vector3(20.0, y + 1.0, 17.2)) < 0.05:
			b.position = Vector3(20.50, cred_top + 0.45, 17.65)
		# 5. The east bench: pushed back flush against the bulkhead (x 26.875..27.875) and
		#    shifted north to z 10.0..12.2 so it clears the fishing rod propped at z 9.5,
		#    which it used to stand on top of. Re-faced in real woven canvas — a flat
		#    saturated albedo is not a body panel — then given a seat cushion and a back.
		elif b.size.is_equal_approx(Vector3(1.0, 0.7, 2.2)) \
				and b.position.distance_to(Vector3(26.8, y + 0.35, 10.5)) < 0.05:
			b.position = Vector3(27.375, y + 0.35, 11.10)
			b.material = MatLib.canvas(Color(0.40, 0.33, 0.30))
			_wall_mesh(Vector3(27.375, y + 0.745, 11.10), Vector3(0.95, 0.09, 2.10),
				MatLib.canvas(Color(0.44, 0.34, 0.28)))                     # seat cushion
			_wall_mesh(Vector3(27.700, y + 1.050, 11.10), Vector3(0.30, 0.52, 2.10),
				MatLib.canvas(Color(0.37, 0.30, 0.26)))                     # back rest

## Four legs and two side rails under a table top, derived from the top's own AABB so the
## joinery cannot drift away from the slab it carries. `inset_x`/`inset_z` are the leg
## centres measured from the top's centre; `w` is the leg section.
func _table_legs(top: CSGBox3D, deck_y: float, w: float, inset_x: float, inset_z: float) -> void:
	var under: float = top.position.y - top.size.y * 0.5
	var h: float = under - deck_y
	if h <= 0.02:
		return                        # already sitting on the deck; nothing to carry
	var c: Vector3 = top.position
	var timber: Material = MatLib.wood()
	for lx in [-inset_x, inset_x]:
		for lz in [-inset_z, inset_z]:
			_wall_mesh(Vector3(c.x + lx, deck_y + h * 0.5, c.z + lz), Vector3(w, h, w), timber)
	# Side rails just under the top, so the frame reads as jointed rather than as four
	# posts holding a plank up — the same apron trick the machine-shop bench uses.
	var rail: float = minf(0.05, h * 0.35)
	for lz in [-inset_z, inset_z]:
		_wall_mesh(Vector3(c.x, under - rail * 0.6, c.z + lz),
			Vector3(inset_x * 2.0 + w, rail, rail), MatLib.weathered_wood())

# ---- machine shop ----
# Fitter's bench top y+0.95, x -21.2..-18.5, z -12.9..-11.2.

func _machine_shop() -> void:
	var y: float = DECK_Y
	# The shop is the tool jackpot — chest, cart, welding rig, drums, jerry cans, all on
	# the wall lines so the middle of the floor stays workable. The west wall's inner
	# face is x -27.875 (sonar-verified): the storage line backs against it at -27.5,
	# not the -26.6 it used to float at, 1.3m out into the walk space.
	_pc("metal_tool_chest", Vector3(-27.5, y, -10.6), 90)
	_pc("tool_cart", Vector3(-22.5, y, -13.5), 0)   # the one mobile piece, mid-job
	_pc("portable_welding_cart", Vector3(-25.5, y, -16.5), 20)
	_pc("drawer_cabinet", Vector3(-27.55, y, -14.8), 90)
	# Declutter pass (owner: "I like it but just a bit too much"): the SE drum cluster is
	# thinned to one barrel + one jerry can — barrel_03 and a second oil can were the least
	# characterful duplicates. The workbenches, tool wall, storage and welding rig all stay.
	_pc("Barrel_01", Vector3(-20.5, y, -17.0), 0)
	_pc("metal_jerrycan_green", Vector3(-19.5, y, -16.6), 60)
	# On the fitter's bench (top y+0.95).
	_p("metal_toolbox", Vector3(-19.75, y + 0.96, -11.8), 0)
	# A hand truck parked where "against the east wall" is actually true — leaned by
	# the door pocket (east wall inner face x -14.125, door gap z -13..-11); the
	# searchlight rides the shelf run, which now stands on the west wall proper.
	_pc("hand_truck", Vector3(-14.6, y, -9.0), -90)
	_p("portable_searchlight", Vector3(-27.55, y + 1.3, -12.5), 40)   # on the shelf run
	# The bench worklight is an anchored ceiling-hung fixture built in rig_builder
	# (_worklight_ceiling) — the old industrial_wall_lamp floated mid-room over the bench.

# ============================================================ BREAKER ROOM 4-A
#
# THE ROOM, measured off rig_builder._room_north(21,10,2 → 28,10,8.8): interior
# x 21.125..27.875, z 2.125..8.675 — 6.75 x 6.55m, floor y10.0 (the annex floor slab's top
# face IS y10, there is no overlay), ceiling underside y13.075. It is the power puzzle's
# room, so it is the one interior on the rig that is allowed to look purely industrial.
#
# FIXED CONTENT (rig_builder's — nothing here may foul any of it):
#   the master breaker  x 22.5..23.5, y 10.7..12.1, z 8.35..8.65, on the north wall
#   its hazard placard + amber marker + stencils, above it (see _breaker_room_layout)
#   the burned cable gap  x 27.55..27.65, z 4.85..7.15 at y10.9, on the EAST wall
#   conduit stubs and cosmetic cable runs at x 27.64..27.76, z 2.5..4.7 and 7.1..8.6
#   the maintenance-log readable at (24.6, 11.2, 8.62); E.V.'s note pinned to the panel
#   the doorway, cut in the z2 shell wall at x 23.5 — clear opening x 22.79..24.21
#   one mains ceiling fixture at (24, 13.07, 6)
#
# THE TWO LANES THAT STAY EMPTY, and every placement below is checked against them:
#   THE PANEL WALK   x 22.0..24.4 from the door (z 2.1) to the panel face (z 8.35). That
#                    is 2.4m wide, twice the 1.2m doctrine minimum, and NOTHING stands in
#                    it — the desk stops at x 21.88, the stool at x 22.70, and everything
#                    on the panel wall itself is bracketed to the plate.
#   THE SPLICE BAY   z 4.4..7.6 along the east wall, so the burned gap can be reached and
#                    worked with the cable in hand. The cart is south of it, the parts
#                    drawers north of it.
#
# THE COMPOSITION. West wall = the maintenance run (desk, stool, tool chest, toolbox).
# North wall = the panel and its spares. East wall = consumables and the splice bay.
# South wall = the schematic board and the fire point, either side of the door. A cable
# tray runs the top of all three long walls at y+2.35 with conduit dropping out of it
# into the panel and the burned feed — which is the fitting that says "plant room" more
# than any prop in the library does.

func _breaker_room() -> void:
	var by: float = 10.0
	var steel: Material = MatLib.galvanized()
	var dark: Material = MatLib.dark_metal()

	# ---- WEST WALL (inner face 21.125): the maintenance run ----
	_pc("metal_office_desk", Vector3(21.60, by, 6.30), 90)     # long axis along z, back to the wall
	_pc("metal_stool_01", Vector3(22.40, by, 6.30), -90)       # pulled out, still west of the walk
	_p("retro_multimeter", Vector3(21.60, by + 0.85, 5.95), 20)
	_p("office_notepads", Vector3(21.66, by + 0.85, 6.68), -25)
	_p("stationery_supplies", Vector3(21.48, by + 0.85, 6.32), 0)
	_pc("metal_tool_chest", Vector3(21.50, by, 3.90), 90)
	_p("adjustable_wrench", Vector3(21.50, by + 1.00, 3.72), 30)
	_p("pliers", Vector3(21.56, by + 1.00, 4.10), -20)
	_pc("metal_toolbox", Vector3(21.60, by + 0.02, 4.95), -90)
	_p("utility_box_01", Vector3(21.55, by + 0.02, 5.55), 20)  # a parts bin set down beside it

	# ---- NORTH WALL: the panel and its spares. Bracketed, never floor-standing. ----
	_pw("power_box_01", Vector3(21.80, by + 1.45, 8.56), 180, 1.0)   # spare junction box
	_pw("power_box_01", Vector3(25.85, by + 1.45, 8.56), 180, 1.0)   # spare fuse box

	# ---- EAST WALL: consumables south of the splice bay, parts drawers north of it ----
	_pc("industrial_storage_cart", Vector3(26.60, by, 3.10), 0)      # the one wheeled thing
	_p("oil_tin", Vector3(26.35, by + 0.95, 3.10), 20)
	_p("lubricant_spray", Vector3(26.88, by + 0.95, 3.05), -30)
	_pc("metal_trash_can", Vector3(27.20, by, 4.35), 0)
	_pc("drawer_cabinet", Vector3(27.35, by, 8.15), -90)             # parts drawers, NE corner
	_p("can_rusted", Vector3(27.35, by + 1.00, 8.30), 0)

	# ---- SOUTH WALL (inner face 2.125): the schematic board, either side of the door ----
	_pw("korean_fire_extinguisher_01", Vector3(22.30, by + 0.95, 2.28), 0, 1.1)
	_pw("wall_clock", Vector3(21.90, by + 2.10, 2.18), 0)
	# The voltage placard goes by the DOOR, not on the panel wall: rig_builder already
	# paints "1) SPLICE THE GAP / 2) CLOSE THIS MASTER" up there, and a plate anywhere near
	# it lands under the second line.
	#
	# IT WAS HUNG IN THE DOORWAY. Centred at x 24.30 it looked like it was beside the
	# opening, but the opening (measured: CSG cut x 22.70..24.30, y 10.0..12.40, with
	# DoorFrame's jamb at x 24.21..24.304 standing proud to z 2.155) ends at exactly
	# 24.30 — so half of the 0.48 m plate hung over the hole and the other half fouled
	# the proud jamb. Solid plate on this wall starts at x >= 24.30 and ABOVE y 12.40.
	#
	# Same fix as the landing-2 signage one file over (_breaker_room_layout): everything
	# goes on the LINTEL over the frame head, centred on the opening. The band is y
	# 12.40 (head) .. 13.075 (measured ceiling underside) = 0.675 m; a 0.42 m plate
	# centred at 12.74 leaves 0.13 m of clear plate below and 0.125 m above, and its
	# 0.48 m width sits inside the 1.6 m of lintel. Everything stays on the room-side
	# face (wall face z 2.125) with each layer a few mm proud of the one behind it.
	_wall_mesh(Vector3(23.50, by + 2.74, 2.16), Vector3(0.48, 0.42, 0.05), MatLib.hazard_stripe())
	_wall_mesh(Vector3(23.50, by + 2.74, 2.185), Vector3(0.42, 0.34, 0.02), MatLib.painted_steel())
	_paint("DANGER\n440 V", Vector3(23.50, by + 2.74, 2.20), 0, 13, 0.2)
	_schematic_board(Vector3(25.70, by + 1.75, 2.17))
	_pw("clipboard", Vector3(24.85, by + 1.50, 2.22), 0)
	_pc("chinese_stool", Vector3(25.70, by, 2.72), 0)                # under the board
	_paint("4-A  DISTRIBUTION", Vector3(25.70, by + 2.42, 2.19), 0, 14, 0.5)

	# ---- CABLE TRAY + CONDUIT: the run that makes this a plant room ----
	# Perimeter tray on the three long walls, cable bundles lying in it, and drops out of
	# it into the two things this room exists for: the master breaker, and the burned feed
	# on the east wall.
	#
	# THE TRAY HEIGHT IS SET BY THE PANEL WALL, NOT BY THE CEILING. At the obvious y+2.35
	# the north run passed straight across the bottom of the hazard placard over the
	# breaker (y 12.35..12.97 after _breaker_room_layout widens it), hiding the "v THIS
	# PANEL v" line and the self-lit amber marker underneath it. y+2.20 threads the tray
	# through the 0.25m of bare plate BETWEEN the cabinet top (12.10) and the placard
	# bottom (12.35) — 7.5cm clear below, 5.5cm clear above — so it now reads as the
	# feed arriving at the panel instead of as a bar drawn over the signage.
	var tray: float = by + 2.20
	_tray(Vector3(24.50, tray, 8.55), Vector3(6.30, 0.05, 0.24), true)
	_tray(Vector3(21.30, tray, 5.40), Vector3(0.24, 0.05, 5.20), false)
	_tray(Vector3(27.70, tray, 5.40), Vector3(0.24, 0.05, 5.20), false)
	for dx in [22.65, 23.00, 23.35]:                 # drops onto the panel top (y12.1)
		_wall_mesh(Vector3(dx, by + 2.14, 8.58), Vector3(0.06, 0.13, 0.06), dark)
	_wall_mesh(Vector3(27.70, by + 1.55, 4.30), Vector3(0.07, 1.25, 0.07), dark)   # drop to the gap
	_wall_mesh(Vector3(27.70, by + 1.55, 7.70), Vector3(0.07, 1.25, 0.07), dark)
	_wall_mesh(Vector3(21.28, by + 1.80, 4.90), Vector3(0.20, 0.34, 0.26), MatLib.painted_steel())
	_wall_mesh(Vector3(21.28, by + 1.80, 7.20), Vector3(0.20, 0.34, 0.26), MatLib.painted_steel())
	_wall_mesh(Vector3(21.20, by + 1.62, 4.90), Vector3(0.04, 0.06, 0.04), steel)   # gland
	_wall_mesh(Vector3(21.20, by + 1.62, 7.20), Vector3(0.04, 0.06, 0.04), steel)

## A length of cable tray: the perforated channel, its two upstands, and the bundle of
## cable lying in it. `along_x` picks which way the run goes.
func _tray(pos: Vector3, size: Vector3, along_x: bool) -> void:
	var steel: Material = MatLib.galvanized()
	_wall_mesh(pos, size, steel)
	var half: float = (size.z if along_x else size.x) * 0.5
	for s in [-1.0, 1.0]:
		var off := Vector3(0, 0.05, s * half) if along_x else Vector3(s * half, 0.05, 0)
		var up := Vector3(size.x, 0.09, 0.02) if along_x else Vector3(0.02, 0.09, size.z)
		_wall_mesh(pos + off, up, steel)
	var bundle := Vector3(size.x * 0.99, 0.07, 0.14) if along_x else Vector3(0.14, 0.07, size.z * 0.99)
	_wall_mesh(pos + Vector3(0, 0.06, 0), bundle, MatLib.flat(Color(0.10, 0.09, 0.08)))

## The single-line schematic pinned by the door: a steel backboard, a drawing sheet, the
## bus and its feeders inked on it, and one feeder ringed in red — the burned one.
## `pos` is the board's centre, its face 0.02 proud of it toward the room (+Z).
func _schematic_board(pos: Vector3) -> void:
	_wall_mesh(pos, Vector3(1.20, 0.90, 0.05), MatLib.dark_metal())
	var face: float = pos.z + 0.032
	_wall_mesh(Vector3(pos.x, pos.y, face), Vector3(1.02, 0.74, 0.006),
		MatLib.flat(Color(0.80, 0.82, 0.84)))
	var ink: Material = MatLib.flat(Color(0.16, 0.17, 0.19))
	_wall_mesh(Vector3(pos.x, pos.y + 0.26, face + 0.004), Vector3(0.86, 0.018, 0.004), ink)  # the bus
	for i in range(5):
		var fx: float = pos.x - 0.34 + i * 0.17
		_wall_mesh(Vector3(fx, pos.y + 0.06, face + 0.004), Vector3(0.014, 0.42, 0.004), ink)
		_wall_mesh(Vector3(fx, pos.y - 0.17, face + 0.004), Vector3(0.10, 0.12, 0.004), ink)  # a breaker
	# The dead feeder, ringed in grease pencil, with the note somebody wrote beside it.
	_wall_mesh(Vector3(pos.x + 0.34, pos.y - 0.17, face + 0.006), Vector3(0.17, 0.19, 0.004),
		MatLib.flat(Color(0.62, 0.16, 0.13)))
	_wall_mesh(Vector3(pos.x + 0.34, pos.y - 0.17, face + 0.008), Vector3(0.12, 0.14, 0.004),
		MatLib.flat(Color(0.80, 0.82, 0.84)))
	_paint("4-A SINGLE LINE", Vector3(pos.x, pos.y + 0.40, face + 0.010), 0, 12, 0.35)
	for hx in [-0.55, 0.55]:                                        # bolts at the corners
		for hy in [-0.41, 0.41]:
			_wall_mesh(Vector3(pos.x + hx, pos.y + hy, face), Vector3(0.03, 0.03, 0.02),
				MatLib.galvanized())

## Repair Breaker Room 4-A's painted signage — the stencils on the panel wall, and the
## sign over the doorway on stair landing 2.
##
## TWO faults, both authored in rig_builder and both the same class of bug as the dining
## hall's stacked bulkhead (see _dining_hall_layout for the contract this follows):
##
##  1. THE PANEL-WALL PAINT SITS ON THE PANEL. "MASTER BREAKER 4-A" is authored at
##     (23, 12.58, 8.58) — dead INSIDE the self-lit amber marker bar (z 8.575..8.605), so
##     the lettering and the glowing bar fight for the same 3cm of depth — and
##     "v THIS PANEL v" at y 12.28 straddles the bottom edge of the hazard placard with
##     its lower half hanging over the 0.18m of bare plate between the placard and the
##     breaker cabinet's top. The two lines and the marker are three fittings sharing one
##     0.5m plate with no margin anywhere.
##  2. THE DOORWAY SIGN HANGS IN THE DOOR. The landing-2 title is authored at y 12.40 —
##     the exact top of a 2.4m opening — so a label 0.20m tall is cut in half by the
##     doorframe HEAD (DoorFrame puts it at y 12.30..12.40, standing PROUD of the wall on
##     both faces, so the paint is not merely level with the frame, it is inside it). Its
##     subtitle and the self-lit marker over it are both authored at z 1.88/1.90, which is
##     INSIDE the 0.25-thick wall (south face 1.875) rather than painted on it.
##
## The fix is the idiom the machinery-room door already uses one level down: everything
## goes ABOVE the head, onto solid lintel plate, stacked title / marker / subtitle with
## real gaps, and every piece is pushed a few millimetres proud of the face it is painted
## on. Panel-wall side, the placard is widened to 1.6 x 0.62 so two lines and a marker
## fit inside it with margin, and the whole group is lifted to leave 0.25m of clear plate
## between the paint and the top of the breaker cabinet.
##
## Same contract as _dining_hall_layout: exact-signature lookups, so a source fix in
## rig_builder silently no-ops this. FOLD INTO rig_builder.gd AND DELETE FROM HERE.
func _breaker_room_layout() -> void:
	var host: Node = get_parent()
	if host == null:
		return
	for n in host.get_children():
		if n is CSGBox3D:
			var b := n as CSGBox3D
			# The hazard placard over the panel: widened and lifted so the two stencil
			# lines and the marker all land inside it with margin.
			if b.size.is_equal_approx(Vector3(1.3, 0.5, 0.05)) \
					and b.position.distance_to(Vector3(23, 12.55, 8.62)) < 0.05:
				b.size = Vector3(1.6, 0.62, 0.05)
				b.position = Vector3(23.0, 12.66, 8.62)
				# A painted field across the top of the plate for the wording to sit on.
				# Charcoal stencil paint on black-and-yellow hazard stripes is very nearly
				# unreadable — the stripes win — so the two lines get a plain steel band
				# and the striping is left showing as a border round it and under the
				# self-lit marker. Built only when the plate was actually found, so a
				# source fix in rig_builder takes this with it.
				_wall_mesh(Vector3(23.0, 12.72, 8.585), Vector3(1.52, 0.46, 0.02),
					MatLib.painted_steel())
			# Its self-lit amber marker, dropped to the bottom of the plate where it
			# underlines the wording instead of running through it.
			elif b.size.is_equal_approx(Vector3(1.05, 0.16, 0.03)) \
					and b.position.distance_to(Vector3(23, 12.58, 8.59)) < 0.05:
				b.size = Vector3(1.36, 0.09, 0.03)
				b.position = Vector3(23.0, 12.44, 8.575)
			# The landing-2 door marker, lifted out of the frame and onto the wall face.
			elif b.size.is_equal_approx(Vector3(1.1, 0.1, 0.03)) \
					and b.position.distance_to(Vector3(23.5, 12.62, 1.9)) < 0.05:
				b.position = Vector3(23.5, 12.70, 1.855)
		elif n is Label3D:
			var l := n as Label3D
			if l.text == "MASTER BREAKER 4-A":
				# Two labels share this text — one inside the room on the panel plate
				# (z 8.58), one over the doorway out on landing 2 (z 1.88).
				if absf(l.position.z - 8.58) < 0.05:
					l.position = Vector3(23.0, 12.82, 8.560)
				elif absf(l.position.z - 1.88) < 0.05:
					l.position = Vector3(23.5, 12.90, 1.860)
			elif l.text.contains("THIS PANEL"):
				l.position = Vector3(23.0, 12.60, 8.560)
			elif l.text.contains("STAIR LEVEL 2"):
				l.position = Vector3(23.5, 12.52, 1.860)

# ---- Deck B: crew cabins ----
# Desks are 1.2 x 0.6 with a top at y+0.80; lockers are 0.55 square with a top at y+1.80.
# Corridor z 11..13; cabin doors at x 0.5/5.5/10.5/15.5/20.5 (south) and 2/10/16.5/21 (north).

func _deck_b_cabins() -> void:
	var y: float = B_Y
	var top: float = y + 0.95        # desk top is y+0.80
	var desks := [Vector3(1.8, y, 6.9), Vector3(6.9, y, 8.0), Vector3(18.0, y, 17.1)]
	var items := [["office_notepads","modified_thermos"], ["binder_notebook","vintage_flashlight"],
			["retro_multimeter","plastic_thermos"]]
	for i in range(desks.size()):
		var d: Vector3 = desks[i]
		_p(items[i][0], d + Vector3(-0.2, 0.95, 0.0), 15 + i * 40)
		_p(items[i][1], d + Vector3(0.25, 0.95, 0.05), -30 - i * 25)
	# A stool in the B-01 desk pocket; the ransacked cabin's flashlight on the floor
	# among the scattered papers, which is where a ransacking leaves it.
	_pc("metal_stool_01", Vector3(2.4, y, 7.7), 0)
	_p("vintage_flashlight", Vector3(20.5, y + 0.05, 7.4), 45)
	_p("plastic_thermos", Vector3(1.5, top, 7.1), 20)

# ---- Deck C: control / mud logging ----
# Console desks (5.8/8.0/10.2, 7.4) top y+0.80. Rig-office desk (14.5, 7.5) is turned 90°,
# so its footprint is x 14.2..14.8, z 6.9..8.1. Filing cabinets (17.3, 7.0/7.9) top y+1.30.
# Mud-log instrument racks (14.5/17.5/20.5, 17.4) top y+1.80.

func _deck_c_control() -> void:
	var y: float = C_Y
	for i in range(3):
		var d := Vector3(5.8 + i * 2.2, y, 7.4)
		_p("retro_multimeter", d + Vector3(-0.3, 0.95, 0.15), 180)
		_p(["modified_thermos", "office_notepads", "plastic_thermos"][i], d + Vector3(0.35, 0.95, 0.1), 160)
	# The prize: a working-looking radio transceiver on a desk squared against the mud-log
	# room's east bulkhead (x 23), with its operator's stool pulled out in front of it.
	_pc("metal_office_desk", Vector3(22.2, y, 16.2), 90)
	_p("vintage_radio_transceiver", Vector3(22.2, y + 1.0, 16.2), 90)
	_lamp(Vector3(22.2, y + 1.15, 16.2), Color(0.5, 0.9, 0.7), 0.35, 3.0)   # cold instrument glow, on the radio
	_p("binder_notebook", Vector3(17.5, y + 2.0, 17.4), -20)                # on an instrument rack
	_pc("metal_stool_02", Vector3(21.2, y, 16.2), 0)
	# Power panel + fire extinguisher on the bulkheads.
	_pw("power_box_01", Vector3(22.7, y + 1.4, 14.2), -90, 1.2)
	_pw("korean_fire_extinguisher_01", Vector3(13.4, y + 0.55, 14.4), 90, 1.1)

# ---- Deck D: works / gym / workshop ----
# Workshop craft bench top y+0.96, x 18.15..19.85, z 16.6..17.4.
# Gym weight bench top y+0.6, x 10.2..10.8, z 9.2..10.8. Washers top y+1.0 at x 17/18.5/20.

func _deck_d_works() -> void:
	var y: float = D_Y
	# Workshop band (x 15.5..23, z 15..18): shelves and heavy kit on the wall lines.
	# Measured: this rack's top is y+1.0 and its footprint is only x 22.28..22.52,
	# z 16.34..16.86 — tins authored at z 16.3 / 16.9 missed it and fell to the deck.
	_pc("steel_frame_shelves_01", Vector3(22.4, y, 16.6), -90)
	_p("cleaner_tin_01", Vector3(22.4, y + 1.3, 16.45), 0)
	_p("oil_tin", Vector3(22.4, y + 1.3, 16.76), 0)
	_pc("portable_generator", Vector3(16.4, y, 17.4), 40)
	_pc("metal_jerrycan", Vector3(17.3, y, 17.6), -20)
	_pc("propane_tank", Vector3(16.2, y, 15.5), 0)
	_p("small_lpg_tank", Vector3(22.6, y + 0.05, 17.6), 0)
	# Gym band: a rack against the west wall (it used to stand in the corridor).
	_pc("worn_metal_rack", Vector3(8.5, y, 12.3), 90)
	_pw("industrial_pipe_lamp", Vector3(19.0, y + 2.4, 16.5), 0)
	_lamp(Vector3(19.0, y + 2.2, 16.5), Color(1.0, 0.85, 0.6), 0.5, 5.0)

# ============================================================ second pass (2x)

func _dining_hall_more() -> void:
	var y: float = DECK_Y
	var tbl: float = y + 0.7          # mess table top is y+0.49
	var counter: float = y + 1.2
	# Food and comfort on the mess tables — the meal that never got eaten.
	_p("carrot_cake", Vector3(2.4, tbl, 11.0), 0)
	_p("croissant", Vector3(8.4, tbl, 14.5), 40)
	_p("bananas", Vector3(1.6, tbl, 14.5), 0)
	_p("brass_pot_01", Vector3(11.8, counter, 16.2), 0)     # on the range's right hob
	# brass_pan_01 used to sit at (11.2, counter, 15.9) — which is exactly the range's LEFT
	# hob, and as of s21 that hob carries the stove's own boiling pot (cook_stove.gd builds
	# it, because it has to come to the boil when you cook mussels). Two vessels were
	# occupying the same 40 cm ring. The brass pot on the right hob stays.
	# TABLE DRESSING. A mess table with two coffee cups on it reads as a set dressing
	# still waiting for its props; these are the things a shift actually leaves behind —
	# a game somebody walked away from, the mugs, a tray, the smokes, the duty pad.
	# Everything sits inside the table's own 1.8 x 1.0 top (x +-0.9, z +-0.5 of centre).
	_p("chess_set", Vector3(2.62, tbl, 10.72), 20)              # (2,11) — the frozen game
	_p("office_notepads", Vector3(1.35, tbl, 10.75), -15)
	_p("tea_set_01", Vector3(1.45, tbl, 11.32), 30)
	_p("brass_goblets", Vector3(7.45, tbl, 10.72), 0)           # (8,11)
	_p("cigarette_pack", Vector3(8.65, tbl, 10.75), 40)
	_p("carved_wooden_plate", Vector3(7.45, tbl, 11.35), -20)
	_p("wooden_bowl_02", Vector3(2.60, tbl, 14.85), 0)          # (2,14.5)
	_p("vintage_lighter", Vector3(1.30, tbl, 14.18), 60)
	_p("tea_set_01", Vector3(7.45, tbl, 14.20), -25)            # (8,14.5)
	_p("russian_food_cans_01", Vector3(8.72, tbl, 14.85), 10)
	_p("office_notepads", Vector3(7.50, tbl, 14.82), 15)
	# West bulkhead, south end: the plant tucked into the corner clear of the notice
	# board above it (board bottom y+1.30, z 8.95..10.15 — the plant used to stand at
	# z 9.0 with its leaves reaching into that panel), and the mess clock centred over
	# the board on the y+2.65 paint datum.
	_pc("ceramic_pot", Vector3(-1.4, y, 8.55), 0)
	_p("calathea_orbifolia_01", Vector3(-1.4, y + 0.6, 8.55), 0)
	_pw("alarm_clock_01", Vector3(-1.8, y + 2.65, 9.55), 90)
	_p("plastic_thermos", Vector3(6.0, counter, 17.0), -60)
	# THE OTHER TWO LIGHTS. rig_builder hangs ONE mains fixture in here, on the centre of
	# a 15.75 x 9.75m hall — the west end (the fridge and the pantry shelves) and the east
	# end (the range and the prep counter) both sat outside its 8.5m falloff, so the room
	# read as one hot pool with two dark ends. These flank it on the same z 13 line, on
	# the same circuit and the same fixture, so all three wake together on the breaker.
	# z 13 threads between the ceiling beams (z 10.5 / 15.5) and the service pipe (z 12).
	var ceil_y: float = y + 3.2 - 0.13      # 21.07 — ceiling underside, rig_builder's datum
	_mains_lamp(Vector3(1.8, ceil_y, 13.0), 1.8, 7.5)
	_mains_lamp(Vector3(10.2, ceil_y, 13.0), 1.8, 7.5)

## THE KITCHEN. rig_builder gives the hall a 10m steel counter, a range, a fridge and a
## pan rail; on its own that is a servery, not a galley kitchen — there was nowhere to
## prep, nothing to wash up in, nowhere for the dry goods, and the range vented into the
## room. This builds the working half: an L of counter (the existing north run plus a new
## prep counter down the east wall), the sink and drainer at the west end of the servery,
## the dry-goods shelves over the middle of it, the extract hood over the range, and the
## pot rail and urn on the prep counter.
##
## All joinery, so it is CSG and mesh rather than props: _carcass for anything the player
## should bump into (it IS the surface, so it is settle-exempt by construction) and
## _wall_mesh for fittings that hang off it. Only the stock on the shelves is queued as
## props, so the settle pass rests every tin on the board actually under it.
##
## RESERVED LANES this must not touch: the servery service lane (z 15.0..16.4 along the
## whole counter) and the 2.9m gap between the mess-table end chairs (x 3.53..6.47).
## Nothing here stands on the floor at all — every piece is against the north or east
## bulkhead or hangs over one of the two counters.
func _dining_hall_kitchen() -> void:
	var y: float = DECK_Y
	var steel: Material = MatLib.galvanized()
	var dark: Material = MatLib.dark_metal()

	# ---- DRY GOODS: two boards over the servery, x 2.6..7.8 ----
	# East limit 7.8 keeps them clear of the pan rail (x 8..11); west limit 2.6 leaves the
	# sink bay and its splashback their own panel of wall. Depth 0.32 at z 17.70 puts the
	# boards' backs on the bulkhead face (17.875) and their fronts just over the counter's
	# back edge (17.6), so nothing overhangs into the cook's face.
	var boards := [y + 1.60, y + 2.10]     # board CENTRES; tops land at +0.025
	for b in boards:
		_carcass(Vector3(5.20, b, 17.70), Vector3(5.20, 0.05, 0.32), MatLib.weathered_wood())
		for bx in [2.85, 5.20, 7.55]:
			_wall_mesh(Vector3(bx, b - 0.11, 17.70), Vector3(0.05, 0.17, 0.30), dark)
	# Stocked. Tinned rows on the lower board where a hand reaches them, the bulk and the
	# awkward shapes up top. The settle pass rests each on the board under it.
	var low: float = y + 1.78
	for spec in [["long_life_food", 3.05], ["russian_food_cans_01", 3.70], ["can_rusted", 4.20],
			["pot_enamel_01", 4.85], ["jug_01", 5.55], ["russian_food_cans_01", 6.15],
			["long_life_food", 6.75], ["CheeseBox_01", 7.35]]:
		_p(String(spec[0]), Vector3(float(spec[1]), low, 17.68), 90)
	var high: float = y + 2.28
	for spec2 in [["can_rusted", 3.10], ["russian_food_cans_01", 3.75], ["wooden_bowl_01", 4.45],
			["long_life_food", 5.20], ["pot_enamel_01", 5.95], ["can_rusted", 6.60],
			["wicker_basket_02", 7.30]]:
		_p(String(spec2[0]), Vector3(float(spec2[1]), high, 17.68), 90)

	# ---- THE SINK, sunk into the servery's west end (basin x 1.47..2.33) ----
	# Drawn as a rim of four bars round a dark well plate rather than as one solid tub:
	# a box "basin" set into an opaque counter is a box you cannot see into.
	_wall_mesh(Vector3(1.90, y + 1.28, 17.58), Vector3(1.24, 0.56, 0.03), steel)   # splashback
	_wall_mesh(Vector3(1.90, y + 1.005, 17.02), Vector3(0.74, 0.02, 0.50),
		MatLib.flat(Color(0.09, 0.10, 0.11)))                                       # the well
	for bar in [[1.90, 16.745, 0.86, 0.07], [1.90, 17.295, 0.86, 0.07],
			[1.505, 17.02, 0.07, 0.62], [2.295, 17.02, 0.07, 0.62]]:
		_wall_mesh(Vector3(float(bar[0]), y + 1.025, float(bar[1])),
			Vector3(float(bar[2]), 0.05, float(bar[3])), steel)                     # rim
	_wall_mesh(Vector3(1.90, y + 1.20, 17.38), Vector3(0.05, 0.34, 0.05), steel)   # tap riser
	_wall_mesh(Vector3(1.90, y + 1.35, 17.20), Vector3(0.045, 0.045, 0.36), steel) # swan neck
	_p("all_purpose_cleaner", Vector3(2.50, y + 1.15, 17.42), 20)
	# The drainer beside it: a wire rack on the counter, standing on its own tray.
	_wall_mesh(Vector3(3.50, y + 1.02, 17.05), Vector3(0.82, 0.04, 0.46), steel)
	for i in range(6):
		_wall_mesh(Vector3(3.19 + i * 0.125, y + 1.14, 17.05), Vector3(0.02, 0.20, 0.42), steel)
	_p("wooden_bowl_01", Vector3(4.20, y + 1.10, 16.80), 0)

	# ---- THE EXTRACT HOOD over the range (x 10.85..12.15, z 15.6..16.8) ----
	# Canopy, drip lip, a strip light under it and a duct up to the deckhead. The duct
	# tops out at y+3.06 against the y+3.075 ceiling underside and stands on z 16.90,
	# clear of the z 15.5 ceiling beam and the z 12.0 service pipe.
	_wall_mesh(Vector3(11.50, y + 1.955, 16.25), Vector3(1.52, 0.30, 1.34), steel)
	_wall_mesh(Vector3(11.50, y + 1.780, 16.25), Vector3(1.62, 0.05, 1.44), dark)
	_wall_mesh(Vector3(11.50, y + 1.790, 15.72), Vector3(1.06, 0.04, 0.10),
		MatLib.flat(Color(0.90, 0.88, 0.80)))
	_wall_mesh(Vector3(11.50, y + 2.580, 16.90), Vector3(0.46, 0.96, 0.46), steel)
	_wall_mesh(Vector3(11.50, y + 2.130, 16.90), Vector3(0.56, 0.06, 0.56), dark)   # duct collar

	# ---- THE PREP COUNTER, down the east bulkhead (inner face x 13.875) ----
	# x 12.63..13.87, z 11.66..15.14, top y+0.99. It stops 0.5m short of the range's
	# z-run and 2.8m clear of the nearest mess chair, so the aisle and the service lane
	# are both untouched. Plinth / carcass / top / drawer fronts — real joinery, the same
	# way the rec room's credenza is built.
	_carcass(Vector3(13.28, y + 0.10, 13.40), Vector3(1.02, 0.20, 3.20), dark)
	_carcass(Vector3(13.28, y + 0.55, 13.40), Vector3(1.15, 0.70, 3.40), MatLib.dirty_white_panel())
	_carcass(Vector3(13.25, y + 0.95, 13.40), Vector3(1.24, 0.08, 3.48), steel)
	_wall_mesh(Vector3(13.845, y + 1.30, 13.40), Vector3(0.05, 0.62, 3.40), steel)  # splashback
	for dz in [-1.05, 0.0, 1.05]:
		_wall_mesh(Vector3(12.685, y + 0.55, 13.40 + dz), Vector3(0.03, 0.56, 0.96),
			MatLib.painted_steel())
		_wall_mesh(Vector3(12.655, y + 0.72, 13.40 + dz), Vector3(0.04, 0.04, 0.34), steel)
	# What is out on it mid-prep.
	var prep: float = y + 1.15
	_p("wooden_cutting_board", Vector3(13.20, prep, 12.30), 0)
	_p("yellow_onion", Vector3(13.45, prep, 12.05), 0)
	_p("sweet_potato", Vector3(13.10, prep, 11.95), 30)
	_p("wooden_bowl_01", Vector3(13.30, prep, 12.80), 0)
	_p("jug_01", Vector3(13.50, prep, 13.35), 0)
	_p("wooden_spoon", Vector3(13.20, prep, 13.85), 40)
	_p("brass_goblets", Vector3(13.55, prep, 14.95), 0)
	# THE COFFEE URN at the counter's north end — the one fixture a mess hall is measured
	# by. Body, lid, tap and sight glass, standing on the prep top (y+0.99).
	_wall_mesh(Vector3(13.30, y + 1.27, 14.60), Vector3(0.34, 0.54, 0.34), steel)
	_wall_mesh(Vector3(13.30, y + 1.57, 14.60), Vector3(0.38, 0.06, 0.38), dark)
	_wall_mesh(Vector3(13.30, y + 1.68, 14.60), Vector3(0.09, 0.10, 0.09), dark)   # lid knob
	_wall_mesh(Vector3(13.30, y + 1.12, 14.43), Vector3(0.05, 0.05, 0.16), dark)   # tap
	_wall_mesh(Vector3(13.14, y + 1.30, 14.43), Vector3(0.03, 0.34, 0.03),
		MatLib.flat(Color(0.70, 0.72, 0.68)))                                       # sight glass
	# ---- HANGING POTS over the prep counter ----
	_wall_mesh(Vector3(13.55, y + 2.05, 13.10), Vector3(0.05, 0.05, 2.60), dark)
	for hz in [12.20, 13.10, 13.95]:
		_wall_mesh(Vector3(13.55, y + 1.94, hz), Vector3(0.03, 0.18, 0.03), steel)
	_pw("brass_pan_01", Vector3(13.50, y + 1.76, 12.20), 0)
	_pw("pot_enamel_01", Vector3(13.50, y + 1.74, 13.10), 0)
	_pw("brass_pot_01", Vector3(13.50, y + 1.76, 13.95), 0)
	# Kitchen fire point, on the east bulkhead between the prep counter and the range.
	_pw("korean_fire_extinguisher_01", Vector3(13.72, y + 0.95, 16.55), -90, 1.1)

func _bunkhouse_more() -> void:
	var y: float = DECK_Y
	# Finishing touches only — the cabins are furnished in _bunkhouse(); this hangs a
	# framed picture on a real bulkhead in three of them and stands one plant in a
	# corner, so six identical shells read as six lived-in homes. Everything is flush
	# against a wall (west/head bulkheads) or tucked into a corner, nothing in a walk line.
	_pw("fancy_picture_frame_01", Vector3(-27.8, y + 1.6, 7.0), 90)     # A-S, west bulkhead
	_pw("fancy_picture_frame_02", Vector3(-8.2, y + 1.6, 16.0), -90)    # C-N, east bulkhead
	_pw("fancy_picture_frame_01", Vector3(BUNKS.bed_pos(1, true).x, y + 1.6, 4.15), 0)  # B-S, head wall
	_pc("fern_02", Vector3(-27.4, y + 0.05, 16.9), 0)                   # A-N, NW corner (lino top)
	# C-N wardrobe-top sprig. Was anchored at x -11.4, which is 0.55m west of that locker's
	# centre — clear off a top only 0.5m wide, so it had nothing under it. On the locker's
	# free quarter it lands on the steel like the rest of the crew's things.
	_p("celandine_01", _locker_top(BUNKS.bed_pos(2, false)) + Vector3(-0.13, 0.09, 0.13), 0)

func _rec_room_more() -> void:
	var y: float = DECK_Y
	var low: float = y + 0.55

	# ---- THE NORTH WALL: media + library, everything on the spine at x 23 ----
	# The working set stands dead centre on the spine, facing SOUTH down the room at the
	# ottoman, the low table and the couch — one unbroken sight line, which is the focal
	# point the room was missing. yaw 180 = facing -Z (the _label convention: 0 faces +Z).
	# The stand measures 0.9 x 0.43 with its top at y+0.52, so z 17.65 puts its back flush
	# on the bulkhead face (17.875).
	_pc("small_wooden_table_01", Vector3(23.00, y, 17.65), 0)
	_pc("television_02", Vector3(23.00, y + 0.58, 17.60), 180)
	# The credenza built under the dead TV (see _rec_room_layout) has a 2.38 x 0.48 top at
	# y+0.685; these two ride its ends, clear of the TV's 1.4m footprint at its centre.
	_p("boombox", Vector3(19.60, y + 0.78, 17.60), 8)
	_p("gaming_console", Vector3(21.44, y + 0.78, 17.60), -6)
	# A framed photo on the bare plate above the credenza, below the beam line (y+2.95).
	_pw("fancy_picture_frame_01", Vector3(20.50, y + 2.15, 17.82), 180)
	# The matched pair that squares the screen: one potted plant either side at +-1.05m,
	# each in the 1.15m gap between the screen stand and the mass beyond it.
	for px in [21.95, 24.05]:
		_pc("ceramic_pot", Vector3(px, y, 17.55), 0)
		_p("calathea_orbifolia_01", Vector3(px, y + 0.60, 17.55), 0)
	# Bookshelf top (top y+2.0, x 24.6..26.4, z 17.43..17.78): the mantel clock centred on
	# the shelf as its anchor, the whale and the candleholders balanced either side of it.
	# The lantern moved off here onto the west-wall lamp table, where a reading light
	# actually belongs — it was the fourth object on one 1.8m shelf top.
	_p("mantel_clock_01", Vector3(25.50, y + 2.25, 17.60), 180)
	_p("bronze_whale_statue", Vector3(24.85, y + 2.25, 17.60), -20)
	_p("brass_candleholders", Vector3(26.15, y + 2.25, 17.60), 0)
	# The library wall's own light — a bracketed lamp over the bookshelf, with the omni set
	# INSIDE the fixture so the warm pool has a visible source. Threads between the shelf-top
	# clutter (up to y+2.30) and the z15.5 ceiling beam (y+2.82..y+3.08).
	_pw("industrial_wall_lamp", Vector3(25.50, y + 2.55, 17.82), 180)
	_lamp(Vector3(25.50, y + 2.40, 17.58), Color(1.0, 0.86, 0.58), 0.45, 4.5)

	# ---- THE EAST WALL: the dart wall ----
	# Board flush on the bulkhead (interior face x 27.875) with a real timber surround
	# behind it and a chalk slate beside it, all settle-exempt wall fittings.
	_pw("dartboard", Vector3(27.80, y + 1.80, 15.50), -90)
	_wall_mesh(Vector3(27.856, y + 1.80, 15.50), Vector3(0.03, 0.95, 0.95), MatLib.weathered_wood())
	_wall_mesh(Vector3(27.850, y + 1.55, 14.35), Vector3(0.04, 0.60, 0.45), MatLib.dark_metal())
	_wall_mesh(Vector3(27.790, y + 1.22, 14.35), Vector3(0.10, 0.05, 0.30), MatLib.weathered_wood())  # chalk tray
	# The oche: a timber throw batten screwed to the deck a regulation 2.37m off the board
	# face. It is what makes the empty north-east quarter read as a throwing lane and not
	# as unfinished floor — and it is a fitting, so it takes scene light like the deck.
	_wall_mesh(Vector3(25.43, y + 0.058, 15.50), Vector3(0.06, 0.016, 1.30), MatLib.weathered_wood())
	# Scorer's stool tucked flush into the north-east corner, out of the throwing space.
	_pc("metal_stool_02", Vector3(27.45, y, 17.20), -90)
	_p("sungka_board", Vector3(27.45, y + 0.85, 17.20), 0)

	# ---- odds and ends that belong to the lounge ----
	_p("chess_set", Vector3(23.30, low, 12.42), 20)          # on the low table, mid-game
	_pc("fir_sapling", Vector3(26.90, y, 8.70), 0)           # SE corner, mate to the SW pot
	_p("baseball_01", Vector3(21.90, y + 0.05, 10.05), 0)    # rolled out from under the sofa
	# East bench cushion top is y+0.79 (see _rec_room_layout) — the reading nook's pillow.
	_p("throw_pillows_01", Vector3(27.32, y + 0.85, 10.45), 15)

func _machine_shop_more() -> void:
	var y: float = DECK_Y
	var bench: float = y + 0.96
	# THE VICE IS THE ONLY LOOSE TOOL LEFT ON THIS BENCH. The crowbar went to the store room
	# (_scatter_wetdeck) and the bolt cutters to the pump room's spares rack (_wet_deck) —
	# owner: "all the tools shouldnt just be in the machine shop, maybe have 2-3 in there",
	# and rig_builder cut the same bench's pocketable set from six to two in the same pass.
	# A bench vice is not a hand tool that could live anywhere else; it is what a bench is for.
	_p("bench_vice_01", Vector3(-18.9, bench, -12.0), 0)
	# The shelf run FLUSH on the west wall (inner face -27.875) with its tins riding along —
	# the whole line sat 1.3m off the wall before the sonar audit caught it. Declutter pass:
	# the second west-corner drum, the loose jerry can and the third shelf tin were dropped
	# (duplicate scatter) — the shelf keeps its oil tin and cleaner tin.
	_pc("steel_frame_shelves_02", Vector3(-27.55, y, -13.0), 90)
	_p("oil_tin", Vector3(-27.55, y + 1.3, -13.3), 0)
	_p("cleaner_tin_01", Vector3(-27.55, y + 1.3, -12.75), 0)
	# ---- The bare SOUTH bulkhead (interior face z -6.125), dressed to match the worked-in
	# rest of the shop. The steel wall shelf, fire-hose reel, gauge panel, safety placard and
	# first-aid box are FLUSH CSG fixtures built in rig_builder._decorate_machine_shop; here we
	# stock the shelf and hang the two glTF wall fittings a shop always carries.
	# Tins ride the two shelf boards (tops y+1.17 / y+1.77); the settle pass rests them.
	_p("oil_tin", Vector3(-25.6, y + 1.22, -6.30), 15)
	_p("cleaner_tin_01", Vector3(-24.6, y + 1.22, -6.30), -20)
	_p("can_rusted", Vector3(-25.1, y + 1.82, -6.30), 0)
	_p("can_rusted", Vector3(-24.4, y + 1.82, -6.28), 40)
	# Fire extinguisher on the south wall by the panel, clock high on the wall — both wall-hung
	# (settle-exempt). Placed a hair proud of the z -6.125 face; the sonar pass verifies flush.
	_pw("korean_fire_extinguisher_01", Vector3(-15.2, y + 1.0, -6.25), 180, 1.1)
	_pw("wall_clock", Vector3(-23.0, y + 2.55, -6.14), 180)

func _stack_more() -> void:
	# Deck B cabins: plants and pictures.
	var b: float = B_Y
	_pw("fancy_picture_frame_01", Vector3(2.2, b + 1.7, 6.2), 0)   # on the pier by the balcony door, off the glass
	_pw("wall_clock", Vector3(14.0, b + 1.9, 11.14), 180)          # quarters alleyway, between doors
	_p("celandine_01", Vector3(6.6, b + 0.82, 8.2), 0)             # B-02 desk (z 7.7..8.3)
	_p("ceramic_vase_02", Vector3(14.7, b + 1.85, 13.8), 0)        # B-06 locker top
	_pc("chinese_stool", Vector3(17.2, b, 15.0), 0)                # B-06, clear of the bunk
	# Deck C control: a plant in the comms corner, a laptop, a chair, a clock on the wall.
	var c: float = C_Y
	_pc("fern_02", Vector3(4.6, c, 17.4), 0)
	_p("classic_laptop", Vector3(6.0, c + 0.82, 7.4), 180)
	_pw("wall_clock", Vector3(12.2, c + 1.9, 9.0), 90)
	_pc("bar_chair_round_01", Vector3(7.0, c, 8.4), 0)
	# Deck D works: more tools + a bronze ray statue on the workshop shelf.
	var d: float = D_Y
	_p("adjustable_wrench", Vector3(22.4, d + 1.3, 16.6), 40)
	_pc("Shelf_01", Vector3(8.6, d, 16.4), 90)
	_p("bronze_ray_statue", Vector3(8.6, d + 1.3, 16.25), 0)
	_p("brass_vase_01", Vector3(8.6, d + 1.3, 16.55), 0)

# ============================================================ scatter
# Small personal/household items on real surfaces. Every coordinate names the surface it
# belongs to in the comment; the settle pass does the last centimetre.

func _scatter_wetdeck() -> void:
	var w: float = WET_Y
	var bench: float = w + 0.75
	# Rigging bench (x 24.2..25.8, z -17.85..-17.15) — a working deck bench. These four
	# were the first floating props a new player ever saw: authored at w+1.06 over a bench
	# whose top is w+0.45, two of them hanging past its west edge over bare deck.
	_p("garden_gloves_01", Vector3(24.5, bench, -17.7), 20)
	_p("can_rusted", Vector3(25.6, bench, -17.6), 0)
	# Hat and oil tin ride the tool chest beside it instead — the bench is full.
	_p("fishermans_hat", Vector3(26.7, w + 1.05, -17.9), -30)
	_p("oil_tin", Vector3(26.65, w + 1.05, -17.6), 40)
	# Pump-room dead-pump top (the orange toolbox sits at 11.6, -12.6, top ~w+2.04).
	_p("russian_food_cans_01", Vector3(11.5, w + 2.25, -12.5), 15)
	# The thermos was authored at z -12.75, which is the toolbox's SOUTH EDGE to the
	# millimetre (box centre -12.6, 0.30 deep), so the settle found no surface under it, it
	# dropped the full 1.8 m to the plating and ended up clipping the dead pump by 0.0031 m3
	# (measured off the live scan). Onto the lid properly: the cans beside it at z -12.5 land
	# at gap +0.01, which is what a correct placement on this surface looks like.
	_p("plastic_thermos", Vector3(11.72, w + 2.25, -12.62), -20)
	_p("plastic_container", Vector3(10.8, w + 0.05, -12.8), 0)
	# Loot-room shelf boards (x 10.4, tops w+0.63 / w+1.33, z -20.3..-17.7) — the crates
	# already standing on them sit at z -19.8 / -19.0 / -18.2, so use the gaps.
	_p("russian_food_cans_01", Vector3(10.4, w + 0.85, -18.6), 10)
	_p("pot_enamel_01", Vector3(10.4, w + 0.85, -20.2), -15)
	_p("can_rusted", Vector3(10.4, w + 1.55, -18.6), 0)
	_p("wicker_basket_01", Vector3(14.6, w + 0.05, -20.6), 30)
	# Store room completion — now that the east archway makes it a room people enter, it
	# earns a proper stores load-out. All clear of the archway (x16, z -17.8..-19.2), the
	# central crate (z-20), the SW kedge (x10.75) and the west shelf (x10.4).
	_pc("Barrel_01", Vector3(15.3, w, -16.7), 0)          # barrels stacked in the NE corner
	_pc("barrel_03", Vector3(14.3, w, -17.0), 20)
	_pc("metal_jerrycan", Vector3(11.0, w, -16.7), 25)    # jerry cans by the west shelf head
	_p("wooden_bucket_01", Vector3(13.7, w + 0.05, -21.4), 0)   # bucket against the south wall
	_p("Lantern_01", Vector3(15.3, w + 1.05, -16.7), 0)   # lantern on the barrels = the room light
	# THE CROWBAR, off the machine-shop bench (owner: spread the tools out). Stood in the
	# store room's SE angle, which is where a pry bar lives: the mesh is 0.7 m tall on its
	# long axis, so upright only reads if two walls are behind it. Interior faces are
	# x 15.875 and z -21.875 (0.25 walls on x16 / z-22), so 0.5 m in from each keeps it clear
	# of the corner post. Nothing else is in that angle — nearest are the bucket at
	# (13.7, -21.4), 1.65 m, and the wicker basket at (14.6, -20.6), 1.06 m — and it is clear
	# of the north door lane (x 12.39..13.61) and the central crate at z -20.
	# +0.65, not +0.0: this prop's origin sits 0.65 m above its mesh base (measured off the
	# sonar scan — see the bolt-cutter note in _wet_deck for the whole trap), so authoring at
	# the floor would bury the bar and let the settle hunt for a surface underneath it.
	_p("crowbar_01", Vector3(15.35, w + 0.65, -21.35), 25)
	_lamp(Vector3(15.0, w + 1.2, -16.9), Color(1.0, 0.85, 0.55), 0.5, 4.5)
	# SPHL interior — the survivor's few things on the aft benches (all west of x18).
	_p("modified_thermos", Vector3(16.6, w + 0.75, -24.9), 10)
	_p("round_spectacles", Vector3(16.0, w + 0.72, -23.1), -20)
	_p("Camera_01", Vector3(15.8, w + 0.75, -23.2), 40)
	_p("wooden_bowl_02", Vector3(17.1, w + 0.72, -24.9), 0)
	# Stair-tower machinery room (y6) — left-behind oddments (the spool moved to the pump room).
	_p("oil_tin", Vector3(27.4, 6.0 + 1.15, 6.2), 20)
	_p("garden_gloves_01", Vector3(25.0, 6.0 + 0.05, 8.6), -10)
	# Breaker Room 4-A (y10). The room is furnished in _breaker_room() now; these two are
	# the hand-put-down items, each named to the surface it lands on. The rusted can used
	# to be authored at z 8.8 — that is 0.125m INSIDE the north wall (inner face 8.675),
	# so it was a tin embedded in concrete beside the breaker.
	_p("clipboard", Vector3(26.60, 10.0 + 0.95, 3.20), 30)   # tossed on the storage cart
	_p("can_rusted", Vector3(21.80, 10.0 + 0.85, 6.28), 0)   # on the maintenance desk

func _scatter_decka() -> void:
	var y: float = DECK_Y
	var tbl: float = y + 0.7
	var counter: float = y + 1.2
	var low: float = y + 0.55
	# Bunkhouse: a second personal item on each locker top. These were authored bed-relative
	# at bed + (1.32, 2.05, -0.68), from the days when the wardrobe stood beside the bunk;
	# rig_builder moved every locker to the head wall (see the note over _bunkhouse), so all
	# six anchors were left over open deck and the settle pass dropped the lot onto the
	# floor — a lighter, spectacles and a cassette player lying in the middle of six cabins.
	# Anchored through _locker_top() they ride the locker, on the opposite quarter of the
	# 0.5m top from the keepsake _bunkhouse() already put there.
	var beds: Array = BUNKS.beds()   # shared with rig_builder — never restate these
	var kit := ["cigarette_pack", "vintage_lighter", "cassette_player", "round_spectacles", "postcard_set_01", "cigarette_case"]
	for i in range(beds.size()):
		var lt: Vector3 = _locker_top(beds[i])
		_p(kit[i], lt + Vector3(0.12, 0.09, 0.11), i * 37.0)
	# The relocated cabin table (-15.7, 13.3) and the nook nightstand (-27.4, 14.0).
	_p("brass_candleholders", Vector3(-15.7, y + 0.95, 13.45), 0)
	_p("wooden_candlestick", Vector3(-15.7, y + 0.95, 13.15), 20)
	_p("standing_picture_frame_01", Vector3(-27.35, y + 0.8, 14.15), 10)
	# Dining hall: dishware + food on the counter (x 1..11, z 16.4..17.6) and the mess tables.
	_p("wooden_bowl_01", Vector3(6.5, counter, 17.0), 0)
	_p("carved_wooden_plate", Vector3(7.6, counter, 17.1), 15)
	_p("tea_set_01", Vector3(9.9, counter, 17.0), -10)
	_p("wooden_cutting_board", Vector3(4.5, counter, 17.1), 0)
	_p("hamburger_buns", Vector3(3.2, counter, 16.7), 20)
	_p("lemon", Vector3(2.4, counter, 17.2), 0)
	_p("wine_bottles_01", Vector3(10.4, counter, 16.9), 0)
	_p("pot_enamel_01", Vector3(9.4, counter, 16.6), 0)
	_p("metal_jug", Vector3(2.0, tbl, 11.0), 30)             # table (2,11)
	_p("wooden_bowl_01", Vector3(8.0, tbl, 11.0), 0)          # table (8,11)
	_p("carved_wooden_plate", Vector3(2.0, tbl, 14.5), -20)
	_p("strawberry_chocolate_cake", Vector3(8.0, tbl, 14.5), 0)
	# Rec room. The shelf top, the credenza top and the low table are all stocked in
	# _rec_room()/_rec_room_more() now that the room has a composition; this pass adds only
	# the last few hand-put-down items, each named to the surface it lands on.
	_p("gamepad", Vector3(22.45, low, 12.75), 20)                  # low table, beside the chess
	_p("vintage_video_camera", Vector3(25.62, y + 0.42, 11.22), 30)  # magazine table (top y+0.34)
	_p("round_spectacles", Vector3(25.42, y + 0.42, 10.92), -15)     # magazine table
	# The book set anchors at its WEST end and runs +0.34m east, so x 27.36 keeps the whole
	# stack on the bench cushion (x 26.90..27.85) instead of hanging off it.
	_p("book_encyclopedia_set_01", Vector3(27.36, y + 0.85, 11.55), 0)  # east bench cushion

func _scatter_deckb() -> void:
	var y: float = B_Y
	var desk: float = y + 0.95
	# Cabins B-01/B-02 — desks at (1.8, 6.9) and (6.9, 8.0), tops y+0.80, 1.2 x 0.6.
	_p("round_spectacles", Vector3(1.8, desk, 6.9), 20)
	_p("cigarette_case", Vector3(2.1, desk, 7.05), -30)
	_p("seadogs_compass", Vector3(6.9, desk, 8.0), 0)
	_p("postcard_set_01", Vector3(6.6, desk, 7.85), 15)
	_p("standing_picture_frame_01", Vector3(7.3, y + 2.05, 6.9), 180)   # B-02 locker top
	_p("vintage_oil_lamp", Vector3(2.4, y + 2.05, 10.2), 0)            # B-01 locker top
	_p("brass_vase_02", Vector3(11.9, y + 0.45, 10.3), 0)              # kelp-shrine plinth
	# Linen store (shelves x 27.6, z 6.4..10.6; tops y+0.63 / 1.33 / 2.03 with bundles).
	_p("throw_pillows_01", Vector3(27.6, y + 1.1, 9.9), 0)
	_p("all_purpose_cleaner", Vector3(27.6, y + 1.6, 9.6), 20)
	# Wash room: toiletries on the counter ENDS (counter x -0.75..3.75, z 16.88..17.73,
	# top y+0.9) — clear of the window centres at x 0 and x 4.
	_p("multi_cleaner_bottle", Vector3(3.4, y + 1.15, 17.3), 0)
	_p("medical_tape", Vector3(-0.5, y + 1.15, 17.3), 20)
	_p("rubber_duck_toy", Vector3(-0.3, y + 1.15, 17.5), -40)
	_p("plunger", Vector3(5.6, y + 0.02, 17.4), 0)             # stood in the corner
	# Crew lounge: the two bench rows are at z 14.2 and z 15.4, tops y+0.5, x 7.5..12.5.
	_p("wooden_bowl_02", Vector3(8.2, y + 0.75, 14.2), 0)
	_p("wine_bottles_01", Vector3(8.7, y + 0.75, 14.3), 15)
	_p("throw_pillows_01", Vector3(11.4, y + 0.75, 15.4), 0)
	_p("filmstrip_projector_8mm", Vector3(12.1, y + 0.75, 15.4), 90)
	# B-06 desk (18, 17.1) + Muster locker crate top (21, 16.8; top y+0.39).
	_p("standing_picture_frame_01", Vector3(18.3, desk, 17.1), 160)
	_p("cigarette_pack", Vector3(17.7, desk, 17.25), 0)
	_p("Megaphone_01", Vector3(21.0, y + 0.95, 16.8), -20)   # crate top settles to y+0.75

func _scatter_deckc() -> void:
	var y: float = C_Y
	var desk: float = y + 0.95
	# Control room consoles (5.8/8.0/10.2, 7.4), tops y+0.80, 1.2 x 0.6 (z 7.1..7.7).
	_p("stationery_supplies", Vector3(5.5, desk, 7.4), 0)
	_p("modified_thermos", Vector3(6.2, desk, 7.6), 20)
	_p("vintage_stapler", Vector3(10.2, desk, 7.4), -15)
	_p("round_spectacles", Vector3(10.6, desk, 7.2), 0)   # clear of the console's multimeter
	# Rig office desk (14.5, 7.5) TURNED 90° — footprint x 14.2..14.8, z 6.9..8.1.
	_p("desk_lamp_arm_01", Vector3(14.5, desk, 7.95), 30)
	_p("stationery_supplies", Vector3(14.5, desk, 7.1), -20)
	_p("modified_thermos", Vector3(17.3, y + 1.5, 7.0), 0)         # filing-cabinet top
	# Med bay exam bench (19.5..21.5, z 7.55..8.45, top y+0.9).
	_p("medical_tape", Vector3(20.3, y + 1.15, 8.0), 0)
	_p("multi_cleaner_bottle", Vector3(20.9, y + 1.15, 8.2), 20)
	_pw("wall_clock", Vector3(21.0, y + 1.8, 11.85), 180)          # med bay north bulkhead
	# East dry store shelves (x 27.25..27.75, z 6.75..11.25, tops y+0.63 / y+1.43).
	_p("russian_food_cans_01", Vector3(27.5, y + 0.85, 8.4), 0)
	_p("pot_enamel_01", Vector3(27.5, y + 0.85, 9.6), 0)
	_p("CheeseBox_01", Vector3(27.5, y + 1.65, 8.6), 0)
	_p("jug_01", Vector3(27.5, y + 1.65, 9.5), 0)
	# Comms desk (6.0, 16.8), top y+0.80, x 5.4..6.6, z 16.5..17.1.
	_p("Megaphone_01", Vector3(6.0, desk, 16.8), 180)
	_p("cigarette_pack", Vector3(5.6, desk, 16.6), 20)
	_p("magnifying_glass_01", Vector3(6.4, desk, 17.0), -30)
	# Mud logging: radio desk against the east bulkhead + an instrument rack top (y+1.8).
	_p("stationery_supplies", Vector3(22.2, y + 1.0, 15.8), 0)
	_p("alarm_clock_01", Vector3(22.2, y + 1.0, 16.7), 160)
	_p("magnifying_glass_01", Vector3(17.5, y + 2.0, 17.4), 40)

func _scatter_deckd() -> void:
	var y: float = D_Y
	var bench: float = y + 1.2        # washer top is y+1.0
	# Gym: the weight bench (x 10.2..10.8, z 9.2..10.8, top y+0.6); the rest on the floor
	# against the walls, which is where gym kit honestly lives.
	_p("garden_gloves_01", Vector3(10.5, y + 0.85, 10.4), 20)
	_p("plastic_bottle_gallon", Vector3(10.5, y + 0.85, 9.6), 0)
	_p("baseball_bat", Vector3(15.1, y + 0.05, 8.7), 70)
	# Laundry: washer tops (x 17 / 18.5 / 20, z 8.35..9.25).
	_p("bleach_bottle", Vector3(17.0, bench, 8.8), 0)
	_p("throw_pillows_01", Vector3(18.5, bench, 8.8), 0)           # folded coveralls stand-in
	_p("multi_cleaner_bottle", Vector3(20.0, bench, 8.8), 20)
	_p("plastic_broom", Vector3(15.9, y + 0.02, 12.6), 10)
	# Storage: crate stacks at x 8.65..9.75 (top y+0.8) and x 9.95..11.05 (top y+1.6);
	# the stashed footlocker in the crouch nook has a top at y+0.39.
	_p("vintage_oil_lamp", Vector3(9.2, y + 1.05, 17.0), 0)
	_p("wicker_basket_02", Vector3(10.5, y + 1.85, 17.0), 30)
	_p("standing_picture_frame_01", Vector3(8.9, y + 0.95, 15.6), 20)
	# THE FLOATING METAL DETECTOR. Authored at the Deck D floor and found by the sonar scan
	# hanging in the DECK C mud-log room, base y26.91 — 1.8m up that room's north wall, on
	# top of an instrument rack, which is the "metal detector mounted high on a wall" the
	# owner photographed. Cause: this glTF is the one prop in the library whose mesh hangs
	# BELOW its origin. Its single node carries a rotation quaternion, so the model's AABB
	# in root space runs y -0.93..+0.20 (scaled to the 1.2m size hint) — the origin sits
	# 0.93m ABOVE the bottom of the mesh. Placing the origin at floor+0.05 therefore dropped
	# the whole detector through the Deck D slab, and the settle pass then rested it on the
	# first real surface it could see underneath: the Deck C rack, a storey down.
	# Authored at floor + 0.98 the mesh base starts ~5cm clear of the Deck D deck and the
	# settle seats it flush. Tucked into the store's north-east corner as before.
	_p("metal_detector", Vector3(14.8, y + 0.98, 17.6), 40)        # leaned in the store corner
	# Workshop craft bench (x 18.15..19.85, z 16.6..17.4, top y+0.96) — the scattered tools
	# were authored west of x 18.15, i.e. off the bench entirely.
	_p("flathead_screwdriver", Vector3(18.4, y + 1.2, 17.1), 40)
	_p("pliers", Vector3(18.8, y + 1.2, 17.25), -30)
	_p("measuring_tape_01", Vector3(19.2, y + 1.2, 16.85), 0)
	_p("lubricant_spray", Vector3(19.6, y + 1.2, 17.2), 10)
	_p("spray_paint_bottles", Vector3(19.4, y + 1.2, 16.7), 0)
	# East vestibule, inside the rails.
	_p("watering_can_metal_01", Vector3(26.8, y + 0.05, 9.0), 0)
