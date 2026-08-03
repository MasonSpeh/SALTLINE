extends Node
## PHOTOGRAPHS A RIGGED GLB *THROUGH ITS ANIMATION*, not as a static pose.
##
## Why this exists. s35 got Tripo to rig the ship's cat — the first skinned mesh in this
## project, 41 joints and a baked clip. But the joint names came back HUMANOID
## (Hip, Pelvis, L_Thigh, L_Clavicle, L_Upperarm, L_Hand, Spine01, Head): Tripo mapped a
## BIPED auto-rig onto a quadruped and retargeted a human walk cycle onto it. That can be
## anything from "reads as a cat" to "a person on all fours doing a breaststroke", and
## nothing in the glTF says which. `CandShot` cannot answer it — a static frame of a walk
## cycle looks fine at almost any phase; what is wrong with a bad retarget is the MOTION.
##
## So this samples the clip at N evenly spaced phases and writes one PNG per phase, from a
## side view where a gait reads. Judge the strip, not one frame.
##
## Runs WINDOWED (--headless never draws; SubViewport read-backs hang forever):
##   godot --path . res://tests/AnimShot.tscn -- <out_dir> <res://path.glb> [more.glb ...]

const SHOT_PX: int = 560
const PHASES: int = 8
## Side decides a gait; three-quarter catches a limb swinging across the body, which is the
## signature of a biped clip on a quadruped.
const VIEWS := {
	"side": Vector3(1.0, 0.10, 0.02),
	"threequarter": Vector3(0.72, 0.26, 0.62),
}

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("[anim] usage: <out_dir> <res://path.glb> ...")
		get_tree().quit()
		return
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	for i in range(1, args.size()):
		var path: String = args[i]
		var slug: String = path.get_file().get_basename()
		if not ResourceLoader.exists(path):
			print("[anim] %s: NOT IMPORTED (%s)" % [slug, path])
			continue
		await _shoot_clip(out, path, slug)
	print("[anim] done")
	get_tree().quit()

func _bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var world: AABB = mi.global_transform * mi.get_aabb()
		acc = world if first else acc.merge(world)
		first = false
	return acc if not first else AABB()

func _shoot_clip(out: String, path: String, slug: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SHOT_PX, SHOT_PX)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -135, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, 60, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.82, 0.88, 1.0)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 1.0
	cam.environment = env
	vp.add_child(cam)

	var scene: PackedScene = load(path)
	var model: Node3D = scene.instantiate()
	vp.add_child(model)
	await get_tree().process_frame

	# Find the clip. Report what is actually there rather than assuming one exists — a GLB
	# whose rig silently failed still instantiates perfectly.
	var ap: AnimationPlayer = null
	for n in model.find_children("*", "AnimationPlayer", true, false):
		ap = n
		break
	var skels: Array = model.find_children("*", "Skeleton3D", true, false)
	if ap == null:
		print("[anim] %s: NO AnimationPlayer — %d skeletons, static mesh only" % [slug, skels.size()])
		vp.queue_free()
		return
	var clips: PackedStringArray = ap.get_animation_list()
	if clips.is_empty():
		print("[anim] %s: AnimationPlayer with ZERO clips" % slug)
		vp.queue_free()
		return
	var clip: String = clips[0]
	var anim: Animation = ap.get_animation(clip)
	var bones: int = (skels[0] as Skeleton3D).get_bone_count() if not skels.is_empty() else 0
	print("[anim] %-18s clip='%s' len=%.2fs tracks=%d bones=%d"
		% [slug, clip, anim.length, anim.get_track_count(), bones])

	var box: AABB = _bounds(model)
	if box.size.length() <= 0.0001 or not is_finite(box.size.length()):
		print("[anim] %s: no geometry" % slug)
		vp.queue_free()
		return
	var centre: Vector3 = box.get_center()
	var span: float = maxf(maxf(box.size.x, maxf(box.size.y, box.size.z)), 0.1)

	# Drive the clip BY SEEKING, never by letting it play against wall-clock: a windowed
	# harness's frame timing is not reproducible, so "wait 0.1 s and shoot" samples a
	# different phase on every run and two candidates are never compared at the same point
	# in their cycle.
	for view in VIEWS:
		cam.size = span * 1.15
		cam.position = centre + (VIEWS[view] as Vector3).normalized() * span * 2.0
		cam.look_at(centre, Vector3.UP)
		for p in range(PHASES):
			var t: float = anim.length * float(p) / float(PHASES)
			ap.play(clip)
			ap.seek(t, true)
			ap.pause()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img: Image = vp.get_texture().get_image()
			img.save_png("%s/%s_%s_p%d.png" % [out, slug, view, p])
	vp.queue_free()
