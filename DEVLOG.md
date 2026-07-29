# SALTLINE — development log

**Read this first in a new session.** It is the current state of the project and
what is in flight. `docs/AGENT_TRAPS.md` is the other required read — it is the
list of things that have already cost hours here.

Newest first. One entry per working session. Keep entries short: what changed,
what it revealed, what is still open. Detail belongs in the commit message; this
is the index.

---

## Current state

- **Branch:** `main`, HEAD `6c91486` (s18).
- **Engine:** Godot 4.7, `gl_compatibility`. macOS.
- **Tests:** `godot --headless --path . res://tests/TestRunner.tscn` → 223 pass,
  `FAILURES: 0`. Keep it there.
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

**Blocked on nothing — ready to pick up:**
- **Reef decoration** — 3 starfish + 10-piece coral palette generated (round 8);
  needs decimation, then scatter placement over the foundation and down the legs
  starting below the grass vegetation. Bulk decoration ⇒ decimate first.
- **Oarfish** — 6 branches generated from the owner-approved `oarX_4` silhouette
  (kept: ribbon body + the tall crest of separate rays; targeted: face and lower
  fin realism). Needs judging, then install as `fish_giant_oarfish`.
- **Pyramid snail mesh** — `_cand5/pyr_{a,b,c}` generated but never judged; the
  species currently runs on procedural geometry.

**Known open bugs** — see `KNOWN_ISSUES.md`.

**Watch items:**
- The NaN guards in `fauna_move.gd` make a bad state *harmless and self-healing*
  rather than loud. If a creature is ever seen freezing or teleporting, that is
  the thread to pull — something upstream may still be producing NaN.
- Candidate meshes are accumulating under `assets/models/fauna/_cand*/`. Prune
  the rejected ones once the winners are installed.
