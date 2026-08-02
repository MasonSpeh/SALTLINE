class_name JellyGlow extends Node3D
## Dusk trigger (GDD 5.4): emissive teal spots appearing in the water below —
## cheap, evocative. Fade in at dusk, out at dawn; slow collective pulse at night.

var _mat: StandardMaterial3D
var _target_energy: float = 0.0
var _time: float = 0.0
var _spots: Array[MeshInstance3D] = []   ## kept so they can ride the swell each frame
## The UNDISPLACED sample point for each spot. Gerstner moves a floating thing horizontally as
## well as vertically, so the drawn position is not the position to sample the next frame from
## — feeding a displaced x/z back in would let each spot walk away across the sea.
var _base: PackedVector3Array = PackedVector3Array()

## HOW DEEP THEY SIT, and it is set by their own size rather than by feel. These are rigid
## HORIZONTAL plates up to 2.2 m square, so a plate's half-diagonal is up to 1.56 m: held only
## 0.5 m under a surface height sampled at its CENTRE, every wave face steeper than
## atan(0.5/1.1) = 24 degrees pushed a corner through the water. Gerstner faces pass 24 degrees
## routinely even at the shipped calm sea state, so the spots surfaced constantly — and being
## untextured emissive quads they surfaced as hard-edged glowing SQUARES. This clears the
## half-diagonal with margin.
const SPOT_DRAFT: float = 1.8

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.1, 0.5, 0.5, 0.85)
	_mat.emission_enabled = true
	_mat.emission = Color(0.15, 0.85, 0.8)   # Bloom teal: the world's light, not ours
	_mat.emission_energy_multiplier = 0.0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A RADIAL FALLOFF, or these are literal squares. An untextured QuadMesh renders as a hard
	# axis-aligned rectangle — the same trap that made marine snow read as confetti
	# (docs/AGENT_TRAPS.md, and MatLib.soft_mote exists because of it). The gradient is built
	# here rather than taken from MatLib.soft_mote() ON PURPOSE: that helper returns a CACHED
	# material shared with the snow and bubbles, and this one has its emission energy driven
	# every frame by the dusk/dawn pulse below, which would drag every other user with it.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_mat.albedo_texture = tex
	_mat.emission_texture = tex
	# Seen from below as well as above: a +Y-facing quad with the default back-face cull is
	# invisible to a diver looking up at it, which is most of where these are meant to read.
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	for i in range(_spots.size()):
		var q: MeshInstance3D = _spots[i]
		var b: Vector3 = _base[i]
		# THE FULL OFFSET, not just the height. Gerstner displaces horizontally toward crests,
		# and gyre.gd says outright that anything floating needs that offset too or it drifts
		# off the peak it should be sitting on — the foam streaks and the drifting debris both
		# apply it. This was the one near-water object that did not, and the horizontal error
		# (up to ~1.5 m at the calm sea state) is more height error on a sloped face than the
		# whole draft. Sampled from the UNDISPLACED base point every frame, never from where
		# the spot was last drawn.
		var wo: Vector3 = Gyre.wave_offset(Vector2(b.x, b.z), t)
		q.position = Vector3(b.x + wo.x, wo.y - SPOT_DRAFT, b.z + wo.z)
