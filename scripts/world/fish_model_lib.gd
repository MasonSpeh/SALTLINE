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

static func fauna_path(species_id: String) -> String:
	return "res://assets/models/fauna/%s/%s.glb" % [species_id, species_id]

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

## Give an UNTEXTURED species mesh the colour the fish table already assigns it.
##
## s15 (2026-07-26): the Meshy account ran down to its last credits mid-wave, so seven of
## the new species shipped as PREVIEW meshes — correct geometry, but glTF primitives with
## no material at all. The schools survive that (underwater_world pushes the table's
## school tint straight into the swim shader), but a fish in the player's HAND has no
## shader in front of it: it was rendering as a blank chalk-white fish, which reads worse
## than the coloured capsule it replaced. So the same `school.tint` the shoal uses becomes
## a plain albedo here, and a landed pollock is a pollock-coloured pollock.
##
## Keyed on "has no albedo texture", not on the species id: every properly refined model
## in the tree carries a baseColorTexture, so this touches exactly the meshes that need it
## and silently stops applying to any species once its textures are generated.
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
			var m: BaseMaterial3D = src.duplicate() if src else StandardMaterial3D.new()
			m.albedo_color = tint
			m.roughness = 0.55                # wet fish: damp, not glossy, not chalk
			m.metallic = 0.0
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
static func _char(model: Node3D) -> void:
	for mi in _meshes(model):
		var inst: MeshInstance3D = mi
		if inst.mesh == null:
			continue
		for s in range(inst.mesh.get_surface_count()):
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
