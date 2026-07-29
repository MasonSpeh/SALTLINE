extends Node
## GROUND TRUTH on the shadow pipeline. Reads back what is ACTUALLY in effect at runtime
## rather than what the source says it set, because in Godot assigning a property name that
## does not exist on the class is a silent no-op — the exact bug that left this project's
## sun on its 1.0 default normal bias for weeks while a line of code "set" it to 0.45.
##
## Three passes:
##   1. CLASS AUDIT. Enumerate every real shadow property on DirectionalLight3D /
##      OmniLight3D / SpotLight3D, then check every name this codebase assigns against it.
##      Anything the codebase writes that is not in the class list is dead code.
##   2. PROJECT SETTINGS. What project.godot asks for vs. what the running RenderingServer
##      and root Viewport actually hold (the positional atlas is a VIEWPORT property, so a
##      project setting is only a default and can be overridden out from under the code).
##   3. LIVE NODES. get() on the real sun and on the shadow-casting fixtures RenderBudget
##      manages, after the world has streamed in.
##
## Run: godot --headless --path . res://tests/ShadowAudit.tscn

## Every shadow-ish property name assigned anywhere in scripts/. Checked for existence.
const ASSIGNED_NAMES: Array[String] = [
	"shadow_enabled", "shadow_bias", "shadow_normal_bias", "shadow_blur",
	"shadow_opacity", "shadow_reverse_cull_face", "shadow_caster_mask",
	"directional_shadow_mode", "directional_shadow_max_distance",
	"directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3",
	"directional_shadow_blend_splits", "directional_shadow_fade_start",
	"directional_shadow_pancake_size",
	# The known-bad name. Must report MISSING.
	"directional_shadow_normal_bias", "directional_shadow_bias", "directional_shadow_blur",
	# distance_fade_shadow exists on Light3D but is Forward+/Mobile only.
	"distance_fade_enabled", "distance_fade_shadow",
]

const SETTINGS: Array[String] = [
	"rendering/renderer/rendering_method",
	"rendering/lights_and_shadows/directional_shadow/size",
	"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
	"rendering/lights_and_shadows/directional_shadow/16_bits",
	"rendering/lights_and_shadows/positional_shadow/atlas_size",
	"rendering/lights_and_shadows/positional_shadow/atlas_16_bits",
	"rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality",
	"rendering/lights_and_shadows/positional_shadow/atlas_quadrant_0_subdiv",
	"rendering/lights_and_shadows/positional_shadow/atlas_quadrant_1_subdiv",
	"rendering/lights_and_shadows/positional_shadow/atlas_quadrant_2_subdiv",
	"rendering/lights_and_shadows/positional_shadow/atlas_quadrant_3_subdiv",
]

func _ready() -> void:
	print("\n================ SHADOW AUDIT ================")
	print("godot        : %s" % Engine.get_version_info().string)
	print("rendering_dev: %s  (null => Compatibility/GL path)"
		% ("null" if RenderingServer.get_rendering_device() == null else "present"))

	_class_audit()
	_settings_audit()

	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	print("\n-- waiting 22 s for the rig + RenderBudget sweeps --")
	await get_tree().create_timer(22.0).timeout
	_viewport_audit()
	_live_audit(main)
	print("================ END AUDIT ================\n")
	get_tree().quit()

func _class_audit() -> void:
	print("\n---- 1. CLASS AUDIT: does the property actually exist? ----")
	for cls in ["DirectionalLight3D", "OmniLight3D", "SpotLight3D"]:
		var have: Dictionary = {}
		for p in ClassDB.class_get_property_list(cls, false):
			have[p["name"]] = true
		var real: Array[String] = []
		var dead: Array[String] = []
		for n in ASSIGNED_NAMES:
			if have.has(n):
				real.append(n)
			else:
				dead.append(n)
		print("  %s" % cls)
		print("     REAL   : %s" % ", ".join(real))
		print("     MISSING: %s" % ", ".join(dead))
		# Also dump everything shadow-named the class really has, so nothing is guessed.
		var all_shadow: Array[String] = []
		for k in have.keys():
			if String(k).contains("shadow"):
				all_shadow.append(String(k))
		all_shadow.sort()
		print("     class exposes: %s" % ", ".join(all_shadow))

