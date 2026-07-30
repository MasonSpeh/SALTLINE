extends Node3D
## S23 owner-bug ground truth: five reported fauna faults, measured off the live world in
## ONE build rather than five launches.
##
##   1. PYRAMID SNAIL FACING — a pyramid_snail.glb landed in s20 and the class was written
##      expecting CreatureAnim.replace() to return {}. Generated meshes do NOT share a
##      forward axis (herring gull -Z, hammerhead +X, ten tropical fish in three
##      conventions from one prompt), so the authored facing is correlated against real
##      travel here: the model node's six local axes vs the direction the animal actually
##      moves, over hundreds of frames. Whichever axis the HEAD lies on must ride at +1.
##      Also dumps the imported PBR material, which is where "too dark" lives.
##   2. HARBOR SEAL SEATING — measure the gap between the model's lowest point and the
##      collider under it while hauled out. Probed, never typed.
##   3. REEF FISH near the player — per-frame step, heading change and wall clearance for
##      the station the player is standing in, so "glitchy" becomes a number.
##   4. GLIDER RAY heights — the band each ray flies and what is above it.
##   5. THE WET-DECK GRUBS — what is actually at the tide-line positions, and its state.
##
##   godot --headless --path . res://tests/FaunaBugsProbe.tscn

const ANIM := preload("res://scripts/world/creature_anim.gd")
const SNAIL_GLB := "res://assets/models/fauna/pyramid_snail/pyramid_snail.glb"
const AXES := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN,
	Vector3.BACK, Vector3.FORWARD]
const AXIS_NAMES := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]

var _main: Node3D
var _player: Node3D

func _ready() -> void:
	AiBudget.enabled = false          # every animal at full rate: this is a measurement
	_dump_snail_material()
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	for i in range(20):
		await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player")
	await _snail_facing()
	await _seal_seat()
	await _reef_fish()
	_rays()
	_grubs()
	await _grubs_at_dawn()
	get_tree().quit()

# --------------------------------------------------------------- 1a. the snail's material
func _dump_snail_material() -> void:
	print("\n=== 1a. pyramid_snail.glb imported surface ===")
	var model: Node3D = ANIM.load_model(SNAIL_GLB, 0.95)
	if model == null:
		print("[snail] MISSING ", SNAIL_GLB)
		return
	add_child(model)
	var tris: int = 0
	for n in ANIM._mesh_instances(model):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		tris += int(mi.mesh.get_faces().size() / 3.0)
		var a: AABB = mi.get_aabb()
		print("[snail] mesh '%s'  local AABB pos=%s size=%s" % [mi.name,
			str(a.position.snappedf(0.001)), str(a.size.snappedf(0.001))])
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				print("[snail]   surface %d: NO BaseMaterial3D" % s)
				continue
			print("[snail]   surface %d: albedo=%s metallic=%.3f rough=%.3f spec=%.3f "
				% [s, str(src.albedo_color), src.metallic, src.roughness,
					src.metallic_specular]
				+ "albedo_tex=%s normal=%s ao=%s emis=%s"
				% [src.albedo_texture != null, src.normal_enabled,
					src.ao_enabled, src.emission_enabled])
	print("[snail] triangles (raw, undecimated): %d  scale=%s" % [tris, str(model.scale)])
	model.queue_free()

