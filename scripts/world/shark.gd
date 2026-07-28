class_name UltraHammerhead extends Node3D
## The Bloom's patrol predator: a hammerhead grown past reason, cruising slow
## ellipses below the swell. Swimmers who stray close get judged — most passes
## (~70%) end in a charge and a hit; the rest it circles you once, close enough
## to count your heartbeats, and moves on. It never bothers what stays on deck.
## Rule 3′: aggression is ecological and readable — you can watch it decide.

enum SState { PATROL, CIRCLE, CHARGE, FLEE }

const NOTICE_RADIUS: float = 9.0
const BITE_RADIUS: float = 1.6
const ATTACK_CHANCE: float = 0.7      # "3-4 out of 5"
const BITE_DAMAGE: float = 0.5    # a hammerhead hit takes HALF the player's full health
const PATROL_SPEED: float = 3.6
const CHARGE_SPEED: float = 8.5
const COOLDOWN_SEC_MIN: float = 12.0
const COOLDOWN_SEC_MAX: float = 22.0

const ANIM := preload("res://scripts/world/creature_anim.gd")
const MODEL_PATH := "res://assets/models/fauna/ultra_hammerhead/ultra_hammerhead.glb"

# ---------------------------------------------------------------------------
# EVOLVED BLOOM (s16). The Bloom's mutations are ADAPTIVE, not corruptive — this is a
# BETTER shark than its ancestor, not a sick one. Three layers of dressing, all
# procedural, all built AFTER ANIM.replace(): replace() hides every mesh that existed
# before it, so overlay geometry built earlier is invisible dead code. (That lesson cost
# us a pass on the crab's claws; see crab.gd around line 392.)
#   1. HIDE      — deep slate, counter-shaded, wet. Not the GLB's tropical teal.
#   2. ARMOUR    — a nose-to-tail ridge of tessellated plates plus flank rosettes:
#                  mineral armour, the beautiful kind. Chiton plates and nacre, never
#                  wounds or growths.
#   3. HEAD      — four eyes on four equal stalks in a clean X, and real teeth.
# ---------------------------------------------------------------------------

## COLOUR. The generated GLB ships a saturated cyan albedo with glow veins painted into
## it, and a multiply tint can DARKEN that but can never desaturate it — so the shark
## drops the imported map entirely for a grey dermal mottle and takes its colour from
## HIDE_COL. Bioluminescence stays, but only as an ACCENT: cold blue irises, a sparse
## line of flank photophores, a low fresnel rim that lifts on a charge. Never a glowing
## teal shark; dark and real first, light second.
const HIDE_COL := Color(0.118, 0.138, 0.160)     ## deep slate, a breath of blue in it
const BELLY_COL := Color(0.372, 0.398, 0.412)    ## counter-shaded underside
const ARMOR_COL := Color(0.166, 0.187, 0.212)    ## plates: read as RAISED, not as holes
const NACRE_COL := Color(0.505, 0.552, 0.605)    ## plate rims and spine tips
const TOOTH_COL := Color(0.935, 0.945, 0.918)    ## pearl. Clean geometry, no gore.
const GLOW := Color(0.34, 0.60, 0.92)            ## cold deep-water blue
const GLOW_IDLE: float = 0.06                    ## restrained — a hint at the edges
const GLOW_HUNT: float = 0.20                    ## the flanks light up on a charge

