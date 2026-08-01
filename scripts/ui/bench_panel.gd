class_name BenchPanel extends Panel
## The rigging bench UI — SALTLINE's crafting is "lay it on the bench":
## move parts from your pack onto the bench surface; when the parts match
## something the rig knows how to be, its name appears; HOLD the work button
## (or Space) and hammer it real. Laid parts also appear physically on the
## bench top in-world. No recipe browser — the parts themselves are the menu.

const MAX_LAID: int = 4
## Slot geometry, matched to the pack's (hud.gd builds 74 px squares with a picture, a
## bottom name/count strip and a riveted steel frame). Owner, 2026-07-30: "Update the
## rigging bench, that should also have UI updated like the inventory."
const LAY_SLOT_PX: int = 84
const PACK_SLOT_PX: int = 66
const PACK_COLS: int = 8
## How big a laid part is drawn ON THE BENCH TOP, in metres along its longest axis. Small
## enough that four of them fit across a 1.6 m bench with air between them, big enough that
## a bolt is still a bolt rather than a speck.
const LAY_WORLD_SIZE: float = 0.30
## Rest this far proud of the top, so a flat part (a plank, a tarp) does not z-fight with the
## plank it is lying on. The same 5 mm support_index.gd rests every settled prop by.
const LAY_CLEAR: float = 0.005
## The hint list is grouped under these headers so ~40 recipes stay readable.
const CAT_ORDER: Array[String] = ["material", "structure", "gear", "food"]
const CAT_LABEL := {
	"material": "MATERIALS", "structure": "STRUCTURES", "gear": "GEAR", "food": "FOOD",
}
const MAX_HINT_LINES: int = 6
## Match-list geometry. The box is tall enough for a full hint set — MAX_HINT_LINES of
## recipe plus the "wants to become" title and up to four CAT_ORDER group headers — so
## the common case never clips, and it is an exact multiple of the line height so the
## overflow case ends between rows instead of slicing one ("Tool Belt" cut in half).
const MATCH_LINE_H: int = 21
const MATCH_VISIBLE_LINES: int = MAX_HINT_LINES + 5
## A needs key starting with "@" is a token matching a FAMILY of items, not one id.
const TOKEN_LABEL := {"@raw_fish": "Any Raw Fish"}

static var recipes: Dictionary = {}
static var items: Dictionary = {}

var laid: Array[String] = []
var bench: Node3D = null            ## the in-world CraftBench, for part visuals + sound
var _pack_grid: GridContainer
var _laid_buttons: Array[Button] = []
var _match_label: RichTextLabel
var _work_button: Button
var _work_bar: ProgressBar
var _working: bool = false
var _work_elapsed: float = 0.0
var _work_recipe: String = ""
var _part_visuals: Array[Node3D] = []
## The HUD's own ItemIcons renderer, handed over at construction. Shared rather than a second
## instance: an icon costs a SubViewport render per distinct item, and the pack has already
## paid for every id the player is carrying.
var icons: Node = null
var _hover_label: Label
var _pack_slots: Array[Button] = []
## What each pack slot currently holds, parallel to _pack_slots — the click and hover handlers
## are bound once at build time and read this, so a refresh never rebuilds a single Control.
var _pack_ids: Array[String] = []

