class_name HUD extends CanvasLayer
## The slice's entire 2D UI: context prompt, toast line, 4-slot hotbar, survival
## stat bars (LIFE/HUNGER/THIRST/WARMTH), crate exchange panel, full-screen
## reading overlay, black fade layer, and the dawn end card. Built in code.

var prompt_label: Label
var prompt_chip: PanelContainer
var prompt_locked: bool = false   # scripted hint owns the chip; ray won't overwrite
var toast_label: Label
var crosshair: Label
var objective_label: Label
var hotbar_slots: Array[PanelContainer] = []
var life_bar: StatBar
var hunger_bar: StatBar
var thirst_bar: StatBar
var warmth_bar: StatBar
var sick_chip: PanelContainer
var reading_panel: Panel
var reading_title: Label
var reading_body: RichTextLabel
var fade_rect: ColorRect
var end_card: CenterContainer

# Panels: help / journal / inventory (one open at a time)
var help_button: Button
var journal_button: Button
var help_panel: Panel
var journal_panel: Panel
var journal_text: RichTextLabel
var inventory_panel: Panel
var inv_grid: GridContainer
var inv_info: Label
var _inv_buttons: Array[Button] = []
var bench_panel: BenchPanel
var crate_panel: Panel
var crate_title: Label
var _crate_list: VBoxContainer
var _pack_list: VBoxContainer
var _crate: LootContainer = null

var _toast_tween: Tween
var reading_open: bool = false
var _thirst_bound: bool = false   # PlayerState.thirst_changed connected?
var _life_bound: bool = false     # PlayerState.life_changed connected?

func _ready() -> void:
	add_to_group("hud")
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_build_panels()
	PlayerState.inventory_changed.connect(_refresh_hotbar)
	PlayerState.inventory_changed.connect(_refresh_inventory_panel)
	PlayerState.inventory_changed.connect(_refresh_crate_panel)
	PlayerState.hunger_changed.connect(func(v: float) -> void: hunger_bar.set_value(v))
	PlayerState.warmth_changed.connect(func(v: float) -> void: warmth_bar.set_value(v))
	# thirst/life are new PlayerState stats — bind defensively so the HUD works
	# the moment the signals exist and never crashes if one is briefly absent.
	if PlayerState.has_signal("thirst_changed"):
		PlayerState.connect("thirst_changed", func(v: float) -> void: thirst_bar.set_value(v))
		_thirst_bound = true
	if PlayerState.has_signal("life_changed"):
		PlayerState.connect("life_changed", func(v: float) -> void: life_bar.set_value(v))
		_life_bound = true
	Journal.entry_added.connect(func(_id: String, _t: String) -> void: _update_journal_badge())
	_refresh_hotbar()
	hunger_bar.set_value(PlayerState.hunger)
	warmth_bar.set_value(PlayerState.warmth)
	thirst_bar.set_value(_stat_value_or_full("thirst"))
	life_bar.set_value(_stat_value_or_full("life"))

func _process(_delta: float) -> void:
	# SICK chip: sickness has no changed-signal, so poll it.
	var sick: bool = PlayerState.sickness > 0.25
	sick_chip.visible = sick
	if sick:
		sick_chip.modulate.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.008)
	# Until thirst/life signals exist, keep those bars honest by polling.
	if not _thirst_bound:
		thirst_bar.set_value(_stat_value_or_full("thirst"))
	if not _life_bound:
		life_bar.set_value(_stat_value_or_full("life"))

