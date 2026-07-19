class_name JellyGlow extends Node3D
## Dusk trigger (GDD 5.4): emissive teal spots appearing in the water below —
## cheap, evocative. Fade in at dusk, out at dawn; slow collective pulse at night.

var _mat: StandardMaterial3D
var _target_energy: float = 0.0
var _time: float = 0.0
var _spots: Array[MeshInstance3D] = []   ## kept so they can ride the swell each frame

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.1, 0.5, 0.5, 0.85)
	_mat.emission_enabled = true
	_mat.emission = Color(0.15, 0.85, 0.8)   # Bloom teal: the world's light, not ours
	_mat.emission_energy_multiplier = 0.0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(26):
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(rng.randf_range(1.0, 2.2), rng.randf_range(1.0, 2.2))
		mesh.material = _mat
		quad.mesh = mesh
		add_child(quad)
		var angle: float = rng.randf_range(0, TAU)
		var radius: float = rng.randf_range(34, 58)
		quad.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		quad.rotation.x = deg_to_rad(-90)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spots.append(quad)
	GameClock.dusk.connect(func() -> void: _target_energy = 1.6)
	GameClock.dawn.connect(func() -> void: _target_energy = 0.0)
	GameClock.day.connect(func() -> void: _target_energy = 0.0)

func _process(delta: float) -> void:
	_time += delta
	var pulse: float = 1.0 + 0.25 * sin(_time * 0.8)
	_mat.emission_energy_multiplier = move_toward(
		_mat.emission_energy_multiplier, _target_energy * pulse, delta * 0.4)
	# These are meant to be glows seen IN THE WATER BELOW. They were pinned at y +0.4,
	# which was "just above a flat sea" — against the Gerstner swell it left 26 flat teal
	# plates hanging in open air over every trough, easily the most conspicuous thing on
	# the night water. Ride the surface and sit just under it, so they read as light
	# diffusing up through the swell.
	if _spots.is_empty():
		return
	# NOTE the absence of the 0.85 factor main.gd uses for its camera test. That factor
	# compresses the wave toward zero, which lifts a point ABOVE the real surface in every
	# trough (at a -3 m trough, 0.85 puts you at -2.55) — so anything "submerged" with it
	# popped out of the water exactly where the sea was deepest. The shader draws the
	# surface at the FULL Gerstner height; things that must stay under it use that.
	var t: float = Gyre.water_time()
	for q in _spots:
		var p: Vector3 = q.position
		q.position.y = Gyre.wave_height(Vector2(p.x, p.z), t) - 0.5