static func load_recipes() -> void:
	if not recipes.is_empty():
		return
	var f: FileAccess = FileAccess.open("res://data/recipes.json", FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			recipes = parsed
			recipes.erase("_schema")

static func load_items() -> void:
	if not items.is_empty():
		return
	var f: FileAccess = FileAccess.open("res://data/items.json", FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			items = parsed
			items.erase("_schema")

## Survivor-facing name for an item id or a family token ("@raw_fish").
static func item_name(id: String) -> String:
	if id.begins_with("@"):
		return str(TOKEN_LABEL.get(id, id))
	load_items()
	var entry: Variant = items.get(id, null)
	if typeof(entry) == TYPE_DICTIONARY and entry.has("name"):
		return str(entry["name"])
	return id.capitalize()

func _ready() -> void:
	load_recipes()
	load_items()
	custom_minimum_size = Vector2(720, 620)
	position = Vector2(-360, -310)
	visible = false
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18
	vbox.offset_top = 12
	vbox.offset_right = -18
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := Label.new()
	title.text = "RIGGING BENCH        lay parts · work them"
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)
	# The pack's hazard-stripe rule, same colour and same 3 px, so the two panels read as
	# one piece of kit rather than two different UIs.
	var hazard_rule := ColorRect.new()
	hazard_rule.custom_minimum_size = Vector2(0, 3)
	hazard_rule.color = Color(0.62, 0.5, 0.14)
	hazard_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hazard_rule)

	# THE BENCH: four lay slots, built exactly like a pack slot.
	var laid_caption := Label.new()
	laid_caption.text = "ON THE BENCH — click a part to take it back"
	laid_caption.add_theme_font_size_override("font_size", 13)
	laid_caption.add_theme_color_override("font_color", Color(0.65, 0.7, 0.68))
	vbox.add_child(laid_caption)
	var laid_row := HBoxContainer.new()
	laid_row.add_theme_constant_override("separation", 8)
	laid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(laid_row)
	for i in range(MAX_LAID):
		var b: Button = slot_button(LAY_SLOT_PX)
		var idx: int = i
		b.pressed.connect(func() -> void: take_back(idx))
		b.mouse_entered.connect(func() -> void:
			_hover(str(laid[idx]) if idx < laid.size() else ""))
		laid_row.add_child(b)
		_laid_buttons.append(b)

	# What the parts want to become. Scrolls — a common part like driftwood or steel
	# plate is a partial for a dozen recipes now, and the list must not shove the pack
	# grid off the bottom of the panel.
	# Height is a whole number of MATCH_LINE_H rows on purpose. At 118px against a ~21px
	# line the box ended on half a row, so the list always read as a recipe cut in two
	# ("Deck Chair" sheared off by the work button) rather than as a list that scrolls.
	var match_scroll := ScrollContainer.new()
	match_scroll.custom_minimum_size = Vector2(0, MATCH_LINE_H * MATCH_VISIBLE_LINES)
	match_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(match_scroll)
	_match_label = RichTextLabel.new()
	_match_label.bbcode_enabled = true
	_match_label.fit_content = true
	_match_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_match_label.add_theme_font_size_override("normal_font_size", 14)
	match_scroll.add_child(_match_label)

	# Work button + progress.
	var work_row := HBoxContainer.new()
	work_row.add_theme_constant_override("separation", 12)
	vbox.add_child(work_row)
	_work_button = Button.new()
	_work_button.text = "HOLD TO WORK  (or hold Space)"
	_work_button.custom_minimum_size = Vector2(280, 44)
	_work_button.focus_mode = Control.FOCUS_NONE
	_work_button.disabled = true
	work_row.add_child(_work_button)
	_work_bar = ProgressBar.new()
	_work_bar.custom_minimum_size = Vector2(220, 44)
	_work_bar.show_percentage = false
	_work_bar.max_value = 1.0
	work_row.add_child(_work_bar)

	var pack_title := Label.new()
	pack_title.text = "YOUR PACK — click a part to lay it on the bench"
	pack_title.add_theme_font_size_override("font_size", 13)
	pack_title.add_theme_color_override("font_color", Color(0.65, 0.7, 0.68))
	vbox.add_child(pack_title)
	var pack_scroll := ScrollContainer.new()
	pack_scroll.custom_minimum_size = Vector2(0, PACK_SLOT_PX * 2 + 14)
	pack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pack_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(pack_scroll)
	_pack_grid = GridContainer.new()
	_pack_grid.columns = PACK_COLS
	_pack_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pack_grid.add_theme_constant_override("h_separation", 6)
	_pack_grid.add_theme_constant_override("v_separation", 6)
	pack_scroll.add_child(_pack_grid)
	# Built ONCE for the largest the pack can ever be, then filled per refresh — the old grid
	# queue_free()d and rebuilt every button on every refresh, which drops the hover state and
	# the mouse-over the player is in the middle of.
	var max_slots: int = PlayerState.HOTBAR_SIZE + PlayerState.MAX_BACKPACK \
		+ PlayerState.TOOL_BELT_SLOTS
	for i in range(max_slots):
		var pb: Button = slot_button(PACK_SLOT_PX)
		var pidx: int = i
		pb.pressed.connect(func() -> void:
			if pidx < _pack_ids.size():
				lay_item(_pack_ids[pidx]))
		pb.mouse_entered.connect(func() -> void:
			_hover(_pack_ids[pidx] if pidx < _pack_ids.size() else ""))
		_pack_grid.add_child(pb)
		_pack_slots.append(pb)

	# The name popup. The pack names the item under the cursor at the bottom of the screen;
	# a panel this size can do it in place, right under the grid the cursor is in.
	_hover_label = Label.new()
	_hover_label.custom_minimum_size = Vector2(0, 20)
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_label.add_theme_font_size_override("font_size", 14)
	_hover_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.84))
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hover_label)

