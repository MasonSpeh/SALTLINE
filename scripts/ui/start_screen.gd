class_name StartScreen extends Control
## Branded start screen: a painted North-Sea night — smooth gradient sky with a low
## Bloom-teal aurora, a hazed moon, drifting fog banks, a stark
## rig silhouette with flickering sodium windows and a slow rotating derrick beacon that
## rims the structure as it passes, its reflection breaking on the swell, distant swell
## glints, an occasional gull drifting the horizon, film grain + a corner vignette, a
## glowing letterspaced SALTLINE wordmark, and a minimal keyboard-navigable menu.
## Everything is built in code (two cheap canvas_item shaders + ColorRect/Polygon2D dressing,
## trivially light on gl_compatibility); the .tscn is just this script on a Control. No
## external art — all procedural, so it ships with zero deps.

const MAIN_SCENE: String = "res://scenes/Main.tscn"

const HORIZON: float = 0.66
const STAR_COUNT: int = 90
const FOG_COUNT: int = 5
const GLINT_COUNT: int = 16

const COL_SKY_TOP: Color = Color(0.015, 0.03, 0.05)
const COL_SKY_MID: Color = Color(0.03, 0.06, 0.09)
const COL_SEA: Color = Color(0.03, 0.12, 0.13)
const COL_SEA_DEEP: Color = Color(0.008, 0.035, 0.045)
const COL_PEARL: Color = Color(0.88, 0.94, 0.92)
const COL_TEAL: Color = Color(0.2, 0.9, 0.85)
const COL_RIG: Color = Color(0.006, 0.016, 0.024)
const COL_BEACON: Color = Color(0.95, 0.2, 0.18)
const COL_WINDOW: Color = Color(0.95, 0.78, 0.42)   ## warm sodium light in the rig windows
const COL_FOG: Color = Color(0.10, 0.19, 0.21)      ## cold charcoal-teal haze

var _stars: Array[ColorRect] = []
var _star_phase: Array[float] = []
var _reflection: Control                 ## the whole rig mirror, wobbled on the swell
var _glow_row: HBoxContainer
var _fog: Array[TextureRect] = []
var _fog_speed: Array[float] = []
var _glints: Array[ColorRect] = []
var _glint_phase: Array[float] = []
var _glint_base: Array[float] = []       ## each glint's base alpha
var _windows: Array[ColorRect] = []      ## the real rig's lit windows (flickering subset flagged)
var _win_flick: Array[bool] = []
var _win_phase: Array[float] = []
var _beacon_pivot: Node2D                ## rotating derrick sweep
var _rig_rim: ColorRect                  ## thin top-edge highlight the beacon brushes across
var _gull: Node2D                        ## the lone drifting gull
var _gull_t: float = -3.0                ## <0 = waiting to re-enter
var _gull_speed: float = 22.0
var _gull_y: float = 0.0
var _menu: VBoxContainer                 ## the slot menu, repopulated on erase
var _rig_node: Control                    ## the rig silhouette; beacon parents to it so both track resize
var _gull_dir: float = 1.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_backdrop()
	_build_moon()
	_build_stars()
	_build_aurora()
	_build_fog()
	_build_rig()
	_build_glints()
	_build_beacon()
	_build_gull()
	_build_vignette()
	_build_grain()
	_build_title()
	_build_menu()
	_build_footer()

