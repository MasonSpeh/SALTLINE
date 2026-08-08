class_name LootContainer extends Interactable
## OPEN verb: a reusable storage crate. Items stay in `items` until the player
## moves them — opening brings up the HUD's exchange panel (crate ⇄ pack, both
## directions), so crates double as stash boxes. Always re-openable.

@export var items: Array[String] = []
## WHAT EACH OF THOSE IS, entry for entry. Parallel to `items` for the same reason
## PlayerState's counts and payloads are parallel to its slots: `items` is read as a flat
## bag of ids by rig_builder, world_storage, cold_store, the HUD and the save, and every one
## of those readers keeps working untouched.
##
## A crate PRESERVES A WEIGHT (owner call): stow a 48 kg grouper in a locker and it is still
## the 48 kg grouper when you take it back out. Entry i is a Dictionary — today only
## `{"kg": float}` — or null for the ordinary case.
##
## SHORTER THAN `items` IS LEGAL AND NORMAL. Every existing producer assigns `items`
## wholesale and knows nothing about this array (world_storage seeds a locker with
## `box.items = seeded`; SaveManager's v2 container payload is a plain id list), so a
## missing tail simply means "those carry nothing" — see meta_at / _fit_meta.
@export var item_meta: Array = []

var _opened: bool = false

# ------------------------------------------------------------------ contents, with payload
# Five small accessors, so no caller outside this file has to keep the two arrays in step —
# which is exactly the discipline the pack's own parallel arrays needed and got.

## Pad or trim `item_meta` to match `items`. Cheap, idempotent, and called by every accessor
## below so an `items = [...]` assignment from anywhere is always safe.
func _fit_meta() -> void:
	while item_meta.size() < items.size():
		item_meta.append(null)
	while item_meta.size() > items.size():
		item_meta.remove_at(item_meta.size() - 1)

## What entry i carries; {} for an ordinary item or an out-of-range index.
func meta_at(i: int) -> Dictionary:
	_fit_meta()
	if i < 0 or i >= item_meta.size():
		return {}
	return PlayerState.as_meta(item_meta[i])

## Put one item in, with whatever it is carrying.
func put_item(id: String, meta: Dictionary = {}) -> void:
	_fit_meta()
	items.append(id)
	item_meta.append(PlayerState.as_meta(meta) if not meta.is_empty() else null)

## Take entry i out and hand back its payload ({} when it had none / bad index).
func take_item(i: int) -> Dictionary:
	_fit_meta()
	if i < 0 or i >= items.size():
		return {}
	var m: Dictionary = meta_at(i)
	items.remove_at(i)
	item_meta.remove_at(i)
	return m

## The first entry holding this id that carries NOTHING, or -1. A bulk stow/take of an
## ordinary stack uses this so it can never reach past the plain ones and move the one
## weighed fish sitting in the same crate.
func find_plain(id: String) -> int:
	_fit_meta()
	for i in range(items.size()):
		if items[i] == id and PlayerState.meta_empty(item_meta[i]):
			return i
	return items.find(id)

func _init() -> void:
	verbs = ["OPEN"] as Array[String]
	# available_verbs() is inherited: crates always offer OPEN.

func _ready() -> void:
	# Every crate, found locker and nest is a save target: its `items` persist keyed by
	# where it stands. Join the group so SaveManager can find it, then — deferred, so
	# the world transform is already set even for a crate rebuilt this very frame — ask
	# for any contents the last load saved for this spot.
	add_to_group("loot_container")
	call_deferred("_claim_saved_contents")

func _claim_saved_contents() -> void:
	if is_instance_valid(SaveManager):
		SaveManager.claim_container(self)

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	if not _opened:
		# First open only: the hatch creak, and the lid stays visibly cracked.
		_opened = true
		AudioDirector.play_one_shot("hatch", global_position)
		for c in get_children():
			if c is MeshInstance3D and c.mesh and c.mesh.material:
				c.mesh.material.albedo_color = c.mesh.material.albedo_color.darkened(0.5)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.open_crate(self)
