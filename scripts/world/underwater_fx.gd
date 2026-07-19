extends Node3D
## Underwater visibility & light: everything that sells the water as a lit MEDIUM the
## player is inside of, rather than a teal void. Owns nothing topside — it reads the
## surface height (Gyre), the daylight (GameClock), the sun bearing (the scene's sun)
## and the storm, and drives:
##   - THE SURFACE FROM BELOW: a Snell's-window plane held over the player just under
##     the swell (the biggest "I'm underwater" cue — bright rippling disc overhead).
##   - LIGHT SHAFTS: additive crossed quads raking down from the surface near the legs.
##   - CAUSTICS: the surface's focused-light net wrapped on the upper legs.
##   - DEPTH-GRADED WATER: re-grades the camera's underwater Environment continuously
##     from the player's depth (green & clear near the surface -> blue-black & near-dark
##     at the bottom) and thickens the near-surface murk when a storm stirs the sediment.
##
## It is added as a child of underwater_world (which owns being in the scene), so main.gd
## is never touched; it only READS the environment main.gd puts on the camera and writes
## better values into it after main has run (process_priority keeps us last).

const LEGS: Array[Vector2] = [Vector2(-22, -12), Vector2(22, -12), Vector2(-22, 12), Vector2(22, 12)]

var _root: Node3D                     # everything visible, toggled by camera depth
var _snell: MeshInstance3D
var _snell_mat: ShaderMaterial
var _shaft_mats: Array[ShaderMaterial] = []
var _caustic_mats: Array[ShaderMaterial] = []
var _sun: DirectionalLight3D
var _storm: Node = null
var _rng := RandomNumberGenerator.new()

# graded underwater colours (near surface -> seabed)
const NEAR_FOG := Color(0.10, 0.27, 0.24)     # greenish, lit from above
const DEEP_FOG := Color(0.006, 0.022, 0.045)  # blue-black deep
const NEAR_AMB := Color(0.16, 0.34, 0.32)
const DEEP_AMB := Color(0.04, 0.10, 0.15)
const STORM_MURK := Color(0.13, 0.17, 0.12)   # stirred sediment, near the surface

func _ready() -> void:
	_rng.seed = 90210
	process_priority = 100   # run AFTER main.gd's environment write, so our grade wins
	_root = Node3D.new()
	add_child(_root)
	_build_snell()
	_build_light_shafts()
	_build_caustics()

# ---------------------------------------------------------------- build

