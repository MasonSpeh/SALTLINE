extends Node3D
## Measures the generated hammerhead's attached bounds in HOST-local space, so the
## procedural armour / eye-stalk / tooth overlays in shark.gd can be placed against the
## real mesh instead of guessed numbers.

const ANIM := preload("res://scripts/world/creature_anim.gd")
const MODEL_PATH := "res://assets/models/fauna/ultra_hammerhead/ultra_hammerhead.glb"

func _ready() -> void:
	var host := Node3D.new()
	add_child(host)
	var gen: Dictionary = ANIM.attach(host, MODEL_PATH, 5.0, ANIM.Mode.UNDULATE, 0.09, 1.1)
	if gen.is_empty():
		print("MISSING MODEL")
		get_tree().quit()
		return
	var pts: PackedVector3Array = PackedVector3Array()
	for n in host.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D = host.global_transform.affine_inverse() * mi.global_transform
		for s in range(mi.mesh.get_surface_count()):
			var arrs: Array = mi.mesh.surface_get_arrays(s)
			for v in (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(xf * v)
	print("verts=", pts.size())
	# --- head region: where are the existing horns, and how wide is the cephalofoil?
	print("--- head slices (z bucket 0.1) x-halfwidth / y range / top-of-body ---")
	var b: Dictionary = {}
	for p in pts:
		if p.z > -1.4:
			continue
		var k: int = int(floor(p.z * 10.0))
		var e: Array = b.get(k, [0.0, -9.0, 9.0])
		e[0] = maxf(e[0], absf(p.x))
		e[1] = maxf(e[1], p.y)
		e[2] = minf(e[2], p.y)
		b[k] = e
	var ks: Array = b.keys()
	ks.sort()
	for k in ks:
		print("z %+.2f  halfwidth %.3f  y %+.3f .. %+.3f" % [k / 10.0, b[k][0], b[k][2], b[k][1]])
	# --- the horns: everything above y 0.20 forward of z -1.6
	print("--- horn cloud (y>0.20, z<-1.6) ---")
	var hx := [9.0, -9.0]
	var hy := [9.0, -9.0]
	var hz := [9.0, -9.0]
	var n_h: int = 0
	for p in pts:
		if p.y > 0.20 and p.z < -1.6:
			n_h += 1
			hx[0] = minf(hx[0], p.x); hx[1] = maxf(hx[1], p.x)
			hy[0] = minf(hy[0], p.y); hy[1] = maxf(hy[1], p.y)
			hz[0] = minf(hz[0], p.z); hz[1] = maxf(hz[1], p.z)
	print("n=%d  x %+.3f..%+.3f  y %+.3f..%+.3f  z %+.3f..%+.3f" % [n_h, hx[0], hx[1], hy[0], hy[1], hz[0], hz[1]])
	# --- dorsal top line, coarse: highest y on the CENTRE line (|x|<0.12) per z
	print("--- spine line (|x|<0.15) ---")
	var sp: Dictionary = {}
	for p in pts:
		if absf(p.x) > 0.15:
			continue
		var k: int = int(round(p.z * 5.0))
		sp[k] = maxf(sp.get(k, -9.0), p.y)
	var sk: Array = sp.keys()
	sk.sort()
	for k in sk:
		print("z %+.2f  spine_top %+.3f" % [k / 5.0, sp[k]])
	# --- flank line: at each z, the most-lateral vertex and its y
	print("--- flank line (widest |x| per z, with its y) ---")
	var fl: Dictionary = {}
	for p in pts:
		var k: int = int(round(p.z * 5.0))
		var e: Array = fl.get(k, [0.0, 0.0])
		if absf(p.x) > e[0]:
			e[0] = absf(p.x); e[1] = p.y
			fl[k] = e
	var fk: Array = fl.keys()
	fk.sort()
	for k in fk:
		print("z %+.2f  |x| %.3f  y %+.3f" % [k / 5.0, fl[k][0], fl[k][1]])
	# --- belly line: lowest y per z on the centre line
	print("--- belly line (|x|<0.25) ---")
	var bl: Dictionary = {}
	for p in pts:
		if absf(p.x) > 0.25:
			continue
		var k: int = int(round(p.z * 5.0))
		bl[k] = minf(bl.get(k, 9.0), p.y)
	var bk: Array = bl.keys()
	bk.sort()
	for k in bk:
		print("z %+.2f  belly %+.3f" % [k / 5.0, bl[k]])
	get_tree().quit()
