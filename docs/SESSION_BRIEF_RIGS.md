# SESSION BRIEF — THE FIELD: three new rigs (owner-approved work order)

> Paste the "Opening prompt" block at the bottom into a fresh session. Everything above it is
> the plan; everything in it is the instruction.

---

## 0. What this is

SALTLINE has one rig. This brief adds **three**, turning a single platform into a **field** —
a bridge-linked complex plus one isolated drilling platform standing over the Bloom fissure.

The owner's words, verbatim, because they are the acceptance criteria:

- *"I want them to be closer and more in view than they are now."*
- *"The 3 new rigs have new items, rooms, purposes/specialities. The last rig is the one with the huge drill above the Bloom fissure."*
- *"The 3rd rig should have a massive aquarium in the lunch area, 2 stories tall. Player can activate electricity and filters, and then use the aquarium to store their own fish that they catch. Rig three should be a large, residential/luxury rig, this was the more public spacing one, with large helicopter pad. The captains/guests staid on this rig, no drilling took place."*
- *"2nd rig is industrial/farming. There is a large rooftop ex-vegetable garden, where player can tend soil, and in a later update grow crops etc."*
- *"I want lots of unique areas, cool visuals, and places to fish. Lots of overviews, overpasses, irregular design, but taking inspiration from epic large oil rigs."*

---

## 1. THE BINDING CONSTRAINT IS DRAW CALLS, AND IT IS NOT CLOSE

Read this before designing anything. **This is the decision that kills the project if it is got wrong**, and it is not a triangle problem.

Measured, on file in `KNOWN_ISSUES.md` and `DEVLOG.md`:

| | measured |
|---|---|
| worst topside vantage (`wet_deck_stand`) | **30.56 ms / 32.7 fps / 2,861 draws / 3.42 M primitives** |
| worst underwater vantage | **38.1–39.4 ms / 14.1–14.3 M prims** |
| the existing rig | **855,644 tris / 715 manifest props** |
| pelagic schools | 37.09 M tris, 1,033 fish, 83 pods |
| reef | 12.55 M tris, 2,747 instances |

The game is **already at 26–33 fps at its worst vantages with ONE rig**. Four rigs naively in
view is on the order of **11,000 draw calls**. The rig's 855 k tris are almost irrelevant next
to the schools' 37 M — **draws and per-frame GDScript are the wall, not geometry.**

### Therefore: a rig LOD tier is not an optimisation to add later. It is the feature.

Design it first, build it before the second rig exists, and prove it on the EXISTING rig
before any new geometry is authored. Two precedents in this codebase already do exactly this
and both are measured and working — copy their shape, do not invent:

- **`leg_reef.REEF_DRAW_M = 55.0`** with an 18 m fade, over 70 MultiMeshes. This is what makes
  a 12.55 M-tri reef affordable: a diver pays for the slice around them, not the column.
- **`underwater_world._cull_topside()` / `TOPSIDE_MARGIN = 2.8`** — a whole subtree flipped by
  a height test.

**Three tiers, minimum:**

| tier | when | what is built |
|---|---|---|
| **RESIDENT** | the rig the player is standing on (+ any bridge they are on) | everything: interiors, props, colliders, fauna, harvest nodes |
| **NEIGHBOUR** | bridge-linked, in view, not occupied | exterior shell, decks, rails, silhouette. **No interiors, no props, no interior colliders.** |
| **HORIZON** | beyond the bridge cluster | a single batched impostor: legs, deck slab, derrick, flare. One draw call if you can manage it. |

Note `mesh_batcher.gd`, `rig_batcher.gd` and `render_budget.gd` already exist (18/11/7
functions) — the batching machinery is there. `RenderBudget` already drops shadow casters
("[budget] meshes budgeted: 7322 shadow casters dropped: 3861").

**A HARD GATE ON THIS PHASE:** before authoring rig 2, stand at `wet_deck_stand` with the LOD
system in and a *stub* neighbour rig placed, and measure. If draws rise more than ~15% over
the 2,861 baseline, the tier system is wrong and no amount of art will save it later.

