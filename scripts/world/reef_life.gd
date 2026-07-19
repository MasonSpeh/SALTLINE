class_name ReefLife extends Node3D
## The reef that has grown on the wreck field and the rock ridge — placed as DEPTH-ZONED
## COMMUNITIES, not scattered singletons, so the bottom reads as ecology:
##   - current-swept ridge FLANKS: coral fans (edge-on to the flow) + sponges
##   - flat SHELVES / wreck tops: brain corals, sponge clusters, seastars, urchins,
##     a grazing nudibranch, a furling basket/feather star, sea cucumbers
##   - soft SILT bottom: sea-grass beds and crowded tube-worm fields, drifting salp chains
##   - a denning OCTOPUS in a wreck pipe, a freezing ISOPOD, a lone deep ANGLERFISH lure
##
## It reads the coral-shelf coordinates ReefDetail reports (so life sits on the real
## geometry, never guessed), grounds every model onto Seabed.floor_height, and gives
## each instance its own scale/rotation. Every placement tolerates a missing .glb —
## CreatureAnim.attach returns {} and that instance simply doesn't appear.
##
## Spawned as a child of ReefDetail; visual only, no collision.

const ANIM := preload("res://scripts/world/creature_anim.gd")
const SEABED := preload("res://scripts/world/seabed.gd")

const TEAL := Color(0.25, 0.95, 0.88)
const AMBER := Color(1.0, 0.62, 0.22)
const VIOLET := Color(0.75, 0.55, 1.0)
const PINK := Color(1.0, 0.55, 0.75)

var _shelves: Array = []
var _rng := RandomNumberGenerator.new()

func _init(shelves: Array = []) -> void:
	_shelves = shelves

func _ready() -> void:
	_rng.seed = 60640
	_populate_shelves()
	_populate_soft_bottom()
	_denning_octopus(Vector3(-8.5, 0, -57.0))       # a pipe end in the main wreck field
	_deep_anglerfish(Vector3(-19.0, 0, -45.0))       # rare, far out, all you see is the lure

# ------------------------------------------------------------ helpers

func floor_y(x: float, z: float) -> float:
	return SEABED.floor_height(Vector2(x, z))

func _path(slug: String) -> String:
	return "res://assets/models/fauna/%s/%s.glb" % [slug, slug]

## Attach a generated model under a fresh host at `pos`, size-normalised, driven once by
## the swim shader, and grounded so its base sits on the floor/shelf. Returns the host,
## or null when the .glb isn't there (host is freed).
func _sessile(slug: String, pos: Vector3, size: float, mode: int, amp: float, rate: float,
		energy: float, glow: Color = TEAL, opacity: float = 1.0, tilt: float = 0.0) -> Node3D:
	var host := Node3D.new()
	add_child(host)
	host.global_position = pos
	host.rotation.y = _rng.randf_range(0.0, TAU)
	if tilt > 0.0:
		host.rotation.x = _rng.randf_range(-tilt, tilt)
		host.rotation.z = _rng.randf_range(-tilt, tilt)
	var gen: Dictionary = ANIM.attach(host, _path(slug), size, mode, amp, rate, glow,
		_rng.randf() * TAU, opacity)
	if gen.is_empty():
		host.queue_free()
		return null
	ANIM.drive(gen["mats"], rate, energy)
	BloomFauna.ground_model(host, gen["model"])
	return host

## The height life actually RESTS on at (x, z).
##
## Most shelves ReefDetail reports are raised geometry — the reef-ridge crown at -12,
## the capsized workboat's bilge at -19.6, the container roof, the east outcrop — and
## life placed for them was being grounded to Seabed.floor_height instead, i.e. dropped
## onto the silt underneath. The ridge crown is the worst case and the one that matters
## most: it is the ONLY reef inside the player's 13 m dive limit, so its whole community
## was landing 11 m below the deepest water a player can reach, and the reachable reef
## was bare rock. When a shelf stands proud of the mud, the shelf IS the ground.
## Nothing this file plants is pelagic — the deepest reachable shelf is the ridge crown
## at -12 — so a "shelf" anywhere near the waterline is a bug in the caller, not a real
## perch. Refuse to seat life above this and the whole class of sentinel/uninitialised-y
## mistakes lands on the mud instead of bobbing on the swell.
const SHELF_CEILING: float = -6.0

