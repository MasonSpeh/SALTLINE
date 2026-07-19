extends Node
## FLOAT HUNT — finds VisualInstance3D geometry hanging in mid-air over the open deck.
##
## Run: godot --headless --path . res://tests/FloatHunt.tscn
##
## Reports every drawn mesh whose world-AABB centre sits inside the search box AND which
## has no visual surface within DROP metres below its underside — i.e. nothing is holding
## it up. Prints the full parent chain, because that is what names the culprit builder.
##
## Unlike placement_probe.gd this does NOT filter by size, group or "managed" status: the
## thing we are hunting is large structural decoration, exactly what that probe exempts.

const SUPPORT := preload("res://scripts/world/support_index.gd")

const OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/87d5de70-f27c-48d3-bab9-cb1e9a8f822d/scratchpad"

## Search box (world space) — the air above the open deck south of the bunkhouse.
const BX0 :=   6.0
const BX1 :=  31.0
const BY0 :=   1.6
const BY1 :=   7.0
const BZ0 := -27.0
const BZ1 :=   1.0

const DROP: float = 0.12     ## no geometry within this far below the underside => floating
const SPAN_CAP: float = 70.0

func _ready() -> void:
	print("[hunt] booting Main")
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[hunt] main added, waiting for world build (slow)")
	for i in range(30):
		await get_tree().create_timer(1.0).timeout
		print("[hunt] t=%ds" % (i + 1))
	for i in range(20):
		await get_tree().physics_frame
	print("[hunt] settled, indexing")

	var index = SUPPORT.new()
	index.build(main)
	print("[hunt] surfaces indexed: ", index.surface_count())

	var all: Array = _geometry(main)
	print("[hunt] geometry nodes walked: ", all.size())

	var hits: Array = []
	var in_box: int = 0
	for n in all:
		var vi := n as VisualInstance3D
		if vi == null or not is_instance_valid(vi) or not vi.is_inside_tree():
			continue
		var local: AABB = vi.get_aabb()
		if local.size == Vector3.ZERO:
			continue
		var a: AABB = vi.global_transform * local
		if a.size == Vector3.ZERO:
			continue
		if a.size.x > SPAN_CAP or a.size.z > SPAN_CAP:
			continue
		var c: Vector3 = a.get_center()
		if c.x < BX0 or c.x > BX1 or c.y < BY0 or c.y > BY1 or c.z < BZ0 or c.z > BZ1:
			continue
		in_box += 1
		# Support: highest visual top at or just below this thing's underside, ignoring
		# its own subtree and its siblings under the same immediate prop parent.
		var top: float = index.support_top(a, vi, 0.05)
		var gap: float = INF if top == -INF else a.position.y - top
		if gap <= DROP:
			continue
		var vol: float = a.size.x * a.size.y * a.size.z
		hits.append([vol, "%-26s size %5.2fx%5.2fx%5.2f  ctr %s  base_y %6.2f  gap %s\n        chain: %s" % [
			vi.name, a.size.x, a.size.y, a.size.z, _v(c), a.position.y,
			("none below" if top == -INF else "%.2f (top %.2f)" % [gap, top]),
			_chain(vi, main)]])

	print("[hunt] geometry with centre in search box: ", in_box)
	hits.sort_custom(func(x, y): return x[0] > y[0])
	print("=== FLOATING GEOMETRY IN BOX: ", hits.size(), " (biggest first) ===")
	for h in hits.slice(0, 60):
		print("  vol %8.2f  %s" % [h[0], h[1]])
	print("[hunt] done")
	get_tree().quit(0)

func _geometry(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_in_group("player") or n.is_in_group("floating_debris") \
				or n.is_in_group("gyre_streaks") or n.is_in_group("lit_flares"):
			continue
		var s: Script = n.get_script() as Script
		var skip: bool = false
		if s != null:
			for frag in SUPPORT.SKIP_SCRIPTS:
				if s.resource_path.ends_with(frag):
					skip = true
					break
		if skip:
			continue
		for c in n.get_children():
			stack.append(c)
		if SUPPORT.is_geometry(n):
			out.append(n)
	return out

func _chain(n: Node, root: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var cur: Node = n
	var guard: int = 0
	while cur != null and guard < 40:
		parts.append(cur.name)
		if cur == root:
			break
		cur = cur.get_parent()
		guard += 1
	parts.reverse()
	return "/".join(parts)

func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
