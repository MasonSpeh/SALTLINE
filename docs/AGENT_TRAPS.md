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

**A windowed Godot launched into the BACKGROUND on macOS reports frozen renderer
counters.** Not zero — frozen at their first-frame values, which is far worse.
An s21 `VantagePerf` run backgrounded from a shell came back with *identical*
draw calls (3449) and primitives (4,560,633) at all six vantages and a constant
6.90 ms frame delta, i.e. a 4x speedup over the same build measured in the
foreground. Everything about it looked like a clean result except that six
different camera positions cannot cost the same to the digit. **Run measurement
harnesses in the foreground**, and print the camera position each vantage
actually reached so a camera that never moved is visible in the log.

**A perf vantage 40 cm off is a different frame, not a slightly different one.**
`VantagePerf`'s `wet_deck` sits at eye y 4.0; the Wet Deck floor is y 2.0 and the
player's eye is 1.6 m up, so a standing eye is 3.6 — and
`underwater_world.TOPSIDE_MARGIN` is 4.0. The vantage was therefore on the hidden
side of the topside cull and the player on the visible side: 2709 draws / 2.15 M
prims / 25.0 ms against 2861 / 3.42 M / 30.6 ms. An optimisation worth 3.86 ms
where the player stands measured as **zero** at the vantage named after that deck.
Derive vantages from the geometry (floor height + eye height), not by eye.

**Do not freeze a world with `Engine.time_scale = 0` to get a still frame for a
pixel diff.** A zero delta divides by zero in the fauna movement code and
produces the NaN that defeats every guard in this repo — the run filled stderr
with "Vector3 cannot be normalized" at frame rate and wrote **5.4 GB** before it
was killed. (Cap harness output with `head -c` while you are at it.) Freeze a
world by removing its motion, never by stopping its clock.

**A frame-difference test must give both comparisons the SAME temporal gap.** The
first version of s21's cull proof captured its null pair one frame apart and its
test pair five, so it was comparing five frames of swell against one: every row
read "visible" by a constant ~4x, at every height, for every target, independent
of the thing being varied. The reverse mistake is just as easy — with *equal* six
frame gaps the sea's own motion (mean 3/255, 1400-3700 pixels over threshold)
swamps the signal and every row reads "invisible". This ocean cannot be stilled
(`amp_scale` bottoms out at 0.18, not 0), so the working answer was a per-pixel
**motion mask**: three captures one frame apart with the target shown in the
first and last, count only pixels the middle frame changed a lot AND the mask
says were steady, then run the identical statistic with nothing toggled to get
the null. That resolves 6 pixels against 17 out of ~102k sampled.

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
- **Name a small, EXACT number of parts, and budget triangles per part.** Four mussel-bed
  candidates were lost asking for "about thirty mussels": thirty closed shells at 4,200 tris is
  ~140 a shell, and a shell needs a few hundred to survive the collapse, so every one came back
  as broken glass. "EXACTLY NINE large adult mussels" held at the same budget. Divide the
  shipping budget by the part count *before* writing the prompt.
- **A patch-shaped ratio has to be attached to the parts' POSE, not to the patch.** "A mat ten
  times wider than it is deep" produced pieces measuring 1.03/1.01/1.03 and 0.97/0.97/0.99 on
  their three axes — balls. Describing the individual shells as "all lying down flat on their
  SIDES in a single overlapping layer, one shell thick" produced 0.92/**0.18**/1.00. The
  decimator prints these extents; a near-cubic set is the ball signature and needs no render to
  reject.

---

## This project's own conventions

**`rig_batcher.gd` WELDS the dressing into `MergedDressing`, so no per-node walk can find a
dressing prop by its material.** Every `_dbox`/`_dcyl` in `wet_deck_detail.gd` and friends is
gone from the tree by the time a probe runs: what is left is a handful of `ArrayMesh` chunks
under `Main/.../MergedDressing`, each carrying ONE shared material with `albedo_color = ffffff`
and a texture. An owner-reported "blank yellow block on the spawndeck" was hunted twice by
walking `VisualInstance3D` and filtering on `albedo_color`, found two unrelated flat-yellow CSG
bollards, and "fixed" those — while the actual culprit, 3 m of flat-yellow tube in
`_boat_landing()`, was invisible to that search *twice over*: welded into a merged chunk, and
its yellow living in a material the walk never reached. **Search from the PICTURE, not the
tree**: stand where the player stands, read the rendered pixels, cluster the ones that are
actually the colour complained about, and shoot the camera's own ray through each cluster
(`tests/SpawnYellow.tscn`). Two further gotchas that cost a run each: F9's `is_in_group("player")`
test only looks at the node itself, so the player's flashlight — a `SpotLight3D` under
`Head/Camera3D` with a 23 x 25 x 24 m AABB — swallows every ray and "identifies" everything;
and an AABB ray test is coarse enough that the answer is often the *second* hit, so return
several.

