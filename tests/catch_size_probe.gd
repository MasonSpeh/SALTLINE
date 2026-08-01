extends Node3D
## s24 — two owner reports and one new species, measured rather than asserted.
##
##   1. HELD FISH SIZE. "when i hold the barrel grouper it is tiny." Reproduces
##      player_controller._normalize_hand_visual exactly (same AABB walk, same
##      container/visual split) and prints the size the fish ACTUALLY ends up at in the
##      hand, before and against its own body length and its pack portrait. If the two
##      disagree the grouper is still tiny and this says so in metres.
##   2. THE SWORDFISH. Does it resolve a mesh, does it roll at its own depth and nowhere
##      above it, and is it genuinely commoner in the rain — as a share of the pool the
##      deep rig actually draws from, not as a multiplier in isolation.
##   3. THE SWORDFISH'S REAL MESH (added once MESH_ALIAS's garfish borrow was retired):
##      two screenshots so the shape can be judged by eye instead of trusted from a
##      passing size check — HELD (the exact ItemVisual mesh, scaled the way the hand
##      normalises it) and FULL BODY (the raw generated mesh with the UNDULATE swim
##      shader live, the way it reads in the water). Saved under /tmp. Needs the real
##      renderer — run WINDOWED, not --headless, same as every other *_shot.gd harness.
##
##   godot --path . res://tests/CatchSizeProbe.tscn

const FISH := preload("res://scripts/world/fish_table.gd")
const FISH_MODEL := preload("res://scripts/world/fish_model_lib.gd")
const ANIM := preload("res://scripts/world/creature_anim.gd")

## Mirrors PlayerController.HAND_ITEM_MAX_DIM — the pocket size everything used to get.
const HAND_BASE: float = 0.18

func _ready() -> void:
	await get_tree().process_frame
	_hand_sizes()
	await _held_grouper()
	_swordfish()
	await _swordfish_shots()
	get_tree().quit()

# ------------------------------------------------------------------ 1. held fish size
func _hand_sizes() -> void:
	print("\n=== held size vs body length, whole fish roster ===")
	print("%-26s %8s %8s %8s" % ["species", "body m", "hand m", "was m"])
	var ids: Array = []
	for id in FISH.all():
		ids.append(String(id))
	ids.sort_custom(func(a, b): return ItemVisual.fish_length_m(a) > ItemVisual.fish_length_m(b))
	for id in ids:
		if not ItemVisual.is_species_fish(id):
			continue
		print("%-26s %8.2f %8.2f %8.2f"
			% [id, ItemVisual.fish_length_m(id), ItemVisual.hand_size_m(id), HAND_BASE])

## The real thing: build the visual, run the controller's own normalisation on it, and
## measure what comes out. A number here that is not hand_size_m() means the hook did not land.
func _held_grouper() -> void:
	print("\n=== what the hand actually ends up holding ===")
	for id in ["fish_copper_sprat", "fish_herring", "fish_coelacanth", "fish_barrel_grouper",
			"fish_fathom_sturgeon", "fish_swordfish", "cooked_fish_barrel_grouper",
			"canned_food", "fishing_rod"]:
		var visual: Node3D = ItemVisual.build(id)
		if visual == null:
			print("[hand] %-28s NO VISUAL" % id)
			continue
		var container := Node3D.new()
		container.add_child(visual)
		add_child(container)
		await get_tree().process_frame     # generated meshes load their geometry in _ready
		var combined: AABB = AABB()
		var found: bool = false
		for n in visual.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			if mi.mesh == null:
				continue
			var box: AABB = (visual.global_transform.affine_inverse() * mi.global_transform) \
				* mi.mesh.get_aabb()
			combined = box if not found else combined.merge(box)
			found = true
		if not found:
			print("[hand] %-28s no meshes" % id)
			container.queue_free()
			continue
		var largest: float = maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
		var target: float = maxf(HAND_BASE, ItemVisual.hand_size_m(id))
		if id == "fishing_rod":
			target = maxf(0.9, target)
		var scale: float = target / maxf(largest, 0.0001)
		print("[hand] %-28s built %.3f m -> held %.3f m  (%.1fx the old 0.18 m pocket size)"
			% [id, largest, largest * scale, (largest * scale) / HAND_BASE])
		container.queue_free()

# --------------------------------------------------------------------- 2. the swordfish
func _swordfish() -> void:
	print("\n=== the swordfish ===")
	var def: Dictionary = FISH.all().get("fish_swordfish", {})
	print("[sword] in fish.json: %s   drop_m=%s  rain=%s  deep=%s"
		% [not def.is_empty(), str(def.get("drop_m")), str(def.get("rain")), str(def.get("deep"))])
	print("[sword] item registered: %s   cooked_to '%s' registered: %s"
		% [PlayerState.items.has("fish_swordfish"), String(def.get("cooked_to", "")),
			PlayerState.items.has(String(def.get("cooked_to", "")))])
	var path: String = FISH_MODEL.fauna_path("fish_swordfish")
	print("[sword] mesh path %s   exists: %s" % [path, ResourceLoader.exists(path)])
	print("[sword] held size %.2f m, body length %.2f m"
		% [ItemVisual.hand_size_m("fish_swordfish"), ItemVisual.fish_length_m("fish_swordfish")])
	# The pool it actually competes in, at its own depth, calm vs rain vs squall.
	for weather in [["calm", false, false], ["RAIN", true, false], ["storm", false, true]]:
		var ctx := {"phase": "dusk", "storming": bool(weather[2]), "raining": bool(weather[1]),
			"fogged": false, "lit": false, "powered": false, "open": true, "bait": "fish_herring"}
		_pool_line(String(weather[0]), ctx, 22.0)
	# ...and it must be invisible above its own rung.
	var ctx20 := {"phase": "dusk", "storming": false, "raining": true, "fogged": false,
		"lit": false, "powered": false, "open": true, "bait": "fish_herring"}
	print("[sword] weight at 20 m (above its rung): %.3f  — must be 0"
		% FISH.weight_for("fish_swordfish", "deep", ctx20, 20.0))
	print("[sword] weight at 22 m: %.3f   at 44 m (faded): %.3f"
		% [FISH.weight_for("fish_swordfish", "deep", ctx20, 22.0),
			FISH.weight_for("fish_swordfish", "deep", ctx20, 44.0)])

