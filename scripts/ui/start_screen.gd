class_name StartScreen extends Control
## Branded start screen: dark sea gradient, abstract rig silhouette on the
## horizon with a pulsing beacon, glowing letterspaced SALTLINE title,
## drifting spore motes, and a minimal keyboard-navigable menu.
## Everything is built in code; the .tscn is just this script on a Control.

const MAIN_SCENE: String = "res://scenes/Main.tscn"
const SAVE_PATH: String = "user://saltline_autosave.json"

const HORIZON: float = 0.65
const SPORE_COUNT: int = 25

const COL_SKY_TOP: Color = Color(0.02, 0.04, 0.06)
const COL_SEA: Color = Color(0.03, 0.12, 0.13)
const COL_SEA_DEEP: Color = Color(0.015, 0.06, 0.07)
const COL_PEARL: Color = Color(0.88, 0.94, 0.92)
const COL_TEAL: Color = Color(0.2, 0.9, 0.85)
const COL_RIG: Color = Color(0.008, 0.02, 0.028)
const COL_BEACON: Color = Color(0.95, 0.2, 0.18)

var _spores: Array[ColorRect] = []
var _spore_speeds: Array[float] = []
var _glow_row: HBoxContainer

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_backdrop()
	_build_rig()
	_build_spores()
	_build_title()
	_build_menu()
	_build_footer()

func _process(delta: float) -> void:
	var view: Vector2 = get_viewport_rect().size
	var t: float = Time.get_ticks_msec() * 0.001
	for i in _spores.size():
		var s: ColorRect = _spores[i]
		s.position.y -= _spore_speeds[i] * delta
		s.position.x += sin(t * 0.6 + float(i) * 1.7) * 5.0 * delta
		if s.position.y < -6.0:
			s.position.y = view.y + randf_range(0.0, 40.0)
			s.position.x = randf() * view.x

## -- backdrop ---------------------------------------------------------------

func _build_backdrop() -> void:
	# Sky: near-black navy fading to deep teal at the horizon.
	var sky_bands: int = 12
	for i in sky_bands:
		var t: float = float(i) / float(sky_bands - 1)
		var col: Color = COL_SKY_TOP.lerp(COL_SEA, pow(t, 1.6))
		_band(float(i) / float(sky_bands) * HORIZON, float(i + 1) / float(sky_bands) * HORIZON, col)
	# Sea: deep teal darkening toward the bottom.
	var sea_bands: int = 5
	for i in sea_bands:
		var t: float = float(i) / float(sea_bands - 1)
		var col: Color = COL_SEA.lerp(COL_SEA_DEEP, t)
		var a0: float = HORIZON + float(i) / float(sea_bands) * (1.0 - HORIZON)
		var a1: float = HORIZON + float(i + 1) / float(sea_bands) * (1.0 - HORIZON)
		_band(a0, a1, col)
	# Horizon glow: a soft halo plus a thin pale line.
	var halo: ColorRect = _band(HORIZON, HORIZON, Color(0.45, 0.65, 0.62, 0.08))
	halo.offset_top = -5.0
	halo.offset_bottom = 5.0
	var line: ColorRect = _band(HORIZON, HORIZON, Color(0.55, 0.75, 0.72, 0.4))
	line.offset_top = -1.0
	line.offset_bottom = 1.0