static func support_y(x: float, z: float, shelf_y: float) -> float:
	var mud: float = SEABED.floor_height(Vector2(x, z))
	if shelf_y > mud + 0.5 and shelf_y < SHELF_CEILING:
		return shelf_y
	return mud

## True when this shelf is raised geometry rather than open mud.
static func _is_raised(pos: Vector3) -> bool:
	return pos.y > SEABED.floor_height(Vector2(pos.x, pos.z)) + 0.5 and pos.y < SHELF_CEILING

func _near(pos: Vector3, spread: float) -> Vector3:
	# On a raised shelf the plate is only a few metres across, so keep the community
	# ON it — a full-spread scatter would hang half the corals off the edge in mid-water.
	var eff: float = spread * 0.55 if _is_raised(pos) else spread
	var a: float = _rng.randf_range(0.0, TAU)
	var r: float = _rng.randf_range(0.0, eff)
	var x: float = pos.x + cos(a) * r
	var z: float = pos.z + sin(a) * r
	return Vector3(x, support_y(x, z, pos.y), z)

# ------------------------------------------------------------ shelf communities

func _populate_shelves() -> void:
	for s in _shelves:
		var p: Vector3 = s["pos"]
		var note: String = String(s.get("note", "")).to_lower()
		var deep: bool = p.y < -18.0
		if note.contains("swept") or note.contains("flank") or note.contains("face"):
			_swept_face(p, deep)
		else:
			_flat_shelf(p, deep)

## Current-swept rock: sea fans stood up to filter the flow, sponges bracketing them.
func _swept_face(p: Vector3, deep: bool) -> void:
	var fans: int = 6 if not deep else 4
	for i in range(fans):
		var fp := _near(p, 3.0)   # _near already seats it on the shelf, or the mud
		var host := _sessile("bloom_coral_fan", fp, _rng.randf_range(1.2, 2.2),
			ANIM.Mode.SWAY, 0.06, _rng.randf_range(0.5, 0.8),
			_rng.randf_range(0.25, 0.5), _fan_tint(), 1.0, 0.12)
		# fans stand proud and lean into the current, not flat on the rock
		if host != null:
			host.rotation.x = _rng.randf_range(-0.35, -0.1)
	for i in range(3):
		var sp := _near(p, 2.6)
		_sessile("bloom_sponge_cluster", sp, _rng.randf_range(0.7, 1.3),
			ANIM.Mode.BREATHE, 0.03, _rng.randf_range(0.25, 0.45),
			_rng.randf_range(0.2, 0.4), _sponge_tint(), 1.0, 0.15)
	# a tube-worm knot tucked at the base of the swept face
	_tube_worm_clump(_near(p, 2.0), 1 if deep else 2)

## Flat shelf / wreck top: the diverse plate. Brain corals, sponges, a seastar, urchins,
## sea cucumbers, a grazing nudibranch, and a furling basket or feather star.
func _flat_shelf(p: Vector3, deep: bool) -> void:
	for i in range(2 if deep else 3):
		var bp := _near(p, 3.2)
		_sessile("bloom_brain_coral", bp, _rng.randf_range(0.8, 1.5),
			ANIM.Mode.BREATHE, 0.02, 0.3, _rng.randf_range(0.18, 0.35),
			_brain_tint(), 1.0, 0.05)
	for i in range(3):
		var sp := _near(p, 3.4)
		_sessile("bloom_sponge_cluster", sp, _rng.randf_range(0.6, 1.2),
			ANIM.Mode.BREATHE, 0.03, 0.35, _rng.randf_range(0.2, 0.4),
			_sponge_tint(), 1.0, 0.15)
	for i in range(2):
		var up := _near(p, 3.0)
		_sessile("bloom_urchin", up, _rng.randf_range(0.35, 0.6),
			ANIM.Mode.BREATHE, 0.04, 0.4, _rng.randf_range(0.3, 0.6),
			VIOLET, 1.0, 0.0)
	_sessile("bloom_seastar", _near(p, 3.0), _rng.randf_range(0.5, 0.9),
		ANIM.Mode.BREATHE, 0.02, 0.25, 0.35, AMBER, 1.0, 0.1)
	_sessile("bloom_sea_cucumber", _near(p, 3.2), _rng.randf_range(0.6, 1.1),
		ANIM.Mode.BREATHE, 0.03, 0.22, 0.25, PINK, 1.0, 0.12)
	# a tube-worm cluster on the plate margin
	_tube_worm_clump(_near(p, 3.0), 2)
	# mobile life keyed to the plate
	var nud := Nudibranch.new(p)
	add_child(nud)
	# basket stars go deep, feather stars shallower — both furl by day, bloom by night
	var star_slug: String = "bloom_basket_star" if deep else "bloom_feather_star"
	var fs := FurlStar.new(star_slug, _near(p, 2.4))
	add_child(fs)
	if _rng.randf() < 0.6:
		var iso := Isopod.new(p)
		add_child(iso)
	if not deep and _rng.randf() < 0.5:
		# a sea spider stilt-walking the shallow plate
		var spider := Isopod.new(p, "bloom_sea_spider", 0.7, 0.55)
		add_child(spider)

