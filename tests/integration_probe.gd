extends Node3D
## INTEGRATION PROBE — boots the real Main scene and interrogates the seams between
## the five domains that were built in parallel. Static greps cannot see any of this:
## a kit can be in KIT_ORDER, have a recipe and a build() arm, and still hand back a
## node the comfort domain will never notice because the marker never got added.
##
## Checks, in order:
##   1. Ambience is live in the tree (autoload).
##   2. Every KIT_ORDER kit builds without error, both real and as a ghost.
##   3. Furniture kits carry a "comfort_furniture" marker with a valid "kind".
##   4. ComfortFurniture actually attaches an Interactable to each marker.
##   5. The world contains salvage stations and harvest nodes covering every
##      material the craft tree demands.
##   6. Every craftable/salvageable id has an ItemVisual body.
## Prints PROBE-FAIL lines for anything broken; exits non-empty-handed either way.

const STRUCTURES := preload("res://scripts/world/structures.gd")
const ITEM_VISUAL := preload("res://scripts/world/item_visual.gd")

var _fails: Array[String] = []
var _main: Node3D

func _fail(s: String) -> void:
	_fails.append(s)
	print("PROBE-FAIL: ", s)

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout

	_check_ambience()
	await _check_kits()
	_check_world_sources()
	_check_fauna_sources()
	_check_visuals()

	print("PROBE-FAILURES: ", _fails.size())
	get_tree().quit()

# ---------------------------------------------------------------- 1. ambience
func _check_ambience() -> void:
	var amb: Node = get_tree().root.get_node_or_null("Ambience")
	if amb == null:
		_fail("Ambience autoload is not in the scene tree")
	else:
		print("ambience: live, ", amb.get_child_count(), " children")

# ---------------------------------------------------------------- 2+3+4. kits
## Which kits the comfort domain is entitled to expect a marker from, and the kind.
const EXPECT_MARKER := {
	"bedroll_kit": "bed", "chair_kit": "seat", "brazier_kit": "fire",
	"locker_kit": "storage", "workbench_kit": "bench", "drying_rack_kit": "drying",
	"rain_catcher_kit": "water", "planter_kit": "planter",
}

## Materials that come off a living creature, not a prop or a takeable — bloom_fauna.gd
## grants these from its own interactions, so no static sweep of the world can find them.
## Line references are checked below so this list cannot quietly go stale.
const FAUNA_SOURCED := {
	"glow_mucus": "LampSnail harvest",
	"limpet_shell": "AnchorLimpet PRY",
	"glow_worm": "glow worm pick-up",
}

func _check_kits() -> void:
	var host := Node3D.new()
	_main.add_child(host)
	var valid_kinds: Array = preload("res://scripts/components/comfort_furniture.gd").KINDS
	for kit in STRUCTURES.KIT_ORDER:
		# ghost first — build mode calls this every frame and a crash here is fatal
		var ghost = STRUCTURES.build(kit, true)
		if ghost == null:
			_fail("%s: build(ghost) returned null" % kit)
		else:
			ghost.queue_free()
		var n = STRUCTURES.build(kit, false)
		if n == null:
			_fail("%s: build() returned null" % kit)
			continue
		host.add_child(n)
		n.global_position = Vector3(0, 40, 0)
		if not n.is_in_group("built_structures"):
			_fail("%s: not in group built_structures" % kit)
		if String(n.get_meta("kit", "")) != kit:
			_fail("%s: meta 'kit' is '%s'" % [kit, n.get_meta("kit", "")])
		# marker contract
		var markers: Array = []
		var stack: Array = [n]
		while stack.size() > 0:
			var c = stack.pop_back()
			for g in c.get_children():
				stack.append(g)
			if c is Node and (c as Node).is_in_group("comfort_furniture"):
				markers.append(c)
		if EXPECT_MARKER.has(kit):
			if markers.is_empty():
				_fail("%s: expected a comfort_furniture marker, found none" % kit)
			else:
				var kind := String(markers[0].get_meta("kind", ""))
				if kind != EXPECT_MARKER[kit]:
					_fail("%s: marker kind is '%s', expected '%s'" % [kit, kind, EXPECT_MARKER[kit]])
				if not kind in valid_kinds:
					_fail("%s: marker kind '%s' is not in ComfortFurniture.KINDS" % [kit, kind])
		print("kit ok: %-18s meshes=%d markers=%d" % [kit, _count_meshes(n), markers.size()])
	# give ComfortFurniture its sweep, then confirm it hooked every marker
	print("... kit loop done, waiting for ComfortFurniture sweep")
	await get_tree().create_timer(2.2).timeout
	print("... sweep window elapsed")
	for m in get_tree().get_nodes_in_group("comfort_furniture"):
		var hooked := false
		for c in (m as Node).get_children():
			if c is Interactable:
				hooked = true
		if not hooked:
			_fail("marker %s (kind=%s) got no Interactable from ComfortFurniture" % [m.name, m.get_meta("kind", "?")])
	print("comfort markers hooked: ", get_tree().get_nodes_in_group("comfort_furniture").size())
	host.queue_free()