func _process(delta: float) -> void:
	var view: Vector2 = get_viewport_rect().size
	var t: float = Time.get_ticks_msec() * 0.001
	# Stars breathe on their own slow clocks — a still starfield reads as a texture,
	# a twinkling one reads as sky.
	for i in _stars.size():
		var star: ColorRect = _stars[i]
		star.modulate.a = 0.35 + 0.45 * (0.5 + 0.5 * sin(t * 0.9 + _star_phase[i]))
	# Fog banks drift slowly sideways and wrap, softening the horizon and the rig base.
	for i in _fog.size():
		var f: TextureRect = _fog[i]
		f.position.x += _fog_speed[i] * delta
		if _fog_speed[i] > 0.0 and f.position.x > view.x:
			f.position.x = -f.size.x
		elif _fog_speed[i] < 0.0 and f.position.x < -f.size.x:
			f.position.x = view.x
	# Sea swell glints shimmer and crawl — cold light broken on a long slow swell.
	for i in _glints.size():
		var g: ColorRect = _glints[i]
		g.modulate.a = _glint_base[i] * (0.25 + 0.75 * pow(0.5 + 0.5 * sin(t * 1.3 + _glint_phase[i]), 3.0))
		g.position.x += sin(t * 0.4 + _glint_phase[i]) * 6.0 * delta
	# Sodium windows: a couple hold steady, the rest buzz and gutter like failing ballast.
	for i in _windows.size():
		if not _win_flick[i]:
			continue
		var ph: float = _win_phase[i]
		var f2: float = 0.62 + 0.28 * sin(t * 8.0 + ph) + 0.10 * sin(t * 23.0 + ph * 2.3)
		# occasional brown-out dip
		if sin(t * 1.7 + ph) > 0.93:
			f2 *= 0.25
		_windows[i].modulate.a = clampf(f2, 0.08, 1.0)
	# The reflection sways gently, as if the whole image is riding a long slow swell.
	if _reflection:
		_reflection.position.x = sin(t * 0.5) * 4.0
	# Derrick beacon: a slow full rotation. The beam is brightest sweeping across the open
	# sky toward the viewer and dims pointing away; when it passes the rig heading it brushes
	# a faint rim across the silhouette's top edge.
	if _beacon_pivot:
		var ang: float = t * 0.6
		_beacon_pivot.rotation = ang
		# beam faces "down the page" at rotation ~PI/2 (Polygon2D built pointing +Y).
		var facing: float = sin(ang)                       # 1.0 when sweeping toward viewer
		_beacon_pivot.modulate.a = 0.10 + 0.55 * clampf(facing, 0.0, 1.0)
		if _rig_rim:
			# rim lights when the beam rakes left across the structure (rotation near PI)
			var rake: float = maxf(0.0, -cos(ang))
			_rig_rim.modulate.a = 0.04 + 0.5 * pow(rake, 3.0)
	# Gull: a lone silhouette drifts the horizon now and then, wings slowly flexing.
	_gull_t += delta
	if _gull and _gull_t >= 0.0:
		var gx: float = -60.0 + _gull_dir * _gull_speed * _gull_t
		if _gull_dir < 0.0:
			gx = view.x + 60.0 - _gull_speed * _gull_t
		_gull.position = Vector2(gx, _gull_y + sin(t * 0.8) * 6.0)
		_gull.scale.x = _gull_dir
		# slow wing flap
		var flap: float = 0.6 + 0.4 * sin(t * 3.2)
		_gull.scale.y = flap
		if gx < -80.0 or gx > view.x + 80.0:
			_reset_gull(view)

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

## -- fog banks ---------------------------------------------------------------

func _build_fog() -> void:
	# Wide, soft, low-alpha charcoal-teal smears drifting across the horizon and low sky.
	# A stretched radial reads as a torn cloud bank; several at different heights/speeds
	# give parallax without a single hard edge.
	var view: Vector2 = get_viewport_rect().size
	for i in FOG_COUNT:
		var w: float = randf_range(view.x * 0.5, view.x * 0.95)
		var h: float = randf_range(70.0, 150.0)
		var a: float = randf_range(0.05, 0.13)
		var f := _soft_blob(Color(COL_FOG.r, COL_FOG.g, COL_FOG.b, a), w, h)
		var yf: float = HORIZON - randf_range(-0.02, 0.20)   # hug the horizon, a few higher
		f.position = Vector2(randf() * view.x, view.y * yf - h * 0.5)
		_fog.append(f)
		var spd: float = randf_range(5.0, 14.0)
		_fog_speed.append(spd if randf() < 0.5 else -spd)