**Flat fills of `Color(0.75, 0.65, 0.15)` are `hazard_stripe()`'s fallback tint, written by
hand where the material was meant.** Found in two independent places (`rig_builder`'s gangplank
bollards, `wet_deck_detail`'s fender posts), both reported by the owner as blank yellow blocks.
If you see that literal, or any of the `Color(0.7-0.85, 0.6-0.75, 0.1-0.2)` family, the author
wanted `MatLib.hazard_stripe()` and it never got called. `MatLib.flat()` is for LIT LENSES and
small emissive parts; a flat fill on anything a metre across reads as un-authored.

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

**`Performance.TIME_PROCESS` and `TIME_PHYSICS_PROCESS` are not per-frame numbers.** Godot
refreshes them ONCE PER SECOND and stores the MAXIMUM over that second. Sampled per frame they
take one or two values inside a 51-frame window and both of them are spikes, so any median,
A/B/A or before/after built on them is measuring the worst frame of the last second. They are
the obvious monitor for "what does the script step cost" and they are the wrong one. The tell
in s23 was a "script step" of **33.26 ms inside a 29.23 ms frame**, a null-pair floor of
**8.98 ms**, and a species measured at **-219%** — but `vantage_perf` had been quietly printing
the same monitor in its `script ms` column for three sessions, where it read 698 ms next to a
22 ms frame and nobody looked. What works instead is bracketing: two nodes, one forced to be
root's FIRST child and one its LAST, each reading `Time.get_ticks_usec()`. Processing is
depth-first in tree order, so their difference is the whole idle pass at microsecond
resolution, every frame. Both harnesses now carry that pair (`tps_profile.gd::Bracket`).

**The frame delta cannot see one species, and at `wet_deck_stand` it cannot see much at all.**
The delta on this machine is quantised at ~0.2 ms, and the interleaved NULL PAIRS — jobs that
toggle nothing — came back at **1.09, 1.39, 2.54 ms** at that vantage across three s23 runs,
with the on-window drifting 29.9 -> 36.1 ms inside two minutes of the same run. bloom_fauna's
whole per-frame GDScript is ~1.3 ms of script time spread over twenty species: the quantity
sits an order of magnitude under the floor of the instrument. A first pass ranked six rows as
"beating" the floor and three of them were animals **85-104 m away**. The same trap wearing a
different hat as the s19 thermal-drift one, and the same defence: publish the null pair, and
never trust a row until it has been measured twice in one session with something else in
between. s23's shadow row read **-4.28 ms** in one run and **0.00 / +0.83 ms** in the next.

**`set_process(false)` is the right toggle for per-node attribution; `process_mode` is not.**
`process_mode = DISABLED` propagates to the whole subtree, so a species with scripted children
(`GlowWormColony` over its `GlowWorm`s, `leg_reef` over its snails) is charged for its children
and the children's own rows double-count the same milliseconds. `set_process` /
`set_physics_process` stop exactly that node's callbacks, which is what makes a per-species
table additive.

**An inner class has an EMPTY `resource_path`, so grouping by it merges every species into one
bucket.** `tps_profile`'s per-species drill grouped on `get_script().resource_path` and the
twenty-odd inner classes of `bloom_fauna.gd` all fell into the `"(no script) Node3D"` bucket
together — i.e. it measured "all of bloom_fauna" a second time and printed it as a breakdown.
The script OBJECT is a perfect grouping key (one `GDScript` instance per inner class, shared by
every instance) and a useless label. The readable name is in the HOST script's
`get_script_constant_map()`, where `class Gull` is registered under `"Gull"`.

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

**A vantage derived from a live object still has to be HELD.** `reef_shot`'s `_place` sets the
player's transform once and then awaits a settle timer, and the controller keeps integrating
across the wait — buoyancy, the fly drift — so three of s21's frames were taken from up to
**3 m** away from where they were aimed, one of them a 1.5 m close-up photographed from 4.2 m.
Nothing looked wrong; the frames were plausible pictures of coral. The only reason it was
caught is the s20 habit of printing the position the camera ACTUALLY ended up at next to the
one it asked for. Re-assert the pose every frame of the settle, not once at the start.

**Occlusion has to be scored, not hoped for.** The shallow band on the legs sits INSIDE
underwater_world's kelp stand — 11 strands a leg on a 3.2-6.0 m holdfast ring, against a
caisson face at 3.0 m, so the innermost strands are 200 mm off the concrete. Four species'
portraits came back as nothing but green blade. Scoring each candidate station on how many
strands fall near the sight line (and counting a strand within 1.6 m of the LENS double — a
frond that close fills the frame while being nowhere near the line) fixed it. A strand at the
camera is an occluder even though it is not "between" anything.

---

## Found while installing the owner-picked fishing tools (s22)

**A `const` Dictionary is READ-ONLY in GDScript, and a harness that sweeps a const table
cannot exist.** `ICON_FOCUS` and `HAND_TOOL_POSE` are both `const {}`; assigning into a local
`var t: Dictionary = D` writes through to the same read-only dictionary and raises
*"Invalid assignment on read-only value"* — a RUNTIME error that aborts the enclosing
function. In a windowed harness that means `_ready()` never reaches `quit()` and Godot **hangs
for ever** with no error visible if the output is piped through a buffering `grep`. Two lessons:
`Dictionary.is_read_only()` is the cheap check, and a sweep over a shipping const table has to
re-implement the few lines that read it and then PROVE the copy equivalent (`tool_final.gd`
renders the installed entry through both paths and diffs the images — 0.0000).

**`GameClock.force_phase()` does not hold the light still, it resets the phase clock.** It sets
`_phase_elapsed_sec = 0.0`, and `SunController` maps DAY f=0 to 16° of elevation — a low warm
sun. Calling it every frame to "keep it daytime" therefore PINS the sun at the reddest end of
day: a whole render pass came back with pink deck plate and salmon girders and the cause looked
like a damage vignette. DAY runs 34 minutes, so nothing in a four-minute harness can leave it:
force it ONCE and then write `_phase_elapsed_sec` to the fraction of DAY you want.

**A roll nobody wrote, from six stacked Euler angles.** The owner reported the held rod
"oriented on side" twice. There was no roll term anywhere: `_hand_item` carries two mount
angles, the container carried three more, and `item_visual.gd`'s own pivot carries a Z lean —
the reel ended up (+0.85 right, +0.20 up) off the blank as the PRODUCT of all six. Nudging any
one of them moves the picture without fixing the cause, and the cause comes back the moment
anyone touches another stage. **State the pose as a target and solve for it**: name the model's
long axis and the axis its reel/drum stands off, name where each must point in CAMERA space,
build the basis from two orthonormal frames, and divide the earlier stages back out
(`_apply_hand_pose`: `B_container = B_hand.inverse() * aim * B_pivot.inverse()`).
Corollary worth knowing before promising an orientation: **the model's handedness can make a
request impossible.** With blank +Y, reel-offset +X and crank +Z, asking for reel-up AND
crank-right AND tip-away needs a basis of determinant −1. One of the three has to give.

**An AABB you are standing INSIDE is the nearest hit for every pixel on screen.** The wet deck's
dressing welds into `MergedDressing` chunks up to 13.65 m across and the player is inside one:
`AABB.intersects_ray` then returns the ray origin, distance 0.00 m, so the first crate hunt
"identified" the same chunk at every yaw, at every pitch, for every blob. `if box.has_point(origin): continue`
is the whole fix. The other half of the same lesson: an AABB ray test is a poor question for a
small prop inside a big loose box, so `spawn_yellow.gd` now also asks the exact one — project
every small node's own AABB corners with `unproject_position` and keep the ones whose SCREEN
rectangle contains the pixel. (That needs the real viewport: headless reports
`get_visible_rect()` as 1280x1280 for a 1280x720 project, so the pixel mapping is wrong there.)

**A probe coroutine that awaits must be awaited.** `_check_tool()` called an `await`-ing helper
without `await`, so the helper was still running when the caller moved on and rebuilt the hand:
*"Invalid access to property 'global_transform' on a previously freed object"*, printed between
two PASS lines, with `FAILURES: 0` at the end. Half the assertions never ran.

## Found while fixing the winch's hold and rebuilding the bench (s23)

**`_hand_posed_cast` CANNOT be set by hand and left.** `player_controller._sync_hand_pose()`
runs every PHYSICS frame and rewrites the flag from `fishing != null`, so a harness that sets
it, awaits anything, and then measures is photographing the IDLE pose. The first run of
`tests/WinchPoseShot.tscn` did exactly this and printed idle and cast axes that agreed **to the
digit** — which is also precisely what a genuinely broken cast pose looks like, so the evidence
was indistinguishable from the bug it was looking for. Drive the pose the way the game does
(hand the controller a live `fishing` node), or read the transform in the same frame you write
it without awaiting. `tests/rod_hand_probe.gd` now does the latter.

**Aiming the wrong axis constrains nothing, and it looks like it works.** The winch's
`HAND_TOOL_POSE` entry named `face` as the drum's AXLE (+Z, the crank side) rather than the
direction the drum stands off the mast. The solve then satisfied the axle exactly while leaving
*which side of the tool the drum is on* completely free — and it landed left, which is the thing
the owner reported three times. If a complaint is about WHERE a part sits, the aimed axis has to
be the one that moves it.

**A model's handedness can make an owner request impossible, and the answer is to mirror the
MODEL, not to keep re-aiming it.** With the mast on +Y and the drum bracket on -X, the crank
(+Z) is fixed by the right-hand rule: mast-up + drum-right forces the crank to point away from
the camera. s22 recorded this as "one of the three has to give" and gave up the side. s23 gave
up the handedness instead (`item_visual._mirror_x`). Two things matter when you do it: mirror in
the axis that keeps the ICON readable (item_icons' camera looks in along +X+Y+Z, so an X-mirror
turns the drum toward it while a Z-mirror would hide the crank), and do NOT use `scale.x = -1` —
a negative-determinant transform inverts triangle winding and back-face culling renders the model
inside out. `M·T1·T2·…·Tn == (M·T1·M)(M·T2·M)…(M·Tn·M)·M`, so negating each node's local x-offset
and its Y and Z Euler terms is an exact reflection with determinant +1 at every level, and the
trailing reflection lands on the leaf mesh where every primitive in `item_visual.gd` is already
x-symmetric.

**`queue_free()` is DEFERRED, so code that re-measures the tree it just freed into still sees the
freed nodes.** `bench_panel._update_part_visuals()` freed the old laid parts and then measured
the bench's AABB to find the top to put the new ones on — with the old parts, standing ON that
top, still children. The "bench surface" climbed 0.45 → 1.468 over one panel session and the
parts climbed with it, ending a metre above the plank. `remove_child()` first, and pass the live
list as a skip set to whatever does the measuring.

**A box has no vertices in the middle of its face.** The first cut of the bench's welded-top
probe asked whether any vertex of the merged dressing fell INSIDE the bench's footprint and found
nothing at all: the work top is 1.7 x 0.8 over a 1.6 x 0.7 carcass, so all eight of its corners
are 50 mm outside and every one was rejected. A containment test against vertices only works when
the thing you are looking for is smaller than the window. Give the footprint a margin (and keep
the height window tight so a neighbouring crate cannot answer instead).

**`Object.get()` does not resolve script CONSTANTS.** `node.get("HAND_TOOL_POSE")` comes back
null, and a probe with a `.get(name, default)` fallback then asserts against the DEFAULT while
printing PASS. Reach a `const` through a `preload()`ed script reference instead.

## Found while adding the harvestable mussels (s21)

**The FaunaTouch trap bites PLACEMENT code too, not just probes.** The s20 entry above is
about a *harness* measuring animals. s21 found the other half: `mussel_beds` seated one bed and
all three of its patches on a passing snail's touch sphere, because leg_reef seeds thirteen
snails onto the caisson faces in exactly the depth band the beds want. The animal then crawled
away, so the probe reported "no collider under it" — and the tell was three patch up-axes of
(0.32, 0.16, −0.93), (0.37, 0.39, −0.84) and (−0.05, −0.26, −0.96) on a caisson face whose
real normal is (0, 0, −1). **Any code that seats something by raycast needs the skip list, not
just the code that checks it afterwards.** And behind the skip list, assert the shape you
expect: a caisson normal is axis-aligned, so `n.dot(expected) >= 0.985` refuses anything the
skip list missed (an animal spawned after the list was built).

**Anything measured in game DAYS cannot be a countdown in seconds.** Sleeping calls
`GameClock.skip_to_next_dawn()`, which bumps `day_count` and resets the phase — the calendar
advances and *no real time passes*. So a five-day regrowth counted in `delta` sits bare through
five slept nights and then completes after five real hours of standing next to it, which is
both wrong and untestable. `GameClock.game_time_hours()` exists for this: absolute game hours,
monotonic across a natural phase advance *and* a sleep. `Salvage.regrow_game_hours` keys off it.

**A test helper that SETS a clock position cannot be called twice.** `MusselProbe`'s
`_advance_game_days` first wrote the intra-day position rather than adding to it, so `(4.5)`
followed by `(0.6)` advanced 4.5 days and then **0.1** — and the probe reported that a five-day
bed had not regrown after five days. The failure was indistinguishable from a bug in the
feature, and the feature *also* had a real bug at the time (a missing `_configure` line), so
two independent faults were producing one symptom. Route every such helper through the one
absolute number and make it additive.

**`Salvage._work` counts REAL seconds, and a headless main loop runs unbounded.** Awaiting a
frame COUNT to let a job finish works at 60 fps and fails headless, where 140 frames is a
quarter of a second rather than two seconds. Wait on the job's own flag with a frame cap. And
the second half: the worker was standing 15 m under water, so the breath ran out, `_drown()`
respawned the player on the deck and `_work` correctly abandoned the job as "you step away from
it, half done" — the probe would have been measuring drowning while reporting on harvesting.
Top the air up every frame of any underwater interaction test.

**A LIT surface on a caisson face at y −15 renders near-black whatever its albedo.** The
picked-bed scar was raised from 0.09 to 0.17 to 0.46 and photographed identically dark every
time, because there is no direct light down there and per-pixel shading gave it only the
environment's ambient. The coral beside it is not lit either — it is EMISSIVE (see the glow
note above). For a flat decal-like surface, `SHADING_MODE_UNSHADED` is the cheap version of the
same trick: the albedo is then what actually reaches the frame, through the fog grade.

