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
	# Pull the galley bulkhead's two stray fittings into the composition documented
	# above the galley section. Safe to run here: rig_builder calls _density_a()
	# (which authors them) BEFORE it adds this node, so they already exist.
	_galley_bulkhead_layout()
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

	# ---- the pump READY ROOM (respawn lives here now) ----
	# The drained pump room keeps its aftermath — stains, silt, the dead pump — but
	# someone has moved in: a cot along the north wall, a storage rack squared on the
	# west wall, safety gear where a hand finds it from the bunk. The respawn point
	# (15.0, +0.6, -10.5) wakes up facing the east archway and open deck beyond.
	_pc("vintage_day_bed", Vector3(14.3, y, -6.9), 180)          # cot, back to the north wall
	_pc("worn_metal_rack", Vector3(10.38, y, -8.6), -90)         # rack flush on the west wall (face x 10.125)
	_p("medical_tape", Vector3(10.38, y + 1.3, -8.5), 30)        # first-aid on the rack shelf
	# Authored onto the rack shelf, but SupportIndex never sees the GLB's thin shelf
	# boards, so settle dropped it to the deck INSIDE the rack frame — a tote visibly
	# clipping through both rack rails (sonar overlap: 76% of its volume inside the
	# rack's AABB). On the deck beside the rack it settles clean.
	_p("plastic_container", Vector3(10.42, y + 0.02, -9.5), -37)
	_p("vintage_flashlight", Vector3(13.3, y + 0.02, -7.6), 70)  # dropped by the cot
	_pc("folding_wooden_stool", Vector3(15.9, y, -7.4), 30)      # pulled to the cot's foot
	_pw("lifebuoy", Vector3(17.82, y + 1.7, -12.2), -90, 1.1)    # east wall, seen from the arch
	_pw("life_jacket", Vector3(12.6, y + 1.5, -6.24), 180)       # hung over the cot
	# The room light used to be a bare OmniLight floating 1m off the wall above the
	# cot — warm light from empty air. Now a pipe lamp on the north wall carries it.
	_pw("industrial_pipe_lamp", Vector3(14.3, y + 2.15, -6.3), 180)
	_lamp(Vector3(14.3, y + 1.95, -6.75), Color(1.0, 0.83, 0.5), 0.55, 4.5)

# ---- galley ----
# Counter run: top y+1.0, x 1..11, z 16.4..17.6.  Mess tables: top y+0.49, 1.8 x 1.0, at
# (2,11) (8,11) (2,14.5) (8,14.5).  Wall shelves x -1.6: tops y+1.63 / y+2.23, z 10.9..14.1
# with canned rows already standing at z 11.2/11.8/12.4/13.0/13.6 — leave those gaps alone.
#
# THE WEST BULKHEAD (galley wall). Its inner face is x = -1.875 (wall centreline x -2,
# WALL_T 0.25) and it runs z 8.125..17.875. See _galley_bulkhead_layout() for the
# composition; the zones it reserves are:
#   z  8.3..8.9   deck corner: the potted plant
#   z  8.95..10.15, y+1.38..y+2.18   the chalk/notice board (clear wall, nothing on it)
#   z  9.55, y+2.65                  the mess clock, centred over the board
#   z 10.5                           structural conduit drop (rig_builder) — leave alone
#   z 10.9..14.1, y+1.6 / y+2.2      the two pantry shelves and their can rows
#   z 11.85..13.35, y+2.65           the PAINTED stencil, on bare plate above the shelves
#   z 14.75..15.65                   the fridge
# The y+2.65 line is a deliberate datum: clock and paint share it, everything else sits
# below, so the wall reads as composed rather than piled.