## Defensive read for stats another system may not have added yet.
func _stat_value_or_full(prop: String) -> float:
	var v: Variant = PlayerState.get(prop)
	if v is float:
		return float(v)
	return 1.0

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Context prompt — a subtle chip sitting just under the crosshair, so the "what
	# button do I press" answer is always right where the eyes already are. Auto-sizes
	# to its text and stays centered; hidden entirely when there's nothing to interact with.
	prompt_chip = PanelContainer.new()
	prompt_chip.set_anchors_preset(Control.PRESET_CENTER)
	prompt_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_chip.grow_vertical = Control.GROW_DIRECTION_BOTH
	prompt_chip.position = Vector2(0, 44)
	prompt_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.04, 0.05, 0.06, 0.72)
	chip_style.set_corner_radius_all(7)
	chip_style.content_margin_top = 6
	chip_style.content_margin_bottom = 6
	chip_style.content_margin_left = 16
	chip_style.content_margin_right = 16
	chip_style.border_color = Color(0.55, 0.6, 0.62, 0.5)
	chip_style.set_border_width_all(1)
	prompt_chip.add_theme_stylebox_override("panel", chip_style)
	prompt_chip.visible = false
	root.add_child(prompt_chip)
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 17)
	prompt_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	prompt_chip.add_child(prompt_label)

	# Toast line above the prompt.
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position += Vector2(-300, -170)
	toast_label.custom_minimum_size = Vector2(600, 30)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 16)
	toast_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	toast_label.modulate.a = 0.0
	root.add_child(toast_label)

	# Crosshair dot — brightens and swells to a ring when aimed at something usable.
	crosshair = Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	crosshair.pivot_offset = Vector2(6, 16)
	root.add_child(crosshair)

	# Objective line, top-left — the one thing the player should be doing right now.
	objective_label = Label.new()
	objective_label.position = Vector2(20, 18)
	objective_label.add_theme_font_size_override("font_size", 16)
	objective_label.add_theme_color_override("font_color", Color(0.82, 0.85, 0.88))
	objective_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	objective_label.add_theme_constant_override("outline_size", 4)
	root.add_child(objective_label)

	# Top-right: journal + help buttons (also on keys J / H; I for inventory).
	var topright := HBoxContainer.new()
	topright.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	topright.position = Vector2(-190, 14)
	topright.add_theme_constant_override("separation", 8)
	root.add_child(topright)
	journal_button = Button.new()
	journal_button.text = "✎ JOURNAL"
	journal_button.custom_minimum_size = Vector2(110, 34)
	journal_button.focus_mode = Control.FOCUS_NONE
	journal_button.pressed.connect(func() -> void: toggle_panel("journal"))
	topright.add_child(journal_button)
	help_button = Button.new()
	help_button.text = "?"
	help_button.custom_minimum_size = Vector2(34, 34)
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.pressed.connect(func() -> void: toggle_panel("help"))
	topright.add_child(help_button)

	# Hotbar: 4 slots, bottom-left.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.position = Vector2(16, -64)
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	for i in range(PlayerState.HOTBAR_SIZE):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(110, 44)
		var lbl := Label.new()
		lbl.name = "L"
		lbl.text = str(i + 1)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		slot.add_child(lbl)
		slot.modulate = Color(1, 1, 1, 0.65)
		bar.add_child(slot)
		hotbar_slots.append(slot)

	# Survival bars: LIFE / HUNGER / THIRST / WARMTH, always visible, stacked just
	# above the hotbar. The stack grows upward so the SICK chip never covers slots.
	var stats := VBoxContainer.new()
	stats.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stats.position = Vector2(16, -72)
	stats.add_theme_constant_override("separation", 4)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stats)
	sick_chip = PanelContainer.new()
	var sick_style := StyleBoxFlat.new()
	sick_style.bg_color = Color(0.14, 0.28, 0.13, 0.8)
	sick_style.set_corner_radius_all(4)
	sick_style.border_color = Color(0.5, 0.8, 0.4, 0.5)
	sick_style.set_border_width_all(1)
	sick_style.content_margin_left = 8
	sick_style.content_margin_right = 8
	sick_style.content_margin_top = 2
	sick_style.content_margin_bottom = 2
	sick_chip.add_theme_stylebox_override("panel", sick_style)
	sick_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sick_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sick_chip.visible = false
	var sick_lbl := Label.new()
	sick_lbl.text = "SICK"
	sick_lbl.add_theme_font_size_override("font_size", 11)
	sick_lbl.add_theme_color_override("font_color", Color(0.72, 0.95, 0.6))
	sick_chip.add_child(sick_lbl)
	stats.add_child(sick_chip)
	life_bar = StatBar.new("LIFE", Color(0.85, 0.3, 0.3))
	stats.add_child(life_bar)
	hunger_bar = StatBar.new("HUNGER", Color(0.9, 0.7, 0.3))
	stats.add_child(hunger_bar)
	thirst_bar = StatBar.new("THIRST", Color(0.4, 0.8, 0.85))
	stats.add_child(thirst_bar)
	warmth_bar = StatBar.new("WARMTH", Color(0.9, 0.55, 0.3))
	stats.add_child(warmth_bar)

	# Reading overlay (full-screen text; stand-in for in-world paper).
	reading_panel = Panel.new()
	reading_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.08, 0.96)
	reading_panel.add_theme_stylebox_override("panel", style)
	reading_panel.visible = false
	add_child(reading_panel)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 220)
	margin.add_theme_constant_override("margin_right", 220)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 80)
	reading_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)
	reading_title = Label.new()
	reading_title.add_theme_font_size_override("font_size", 26)
	reading_title.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	vbox.add_child(reading_title)
	reading_body = RichTextLabel.new()
	reading_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reading_body.add_theme_font_size_override("normal_font_size", 18)
	reading_body.add_theme_color_override("default_color", Color(0.82, 0.8, 0.75))
	vbox.add_child(reading_body)
	var hint := Label.new()
	hint.text = "[E]  put it down"
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

	# Fade layer (cold open, contact blackouts) — above everything but the end card.
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)

	# End card (hidden until the second dawn).
	end_card = CenterContainer.new()
	end_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_card.visible = false
	add_child(end_card)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 24)
	end_card.add_child(card_box)
	var title := Label.new()
	title.text = "SALTLINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	card_box.add_child(title)
	var sub := Label.new()
	sub.text = "First Night.  To be continued."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.6, 0.63, 0.66))
	card_box.add_child(sub)
	var credits := Label.new()
	credits.text = "\na quiet, patient, heavy thing\n\n[R] restart      [Q] quit"
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.add_theme_font_size_override("font_size", 14)
	credits.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5))
	card_box.add_child(credits)