func _settings_audit() -> void:
	print("\n---- 2. PROJECT SETTINGS ----")
	for s in SETTINGS:
		print("  %-72s = %s" % [s, str(ProjectSettings.get_setting(s, "<UNSET>"))])

func _viewport_audit() -> void:
	var vp: Viewport = get_viewport()
	print("\n---- 2b. ROOT VIEWPORT (positional atlas lives HERE, not in the server) ----")
	print("  positional_shadow_atlas_size   = %d" % vp.positional_shadow_atlas_size)
	print("  positional_shadow_atlas_16_bits= %s" % str(vp.positional_shadow_atlas_16_bits))
	for q in range(4):
		print("  positional_shadow_atlas_quad_%d = %d"
			% [q, vp.get("positional_shadow_atlas_quad_%d" % q)])
	print("  msaa_3d                        = %d" % vp.msaa_3d)
	print("  scaling_3d_scale               = %.3f" % vp.scaling_3d_scale)

func _live_audit(main: Node3D) -> void:
	print("\n---- 3. LIVE NODES ----")
	var suns: Array = []
	for c in main.get_children():
		if c is DirectionalLight3D:
			suns.append(c)
	for i in range(suns.size()):
		var d: DirectionalLight3D = suns[i]
		print("  DirectionalLight3D #%d  energy %.3f  shadow_enabled %s"
			% [i, d.light_energy, str(d.shadow_enabled)])
		for n in ["shadow_bias", "shadow_normal_bias", "shadow_blur", "shadow_opacity",
				"directional_shadow_mode", "directional_shadow_max_distance",
				"directional_shadow_split_1", "directional_shadow_split_2",
				"directional_shadow_split_3", "directional_shadow_blend_splits",
				"directional_shadow_fade_start", "directional_shadow_pancake_size"]:
			print("      %-34s = %s" % [n, str(d.get(n))])
		# What the code TRIED to set under the wrong name. null => never existed.
		print("      %-34s = %s  <-- null means the assignment is a no-op"
			% ["directional_shadow_normal_bias", str(d.get("directional_shadow_normal_bias"))])
		# Effective texel density of the far split.
		var dsize: int = ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/size", 4096)
		var per_split: int = dsize
		match d.directional_shadow_mode:
			DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS:
				per_split = dsize / 2
			DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
				per_split = dsize / 2
		var far_extent: float = d.directional_shadow_max_distance \
			* (1.0 - (d.directional_shadow_split_1 if d.directional_shadow_mode != 0 else 0.0))
		print("      -> atlas %d, per-split %d, far split covers %.1f m = %.1f texels/m (%.1f mm/texel)"
			% [dsize, per_split, far_extent, per_split / maxf(far_extent, 0.001),
				1000.0 * far_extent / maxf(float(per_split), 1.0)])

	var casters: Array = []
	var enrolled: Array = []
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var l := n as Light3D
		if l != null and not (l is DirectionalLight3D):
			if l.shadow_enabled:
				casters.append(l)
			if is_equal_approx(l.shadow_normal_bias, 0.55):
				enrolled.append(l)
	print("\n  positional lights CURRENTLY casting: %d" % casters.size())
	for l in casters:
		print("      %-46s bias %.4f normal_bias %.3f blur %.3f  (%s)"
			% [l.name, l.shadow_bias, l.shadow_normal_bias, l.shadow_blur, l.get_class()])
	print("  positional lights RenderBudget has retuned (normal_bias==0.55): %d" % enrolled.size())
	var rb: Node = main.get_node_or_null("RenderBudget")
	print("  RenderBudget node present: %s" % str(rb != null))
	if rb != null:
		print("  RenderBudget SHADOW_BUDGET = %s" % str(rb.get("SHADOW_BUDGET")))
		print("  _shadow_lights enrolled    = %s" % str((rb.get("_shadow_lights") as Array).size()))
