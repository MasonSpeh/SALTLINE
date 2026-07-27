extends SceneTree
## Which items still have NO distinctive look? Headless, no rendering needed.
##
## item_visual.gd dispatches on item id and ends in a `_:` arm that draws ONE box of
## 0.28 x 0.30 x 0.28 in the generic takeable colour. In the pack that reads as an
## anonymous yellow cube, and once the inventory started showing items instead of naming
## them (2026-07-26) every one of those became indistinguishable from every other.
##
## This finds them by their signature rather than by maintaining a hand-written list that
## would go stale the moment someone adds an item. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/item_visual_audit.gd
##
## A species fish legitimately builds as ONE MeshInstance3D (the generated GLB is a single
## mesh), so "one mesh" alone is not the test — it has to be one box of exactly that size.

const FALLBACK_SIZE := Vector3(0.28, 0.3, 0.28)

func _init() -> void:
	var IV := preload("res://scripts/world/item_visual.gd")
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var plain: Array = []
	var total_items: int = 0
	for id in d.keys():
		if typeof(d[id]) != TYPE_DICTIONARY:
			continue
		total_items += 1
		var n: Node3D = IV.build(id)
		if n == null:
			plain.append(id)
			continue
		var parts: int = 0
		var boxes: Array = []
		var stack: Array = [n]
		while not stack.is_empty():
			var x: Node = stack.pop_back()
			if x is CSGBox3D:
				parts += 1
				boxes.append((x as CSGBox3D).size)
			elif x is MeshInstance3D:
				parts += 1
				if (x as MeshInstance3D).mesh is BoxMesh:
					boxes.append(((x as MeshInstance3D).mesh as BoxMesh).size)
			elif x is CSGShape3D:
				parts += 1
			for c in x.get_children():
				stack.append(c)
		if parts == 1 and boxes.size() == 1 and (boxes[0] as Vector3).is_equal_approx(FALLBACK_SIZE):
			plain.append(id)
		n.free()
	print("items checked: %d" % total_items)
	print("STILL THE GENERIC BOX (%d):" % plain.size())
	for p in plain:
		print("   %-24s %s" % [p, d[p].get("name", "")])
	quit(1 if plain.size() > 0 else 0)