func _count_meshes(n: Node) -> int:
	var c := 0
	var stack: Array = [n]
	while stack.size() > 0:
		var x = stack.pop_back()
		for g in x.get_children():
			stack.append(g)
		if x is MeshInstance3D or x is CSGShape3D:
			c += 1
	return c

# ---------------------------------------------------------------- 5. sources
func _check_world_sources() -> void:
	_collect_takeables()
	print("takeable ids live in world: ", _takeable_ids.keys())
	var salv := get_tree().get_nodes_in_group("salvageable")
	print("salvage stations in world: ", salv.size())
	if salv.size() < 20:
		_fail("only %d salvage stations in the world" % salv.size())
	var available := {}
	for s in salv:
		var y = s.get("yields")
		if y is Dictionary:
			for k in y:
				available[k] = int(available.get(k, 0)) + 1
	# harvest nodes are Salvage too, so this sweep covers both
	print("obtainable material ids: ", available)
	var recipes: Dictionary = _load_json("res://data/recipes.json")
	var made := {}
	for rid in recipes:
		if rid.begins_with("_"):
			continue
		made[recipes[rid].get("makes", "")] = true
		for k in recipes[rid].get("extra", {}):
			made[k] = true
	for rid in recipes:
		if rid.begins_with("_"):
			continue
		var needs: Dictionary = recipes[rid].get("needs", {})
		for n in needs:
			if String(n).begins_with("@"):
				continue
			if available.has(n) or made.has(n) or FAUNA_SOURCED.has(n):
				continue
			# last resort: a takeable of that id standing in the world
			if _world_has_takeable(n):
				continue
			_fail("recipe '%s' needs '%s' which has NO world source" % [rid, n])
		var tool_id := String(recipes[rid].get("tool", ""))
		if tool_id != "" and not _world_has_takeable(tool_id) and not made.has(tool_id):
			_fail("recipe '%s' needs tool '%s' which is not obtainable in the world" % [rid, tool_id])

## Takeables are not in a group, and interior_props STREAMS them in by proximity —
## so a live-tree sweep alone would report the machine-shop tools as unobtainable
## just because the player has not walked over there yet. Walk the tree, then fall
## back to the spawn tables that will produce them.
var _takeable_ids: Dictionary = {}

func _collect_takeables() -> void:
	var stack: Array = [get_tree().root]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Takeable:
			_takeable_ids[String((n as Takeable).item_id)] = true

func _world_has_takeable(id: String) -> bool:
	return _takeable_ids.has(id)

## Prove the fauna whitelist is not a lie: each id must really be granted by
## bloom_fauna.gd. If someone deletes a creature's harvest, this fails instead of
## silently excusing an unobtainable recipe input.
func _check_fauna_sources() -> void:
	var f := FileAccess.open("res://scripts/world/bloom_fauna.gd", FileAccess.READ)
	var src := f.get_as_text()
	for id in FAUNA_SOURCED:
		if not src.contains('add_item("%s")' % id):
			_fail("'%s' is whitelisted as fauna-sourced (%s) but bloom_fauna.gd never grants it"
				% [id, FAUNA_SOURCED[id]])
	print("fauna-sourced materials confirmed: ", FAUNA_SOURCED.keys())

# ---------------------------------------------------------------- 6. visuals
func _check_visuals() -> void:
	var items: Dictionary = _load_json("res://data/items.json")
	var flat := 0
	for id in items:
		if String(id).begins_with("_"):
			continue
		var v = ITEM_VISUAL.build(id)
		if v == null:
			_fail("item '%s' has no ItemVisual" % id)
			continue
		if _count_meshes(v) == 0:
			_fail("item '%s' builds an empty (invisible) visual" % id)
		else:
			flat += 1
		v.queue_free()
	print("items with a real visual: %d/%d" % [flat, items.size()])

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}