## A soft-edged elliptical haze `w`x`h` px, brightest at centre.
func _soft_blob(col: Color, w: float, h: float) -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([col, Color(col.r, col.g, col.b, col.a * 0.4),
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
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(w, h)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	return tr

## -- rig silhouette + reflection --------------------------------------------

func _build_rig() -> void:
	_reflection = _rig_body(true)    # water reflection first (drawn under)
	_rig_node = _rig_body(false)     # the rig itself on top (beacon anchors to this)

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
	var idx: int = 0
	for w in [Vector2(-46.0, -50.0), Vector2(-40.0, -50.0), Vector2(-46.0, -42.0),
			Vector2(-2.0, -40.0), Vector2(4.0, -40.0), Vector2(34.0, -36.0)]:
		var win: ColorRect = _rig_rect(rig, w, Vector2(3.0, 3.0), wcol)
		if not mirror:
			_windows.append(win)
			# three of the six gutter; the rest hold.
			_win_flick.append(idx == 1 or idx == 3 or idx == 5)
			_win_phase.append(randf() * TAU)
		idx += 1
	if not mirror:
		# Thin rim highlight along the superstructure/deck top edge that the beacon rakes.
		_rig_rim = _rig_rect(rig, Vector2(-54.0, -57.0), Vector2(90.0, 1.5), COL_TEAL)
		_rig_rim.modulate.a = 0.04
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

## -- sea swell glints --------------------------------------------------------

func _build_glints() -> void:
	# Short bright horizontal dashes scattered across the water — cold moon/Bloom light
	# catching the crests. They shimmer (alpha) and crawl a little on the swell.
	var view: Vector2 = get_viewport_rect().size
	for i in GLINT_COUNT:
		var g := ColorRect.new()
		var w: float = randf_range(4.0, 16.0)
		g.size = Vector2(w, randf_range(1.0, 1.6))
		var warm: float = randf()
		g.color = COL_PEARL.lerp(COL_TEAL, 0.3 + warm * 0.5)
		# spread across the sea, denser near the horizon
		var yf: float = HORIZON + pow(randf(), 1.7) * (0.9 - HORIZON) + 0.01
		g.position = Vector2(randf() * view.x, yf * view.y)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(g)
		_glints.append(g)
		_glint_phase.append(randf() * TAU)
		_glint_base.append(randf_range(0.10, 0.32))

## -- derrick beacon sweep ----------------------------------------------------

func _build_beacon() -> void:
	# A long, narrow, soft light wedge pivoting at the mast tip — the rotating aero-warning
	# beacon of a dead rig, still turning. Polygon2D with vertex-colour fade: bright at the
	# apex, transparent at the far end.
	var view: Vector2 = get_viewport_rect().size
	_beacon_pivot = Node2D.new()
	# Parent the pivot to the rig silhouette at the mast tip (rig-local coords), so the
	# beam stays glued to the mast when the window resizes / goes fullscreen. Previously
	# it sat at an absolute pixel computed once, and drifted off the rig on resize.
	_beacon_pivot.position = Vector2(-28.5, -94.0)
	if is_instance_valid(_rig_node):
		_rig_node.add_child(_beacon_pivot)
	else:
		add_child(_beacon_pivot)
	var length: float = view.y * 0.85
	var half_w: float = length * 0.055            # slim cone
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(-half_w, length), Vector2(half_w, length)])
	beam.vertex_colors = PackedColorArray([
		Color(0.72, 0.86, 0.9, 0.9), Color(0.72, 0.86, 0.9, 0.0), Color(0.72, 0.86, 0.9, 0.0)])
	_beacon_pivot.add_child(beam)
	_beacon_pivot.modulate.a = 0.0

## -- gull --------------------------------------------------------------------

