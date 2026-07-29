class_name Handbook extends Readable
## THE FISHERMAN'S HANDBOOK — the one readable on this rig that is also a THING.
##
## Every other Readable is scenery with words on it: bolted where a world script put it,
## read where it stands, there for good. The handbook is the book you actually work from,
## so it behaves like a tool instead of a notice — you take it off the wet deck, it rides
## in the pack, you set it down by whatever rail you are fishing, and it reads from
## wherever it is sitting.
##
## WHY ONE VERB AND A KEY, and not two verbs. InteractionRay dispatches available_verbs()[0]
## and prints that same verb in the prompt (interaction_ray.gd _unhandled_input) — one
## object, one verb, no cycling, and a second entry in the array would silently never fire.
## So READ is the verb ([E], the press that opens every other readable on the rig) and
## taking it is a separate key named on the same prompt: [F], claimed ONLY while the book
## is actually open in front of you. That mirrors the deep rig's [B]-to-bait exactly — a
## dedicated key, a prompt that says so, and one static hook the player controller calls
## without needing to know anything else about this file.
##
## WHERE THE COPIES LIVE. There is exactly one handbook in the world and the save has to
## agree, across the three places it can be:
##   on the wet deck    — the original, placed by wet_deck_detail into ORIGIN_GROUP
##   in the pack        — an ordinary inventory item, saved with the rest of the inventory
##   set down somewhere — a "dropped_item", saved with id + transform like any dropped item
## The world is rebuilt from scratch on every load and only THEN is the save applied, so
## the wet-deck original always respawns. sync_world() runs after the load and deletes it
## when the save says the book is elsewhere — otherwise a player who pocketed it and
## reloaded would find a second copy lying where the first one had been.

const ITEM_ID: String = "fishermans_handbook"
## The data/readables.json key. Deliberately unchanged: it is the stable id the journal's
## read log, the save file and the test runner all already carry. The TITLE is what the
## player sees, and that is in the json.
const READABLE_ID: String = "anglers_notes"
const DISPLAY_NAME: String = "Fisherman's Handbook"
## The wet-deck original, so sync_world() can tell it from a copy the player set down.
const ORIGIN_GROUP: String = "handbook_origin"

## Placement boxes. ReadableVisual reads the THIN axis as the one you look through, so the
## two shapes are two poses: PROPPED stands the book on its edge against the store-room
## bench where a rigger left it, FLAT lays it face-up on the deck where a player put it
## down. Thin-Y is what makes it lie down (readable_visual.build, ax == 1).
const SIZE_PROPPED := Vector3(0.32, 0.4, 0.05)
const SIZE_FLAT := Vector3(0.3, 0.05, 0.38)

## Saved by SaveManager._dropped_payload() for a copy the player set down. Declared as a
## real property (not just set() on the node) because that payload reads it back off the
## node, and set() on an undeclared name is a silent no-op.
@export var item_id: String = ITEM_ID

## Which pose this copy is in. Read by _ready(), so a caller only has to assign it before
## adding the node to the tree.
var placement: Vector3 = SIZE_FLAT

## The handbook whose text is on screen right now, or null. [F] is the take key only while
## this is set; every other time it is the flashlight/hook key it has always been.
## Typed as the base class, not as Handbook: see _new() for why this file never names its
## own global class.
static var _reading: Readable = null

## A fresh handbook node. `class_name Handbook` is registered in Godot's global class cache,
## which is only rebuilt by an editor/import pass — so a HEADLESS run against a cache that
## predates this file cannot resolve the name, and every script that depends on it fails to
## compile ("Identifier not found: Handbook"). That is the same lag structures.gd notes when
## it preloads drop_net.gd by path. load() here hits the already-resident script resource at
## call time, so the file never has to name itself while it is being parsed.
static func _new() -> Readable:
	return (load("res://scripts/components/handbook.gd") as GDScript).new()

var _built: bool = false

func _init() -> void:
	readable_id = READABLE_ID
	display_name = DISPLAY_NAME
	verbs = ["READ"] as Array[String]

