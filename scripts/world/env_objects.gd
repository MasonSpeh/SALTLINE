class_name EnvObjects extends RefCounted
## Six environmental object builders for the rig. Static factories keep RigBuilder
## readable; the animated ones (fire barrel, crane hook, beacon, vent fan) are
## self-contained inner classes with their own _process.

## 1. Oil drum — a loose physics prop you can carry, throw, and knock around.
static func oil_drum(parent: Node3D, pos: Vector3) -> PhysProp:
	var drum := PhysProp.new()
	parent.add_child(drum)
	drum.global_position = pos
	drum.mass = 2.5
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.32
	cm.height = 0.9
	cm.material = MatLib.rusty_metal()
	mi.mesh = cm
	drum.add_child(mi)
	# Rim rings read as "drum" even in greybox.
	for ry in [-0.28, 0.0, 0.28]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.335
		rm.bottom_radius = 0.335
		rm.height = 0.04
		rm.material = MatLib.dark_metal()
		ring.mesh = rm
		drum.add_child(ring)
		ring.position.y = ry
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34
	shape.height = 0.92
	col.shape = shape
	drum.add_child(col)
	return drum

## 2. Life ring — pearl torus on a rail post; one variant is takeable.
## A life ring mounted FLAT on a wall/rail: a backboard sits flush on the surface
## at `pos`, the ring stands proud in front of it, and the whole thing faces along
## `face_yaw` (degrees; 0 = faces +Z, 180 = faces -Z, 90 = faces +X). Placed on a
## wall face with face_yaw pointing into the open, it never reads edge-on or
## half-embedded. `pos` should be ON the wall face.
static func life_ring(parent: Node3D, pos: Vector3, face_yaw: float = 0.0, takeable: bool = false) -> void:
	var root: Node3D
	if takeable:
		var t := Takeable.new()
		t.item_id = "life_ring"
		t.display_name = "Life Ring"
		parent.add_child(t)
		t.global_position = pos
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.86, 0.86, 0.22)
		shape.shape = box
		shape.position = Vector3(0, 0, 0.1)
		t.add_child(shape)
		root = t
	else:
		root = Node3D.new()
		parent.add_child(root)
		root.global_position = pos
	# `mount` carries the facing: everything is built facing +Z, then swung to face_yaw.
	var mount := Node3D.new()
	root.add_child(mount)
	mount.rotation.y = deg_to_rad(face_yaw)
	# Backboard flush on the wall, so the fixture reads mounted (and hides any seam).
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.05)
	bm.material = MatLib.painted_steel()
	board.mesh = bm
	mount.add_child(board)
	board.position = Vector3(0, 0, 0.025)   # front face at z=+0.05, flush-proud
	# The ring standing proud in front of the board — disc in XY, face along +Z.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.38
	tm.material = MatLib.flat(Color(0.9, 0.55, 0.2))
	ring.mesh = tm
	mount.add_child(ring)
	ring.rotation.x = deg_to_rad(90)
	ring.position = Vector3(0, 0, 0.14)     # proud of the board
	# Four pale rope lashings around the face.
	for i in range(4):
		var knot := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(0.1, 0.1, 0.06)
		km.material = MatLib.flat(Color(0.85, 0.82, 0.7))
		knot.mesh = km
		mount.add_child(knot)
		var a: float = i * TAU / 4.0 + 0.4
		knot.position = Vector3(cos(a) * 0.38, sin(a) * 0.38, 0.14)
	# Two mounting straps from the board across the ring (top + bottom).
	for sy in [0.3, -0.3]:
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.12, 0.32, 0.03)
		sm.material = MatLib.dark_metal()
		strap.mesh = sm
		mount.add_child(strap)
		strap.position = Vector3(0, sy, 0.1)

