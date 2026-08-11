# Atrium / Oceanarium finish pass — s59 review package

Captures in this folder are the current build (`FieldShot --only=atrium` + `s56_colonnade`).
Every acceptance number below is raw probe output, not a summary judgement.

## A. Fish — DONE, gated
- **A1 tank facing.** Root cause by construction: `FishModelLib` models face **+Z**, the old
  swimmer code aimed `look_at` (**−Z**) along the travel tangent — every stocked fish swam
  tail-first (the mahi report). The new orientation aims +Z along velocity, eased with bank.
  Gate (AquariumSwimProbe, 30 s sim, 2,160 samples): **mean(head·velocity) = 0.993** (gate 0.9).
  *Deferred:* the world/reef-path species audit via `tools/measure_facing.py` — the tank path is
  proven; the reef/pelagic paths were not re-measured this session.
- **A2 real swimming.** `aquarium_stock._process` is agents now: per-fish wander (schooling
  species share a species clock so shoals drift as one body), same-species boids
  (align 1.5 / cohere 0.4 / separate), size behaviour (big fish cruise the open mid-lane slowly,
  small fish hug core and bed), analytic glass/core/surface/bed avoidance. Raw gates: worst
  radius **4.45** vs glass 5.00 (margin gate 4.60) · nearest core pass **1.86** (core 2.05 soft) ·
  water-column excursion **0.000** · school alignment **0.556** (gate 0.5) · min pair gap
  **0.56 m** (gate 0.25). O(n²) over ≤ ~40 fish at cap; no physics queries.
- **A3 capacity.** `MAX_TOTAL_M = 30.48` (100 ft). `MAX_ONE_M = 2.4384` (**8 ft**): the swim
  annulus between core clearance (~2.0 m) and glass margin (~4.7 m) is 2.7 m wide — an 8 ft fish
  keeps better than a body length of lane and a ~21 m mid-lane circuit; 10 ft would fill its lane.
  *Not yet captured:* the biggest-allowed-fish circulation clip.

## B. Tank decoration — DONE at the procedural tier
- Reef BED: 34 scattered pieces (golden-angle jitter, denser toward the core) — fingers, fans,
  domes, rocks in the reef palette + crust tones. CORE: 9 encrusting patches up the rock so it
  reads grown-over. LIGHT: 6 warm lenses under the crown + a faint teal bed ring.
  Added cost ≈ **~120 primitives**, baked into the existing tank chunks.
- *Deferred:* Tripo hero rockwork (the brief's reef-library import is a bigger lift; the
  current pass is richer procedural massing, judged in `field_atrium_tank_base_looking_up.png`).
  Water/glass materials untouched this pass (no z-fighting observed at any gallery height —
  the 0.13 m inset holds; see the g3/spur captures).

## C. Architecture — verified where instrumented, partly deferred
- C1/C2: RigFieldProbe **FAILURES: 0** — 58+ flights, every stair foot/head on real floor,
  every climb line clear, both helices arrive through the s56 ring openings (see
  `field_s56_atrium_openings_up.png` and `field_atrium_chord_stairs.png` for the flush joins).
- *Deferred:* C3 (gallery → roof-deck and → neighbour-building connections) and C4 (food-court
  stalls/signage beyond the existing dining + lounge fit-out). Both need a layout decision
  (which bays to pierce) that is worth an owner look first.

## D. Corner-wedge + crouch-death — PATCHED (two of three layers)
- Wedge escape: when the stuck detector finds only opposing wall faces (a true V), the body
  moves along the corner's **outward bisector** to the nearest candidate that is unoccupied
  AND has floor within 1.4 m below — it can never be shoved through steel or off the rim.
- Crouch clamp: the controller tracks the floor last STOOD on; while crouched/prone and not
  genuinely swimming, any drop >0.3 m below that floor is treated as the wedge slip — the body
  is restored to its floor and the escape runs. A crouch in a corner can no longer put the
  capsule into the sea band under the deck, which was the death.
- *Deferred:* D3 (chamfer/kick-plate at the rail-post source) and the automated multi-fence
  wedge probe — the patch is code-verified and parse/TestRunner-clean but not yet driven by a
  dedicated harness. Flagged as the top follow-up.

## E. The "two bulky lamps" — IDENTIFIED from the owner's photo, replaced everywhere
The photo shows a dark-green cone on a grey cylinder: these were the two-primitive PLANTERS
(pot + cone) from the s56 pass — around the tank saucer, at the drum portals, on the terrace
and in the pool hall. They read as giant lampshades at close range. All four site families now
build `_planter()`: a low ribbed bowl, soil, slim trunk and six individual fronds (~10 prims).
No lights were attached to the old props, so no relight was needed. Cone-planter count in
rig_three after the sweep: **0**.

## Gates at close
TestRunner **0** · RigFieldProbe **0** · AquariumSaveProbe **0** (stock contract intact) ·
AquariumSwimProbe **0** (all numbers above).

**awaiting human review.**

## s59b addendum (owner's "actually do the work" round)
- **Spawn + kit:** game starts on THE ANCHORAGE's south arrival mat (respawn too); 12
  survival takeables placed rig-1-style across five levels, including two fishing rods
  (promenade + marina). TestRunner's spawn row rewritten to assert the NEW design.
- **B for real:** hero tier in the tank — 11 branching coral trees to 2.2 m, 8 sea fans
  to 1.8 m, 8 barrel heads, a 9-strand full-height kelp curtain, 4 barnacle collars with
  studs, 6 glowing anemone beds (~190 prims). Every colour REUSES an existing material
  instance: the far-chunk budget sat at exactly 150/150 and each novel colour was +1
  chunk (measured, 159/150, fixed). Judged in field_atrium_tank_base_looking_up.png.
- **C3 done:** G1 west bay -> terrace stair (the "2nd floor" is G1, 0.5 m under the roof
  deck); G2 west bay -> catwalk + door into the WEST tower's upper storey (mirror of
  s55's east link). Climb audit green.
- **C4 done (Sonnet subagent):** three stalls + menu panels + cafe arc + lounge panel and
  planters, 70 prims, radius rules respected. field_s59b_food_court.png.
- **Probe lesson recorded:** the field probe's seat ray was reading the top of the
  PLAYER's own capsule at the new spawn (23.80) — skip list added, the repo's standing
  rule, newly earned by the spawn move.
Gates: TestRunner 0 · RigFieldProbe 0 (chunks 217/220, far 150/150) · AquariumSwimProbe 0.
Still deferred: Tripo hero rockwork (budget), world-path facing audit, wedge harness.

**awaiting human review.**