func show_prompt(text: String) -> void:
	if prompt_locked:
		return   # a scripted hint (e.g. the cold open) owns the chip right now
	_set_chip(("[E]   " + text) if text != "" else "")
	set_targeting(text != "")

func show_prompt_raw(text: String) -> void:
	## Used while carrying a prop — full control of the line, no "[E]" prefix.
	if prompt_locked:
		return
	_set_chip(text)

## A persistent, ray-proof prompt for scripted moments (cold open, tutorials).
## Pass "" to release it back to the interaction system.
func set_hint(text: String) -> void:
	prompt_locked = text != ""
	_set_chip(text)
	set_targeting(text != "")

func _set_chip(text: String) -> void:
	prompt_label.text = text
	prompt_chip.visible = text != ""

func set_targeting(on: bool) -> void:
	if not crosshair:
		return
	if on:
		crosshair.text = "◎"
		crosshair.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6, 0.95))
	else:
		crosshair.text = "·"
		crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))

func set_objective(text: String) -> void:
	objective_label.text = text

func toast(text: String) -> void:
	toast_label.text = text
	if _toast_tween:
		_toast_tween.kill()
	toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 1.0)

func show_reading(title: String, body: String) -> void:
	reading_title.text = title
	reading_body.text = body
	reading_panel.visible = true
	reading_open = true

func close_reading() -> void:
	reading_panel.visible = false
	reading_open = false

func _unhandled_input(event: InputEvent) -> void:
	if reading_open and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		close_reading()
		get_viewport().set_input_as_handled()
	if end_card.visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			get_tree().paused = false
			get_tree().reload_current_scene()
		elif event.keycode == KEY_Q:
			get_tree().quit()

func _refresh_hotbar() -> void:
	for i in range(hotbar_slots.size()):
		var lbl: Label = hotbar_slots[i].get_node("L")
		var item: Variant = PlayerState.hotbar[i]
		lbl.text = "%d  %s" % [i + 1, str(item).capitalize() if item != null else "—"]
		hotbar_slots[i].modulate.a = 0.95 if item != null else 0.5

func fade_to_black(duration: float) -> Tween:
	var tw: Tween = create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, duration)
	return tw

func fade_from_black(duration: float) -> Tween:
	var tw: Tween = create_tween()
	tw.tween_property(fade_rect, "color:a", 0.0, duration)
	return tw

func set_black() -> void:
	fade_rect.color.a = 1.0

func show_end_card() -> void:
	end_card.visible = true

# ============================ panels: help / journal / inventory ==============

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.09, 0.1, 0.97)
	s.border_color = Color(0.35, 0.4, 0.42)
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(18)
	return s

func _make_panel(w: float, h: float) -> Panel:
	var p := Panel.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(w, h)
	p.position = Vector2(-w * 0.5, -h * 0.5)
	p.add_theme_stylebox_override("panel", _panel_style())
	p.visible = false
	add_child(p)
	return p