func _tube_worm_clump(base: Vector3, n: int) -> void:
	for i in range(n):
		var a: float = _rng.randf_range(0.0, TAU)
		var r: float = _rng.randf_range(0.2, 0.8)
		var x: float = base.x + cos(a) * r
		var z: float = base.z + sin(a) * r
		# base already carries its support height (mud or shelf top) — keep it.
		_sessile("bloom_tube_worms", Vector3(x, support_y(x, z, base.y), z),
			_rng.randf_range(0.7, 1.2), ANIM.Mode.CIRRI, 0.05,
			_rng.randf_range(0.5, 0.9), _rng.randf_range(0.35, 0.6),
			_fan_tint(), 1.0, 0.06)

# ------------------------------------------------------------ soft bottom

## The silt flats between the rig and the wreck: sea-grass meadows, tube-worm fields, sea
## cucumbers ploughing the mud, and salp chains drifting a metre off the bottom.
func _populate_soft_bottom() -> void:
	var beds := [Vector2(-4, -38), Vector2(3, -46), Vector2(-13, -42),
			Vector2(16, -40), Vector2(-2, -58)]
	for b in beds:
		# The bed's own seat on the mud. These used to be built as Vector3(b.x, 0, b.y),
		# with the 0 meaning "no shelf, ground it" — which _near honoured only because it
		# re-grounded unconditionally. Now that a raised y IS a perch, that 0 read as a
		# shelf at the WATERLINE and floated every meadow on the open sea. Pass the real
		# mudline instead of a sentinel.
		var bed_pos := Vector3(b.x, floor_y(b.x, b.y), b.y)
		# sea-grass meadow: a dense low clump, per-blade scale/rotation variation
		var blades: int = _rng.randi_range(7, 12)
		for i in range(blades):
			var gp := _near(bed_pos, 3.2)
			_sessile("bloom_sea_grass", gp, _rng.randf_range(1.0, 2.0),
				ANIM.Mode.SWAY, 0.12, _rng.randf_range(0.5, 0.9),
				_rng.randf_range(0.12, 0.28), Color(0.35, 0.9, 0.6), 1.0, 0.0)
		# a tube-worm field on the edge of the meadow
		_tube_worm_clump(_near(bed_pos, 3.5), _rng.randi_range(2, 4))
		# a cucumber or two ploughing the silt
		for i in range(_rng.randi_range(1, 2)):
			_sessile("bloom_sea_cucumber", _near(bed_pos, 3.0),
				_rng.randf_range(0.7, 1.2), ANIM.Mode.BREATHE, 0.03, 0.2,
				0.2, PINK, 1.0, 0.1)
	# salp chains drifting just off the bottom (translucent, gelatinous)
	for c in [Vector3(0, -20.5, -44), Vector3(-10, -20.0, -50), Vector3(8, -20.0, -55)]:
		var host := _sessile("bloom_salp_chain", Vector3(c.x, floor_y(c.x, c.z), c.z),
			2.4, ANIM.Mode.UNDULATE, 0.08, 0.6, 0.4, Color(0.7, 0.95, 1.0), 0.5)
		if host != null:
			host.position.y = c.y   # lift it into the water column
			host.add_child(SalpDrift.new())

# ------------------------------------------------------------ tints

func _fan_tint() -> Color:
	return [TEAL, PINK, VIOLET][_rng.randi() % 3]
