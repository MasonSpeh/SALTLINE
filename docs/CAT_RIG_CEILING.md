# The cat rig's ceiling — what animation cannot fix, and what a re-rig buys

The ship-cat's procedural animator (`scripts/world/cat_rig.gd`) drives the one Tripo
auto-rigged skeleton in `assets/models/fauna/_rigged/cat_stand_idle.glb`: 41 humanoid-named
joints fitted to a cat, measured hinges, analytic foot-lock IK. Everything below is a limit
of that ASSET, not of the animator — each one has been measured, worked around as far as the
mesh allows, and is listed here so a future re-rig decision can be made on payoffs rather
than re-diagnosis.

Ranked by what fixing it would buy:

## 1. A real caudal tail chain (payoff: the loudest body-language channel)

The auto-rig has no tail bones. `tests/CatTailDiag` measured where the tail's 29,363
vertices actually went: onto **`R_ThighTwist01`**, a child of the right thigh, whose weights
cover the rump AND the tail as one block. Consequences, all shipped-around:

- One rigid paddle. No wave can travel down a tail that is a single bone: base-led lag,
  curl, tip flick, bottle-brush are all inexpressible. The spring drive (carriage + lag +
  overshoot, `cat_rig.tick` 5b) is the ceiling of what one bone can say.
- Amplitude capped at `TAIL_MAX = 0.30 rad`, because past that the bone visibly bends the
  hindquarters with it (the rump vertices are the same bone). Set by render, not taste.
- The bone is a CHILD of the right hind leg, so the gait would drag the tail once per
  stride; the animator counter-rotates it out per frame (exact parent-frame solve).

A re-skin cannot be avoided by appending virtual bones at runtime: new bones carry no
vertex weights, so they move nothing. **Re-rig ask:** 4–6 caudal bones, rump weights left
on the pelvis. Unlocks the full tail vocabulary — the one channel this animal has.

## 2. Ear bones + eyelid blendshapes (payoff: a face)

The mesh has immobile ears and painted-on pupils; there are no eyelid blendshapes and no
jaw bone. Ear flicks, the slow blink (the single most endearing thing a cat does at a
person), and a real chatter are all unreachable — the shipped chatter is a small head
tremor, which reads correctly at deck distance but is a substitute. Nothing procedural can
fake a blink on a mesh with no lids; we deliberately do not try (a deforming face without
face geometry is worse than a still one). **Re-rig ask:** 2 ear bones per side, `blink`
and `half_blink` blendshapes, optionally a jaw bone.

## 3. Symmetric limb bones, one shared rest pose (payoff: the gallop)

Measured on this fit (`tests/BoneDump`, `tests/CatYawDiag` PART 4):

- `L_Thigh -> L_Calf` is **0.336 m** against `R_Thigh -> R_Calf` at **0.086 m** — the
  right femur is a quarter of the left, because the auto-rig stretched that chain
  backwards to cover the tail (item 1 is the same defect seen from the other side).
- The left hind is DEAD STRAIGHT in bind pose (hip-to-paw 0.214 m from bones summing
  0.214 m), so it sits on the edge of its own reachable set: at a gallop the spine engine
  swings the hip sockets, that leg runs out of reach first, and the hind reach ratio
  measures **0.67** (walk is symmetric to ~1% — the asymmetry only bites at full stretch).
- `R_Upperarm`'s local X is ~90° off its opposite number (0.005 m/rad of paw travel vs
  0.198). The animator derives every hinge from geometry now, so this costs nothing at
  runtime — but it is why no hand-authored sign map ever worked.

**Re-rig ask:** left/right bones mirrored to the millimetre, knees slightly flexed in the
bind pose. Unlocks a symmetric gallop and removes a whole class of per-limb compensation.

## 4. The three sibling GLBs are three different meshes (payoff: none — solved, listed for history)

`cat_stand_idle.glb`, the walk and the run GLBs carry three different meshes with three
different baked rest poses and disagreeing inverse-bind matrices on all 41 joints; their
animation clips are humanoid presets. That is why the clips are stopped at attach and every
pose is authored on THIS skeleton's rest (s37's lesson: rotations only mean something on
the skeleton they were measured on). A re-rig does not need to fix this — the one-skeleton
architecture already did — but any future asset drop must not resurrect clip playback.

---

**If a re-rig happens:** re-run `tests/CatTailDiag` (the tail bone name is a measured
constant), `tests/BoneDump`, `tests/CatAxisDiag`, and `tests/CatYawDiag` before authoring
anything; `cat_rig.gd` re-derives hinges, gains and stride from whatever skeleton it is
handed, so most of the animator carries over unchanged.
