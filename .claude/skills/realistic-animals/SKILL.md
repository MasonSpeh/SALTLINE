---
name: realistic-animals
description: Generate realistic, riggable/animatable 3D animal models with AI (Meshy / Tripo / local) and swap them into SALTLINE's Godot fauna scripts in place of the procedural primitive shapes. Use when the user wants a creature (crab, seal, gull, shark, eel, jelly, whale, or a new species) to look like a real animal instead of assembled balls/cylinders, or asks to "generate a 3D model", "make the fauna realistic", or "replace the basic shapes".
---

# Realistic animal models for SALTLINE

The fauna are currently assembled from primitives (`creature_kit.gd` balls/limbs/fins),
which reads as "floating ovals". This skill produces a **real, rigged, animated** animal
mesh and drops it into the existing creature so the AI/behavior stays and only the *look*
changes.

## The one idea that makes this cheap

Every SALTLINE creature already splits **visual** from **behavior**:

- `_build_body()` — assembles the look (this is the ONLY thing we replace).
- `_process(delta)` — patrol / pursue / retreat AI + movement (KEEP verbatim).
- `_animate(delta)` — poses the parts (we repoint this at an `AnimationPlayer`).
- The collider + `add_to_group("hittable")` + `repel()` (KEEP — combat/physics).

So the whole job is: get a rigged glTF, load it in `_build_body()`, and drive its
animation clips from `_animate()`. Nothing about spawning, movement, the lamp, combat,
or the day/night logic changes.

## Pipeline

```
reference (text prompt + optional image)
  → AI generation service  (mesh + PBR textures + auto-rig + walk/idle clips)
  → download GLB           → assets/models/fauna/<species>/<species>.glb
  → Godot import           (Skeleton3D + AnimationPlayer come through automatically)
  → swap into <species>.gd _build_body() + drive clips in _animate()
  → verify (headless import, then tests/StairShot-style screenshot)
```

## Step 1 — pick a generator

> **VERIFIED THE HARD WAY: Meshy's auto-rig is HUMANOID-ONLY.** Its `/v1/rigging`
> endpoint runs bipedal pose estimation and returns
> `422 "Pose estimation failed, please provide a valid model"` for a crab, ray, whale or
> eel — on both the preview and the refine task id. Do **not** plan on skeletal clips
> from it for a bestiary. Mixamo is humanoid-only too. Assume **mesh generation only**
> and animate on our side (Step 5) unless you have specifically confirmed otherwise.

| Tool | Text→3D | Image→3D | Auto-rig **animals** | Output | Notes |
|------|:---:|:---:|:---:|--------|-------|
| **Meshy AI** (meshy.ai) | ✓ | ✓ | ✗ humanoid only (confirmed 422) | GLB/FBX | Excellent meshes + PBR, solid API, free monthly credits. **Default for geometry.** |
| **Tripo3D** (tripo3d.ai) | ✓ | ✓ | partial — worth testing | GLB/FBX | Great quality; its rigger is also character-leaning. |
| **Rodin / Hyper3D** | ✓ | ✓ | ✗ | GLB | Highest-fidelity static meshes. |
| **Anything World** | ✓ | — | ✓ animal-specialised | GLB | The one built for animated animals; heavier setup, separate account. |
| **TripoSR / Hunyuan3D (local)** | — | ✓ | ✗ | OBJ/GLB | Free, offline; rig in Blender. See `references/local-fallback.md`. |

Recommendation for this project: **Meshy for the mesh**, then animate with the vertex
shader (Step 5). That combination is what shipped the whole bestiary — it looks alive,
costs no bones, and never fights the movement code. Only reach for Anything World or a
Blender rig when a species genuinely needs articulated limbs (a walking gait).

## Step 2 — set up the key (once)

I can't create the account or paste the key for you (that's yours to hold). Once you have
an API key from the chosen service:

```bash
# In the SALTLINE repo root:
printf 'MESHY_API_KEY=msy_xxx...\n' >> .env
grep -qxF '.env' .gitignore || printf '\n.env\n' >> .gitignore   # never commit the key
python3 -m pip install requests            # only dependency the script needs
```

## Step 3 — generate

`scripts/gen_animal.py` (bundled with this skill) drives text→3D→(rig+animate)→download.

```bash
python3 .claude/skills/realistic-animals/scripts/gen_animal.py \
  --name lamplight_crab \
  --prompt "a large deep-sea crab, mottled dark chitin, long jointed legs, raised pincer claws, a single bioluminescent lure on a stalk, photoreal, neutral pose, full body" \
  --animate walk idle \
  --out assets/models/fauna
```

It writes `assets/models/fauna/lamplight_crab/lamplight_crab.glb` (+ textures) and prints
the clip names it found. Re-run with `--image ref.png` to drive it from a reference photo
instead of text (much better likeness). See prompting tips in
`references/prompting.md`.

> If a rigging/animation endpoint has moved, the script says so and still leaves you the
> static mesh; finish rig+anim in the service's web UI and export the GLB to the same path.

## Step 4 — import in Godot

Copy/verify the GLB is under `assets/models/fauna/<species>/`, then let Godot import it:

```bash
godot --headless --path . --import      # generates the .import + .godot/imported scene
```

Open the imported scene once to confirm it has a **Skeleton3D** and an **AnimationPlayer**
with your clips (`walk`, `idle`, …). Import gotchas for animals:

- **Scale**: set the real size on import or normalise in code (SALTLINE uses the
  `PropLib` longest-axis trick). A crab is ~0.9 m across; a whale is ~10 m.