func _build_panels() -> void:
	# HELP — controls and the shape of the day.
	help_panel = _make_panel(560, 580)
	var help_text := RichTextLabel.new()
	help_text.bbcode_enabled = true
	help_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	help_text.offset_left = 18
	help_text.offset_top = 14
	help_text.offset_right = -18
	help_text.offset_bottom = -14
	help_text.add_theme_font_size_override("normal_font_size", 15)
	help_text.text = """[b]SALTLINE — HOW TO SURVIVE THE FIRST NIGHT[/b]

[b]The day:[/b] wake in the lifeboat → climb the rig → find the cable spool →
splice the burned cable → throw Master Breaker 4-A → when night falls,
[b]stay inside the floodlight wash[/b] → see the dawn.

[b]Move[/b]           WASD · Shift sprint · Space jump
[b]Posture[/b]        Ctrl (hold) crouch — slow, quiet, hard to spot
                Z lie flat on the deck — a slow crawl, eye to the plating, sky overhead
                (Space or Z to rise · a low ceiling keeps you down until you crawl clear)
[b]Interact[/b]       E — one context verb (take / open / read / connect / operate)
[b]Climb[/b]          HOLD E on a ladder — E rides up, E+S rides down, release to let go
[b]Carry[/b]          E grabs loose props · LMB throws · E/G sets down
[b]Hotbar[/b]         1–4 brings that item to hand · same number again eats or drinks it
[b]Inventory[/b]      I — pack and hotbar, click items to move them
[b]Crates[/b]         E opens an exchange panel — take what you need, stow what you don't
[b]Journal[/b]        J — discoveries, item notes, craft hints
[b]Hook[/b]           F — throw the rigging hook (craft it at the bench)
[b]Craft[/b]          E at the rigging bench — lay parts on it, hold WORK / Space
[b]Build[/b]          B — ghost preview · LMB place · R rotate · Tab next kit · B done
[b]Pause[/b]          Esc — volume, mouse, invert-Y

[b]Body[/b]
· Watch [b]LIFE[/b] — starving or dehydration drains it; food and water bring it back.
· Glow worms must be [b]seared at a bench[/b] before eating — raw ones make you sick.

[b]Tips[/b]
· The fire barrel on the wet deck is warmth that needs no power.
· The gyre south of the rig collects what the sea carries. Hook it.
· Bloom lamps you build make real safe light — the crab honors them.
· A lean-to is a pocket of warmth anywhere. Walkways bridge anything.
· When the gulls leave, you have one dusk of grace. Use it.
· Listen. The claw-ticks through the deck are a countdown."""
	help_panel.add_child(help_text)

	# JOURNAL — discoveries, grouped; logs re-readable.
	journal_panel = _make_panel(640, 560)
	var jscroll := ScrollContainer.new()
	jscroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	jscroll.offset_left = 18
	jscroll.offset_top = 14
	jscroll.offset_right = -18
	jscroll.offset_bottom = -14
	journal_panel.add_child(jscroll)
	journal_text = RichTextLabel.new()
	journal_text.bbcode_enabled = true
	journal_text.fit_content = true
	journal_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_text.add_theme_font_size_override("normal_font_size", 15)
	jscroll.add_child(journal_text)

	# INVENTORY — hotbar row + pack grid, click to move. Minecraft, pocket edition.
	inventory_panel = _make_panel(560, 480)
	var ivbox := VBoxContainer.new()
	ivbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	ivbox.offset_left = 18
	ivbox.offset_top = 12
	ivbox.offset_right = -18
	ivbox.offset_bottom = -12
	ivbox.add_theme_constant_override("separation", 10)
	inventory_panel.add_child(ivbox)
	var ititle := Label.new()
	ititle.text = "PACK        (click: hotbar ⇄ pack)"
	ititle.add_theme_font_size_override("font_size", 17)
	ivbox.add_child(ititle)
	inv_grid = GridContainer.new()
	inv_grid.columns = 4
	inv_grid.add_theme_constant_override("h_separation", 8)
	inv_grid.add_theme_constant_override("v_separation", 8)
	ivbox.add_child(inv_grid)
	for i in range(PlayerState.HOTBAR_SIZE + PlayerState.MAX_BACKPACK):
		var b := Button.new()
		b.custom_minimum_size = Vector2(118, 52)
		b.focus_mode = Control.FOCUS_NONE
		var idx: int = i
		b.pressed.connect(func() -> void: _inv_slot_clicked(idx))
		b.mouse_entered.connect(func() -> void: _inv_slot_hovered(idx))
		inv_grid.add_child(b)
		_inv_buttons.append(b)
	inv_info = Label.new()
	inv_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv_info.custom_minimum_size = Vector2(0, 90)
	inv_info.add_theme_font_size_override("font_size", 13)
	inv_info.add_theme_color_override("font_color", Color(0.72, 0.76, 0.72))
	ivbox.add_child(inv_info)

	# CRATE — exchange with a storage crate: its contents left, your pack right.
	crate_panel = _make_panel(560, 460)
	var cbox := VBoxContainer.new()
	cbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	cbox.offset_left = 18
	cbox.offset_top = 12
	cbox.offset_right = -18
	cbox.offset_bottom = -12
	cbox.add_theme_constant_override("separation", 10)
	crate_panel.add_child(cbox)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	cbox.add_child(crow)
	crate_title = Label.new()
	crate_title.text = "CRATE"
	crate_title.add_theme_font_size_override("font_size", 17)
	crate_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(crate_title)
	var take_all := Button.new()
	take_all.text = "TAKE ALL"
	take_all.custom_minimum_size = Vector2(96, 30)
	take_all.focus_mode = Control.FOCUS_NONE
	take_all.pressed.connect(_crate_take_all)
	crow.add_child(take_all)
	var close_x := Button.new()
	close_x.text = "✕"
	close_x.custom_minimum_size = Vector2(30, 30)
	close_x.focus_mode = Control.FOCUS_NONE
	close_x.pressed.connect(func() -> void: toggle_panel("crate"))
	crow.add_child(close_x)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	cbox.add_child(cols)
	_crate_list = _crate_column(cols, "CRATE — click to take")
	_pack_list = _crate_column(cols, "PACK — click to stow")

	# BENCH — crafting surface, opened by the in-world rigging bench.
	bench_panel = BenchPanel.new()
	bench_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(bench_panel)
	bench_panel.set_anchors_preset(Control.PRESET_CENTER)
	bench_panel.offset_left = -310
	bench_panel.offset_top = -270
	bench_panel.offset_right = 310
	bench_panel.offset_bottom = 270

