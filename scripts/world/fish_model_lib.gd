extends RefCounted
## Real 3-D fish for a held / dropped / hung fish item.
##
## The fauna generator drops per-species meshes into assets/models/fauna/<id>/<id>.glb
## (the SAME meshes the underwater schools use). This lib loads one, normalised to a
## hand-held size, so a caught fish reads as that species instead of a coloured capsule.
## Missing asset -> returns null, and ItemVisual keeps its procedural silhouette; a fish
## generating in the background never leaves a hole in the world.
##
## Cooked fish reuse the raw species mesh, darkened to a seared char (albedo crushed to a
## grey-brown, roughness up) — same shape, off the pan.
##
## Preload it (class cache lags for referencing scripts):
##   const FISH_MODEL := preload("res://scripts/world/fish_model_lib.gd")
##   var m := FISH_MODEL.build("fish_herring", false)   # raw
##   var c := FISH_MODEL.build("fish_herring", true)    # seared

const ANIM := preload("res://scripts/world/creature_anim.gd")

## Default longest-axis size in the hand (metres). Callers scale by species heft.
const HELD_SIZE := 0.42

## ---------------------------------------------------------------- SPECIES ID -> MESH SLUG
## Where a fish.json species id and its .glb slug are not the same word.
##
## TWO KINDS OF ENTRY LIVE HERE, AND THEY HAVE OPPOSITE LIFETIMES. Read this before deleting
## anything out of the table.
##
##   PLACEHOLDER (temporary) — a species whose own .glb has not been generated yet, borrowing
##   the nearest silhouette in the tree so it lands as a FISH instead of the default grey
##   capsule. Delete the entry the moment the real asset exists and the species picks up its
##   own mesh with no other edit anywhere. The table's own `school.tint` is applied on top by
##   _skin() below, so a borrowed body still comes up the right COLOUR for the species
##   wearing it. There are none right now: the swordfish, the last one, got its own mesh in
##   s24.
##
##   PERMANENT — the ten `trop_*` entries below. These are NOT borrows and must NOT be
##   deleted "once the real asset arrives": the real asset is the one they already point at.
##   The reason the two names differ is a hard constraint elsewhere. reef_fish.gd shipped the
##   reef community under Tripo's own slugs (trop_clown, trop_angel, ...), and a fish.json id
##   MUST begin with "fish_" — sixteen literal begins_with("fish_") / begins_with("cooked_")
##   tests across bench_panel, ship_cat, item_visual, hang_line, cold_store and fishing_rod
##   would silently drop a species called `trop_clown` out of the pack, the stove, the drying
##   line and the cold store, with no error anywhere. Renaming the GLB directories instead
##   would break reef_fish.gd's MODEL_PATH and creature_anim.gd's FACING_OVERRIDES, which are
##   keyed on the slug and were measured against it. So the id and the slug differ on
##   purpose, permanently, and this table is the join.
##
## s52: the ten reef species became CATCHABLE with zero new assets — all ten meshes were
## already in the tree and already swimming the caisson reef, and all ten together are
## 16,199 triangles (measured off the GLB index buffers), i.e. less than ONE undecimated
## leopard grouper at 198,902 (KNOWN_ISSUES:265-274).
const MESH_ALIAS := {
	"fish_clownfish": "trop_clown",
	"fish_yellow_tang": "trop_yellow_tang",
	"fish_damsel": "trop_damsel",
	"fish_cleaner_wrasse": "trop_wrasse",
	"fish_butterflyfish": "trop_butterfly",
	"fish_blue_tang": "trop_blue_tang",
	"fish_anthias": "trop_anthias",
	"fish_triggerfish": "trop_triggerfish",
	"fish_emperor_angel": "trop_angel",
	"fish_parrotfish": "trop_parrot",
}

static func fauna_path(species_id: String) -> String:
	var slug: String = String(MESH_ALIAS.get(species_id, species_id))
	return "res://assets/models/fauna/%s/%s.glb" % [slug, slug]

## Return true when a real mesh exists for this RAW species id.
static func has_model(species_id: String) -> bool:
	return ResourceLoader.exists(fauna_path(species_id))

## Build a held-size model Node3D for a species, or null when the asset is absent.
##   species_id — the RAW fish id (e.g. "fish_herring"); pass the raw id even for a
##                cooked meal (derive it with species_of()).
##   cooked     — darken the surfaces to a seared char.
##   target_m   — longest-axis size in metres (default HELD_SIZE).
static func build(species_id: String, cooked: bool = false, target_m: float = HELD_SIZE) -> Node3D:
	var model: Node3D = ANIM.load_model(fauna_path(species_id), target_m)
	if model == null:
		return null
	_skin(model, species_id)
	if cooked:
		_char(model)
	return model

## Strip a "cooked_" prefix to recover the underlying species id.
##   "cooked_fish_herring" -> "fish_herring"; "fish_herring" -> "fish_herring".
static func species_of(item_id: String) -> String:
	return item_id.trim_prefix("cooked_")

# ---- internals ----