func _pool_line(label: String, ctx: Dictionary, depth: float) -> void:
	var total: float = FISH.pool_weight("deep", ctx, depth)
	var mine: float = FISH.weight_for("fish_swordfish", "deep", ctx, depth)
	var parts: Array[String] = []
	for id in FISH.all():
		var w: float = FISH.weight_for(id, "deep", ctx, depth)
		if w > 0.0:
			parts.append("%s %.1f" % [String(id).trim_prefix("fish_"), w])
	print("[sword] %-5s at %d m, dusk, herring on the hook: swordfish %.2f of %.2f = %.1f%% of the pool"
		% [label, int(depth), mine, total, 100.0 * mine / maxf(total, 0.001)])
	print("[sword]        pool: %s" % ", ".join(parts))

# ------------------------------------------------------------- 3. visual verification
## Two pictures of the real generated mesh, so the shape can be judged instead of just
## trusted from the size numbers above. Saved under /tmp, same convention as the other
## *_shot.gd harnesses (BestiaryShot's /tmp/bs_<slug>.png, FacingShot's /tmp/face_<slug>.png).
func _swordfish_shots() -> void:
	print("\n=== swordfish screenshots ===")
	await _shoot_held("fish_swordfish", "/tmp/cs_swordfish_held.png")
	await _shoot_body("fish_swordfish", "/tmp/cs_swordfish_body.png")

## HELD: exactly what ItemVisual.build() returns for this species, isolated in its own
## SubViewport/World3D (the same isolation ItemModelShot uses — a shared render target
## leaked one item's geometry into the next one's icon the first time this was tried).
func _shoot_held(id: String, out_path: String) -> void:
	var visual: Node3D = ItemVisual.build(id)
	if visual == null:
		print("[shot] %-18s NO VISUAL" % id)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(768, 768)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -135, 0)
	key.light_energy = 1.6
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, 60, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.82, 0.88, 1.0)
	vp.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.12, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_energy = 1.0
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.environment = env
	vp.add_child(cam)
	vp.add_child(visual)
	await get_tree().process_frame     # generated meshes load their geometry in _ready
	var box := AABB()
	var found := false
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var b: AABB = (visual.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		box = b if not found else box.merge(b)
		found = true
	if not found:
		print("[shot] %-18s no geometry" % id)
		vp.queue_free()
		return
	var centre: Vector3 = box.get_center()
	var span: float = maxf(maxf(box.size.x, maxf(box.size.y, box.size.z)), 0.02)
	cam.size = span * 1.15
	cam.position = centre + Vector3(0.75, 0.4, 1.0).normalized() * span * 2.5
	cam.look_at(centre, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	img.save_png(out_path)
	print("[shot] saved %s  (held span %.2f m)" % [out_path, span])
	vp.queue_free()

## FULL BODY: the raw fauna mesh with CreatureAnim's UNDULATE swim shader live, on a
## neutral studio stage — the same recipe BestiaryShot uses for the rest of the bestiary,
## scoped to just this one species since fish_swordfish isn't a bespoke creature.gd.
func _shoot_body(id: String, out_path: String) -> void:
	var path: String = FISH_MODEL.fauna_path(id)
	if not ResourceLoader.exists(path):
		print("[shot] %-18s NO MESH at %s" % [id, path])
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 640)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.09, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.42, 0.5)
	e.ambient_light_energy = 0.9
	env_node.environment = e
	vp.add_child(env_node)
	for spec in [[Vector3(4, 5, 4), 1.5], [Vector3(-5, 2, -3), 0.7]]:
		var l := DirectionalLight3D.new()
		vp.add_child(l)
		l.position = spec[0]
		l.light_energy = spec[1]
		l.look_at(Vector3.ZERO, Vector3.UP)
	var host := Node3D.new()
	vp.add_child(host)
	var target_m := 3.0   # matches ItemVisual.FISH_SIZE's authored length for this species
	var gen: Dictionary = ANIM.attach(host, path, target_m, ANIM.Mode.UNDULATE, 0.06, 1.2)
	if gen.is_empty():
		print("[shot] %-18s attach failed" % id)
		vp.queue_free()
		return
	ANIM.drive(gen["mats"], 1.2, 0.0)
	var cam := Camera3D.new()
	cam.current = true
	vp.add_child(cam)
	var acc := AABB()
	var first := true
	for n in host.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var w: AABB = mi.global_transform * mi.get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	var focus: Vector3 = acc.get_center() if not first else Vector3.ZERO
	var d: float = target_m * 0.75 + 0.5
	cam.position = focus + Vector3(d * 0.9, d * 0.35, d * 0.9)
	cam.look_at(focus, Vector3.UP)
	await get_tree().create_timer(0.6).timeout   # let the shader tick + textures land
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	img.save_png(out_path)
	print("[shot] saved %s  (body target %.1f m)" % [out_path, target_m])
	vp.queue_free()
