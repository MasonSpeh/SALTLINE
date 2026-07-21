extends Node
## Makes the rig's EXISTING cabinets, chests, lockers and drawer units usable as stashes.
##
## The crew left steel job boxes, tool chests and wall cabinets all over this platform and
## every one of them was scenery. A player who has just crafted a bedroll and a brazier
## wants to put things down somewhere near them — and the most believable somewhere is the
## locker that is already bolted to that bulkhead, not a crate they have to build first.
##
## Implemented as a self-contained scanner rather than an edit to the dressing scripts:
## it walks the tree once the world is up, matches prop nodes by name against STORABLE,
## and hangs a LootContainer proxy on each. That means no coordinates move, nothing about
## the dressing pass changes, and the same crate/pack exchange panel the HUD already owns
## does the work — so a found locker behaves exactly like a built one.

const LOOT := preload("res://scripts/components/loot_container.gd")

## Prop-name fragments that read to a player as "this opens and holds things".
## Matched case-insensitively against the node name PropLib gives each spawned prop.
const STORABLE: Array[String] = [
	"tool_chest", "toolbox", "metal_toolbox", "job_box",
	"cabinet", "locker", "cupboard", "drawer", "sideboard",
	"footlocker", "trunk", "chest_", "storage_box", "crate_wood",
	"nightstand", "trash_can",
]

## Never turn these into stashes even if the name matches: they are containers the game
## already drives (loot caches, the gull nest), or fixtures whose interaction is spoken for.
const EXCLUDE: Array[String] = ["nest", "fridge", "stove", "oven", "washing", "dishwasher"]

## Model SUB-MESH names. A glTF prop's internals are often storable-named — the office
## desk carries six meshes literally called metal_office_desk_drawer_01.., a tool chest
## has *_lid / *_hinge_* / *_handle_* parts. Those are pieces of a prop, never props;
## without this filter each one adopted as its own stash ("Drawer Unit x12"), including
## inside salvage stations whose contents would vanish with the dismantled prop.
## (No "_chest" here — that substring is part of the tool chest's own root name; a
## chest's inner *_chest mesh is deduped by _under_loot_container instead.)
const PART_NAMES: Array[String] = [
	"_drawer_0", "_drawer_1", "_lid", "_handle", "_hinge", "_lock", "_latch",
]

## How far above the prop's base the interaction volume sits, and how big it is. A found
## locker should be reachable from standing height without swallowing the doorway beside it.
const PAD: float = 0.06

var _adopted: int = 0

func _ready() -> void:
	# The dressing STREAMS in over many seconds (interior_props instances a few props per
	# frame, then settles them), so one scan at t=3 raced it — whichever cabinets hadn't
	# landed yet stayed scenery, and the adopted count varied run to run. Sweep several
	# times instead; a prop already adopted carries a LootContainer child, which the
	# Interactable-child guard in _scan skips, so re-sweeping is idempotent and cheap.
	for i in range(6):
		await get_tree().create_timer(3.0).timeout
		var root: Node = get_tree().current_scene
		if root == null:
			root = get_parent()
		_scan(root)
	if _adopted > 0:
		print("[world_storage] adopted %d found containers" % _adopted)

func _scan(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Node3D) or n is LootContainer:
			continue
		if not _is_storable(n):
			continue
		# Skip anything that already answers to the player — a salvage station, a
		# takeable, a comfort fixture. Two prompts on one object is worse than none.
		if n is Interactable or _has_interactable_child(n):
			continue
		# ONE stash per prop. Parents are processed before children in this walk, so by
		# the time a prop's inner mesh comes up, the prop root already carries its
		# LootContainer — a claimed ancestry means this subtree is spoken for. (The
		# PART_NAMES filter in _is_storable handles the other half: model sub-meshes
		# named *_drawer_NN / *_lid / *_handle that belong to props this scanner never
		# adopts at all, like the salvage office desk.)
		if _under_loot_container(n):
			continue
		# A LootContainer under a RigidBody3D is invalid (a static body riding a moving
		# one floods the log) — and carryable props shouldn't be stashes anyway: you pick
		# those up. A StaticBody3D wrapper is FINE though: fixed furniture (the drawer
		# cabinets, tool chests, bins — everything PropLib.FIXED) spawns wrapped in one,
		# and the old blanket CollisionObject3D guard was silently rejecting all of it,
		# which is why only a couple of containers ever got adopted.
		if _inside_rigid_body(n):
			continue
		_adopt(n as Node3D)

