class_name StartScreen extends Control
## Branded start screen: a painted North-Sea night — smooth gradient sky with a low
## Bloom-teal aurora, a hazed moon, a stark rig silhouette with lit windows and a
## pulsing beacon, its reflection breaking on the swell, a drifting spore field and
## a starfield overhead, a glowing letterspaced SALTLINE wordmark, and a minimal
## keyboard-navigable menu. Everything is built in code; the .tscn is just this
## script on a Control. No external art — all procedural, so it ships with zero deps.

const MAIN_SCENE: String = "res://scenes/Main.tscn"
const SAVE_PATH: String = "user://saltline_autosave.json"

const HORIZON: float = 0.66
const SPORE_COUNT: int = 34
const STAR_COUNT: int = 90

const COL_SKY_TOP: Color = Color(0.015, 0.03, 0.05)
const COL_SKY_MID: Color = Color(0.03, 0.06, 0.09)
const COL_SEA: Color = Color(0.03, 0.12, 0.13)
const COL_SEA_DEEP: Color = Color(0.008, 0.035, 0.045)
const COL_PEARL: Color = Color(0.88, 0.94, 0.92)
const COL_TEAL: Color = Color(0.2, 0.9, 0.85)
const COL_RIG: Color = Color(0.006, 0.016, 0.024)
const COL_BEACON: Color = Color(0.95, 0.2, 0.18)
const COL_WINDOW: Color = Color(0.95, 0.78, 0.42)   ## warm sodium light in the rig windows

var _spores: Array[ColorRect] = []
var _spore_speeds: Array[float] = []
var _stars: Array[ColorRect] = []
var _star_phase: Array[float] = []
var _reflection: Control          ## the whole rig mirror, wobbled on the swell
var _glow_row: HBoxContainer

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_backdrop()
	_build_moon()
	_build_stars()
	_build_aurora()
	_build_rig()
	_build_spores()
	_build_vignette()
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
	# Stars breathe on their own slow clocks — a still starfield reads as a texture,
	# a twinkling one reads as sky.
	for i in _stars.size():
		var star: ColorRect = _stars[i]
		star.modulate.a = 0.35 + 0.45 * (0.5 + 0.5 * sin(t * 0.9 + _star_phase[i]))
	# The reflection sways gently, as if the whole image is riding a long slow swell.
	if _reflection:
		_reflection.position.x = sin(t * 0.5) * 4.0

## -- backdrop (smooth gradients, not banded rects) --------------------------

func _build_backdrop() -> void:
	# Sky: one smooth vertical gradient, near-black overhead easing to a faint teal
	# breath at the horizon. GradientTexture2D beats a stack of ColorRects — no banding.
	var sky_grad := Gradient.new()
	sky_grad.offsets = PackedFloat32Array([0.0, 0.55, 0.86, 1.0])
	sky_grad.colors = PackedColorArray([COL_SKY_TOP, COL_SKY_MID,
		Color(0.06, 0.16, 0.18), Color(0.12, 0.28, 0.29)])
	_grad_rect(0.0, HORIZON, sky_grad, true)
	# Sea: teal just under the horizon darkening to near-black at the player's feet.
	var sea_grad := Gradient.new()
	sea_grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	sea_grad.colors = PackedColorArray([Color(0.08, 0.2, 0.21), COL_SEA, COL_SEA_DEEP])
	_grad_rect(HORIZON, 1.0, sea_grad, true)
	# Horizon line: a thin pale seam where sky meets water.
	var line: ColorRect = _band(HORIZON, HORIZON, Color(0.6, 0.8, 0.76, 0.5))
	line.offset_top = -1.0
	line.offset_bottom = 1.0

## A vertical gradient panel spanning anchor fractions a_top..a_bottom.
func _grad_rect(a_top: float, a_bottom: float, grad: Gradient, vertical: bool) -> TextureRect:
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.anchor_left = 0.0
	tr.anchor_right = 1.0
	tr.anchor_top = a_top
	tr.anchor_bottom = a_bottom
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	return tr

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

## -- moon --------------------------------------------------------------------

func _build_moon() -> void:
	# A cold hazed moon low over the sea, well off to one side of the rig. A radial
	# gradient gives it a real halo instead of a hard disc.
	var view: Vector2 = get_viewport_rect().size
	var moon_c := Vector2(view.x * 0.24, view.y * HORIZON - view.y * 0.22)
	var halo := _radial(Color(0.7, 0.82, 0.85, 0.5), 220.0)
	halo.position = moon_c - Vector2(110, 110)
	var disc := _radial(Color(0.9, 0.95, 0.96, 0.95), 58.0)
	disc.position = moon_c - Vector2(29, 29)
	# Its long reflected track down the water toward the viewer.
	var track := ColorRect.new()
	track.color = Color(0.7, 0.82, 0.85, 0.06)
	track.size = Vector2(46.0, view.y * (1.0 - HORIZON))
	track.position = Vector2(moon_c.x - 23.0, view.y * HORIZON)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(track)

