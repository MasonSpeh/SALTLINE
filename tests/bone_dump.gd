extends Node
## Dumps a rigged GLB's skeleton: bone names, parents, and each bone's REST offset in its
## parent's frame. This is what makes a hand-written gait possible without guessing —
## "which local axis swings a leg fore-and-aft" is a measurement, not an assumption, and
## Tripo fitted a HUMANOID rig to a quadruped so no naming convention can be trusted here.
##
## Headless is correct: skeleton rests are data, nothing needs to be drawn.
##   godot --headless --path . res://tests/BoneDump.tscn -- res://path/to.glb

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("[bones] usage: <res://path.glb>")
		get_tree().quit()
		return
	for path in args:
		_dump(path)
	get_tree().quit()

func _dump(path: String) -> void:
	if not ResourceLoader.exists(path):
		print("[bones] NOT IMPORTED: %s" % path)
		return
	var scene: PackedScene = load(path)
	var root: Node3D = scene.instantiate()
	add_child(root)
	var skels: Array = root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("[bones] %s: NO Skeleton3D" % path.get_file())
		root.queue_free()
		return
	var sk: Skeleton3D = skels[0]
	print("\n=== %s — %d bones ===" % [path.get_file(), sk.get_bone_count()])
	for i in range(sk.get_bone_count()):
		var rest: Transform3D = sk.get_bone_rest(i)
		var parent: int = sk.get_bone_parent(i)
		var pname: String = sk.get_bone_name(parent) if parent >= 0 else "-"
		# The offset from the parent IS the limb segment's direction: a thigh whose child
		# calf sits at (0, -0.2, 0.01) runs down local -Y, so the swing axis is the one
		# perpendicular to both that and the body's long axis.
		var o: Vector3 = rest.origin
		print("  %2d %-18s parent=%-14s rest_origin=(%+.3f, %+.3f, %+.3f) len=%.3f"
			% [i, sk.get_bone_name(i), pname, o.x, o.y, o.z, o.length()])
	# Where the mesh actually is, so the gait can be scaled to the animal.
	var mis: Array = root.find_children("*", "MeshInstance3D", true, false)
	if not mis.is_empty():
		var mi: MeshInstance3D = mis[0]
		print("  mesh aabb: %s" % str(mi.get_aabb().size.snappedf(0.001)))
	root.queue_free()