## 3. Fire barrel — early warmth before the power puzzle; flickering light + heat zone.
class FireBarrel extends Node3D:
	## AN ACTUAL BURN BARREL. Owner: "make the fire barrel more realistic / an actual fire
	## barrel, player cant stand in it."
	##
	## What it was: one smooth closed cylinder with a flat glowing DISC LAID ON THE LID.
	## The fire was therefore on top of a sealed drum rather than inside an open one, and
	## because the cap is a flat surface 1.0 m up — inside the player's mantle band of
	## 0.4-1.3 m (player_controller MANTLE_MIN_H / MANTLE_MAX_H) — you could climb it and
	## stand with your boots in the embers.
	##
	## What it is now: a real 55-gallon drum, open-topped, burning inside.
	##   * 0.29 m radius, 0.88 m tall — the actual dimensions of a 208 L steel drum;
	##   * OPEN: the shell is a tube (a cylinder with no caps) with a separate darker
	##     interior wall and a charred floor disc set down inside it, so looking in from
	##     above you see into the barrel rather than at a lid;
	##   * two rolling hoops, the ribs a real drum is pressed with, which are most of what
	##     makes a bare cylinder read as a barrel at a glance;
	##   * six punched draught holes round the base — the thing that makes a burn barrel a
	##     burn barrel, and the reason it drags air and glows at the bottom;
	##   * a heat-scorched band up the top third: bare steel discolours before it rusts,
	##     and the gradient from rusty base to blued rim is the strongest realism cue here;
	##   * the fire DOWN INSIDE at a third height, with soft-edged flame billboards licking
	##     up past the rim rather than a hard-edged disc sitting on it.
	##
	## AND YOU CANNOT STAND IN IT. The collider is the drum to its rim, plus an invisible
	## CONE above the opening whose flank is 64 degrees off horizontal — comfortably past
	## the controller's floor_max_angle of 46, so the surface is never classified as floor
	## and a player who tries to mantle in simply slides back off. The cone tops out at
	## 1.62 m, above MANTLE_MAX_H, so the rim cannot be mantled either. It is collision-only
	## and invisible, and it occupies exactly the space the flames do.
	const R: float = 0.29           ## a 208 L drum is 572 mm across
	const H: float = 0.88           ## ...and 880 mm tall
	const FIRE_Y: float = 0.34      ## the burning heap sits low inside, as it would

	var _light: OmniLight3D
	var _coals: StandardMaterial3D
	var _flames: Array[MeshInstance3D] = []
	var _flame_mat: StandardMaterial3D
	var _t: float = 0.0

	func _ready() -> void:
		var steel: Material = MatLib.dark_metal()
		# THE SHELL, as a tube: an open cylinder has no cap to stand on and lets the eye
		# into the barrel. CylinderMesh's cap flags are exactly the right tool.
		var shell := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = R
		cm.bottom_radius = R
		cm.height = H
		cm.cap_top = false
		cm.material = steel
		shell.mesh = cm
		add_child(shell)
		shell.position.y = H * 0.5
		# The inside wall, a hair narrower and much darker — soot, and it stops the shell
		# looking like paper when you see its back face through the opening.
		var sooted := StandardMaterial3D.new()
		sooted.albedo_color = Color(0.07, 0.06, 0.055)
		sooted.roughness = 1.0
		sooted.cull_mode = BaseMaterial3D.CULL_FRONT   # we are looking at its INSIDE
		var liner := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = R - 0.012
		lm.bottom_radius = R - 0.012
		lm.height = H - 0.02
		lm.cap_top = false
		lm.material = sooted
		liner.mesh = lm
		add_child(liner)
		liner.position.y = H * 0.5
		# The charred floor of the barrel, set down inside where ash would collect.
		var floor_disc := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = R - 0.02
		fm.bottom_radius = R - 0.02
		fm.height = 0.03
		fm.material = sooted
		floor_disc.mesh = fm
		add_child(floor_disc)
		floor_disc.position.y = 0.10
		# HEAT SCORCH. Bare steel blues and greys where it has been hot, and on a burn
		# barrel that is the top third. A slightly proud band reads as discolouration
		# rather than as a separate object.
		var scorch := StandardMaterial3D.new()
		scorch.albedo_color = Color(0.16, 0.15, 0.16)
		scorch.roughness = 0.85
		scorch.metallic = 0.35
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = R + 0.004
		bm.bottom_radius = R + 0.004
		bm.height = H * 0.34
		bm.cap_top = false
		bm.cap_bottom = false
		bm.material = scorch
		band.mesh = bm
		add_child(band)
		band.position.y = H - H * 0.17
		# THE ROLLING HOOPS. Two pressed ribs are what say "drum" rather than "pipe".
		for hy in [H * 0.34, H * 0.66]:
			var hoop := MeshInstance3D.new()
			var hm := TorusMesh.new()
			hm.inner_radius = R - 0.008
			hm.outer_radius = R + 0.022
			hm.material = steel
			hoop.mesh = hm
			add_child(hoop)
			hoop.position.y = hy
		# THE DRAUGHT HOLES, punched round the base. Dark, slightly proud of the shell so
		# they read as holes rather than as decals, and lit from within by the coals.
		var hole_mat := StandardMaterial3D.new()
		hole_mat.albedo_color = Color(0.9, 0.32, 0.06)
		hole_mat.emission_enabled = true
		hole_mat.emission = Color(1.0, 0.42, 0.08)
		hole_mat.emission_energy_multiplier = 1.4
		for i in range(6):
			var a: float = TAU * float(i) / 6.0
			var hole := MeshInstance3D.new()
			var hbm := BoxMesh.new()
			hbm.size = Vector3(0.055, 0.075, 0.02)
			hbm.material = hole_mat
			hole.mesh = hbm
			add_child(hole)
			hole.position = Vector3(cos(a) * (R + 0.002), 0.15, sin(a) * (R + 0.002))
			hole.rotation.y = -a + PI * 0.5
		# THE COALS, down inside on the ash floor.
		_coals = StandardMaterial3D.new()
		_coals.albedo_color = Color(1.0, 0.42, 0.09)
		_coals.emission_enabled = true
		_coals.emission = Color(1.0, 0.46, 0.10)
		_coals.emission_energy_multiplier = 2.0
		var glow := MeshInstance3D.new()
		var gm := CylinderMesh.new()
		gm.top_radius = R - 0.05
		gm.bottom_radius = R - 0.05
		gm.height = 0.07
		gm.material = _coals
		glow.mesh = gm
		add_child(glow)
		glow.position.y = FIRE_Y * 0.55
		# THE FLAME. Soft-edged billboards, not cones: docs/AGENT_TRAPS records that an
		# unshaded double-sided cone photographs as a flat blade with no volume, and that
		# an untextured billboard is a hard white rectangle — the fix that worked for the
		# stove's steam was a radial GradientTexture2D whose alpha falls to zero at the
		# rim, built in code with no asset. Same recipe, warm ramp.
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.85, 0.35, 0.95))
		grad.set_color(1, Color(0.9, 0.22, 0.03, 0.0))
		grad.add_point(0.45, Color(1.0, 0.48, 0.08, 0.6))
		var gtex := GradientTexture2D.new()
		gtex.gradient = grad
		gtex.fill = GradientTexture2D.FILL_RADIAL
		gtex.fill_from = Vector2(0.5, 0.5)
		gtex.fill_to = Vector2(1.0, 0.5)
		gtex.width = 64
		gtex.height = 64
		_flame_mat = StandardMaterial3D.new()
		_flame_mat.albedo_texture = gtex
		_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flame_mat.billboard_keep_scale = true
		_flame_mat.disable_receive_shadows = true
		for i in range(3):
			var fl := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.42 - 0.07 * float(i), 0.62 - 0.11 * float(i))
			qm.material = _flame_mat
			fl.mesh = qm
			add_child(fl)
			fl.position = Vector3(0.0, FIRE_Y + 0.20 + 0.10 * float(i), 0.0)
			fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_flames.append(fl)
		_build_collision()
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.6, 0.25)
		_light.omni_range = 9.0
		_light.light_energy = 2.2
		_light.light_volumetric_fog_energy = 1.6
		_light.shadow_enabled = true
		add_child(_light)
		# Just above the rim: a light down inside a now-genuinely-open drum lights the
		# inside of the barrel and nothing else.
		_light.position.y = H + 0.12
		var heat := WarmthZone.new()
		heat.mode = 1
		heat.setup(Vector3(5, 3, 5))
		add_child(heat)
		heat.position.y = 1.2

	## The drum, plus the cone that makes the opening unstandable.
	func _build_collision() -> void:
		var sb := StaticBody3D.new()
		add_child(sb)
		var body_col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = R + 0.02
		cyl.height = H
		body_col.shape = cyl
		sb.add_child(body_col)
		body_col.position.y = H * 0.5
		# THE NO-STAND CONE. Godot has no cone primitive shape, so this is a convex hull:
		# a ring at the rim and a single apex above it. The flank rises 0.74 m over a
		# 0.31 m radius, i.e. 64 degrees from horizontal, against the player controller's
		# floor_max_angle of 46 — so it can never be classified as floor, and anything
		# that lands on it slides off. Its apex at 1.62 m also puts the whole assembly
		# above MANTLE_MAX_H (1.3 m), so the rim cannot be mantled onto in the first place.
		var pts := PackedVector3Array()
		for i in range(12):
			var a: float = TAU * float(i) / 12.0
			pts.append(Vector3(cos(a) * (R + 0.02), H, sin(a) * (R + 0.02)))
		pts.append(Vector3(0.0, H + 0.74, 0.0))
		var cone := ConvexPolygonShape3D.new()
		cone.points = pts
		var cone_col := CollisionShape3D.new()
		cone_col.shape = cone
		sb.add_child(cone_col)

	func _process(delta: float) -> void:
		_t += delta
		Journal.discover_if_near(self, "place_fire_barrel", 5.0)
		var flicker: float = 2.2 + sin(_t * 9.0) * 0.35 + sin(_t * 23.0) * 0.2
		_light.light_energy = flicker
		_coals.emission_energy_multiplier = flicker * 0.9
		# The flames breathe out of phase with each other — in phase they pulse as one
		# blob, which is the same lesson the cat's body shake learned about segments.
		for i in range(_flames.size()):
			var f: MeshInstance3D = _flames[i]
			var ph: float = _t * (6.0 + 1.7 * float(i)) + float(i) * 2.1
			var s: float = 0.86 + 0.20 * sin(ph) + 0.07 * sin(ph * 2.7)
			f.scale = Vector3(0.94 + 0.10 * sin(ph * 1.3), s, 1.0)
			f.position.x = sin(ph * 0.7) * 0.022
			f.position.z = cos(ph * 0.9) * 0.022

