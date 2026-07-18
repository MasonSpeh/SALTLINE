class_name BenchPanel extends Panel
## The rigging bench UI — SALTLINE's crafting is "lay it on the bench":
## move parts from your pack onto the bench surface; when the parts match
## something the rig knows how to be, its name appears; HOLD the work button
## (or Space) and hammer it real. Laid parts also appear physically on the
## bench top in-world. No recipe browser — the parts themselves are the menu.

const MAX_LAID: int = 4

static var recipes: Dictionary = {}

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

func _ready() -> void:
	load_recipes()
	custom_minimum_size = Vector2(620, 540)
	position = Vector2(-310, -270)
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

	# What the parts want to become.
	_match_label = RichTextLabel.new()
	_match_label.bbcode_enabled = true
	_match_label.fit_content = true
	_match_label.custom_minimum_size = Vector2(0, 84)
	_match_label.add_theme_font_size_override("normal_font_size", 14)
	vbox.add_child(_match_label)

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
	_pack_grid = GridContainer.new()
	_pack_grid.columns = 4
	_pack_grid.add_theme_constant_override("h_separation", 8)
	_pack_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(_pack_grid)

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

## Exact multiset match against a recipe's needs.
func current_match() -> String:
	var counts: Dictionary = _laid_counts()
	for rid in recipes:
		if _counts_equal(counts, recipes[rid]["needs"]):
			return rid
	return ""

## Recipes the laid parts are a strict subset of — the bench's whisper of intent.
func partial_matches() -> Array[String]:
	var counts: Dictionary = _laid_counts()
	var out: Array[String] = []
	if counts.is_empty():
		return out
	for rid in recipes:
		var needs: Dictionary = recipes[rid]["needs"]
		var subset: bool = true
		for item in counts:
			if counts[item] > int(needs.get(item, 0)):
				subset = false
				break
		if subset and not _counts_equal(counts, needs):
			out.append(rid)
	return out

func _laid_counts() -> Dictionary:
	var counts: Dictionary = {}
	for id in laid:
		counts[id] = counts.get(id, 0) + 1
	return counts

func _counts_equal(a: Dictionary, needs: Dictionary) -> bool:
	if a.size() != needs.size():
		return false
	for item in needs:
		if a.get(item, 0) != int(needs[item]):
			return false
	return true

# ---------------------------------------------------------------- working

func _set_working(on: bool) -> void:
	if on and current_match() == "":
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
	var recipe: Dictionary = recipes.get(_work_recipe, {})
	_working = false
	_work_recipe = ""     # so re-laying the same recipe next is a fresh craft, not stale resume
	_work_elapsed = 0.0
	_work_bar.value = 0.0
	laid.clear()
	var product: String = recipe.get("makes", "")
	if product != "":
		PlayerState.add_item(product)
	if bench:
		AudioDirector.play_one_shot("breaker", bench.global_position, -6.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Made: %s" % recipe.get("name", product))
		if recipe.get("makes", "").ends_with("_kit"):
			hud.toast("Made: %s — press B to build it." % recipe.get("name", product))
	Journal.discover("place_rigging_bench")
	refresh()

# ---------------------------------------------------------------- display

func refresh() -> void:
	# Lay slots.
	for i in range(MAX_LAID):
		if i < laid.size():
			_laid_buttons[i].text = str(laid[i]).capitalize()
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
		b.text = str(it).capitalize()
		var id: String = str(it)
		b.pressed.connect(func() -> void: lay_item(id))
		_pack_grid.add_child(b)
	# Match line.
	var exact: String = current_match()
	if exact != "":
		var r: Dictionary = recipes[exact]
		_match_label.text = "[b][color=#7fd8c8]These parts make: %s[/color][/b]\n%s" % [r["name"], r["desc"]]
		_work_button.disabled = false
	else:
		_work_button.disabled = true
		var partials: Array[String] = partial_matches()
		if laid.is_empty():
			_match_label.text = "[color=#8a8f8c]The bench is clear. Lay parts on it and see what they want to be.[/color]"
		elif partials.is_empty():
			_match_label.text = "[color=#8a8f8c]These parts don't speak to each other. Take something back.[/color]"
		else:
			var lines: Array[String] = []
			for rid in partials:
				var r2: Dictionary = recipes[rid]
				var missing: Array[String] = []
				var counts: Dictionary = _laid_counts()
				for item in r2["needs"]:
					var short: int = int(r2["needs"][item]) - int(counts.get(item, 0))
					if short > 0:
						missing.append("%d× %s" % [short, str(item).capitalize()])
				lines.append("[b]%s[/b] — still needs %s" % [r2["name"], ", ".join(missing)])
			_match_label.text = "[color=#c9b458]This wants to become:[/color]\n" + "\n".join(lines)
	_update_part_visuals()

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
