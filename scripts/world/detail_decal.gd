class_name DetailDecal extends RefCounted
## Off-surface "sticker" quads — the fine-surface-detail replacement for Godot's
## Decal node, which does nothing under the gl_compatibility renderer. A thin
## QuadMesh laid ~1.5cm proud of a wall/deck, facing along a normal, carrying a
## MatLib grime/stain/cutout material. The same physical-offset trick the scuff
## strips and spill stains already use to avoid z-fighting.

## Lay a sticker at `pos`, its face pointing along `normal`. `size` is metres,
## `roll` spins it in-plane, `offset` lifts it off the host surface.
static func sticker(parent: Node3D, mat: Material, pos: Vector3, normal: Vector3,
		size: Vector2, roll: float = 0.0, offset: float = 0.015) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var n: Vector3 = normal.normalized()
	mi.global_position = pos + n * offset
	# QuadMesh faces +Z; look_at points -Z at the target, so aim at a point BEHIND
	# to leave +Z along the normal. Pick a non-parallel up for floor/ceiling stickers.
	var up: Vector3 = Vector3.UP if absf(n.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	mi.look_at(mi.global_position - n, up)
	if roll != 0.0:
		mi.rotate(n, roll)
	return mi