# ---------------------------------------------------------------- 1b. the snail's facing
func _snail_facing() -> void:
	print("\n=== 1b. pyramid snail: travel vs the model node's own local axes ===")
	var snails: Array = get_tree().get_nodes_in_group("snail_pyramid")
	print("[snail] %d pyramid snails in the world" % snails.size())
	if snails.is_empty():
		return
	# Only the free-roaming deck snails: the leg_reef climbers are on vertical concrete and
	# their heading is re-picked in the face plane, which is a different question.
	var deck: Array = []
	for s in snails:
		if (s as Node3D).global_position.y > 10.0:
			deck.append(s)
	if deck.is_empty():
		deck = snails
	print("[snail] measuring %d deck snails" % deck.size())
	var models: Array = []
	for s in deck:
		models.append(_generated(s))
	var sums: Array = []
	var prev: Array = []
	var moved: Array = []
	for i in range(deck.size()):
		var row := PackedFloat32Array()
		row.resize(AXES.size())
		sums.append(row)
		prev.append((deck[i] as Node3D).global_position)
		moved.append(0)
	var host_fwd: float = 0.0
	var samples: int = 0
	Engine.time_scale = 4.0
	for f in range(900):
		await get_tree().process_frame
		for i in range(deck.size()):
			var node: Node3D = deck[i]
			var model: Node3D = models[i]
			if model == null:
				continue
			var now: Vector3 = node.global_position
			var travel: Vector3 = now - prev[i]
			prev[i] = now
			if travel.length() < 0.0008:
				continue
			var t: Vector3 = travel.normalized()
			var mb: Basis = model.global_transform.basis.orthonormalized()
			for a in range(AXES.size()):
				sums[i][a] += (mb * (AXES[a] as Vector3)).normalized().dot(t)
			host_fwd += (node.global_transform.basis.orthonormalized() * Vector3.FORWARD).dot(t)
			moved[i] += 1
			samples += 1
	Engine.time_scale = 1.0
	if samples == 0:
		print("[snail] NOTHING MOVED — cannot measure")
		return
	var tot := PackedFloat32Array()
	tot.resize(AXES.size())
	for i in range(deck.size()):
		if moved[i] == 0:
			print("[snail] snail %d never moved" % i)
			continue
		var line: String = "[snail] snail %d (%d samples): " % [i, moved[i]]
		for a in range(AXES.size()):
			line += "%s %+.3f  " % [AXIS_NAMES[a], sums[i][a] / float(moved[i])]
			tot[a] += sums[i][a]
		print(line)
	var pooled: String = "[snail] POOLED (%d samples): " % samples
	for a in range(AXES.size()):
		pooled += "%s %+.4f  " % [AXIS_NAMES[a], tot[a] / float(samples)]
	print(pooled)
	print("[snail] host -Z . travel = %+.4f  (the crawler's own forward)"
		% (host_fwd / float(samples)))
	print("[snail] READ: the local axis the HEAD lies on must be the one at +1.000")
	var m0: Node3D = models[0]
	if m0 != null:
		print("[snail] model rotation_degrees=%s scale=%s"
			% [str(m0.rotation_degrees.snappedf(0.01)), str(m0.scale.snappedf(0.0001))])

# ------------------------------------------------------------------------ 2. the seal
func _seal_seat() -> void:
	print("\n=== 2. harbor seal haul-out seating ===")
	var seal: Node3D = null
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var s: Script = n.get_script()
		if s == null:
			continue
		if n.get("_haul") != null and n.get("_haul_floor") != null:
			seal = n
			break
	if seal == null:
		print("[seal] not found")
		return
	print("[seal] node=%s  _belly=%.4f  _haul=%s  _haul_floor=%.4f  _haul_snapped=%s"
		% [seal.name, float(seal.get("_belly")), str((seal.get("_haul") as Vector3).snappedf(0.001)),
			float(seal.get("_haul_floor")), str(seal.get("_haul_snapped"))])
	# Independent probe of the shelf, with every fauna collider excluded.
	var haul: Vector3 = seal.get("_haul")
	var from := Vector3(haul.x, 4.0, haul.z)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 8.0, 0))
	q.collision_mask = 1
	q.exclude = _fauna_rids()
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var shelf: float = float(hit["position"].y) if not hit.is_empty() else NAN
	print("[seal] independent floor probe under (%.2f, %.2f): y=%.4f  collider=%s"
		% [haul.x, haul.z, shelf,
			str(hit.get("collider", null))])
	# Force it hauled out and let it arrive.
	seal.set("_hauled", true)
	seal.set("_haul_timer", 1.0e9)
	seal.global_position = Vector3(haul.x, haul.y + 0.5, haul.z)
	for i in range(240):
		seal.set("_hauled", true)
		seal.set("_haul_timer", 1.0e9)
		await get_tree().process_frame
	var model: Node3D = seal.get("_model")
	if model == null:
		print("[seal] NO GENERATED MODEL — running the procedural body")
		return
	var low: float = ANIM.low_point(model)
	print("[seal] settled at %s  rot=%s"
		% [str(seal.global_position.snappedf(0.001)),
			str(seal.rotation.snappedf(0.0001))])
	print("[seal] model low point y=%.4f   shelf y=%.4f   GAP=%+.1f mm  (+ = hovering)"
		% [low, shelf, (low - shelf) * 1000.0])
	# Where every mesh of the model sits, so a hover can be told from a tilt.
	var box: AABB = _world_bounds(model)
	print("[seal] model world AABB pos=%s size=%s"
		% [str(box.position.snappedf(0.001)), str(box.size.snappedf(0.001))])
	# --- AND THE OTHER SEAL: the one that never hauls out and lives on the swell -----------
	# The patrol writes a FIXED y (-0.15 plus a porpoise arc) into an ocean whose surface is
	# an 11-band Gerstner sum. If the animal's belly is above Gyre.wave_height() at its own
	# xz for any real fraction of the loop it is flying, which is the other reading of "the
	# harbor seal floats above the surface".
	seal.set("_hauled", false)
	seal.set("_haul_timer", 1.0e9)
	var above: int = 0
	var samples: int = 0
	var worst: float = -1.0e9
	var belly_gap_sum: float = 0.0
	for i in range(600):
		seal.set("_hauled", false)
		seal.set("_haul_timer", 1.0e9)
		await get_tree().process_frame
		var p: Vector3 = seal.global_position
		var sea: float = Gyre.wave_height(Vector2(p.x, p.z), Gyre.water_time())
		var low2: float = ANIM.low_point(model)
		var gap: float = low2 - sea          # + = the BELLY is clear of the water
		belly_gap_sum += gap
		worst = maxf(worst, gap)
		if gap > 0.0:
			above += 1
		samples += 1
	print("[seal] SWIMMING: belly above the wave surface on %d of %d frames (%.1f%%), "
		% [above, samples, 100.0 * float(above) / float(maxi(samples, 1))]
		+ "mean belly-to-sea %+.3f m, worst %+.3f m" % [belly_gap_sum / float(maxi(samples, 1)), worst])
	print("[seal] sea state: trough floor %.3f m, wave_height at origin now %.3f"
		% [Gyre.trough_floor(), Gyre.wave_height(Vector2.ZERO, Gyre.water_time())])

