extends Node
## JSON save/load of world + player state. THREE save slots; the active slot autosaves
## at dawn/dusk. The start screen picks the slot (New Expedition / Continue), stashes the
## choice here, and Main restores it on boot — see begin_new_game / begin_continue /
## consume_pending_load. Before this, load_game() was never called at boot, so saves
## wrote but never came back; the slot flow closes that gap.

const SLOT_COUNT: int = 3
## Legacy single-slot path from before slots existed. Migrated into slot 1 on first run
## so an existing player's CONTINUE keeps working.
const LEGACY_PATH: String = "user://saltline_autosave.json"
## Format version. v1 = the original (plain hotbar/inventory string arrays, no
## container/dropped/structure persistence). v2 = stacks carry counts, and placed
## structures, container contents and dropped items all round-trip. Old (v1, or
## version-less) saves still load: every reader below defaults gracefully.
const SAVE_VERSION: int = 2

const TAKEABLE := preload("res://scripts/components/takeable.gd")
const FAUNA := preload("res://scripts/world/bloom_fauna.gd")

## Which slot (1..SLOT_COUNT) autosaves and loads. Set by the start screen; defaults to
## 1 so a direct Main boot (tests, editor Play) still has a valid target.
var active_slot: int = 1
## Filename stem for slots. Tests point this at a throwaway stem so the suite's save/load
## checks never clobber the player's real saltline_slot_*.json files.
var slot_file_prefix: String = "saltline_slot_"
## True when the start screen chose CONTINUE: Main consumes it after building the world
## and calls load_game(). A New Expedition leaves it false so Main starts fresh.
var _pending_load: bool = false

## Container contents pulled from the last load, keyed by a stable position key. Held
## so that containers which only exist AFTER the load call — structures rebuilt this
## frame, found lockers the world-storage scanner adopts seconds later — can claim
## their saved contents when they come up (see claim_container).
var _pending_containers: Dictionary = {}

func _ready() -> void:
	_migrate_legacy()
	GameClock.dawn.connect(save_game)
	GameClock.dusk.connect(save_game)

## Path for a slot number. Clamped so a bad caller can't write outside the slot set.
func slot_path(slot: int) -> String:
	var s: int = clampi(slot, 1, SLOT_COUNT)
	return "user://%s%d.json" % [slot_file_prefix, s]

## One-time move of the old single autosave into slot 1, if slot 1 is still empty.
func _migrate_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	if FileAccess.file_exists(slot_path(1)):
		return
	var src: FileAccess = FileAccess.open(LEGACY_PATH, FileAccess.READ)
	if src == null:
		return
	var body: String = src.get_as_text()
	src.close()
	var dst: FileAccess = FileAccess.open(slot_path(1), FileAccess.WRITE)
	if dst:
		dst.store_string(body)
		dst.close()

# ---------------------------------------------------------------- slot selection
# The start screen calls these. Nothing here touches the world — they only record the
# choice; Main acts on it once the scene is up.

## Menu metadata for one slot without committing to a load: does it exist, and if so
## which day/phase it holds, plus a ready-made button label.
func slot_info(slot: int) -> Dictionary:
	var path: String = slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false, "day": 0, "phase": 0, "label": "New Expedition"}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"exists": false, "day": 0, "phase": 0, "label": "New Expedition"}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"exists": false, "day": 0, "phase": 0, "label": "New Expedition"}
	var day: int = int((parsed as Dictionary).get("day_count", 0))
	var phase: int = int((parsed as Dictionary).get("phase", 0))
	var names: Array = ["Dawn", "Day", "Dusk", "Night"]
	var phase_name: String = names[phase] if phase >= 0 and phase < names.size() else "Day"
	return {"exists": true, "day": day, "phase": phase,
		"label": "Continue · Day %d, %s" % [day + 1, phase_name]}

## Start a fresh run in a slot: make it active, wipe any old save there so nothing
## bleeds through, and DON'T flag a load (Main builds the world clean).
func begin_new_game(slot: int) -> void:
	active_slot = clampi(slot, 1, SLOT_COUNT)
	_pending_load = false
	erase_slot(active_slot)

## Resume a slot: make it active and flag the load for Main to consume.
func begin_continue(slot: int) -> void:
	active_slot = clampi(slot, 1, SLOT_COUNT)
	_pending_load = true

## Main calls this once after building the world; true means "load the active slot now".
func consume_pending_load() -> bool:
	var v: bool = _pending_load
	_pending_load = false
	return v

