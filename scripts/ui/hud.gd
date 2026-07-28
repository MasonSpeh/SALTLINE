class_name HUD extends CanvasLayer
## The slice's entire 2D UI: context prompt, toast line, 4-slot hotbar, survival
## stat bars (LIFE/HUNGER/THIRST/WARMTH), crate exchange panel, full-screen
## reading overlay, black fade layer, and the dawn end card. Built in code.

var prompt_label: Label
var prompt_chip: PanelContainer
var prompt_locked: bool = false   # scripted hint owns the chip; ray won't overwrite
const CHIP_FADE_OUT: float = 0.22 ## seconds the chip takes to let go (see _set_chip)
var _chip_tween: Tween
## Deep-drop rig bait chip — a DEDICATED primitive (owner spec 2026-07-27: "press [B],
## prompted by a text pop up"), not the shared prompt_chip. prompt_chip is InteractionRay's
## to write every frame off whatever the look-ray is aimed at; sharing it with a second,
## unrelated writer polling on its own schedule is exactly how two systems end up racing to
## stomp each other's text — the rig gets its own chip instead, sitting below the crosshair
## prompt so both can be up at once without either one flickering the other out.
var bait_chip: PanelContainer
var bait_label: Label
const FISHING_ROD := preload("res://scripts/components/fishing_rod.gd")
var toast_label: Label
## The bare item name that flashes up when the interaction ray's target CHANGES (owner
## request, 2026-07-27) — a brief "notice", distinct from the persistent "[E] TAKE ..."
## chip which is driven separately and must keep working exactly as it does today. Lives
## low, near the hotbar, so it never collides with the toast/comfort lines stacked above
## the chip at center screen.
var item_name_label: Label
var _item_name_tween: Tween
const ITEM_NAME_HOLD: float = 1.0   ## seconds the name sits fully visible before it fades
const ITEM_NAME_FADE: float = 0.5
## The hotbar-selection name (owner spec, 2026-07-27c: "fade out and disappear after 2
## seconds"). Hold + fade is that 2.0s in full, spent mostly at full alpha so the name is
## readable, with the tail doing the getting-out-of-the-way.
const SELECTED_NAME_HOLD: float = 1.4
const SELECTED_NAME_FADE: float = 0.6
var crosshair: Label
var objective_label: Label
var hotbar_slots: Array[PanelContainer] = []
var life_bar: StatBar
var hunger_bar: StatBar
var thirst_bar: StatBar
var warmth_bar: StatBar
var _cold_hint_shown: bool = false   ## one-time "how to warm up" teach (see warmth hook)
var rest_bar: StatBar
var oxygen_bar: StatBar               ## only visible while in the water (see _process)
var _player: Node = null              ## cached for the swimming read that gates oxygen_bar
var comfort_label: Label
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
var inv_title: Label              ## doubles as the "picked up, click away to drop" line
## RichTextLabel (was a plain Label) so the richer hover panel (owner request 2026-07-27:
## "add more info") can color a stat line (e.g. the amber ▸ hint, a red side-effect
## warning) without hand-rolling a second label stack.
var inv_info: RichTextLabel
var _inv_buttons: Array[Button] = []
## Renders each item's own 3D model into a slot picture, once, on demand. See item_icons.gd.
## Preloaded by path, not referenced by class_name: the global class cache lags for a
## newly added script and resolves it as an unknown type on the first run.
const ITEM_ICONS := preload("res://scripts/ui/item_icons.gd")
var _icons: Node
var _inv_hovered_idx: int = -1   ## last unified slot the cursor was over (for DROP)
## The pick-to-drop selection: a unified slot index plus the id that was sitting in it.
## Both, because pack indices SHIFT whenever a stack empties (inventory is a list) — the id
## is how we tell "still the thing I picked" from "something else slid into that slot", and
## it is the difference between dropping what the player chose and dropping their dinner.
var _inv_selected_idx: int = -1
var _inv_selected_id: String = ""
var bench_panel: BenchPanel
var crate_panel: Panel
var crate_title: Label
var _crate_list: VBoxContainer
var _pack_list: VBoxContainer
var _crate: LootContainer = null

var _toast_tween: Tween
var _comfort_tween: Tween
var reading_open: bool = false
var _thirst_bound: bool = false   # PlayerState.thirst_changed connected?
var _life_bound: bool = false     # PlayerState.life_changed connected?
var _rest_bound: bool = false     # PlayerState.rest_changed connected?