# ------------------------------------------------------------------- 3. the reef fish
func _reef_fish() -> void:
	print("\n=== 3. tropical reef fish near the player ===")
	var rf: Node = null
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with("reef_fish.gd"):
			rf = n
			break
	if rf == null:
		print("[fish] reef_fish.gd node not found")
		return
	var stations: Array = rf.get("_stations")
	print("[fish] %d stations" % stations.size())
	if stations.is_empty():
		return
	# Pick a big skittish shoal — the failure the owner is describing is a crowd effect.
	var pick: Dictionary = {}
	for st in stations:
		if String(st["sp"]["slug"]) == "trop_damsel":
			pick = st
			break
	if pick.is_empty():
		pick = stations[0]
	var centre: Vector3 = pick["centre"]
	var outv: Vector3 = pick["out"]
	print("[fish] watching %s at %s (skit %.1f, stand %.2f, n=%d)"
		% [pick["sp"]["slug"], str(centre.snappedf(0.01)), float(pick["sp"]["skit"]),
			float(pick["sp"]["stand"]), (pick["fish"] as Array).size()])
	if _player:
		_player.set_physics_process(false)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		print("[fish] no camera — reef_fish will not tick")
		return
	# Fly the PLAYER in from 12 m to 1.5 m along the station's own face normal, logging the
	# per-frame motion of every fish. Position the player, not a loose camera: reef_fish
	# reads the active camera, which is the player's.
	var fish: Array = pick["fish"]
	var prev: Array = []
	var prev_step: Array = []
	for f in fish:
		prev.append((f as Node3D).global_position)
		prev_step.append(Vector3.ZERO)
	var worst_jerk: float = 0.0
	var worst_frame: int = -1
	var worst_speed: float = 0.0
	var min_wall: float = 1.0e9
	var wall: Vector3 = pick["wall"]
	var rows: Array = []
	var frames: int = 420
	for f in range(frames):
		var k: float = float(f) / float(frames - 1)
		var d: float = lerpf(12.0, 1.2, k)
		var eye: Vector3 = centre + outv * d
		if _player:
			_player.global_position = eye - Vector3(0, 1.6, 0)
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		var sum_speed: float = 0.0
		var sum_jerk: float = 0.0
		for i in range(fish.size()):
			var node: Node3D = fish[i]
			var now: Vector3 = node.global_position
			var step: Vector3 = now - prev[i]
			prev[i] = now
			var jerk: Vector3 = step - prev_step[i]
			prev_step[i] = step
			sum_speed += step.length() / maxf(dt, 0.0001)
			var jm: float = jerk.length() / maxf(dt * dt, 1.0e-8)
			sum_jerk += jm
			if jm > worst_jerk:
				worst_jerk = jm
				worst_frame = f
			var off: float = absf((now - wall).dot(outv))
			min_wall = minf(min_wall, off)
		var alarm: float = float(pick["alarm"])
		if f % 42 == 0 or f == frames - 1:
			rows.append("[fish] f%3d  player %5.2f m  alarm %.3f  mean speed %.3f m/s  "
				% [f, d, alarm, sum_speed / float(fish.size())]
				+ "mean |jerk| %.1f m/s^2  min wall gap %.3f m"
				% [sum_jerk / float(fish.size()), min_wall])
	for r in rows:
		print(r)
	print("[fish] worst single-fish |jerk| %.1f m/s^2 at frame %d, min wall gap over run %.3f m"
		% [worst_jerk, worst_frame, min_wall])
	print("[fish] speed at closest approach %.3f m/s" % worst_speed)
	# What is actually between the fish and the wall: the corals stand proud of it.
	var q := PhysicsRayQueryParameters3D.create(centre + outv * 3.0, centre - outv * 1.0)
	q.collision_mask = 1
	q.exclude = _fauna_rids()
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		print("[fish] concrete under the station at %.3f m out from the station centre"
			% (hit["position"] as Vector3).distance_to(centre))