## WHERE THE DRESSING HANGS, in host metres. MEASURED off the generated mesh with
## tests/SharkProbe.tscn (which slices its vertex cloud), not guessed — the glTF pivot is
## not centred and the cephalofoil is nothing like the primitive stand-in. DRESS_PROC
## repeats the job against the fallback capsule body, so a missing GLB still gets the
## evolved look instead of a bare grey capsule.
##   head/lobe_x/stalk — the four-eye rig: stalks leave the head at ±lobe_x and run
##                       `stalk` metres out at ±STALK_DEG. See _build_eyes().
##   ridge  — Vector2(z, y) spine polyline, snout -> dorsal -> back -> caudal lobe.
##   flank  — Vector3(z, halfwidth, y) armour-cluster stations, mirrored both sides.
##   belly  — Vector3(z, halfwidth, y) ventral counter-shade panel stations.
const STALK_DEG: float = 35.0    ## all four, so the eyes land on a true X
const DRESS_GEN := {
	"head": Vector3(0.0, -0.27, -2.18),
	"lobe_x": 0.46,
	"stalk": 0.82,
	"eye_r": 0.135,
	"mouth": Vector3(0.0, -0.50, -2.28),
	"mouth_hw": 0.42,
	"mouth_bow": 0.11,
	"tooth": 0.20,
	"sc": 1.0,
	"crest": [Vector3(-2.28, 0.0, -0.115), Vector3(-2.08, 0.0, -0.088),
		Vector3(-1.88, 0.0, -0.070)],
	"horn": Vector3(0.50, 0.30, -2.13),
	"ridge": [
		Vector2(-2.36, -0.150), Vector2(-2.00, -0.085), Vector2(-1.60, -0.025),
		Vector2(-1.20, 0.065), Vector2(-0.92, 0.145), Vector2(-0.74, 0.200),
		Vector2(-0.56, 0.400), Vector2(-0.38, 0.600), Vector2(-0.20, 0.745),
		Vector2(-0.04, 0.790), Vector2(0.06, 0.550), Vector2(0.14, 0.310),
		Vector2(0.22, 0.145), Vector2(0.60, 0.055), Vector2(1.00, 0.000),
		Vector2(1.40, 0.030), Vector2(1.76, 0.110), Vector2(2.00, 0.310),
		Vector2(2.22, 0.455), Vector2(2.40, 0.560),
	],
	"flank": [
		Vector3(-1.95, 0.88, -0.30), Vector3(-1.60, 0.68, -0.32),
		Vector3(-1.25, 0.63, -0.30), Vector3(-0.92, 0.62, -0.27),
		Vector3(-0.55, 0.62, -0.24), Vector3(-0.15, 0.60, -0.22),
		Vector3(0.25, 0.50, -0.26), Vector3(0.62, 0.40, -0.32),
		Vector3(0.98, 0.18, -0.24),
	],
	"belly": [
		Vector3(-2.15, 0.42, -0.630), Vector3(-1.80, 0.41, -0.741),
		Vector3(-1.40, 0.40, -0.794), Vector3(-1.00, 0.39, -0.803),
		Vector3(-0.60, 0.38, -0.784), Vector3(-0.20, 0.35, -0.739),
		Vector3(0.20, 0.30, -0.652), Vector3(0.60, 0.24, -0.545),
		Vector3(1.00, 0.14, -0.375), Vector3(1.40, 0.10, -0.352),
		Vector3(1.75, 0.08, -0.300),
	],
}
const DRESS_PROC := {
	"head": Vector3(0.0, 0.0, -2.45),
	"lobe_x": 0.52,
	"stalk": 0.82,
	"eye_r": 0.135,
	"mouth": Vector3(0.0, -0.32, -2.42),
	"mouth_hw": 0.36,
	"mouth_bow": 0.08,
	"tooth": 0.20,
	"sc": 1.0,
	"crest": [Vector3(-2.30, 0.0, 0.22), Vector3(-2.10, 0.0, 0.27),
		Vector3(-1.90, 0.0, 0.32)],
	"horn": Vector3(0.0, 0.0, 0.0),
	# Hugs the r=0.55 capsule: flat over the cylinder, falling away only inside the end
	# caps (top y = sqrt(0.55^2 - (|z|-1.95)^2) there), then up over the dorsal fin.
	"ridge": [
		Vector2(-2.30, 0.34), Vector2(-2.10, 0.47), Vector2(-1.80, 0.55),
		Vector2(-1.10, 0.55), Vector2(-0.55, 0.55), Vector2(-0.34, 0.63),
		Vector2(-0.05, 1.00), Vector2(0.20, 1.32), Vector2(0.45, 0.95),
		Vector2(0.72, 0.58), Vector2(1.30, 0.55), Vector2(1.90, 0.55),
		Vector2(2.15, 0.50), Vector2(2.38, 0.33),
	],
	"flank": [
		Vector3(-2.00, 0.50, -0.06), Vector3(-1.60, 0.53, -0.04),
		Vector3(-1.20, 0.54, -0.02), Vector3(-0.80, 0.54, 0.00),
		Vector3(-0.35, 0.54, 0.00), Vector3(0.10, 0.53, -0.02),
		Vector3(0.55, 0.51, -0.06), Vector3(1.00, 0.50, -0.10),
		Vector3(1.45, 0.48, -0.14), Vector3(1.90, 0.42, -0.16),
	],
	"belly": [
		Vector3(-2.10, 0.30, -0.44), Vector3(-1.60, 0.33, -0.50),
		Vector3(-1.10, 0.34, -0.52), Vector3(-0.60, 0.34, -0.53),
		Vector3(-0.10, 0.34, -0.53), Vector3(0.40, 0.33, -0.51),
		Vector3(0.90, 0.30, -0.48), Vector3(1.40, 0.25, -0.43),
		Vector3(1.85, 0.18, -0.36),
	],
}

var _mats: Array = []
var _eyes: Array[Node3D] = []          ## the four eye bulbs, for the symmetry assertion
var _photophores: Array = []           ## flank lights, driven with the hunt glow
static var _dermal: NoiseTexture2D = null

var _idx: int = 0
var _t: float = 0.0
var _state: SState = SState.PATROL
var _center: Vector3
var _radius: float
var _depth: float
var _cooldown: float = 0.0
var _judged: bool = false           ## one roll per approach
var _circle_t: float = 0.0
var _flee_target: Vector3
var _tail: Node3D
var _rng := RandomNumberGenerator.new()

func _init(idx: int = 0) -> void:
	_idx = idx
	_t = idx * 7.3
	_rng.randomize()
	_center = [Vector3(0, 0, -38), Vector3(30, 0, 8), Vector3(-34, 0, -4)][idx % 3]
	_radius = 14.0 + idx * 4.0
	_depth = -2.6 - idx * 1.2