**An untextured billboard quad is a white RECTANGLE.** Steam over the stove's pot was built
first as tapered cylinders (which photograph as flat blades, since an unshaded double-sided
cone has no volume) and then as billboarded quads (hard corners, reads as paper). Vapour needs
a soft edge, and that costs nothing to generate: a `GradientTexture2D` with `FILL_RADIAL` and
alpha falling to zero at the rim, built once in code, no asset and no import.

**Two vessels can end up on the same hob.** `interior_props` had already dressed the range with
`brass_pan_01` at (11.2, counter, 15.9) — which is exactly the left burner ring `rig_builder`
draws, and exactly where the stove's new boiling pot goes. **Before adding a prop to a surface
the dressing scripts also dress, grep the position, not just the room.** Three separate files
(`rig_builder`, `interior_props`, `cook_stove`) put geometry on this one range.

## Found while un-clustering the day crab pack (s21)

**"They never move" and "they sit next to each other" are DIFFERENT BUGS, and only one of them
has a probe.** The owner reported the giant crabs "sitting unnaturally next to each other all
day" after a pass that had already measured them crawling 89–101 m each in four minutes over
10–11 m of depth. Both facts were true: the pack was busy and CROWDED. `CrabLifeProbe`'s only
movement bar was `travelled > 1 m` and it had no notion of SPACING at all, so the complaint was
invisible to it. The tell, once measured, was unmistakable — **nearest-neighbour distances came
back in identical pairs** (crabs 0+4, 1+5, 2+6, 3+7), which is what a per-animal number looks
like when every animal's nearest neighbour is the same fixed partner. If an owner's word is
about the RELATIONSHIP between agents (crowded, lined up, following each other, ignoring each
other), measure the pairwise matrix. A per-animal statistic cannot see it.

