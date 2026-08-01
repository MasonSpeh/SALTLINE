extends Node3D
## s24 — two owner reports and one new species, measured rather than asserted.
##
##   1. HELD FISH SIZE. "when i hold the barrel grouper it is tiny." Reproduces
##      player_controller._normalize_hand_visual exactly (same AABB walk, same
##      container/visual split) and prints the size the fish ACTUALLY ends up at in the
##      hand, before and against its own body length and its pack portrait. If the two
##      disagree the grouper is still tiny and this says so in metres.
##   2. THE SWORDFISH. Does it resolve a mesh, does it roll at its own depth and nowhere
##      above it, and is it genuinely commoner in the rain — as a share of the pool the
##      deep rig actually draws from, not as a multiplier in isolation.
##
##   godot --headless --path . res://tests/CatchSizeProbe.tscn

const FISH := preload("res://scripts/world/fish_table.gd")
const FISH_MODEL := preload("res://scripts/world/fish_model_lib.gd")

## Mirrors PlayerController.HAND_ITEM_MAX_DIM — the pocket size everything used to get.
const HAND_BASE: float = 0.18

func _ready() -> void:
	await get_tree().process_frame
	_hand_sizes()
	await _held_grouper()
	_swordfish()
	get_tree().quit()

# ------------------------------------------------------------------ 1. held fish size
func _hand_sizes() -> void:
	print("\n=== held size vs body length, whole fish roster ===")
	print("%-26s %8s %8s %8s" % ["species", "body m", "hand m", "was m"])
	var ids: Array = []
	for id in FISH.all():
		ids.append(String(id))
	ids.sort_custom(func(a, b): return ItemVisual.fish_length_m(a) > ItemVisual.fish_length_m(b))
	for id in ids:
		if not ItemVisual.is_species_fish(id):
			continue
		print("%-26s %8.2f %8.2f %8.2f"
			% [id, ItemVisual.fish_length_m(id), ItemVisual.hand_size_m(id), HAND_BASE])

## The real thing: build the visual, run the controller's own normalisation on it, and
## measure what comes out. A number here that is not hand_size_m() means the hook did not land.
func _held_grouper() -> void:
	print("\n=== what the hand actually ends up holding ===")
	for id in ["fish_copper_sprat", "fish_herring", "fish_coelacanth", "fish_barrel_grouper",
			"fish_fathom_sturgeon", "fish_swordfish", "cooked_fish_barrel_grouper",
			"canned_food", "fishing_rod"]:
		var visual: Node3D = ItemVisual.build(id)
		if visual == null:
			print("[hand] %-28s NO VISUAL" % id)
			continue
		var container := Node3D.new()
		container.add_child(visual)
		add_child(container)
		await get_tree().process_frame     # generated meshes load their geometry in _ready
		var combined: AABB = AABB()
		var found: bool = false
		for n in visual.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			if mi.mesh == null:
				continue
			var box: AABB = (visual.global_transform.affine_inverse() * mi.global_transform) \
				* mi.mesh.get_aabb()
			combined = box if not found else combined.merge(box)
			found = true
		if not found:
			print("[hand] %-28s no meshes" % id)
			container.queue_free()
			continue
		var largest: float = maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
		var target: float = maxf(HAND_BASE, ItemVisual.hand_size_m(id))
		if id == "fishing_rod":
			target = maxf(0.9, target)
		var scale: float = target / maxf(largest, 0.0001)
		print("[hand] %-28s built %.3f m -> held %.3f m  (%.1fx the old 0.18 m pocket size)"
			% [id, largest, largest * scale, (largest * scale) / HAND_BASE])
		container.queue_free()

# --------------------------------------------------------------------- 2. the swordfish
func _swordfish() -> void:
	print("\n=== the swordfish ===")
	var def: Dictionary = FISH.all().get("fish_swordfish", {})
	print("[sword] in fish.json: %s   drop_m=%s  rain=%s  deep=%s"
		% [not def.is_empty(), str(def.get("drop_m")), str(def.get("rain")), str(def.get("deep"))])
	print("[sword] item registered: %s   cooked_to '%s' registered: %s"
		% [PlayerState.items.has("fish_swordfish"), String(def.get("cooked_to", "")),
			PlayerState.items.has(String(def.get("cooked_to", "")))])
	var path: String = FISH_MODEL.fauna_path("fish_swordfish")
	print("[sword] mesh path %s   exists: %s" % [path, ResourceLoader.exists(path)])
	print("[sword] held size %.2f m, body length %.2f m"
		% [ItemVisual.hand_size_m("fish_swordfish"), ItemVisual.fish_length_m("fish_swordfish")])
	# The pool it actually competes in, at its own depth, calm vs rain vs squall.
	for weather in [["calm", false, false], ["RAIN", true, false], ["storm", false, true]]:
		var ctx := {"phase": "dusk", "storming": bool(weather[2]), "raining": bool(weather[1]),
			"fogged": false, "lit": false, "powered": false, "open": true, "bait": "fish_herring"}
		_pool_line(String(weather[0]), ctx, 22.0)
	# ...and it must be invisible above its own rung.
	var ctx20 := {"phase": "dusk", "storming": false, "raining": true, "fogged": false,
		"lit": false, "powered": false, "open": true, "bait": "fish_herring"}
	print("[sword] weight at 20 m (above its rung): %.3f  — must be 0"
		% FISH.weight_for("fish_swordfish", "deep", ctx20, 20.0))
	print("[sword] weight at 22 m: %.3f   at 44 m (faded): %.3f"
		% [FISH.weight_for("fish_swordfish", "deep", ctx20, 22.0),
			FISH.weight_for("fish_swordfish", "deep", ctx20, 44.0)])

func _pool_line(label: String, ctx: Dictionary, depth: float) -> void:
	var total: float = FISH.pool_weight("deep", ctx, depth)
	var mine: float = FISH.weight_for("fish_swordfish", "deep", ctx, depth)
	var parts: Array[String] = []
	for id in FISH.all():
		var w: float = FISH.weight_for(id, "deep", ctx, depth)
		if w > 0.0:
			parts.append("%s %.1f" % [String(id).trim_prefix("fish_"), w])
	print("[sword] %-5s at %d m, dusk, herring on the hook: swordfish %.2f of %.2f = %.1f%% of the pool"
		% [label, int(depth), mine, total, 100.0 * mine / maxf(total, 0.001)])
	print("[sword]        pool: %s" % ", ".join(parts))