## One pack-style slot: a square riveted socket with the item's own render filling it and an
## always-visible name/count strip along the bottom.
##
## THE ONE COPY. It started as a lift of hud.gd's inventory grid ("so the two panels cannot
## drift apart"), which is a promise a copy cannot keep — the crate exchange was built before
## either of them and stayed a list of wide name buttons through two theme passes because
## nothing tied it to the others. So it is static now and hud.gd calls it for BOTH the pack
## grid and the crate exchange: same sizes, same three styleboxes, same amber hover, by
## construction rather than by discipline.
static func slot_button(px: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	var slot_normal := StyleBoxFlat.new()
	slot_normal.bg_color = Color(0.145, 0.15, 0.16)
	slot_normal.border_color = Color(0.05, 0.05, 0.055)
	slot_normal.set_border_width_all(2)
	slot_normal.set_corner_radius_all(3)
	b.add_theme_stylebox_override("normal", slot_normal)
	var slot_hover := slot_normal.duplicate()
	slot_hover.border_color = Color(0.7, 0.55, 0.2)
	slot_hover.bg_color = Color(0.19, 0.19, 0.2)
	b.add_theme_stylebox_override("hover", slot_hover)
	var slot_pressed := slot_normal.duplicate()
	slot_pressed.border_color = Color(0.62, 0.5, 0.14)
	slot_pressed.bg_color = Color(0.1, 0.1, 0.11)
	b.add_theme_stylebox_override("pressed", slot_pressed)
	b.add_theme_stylebox_override("focus", slot_normal)
	b.add_theme_stylebox_override("disabled", slot_normal)
	var pic := TextureRect.new()
	pic.name = "Pic"
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.offset_left = 4
	pic.offset_top = 4
	pic.offset_right = -4
	pic.offset_bottom = -4
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	var tag_bg := Panel.new()
	tag_bg.name = "TagBG"
	tag_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tag_bg.custom_minimum_size = Vector2(0, TAG_STRIP_PX)
	tag_bg.offset_top = -TAG_STRIP_PX
	tag_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag_style := StyleBoxFlat.new()
	tag_style.bg_color = Color(0.02, 0.02, 0.02, 0.72)
	tag_style.content_margin_left = 2
	tag_style.content_margin_right = 2
	tag_bg.add_theme_stylebox_override("panel", tag_style)
	var tag_lbl := Label.new()
	tag_lbl.name = "Tag"
	tag_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag_lbl.clip_text = true
	tag_lbl.add_theme_font_size_override("font_size", 9)
	tag_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.84))
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_bg.add_child(tag_lbl)
	b.add_child(tag_bg)
	return b

## Fill one slot: the item's own render as the picture, the name (and stack count) in the
## strip. `id` empty leaves the socket bare rather than stale. `renderer` is the HUD's shared
## ItemIcons — passed in rather than read off `self`, because the crate exchange fills slots
## from hud.gd and there is only ever one renderer to hand it.
static func fill_slot(b: Button, id: String, count: int, empty_text: String,
		renderer: Node) -> void:
	var pic: TextureRect = b.get_node("Pic")
	var tag_bg: Panel = b.get_node("TagBG")
	var tag_lbl: Label = tag_bg.get_node("Tag")
	if id == "":
		pic.texture = null
		tag_bg.visible = false
		b.text = empty_text
		b.modulate = Color(1, 1, 1, 0.35)
		return
	pic.texture = renderer.get_icon(id) if renderer != null \
		and renderer.has_method("get_icon") else null
	tag_bg.visible = true
	tag_lbl.text = tag_text(id, count)
	b.text = ""
	b.modulate = Color(1, 1, 1)

## The pack's own abbreviation rule: a 66-74 px slot at 9 pt fits ~11-12 narrow characters,
## so long names are cut at a word boundary rather than left to Label.clip_text.
const _TAG_MAX_CHARS: int = 12
## Height of that bottom name/count strip. One number for every panel that builds a slot.
const TAG_STRIP_PX: int = 16
static func tag_text(id: String, count: int) -> String:
	var full: String = item_name(id)
	var suffix: String = " ×%d" % count if count > 1 else ""
	var budget: int = _TAG_MAX_CHARS - suffix.length()
	var shown: String = full
	if full.length() > budget:
		var cut: int = full.rfind(" ", budget)
		shown = full.substr(0, cut if cut > 3 else budget) + "…"
	return shown + suffix

func _hover(id: String) -> void:
	if _hover_label == null:
		return
	_hover_label.text = "" if id == "" else item_name(id)

var test_hold: bool = false   ## headless tests hold the work button through this

func _process(delta: float) -> void:
	if not visible:
		return
	# Space works as well as the mouse — either counts as "holding the hammer".
	var held: bool = _work_button.button_pressed or Input.is_key_pressed(KEY_SPACE) or test_hold
	if held and not _working and not _work_button.disabled:
		_set_working(true)
	elif _working and not held:
		_set_working(false)
	if _working:
		_work_elapsed += delta
		var need: float = recipes.get(_work_recipe, {}).get("work_sec", 2.5)
		_work_bar.value = clampf(_work_elapsed / need, 0.0, 1.0)
		# Hammer rhythm.
		if fmod(_work_elapsed, 0.55) < delta and bench:
			AudioDirector.play_one_shot("clang", bench.global_position, -16.0)
		if _work_elapsed >= need:
			_finish_work()

# ---------------------------------------------------------------- lay / take

func lay_item(item_id: String) -> bool:
	if laid.size() >= MAX_LAID or not PlayerState.has_item(item_id):
		return false
	PlayerState.remove_item(item_id)
	laid.append(item_id)
	refresh()
	if bench:
		AudioDirector.play_one_shot("step", bench.global_position, -18.0)
	return true

func take_back(idx: int) -> void:
	if _working or idx >= laid.size():
		return
	var id: String = laid[idx]
	if PlayerState.add_item(id):
		laid.remove_at(idx)
		refresh()

