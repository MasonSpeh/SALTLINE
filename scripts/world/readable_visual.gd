class_name ReadableVisual extends RefCounted
## Real paper for every Readable, in place of the flat white greybox card.
##
## Four forms:
##   BOOK   — hard cloth cover a shade larger than the page block, spine, visible
##            page edges on the three open sides.
##   JOURNAL— worn leather boards, an elastic band wrapped round the fore-edge,
##            one dog-eared corner.
##   PAPER  — a few thin sheets stacked slightly offset and askew, the top one
##            faintly ruled with printed lines.
##   POSTER — a paper quad taped flat to a bulkhead, tape tabs at the corners.
##
## Each form is built CENTRED on the Readable's origin, facing local +Z, then the
## root is yawed/pitched so that face points down the THIN axis of the placement
## `size` — the same axis the old box already used as its "you read it from here"
## normal. So nothing moves: a wall notice stays on its wall, a log lying on a desk
## stays lying on the desk. The interaction collider is still the caller's box, so
## aiming at a readable is unchanged.
##
## Form choice is deterministic (same id -> same form every run): an explicit
## `type`/`form` field in data/readables.json wins if one is ever added, then ids
## that clearly read as posted notices become POSTERS (but only where the
## placement is actually wall-mounted — a "memo" lying flat on a desk is paper),
## then content words (log/manual/note...), then a hash of the id.

enum Form { BOOK, JOURNAL, PAPER, POSTER }

## Posted-notice words. Only win when the placement is wall-mounted (see build()).
const POSTER_WORDS: Array[String] = [
	"sign", "notice", "poster", "placard", "bulletin", "warning", "muster",
	"roster", "menu", "plan", "scrawl", "memo",
]
const BOOK_WORDS: Array[String] = ["handbook", "manual", "book", "encyclopedia"]
const JOURNAL_WORDS: Array[String] = ["log", "journal", "notebook", "ledger", "diary", "tally", "notes"]
const PAPER_WORDS: Array[String] = ["note", "letter", "memo", "tag", "slate", "card", "photo", "mark", "splice"]

# Book cloth — the drab bindings a company issues, not a library.
const COVER_COLS: Array[Color] = [
	Color(0.34, 0.16, 0.14),   # oxblood
	Color(0.16, 0.23, 0.34),   # navy
	Color(0.19, 0.29, 0.22),   # bottle green
	Color(0.40, 0.33, 0.17),   # ochre
	Color(0.27, 0.22, 0.29),   # plum
]
const PAGE_COL := Color(0.87, 0.85, 0.77)
const PAGE_EDGE := Color(0.80, 0.77, 0.67)
const LEATHER := Color(0.30, 0.20, 0.13)
const LEATHER_WORN := Color(0.37, 0.26, 0.17)
const ELASTIC := Color(0.11, 0.11, 0.12)
const SHEET_COL := Color(0.89, 0.88, 0.82)
const POSTER_COL := Color(0.84, 0.81, 0.71)
const PRINT_COL := Color(0.24, 0.24, 0.26)
const TAPE_COL := Color(0.78, 0.72, 0.54)

static var _mats: Dictionary = {}

# ---------------------------------------------------------------- form choice

## Stable 32-bit FNV-1a so a given readable id always builds the same form,
## independent of engine build or String.hash() internals.
static func _hash(s: String) -> int:
	var h: int = 2166136261
	for i in range(s.length()):
		h = (h ^ s.unicode_at(i)) * 16777619
		h = h & 0xFFFFFFFF
	return h

static func _has_word(low: String, words: Array[String]) -> bool:
	for w in words:
		if low.contains(w):
			return true
	return false

## `wall_mounted` = the placement's thin axis is horizontal (X or Z), i.e. it is
## stood against / pinned to something rather than lying face-up on a surface.
## `declared` is the readable's own `type`/`form` field, passed in by the caller
## (Readable already holds the parsed JSON — this file stays free of that lookup
## so the two scripts never form a preload cycle).
static func form_for(id: String, wall_mounted: bool = true, declared: String = "") -> int:
	var low: String = id.to_lower()
	# 1. Explicit type in the data, if that field ever lands.
	match declared.to_lower():
		"book": return Form.BOOK
		"journal": return Form.JOURNAL
		"paper", "papers", "paper_stack": return Form.PAPER
		"poster", "notice": return Form.POSTER
	# 2. Posted notices — but only where it is actually mounted on something.
	if wall_mounted and _has_word(low, POSTER_WORDS):
		return Form.POSTER
	# 3. What the thing plainly is.
	if _has_word(low, BOOK_WORDS):
		return Form.BOOK
	if _has_word(low, JOURNAL_WORDS):
		return Form.JOURNAL
	if _has_word(low, PAPER_WORDS):
		return Form.PAPER
	# 4. Deterministic fallback.
	match _hash(low) % 3:
		0: return Form.BOOK
		1: return Form.JOURNAL
		_: return Form.PAPER