func _ready() -> void:
	add_to_group("hud")
	# Slot pictures. Each item is photographed once from its own 3D model and cached, so
	# the first refresh after a pickup shows the item's name and the next shows the item.
	_icons = ITEM_ICONS.new()
	add_child(_icons)
	_icons.icon_ready.connect(func(_id: String) -> void:
		_refresh_hotbar()
		_refresh_inventory_panel())
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_build_panels()
	PlayerState.inventory_changed.connect(_refresh_hotbar)
	# Which slot is in hand is written from the number keys, the inventory panel and scripted
	# setups alike — PlayerState announces it so the outline and the name popup never depend
	# on every writer remembering to call us. Bound defensively, like the stat signals below.
	if PlayerState.has_signal("hotbar_selection_changed"):
		PlayerState.connect("hotbar_selection_changed", _on_hotbar_selection_changed)
	PlayerState.inventory_changed.connect(_refresh_inventory_panel)
	PlayerState.inventory_changed.connect(_refresh_crate_panel)
	GameClock.phase_changed.connect(_on_phase_changed)
	PlayerState.hunger_changed.connect(func(v: float) -> void: hunger_bar.set_value(v))
	PlayerState.warmth_changed.connect(func(v: float) -> void:
		warmth_bar.set_value(v)
		# One-time contextual teach the first time the cold actually bites: the ways to
		# warm up exist (lit fire barrel, lean-to shelter, a night's sleep) but were only
		# named in the static tips list — a player who skipped that had no way to know.
		if v < 0.35 and not _cold_hint_shown:
			_cold_hint_shown = true
			toast("The cold is setting in. A lit fire barrel, a lean-to, or a night's sleep in a bunk will warm you."))
	# thirst/life are new PlayerState stats — bind defensively so the HUD works
	# the moment the signals exist and never crashes if one is briefly absent.
	if PlayerState.has_signal("thirst_changed"):
		PlayerState.connect("thirst_changed", func(v: float) -> void: thirst_bar.set_value(v))
		_thirst_bound = true
	if PlayerState.has_signal("life_changed"):
		PlayerState.connect("life_changed", func(v: float) -> void: life_bar.set_value(v))
		_life_bound = true
	if PlayerState.has_signal("rest_changed"):
		PlayerState.connect("rest_changed", func(v: float) -> void: rest_bar.set_value(v))
		_rest_bound = true
	if PlayerState.has_signal("oxygen_changed"):
		PlayerState.connect("oxygen_changed", func(v: float) -> void: oxygen_bar.set_value(v))
	Journal.entry_added.connect(func(_id: String, _t: String) -> void: _update_journal_badge())
	_refresh_hotbar()
	hunger_bar.set_value(PlayerState.hunger)
	warmth_bar.set_value(PlayerState.warmth)
	thirst_bar.set_value(_stat_value_or_full("thirst"))
	life_bar.set_value(_stat_value_or_full("life"))
	rest_bar.set_value(_stat_value_or_full("rest"))

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
	if not _rest_bound:
		rest_bar.set_value(_stat_value_or_full("rest"))
	# Oxygen bar rides along only while you're in the water — in the sea it's always up,
	# and it lingers a beat after you climb out so you watch the breath come back, then hides.
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var in_water: bool = is_instance_valid(_player) and bool(_player.get("swimming"))
	oxygen_bar.visible = in_water or PlayerState.oxygen < 0.999
	# Deep-drop bait chip: polled the same defensive way as the stat bars above, since
	# there's no changed-signal for "wielding the rig with an empty hook" either.
	var bait_text: String = FISHING_ROD.bait_prompt_text(_player) if is_instance_valid(_player) else ""
	bait_chip.visible = bait_text != ""
	if bait_text != "":
		bait_label.text = bait_text

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

	# Bait chip — same look as the context prompt, parked just under it so wielding the
	# deep rig while also aiming at some other interactable doesn't fight it for the line.
	bait_chip = PanelContainer.new()
	bait_chip.set_anchors_preset(Control.PRESET_CENTER)
	bait_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bait_chip.grow_vertical = Control.GROW_DIRECTION_BOTH
	bait_chip.position = Vector2(0, 78)
	bait_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bait_chip.add_theme_stylebox_override("panel", chip_style)
	bait_chip.visible = false
	root.add_child(bait_chip)
	bait_label = Label.new()
	bait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bait_label.add_theme_font_size_override("font_size", 15)
	bait_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.75))
	bait_chip.add_child(bait_label)

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

	# Item-name popup — bottom of screen, above the hotbar row. Bare name only (no verb,
	# no "[E]"); that's what the persistent prompt chip already says. This is just a quick
	# "you're looking at: X" notice that gets out of the way on its own.
	item_name_label = Label.new()
	item_name_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	item_name_label.position += Vector2(-200, -96)
	item_name_label.custom_minimum_size = Vector2(400, 24)
	item_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_name_label.add_theme_font_size_override("font_size", 15)
	item_name_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.84))
	item_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	item_name_label.add_theme_constant_override("outline_size", 3)
	item_name_label.modulate.a = 0.0
	root.add_child(item_name_label)

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

	# Hotbar: HOTBAR_SIZE slots (6 as of 2026-07-27), bottom-left.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.position = Vector2(16, -64)
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	for i in range(PlayerState.HOTBAR_SIZE):
		# SQUARE, and showing the item rather than naming it (owner call, 2026-07-26).
		# The picture is a TextureRect filling the slot; the label survives on top of it,
		# demoted to the two things a picture cannot carry — the 1-4 key that selects the
		# slot, and the stack count. An item with no rendered icon yet falls back to its
		# name in that same label, so the bar is never blank while icons are still baking.
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(58, 58)
		slot.add_theme_stylebox_override("panel", _hotbar_slot_style(false))
		var pic := TextureRect.new()
		pic.name = "Pic"
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(pic)
		var lbl := Label.new()
		lbl.name = "L"
		lbl.text = str(i + 1)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lbl)
		slot.modulate = Color(1, 1, 1, 0.65)
		bar.add_child(slot)
		hotbar_slots.append(slot)
	# The selection outline has to be live before the first frame, not only after the first
	# key press — the slice can start with something already in hand.
	_refresh_hotbar_selection()

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
	rest_bar = StatBar.new("REST", Color(0.55, 0.5, 0.75))
	stats.add_child(rest_bar)
	# Oxygen: your held breath underwater. Hidden on dry land, shown the moment you're
	# in the sea (see _process). Cold cyan so it reads as air/water, not a vital.
	oxygen_bar = StatBar.new("OXYGEN", Color(0.4, 0.78, 0.95))
	oxygen_bar.visible = false
	stats.add_child(oxygen_bar)

	# Comfort is never a bar and never a number — it's a line that shows up when
	# the place you're standing in changes character, then gets out of the way.
	comfort_label = Label.new()
	comfort_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# Its own slot, well clear of the toast line at -170. At -206 the two sat 36px
	# apart and a comfort note landing next to a "Journal — ..." discovery read as
	# one run-on paragraph rather than as two different kinds of thing.
	comfort_label.position += Vector2(-300, -248)
	comfort_label.custom_minimum_size = Vector2(600, 26)
	comfort_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	comfort_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	comfort_label.add_theme_font_size_override("font_size", 15)
	comfort_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.74))
	comfort_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	comfort_label.add_theme_constant_override("outline_size", 3)
	comfort_label.modulate.a = 0.0
	root.add_child(comfort_label)

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

