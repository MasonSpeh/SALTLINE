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