func _ready() -> void:
	var hide_mat := _lit(HIDE_COL * 1.25, 0.34, 0.10)   # the fallback carries no texture,
	var belly := _lit(BELLY_COL, 0.46, 0.04)            # so it sits a touch above HIDE_COL
	# Body: a 5m tapered capsule with a pale underside slab.
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.55
	bm.height = 5.0
	bm.material = hide_mat
	body.mesh = bm
	body.rotation.x = deg_to_rad(90)
	add_child(body)
	var under := MeshInstance3D.new()
	var um := BoxMesh.new()
	um.size = Vector3(0.7, 0.18, 3.4)
	um.material = belly
	under.mesh = um
	under.position = Vector3(0, -0.42, 0.2)
	add_child(under)
	# The hammer: the crossbar that names it, an eye bulb at each end.
	var hammer := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(2.3, 0.3, 0.6)
	hm.material = hide_mat
	hammer.mesh = hm
	hammer.position = Vector3(0, 0, -2.5)
	add_child(hammer)
	# NOTE: the primitive body no longer carries eyes of its own. The four-eye rig in
	# _build_eyes() supplies them on BOTH paths, so a fallback shark and a generated one
	# have the same face.
	# Dorsal fin, second dorsal, pectorals, gill slits, and a heterocercal tail
	# on its own pivot — the long upper lobe that writes the silhouette.
	var fin := MeshInstance3D.new()
	var fm := PrismMesh.new()
	fm.size = Vector3(0.16, 1.0, 1.1)
	fm.material = hide_mat
	fin.mesh = fm
	fin.position = Vector3(0, 0.85, 0.2)
	add_child(fin)
	var fin2 := MeshInstance3D.new()
	var f2m := PrismMesh.new()
	f2m.size = Vector3(0.1, 0.4, 0.5)
	f2m.material = hide_mat
	fin2.mesh = f2m
	fin2.position = Vector3(0, 0.6, 1.7)
	add_child(fin2)
	for side in [-1.0, 1.0]:
		var pec := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.1, 0.5, 1.3)
		pm.material = hide_mat
		pec.mesh = pm
		pec.position = Vector3(side * 0.65, -0.25, -0.9)
		pec.rotation_degrees = Vector3(0, 0, 105 * side)
		add_child(pec)
		# Five gill slits ahead of each pectoral.
		for g in range(5):
			var slit := MeshInstance3D.new()
			var sm2 := BoxMesh.new()
			sm2.size = Vector3(0.015, 0.3, 0.06)
			sm2.material = StandardMaterial3D.new()
			(sm2.material as StandardMaterial3D).albedo_color = Color(0.12, 0.14, 0.16)
			slit.mesh = sm2
			slit.position = Vector3(side * 0.52, 0.0, -1.5 + g * 0.13)
			add_child(slit)
	_tail = Node3D.new()
	add_child(_tail)
	_tail.position = Vector3(0, 0.1, 2.5)
	var upper := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(0.14, 1.7, 1.0)
	tm.material = hide_mat
	upper.mesh = tm
	upper.position = Vector3(0, 0.5, 0.4)
	upper.rotation.x = deg_to_rad(24)
	_tail.add_child(upper)
	var lower := MeshInstance3D.new()
	var lm := PrismMesh.new()
	lm.size = Vector3(0.12, 0.6, 0.5)
	lm.material = hide_mat
	lower.mesh = lm
	lower.position = Vector3(0, -0.3, 0.3)
	lower.rotation.x = deg_to_rad(155)
	_tail.add_child(lower)
	# Swap in the generated hammerhead if it's been produced; the body wave comes from
	# CreatureAnim's vertex shader (Meshy can't rig animals), driven below by swim effort.
	var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 5.0, ANIM.Mode.UNDULATE,
		0.09, 1.1, GLOW)
	# EVERYTHING BELOW THIS LINE runs AFTER replace() on purpose. replace() hides every
	# MeshInstance3D that already existed under this node, so the armour, the eye stalks
	# and the teeth have to be built here or they are born invisible.
	if gen.is_empty():
		_build_bloom(DRESS_PROC)      # no GLB: dress the primitive body instead
	else:
		_mats = gen["mats"]
		_shade_generated()
		_build_bloom(DRESS_GEN)
	global_position = _center + Vector3(_radius, _depth, 0)

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	# The tail works harder the harder it swims; the body wiggles a beat ahead.
	if _tail:
		var effort: float = 2.2 if _state == SState.CHARGE else 1.0
		_tail.rotation.y = sin(_t * 3.2 * effort) * 0.35
		rotation.y += sin(_t * 3.2 * effort + PI * 0.5) * 0.006 * effort
		# Generated mesh: body wave + rim glow track the same effort. The glow numbers are
		# deliberately small — this animal is dark first. It reads as a shadow that has a
		# cold edge to it, and only really lights up in the seconds it commits to a charge.
		var hot: float = GLOW_HUNT if _state == SState.CHARGE else GLOW_IDLE
		ANIM.drive(_mats, 0.9 * effort, hot)
		var pulse: float = 1.0 + sin(_t * 1.7) * 0.25
		for p in _photophores:
			(p as StandardMaterial3D).emission_energy_multiplier = \
				(1.7 if _state == SState.CHARGE else 0.85) * pulse
	var player: Node3D = _player()
	var swimmer: bool = player != null and player.get("swimming") and player.swimming
	match _state:
		SState.PATROL:
			var a: float = _t * (PATROL_SPEED / _radius)
			var next: Vector3 = _center + Vector3(cos(a) * _radius, _depth + sin(_t * 0.3) * 0.6, sin(a) * _radius)
			_move_toward_point(next, delta, PATROL_SPEED)
			if swimmer and _cooldown <= 0.0 \
					and player.global_position.distance_to(global_position) < NOTICE_RADIUS:
				Journal.discover("creature_hammerhead")
				if not _judged:
					_judged = true
					if _rng.randf() < ATTACK_CHANCE:
						_state = SState.CHARGE
						AudioDirector.play_one_shot("groan", global_position, -10.0)
					else:
						_state = SState.CIRCLE
						_circle_t = 0.0
			elif not swimmer or player.global_position.distance_to(global_position) > NOTICE_RADIUS + 4.0:
				_judged = false   # the next approach is a fresh judgment
		SState.CIRCLE:
			# Spared — this pass. One slow ring around the swimmer, then away.
			_circle_t += delta
			if not swimmer or _circle_t > 7.0:
				_state = SState.PATROL
				_cooldown = 6.0
				return
			var ca: float = _circle_t * 0.9
			var around: Vector3 = player.global_position + Vector3(cos(ca) * 5.0, -0.8, sin(ca) * 5.0)
			_move_toward_point(around, delta, PATROL_SPEED * 1.2)
		SState.CHARGE:
			if not swimmer:
				_state = SState.PATROL   # target climbed out — the deck is not its world
				_cooldown = 4.0
				return
			var target: Vector3 = player.global_position + Vector3(0, -0.3, 0)
			_move_toward_point(target, delta, CHARGE_SPEED)
			if global_position.distance_to(player.global_position) < BITE_RADIUS:
				_bite(player)
		SState.FLEE:
			_move_toward_point(_flee_target, delta, CHARGE_SPEED * 0.8)
			if global_position.distance_to(_flee_target) < 3.0:
				_state = SState.PATROL

