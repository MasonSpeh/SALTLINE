# Godot import + per-species swap (SALTLINE)

## Import settings for an animated GLB

Drop the GLB at `assets/models/fauna/<species>/<species>.glb` and run
`godot --headless --path . --import`. Then in the Import dock (or the `.import` file):

- **Meshes → Ensure Tangents**: on (needed for normal maps).
- **Animation → Import**: on. Confirm an `AnimationPlayer` appears with your clips.
- **Loop**: set `walk`/`idle`/`swim` clips to *Loop* (or set `loop_mode` in code).
- **Skins**: leave default (glTF skin → `Skeleton3D`).
- If the mesh imports huge/tiny, either set the root scale here or normalise in code with
  the `_fit_scale` helper (SALTLINE convention: target a real-world longest-axis size).

`gl_compatibility` gotcha: if the imported material renders black on the user's Mac (it
renders fine elsewhere), rebuild it as a plain `StandardMaterial3D` with just
albedo + roughness (+ AO), same fix as the texture pass. Some ORM/normal packings don't
survive the ANGLE/Metal path.

## The swap, per current species

Each is a `Node3D` subclass with `_build_body()` (visual — REPLACE) and `_process()` /
species helpers (behavior — KEEP). Handles you must preserve:

| Species | script | keep-alive | animation states → clips |
|---------|--------|-----------|--------------------------|
| Lamplight crab | `crab.gd` | `_lamp_light` (OmniLight), `repel()`, `"hittable"` group, `State` enum, collider | PATROL/PURSUE→`walk`, IDLE/RETREAT→`idle` |
| Harbor seal | `bloom_fauna.gd` (HarborSeal) | patrol path, haul-out pos | swimming→`swim`, hauled→`rest`/`idle` |
| Hammerhead | `shark.gd` | patrol ellipse, notice/charge logic, bite | always→`swim`, speed_scale on charge |
| Gull / Corvid | `bloom_fauna.gd` | perch idx, heist logic (corvid) | perched→`idle`, flying→`fly` |
| Lamp eel / Jelly / Whale | `bloom_fauna.gd` | glow shader, path | motion→`swim`, else→`idle` |

General rules:

1. **Only edit `_build_body()` and `_animate()`.** Leave `_process`, movement, combat,
   spawn, and day/night alone. The model is a child `Node3D`; the parent still moves.
2. **Face the model the right way.** glTF forward is usually +Z or -Z; SALTLINE faces a
   creature with `rotation.y = atan2(-dir.x, -dir.z)`. If the model faces backward, add a
   fixed `model.rotation.y = PI` (or 0) once in `_build_body()` — don't fight the movement
   code.
3. **Keep gameplay tells.** The crab's lamp is a *mechanic* (it repels via the light). Keep
   `_lamp_light` as a child positioned at the model's lure bone: after load, find the bone
   (`skeleton.find_bone("lure")`) or just parent the light at a fixed local offset that
   matches the model's lure.
4. **Collider stays a simple capsule/box** sized to the model — don't use the mesh as a
   collider (perf + tunnelling). The existing creatures already own their collider; keep it.
5. **Animation speed** should track movement: `_anim.speed_scale = clampf(_speed / base, …)`
   so a fast pursuit doesn't moonwalk.

## If there's no rig yet (static mesh)

Still swap the mesh into `_build_body()` — a real static crab beats primitives. In
`_animate()` keep a light procedural motion: a small vertical bob and a gentle lean/yaw
toward `_speed`, plus (for legged animals) nothing fancy. Add the real rig later and only
`_animate()` changes.

## Verify

1. `godot --headless res://tests/TestRunner.tscn` → FAILURES: 0 (compiles, world builds).
2. A StairShot-style screenshot scene: fly cam to `rig.crab_spawn`, `GameClock.force_phase(NIGHT)`,
   set the creature's state to PURSUE with speed 0 to hold the pose, save PNG, Read it.
   Confirm: reads as the animal, feet on the deck (not floating/sunk), clip visibly playing,
   scale sane next to the ~1.8 m player.