# ---------------------------------------------------------------- build

## Returns a visual root to parent to a Readable. `size` is the placement box the
## world scripts already author: its SMALLEST axis is the direction you look from.
## `declared` is an optional `type`/`form` string from data/readables.json.
static func build(id: String, size: Vector3, declared: String = "") -> Node3D:
	var root := Node3D.new()
	# Which axis is the "through the paper" one.
	var ax: int = 2
	if size.x <= size.y and size.x <= size.z:
		ax = 0
	elif size.y <= size.x and size.y <= size.z:
		ax = 1
	# Width / height / thickness in the form's own frame (front faces local +Z).
	var w: float = size.x
	var h: float = size.y
	var t: float = size.z
	if ax == 0:
		w = size.z; h = size.y; t = size.x
	elif ax == 1:
		w = size.x; h = size.z; t = size.y
	w = maxf(w, 0.05)
	h = maxf(h, 0.05)
	t = maxf(t, 0.015)

	var form: int = form_for(id, ax != 1, declared)
	var content := Node3D.new()
	root.add_child(content)
	match form:
		Form.BOOK: _book(content, id, w, h, t)
		Form.JOURNAL: _journal(content, id, w, h, t)
		Form.POSTER: _poster(content, id, w, h, t)
		_: _paper(content, id, w, h, t)

	# Point the built face down the thin axis. Local +Z -> +X is a +90 yaw;
	# local +Z -> +Y (lying face-up on a desk) is a -90 pitch.
	if ax == 0:
		root.rotation.y = deg_to_rad(90.0)
	elif ax == 1:
		root.rotation.x = deg_to_rad(-90.0)
	return root

# ---------------------------------------------------------------- forms

static func _book(root: Node3D, id: String, w: float, h: float, t: float) -> void:
	t = maxf(t, 0.035)
	var cloth: Color = COVER_COLS[_hash(id) % COVER_COLS.size()]
	var board: float = t * 0.15
	# Page block first, a shade smaller all round so the boards overhang and the
	# cut edges of the paper show on the three open sides.
	_slab(root, Vector3(w * 0.94, h * 0.93, t * 0.68), PAGE_COL, Vector3(w * 0.025, 0, 0))
	# Front and back boards.
	_slab(root, Vector3(w, h, board), cloth, Vector3(0, 0, t * 0.5 - board * 0.5))
	_slab(root, Vector3(w, h, board), cloth.darkened(0.12), Vector3(0, 0, -t * 0.5 + board * 0.5))
	# Spine down the left edge, wrapping the full thickness.
	_slab(root, Vector3(t * 0.22, h, t), cloth.darkened(0.2), Vector3(-w * 0.5 + t * 0.11, 0, 0))
	# A sunk title panel on the front board — reads as blocked/foiled lettering.
	_slab(root, Vector3(w * 0.5, h * 0.1, t * 0.03),
		cloth.lightened(0.22), Vector3(w * 0.04, h * 0.26, t * 0.5 + t * 0.015))

static func _journal(root: Node3D, id: String, w: float, h: float, t: float) -> void:
	t = maxf(t, 0.035)
	var board: float = t * 0.16
	# Page block, offset off the spine so the fore-edge shows.
	_slab(root, Vector3(w * 0.92, h * 0.91, t * 0.64), PAGE_COL, Vector3(w * 0.03, 0, 0))
	# Worn leather boards — the front a little more sun/salt-lifted than the back.
	_slab(root, Vector3(w, h, board), LEATHER_WORN, Vector3(0, 0, t * 0.5 - board * 0.5))
	_slab(root, Vector3(w, h, board), LEATHER, Vector3(0, 0, -t * 0.5 + board * 0.5))
	_slab(root, Vector3(t * 0.24, h, t), LEATHER.darkened(0.18), Vector3(-w * 0.5 + t * 0.12, 0, 0))
	# Elastic band closure, wrapped round the fore-edge and over both boards.
	_slab(root, Vector3(w * 0.055, h * 1.03, t * 1.06), ELASTIC, Vector3(w * 0.33, 0, 0))
	# One dog-eared corner, top right of the page block.
	var ear := _slab(root, Vector3(w * 0.14, h * 0.12, t * 0.5),
		PAGE_EDGE, Vector3(w * 0.40, h * 0.38, 0))
	ear.rotation.z = deg_to_rad(38.0)