func _bite(player: Node3D) -> void:
	PlayerState.life -= BITE_DAMAGE
	PlayerState.warmth -= 0.1
	AudioDirector.play_one_shot("crab_snap", global_position, 2.0)   # hard bite crack
	AudioDirector.play_one_shot("splash", global_position, -2.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("HAMMERHEAD — it hit you. Get out of the water!")
	# Shove the swimmer aside and leave — a test, not a meal (Rule 3′).
	if player is CharacterBody3D:
		var away: Vector3 = (player.global_position - global_position).normalized()
		(player as CharacterBody3D).velocity += away * 6.0 + Vector3(0, 2.0, 0)
	_cooldown = _rng.randf_range(COOLDOWN_SEC_MIN, COOLDOWN_SEC_MAX)
	_flee_target = global_position + (global_position - player.global_position).normalized() * 18.0
	_flee_target.y = _depth
	_state = SState.FLEE

const MOVE := preload("res://scripts/world/fauna_move.gd")
const BODY_R: float = 1.2     ## the hammerhead is big — keep its bulk out of the steel

func _move_toward_point(target: Vector3, delta: float, speed: float) -> void:
	var to: Vector3 = target - global_position
	if to.length() < 0.05:
		return
	# A hammerhead is not a ghost: it cannot swim through the caissons, pontoons or the
	# drop net. Clamp the step at any solid in the way, and if it hits one, break off and
	# veer away instead of grinding into it — the same "meet a wall, pick a new heading"
	# rule the deck crawlers use.
	var want: Vector3 = global_position + to.limit_length(speed * delta)
	var res: Dictionary = MOVE.swim_clear(self, global_position, want, BODY_R)
	global_position = res["pos"]
	if res["blocked"] and _state != SState.FLEE:
		var away: Vector3 = (global_position - target)
		away.y = 0.0
		if away.length() < 0.5:
			away = Vector3(-to.z, 0.0, to.x)   # no clean push-off: veer sideways
		_flee_target = global_position + away.normalized() * 16.0
		_flee_target.y = _depth
		_state = SState.FLEE
	var flat := Vector3(to.x, 0, to.z)
	if flat.length_squared() > 0.0001:
		var desired: float = atan2(flat.x, flat.z)
		rotation.y = lerp_angle(rotation.y, desired + PI, delta * 3.0)
	rotation.z = lerp_angle(rotation.z, clampf(to.x * 0.02, -0.25, 0.25), delta * 2.0)

# ===========================================================================
# EVOLVED-BLOOM DRESSING
# Everything below is built AFTER ANIM.replace() (see _ready) and parented to `self`, so
# it inherits the body's yaw/roll/tail beat for free. It is deliberately all primitives:
# there are no API credits left to regenerate the GLB, and a mesh is not the only way to
# say "this animal grew something new".
# ===========================================================================

## One material, spelled once. Wet skin wants LOW roughness and a little metallic — the
## specular is most of what sells "just broke the surface" on a near-black hide.
static func _lit(col: Color, rough: float, metal: float,
		emit: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.62
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m

func _piece(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3,
		parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	(parent if parent != null else self).add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi

static func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b

static func _prism(sz: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = sz
	return p

## A unit-diameter sphere, shared. SphereMesh only exposes radius + height, so anything
## lens- or boss-shaped is made by scaling the INSTANCE — one mesh, many armour plates.
static var _sphere: SphereMesh = null
static func _unit_sphere() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 14
		_sphere.rings = 7
	return _sphere

## DERMAL MOTTLE. Shark skin is not a flat colour — it is denticles, and at any distance
## that reads as a fine tonal grain. Cellular noise ramped over a NARROW range (0.80..1.0)
## multiplies the hide down by at most a fifth: enough that the light catches unevenly,
## far too little to read as camouflage or as a rash. Shared by every hammerhead.
static func _dermal_tex() -> Texture2D:
	if _dermal != null:
		return _dermal
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	n.frequency = 0.055
	n.fractal_octaves = 3
	var g := Gradient.new()
	g.set_color(0, Color(0.80, 0.82, 0.86))
	g.set_color(1, Color(1.0, 1.0, 1.0))
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.color_ramp = g
	_dermal = t
	return _dermal

## Retune the generated mesh's surfaces: drop the tropical albedo for the dermal mottle,
## take the colour from HIDE_COL, and tighten the fresnel so the rim glow is a hairline
## rather than a wash. CreatureAnim.apply() copied the GLB's own albedo_color into `tint`,
## which is why this has to run after replace() rather than be passed into it.
func _shade_generated() -> void:
	var tex := _dermal_tex()
	for m in _mats:
		var sm: ShaderMaterial = m
		sm.set_shader_parameter("albedo_tex", tex)
		sm.set_shader_parameter("tint", HIDE_COL)
		sm.set_shader_parameter("roughness_v", 0.36)
		sm.set_shader_parameter("metallic_v", 0.12)
		sm.set_shader_parameter("use_normal", false)
		sm.set_shader_parameter("glow_color", GLOW)
		sm.set_shader_parameter("glow_energy", GLOW_IDLE)
		sm.set_shader_parameter("rim_power", 4.5)

func _build_bloom(d: Dictionary) -> void:
	_build_ridge(d)
	_build_flanks(d)
	_build_belly(d)
	_build_head_armour(d)
	_build_eyes(d)
	_build_teeth(d)

## THE DORSAL RIDGE — a line of tessellated plates running snout to tail, up the leading
## edge of the dorsal and out along the caudal lobe. Each plate is laid on the tangent of
## the spine polyline, so the line stays flush over the curve instead of stair-stepping,
## and every third plate carries a low nacre spine. Deep-sea chiton, not spikes on a prop.
func _build_ridge(d: Dictionary) -> void:
	var pts: Array = d["ridge"]
	var sc: float = d["sc"]
	var plate := _lit(ARMOR_COL, 0.22, 0.36)
	var rim := _lit(NACRE_COL, 0.16, 0.55)
	var step: float = 0.135 * sc
	var i: int = 0
	for k in range(pts.size() - 1):
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var seg: Vector2 = b - a
		var n: int = maxi(1, int(round(seg.length() / step)))
		# seg.x is z, seg.y is y: a rotation of -atan2(dy,dz) about X lays local +Z on it.
		var rx: float = -rad_to_deg(atan2(seg.y, seg.x))
		for j in range(n):
			var p: Vector2 = a + seg * (float(j) / float(n))
			var w: float = clampf(0.26 - 0.062 * absf(p.x + 0.3), 0.065, 0.26) * sc
			var l: float = seg.length() / float(n) * 1.06
			# One pivot per station carries the tangent, so the blades below can take their
			# OWN local rotation without Godot's YXZ order swinging the tangent off-axis.
			var pv := Node3D.new()
			add_child(pv)
			pv.position = Vector3(0.0, p.y, p.x)
			pv.rotation_degrees = Vector3(rx, 0, 0)
			_piece(_box(Vector3(w, 0.048 * sc, l)), plate, Vector3.ZERO, Vector3.ZERO, pv)
			_piece(_box(Vector3(w * 0.40, 0.018 * sc, l * 0.88)), rim,
				Vector3(0.0, 0.031 * sc, 0.0), Vector3.ZERO, pv)
			if i % 3 == 0:
				# A low keeled BLADE, not a post: the prism's triangle is authored in XY, so
				# yawing it 90 lays the base along the body and leaves it a few centimetres
				# thick across — a serration you read in profile and barely see head-on.
				_piece(_prism(Vector3(l * 1.15, 0.115 * sc, 0.038 * sc)), rim,
					Vector3(0.0, 0.045 * sc, 0.0), Vector3(0, 90, 0), pv)
			i += 1

## FLANK ARMOUR — a band of overlapping dermal plates down each side, exactly mirrored.
## Each plate is WIDER THAN IT IS TALL and thin across, so it lies along the flank like an
## imbricated scale instead of standing off it like a crate; the cluster root sits at the
## measured halfwidth, which leaves roughly half of each plate sunk into the body. Sparse
## on purpose — the silhouette has to stay a shark's, and the eye should find the armour,
## not be buried by it.
const _SCALES := [
	# offset (y, z), length scale, tilt degrees
	Vector4(0.000, 0.000, 1.00, 0.0),
	Vector4(0.108, -0.032, 0.84, -7.0),
	Vector4(-0.104, 0.026, 0.80, 6.0),
]
func _build_flanks(d: Dictionary) -> void:
	var sc: float = d["sc"]
	var plate := _lit(ARMOR_COL, 0.21, 0.38)
	var rim := _lit(NACRE_COL, 0.17, 0.55)
	var lamp := _lit(Color(0.10, 0.13, 0.16), 0.30, 0.0, GLOW, 0.45)
	_photophores.append(lamp)
	var st_i: int = 0
	for s in d["flank"]:
		var st: Vector3 = s      # (z, halfwidth, y)
		for side in [-1.0, 1.0]:
			var pv := Node3D.new()
			add_child(pv)
			pv.position = Vector3(side * st.y, st.z, st.x)
			pv.rotation_degrees = Vector3(0, 0, side * -10.0)
			var r_i: int = 0
			for v in _SCALES:
				var o: Vector4 = v
				# Lens-shaped, not boxy. A dermal scale is a smooth mineral boss; boxes read
				# as crates bolted to a shark, which is the wrong half of "evolved".
				var sq := _piece(_unit_sphere(), plate, Vector3(0.0, o.x * sc, o.y * sc),
					Vector3(o.w, side * 5.0 * float(r_i), 0.0), pv)
				sq.scale = Vector3(0.098, 0.112, 0.235 * o.z) * sc
				if r_i == 0:
					var rr := _piece(_unit_sphere(), rim,
						Vector3(0.0, 0.040 * sc, o.y * sc), Vector3(o.w, 0, 0), pv)
					rr.scale = Vector3(0.100, 0.036, 0.200) * sc
				r_i += 1
			# One cold photophore per other station, tucked under the leading plate. Sparse:
			# a shark that lights up along its whole length is a lure, not a predator.
			if st_i % 2 == 0:
				var sm := SphereMesh.new()
				sm.radius = 0.030 * sc
				sm.height = 0.060 * sc
				sm.radial_segments = 10
				sm.rings = 6
				_piece(sm, lamp, Vector3(0.028 * sc, -0.165 * sc, 0.02 * sc),
					Vector3.ZERO, pv)
		st_i += 1

## COUNTER-SHADING. The shader has no way to grade dark-back-to-pale-belly (it samples one
## albedo and this file does not own the shader), so the pale underside is GEOMETRY: a
## shallow keel panel that follows the measured belly line, sitting a couple of centimetres
## proud. From the side it reads as the pale line every open-water shark carries.
func _build_belly(d: Dictionary) -> void:
	var sc: float = d["sc"]
	var pale := _lit(BELLY_COL, 0.44, 0.05)
	var pts: Array = d["belly"]
	for k in range(pts.size() - 1):
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var dz: float = b.x - a.x
		var dy: float = b.z - a.z
		var w: float = (a.y + b.y) * 0.5 * 1.45 * sc
		var l: float = sqrt(dz * dz + dy * dy) * 1.04
		var tilt: float = -rad_to_deg(atan2(dy, dz))
		var mid := Vector3(0.0, (a.z + b.z) * 0.5 + 0.038 * sc, (a.x + b.x) * 0.5)
		_piece(_box(Vector3(w, 0.058 * sc, l)), pale, mid, Vector3(tilt, 0, 0))
		# Two strakes canted up the lower flank. The keel plate alone is edge-on from
		# abeam — invisible exactly where counter-shading is supposed to be read — so the
		# pale carries a little way up each side, which is where a real shark's does.
		for side in [-1.0, 1.0]:
			_piece(_box(Vector3(0.050 * sc, 0.100 * sc, l)), pale,
				mid + Vector3(side * w * 0.40, 0.058 * sc, 0.0),
				Vector3(tilt, 0, side * 30.0))

## HEAD PLATING. A short crest along the top of the cephalofoil, and — on the generated
## mesh — armoured caps over the two horns it was born with, which turns a pair of stray
## Meshy spurs into part of the same mineral system as the ridge.
func _build_head_armour(d: Dictionary) -> void:
	var sc: float = d["sc"]
	var plate := _lit(ARMOR_COL, 0.22, 0.36)
	var rim := _lit(NACRE_COL, 0.16, 0.55)
	var i: int = 0
	for c in d["crest"]:
		var p: Vector3 = c     # (z, unused, y)
		var w: float = (0.30 - 0.045 * float(i)) * sc
		_piece(_box(Vector3(w, 0.042 * sc, 0.15 * sc)), plate,
			Vector3(0.0, p.z, p.x), Vector3(-6.0, 0, 0))
		_piece(_box(Vector3(w * 0.4, 0.016 * sc, 0.135 * sc)), rim,
			Vector3(0.0, p.z + 0.028 * sc, p.x), Vector3(-6.0, 0, 0))
		# A pair of low plates flanking the crest, so the head reads as tessellated.
		for side in [-1.0, 1.0]:
			_piece(_box(Vector3(0.14 * sc, 0.036 * sc, 0.125 * sc)), plate,
				Vector3(side * (w * 0.5 + 0.09 * sc), p.z - 0.018 * sc, p.x),
				Vector3(-6.0, 0, side * -18.0))
		i += 1
	var horn: Vector3 = d["horn"]
	if horn.x <= 0.001:
		return
	# THE HORNS. The generated mesh came with two spurs above the skull that belong to no
	# anatomy in particular. Rather than fight them, they get banded — three narrowing
	# armour rings and a nacre blade at the tip — which folds them into the same mineral
	# system as the ridge and reads as a crest instead of as a modelling accident.
	for side in [-1.0, 1.0]:
		var pv := Node3D.new()
		add_child(pv)
		pv.position = Vector3(side * horn.x, horn.y, horn.z)
		pv.rotation_degrees = Vector3(-8.0, 0, side * -7.0)
		var band: int = 0
		for h in [-0.01, 0.14]:
			var k: float = 1.0 - 0.24 * float(band)
			_piece(_box(Vector3(0.185 * sc * k, 0.046 * sc, 0.175 * sc * k)), plate,
				Vector3(0.0, h * sc, 0.0), Vector3.ZERO, pv)
			band += 1
		_piece(_prism(Vector3(0.115 * sc, 0.135 * sc, 0.042 * sc)), rim,
			Vector3(0.0, 0.28 * sc, 0.0), Vector3(0, 90, 0), pv)

## THE FOUR EYES.
##
## Four stalks, TWO PER SIDE — one up-and-out, one down-and-out — so the eyes sit at the
## four corners of an X seen head-on. The geometry is generated from ONE set of numbers so
## the symmetry cannot drift: every stalk is `stalk` metres long, every one leaves the head
## at exactly STALK_DEG from the body plane, and the only thing that differs between the
## four is the sign of the lateral and vertical components. That gives
##     eye = (±(lobe_x + L·cos35), head.y ± L·sin35, head.z)
## which is equal-and-opposite in x for the upper pair and for the lower pair, and puts all
## four at the same distance from the head centre. tests/SharkShot.tscn asserts exactly
## that from eye_positions() rather than trusting the reading.
##
## Each stalk is a pivot Node3D parented to the body, so it inherits the swim yaw and the
## roll on a turn; the stalk, its armoured collar and the eye all hang off that pivot.
const _STALK_PROFILE := [       ## (fraction along the stalk, radius) — thick root, thin neck
	Vector2(0.00, 0.130), Vector2(0.34, 0.092),
	Vector2(0.66, 0.062), Vector2(1.00, 0.046),
]
func _build_eyes(d: Dictionary) -> void:
	var sc: float = d["sc"]
	var head: Vector3 = d["head"]
	var lobe: float = d["lobe_x"]
	var L: float = d["stalk"]
	var er: float = d["eye_r"]
	var hide_m := _lit(HIDE_COL * 1.35, 0.32, 0.14)
	var collar := _lit(ARMOR_COL, 0.24, 0.30)
	var rim := _lit(NACRE_COL, 0.15, 0.60)
	var sclera := _lit(Color(0.048, 0.058, 0.078), 0.06, 0.35)
	var iris := _lit(Color(0.06, 0.11, 0.17), 0.10, 0.0, GLOW, 1.35)
	_photophores.append(iris)
	_eyes.clear()
	for side in [-1.0, 1.0]:
		for up in [1.0, -1.0]:
			var pivot := Node3D.new()
			add_child(pivot)
			pivot.position = Vector3(side * lobe, head.y, head.z)
			# Rotating +Y (the cylinder/prism axis) onto d = (side·cos35, up·sin35, 0)
			# takes a single Z rotation of atan2(-dx, dy) — mirrored by construction.
			var dx: float = side * cos(deg_to_rad(STALK_DEG))
			var dy: float = up * sin(deg_to_rad(STALK_DEG))
			pivot.rotation.z = atan2(-dx, dy)
			# The stalk is a MUSCULAR PEDUNCLE, not a tube: it leaves the skull thick and
			# necks down hard into the socket. (An early pass made it a constant-radius
			# cylinder with a ring at the tip and the whole animal read as four cannons —
			# taper plus a plated base is what turns it back into an animal.)
			for i_seg in range(_STALK_PROFILE.size() - 1):
				var seg: Vector2 = _STALK_PROFILE[i_seg]
				var nxt: Vector2 = _STALK_PROFILE[i_seg + 1]
				var cyl := CylinderMesh.new()
				cyl.bottom_radius = seg.y * sc
				cyl.top_radius = nxt.y * sc
				cyl.height = (nxt.x - seg.x) * L
				cyl.radial_segments = 12
				cyl.rings = 1
				_piece(cyl, hide_m, Vector3(0.0, (seg.x + nxt.x) * 0.5 * L, 0.0),
					Vector3.ZERO, pivot)
				# A narrow armour band at each joint — the stalk is plated too, but the
				# bands are rounded: square collars turned the stalks into hydraulic rams.
				var bd := _piece(_unit_sphere(), collar, Vector3(0.0, nxt.x * L, 0.0),
					Vector3.ZERO, pivot)
				bd.scale = Vector3(nxt.y * 2.6, 0.055, nxt.y * 2.6) * sc
			# Armoured collar where the stalk leaves the head: a ring plus three splayed
			# plates, so the socket looks grown into the skull rather than screwed on.
			var tor := TorusMesh.new()
			tor.inner_radius = 0.130 * sc
			tor.outer_radius = 0.205 * sc
			tor.rings = 12
			tor.ring_segments = 8
			_piece(tor, collar, Vector3(0.0, 0.045 * sc, 0.0), Vector3.ZERO, pivot)
			for a in [-58.0, 58.0]:
				var cp := _piece(_unit_sphere(), collar, Vector3(0.0, 0.105 * sc, 0.0),
					Vector3(-14.0, a, 0), pivot)
				cp.scale = Vector3(0.115, 0.055, 0.185) * sc
			var bulb := SphereMesh.new()
			bulb.radius = er
			bulb.height = er * 2.0
			bulb.radial_segments = 20
			bulb.rings = 12
			var eye := _piece(bulb, sclera, Vector3(0.0, L, 0.0), Vector3.ZERO, pivot)
			# THE IRIS is a RING around the bulb's equator, not a cap on its end. A cap only
			# lights up for whoever is standing on the stalk's axis — from every other angle
			# the animal wore four black golf balls. The ring circles the eye perpendicular
			# to the stalk, so it catches the light from any approach, and it is the one
			# place the bioluminescence is allowed to be bright. Everything else stays dark.
			var band := TorusMesh.new()
			band.inner_radius = er * 0.82
			band.outer_radius = er * 1.04
			band.rings = 20
			band.ring_segments = 8
			_piece(band, iris, Vector3(0.0, er * 0.10, 0.0), Vector3.ZERO, eye)
			# The PUPIL faces FORWARD (body -Z), not out along the stalk. The pivot only
			# rotates about Z, so local -Z is still the way the animal is swimming whichever
			# corner of the X this eye occupies — which means all four look where it is
			# going, and a head-on charge shows four points of light instead of four
			# silhouettes. (A tip-mounted lens only lit up for whoever stood on the axis.)
			var pup := SphereMesh.new()
			pup.radius = er * 0.46
			pup.height = er * 0.92
			pup.radial_segments = 14
			pup.rings = 8
			_piece(pup, iris, Vector3(0.0, 0.0, -er * 0.70), Vector3.ZERO, eye)
			# Three brow plates behind the bulb — a bony orbit, the way an armoured animal
			# protects the one soft thing it has left.
			for a in [-60.0, 60.0, 180.0]:
				_piece(_box(Vector3(er * 0.62, er * 0.26, er * 0.90)), collar,
					Vector3(0.0, -er * 0.55, 0.0), Vector3(-30.0, a, 0), eye)
			_eyes.append(eye)

## The four eye centres in WORLD space, upper pair first per side. Ordered
## [left-up, left-down, right-up, right-down] — the harness checks x is equal and opposite
## across the pairs and that all four are equidistant from the head.
func eye_positions() -> Array:
	var out: Array = []
	for e in _eyes:
		out.append((e as Node3D).global_position)
	return out

## TEETH. Big enough to read at charge distance — an order up from the millimetre nicks the
## generated mesh carries — but kept clean: pearl, geometric, arranged on a proper parabolic
## jaw with the centre teeth largest and the commissures small. Impressive dentition, not
## gore. Upper row hangs down-and-forward, lower row rises up-and-forward, and both fan
## outward toward the corners the way a real jaw does.
func _build_teeth(d: Dictionary) -> void:
	var sc: float = d["sc"]
	var m: Vector3 = d["mouth"]
	var hw: float = d["mouth_hw"]
	var bow: float = d["mouth_bow"]
	var th: float = d["tooth"] * sc
	var gum := _lit(Color(0.075, 0.085, 0.095), 0.42, 0.0)
	var enamel := _lit(TOOTH_COL, 0.20, 0.05)
	# A dark jaw line, so the teeth sit in a mouth instead of on a chin.
	_piece(_box(Vector3(hw * 2.15, 0.075 * sc, 0.10 * sc)), gum,
		Vector3(0.0, m.y, m.z - bow * 0.55), Vector3(-4.0, 0, 0))
	var n: int = 11
	for i in range(n):
		var f: float = float(i) / float(n - 1) * 2.0 - 1.0     # -1 .. +1 across the jaw
		var x: float = f * hw
		var z: float = m.z - bow * (1.0 - f * f)               # centre teeth furthest forward
		var k: float = lerpf(1.0, 0.55, absf(f))               # commissures taper away
		var fan: float = -f * 13.0
		_piece(_prism(Vector3(0.125 * sc * k, th * k, 0.05 * sc)), enamel,
			Vector3(x, m.y + 0.030 * sc, z), Vector3(195.0, 0.0, fan))
		_piece(_prism(Vector3(0.110 * sc * k, th * 0.82 * k, 0.045 * sc)), enamel,
			Vector3(x, m.y - 0.038 * sc, z), Vector3(-15.0, 0.0, -fan))