# --------------------------------------------------------------------------- 4. rays
func _rays() -> void:
	print("\n=== 4. glider rays ===")
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var found: int = 0
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n.get("_band_y") == null or n.get("_span") == null or n.get("_roll") == null:
			continue
		found += 1
		var band: float = float(n.get("_band_y"))
		var span: float = float(n.get("_span"))
		var r: float = float(n.get("_r"))
		# What is over this orbit: sample the ring and take the LOWEST ceiling.
		var ceil_y: float = 1.0e9
		var ceil_at: float = 0.0
		for k in range(72):
			var a: float = float(k) * TAU / 72.0
			var p := Vector3(cos(a) * (r + 2.6), band, sin(a) * (r + 2.6))
			var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 40.0)
			q.collision_mask = 1
			q.exclude = _fauna_rids()
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				var y: float = float((hit["position"] as Vector3).y)
				if y < ceil_y:
					ceil_y = y
					ceil_at = rad_to_deg(a)
		print("[ray] band y %.2f  span %.1f m  orbit r %.1f  pos %s"
			% [band, span, r, str((n as Node3D).global_position.snappedf(0.01))])
		print("[ray]   lowest ceiling over the orbit ring (r+clamp %.1f): y %.2f at %.0f deg"
			% [r + 2.6, ceil_y, ceil_at])
		print("[ray]   current top of its depth wander = %.2f, headroom %.2f m"
			% [band + 3.0, ceil_y - (band + 3.0)])
	print("[ray] %d glider rays" % found)

# --------------------------------------------------------------------------- 5. grubs
func _grubs() -> void:
	print("\n=== 5. the wet-deck grubs ===")
	var spots: Array[Vector3] = [Vector3(24.5, 2.02, -17.5), Vector3(21.5, 2.02, -19.5),
		Vector3(26.5, 2.02, -13.0), Vector3(2.0, 0.97, -12.0), Vector3(-6.0, 0.97, -11.0)]
	for p in spots:
		var best: Node = null
		var bd: float = 1.0e9
		for n in get_tree().root.find_children("*", "Node3D", true, false):
			var d: float = (n as Node3D).global_position.distance_to(p)
			if d < bd and d < 1.0:
				bd = d
				best = n
		if best == null:
			print("[grub] %s : nothing within 1 m" % str(p))
			continue
		var meshes: Array = (best as Node3D).find_children("*", "MeshInstance3D", true, false)
		var vis: int = 0
		var box: AABB = AABB()
		var first: bool = true
		for m in meshes:
			var mi: MeshInstance3D = m
			if not mi.is_visible_in_tree():
				continue
			vis += 1
			var w: AABB = mi.global_transform * mi.get_aabb()
			box = w if first else box.merge(w)
			first = false
		var touch: int = 0
		for c in (best as Node3D).find_children("*", "StaticBody3D", true, false):
			touch += 1
		print("[grub] %s : node '%s' script=%s  d=%.3f" % [str(p), best.name,
			str(best.get_script().resource_path if best.get_script() else "none"), bd])
		print("[grub]     %d meshes, %d VISIBLE, visible AABB pos=%s size=%s, %d interaction bodies"
			% [meshes.size(), vis, str(box.position.snappedf(0.001)),
				str(box.size.snappedf(0.001)), touch])
		if best.get("_emerge") != null:
			print("[grub]     _emerge=%.3f  _body.visible=%s  phase=%s"
				% [float(best.get("_emerge")),
					str((best.get("_body") as Node3D).visible if best.get("_body") else "n/a"),
					str(GameClock.current_phase)])