## Repair the galley bulkhead's stacked fittings.
##
## The board and the stencil are authored in rig_builder._density_a() at the SAME spot
## (-1.86 / -1.82, DECK_Y+1.9, 12.5) — dead centre of the pantry-shelf run. The result
## the owner photographed: painted lettering silk-screened across a dark notice board,
## both shelves and both rows of cans cutting straight through the pair of them.
##
## Nothing here re-authors that dressing; it only moves two existing nodes into the free
## zones the wall already has. This file settling other builders' props at runtime is an
## established pattern (see _settle_pass, which sweeps the whole tree). Both lookups are
## gated on an exact signature — position, size, text — so if rig_builder is ever fixed
## at source this silently no-ops instead of fighting it. FOLD INTO rig_builder.gd AND
## DELETE FROM HERE when that file is next opened.
func _galley_bulkhead_layout() -> void:
	var y: float = DECK_Y
	var host: Node = get_parent()
	if host == null:
		return
	for n in host.get_children():
		# The notice board: 0.05 x 0.8 x 1.2 slab buried in the shelf run.
		# Rehung on the clear south panel, back flush to the wall face (x -1.875).
		if n is CSGBox3D:
			var b := n as CSGBox3D
			if b.size.is_equal_approx(Vector3(0.05, 0.8, 1.2)) \
					and b.position.distance_to(Vector3(-1.86, y + 1.9, 12.5)) < 0.05:
				b.position = Vector3(-1.85, y + 1.78, 9.55)
		# The stencil is PAINT. It moves up onto the bare plate above the shelves, on the
		# y+2.65 datum: clear of the upper shelf (top y+2.23, cans to y+2.41) and clear
		# of the ceiling beam that lands at y+2.82. 0.01 proud of the wall so it does not
		# z-fight the plate it is painted on.
		elif n is Label3D and (n as Label3D).text.contains("LAST MENU"):
			n.position = Vector3(-1.865, y + 2.65, 12.6)
	_galley_board_dressing()

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

func _galley() -> void:
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
	# A mess stool pushed back from a table, a thermos left on a table top. Was a white
	# plastic garden monobloc — the one object in the galley that read as suburban patio
	# furniture rather than as something a supply boat landed on a North Sea rig.
	_pc("metal_stool_01", Vector3(4.3, y, 12.9), 30)
	_p("modified_thermos", Vector3(8.5, y + 0.7, 11.3), 60)
	_p("russian_food_cans_01", Vector3(2.5, y + 0.7, 14.15), -30)
	# A trash can by the fridge, overflowing a little.
	_pc("metal_trash_can", Vector3(0.2, y, 16.6), 0)

# ---- bunkhouse ----
# Six bunks at z 6.5 (south row) / z 15.5 (north row), x -25.5 / -18.8 / -12.0.
# Each has a steel locker at bed + (1.2, *, -0.8), top y+1.8, and a footlocker at
# bed + (0, *, 1.45), top y+0.4.  THE CORRIDOR IS z 10..12 AND STAYS EMPTY — the sitting
# nook and the shared table that used to stand in it are now inside cabins.

