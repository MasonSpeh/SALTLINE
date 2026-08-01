extends Node
## THE CRATE EXCHANGE, DRIVEN THE WAY THE PLAYER DRIVES IT.
##
## Builds a real HUD and a real LootContainer and moves goods across, because the exchange is
## the one panel whose bugs are invisible from the source: it was rebuilt onto the pack's slot
## kit (BenchPanel.slot_button / fill_slot) and every claim that makes — icons, stack counts,
## locker steel, rivets, capacity captions, hover info — is a fact about built nodes, not about
## the code that asks for them. av2_probe covers the locker round trip in a live world; this
## covers the PANEL, in two seconds, without one.
##
## It also asserts the pack grid and the bench lay slots still build, since all three now share
## one factory and a change to it can only be caught by checking all three.

var _fails: int = 0

func _ok(msg: String) -> void:
	print("  ok   ", msg)

func _bad(msg: String) -> void:
	_fails += 1
	print("  FAIL ", msg)

func _ready() -> void:
	await get_tree().process_frame
	var hud: HUD = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	await get_tree().process_frame

	print("\n== crate exchange ==")
	var crate := LootContainer.new()
	crate.display_name = "Supply Crate"
	crate.items = ["rope", "rope", "rope", "steel_plate", "driftwood"] as Array[String]
	add_child(crate)
	await get_tree().process_frame

	# ---- panel opens, and wears the pack's kit
	hud.open_crate(crate)
	await get_tree().process_frame
	if not hud.crate_panel.visible:
		_bad("open_crate did not raise the panel")
		_finish()
		return
	_ok("open_crate raises the exchange panel")
	if hud.crate_title.text == "SUPPLY CRATE":
		_ok("title reads the crate's own name")
	else:
		_bad("title = '%s'" % hud.crate_title.text)
	var st: StyleBox = hud.crate_panel.get_theme_stylebox("panel")
	var locker: StyleBoxFlat = hud._locker_panel_style()
	if st is StyleBoxFlat and (st as StyleBoxFlat).border_color.is_equal_approx(locker.border_color):
		_ok("panel wears the crew-locker steel stylebox")
	else:
		_bad("panel is not on _locker_panel_style")
	var rivets: int = 0
	for c in hud.crate_panel.get_children():
		if c is Panel and (c as Panel).custom_minimum_size == Vector2(7, 7):
			rivets += 1
	if rivets == 4:
		_ok("four corner rivets")
	else:
		_bad("rivet count = %d" % rivets)

	# ---- slots: icons, tags, counts
	var slots: Array = hud._crate_slots
	if slots.size() >= hud.CRATE_SLOTS_BUILT:
		_ok("crate side built %d sockets up front" % slots.size())
	else:
		_bad("only %d sockets built" % slots.size())
	var first: Button = slots[0]
	if first.custom_minimum_size == Vector2(hud.CRATE_SLOT_PX, hud.CRATE_SLOT_PX):
		_ok("sockets are %d px squares" % hud.CRATE_SLOT_PX)
	else:
		_bad("socket size = %s" % first.custom_minimum_size)
	if first.get_node_or_null("Pic") != null and first.get_node_or_null("TagBG/Tag") != null:
		_ok("socket has the pack's Pic + TagBG/Tag children")
	else:
		_bad("socket is missing Pic/TagBG")
	var tag: Label = first.get_node("TagBG/Tag")
	if tag.text.contains("×3"):
		_ok("stack count on the tag strip: '%s'" % tag.text)
	else:
		_bad("first tag = '%s' (expected a ×3 rope stack)" % tag.text)
	if hud._crate_slot_ids.size() == 3 and hud._crate_slot_ids[0] == "rope":
		_ok("crate grouped to 3 stacks, rope first")
	else:
		_bad("crate ids = %s" % str(hud._crate_slot_ids))
	if slots[hud.CRATE_SLOTS_BUILT - 1].visible:
		_ok("the empty sockets stay on screen, like the pack's")
	else:
		_bad("empty sockets were hidden — the grid will float over dead space")

	# ---- captions carry the capacity
	if hud._crate_caption.text.contains("5 inside"):
		_ok("crate caption: '%s'" % hud._crate_caption.text)
	else:
		_bad("crate caption = '%s'" % hud._crate_caption.text)
	# Counted over hotbar + pack, since the column shows both.
	if hud._crate_pack_caption.text.contains(
			"/%d" % (PlayerState.HOTBAR_SIZE + PlayerState.backpack_capacity())):
		_ok("pack caption: '%s'" % hud._crate_pack_caption.text)
	else:
		_bad("pack caption = '%s'" % hud._crate_pack_caption.text)

	# ---- hover writes the pack's own info box
	first.mouse_entered.emit()
	await get_tree().process_frame
	if hud._crate_info.text.contains("Rope"):
		_ok("hover fills the info box (%d chars)" % hud._crate_info.text.length())
	else:
		_bad("info box after hover = '%s'" % hud._crate_info.text)

	# ---- click one across, then the whole stack
	hud._crate_move("rope", true, false)
	await get_tree().process_frame
	if PlayerState.count_item("rope") == 1 and crate.items.count("rope") == 2:
		_ok("click takes exactly one")
	else:
		_bad("after one take: pack=%d crate=%d" % [
			PlayerState.count_item("rope"), crate.items.count("rope")])
	hud._crate_move("rope", true, true)
	await get_tree().process_frame
	if PlayerState.count_item("rope") == 3 and not crate.items.has("rope"):
		_ok("shift-click takes the whole stack")
	else:
		_bad("after stack take: pack=%d crate=%s" % [
			PlayerState.count_item("rope"), str(crate.items)])
	hud._crate_move("rope", false, true)
	await get_tree().process_frame
	if PlayerState.count_item("rope") == 0 and crate.items.count("rope") == 3:
		_ok("shift-click stows the whole stack back")
	else:
		_bad("after stack stow: pack=%d crate=%s" % [
			PlayerState.count_item("rope"), str(crate.items)])

	# ---- the probes' own entry points still work
	hud._crate_take("driftwood")
	await get_tree().process_frame
	if PlayerState.has_item("driftwood") and not crate.items.has("driftwood"):
		_ok("_crate_take(id) still moves one (av2_probe's path)")
	else:
		_bad("_crate_take(id) broke")
	hud._crate_stow("driftwood")
	await get_tree().process_frame
	if not PlayerState.has_item("driftwood") and crate.items.has("driftwood"):
		_ok("_crate_stow(id) still moves one")
	else:
		_bad("_crate_stow(id) broke")

	# ---- sweeps
	hud._crate_take_all()
	await get_tree().process_frame
	if crate.items.is_empty() and PlayerState.count_item("rope") == 3:
		_ok("TAKE ALL empties the crate")
	else:
		_bad("after take all: crate=%s" % str(crate.items))
	if hud._crate_caption.text.contains("· empty ·"):
		_ok("empty crate says so in the caption")
	else:
		_bad("empty caption = '%s'" % hud._crate_caption.text)
	hud._crate_stow_all()
	await get_tree().process_frame
	if PlayerState.pack_used() == 0 and crate.items.size() == 5:
		_ok("STOW ALL empties the pack back into the crate")
	else:
		_bad("after stow all: pack_used=%d crate=%d" % [
			PlayerState.pack_used(), crate.items.size()])

	# ---- ESC closes
	hud.toggle_panel("crate")
	if not hud.crate_panel.visible:
		_ok("toggle closes it")
	else:
		_bad("toggle did not close it")

	# ---- the two panels it must match still build
	print("\n== the panels it was matched to ==")
	if hud.inventory_panel != null and hud._inv_buttons.size() > 0 \
			and hud._inv_buttons[0].get_node_or_null("TagBG/Tag") != null:
		_ok("pack grid still builds (%d sockets, shared factory)" % hud._inv_buttons.size())
	else:
		_bad("pack grid broke")
	hud.bench_panel.laid.assign(["rope"])
	hud.bench_panel.refresh()
	await get_tree().process_frame
	if hud.bench_panel._laid_buttons[0].get_node("TagBG/Tag").text.contains("Rope"):
		_ok("bench lay slot still fills through the shared factory")
	else:
		_bad("bench fill broke: '%s'"
			% hud.bench_panel._laid_buttons[0].get_node("TagBG/Tag").text)
	_finish()

func _finish() -> void:
	print("\n%s — %d failure(s)\n" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