### Sightlines and fog are a second, coupled cost
`main.gd:208` notes the current fog/silhouette setup is tuned around **45 m** ("45 m still
covers the whole deck you can stand on"). Making three rigs "more in view" means pushing the
useful sightline to **150 m+**, which changes the atmosphere grade AND exposes far geometry
every frame. Re-grade the fog deliberately and re-run `tests/FogShot.tscn`; do not just raise
a number. The North Sea look — rigs half-dissolved in weather (see the owner's first
reference image) — is your friend here: **fog is both the mood and the occlusion budget.**

---

## 2. ARCHITECTURE: a module kit, not a fourth copy of `rig_builder.gd`

Current authoring code is **7,685 lines** across `rig_builder.gd` (4,533),
`rig_superstructure.gd` (1,594), `structures.gd` (995) and `rig_exterior.gd` (563) — all
hand-authored absolute positions for ONE rig.

`CLAUDE.md` states the project's philosophy: *"the rig is built in code … positions in those
scripts ARE the level design."* **Keep that.** Do not build a procedural rig generator — it
will produce four identical boring platforms and destroy the hand-placed quality that makes
the existing rig read as real.

**The correct middle:**

1. **Extract a module kit** from what already exists — `structure_lib.gd` (12 funcs),
   `stair_kit.gd`, `prop_lib.gd` (18), plus new module builders for: leg/caisson, deck slab,
   accommodation block, stair tower, catwalk/overpass, flare boom, derrick, helipad, crane,
   boat landing, **bridge span**. Each takes an origin + dimensions and builds *relative* to it.
2. **One composition script per rig** — `rig_two.gd`, `rig_three.gd`, `rig_four.gd` — each
   hand-authoring its own layout in LOCAL coordinates, then parented to a rig root placed in
   world space. Local coordinates matter: it is what lets a rig be moved, re-oriented, LOD'd
   and scanned independently.
3. **Do NOT refactor `rig_builder.gd` into the kit in the same session as building new rigs.**
   That is how you break the shipping rig. Extract modules *additively*, leave rig 1 alone,
   and only migrate it later once three rigs prove the kit.

### Coordinate contract
Every existing tool is keyed to world coordinates: the sonar scan, `tools/export_rig.sh`, the
save system's position-keyed harvest nodes (`save_manager._harvest_key()` is
`"%.2f,%.2f,%.2f"` of `global_position`), `AiBudget`, `Gyre.swim_line`. Rigs must sit at
**fixed, deterministic world offsets** — never runtime-randomised — or harvest state will not
round-trip. Give each rig a named constant origin and derive everything from it.

---

## 3. THE FIELD — world layout

Existing rig footprint: **x[−30, 30], z[−20, 20]**, topside y 18, wet deck y 2, boat landing
y −3…1, stack roof y 32, derrick/crane to y 52, caissons `LEG_SIZE (6, 109, 6)` from y 17
down to y −92.

Real inspiration: **Ekofisk and Brent** were bridge-linked complexes — several platforms in
sight of each other, joined by 100–150 m walkways. The owner's second reference image is
exactly this: a bridge running off to a separate flare tower.

### OWNER DECISIONS — SETTLED, DO NOT RE-OPEN

1. **BRIDGES, not boats.** The field is bridge-linked. Bridges start damaged and repairing a
   span is the progression gate.
2. **RIG 1 STAYS EXACTLY AS IT IS.** SALTLINE-0 keeps its derrick, its layout, everything. Do
   not "improve" it, do not rebalance it against the new rigs, and do not refactor
   `rig_builder.gd` while adding them. It is the shipping rig and the known-good reference.
3. **RIG 4 IS EVENLY SPACED, NOT DISTANT.** The four rigs form a roughly even field rather
   than a tight cluster plus one far outlier. Rig 4 is still the last one reached and still the
   dramatic one, but it sits at a comparable spacing to the others — close enough to read
   properly, not a speck on the horizon. See the revised layout below.

**Proposed layout** (final numbers to be probed, not hand-typed — see §7):

An even field, roughly 180–220 m between neighbours — a real North Sea complex, all four
legible from each other in clear weather. A shallow arc rather than a square: a square reads
as a game level, an arc reads as a field that grew one platform at a time.

