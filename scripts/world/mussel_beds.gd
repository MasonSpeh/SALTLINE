extends Node3D
## HARVESTABLE MUSSEL BEDS through the caisson coral (owner brief, s21: "harvestable
## mussels scattered throughout the coral ... it needs to be boiled to eat good ... mussels
## regenerate every 5 days from picking").
##
## The reef was, until now, entirely look-at: 1,170 MultiMesh instances of coral, sponge,
## barnacle and starfish that a diver swims through and cannot touch. This is the first
## thing down there the player can take, and it is the only renewable food source on the rig
## that is neither caught on a hook nor scraped off the wet deck.
##
## WHY IT IS ITS OWN FILE. leg_reef.gd owns the look of the reef and is shared with a
## concurrent session; reef_fish.gd already established the pattern of a separate file that
## takes `colony_seats` and builds the life that lives on the coral. This is the same shape,
## for the same reason: nothing here is a MultiMesh (each bed is an interactable node with a
## collider), the placement rule is different (mussels want the SHALLOW half of the band, see
## _dive_floor), and it drives the save system, which no part of the reef did before.
##
## WHAT IS MEASURED RATHER THAN TYPED
##   * every bed's seat and surface normal — a physics raycast into the real concrete, from
##     the colony centre leg_reef recorded. Nothing in this file hand-types an X, Y or Z
##     against the caisson, and a candidate whose ray finds nothing is REFUSED rather than
##     seated on a guess (a Salvage node needs a real collider under it: the player's
##     interaction ray has to be able to hit the bed, and the probe measures flushness
##     against the surface the bed claims to be on).
##   * how deep a bed may be — derived from the PLAYER CONTROLLER's own air budget, not from
##     a number somebody liked the look of. See _dive_floor: food the player cannot reach on
##     one breath is not food.
##   * where the coral actually is — the seats come from leg_reef, so a bed can never end up
##     on a patch of bare concrete the reef's own spacing rejection threw away.
##
## FIVE DAYS, and why it is not a number of seconds. See Salvage.regrow_game_hours and
## GameClock.game_time_hours(). A real-seconds countdown cannot see a night the player slept
## through, so `regrow_days: 5.0` is counted on the calendar instead.

const SALVAGE := preload("res://scripts/components/salvage.gd")
const REEF_PATH := "res://assets/models/fauna/reef/%s/%s.glb"
## For the air budget below. By path, not class_name — the global class cache lags.
const PC := preload("res://scripts/components/player_controller.gd")

## THE MESHES. Two assets, both cut by tools/decimate_reef.py to the reef contract
## (+Y = growth, base at y = 0, XZ centred), so a bed's +Y goes straight onto a probed
## normal like every other reef piece.
##
## `mussel_bed_e` is the mat: NINE large adult shells lying flat in one overlapping layer,
## 0.18 deep against 1.00 across — the low encrusting crust the brief asked for. It is what
## the player harvests and it is always the piece left standing (Salvage._strip keeps the
## largest mesh).
##
## `mussel_clump` is the accent: six shells in a rosette. Scattered around the mat so a bed
## reads as a PATCH rather than as one ornament stuck on a wall, and so there is something
## for a harvest to visibly take away.
##
## FOUR EARLIER BED CANDIDATES WERE REJECTED ON THE RENDER, at the shipping ratio — see
## DEVLOG.md. All four asked for 22-30 shells, which at 4,200 triangles is ~140 a shell; a
## shell needs a few hundred to stay closed, so every one came back as the "loose flat
## facets / broken glass" failure docs/AGENT_TRAPS.md describes. Nine big shells hold.
const BED_SLUG: String = "mussel_bed_e"
const CLUMP_SLUG: String = "mussel_clump"
const BED_TRIS: int = 4200
const CLUMP_TRIS: int = 3000

## Bed sizes, longest axis in metres. A wild Mytilus bed is metres across; these are patches
## on a 6 m concrete face among 0.35-3.4 m coral, so a bed reads as a patch at 0.6-1.0 m.
## SIZED BY RENDER, not by taste. At 0.62-1.05 m the beds photographed as small dark specks
## between 1.6-3.4 m reef masses — real, seated, and not findable, which for the one edible
## thing on the reef is a failure. A wild Mytilus bed is metres across anyway, so this is both
## the more legible number and the truer one.
const BED_LO: float = 0.85
const BED_HI: float = 1.45
const CLUMP_LO: float = 0.34
const CLUMP_HI: float = 0.60

## How many beds, and how they are spread. Deliberately per-leg rather than a global count:
## a diver only ever visits one leg at a time, so six a leg is what "scattered throughout the
## coral" means from the water, and a global 24 could otherwise land 20 of them on one leg.
const BEDS_PER_LEG: int = 6
## Accents per bed. Each is a real MeshInstance3D, which is the cost driver here (this is a
## draw-call-bound renderer): 1 mat + 2 accents = 3 draws a bed, 72 in the whole ocean.
const ACCENTS: int = 2

## No two beds closer than this, so they read as separate patches you find one at a time
## rather than as a stripe of mussels.
const BED_SPACING: float = 2.6

## MUSSELS LIE FLUSH. The brief is explicit — "a low encrusting mat: near-zero tilt, flush
## to the face, clustered in patches" — and it is also true: a mussel is held on by byssal
## threads and grows tight to its rock, unlike a gorgonian which leans into the flow. So the
## tilt off the probed normal is a couple of degrees of scatter and nothing more.
const TILT_MAX_DEG: float = 4.0
## Bite the base a little into the concrete so no cut edge shows along the mat's rim. Small,
## because a 0.18-deep mat has very little height to spend: leg_reef caps its own recess at a
## third of a piece's height for exactly this reason and this is a fifth of it.
const RECESS: float = 0.028

## Yield per pick, re-rolled on every regrowth — the same trick harvest_nodes.GlowCluster
## uses, which keeps the grant inside Salvage's all-or-nothing pack check instead of bolting
## extra add_item() calls onto the end of it.
const YIELD_LO: int = 2
const YIELD_HI: int = 4

## FIVE DAYS (owner brief). Counted on the game calendar — see the module note.
const REGROW_DAYS: float = 5.0
## Work seconds for one pick. Bare hands do it; a knife or prybar halves it and spares your
## hands (Salvage.speed_tools + bare_hand_risk). Short, because it is paid underwater out of
## the same breath as the swim down — see _dive_floor.
const WORK_SEC: float = 2.0

## AIR MARGIN. What fraction of one breath a dive to a bed must leave unspent: down, work,
## and back up to the surface. A quarter of the lungs is the reserve for missing the ladder,
## getting turned around in the fog grade, or meeting a shark on the way up.
const AIR_MARGIN: float = 0.25
## Sanity envelope on the derived dive floor. If the controller's constants ever change
## enough to put this outside the band, that is worth looking at rather than obeying.
const DIVE_FLOOR_MIN: float = -24.0
const DIVE_FLOOR_MAX: float = -8.0

## Drawn out to here and no further. The underwater fog grade runs 0.028-0.2 per metre, so a
## 0.8 m bed at 34 m is a smudge; beyond that it is 3 draw calls of nothing.
const DRAW_RANGE: float = 34.0

## Shell, not living tissue: the mussels take a fraction of the reef's bloom emission, the
## same way the chalk barnacles do. NOTE this is a BRIGHTENER, not a bloom — main.gd's
## glow_hdr_threshold is 0.8 and nothing at this energy reaches it (docs/AGENT_TRAPS.md).
## It exists so a near-black shell is still findable at y -15 through the fog, no more.
const GLOW: float = 0.20
const GLOW_TINT := Color(0.94, 1.00, 0.99)
## The generator returned the documented failure mode — saturated cobalt with a glassy
## specular, a gemstone rather than a shell. Both are corrected on the material: albedo_color
## multiplies the map, so this darkens and desaturates it toward the blue-black of a real
## Mytilus, and the roughness kills the plastic highlight.
const SHELL_TINT := Color(0.62, 0.66, 0.72)
const SHELL_ROUGH: float = 0.72

var _rng := RandomNumberGenerator.new()
var _space: PhysicsDirectSpaceState3D
var _seats: Array = []
var _band_top: float = 0.0
var _band_bottom: float = 0.0
var _keep_out: Array = []
var _bed_mesh: Mesh = null
var _clump_mesh: Mesh = null
var _mat: StandardMaterial3D = null

## Report numbers, not impressions.
var beds: Array = []             ## the live Salvage nodes, for the probe and the report
var _refused_no_collider: int = 0
var _refused_spacing: int = 0
var _refused_blocked: int = 0
var _dive_y: float = 0.0

func _init(seats: Array = [], band_top: float = -12.6, band_bottom: float = -22.0,
		keep_out: Array = []) -> void:
	name = "MusselBeds"
	_seats = seats
	_band_top = band_top
	_band_bottom = band_bottom
	_keep_out = keep_out

func _ready() -> void:
	_rng.seed = 51_09_21
	# Physics is not queryable until a frame has run, and the animals this has to skip are
	# spawned by their own _ready calls — so the skip list is collected after the tree has
	# ticked, not during the build.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	_collect_skip()
	_dive_y = _dive_floor()
	if not _load_meshes():
		push_warning("[mussels] no mesh — no beds planted")
		return
	_plant()
	_report()

# ------------------------------------------------------------ the air budget

## THE DEEPEST A BED MAY SIT, derived from the player's own lungs.
##
## Food the player cannot reach on one breath is not food, and the coral band runs to y -22
## — well past what a breath-hold dive can do. Rather than pick a depth that "feels
## reachable", this integrates the controller's real drain: OXYGEN_DRAIN above
## DEEP_UNEASE_M, OXYGEN_DRAIN_DEEP below it (the dark burns air near twice as fast), over a
## round trip at SWIM_SPEED plus the work seconds spent holding still at the bed. The answer
## is the deepest depth that still leaves AIR_MARGIN of the breath unspent.
##
## Conservative on purpose: it costs the descent at flat swim speed although a crouch-dive is
## faster, and it ignores the sprint multiplier entirely.
func _dive_floor() -> float:
	var budget: float = 1.0 - AIR_MARGIN
	var best: float = 0.0
	# 10 cm steps down the band — cheap, and it avoids inverting a piecewise rate by hand.
	for i in range(1, 400):
		var d: float = float(i) * 0.1
		if _air_cost(d) > budget:
			break
		best = d
	var y: float = -best
	if y < DIVE_FLOOR_MIN or y > DIVE_FLOOR_MAX:
		push_warning("[mussels] derived dive floor y %.2f is outside [%.1f, %.1f] — clamping"
			% [y, DIVE_FLOOR_MIN, DIVE_FLOOR_MAX])
		y = clampf(y, DIVE_FLOOR_MIN, DIVE_FLOOR_MAX)
	return y

## Fraction of one breath a dive to `depth` metres costs: swim down, work, swim back up.
func _air_cost(depth: float) -> float:
	var shallow_m: float = minf(depth, PC.DEEP_UNEASE_M)
	var deep_m: float = maxf(0.0, depth - PC.DEEP_UNEASE_M)
	var speed: float = maxf(PC.SWIM_SPEED, 0.01)
	# The work is paid at whatever rate applies at the bed's own depth.
	var work_rate: float = PC.OXYGEN_DRAIN_DEEP if depth > PC.DEEP_UNEASE_M else PC.OXYGEN_DRAIN
	return (2.0 * shallow_m / speed) * PC.OXYGEN_DRAIN \
		+ (2.0 * deep_m / speed) * PC.OXYGEN_DRAIN_DEEP \
		+ WORK_SEC * work_rate

# ------------------------------------------------------------ placement

func _load_meshes() -> bool:
	_bed_mesh = _mesh_of(BED_SLUG)
	_clump_mesh = _mesh_of(CLUMP_SLUG)
	if _bed_mesh == null:
		return false
	if _clump_mesh == null:
		_clump_mesh = _bed_mesh      # degrade to mat-only rather than dropping the feature
	return true

## Pull the mesh (and, once, the material) out of a decimated reef GLB.
func _mesh_of(slug: String) -> Mesh:
	var path: String = REEF_PATH % [slug, slug]
	if not ResourceLoader.exists(path):
		push_warning("[mussels] missing %s" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var found: MeshInstance3D = null
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		found = node
		break
	if found == null or found.mesh == null:
		inst.queue_free()
		return null
	var mesh: Mesh = found.mesh
	if _mat == null:
		var src: Material = found.get_active_material(0)
		_mat = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D \
			else StandardMaterial3D.new()
		_mat.albedo_color = SHELL_TINT
		_mat.roughness = SHELL_ROUGH
		_mat.metallic = 0.0
		if _mat.albedo_texture != null:
			_mat.emission_enabled = true
			_mat.emission_texture = _mat.albedo_texture
			_mat.emission = GLOW_TINT
			_mat.emission_energy_multiplier = GLOW
	inst.queue_free()
	return mesh

## Which caisson leg a seat belongs to. Derived from its own position rather than carried
## along in the seat record, so this stays a read-only consumer of leg_reef's data.
func _leg_of(pos: Vector3) -> int:
	return (1 if pos.x > 0.0 else 0) + (2 if pos.z > 0.0 else 0)

func _plant() -> void:
	# Bucket the reef's own colony seats by leg, keeping only the ones a diver can reach on
	# one breath (see _dive_floor). Shuffled so a leg's beds are not the first six colonies
	# leg_reef happened to record on it.
	var by_leg: Dictionary = {}
	var reachable: int = 0
	for seat in _seats:
		var p: Vector3 = seat["pos"]
		if p.y < _dive_y:
			continue
		reachable += 1
		var leg: int = _leg_of(p)
		if not by_leg.has(leg):
			by_leg[leg] = [] as Array
		(by_leg[leg] as Array).append(seat)
	var placed: Array = []       # [pos] rejection list for BED_SPACING
	for leg in by_leg.keys():
		var pool: Array = (by_leg[leg] as Array).duplicate()
		_shuffle(pool)
		var made: int = 0
		for seat in pool:
			if made >= BEDS_PER_LEG:
				break
			if _seat_bed(seat, placed):
				made += 1
	print("[mussels] %d beds (%d/%d colony seats above the derived dive floor y %.2f) · %d refused (%d no collider, %d spacing, %d keep-out)"
		% [beds.size(), reachable, _seats.size(), _dive_y, _refused_no_collider
			+ _refused_spacing + _refused_blocked, _refused_no_collider, _refused_spacing,
			_refused_blocked])

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t

## One bed. Returns true if it seated.
func _seat_bed(seat: Dictionary, placed: Array) -> bool:
	var n: Vector3 = (seat["n"] as Vector3).normalized()
	var tangent := Vector3(n.z, 0.0, -n.x)
	# A little off the colony centre, in the face plane, so the mussels sit AMONG the coral
	# rather than exactly on top of its densest point.
	var target: Vector3 = (seat["pos"] as Vector3) \
		+ tangent * _rng.randf_range(-0.75, 0.75) \
		+ Vector3.UP * _rng.randf_range(-0.55, 0.55)
	if target.y < _dive_y or target.y > _band_top:
		return false
	var hit: Dictionary = _probe(target, n)
	if hit.is_empty() or not _is_wall((hit["normal"] as Vector3).normalized(), n):
		_refused_no_collider += 1
		return false
	var surface: Vector3 = hit["position"]
	if _blocked(surface):
		_refused_blocked += 1
		return false
	for p in placed:
		if surface.distance_to(p) < BED_SPACING:
			_refused_spacing += 1
			return false
	var face: Vector3 = (hit["normal"] as Vector3).normalized()
	var visual := MusselBed.new()
	var size: float = _rng.randf_range(BED_LO, BED_HI)
	# The mat itself, at the seat. Built FIRST and biggest, which is also what makes it the
	# piece Salvage._strip leaves standing (it sorts by AABB volume and never pulls the
	# largest) — a harvested bed loses an accent clump, never the bed.
	visual.add_patch(_bed_mesh, _mat, Vector3.ZERO, face, size, _rng, TILT_MAX_DEG, RECESS)
	# The accents, each seated by its OWN raycast so a clump on a slightly different plane
	# (a corner, a lip, a chamfer) still lies flush instead of inheriting the mat's normal.
	for i in range(ACCENTS):
		var off: Vector3 = tangent * _rng.randf_range(-0.62, 0.62) \
			+ Vector3.UP * _rng.randf_range(-0.42, 0.42)
		var a_hit: Dictionary = _probe(surface + off + face * 0.05, face)
		if a_hit.is_empty() or _blocked(a_hit["position"]):
			continue
		var a_face: Vector3 = (a_hit["normal"] as Vector3).normalized()
		if not _is_wall(a_face, n):
			continue
		visual.add_patch(_clump_mesh, _mat, (a_hit["position"] as Vector3) - surface,
			a_face, _rng.randf_range(CLUMP_LO, CLUMP_HI), _rng, TILT_MAX_DEG, RECESS)
	# The scar: the bare patch the mussels are sitting on, revealed when they are picked off.
	visual.add_scar(size, face)
	# Salvage._finish already logs "first_salvage" in the journal, so nothing extra is
	# hooked here — a bed is a harvest node like any other as far as the journal is concerned.
	var node: Salvage = SALVAGE.from_visual(self, visual, surface, 0.0, _def(), 0.5)
	visual.bind(node)
	beds.append(node)
	placed.append(surface)
	return true

## The harvest definition. Bare hands do it; a knife or prybar is faster and saves your
## skin. `regrow_days` is the field Salvage turns into game hours — see its own note.
func _def() -> Dictionary:
	return {
		"tools": [], "speed": ["crude_knife", "honed_knife", "prybar"],
		"verb": "GATHER", "work": WORK_SEC, "sound": "scuttle_c",
		"regrow_days": REGROW_DAYS, "risk": 0.02, "name": "Mussel Bed",
		"yields": {"mussels": YIELD_LO},   # re-rolled 2-4 per growth, see MusselBed
		"hint": "", "start": "You work your fingers under the shells.",
		"done": "A double handful of mussels comes away, threads and all.",
	}

## LIVE ANIMALS AND HARVEST BOXES, excluded from every ray this file fires at the concrete.
##
## This is not tidiness; the first run of tests/MusselProbe.tscn caught it. Every creature in
## bloom_fauna.gd carries a FaunaTouch — an Interactable, i.e. a StaticBody3D with a 0.6-0.85 m
## sphere on the DEFAULT collision layer, because that is how the player's interaction ray
## finds an animal — and leg_reef seeds thirteen snails onto the caisson faces in exactly this
## depth band. So one bed and all three of its patches seated on a passing snail's touch
## sphere: the probe reported "no collider under it" (the animal had crawled on) and the three
## patches' up axes came back at (0.32, 0.16, -0.93) and friends, i.e. sphere normals, on a
## wall whose real normal is (0, 0, -1). Confident, stable and completely wrong — the same
## failure that made a caisson appear to have moved 606 mm in s20 (docs/AGENT_TRAPS.md).
##
## Collected by SCRIPT FILE rather than by group, so it catches an animal wherever it is
## parented — bloom_fauna's own fauna_bodies() helper walks up looking for a bloom_fauna host
## and therefore misses the snails LegReef spawns under itself.
const FAUNA_SCRIPTS := ["bloom_fauna.gd", "reef_life.gd", "reef_fish.gd", "leg_reef.gd",
	"underwater_world.gd", "shark.gd", "salvage.gd", "mussel_beds.gd"]
var _skip: Array[RID] = []

func _collect_skip() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	for node in root.find_children("*", "CollisionObject3D", true, false):
		var p: Node = node
		while p != null:
			var s: Script = p.get_script()
			if s != null and FAUNA_SCRIPTS.has(String(s.resource_path).get_file()):
				_skip.append((node as CollisionObject3D).get_rid())
				break
			p = p.get_parent()

## Fire a ray at the concrete from a point known to be in open water. Unlike leg_reef's own
## probe there is NO FALLBACK to the sonar-measured face: a MultiMesh instance that misses
## is only drawn, but a mussel bed carries a collider the player's interaction ray has to
## hit, and this file's whole flushness claim rests on having measured the surface.
func _probe(target: Vector3, normal: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(target + normal * 1.8, target - normal * 0.7)
	q.collision_mask = 1
	var skip: Array[RID] = _skip.duplicate()
	# ...plus the beds already built, or the second bed on a face measures the first bed's
	# interaction box instead of the wall.
	for b in beds:
		if is_instance_valid(b):
			skip.append((b as CollisionObject3D).get_rid())
	q.exclude = skip
	return _space.intersect_ray(q)

## A surface normal on a caisson face is axis-aligned: the legs are one flat-sided casting.
## Anything more than a few degrees off means the ray found something that is not the wall —
## the last line of defence behind the skip list above, since an animal spawned after
## _collect_skip ran would not be in it. Refused, not seated on.
const FACE_ALIGN_MIN: float = 0.985

func _is_wall(n: Vector3, expect: Vector3) -> bool:
	return n.dot(expect) >= FACE_ALIGN_MIN

func _blocked(p: Vector3) -> bool:
	for k in _keep_out:
		if p.distance_to(k["c"]) < float(k["r"]):
			return true
	return false

func _report() -> void:
	var meshes: int = 0
	var tris: int = 0
	for b in beds:
		for mi in (b as Node).find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			if (mi as MeshInstance3D).mesh == _bed_mesh:
				tris += BED_TRIS
			elif (mi as MeshInstance3D).mesh == _clump_mesh:
				tris += CLUMP_TRIS
	var lo: float = 1.0e9
	var hi: float = -1.0e9
	for b in beds:
		lo = minf(lo, (b as Node3D).global_position.y)
		hi = maxf(hi, (b as Node3D).global_position.y)
	if beds.is_empty():
		lo = 0.0
		hi = 0.0
	print("[mussels] %d meshes, %d tris, seated y %.2f .. %.2f (band %.2f .. %.2f, dive floor %.2f)"
		% [meshes, tris, lo, hi, _band_top, _band_bottom, _dive_y])
	print("[mussels] regrow %.0f game days = %.0f game hours = %.0f real seconds at time_scale 1.0"
		% [REGROW_DAYS, REGROW_DAYS * 24.0, REGROW_DAYS * GameClock.real_sec_per_game_day()])

# ------------------------------------------------------------ the live bed

## One bed's geometry, and the half of "visibly picked" that Salvage cannot do.
##
## Salvage._strip() already pulls a mesh off, soots what is left and heals it all again on
## regrow — that is most of the read. What it cannot do is make the SURVIVING mussels look
## like the leftovers of a picked bed, because soot only darkens. So this shrinks the
## remaining shells toward the rock (what you leave behind are the small ones you could not
## get a finger under) and fades in a bare scar patch of empty byssal threads under them,
## then puts both back as the bed grows in. It is also where the 2-4 yield lives.
class MusselBed extends Node3D:
	const PICKED_SCALE: float = 0.52   ## how small the survivors read once picked over
	const EASE: float = 0.9            ## how fast the look follows the state, per second

	var _patches: Array = []           ## [{mi, basis}] — basis is the planted, unpicked one
	var _scar: MeshInstance3D = null
	var _scar_mat: StandardMaterial3D = null
	var _node: Salvage = null
	var _ease: float = 0.0             ## 0 = full bed, 1 = picked over
	var _was_spent: bool = false
	## Salvage._strip() knocks a small prop askew and _restore() does not put it back, so a
	## renewable node would lean further every cycle. Remembered and re-seated on regrow —
	## the same fix harvest_nodes.GlowCluster carries.
	var _base_rot: Vector3
	var _rng := RandomNumberGenerator.new()

	## Add one mussel patch. `offset` is relative to the bed's own origin (the Salvage node
	## sits at the mat's seat, unrotated, so this space is world-axis-aligned); `face` is the
	## PROBED surface normal at that offset, which is what the patch's +Y is put on.
	func add_patch(mesh: Mesh, mat: Material, offset: Vector3, face: Vector3, size: float,
			rng: RandomNumberGenerator, tilt_deg: float, recess: float) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		# Decoration on a reef that was measured at 9.3 fps, under water where the sun does
		# not reach: no shadows, no GI, and gone past the fog's reach.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_end = DRAW_RANGE
		mi.visibility_range_end_margin = 4.0
		add_child(mi)
		# Growth axis: the probed normal with a couple of degrees of scatter. A mussel lies
		# FLUSH — this is not the coral's 8-70 degree lean into the light.
		var grow: Vector3 = _scatter(face, deg_to_rad(rng.randf_range(0.0, tilt_deg)), rng)
		var ref := Vector3.UP if absf(grow.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var x_ax: Vector3 = ref.cross(grow).normalized()
		var basis := Basis(x_ax, grow, x_ax.cross(grow))
		basis = basis.rotated(grow, rng.randf_range(0.0, TAU))
		# The mesh is normalised to a 1 m longest axis by the decimator, so scale IS the size.
		var norm: float = 1.0 / maxf(_longest_axis(mesh), 0.001)
		basis = basis.scaled(Vector3.ONE * size * norm)
		mi.transform = Transform3D(basis, offset - face * recess)
		_patches.append({"mi": mi, "basis": basis})

	## The bare rock a bed is anchored to: a thin dark disc of spent byssal threads, invisible
	## while the mussels cover it and faded in once they have been picked off.
	func add_scar(size: float, face: Vector3) -> void:
		_scar_mat = StandardMaterial3D.new()
		# Not black. The first version was (0.09, 0.10, 0.11) at 0.72 alpha and photographed
		# as a HOLE punched through the caisson rather than as bare rock — see DEVLOG.md.
		# This is the wet concrete's own value, a stain rather than a void.
		_scar_mat.albedo_color = Color(0.17, 0.16, 0.14, 0.0)
		_scar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_scar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_scar_mat.roughness = 0.55
		_scar_mat.metallic_specular = 0.7      # wet, so it catches what light gets down here
		var cm := CylinderMesh.new()
		cm.top_radius = size * 0.38
		cm.bottom_radius = size * 0.38
		cm.height = 0.012
		cm.material = _scar_mat
		_scar = MeshInstance3D.new()
		_scar.mesh = cm
		_scar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_scar.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_scar.visibility_range_end = DRAW_RANGE
		add_child(_scar)
		# Lie in the face, just clear of the concrete.
		var ref := Vector3.UP if absf(face.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var x_ax: Vector3 = ref.cross(face).normalized()
		_scar.transform = Transform3D(Basis(x_ax, face, x_ax.cross(face)), face * 0.006)

	func bind(node: Salvage) -> void:
		_node = node
		_base_rot = rotation
		_rng.randomize()
		_reroll()
		# Only tick when there is something to animate: idle beds cost nothing, and a bed
		# keeps processing while spent so it can see itself grow back (Salvage._restore
		# emits no signal).
		set_process(false)
		node.interacted.connect(func(_v: String) -> void: set_process(true))

	func _reroll() -> void:
		if _node != null and is_instance_valid(_node):
			_node.yields = {"mussels": _rng.randi_range(YIELD_LO, YIELD_HI)}

	func _process(delta: float) -> void:
		var spent: bool = _node != null and is_instance_valid(_node) and _node.spent
		if spent != _was_spent:
			_was_spent = spent
			if not spent:
				_reroll()                # the bed has grown back: a fresh handful is on it
				rotation = _base_rot
		_ease = move_toward(_ease, 1.0 if spent else 0.0, delta * EASE)
		var f: float = lerpf(1.0, PICKED_SCALE, _ease)
		for p in _patches:
			var mi: MeshInstance3D = p["mi"]
			if is_instance_valid(mi):
				# Scaling the basis shrinks each patch toward its OWN origin, which is the
				# point on the concrete the decimator put its base on — so a picked-over bed
				# stays seated instead of lifting off the wall.
				mi.transform = Transform3D((p["basis"] as Basis).scaled(Vector3.ONE * f),
					mi.transform.origin)
		if _scar_mat != null:
			_scar_mat.albedo_color.a = 0.50 * _ease
		if not spent and is_equal_approx(_ease, 0.0):
			set_process(false)

	static func _longest_axis(mesh: Mesh) -> float:
		var s: Vector3 = mesh.get_aabb().size
		return maxf(s.x, maxf(s.y, s.z))

	## `normal`, tipped by `ang` in a random direction about itself.
	static func _scatter(normal: Vector3, ang: float, rng: RandomNumberGenerator) -> Vector3:
		if ang <= 0.0001:
			return normal
		var ref := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var side: Vector3 = ref.cross(normal).normalized()
		side = side.rotated(normal, rng.randf_range(0.0, TAU))
		return (normal * cos(ang) + side * sin(ang)).normalized()
