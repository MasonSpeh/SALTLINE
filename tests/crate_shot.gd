extends Node
## Photographs the rebuilt crate exchange. Run WINDOWED — ItemIcons bakes its slot pictures
## through SubViewports, which present nothing under --headless, so a headless run saves a
## panel of empty sockets and lies about the whole point.
##
## Deliberately does NOT load Main.tscn the way inventory_shot does: the panel under test is a
## CanvasLayer and a LootContainer, and building the rig to look at a UI costs 24 seconds and
## the owner's framerate for nothing.

const CRATE_LOAD := [
	"rope", "rope", "rope", "steel_plate", "steel_plate", "driftwood", "driftwood",
	"driftwood", "scrap_metal", "canned_food", "bottle_water", "storm_lantern",
	"bandage", "cooked_fish",
]
const PACK_LOAD := [
	"crude_knife", "rope", "rope", "plank", "plank", "plank", "scrap_metal",
	"bolt", "cable_length", "water_ration",
]

func _ready() -> void:
	var hud: HUD = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	await get_tree().process_frame
	PlayerState.hotbar = PlayerState._new_hotbar()
	PlayerState.hotbar_counts = PlayerState._new_hotbar_counts()
	PlayerState.inventory.clear()
	PlayerState.inventory_counts.clear()
	for id in PACK_LOAD:
		PlayerState.add_item(id)
	var crate := LootContainer.new()
	crate.display_name = "Deck Store"
	crate.items.assign(CRATE_LOAD)
	add_child(crate)
	await get_tree().process_frame
	hud.open_crate(crate)
	# Icons bake one per frame; ~18 distinct ids across both sides.
	await get_tree().create_timer(6.0).timeout
	# Stand in for the cursor so the hover info box is in the same frame.
	hud._crate_slots[0].mouse_entered.emit()
	hud._refresh_crate_panel()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("[crate] saved err=", get_viewport().get_texture().get_image().save_png(
		"/tmp/crate_panel.png"))
	# The two it has to match, same window, same run.
	hud.toggle_panel("crate")
	hud.toggle_panel("inventory")
	hud._inv_slot_hovered(1)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("[pack] saved err=", get_viewport().get_texture().get_image().save_png(
		"/tmp/crate_ref_pack.png"))
	hud.toggle_panel("inventory")
	hud.bench_panel.lay_item("plank")
	hud.toggle_panel("bench")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("[bench] saved err=", get_viewport().get_texture().get_image().save_png(
		"/tmp/crate_ref_bench.png"))
	get_tree().quit()
