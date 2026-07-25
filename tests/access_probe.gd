extends Node
## ACCESS PROBE — physics ground truth for the crane ladder hatch, the way down off the
## machinery deck. The deck used to be one solid 7x7 plate with the upper mast ladder
## topping out INSIDE its footprint, so there was no opening: you could climb up (climbing
## runs with world collision off) and then had no way back down but a 16 m drop.
##
## USE RAYS, NOT SHAPE QUERIES. Every structural box here is a CSGBox3D, and CSG collision
## is baked to a ConcavePolygonShape3D — a one-sided trimesh. `intersect_shape` against a
## trimesh does not reliably report containment, so an earlier version of this probe called
## the deck "not solid" in three places out of four and looked like a catastrophic bug.
## `intersect_ray` handles trimesh correctly. Do not reintroduce shape queries here.
##
## The machine-shop roof ladder's blockers (cable tray, conduit) are NON-COLLIDING dressing
## and are therefore invisible to physics entirely — that fix is verified geometrically off
## the sonar scan (AABB overlap against the climb corridor), not here.
##
## Run headless: godot --headless --path . res://tests/access_probe.tscn

const SETTLE_SEC: float = 5.0
## Hatch cut in the machinery deck, mirroring rig_builder's CRANE_HATCH_* constants.
const HX0: float = -0.95
const HX1: float = 0.15
const HZ0: float = -14.9
const HZ1: float = -13.4
const PLATE_TOP: float = 34.15

var _fails: int = 0
var _t: float = 0.0
var _ran: bool = false

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	add_child(packed.instantiate())

func _process(delta: float) -> void:
	if _ran:
		return
	_t += delta
	if _t < SETTLE_SEC:
		return
	_ran = true
	_run()
	print("\n[access_probe] FAILURES: %d" % _fails)
	get_tree().quit()

## Height of the first surface under (x,z), or NAN if the column is empty down to y30.
func _floor_at(x: float, z: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 35.4, z), Vector3(x, 30.0, z))
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s %s" % [label, detail])

func _run() -> void:
	print("\n=== CRANE machinery deck — the ladder hatch is a real hole ===")
	# Inside the hatch but CLEAR OF THE LADDER (the ladder's own collider legitimately fills
	# x -0.7..0.0, z -14.175..-13.825 and tops out at the plate line).
	for p in [Vector2(-0.80, -14.60), Vector2(-0.80, -13.70), Vector2(0.00, -14.60),
			Vector2(-0.55, -14.65)]:
		var y: float = _floor_at(p.x, p.y)
		_check("hatch open at (%.2f, %.2f)" % [p.x, p.y], is_nan(y),
			"found a surface at y%.2f" % y if not is_nan(y) else "")
	# The ladder must still be there, in the hole, to climb down.
	var yl: float = _floor_at(-0.40, -14.00)
	_check("ladder is present inside the hatch", not is_nan(yl) and absf(yl - PLATE_TOP) < 0.2,
		"ray under the ladder line found y%.2f" % yl)
	# ...and the plate all round it must still carry you.
	# NEVER sample a strip's exact CENTRE LINE. CSG boxes are triangulated, and a ray fired
	# straight down the middle of one can slip through the seam where the tessellation splits:
	# a 0.1 m sweep across the south strip returned solid 34.15 at every step except exactly
	# z -16.20, its centre. That is a degenerate ray-vs-trimesh hit, not a hole — but it will
	# read as "deck cut away" and send you hunting a bug that isn't there.
	for p in [Vector2(-1.25, -14.15), Vector2(-0.40, -16.05), Vector2(-0.40, -11.60),
			Vector2(-1.25, -11.00), Vector2(-1.25, -16.80)]:
		var y2: float = _floor_at(p.x, p.y)
		_check("plate solid at (%.2f, %.2f)" % [p.x, p.y],
			not is_nan(y2) and y2 >= PLATE_TOP - 0.05,
			"got y%.2f" % y2 if not is_nan(y2) else "NOTHING THERE — deck cut away")
	# You have to be able to stand beside the opening to get onto the rungs.
	var ys: float = _floor_at(0.60, -14.15)
	_check("standing room on the hatch's east lip", not is_nan(ys),
		"nothing to stand on at (0.60, -14.15)")

	print("\n=== the upper mast ladder head lands in the opening ===")
	var lad: Node3D = _find_ladder("Mast Ladder — Upper")
	_check("upper mast ladder exists", lad != null)
	if lad != null:
		var lp: Vector3 = lad.global_position
		var inside: bool = lp.x > HX0 and lp.x < HX1 and lp.z > HZ0 and lp.z < HZ1
		_check("ladder axis inside the hatch footprint", inside, "at %s" % str(lp.snappedf(0.01)))
		_check("ladder reaches the plate line",
			absf(lp.y + lad.get("height") - PLATE_TOP) < 0.25,
			"top at y%.2f, plate at %.2f" % [lp.y + float(lad.get("height")), PLATE_TOP])

func _find_ladder(name_: String) -> Node3D:
	for n in get_tree().root.find_children("*", "StaticBody3D", true, false):
		var dn: Variant = n.get("display_name")
		if dn != null and String(dn) == name_:
			return n as Node3D
	return null
