class_name HUD extends CanvasLayer
## The slice's entire 2D UI: context prompt, toast line, 4-slot hotbar, low-stat icons,
## full-screen reading overlay, black fade layer, and the dawn end card. Built in code.

var prompt_label: Label
var toast_label: Label
var hotbar_slots: Array[PanelContainer] = []
var hunger_icon: Label
var warmth_icon: Label
var reading_panel: Panel
var reading_title: Label
var reading_body: RichTextLabel
var fade_rect: ColorRect
var end_card: CenterContainer

var _toast_tween: Tween
var reading_open: bool = false

func _ready() -> void:
	add_to_group("hud")
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	PlayerState.inventory_changed.connect(_refresh_hotbar)
	PlayerState.hunger_changed.connect(func(v: float) -> void: hunger_icon.visible = v < 0.5)
	PlayerState.warmth_changed.connect(func(v: float) -> void: warmth_icon.visible = v < 0.5)
	_refresh_hotbar()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Center-bottom context prompt.
	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position += Vector2(-200, -120)
	prompt_label.custom_minimum_size = Vector2(400, 30)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 18)
	prompt_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	root.add_child(prompt_label)

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

	# Crosshair dot.
	var dot := Label.new()
	dot.text = "·"
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.add_theme_font_size_override("font_size", 24)
	dot.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	root.add_child(dot)

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

	# Diegetic-ish stat icons: only visible below 50% (GDD 5.6).
	var stats := VBoxContainer.new()
	stats.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stats.position = Vector2(-120, -90)
	root.add_child(stats)
	hunger_icon = Label.new()
	hunger_icon.text = "◆ HUNGRY"
	hunger_icon.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	hunger_icon.visible = false
	stats.add_child(hunger_icon)
	warmth_icon = Label.new()
	warmth_icon.text = "◆ COLD"
	warmth_icon.add_theme_color_override("font_color", Color(0.5, 0.75, 0.95))
	warmth_icon.visible = false
	stats.add_child(warmth_icon)

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
	prompt_label.text = ("[E]  " + text) if text != "" else ""

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
