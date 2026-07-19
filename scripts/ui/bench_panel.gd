class_name BenchPanel extends Panel
## The rigging bench UI — SALTLINE's crafting is "lay it on the bench":
## move parts from your pack onto the bench surface; when the parts match
## something the rig knows how to be, its name appears; HOLD the work button
## (or Space) and hammer it real. Laid parts also appear physically on the
## bench top in-world. No recipe browser — the parts themselves are the menu.

const MAX_LAID: int = 4
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
	custom_minimum_size = Vector2(620, 660)
	position = Vector2(-310, -330)
	visible = false
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18
	vbox.offset_top = 12
	vbox.offset_right = -18
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var title := Label.new()
	title.text = "RIGGING BENCH        lay parts · work them"
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)

	# THE BENCH: four lay slots.
	var laid_row := HBoxContainer.new()
	laid_row.add_theme_constant_override("separation", 8)
	laid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(laid_row)
	for i in range(MAX_LAID):
		var b := Button.new()
		b.custom_minimum_size = Vector2(130, 56)
		b.focus_mode = Control.FOCUS_NONE
		var idx: int = i
		b.pressed.connect(func() -> void: take_back(idx))
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
	pack_scroll.custom_minimum_size = Vector2(0, 196)
	pack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pack_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(pack_scroll)
	_pack_grid = GridContainer.new()
	_pack_grid.columns = 4
	_pack_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pack_grid.add_theme_constant_override("h_separation", 8)
	_pack_grid.add_theme_constant_override("v_separation", 8)
	pack_scroll.add_child(_pack_grid)

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

func return_all() -> void:
	for id in laid:
		PlayerState.add_item(id)
	laid.clear()
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
func tool_ready(rid: String) -> bool:
	var t: String = recipe_tool(rid)
	return t == "" or PlayerState.has_item(t)

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

# ---------------------------------------------------------------- display

func refresh() -> void:
	# Lay slots.
	for i in range(MAX_LAID):
		if i < laid.size():
			_laid_buttons[i].text = item_name(str(laid[i]))
			_laid_buttons[i].modulate = Color(1, 0.95, 0.75)
		else:
			_laid_buttons[i].text = "· lay here ·"
			_laid_buttons[i].modulate = Color(1, 1, 1, 0.4)
	# Pack grid: one button per item instance.
	for c in _pack_grid.get_children():
		c.queue_free()
	var all_items: Array = []
	for it in PlayerState.hotbar:
		if it != null:
			all_items.append(it)
	all_items.append_array(PlayerState.inventory)
	for it in all_items:
		var b := Button.new()
		b.custom_minimum_size = Vector2(130, 40)
		b.focus_mode = Control.FOCUS_NONE
		b.text = item_name(str(it))
		var id: String = str(it)
		b.pressed.connect(func() -> void: lay_item(id))
		_pack_grid.add_child(b)
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
		blocks.append("[b][color=%s]%s[/color][/b]%s\n%s%s" % [
			tint, head, _tool_note(exact), r["desc"], _yield_note(exact)])
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
	if blocks.is_empty():
		if laid.is_empty():
			blocks.append("[color=#8a8f8c]The bench is clear. Lay parts on it and see what they want to be.[/color]")
		else:
			blocks.append("[color=#8a8f8c]These parts don't speak to each other. Take something back.[/color]")
	_match_label.text = "\n".join(blocks)
	_update_part_visuals()

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

## "needs: Hacksaw in hand" — tools gate the craft but are never laid or spent.
func _tool_note(rid: String) -> String:
	var t: String = recipe_tool(rid)
	if t == "":
		return ""
	if PlayerState.has_item(t):
		return "  [color=#7fd8c8](%s in hand)[/color]" % item_name(t)
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

## Physical parts on the in-world bench top.
func _update_part_visuals() -> void:
	for v in _part_visuals:
		if is_instance_valid(v):
			v.queue_free()
	_part_visuals.clear()
	if bench == null:
		return
	for i in range(laid.size()):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.24, 0.14, 0.24)
		var hue: float = fmod(hash(laid[i]) * 0.000001, 1.0)
		bm.material = MatLib.flat(Color.from_hsv(hue, 0.35, 0.65))
		mi.mesh = bm
		bench.add_child(mi)
		mi.position = Vector3(-0.55 + i * 0.37, 1.08, 0.0)
		_part_visuals.append(mi)
