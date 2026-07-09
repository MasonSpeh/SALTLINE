extends Node3D
## The Phase 1 verb demo room: one of each interactable proving all six verbs.
## Play it directly: godot res://tests/VerbRoom.tscn

func _ready() -> void:
	# Room: 14x14, one light, a mezzanine for the ladder.
	_box(Vector3(0, -0.25, 0), Vector3(14, 0.5, 14), MatLib.deck_plate())
	_box(Vector3(0, 2, -7), Vector3(14, 4, 0.3), MatLib.interior_wall())
	_box(Vector3(0, 2, 7), Vector3(14, 4, 0.3), MatLib.interior_wall())
	_box(Vector3(-7, 2, 0), Vector3(0.3, 4, 14), MatLib.interior_wall())
	_box(Vector3(7, 2, 0), Vector3(0.3, 4, 14), MatLib.interior_wall())
	_box(Vector3(4.5, 3.0, -5.5), Vector3(5, 0.3, 3), MatLib.deck_plate()) # mezzanine
	var light := OmniLight3D.new()
	light.light_energy = 1.0
	light.omni_range = 18
	add_child(light)
	light.position = Vector3(0, 3.5, 0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.45)
	env.environment = e
	add_child(env)

	# TAKE
	var take := Takeable.new()
	take.item_id = "canned_food"
	take.display_name = "Canned Food"
	add_child(take)
	take.position = Vector3(-4, 0.4, -4)
	take.build_box_visual(Vector3(0.3, 0.35, 0.3), Interactable.COLOR_TAKEABLE)
	# OPEN (door)
	var door := InteractDoor.new()
	door.display_name = "Door"
	add_child(door)
	door.position = Vector3(-4, 0, 0)
	door.build_box_visual(Vector3(0.12, 2.2, 1.1), Color(0.5, 0.52, 0.5))
	# READ
	var read := Readable.new()
	read.readable_id = "sphl_manual"
	read.display_name = "Manual Page"
	add_child(read)
	read.position = Vector3(-4, 1.2, 4)
	read.build_box_visual(Vector3(0.35, 0.45, 0.06), Interactable.COLOR_READABLE)
	# OPEN (loot)
	var crate := LootContainer.new()
	var crate_items: Array[String] = ["canned_peaches", "flare"]
	crate.items = crate_items
	crate.display_name = "Crate"
	add_child(crate)
	crate.position = Vector3(0, 0.4, 4)
	crate.build_box_visual(Vector3(1.1, 0.8, 0.8), Color(0.5, 0.45, 0.3))
	# CONNECT + OPERATE (the power chain) + a light that proves it
	var spool := Takeable.new()
	spool.item_id = "cable_spool"
	spool.display_name = "Cable Spool"
	add_child(spool)
	spool.position = Vector3(0, 0.4, -4)
	spool.build_box_visual(Vector3(0.5, 0.5, 0.5), Interactable.COLOR_TAKEABLE)
	var cable := CableSegment.new()
	cable.display_name = "Burned Cable Gap"
	add_child(cable)
	cable.position = Vector3(2.5, 0.9, -6.6)
	cable.build_box_visual(Vector3(0.4, 0.5, 1.6), Color(0.12, 0.08, 0.06))
	var breaker := BreakerPanel.new()
	breaker.display_name = "Test Breaker"
	breaker.circuit_id = "topside_floodlights"
	add_child(breaker)
	breaker.position = Vector3(5, 1.4, -6.6)
	breaker.build_box_visual(Vector3(1.0, 1.4, 0.3), Interactable.COLOR_OPERABLE)
	breaker.set_cable(cable)
	var zone := LightZone.new()
	zone.circuit_id = "topside_floodlights"
	zone.zone_extents = Vector3(14, 5, 14)
	add_child(zone)
	zone.position = Vector3(0, 2, 0)
	var spot := SpotLight3D.new()
	spot.light_energy = 8.0
	spot.spot_range = 8.0
	spot.spot_angle = 60.0
	spot.light_color = Color(1.0, 0.9, 0.7)
	zone.add_light(spot)
	spot.position = Vector3(2, 1.8, 2)
	spot.rotation.x = deg_to_rad(-90)
	# CLIMB (up to the mezzanine)
	var ladder := Ladder.new()
	ladder.height = 3.2
	ladder.display_name = "Ladder"
	ladder.exit_forward = 0.9
	add_child(ladder)
	ladder.position = Vector3(2.2, 0, -3.8)
	ladder.rotation.y = deg_to_rad(180)
	var rail := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.6, 3.2, 0.12)
	rm.material = MatLib.flat(Interactable.COLOR_TAKEABLE)
	rail.mesh = rm
	ladder.add_child(rail)
	rail.position = Vector3(0, 1.6, 0)
	var lshape := CollisionShape3D.new()
	var lbox := BoxShape3D.new()
	lbox.size = Vector3(0.7, 3.2, 0.35)
	lshape.shape = lbox
	ladder.add_child(lshape)
	lshape.position = Vector3(0, 1.6, 0)

	# Test props: physics objects to pick up
	_add_prop(Vector3(-2, 0.6, 2), "Box", Vector3(0.4, 0.4, 0.4), Color(0.6, 0.3, 0.2))
	_add_prop(Vector3(2, 0.6, 2), "Sphere", Vector3(0.4, 0.4, 0.4), Color(0.2, 0.5, 0.7))
	_add_prop(Vector3(0, 0.6, 2), "Cylinder", Vector3(0.3, 0.5, 0.3), Color(0.7, 0.6, 0.2))

	# Player + UI
	var player: CharacterBody3D = load("res://scenes/Player.tscn").instantiate()
	add_child(player)
	player.position = Vector3(0, 0.2, 0)
	add_child(HUD.new())
	add_child(PauseMenu.new())

func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.material = mat
	b.use_collision = true
	add_child(b)
	b.position = pos

func _add_prop(pos: Vector3, shape_name: String, size: Vector3, color: Color) -> void:
	var prop := PhysProp.new()
	add_child(prop)
	prop.position = pos
	prop.mass = 1.0
	var mesh_inst := MeshInstance3D.new()
	prop.add_child(mesh_inst)
	match shape_name:
		"Box":
			var box := BoxMesh.new()
			box.size = size
			mesh_inst.mesh = box
			var col := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = size
			col.shape = box_shape
			prop.add_child(col)
		"Sphere":
			var sphere := SphereMesh.new()
			sphere.radius = size.x
			mesh_inst.mesh = sphere
			var col := CollisionShape3D.new()
			var sphere_shape := SphereShape3D.new()
			sphere_shape.radius = size.x
			col.shape = sphere_shape
			prop.add_child(col)
		"Cylinder":
			var cyl := CylinderMesh.new()
			cyl.radius = size.x
			cyl.height = size.y
			mesh_inst.mesh = cyl
			var col := CollisionShape3D.new()
			var cyl_shape := CylinderShape3D.new()
			cyl_shape.radius = size.x
			cyl_shape.height = size.y
			col.shape = cyl_shape
			prop.add_child(col)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mesh_inst.material_override = mat
