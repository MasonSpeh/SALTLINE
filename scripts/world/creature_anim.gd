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

enum Mode { UNDULATE = 0, WING = 1, PULSE = 2, FLAP = 3 }

## Swap every surface on `model` to the motion shader, carrying the imported PBR maps
## across. Returns the ShaderMaterials so the caller can modulate them per frame.
static func apply(model: Node3D, mode: int, amp: float = 0.06, rate: float = 2.0,
		glow: Color = Color(0.25, 0.95, 0.88), phase: float = 0.0) -> Array:
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
		phase: float = 0.0) -> Dictionary:
	var model := load_model(path, target_m)
	if model == null:
		return {}
	host.add_child(model)
	return {"model": model, "mats": apply(model, mode, amp, rate, glow, phase)}

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
		phase: float = 0.0) -> Dictionary:
	var superseded: Array = _mesh_instances(host)
	var gen := attach(host, path, target_m, mode, amp, rate, glow, phase)
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