```
        RIG 2 — MARROW                                RIG 3 — THE ANCHORAGE
        industrial / farming                          residential / luxury
        origin ~(-190, 0, -70)                        origin ~(200, 0, -40)
                  \                                         /
                   \  bridge ~195 m                        /  bridge ~205 m
                    \                                     /
                     ●───────────  SALTLINE-0  ──────────●
                                  (existing, 0,0,0)
                                  UNCHANGED
                                        │
                                        │  bridge ~200 m  (the LAST span repaired)
                                        │
                              RIG 4 — DEEPWELL
                              the Bloom drill
                              origin ~(20, 0, 200)
```

**Why this shape:**

- **All four are bridge-linked** at ~180–220 m — close enough to be legible from each other's
  decks, which is the owner's "closer and more in view", and close enough that a bridge span
  is structurally plausible (real Ekofisk/Brent bridges ran 100–150 m; 200 m is a stretch but
  a defensible one for a fictional field, and the sag/truss depth should show it).
- **Bridges are the progression gate.** Every span starts damaged. Repairing one is a
  substantial build-and-salvage goal, and it lets the owner control the order the field is
  discovered in without a single invisible wall.
- **Rig 4 is still last, but by BRIDGE ORDER, not by distance.** Its span is the longest,
  worst-damaged and most expensive to repair — so it looms in full view from hour one, clearly
  reachable in principle and clearly not yet. That is a stronger tension than putting it out of
  sight, and it costs a NEIGHBOUR-tier shell instead of a horizon impostor.
- **The Bloom glow does the distance work.** Rig 4 needs no extra separation to feel other:
  teal light coming up out of the water under one platform and no other will read from every
  deck in the field.
- Vary the **bearing and elevation** so the skyline is never symmetric. Rig 3 sits higher
  (taller accommodation stack); rig 2 sits lower and broader (industrial); rig 4 is the tallest
  thing in the world by a wide margin.
- **Perf consequence of an even field, and it is the big one:** with four rigs at ~200 m and
  sightlines to match, THREE NEIGHBOURS CAN BE IN FRAME AT ONCE from a high deck. That is the
  worst case the LOD tiers in §1 must survive, and it is the frame to measure — not a
  comfortable one at deck level. Budget for it from the start.

---

## 4. RIG BRIEFS

Common to all three — the owner asked for *"lots of unique areas, cool visuals, and places to
fish. Lots of overviews, overpasses, irregular design."* Translate that into rules:

- **Every rig gets at least 3 distinct fishing spots** at different heights and water types
  (a low boat-landing spot, a mid-deck spot over open water, a high spot). The catch table
  already supports this: `water: near|open` keys off distance from the rig rim, so a spot
  cantilevered out over open water genuinely fishes differently. **Check `docs/FISHING_BALANCE.md`** for
  the live pool before choosing.
- **Irregular by construction:** no rig should be a rectangle. Cantilever decks past the legs,
  set the accommodation block off-axis, run catwalks at diagonals, put one deck at a half
  level. The existing rig's `deck B/C/D at 21.6 / 25.1 / 28.6` is a good rhythm to break
  rather than repeat.
- **Overviews:** each rig needs one place you climb to and look back over the field. The
  existing `ops_lookout` at y 38 is the model.
- **Verticality:** the reference images are all about the stack of decks under the topside —
  the underslung pipework, the boat landing far below, the legs vanishing into the swell.

### RIG 2 — "MARROW" · industrial / farming

The working platform. Grimy, functional, the one that kept the field alive.

| | |
|---|---|
| **Hero feature** | **The rooftop garden.** A large ex-vegetable garden on the accommodation roof — raised beds, a collapsed polytunnel, frost-cracked soil, a dead irrigation ring. Sea-blasted and abandoned, but recoverable. |
| **Rooms** | Hydroponics bay · seed store / cold vault · fertiliser & chemical store · pump hall · grain/feed silo · mess with a long steel table · workshop-scale machine shop (bigger than rig 1's) · water treatment |
| **New items** | Seed packets (several crop types) · soil sample kit · trowel/hoe · fertiliser sacks · grow lamps · watering can · irrigation pipe · compost |
| **System to build now** | **Soil tending.** Player can clear, till and water beds. Beds hold state (untilled / tilled / watered / planted) and persist through the save. Growing crops is explicitly a LATER update — *build the soil substrate and the interaction, leave the growth curve stubbed but designed for.* |
| **Fishing** | A low working deck near the waterline by the pump intakes (`water: near`); a long cantilevered pipe rack over open water (`water: open`). |
| **Visual notes** | Rust-streaked, utilitarian, sodium-lit. Broad and low. Big external pipework, a cargo crane, stacked containers. This is the rig that looks like the owner's **third reference image** — heavy machinery lit at dusk. |

### RIG 3 — "THE ANCHORAGE" · residential / luxury

Where the captains and guests stayed. **No drilling.** Corporate, once-comfortable, now
salt-ruined. The tonal opposite of rig 2 — and the contrast is the point.

| | |
|---|---|
| **Hero feature** | **The two-storey aquarium in the lunch area.** See §5 — this is a real system, not set dressing. |
| **Rooms** | Two-storey mess/lunch hall wrapped around the aquarium · guest cabins (better than rig 1's bunks — real beds, private heads) · captain's suite · briefing/boardroom with a field map · lounge/bar · gym · cinema/rec room · library · medical suite · **large helipad** (the owner asked for this explicitly — make it genuinely large, with the painted circle, perimeter netting, floodlights, a windsock, and a wrecked helicopter *or* a conspicuously empty pad) |
| **New items** | Guest keycards · wine/spirits · records · board games · a captain's log (readable) · brass fittings · good cutlery · fish food · aquarium filter cartridges · a fuse/breaker for the aquarium circuit |
| **Fishing** | An elegant railed promenade deck over open water · a sheltered spot under the helipad overhang · a low luxury boat landing with a davit. |
| **Visual notes** | Painted white/cream superstructure like the accommodation block in the **first reference image**. Big windows (now salt-frosted and cracked), carpet, wood veneer, all of it water-damaged. The luxury reading *dead* is what sells it. |

### RIG 4 — "DEEPWELL" · the Bloom drill

The endgame. A massive drilling platform standing directly over the Bloom fissure. This is the
one the player sees on the horizon from hour one.

| | |
|---|---|
| **Hero feature** | **The drill.** Enormous — taller and heavier than rig 1's derrick, which reaches y 52. This should read as industrial-sacrilegious: a machine that went too deep. Consider y 80–100 for the crown block. |
| **Rooms** | Drill floor · mud pits & shaker house · BOP deck · core sample lab (the story lives here) · containment/decon airlock · a control room with the last shift's readouts frozen mid-alarm · **the moon pool**, open to the fissure below |
| **The fissure** | The Bloom glow should come *up through* the rig — light from below through grating, in the moon pool, along the legs. Coupled to the existing `underwater_world` Bloom palette so it is the same phenomenon, not a separate effect. |
| **New items** | Core samples · drill bits · containment canisters · hazmat gear · the research readables that explain the Bloom |
| **Fishing** | Deliberately strange. This is the natural home for the **deep-drop rig** and the rarest species — the existing deep pool (`drop_m` 20–44, `fish_fathom_sturgeon` at 44 m) is currently one-species-dominated per band (`KNOWN_ISSUES` records Abyss Grenadier at 66.2% at 24 m). **Rig 4 is the opportunity to fix that** by giving the fissure its own species set. |
| **Visual notes** | Silhouette first — it must read at ~200 m as the tallest thing in the world by a clear margin. Heavy, black, over-scaled, with the Bloom teal bleeding up out of the water beneath it. Since it is now bridge-linked and in full view from hour one (owner decision 3), it carries the skyline: it should be the thing the eye goes to from every other deck. |
| **Gating** | Its bridge span is the longest, worst-damaged and most expensive to repair, so it is reached LAST by cost rather than by distance. Design the wrecked span to be visible and legible from rig 1 — the player should be able to see exactly what is broken and want to fix it. |

---

## 5. THE AQUARIUM — the one genuinely new system

Owner: *"a massive aquarium in the lunch area, 2 stories tall. Player can activate electricity
and filters, and then use the aquarium to store their own fish that they catch."*

This is a **storage container with a viewing pane**, and the codebase already has every part:

- **Container storage** — `loot_container.gd` now carries `items` **plus a parallel
  `item_meta`** array (added s52 so crates preserve per-fish weight). An aquarium is a
  container with a species filter. **Per-fish weight already round-trips**, so a stored 41 kg
  grouper stays a 41 kg grouper.
- **Live fish rendering** — do NOT write a new fish renderer. `underwater_world`'s schools are
  one `Node3D` per fish with a swim shader, and `reef_fish.gd` has the small-shoal version
  with per-station phase variants. The aquarium is a tiny bounded version of a reef station.
  Budget it: 10–20 fish maximum, and remember 11 pelagic species are **undecimated at
  109 k–198 k tris each** (`KNOWN_ISSUES`) — a tank full of leopard grouper is 2 M tris in one
  room. **Cap by triangle count, not fish count.**
- **Power** — `PowerGrid.is_powered("topside_floodlights")` is the existing pattern; add an
  aquarium circuit. `FishTable.context()` already reads `PowerGrid`.
- **Filters** — a consumable + a condition state. Unfiltered water should degrade and
  eventually kill/expel stock; this gives the player a reason to keep visiting.

**Design it as a real reward loop:** a place to *display* trophies, not just store them. It
should show the fish at its actual landed size — `ItemVisual.fish_instance_length_m()` already
renders a dropped fish at the real body length its weight implies.

**Two storeys tall means the player sees it from both levels** — from the mess floor looking
up, and from a gallery looking down into it. That is the shot. Build the room around the view.

---

## 6. TRIPO — what to generate and what not to

The owner has Tripo access (`.claude/skills/realistic-animals/`, key in `.env`). Notes from
hard experience in this repo:

- **Tripo returns ~500,000 triangles per mesh.** The median whole animal here is 31 k. A 20 cm
  coil of rope once arrived costing 16× a shark. **Decimate everything, and measure before
  wiring anything in.**
- `tests/CandShot.tscn` photographs a raw GLB straight off disk — **judge every candidate this
  way before it enters the tree.**
- **MEASURE FACING.** `creature_anim.gd`'s facing table exists because one Tripo batch came
  back in *three different conventions*. `tools/measure_facing.py` checks it headless.
- **Do not generate what a box can do.** Rig structure — decks, rails, stairs, pipework — is
  better and cheaper as authored CSG/boxes. Reserve Tripo for **hero props**: the wrecked
  helicopter, the aquarium's coral/rockwork, the drill crown block, garden beds, the captain's
  furniture, laboratory equipment.
- Seven existing fish already ship with **zero materials** (s15 Meshy preview meshes) and are
  covered by `materials/fish_skin.gdshader`. Regenerating those seven is a drop-in with no
  code change — a cheap win if the generator is being used anyway.

---

## 7. NON-NEGOTIABLES (this repo enforces them, and they have all cost hours)

1. **PROBE, DON'T GUESS. Never hand-type a Y coordinate.** Every floating-prop bug in this repo
   traces to an authored constant that drifted. In s52, **three of four kelp stands were found
   growing in mid-air** and the fourth was sealed under a deck slab — all four were hand-typed.
2. **Lead with sonar.** `scene_brief` first, then `props_find` / `spatial_probe`. Wired via
   `.mcp.json`. Regenerate after building with `tools/export_rig.sh` — **and the new rigs must
   be added to that export**, or the spatial oracle goes stale and silently wrong.
3. **Verify by looking.** Render it, read the PNG back, iterate, *then* report. Screenshot
   harnesses must run **WINDOWED** — `--headless` never draws.
   **Watch for this exact trap:** `beta1_shot`'s `sphl_interior` shot spent months
   photographing an *exterior wall* — a twice-reported visual defect had never appeared in any
   frame anyone checked. Also, `_place()` moves the PLAYER and the eye rides **~1.6 m above its
   feet**, so a camera argument is a FLOOR position.
4. **Measure, don't assert.** Numbers, not impressions.
5. **Batch the verification.** One import and one render pass per *batch* of changes.
   Repeatedly relaunching Godot lags and crashes the owner's machine.
6. **Commit verified work immediately.** Sessions have been lost.
7. **Report honestly.** Blocked and partial work gets said out loud.
8. Keep `DEVLOG.md`, `KNOWN_ISSUES.md` and `docs/AGENT_TRAPS.md` current — that upkeep is the
   whole reason the next session is cheap.

---

## 8. SUGGESTED PHASE ORDER

Do **not** try to build three rigs in one session.

| phase | deliverable | gate |
|---|---|---|
| **A** | Rig-LOD tier system + fog/sightline re-grade, proven on the EXISTING rig with a stub neighbour | draws at `wet_deck_stand` rise <15% over 2,861 |
| **B** | Module kit extracted additively (leg, deck, block, catwalk, bridge, helipad). Rig 1 untouched. | rig 1 renders byte-identical; TestRunner FAILURES: 0 |
| **C** | Rig 2 MARROW shell + bridge from rig 1 + the soil-tending system | walkable end to end, probed seating, perf gate holds |
| **D** | Rig 3 THE ANCHORAGE shell + helipad + **the aquarium system** | a caught fish can be stored, displayed and retrieved across a save |
| **E** | Rig 4 DEEPWELL + the fissure + the deep species set | reads at 400 m; deep pool no longer one-species-per-band |
| **F** | Interiors, props, readables, fishing spots, polish pass across all three | screenshot pass, owner review |

---

## OPENING PROMPT — paste this into the new session

> Read `docs/SESSION_BRIEF_RIGS.md` FIRST — it is the complete work order for this chapter.
> Then read `CLAUDE.md`, the last ~200 lines of `DEVLOG.md` (entries append at the BOTTOM),
> `docs/AGENT_TRAPS.md`, and `KNOWN_ISSUES.md`.
>
> The project is the Godot 4 game at **`~/SALTLINE`** (NOT `~/Desktop/SALTLINE` — a macOS TCC
> denial blocks shell access to Desktop). GitHub remote is **MasonSpeh/SALTLINE**, already
> authenticated via `gh`; push after each verified commit.
>
> **We are adding three rigs to the one that exists, turning the world into a bridge-linked
> field of four, evenly spaced at ~180-220 m.** Rig 2 is industrial/farming with a rooftop
> ex-vegetable garden the player can tend. Rig 3 is a residential/luxury platform — no
> drilling, big helipad, and a two-storey aquarium in the lunch hall that the player powers up,
> filters, and stocks with fish they catch. Rig 4 is the huge drill standing over the Bloom
> fissure — in full view from everywhere and reached LAST because its bridge span is the
> longest and worst-wrecked, not because it is far away.
>
> **THREE OWNER DECISIONS ARE SETTLED — do not re-open them:** bridges rather than boats;
> **RIG 1 STAYS EXACTLY AS IT IS** (do not improve, rebalance or refactor it); and rig 4 is
> evenly spaced with the rest rather than a distant outlier.
>
> **START WITH PHASE A, AND DO NOT SKIP IT.** The binding constraint on this entire chapter is
> DRAW CALLS, not art: the game already runs at 30.56 ms / 2,861 draws / 32.7 fps at its worst
> topside vantage with ONE rig. Build the three-tier rig LOD system (RESIDENT / NEIGHBOUR /
> HORIZON) and prove it on the EXISTING rig with a stub neighbour placed, before authoring any
> new geometry. Copy the shape of the two culling systems that already work and are measured:
> `leg_reef.REEF_DRAW_M` (55 m + 18 m fade over 70 MultiMeshes) and
> `underwater_world._cull_topside()`. If draws rise more than ~15% over baseline, stop and
> redesign — no amount of art recovers from getting this wrong.
>
> Do NOT write a procedural rig generator, and do NOT refactor `rig_builder.gd` while adding
> rigs. Extract a module kit ADDITIVELY and give each new rig its own hand-authored
> composition script in LOCAL coordinates under a placed rig root.
>
> Probe every coordinate — in s52 three of four kelp stands were found growing in mid-air
> because someone hand-typed a Y. Lead with sonar (`scene_brief`, then `props_find` /
> `spatial_probe`), and add the new rigs to `tools/export_rig.sh` so the scan does not go
> stale. Render windowed and READ THE FRAME BACK before claiming any visual result.
>
> Run `godot --headless --path . res://tests/TestRunner.tscn` before each commit and keep it at
> FAILURES: 0.
