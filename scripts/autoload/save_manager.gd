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
## By path rather than by class name: handbook.gd is newer than the class cache this
## autoload is parsed against, and a dropped handbook has to rebuild as a readable book
## rather than a bare Takeable. See _make_drop().
const HANDBOOK := preload("res://scripts/components/handbook.gd")
const FAUNA := preload("res://scripts/world/bloom_fauna.gd")
## Surface lookup, so a rebuilt camp lands on the deck instead of inheriting a bad saved Y.
const SUPPORT := preload("res://scripts/world/support_index.gd")
## The size ledger: a dropped sized fish carries its landed weight (see _make_drop), and
## the ledger itself rides the save so a reload keeps the pack's weights too.
const FISH := preload("res://scripts/world/fish_table.gd")

## Which slot (1..SLOT_COUNT) autosaves and loads. Set by the start screen — and until
## something chooses one, 0: NO SESSION, NO WRITES.
##
## The old default of 1 ("so a direct Main boot still has a valid target") was the wipe
## the owner reported as "player loses all items when game loads from save". Every probe
## and screenshot harness in tests/ instantiates Main with a fresh, EMPTY PlayerState, and
## several sweep the clock phases — force_phase(DUSK) EMITS dusk, dusk is wired to
## save_game(), and with active_slot defaulting to a real slot each of those runs quietly
## overwrote saltline_slot_1.json with an empty world at "dusk, day 0". The owner's
## clobbered save on disk read exactly that. The probes never chose a session; the default
## chose one for them.
##
## Editor Play on Main.tscn still autosaves: main.gd claims a direct session at boot, but
## ONLY when Main is the scene ROOT — a probe's Main is a child of the probe, so a harness
## can never claim a slot by accident again.
var active_slot: int = 0
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

## Harvest/salvage state pulled from the last load, keyed the same way. Held for the same
## reason: the reef's mussel beds are built two physics frames after the load runs, so they
## have to be able to come and ask for their state (see claim_harvest).
var _pending_harvest: Dictionary = {}

## True only while load_game() is applying a save. THE MOST DESTRUCTIVE BUG THIS FILE HAS
## HAD, and it hid in plain sight: load_game() calls GameClock.force_phase() to restore the
## saved time of day, force_phase() emits dawn/dusk, and dawn/dusk are wired to save_game()
## in _ready(). A save is ONLY ever written at dawn or dusk, so EVERY save file on disk
## carries one of those two phases — meaning every single load re-entered save_game()
## halfway through, BEFORE structures, containers, dropped items and the player position
## had been restored, and wrote that half-empty world straight over the file. The running
## session still looked correct (the rest of load_game finishes off the in-memory dict), so
## the damage was invisible until the next boot: build a camp, save at dusk, Continue, quit,
## and the camp was gone. The suite never caught it because every save test calls
## force_phase(DAY) first, and DAY is the one phase NOT connected to save_game.
var _loading: bool = false

func _ready() -> void:
	_migrate_legacy()
	GameClock.dawn.connect(save_game)
	GameClock.dusk.connect(save_game)

## Path for a slot number. Clamped so a bad caller can't write outside the slot set.
func slot_path(slot: int) -> String:
	var s: int = clampi(slot, 1, SLOT_COUNT)
	return "user://%s%d.json" % [slot_file_prefix, s]

## One-time move of the old single autosave into slot 1, if slot 1 is still empty.
## Genuinely one-time: the legacy file is renamed out of the way once consumed, so it
## can never migrate a second time even if slot 1 is later emptied or deleted (a
## corrupted-save recovery, a manual clear). It used to just sit there forever and
## silently resurrect into any future empty slot 1 — that's how stale probe-fixture
## data kept reappearing across sessions. See DEVLOG for the incident.
func _migrate_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	if not FileAccess.file_exists(slot_path(1)):
		var src: FileAccess = FileAccess.open(LEGACY_PATH, FileAccess.READ)
		if src:
			var body: String = src.get_as_text()
			src.close()
			var dst: FileAccess = FileAccess.open(slot_path(1), FileAccess.WRITE)
			if dst:
				dst.store_string(body)
				dst.close()
	DirAccess.rename_absolute(LEGACY_PATH, LEGACY_PATH + ".migrated")

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
## Editor Play / a direct Main boot, claimed EXPLICITLY by main.gd when Main is the scene
## root. Keeps the owner's from-the-editor workflow autosaving to slot 1 without handing
## every test harness a loaded gun.
func begin_direct_session() -> void:
	if active_slot < 1:
		active_slot = 1

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