func any_panel_open() -> bool:
	return help_panel.visible or journal_panel.visible or inventory_panel.visible \
		or bench_panel.visible or crate_panel.visible

func open_bench(bench: Node3D) -> void:
	bench_panel.bench = bench
	toggle_panel("bench")

## Called by a LootContainer's OPEN verb — crate ⇄ pack exchange view.
func open_crate(container: LootContainer) -> void:
	_crate = container
	toggle_panel("crate")

func toggle_panel(which: String) -> void:
	var target: Panel = {"help": help_panel, "journal": journal_panel,
		"inventory": inventory_panel, "bench": bench_panel, "crate": crate_panel}[which]
	var was_open: bool = target.visible
	if bench_panel.visible:
		bench_panel.return_all()   # never eat laid parts on close
	help_panel.visible = false
	journal_panel.visible = false
	inventory_panel.visible = false
	bench_panel.visible = false
	crate_panel.visible = false
	if not was_open:
		target.visible = true
		if which == "journal":
			Journal.mark_seen()
			_update_journal_badge()
			_rebuild_journal()
		elif which == "inventory":
			_refresh_inventory_panel()
		elif which == "bench":
			bench_panel.refresh()
		elif which == "crate":
			_refresh_crate_panel()
	if not crate_panel.visible:
		_crate = null   # drop the reference the moment the exchange view closes
	_sync_panel_mode()

func _sync_panel_mode() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if any_panel_open():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if player:
			player.ui_locked = true
	else:
		if not get_tree().paused and not end_card.visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if player:
			player.ui_locked = false

