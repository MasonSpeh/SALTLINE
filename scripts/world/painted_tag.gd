extends Node3D
## A PAINTED equipment tag: stencilled letters lying ON a surface, not a sign floating
## near one. The s55 equipment numbers were bare Label3D quads at hand-typed offsets —
## crisp white text with a black outline hanging in the air near the vessel it named,
## which reads as UI, not as paint.
##
## Authored as a position plus the outward facing it was meant to read from. On the first
## physics frames it rays BACKWARD onto whatever it was painted on and lies flat against
## the REAL face, 8 mm proud, oriented to the measured normal — so a re-authored vessel
## carries its own paint with it, and the letters can never hang in the air (the probe
## rule: never trust an authored coordinate when the surface can be measured).
##
## The paint reading comes from three choices: `shaded` (paint is lit by the world, a
## floating label is not), no outline (a stencil has none), and alpha-cut prepass (a
## crisp masked edge instead of a glassy blend).

var text: String = ""
var face_dir: Vector3 = Vector3.FORWARD    ## outward normal the tag was authored to face
var tint: Color = Color(0.88, 0.86, 0.78)  ## weathered stencil white
var size_mm: float = 3.6                   ## pixel_size * 1000 — glyph scale on the surface

func _ready() -> void:
	_snap.call_deferred()

func _snap() -> void:
	# CSG colliders do not exist on the frame they enter the tree (see surface_snap.gd).
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var n: Vector3 = face_dir.normalized()
	# BOTH directions, behind first. The s55 Label3D quads were double-sided, so a facing
	# authored 180 degrees wrong read fine and nobody could tell — four of the eleven tags
	# proved to be flipped the moment a single-sided probe asked. The paint goes on
	# whichever face actually answers, and reads outward along that face's own normal.
	var hit: Dictionary = _cast(global_position + n * 0.05, -n)
	if hit.is_empty():
		hit = _cast(global_position - n * 0.05, n)
	var pos: Vector3 = global_position
	var nrm: Vector3 = n
	if hit.is_empty():
		# A finding, not a null: the tag was authored off its own equipment. Keep the
		# authored spot so the tag is at least findable, and say so out loud.
		push_warning("[painted_tag] '%s' found no surface within 2.5 m either side" % text)
	else:
		pos = hit["position"]
		nrm = (hit["normal"] as Vector3).normalized()
		if nrm.length_squared() < 0.5:
			nrm = n
	var l := Label3D.new()
	l.text = text
	l.font_size = 160
	l.pixel_size = size_mm / 1000.0
	l.modulate = tint
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	add_child(l)
	l.global_position = pos + nrm * 0.008
	# Label3D's readable face is its +Z side: aim +Z along the surface normal. On a near-
	# horizontal face (a deck stencil) world-up is degenerate as the up hint; use +X.
	var up: Vector3 = Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT
	l.global_transform.basis = Basis.looking_at(-nrm, up)

func _cast(from: Vector3, dir: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.5)
	q.collision_mask = 1
	q.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(q)