func _build_gull() -> void:
	var view: Vector2 = get_viewport_rect().size
	_gull = Node2D.new()
	_gull.z_index = 1
	add_child(_gull)
	# A shallow "M" of two wings, dark against the sky.
	var wing := Line2D.new()
	wing.points = PackedVector2Array([
		Vector2(-11, 2), Vector2(-6, -3), Vector2(0, 1), Vector2(6, -3), Vector2(11, 2)])
	wing.width = 2.0
	# A faint pale-slate mark — a true black silhouette vanishes against the night sky.
	wing.default_color = Color(0.5, 0.58, 0.6, 0.5)
	wing.joint_mode = Line2D.LINE_JOINT_ROUND
	wing.begin_cap_mode = Line2D.LINE_CAP_ROUND
	wing.end_cap_mode = Line2D.LINE_CAP_ROUND
	_gull.add_child(wing)
	_reset_gull(view)

func _reset_gull(view: Vector2) -> void:
	_gull_t = -randf_range(4.0, 12.0)                       # a pause between passes
	_gull_dir = 1.0 if randf() < 0.6 else -1.0
	_gull_speed = randf_range(18.0, 30.0)
	_gull_y = view.y * randf_range(0.30, 0.52)
	_gull.position = Vector2(-999.0, _gull_y)               # park offscreen while waiting

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

## -- film grain (canvas shader) ----------------------------------------------

func _build_grain() -> void:
	# A very subtle animated grain veil — enough to break the flat gradients into something
	# that feels shot on stock, not rendered. One cheap hash per pixel.
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float amount = 0.05;
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 p = FRAGCOORD.xy + vec2(fract(TIME) * 311.0, fract(TIME * 1.7) * 197.0);
	float n = h(floor(p));
	COLOR = vec4(vec3(n), (n - 0.5) * amount + amount * 0.15);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.material = mat
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

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

const MENU_MAIN_W: float = 300.0
const MENU_ERASE_W: float = 84.0

func _build_menu() -> void:
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 14)
	_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	# Sit the menu in the lower third but clear of the footer (was 0.66–0.94, which
	# crowded QUIT into the beta-tips line).
	_center_region(0.60, 0.90).add_child(_menu)
	_populate_menu()

## (Re)build the slot list. Each of the three slots is Continue if it holds a save
## (with a small ERASE to clear it) or New Expedition if empty. Every row reserves the
## same erase-column width so the main buttons line up whether or not a slot is filled.
## Called again after an erase so the labels refresh in place.
func _populate_menu() -> void:
	for c in _menu.get_children():
		c.queue_free()
	var first: Button = null
	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var info: Dictionary = SaveManager.slot_info(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_menu.add_child(row)
		var main_btn: Button = _menu_button(row, "%d.  %s" % [slot, info.get("label", "New Expedition")])
		main_btn.custom_minimum_size = Vector2(MENU_MAIN_W, 46.0)
		var s: int = slot
		if bool(info.get("exists", false)):
			main_btn.pressed.connect(func() -> void: _continue_slot(s))
			var erase: Button = _menu_button(row, "ERASE")
			erase.custom_minimum_size = Vector2(MENU_ERASE_W, 46.0)
			erase.add_theme_font_size_override("font_size", 14)
			erase.pressed.connect(func() -> void:
				SaveManager.erase_slot(s)
				_populate_menu())
		else:
			main_btn.pressed.connect(func() -> void: _new_slot(s))
			# Empty slot: hold the erase column open with an invisible spacer so this
			# row is exactly as wide as a filled one and the main buttons stay aligned.
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(MENU_ERASE_W, 46.0)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(spacer)
		if first == null:
			first = main_btn
	# QUIT sits on its own, matched to the main-button width so it lines up under them.
	var quit_row := HBoxContainer.new()
	quit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu.add_child(quit_row)
	var quit: Button = _menu_button(quit_row, "QUIT")
	quit.custom_minimum_size = Vector2(MENU_MAIN_W, 46.0)
	quit.pressed.connect(func() -> void: get_tree().quit())
	if first:
		first.grab_focus()

func _new_slot(slot: int) -> void:
	SaveManager.begin_new_game(slot)
	_start_game()

func _continue_slot(slot: int) -> void:
	SaveManager.begin_continue(slot)
	_start_game()

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