func _bunkhouse() -> void:
	var y: float = DECK_Y
	# Six single cabins (2 rows x 3): A/B/C west-to-east, south row (z4..10) and north
	# row (z12..18). Each has its bunk on the WEST side against the head wall and a
	# head-wall wardrobe (both built in rig_builder). This pass gives every cabin one
	# distinct, wall-aligned piece on the EAST side against the divider it shares — so
	# each reads as a different crew member's room, and nothing stands free in the middle.
	# East-divider interior faces: A x-21.455 · B x-14.785 · C x-8.125.
	var beds := [Vector3(-25.5, y, 6.5), Vector3(-18.8, y, 6.5), Vector3(-12.0, y, 6.5),
			Vector3(-25.5, y, 15.5), Vector3(-18.8, y, 15.5), Vector3(-12.0, y, 15.5)]

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
	_pc("ArmChair_01", Vector3(-21.95, y, 13.3), 215)
	_pc("ClassicNightstand_01", Vector3(-21.8, y, 14.7), -90)
	_p("book_encyclopedia_set_01", Vector3(-21.8, y + 0.8, 14.7), 0)
	_p("Lantern_01", Vector3(-21.95, y + 0.8, 14.25), 0)
	_lamp(Vector3(-21.85, y + 1.0, 14.4), Color(1.0, 0.85, 0.55), 0.5, 4.0)

	# --- B-N · the radio op: the set squared on a table against the east divider. ---
	_pc("small_wooden_table_01", Vector3(-15.15, y, 15.0), -90)
	_pc("WoodenChair_01", Vector3(-16.3, y, 15.0), 90)
	_p("vintage_radio_transceiver", Vector3(-15.1, y + 0.5, 15.0), 200)

	# --- C-N · the bosun: a sea chest against the divider, kit stowed on the lid. ---
	_pc("drawer_cabinet", Vector3(-8.5, y, 15.0), -90)
	_p("binoculars", Vector3(-8.55, y + 0.95, 15.25), 20)
	_p("old_gas_mask", Vector3(-8.55, y + 0.95, 14.7), -30)

	# Each crew member's few things on their head-wall wardrobe top (locker at bed.x+1.15,
	# z 4.55 south / 17.45 north, top y+1.8) — now that the lockers sit where the comment
	# always claimed, these land on a real surface instead of the old floating box.
	var lock := ["ceramic_vase_01", "food_apple_01", "decorative_book_set_01",
			"brass_goblets", "plastic_thermos", "round_spectacles"]
	for i in range(beds.size()):
		var p: Vector3 = beds[i]
		var lz: float = 4.55 if p.z < 11.0 else 17.45
		_p(lock[i], Vector3(p.x + 1.15, y + 1.85, lz), i * 33.0)
	# Corridor (z10..12) keeps only wall-hung items, between the cabin doors and clear of
	# the 1.2m walk lane: a fire point and a framed photo. Life jacket by the C-S door.
	_pw("korean_fire_extinguisher_01", Vector3(-15.0, y + 0.9, 10.2), 180, 1.1)
	_pw("fancy_picture_frame_02", Vector3(-21.0, y + 1.6, 11.8), 0)
	_pw("life_jacket", Vector3(-8.25, y + 1.5, 6.2), -90)

# ---- rec room ----
# Low table top y+0.32 (x 22.25..23.75, z 12.03..12.98). Couch top y+0.7 (x 21.8..24.2,
# z 8.7..9.7). Bookshelf top y+2.0 (x 24.6..26.4, z 17.43..17.78). West door at (18, 11).

func _rec_room() -> void:
	var y: float = DECK_Y
	var low: float = y + 0.55        # low table top is y+0.32
	_p("boombox", Vector3(22.5, low, 12.3), 30)
	_p("plastic_thermos", Vector3(22.5, y + 0.75, 10.4), -40)   # on the ottoman
	# Television on its stand, backed against the east bulkhead (interior face x 27.875).
	_pc("small_wooden_table_01", Vector3(27.3, y, 12.5), -90)
	_pc("television_02", Vector3(27.3, y + 1.0, 12.3), -90)
	# A worn chair facing the table, and a stool.
	_pc("painted_wooden_chair_01", Vector3(20.7, y, 12.4), 100)
	_pc("metal_stool_02", Vector3(24.6, y, 14.2), -60)
	# Reading light on the bookshelf top (top y+2.0, x 24.6..26.4, z 17.43..17.78).
	_p("Lantern_01", Vector3(25.35, y + 2.25, 17.6), 0)
	_lamp(Vector3(25.5, y + 2.5, 17.4), Color(1.0, 0.83, 0.52), 0.4, 3.5)

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