func _input(event: InputEvent) -> void:
	if end_card.visible or reading_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if get_tree().paused:
			return   # pause menu owns the screen
		match event.keycode:
			KEY_I:
				if crate_panel.visible:
					toggle_panel("crate")   # crate view already shows the pack
				else:
					toggle_panel("inventory")
				get_viewport().set_input_as_handled()
			KEY_J:
				toggle_panel("journal")
				get_viewport().set_input_as_handled()
			KEY_H:
				toggle_panel("help")
				get_viewport().set_input_as_handled()
			KEY_E:
				if crate_panel.visible:
					toggle_panel("crate")
					get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if any_panel_open():
					var open: String = "help" if help_panel.visible else (
						"journal" if journal_panel.visible else (
						"inventory" if inventory_panel.visible else (
						"crate" if crate_panel.visible else "bench")))
					toggle_panel(open)
					get_viewport().set_input_as_handled()

func _update_journal_badge() -> void:
	journal_button.text = ("✎ JOURNAL (%d)" % Journal.unseen_count) if Journal.unseen_count > 0 else "✎ JOURNAL"

func _rebuild_journal() -> void:
	var bb: String = "[b]SURVIVOR'S JOURNAL[/b]\n"
	var sections := [
		["creature", "THINGS ALIVE OUT HERE"],
		["item", "THINGS IN MY HANDS"],
		["place", "THINGS I UNDERSTAND NOW"],
	]
	var total: int = 0
	for sec in sections:
		var ids: Array = Journal.entries_by_category(sec[0])
		if ids.is_empty():
			continue
		bb += "\n[color=#8fb0a8][b]— %s —[/b][/color]\n" % sec[1]
		for id in ids:
			var e: Dictionary = Journal.data[id]
			bb += "\n[b]%s[/b]\n%s\n" % [e.get("title", id), e.get("body", "")]
			if e.get("hint", "") != "":
				bb += "[color=#c9b458]▸ %s[/color]\n" % e["hint"]
			total += 1
	var logs: Array[String] = Journal.read_logs
	if not logs.is_empty():
		bb += "\n[color=#8fb0a8][b]— PAPERS I'VE READ —[/b][/color]\n"
		for rid in logs:
			var entry: Dictionary = Readable.text_for(rid)
			bb += "\n[b]%s[/b]\n[color=#9a9a90]%s[/color]\n" % [entry.get("title", rid), entry.get("body", "")]
			total += 1
	if total == 0:
		bb += "\nNothing yet. Touch things. Read things. Get close to what glows\n(within reason)."
	journal_text.text = bb

func _inv_all_slots() -> Array:
	var slots: Array = []
	for i in range(PlayerState.HOTBAR_SIZE):
		slots.append(PlayerState.hotbar[i])
	for i in range(PlayerState.MAX_BACKPACK):
		slots.append(PlayerState.inventory[i] if i < PlayerState.inventory.size() else null)
	return slots

func _refresh_inventory_panel() -> void:
	if inventory_panel == null or not inventory_panel.visible:
		return
	var slots: Array = _inv_all_slots()
	for i in range(_inv_buttons.size()):
		var item: Variant = slots[i]
		var label: String = str(item).capitalize() if item != null else "—"
		if i < PlayerState.HOTBAR_SIZE:
			_inv_buttons[i].text = "%d· %s" % [i + 1, label]
			_inv_buttons[i].modulate = Color(1, 0.95, 0.75) if item != null else Color(0.85, 0.85, 0.8, 0.7)
		else:
			_inv_buttons[i].text = label
			_inv_buttons[i].modulate = Color(1, 1, 1) if item != null else Color(1, 1, 1, 0.45)

func _inv_slot_clicked(idx: int) -> void:
	if idx < PlayerState.HOTBAR_SIZE:
		PlayerState.hotbar_to_backpack(idx)
	else:
		PlayerState.backpack_to_hotbar(idx - PlayerState.HOTBAR_SIZE)
	_refresh_inventory_panel()

func _inv_slot_hovered(idx: int) -> void:
	var slots: Array = _inv_all_slots()
	var item: Variant = slots[idx]
	if item == null:
		inv_info.text = ""
		return
	var id: String = str(item)
	var def: Dictionary = PlayerState.items.get(id, {})
	var jinfo: Dictionary = Journal.item_info(id)
	var line: String = def.get("name", id.capitalize())
	if def.get("use", "") == "eat":
		line += "  —  edible (+%d%% hunger)" % int(def.get("hunger", 0.0) * 100.0)
	else:
		line += "  —  tool"
	if jinfo.get("body", "") != "":
		line += "\n%s" % jinfo["body"]
	if jinfo.get("hint", "") != "":
		line += "\n▸ %s" % jinfo["hint"]
	inv_info.text = line

