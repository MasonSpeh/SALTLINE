class_name CreatureAnim extends RefCounted
## Makes a STATIC AI-generated animal mesh actually move.
##
## Text-to-3D services auto-rig humanoids only (Meshy runs bipedal pose estimation and
## returns "Pose estimation failed" for a crab, a ray, a whale). Rather than hand-rig
## every species in Blender, the motion lives in a vertex shader: the body undulates,
## wings beat, bells pulse. It costs no bones, no AnimationPlayer, and it never fights
## the movement code — the species script just pushes `rate`/`amp`/`glow` each frame
## from the SAME state machine that already drives patrol/pursue.
##
## Usage in a species _build_body():
##     _mats = CreatureAnim.apply(model, CreatureAnim.Mode.UNDULATE, 0.05, 1.6)
## ...and in _animate(delta):
##     CreatureAnim.drive(_mats, speed_hz, glow_energy)

const SHADER := preload("res://materials/creature_swim.gdshader")

enum Mode {
	UNDULATE = 0,   ## body wave, head to tail — fish, eel, shark, whale, seal, worm
	WING = 1,       ## wings beat, amplitude to the tips — ray
	PULSE = 2,      ## bell squash + skirt flare — jelly
	FLAP = 3,       ## fast wingbeat — birds
	SCUTTLE = 4,    ## legged metachronal gait — crab
	PEDAL = 5,      ## muscular foot wave — the gastropods
	CIRRI = 6,      ## feathery feeding sweep — barnacles
	BREATHE = 7,    ## resting swell — limpet, denned glow worm
	SWAY = 8,       ## anchored drift in the current — flora
	SCULL = 9,      ## stiff body, sculling tail, rowing lobed fins — coelacanth
}

## SPECIES WITH A SIGNATURE GAIT (added for the coelacanth, 2026-07-26).
## Swim style is a property of the ANIMAL, not of whoever spawned it. Every other species
## in the game happens to move the way its caller guessed, so callers pass the mode. The
## coelacanth does not: mode 0 (the fish default that DeepGiant, ReefLife and the bestiary
## sheet all hand it) bends it like a cod and ignores its four lobed fins, which is most of
## what makes it recognisable. Rather than make five call sites remember Mode.SCULL —
## across files owned by other work — the animal carries its own gait here, exactly the way
## it already carries its own authored facing in FACING_OVERRIDES below. Add an entry ONLY
## for a species whose motion no caller should have to know about; the caller's `amp`/`rate`
## are left alone, since those are tuned per-instance for size and distance.
const MOTION_OVERRIDES: Dictionary = {
	"fish_coelacanth": Mode.SCULL,
}

static func mode_for(path: String, requested: int) -> int:
	return MOTION_OVERRIDES.get(path.get_file().get_basename(), requested)