## Write the active slot. Returns true when the file is on disk, so the pause menu's
## SAVE GAME can tell the player the truth instead of assuming.
func save_game() -> bool:
	# Re-entered from GameClock.force_phase() inside load_game(). Writing here would
	# persist a half-restored world over a good save — see _loading.
	if _loading:
		return false
	# NO SESSION, NO WRITE — the belt to active_slot's braces. Nothing may reach disk
	# unless the start screen or a deliberate direct-session claim picked a slot; the
	# dawn/dusk signals stay connected in every context, so this return is what makes a
	# phase-sweeping test harness harmless to real saves.
	if active_slot < 1:
		return false
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
		"harvest": _harvest_payload(),
		# Landed weights not yet spent (fished but not filleted, dropped, or dried). A v2
		# reader that predates the key simply never looks at it.
		"fish_sizes": FISH.sizes_payload(),
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
	# Write to a sidecar first and only swap it in once the bytes are down. A crash or a
	# full disk midway through a direct write leaves a truncated file, which parses as
	# null — i.e. the previous good save is destroyed by the act of failing to replace it.
	var path: String = slot_path(active_slot)
	var tmp: String = path + ".part"
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("[save] cannot open %s to write (err %d)" % [tmp, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	# rename_absolute replaces the target, so the old save is only ever destroyed by a
	# complete new one landing on top of it — never by a write that got half way.
	var err: int = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("[save] cannot move %s into place (err %d)" % [tmp, err])
		return false
	return true

func load_game() -> bool:
	if active_slot < 1:
		return false
	var path: String = slot_path(active_slot)
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	# A truncated or hand-mangled file parses to null. Say so and start fresh rather than
	# half-applying it — the caller (Main._resume_saved_game) treats false as "cold open".
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[save] %s is not readable JSON — starting fresh" % path)
		return false
	var data: Dictionary = parsed
	# Everything from here on mutates live world state, and restoring the clock below
	# re-emits dawn/dusk straight back into save_game(). Hold the door shut until the
	# whole save is applied — see _loading. Deferred clear as well as the one on the
	# normal path, so a hard error inside a restore step cannot leave saving switched
	# off for the rest of the session.
	_loading = true
	_clear_loading.call_deferred()
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
	# The pack's landed weights come back with the pack. Authoritative replace (the save's
	# inventory just replaced the session's, and these numbers belong to it); a save from
	# before weights persisted restores an empty ledger, i.e. exactly the old behaviour.
	FISH.restore_sizes(data.get("fish_sizes", {}))
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
	restore_harvest(data.get("harvest", {}))
	restore_structures(data.get("structures", []))
	_apply_pending_to_existing()
	restore_dropped(data.get("dropped", []))
	# The world rebuild always respawns the wet-deck handbook, because the world is built
	# before any save is read. Now that the pack and the dropped items are back, the book
	# knows where it really is and can delete the duplicate. Must run AFTER both.
	HANDBOOK.sync_world(get_tree())
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
	_loading = false
	return true

## Only ever called to lower the re-entrancy guard — see _loading. Deferred out of
## load_game() as the backstop for a restore step that errors out before the flag drops.
func _clear_loading() -> void:
	_loading = false

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
	var rebuilt: Array[Node3D] = []
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
		if not Structures.WALL_MOUNT.has(kit):
			rebuilt.append(node)
		built += 1
	_ground_restored(scene, rebuilt)
	return built

## Rest a rebuilt camp back ON the deck it was standing on.
##
## The transform round-trip is exact, which is right, but it also means a save carrying a
## bad Y hands that Y straight back every single load — the camp hangs in the air and no
## amount of reloading shakes it loose. That is exactly what a stale save slot did on this
## project: a brazier and a deck chair pinned at y19 over the y18 main deck, floating a
## clean metre up, with the chair's box cutting through the storage bin beside it.
##
## SUPPORT.settle only ever moves a node DOWN onto the highest surface under it, does
## nothing at all when there is no surface below (so a hanging kit stays hung) and is
## capped by MAX_DROP. WALL_MOUNT kits are excluded by the caller: a shelf bolted to a
## bulkhead has a deck within falling distance underneath it.
##
## Only a REAL float is corrected. Anything already within GROUND_EPS of its support is
## left on its saved Y untouched, because container contents are keyed by rounded world
## position (_container_key): nudging a restored storage bin by even the settle pass's
## 5 mm clearance changes its key and its stash comes back empty. A camp is only worth
## moving when it is visibly in the air, and 5 cm is well under anything a player sees.
const GROUND_EPS: float = 0.05

func _ground_restored(scene: Node, nodes: Array[Node3D]) -> void:
	if nodes.is_empty():
		return
	var index = SUPPORT.new()
	index.build(scene)
	for n in nodes:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var a: AABB = SUPPORT.world_aabb_of_tree(n)
		if a.size == Vector3.ZERO:
			continue
		var top: float = index.support_top(a, n)
		if top == -INF:
			continue                       # nothing under it: hung or wall-mounted
		if a.position.y - top <= GROUND_EPS:
			continue                       # already resting: leave the saved Y exactly
		index.settle(n, a)

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

# ------------------------------------------------------------- harvest / salvage
# A rig you have stripped should stay stripped, and this is the gap that closed it: before
# s21 NOTHING about Salvage persisted, so a player could gut every locker, scrape every tar
# seam, save, reload, and find the whole rig whole again. It matters most for the mussel beds,
# whose regrowth is FIVE GAME DAYS — a bed that grew back on every load would have no
# regrowth at all.
#
# Keyed by where the node stands. That is stable for exactly the reason container keys are:
# harvest nodes are placed by world construction from seeded RNG, so the same spot comes back
# on the same spot. Only SPENT nodes are written — an untouched node is the default, and
# writing 60 "false" entries a save would bloat every slot for nothing.

func _harvest_key(s: Node3D) -> String:
	var p: Vector3 = s.global_position
	return "%.2f,%.2f,%.2f" % [p.x, p.y, p.z]

func _harvest_payload() -> Dictionary:
	var out: Dictionary = {}
	for s in get_tree().get_nodes_in_group("salvageable"):
		if not (s is Node3D) or not is_instance_valid(s) or not s.has_method("harvest_state"):
			continue
		var st: Variant = s.call("harvest_state")
		if typeof(st) != TYPE_DICTIONARY or not bool((st as Dictionary).get("spent", false)):
			continue
		out[_harvest_key(s as Node3D)] = st
	return out

## Reapply saved harvest state. AUTHORITATIVE in both directions: a node the save does not
## mention is put back to untouched, so loading a fresh slot over a session in which the
## player stripped half the rig does not leave those wounds standing.
func restore_harvest(data: Variant) -> int:
	_pending_harvest = data if typeof(data) == TYPE_DICTIONARY else {}
	var n: int = 0
	for s in get_tree().get_nodes_in_group("salvageable"):
		if not (s is Node3D) or not is_instance_valid(s) or not s.has_method("harvest_restore"):
			continue
		var key: String = _harvest_key(s as Node3D)
		var st: Variant = _pending_harvest.get(key, {"spent": false})
		if typeof(st) != TYPE_DICTIONARY:
			continue
		s.call("harvest_restore", st)
		if bool((st as Dictionary).get("spent", false)):
			n += 1
	return n

## Called (deferred) by a Salvage node once it is in the tree WITH ITS FINAL POSITION. The
## reef's mussel beds do not exist when load_game() runs — LegReef waits two physics frames
## and Main defers the load by one — so they claim their own saved state on arrival, exactly
## as a rebuilt storage crate claims its contents.
func claim_harvest(s: Node3D) -> void:
	if _pending_harvest.is_empty() or not is_instance_valid(s) \
			or not s.has_method("harvest_restore"):
		return
	var key: String = _harvest_key(s)
	if not _pending_harvest.has(key):
		return
	var st: Variant = _pending_harvest[key]
	if typeof(st) == TYPE_DICTIONARY:
		s.call("harvest_restore", st)

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
		var entry: Dictionary = {"id": id}
		# A sized fish keeps its landed weight across the reload — the whole point of the
		# weight riding the node. Only written when there is one, so every other dropped
		# item's entry is byte-identical to what it always was.
		var kg: Variant = d.get("size_kg")
		if kg != null and float(kg) > 0.0:
			entry["kg"] = float(kg)
		out.append(_xform_dict(entry, (d as Node3D).global_transform))
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
		# A save from before weights persisted has no "kg" on its dropped fish. Those
		# fish still have to be SOME size now that sized species render at their weight,
		# so they come back as the species' typical catch (FishTable.median_size) — an
		# ordinary fish, deterministically, never a reload-lottery monster. Species with
		# no size range get 0.0 from median_size and are untouched.
		var kg: float = float(entry.get("kg", 0.0))
		if kg <= 0.0:
			kg = FISH.median_size(id)
		var t: Node3D = _make_drop(id, kg)
		scene.add_child(t)
		t.global_transform = _xform_from(entry)
		n += 1
	return n

## Build a dropped-item Takeable: its real world visual plus an interaction collider,
## tagged so it persists. Not yet parented.
##
## `kg` is a sized fish's landed weight (0.0 for everything else, and for every non-fish
## caller): the node remembers it (takeable.size_kg — given back to the ledger on TAKE),
## ItemVisual draws the body at the real length that weight implies, and the interaction
## box grows along the body so a two-metre grouper can be picked up by its tail, not
## only by a 0.4 m cube buried somewhere in its middle.
func _make_drop(item_id: String, kg: float = 0.0) -> Node3D:
	# THE HANDBOOK IS NOT A TAKEABLE. Set down anywhere on the rig it has to still be the
	# book — [E] READs it where it sits, [F] pockets it again (Handbook) — where a plain
	# Takeable would offer nothing but TAKE and make "place it where you fish and read it
	# there" a lie. It saves through the same "dropped_item" group as everything else, so
	# the only special case is which node gets built. See scripts/components/handbook.gd.
	if item_id == HANDBOOK.ITEM_ID:
		return HANDBOOK.make_dropped()
	var t: Node3D = TAKEABLE.new()
	t.set("item_id", item_id)
	t.set("display_name", String(PlayerState.items.get(item_id, {}).get("name", item_id.capitalize())))
	var fish_m: float = ItemVisual.fish_instance_length_m(item_id, kg)
	if fish_m > 0.0:
		t.set("size_kg", kg)
		# A sized fish's grown box must not also be a wall. An Interactable is a
		# StaticBody3D on the solid layer, the landing is ~0.7 m from the dropper's
		# feet, and a grouper-length box reaches further than that — the player would
		# be standing inside it the frame it lands, and depenetration shoves whoever
		# dropped it. The s35 third layer is exactly this case (see interaction_ray:
		# reachable by the ray, nothing to the capsule). Ordinary drops keep their
		# solid 0.4 cube untouched.
		t.set("collision_layer", InteractionRay.INTERACT_LAYER)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if fish_m > 0.0:
		# The body lies along X (ItemVisual yaws the mesh so the flank faces the view).
		# Footprint follows the animal, CAPPED — a 3.5 m sturgeon does not need three
		# and a half metres of hitbox to be picked up by, and stray interaction rays
		# should not find a fish through a bulkhead. Height stays the ordinary 0.4 —
		# the ray wants width, not a wall.
		box.size = Vector3(clampf(fish_m * 0.85, 0.4, 2.4), 0.4, clampf(fish_m * 0.3, 0.4, 0.9))
	else:
		box.size = Vector3(0.4, 0.4, 0.4)
	col.shape = box
	col.position.y = 0.2
	t.add_child(col)
	t.add_child(ItemVisual.build(item_id, kg))
	t.add_to_group("dropped_item")
	return t

## Drop one item into the world at a foot point, with a short toss so it reads as set
## down rather than teleported. Called by the HUD's drop control. Returns the node.
##
## `kg`: the fish's landed weight, for callers that know it (the rod's and the spear's
## full-pack spill — the fish never entered the pack, so its weight was never recorded
## and rides straight onto the node). The default -1.0 means "ask the ledger": a sized
## species popped out of the pack takes its OLDEST recorded weight with it, exactly as
## the stove does when it fillets one, and a fish the ledger never saw (a pre-size save,
## a locker find) rolls fresh from its own range. Non-fish ids resolve to 0.0 either way
## and drop precisely as they always have.
func drop_into_world(item_id: String, feet: Vector3, toss_dir: Vector3 = Vector3.ZERO,
		kg: float = -1.0) -> Node3D:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	if kg < 0.0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		kg = FISH.take_size(item_id, rng)
	var t: Node3D = _make_drop(item_id, kg)
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