func _galley_more() -> void:
	var y: float = DECK_Y
	var tbl: float = y + 0.7          # mess table top is y+0.49
	var counter: float = y + 1.2
	# Food and comfort on the mess tables — the meal that never got eaten.
	_p("carrot_cake", Vector3(2.4, tbl, 11.0), 0)
	_p("croissant", Vector3(8.4, tbl, 14.5), 40)
	_p("bananas", Vector3(1.6, tbl, 14.5), 0)
	_p("brass_pot_01", Vector3(11.8, counter, 16.2), 0)     # on the stove
	_p("brass_pan_01", Vector3(11.2, counter, 15.9), 30)
	# Chairs actually pulled up to the tables — the mess is a deliberate centre piece.
	for tp in [Vector3(2, y, 11), Vector3(8, y, 11), Vector3(2, y, 14.5), Vector3(8, y, 14.5)]:
		_pc("WoodenChair_01", tp + Vector3(0, 0, -1.0), 0)
		_pc("WoodenChair_01", tp + Vector3(0, 0, 1.0), 180)
	# West bulkhead, south end: the plant tucked into the corner clear of the notice
	# board above it (board bottom y+1.30, z 8.95..10.15 — the plant used to stand at
	# z 9.0 with its leaves reaching into that panel), and the mess clock centred over
	# the board on the y+2.65 paint datum.
	_pc("ceramic_pot", Vector3(-1.4, y, 8.55), 0)
	_p("calathea_orbifolia_01", Vector3(-1.4, y + 0.6, 8.55), 0)
	_pw("alarm_clock_01", Vector3(-1.8, y + 2.65, 9.55), 90)
	_p("plastic_thermos", Vector3(6.0, counter, 17.0), -60)

func _bunkhouse_more() -> void:
	var y: float = DECK_Y
	# Finishing touches only — the cabins are furnished in _bunkhouse(); this hangs a
	# framed picture on a real bulkhead in three of them and stands one plant in a
	# corner, so six identical shells read as six lived-in homes. Everything is flush
	# against a wall (west/head bulkheads) or tucked into a corner, nothing in a walk line.
	_pw("fancy_picture_frame_01", Vector3(-27.8, y + 1.6, 7.0), 90)     # A-S, west bulkhead
	_pw("fancy_picture_frame_02", Vector3(-8.2, y + 1.6, 16.0), -90)    # C-N, east bulkhead
	_pw("fancy_picture_frame_01", Vector3(-18.8, y + 1.6, 4.15), 0)     # B-S, head wall
	_pc("fern_02", Vector3(-27.4, y, 16.9), 0)                          # A-N, NW corner
	_p("celandine_01", Vector3(-11.4, y + 1.85, 17.45), 0)             # C-N wardrobe-top sprig

func _rec_room_more() -> void:
	var y: float = DECK_Y
	var low: float = y + 0.55
	# The rec room earns its name: dartboard, chess mid-game, a real sofa.
	# The board hangs on the EAST bulkhead (interior face x 27.875), facing back across
	# the room with a clear throwing lane.
	_pw("dartboard", Vector3(27.82, y + 1.8, 15.5), -90)
	_p("chess_set", Vector3(23.3, low, 12.4), 20)           # on the low table
	# Seating along the south wall, an L with the built-in couch; ottoman in front.
	_pc("Sofa_01", Vector3(20.6, y, 8.8), 0)
	_pc("Ottoman_01", Vector3(22.5, y, 10.4), 0)
	# A bronze Bloom-creature statue up on the bookshelf — someone was already a believer.
	_p("bronze_whale_statue", Vector3(26.2, y + 2.25, 17.6), -20)
	_pc("fir_sapling", Vector3(26.9, y, 8.7), 0)
	_p("classic_laptop", Vector3(22.6, y + 0.95, 9.2), 200)  # left open on the couch (top y+0.7)
	_p("food_avocado_01", Vector3(22.9, low, 12.85), 0)