## Authored-facing normalisation. VERIFIED via tests/FacingShot.tscn side views: every
## directional Meshy model faces the VIEWER (+Z) — heads point screen-left from a +X
## camera — while Godot's forward (and all the movement code's look_at) is -Z. So the
## DEFAULT is: yaw the model node 180 and tell the shader the head is at the +Z end
## (flow_flip 1). Radially symmetric models (jelly, barnacles, limpet, flora) don't
## care. Add a slug here ONLY when a future model breaks the convention.
##   yaw/pitch — degrees on the model node. Applied in Godot's YXZ order, so `pitch` is
##               taken FIRST in the mesh's own space and `yaw` then swings the result.
##   axis/flip — where the shader finds the body: see flow_axis / flow_flip.
##   lift      — which local axis the WING/FLAP beat displaces along: 0 = Y, 1 = Z.
const FACING_DEFAULT := {"yaw": 180.0, "pitch": 0.0, "axis": 0, "flip": 1.0, "lift": 0}
## THE MANTLE RAY is the one model that breaks the convention, and it broke it in the one
## way a yaw cannot fix (re-verified from the FacingShot side view, 2026-07-25): Meshy
## authored it STANDING ON ITS TAIL, like a kite. Wings span local X, the head is at +Y
## with the tail whip hanging to -Y, and the thin dorsal-ventral axis runs Z — dark back
## at -Z, pale belly at +Z, because a "front" view of a ray is a view of its underside.
## Yawing that 180 like everything else only spins the kite: the animal swims edge-on, on
## its side, which is exactly what it has been doing. Pitching +90 lays it flat (head
## +Y -> -Z, dark back -Z -> +Y) and the usual 180 yaw then puts the head on Godot's
## forward. `across` is still local X so the wingbeat spans correctly, but the beat has to
## displace along local Z — the mesh's dorsal-ventral axis — or the wingtips shear
## fore-and-aft along the body instead of flapping.
## fish_coelacanth (owner-supplied Meshy model, CHECKED 2026-07-26 rather than assumed —
## six fixed views of the raw mesh): body runs local Z (1.90 long) x 1.07 dorsal-ventral
## x 0.41 across, head at +Z with the dorsals up at +Y and the lobed pairs hanging below.
## That is the convention exactly, so it takes NO entry here — the default's 180 yaw and
## flip 1.0 land it head-first on Godot's -Z, right side up. Recorded so the next person
## knows it was verified and not skipped.
## herring_gull (owner-picked photoreal gull, CHECKED 2026-07-28 through CandShot's side
## view before it was wired in): it is the FIRST model here authored the other way round.
## From the +X camera its bill points screen-RIGHT, which is world -Z — already Godot's
## forward. The default's 180 yaw would spin it and the deck gull would strut backwards
## down the plating, tail first. So: no yaw, and the head is at the MIN end of local Z
## (flip 0), which is also what the shader needs to keep the wave running head -> tail.
## ultra_hammerhead (owner-picked photoreal hammerhead, MEASURED 2026-07-29 — not read off
## a render). Its body is authored along local X, which is neither the Meshy +Z convention
## nor Godot's -Z, so the default 180 yaw left it swimming BROADSIDE: tests/HammerheadProbe
## correlated 238 frames of real patrol travel against the model node's six local axes and
## got +Z 0.989 / +X -0.014 — the animal was being dragged sideways through the water.
## Raw mesh (tests/SharkProbe, one surface, 81622 verts): AABB 1.000 x 0.338 x 0.517 with
## the NOSE at max X — the top and side views both put the cephalofoil at world +X, and the
## centreline's min-X end is the one that lifts (y +0.13), which is the caudal fin's upper
## lobe. So: yaw +90 swings local +X onto Godot's -Z (R_y(90) takes +X to -Z) and leaves
## +Y up, and the shader is told the body runs along X (axis 1) with the head at the MAX
## end (flip 1) so the undulation still travels head -> tail and leaves the hammer rigid.
## trop_* (the ten tropical reef fish, MEASURED 2026-07-29 off tests/CandShot side and front
## views before any of them was wired in — the hammerhead shipped swimming broadside because
## somebody skipped this). One Tripo batch, one prompt template, and it came back in THREE
## different conventions, which is the whole argument for measuring every model:
##   * blue_tang, yellow_tang, wrasse, triggerfish — head at local +Z. The default exactly,
##     so they take no entry here. Recorded so the next person knows it was checked.
##   * clown, parrot, anthias, damsel — head at local -Z. From the +X side camera their
##     mouths point screen-RIGHT, which is world -Z, i.e. already Godot's forward: the
##     default's 180 yaw would swim them backwards, tail first. Same case as herring_gull.
##   * angel, butterfly — body authored along local X (AABB 1.00 x 0.88 x 0.32 and
##     1.00 x 0.67 x 0.20), head at MAX X: the front camera, whose screen-right is world +X,
##     shows both in full profile facing right. Same case as ultra_hammerhead — yaw +90
##     takes local +X onto Godot's -Z, and the shader is told the body runs along X so the
##     undulation still travels head -> tail instead of shearing the fish sideways.
## pyramid_snail (owner-reported "the pyramid snails crawl backwrds", MEASURED 2026-07-30 —
## tests/FaunaBugsProbe correlated 2,691 frames of real crawl against the model node's six
## local axes on three live deck snails and got model +Z . travel = +0.9991, +X +0.005,
## +Y 0.000; the host's own -Z rides the same +0.9991, i.e. the facing table and the crawler
## agree and the question is only which end of the MESH the head is on. CandShot's side view
## (camera +X, so screen-right is world -Z) puts the eye stalks and both oral tentacles at
## screen-RIGHT and the trailing foot at screen-left — head at local -Z, min end — and the
## front view (camera +Z) photographs the back of the shell with no head in it at all. Raw
## AABB 0.638 x 0.731 x 1.000 confirms the body runs Z. So the default's 180 yaw was putting
## the mesh's TAIL on Godot's forward and the animal crawled tail-first at 0.115 m/s across
## the whole rig. Same case as herring_gull and the four -Z tropicals: no yaw, and the head at
## the MIN end of local Z (flip 0) so the pedal wave still runs tail -> head up the foot.
## THE ELEVEN s31 SPECIES, MEASURED s34 — and three of them were swimming backwards.
## The owner reported "at least one of the new grouper models is swimming backwards", and
## the reason nobody had caught it is that all eleven were wired in during s31 without a
## single facing check, which is the exact mistake the ultra_hammerhead paragraph above was
## written to prevent. Measured two independent ways and they agree on all eleven:
##   * tools/measure_facing.py, headless off the raw GLB — two statistics (vertex-mass
##     centroid along the long axis, and the same centroid weighted by across-body extent)
##     which must AGREE or the tool prints UNCERTAIN. Calibrated first against the 19 models
##     whose facing is already pinned in this table: 19/19 correct, 0 confidently wrong.
##   * tests/CandShot side and front views, read by eye — the method every earlier entry
##     here used.
## Eight of the eleven (all four remaining tunas, humpback and leopard grouper, mahi-mahi,
## swallowtail) have the head at local +Z, i.e. the default exactly, and take no entry. The
## three below have the head at local -Z: from the +X side camera, whose screen-right is
## world -Z, their mouths point screen-RIGHT, so they are ALREADY on Godot's forward and the
## default's 180 yaw was turning them round to swim tail-first. Same case as herring_gull,
## pyramid_snail and the four -Z tropicals: no yaw, head at the MIN end of local Z (flip 0)
## so the body wave still travels head -> tail.
## THE RIBBON EEL WAS SWIMMING BROADSIDE, and had been since it was wired in. Found s34 by
## tests/FishSpreadProbe, which correlates each species' mesh geometry against its live
## velocity and reported a mean alignment of **+0.011** — not backwards, PERPENDICULAR,
## which is the ultra_hammerhead failure exactly. Raw AABB 1.899 x 0.916 x 0.320: the body
## runs local X, not Z, so the default's 180 yaw was spinning a fish that was already lying
## across Godot's forward and leaving it there. CandShot's front view (camera +Z, so
## screen-right is world +X) shows the whole animal in profile across the frame — an
## end-on foreshortened view is what a Z-authored eel would have given — with the head and
## its eye at screen-LEFT, i.e. head at local MIN X. R_y(-90) takes local -X onto Godot's
## -Z, and the shader is told the body runs along X (axis 1) with the head at the MIN end
## (flip 0) so the undulation still travels head -> tail.
## NOTE the mesh is authored CURVED rather than straight nose-to-tail, which the UNDULATE
## body wave assumes; this fixes the heading, not the banana. A straight re-roll is the
## only fix for that and it is not this session's job.
## THE CAT'S POSE MESHES (s34). Five separate Tripo rolls of the same animal came back in
## TWO conventions, which is the whole argument for measuring every model even inside one
## batch: cat_run, cat_walk and cat_sleep put the head at local +Z (the default, no entry),
## while cat_sit and cat_groom are authored along local X with the nose at MAX X — the front
## camera, whose screen-right is world +X, shows both in full profile facing right. Same case
## as ultra_hammerhead: yaw +90 takes local +X onto Godot's -Z. `axis 1` matters less here
## than it does for a fish (the cat runs Mode.BREATHE, which is a swell rather than a
## travelling wave) but it is set honestly so a future gait mode finds the body where the
## table says it is. The s32 standing ship_cat mesh was re-checked at the same time and has
## its head at local +Z — the default — so it keeps no entry and does not move.
const FACING_OVERRIDES: Dictionary = {
	"mantle_ray": {"yaw": 180.0, "pitch": 90.0, "axis": 0, "flip": 1.0, "lift": 1},
	"fish_ribbon_eel": {"yaw": -90.0, "pitch": 0.0, "axis": 1, "flip": 0.0, "lift": 0},
	"fish_skipjack_tuna": {"yaw": 0.0, "pitch": 0.0, "axis": 0, "flip": 0.0, "lift": 0},
	"fish_peacock_grouper": {"yaw": 0.0, "pitch": 0.0, "axis": 0, "flip": 0.0, "lift": 0},
	"fish_bluelined_grouper": {"yaw": 0.0, "pitch": 0.0, "axis": 0, "flip": 0.0, "lift": 0},
	"cat_sit": {"yaw": 90.0, "pitch": 0.0, "axis": 1, "flip": 1.0, "lift": 0},
	"cat_groom": {"yaw": 90.0, "pitch": 0.0, "axis": 1, "flip": 1.0, "lift": 0},
	"pyramid_snail": {"yaw": 0.0, "pitch": 0.0, "axis": 0, "flip": 0.0, "lift": 0},
	"herring_gull": {"yaw": 0.0, "pitch": 0.0, "axis": 0, "flip": 0.0, "lift": 0},
	"ultra_hammerhead": {"yaw": 90.0, "pitch": 0.0, "axis": 1, "flip": 1.0, "lift": 0},
	"trop_clown": {"yaw": 0.0, "pitch": 0.0, "axis": 0, "flip": 0.0, "lift": 0},
	"trop_parrot": {"yaw": 0.0, "pitch": 0.0, "axis": 0, "flip": 0.0, "lift": 0},
	"trop_anthias": {"yaw": 0.0, "pitch": 0.0, "axis": 0, "flip": 0.0, "lift": 0},
	"trop_damsel": {"yaw": 0.0, "pitch": 0.0, "axis": 0, "flip": 0.0, "lift": 0},
	"trop_angel": {"yaw": 90.0, "pitch": 0.0, "axis": 1, "flip": 1.0, "lift": 0},
	"trop_butterfly": {"yaw": 90.0, "pitch": 0.0, "axis": 1, "flip": 1.0, "lift": 0},
}

static func facing_for(path: String) -> Dictionary:
	return FACING_OVERRIDES.get(path.get_file().get_basename(), FACING_DEFAULT)

## Swap every surface on `model` to the motion shader, carrying the imported PBR maps
## across. Returns the ShaderMaterials so the caller can modulate them per frame.
static func apply(model: Node3D, mode: int, amp: float = 0.06, rate: float = 2.0,
		glow: Color = Color(0.25, 0.95, 0.88), phase: float = 0.0,
		opacity: float = 1.0) -> Array:
	var mats: Array = []
	for mi in _mesh_instances(model):
		var inst: MeshInstance3D = mi
		if inst.mesh == null:
			continue
		var aabb: AABB = inst.get_aabb()
		for s in range(inst.mesh.get_surface_count()):
			var sm := ShaderMaterial.new()
			sm.shader = SHADER
			var src := inst.mesh.surface_get_material(s) as BaseMaterial3D
			if src:
				if src.albedo_texture:
					sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("tint", src.albedo_color)
				sm.set_shader_parameter("roughness_v", src.roughness)
				sm.set_shader_parameter("metallic_v", src.metallic)
				# THE metallicRoughness MAP. Godot's glTF importer puts metallicFactor and
				# roughnessFactor in the SCALARS above and the real per-texel values in a
				# TEXTURE, and every Tripo-era asset here ships both factors at 1.0 — so a
				# shader reading only the scalars renders thirteen species (pyramid_snail,
				# herring_gull, ultra_hammerhead, all ten trop_*, five deep fish) as FULLY
				# METALLIC, i.e. near-black under an environment with no reflection probe.
				# Measured s23; it is the whole of the owner's "the snail reads much darker
				# in game than the model does". The CHANNEL is read off the material rather
				# than assumed to be glTF's G/B, so an importer that changes its convention
				# cannot quietly go dark again. Older Meshy assets carry no map and honest
				# 0.0/0.8 scalars, so use_orm stays false and nothing about them moves.
				# Both halves or neither: glTF packs one metallicRoughness image and the
				# importer binds it to both slots, so a material carrying only one of them is
				# not this convention and is safer left on its scalars.
				if src.metallic_texture != null and src.roughness_texture != null:
					sm.set_shader_parameter("orm_tex", src.metallic_texture)
					sm.set_shader_parameter("use_orm", true)
					sm.set_shader_parameter("orm_rough_mask",
						_channel_mask(src.roughness_texture_channel))
					sm.set_shader_parameter("orm_metal_mask",
						_channel_mask(src.metallic_texture_channel))
				if src.normal_enabled and src.normal_texture:
					sm.set_shader_parameter("normal_tex", src.normal_texture)
					sm.set_shader_parameter("use_normal", true)
			sm.set_shader_parameter("mode", mode)
			sm.set_shader_parameter("amp", amp)
			sm.set_shader_parameter("rate", rate)
			sm.set_shader_parameter("phase", phase)
			sm.set_shader_parameter("glow_color", glow)
			sm.set_shader_parameter("opacity", opacity)
			# Local-space bounds let the shader know head-from-tail without hardcoding scale.
			sm.set_shader_parameter("bounds_min", aabb.position)
			sm.set_shader_parameter("bounds_size", aabb.size)
			inst.set_surface_override_material(s, sm)
			mats.append(sm)
	return mats

