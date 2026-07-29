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

**Unpausing does not remove the PAUSED panel.** `get_tree().paused = false`
resumes the world; the dialog is `PauseMenu.panel`, on its own CanvasLayer, and
it stays drawn. A harness that only unpauses loses every frame taken after the
moment focus went elsewhere — s20 lost the last eight frames of a render pass
that way, cleanly and silently. Hide the panel too, every frame (see
`reef_shot.gd::_find_pause`).

**A harness whose script fails to parse hangs a windowed Godot for ever.** The
scene root comes back with its script dropped (see the GDScript note below), so
`_ready()` never runs, nothing calls `quit()`, and the window just sits there
until something kills it — ten minutes of wall clock for a one-line type error.
Parse-check before every windowed launch. `--check-only --script <path>` is the
cheap gate, but read its output carefully: it does not set up autoloads or fully
build the global class cache, so "Identifier not found: GameClock / PowerGrid" is
a false positive from the checker, not a real error.

**The camera's eye is ~1.6 m above `global_position`.** Aiming a shot from the
node origin photographs the floor, or a wall on the far side of the room.

**Drop the harness camera out of the `player` group** or the fauna will hunt the
lens — a crab "census" once photographed six crabs lined up chasing the camera.

**Frame-time measurement needs vsync off** (60 fps quantises every sample to
16.67 ms) and an interleaved A/B with a published null-pair noise floor. A first
pass once "measured" a 3.2 ms cost at a vantage where both sides had identical
triangle and draw counts — it was thermal drift.

**Every creature carries a solid 0.6–0.85 m sphere, and it will corrupt your
measurements.** `FaunaTouch` is an `Interactable`, i.e. a `StaticBody3D` on the
default collision layer — that is how the player's interaction ray finds an
animal. So the instant fauna is placed on a surface a harness raycasts *against*,
that harness starts measuring animals. Found in s20 the moment snails went onto
the caisson faces: `ReefProbe` reported the caisson had moved **606 mm** off its
own centre line, and **19** perfectly seated corals as **buried by up to 926 mm**.
Both numbers were stable, plausible and pure fiction. Any probe aimed at world
geometry must build a skip list and pass it as `q.exclude`
(`BloomFauna.fauna_bodies`, or collect by script file — the helper walks up to a
`bloom_fauna.gd` host and so misses fauna parented anywhere else).

---

## Generated assets (Tripo / Meshy)

**Tripo returns ~500,000 triangles per mesh.** The median whole *animal* in this
repo is 31k. A 20 cm coil of rope arrived costing 16× a shark. Anything placed
in bulk must be decimated (headless Blender, ~8k, UVs preserved) before it
ships. `render_budget.gd` exists because this rig was measured at 9.3 fps.

**The decimation floor is set by SURFACE TYPE, not by how big the piece is.**
Anything whose detail is a dense field of small bumps — brain coral, bubble
coral, a barnacle crust — collapses into loose flat facets below about 4k and
reads as a pile of broken glass. A branching or fan silhouette survives 5–6k
untouched, and a flat starfish is fine at 2k. s20 cut the whole reef one notch
leaner to pay for twice the instances, rendered it, and had to put brain, bubble
and the barnacle crust straight back up. **Judge the render at the ratio you
intend to ship**, not the raw mesh — `tests/CandShot.tscn` photographs whatever
GLB you point it at, so this costs one Blender pass and one look.

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

**A new `class_name` that matches an existing INNER class breaks the whole
project.** `bloom_fauna.gd` has held `class ReefFish` for months; a new
`scripts/world/reef_fish.gd` declaring `class_name ReefFish` produced
`Parse Error: Class "ReefFish" hides a global script class` *at bloom_fauna.gd*,
which failed every script that depends on it — i.e. every world script, i.e. every
harness in the repo, for whoever else was working at the time. Grep the inner
class names before choosing a global one. (And note the cache is sticky: after the
`class_name` is removed the stale entry survives in
`.godot/global_script_class_cache.cfg` until Godot rescans.)

**Emission below the environment's glow threshold produces no bloom at all.**
`main.gd` runs `glow_enabled` with `glow_hdr_threshold = 0.8`, so a material only
reaches the glow buffer once its lit pixel clears 0.8. The reef shipped s19 at
`emission_energy_multiplier = 0.15` keyed off its albedo map, which is nowhere
near — it was a slightly brighter texture and *nothing* was blooming. The window
above that is narrow, too: MultiMesh per-instance colour multiplies **albedo, not
emission**, so past ~0.7 the emission swamps every tint and the whole reef renders
featureless white (measured — 1.35 photographed as a white smear). Sweep it off
one world build rather than guessing: `ReefShot.tscn --glow=a,b,c` re-exposes the
same frame at each value.

**A snail on a vertical face will not climb if its heading is chosen in world XZ.**
`SurfaceCrawler` projects the heading into the face it is stuck to, so a direction
picked as `(cos a, 0, sin a)` on a caisson wall projects to *pure sideways* — the
animal sidles back and forth for ever and never goes up or down. `PyramidSnail`
re-picks exactly that way every 16–42 s. Pick in the FACE plane (world up,
projected into the face, crossed with the normal), and set `climb_base` to the
spawn Y or `CLIMB_MAX`'s "six metres above the foothold" is measured from y = 0.

**MultiMesh instance data is invisible under `--headless`.** The transforms and
colours live in the RenderingServer, and the dummy renderer drops every write and
returns **identity** to every read. A headless probe therefore measures every
instance sitting on the world origin and reports a confident "0 floating, 0
buried" — a vacuous pass that looks exactly like a real one. Verified both ways
in one sitting: windowed reads back the real transform, headless reads identity,
same code. **Any harness that reads `get_instance_transform` must run windowed**,
and should assert that it re-measured a plausible *number* of instances, not just
that it found no failures.