**Two animals on one 6 x 6 m caisson leg will find each other, and the surface frame helps
them.** `FaunaMove.seat` wraps a convex edge on purpose — that is what carries a crawler over a
deck rim onto the rim face — so on a leg it walks the body straight round the corner onto its
pack-mate's wall. Measured: one crab's cling normal visited (1,0,0), (0,0,−1) and (0,0,1) in a
single day, three of the leg's four faces. Clamping the roam target to the leg's FOOTPRINT
rather than to the crab's own face plane is what let it aim there in the first place. If two of
a species share one small structure, give each an explicit patch of it — the animals will not
divide it up on their own.

**`FaunaTouch` spheres do not only corrupt PROBES — they corrupt the animals.** The existing
trap above is written from a probe's point of view. It is worse than that: a crawler seats
itself with the same kind of raycast, and `FaunaMove.kin_bodies` only excludes fauna beneath a
`bloom_fauna.gd` host. The reef's climbing snails are `BloomFauna` inner-class instances
parented under `leg_reef`, and the s21 mussel beds under `mussel_beds`, so a crab crawling down
a caisson **stood on a snail**: its cling normal tumbled — (0.36,−0.77,0.52), (0.39,0.4,−0.83),
(0.31,0.87,0.38) — for the rest of the day, seat error 1.36 m, 34 buried crab-frames, 3 of 8
adrift. `CrabLifeProbe`'s own column sweep had been printing the evidence all along as
"face at |x| 25.48" against a real face at 25.00.

**Where a surface is provably ONE PLANE, hold it analytically and delete the raycast.** The
caisson faces measure |x| 25.00 unbroken from y 1.0 to y −23.5. So the day cling is now a plane
pin — no query, immune to whatever the next session bolts to the concrete, and it cannot let go
of the face. It removed one raycast per crab per frame; "probe, don't guess" means derive the
number from the geometry ONCE and assert it, not re-cast it every frame into a world that other
sessions keep adding colliders to.

**Narrowing an animal's patch SLOWS IT DOWN, and nothing warns you.** Speeds, pauses and
targets were untouched, but confining each crab to a 2.1 x 4.0 m patch took the pack from
68–80% of the day in motion to 48–54%: a uniformly-drawn target lands next to where the animal
already stands, the move finishes before it starts, and the rest of the beat is a pause. Draw
the DIRECTION weighted by the room left on each side and the distance as a real fraction of
that room (`crab.gd::_jog`) — never a uniform sample you then clamp, because clamping at the
boundary is the same no-op and it parks the animal against its own edge.

**A probe with a fixed watch window rots when the schedule it watches gains a ramp.**
`crab_hunt_probe` (100 s) and `crab_qa` (110 s) both pre-date s18's late-weighted emergence
draw, under which the median crab does not attempt to surface until about half way through a
780 s night. Both were reporting failure — "first contact: NEVER  <- not scary" — about
behaviour working exactly as specified, and `crab_qa` was ALSO measuring the day pack's
clearance along world −Y at animals clinging to a vertical wall ("hovering 62.7% of the time",
gaps to 3.36 m: stable, confident, meaningless). Fixed: 480 s / 300 s at `Engine.time_scale`
6 (every figure either probe takes is a position, never a rate), and the gap is cast along the
animal's own `up`. 62.7% → 0.4% hovering, 9.1% → 0% sunk, NEVER → contact at 195.9 s.

## Found fixing the owner's five fauna bugs (s23)

**Godot's glTF importer puts metallicFactor/roughnessFactor in the SCALARS and the real
values in a TEXTURE, and every Tripo-era asset here ships both factors at 1.0.** So a shader
that reads `BaseMaterial3D.metallic` / `.roughness` and ignores `metallic_texture` /
`roughness_texture` renders those models **fully metallic**, and a metal with no reflection
probe under it is BLACK. Thirteen species were affected — `pyramid_snail`, `herring_gull`,
`ultra_hammerhead`, all ten `trop_*` and five deep fish — and the only reason it was ever
reported is that the pyramid snail is a WHITE animal on a sunlit deck, so it was the one where
the difference from the model render was unmissable. The older Meshy assets carry honest
0.0 / 0.8 scalars and no map, which is exactly why this survived three asset generations
without anybody seeing it. The tell is a one-line dump: `metallic=1.000 rough=1.000` with
`has_metal_tex=true`. `creature_swim`, `creature_swim_glass` and `reef_fish` now sample the
map through a channel mask read off the material rather than assuming glTF's G/B.

**`rate` being a time multiplier is not only a SHADER trap — the same bug writes itself in
GDScript as `t * pace`.** `underwater_world.GliderRay` already carries the shader half of this
in a comment ("writing a new rate at second T teleports the wave phase"). `reef_fish.gd` had
BOTH halves and neither was noticed: it drove the shader's `rate` from `alarm` every frame the
player was walking toward a shoal, AND it sampled its own multi-octave offsets at
`st["t"] * pace` off a clock seeded up to 400 s and only growing. A 10% pace change at t = 400
moves the argument of every sine by **58 radians**. Measured on a 10-fish damsel shoal with the
player closing from 12 m to 1.2 m: mean speed 0.13 m/s at alarm 0 → **1.13 m/s at alarm 0.105**,
mean |acceleration| 0.2 → **45 m/s²** — the shoal detonating at the first touch of alarm and
then jittering, which is what "glitchy near the player" looks like. **Integrate the paced time
(`t += dt * pace`) and spend the intensity on AMPLITUDE**, which is a multiplier outside the
sine. After: 0.148 → 0.227 m/s and |acceleration| 0.2 m/s² across the whole approach.
Rule of thumb: if a tuning value ends up INSIDE a `sin()` argument multiplied by an
accumulating clock, it cannot be animated at all.

