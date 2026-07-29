# SALTLINE — development log

**Read this first in a new session.** It is the current state of the project and
what is in flight. `docs/AGENT_TRAPS.md` is the other required read — it is the
list of things that have already cost hours here.

Newest first. One entry per working session. Keep entries short: what changed,
what it revealed, what is still open. Detail belongs in the commit message; this
is the index.

---

## Current state

- **Branch:** `main`, HEAD `6395323` + uncommitted s19/s20 batch below.
- **Engine:** Godot 4.7, `gl_compatibility`. macOS.
- **Tests:** `godot --headless --path . res://tests/TestRunner.tscn` → 238 pass,
  `FAILURES: 0`. Keep it there. `tests/ReefFishProbe.tscn` and `tests/ReefProbe.tscn`
  (windowed only) cover the reef/fish system specifically.
- **Shipping target:** itch.io. Windows packaging is `tools/package_windows.sh`;
  player-facing instructions live in `dist/START HERE - How to Play.txt`.

### What the game is
First-person survival on an abandoned North Sea oil rig, in an ocean the Bloom
has mutated into cold teal light. The rig is built **in code** by
`scripts/world/rig_builder.gd` and the dressing scripts it spawns — the
positions in those scripts *are* the level design. There is no scene file to
open and drag things around in.

### Tools that exist (use them)
- **sonar MCP** — a live spatial oracle over a real scan of the rig. Wired via
  `.mcp.json`, scan in `.sonar-rig/`. **Call `scene_brief` first**; it returns
  `RIG_ATLAS.md` with the coordinate mapping and zone list. Use `props_find`,
  `spatial_probe`, `spatial_raycast`, `spatial_measure` instead of guessing
  coordinates. Refresh after rig edits with `tools/export_rig.sh`.
  *This is the single most under-used tool in the project — most of the
  "floating prop" bugs found in s17/s18 would have been caught by probing.*
- **`.claude/skills/realistic-animals/`** — text→3D asset pipeline (Tripo
  default, Meshy fallback). Key in `.env`, which is gitignored.
- **Screenshot harnesses** — `tests/*Shot.tscn`. Must run **windowed**.
  `tests/CandShot.tscn` photographs a raw GLB straight off disk, which is how
  generated candidates get judged before anything is wired in.
- **Probes** — `ContentProbe`, `PlacementProbe`, `LabelAnchorProbe`,
  `LightAnchorProbe`, `CatchProbe`, `CrabLifeProbe`, `HandbookProbe`,
  `FaunaDegenerate`. Prefer adding a probe over asserting in prose.

---

## Working agreements

These exist because the project is a long-running, multi-session build and the
same mistakes kept recurring.

1. **Probe, don't guess.** Never hand-type a Y coordinate. Every floating-prop
   bug in this repo traces to an authored constant that drifted from the real
   geometry.
2. **Verify by looking.** The owner judges by screenshot. Render it, *read the
   PNG back*, iterate until it is right — then show it. Never claim a visual
   result that has not been looked at.
3. **Measure, don't assert.** "Feels faster", "should be fixed" and "the shadows
   are better now" are not results. Numbers are.
4. **Commit verified work promptly.** Sessions have been lost to crashes and API
   stalls. Anything green and finished goes in a commit, immediately.
5. **Report honestly.** If a thing is blocked, partial, or was skipped, say so in
   the same message. Do not let a completion summary imply more than was done.
6. **Record what bit you.** New trap → `docs/AGENT_TRAPS.md`, same session.

---

## Sessions

### s20 — 2026-07-29 (tropical reef fish)
**Ten small reef species living on the leg coral**, anchored to real colony
positions rather than patrolling waypoints. Each fish belongs to a **station**
for the whole game — position is that station's seat on the coral plus a
multi-octave offset — so schooling behaviour cannot get lost off, and it varies
independently by school size, depth band, wall-hugging tightness, skittishness,
pace and night shutdown: clownfish trios that never leave one coral head,
50-strong damsel shoals (the most skittish thing on the reef), a solitary
triggerfish that closes on the player instead of fleeing, bonded butterflyfish
pairs. **252 fish, 55 stations, 352k tris**, meshes decimated 2.08M → 16.2k
(`tools/decimate_fish.py` — centres the pivot on all three axes rather than
seating the base at y=0 like the reef decimator, because a swimmer's `look_at`
has to pivot about its centre, not its belly).

