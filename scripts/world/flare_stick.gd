class_name FlareStick extends PhysProp
## A lit emergency flare: thrown physics prop, burns ~45s of harsh red light.
## While burning, its radius counts as light — the crab will not cross it (Rule 7
## counterplay). Floats if it lands in the sea. Can be picked back up and re-thrown.

const BURN_SECONDS: float = 45.0
const DETER_RADIUS: float = 5.0

var lit: bool = true
var _light: OmniLight3D
var _age: float = 0.0

func _ready() -> void:
	display_name = "Burning Flare"
	buoyant = true
	mass = 0.3
	add_to_group("lit_flares")
	_build_visual(Vector3(0.09, 0.28, 0.09), MatLib.flat(Color(0.9, 0.2, 0.12), true, 3.0))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.25, 0.12)
	_light.light_energy = 2.6
	_light.omni_range = 8.0
	_light.light_volumetric_fog_energy = 2.5
	add_child(_light)

## Build a simple boxed mesh + matching collision for this physics prop.
func _build_visual(size: Vector3, material: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mi.mesh = bm
	add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	add_child(col)

func _process(delta: float) -> void:
	if not lit:
		return
	_age += delta
	# Harsh flicker.
	_light.light_energy = 2.6 * (0.85 + 0.15 * sin(_age * 31.0) * sin(_age * 7.3)) \
		* clampf((BURN_SECONDS - _age) / 8.0, 0.0, 1.0)
	if _age >= BURN_SECONDS:
		lit = false
		display_name = "Spent Flare"
		remove_from_group("lit_flares")
		_light.queue_free()
		for c in get_children():
			if c is MeshInstance3D:
				c.mesh.material = MatLib.flat(Color(0.25, 0.12, 0.1))