## Give an UNTEXTURED species mesh a real fish read, built from the colour the fish table
## already assigns it.
##
## s15 (2026-07-26): the Meshy account ran down to its last credits mid-wave, so SEVEN of
## the new species shipped as PREVIEW meshes — correct geometry, but glTF primitives with
## no material at all. Verified s52 by parsing the GLBs directly: 0 materials, 0 textures,
## 0 images, and POSITION/NORMAL/TEXCOORD_0 with no COLOR_0. The seven are
##   fish_anchor_ray  fish_gannet_mackerel  fish_kelp_pipefish  fish_lantern_dogfish
##   fish_rust_wrasse  fish_squall_garfish  fish_tallow_pollock
## The schools survive it (underwater_world pushes the table's tint into the swim shader),
## but a fish in the player's HAND has no shader in front of it: it rendered chalk-white,
## which reads worse than the coloured capsule it replaced.
##
## s15's cover was one flat albedo. That stopped the white and produced the owner's next
## report instead — "it shouldnt be just 1 color" — because a single uniform matte value
## over a whole body is not a fish, it is a fish-shaped swatch. There is nothing to fall
## back to: with 0 materials in the GLB, removing this override returns Godot's default
## white, i.e. the s15 failure. The colour has to be SYNTHESISED, so it may as well be
## synthesised into something that reads.
##
## materials/fish_skin.gdshader does that from the same one number: countershading (dark
## back, pale belly) off the WORLD normal, body-locked mottle, and a wet fresnel sheen.
## The shader's header records why the countershade cannot key off a body axis — the seven
## meshes disagree about which axis is dorsoventral and none of them says which end is the
## back.
##
## Still keyed on "has no albedo texture", not on a species list: every properly refined
## model in the tree carries a baseColorTexture, so this touches exactly the meshes that
## need it and silently stops applying to any species the moment its textures land. That
## is what makes regenerating these seven a drop-in with no code change.
const SKIN_SHADER := preload("res://materials/fish_skin.gdshader")

static func _skin(model: Node3D, species_id: String) -> void:
	var tint: Color = _tint_of(species_id)
	if tint.a < 0.5:                          # species not in the table / no tint
		return
	for mi in _meshes(model):
		var inst: MeshInstance3D = mi
		if inst.mesh == null:
			continue
		for s in range(inst.mesh.get_surface_count()):
			var src := inst.mesh.surface_get_material(s) as BaseMaterial3D
			if src != null and src.albedo_texture != null:
				continue                      # a real texture pass: leave it alone
			var m := ShaderMaterial.new()
			m.shader = SKIN_SHADER
			m.set_shader_parameter("base_tint", Vector3(tint.r, tint.g, tint.b))
			inst.set_surface_override_material(s, m)

## The fish table's school tint for a species, or a zero-alpha Color when it has none.
##
## Read straight out of data/fish.json rather than through FishTable, deliberately:
## FishTable reaches for the GameClock autoload to build a catch context, and this is a
## leaf VISUAL lib that ItemVisual preloads. Borrowing the table's parser here would drag
## the clock into the load graph of anything that just wants to draw a fish — and it
## breaks flat in any harness that runs without the autoloads. One cached parse of six
## floats is cheaper than that coupling. data/fish.json stays the one source of truth
## either way; only the reader differs.
static var _tints: Dictionary = {}

static func _tint_of(species_id: String) -> Color:
	if _tints.is_empty():
		var f: FileAccess = FileAccess.open("res://data/fish.json", FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				for id in (parsed as Dictionary):
					var def: Variant = (parsed as Dictionary)[id]
					if not (def is Dictionary):
						continue
					var school: Variant = (def as Dictionary).get("school")
					if not (school is Dictionary):
						continue
					var t: Variant = (school as Dictionary).get("tint")
					if t is Array and (t as Array).size() >= 3:
						_tints[id] = Color(float(t[0]), float(t[1]), float(t[2]))
		# A miss must not re-read the file on every fish landed.
		_tints["_loaded"] = Color(0, 0, 0, 0)
	return _tints.get(species_id, Color(0, 0, 0, 0))

## Darken every surface to a seared look. Duplicates the imported PBR material so the
## textures survive; the albedo tint is crushed to a char grey-brown and roughness is
## lifted (a cooked surface isn't glossy). No motion shader — a plated fish is dead.
##
## Reads the OVERRIDE first: on an untextured species _skin() has already put the table's
## colour there, and searing must crush that, not the white nothing underneath it.
##
## THE SHADER BRANCH IS NOT OPTIONAL. Since s52 the seven untextured species wear a
## ShaderMaterial, and `as BaseMaterial3D` on one returns NULL — which would fall straight
## through to `StandardMaterial3D.new()` and plate a pure WHITE fish, silently, only on
## the cooked path. The shader carries its own `sear` uniform for exactly this reason.
static func _char(model: Node3D) -> void:
	for mi in _meshes(model):
		var inst: MeshInstance3D = mi
		if inst.mesh == null:
			continue
		for s in range(inst.mesh.get_surface_count()):
			var shaded := inst.get_surface_override_material(s) as ShaderMaterial
			if shaded != null:
				var sm: ShaderMaterial = shaded.duplicate()
				sm.set_shader_parameter("sear", 1.0)
				inst.set_surface_override_material(s, sm)
				continue
			var src := inst.get_surface_override_material(s) as BaseMaterial3D
			if src == null:
				src = inst.mesh.surface_get_material(s) as BaseMaterial3D
			var m: BaseMaterial3D = src.duplicate() if src else StandardMaterial3D.new()
			var a: Color = m.albedo_color
			m.albedo_color = Color(a.r * 0.35, a.g * 0.30, a.b * 0.26, a.a)
			m.roughness = clampf(m.roughness + 0.35, 0.0, 1.0)
			m.metallic = 0.0
			m.emission_enabled = false
			inst.set_surface_override_material(s, m)

static func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