func _build_snell() -> void:
	_snell_mat = ShaderMaterial.new()
	_snell_mat.shader = load("res://materials/underwater_surface.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(620, 620)   # large enough to occlude the far surface toward the horizon
	plane.subdivide_width = 48       # enough that per-vertex world pos feeds smooth ripple
	plane.subdivide_depth = 48
	plane.material = _snell_mat
	_snell = MeshInstance3D.new()
	_snell.mesh = plane
	_snell.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_snell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snell.extra_cull_margin = 200.0    # it's always overhead; never let it cull out
	_root.add_child(_snell)

## Crossed vertical slabs — a shaft always presents a lit face without billboard math.
## Kept soft: narrow, low density, strong edge falloff, so they read as raked light and
## not as bright walls.
func _build_light_shafts() -> void:
	var spots: Array[Vector3] = []
	for leg in LEGS:
		spots.append(Vector3(leg.x + _rng.randf_range(-3.5, 3.5), 0, leg.y + _rng.randf_range(-3.5, 3.5)))
	# a few in the open water off the wet deck and toward the gyre
	for extra in [Vector3(16, 0, -18), Vector3(6, 0, -24), Vector3(-6, 0, 2), Vector3(12, 0, 6)]:
		spots.append(extra)
	for sp in spots:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://materials/light_shaft.gdshader")
		mat.set_shader_parameter("reach", _rng.randf_range(11.0, 15.0))
		mat.set_shader_parameter("density", _rng.randf_range(0.22, 0.38))
		_shaft_mats.append(mat)
		var yaw: float = _rng.randf_range(0, TAU)
		var w: float = _rng.randf_range(1.3, 2.1)
		for k in range(2):    # two crossed quads
			var q := QuadMesh.new()
			q.size = Vector2(w, 17.0)
			q.material = mat
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 12.0
			_root.add_child(mi)
			mi.position = Vector3(sp.x, -5.5, sp.z)
			mi.rotation.y = yaw + float(k) * PI * 0.5

## Caustic light on the upper legs — one flat quad laid on each of the four caisson
## faces (NOT a box sleeve, which reads as a glass box haloing past the leg). Each quad
## is the exact size of the face and sits 6 cm proud, additive, so the rippling net
## lands ON the steel with no overhang. Fades out by ~6 m down. One shared material.
func _build_caustics() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://materials/caustics.gdshader")
	mat.set_shader_parameter("reach", 6.5)
	mat.set_shader_parameter("scale", 0.85)
	mat.set_shader_parameter("strength", 1.1)
	_caustic_mats.append(mat)
	# face offset dir (unit), yaw so the QuadMesh (+Z normal) faces outward
	var faces := [
		[Vector3(1, 0, 0), PI * 0.5], [Vector3(-1, 0, 0), -PI * 0.5],
		[Vector3(0, 0, 1), 0.0], [Vector3(0, 0, -1), PI],
	]
	for leg in LEGS:
		for f in faces:
			var dir: Vector3 = f[0]
			var q := QuadMesh.new()
			q.size = Vector2(6.0, 8.0)   # exact caisson face width, 8 m tall (y2..-6)
			q.material = mat
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(mi)
			mi.position = Vector3(leg.x, -2.0, leg.y) + dir * 3.06   # just proud of the 6 m face
			mi.rotation.y = f[1]

# ---------------------------------------------------------------- per frame

func _find_sun() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for n in scene.find_children("*", "DirectionalLight3D", true, false):
		_sun = n
		return

func _daylight() -> float:
	var fr: float = clampf(GameClock.phase_fraction(), 0.0, 1.0)
	match GameClock.current_phase:
		GameClock.Phase.DAY:
			return 1.0
		GameClock.Phase.DAWN:
			return lerpf(0.12, 1.0, fr)
		GameClock.Phase.DUSK:
			return lerpf(1.0, 0.12, fr)
		_:
			return 0.08

## Find the StormSystem by walking the tree (works whether the scene root is Main or a
## test harness), cached once located.
func _storm_node() -> Node:
	if _storm != null and is_instance_valid(_storm):
		return _storm
	var stack: Array = [get_tree().root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is StormSystem:
			_storm = n
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _storm_intensity() -> float:
	var st: Node = _storm_node()
	if st == null:
		return 0.0
	var v: Variant = st.get("_intensity")
	return clampf(float(v), 0.0, 1.0) if v != null else 0.0

func _process(_delta: float) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		_root.visible = false
		return
	var cam: Camera3D = player.get_node_or_null("Head/Camera3D")
	if cam == null:
		return
	if _sun == null:
		_find_sun()

	var px: float = player.global_position.x
	var pz: float = player.global_position.z
	var surf: float = Gyre.wave_height(Vector2(px, pz), Gyre.water_time()) * 0.85
	var cam_y: float = cam.global_position.y
	var under: bool = cam_y < surf

	# Only render the FX when the camera is at/under the surface (small margin so the
	# caustics on the legs are already there as you break through).
	_root.visible = cam_y < surf + 1.5

	var day: float = _daylight()
	var storm: float = _storm_intensity()
	var sun_dir := Vector3(0.25, 0.85, 0.2)
	if _sun != null:
		sun_dir = _sun.global_transform.basis.z   # points back toward the sun

	# Snell window: park it over the player, just under the swell.
	if _snell != null:
		_snell.global_position = Vector3(px, surf - 0.15, pz)
		_snell_mat.set_shader_parameter("daylight", day)
		_snell_mat.set_shader_parameter("sun_dir", sun_dir)
		# a storm chops the surface: soften the window and knock the light back
		_snell_mat.set_shader_parameter("ripple", 1.0 + storm * 1.4)
		_snell_mat.set_shader_parameter("window_color",
			Color(0.42, 0.72, 0.74).lerp(Color(0.20, 0.34, 0.30), storm * 0.7))

	for m in _shaft_mats:
		m.set_shader_parameter("daylight", day * (1.0 - storm * 0.55))
		m.set_shader_parameter("top_y", surf)
	for m in _caustic_mats:
		m.set_shader_parameter("daylight", day * (1.0 - storm * 0.6))
		m.set_shader_parameter("top_y", surf)

	# ---- depth-graded water: re-grade the camera's underwater environment ----
	if under:
		var env: Environment = cam.environment
		if env != null and env.fog_enabled:
			var depth: float = maxf(surf - cam_y, 0.0)
			var t: float = clampf(depth / 22.0, 0.0, 1.0)     # 0 surface .. 1 seabed
			var tc: float = t * t                              # deep thickens faster
			# base grade
			var fog_col: Color = NEAR_FOG.lerp(DEEP_FOG, tc)
			var amb_col: Color = NEAR_AMB.lerp(DEEP_AMB, tc)
			var dens: float = lerpf(0.040, 0.165, tc)
			var amb_e: float = lerpf(0.85, 0.14, t)
			# storm stirs sediment near the surface: denser, murkier, dimmer up top
			var near: float = (1.0 - t)
			dens += storm * near * 0.11
			fog_col = fog_col.lerp(STORM_MURK, storm * near * 0.6)
			amb_e *= (1.0 - storm * near * 0.35)
			# night pulls the whole column toward the dark, leaving the Bloom's own glow
			# (seabed shader, fauna rims) as the main light — brightest by day.
			var lum: float = 0.28 + 0.72 * day
			fog_col *= lum
			amb_col *= (0.4 + 0.6 * day)
			amb_e *= lum
			env.fog_light_color = fog_col
			env.fog_density = dens
			env.background_color = fog_col.darkened(0.5)
			env.ambient_light_color = amb_col
			env.ambient_light_energy = amb_e