## The one place the prompt chip's text and visibility change. Appearing is instant (you
## looked at a thing, the answer should already be there); going away is a short fade, so
## the ray losing its target reads as the chip letting go rather than blinking out.
func _set_chip(text: String) -> void:
	if _chip_tween:
		_chip_tween.kill()   # a new line always wins over a fade-out in progress
	if text != "":
		prompt_label.text = text
		prompt_chip.modulate.a = 1.0
		prompt_chip.visible = true
		return
	if not prompt_chip.visible:
		prompt_label.text = ""
		return
	# Fade the chip out with its text still in it: emptying the label first would leave an
	# empty bordered box dissolving on screen, which reads as a bug rather than as a
	# prompt letting go. Hidden (not merely transparent) at the end, because visible ==
	# false is what the rest of the HUD reads as "there is no prompt".
	_chip_tween = create_tween()
	_chip_tween.tween_property(prompt_chip, "modulate:a", 0.0, CHIP_FADE_OUT)
	_chip_tween.tween_callback(func() -> void:
		prompt_chip.visible = false
		prompt_label.text = "")

## Flash an item's bare name at the bottom of the screen, then let it fade — called by
## InteractionRay whenever its target CHANGES (owner request, 2026-07-27), not every frame
## it stays on the same thing. Appearing is instant, same reasoning as the prompt chip:
## the player already looked, the answer should already be there.
func show_item_name(text: String) -> void:
	_flash_item_name(text, ITEM_NAME_HOLD, ITEM_NAME_FADE)

## The held-item name, shown whenever the hotbar selection changes. Same label and the same
## bottom-centre slot as the look-at notice above (they can never be wanted at once — the
## latest thing the player did is the thing worth naming), on the owner's 2-second budget:
## full alpha immediately, hold, then fade out so it is gone at 2.0s exactly.
func show_selected_item_name(text: String) -> void:
	_flash_item_name(text, SELECTED_NAME_HOLD, SELECTED_NAME_FADE)

## Snap to full alpha, hold, fade. Killing the running tween first is what makes a re-select
## or a switch mid-fade RESTART the notice at full alpha instead of racing the fade already
## in flight — otherwise the second name would inherit whatever alpha the first was down to.
func _flash_item_name(text: String, hold: float, fade: float) -> void:
	if item_name_label == null or text == "":
		return
	if _item_name_tween:
		_item_name_tween.kill()
	item_name_label.text = text
	item_name_label.modulate.a = 1.0
	_item_name_tween = create_tween()
	_item_name_tween.tween_interval(hold)
	_item_name_tween.tween_property(item_name_label, "modulate:a", 0.0, fade)

## Take the name down NOW (selecting an empty slot). Nothing is left mid-fade.
func _hide_item_name() -> void:
	if item_name_label == null:
		return
	if _item_name_tween:
		_item_name_tween.kill()
	item_name_label.modulate.a = 0.0
	item_name_label.text = ""

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

## A toast is about RIGHT NOW. Forcing the clock (contact respawn, sleeping through
## to dawn, a debug phase jump) used to leave the last one burned into the corner:
## "Something's out there. Stay in the light until dawn." sat over full daylight in
## every capture of the last batch, because nothing ever cleared it.
func _on_phase_changed(_phase: GameClock.Phase) -> void:
	if _toast_tween:
		_toast_tween.kill()
	toast_label.modulate.a = 0.0
	toast_label.text = ""

## The comfort read-out. Deliberately not a toast: it fades in slowly, sits above the
## toast line so it never fights it, and lingers. ComfortFurniture rate-limits the
## call sites — this only ever fires on a genuine change of place.
func comfort_note(text: String) -> void:
	if comfort_label == null:
		return
	comfort_label.text = text
	if _comfort_tween:
		_comfort_tween.kill()
	comfort_label.modulate.a = 0.0
	_comfort_tween = create_tween()
	_comfort_tween.tween_property(comfort_label, "modulate:a", 0.85, 1.6)
	_comfort_tween.tween_interval(3.4)
	_comfort_tween.tween_property(comfort_label, "modulate:a", 0.0, 2.2)

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

## One hotbar socket's frame. Unselected is the same dark chip the prompt uses, so the bar
## reads as one family of HUD furniture; SELECTED is the crosshair's warm amber at 3px —
## the one high-contrast box on the screen (owner call, 2026-07-27c: the box belongs on the
## hotbar, never around a world object), so "what is in my hand" is answerable at a glance.
func _hotbar_slot_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.06, 0.72)
	s.set_corner_radius_all(4)
	if selected:
		s.border_color = Color(1.0, 0.92, 0.6, 0.95)
		s.set_border_width_all(3)
	else:
		s.border_color = Color(0.55, 0.6, 0.62, 0.5)
		s.set_border_width_all(1)
	return s

## Paint the outline on exactly one slot — the held one — and plain frames on the rest.
func _refresh_hotbar_selection() -> void:
	var sel: int = PlayerState.selected_hotbar
	for i in range(hotbar_slots.size()):
		hotbar_slots[i].add_theme_stylebox_override("panel", _hotbar_slot_style(i == sel))