## Does the tide worm actually COME OUT and MOVE at dawn, with the player standing off? That
## is the whole behaviour the generated mesh was bypassing.
func _grubs_at_dawn() -> void:
	print("\n=== 5b. the tide worms at DAWN, player 8 m off ===")
	var worm: Node3D = null
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n.get("_emerge") != null and n.get("_sink") != null:
			if (n as Node3D).global_position.distance_to(Vector3(24.5, 2.02, -17.5)) < 1.0:
				worm = n
				break
	if worm == null:
		print("[grub] no tide worm found")
		return
	if _player:
		_player.set_physics_process(false)
		_player.global_position = Vector3(24.5, 2.0, -9.5)   # 8 m north, on the wet deck
	GameClock.force_phase(GameClock.Phase.DAWN)
	var model: Node3D = worm.get("_model")
	var lo: float = 1.0e9
	var hi: float = -1.0e9
	for i in range(420):
		GameClock.force_phase(GameClock.Phase.DAWN)
		await get_tree().process_frame
		if model != null:
			var y: float = (_world_bounds(model)).position.y
			lo = minf(lo, y)
			hi = maxf(hi, y)
	print("[grub] after 420 dawn frames: _emerge=%.3f  _body.visible=%s  _rise=%.3f _sink=%.3f"
		% [float(worm.get("_emerge")), str((worm.get("_body") as Node3D).visible),
			float(worm.get("_rise")), float(worm.get("_sink"))])
	if model != null:
		var box: AABB = _world_bounds(model)
		print("[grub] worm mesh world AABB pos=%s size=%s  (deck plate top y 2.000)"
			% [str(box.position.snappedf(0.001)), str(box.size.snappedf(0.001))])
		print("[grub] the body's lowest point travelled y %.3f -> %.3f over the emergence"
			% [lo, hi])
	# ...and does it duck when you walk up to it?
	if _player:
		_player.global_position = Vector3(24.5, 2.0, -16.6)   # 0.9 m away
	for i in range(240):
		GameClock.force_phase(GameClock.Phase.DAWN)
		await get_tree().process_frame
	print("[grub] player 0.9 m away: _emerge=%.3f  _body.visible=%s"
		% [float(worm.get("_emerge")), str((worm.get("_body") as Node3D).visible)])

# ------------------------------------------------------------------------- helpers
func _generated(host: Node3D) -> Node3D:
	for i in range(host.get_child_count() - 1, -1, -1):
		var c: Node = host.get_child(i)
		if c is Node3D and not (c is MeshInstance3D) \
				and (c as Node3D).find_children("*", "MeshInstance3D", true, false).size() > 0:
			return c as Node3D
	return null

func _world_bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var w: AABB = mi.global_transform * mi.get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	return acc

## Every fauna collider in the world, as RIDs — FaunaTouch is a StaticBody3D on layer 1 and
## it will happily be measured as "the floor" (docs/AGENT_TRAPS.md).
func _fauna_rids() -> Array[RID]:
	var out: Array[RID] = []
	for n in get_tree().root.find_children("*", "CollisionObject3D", true, false):
		var host: Node = n
		var depth: int = 0
		while host != null and depth < 12:
			var s: Script = host.get_script()
			if s != null:
				var rp: String = String(s.resource_path)
				if rp.ends_with("bloom_fauna.gd") or rp.ends_with("leg_reef.gd") \
						or rp.ends_with("mussel_beds.gd") or rp.ends_with("reef_life.gd"):
					out.append((n as CollisionObject3D).get_rid())
					break
			host = host.get_parent()
			depth += 1
	return out
