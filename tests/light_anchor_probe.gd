extends Node
## Regression guard against the floating-light class of bug.
##
## Every lamp on this rig is a physical fixture — a caged worklight, a bulkhead dome, a
## floodlight head, a lantern on a table — so every OmniLight3D/SpotLight3D that stands
## for one has to have visible geometry right behind or above it. This boots the real
## Main, walks every light in the built world, and requires real geometry within RADIUS
## of the light's position. A light hanging in open air fails.
##
## Modelled on LabelAnchorProbe, and for the same two hard-won reasons it:
##   - does not raycast (most fixture dressing is non-colliding CSG / decorative mesh).
##   - tests each mesh's OWN oriented local box, not its world-space AABB (rotated pipes
##     and derrick steel have huge axis-aligned bounds that would "back" empty air).
## Distance is measured to the closest point of each oriented box, transformed back to
## world space, so non-uniform prop scales are handled exactly.
##
## Exemptions (documented, principled — same spirit as LabelAnchorProbe's ENV/QUARANTINE):
##   - DirectionalLight3D (sun/moon/storm flash) — not a fixture; excluded by type.
##   - lights in group "spill_lights" — daylight / window-shaft simulation. These stand
##     for light coming THROUGH an opening, not a lamp; their anchor is the window, and
##     they are deliberately offset into the room. Excluded like the sky dome is.
##   - lights with energy <= 0 or hidden — an unlit fixture (a carried lantern nobody is
##     holding, a beacon mid-blink) has nothing to anchor this frame.
##
## Run: godot --headless --path . res://tests/LightAnchorProbe.tscn

const RADIUS: float = 0.45          ## a fixture light must sit within this of real geometry
const ENV_SCALE: float = 150.0      ## sky dome / sea / fog — too big to be a fixture (see label probe)
const CELL: float = 3.0             ## broad-phase cell size
const BIG: float = 8.0              ## boxes larger than this are tested against every light
const MARGIN: float = 0.02

const EXEMPT_GROUPS: Array[String] = ["spill_lights"]

## Hand-off floaters that live in a file this batch does not own. Match by node-path
## substring. Reported every run but do not fail the gate; the probe complains if a
## quarantined light turns out to be backed, so this list cannot quietly rot.
const QUARANTINE: Array[String] = []

const LOG_PATH: String = "/tmp/light_anchor_probe.txt"

var _fwd: Array[Transform3D] = []
var _inv: Array[Transform3D] = []
var _local: Array[AABB] = []
var _names: Array[String] = []
var _cells: Dictionary = {}
var _big: PackedInt32Array = PackedInt32Array()
var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()

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
	await get_tree().create_timer(5.0).timeout

	var lights: Array[Light3D] = []
	_collect(main, lights)
	_say("LIGHT ANCHOR PROBE: %d fixture lights, %d geometry nodes" % [lights.size(), _local.size()])

	var unbacked: Array[String] = []
	var known: Array[String] = []
	var fixed: Array[String] = []
	for l in lights:
		var path: String = String(l.get_path())
		var d: float = _min_dist(l.global_position)
		var quarantined: bool = _is_quarantined(path)
		if d > RADIUS:
			var entry: String = "%s (%s) @ %s  nearest geometry %.2fm away" % [
				l.name, l.get_class(), str(l.global_position.snappedf(0.01)), d]
			if quarantined:
				known.append(entry)
			else:
				unbacked.append(entry)
		elif quarantined:
			fixed.append(path)

	for k in known:
		_say("KNOWN (hand-off, unowned file) floating light: " + k)
	for fx in fixed:
		_say("NOTE  quarantined light %s is backed now — drop it from QUARANTINE" % fx)
	for u in unbacked:
		_say("FAIL  floating light: " + u)
	if unbacked.is_empty():
		_say("PASS  every fixture light has geometry within %.2fm" % RADIUS)
	else:
		failures = unbacked.size()
	_say("---")
	_say("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _is_quarantined(path: String) -> bool:
	for q in QUARANTINE:
		if path.contains(q):
			return true
	return false

func _exempt(l: Light3D) -> bool:
	if not l.is_visible_in_tree():
		return true
	if l.light_energy <= 0.0:
		return true
	for g in EXEMPT_GROUPS:
		if l.is_in_group(g):
			return true
	return false

func _collect(n: Node, lights: Array[Light3D]) -> void:
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		# DirectionalLight is not a fixture; only Omni/Spot stand for lamps.
		if cur is OmniLight3D or cur is SpotLight3D:
			var lt := cur as Light3D
			if not _exempt(lt):
				lights.append(lt)
			continue
		var gi := cur as GeometryInstance3D
		if gi == null or not gi.is_visible_in_tree():
			continue
		var box: AABB = gi.get_aabb()
		if box.size == Vector3.ZERO:
			continue
		if box.size.x > ENV_SCALE or box.size.y > ENV_SCALE or box.size.z > ENV_SCALE:
			continue
		var idx: int = _local.size()
		_local.append(box)
		_names.append(String(gi.get_path()))
		_fwd.append(gi.global_transform)
		_inv.append(gi.global_transform.affine_inverse())
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

func _min_dist(p: Vector3) -> float:
	var best: float = INF
	var r: int = int(ceil(RADIUS / CELL)) + 1
	var base := Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
	var seen: Dictionary = {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var key := base + Vector3i(dx, dy, dz)
				if not _cells.has(key):
					continue
				for idx in (_cells[key] as PackedInt32Array):
					if seen.has(idx):
						continue
					seen[idx] = true
					best = minf(best, _dist_to_box(idx, p))
	for idx2 in _big:
		best = minf(best, _dist_to_box(idx2, p))
	return best

func _dist_to_box(idx: int, p: Vector3) -> float:
	var lp: Vector3 = _inv[idx] * p
	var b: AABB = _local[idx].grow(MARGIN)
	var mn: Vector3 = b.position
	var mx: Vector3 = b.position + b.size
	var cl := Vector3(clampf(lp.x, mn.x, mx.x), clampf(lp.y, mn.y, mx.y), clampf(lp.z, mn.z, mx.z))
	return p.distance_to(_fwd[idx] * cl)