**Measured cost: zero on deck** (0/55 stations live, +0 tris, +0 draws — inside
the existing topside cull), **+0.5–0.9 ms underwater**, at or near this
machine's own noise floor. The file never calls `Gyre` — the exact per-frame
pattern that cost the existing schools 3.7 ms at the waterline was deliberately
avoided from the start.

`tests/ReefFishProbe.tscn`, 7/7 PASS: caisson clearance 0.450 m minimum, 0
fish-samples inside the pontoon slab, every species inside its own home range,
all 55 seats on a real caisson face, startle measured (damsels pulled the shoal
0.83→0.58 m off the wall), and **all 252 models carry the authored rotation** —
worth calling out because facing came back in **three different conventions
from one prompt template** (some face +Z, some −Z, two are authored along local
X), all measured off `CandShot` rather than assumed, in `FACING_OVERRIDES`.

**Design call flagged for review, not decided unilaterally:** the shallow band
(clownfish, yellow tang, damsel) sits inside the kelp forest — the innermost
kelp strands are 200 mm off the concrete at that depth. Reads as fish
discovered among kelp, which seems right, but it's the owner's call to
overrule.

### s20 — 2026-07-29 (lush leg reef)
**The caisson reef became an ecosystem** (owner brief: brighter bloom, more coral,
sponges and barnacles, sculpted reef *masses*, bigger starfish all down the legs,
and snails climbing them). Tripo round 9 (`_cand9`), 15 reef candidates.

**Rejected by render, at the shipping decimation ratio** (`tests/CandShot.tscn`):
`sponge_fan` — two thirds of it is a smooth pale trumpet foot, the same
reads-as-a-plinth failure that cut `coral_encrust`; `star_big_blue` — glassy cobalt
with bent arms and a warped side profile, the plastic-toy default; `barnacle_goose`
— a radially symmetric spiky ball (0.97/0.99/0.93 on its three axes), not a bunch
of stalked shells, and its spines decimated into loose shards. It also 502'd
mid-poll on the first attempt and was regenerated, which paid twice — the task id
was not logged at submit time. **Kept 12**: 4 reef masses, 3 sponges, 2 barnacle
crusts, 3 big starfish.

**Decimation** (`tools/decimate_reef.py`, now with a slug-list argument, a search
path over both `_cand` roots, and a measured auto-orient rule for flat/blade pieces
instead of a hand-written rotation table). Every s19 coral was re-cut one notch
leaner to pay for twice the instances — and **three of them had to go straight back
up**: brain, bubble and the barnacle crust shatter into loose facets below ~4k
because their detail is a dense field of small bumps. Branching and fan silhouettes
are fine at 5–6k, flat starfish at 2k. The floor is set by surface type, not size.

**Numbers.** 560 → **1,170 instances, 62 MultiMesh draws, 4.34 M tris** across 21
species. Per leg ~0.94–1.03 M (was 0.62–0.72 M), foundation 0.43 M — one MultiMesh
per species per leg still means looking at one leg culls the other three, at ~15
draws for that leg. Seating: **0 floating, 0 buried, median +64 mm recessed**, and
**0 of ~2,400 seating rays fell back** to the sonar face. Big starfish: 11 attempts
a leg produced only 41 in the whole ocean once the spacing rejection had had its
say, so the attempt count went to 18 and a star's claim radius came down from 0.62
to 0.44 of its size (a flat animal lies ON the reef rather than competing with it) —
**79 big starfish**, on the legs as well as the foundation.

Not re-profiled: s19 measured the 560-instance reef at 1.98 ms (8.5%) at
`submerged_deep`. This is ~1.45x the per-leg triangles and 2.1x the instances and
the cost has NOT been measured. Filed in `KNOWN_ISSUES.md` with the cheapest levers
in order, since a concurrent session owns the frame budget.

