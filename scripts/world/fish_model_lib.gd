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
	if cooked:
		_char(model)
	return model

## Strip a "cooked_" prefix to recover the underlying species id.
##   "cooked_fish_herring" -> "fish_herring"; "fish_herring" -> "fish_herring".
static func species_of(item_id: String) -> String:
	return item_id.trim_prefix("cooked_")

# ---- internals ----

## Darken every surface to a seared look. Duplicates the imported PBR material so the
## textures survive; the albedo tint is crushed to a char grey-brown and roughness is
## lifted (a cooked surface isn't glossy). No motion shader — a plated fish is dead.
static func _char(model: Node3D) -> void:
	for mi in _meshes(model):
		var inst: MeshInstance3D = mi
		if inst.mesh == null:
			continue
		for s in range(inst.mesh.get_surface_count()):
			var src := inst.mesh.surface_get_material(s) as BaseMaterial3D
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