## The player changed what's in hand: move the outline, and name the item under the
## crosshair for a couple of seconds (owner request, 2026-07-27c). An empty slot gets the
## outline but no name — there is nothing to announce, and a stale name over an empty hand
## would be worse than silence.
func _on_hotbar_selection_changed(slot: int) -> void:
	_refresh_hotbar_selection()
	if slot < 0 or slot >= PlayerState.HOTBAR_SIZE or PlayerState.hotbar[slot] == null:
		_hide_item_name()
		return
	show_selected_item_name(_item_name(String(PlayerState.hotbar[slot])))

func _refresh_hotbar() -> void:
	_refresh_hotbar_selection()
	for i in range(hotbar_slots.size()):
		var lbl: Label = hotbar_slots[i].get_node("L")
		var pic: TextureRect = hotbar_slots[i].get_node("Pic")
		var item: Variant = PlayerState.hotbar[i]
		if item == null:
			pic.texture = null
			lbl.text = str(i + 1)
			hotbar_slots[i].modulate.a = 0.5
			continue
		var id: String = str(item)
		pic.texture = _icons.get_icon(id)
		# The slot number always, the count when it stacks, and the NAME only while the
		# icon has not baked yet — so a fresh pickup is never an anonymous empty square.
		var txt: String = str(i + 1)
		if pic.texture == null:
			txt = "%d %s" % [i + 1, id.capitalize()]
		var n: int = PlayerState.hotbar_stack(i)
		if n > 1:
			txt += "  ×%d" % n
		lbl.text = txt
		hotbar_slots[i].modulate.a = 0.95

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

## Crew-locker steel for the inventory panel specifically (owner request 2026-07-27:
## "improve the UI to theme" — the generic dark rounded rectangle every panel shared
## didn't say "this rig" the way MatLib's dark_metal/rust_steel/hazard_stripe palette
## does everywhere else in the game). No StyleBoxTexture is available under
## gl_compatibility-friendly static theming, so the "riveted plate" read comes from a
## flat dark-steel bg plus a warm rust border rather than an actual texture — cheap,
## and it never redraws per frame.
func _locker_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.105, 0.115, 0.97)   ## MatLib.dark_metal's tone, flattened for UI
	s.border_color = Color(0.42, 0.27, 0.15, 0.95)  ## rust_steel — the locker's worn edge
	s.set_border_width_all(3)
	s.set_corner_radius_all(3)   ## near-square: a toolbox corner, not a rounded app card
	s.set_content_margin_all(18)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 8
	return s

## A small bolt-head circle for the panel's four corners. Purely decorative, built once
## at panel construction — not per-frame, keeping the "riveted steel" read affordable
## on gl_compatibility.
func _rivet() -> Panel:
	var r := Panel.new()
	r.custom_minimum_size = Vector2(7, 7)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.32, 0.33, 0.35)
	st.set_corner_radius_all(4)
	st.border_color = Color(0.05, 0.05, 0.06)
	st.set_border_width_all(1)
	r.add_theme_stylebox_override("panel", st)
	return r

func _add_rivets(panel: Panel, w: float, h: float) -> void:
	var inset := 9.0
	for corner in [Vector2(inset, inset), Vector2(w - inset - 7, inset),
			Vector2(inset, h - inset - 7), Vector2(w - inset - 7, h - inset - 7)]:
		var r := _rivet()
		r.position = corner
		panel.add_child(r)

## Panels sit above the world-layer text. The toast line lives at center-bottom -170
## and the centred panels span most of the screen height, so a Journal discovery
## firing while the bench was open drew straight across the pack grid.
const PANEL_Z: int = 20

func _make_panel(w: float, h: float) -> Panel:
	var p := Panel.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(w, h)
	p.position = Vector2(-w * 0.5, -h * 0.5)
	p.add_theme_stylebox_override("panel", _panel_style())
	p.visible = false
	p.z_index = PANEL_Z
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
[b]Hotbar[/b]         1–6 brings that item to hand · same number again eats or drinks it
[b]Inventory[/b]      I — click an item to pick it up, then click the slot you want it in
                (swaps with whatever is there, so a full pack is never a dead end)
                click it again to put it back · click empty space to drop it
[b]Crates[/b]         E opens an exchange panel — take what you need, stow what you don't
[b]Journal[/b]        J — discoveries, item notes, craft hints
[b]Hook[/b]           F — throw the rigging hook (craft it at the bench)
[b]Craft[/b]          E at the rigging bench — lay parts on it, hold WORK / Space
[b]Build[/b]          B — ghost preview · LMB place · R rotate · Tab next kit · B done
[b]Pause[/b]          Esc — volume, mouse, invert-Y

[b]Body[/b]
· Watch [b]LIFE[/b] — starving or dehydration drains it; food and water bring it back.
· Glow worms must be [b]seared at a bench[/b] before eating — raw ones make you sick.
· [b]REST[/b] only comes back in a bed. Sit down and it stops falling so fast.