func _sponge_tint() -> Color:
	return [AMBER, Color(0.9, 0.7, 0.5), Color(0.6, 0.85, 0.9)][_rng.randi() % 3]
func _brain_tint() -> Color:
	return [Color(0.5, 0.9, 0.8), Color(0.7, 0.85, 0.6)][_rng.randi() % 2]

# ------------------------------------------------------------ octopus + anglerfish

## An octopus that dens in a wreck pipe by day and crawls out to hunt the rubble after
## dark. By day it sits tucked and dim at the den mouth; at night it emerges and its
## mantle lights. Grounds onto the floor at both ends.
func _denning_octopus(around: Vector3) -> void:
	var den := Vector3(around.x, floor_y(around.x, around.z) + 0.3, around.z)
	var oct := DenningOctopus.new(den)
	add_child(oct)

## One anglerfish, deep and rare: the body barely registers in the dark — the lure is
## the only thing you see, a single bob of light drawing you in.
func _deep_anglerfish(around: Vector3) -> void:
	var pos := Vector3(around.x, floor_y(around.x, around.z) + 1.4, around.z)
	var ang := DeepAngler.new(pos)
	add_child(ang)

# ============================================================ BEHAVIOURS

## Nudibranch: grazes a slow loop across its plate and BRIGHTENS when the player's light
## gets close — the Bloom answering the intrusion. PEDAL foot wave.
class Nudibranch extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	var _home: Vector3
	var _mats: Array = []
	var _t: float = 0.0
	var _glow: float = 0.25

	func _init(home: Vector3) -> void:
		_home = home

	func _ready() -> void:
		global_position = _home
		var gen: Dictionary = ANIM.attach(self, "res://assets/models/fauna/bloom_nudibranch/bloom_nudibranch.glb",
			0.45, ANIM.Mode.PEDAL, 0.05, 0.7, Color(1.0, 0.5, 0.85), randf() * TAU)
		if gen.is_empty():
			queue_free()
			return
		_mats = gen["mats"]
		BloomFauna.ground_model(self, gen["model"])
		_t = randf() * 100.0

	func _process(delta: float) -> void:
		_t += delta
		# slow graze loop, hugging the plate
		var a: float = _t * 0.12
		var tgt := _home + Vector3(cos(a) * 1.4, 0.0, sin(a * 1.3) * 1.4)
		# Graze the plate it was placed on. Re-grounding to the raw mudline every frame
		# walked shelf-dwellers off their rock and sank them into the silt below it.
		tgt.y = ReefLife.support_y(tgt.x, tgt.z, _home.y)
		var vel: Vector3 = tgt - global_position
		global_position = global_position.lerp(tgt, delta * 0.8)
		var flat := Vector3(vel.x, 0, vel.z)
		if flat.length_squared() > 0.0001:
			look_at(global_position + flat, Vector3.UP)
		# brighten near the player (its "light")
		var want: float = 0.25
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player != null:
			var d: float = player.global_position.distance_to(global_position)
			if d < 5.0:
				want = lerpf(1.4, 0.25, clampf(d / 5.0, 0.0, 1.0))
		_glow = lerpf(_glow, want, delta * 2.0)
		ANIM.drive(_mats, 0.7 + (_glow - 0.25) * 0.4, _glow)

## Basket / feather star: FURLED (drawn in small) by day, UNFURLED (arms spread) by
## night, when it climbs a perch and opens to filter the dark. Pure scale + glow lerp
## over the CIRRI arm beat.
class FurlStar extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	var _slug: String
	var _home: Vector3
	var _mats: Array = []
	var _model: Node3D
	var _open: float = 0.0
	var _base_scale: float = 1.0

	func _init(slug: String, home: Vector3) -> void:
		_slug = slug
		_home = home

	func _ready() -> void:
		global_position = _home
		var gen: Dictionary = ANIM.attach(self, "res://assets/models/fauna/%s/%s.glb" % [_slug, _slug],
			1.1, ANIM.Mode.CIRRI, 0.06, 0.5, Color(0.6, 0.9, 1.0), randf() * TAU)
		if gen.is_empty():
			queue_free()
			return
		_mats = gen["mats"]
		_model = gen["model"]
		_base_scale = _model.scale.x
		BloomFauna.ground_model(self, _model)

	func _process(delta: float) -> void:
		var want: float = 1.0 if BloomFauna.is_dark_phase() else 0.0
		_open = lerpf(_open, want, delta * 0.4)
		if _model != null:
			var s: float = _base_scale * lerpf(0.4, 1.0, _open)
			_model.scale = Vector3(s, _base_scale * lerpf(0.55, 1.0, _open), s)
		ANIM.drive(_mats, 0.5, lerpf(0.1, 0.7, _open))

