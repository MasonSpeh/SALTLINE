class_name JellyGlow extends Node3D
## Dusk trigger (GDD 5.4): emissive teal spots appearing in the water below —
## cheap, evocative. Fade in at dusk, out at dawn; slow collective pulse at night.

var _mat: StandardMaterial3D
var _target_energy: float = 0.0
var _time: float = 0.0

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
		quad.position = Vector3(cos(angle) * radius, 0.4, sin(angle) * radius)
		quad.rotation.x = deg_to_rad(-90)
	GameClock.dusk.connect(func() -> void: _target_energy = 1.6)
	GameClock.dawn.connect(func() -> void: _target_energy = 0.0)
	GameClock.day.connect(func() -> void: _target_energy = 0.0)

func _process(delta: float) -> void:
	_time += delta
	var pulse: float = 1.0 + 0.25 * sin(_time * 0.8)
	_mat.emission_energy_multiplier = move_toward(
		_mat.emission_energy_multiplier, _target_energy * pulse, delta * 0.4)