func _is_storable(n: Node) -> bool:
	var low: String = n.name.to_lower()
	for bad in EXCLUDE:
		if low.contains(bad):
			return false
	for part in PART_NAMES:
		if low.contains(part):
			return false
	for frag in STORABLE:
		if low.contains(frag):
			return true
	return false

## True when this node IS a RigidBody3D or sits under one. Nesting a StaticBody3D
## inside a RigidBody3D is invalid in Godot and floods the log (it is what silently
## broke the test run when this scanner first landed). Static ancestry is allowed —
## fixed furniture is wrapped in a StaticBody3D by PropLib and hosts a stash fine.
func _inside_rigid_body(n: Node) -> bool:
	var cur: Node = n
	while cur != null:
		if cur is RigidBody3D:
			return true
		cur = cur.get_parent()
	return false

func _has_interactable_child(n: Node) -> bool:
	for c in n.get_children():
		if c is Interactable:
			return true
	return false

## True when `n` sits under a node WITHIN ITS OWN PROP that is (or hosts) a LootContainer
## — the prop is adopted, or is itself a built crate; its inner meshes must not sprout
## stashes of their own. The walk stops at the first scripted ancestor: builder roots
## (rig_builder, interior_props, wet_deck_detail...) all carry scripts and parent HUNDREDS
## of unrelated nodes — including the built crates, which are LootContainers themselves —
## so walking past the prop's own scope reads the whole rig as "claimed" and kills every
## adoption. Prop internals are plain script-less scene nodes, so the script boundary IS
## the prop boundary.
func _under_loot_container(n: Node) -> bool:
	var cur: Node = n.get_parent()
	while cur != null:
		if cur is LootContainer:
			return true
		for c in cur.get_children():
			if c is LootContainer:
				return true
		if cur.get_script() != null:
			return false   # reached a builder/system node — the prop's scope has ended
		cur = cur.get_parent()
	return false

## Hang a LootContainer on the prop, sized to the prop's own bounds, and seed it with a
## little of what a locker on an abandoned rig would plausibly still hold.
func _adopt(prop: Node3D) -> void:
	var bounds: AABB = _tree_aabb(prop)
	if bounds.size == Vector3.ZERO:
		return
	# Too small to be a container (a hand tool named "toolbox_small_detail", say).
	# Judge by SORTED dimensions, not by the x axis: the old `size.x < 0.25` test was
	# axis-roulette — the drawer cabinet is a tall narrow unit (0.23 x 0.9 x 0.55) and
	# happened to face its thin side down x, so the one prop literally made of drawers
	# was the one the storage pass rejected. A real container is big on two axes.
	var dims: Array = [bounds.size.x, bounds.size.y, bounds.size.z]
	dims.sort()
	if dims[2] < 0.45 or dims[1] < 0.2:
		return
	var box: LootContainer = LOOT.new()
	box.display_name = _pretty(prop.name)
	var seeded: Array[String] = _seed_for(prop.name)
	box.items = seeded
	prop.add_child(box)
	box.global_position = bounds.get_center()
	var shape := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bounds.size + Vector3(PAD, PAD, PAD)
	shape.shape = sh
	box.add_child(shape)
	_adopted += 1

## Deterministic contents from the node name — no RNG, so a save reloads the same rig.
## Most are empty: a stash you find full is a loot pinata, a stash you find empty is
## yours to fill, and this game is about the second thing.
func _seed_for(name_: String) -> Array[String]:
	var h: int = 0
	for i in range(name_.length()):
		h = (h * 31 + name_.unicode_at(i)) % 100003
	var out: Array[String] = []
	match h % 6:
		0: out.append("scrap_metal")
		1: out.append("rope")
		2: out.append("driftwood")
		_: pass                        # 50% stay empty — space to put your own things
	return out

func _pretty(raw: String) -> String:
	var low: String = raw.to_lower()
	if low.contains("chest"):
		return "Tool Chest"
	if low.contains("toolbox"):
		return "Toolbox"
	if low.contains("drawer"):
		return "Drawer Unit"
	if low.contains("cabinet") or low.contains("cupboard"):
		return "Cabinet"
	if low.contains("crate"):
		return "Crate"
	return "Locker"

func _tree_aabb(n: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var mi := cur as MeshInstance3D
			var w: AABB = mi.global_transform * mi.get_aabb()
			acc = w if first else acc.merge(w)
			first = false
	return acc if not first else AABB()