func _band(a_top: float, a_bottom: float, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = a_top
	r.anchor_bottom = a_bottom
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

## -- rig silhouette ----------------------------------------------------------

func _build_rig() -> void:
	# Anchored point on the horizon; children are pixel offsets (negative y = up).
	var rig := Control.new()
	rig.anchor_left = 0.72
	rig.anchor_right = 0.72
	rig.anchor_top = HORIZON
	rig.anchor_bottom = HORIZON
	rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rig)
	# Legs (poke slightly below the horizon into the sea).
	_rig_rect(rig, Vector2(-60.0, -20.0), Vector2(7.0, 24.0))
	_rig_rect(rig, Vector2(-4.0, -20.0), Vector2(7.0, 24.0))
	_rig_rect(rig, Vector2(53.0, -20.0), Vector2(7.0, 24.0))
	# Deck slab.
	_rig_rect(rig, Vector2(-72.0, -28.0), Vector2(144.0, 9.0))
	# Blocky superstructure.
	_rig_rect(rig, Vector2(-52.0, -56.0), Vector2(40.0, 28.0))
	_rig_rect(rig, Vector2(-6.0, -46.0), Vector2(30.0, 18.0))
	_rig_rect(rig, Vector2(30.0, -40.0), Vector2(16.0, 12.0))
	# Crane boom off the deck edge.
	_rig_rect(rig, Vector2(24.0, -62.0), Vector2(3.0, 34.0))
	_rig_rect(rig, Vector2(24.0, -62.0), Vector2(38.0, 3.0))
	# Antenna mast atop the tall block, with a pulsing red beacon.
	_rig_rect(rig, Vector2(-30.0, -92.0), Vector2(3.0, 36.0))
	var beacon: ColorRect = _rig_rect(rig, Vector2(-31.0, -97.0), Vector2(5.0, 5.0), COL_BEACON)
	var tw: Tween = create_tween().set_loops()
	tw.tween_property(beacon, "modulate:a", 0.15, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(beacon, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _rig_rect(parent: Control, pos: Vector2, sz: Vector2, col: Color = COL_RIG) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.position = pos
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

## -- spores ------------------------------------------------------------------

func _build_spores() -> void:
	var view: Vector2 = get_viewport_rect().size
	for i in SPORE_COUNT:
		var s := ColorRect.new()
		var px: float = randf_range(1.5, 4.0)
		s.size = Vector2(px, px)
		s.color = Color(COL_TEAL.r, COL_TEAL.g, COL_TEAL.b, randf_range(0.12, 0.55))
		s.position = Vector2(randf() * view.x, randf() * view.y)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		_spores.append(s)
		_spore_speeds.append(randf_range(8.0, 32.0))

## -- title -------------------------------------------------------------------

func _build_title() -> void:
	# Teal glow echo behind the pearl title, slightly scaled up, alpha looping.
	_glow_row = _title_row(COL_TEAL)
	_glow_row.scale = Vector2(1.05, 1.05)
	_glow_row.resized.connect(func() -> void:
		_glow_row.pivot_offset = _glow_row.size * 0.5)
	_center_region(0.08, 0.38).add_child(_glow_row)
	_glow_row.modulate.a = 0.25
	var tw: Tween = create_tween().set_loops()
	tw.tween_property(_glow_row, "modulate:a", 0.5, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_glow_row, "modulate:a", 0.25, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_center_region(0.08, 0.38).add_child(_title_row(COL_PEARL))

	var subtitle := Label.new()
	subtitle.text = "FIRST NIGHT — an abandoned-rig survival mystery"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.72, 0.7, 0.7))
	subtitle.anchor_left = 0.0
	subtitle.anchor_right = 1.0
	subtitle.anchor_top = 0.38
	subtitle.anchor_bottom = 0.44
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)

func _title_row(col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch: String in "SALTLINE":
		var l := Label.new()
		l.text = ch
		l.add_theme_font_size_override("font_size", 110)
		l.add_theme_color_override("font_color", col)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	return row

func _center_region(a_top: float, a_bottom: float) -> CenterContainer:
	var c := CenterContainer.new()
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = a_top
	c.anchor_bottom = a_bottom
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c

## -- menu --------------------------------------------------------------------

func _build_menu() -> void:
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 12)
	_center_region(0.66, 0.94).add_child(menu)
	var begin: Button = _menu_button(menu, "BEGIN")
	begin.pressed.connect(_start_game)
	if FileAccess.file_exists(SAVE_PATH):
		var cont: Button = _menu_button(menu, "CONTINUE")
		cont.pressed.connect(_start_game)   # Main restores the autosave itself.
	var quit: Button = _menu_button(menu, "QUIT")
	quit.pressed.connect(func() -> void: get_tree().quit())
	begin.grab_focus()

func _start_game() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)

func _menu_button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260.0, 46.0)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.68, 0.8, 0.78))
	b.add_theme_color_override("font_hover_color", COL_PEARL)
	b.add_theme_color_override("font_focus_color", COL_PEARL)
	b.add_theme_color_override("font_pressed_color", COL_TEAL)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.03, 0.07, 0.08, 0.85)
	normal.border_color = Color(0.1, 0.24, 0.24)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(10)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.border_color = COL_TEAL
	hover.set_border_width_all(2)
	var pressed: StyleBoxFlat = hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.05, 0.14, 0.14, 0.9)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = COL_TEAL
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(2)
	focus.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	parent.add_child(b)
	return b

## -- footer ------------------------------------------------------------------

func _build_footer() -> void:
	var footer := Label.new()
	footer.text = "v0.1 slice — WASD move · E interact · I inventory"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.55, 0.65, 0.63, 0.55))
	footer.anchor_left = 0.0
	footer.anchor_right = 1.0
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_top = -32.0
	footer.offset_bottom = -12.0
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)