## Sweep the bench back into the pack. Anything that will not fit STAYS on the
## bench — walking away from a full pack must not delete the parts you laid.
func return_all() -> void:
	var stuck: Array[String] = []
	for id in laid:
		if not PlayerState.add_item(id):
			stuck.append(id)
	laid.assign(stuck)
	if not stuck.is_empty():
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("No room for all of it. The rest stays on the bench.")
	refresh()

# ---------------------------------------------------------------- matching

## Exact multiset match against a recipe's needs. When two recipes could read the
## same laid parts, the one whose TOOL you are actually carrying wins — otherwise
## we still return a match so the panel can say which tool it wants.
func current_match() -> String:
	var counts: Dictionary = _laid_counts()
	var fallback: String = ""
	for rid in recipes:
		if _fits(counts, recipes[rid]["needs"], true):
			if tool_ready(rid):
				return rid
			if fallback == "":
				fallback = rid
	return fallback

## Recipes the laid parts are a strict subset of — the bench's whisper of intent.
func partial_matches() -> Array[String]:
	var counts: Dictionary = _laid_counts()
	var out: Array[String] = []
	if counts.is_empty():
		return out
	for rid in recipes:
		var needs: Dictionary = recipes[rid]["needs"]
		if _fits(counts, needs, false) and not _fits(counts, needs, true):
			out.append(rid)
	return out

## The tool a recipe wants held (never laid, never consumed) — "" for none.
func recipe_tool(rid: String) -> String:
	return str(recipes.get(rid, {}).get("tool", ""))

## Tools are checked, not spent. You keep the hacksaw; the scrap becomes a plate.
## has_tool, not has_item — an upgraded tool satisfies the gate its crude version set.
func tool_ready(rid: String) -> bool:
	var t: String = recipe_tool(rid)
	return t == "" or PlayerState.has_tool(t)

func _laid_counts() -> Dictionary:
	var counts: Dictionary = {}
	for id in laid:
		counts[id] = counts.get(id, 0) + 1
	return counts

static func _is_token(key: String) -> bool:
	return key.begins_with("@")

## Family tokens: "@raw_fish" is any species you could actually put a knife through
## — not the picked-clean spine, not something the gulls already found.
static func _token_accepts(token: String, item: String) -> bool:
	match token:
		"@raw_fish":
			return item.begins_with("fish_") and item != "fish_bone" and item != "fish_rotten"
	return false

## Does the laid multiset `a` satisfy `needs`? exact=true demands equality (craftable),
## exact=false demands only that nothing is over-supplied (a partial, still building).
## Literal ids are claimed first, then family tokens eat whatever is left over.
func _fits(a: Dictionary, needs: Dictionary, exact: bool) -> bool:
	var left: Dictionary = a.duplicate()
	for k in needs:
		if _is_token(k):
			continue
		var have: int = int(left.get(k, 0))
		var want: int = int(needs[k])
		if have > want or (exact and have != want):
			return false
		left.erase(k)
	for k in needs:
		if not _is_token(k):
			continue
		var short: int = _consume_token(left, k, int(needs[k]))
		if exact and short > 0:
			return false
	return left.is_empty()

## Take up to `want` token-matching items out of `left`; returns how many are missing.
func _consume_token(left: Dictionary, token: String, want: int) -> int:
	for item in left.keys():
		if want <= 0:
			break
		if not _token_accepts(token, str(item)):
			continue
		var take: int = mini(want, int(left[item]))
		want -= take
		left[item] = int(left[item]) - take
		if int(left[item]) <= 0:
			left.erase(item)
	return want

## Per-need shortfall for the "still needs" hint line.
func _shortfall(a: Dictionary, needs: Dictionary) -> Array[String]:
	var left: Dictionary = a.duplicate()
	var out: Array[String] = []
	var token_keys: Array = []
	for k in needs:
		if _is_token(k):
			token_keys.append(k)
			continue
		var short: int = int(needs[k]) - int(left.get(k, 0))
		if short > 0:
			out.append("%d× %s" % [short, item_name(str(k))])
		left.erase(k)
	for k in token_keys:
		var missing: int = _consume_token(left, str(k), int(needs[k]))
		if missing > 0:
			out.append("%d× %s" % [missing, item_name(str(k))])
	return out

func _counts_equal(a: Dictionary, needs: Dictionary) -> bool:
	return _fits(a, needs, true)

# ---------------------------------------------------------------- working

func _set_working(on: bool) -> void:
	if on and (current_match() == "" or not tool_ready(current_match())):
		return
	if on:
		# Only zero progress when the recipe actually CHANGES. A one-frame drop in
		# `held` (cursor drifting off the HOLD button, a dropped frame) must RESUME
		# the same work, not restart it — else a real hold never reaches work_sec.
		var m: String = current_match()
		if m != _work_recipe:
			_work_recipe = m
			_work_elapsed = 0.0
	_working = on
	if not on:
		_work_bar.value = 0.0

func _finish_work() -> void:
	# Lose the tool mid-swing (dropped, eaten by the sea) and the work doesn't land.
	if _work_recipe == "" or not tool_ready(_work_recipe):
		_set_working(false)
		refresh()
		return
	var recipe: Dictionary = recipes.get(_work_recipe, {})
	# All-or-nothing, same contract as salvage: the laid parts are about to be
	# destroyed, so refuse the craft outright rather than consume the inputs and
	# bounce the output off a full pack. Counted BEFORE `laid` is cleared — laid
	# parts already left the pack, so clearing them frees no slot.
	if _free_slots() < _yield_total(recipe):
		_set_working(false)
		var hud_full: Node = get_tree().get_first_node_in_group("hud")
		if hud_full:
			hud_full.toast("No room in your pack for what this makes.")
		refresh()
		return
	_working = false
	_work_recipe = ""     # so re-laying the same recipe next is a fresh craft, not stale resume
	_work_elapsed = 0.0
	_work_bar.value = 0.0
	laid.clear()
	var product: String = str(recipe.get("makes", ""))
	var count: int = maxi(1, int(recipe.get("count", 1)))
	if product != "":
		for i in range(count):
			PlayerState.add_item(product)
	# Byproducts: filleting a fish leaves you the spine whether you wanted it or not.
	var extra: Dictionary = recipe.get("extra", {})
	for extra_id in extra:
		for i in range(maxi(1, int(extra[extra_id]))):
			PlayerState.add_item(str(extra_id))
	if bench:
		AudioDirector.play_one_shot("breaker", bench.global_position, -6.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		var made: String = str(recipe.get("name", product))
		if count > 1:
			made = "%s ×%d" % [made, count]
		hud.toast("Made: %s" % made)
		for extra_id2 in extra:
			hud.toast("Also: %s ×%d" % [item_name(str(extra_id2)), maxi(1, int(extra[extra_id2]))])
		if product.ends_with("_kit"):
			hud.toast("Made: %s — press B to build it." % recipe.get("name", product))
	Journal.discover("place_rigging_bench")
	refresh()

## Everything one craft will hand back: the product (times its count) plus byproducts.
func _yield_total(recipe: Dictionary) -> int:
	var n: int = 0
	if str(recipe.get("makes", "")) != "":
		n += maxi(1, int(recipe.get("count", 1)))
	var extra: Dictionary = recipe.get("extra", {})
	for extra_id in extra:
		n += maxi(1, int(extra[extra_id]))
	return maxi(n, 1)

## Free carry slots right now — hotbar holes plus room left in the pack.
func _free_slots() -> int:
	var n: int = 0
	for s in PlayerState.hotbar:
		if s == null:
			n += 1
	return n + maxi(0, PlayerState.backpack_capacity() - PlayerState.pack_used())

# ---------------------------------------------------------------- display

func refresh() -> void:
	# Lay slots — the item's own picture now, not its name in a wide button.
	for i in range(MAX_LAID):
		fill_slot(_laid_buttons[i], str(laid[i]) if i < laid.size() else "", 1,
			"· lay here ·", icons)
	# Pack grid: one slot per STACK, filled into buttons that already exist.
	var stacks: Array = _pack_stacks()
	_pack_ids.clear()
	for st in stacks:
		_pack_ids.append(str(st["id"]))
	for i in range(_pack_slots.size()):
		if i >= stacks.size():
			_pack_slots[i].visible = i < maxi(stacks.size(), PACK_COLS)
			fill_slot(_pack_slots[i], "", 0, "", icons)
			continue
		_pack_slots[i].visible = true
		fill_slot(_pack_slots[i], str(stacks[i]["id"]), int(stacks[i]["n"]), "", icons)
	# Match line.
	var exact: String = current_match()
	var partials: Array[String] = partial_matches()
	var blocks: Array[String] = []
	if exact != "":
		var r: Dictionary = recipes[exact]
		var ready: bool = tool_ready(exact)
		var head: String = "These parts make: %s" % r["name"]
		var tint: String = "#7fd8c8"
		if not ready:
			head = "These parts want to be: %s" % r["name"]
			tint = "#c9b458"
		blocks.append("[b][color=%s]%s[/color][/b]%s\n%s%s%s%s" % [
			tint, head, _tool_note(exact), r["desc"], _yield_note(exact),
			_stock_note(exact), _hint_note(exact)])
		_work_button.disabled = not ready
	else:
		_work_button.disabled = true
	# A finished match must not hide the rest of the tree: one plank IS a slat craft,
	# but it is also the start of a walkway, a lean-to and a drying rack.
	if not partials.is_empty():
		var lead: String = "This wants to become:"
		if exact != "":
			lead = "Or, with more parts:"
		blocks.append("[color=#c9b458]%s[/color]\n%s" % [lead, _hint_lines(partials)])
		# The nearest unfinished recipe gets the same have-vs-needs breakdown the finished
		# one does, so "still needs 2× Rope" is answerable without closing the panel and
		# opening the pack (owner: "player should also know how many of each material they
		# have left").
		blocks.append(_stock_note(partials[0], "%s — what it wants"
			% str(recipes[partials[0]]["name"])).strip_edges())
	if blocks.is_empty():
		if laid.is_empty():
			blocks.append("[color=#8a8f8c]The bench is clear. Lay parts on it and see what they want to be.[/color]")
		else:
			blocks.append("[color=#8a8f8c]These parts don't speak to each other. Take something back.[/color]")
	_match_label.text = "\n".join(blocks)
	_update_part_visuals()

## The pack as a list of STACKS — {id, n} per occupied slot, hotbar first, in the order the
## player sees them. The old grid appended one button per slot without its count, so a stack
## of six ropes read as one rope.
func _pack_stacks() -> Array:
	var out: Array = []
	for i in range(PlayerState.hotbar.size()):
		if PlayerState.hotbar[i] != null and String(PlayerState.hotbar[i]) != "":
			out.append({"id": String(PlayerState.hotbar[i]), "n": PlayerState.hotbar_stack(i)})
	for i in range(PlayerState.inventory.size()):
		if PlayerState.inventory[i] != null and String(PlayerState.inventory[i]) != "":
			out.append({"id": String(PlayerState.inventory[i]),
				"n": PlayerState.inventory_stack(i)})
	return out

## HOW MANY OF EACH MATERIAL YOU ACTUALLY HAVE, per ingredient, against what the recipe wants.
##
## Owner, 2026-07-30: "player should also know how many of each material they have left."
## The hint lines only ever said what was MISSING from the bench ("still needs 2× Rope"), which
## is not the same question — a player short two ropes cannot tell from that whether they are
## in the pack, in a crate, or not on the rig at all. Each line is
## `<name>   <on the bench> + <in the pack> / <needed>`, green once the count is covered by
## what is laid, amber while the pack can still cover it, red when the rig cannot.
## Family tokens ("@raw_fish") are counted over everything the token accepts, which is the same
## rule _consume_token crafts by.
func _stock_note(rid: String, heading: String = "MATERIALS  (on the bench + in the pack / needed)") -> String:
	var needs: Dictionary = recipes.get(rid, {}).get("needs", {})
	if needs.is_empty():
		return ""
	var laid_counts: Dictionary = _laid_counts()
	var lines: Array[String] = ["\n[color=#6f7a76]%s[/color]" % heading]
	for k in needs:
		var key: String = str(k)
		var want: int = int(needs[k])
		var on_bench: int = 0
		var in_pack: int = 0
		if _is_token(key):
			for id in laid_counts:
				if _token_accepts(key, str(id)):
					on_bench += int(laid_counts[id])
			for id2 in _pack_ids_all():
				if _token_accepts(key, id2):
					in_pack += PlayerState.count_item(id2)
		else:
			on_bench = int(laid_counts.get(key, 0))
			in_pack = PlayerState.count_item(key)
		var tint: String = "#c96f58"                     # short, and the pack cannot cover it
		if on_bench >= want:
			tint = "#7fd8c8"                             # already on the bench
		elif on_bench + in_pack >= want:
			tint = "#c9b458"                             # reachable: go and lay it
		lines.append("  [color=%s]%-22s %d + %d / %d[/color]"
			% [tint, item_name(key), on_bench, in_pack, want])
	return "\n".join(lines)

## Every distinct id the pack holds — the search space a family token is counted over.
func _pack_ids_all() -> Array[String]:
	var seen: Dictionary = {}
	for it in PlayerState.hotbar:
		if it != null and String(it) != "":
			seen[String(it)] = true
	for it in PlayerState.inventory:
		if it != null and String(it) != "":
			seen[String(it)] = true
	var out: Array[String] = []
	for k in seen:
		out.append(str(k))
	return out

## The "still needs" list, grouped Materials / Structures / Gear / Food and capped —
## a single plate of steel is a partial for a dozen things now.
func _hint_lines(partials: Array[String]) -> String:
	var counts: Dictionary = _laid_counts()
	var lines: Array[String] = []
	var shown: int = 0
	for cat in CAT_ORDER:
		var group: Array[String] = []
		for rid in partials:
			if shown >= MAX_HINT_LINES:
				break
			if str(recipes[rid].get("cat", "material")) != cat:
				continue
			var missing: Array[String] = _shortfall(counts, recipes[rid]["needs"])
			group.append("  [b]%s[/b] — still needs %s%s" % [
				recipes[rid]["name"], ", ".join(missing), _tool_note(rid)])
			shown += 1
		if not group.is_empty():
			lines.append("[color=#6f7a76]%s[/color]" % CAT_LABEL.get(cat, cat))
			lines.append_array(group)
	var hidden: int = partials.size() - shown
	if hidden > 0:
		lines.append("[color=#6f7a76]…and %d more. Lay another part to narrow it.[/color]" % hidden)
	return "\n".join(lines)

## The authored line under the description — the bench's own opinion of the thing
## ("Nobody is coming. Cut the ring."). Dimmed and italic so it reads as a thought
## rather than as another instruction.
func _hint_note(rid: String) -> String:
	var h: String = str(recipes.get(rid, {}).get("hint", ""))
	if h == "":
		return ""
	return "\n[i][color=#7c8a86]%s[/color][/i]" % h

## "needs: Hacksaw in hand" — tools gate the craft but are never laid or spent.
func _tool_note(rid: String) -> String:
	var t: String = recipe_tool(rid)
	if t == "":
		return ""
	if PlayerState.has_item(t):
		return "  [color=#7fd8c8](%s in hand)[/color]" % item_name(t)
	# Name what you are ACTUALLY holding, or the panel says "needs: Crude Knife"
	# at a player who is carrying the honed one that supersedes it.
	for better: String in PlayerState.TOOL_SUPERSEDES.get(t, []):
		if PlayerState.has_item(better):
			return "  [color=#7fd8c8](%s in hand)[/color]" % item_name(better)
	return "  [color=#c96f58](needs: %s in hand)[/color]" % item_name(t)

## Spell out multi-output and byproduct crafts so the bench never lies about its yield.
func _yield_note(rid: String) -> String:
	var r: Dictionary = recipes.get(rid, {})
	var bits: Array[String] = []
	var count: int = maxi(1, int(r.get("count", 1)))
	if count > 1:
		bits.append("%d× %s" % [count, item_name(str(r.get("makes", "")))])
	var extra: Dictionary = r.get("extra", {})
	for extra_id in extra:
		bits.append("%d× %s" % [maxi(1, int(extra[extra_id])), item_name(str(extra_id))])
	if bits.is_empty():
		return ""
	return "\n[color=#8a8f8c]Yields %s[/color]" % ", ".join(bits)

## PHYSICAL PARTS ON THE IN-WORLD BENCH TOP — the real items, on the real surface.
##
## Owner, 2026-07-30: "The items should also display on the table surface as the player
## selects/lays them down to craft." They already did, after a fashion: four flat pastel BOXES
## whose colour was `hash(id) * 0.000001`, standing at a hand-typed local y = 1.08. The wet-deck
## bench's carcass is 0.9 m tall CENTRED on its own origin, so its top is +0.45 — every part was
## floating 0.63 m over the bench it was supposed to be lying on, which is the exact class of
## bug docs/AGENT_TRAPS.md's "never hand-type a Y coordinate" rule exists for.
##
## Now: ItemVisual.build() — the same node the world puts on the ground and the hand holds and
## ItemIcons photographs for the slot above — scaled to LAY_WORLD_SIZE along its longest axis
## and SEATED on a measured surface, spread across the bench's own measured footprint.
func _update_part_visuals() -> void:
	# REMOVED, not just queue_free()d. `queue_free` is deferred, so the old parts are still
	# children of the bench when _bench_surface() measures it on the very next line — and since
	# they are standing ON the surface, the surface reads higher every refresh. Measured: three
	# parts walked the "bench top" from local y 0.50 to 1.468 over one panel session, and the
	# parts went with it, hanging a metre over the plank. Detach first.
	for v in _part_visuals:
		if is_instance_valid(v):
			if v.get_parent() != null:
				v.get_parent().remove_child(v)
			v.queue_free()
	_part_visuals.clear()
	if bench == null or not is_instance_valid(bench) or laid.is_empty():
		return
	var top: Dictionary = _bench_surface()
	var span: float = float(top["half_x"]) * 1.30      # 65% of the plank, each side of centre
	for i in range(laid.size()):
		var v: Node3D = ItemVisual.build(str(laid[i]))
		if v == null:
			continue
		bench.add_child(v)
		_part_visuals.append(v)
		var box: AABB = _tree_aabb(v, v)
		var largest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
		var k: float = LAY_WORLD_SIZE / largest if largest > 0.0001 else 1.0
		v.scale = Vector3.ONE * k
		# Laid out along the bench's long axis, centred, and rotated a little each so four
		# parts read as a job in progress rather than as a shop display.
		var t: float = 0.0 if laid.size() < 2 else float(i) / float(laid.size() - 1) - 0.5
		var cx: float = t * span
		var cz: float = (-0.06 if i % 2 == 0 else 0.06) * float(top["half_z"])
		v.rotation.y = deg_to_rad(-18.0 + 12.0 * float(i))
		# Base ON the surface, centred over its slot: the AABB is in the visual's OWN space,
		# so its centre and its floor both have to come back through the same scale.
		var c: Vector3 = box.get_center()
		v.position = Vector3(cx - c.x * k,
			float(top["y"]) + LAY_CLEAR - box.position.y * k, cz - c.z * k)

## THE BENCH'S REAL TOP AND FOOTPRINT, in the bench's own local space. Measured, never typed.
##
## Two sources, because one is not enough here. The CraftBench node's own geometry is its
## carcass (`build_box_visual`, 1.6 x 0.9 x 0.7 centred on the origin), but both benches on the
## rig carry a 1.7 x 0.06 x 0.8 PLANK that rig_builder/rig_superstructure add to THEMSELVES, not
## to the bench — so the carcass AABB alone is 50 mm short and every part would sit inside the
## plank. So the bench's own tree is measured first, and then its siblings are scanned for a
## small slab lying directly over that footprint, which is what the plank is.
var _surface_cache: Dictionary = {}
func _bench_surface() -> Dictionary:
	if _surface_cache.has(bench.get_instance_id()):
		return _surface_cache[bench.get_instance_id()]
	var box: AABB = _tree_aabb(bench, bench, _part_visuals)
	if box.size == Vector3.ZERO:
		# A bench with no visual children of its own (a build-mode ghost, a stub in a probe):
		# fall back to its collision shape, which every spawn path does give it.
		for c in bench.get_children():
			var cs := c as CollisionShape3D
			if cs != null and cs.shape is BoxShape3D:
				var half: Vector3 = (cs.shape as BoxShape3D).size * 0.5
				box = AABB(cs.position - half, half * 2.0)
	var top_y: float = box.end.y
	var half_x: float = maxf(box.size.x, 0.4) * 0.5
	var half_z: float = maxf(box.size.z, 0.3) * 0.5
	var parent: Node = bench.get_parent()
	if parent != null:
		var inv: Transform3D = bench.global_transform.affine_inverse()
		for sib in parent.get_children():
			var vi := sib as VisualInstance3D
			if vi == null or vi == bench:
				continue
			var w: AABB = vi.get_aabb()
			if w.size.x > 3.0 or w.size.z > 3.0 or w.size.y > 0.35:
				continue    # merged dressing chunks and furniture, not a bench top
			var local: AABB = (inv * vi.global_transform) * w
			if absf(local.get_center().x) > half_x or absf(local.get_center().z) > half_z:
				continue
			if local.end.y > top_y and local.end.y < top_y + 0.35:
				top_y = local.end.y
				half_x = maxf(half_x, local.size.x * 0.5)
				half_z = maxf(half_z, local.size.z * 0.5)
	top_y = maxf(top_y, _welded_top(top_y, half_x, half_z))
	_surface_cache[bench.get_instance_id()] = {
		"y": top_y, "half_x": half_x, "half_z": half_z}
	return _surface_cache[bench.get_instance_id()]

## THE WORK TOP IS NOT A NODE. `rig_batcher.gd` welds the rig's dressing into a handful of
## `MergedDressing` ArrayMesh chunks and FREES the sources, so the 1.7 x 0.06 x 0.8 plank both
## benches wear — built by rig_builder/rig_superstructure onto THEMSELVES, not onto the bench —
## cannot be found by any walk over the tree. That is docs/AGENT_TRAPS.md's "search from the
## picture, not the tree" in its purest form, and a merged chunk's AABB is up to 13 m across so
## it answers nothing. So the question is put to the TRIANGLES: the highest vertex inside the
## bench's own footprint and within 350 mm of the carcass top. Without it the parts sit 50 mm
## down inside the plank — a fifth of a 260 mm item buried.
##
## Bounded (VERT_BUDGET) and cached per bench for the session, so this vertex walk is paid once
## on the first open of a given bench and never again.
const VERT_BUDGET: int = 400000
## A BOX HAS NO VERTICES IN THE MIDDLE OF ITS FACE. The first cut of this probe asked whether a
## vertex fell inside the carcass footprint and found nothing at all: the plank is 1.7 x 0.8
## against a 1.6 x 0.7 carcass, so all eight of its corners are OUTSIDE by 50 mm and every one
## was rejected. The footprint test is therefore given a margin — a work top overhangs its
## carcass, that is what a work top is — while the 350 mm height window keeps a neighbouring
## crate or barrel out.
const FOOT_MARGIN: float = 0.30
func _welded_top(base_y: float, half_x: float, half_z: float) -> float:
	if bench == null or not bench.is_inside_tree():
		return base_y
	var inv: Transform3D = bench.global_transform.affine_inverse()
	var best: float = base_y
	var budget: int = VERT_BUDGET
	for n in bench.get_tree().get_nodes_in_group("merged_dressing"):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# Cheap reject on the chunk as a whole: the bench has to be inside it at all.
		var chunk: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not chunk.intersects(AABB(Vector3(-half_x, base_y - 0.05, -half_z),
				Vector3(half_x * 2.0, 0.40, half_z * 2.0))):
			continue
		var to_local: Transform3D = inv * mi.global_transform
		for si in range(mi.mesh.get_surface_count()):
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			budget -= verts.size()
			if budget < 0:
				return best
			for v in verts:
				var l: Vector3 = to_local * v
				if l.y <= best or l.y > base_y + 0.35:
					continue
				if absf(l.x) > half_x + FOOT_MARGIN or absf(l.z) > half_z + FOOT_MARGIN:
					continue
				best = l.y
	return best

## Combined AABB of every mesh under `node`, expressed in `base`'s local space. `skip` prunes
## whole sub-trees — the laid parts themselves, which must never be measured as part of the
## surface they are standing on.
static func _tree_aabb(node: Node3D, base: Node3D, skip: Array = []) -> AABB:
	var out: AABB = AABB()
	var found: bool = false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if skip.has(n):
			continue
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var t: Transform3D = Transform3D.IDENTITY
		var cur: Node3D = mi
		while cur != null and cur != base:
			t = cur.transform * t
			cur = cur.get_parent() as Node3D
		var b: AABB = t * mi.mesh.get_aabb()
		out = b if not found else out.merge(b)
		found = true
	return out if found else AABB()