static func _paper(root: Node3D, id: String, w: float, h: float, t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash(id)
	var sheets: int = 4
	var leaf: float = maxf(t / float(sheets) * 0.55, 0.0012)
	# A few loose sheets, each shoved a little out of true.
	for i in range(sheets):
		var f: float = float(i) / float(sheets - 1)
		var z: float = -t * 0.5 + t * f * 0.9 + leaf
		var sheet := _slab(root, Vector3(w, h, leaf),
			SHEET_COL.darkened(0.06 * (1.0 - f)),
			Vector3(rng.randf_range(-w, w) * 0.045, rng.randf_range(-h, h) * 0.045, z))
		sheet.rotation.z = deg_to_rad(rng.randf_range(-5.0, 5.0))
	# The top sheet carries faint ruled/printed lines — thin dark strips, short of
	# the margins so it reads as a typed page rather than a barcode. Sat exactly on
	# the top sheet's face (its centre is at 0.4t + leaf, half a leaf thick).
	var top_z: float = -t * 0.5 + t * 0.9 + leaf * 1.8
	for i in range(6):
		var ly: float = h * 0.30 - float(i) * h * 0.115
		var lw: float = w * (0.66 if i == 0 else 0.52 + rng.randf_range(-0.12, 0.12))
		var line := _slab(root, Vector3(lw, h * 0.017, leaf * 0.6),
			PRINT_COL, Vector3(-w * 0.5 + lw * 0.5 + w * 0.12, ly, top_z))
		line.rotation.z = deg_to_rad(rng.randf_range(-5.0, 5.0))

static func _poster(root: Node3D, id: String, w: float, h: float, t: float) -> void:
	var paper: float = maxf(t * 0.5, 0.004)
	# The sheet itself — thin, and centred so it sits hard against its bulkhead
	# whichever side the steel is on. Double-sided: paper has no back face to cull.
	_slab(root, Vector3(w, h, paper), POSTER_COL, Vector3.ZERO, true)
	# Print and tape go on BOTH faces. The placements only tell us which AXIS a
	# readable is viewed along, not which side of it the steel is on, so a poster
	# dressed on one face only would show the room its blank back half the time.
	# The face that ends up against the bulkhead is buried in it and never seen.
	for s in [1.0, -1.0]:
		var front: float = paper * 0.5 * s
		# Printed head rule + body lines.
		_slab(root, Vector3(w * 0.74, h * 0.055, paper * 0.4), PRINT_COL,
			Vector3(0, h * 0.32, front + paper * 0.2 * s))
		var line_rng := RandomNumberGenerator.new()
		line_rng.seed = _hash(id)
		for i in range(5):
			var lw: float = w * (0.62 + line_rng.randf_range(-0.16, 0.10))
			_slab(root, Vector3(lw, h * 0.022, paper * 0.35), PRINT_COL.lightened(0.25),
				Vector3(-w * 0.5 + lw * 0.5 + w * 0.09, h * 0.16 - float(i) * h * 0.1,
					front + paper * 0.2 * s))
		# Tape tabs across each corner, stuck proud of the paper.
		for c in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			var tab := _slab(root, Vector3(minf(w, h) * 0.24, minf(w, h) * 0.07, paper * 0.5),
				TAPE_COL, Vector3(c.x * w * 0.44, c.y * h * 0.45, front + paper * 0.3 * s), true)
			tab.rotation.z = deg_to_rad(45.0 * (1.0 if c.x * c.y > 0.0 else -1.0))

# ---------------------------------------------------------------- primitives

static func _slab(root: Node3D, size: Vector3, color: Color, pos: Vector3,
		double_sided: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = _mat(color, double_sided)
	mi.mesh = m
	# Match the greybox card these replace: props this small never cast shadows.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.position = pos
	return mi

## Own material cache — never hand back a shared MatLib material, since posters
## need cull_disabled and mutating a cached one would leak across the whole rig.
static func _mat(color: Color, double_sided: bool = false) -> StandardMaterial3D:
	var key: String = "%s_%s" % [color.to_html(), double_sided]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.82
	m.metallic = 0.0
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m