**`maxf(x, FLOOR)` on a value that is already near its floor is not a safety net, it is a
rectifier.** `reef_fish` clamped each fish's wall standoff to `MIN_STAND` while ALSO lerping
the shoal's standoff down to `MIN_STAND` when it ducked — so most of a shoal sat on **exactly
0.450 m**, at every alarm level, for every sample of a 420-frame approach, with a corner in its
velocity every time it arrived on the clamp and left it again. A constant in a measurement that
equals a named constant to three decimals is the signature. Make the clearance structural
(`floor + span * something_that_cannot_go_negative`) and delete the clamp.

**`CreatureAnim.replace()` swaps the BODY but not the BEHAVIOUR, and the behaviour keeps
running on the hidden one.** `TideWorm` drove emergence, retraction, sway and visibility on
`_body` — four procedural spheres — while `replace()` hid those and parented the generated mesh
to the HOST. The animal was therefore permanently, fully out, never moving, and (because its
per-frame drive was `rate = 1.1 * _emerge`) frozen at a wave rate of ZERO: the owner's "weird
grubs on the wet deck that dont move". Nothing errors and the class still reads correctly.
**When a species gets its first real mesh, grep its `_process` for every node handle it poses
and check which of them the generated model is actually under.** The generated mesh was also
centred on its own box, so it sat half inside the plating — `belly()`/`ground()` exist for that
and the fallback path never needed them.

**A fauna patrol that writes a FIXED y into a moving sea is flying.** The harbor seal's haul-out
had been probed, seated and asserted at a 0.0 mm gap — and the owner still reported it hovering,
because the OTHER half of the animal swims a loop at `y = -0.15 + porpoise`, in an ocean whose
surface is an 11-band Gerstner sum with a −6.44 m trough floor. Measured over 600 frames: the
belly was clear of the water on **134 of them (22.3%)**, by up to 379 mm. A correct seat on the
concrete says nothing about the 90% of the time the animal is in the water. Take the depth from
`Gyre.wave_height()` at the animal's own xz; two calls a frame is nothing (the term s19 profiled
out was 512 of them).

**…and then the SAME animal was reported floating again, against a green assertion. The metric
was the trap.** The s23 fix above shipped with "the belly is above the water on 0 of 600
frames", which was true, is still true, and does not mean the animal is in the sea: the height
was `sea - 0.45 + max(sin, 0) * 0.55`, and the lift is bigger than the drop, so the animal's own
CENTRE rode up to **+0.159 m ABOVE the waterline** with a mean of **0.575 m of back in the air on
600 of 600 frames**. A belly-only test cannot see that, and neither can a probe that compares
against `Gyre.wave_height()` alone — the shader displaces horizontally too, so the drawn surface
at a given world xz is up to ~0.15 m from the number the CPU steers by (`tests/SealFloatProbe.tscn`
inverts that displacement and reports both). **When the report is visual ("it floats"), measure
the visible quantity: how much of the BODY is out of the water, against the surface that is
actually drawn.** Two more things fell out of the same block: `look_at()` on the raw per-frame
delta pitches the animal by the SEA's vertical velocity (the 1.7 m chop band runs at metres per
second — a 0.76 m deep body measured a **1.58 m tall** world AABB), so smooth the heading; and a
`global_position.lerp(dest)` haul-out lifts the animal off the water the instant it turns for
shore and flies it home at shelf height. Also: `get_index() % 2 == 0` is not an identity. It
picked exactly one of a pair only because they happen to be added back to back, and it picked
the *other* one from the pair's own `spawn_index` numbering.

**A load that restores the clock re-enters the autosave and overwrites the file it is
reading.** `SaveManager` autosaves on `GameClock.dawn`/`.dusk`, so *every* save file on disk
carries phase DAWN or DUSK — and `load_game()` restores the phase with `force_phase()`, which
emits those same signals. Every single load therefore called `save_game()` from the middle of
itself, *before* structures, containers, dropped items and the player position had been
restored, and wrote that half-empty world over the good save. The running session still looked
perfect (the rest of `load_game` finishes off the in-memory dict), so it only showed up on the
*next* boot: build a camp, save at dusk, Continue, quit, camp gone. Thirty-eight passing save
tests missed it because each one calls `force_phase(DAY)` first and DAY is the one phase not
wired to `save_game`. **A restore step that writes to a system with signals attached is a
re-entrancy hazard; guard the whole apply with a `_loading` flag.** And when a test sets up
state before exercising a save, check the setup is not quietly avoiding the only conditions the
feature ever runs under — assert on the file re-read off disk, not on live memory.

---

## Found characterising the dive hitch (s26)

**A performance fix that "should obviously work" needs the same proof as any other claim, and
three of them here did not.** The first dive of a session stalls ~285 ms. Every intuitive cause
was wrong: first-draw of the subtree's 1,120 materials (drawn at load, verified rasterising
37.76 M prims/frame — no change), the underwater Environment (paid topside, cost 275.5 ms by
itself, no change), and load ordering against `rig_batcher`'s weld (no change). The actual
property is that the warm state **decays with time hidden** — 3 s → 67 ms, 30 s → 127 ms, 36 s →
264 ms, never → 285 ms. Nothing about the first three hypotheses was unreasonable; what was
unreasonable would have been shipping any of them on the strength of the reasoning. The
harness is `tests/DiveProbe.tscn` and the full account is in `KNOWN_ISSUES.md`.

**Instrument the prewarm, not just the thing being prewarmed.** A prewarm that silently draws
nothing looks exactly like one that works. `_prewarm_underwater_world` printed its
primitives-per-frame precisely so "it ran and rasterised 37.76 M" was a *measurement* rather than
an assumption — which is what made it possible to reject the hypothesis instead of the
implementation. The pre-existing `_prewarm_underwater_env` had no such readout and its comment
had claimed the freeze solved for several sessions.

**Two dives, not one.** Any "first time X is slow" bug should be measured by doing X twice in one
session. The ratio between them separates a one-off (build/upload/compile) from a per-transition
cost, and those need opposite fixes. Here it immediately exonerated the ~4,100-node visibility
walk that was the obvious suspect.

**`head -N` on a Godot run can SIGPIPE the engine before it prints its result.** The first
DiveProbe run reached its report, printed the header, and was killed by the pipe closing three
lines before the verdict. Redirect to a file and read the file.