## 4. Crane — mast, jib out over the deck, and a hook block that swings in the wind.
## The mast/jib used to be plain boxes and the "hook" a single 0.5x0.7x0.3 block on a
## square cable — pure greybox. Now the mast is a tapered tube with a tie-back strut, the
## jib tip carries a real grooved SHEAVE between cheek plates, the fall is round rope, and
## the hook is a segmented block-and-hook (swivel, cheeks, pin, and a curved point).
class CraneHook extends Node3D:
	var _pivot: Node3D
	var _t: float = 0.0

	static func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		parent.add_child(mi)
		mi.position = pos
		return mi

	static func _cyl(r: float, h: float, mat: Material) -> CylinderMesh:
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.material = mat
		return m

	static func _box_mesh(size: Vector3, mat: Material) -> BoxMesh:
		var m := BoxMesh.new()
		m.size = size
		m.material = mat
		return m

	func _ready() -> void:
		var steel: Material = MatLib.rust_steel()
		var dark: Material = MatLib.dark_metal()
		var galv: Material = MatLib.galvanized()
		# Mast: a tapered tube (was a square 0.8m box), on a small base plate.
		var mm := CylinderMesh.new()
		mm.top_radius = 0.26
		mm.bottom_radius = 0.36
		mm.height = 9.0
		mm.material = steel
		_mesh(self, mm, Vector3(0, 4.5, 0))
		_mesh(self, _box_mesh(Vector3(1.0, 0.2, 1.0), dark), Vector3(0, 0.1, 0))
		# Jib out over the deck, with a diagonal tie back to the mast head so it reads as
		# a braced boom rather than one floating bar.
		_mesh(self, _box_mesh(Vector3(0.34, 0.34, 9.0), steel), Vector3(0, 8.8, -4.2))
		var tie := _mesh(self, _box_mesh(Vector3(0.14, 0.14, 5.6), dark), Vector3(0, 9.5, -3.0))
		tie.rotation.x = deg_to_rad(28.0)
		# --- sheave at the jib tip: two cheek plates and a grooved wheel between them ---
		var tip := Vector3(0, 8.6, -8.2)
		for s in [-0.12, 0.12]:
			_mesh(self, _box_mesh(Vector3(0.06, 0.7, 0.6), dark), tip + Vector3(s, 0, 0))
		var wheel := MeshInstance3D.new()
		var wm := TorusMesh.new()
		wm.inner_radius = 0.16
		wm.outer_radius = 0.28
		wm.material = galv
		wheel.mesh = wm
		add_child(wheel)
		wheel.position = tip
		wheel.rotation.y = deg_to_rad(90)   # wheel plane faces along the jib (swings in Z)
		# --- the swinging block-and-hook, hung from the sheave on a round fall ---
		_pivot = Node3D.new()
		add_child(_pivot)
		_pivot.position = tip
		_mesh(_pivot, _cyl(0.03, 4.2, dark), Vector3(0, -2.1, 0))          # wire rope fall
		var block_y: float = -4.2
		_mesh(_pivot, _box_mesh(Vector3(0.34, 0.42, 0.26), dark), Vector3(0, block_y, 0))  # hook block cheeks
		var pin := _mesh(_pivot, _cyl(0.14, 0.4, galv), Vector3(0, block_y, 0))            # sheave pin
		pin.rotation.z = deg_to_rad(90)
		# Swivel + shank down to the throat.
		_mesh(_pivot, _cyl(0.05, 0.22, galv), Vector3(0, block_y - 0.32, 0))
		var hook_body := StaticBody3D.new()
		_pivot.add_child(hook_body)
		hook_body.position = Vector3(0, block_y - 0.55, 0)
		_mesh(hook_body, _cyl(0.06, 0.4, galv), Vector3(0, 0.1, 0))        # shank
		# The curved point, swept from three short segments back up to a tip.
		var bend := [
			[Vector3(0.0, -0.14, 0.0), 0.0],
			[Vector3(0.11, -0.24, 0.0), 55.0],
			[Vector3(0.24, -0.20, 0.0), 110.0],
			[Vector3(0.30, -0.08, 0.0), 150.0],
		]
		for seg in bend:
			var m := _mesh(hook_body, _box_mesh(Vector3(0.09, 0.16, 0.09), galv), seg[0])
			m.rotation.z = deg_to_rad(seg[1])
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.42, 0.7, 0.3)
		col.shape = shape
		col.position = Vector3(0.1, -0.1, 0)
		hook_body.add_child(col)

	func _process(delta: float) -> void:
		_t += delta
		# Slow pendulum with a slight cross-swing: wind, not machinery.
		_pivot.rotation.x = sin(_t * 0.5) * 0.06
		_pivot.rotation.z = sin(_t * 0.34 + 1.2) * 0.05

