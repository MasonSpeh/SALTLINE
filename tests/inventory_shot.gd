extends Node
## Visual check on the square icon slots. Run WINDOWED with --always-on-top — an occluded
## window presents nothing and saves a black or stale frame.
##
## Fills the pack with a deliberately mixed load (a fish, a tool, a drink, a material, a
## weapon, a stacked consumable) and photographs the pack panel and the hotbar, so the
## question "does every item actually read as itself?" has an answer you can look at
## rather than infer. Prints which items got an icon and which fell back to their name.

const LOAD := [
	"fish_barrel_grouper", "fish_herring", "cooked_fish_slate_cod",
	"bottle_water", "bottle_empty", "thermos_empty",
	"crude_knife", "crude_spear", "fishing_rod", "prybar", "hammer_tool",
	"flare", "bandage", "medkit", "scrap_metal", "rope", "cable_spool",
	"canned_food", "canned_peaches", "flashlight", "storm_lantern", "tool_belt",
]

var main: Node3D

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(24.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	PlayerState.hotbar = [null, null, null, null]
	PlayerState.hotbar_counts = [1, 1, 1, 1]
	PlayerState.inventory.clear()
	PlayerState.inventory_counts.clear()
	for id in LOAD:
		PlayerState.add_item(id)
	# A stack, so the ×N glyph is exercised against a picture.
	for i in range(5):
		PlayerState.add_item("scrap_metal")
	PlayerState.inventory_changed.emit()
	main.hud.toggle_panel("inventory")
	# Icons bake one per frame; this load is ~22 distinct items, so a couple of seconds is
	# generous. If a slot still shows a word after this, that item genuinely has no art.
	await get_tree().create_timer(6.0).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	print("[inv] saved err=", img.save_png("/tmp/inv_icons.png"))
	# Report coverage explicitly — a screenshot shows the slots that ARE filled, but the
	# list of what fell back is the actionable half ("most holdable items have good
	# visual graphics" is the owner's bar, so name the ones that miss it).
	var icons: Node = main.hud._icons
	var missing: Array[String] = []
	for id in LOAD:
		if icons._cache.get(id, null) == null:
			missing.append(id)
	print("[inv] items with no icon (%d of %d): %s" % [missing.size(), LOAD.size(), ", ".join(missing)])
	get_tree().quit()