**`--check-only --script` reports `Identifier not found: GameClock` for any file touching an
autoload.** Already noted above as a false positive; restating because it is the single most
common output of the parse gate and it will be seen on every windowed harness launch. Read past
it and check whether any OTHER error is present — that is the signal.

---

## Found building spearfishing (s27)

**"It renders black" has more than one cause, and s24's famous one is not always it.** The
catchable shoals photographed as featureless black cut-outs at spear range while the tropical
reef fish beside them showed full colour. The obvious read was s24's metallic bug (glTF putting
PBR factors in the material SCALARS; fully metallic with no reflection probe renders black), and
it was wrong: a scan of the imported materials showed every catchable species carrying honest
scalars (metallic 0.000, roughness 0.800, no ORM map), while the trop_* fish are the ones at
metallic 1.000 — already handled. The real cause was LIGHT: underwater_fx grades ambient to
~(0.088, 0.203, 0.223) at 0.5 energy by 8 m and the sun floors near 0.06, so an unlit albedo of
(0.80, 0.40, 0.25) lands around (0.035, 0.040, 0.028) before the filmic curve. The reef and the
trop fish read at that depth because they carry emission and the shoals carried none. Scan the
material before blaming the material.

**`glow_energy` and `body_glow` default to 0, so a creature only glows if something CALLS
`ANIM.drive`.** Exactly one species ever did (the herring lantern shoal). Anything relying on the
Bloom rim to be visible in deep water needs the call; `ANIM.attach`'s `glow` argument sets the
COLOUR of a rim whose energy is still zero, which reads in code as though it were already lit.

**A harness that disables the player's `_physics_process` silently disables anything polled
there.** SpearShot turned physics off to stop the player swimming out of frame, which also
stopped `_update_spear_prompt` — so the first three frames photographed a working feature with no
prompt on screen and the log cheerfully printed `prompt: (none)`. Drive the poll by hand in a
harness, and remember the chip is written by ANOTHER node (`interaction_ray`) in ITS `_process`:
the shutter has to come a frame or two after the value is set, not in the same frame.

**Sweep a look-tuning value off ONE world build.** Picking emission by eye across separate
launches is several windowed runs in several thermal states, and this machine's frame times drift
enough between runs to make cross-run comparison meaningless. Re-expose the same frame at each
candidate instead (`SpearShot` does this for the shoal rim, `ReefShot --glow` for the reef).

**A probe that dies mid-run still prints `FAILURES: 0`.** A SCRIPT ERROR inside an `await`ed
coroutine abandons it and returns quietly to the caller, which then reports on the checks that
DID run. SpearProbe hit this on a mistyped `PlayerState.selected_slot` (it is `selected_hotbar`)
and reported a clean pass over a run that stopped a third of the way through. Every probe that
runs its body in a coroutine needs a completion sentinel set on the last line and checked by the
reporter.

**underwater_world only swims its schools while the subtree is VISIBLE, and the pod root never
leaves the world origin.** So on any harness that starts topside, every fish is still stacked at
(0,0,0) — and a query aimed at one of them "passes" while measuring nothing. Get the camera under
the water first, give the pods real frames, and assert the pod is off the origin before trusting
a position read.

---

## Found clearing two KNOWN_ISSUES entries (s28)

**"Fixed entries are deleted, not struck through" cuts both ways: an entry can also be HALF
stale, and that is worse than either.** `KNOWN_ISSUES` carried "un-crouching has no headroom
check". The gate existed and was correctly wired — but it probed only a 0.3 m sphere where the
new HEAD lands (1.55..2.15 above the feet), and the standing capsule spans 0.00..1.80, so
nothing between the crouched top at 0.90 and 1.55 was ever tested. A beam or pipe run at chest
height passed the check and the capsule grew into it. Reading the code said "stale"; testing it
said "half true". **Before deleting a stale-looking entry, write the assertion that would fail
if it were true.**

**An assertion that only ever runs in the good case cannot tell a working gate from a missing
one.** `playtest.gd` had crouched and un-crouched for many sessions — always in open air, where
a present gate and an absent gate produce identical output. That is precisely why the entry
survived. Both the BLOCKED case and the released case now assert, because a "refusal" that
passes for a player who simply cannot stand at all is not a test either.

**The diagnosis in a bug entry is a hypothesis, not evidence.** The store-room crate entry said
the prop "drops through" because the CSG deck has no collider yet. It does not drop —
a `LootContainer` is a `StaticBody3D` and never falls. `SurfaceSnap` actively moved it: the ray
passed through the unbaked deck, hit the structure 3 m below, and seated it there, "succeeding"
every time. A fix built on the entry's own wording (retry while nothing is found) changed
nothing, because that ray never failed to find something.

**Bounding a correction by DISTANCE only works if the legitimate corrections are small — measure
the distribution first.** The obvious fix for the crate was a `max_drop`. Instrumenting the live
world showed all 36 snaps: 2.954 (the bug), 1.800, 0.900, then everything else <= 0.32 — and the
1.800 and 0.900 are real props authored above a deck being correctly seated onto it. No threshold
separates them. The discriminator was time, not distance: wait for the CSG colliders to bake.

**A `head -N` on a probe's output can hide the very line you are looking for, and make an A/B
read backwards.** A first pass concluded the crate fix worked because the crate was absent from a
truncated list — the reef-shelf log lines had eaten the budget. Grep for the specific thing, or
count, rather than eyeballing a head.

---

## Found doing the owner's s34 focus session

**A PROBE CAN MEASURE ITSELF, AND IT LOOKS EXACTLY LIKE A PASS.** `FaunaBugsProbe` reported
the hauled-out seal at `GAP +0.0 mm` while the owner was looking at a seal in the air, for
two sessions. `_seat()` runs `y += _haul_floor - low_point(_model)` every frame — it DEFINES
`low_point == _haul_floor` — and the probe compared `low_point` against an independent ray
with the same origin, direction, mask and exclusions. The two are the same number by
construction, so the printed gap could not have been anything but zero **however far the
drawn animal was off the concrete**. It would have printed +0.0 mm for a seal on the moon.
The test for this is not "is the assertion true" but **"what value of the world would make
this assertion fail?"** — if you cannot name one, it is a tautology. Fixing it needs a
genuinely independent path to the same quantity: the game seats a cached CONVEX HULL, the
probe now brute-forces every vertex, and it asserts the two agree.