## 5. Antenna array — dishes and poles with a blinking red aircraft beacon.
class AntennaArray extends Node3D:
	var _beacon_mat: StandardMaterial3D
	var _beacon_light: OmniLight3D
	var _t: float = 0.0

	func _ready() -> void:
		for spec in [[Vector3(-0.8, 0, 0.4), 3.6], [Vector3(0.7, 0, -0.3), 2.6]]:
			var pole := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.04
			pm.bottom_radius = 0.07
			pm.height = spec[1]
			pm.material = MatLib.dark_metal()
			pole.mesh = pm
			add_child(pole)
			pole.position = spec[0] + Vector3(0, spec[1] * 0.5, 0)
		var dish := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.55
		dm.bottom_radius = 0.1
		dm.height = 0.25
		dm.material = MatLib.painted_steel()
		dish.mesh = dm
		add_child(dish)
		dish.position = Vector3(0.7, 2.0, -0.3)
		dish.rotation.x = deg_to_rad(55)
		_beacon_mat = StandardMaterial3D.new()
		_beacon_mat.albedo_color = Color(0.8, 0.1, 0.08)
		_beacon_mat.emission_enabled = true
		_beacon_mat.emission = Color(1.0, 0.12, 0.08)
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.12
		bm.height = 0.24
		bm.material = _beacon_mat
		bulb.mesh = bm
		add_child(bulb)
		bulb.position = Vector3(-0.8, 3.75, 0.4)
		_beacon_light = OmniLight3D.new()
		_beacon_light.light_color = Color(1.0, 0.15, 0.1)
		_beacon_light.omni_range = 7.0
		add_child(_beacon_light)
		_beacon_light.position = bulb.position

	func _process(delta: float) -> void:
		_t += delta
		var on: bool = fmod(_t, 2.4) < 0.25
		_beacon_mat.emission_energy_multiplier = 5.0 if on else 0.05
		_beacon_light.light_energy = 2.5 if on else 0.0