## Isopod (and, reused, the sea spider): SCUTTLES its plate, but FREEZES stock-still the
## moment the player is looking at it or standing over it — the classic tide-pool
## vanishing act.
class Isopod extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	var _home: Vector3
	var _slug: String
	var _size: float
	var _rate: float
	var _mats: Array = []
	var _t: float = 0.0
	var _frozen: float = 0.0

	func _init(home: Vector3, slug: String = "bloom_isopod", size: float = 0.4, rate: float = 0.9) -> void:
		_home = home
		_slug = slug
		_size = size
		_rate = rate

	func _ready() -> void:
		global_position = Vector3(_home.x, ReefLife.support_y(_home.x, _home.z, _home.y), _home.z)
		var gen: Dictionary = ANIM.attach(self, "res://assets/models/fauna/%s/%s.glb" % [_slug, _slug],
			_size, ANIM.Mode.SCUTTLE, 0.05, _rate, Color(0.8, 0.9, 0.7), randf() * TAU)
		if gen.is_empty():
			queue_free()
			return
		_mats = gen["mats"]
		BloomFauna.ground_model(self, gen["model"])
		_t = randf() * 100.0

	func _process(delta: float) -> void:
		var watched: bool = _is_watched()
		_frozen = lerpf(_frozen, 1.0 if watched else 0.0, delta * (6.0 if watched else 2.0))
		var move: float = 1.0 - _frozen
		if move > 0.05:
			_t += delta * move
			var a: float = _t * 0.5
			var tgt := _home + Vector3(cos(a) * 1.6, 0.0, sin(a * 1.7) * 1.6)
			tgt.y = ReefLife.support_y(tgt.x, tgt.z, _home.y)   # scuttle its plate, not the mud
			var vel: Vector3 = tgt - global_position
			global_position = global_position.lerp(tgt, delta * 1.2 * move)
			var flat := Vector3(vel.x, 0, vel.z)
			if flat.length_squared() > 0.0001:
				look_at(global_position + flat, Vector3.UP)
		ANIM.drive(_mats, _rate * move, 0.3 * move)

	func _is_watched() -> bool:
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player == null:
			return false
		var d: float = player.global_position.distance_to(global_position)
		if d < 2.4:
			return true
		if d > 12.0:
			return false
		var cam: Camera3D = player.get_node_or_null("Head/Camera3D")
		if cam == null:
			return false
		var fwd: Vector3 = -cam.global_transform.basis.z
		var to: Vector3 = (global_position - cam.global_position).normalized()
		return fwd.dot(to) > 0.985   # roughly centred in view

## Octopus: dens in a wreck pipe by day, emerges after dark. Lerps between a tucked, dim
## den pose and an emerged, lit hunting pose over the CIRRI/undulate arm motion.
class DenningOctopus extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	var _den: Vector3
	var _out: Vector3
	var _mats: Array = []
	var _model: Node3D
	var _emerge: float = 0.0
	var _t: float = 0.0

	func _init(den: Vector3) -> void:
		_den = den

	func _ready() -> void:
		_out = _den + Vector3(1.8, 0.0, 1.2)
		_out.y = SEABED.floor_height(Vector2(_out.x, _out.z)) + 0.2   # den + crawl are both on the mud
		global_position = _den
		var gen: Dictionary = ANIM.attach(self, "res://assets/models/fauna/bloom_octopus/bloom_octopus.glb",
			1.0, ANIM.Mode.UNDULATE, 0.07, 0.5, Color(0.9, 0.45, 0.8), randf() * TAU)
		if gen.is_empty():
			queue_free()
			return
		_mats = gen["mats"]
		_model = gen["model"]
		BloomFauna.ground_model(self, _model)
		_t = randf() * 100.0

	func _process(delta: float) -> void:
		_t += delta
		var want: float = 1.0 if BloomFauna.is_dark_phase() else 0.0
		_emerge = lerpf(_emerge, want, delta * 0.3)
		var wander := Vector3(sin(_t * 0.4) * 0.5, 0.0, cos(_t * 0.33) * 0.5) * _emerge
		global_position = _den.lerp(_out, _emerge) + wander
		if _model != null:
			var s: float = lerpf(0.55, 1.0, _emerge)   # balled-up in the den, spread out hunting
			_model.scale = Vector3(s, s, s) * (_model_base())
		ANIM.drive(_mats, 0.4 + _emerge * 0.5, lerpf(0.05, 0.6, _emerge))

	var _mb: float = -1.0
	func _model_base() -> float:
		if _mb < 0.0 and _model != null:
			_mb = _model.scale.x
		return maxf(_mb, 0.001)