## A soft radial disc `diameter` px across, brightest at the centre.
func _radial(col: Color, diameter: float) -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([col, Color(col.r, col.g, col.b, col.a * 0.25),
		Color(col.r, col.g, col.b, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.size = Vector2(diameter, diameter)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	return tr

## -- stars -------------------------------------------------------------------

func _build_stars() -> void:
	var view: Vector2 = get_viewport_rect().size
	for i in STAR_COUNT:
		var star := ColorRect.new()
		var px: float = randf_range(1.0, 2.4)
		star.size = Vector2(px, px)
		# Faintly tinted pearl/teal, brighter ones rarer.
		var warm: float = randf()
		star.color = COL_PEARL.lerp(COL_TEAL, warm * 0.4)
		# Only above the horizon, denser toward the top.
		var yf: float = pow(randf(), 1.6) * (HORIZON - 0.02)
		star.position = Vector2(randf() * view.x, yf * view.y)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(star)
		_stars.append(star)
		_star_phase.append(randf() * TAU)

## -- aurora ------------------------------------------------------------------

func _build_aurora() -> void:
	# The Bloom's answer in the sky: a low, wide teal glow smeared along the horizon,
	# the same cold light the sea carries. Two soft radial smears, very dim.
	var view: Vector2 = get_viewport_rect().size
	for spec in [[0.55, 0.9], [0.8, 0.6]]:
		var glow := _radial(Color(COL_TEAL.r, COL_TEAL.g, COL_TEAL.b, 0.05), view.x * float(spec[1]))
		glow.position = Vector2(view.x * float(spec[0]) - glow.size.x * 0.5,
			view.y * HORIZON - glow.size.y * 0.62)

## -- rig silhouette + reflection --------------------------------------------

func _build_rig() -> void:
	_reflection = _rig_body(true)    # water reflection first (drawn under)
	_rig_body(false)                 # the rig itself on top

## Build the whole rig at the horizon; `mirror` flips it down into the water as a
## dim, wobbling reflection.
func _rig_body(mirror: bool) -> Control:
	var rig := Control.new()
	rig.anchor_left = 0.72
	rig.anchor_right = 0.72
	rig.anchor_top = HORIZON
	rig.anchor_bottom = HORIZON
	rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rig)
	if mirror:
		rig.scale = Vector2(1.0, -0.85)   # flipped and foreshortened, as reflections are
		rig.modulate = Color(1.0, 1.0, 1.0, 0.22)
	var col: Color = COL_RIG if not mirror else Color(0.05, 0.12, 0.13)
	# Legs (poke slightly below the horizon into the sea).
	_rig_rect(rig, Vector2(-60.0, -20.0), Vector2(7.0, 24.0), col)
	_rig_rect(rig, Vector2(-4.0, -20.0), Vector2(7.0, 24.0), col)
	_rig_rect(rig, Vector2(53.0, -20.0), Vector2(7.0, 24.0), col)
	# Deck slab.
	_rig_rect(rig, Vector2(-72.0, -28.0), Vector2(144.0, 9.0), col)
	# Blocky superstructure.
	_rig_rect(rig, Vector2(-52.0, -56.0), Vector2(40.0, 28.0), col)
	_rig_rect(rig, Vector2(-6.0, -46.0), Vector2(30.0, 18.0), col)
	_rig_rect(rig, Vector2(30.0, -40.0), Vector2(16.0, 12.0), col)
	# Crane boom off the deck edge.
	_rig_rect(rig, Vector2(24.0, -62.0), Vector2(3.0, 34.0), col)
	_rig_rect(rig, Vector2(24.0, -62.0), Vector2(38.0, 3.0), col)
	# Antenna mast atop the tall block, with a pulsing red beacon.
	_rig_rect(rig, Vector2(-30.0, -92.0), Vector2(3.0, 36.0), col)
	# Lit windows — a few warm squares on the accommodation block. The one sign someone
	# was here. Dimmer and cooler in the reflection.
	var wcol: Color = COL_WINDOW if not mirror else Color(0.5, 0.4, 0.28)
	for w in [Vector2(-46.0, -50.0), Vector2(-40.0, -50.0), Vector2(-46.0, -42.0),
			Vector2(-2.0, -40.0), Vector2(4.0, -40.0), Vector2(34.0, -36.0)]:
		_rig_rect(rig, w, Vector2(3.0, 3.0), wcol)
	if not mirror:
		var beacon: ColorRect = _rig_rect(rig, Vector2(-31.0, -97.0), Vector2(5.0, 5.0), COL_BEACON)
		var tw: Tween = create_tween().set_loops()
		tw.tween_property(beacon, "modulate:a", 0.15, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(beacon, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return rig

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

## -- vignette ----------------------------------------------------------------

func _build_vignette() -> void:
	# Darken the corners so the eye falls to the title and the rig. A radial gradient
	# that is transparent in the middle and black at the edges.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.anchor_right = 1.0
	tr.anchor_bottom = 1.0
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)

## -- title -------------------------------------------------------------------

func _build_title() -> void:
	# A dark drop-shadow copy sits behind everything so the wordmark reads against the
	# bright horizon; then the teal glow echo; then the solid pearl letters on top.
	var shadow := _title_row(Color(0, 0, 0, 0.55))
	shadow.position = Vector2(3, 4)
	_center_region(0.1, 0.4).add_child(shadow)

	_glow_row = _title_row(COL_TEAL)
	_glow_row.scale = Vector2(1.05, 1.05)
	_glow_row.resized.connect(func() -> void:
		_glow_row.pivot_offset = _glow_row.size * 0.5)
	_center_region(0.1, 0.4).add_child(_glow_row)
	_glow_row.modulate.a = 0.25
	var tw: Tween = create_tween().set_loops()
	tw.tween_property(_glow_row, "modulate:a", 0.5, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_glow_row, "modulate:a", 0.25, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_center_region(0.1, 0.4).add_child(_title_row(COL_PEARL))

	var subtitle := Label.new()
	subtitle.text = "FIRST NIGHT — an abandoned-rig survival mystery"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.76, 0.74, 0.85))
	subtitle.anchor_left = 0.0
	subtitle.anchor_right = 1.0
	subtitle.anchor_top = 0.4
	subtitle.anchor_bottom = 0.46
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)

func _title_row(col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch: String in "SALTLINE":
		var l := Label.new()
		l.text = ch
		l.add_theme_font_size_override("font_size", 116)
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
	footer.text = "Beta 0.1 — WASD move · E interact · I inventory · F flashlight"
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