## 6. Vent fan — roof unit; idles in the wind, spins up when the grid is live.
class VentFan extends Node3D:
	var _blades: Node3D
	var _speed: float = 0.8

	func _ready() -> void:
		var housing := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.55
		hm.bottom_radius = 0.55
		hm.height = 0.5
		hm.material = MatLib.painted_steel()
		housing.mesh = hm
		add_child(housing)
		housing.position.y = 0.25
		_blades = Node3D.new()
		add_child(_blades)
		_blades.position.y = 0.42
		for i in range(2):
			var blade := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 0.04, 0.16)
			bm.material = MatLib.dark_metal()
			blade.mesh = bm
			_blades.add_child(blade)
			blade.rotation.y = i * PI * 0.5
		PowerGrid.circuit_powered.connect(func(id: String) -> void:
			if id == "topside_floodlights":
				_speed = 9.0)
		PowerGrid.circuit_lost.connect(func(id: String) -> void:
			if id == "topside_floodlights":
				_speed = 0.8)

	func _process(delta: float) -> void:
		_blades.rotation.y += _speed * delta

## 7. Emergency red flasher — a battery beacon that PULSES while the grid is dead, so a
## player in the blackout always has a red heartbeat to steer by. When mains power comes
## back it drops to a steady dim standby (the deck lamps take over). NOT a LightZone: the
## dark stays dangerous, this only gives the player something to see BY. Cheap OmniLight,
## shadows off (gl_compat). Call setup() BEFORE add_child (which fires _ready).
class RedFlasher extends Node3D:
	var _light: OmniLight3D
	var _lens: StandardMaterial3D
	var _t: float = 0.0
	var _powered: bool = false
	var _rng: float = 8.0
	var _peak: float = 3.0
	var _scale: float = 1.0
	var _period: float = 1.3
	var _ceiling: bool = false

	## rng = light range, peak = flash energy, sz = housing scale, period = seconds/flash.
	##
	## The fixture is BUILT STANDING: the origin is the base of the housing and the lens
	## sits 0.2 m above it, which is right for a mast head or a pole top. `ceiling` flips
	## the whole assembly so the housing's wide end becomes the mounting flange, the lens
	## and its guard ribs hang BELOW it, and the origin becomes the point that goes hard
	## against the deckhead. Without it, a beacon placed on a ceiling reads upside down —
	## and, because the fixture is 0.32 m tall, its position has to be the ceiling
	## underside for the flange to be flush instead of hanging in mid-air.
	func setup(rng: float, peak: float, sz: float = 1.0, period: float = 1.3,
			ceiling: bool = false) -> void:
		_rng = rng
		_peak = peak
		_scale = sz
		_period = period
		_ceiling = ceiling

	func _ready() -> void:
		# Hung fixture: everything below is authored upward from the base, so one flip
		# about X turns the whole thing over and leaves the origin on the mounting face.
		if _ceiling:
			rotation.x = PI
		# Dark housing can on a short stalk, a red lens dome, and a small guard cage.
		var housing := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.13 * _scale
		hm.bottom_radius = 0.15 * _scale
		hm.height = 0.16 * _scale
		hm.material = MatLib.dark_metal()
		housing.mesh = hm
		add_child(housing)
		housing.position.y = 0.08 * _scale
		_lens = StandardMaterial3D.new()
		_lens.albedo_color = Color(0.7, 0.06, 0.05)
		_lens.emission_enabled = true
		_lens.emission = Color(1.0, 0.12, 0.08)
		_lens.emission_energy_multiplier = 5.0
		var lens := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.12 * _scale
		lm.height = 0.2 * _scale
		lm.material = _lens
		lens.mesh = lm
		add_child(lens)
		lens.position.y = 0.2 * _scale
		# Guard ribs over the lens.
		for i in range(3):
			var rib := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.015 * _scale, 0.24 * _scale, 0.015 * _scale)
			rm.material = MatLib.dark_metal()
			rib.mesh = rm
			add_child(rib)
			var a: float = i * PI / 3.0
			rib.position = Vector3(cos(a) * 0.13 * _scale, 0.2 * _scale, sin(a) * 0.13 * _scale)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.14, 0.1)
		_light.omni_range = _rng
		_light.light_energy = _peak
		_light.shadow_enabled = false
		_light.light_volumetric_fog_energy = 1.4
		add_child(_light)
		_light.position.y = 0.2 * _scale
		PowerGrid.circuit_powered.connect(func(id: String) -> void:
			if id == "topside_floodlights":
				_powered = true)
		PowerGrid.circuit_lost.connect(func(id: String) -> void:
			if id == "topside_floodlights":
				_powered = false)

	func _process(delta: float) -> void:
		_t += delta
		if _powered:
			# Steady dim standby once the deck is lit.
			_light.light_energy = 0.35
			_lens.emission_energy_multiplier = 0.8
			return
		# A double-blink heartbeat: bright on the first third of the period.
		var ph: float = fmod(_t, _period)
		var on: bool = ph < _period * 0.28
		_light.light_energy = _peak if on else 0.0
		_lens.emission_energy_multiplier = 6.0 if on else 0.35