**Blender's glTF importer converts Y-up to Z-up.** Anything you measure or
transform inside a headless Blender script is in Blender's frame:
`blender = (gltf.x, −gltf.z, gltf.y)`. A decimation pass that normalised "up"
using Blender's Y silently normalised glTF's −Z instead — every mesh exported
with its base pushed sideways and its rotation not applied, and the numbers it
printed looked reasonable. Name the axis indices in one place and convert.

**`bpy.ops.object.transform_apply` is a no-op if the context is not what it
expects.** After `modifier_apply`, a rotation set on the object and "applied"
this way did nothing and reported no error. `ob.data.transform(Matrix…)` writes
the mesh directly and takes no context — prefer it in headless scripts.

**A GDScript parse error hands `PackedScene.instantiate()` back a bare node.**
It does not return null. The root arrives with its script dropped, builds
nothing, and every probe that walks it passes vacuously on an empty tree — and
`TestRunner` reports `FAILURES: 0`. Check `get_script() != null` on the
instantiated root before trusting anything a harness says about the world. This
matters most when another session is mid-edit in a file yours does not touch.

**Frame-skipping a creature SLOWS IT DOWN.** Godot hands `_process` the time
since the last FRAME, not the time since that node last ran. So the obvious way
to make distant animals cheaper — `process_mode`, or an early `return` every Nth
frame — runs them at 1/N speed: a shark patrols at a quarter pace, a crab's night
emergence takes four times as long, a snail crawls. Nothing errors and no
screenshot shows it. Every decimated creature must accumulate its own delta and
act on the SUM (`scripts/world/ai_budget.gd`). The invariant to test is
**d(own clock)/d(wall clock) == 1.00**, not "the frame got cheaper".

**`lerpf(x, target, delta * k)` is not frame-rate independent** and it breaks
down at long steps: past `delta * k > 1` it overshoots the target, past 2 it
oscillates away from it. That is the ceiling on how far any decimation scheme can
go — hence `AiBudget.MAX_STEP`. `1 - exp(-k * delta)` has neither problem and is
what the fish shoals already used, which is why they took decimation for free.

**`wave_offset()` returns a `Vector3`, whose components are single-precision.**
Reading `.y` off it silently rounds a double to float32. Anything that reads a
height through a Vector3 is ~1e-7 less accurate than the sum that produced it —
which is fine for a wave and is NOT fine as a claim of "identical output". If two
functions are supposed to agree exactly, assert it; if they cannot, bound the
disagreement and say which one is right.

**A profiling harness that takes an hour gets killed before it prints.**
`tps_profile.gd` grouped its per-species drill by a label that falls back to the
node's autogenerated name, so the 48 scriptless fish-pod roots each became their
own A/B/A job: 341 measurements, ~50 minutes, and the run was terminated at 52
minutes having produced exactly one useful line. Group by KIND. Budget a harness
by multiplying jobs x windows x frames x frame time before you start it.

---

## Found while adding the tropical reef fish (s20)

**A harness that un-pauses in `_process` must ALSO set `process_mode = PROCESS_MODE_ALWAYS`.**
The existing rule above ("force-unpause every frame") is necessary and not sufficient: a
node inherits `PROCESS_MODE_PAUSABLE`, so the instant the pause menu auto-pauses on
focus-out the harness stops processing and can never un-pause itself again — while
`create_timer` keeps firing, because it ignores pause by default. The shot list therefore
runs to completion over a frozen world. This is worse than the PAUSED panel it is trying to
avoid, because `underwater_fx` also stops updating its depth grade: a whole 16-frame pass
came back with pale, un-fogged, *plausible-looking* water and every fish stopped mid-stroke.
Also: the pause PANEL is its own `CanvasLayer` (layer 15), not part of the HUD, so hiding
`main.hud` does not hide it. `tests/reef_shot.gd` still has both of these.

**Declaring a `class_name` on a brand-new file breaks the import that is creating its cache
entry.** `class_name ReefFish` on a new script produced `Parse Error: Class "ReefFish" hides
a global script class` during `--import`, which cascaded into "Failed to compile depended
scripts" on unrelated autoloads. The cache entry it was colliding with was its own,
half-written. It cleared on the next import, but the first run is exactly when a new file is
least trusted, so the cheap answer is: if nothing needs the global name (preload by path
instead — already the rule here), don't declare one.

**Correct scale is not visible scale, and a shot list that reports only its INTENDED camera
position cannot tell you it missed.** Ten reef fish were built at real field-guide lengths
(13 cm anthias, 12 cm damsel) and photographed at the natural portrait distance. Every frame
came back as empty coral. Nothing was wrong: the player's view is ~107 degrees across, so a
13 cm fish at 7 m is SEVEN PIXELS. Two habits came out of it. Print the camera position the
harness actually ended up at next to the one it asked for and the distance to the subject —
that is what proved the framing was right and the subject was tiny. And derive shot vantages
from the live objects (`census()` off the running system) rather than hand-typing them: with
55 stations spread over 16 caisson faces, a guessed vantage is far likelier to photograph
bare wall than a shoal.

**Occlusion has to be scored, not hoped for.** The shallow band on the legs sits INSIDE
underwater_world's kelp stand — 11 strands a leg on a 3.2-6.0 m holdfast ring, against a
caisson face at 3.0 m, so the innermost strands are 200 mm off the concrete. Four species'
portraits came back as nothing but green blade. Scoring each candidate station on how many
strands fall near the sight line (and counting a strand within 1.6 m of the LENS double — a
frond that close fills the frame while being nowhere near the line) fixed it. A strand at the
camera is an occluder even though it is not "between" anything.
