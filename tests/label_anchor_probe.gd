extends Node
## Regression guard against the floating-label class of bug.
##
## Every Label3D on this rig is either stencil paint or a bolted placard, so there has
## to be something solid immediately behind its text face. This boots the real Main,
## walks every Label3D in the built world, samples a grid of points across the label's
## OWN glyph AABB, marches each sample backwards along the label's local -Z (the
## direction into whatever it is supposed to be painted on) and requires it to enter
## real geometry within BACKING_DEPTH.
##
## Two things this deliberately does NOT do, both learned the hard way:
##   - it does not raycast. Most rig dressing is non-colliding CSG and decorative mesh,
##     so a physics ray reports solid bulkheads as open air.
##   - it does not test world-space AABBs. The rig is full of rotated pipes and derrick
##     steel whose axis-aligned world bounds enclose many times the volume they occupy,
##     so a point hanging in open air lands "inside" a girder metres away. Containment
##     is tested in each mesh's OWN local space, which is an exact oriented-box test.
##
## Sampling the whole glyph box rather than just the label's origin is what catches the
## half-on-half-off case — a warning board whose right half lands on a bulkhead and
## whose left half hangs over open sea passes a centre-point test and fails this one.
##
## Run: godot --headless --path . res://tests/LabelAnchorProbe.tscn

const BACKING_DEPTH: float = 0.35   ## how far behind the glyphs we are willing to look
const STEP: float = 0.02            ## march resolution along the backing direction
const GRID: int = 3                 ## GRID x GRID sample points across the glyph box
const MIN_BACKED: float = 0.65      ## fraction of samples that must find backing

## --- FIT (the second half of this probe) -----------------------------------------
## Backing is necessary and not sufficient. A label can be perfectly backed and still be
## WRONG, because what is behind it is a 20 m bulkhead and the thing it is labelling is a
## 0.86 m red header plate the wording overhangs by 350 mm. The owner's words were "text
## spanning edge to edge / going over sign width"; a 3 x 3 backing grid cannot see it,
## because its outermost sample sits at 5/6 of the glyph box and a sign can overhang by a
## third before that sample leaves the plate.
##
## So: march back from the glyph CENTRE, take the first surface big enough to be a sign
## face, and require the whole glyph box to fit inside it. Paint applied straight onto a
## bulkhead finds the bulkhead and passes; paint applied onto a fixture's own name plate
## has to fit that plate.
const FIT_MARGIN: float = 0.004     ## slack, for glyph boxes that touch the plate edge
const FACE_MIN_W: float = 0.12      ## narrower than this is a bolt or a pipe, not a face
const FACE_MIN_H: float = 0.05

const SignFit = preload("res://scripts/world/sign_fit.gd")
const CELL: float = 3.0             ## broad-phase cell size
const BIG: float = 8.0              ## anything larger than this is tested against all
const MARGIN: float = 0.02          ## slack on each box, for coplanar paint
## Anything this large is the sky dome, the sea, or a fog volume — not a surface
## anybody paints a sign on. Leaving these in makes the whole test vacuous: the sky
## dome's AABB is 3200m on a side, so it "backs" every point in the world and every
## label passes no matter where it hangs. The rig's own largest slab is ~60m, which
## is real backing for deck paint and stays in.
const ENV_SCALE: float = 150.0

const LOG_PATH: String = "/tmp/label_anchor_probe.txt"

## Floating labels this probe found that live in a file the current batch does not own
## (scripts/world/wet_deck_detail.gd). They are reported every run but do not fail the
## gate, so the guard still catches anything NEW. Delete an entry as soon as it is
## fixed — the probe complains if a quarantined label turns out to be backed, so this
## list cannot quietly rot into a permanent excuse.
const QUARANTINE: Array[String] = [
	# All five former wet_deck_detail.gd hand-offs are now backed by bolted sign plates
	# (see _signplate) and are asserted for real. Add an entry back only for a genuinely
	# un-fixable hand-off in a file this batch does not own.
]

var _xforms: Array[Transform3D] = []
var _fwd: Array[Transform3D] = []
var _local: Array[AABB] = []
var _cells: Dictionary = {}         ## Vector3i -> PackedInt32Array of geometry indices
var _big: PackedInt32Array = PackedInt32Array()
var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()
var _debug: bool = false
var _names: Array[String] = []

