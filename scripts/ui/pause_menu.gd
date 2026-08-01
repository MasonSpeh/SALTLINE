class_name PauseMenu extends CanvasLayer
## Esc pause with settings (volume, mouse sensitivity, invert-Y), SAVE GAME, resume, quit.
## The only menu in the slice besides the end card.

var panel: CenterContainer
var _sens_slider: HSlider
var _vol_slider: HSlider
var _invert_check: CheckBox
var _wildlife_check: CheckBox
var _atmos_check: CheckBox
## Result line under SAVE GAME. Reset each time the menu opens so the player is never
## reading a "Game saved" from ten minutes ago as if it were about now.
var _save_note: Label

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = CenterContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# This full-rect overlay (layer 15) must NOT swallow clicks meant for the HUD's
	# top-right "?" help button beneath it (HUD is layer 10). Its children — the bg
	# box, sliders, Resume/Quit — keep their own STOP filter, so they still click.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	add_child(panel)
	var bg := PanelContainer.new()
	bg.custom_minimum_size = Vector2(380, 320)
	panel.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	bg.add_child(v)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)

	v.add_child(_label("Volume"))
	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 1.0
	_vol_slider.step = 0.05
	_vol_slider.value = 1.0
	_vol_slider.value_changed.connect(func(val: float) -> void:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(val, 0.001))))
	v.add_child(_vol_slider)

	v.add_child(_label("Mouse sensitivity"))
	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.3
	_sens_slider.max_value = 2.5
	_sens_slider.step = 0.1
	_sens_slider.value = 1.0
	_sens_slider.value_changed.connect(func(val: float) -> void:
		var p: Node = get_tree().get_first_node_in_group("player")
		if p:
			p.mouse_sensitivity_scale = val)
	v.add_child(_sens_slider)

	_invert_check = CheckBox.new()
	_invert_check.text = "Invert Y"
	_invert_check.toggled.connect(func(on: bool) -> void:
		var p: Node = get_tree().get_first_node_in_group("player")
		if p:
			p.invert_y = on)
	v.add_child(_invert_check)

	# Audio options. The rig ran too many competing sources at once; these mute whole
	# categories so the mix can fall back to the honest weather — sea, wind, rain, gulls.
	# (There is no music track in SALTLINE, so the second switch governs the atmosphere
	# layer: the tonal beds and randomized structural events that read as scoring.)
	_wildlife_check = CheckBox.new()
	_wildlife_check.text = "Wildlife & machinery sounds"
	_wildlife_check.button_pressed = true
	_wildlife_check.toggled.connect(func(on: bool) -> void:
		AudioDirector.set_wildlife_machinery(on))
	v.add_child(_wildlife_check)

	_atmos_check = CheckBox.new()
	_atmos_check.text = "Ambient atmosphere"
	_atmos_check.button_pressed = true
	_atmos_check.toggled.connect(func(on: bool) -> void:
		AudioDirector.set_atmosphere(on))
	v.add_child(_atmos_check)

	# SAVE GAME. Until now the only way a run reached disk was SaveManager's dawn/dusk
	# autosave, which is silent and up to half an hour apart — so a player who built a
	# camp mid-morning and quit had no way to ask the game to write it, and no way to
	# know it hadn't. This is that way, and _save_note says out loud whether it worked.
	var save_btn := Button.new()
	save_btn.text = "Save Game"
	save_btn.pressed.connect(_save_now)
	v.add_child(save_btn)
	_save_note = Label.new()
	_save_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_note.add_theme_font_size_override("font_size", 13)
	v.add_child(_save_note)
	_reset_note()

	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(toggle)
	v.add_child(resume)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	v.add_child(quit)

## Write the active slot right now and report the outcome in place. save_game() returns
## false for a write it could not complete, so a failure is shown as a failure rather
## than being swallowed into a cheerful "saved" the player would trust and lose a run to.
func _save_now() -> void:
	if _save_note == null:
		return
	if SaveManager.save_game():
		_save_note.text = "Game saved — slot %d" % SaveManager.active_slot
		_save_note.add_theme_color_override("font_color", Color(0.6, 0.88, 0.7))
	else:
		_save_note.text = "SAVE FAILED — could not write the save file"
		_save_note.add_theme_color_override("font_color", Color(0.95, 0.52, 0.45))

## The line's resting state. It carries the standing fact rather than sitting blank,
## because a Label with no text still holds its row open — an empty one just reads as a
## gap between Save Game and Resume — and because "which slot am I writing, and does this
## happen on its own too?" is exactly what a player wants answered before they press it.
func _reset_note() -> void:
	if _save_note == null:
		return
	_save_note.text = "Writes slot %d · also autosaves at dawn and dusk" % SaveManager.active_slot
	_save_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	return l

## Auto-pause when the window loses focus (alt-tab, click away). Without this the sim
## keeps running while the player is "away" — hunger/thirst/warmth drain, which lowers
## the stamina ceiling, so they come back walking slower for no visible reason. Pausing
## on focus-out freezes the whole survival clock; they return to a PAUSED menu and resume
## at exactly the speed they left.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if is_instance_valid(panel) and not panel.visible:
			toggle()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.reading_open:
			return   # reading overlay consumes Esc first
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	var opening: bool = not panel.visible
	# A stale "Game saved" from the last time the menu was open would read as a claim
	# about THIS moment. Back to the resting line on the way in.
	if opening:
		_reset_note()
	panel.visible = opening
	get_tree().paused = opening
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED
