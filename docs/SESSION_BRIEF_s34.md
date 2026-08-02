# s34 SESSION BRIEF — owner-directed focus session

Written at the end of s33 as a handoff. The owner reviewed the s33 results and gave the
directions below. This file is the authority for what s34 does; where it conflicts with an
older plan or DEVLOG note, THIS file wins.

## Read first, non-negotiable

1. `CLAUDE.md` — how to run a session here (sonar first, batch verification, update the log).
2. `DEVLOG.md` — current state. Newest entries at the BOTTOM (s27 onward; the header says
   newest-first but recent sessions appended).
3. `docs/AGENT_TRAPS.md` — the expensive lessons. Do not re-learn them.
4. `KNOWN_ISSUES.md` — open bugs.

Working agreements that keep biting: probe, don't guess (never hand-type a Y); verify by
LOOKING at a rendered frame; measure, don't assert; **run the FULL TestRunner suite after
every change** (a s31 regression shipped because only targeted probes were run — see the
JellyGlow story in DEVLOG s33); commit verified work immediately; report honestly.

Generators: **Tripo has ~800 credits and is the default. Meshy has 4 credits — do not use
Meshy.** Key in `.env`. Prompt rules are in `docs/AGENT_TRAPS.md` ("Generated assets") and
they work — s31 went 11/11 first try. Log task ids at submit time.

## Owner decisions (verbatim intent, do not relitigate)

- **DIVE HITCH: DROP IT.** The owner accepts the current first-dive load ("takes a second the
  first time, then fine"). Do not build the warm-on-approach system. Close the KNOWN_ISSUES
  entry as "accepted by owner, s34" rather than leaving it open.
- **TIDES: KEEP.** No further debate needed.
- **The ten s33 design plans were rejected at review, but the owner's read is correct:** the
  flagged defects are ordinary engineering problems, not reasons to abandon the tasks. The
  plans live in the s33 workflow journal and are USEFUL AS RESEARCH — fix the flagged defect
  and execute, or redo from scratch if simpler. Do not treat "the plan was unsound" as "the
  task is hard". Declutter and reef-expansion in particular are simple tasks: go one by one,
  check each placement against the real geometry (sonar / probe), done.

## The work, in execution order

Order chosen so async generation runs while code work happens, visible bugs go first, and
the expensive windowed verification is batched at the end.

### 0. FIRST ACTION — kick off Tripo generation for the cat poses (async, ~15 min)

The cat needs distinct pose models (owner: "sitting, licking paw, running, sleeping, at
least, + whichever others are needed"). Current cat is ONE static mesh
(`assets/models/fauna/ship_cat/ship_cat.glb`, behaviour in `scripts/world/ship_cat.gd`).

Generate per-pose meshes via Tripo (text-to-3D, one per pose — same cat described in the
same words each time, only the pose clause changes, so the coat stays consistent):
`sit`, `groom` (licking a forepaw), `run` (full stride), `sleep` (curled), `walk`, plus keep
the existing standing mesh. Then swap meshes on state change and drive motion with the
existing vertex-shader animation (`creature_anim.gd` UNDULATE/pose drive — see how the crab
and gulls animate; Tripo's rigger is unverified for quadrupeds, do NOT depend on skeletal
clips). Decimate to the fauna budget with `tools/decimate_inplace.py` if a mesh arrives
huge; **after import, check the texture sidecars** — a headlessly generated texture imports
at `compress/mode=0` (uncompressed!) until fixed; set `compress/mode=2`,
`process/size_limit=1024` like every other fauna texture (this bit s33 for 872 MB of VRAM;
grep `^compress/mode=0` over assets after any import).

### 1. FISH REBALANCE — the spawn pattern under the rig broke with the 11 new species

Owner: "The fish generation got messed up under the rig with the new species... at least one
of the new grouper models is swimming backwards. Most of the grouper should be schooling.
I liked the previous fish array — all I want is a few extra appearances of the new species,
maybe substitute a few, but in general rebalance the fish spacing."

Concretely:
a. **The backwards grouper is a facing bug.** Generated meshes do NOT share a forward axis
   (AGENT_TRAPS: "measure it — correlate travel direction against the model's own local axes
   over a few hundred frames, then add a FACING_OVERRIDES entry" in
   `scripts/world/creature_anim.gd`). Do that measurement for ALL 11 new species in one
   harness run, not just the one the owner saw — a hammerhead once shipped swimming
   broadside because nobody checked. `tests/FacingShot.tscn` photographs along the live
   heading so a reversed mesh cannot pass.
b. **Restore the previous array's feel.** The 29 pre-s31 species and their counts were
   liked. The 11 new species were added at ~57 members/pod with other counts trimmed
   (fish.json history, commit cd42686). Rebalance: new species should be OCCASIONAL
   accents, not a third of the water. Groupers school in small tight groups near the legs
   (`water: near`), tunas pass through open water in schools, mahi near the surface. Check
   pod SPACING too — `_spawn_pod` spreads pods over POD_SPREAD; if the new pods crowd the
   under-rig volume, push them to the open-water pod ring.
c. Verify with CatchProbe (headless, catchability must stay green for all 40 species) and
   ONE windowed swim-through screenshot pass at the end (batch with step 5's).

### 2. WATER CLARITY + REMOVE THE LIGHT BEAMS — "this is a coral reef for christ's sake"

Owner: water reads hazier than before; the vertical light columns look bad; wants clearer
water so detail shows, and a balanced reef ecosystem look.

a. **Delete the god-ray shafts outright.** `underwater_fx.gd::_build_light_shafts()` (~line
   100-134), the `_shaft_mats` var, the per-frame uniform writes (~312), and
   `materials/light_shaft.gdshader`. 3 of the 4 leg shafts spawn INSIDE the solid caisson
   (verified s32) — they were never right. The s33 light-cone plan (workflow journal) has a
   verified inventory of every line to remove; its cone REPLACEMENT had a bad density
   derivation, so either fix that derivation against the real glow threshold or ship the
   removal alone first — removal alone is already the owner's minimum ask.
b. **Clarity: re-grade the fog.** The depth grade lives in `underwater_fx.gd::_process`
   (fog density lerp 0.028→MAX_DENS 0.19 over REACHABLE_DEPTH_M 13, plus storm murk).
   The reef band (y −8..−19) currently sits in the thick half. Lower the mid-band density
   so the reef reads at 10–15 m (try MAX_DENS ~0.12–0.14 and/or push the smoothstep knee
   deeper), keep the near-surface shimmer, keep the abyss ramp so the −92 floor stays
   hidden. **Sweep 3 candidate density curves off ONE windowed build** (the SpearShot /
   ReefShot re-expose trick — AGENT_TRAPS has the pattern) and pick by screenshot, not by
   feel. Note POD_RIM_ENERGY 0.75 / POD_BODY_GLOW 0.38 on shoal fish were tuned against the
   CURRENT fog — after clearing the water, re-check one frame that the fish don't now glow
   like lanterns; re-sweep those two constants down if needed.
c. The under-deck lights stay as-is unless time allows the PowerGrid wiring (nice-to-have;
   template: how rig_builder wires `topside_floodlights`).

### 3. SEAL — "when it rests on the foundation there's like a meter of room under it"

The owner is describing the RESTING seal, and is right even though `FaunaBugsProbe` reports
GAP +0.0 mm. Those two facts together mean the probe measures the wrong thing — probably
node origin / collider low point vs the VISIBLE MESH's low point after the rest-pose pitch
(`rotation.x = -0.12` chest-up) and the model's own pivot. Do what the owner says: when
seated, the seal should sit ON the surface like gravity holds it there.

Approach: at `_seat()`, compute the model's WORLD-space AABB low point in its actual seated
pose (windowed if MultiMesh is involved — it isn't, the seal is a plain mesh, so headless
AABB is honest) and drop the node until that low point touches the probed shelf y. Then fix
`FaunaBugsProbe` to assert on the MESH low point in pose, which is what the last session
thought it was asserting. Verify with one windowed screenshot of the basking seal from the
pontoon (batch with the others).

### 4. DECLUTTER THE STARTING WET DECK — simple, do it one prop at a time

Owner: clear the main walkway of uninteractable scenery. The s33 investigation (workflow
journal, `declutter` item) found the clutter is concentrated in two spots and the middle of
the forecourt is already clear:
- the SPHL hatch lane: a 0.9 m rusted drum 65% across the 1.6 m exit gap, a tire fender
  intersecting the gangplank, a bollard chain crossing at shin height (two of the three
  don't even collide — you walk through them);
- the caisson-foot turn: three mooring-chain links half-buried in the plating.

Its execution steps had placement errors (a relocation onto a DeckGull home at
(24.0, 2.0, −15.5), a hand-typed chain Y) — so DON'T reuse its coordinates. Rule: for each
prop, either DELETE it or relocate it to a spot verified empty with the sonar
placement-check recipe (`RIG_ATLAS.md` bottom) or a runtime probe, and keep it off fauna
homes (grep bloom_fauna for authored home/perch coordinates before choosing). Refresh the
scan afterward (`tools/export_rig.sh`). One windowed before/after pair from the spawn
vantage (batch with the others).

### 5. REEF EXPANSION — coral, kelp, plants, seabed (owner has asked three times; deliver)

Owner directions, standing: triple the coral, spaced DOWNWARD to expand the reef down the
supports; ocean floor 33% deeper with basic ground variation; more seaweed/kelp diversity
and deeper; plants ROOTED INTO THE WALL and ANGLED OUT.

The s33 plan's research is sound on the numbers, its steps had two real defects. Use the
research, avoid the defects:
- **Downward is correct and cheap.** The placement rule saturates against density in the
  existing band (3x attempts → only 2x instances) but NOT against depth: extend the band
  downward (currently bottoms ~−19; take it toward the new floor) and add instances there.
  The s32 distance cull (REEF_DRAW_M 55 / FADE 18 on the reef MultiMeshes) is what makes
  this affordable; spot-check draw stats at `submerged_deep` after.
- **Seabed deeper + variation:** `scripts/world/seabed.gd`. −23 → ~−30 (33%). Add low-freq
  height noise; keep it BELOW the abyss fog ramp so the floor stays unseen from the
  surface. Re-check anything that references the floor depth (grep for -23 / seabed
  constants; `reef_detail.gd` landmarks sit on the old floor and must move with it).
- **Rooting:** plants on caisson faces must seat by RAYCAST to the face, orient their
  growth axis along the hit NORMAL (tilted out 20–45° per species, world-up projected into
  the face plane for the climb direction — see the PyramidSnail heading trap), never
  world-up off a vertical wall. The s33 defect to avoid: a kelp rooted shallow on a leg
  face can breach the waterline / punch the pontoon — clamp root sites to y < −2.5 and
  check the grown TIP stays under the trough floor for surface-adjacent placements.
- **Kelp diversity:** 2–3 new kelp/seaweed forms (procedural like the existing strands is
  fine — colour/height/blade variation), extend depth range down the legs.
- Exclude fauna colliders from every placement raycast (`BloomFauna.fauna_bodies` skip
  list — the ReefProbe corruption trap).
- Verify: ReefProbe (windowed for instance transforms — headless reads identity!), then
  the batched screenshot pass: reef at 3 depths, kelp, a rooted-plant closeup.

### 6. CAT STATES — make it feel alive (models from step 0 should be back by now)

`scripts/world/ship_cat.gd` currently: found in bunkhouse → hello → follows, sits when the
player stops, closes in when a fish is held. Owner wants real STATES with per-state models
and intuitive interactivity.

State machine (extend, don't rewrite — the follow/edge-probe/AiBudget bones are correct and
probe-verified in `tests/CatProbe.tscn`):
- IDLE_SIT / GROOM (licking paw — its found-state and its default when the player lingers)
- FOLLOW (walk mesh + gait bob) breaking into RUN (run mesh) when > ~8 m behind
- SLEEP: when the player sleeps in a bed or sits long at a comfort spot, the cat curls up
  NEARBY (on the bed's foot, a chair, a warm spot — probe a seat, don't hand-type)
- FISH INTEREST: already exists (closes in when fish held) — extend: feeding it a raw fish
  once per game day gives a small REST/comfort bonus and a happy-wiggle (mirror the seal's
  `_pet_bump` / `_fed` pattern in bloom_fauna, and the comfort_furniture comfort hooks)
- PET: [E] on the cat → brief head-bump animation + purr audio (`tools/gen_audio.py`
  synthesises; see gen_crab_audio.py for the pattern) — already half-exists via the hello
  interactable; make it repeatable.
Swap meshes via `ANIM.replace` — REMEMBER: overlay meshes built BEFORE `ANIM.replace` are
hidden (trap file); build after. Each state change re-runs the deck probe so a sleeping
cat can't be left floating when furniture moves. Extend CatProbe: one assertion per state
transition, plus the completion sentinel pattern every probe now uses.

### 7. CLOSE OUT

- Full suite: TestRunner + CatchProbe + CatProbe + SpearProbe + TideProbe + SunkProbe +
  SealApproachProbe + FaunaBugsProbe (fixed) + ReefProbe. All green.
- ONE batched windowed screenshot session covering: fish rebalance swim-through, cleared
  water at the reef, basking seal, decluttered spawn walkway, expanded reef/kelp, cat in
  each state. Read every PNG back before claiming it.
- Update DEVLOG (append, dated s34), KNOWN_ISSUES (close dive-hitch as owner-accepted;
  sweep for staleness while in there), AGENT_TRAPS (anything new that bit).
- Commit per completed item, not one mega-commit at the end.

## Standing traps most likely to bite THIS session

- MultiMesh transforms are IDENTITY under --headless — reef verification must be windowed.
- `ANIM.replace()` hides meshes built before it.
- A probe that dies mid-coroutine still prints FAILURES: 0 — use the completion sentinel.
- Headlessly imported textures land at compress/mode=0 — check after every generation.
- underwater_world only swims schools while VISIBLE — dive the camera before measuring fish.
- Sweep look-tuning values off ONE windowed build, never across separate launches.
- The pause menu auto-pauses on focus-out and the panel survives unpausing — harness boilerplate.