# ============================ crate exchange ==================================

## One side of the crate exchange: heading + scrollable button list.
func _crate_column(parent: Control, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	var head := Label.new()
	head.text = heading
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(0.65, 0.7, 0.68))
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list

func _crate_item_button(item_id: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = item_id.capitalize()
	b.custom_minimum_size = Vector2(0, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b

func _crate_empty_line(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.5, 0.54, 0.52))
	return l

## Rebuild both columns from live state. Also connected to inventory_changed, so
## eating from the hotbar (etc.) while the panel is open stays in sync.
func _refresh_crate_panel() -> void:
	if crate_panel == null or not crate_panel.visible:
		return
	if _crate == null or not is_instance_valid(_crate):
		toggle_panel("crate")   # the crate got freed under us — close its view
		return
	crate_title.text = _crate.display_name.to_upper()
	for c in _crate_list.get_children():
		c.queue_free()
	for c in _pack_list.get_children():
		c.queue_free()
	if _crate.items.is_empty():
		_crate_list.add_child(_crate_empty_line("· empty ·"))
	for it in _crate.items:
		var id: String = str(it)
		_crate_list.add_child(_crate_item_button(id, func() -> void: _crate_take(id)))
	var pack: Array = []
	for it in PlayerState.hotbar:
		if it != null:
			pack.append(it)
	pack.append_array(PlayerState.inventory)
	if pack.is_empty():
		_pack_list.add_child(_crate_empty_line("· nothing to stow ·"))
	for it in pack:
		var pid: String = str(it)
		_pack_list.add_child(_crate_item_button(pid, func() -> void: _crate_stow(pid)))

func _crate_take(item_id: String) -> void:
	if _crate == null or not is_instance_valid(_crate):
		_refresh_crate_panel()
		return
	var idx: int = _crate.items.find(item_id)
	if idx == -1:
		return
	if PlayerState.add_item(item_id):
		_crate.items.remove_at(idx)
	else:
		toast("Pack is full.")
	_refresh_crate_panel()

func _crate_stow(item_id: String) -> void:
	if _crate == null or not is_instance_valid(_crate):
		_refresh_crate_panel()
		return
	if PlayerState.remove_item(item_id):
		_crate.items.append(item_id)
	_refresh_crate_panel()

func _crate_take_all() -> void:
	if _crate == null or not is_instance_valid(_crate):
		_refresh_crate_panel()
		return
	while not _crate.items.is_empty():
		if not PlayerState.add_item(_crate.items[0]):
			toast("Pack is full.")
			break
		_crate.items.remove_at(0)
	_refresh_crate_panel()

# ============================ stat bar widget =================================

class StatBar extends Panel:
	## One always-visible survival bar: dark rounded trough, colored fill, tiny
	## uppercase label inside. Pulses via _process when below PULSE_BELOW.

	const BAR_W: float = 170.0
	const BAR_H: float = 13.0
	const PULSE_BELOW: float = 0.25

	var value: float = 1.0
	var _fill: Panel

	func _init(label_text: String, fill_color: Color) -> void:
		custom_minimum_size = Vector2(BAR_W, BAR_H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var trough := StyleBoxFlat.new()
		trough.bg_color = Color(0.04, 0.05, 0.06, 0.66)
		trough.set_corner_radius_all(4)
		trough.border_color = Color(0.55, 0.6, 0.62, 0.35)
		trough.set_border_width_all(1)
		add_theme_stylebox_override("panel", trough)
		_fill = Panel.new()
		_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = fill_color
		fill_style.set_corner_radius_all(3)
		_fill.add_theme_stylebox_override("panel", fill_style)
		add_child(_fill)
		var lbl := Label.new()
		lbl.text = label_text
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.offset_left = 6.0
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.96, 0.93, 0.92))
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		lbl.add_theme_constant_override("outline_size", 3)
		add_child(lbl)
		set_value(1.0)

	func set_value(v: float) -> void:
		value = clampf(v, 0.0, 1.0)
		_fill.position = Vector2(2.0, 2.0)
		_fill.size = Vector2((BAR_W - 4.0) * value, BAR_H - 4.0)
		_fill.visible = value > 0.015

	func _process(_delta: float) -> void:
		# Low-stat pulse — the bar itself asks for attention.
		if value < PULSE_BELOW:
			_fill.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
		else:
			_fill.modulate.a = 1.0