func _machine_shop_more() -> void:
	var y: float = DECK_Y
	var bench: float = y + 0.96
	# The rest of the tool wall, resting on the fitter's bench top.
	_p("crowbar_01", Vector3(-20.55, bench, -12.55), 60)
	_p("bolt_cutters_01", Vector3(-19.05, bench, -11.7), -40)
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
	_p("plastic_thermos", Vector3(11.75, w + 2.25, -12.75), -20)
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
	_lamp(Vector3(15.0, w + 1.2, -16.9), Color(1.0, 0.85, 0.55), 0.5, 4.5)
	# SPHL interior — the survivor's few things on the aft benches (all west of x18).
	_p("modified_thermos", Vector3(16.6, w + 0.75, -24.9), 10)
	_p("round_spectacles", Vector3(16.0, w + 0.72, -23.1), -20)
	_p("Camera_01", Vector3(15.8, w + 0.75, -23.2), 40)
	_p("wooden_bowl_02", Vector3(17.1, w + 0.72, -24.9), 0)
	# Stair-tower machinery room (y6) beside the spool + NW corner.
	_p("oil_tin", Vector3(27.4, 6.0 + 1.15, 6.2), 20)
	_p("garden_gloves_01", Vector3(25.0, 6.0 + 0.05, 8.6), -10)
	# Breaker Room 4-A (y10) — utilitarian floor corners.
	_p("clipboard", Vector3(26.6, 10.0 + 0.02, 3.2), 30)
	_p("can_rusted", Vector3(27.0, 10.0 + 0.05, 8.8), 0)

func _scatter_decka() -> void:
	var y: float = DECK_Y
	var tbl: float = y + 0.7
	var counter: float = y + 1.2
	var low: float = y + 0.55
	# Bunkhouse: a second personal item on each locker top (top = bed + (1.2, 1.8, -0.8)).
	var beds := [Vector3(-25.5, y, 6.5), Vector3(-18.8, y, 6.5), Vector3(-12.0, y, 6.5),
			Vector3(-25.5, y, 15.5), Vector3(-18.8, y, 15.5), Vector3(-12.0, y, 15.5)]
	var kit := ["cigarette_pack", "vintage_lighter", "cassette_player", "round_spectacles", "postcard_set_01", "cigarette_case"]
	for i in range(beds.size()):
		var p: Vector3 = beds[i]
		_p(kit[i], p + Vector3(1.32, 2.05, -0.68), i * 37.0)
	# The relocated cabin table (-15.7, 13.3) and the nook nightstand (-27.4, 14.0).
	_p("brass_candleholders", Vector3(-15.7, y + 0.95, 13.45), 0)
	_p("wooden_candlestick", Vector3(-15.7, y + 0.95, 13.15), 20)
	_p("standing_picture_frame_01", Vector3(-27.35, y + 0.8, 14.15), 10)
	# Galley: dishware + food on the counter (x 1..11, z 16.4..17.6) and the mess tables.
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
	# Rec room: shelf top (x 24.6..26.4, z 17.6), TV stand, low table, couch, stool.
	_p("mantel_clock_01", Vector3(24.85, y + 2.25, 17.6), 180)
	_p("brass_candleholders", Vector3(25.8, y + 2.25, 17.6), 0)
	_p("gaming_console", Vector3(27.3, y + 1.0, 12.8), -90)
	_p("gamepad", Vector3(23.5, low, 12.8), 20)
	_p("sungka_board", Vector3(24.6, y + 0.85, 14.2), 0)     # left out on the stool
	_p("baseball_01", Vector3(21.2, y + 0.05, 10.8), 0)      # rolled under the sofa
	_p("vintage_video_camera", Vector3(23.7, y + 0.95, 9.25), 30)   # on the couch

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
	_p("metal_detector", Vector3(14.8, y + 0.05, 17.6), 40)        # leaned on the store wall
	# Workshop craft bench (x 18.15..19.85, z 16.6..17.4, top y+0.96) — the scattered tools
	# were authored west of x 18.15, i.e. off the bench entirely.
	_p("flathead_screwdriver", Vector3(18.4, y + 1.2, 17.1), 40)
	_p("pliers", Vector3(18.8, y + 1.2, 17.25), -30)
	_p("measuring_tape_01", Vector3(19.2, y + 1.2, 16.85), 0)
	_p("lubricant_spray", Vector3(19.6, y + 1.2, 17.2), 10)
	_p("spray_paint_bottles", Vector3(19.4, y + 1.2, 16.7), 0)
	# East vestibule, inside the rails.
	_p("watering_can_metal_01", Vector3(26.8, y + 0.05, 9.0), 0)