**Emission: 0.15 → 0.50.** `main.gd` blooms above `glow_hdr_threshold = 0.8`, so the
s19 value produced no bloom whatsoever — it was a slightly brighter texture. The
first attempt at 1.35 rendered the reef as featureless white (MultiMesh vertex
colour multiplies albedo, *not* emission, so past ~0.7 emission swamps every tint).
`ReefShot.tscn --glow=a,b,c` was added to sweep it off one world build; 0.50 read
off the ladder as the top of the range that keeps the reef's own colours.

**Snails.** 13 on the caisson faces — 7 lamp (moon-white, own light) + 6 pyramid —
spawned from `leg_reef.gd`, not from the shared `bloom_fauna.gd`. Three things a
wall crawler needs that a deck crawler does not are set on its `SurfaceCrawler`
after `add_child`: `up` = the probed face normal, a heading with a real vertical
component, and `climb_base` = the spawn Y (or `CLIMB_MAX`'s "six metres above the
foothold" is measured from y = 0). `PyramidSnail` re-picks its heading in world XZ,
which on a vertical wall projects to *pure sideways* — its timer is pushed out of
reach and `LegReef._process` hands it a heading in the FACE plane instead. Seeded
only where a raycast found real collider (`_probe` reports its fallbacks; 0 refused).
Verified in `ReefProbe`: foot on the face within +20 mm, body-up vs face-normal
1.00, 13 of 13 crawling, 13 of 13 still on a face after 3 s.

**Three silent failures, all now in `docs/AGENT_TRAPS.md`:** every creature carries
a solid 0.6–0.85 m `FaunaTouch` sphere on the default layer, so putting snails on
the caisson made `ReefProbe` report the caisson had moved **606 mm** and 19 flush
corals as buried by up to **926 mm** — confident, stable, fiction; unpausing does
not remove the PAUSED *panel* (its own CanvasLayer), and `_process` cannot unpause
at all unless the harness is `PROCESS_MODE_ALWAYS`, which cost a render pass and a
"0 of 13 snails moved" false failure; and a harness whose script fails to parse
hangs a windowed Godot for ever, because the root comes back script-less and
nothing ever calls `quit()`.

**Also:** the first snail placement was correct and invisible — d 0.16–0.72 put half
of them inside the kelp stand (measured floor y −12.09). Moved to d 0.44–0.86, under
the kelp and among the coral. `ReefProbe` gained a snails section and its
kelp assertion was split (the coral band must start below the kelp; the barnacle
crust and starfish deliberately run up to the pontoon skirt). Two `TestRunner`
lamp-snail assertions hard-coded "6" and now count what is there.

Screenshots: `/tmp/reef_s20/` (day + night, incl. one frame per live snail).

### s19 — 2026-07-29 (performance)
**"Runs without lag" pass, measurement-first.** Re-profiled before touching
anything: 35.65 ms/frame (28.1 fps), 3392 draw calls at the spawn vantage —
confirming the earlier profile still held. Ended at **30.23 ms (33.1 fps), 3293
draws at the same vantage, with the 560-instance leg reef added in between**.

**Where the frame actually went, and what was done about it:**
- **The wave math** (`gyre.gd`). `wave_height` was `wave_offset().y` — it paid for
  the horizontal Gerstner displacement, and therefore ELEVEN `cos()` calls, that
  nobody reading a surface height ever uses. It is now its own loop, and `k` and
  `omega` are precomputed per band instead of being re-derived (11 divisions and
  11 square roots) on every one of the several hundred calls a frame.
  **1.44x measured** (`tests/WaveBench.tscn`, 40k samples). One behaviour change,
  documented and asserted: the old path rounded through a `Vector3`, whose
  components are single-precision, so the height is now ~1.2e-7 m *more* accurate.
- **The per-fish swell sample** (`underwater_world.gd`). `Gyre.water_time()` was
  called once per fish per frame — 512 engine calls for a number that cannot
  change within a frame. Hoisted. The surface clamp is also skipped outright for
  any pod whose ceiling is provably below `Gyre.trough_floor()`, the analytic
  deepest the sea can reach at any sea state (-6.44 m). **Every fish kept.**
- **AI decimation** (`scripts/world/ai_budget.gd`, new). The wall was per-frame
  GDScript on animals nobody is looking at. Distant and undrawn creatures now
  think every 2nd or 4th frame and are handed the delta they missed. 27 species
  across `bloom_fauna`, `reef_life` and `underwater_world`, plus per-pod
  decimation for the 48 fish shoals. **Nothing inside 18 m is ever decimated**,
  and nothing was deleted or thinned.

**Worth 2.5-5.4 ms at five of six vantages** (A/B/A in one session, each row
against its own noise floor — `tests/VantagePerf.tscn`), i.e. 12-27% of frame.

**Proving the animals did not slow down** is most of the work here, because the
obvious version of this optimisation silently runs everything at 1/N speed
(Godot passes the FRAME delta, not the accumulated one). Three independent
checks: `tests/AiBudgetProbe.tscn` measures d(_t)/d(wall) A/B/A on the live world
and gets **1.000 for all 27 species**; the suite asserts delta conservation
arithmetically; and it asserts that a creature stepped 300x at 1/30 s and one
stepped 75x at 4/30 s finish **0.000000 m apart**.

**The new leg reef costs 1.98 ms (8.5%) at the deep underwater vantage and is at
or below the noise floor at all five others** — it is affordable, it is not the
wall, and it should stay.

Tests: 238 pass, `FAILURES: 0`.

### s19 — 2026-07-29 (reef)
**Coral reef down the caisson legs + starfish on the foundation.** Tripo round 8
judged by render: **rejected `coral_tube` and `coral_fan_b`** (both bedded on a
baked-in rock, so neither can seat flush; fan_b also duplicated fan_a's
silhouette), **`coral_encrust`** (smooth pale stalk reads as a plinth, and it took
decimation worst of the set), and **`coral_whip`** — that one survived judging and
decimation and was cut later, *on the wall*: a 2 cm wand colony renders as red
scratches on concrete at any distance you actually see a caisson from. Shipped 6
corals + 3 starfish.

**Decimation** (`tools/decimate_reef.py`, headless Blender, matches the s17 item
pass): 500k → per-slug budgets spent where they show — 8k for the pieces that ARE
their silhouette (staghorn, sea fan), 5–7k for the massive blobs whose detail is
normal-mapped, 3k for the flat starfish. 3.36M raw → 53k across 10 pieces, UVs
kept, textures 2048 → 1024. It also **normalises orientation** into one contract
(+Y = growth, base at y=0, XZ centred), which is what lets the placement code
point a host's +Y down a probed normal instead of carrying ten special cases.

**Placement** (`scripts/world/leg_reef.gd`, spawned by reef_life): patchy colonies
— a dominant species plus an accent, clustered on a seed, thinning with depth,
favouring the outboard and up-current faces. **560 instances, 27 MultiMesh draws,
3.14M tris**, one MultiMesh per species PER LEG so looking at one leg culls the
other three (~0.62–0.72M per leg, 0.48M foundation).

**Sonar earned its keep twice.** The caisson faces came from `spatial_raycast`
(every face exactly 3.000 m from its centre line, at eight depths) and
`spatial_slice` confirmed the pontoon plan independently; `ReefProbe` then
re-derives both from the live colliders every run (0.000 m deviation over 64
rays). The band top is **measured, not typed**: 44 tagged kelp strands, floor
y −12.09, reef starts 0.6 m under it.

**Three silent failures worth the entry** (all now in `docs/AGENT_TRAPS.md`):
MultiMesh instance data is dropped by the headless renderer and reads back as
IDENTITY, so a headless probe cheerfully certified 292 corals sitting on the world
origin; Blender's glTF importer is Z-up, so a decimation pass "normalising up"
normalised sideways and printed plausible numbers; and the first vegetation walk
measured y −20.98 because the deepest things near a footing are floodlight cones,
god-ray quads and *passing fish* — it would have shipped a 1 m reef.

**Blocked at hand-off:** `scripts/world/underwater_world.gd` does not parse in the
working tree — a concurrent session added `var _eye` alongside the existing
`func _eye()`. Every visual and probe number above was taken in a disposable
copy-on-write clone with that variable renamed locally (behaviour-neutral); the
working tree was not touched. `TestRunner` there reports **FAILURES: 1**,
`wave_height is exactly wave_offset().y`, which is **not from this work** — it
reproduces with LegReef disabled and lives in the same session's `gyre.gd`.
Screenshots: `/tmp/reef_shots/` (15 day + 4 night).

### s18 — 2026-07-29
Hammerhead (owner-picked `hh_a`) installed and found to be swimming **broadside**
— generated meshes do not share a forward axis; fixed with a measured
`FACING_OVERRIDES` entry and 5→7 m scale. Killed a per-frame `Vector3 cannot be
normalized` storm in `fauna_move.gd` (cause was **NaN**, which defeats every
existing guard; one harness run wrote 4.4 GB of stderr). Crabs: fixed the
origin-drift bug, moved the day band out of the inside of the foundation
casting, and gave the night emergence a real ramp (was flat 3/8 all night).
Shadows: most previous shadow work measured as **inert on gl_compatibility**;
the real cause was `SHADOW_PARALLEL_2_SPLITS` halving the atlas — orthogonal at
8192 gives 3.4× texel density for +0.5 ms. Fishing: all 35 species now reachable
across weather/fog/light/bait/depth conditions (the oarfish was effectively
uncatchable); the Fisherman's Handbook is now a carryable, placeable readable
whose text documents those conditions. Lamp snail pattern now slowly morphs.
Fish schools profiled and deliberately **not** cut — they cost 0 on deck.

### s17 — 2026-07-28/29
Deck birds: replaced the stork-like `corvid_gull` with a real herring gull;
takeoff squawk replaced by a synthesized wingbeat. 58 inventory items given real
graphics (24 mapped free from the existing CC0 library, 34 generated + decimated
to 8k). Rod icon fixed — the 57-mesh rod was building fine but the icon camera
sized off the world diagonal, so a 1.90 m rod drew as ~1 px. Fish inventory
previews now scale to real length. Fauna seating: three gull perches at exactly
+750 mm, seal intersecting five colliders and a patrol clipping the pontoon.
World geometry: ceiling beacon, DANGER sign, splice label, crate/barrel overlap.
Ladders: three shipped with an inverted `face_dir()` making them impassable.

### s16 and earlier
See git log. Highlights: deep-sea rod graphic (57 meshes), snail marble shell
shader, Pyramid Snail species, Tripo swapped in as the default generator.

---

## Open / next

**Oarfish — text-to-3D has failed. Stop spending credits on it without a new
approach.** Nine rounds, 33+ generations across s16–s20, all rejected: early
rounds returned an ordinary round-bodied fish (the model has a strong prior
toward normal fish anatomy), later rounds got the ribbon body and the crest of
rays right but distorted the head every time — chunky/froggy, catfish barbels
and horns, one attempt produced what reads as two heads. The owner supplied a
reference photo mid-session; it clarified what to ask for (serpentine S-curve
pose, continuous low dorsal fringe rising into a separate crest, dark vertical
bar markings) but round 9, prompted directly from it, still failed on the face.
**Two paths forward, not attempted:** (1) image-to-3D from the reference photo
— blocked because the photo exists only in the chat session and nothing here
can read a chat image as a file; ask the owner to drop it in `~/SALTLINE/refs/`
and retry immediately. (2) Build it procedurally — this project already builds
far more complex procedural geometry than an oarfish needs (the fishing rod is
57 meshes) and it gives exact control over the three things generation keeps
failing: length, thinness, and the tail. Recommend (2) if (1) doesn't land.

- **Pyramid snail mesh** — `_cand5/pyr_{a,b,c}` generated but never judged; the
  species currently runs on procedural geometry.

**Known open bugs** — see `KNOWN_ISSUES.md`.

**Watch items:**
- The NaN guards in `fauna_move.gd` make a bad state *harmless and self-healing*
  rather than loud. If a creature is ever seen freezing or teleporting, that is
  the thread to pull — something upstream may still be producing NaN.
- Candidate meshes are accumulating under `assets/models/fauna/_cand*/`. Prune
  the rejected ones once the winners are installed.