**`global_transform * aabb` IS THE BOX OF THE ROTATED BOX, WHICH IS BIGGER THAN THE MESH.**
`CreatureAnim.low_point` seats things on that bound. On the harbor seal at its -0.12 rad
rest pitch the bound sits **102.0 mm** below the lowest real vertex, so seating it on the
concrete hangs the animal 102 mm over it. Note the shape of the history: that function was
introduced to fix a 105 mm BURIAL from an unrotated measurement — a bound that was too high
swapped for a bound that is too low, twice without measuring the mesh. If a pose is applied
after placement, seat on `low_vertex()` (a support query over the convex hull: exact, and
29,064 vertices become a couple of hundred dot products).

**A HARNESS THAT DROPS THE LENS OUT OF THE `player` GROUP SWITCHES OFF `underwater_fx`.**
Its `_process` finds the player with `get_tree().get_first_node_in_group("player")` and
returns immediately without one, so the ENTIRE depth grade stops and `main.gd`'s much
simpler fallback curve becomes the only writer on that Environment. Every shot harness here
drops the lens out of that group (the s20 crab census), so this is armed for all of them.
The s34 fog sweep lost an hour to it: five candidate curves written into a node that was no
longer listening, five logged confirmations of the write, and `fog_density=0.1700` — main.gd's
lerp at its ceiling — on all five frames. **Read the property back off the thing that draws
the picture** (`cam.environment`), not off the node you wrote to. And two writers on one
Environment resolving by `process_priority` is a trap in itself; make one stand down.

**A WHOLE-FRAME STATISTIC CANNOT SEE A CHANGE CONFINED TO THE SUBJECT.** The same sweep was
nearly abandoned because mean luminance and edge energy over the full frame came back within
1-7% across candidates that a pixel diff showed differing by up to 147 levels on 75,000
pixels. ~90% of an underwater frame is empty graded water, which is dark either way, so the
subject's contribution is inside the noise of any global mean. Measure the SUBJECT: pixels
standing clear of the background's modal luminance, and how far above it they stand.

**A PER-NODE SEARCH CANNOT FIND WELDED DRESSING — AND THE SIZE FILTER YOU ADD TO FIX IT
FINISHES THE JOB.** `DeclutterProbe` reported the spawn walk clear while a tyre stood on the
gangplank. `rig_batcher` welds the dressing into `MergedDressing` chunks, so the tyre, the
chain and the mooring links are not nodes by probe time — they are triangles inside ArrayMesh
chunks metres across, which a "props are smaller than 4 m" filter then discards as scenery.
This file already says "search from the PICTURE, not the tree" for a colour hunt; for a
GEOMETRY hunt the equivalent is to search FACES. Pre-filter meshes by AABB, then test
triangle centroids against the volume.

**"THE WIDEST FREE SPAN" IS NOT "HOW MUCH ROOM IS THERE ON THE PATH".** The same probe's
first metric took the widest capsule-free run within range and called a station 3.00 m clear
whose walk line was blocked outright — there was open deck 1.70 m west of the route. Take
the run CONTAINING the path. And that run is the span of valid capsule CENTRES, which is one
capsule DIAMETER narrower than the opening: comparing it against a width failed a doorway
built 1.60 m wide.

**TWO CORRECT FEATURES CAN BE JOINTLY WRONG, AND ONLY A SCREENSHOT WILL SAY SO.** s34 step 2
put the abyss fog ramp at -26, correct against a reef that stopped at -22. Step 5 then took
the coral band to -40. Neither change was wrong and neither probe could see anything amiss;
the close-out frame at y -28 showed coral fading into murk whose entire purpose is to hide
things. Batch the visual pass at the END of a session as well as per feature, and aim it at
the SEAMS between features rather than only at each feature.

**A COUNT-SCALED PLACEMENT PASS MUST SCALE WITH THE BAND, OR EXTENDING THE BAND THINS IT.**
Every "attempts" number in `leg_reef.gd` was tuned against a 9.3 m band. Trebling the band's
height without touching them would have spread the same coral over three times the concrete
and read as a reef that got sparser. Derive the multiplier from the band so the next person
to move `BAND_BOTTOM` does not have to know.

**GENERATED FLORA IS NOT REEF-BUDGET FLORA.** Pointing a bulk placement pass at the fauna
GLBs cost 10.7 M triangles for 363 plants — 28,844 / 29,778 / 30,745 tris a piece against a
reef set that runs 1,400-7,000. The rule about decimating anything placed in bulk is already
in this file; what is new is that the flora were ALREADY in the tree and looked like free
reuse. `tools/decimate_reef.py` also bakes the placement contract (+Y growth, base at y=0),
so re-cutting removes special cases as well as triangles.

**THE HEADLESS TEXTURE TRAP FIRES ON ANYTHING THAT WRITES A TEXTURE, NOT JUST ON A DOWNLOAD.**
It bit three times in s34: the Tripo cat poses (expected), and then the maps
`decimate_reef.py` wrote when re-cutting three meshes. Any tool that emits an image file
gets `compress/mode=0` on import. `grep -rl '^compress/mode=0' assets/` after ANY step that
produces one.

**A SPECIES WITH AN EMPTY `active` LIST IS ON SHIFT ONLY IN A STORM, AND A PROBE THAT WALKS
THE FOUR CLOCK PHASES NEVER SEES IT.** `FishSpreadProbe`'s first cut measured in DAY, then
in all four phases, and still could not judge `fish_drum_croaker` or `fish_squall_garfish`:
`underwater_world` reads an empty list as "storming". Two species, 20 fish a pod, had never
been watched swimming at all. Force a squall as a fifth window.