## The deep anglerfish: the body is a dark shape you can barely make out; the LURE is a
## single bob of light on its stalk, drifting in the black. That light is the whole point.
class DeepAngler extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	var _home: Vector3
	var _mats: Array = []
	var _t: float = 0.0
	var _lure: MeshInstance3D
	var _lure_light: OmniLight3D
	var _lure_mat: StandardMaterial3D

	func _init(home: Vector3) -> void:
		_home = home

	func _ready() -> void:
		global_position = _home
		var gen: Dictionary = ANIM.attach(self, "res://assets/models/fauna/bloom_anglerfish/bloom_anglerfish.glb",
			1.6, ANIM.Mode.UNDULATE, 0.05, 0.4, Color(0.3, 0.6, 0.9), randf() * TAU)
		if not gen.is_empty():
			_mats = gen["mats"]
			ANIM.drive(_mats, 0.4, 0.04)   # body barely glows — nearly invisible in the deep
		# The lure: a small bright bead + a soft light, out in front of the head (-Z).
		_lure_mat = StandardMaterial3D.new()
		_lure_mat.albedo_color = Color(0.7, 0.95, 1.0)
		_lure_mat.emission_enabled = true
		_lure_mat.emission = Color(0.6, 0.9, 1.0)
		_lure_mat.emission_energy_multiplier = 6.0
		_lure_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var bead := SphereMesh.new()
		bead.radius = 0.06
		bead.height = 0.12
		bead.material = _lure_mat
		_lure = MeshInstance3D.new()
		_lure.mesh = bead
		add_child(_lure)
		_lure.position = Vector3(0, 0.7, -1.1)
		_lure_light = OmniLight3D.new()
		_lure_light.light_color = Color(0.55, 0.85, 1.0)
		_lure_light.light_energy = 1.6
		_lure_light.omni_range = 6.0
		add_child(_lure_light)
		_lure_light.position = _lure.position
		_t = randf() * 100.0

	func _process(delta: float) -> void:
		_t += delta
		# a slow prowl in a small deep patch
		var tgt := _home + Vector3(cos(_t * 0.06) * 4.0, sin(_t * 0.05) * 0.6, sin(_t * 0.045) * 4.0)
		var vel: Vector3 = tgt - global_position
		global_position = global_position.lerp(tgt, delta * 0.4)
		var flat := Vector3(vel.x, 0, vel.z)
		if flat.length_squared() > 0.0001:
			look_at(global_position + flat, Vector3.UP)
		# the lure jigs — the bob that draws prey (and the player) in
		var bob: float = sin(_t * 1.7) * 0.12 + sin(_t * 0.9) * 0.06
		_lure.position = Vector3(sin(_t * 1.1) * 0.1, 0.7 + bob, -1.1)
		_lure_light.position = _lure.position
		var pulse: float = 4.5 + sin(_t * 2.3) * 2.0
		_lure_mat.emission_energy_multiplier = pulse
		_lure_light.light_energy = 1.0 + sin(_t * 2.3) * 0.6

## Salp chain: a translucent gelatinous string pulsing slowly through the water column.
## Rides its parent (the salp host) so the model actually drifts, not this empty node.
class SalpDrift extends Node3D:
	var _t: float = 0.0
	func _ready() -> void:
		_t = randf() * 100.0
	func _process(delta: float) -> void:
		_t += delta
		var host: Node3D = get_parent() as Node3D
		if host == null:
			return
		host.position += Vector3(sin(_t * 0.2) * delta * 0.3, sin(_t * 0.13) * delta * 0.1, cos(_t * 0.17) * delta * 0.3)
		host.rotation.y += delta * 0.15