## Every line goes to stdout AND to a file, rewritten after each line: headless runs
## lose buffered stdout when the tree quits.
func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	# The rig streams its dressing over several frames; let all of it land first.
	await get_tree().create_timer(5.0).timeout

	var labels: Array[Label3D] = []
	_collect(main, labels)
	_say("LABEL ANCHOR PROBE: %d labels, %d geometry nodes" % [labels.size(), _local.size()])

	var focus: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--label="):
			focus = a.substr(8)

	var unbacked: Array[String] = []
	var known: Array[String] = []
	var fixed: Array[String] = []
	for l in labels:
		if focus != "" and l.text.contains(focus):
			_debug = true
			_say("DEBUG %s @ %s  back=%s" % [l.text, str(l.global_position.snappedf(0.01)),
				str((-l.global_transform.basis.z.normalized()).snappedf(0.01))])
		var frac: float = _backed_fraction(l)
		_debug = false
		var quarantined: bool = QUARANTINE.has(l.text)
		if frac < MIN_BACKED:
			var entry: String = "%s  \"%s\" @ %s  (%d%% of its glyph box backed)" \
				% [l.name, l.text.replace("\n", " "), str(l.global_position.snappedf(0.01)),
					int(round(frac * 100.0))]
			if quarantined:
				known.append(entry)
			else:
				unbacked.append(entry)
		elif quarantined:
			fixed.append(l.text)

	for k in known:
		_say("KNOWN (hand-off, wet_deck_detail.gd) floating label: " + k)
	for f in fixed:
		_say("NOTE  quarantined label \"%s\" is backed now — drop it from QUARANTINE" % f)
	for u in unbacked:
		_say("FAIL  floating label: " + u)
	if unbacked.is_empty():
		_say("PASS  every Label3D outside the quarantine has geometry within %.2fm behind its text face"
			% BACKING_DEPTH)
	else:
		failures = unbacked.size()

	_metrics_agree(labels)
	_fit_audit(labels)
	_say("---")
	_say("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## GeometryInstance3D, not MeshInstance3D: the rig's PRIMARY structure — decks,
## pontoons, bulkheads, caissons — is built from CSGBox3D. Collecting only
## MeshInstance3D sees just the decorative detail layer and reports solid steel
## bulkheads as open air.
func _collect(n: Node, labels: Array[Label3D]) -> void:
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		# mesh_batcher.gd's welded chunks are a DUPLICATE of geometry collected below from
		# the source nodes (which the batcher deliberately leaves in the tree). Indexing
		# them too would put one filled 20m AABB behind every label in the bucket and this
		# probe would pass on geometry that isn't there.
		if cur.is_in_group("render_batch"):
			continue
		for c in cur.get_children():
			stack.append(c)
		if cur is Label3D:
			labels.append(cur as Label3D)
			continue
		var gi := cur as GeometryInstance3D
		if gi == null or not gi.is_visible_in_tree():
			continue
		var box: AABB = gi.get_aabb()
		if box.size == Vector3.ZERO:
			continue
		if box.size.x > ENV_SCALE or box.size.y > ENV_SCALE or box.size.z > ENV_SCALE:
			continue   # sky dome / sea / fog volume — see ENV_SCALE
		var idx: int = _local.size()
		_local.append(box)
		_names.append(String(gi.get_path()))
		_xforms.append(gi.global_transform.affine_inverse())
		_fwd.append(gi.global_transform)
		_index(idx, gi.global_transform * box)

func _index(idx: int, world: AABB) -> void:
	if world.size.x > BIG or world.size.y > BIG or world.size.z > BIG:
		_big.append(idx)
		return
	var lo: Vector3 = world.position / CELL
	var hi: Vector3 = (world.position + world.size) / CELL
	for x in range(floori(lo.x), floori(hi.x) + 1):
		for y in range(floori(lo.y), floori(hi.y) + 1):
			for z in range(floori(lo.z), floori(hi.z) + 1):
				var key := Vector3i(x, y, z)
				if not _cells.has(key):
					_cells[key] = PackedInt32Array()
				var arr: PackedInt32Array = _cells[key]
				arr.append(idx)
				_cells[key] = arr

## Fraction of the label's glyph box that has something solid behind it.
func _backed_fraction(l: Label3D) -> float:
	var box: AABB = l.get_aabb()
	if box.size == Vector3.ZERO:
		return 1.0   # nothing rendered; nothing to float
	var xf: Transform3D = l.global_transform
	var back: Vector3 = -xf.basis.z.normalized()
	var hits: int = 0
	var total: int = 0
	for i in range(GRID):
		for j in range(GRID):
			var lp := Vector3(
				box.position.x + box.size.x * (float(i) + 0.5) / float(GRID),
				box.position.y + box.size.y * (float(j) + 0.5) / float(GRID),
				0.0)
			total += 1
			if _march(xf * lp, back):
				hits += 1
	return float(hits) / float(total)

## `sign_fit.gd` is what every signage helper sizes its plate from, so if it ever drifts
## from what the renderer actually draws, every plate on the rig is wrong and nothing
## errors. Assert the agreement against `Label3D.get_aabb()` on the LIVE labels — real
## wording, real font sizes — not on a synthetic sample.
func _metrics_agree(labels: Array[Label3D]) -> void:
	var worst: float = 0.0
	var worst_text: String = ""
	var checked: int = 0
	for l in labels:
		var real: AABB = l.get_aabb()
		if real.size == Vector3.ZERO:
			continue
		var est: Vector2 = SignFit.extent(l.text, l.font_size, l.pixel_size)
		checked += 1
		var d: float = maxf(absf(est.x - real.size.x), absf(est.y - real.size.y))
		if d > worst:
			worst = d
			worst_text = l.text.replace("\n", " ")
	if checked == 0:
		_say("FAIL  SignFit.extent could not be checked — no label rendered any glyphs")
		failures += 1
	elif worst > 0.001:
		_say("FAIL  SignFit.extent disagrees with Label3D.get_aabb by %.4fm (worst: \"%s\") over %d labels"
			% [worst, worst_text, checked])
		failures += 1
	else:
		_say("PASS  SignFit.extent matches Label3D.get_aabb on all %d rendered labels (worst %.5fm)"
			% [checked, worst])

## THE GATE: every label whose helper knows the surface it is painted on declares that
## surface as a `sign_face` meta (the auto-grown plate of `_sign`/`_signplate`/`_placard`,
## or the `fit` box passed to `_plabel`/`_paint`/`_label`). The wording must fit inside it.
##
## This is an EXACT test against a number the builder wrote down, not a guess about which
## of the several hundred pieces of geometry behind a label is "the sign". An earlier
## version of this probe ray-marched for the sign face and could not tell a 0.86 m name
## plate from a 0.9 m paint scuff on the deck plating underneath a lane marking — it
## flagged both. The ray-march survives below as a REPORT, because it is the only thing
## that can find a label whose author never declared a face at all.
const DECLARED_MIN: int = 25   ## below this the gate has gone vacuous, not clean

func _fit_audit(labels: Array[Label3D]) -> void:
	var over: Array[String] = []
	var declared: int = 0
	var undeclared: Array[Label3D] = []
	for l in labels:
		if not l.has_meta("sign_face"):
			undeclared.append(l)
			continue
		declared += 1
		var face: Vector2 = l.get_meta("sign_face")
		var g: AABB = l.get_aabb()
		if (face.x > 0.0 and g.size.x > face.x + FIT_MARGIN) \
				or (face.y > 0.0 and g.size.y > face.y + FIT_MARGIN):
			over.append("\"%s\" fs%d @ %s  text %.3f x %.3f declared face %.3f x %.3f  -> over by %.3f w / %.3f h"
				% [l.text.replace("\n", " "), l.font_size,
					str(l.global_position.snappedf(0.01)), g.size.x, g.size.y,
					face.x, face.y, g.size.x - face.x, g.size.y - face.y])
	_say("LABEL FIT: %d labels, %d declare a sign face, %d are paint on open surface"
		% [labels.size(), declared, undeclared.size()])
	if declared < DECLARED_MIN:
		_say("FAIL  only %d labels declared a sign face (expected >= %d) — the fit gate is vacuous"
			% [declared, DECLARED_MIN])
		failures += 1
	for o in over:
		_say("FAIL  overflowing sign: " + o)
	if over.is_empty():
		_say("PASS  all %d labels with a declared sign face fit inside it" % declared)
	else:
		failures += over.size()
	_fit_report(undeclared)

## Report-only sweep over the labels that declared nothing: ray-march for the surface
## behind them and print any whose wording runs off it. These are paint on decks, beams
## and bulkheads, where "the panel" is a judgement call — so this informs rather than
## gates. Anything listed here is a candidate for a `fit` argument.
func _fit_report(labels: Array[Label3D]) -> void:
	var lines: Array[String] = []
	for l in labels:
		var r: Dictionary = _fit(l)
		if r.is_empty():
			continue
		var ow: float = r["over_w"]
		var oh: float = r["over_h"]
		if ow > 0.02 or oh > 0.02:
			var face: Rect2 = r["face"]
			var glyph: Vector2 = r["glyph"]
			lines.append("      \"%s\" fs%d @ %s  text %.3f x %.3f on %.3f x %.3f  over %.3f w / %.3f h"
				% [l.text.replace("\n", " "), l.font_size,
					str(l.global_position.snappedf(0.01)),
					glyph.x, glyph.y, face.size.x, face.size.y, ow, oh])
	_say("NOTE  %d undeclared labels run past the surface the probe found behind them:" % lines.size())
	for ln in lines:
		_say(ln)

## ---------------------------------------------------------------- fit
##
## Returns {} when the label has no identifiable sign face behind it (paint on nothing,
## or on something too small to judge — the backing test above owns that case). Otherwise
## {face, glyph, over_w, over_h, name} with everything measured in the LABEL's own frame,
## in metres. `over_w`/`over_h` are how far the wording sticks out past the face; <= 0 is
## a fit.
func _fit(l: Label3D) -> Dictionary:
	var box: AABB = l.get_aabb()
	if box.size == Vector3.ZERO:
		return {}
	var xf: Transform3D = l.global_transform
	var inv: Transform3D = xf.affine_inverse()
	var back: Vector3 = -xf.basis.z.normalized()
	var centre: Vector3 = xf * Vector3(box.position.x + box.size.x * 0.5,
		box.position.y + box.size.y * 0.5, 0.0)
	var t: float = 0.0
	while t <= BACKING_DEPTH:
		var p: Vector3 = centre + back * t
		# LARGEST face at the FIRST depth that has one. Not simply the first hit: deck
		# stencils are laid on the plating a few millimetres above scuff patches and
		# chevrons, so "first hit" picks a 0.9 m paint smudge and reports a 2.3 m lane
		# marking as overflowing it. Taking the largest at the same depth picks the
		# plating. It does NOT collapse into "the biggest thing behind the label",
		# because a fixture's own name plate stands proud of the bulkhead it is bolted
		# to and is therefore hit at a strictly earlier depth.
		var best: int = -1
		var best_area: float = 0.0
		for idx in _at(p):
			var f: Rect2 = _face_in(idx, inv)
			if f.size.x < FACE_MIN_W or f.size.y < FACE_MIN_H:
				continue
			var area: float = f.size.x * f.size.y
			if area > best_area:
				best_area = area
				best = idx
		if best >= 0:
			var bf: Rect2 = _face_in(best, inv)
			var gx0: float = box.position.x
			var gx1: float = box.position.x + box.size.x
			var gy0: float = box.position.y
			var gy1: float = box.position.y + box.size.y
			return {"face": bf, "glyph": Vector2(box.size.x, box.size.y),
				"over_w": maxf(bf.position.x - gx0, gx1 - (bf.position.x + bf.size.x)),
				"over_h": maxf(bf.position.y - gy0, gy1 - (bf.position.y + bf.size.y)),
				"name": _names[best]}
		t += STEP
	return {}

## The in-plane extent of geometry `idx`, expressed in the label's own frame. Projects the
## eight corners of the node's LOCAL box, so a plate rotated relative to its label is
## measured honestly rather than through a world-axis-aligned box (see the header note on
## why this probe never uses world AABBs).
func _face_in(idx: int, label_inv: Transform3D) -> Rect2:
	var b: AABB = _local[idx]
	var to_label: Transform3D = label_inv * _fwd[idx]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(8):
		var c: Vector3 = to_label * b.get_endpoint(i)
		lo.x = minf(lo.x, c.x)
		lo.y = minf(lo.y, c.y)
		hi.x = maxf(hi.x, c.x)
		hi.y = maxf(hi.y, c.y)
	return Rect2(lo, hi - lo)

## Every indexed geometry containing world point `p`.
func _at(p: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	var key := Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
	if _cells.has(key):
		for idx in (_cells[key] as PackedInt32Array):
			if _local[idx].grow(MARGIN).has_point(_xforms[idx] * p):
				out.append(idx)
	for idx2 in _big:
		if _local[idx2].grow(MARGIN).has_point(_xforms[idx2] * p):
			out.append(idx2)
	return out

func _march(from: Vector3, dir: Vector3) -> bool:
	var t: float = 0.0
	while t <= BACKING_DEPTH:
		if _solid(from + dir * t):
			return true
		t += STEP
	return false

func _solid(p: Vector3) -> bool:
	var key := Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
	if _cells.has(key):
		for idx in (_cells[key] as PackedInt32Array):
			if _local[idx].grow(MARGIN).has_point(_xforms[idx] * p):
				if _debug:
					_say("   backed at %s by %s" % [str(p.snappedf(0.01)), _names[idx]])
				return true
	for idx2 in _big:
		if _local[idx2].grow(MARGIN).has_point(_xforms[idx2] * p):
			if _debug:
				_say("   backed at %s by BIG %s size=%s" % [str(p.snappedf(0.01)),
					_names[idx2], str(_local[idx2].size.snappedf(0.1))])
			return true
	return false
