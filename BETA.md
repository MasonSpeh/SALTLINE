# SALTLINE — Playable Beta (v0.2-beta)

First-person survival on an abandoned North Sea oil rig, in an ocean the Bloom has
mutated into cold teal light. Wake in the survival capsule, get the power back before
dark, and learn to live on the rig — because the thing that walks at night keeps to the
shadows, and the light is yours to build.

## Running it

Open the project in Godot 4.7 (compatibility renderer) and press Play, or run a build.
It boots straight into the start screen; a save is written and restored automatically.

## The first hour

1. **Open the hatch** ([E]) and step onto the wet deck.
2. **Find the cable spool**, splice the **burned cable gap** ([E], needs the spool), then
   climb the stair tower and **throw Master Breaker 4-A** in the breaker room. The
   objective line tells you where to go at each step.
3. Powered floodlights make a **safe circle of light**. When night falls, stay lit — the
   Lamplight Crabs hunt the dark, but they honor real light, including the Bloom lamps you
   craft.
4. After that it opens up: fish, cook, salvage the rig for materials, and **build a camp**
   — a bedroll under a tarp with a brazier burning is a place to come back to.

## Controls

| | |
|---|---|
| **Move** | WASD · Shift sprint · Space jump |
| **Posture** | Ctrl (hold) crouch — slow, quiet · Z lie flat on the deck |
| **Interact / Take** | E |
| **Carry props** | E grabs · LMB throws · E or G sets down |
| **Hotbar** | 1–4 to hand · same number again eats/drinks it |
| **Inventory** | I — click items to move them between pack and hotbar |
| **Journal** | J — discoveries, item notes, craft hints |
| **Fish / Hook** | fishing rod from the hotbar · F throws the rigging hook |
| **Craft** | E at the rigging bench — lay parts on it, hold WORK / Space |
| **Build** | B — LMB place · R rotate · Tab next kit · B done |
| **Pause / Options** | Esc — volume, sensitivity, and audio toggles |

## What's in the beta

- **The rig**: wet deck, SPHL survival capsule, galley, bunkhouse, rec room, machine
  shop, a switchback stair tower up to a glass ops lookout, an exterior crane whose boom
  reaches out over the water, and a dressed exterior deck.
- **Survival loop**: hunger, thirst, warmth, life, and rest; eat found food, drink,
  shelter, and sleep.
- **Fishing & cooking**: 20 catchable species with their own 3-D models, rod and drop-net,
  a galley stove that sears each fish into its own named meal.
- **Base building**: ~18 placeable structures (bedroll, brazier, locker, workbench, rain
  catcher, lamp post, shelves, walls, rugs…) crafted from a salvage economy — dismantle
  the rig's dead gear for materials at the bench.
- **Storage**: lockers, crates and cabinets you can stash items in; stacks up to 16.
- **The Bloom**: 30+ AI-generated creatures — the night crab and a mutated four-eyed
  hammerhead, plus seals, gulls, rays, an eel, jellies, four kinds of snail, a reef of
  corals, sponges, nudibranchs, an octopus and more, each animated in the water.
- **Weather**: storms roll through with rain that falls everywhere outdoors and through
  every window, but never indoors; audio shifts under cover by roof type and distance.
- **Sky & sea**: Gerstner ocean swell, a star field with atmospheric extinction and a
  Milky Way, a day/night cycle, and an underwater world with a sculpted seabed and wreck
  field to dive.

## Verification (this build)

- Boots clean: 0 script/parse errors over a 400-frame run.
- **111 integration tests pass**, 0 failures — the full core loop (power puzzle, night
  crab, build mode, fishing, cooking, save/load) is exercised, not just compiled.
- Acceptance probes all green: placement (0 floating / 0 blocking props), stair-walk
  (every route climbable, no trap), label anchoring, doorframe alignment, snail
  wandering, and the end-to-end fauna/inventory checks.
- Frame rate on the compatibility renderer: **~53 fps on deck, ~40 at sea level** after a
  draw-call reduction pass (down from 30/21).

## Known issues (beta-honest)

- **Frame rate is playable, not locked 60.** The compat renderer draws one call per mesh
  surface per shadow split; batching cut draw calls ~66%, but the remaining per-primitive
  cost is the ceiling without further mesh-merging work. Expect 40–55 fps, dipping at sea
  level in a storm.
- **Underwater fidelity is uneven.** Depth-graded water, caustics on the caissons and a
  Snell's-window surface are in, but directly sun-lit rig surfaces can still read a touch
  bright for their depth, and the diving polish is the least-tested area. (The god-ray
  light shafts were removed in s34 — three of the four spawned inside the solid concrete.)
- **Fauna motion is vertex-shader animation, not skeletal rigging.** Creatures swim, flap,
  scuttle and pulse convincingly at gameplay distance; legged animals bend as a whole
  rather than at joints, so they won't hold up to a close inspection.
- This is a beta: expect rough edges in balance and the occasional misplaced prop.