[b]Tips[/b]
· The fire barrel on the wet deck is warmth that needs no power.
· The gyre south of the rig collects what the sea carries. Hook it.
· Bloom lamps you build make real safe light — the crab honors them.
· A lean-to is a pocket of warmth anywhere. Walkways bridge anything.
· Three of your own structures around a bed or a fire make a [b]camp[/b]. Camps keep you.
· Sit in a chair and watch the sea. It costs you almost nothing, and it isn't nothing.
· When the gulls leave, you have one dusk of grace. Use it.
· The crabs live under the waterline by day. After dark, watch the deck rim east."""
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
	# 480 was already short for 5 grid rows + title + info + drop button before this pass
	# (they only fit by silently overflowing the panel's bottom edge — Panel doesn't clip
	# by default, so the drop button and hover info were rendering past the border onto
	# the world behind it). The richer hover info box (owner request 2026-07-27) made the
	# overflow worse and visible, which is what surfaced it: 620 is sized to actually fit
	# 5 rows of 74px slots + header + hazard rule + a 2-3 line info box + the drop button.
	inventory_panel = _make_panel(560, 620)
	# Crew-locker re-theme (owner request 2026-07-27): the panel gets its own steel
	# stylebox and corner rivets instead of the generic dark rounded rectangle every
	# other panel uses — see _locker_panel_style / _add_rivets.
	inventory_panel.add_theme_stylebox_override("panel", _locker_panel_style())
	_add_rivets(inventory_panel, 560, 620)
	# Clicks that land on the panel but NOT on a slot button are the "drop what I picked"
	# gesture (see _inv_panel_input). For those to reach the panel at all, the layout
	# containers and labels covering it must not swallow them — a Control only takes the
	# mouse for itself, so IGNORE here leaves every child button's own clicks untouched.
	inventory_panel.gui_input.connect(_inv_panel_input)
	var ivbox := VBoxContainer.new()
	ivbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	ivbox.offset_left = 18
	ivbox.offset_top = 12
	ivbox.offset_right = -18
	ivbox.offset_bottom = -12
	ivbox.add_theme_constant_override("separation", 8)
	ivbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_panel.add_child(ivbox)
	inv_title = Label.new()
	inv_title.text = INV_TITLE
	inv_title.add_theme_font_size_override("font_size", 17)
	# Warm amber warning-label tint (MatLib.hazard_stripe's palette) instead of the
	# default white — the header reads as a stencilled locker label, not a UI caption.
	inv_title.add_theme_color_override("font_color", Color(0.86, 0.74, 0.42))
	inv_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ivbox.add_child(inv_title)
	# Hazard stripe accent under the header — the one splash of the deck's
	# watch-your-step chevron color the panel gets (owner call: "a hazard-stripe
	# accent" per the theme brief). A single flat rule, not a shader, so it costs
	# nothing per frame.
	var hazard_rule := ColorRect.new()
	hazard_rule.custom_minimum_size = Vector2(0, 3)
	hazard_rule.color = Color(0.62, 0.5, 0.14)
	hazard_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ivbox.add_child(hazard_rule)
	inv_grid = GridContainer.new()
	# 6 across instead of 4: the slots are square now (owner call, 2026-07-26) and a
	# 4-wide grid of squares makes a tall narrow column that overruns the panel once the
	# tool belt adds its four.
	inv_grid.columns = 6
	inv_grid.add_theme_constant_override("h_separation", 8)
	inv_grid.add_theme_constant_override("v_separation", 8)
	ivbox.add_child(inv_grid)
	# Build for the LARGEST the pack can ever get (with a tool belt on), and hide the
	# slots past current capacity in _refresh — MAX_BACKPACK is derived now, so the
	# grid can't be sized to a fixed number once and go stale when the belt is found.
	var max_slots: int = PlayerState.HOTBAR_SIZE + PlayerState.MAX_BACKPACK + PlayerState.TOOL_BELT_SLOTS
	for i in range(max_slots):
		# SQUARE slots showing the item itself (owner call, 2026-07-26). The Button keeps
		# every existing interaction — pick/place, right-click drop, hover info — and gains
		# a TextureRect child for the picture. The picture is a CHILD rather than the
		# Button's own `icon` because Button.icon is laid out against the button text and
		# gets shoved aside by the stack-count and pick-marker glyphs; a child fills the
		# whole square and the glyphs overlay it.
		var b := Button.new()
		b.custom_minimum_size = Vector2(74, 74)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_contents = true
		# Steel-slot styling (owner theme pass, 2026-07-27) — a riveted socket rather than
		# a stock Godot button, and the hover/pressed states pick up the same warm amber
		# the hazard rule uses, so "this slot is interactive" reads as rig hardware, not UI
		# chrome. Static styleboxes only — no per-frame cost.
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
		# ALWAYS-VISIBLE name + count strip (owner request 2026-07-27: "should be able to
		# see how many of each item/name even without hovering"). A thin semi-transparent
		# backing along the slot's bottom edge so the label reads over any icon color, with
		# the icon staying the dominant visual above it. Built once here; text set per
		# refresh in _refresh_inventory_panel via _slot_name_tag_text().
		var tag_bg := Panel.new()
		tag_bg.name = "TagBG"
		tag_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		tag_bg.custom_minimum_size = Vector2(0, 16)
		tag_bg.offset_top = -16
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
		var idx: int = i
		b.pressed.connect(func() -> void: _inv_slot_clicked(idx))
		b.mouse_entered.connect(func() -> void: _inv_slot_hovered(idx))
		b.gui_input.connect(func(e: InputEvent) -> void: _inv_slot_gui_input(idx, e))
		inv_grid.add_child(b)
		_inv_buttons.append(b)
	inv_info = RichTextLabel.new()
	inv_info.bbcode_enabled = true
	inv_info.fit_content = false
	inv_info.scroll_active = false
	inv_info.custom_minimum_size = Vector2(0, 92)
	inv_info.add_theme_font_size_override("normal_font_size", 13)
	inv_info.add_theme_color_override("default_color", Color(0.72, 0.76, 0.72))
	inv_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ivbox.add_child(inv_info)
	# Drop control: acts on the picked slot if there is one, otherwise on the last slot the
	# cursor was over — so it works for pack and hotbar slots alike, and agrees with the
	# click-away drop about WHICH item is on the block. The G key does the same for the
	# selected hotbar slot in play.
	var drop_btn := Button.new()
	drop_btn.text = "⤓  DROP ONE"
	drop_btn.custom_minimum_size = Vector2(0, 32)
	drop_btn.focus_mode = Control.FOCUS_NONE
	drop_btn.pressed.connect(func() -> void:
		_drop_slot(_inv_selected_idx if _inv_selection_valid() else _inv_hovered_idx))
	ivbox.add_child(drop_btn)

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
	var stow_all := Button.new()
	stow_all.text = "STOW ALL"
	stow_all.custom_minimum_size = Vector2(96, 30)
	stow_all.focus_mode = Control.FOCUS_NONE
	stow_all.pressed.connect(_crate_stow_all)
	crow.add_child(stow_all)
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
	bench_panel.z_index = PANEL_Z
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
	# A pick-to-drop selection is per-visit: never carry one across a close, or the next
	# click on empty space would let go of something the player picked minutes ago.
	_inv_clear_selection()
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
			KEY_G:
				# Drop one of the selected hotbar item — but only in open play, and
				# never while carrying a prop (the player controller's G sets THAT
				# down). With a panel open the on-screen DROP control owns it.
				if not any_panel_open():
					var pl: Node = get_tree().get_first_node_in_group("player")
					if pl and pl.get("carried") == null:
						var sel: int = PlayerState.selected_hotbar
						if sel >= 0 and sel < PlayerState.HOTBAR_SIZE and PlayerState.hotbar[sel] != null:
							_drop_slot(sel)
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
	for i in range(PlayerState.backpack_capacity()):
		slots.append(PlayerState.inventory[i] if i < PlayerState.inventory.size() else null)
	return slots

## Header when nothing is picked. With a pick live, the header becomes the drop instruction —
## it is the one line in the panel that is always on screen and never grows the layout.
const INV_TITLE: String = "PACK        (click: into your hand · right-click: drop one)"

func _refresh_inventory_panel() -> void:
	if inventory_panel == null or not inventory_panel.visible:
		return
	# A pick only survives while the item it named is still in the slot it named. Eating,
	# a crate exchange or a craft can all move things under an open panel.
	if not _inv_selection_valid():
		_inv_clear_selection()
	inv_title.text = INV_TITLE if _inv_selected_id == "" else \
		"PACK        ▸ %s  —  click the empty space to drop it" % _item_name(_inv_selected_id)
	var slots: Array = _inv_all_slots()
	var shown: int = PlayerState.HOTBAR_SIZE + PlayerState.backpack_capacity()
	for i in range(_inv_buttons.size()):
		# Slots past current capacity (no tool belt) are hidden, not stale.
		if i >= shown:
			_inv_buttons[i].visible = false
			continue
		_inv_buttons[i].visible = true
		var item: Variant = slots[i] if i < slots.size() else null
		var pic: TextureRect = _inv_buttons[i].get_node("Pic")
		var tag_bg: Panel = _inv_buttons[i].get_node("TagBG")
		var tag_lbl: Label = tag_bg.get_node("Tag")
		# THE PICTURE IS THE SLOT. b.text is now only what a picture cannot say: the 1-4 key
		# for a hotbar slot and the pick marker. The name + stack count moved into the
		# always-visible bottom tag strip (owner request 2026-07-27) — see TagBG above —
		# so they no longer depend on the icon still being baked to show at all.
		var glyphs: PackedStringArray = []
		if i < PlayerState.HOTBAR_SIZE:
			glyphs.append(str(i + 1))
		if item == null:
			pic.texture = null
			tag_bg.visible = false
			_inv_buttons[i].text = " ".join(glyphs)
			_inv_buttons[i].modulate = Color(1, 1, 1, 0.45)
			continue
		var id: String = str(item)
		pic.texture = _icons.get_icon(id)
		var cnt: int = PlayerState.hotbar_stack(i) if i < PlayerState.HOTBAR_SIZE \
			else PlayerState.inventory_stack(i - PlayerState.HOTBAR_SIZE)
		tag_bg.visible = true
		tag_lbl.text = _slot_tag_text(id, cnt)
		_inv_buttons[i].modulate = Color(1, 0.95, 0.75) if i < PlayerState.HOTBAR_SIZE \
			else Color(1, 1, 1)
		# The picked slot reads as picked — the drop instruction in the header has to be
		# aimed at something the player can see they chose.
		if i == _inv_selected_idx:
			glyphs.insert(0, "▸")
			_inv_buttons[i].modulate = Color(0.68, 1.0, 0.78)
		_inv_buttons[i].text = " ".join(glyphs)

## The always-visible name+count strip's text. A 74px slot at 9pt fits roughly 11-12
## narrow characters before Label.clip_text starts eating the tail, so long item names
## (e.g. "Fathom Halibut Fillet") get shortened to their first word or two rather than
## trusting clip to pick a sane cutoff — "Fathom..." reads as a name, "Fathom Halibut F"
## reads as a bug. Short names pass through untouched.
const _TAG_MAX_CHARS: int = 12
func _slot_tag_text(item_id: String, count: int) -> String:
	var full: String = _item_name(item_id)
	var suffix: String = " ×%d" % count if count > 1 else ""
	var budget: int = _TAG_MAX_CHARS - suffix.length()
	var shown: String = full
	if full.length() > budget:
		# Prefer to break on a word boundary so an abbreviation still reads as a word
		# ("Fathom…" not "Fatho…").
		var cut: int = full.rfind(" ", budget)
		shown = full.substr(0, cut if cut > 3 else budget) + "…"
	return shown + suffix

## The id in a unified slot index (hotbar 0..HOTBAR_SIZE-1, then the pack); "" when the slot
## is empty or out of range. The one place unified indices are decoded for reading.
func _inv_slot_item(unified_idx: int) -> String:
	if unified_idx < 0:
		return ""
	if unified_idx < PlayerState.HOTBAR_SIZE:
		var h: Variant = PlayerState.hotbar[unified_idx]
		return String(h) if h != null else ""
	var i: int = unified_idx - PlayerState.HOTBAR_SIZE
	# The pack is a sparse grid — an index inside it can hold null, meaning "the player left
	# this square empty". String(null) would hand back "<null>" and make an empty slot look
	# picked, so nulls have to be answered as "" here like any other empty slot.
	if i >= PlayerState.inventory.size() or PlayerState.inventory[i] == null:
		return ""
	return String(PlayerState.inventory[i])

func _item_name(item_id: String) -> String:
	return PlayerState.items.get(item_id, {}).get("name", item_id.capitalize())

## Pick a slot for the click-away drop, remembering WHAT was in it (see _inv_selected_id).
func _inv_select(idx: int) -> void:
	_inv_selected_idx = idx
	_inv_selected_id = _inv_slot_item(idx)
	if _inv_selected_id == "":
		_inv_selected_idx = -1

func _inv_clear_selection() -> void:
	_inv_selected_idx = -1
	_inv_selected_id = ""

## True while the picked slot still holds the item that was picked.
func _inv_selection_valid() -> bool:
	return _inv_selected_id != "" and _inv_slot_item(_inv_selected_idx) == _inv_selected_id

## Left-click a slot: PICK IT UP, then click where you want it. That is the whole model.
##
## Owner call, 2026-07-25b — the old behaviour was reported as glitchy, and it was, because
## one click meant two different things depending on which half of the panel it landed in.
## A hotbar click STOWED the item instantly, at the end of the pack, with no say in where
## it went. A pack click swapped it into `PlayerState.selected_hotbar` — whichever slot was
## last equipped, state the player could not see and had not chosen — so the same click
## sent the item somewhere different depending on invisible history. Neither hotbar->hotbar
## nor pack->pack reordering was possible at all, and because the selection marker followed
## the item to wherever it had been flung, the highlight jumped to a slot the player never
## clicked. That is the "glitch".
##
## Now: first click picks (nothing moves), second click places. Same slot twice cancels.
## Empty slot with nothing picked clears. Every pair of slots is a legal move, so there is
## no dead end and no case where a click silently does nothing.
func _inv_slot_clicked(idx: int) -> void:
	# ---- nothing picked yet: this click picks, and moves nothing.
	if not _inv_selection_valid():
		if _inv_slot_item(idx) == "":
			_inv_clear_selection()
		else:
			_inv_select(idx)
		_refresh_inventory_panel()
		return
	# ---- clicking the picked slot again puts it back down.
	if idx == _inv_selected_idx:
		_inv_clear_selection()
		_refresh_inventory_panel()
		return
	# ---- place it. The selection follows the item so a mis-drop is one click to undo,
	# and so the click-away drop below still has something aimed at it.
	if PlayerState.move_slot(_inv_selected_idx, idx):
		# Bringing something to a hotbar slot equips that slot, so the held-item visual
		# matches what the panel just showed going into your hand.
		if idx < PlayerState.HOTBAR_SIZE:
			PlayerState.selected_hotbar = idx
		_inv_select(idx)
	else:
		_inv_clear_selection()
	_refresh_inventory_panel()

## A click inside the panel but away from the slot grid drops the picked item — "put it
## down over there". The grid's own rect is excluded so the gaps between slots (and the
## hidden past-capacity row) can never read as "away": inside the grid, a click is a slot
## click or nothing at all.
func _inv_panel_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _inv_selection_valid():
		return
	if inv_grid.get_global_rect().has_point(mb.global_position):
		return
	# Drops ONE, matching right-click and the G key, so clicking away again empties a stack
	# a can at a time. _drop_slot refreshes the panel, which retires a spent selection.
	_drop_slot(_inv_selected_idx)

func _inv_slot_hovered(idx: int) -> void:
	_inv_hovered_idx = idx
	var slots: Array = _inv_all_slots()
	var item: Variant = slots[idx] if idx < slots.size() else null
	if item == null:
		inv_info.text = ""
		return
	inv_info.text = _item_info_bbcode(str(item))

## Owner request 2026-07-27 ("add more info"): richer than a one-line summary — the
## use category up top, then every stat items.json actually encodes for this item
## (hunger/thirst restore, heal/cures, warmth, melee, worn-gear effects, vessel/bait
## behaviour), then the Journal's own body/hint. Everything here is read straight off
## data/items.json and Journal.item_info — no new fields invented, per the brief.
## bbcode because inv_info is a RichTextLabel now (see its declaration), so a category
## tag and a warning can each get their own color without a second label.
func _item_info_bbcode(id: String) -> String:
	var def: Dictionary = PlayerState.items.get(id, {})
	var jinfo: Dictionary = Journal.item_info(id)
	var use: String = def.get("use", "tool")
	var cat_color := {"eat": "#c9a84a", "drink": "#6fb8c9", "tool": "#9aa0a6", "build": "#8fb0a8"}
	var cat_word := {"eat": "FOOD", "drink": "DRINK", "tool": "TOOL", "build": "BUILD KIT"}
	var out: String = "[b]%s[/b]  [color=%s]%s[/color]\n" % [
		def.get("name", id.capitalize()), cat_color.get(use, "#9aa0a6"), cat_word.get(use, use.to_upper())]
	for stat in _item_stat_lines(def):
		out += stat + "\n"
	if jinfo.is_empty():
		# No journal.json entry authored for this item at all — distinct from "not yet
		# discovered" (add_item auto-discovers on pickup, and you can only hover an item
		# you're holding), so this reads as "the survivor hasn't puzzled this one out",
		# not as a content bug.
		out += "[color=#5c605e]Not yet catalogued in the journal.[/color]"
		return out
	if jinfo.get("body", "") != "":
		out += "%s\n" % jinfo["body"]
	if jinfo.get("hint", "") != "":
		out += "[color=#c9b458]▸ %s[/color]" % jinfo["hint"]
	return out

## One bbcode line per stat items.json actually carries for this item. Order follows
## the _schema comment at the top of items.json: consumption, healing, worn effects,
## melee, then vessel/loop behaviour.
func _item_stat_lines(def: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var hunger: float = def.get("hunger", 0.0)
	var thirst: float = def.get("thirst", 0.0)
	if def.get("use", "") == "eat" and hunger > 0.0:
		lines.append("Hunger  +%d%%" % int(hunger * 100.0))
	if thirst > 0.0:
		lines.append("Thirst  +%d%%" % int(thirst * 100.0))
	if def.get("warmth", 0.0) > 0.0:
		lines.append("Warmth  +%d%%" % int(float(def["warmth"]) * 100.0))
	if def.get("heal", 0.0) > 0.0:
		lines.append("Heals  +%d%% life" % int(float(def["heal"]) * 100.0))
	if def.get("cures", "") != "":
		lines.append("Cures %s" % String(def["cures"]))
	if def.get("side_effect", "") != "":
		lines.append("[color=#c96a4a]Raw — risk of %s[/color]" % String(def["side_effect"]))
	if def.has("melee_damage"):
		lines.append("Melee  %.1f dmg · %.1fm reach · %.2fs swing" % [
			float(def.get("melee_damage", 0.0)), float(def.get("melee_reach", 0.0)),
			float(def.get("swing_sec", 0.0))])
	if def.get("worn", false):
		var bits: Array[String] = []
		if def.get("light", false):
			bits.append("carried light")
		if def.get("pack_slots", 0) > 0:
			bits.append("+%d pack slots" % int(def["pack_slots"]))
		if def.get("cold_relief", 0.0) > 0.0:
			bits.append("%d%% slower cold loss" % int(float(def["cold_relief"]) * 100.0))
		lines.append("Worn — %s" % ", ".join(bits) if not bits.is_empty() else "Worn")
	if def.get("vessel", false):
		if def.has("fills_to"):
			lines.append("Vessel — fills from rain (~%.1fh)" % float(def.get("fill_hours", 0.0)))
		elif def.get("returns", "") != "":
			lines.append("Vessel — empties back to %s" % _item_name(String(def["returns"])))
	return lines

## Right-click a slot to drop one from it (left-click still moves it).
func _inv_slot_gui_input(idx: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_drop_slot(idx)

## Drop one item from a unified slot into the world at the player's feet.
func _drop_slot(unified_idx: int) -> void:
	if unified_idx < 0:
		return
	var id: String = PlayerState.take_one_from_slot(unified_idx)
	if id == "":
		return
	_spawn_drop(id)
	_refresh_inventory_panel()
	toast("Dropped %s" % _item_name(id))

## Make the item real again on the deck in front of the player, with a small toss.
func _spawn_drop(item_id: String) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side: Vector3 = player.global_transform.basis.x
	# A little forward of the feet, jittered sideways so a burst of drops fans out.
	var toss: Vector3 = fwd * 0.7 + side * randf_range(-0.18, 0.18)
	SaveManager.drop_into_world(item_id, player.global_position, toss)

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

func _crate_item_button(item_id: String, on_press: Callable, count: int = 1) -> Button:
	var b := Button.new()
	var nm: String = PlayerState.items.get(item_id, {}).get("name", item_id.capitalize())
	b.text = nm + ("  ×%d" % count if count > 1 else "")
	b.custom_minimum_size = Vector2(0, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b

## [ [id, count], ... ] in first-seen order — collapses duplicate ids into one row.
func _group_counts(list: Array) -> Array:
	var order: Array = []
	var counts: Dictionary = {}
	for it in list:
		var id: String = str(it)
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + 1
	var out: Array = []
	for id in order:
		out.append([id, int(counts[id])])
	return out

## The pack as [ [id, total], ... ], summing across split stacks.
func _pack_groups() -> Array:
	var order: Array = []
	var seen: Dictionary = {}
	for it in PlayerState.hotbar:
		if it != null and not seen.has(it):
			seen[it] = true
			order.append(str(it))
	for it in PlayerState.inventory:
		if it == null:
			continue   # an empty square in the sparse pack grid, not an item
		if not seen.has(it):
			seen[it] = true
			order.append(str(it))
	var out: Array = []
	for id in order:
		out.append([id, PlayerState.count_item(id)])
	return out

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
	var crate_groups: Array = _group_counts(_crate.items)
	if crate_groups.is_empty():
		_crate_list.add_child(_crate_empty_line("· empty ·"))
	for g in crate_groups:
		var id: String = g[0]
		_crate_list.add_child(_crate_item_button(id, func() -> void: _crate_take(id), g[1]))
	var pack_groups: Array = _pack_groups()
	if pack_groups.is_empty():
		_pack_list.add_child(_crate_empty_line("· nothing to stow ·"))
	for g in pack_groups:
		var pid: String = g[0]
		_pack_list.add_child(_crate_item_button(pid, func() -> void: _crate_stow(pid), g[1]))

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

## Empty the pack into the crate — the mirror of TAKE ALL. Snapshot the totals first
## so decrementing stacks as we go can't race the loop.
func _crate_stow_all() -> void:
	if _crate == null or not is_instance_valid(_crate):
		_refresh_crate_panel()
		return
	for g in _pack_groups():
		for _k in range(int(g[1])):
			if PlayerState.remove_item(g[0]):
				_crate.items.append(g[0])
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