- **Materials**: keep imported PBR. If it renders black on the user's `gl_compatibility`
  Mac, it's usually a normal-map/ORM channel issue — re-save the material as a plain
  `StandardMaterial3D` (albedo+roughness), the same lesson as the texture pass.
- **Animation loop**: mark `walk`/`idle` clips as looping in the import dock (or set
  `.loop = true` in code).

## Step 5 — animate it (no skeleton needed) and swap it in

Since the services won't rig animals, the motion lives in a **vertex shader**:
`materials/creature_swim.gdshader` + `scripts/world/creature_anim.gd`.

```gdscript
const ANIM := preload("res://scripts/world/creature_anim.gd")   # preload: class cache lags
const MODEL_PATH := "res://assets/models/fauna/mantle_ray/mantle_ray.glb"
const GLOW := Color(0.25, 0.95, 0.88)
var _gen_mats: Array = []

# LAST line of the species' body build — hides the primitives it supersedes:
var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 6.0, ANIM.Mode.WING, 0.14, 0.45, GLOW)
if not gen.is_empty():
    _gen_mats = gen["mats"]
    ANIM.drive(_gen_mats, 0.45, 0.5)      # steady look: set once, shader runs off TIME
```

Modes: `UNDULATE` (fish/eel/shark body wave), `WING` (ray), `PULSE` (jelly bell),
`FLAP` (bird). Call `ANIM.drive(mats, rate, glow)` **per frame only** when the look should
react to state (the crab's hunt strobe, the shark's charge, the whale's night presence) —
otherwise set it once and pay nothing.

`replace()` returns `{}` when the asset is missing, which is the signal to build the
procedural body instead — a failed generation degrades to the old look, never a crash.

### Gotchas that cost time here
- **Preload by path**, not `class_name` — Godot's global class cache lags for new files.
- **Name your var uniquely** (`_gen_mats`): a collision with an existing `_mats` reports
  only `"same name as a previously declared variable"` with **no line number**, and
  surfaces as an unrelated `"Could not resolve class X"`. Load the script directly
  (`load("res://…gd")` in a scratch scene) to get the real message.
- Frame verification shots on the model's **combined AABB centre** — glTF pivots are
  rarely centred, so `look_at(Vector3.ZERO)` often misses the subject.

## Step 5b — the older swap notes (still valid for rigged models)

Edit the species script (start with `scripts/world/crab.gd`). Replace the body of
`_build_body()` and repoint `_animate()`. **Keep everything else.** Pattern:

```gdscript
const MODEL := preload("res://assets/models/fauna/lamplight_crab/lamplight_crab.glb")
var _anim: AnimationPlayer
var _lamp_mat: StandardMaterial3D    # if the species drives a glow, keep a handle

func _build_body() -> void:
    var model: Node3D = MODEL.instantiate()
    model.scale = Vector3.ONE * _fit_scale(model, 0.9)   # target ~0.9 m across
    add_child(model)
    _anim = model.find_child("AnimationPlayer", true, false)
    if _anim:
        for c in ["walk", "idle"]:
            if _anim.has_animation(c):
                _anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
        _anim.play("idle")
    # OPTIONAL: recover a material handle to keep the bioluminescent lure pulsing.
    # var lure := model.find_child("*lure*", true, false)   # name depends on the model

func _animate(delta: float) -> void:
    # Replace the primitive posing with clip selection driven by the SAME state machine.
    if _anim == null:
        return
    var moving := state == State.PATROL or state == State.PURSUE
    var want := "walk" if moving else "idle"
    if _anim.current_animation != want:
        _anim.play(want, 0.25)          # 0.25s crossfade
    _anim.speed_scale = clampf(_speed / patrol_speed, 0.6, 2.2) if moving else 1.0

# helper: normalise import scale to a target longest-axis size (metres)
func _fit_scale(node: Node3D, target_m: float) -> float:
    var aabb := node.get_child(0).get_aabb() if node.get_child_count() else AABB()
    var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
    return target_m / longest if longest > 0.001 else 1.0
```

Do NOT touch `_process`, `repel`, the collider, `add_to_group("hittable")`, `crab_spawn`,
or the state enum. The lamp light (`_lamp_light`) can stay as a separate `OmniLight3D`
child positioned at the model's lure bone if you want the gameplay tell to persist.

If the model has no usable rig (static mesh), still swap it in `_build_body()` and keep a
light procedural sway in `_animate()` (bob + yaw toward `_speed`) — better than balls, and
you can add a real rig later.

## Step 6 — verify

```bash
godot --headless res://tests/TestRunner.tscn          # compiles + world builds clean
```
Then screenshot it in place with a StairShot-style scene (fly cam to `rig.crab_spawn`,
force NIGHT, hold the pose) and Read the PNG — confirm it reads as the animal, sits on the
deck (not floating/half-sunk), and the clip plays. The user judges by screenshot; always
look before claiming it's done.

## SALTLINE fauna, in priority order

The crab is the money shot (it's the night's face and the "floating ovals" the user
called out) — do it first. Then, by screen time: **seal** (day patrol, befriendable),
**gull/corvid** (perched + flying), **shark** (hammerhead), **eel**, **jelly**, **whale**.
Each is a `scripts/world/*.gd` (see `bloom_fauna.gd` for the small ones) with the same
`_build_body`/`_animate`/behavior split — the swap recipe is identical.

## Files in this skill
- `scripts/gen_animal.py` — text/image → 3D → rig+animate → GLB downloader (Meshy; Tripo notes inline).
- `references/prompting.md` — how to prompt for a realistic, game-ready animal in a neutral pose.
- `references/godot-fauna-integration.md` — deeper Godot import + per-species swap notes.
- `references/local-fallback.md` — offline generation on an Apple-Silicon Mac (TripoSR), rig in Blender.