## Which channel of the ORM texture a BaseMaterial3D says a value lives in, as a dot mask.
## The shader multiplies the scalar by `dot(orm, mask)`, so this is what keeps the metal read
## out of the roughness and vice versa. glTF is always G = roughness, B = metallic, but the
## enum is what is asked rather than the convention assumed.
static func _channel_mask(channel: int) -> Color:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Color(1.0, 0.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Color(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Color(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Color(0.0, 0.0, 0.0, 1.0)
	# GRAYSCALE: the importer's own convention is the RED channel.
	return Color(1.0, 0.0, 0.0, 0.0)

## Per-frame modulation: beat faster when it's moving, glow harder when it's hunting.
static func drive(mats: Array, rate: float, glow_energy: float = 0.0, amp: float = -1.0) -> void:
	for m in mats:
		var sm: ShaderMaterial = m
		sm.set_shader_parameter("rate", rate)
		sm.set_shader_parameter("glow_energy", glow_energy)
		if amp >= 0.0:
			sm.set_shader_parameter("amp", amp)

## Load a generated species mesh and normalise it to a real-world size (metres along its
## longest axis). Returns null if the asset is missing, so callers can fall back to
## their procedural body instead of crashing.
static func load_model(path: String, target_m: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		return null
	var longest: float = 0.0
	for mi in _mesh_instances(model):
		var a: AABB = (mi as MeshInstance3D).get_aabb()
		longest = maxf(longest, maxf(a.size.x, maxf(a.size.y, a.size.z)))
	if longest > 0.001:
		model.scale = Vector3.ONE * (target_m / longest)
	return model

## Load + scale + parent + shade a generated species mesh in one call. Returns {} when
## the asset isn't there, which is the signal for a species to build its procedural body
## instead — so a missing/failed generation degrades to the old look, never to a crash.
##   var gen := CreatureAnim.attach(self, PATH, 6.0, CreatureAnim.Mode.WING, 0.12, 0.5, GLOW)
##   if not gen.is_empty(): _model = gen["model"]; _mats = gen["mats"]; return
static func attach(host: Node3D, path: String, target_m: float, mode: int,
		amp: float = 0.06, rate: float = 2.0, glow: Color = Color(0.25, 0.95, 0.88),
		phase: float = 0.0, opacity: float = 1.0) -> Dictionary:
	var model := load_model(path, target_m)
	if model == null:
		return {}
	host.add_child(model)
	# A species with a signature gait (MOTION_OVERRIDES) supplies its own mode; everything
	# else moves the way its caller asked. Done HERE and not in apply() so the raw shading
	# entry point stays literal for the screenshot harnesses that drive it by hand.
	var mats := apply(model, mode_for(path, mode), amp, rate, glow, phase, opacity)
	# Normalise authored facing so the species' look_at movement drives it head-first — and
	# right-side-up: a model authored standing on end needs the pitch as well as the yaw.
	var fac := facing_for(path)
	model.rotation = Vector3(deg_to_rad(fac["pitch"]), deg_to_rad(fac["yaw"]), 0.0)
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("flow_axis", fac["axis"])
		(m as ShaderMaterial).set_shader_parameter("flow_flip", fac["flip"])
		(m as ShaderMaterial).set_shader_parameter("lift_axis", fac["lift"])
	return {"model": model, "mats": mats}

## Stand an attached model ON the host's origin plane and return the lift applied, metres.
##
## Every generated mesh here is authored CENTRED on its own bounding box, so a walker
## whose host node sits on the deck plating gets buried to the waist — the old long-legged
## gull hid a quarter-metre of leg under the deck and nobody noticed, because the visible
## feet were procedural. A model with its OWN feet has to be lifted by its own half-height
## or it sinks. Measured off the post-scale, post-facing bounds rather than a hand-typed
## offset, so it stays right if the target size or the facing table changes.
## Call it AFTER attach() — it needs the final scale and rotation — and only for creatures
## that stand on something. Swimmers and perched-on-nothing species want the centre.
static func ground(host: Node3D, model: Node3D) -> float:
	var lift := belly(host, model)
	model.position.y += lift
	return lift

## How far the model's LOWEST point hangs below the host origin, metres — the lift ground()
## applies, without applying it.
##
## Split out for the amphibians: the harbor seal swims CENTRED on its node (the patrol code
## drives the node along the body's own axis, so a grounded model would ride half a body
## high through the water) but hauls out ON a surface, where the node has to sit this far
## above the plating or the animal is buried to the flippers in it. One measurement, two
## uses, and the haul height stays derived from the mesh instead of typed.
static func belly(host: Node3D, model: Node3D) -> float:
	var acc := AABB()
	var first := true
	var inv: Transform3D = host.global_transform.affine_inverse()
	for m in _mesh_instances(model):
		var inst: MeshInstance3D = m
		if inst.mesh == null:
			continue
		var box: AABB = (inv * inst.global_transform) * inst.get_aabb()
		acc = box if first else acc.merge(box)
		first = false
	if first:
		return 0.0
	return -acc.position.y

## WORLD y of the model's lowest point right now, in whatever pose it is currently in.
##
## belly() answers the same question in the host's frame at BUILD time, which is the number
## you want for a fixed stance. It is the wrong number for a body that is posed after it has
## been placed: pitching the harbor seal into its -0.12 rad chest-up rest tips the tail down
## about 0.1 m on a 2 m animal, and a haul height derived from the unpitched bounds buried it
## exactly that far in the concrete (measured -105 mm). Seat against this instead and the
## pose can change freely without the placement going wrong. INF when there is no mesh.
## AND IT IS A BOUND, NOT THE ANIMAL — which is the whole of the s34 seal bug.
##
## `global_transform * aabb` is the axis-aligned bounding box OF THE ROTATED BOX, and that
## is strictly bigger than the rotated mesh whenever the basis is not axis-aligned. Measured
## exactly on the shipped harbor_seal mesh in its -0.12 rad chest-up rest pose: the lowest
## actual VERTEX is 0.385001 m below the node, this function returns 0.487041 m, and _seat()
## puts THIS number on the concrete. So the drawn animal floats 102.0 mm above the slab
## while every probe reports a perfect seat. Note the direction of the history: the comment
## above records fixing a 105 mm BURIAL by switching to this function, i.e. a bound that was
## too high was swapped for a bound that is too low, and the mesh itself was never measured
## either time. Use low_vertex() to seat anything; this stays for callers that genuinely
## want a conservative bound.
static func low_point(model: Node3D) -> float:
	var low: float = INF
	for m in _mesh_instances(model):
		var inst: MeshInstance3D = m
		if inst.mesh == null:
			continue
		low = minf(low, (inst.global_transform * inst.get_aabb()).position.y)
	return low

## WORLD y of the lowest point of the DRAWN MESH in its current pose. Exact, not a bound.
##
## The minimum of (M * v).y over every vertex v is a support query, so it is enough to test
## the CONVEX HULL — the hull contains every extreme point in every direction, so its
## minimum IS the mesh's minimum, for any transform. The hull is built once per mesh and
## cached on the instance, which turns a 29,000-vertex walk into a couple of hundred dot
## products a frame: affordable for something a seated animal re-runs continuously, which a
## full vertex walk would not be. Falls back to the AABB corners (i.e. exactly low_point's
## answer) for a mesh that will not produce a hull, so this is never worse than what it
## replaces. INF when there is no mesh.
static func low_vertex(model: Node3D) -> float:
	var low: float = INF
	for m in _mesh_instances(model):
		var inst: MeshInstance3D = m
		if inst.mesh == null:
			continue
		var xf: Transform3D = inst.global_transform
		for p in _hull_points(inst):
			low = minf(low, (xf * p).y)
	return low

static func _hull_points(inst: MeshInstance3D) -> PackedVector3Array:
	if inst.has_meta("_hull_pts"):
		return inst.get_meta("_hull_pts")
	var pts := PackedVector3Array()
	var shape: ConvexPolygonShape3D = inst.mesh.create_convex_shape(true, false)
	if shape != null:
		pts = shape.points
	if pts.is_empty():
		var b: AABB = inst.get_aabb()
		for i in range(8):
			pts.append(b.get_endpoint(i))
	inst.set_meta("_hull_pts", pts)
	return pts

## Attach the generated mesh and hide the procedural geometry it supersedes.
##
## The species build their primitive bodies inline (in _ready() or _build_body()) and
## keep node handles into them — `_tail`, `_wings`, `_legs` — that their _process code
## still poses. Rather than refactor every one of those classes, we let them build as
## before, then swap what's VISIBLE. The hidden nodes cost nothing to draw and the
## existing animation code keeps working untouched; if the generated asset is missing
## this returns {} and the procedural body simply stays visible.
## Call it as the LAST line of the species' body build.
static func replace(host: Node3D, path: String, target_m: float, mode: int,
		amp: float = 0.06, rate: float = 2.0, glow: Color = Color(0.25, 0.95, 0.88),
		phase: float = 0.0, opacity: float = 1.0) -> Dictionary:
	var superseded: Array = _mesh_instances(host)
	var gen := attach(host, path, target_m, mode, amp, rate, glow, phase, opacity)
	if gen.is_empty():
		return {}
	for mi in superseded:
		(mi as MeshInstance3D).visible = false
	return gen

static func _mesh_instances(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_mesh_instances(c))
	return out
