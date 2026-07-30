extends RefCounted
## SIGNAGE METRICS — the one place that knows how wide a Label3D actually renders.
##
## Preload by path (`const SignFit = preload("res://scripts/world/sign_fit.gd")`), never
## by class_name: the global class cache lags for new files (see docs/AGENT_TRAPS.md).
##
## WHY THIS EXISTS. Every signage helper on this rig used to size its plate from an
## ESTIMATE — `max_chars * font_size * 0.01 * 0.58` — as if every glyph were 0.58 em
## wide. It is not, and the error is not small or one-signed. Measured against
## `Label3D.get_aabb()` on the shipping font (Open Sans SemiBold, the engine fallback):
##
##     "iiiiii"          0.29 em/char   estimate 99% too WIDE
##     "FIRE HOSE REEL"  0.54 em/char   estimate  7% too wide
##     "MUSTER STATION B" 0.59 em/char  estimate  1% too NARROW  <- clips
##     "NO SMOKING"      0.66 em/char   estimate 14% too narrow  <- clips
##     "MMMM"            0.93 em/char   estimate 59% too narrow  <- clips badly
##
## Upper-case signage — which is all of it — runs 0.54-0.66 em/char, i.e. the estimate
## was *below* the truth for most real wording. That is the whole "text spans edge to
## edge / goes over the sign width" complaint.
##
## The exact number is free: `Font.get_string_size(...).x * pixel_size` is byte-identical
## to `Label3D.get_aabb().size.x`, and `Font.get_height(font_size) * pixel_size` is the
## per-line height. Verified both ways in `tests/label_anchor_probe.gd`, which asserts the
## agreement on every live label every run, so this file cannot drift from the renderer.

## The font a Label3D uses when its own `font` is null — which is every label on the rig.
static func font() -> Font:
	return ThemeDB.fallback_font

## EXACT rendered extent, in metres, of `text` drawn by a Label3D at `font_size` and
## `pixel_size`. Matches `Label3D.get_aabb().size` (x, y) to the pixel.
static func extent(text: String, font_size: int, pixel_size: float = 0.01) -> Vector2:
	var f: Font = font()
	if f == null:
		# Cannot happen in-engine; degrade to the old estimate rather than divide by zero.
		return Vector2(float(text.length() * font_size) * pixel_size * 0.7,
			float(font_size) * pixel_size * 1.45)
	var lines: PackedStringArray = text.split("\n")
	var w: float = 0.0
	for ln in lines:
		w = maxf(w, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return Vector2(w * pixel_size, f.get_height(font_size) * float(lines.size()) * pixel_size)

## Largest font size <= `want` at which `text` fits inside `max_w` x `max_h` metres.
## Pass 0.0 for either bound to leave that axis unconstrained. Never returns below
## `floor_size` — a sign nobody can read is not an improvement over one that overhangs,
## so if the wording cannot be made to fit the caller should shorten it or widen the
## plate, and `tests/label_anchor_probe.gd` will keep saying so.
##
## Text metrics are very close to linear in font size, so this seeds from the ratio and
## then steps, rather than scanning 40 sizes.
static func fit_size(text: String, max_w: float, max_h: float, want: int,
		pixel_size: float = 0.01, floor_size: int = 6) -> int:
	var fs: int = maxi(floor_size, want)
	if max_w <= 0.0 and max_h <= 0.0:
		return fs
	var ext: Vector2 = extent(text, fs, pixel_size)
	if _fits(ext, max_w, max_h):
		return fs
	# Seed from the linear guess on whichever axis is the binding constraint.
	var scale: float = 1.0
	if max_w > 0.0 and ext.x > 0.0:
		scale = minf(scale, max_w / ext.x)
	if max_h > 0.0 and ext.y > 0.0:
		scale = minf(scale, max_h / ext.y)
	fs = clampi(int(floor(float(fs) * scale)), floor_size, want)
	# Walk down until it really fits (kerning is not perfectly linear), then try to
	# recover a size, so we never give away more than one step.
	while fs > floor_size and not _fits(extent(text, fs, pixel_size), max_w, max_h):
		fs -= 1
	while fs < want and _fits(extent(text, fs + 1, pixel_size), max_w, max_h):
		fs += 1
	return fs

static func _fits(ext: Vector2, max_w: float, max_h: float) -> bool:
	if max_w > 0.0 and ext.x > max_w:
		return false
	if max_h > 0.0 and ext.y > max_h:
		return false
	return true
