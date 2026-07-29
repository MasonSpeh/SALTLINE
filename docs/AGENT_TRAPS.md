# Traps

Things that cost real hours in this repo. Each one is written down because it
was found the expensive way — by a wrong result that looked right, not by an
error message. Read this before starting work; add to it when something bites.

---

## Godot / engine

**A property name that doesn't exist fails SILENTLY.** `sun.directional_shadow_normal_bias`
was set for months and did nothing — the real property is `shadow_normal_bias`
(inherited from `Light3D`). Nothing warns. If a tuning change "doesn't seem to
land", boot headless and *read the property back off the live node* before
touching anything else.

**On `gl_compatibility`, several shadow settings are inert.** Measured, not
assumed: `Light3D.shadow_blur` at 0.0 vs 4.0 renders byte-identical frames.
Both `soft_shadow_filter_quality` keys change nothing for the *sun* — GLES3
shares one PCF specialisation between the directional and spot paths.
Omni shadows take a single hardware sample with no kernel at all. For the sun,
**resolution is the only lever that exists.**

**`SHADOW_PARALLEL_2_SPLITS` halves your atlas per cascade.** It does not give
each cascade the full map. This is what made shadows blocky for a long time.

**`_ready()` runs inside `add_child()`** — *before* the caller's next line. Any
spawner that does `add_child(x)` then `x.global_position = …` gives `_ready()`
a position of `(0,0,0)`. This shipped: all 8 crabs seeded their roam target to
the world origin and walked a straight line through the middle of the rig for
50 seconds every session.

**`point_solid()` / point queries lie inside CSG.** CSG collision is a trimesh,
and Godot's point query never sees the inside of a concave shape — it happily
reports "open water" 4 m inside a concrete casting. To test enclosure, **ray in
from known-open space** instead.

**NaN defeats every guard you have already written.** Every comparison against
NaN is false, so `if d < 0.0001` and `if v.length() < 0.5` both fall through. A
NaN then reaches `intersect_ray`, which normalizes internally and warns *with a
full GDScript backtrace*, every frame, per animal — one harness run wrote 4.4 GB
of stderr. Always `is_finite()` **before** testing length. And never return a
possibly-NaN value as a creature's new position: one bad frame becomes a
permanently lost animal.

**Rotating a zero-length vector returns zero.** `Vector3.ZERO.rotated(up, a)` is
still zero, so a stall-watchdog built on "turn and try again" can never free a
stuck agent.

**Opening the Godot *project manager* rewrites `project.godot`** — stripping
every comment and every default-valued key. It happens if you run `godot --path .`
from the wrong directory. This project's `project.godot` is heavily commented;
check `git diff` on it after any Godot invocation that might have missed.

---

## Harnesses and screenshots

**`--headless` never draws.** SubViewport read-backs hang forever. Screenshot
harnesses must run **windowed**.

**The pause menu auto-pauses on focus-out.** Another agent's window stealing
focus silently freezes the world mid-capture and pastes a PAUSED panel over
every frame. A paused world still *renders*, so you get beautiful, stable,
completely meaningless measurements. Force-unpause every frame in a harness.

**The camera's eye is ~1.6 m above `global_position`.** Aiming a shot from the
node origin photographs the floor, or a wall on the far side of the room.

**Drop the harness camera out of the `player` group** or the fauna will hunt the
lens — a crab "census" once photographed six crabs lined up chasing the camera.

**Frame-time measurement needs vsync off** (60 fps quantises every sample to
16.67 ms) and an interleaved A/B with a published null-pair noise floor. A first
pass once "measured" a 3.2 ms cost at a vantage where both sides had identical
triangle and draw counts — it was thermal drift.

---

## Generated assets (Tripo / Meshy)

**Tripo returns ~500,000 triangles per mesh.** The median whole *animal* in this
repo is 31k. A 20 cm coil of rope arrived costing 16× a shark. Anything placed
in bulk must be decimated (headless Blender, ~8k, UVs preserved) before it
ships. `render_budget.gd` exists because this rig was measured at 9.3 fps.

**A "FAILED" download is usually a succeeded task.** Tripo polling drops
connections constantly in this environment; the task keeps running server-side.
**Log every task id at submit time**, then recover with
`GET /v2/openapi/task/<id>` and pull `data.output.pbr_model` with curl. Do not
regenerate — that pays twice. This has saved credits repeatedly.

**Credit exhaustion is HTTP 403 with `code:2010` in the body**, not 402.
`raise_for_status()` throws the body away, so the batch classifier must fold it
into the message or it grinds every remaining species into the same wall.

**Generated meshes do NOT share a forward axis.** The old Meshy convention was
+Z (hence the blanket 180° yaw in `creature_anim.gd`), but the herring gull
arrived facing −Z and the hammerhead facing +X. **Measure it**: correlate travel
direction against the model's own local axes over a few hundred frames, then add
a `FACING_OVERRIDES` entry. A hammerhead shipped swimming broadside because
nobody checked (`+Z·travel = +0.99` when it should have been `+X`).

**Prompting lessons, in order of how much they moved the result:**
- Name the species binomial and frame it as *specimen / reference photography*.
  This anchors far harder than any number of adjectives.
- Give shape constraints as **numeric ratios plus a physical simile** ("twenty
  times longer than deep, like a belt"). "Long and thin" is a mood, not a
  constraint — six oarfish rolls came back as ordinary fish.
- Negate the toy look explicitly. Glassy / smooth / plastic is the *default*
  failure mode and returns unless named.
- Always add "no base, no plinth, no ground" — generators bed things on rocks.
- Describing an anatomical feature as a *modification to make* deforms the whole
  model; describe it as anatomy the animal already has. Asking for eyes "at the
  tip" repeatedly destroyed the hammer head; "as in every real hammerhead, the
  eye sits at the outboard end" worked.
- Items are viewed at 96 px — ask for one clear silhouette, not filigree.

---

## This project's own conventions

**`ANIM.replace()` hides every mesh built before it.** Overlay geometry (claws,
armour, eyes) must be added *after* the call or it is invisible dead code.
`ANIM.attach()` does not hide.

**Never hand-type a Y coordinate.** Authored constants drift from the real
geometry every time. Found this session: three gull perches floating exactly
+750 mm, a beacon 155 mm below its ceiling, a seal intersecting five colliders,
a crate 3 m under the deck. **Probe the surface at runtime.** `SurfaceCrawler`
and the `_snap_to_*` helpers exist for this.

**Rail colliders are not where the rail looks.** `rig_builder` draws the top bar
at y18.61 but fences the run with one slab topping at y19.225 — an honest
down-probe onto a rail lands 615 mm above the visible steel.

**Ladders: `face_dir()` is the ladder's local −Z**, and the controller latches at
`base + face_dir * 0.45`. A ladder built unrotated against a wall points that
into the building — the climb column measures 0.00 m against a 0.37 m capsule
(*mathematically* impassable) and the top exit drops the player off the roof.
Three ladders shipped with this. When you fix one, **audit all twelve**.

**Preload by path, not `class_name`** — the global class cache lags for new
files, and the failure surfaces as an unrelated "Could not resolve class X".