## Delete a slot's save file (New Expedition over an occupied slot, or a menu erase).
func erase_slot(slot: int) -> void:
	var path: String = slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func save_game() -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"hunger": PlayerState.hunger,
		"thirst": PlayerState.thirst,
		"warmth": PlayerState.warmth,
		"life": PlayerState.life,
		"hotbar": PlayerState.hotbar,
		"inventory": PlayerState.inventory,
		"hotbar_counts": PlayerState.hotbar_counts,
		"inventory_counts": PlayerState.inventory_counts,
		"phase": GameClock.current_phase,
		"day_count": GameClock.day_count,
		"powered": PowerGrid.powered_ids(),
		"structures": _structures_payload(),
		"containers": _containers_payload(),
		"dropped": _dropped_payload(),
		"snails": FAUNA.snail_payload(get_tree()),
	}
	# Where the player stood at save time, so Continue resumes them there rather than
	# back at the pod. Only written when a player is actually in the tree.
	var pl: Node = get_tree().get_first_node_in_group("player")
	if pl is Node3D:
		var p: Vector3 = (pl as Node3D).global_position
		data["player_pos"] = [p.x, p.y, p.z]
		data["player_yaw"] = (pl as Node3D).rotation.y
	# rest / comfort / camp_found live with the stats that feed them.
	data.merge(PlayerState.comfort_payload())
	# Discoveries, read logs and catch records. The journal also keeps its own per-slot
	# sidecar, but the slot save is authoritative — this is what survives a slot copy.
	data.merge(Journal.payload())
	var file: FileAccess = FileAccess.open(slot_path(active_slot), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func load_game() -> bool:
	var path: String = slot_path(active_slot)
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	PlayerState.hunger = data.get("hunger", 1.0)
	PlayerState.thirst = data.get("thirst", 1.0)
	PlayerState.warmth = data.get("warmth", 1.0)
	PlayerState.life = data.get("life", 1.0)
	# load_inventory keeps the id arrays and their counts the same length, and copes
	# with a v1 save that has no counts arrays at all (every slot defaults to one).
	PlayerState.load_inventory(
		data.get("hotbar", [null, null, null, null]),
		data.get("hotbar_counts", []),
		data.get("inventory", []),
		data.get("inventory_counts", []))
	PlayerState.apply_comfort_payload(data)
	# Non-destructive merge: discoveries union and a catch record keeps the heavier fish,
	# so this layers cleanly over whatever the journal's own sidecar already restored.
	Journal.restore(data)
	GameClock.day_count = int(data.get("day_count", 0))
	for id in data.get("powered", []):
		PowerGrid.power_circuit(id)
	GameClock.force_phase(int(data.get("phase", GameClock.Phase.DAWN)) as GameClock.Phase)
	# Stash container contents BEFORE rebuilding structures, so a storage crate that
	# comes back as part of a rebuilt camp can claim its items the moment it spawns.
	_pending_containers = data.get("containers", {}) if typeof(data.get("containers")) == TYPE_DICTIONARY else {}
	restore_structures(data.get("structures", []))
	_apply_pending_to_existing()
	restore_dropped(data.get("dropped", []))
	var snails: Variant = data.get("snails", {})
	if typeof(snails) == TYPE_DICTIONARY:
		FAUNA.snail_restore(get_tree(), snails)
	# Put the player back where they saved. Clear motion/water state so they don't
	# resume mid-fall or flagged as swimming on dry footing.
	var pl: Node = get_tree().get_first_node_in_group("player")
	if pl is Node3D and typeof(data.get("player_pos")) == TYPE_ARRAY and (data["player_pos"] as Array).size() >= 3:
		var a: Array = data["player_pos"]
		(pl as Node3D).global_position = Vector3(float(a[0]), float(a[1]), float(a[2]))
		(pl as Node3D).rotation.y = float(data.get("player_yaw", (pl as Node3D).rotation.y))
		if pl is CharacterBody3D:
			(pl as CharacterBody3D).velocity = Vector3.ZERO
		if "swimming" in pl:
			pl.set("swimming", false)
	return true

# --------------------------------------------------------------- base building
# A camp that evaporates when you go to bed is not a camp. Every placed structure
# carries meta "kit" and Structures.build(kit) reconstructs it whole, so kit id
# plus the world transform is the entire save: no per-kit serialisation to drift.

func _structures_payload() -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("built_structures"):
		if not (s is Node3D) or not is_instance_valid(s):
			continue
		var kit: String = String((s as Node3D).get_meta("kit", ""))
		if kit == "":
			continue
		out.append(_xform_dict({"kit": kit}, (s as Node3D).global_transform))
	return out

## Rebuild a saved camp. Clears whatever is standing first so a mid-session load
## cannot double every structure.
func restore_structures(list: Variant) -> int:
	if typeof(list) != TYPE_ARRAY:
		return 0
	var scene: Node = get_tree().current_scene
	if scene == null:
		return 0
	for old in get_tree().get_nodes_in_group("built_structures"):
		if is_instance_valid(old):
			old.queue_free()
	var built: int = 0
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kit: String = String(entry.get("kit", ""))
		if kit == "" or not Structures.KIT_ORDER.has(kit):
			continue
		var node: Node3D = Structures.build(kit, false)
		if node == null:
			continue
		scene.add_child(node)
		node.global_transform = _xform_from(entry)
		built += 1
	return built

# ------------------------------------------------------------ container contents
# Every LootContainer (built crate, found locker, gull nest) tags itself into group
# "loot_container" and its items save keyed by where it stands. On load, contents are
# reapplied both to containers that already exist and — via claim_container — to ones
# that spawn later, so a stash keeps what you left in it across a night's sleep.

## A position key stable across a reload: containers do not move, and rebuilt/adopted
## ones land back on the same spot, so rounded world position + name identifies them.
func _container_key(c: Node3D) -> String:
	var p: Vector3 = c.global_position
	var name_: String = String(c.get("display_name")) if c.get("display_name") != null else ""
	return "%.2f,%.2f,%.2f|%s" % [p.x, p.y, p.z, name_]

func _containers_payload() -> Dictionary:
	var out: Dictionary = {}
	for c in get_tree().get_nodes_in_group("loot_container"):
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var its: Variant = c.get("items")
		if typeof(its) != TYPE_ARRAY:
			continue
		out[_container_key(c as Node3D)] = (its as Array).duplicate()
	return out

## Reapply saved contents to every container currently in the tree with a final
## position. Idempotent: applying the same saved list twice is a no-op in effect.
func _apply_pending_to_existing() -> void:
	if _pending_containers.is_empty():
		return
	for c in get_tree().get_nodes_in_group("loot_container"):
		if c is Node3D and is_instance_valid(c):
			claim_container(c as Node3D)

## Called (deferred) by a LootContainer once it is in the tree and positioned. If the
## last load carried contents for its spot, adopt them.
func claim_container(c: Node3D) -> void:
	if _pending_containers.is_empty() or not is_instance_valid(c):
		return
	var key: String = _container_key(c)
	if not _pending_containers.has(key):
		return
	var saved: Variant = _pending_containers[key]
	if typeof(saved) != TYPE_ARRAY:
		return
	var restored: Array[String] = []
	for it in (saved as Array):
		restored.append(String(it))
	c.set("items", restored)

# ---------------------------------------------------------------- dropped items
# Items the player tosses out of the pack become real Takeables on the deck. They are
# tagged "dropped_item" so they save (id + transform) and come back where they fell.

func _dropped_payload() -> Array:
	var out: Array = []
	for d in get_tree().get_nodes_in_group("dropped_item"):
		if not (d is Node3D) or not is_instance_valid(d):
			continue
		var id: String = String(d.get("item_id")) if d.get("item_id") != null else ""
		if id == "":
			continue
		out.append(_xform_dict({"id": id}, (d as Node3D).global_transform))
	return out

## Rebuild dropped items. Clears any currently on the deck first so a second load
## cannot litter the world with duplicates.
func restore_dropped(list: Variant) -> int:
	if typeof(list) != TYPE_ARRAY:
		return 0
	var scene: Node = get_tree().current_scene
	if scene == null:
		return 0
	for old in get_tree().get_nodes_in_group("dropped_item"):
		if is_instance_valid(old):
			old.queue_free()
	var n: int = 0
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id: String = String(entry.get("id", ""))
		if id == "":
			continue
		var t: Node3D = _make_drop(id)
		scene.add_child(t)
		t.global_transform = _xform_from(entry)
		n += 1
	return n

## Build a dropped-item Takeable: its real world visual plus an interaction collider,
## tagged so it persists. Not yet parented.
func _make_drop(item_id: String) -> Node3D:
	var t: Node3D = TAKEABLE.new()
	t.set("item_id", item_id)
	t.set("display_name", String(PlayerState.items.get(item_id, {}).get("name", item_id.capitalize())))
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	col.shape = box
	col.position.y = 0.2
	t.add_child(col)
	t.add_child(ItemVisual.build(item_id))
	t.add_to_group("dropped_item")
	return t

## Drop one item into the world at a foot point, with a short toss so it reads as set
## down rather than teleported. Called by the HUD's drop control. Returns the node.
func drop_into_world(item_id: String, feet: Vector3, toss_dir: Vector3 = Vector3.ZERO) -> Node3D:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var t: Node3D = _make_drop(item_id)
	scene.add_child(t)
	var landing: Vector3 = feet + toss_dir
	t.global_position = feet + Vector3(0, 0.6, 0)
	var tw: Tween = t.create_tween()
	tw.tween_property(t, "global_position", landing + Vector3(0, 0.3, 0), 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(t, "global_position", landing, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return t

# ------------------------------------------------------------------- transforms
# JSON has no Transform3D, and euler angles lose the wall-mount orientations build
# mode produces, so a basis is stored column-major as nine floats.

func _xform_dict(base: Dictionary, t: Transform3D) -> Dictionary:
	base["pos"] = [t.origin.x, t.origin.y, t.origin.z]
	base["basis"] = [
		t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
	]
	return base

func _xform_from(entry: Dictionary) -> Transform3D:
	return Transform3D(_basis_from(entry.get("basis", [])), _vec_from(entry.get("pos", [])))

func _vec_from(a: Variant) -> Vector3:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 3:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _basis_from(a: Variant) -> Basis:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 9:
		return Basis()
	return Basis(
		Vector3(float(a[0]), float(a[1]), float(a[2])),
		Vector3(float(a[3]), float(a[4]), float(a[5])),
		Vector3(float(a[6]), float(a[7]), float(a[8]))).orthonormalized()