## Build the book and its collider the moment it lands in the tree, whatever put it there —
## the wet deck's placement pass, a drop out of the pack, or a save being restored. Safe to
## run before the node has been positioned: ReadableVisual.build() works entirely in local
## space (it returns a child, and the collider is a child), so nothing here depends on
## where the book ends up standing.
func _ready() -> void:
	if not _built:
		_built = true
		build_visual(placement)

## The prompt has to carry the take key: a book you can pick up is not something players
## guess at when every other readable on this rig is bolted down.
func get_prompt() -> String:
	return "READ  %s   ·   [F] pocket it" % display_name

func interact(verb: String, player: Node3D) -> void:
	_reading = self
	super(verb, player)

## Put the wet-deck original where it belongs, propped and ready to read.
static func place_origin(parent: Node, pos: Vector3) -> Readable:
	var h: Readable = _new()
	h.placement = SIZE_PROPPED
	h.add_to_group(ORIGIN_GROUP)
	parent.add_child(h)
	h.global_position = pos
	return h

## A copy for the deck, lying flat — what SaveManager builds when the book is dropped out
## of the pack or restored from a save. Unparented; the caller positions it.
static func make_dropped() -> Readable:
	var h: Readable = _new()
	h.placement = SIZE_FLAT
	h.add_to_group("dropped_item")
	return h

# ------------------------------------------------------------------ the [F] key
## Everything [F] means for the handbook, in the order a hand actually uses it. Returns
## true when the press was ours, so player_controller's own [F] chain (flashlight, rigging
## hook, double-tap fly) carries on untouched whenever it wasn't. Static for the same
## reason FishingRod's bait hooks are: the controller should need exactly one line.
static func f_pressed(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var hud: Node = player.get_tree().get_first_node_in_group("hud")
	# 1. Reading one that is lying in the world: pocket it, and shut the book.
	if _reading != null and is_instance_valid(_reading) and _reading.is_inside_tree():
		if hud == null or not bool(hud.get("reading_open")):
			_reading = null   # they closed it and walked off; the press isn't ours
		else:
			if not PlayerState.add_item(ITEM_ID):
				hud.toast("Pack's full — nowhere to put the handbook.")
				return true
			_reading.queue_free()
			_reading = null
			hud.close_reading()
			hud.toast("Took the %s. Hold it and press [F] to read it anywhere." % DISPLAY_NAME)
			return true
	# 2. Carrying it, with it in hand: open it wherever you happen to be standing.
	if _selected(player) == ITEM_ID:
		if hud:
			var entry: Dictionary = Readable.text_for(READABLE_ID)
			hud.show_reading(entry.get("title", DISPLAY_NAME), entry.get("body", ""))
			Journal.discover_log(READABLE_ID, entry.get("title", DISPLAY_NAME))
		return true
	return false

static func _selected(player: Node) -> String:
	if player.has_method("_selected_item_id"):
		return String(player.call("_selected_item_id"))
	var sel: int = PlayerState.selected_hotbar
	if sel < 0 or sel >= PlayerState.HOTBAR_SIZE or PlayerState.hotbar[sel] == null:
		return ""
	return String(PlayerState.hotbar[sel])

# ------------------------------------------------------------------ one copy only
## Called once after a save is applied (SaveManager.load_game). If the book is in the pack
## or already set down somewhere, the wet-deck original that the world rebuild just
## respawned is a duplicate — delete it. Safe to call with no save at all: nothing matches,
## the original stays, and a fresh expedition finds its handbook where it should be.
## Returns how many originals were removed (0 or 1), for the probes.
static func sync_world(tree: SceneTree) -> int:
	if tree == null:
		return 0
	var elsewhere: bool = PlayerState.count_item(ITEM_ID) > 0
	if not elsewhere:
		for n in tree.get_nodes_in_group("dropped_item"):
			if is_instance_valid(n) and String(n.get("item_id")) == ITEM_ID:
				elsewhere = true
				break
	if not elsewhere:
		return 0
	var freed: int = 0
	for n in tree.get_nodes_in_group(ORIGIN_GROUP):
		if is_instance_valid(n):
			n.queue_free()
			freed += 1
	return freed