**NET DISPLACEMENT OVER A CLOSED CIRCUIT IS NOT A HEADING.** Summing a pod's per-frame
displacement over a measurement window and taking the direction of the sum reported six
species as swimming backwards; every one was an artifact, because a pod wanders a closed
Lissajous and over a full lap the displacements cancel, leaving a residual pointing wherever
the lap happened to stop. Accumulate the per-frame ALIGNMENT (dot of heading against that
frame's velocity) and average it — which is what "correlate over a few hundred frames" in
this file's facing entry has always meant.

**A GEOMETRIC HEAD-FINDER FAILS ON BILLS, NEEDLES AND WINGS, AND IT FAILS CONFIDENTLY.** The
vertex-centroid statistic that identifies a fish's head end is correct on 19 of 19
calibration models and wrong on five body plans: a marlin's bill and a pipefish's snout
carry no mass in front of a heavy tail, and a ray's WINGSPAN is longer than its body so the
"long axis" is not the body at all. Require two independent statistics to AGREE and print
UNCERTAIN otherwise; name the species the instrument cannot judge, in the file, with what a
render showed — an assertion that is silently skipped is how a real defect hides among four
false alarms.

---

## Found doing the owner's s35 fix list

**TRIPO WILL RIG A QUADRUPED — AND ITS CLIPS ARE STILL UNUSABLE.** `creature_swim.gdshader`
has asserted in its own header for many sessions that "Meshy (and most text-to-3D services)
only auto-rig HUMANOIDS", and the whole vertex-displacement architecture in `creature_anim.gd`
follows from it. That is true of Meshy and FALSE of Tripo: rigging the ship's cat off the task
ids s34 logged returned a real skin — 41 joints, clean weights, and a bind pose that
photographs identically to the static mesh. Zero of this project's 165 GLBs had ever contained
an animation or a skin, so nobody had checked. **Two things are still wrong with what comes
back, and both are invisible in the glTF:** the joint names are HUMANOID (Hip/Pelvis/Thigh/
Clavicle/Upperarm/Hand fitted to a cat), so `preset:walk` is a human walk cycle on a quadruped
and photographs as a wrung-out animal; and the BONE LENGTHS ARE ASYMMETRIC — `L_Calf->L_Foot`
0.156 against `R_Calf->R_Foot` 0.569, with the forelimbs disagreeing the same way. So: take the
SKIN, discard the CLIPS, and drive it with forward kinematics on the proximal joints, which is
immune to the length asymmetry because rotating a bone swings whatever is weighted to it.
`tests/BoneDump.tscn` prints the rest pose; `tests/AnimShot.tscn` samples a clip at eight
phases, because a single frame of a bad retarget looks fine at almost any phase.

**A CREATURE THAT SEATS ITSELF BY RAYCAST MUST EXCLUDE ITS OWN INTERACTION HANDLE.** The ship's
cat spawned exactly 0.500 m in the air for two sessions. `_seat()` dropped a ray from +1.2 with
`collision_mask = 1` and no exclusions, and an `Interactable` is a `StaticBody3D` on the default
layer carrying a 0.5 m box centred 0.25 m up — so the first thing the ray hit was the top of the
cat's own collider. The existing FaunaTouch trap in this file is about a probe measuring OTHER
animals; this is the animal measuring ITSELF. It read as intermittent ("floating until you say
hello") only because the other two rays in the same file DO exclude the handle, so the first
step re-seated it and the bug vanished — which sent one investigation looking at the greeting
code. **If a bug appears to be cured by an unrelated action, find what that action re-runs.**

**`atan2(d.x, d.z)` POINTS +Z AT THE TARGET, AND GODOT'S FORWARD IS -Z.** Every creature here
adds `+ PI` after it (`fauna_move.gd:511`, `bloom_fauna.gd:2927/2969/4423/4455`, one of them
commented "this turns the head toward the player instead of pointing its tail at them") because
`CreatureAnim` normalises every generated mesh's head onto the host's -Z. `ship_cat.gd` was the
one call site that missed it, so the cat aimed its tail wherever it was going. The half turn is
invisible in review precisely because the line looks like the correct idiom.

**A BODY OFFSET WRITTEN BY ONE STATE AND NEVER CLEARED IS CARRIED BY EVERY OTHER STATE.**
`_groom()` wrote `_body.rotation.x` and `_pose_sit()` wrote `_body.rotation.y`; only ROLL was
ever eased home. So the cat picked up a permanent pitch the moment the player met it and a yaw
skew off its direction of travel every time it sat down, and kept both for the session — the
owner's "not straight". Ease the whole offset to neutral once per frame and let each state ADD
what it wants; a state machine whose states leave residue is not one.

**`Interactable` IS A `StaticBody3D`, SO EVERY INTERACTABLE IS SOLID TO THE PLAYER.** Fine for a
crate, wrong for an animal — you could not walk through the cat. `bloom_fauna`'s existing lever
(`collision_layer = 1 if solid else 0`) cannot express the third case, because layer 0 also
makes the thing unreachable by `InteractionRay`. Everything in this project lived on layer 1,
so layer 3 is now INTERACTABLE-BUT-NOT-SOLID and `InteractionRay` masks `1 | 3`. Assert BOTH
halves when you use it: off the solid layer, and not on no layer at all.

**A SHARED ShaderMaterial FED A PER-PLAYER QUANTITY MAKES EVERY SURFACE MOVE WITH THE VIEWER.**
The owner reported "wall textures still moving" across several sessions and every investigation
went to the wall MATERIALS, where nothing was wrong — `mat_lib.gd` had not been touched in
twelve sessions. The actual defect was `underwater_fx.gd` writing the caustic shader's `top_y`
from `surf`, i.e. `Gyre.swim_line()` sampled at the PLAYER's xz, into the ONE material every
caisson shares: the band of moving light on all four legs rose and fell with the wave the player
happened to be standing in. **When a complaint is that something moves WITH the observer, look
for an observer-derived value crossing into shared render state** — the fault is a coupling, not
a mapping, and no amount of staring at the material will show it.

**A TOLERANCE WIDER THAN THE DEFECT CANNOT SEE THE DEFECT.** `CatProbe` asserted the cat's
height as `absf(y - 18.0) < 1.2` against the literal deck height — which passes for an animal
hanging 1.19 m in the air, while the real bug was a 0.5 m float. It had no notion of facing,
collision layer or skeleton at all. Sibling of the s34 seal tautology and just as green: pick
the tolerance from the smallest defect worth reporting, not from what currently passes.

**TRIPO SILENTLY TRUNCATES A PROMPT AT 1000 CHARACTERS, AND THE TAIL IS WHERE THE NEGATION
LIVES.** All three s35 goliath grouper drafts came out 1067-1098 chars. The template this file
recommends puts the shape and the pattern first and the "NOT glossy, NOT plastic, NOT a toy, no
base, no plinth" clause LAST — so an over-long prompt loses exactly the part that fights the
default failure mode, and comes back as a glossy toy that looks like a prompting failure rather
than a truncation. Assert the length before spending the credits.

**A FUNCTION CAN EXIST, BE CALLED CORRECTLY, AND HAVE EVERY LINE IN IT BE DEAD.**
`AudioDirector.set_underwater()` was wired from `main.gd` and did nothing at all: every bed id
it faded is in `AMBIENCE_OWNED`, and `_fade` forces exactly those to -80 dB, so
`_fade("sea", -8.0, 0.6)` set the sea to SILENCE. The feature read as implemented in every
review. The same shape as the shadow-property trap at the top of this file — the tell is that
nobody had ever measured the OUTPUT, only read the call site.

**AN AGENT FLEET SHARING ONE WORKING TREE MAKES `git add -A` A LANDMINE.** Two agents' mid-flight
edits were swept into commits describing something else entirely. Nothing was lost and the suite
stayed green, but the history now misdescribes itself. With concurrent agents, commit by explicit
PATH, always — and give each agent a disjoint file set up front, because the alternative is
per-agent worktrees and this repo's working tree is 18 GB.
