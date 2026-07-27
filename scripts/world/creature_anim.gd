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
const FACING_OVERRIDES: Dictionary = {
	"mantle_ray": {"yaw": 180.0, "pitch": 90.0, "axis": 0, "flip": 1.0, "lift": 1},
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
