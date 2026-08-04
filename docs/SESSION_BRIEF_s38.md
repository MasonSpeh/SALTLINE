# SESSION BRIEF s38 — cat animation polish (owner-approved work order)

## Paste this as the opening prompt of the new session

> Read `docs/SESSION_BRIEF_s38.md` FIRST — it is the complete work order and carries the
> context you need to start immediately. Then read `CLAUDE.md`, the last ~150 lines of
> `DEVLOG.md` (entries append at the BOTTOM), the "Found rebuilding the cat as one
> skeleton (s37)" section of `docs/AGENT_TRAPS.md`, and `KNOWN_ISSUES.md`.
>
> The project is the Godot 4 game at **`~/SALTLINE`** (NOT `~/Desktop/SALTLINE` — a macOS
> TCC denial blocks shell access to Desktop). GitHub remote is **MasonSpeh/SALTLINE**,
> already authenticated via `gh`; push after each verified commit.
>
> Work the flaw list below in order. Every claim must be verified by RENDERING and reading
> the frame back before you report it. Run `godot --headless --path . res://tests/TestRunner.tscn`
> and `res://tests/CatProbe.tscn` before each commit.

## First command to run (proves the toolchain and shows you the current cat)

```bash
cd ~/SALTLINE && godot --path . tests/CatFilm.tscn -- /tmp/film && ls /tmp/film | head
```

That films the live cat on the open main deck in daylight: behaviour beats (walk, sit,
gallop, cross, settle) then a directed pose showcase (sit, groom, stretch, sleep, stand),
one PNG per film frame plus per-frame telemetry. **Read the frames back.**

---

## Where the cat is right now (end of s37)

**Architecture: ONE mesh, ONE skeleton, every pose blended.** The pose-per-mesh design is
gone — six meshes swapped by a visibility flip was a whole-body teleport at every state
change, which is why three sessions of polish never made it fluid.

| file | what it is |
|---|---|
| `scripts/world/cat_rig.gd` | **The animation core.** Pose library (FK offsets from rest; legs solved by hinge-constrained CCD IK at bake time), per-bone slerp blending, keyframed gait cycles (lateral-sequence walk / rotary gallop + spine engine), breath, look. Blend state is `_cur_q`/`_cur_hip`; additive layers compose into a per-frame `_out` and are **never** written back — that separation was bought with a shipped bug. |
| `scripts/world/ship_cat.gd` | **Behaviour.** States GROOM/FOLLOW/RUN/SIT/SLEEP/FISH/PET/JUMP, volume-based movement clearance, per-frame re-seat, sticky sleep spot, jump arc. Calls `rig.tick(dt, speed, moved)` once per frame. |
| `assets/models/fauna/_rigged/cat_stand_idle.glb` | The one body: neutral standing mesh, 41-bone Tripo rig. `custom_aabb` is set at attach — hand-driven skeletons corrupt the auto cull box and the animal vanishes from clear line of sight without it. |
| `tests/CatFilm.tscn` | **The instrument that settles arguments.** World-fixed-bearing tracking camera, staged on probed open deck, per-frame telemetry (pose, drawn pitch, up_y, node vs drawn head bearing). |
| `tests/CatBlendShot.tscn` | Pose stills (incl. a rear-view sit), transition strips, walk + gallop gait strips, with a floor. |
| `tests/CatAxisDiag.tscn` | The axis atlas — one bone, one axis, +0.6 rad per frame. **Re-render before authoring any new pose. Do not guess signs.** |
| `tests/CatProbe.tscn` | Headless assertions incl. burial sweep and the continuity bound (worst paw step < 150 mm/frame). |
| `tests/DeckFind.tscn` | Sweeps the topside for open, unroofed, clear deck. Used to stage the film. |

### Facts that must not be re-learned (long form in AGENT_TRAPS)
- **Pose transfer across auto-rig fits does not work** — shared bone names ≠ shared joint frames.
- **Additive layers must never write blend state** — shipped as a permanent ~30° rear-up and a measured 75° body yaw (the owner's "walks sideways / horror movie").
- **A per-tick `+=` without a delta term** reaches rate-ratio equilibrium, not zero.
- **Axis facts:** `Hip +X` pitches the body; `Thigh +X` folds a hind leg forward; `Calf +X` flexes the knee BACK; the upperarms are MIRRORED left/right.
- **Rays starting inside CSG report nothing** — two camera placements were "probed clear" through solid furniture.
- **Pin the clock AND storm every frame** in any long harness, or a squall rolls in and the back half films at night in the rain.

### Verified state at s37 close
Walk/gallop head-first (node and drawn agree), level (0–8° pitch), no roll (up_y 1.00),
no accumulation. Continuity: worst paw step 84 mm/frame (bound 150). Burial: 0/180 samples.
TestRunner FAILURES: 0, CatProbe FAILURES: 0 twice consecutively.

---

## The flaw list — work top to bottom

1. **The walk is still choppy** (owner-confirmed, latest film). Suspects in order:
   (a) **the instrument may be part of it** — the film captures at 8 fps with 5 sim frames
   per film frame; capture at 30 fps before judging anything else;
   (b) FOLLOW's blend rate (10.0) may pop the first strides — try easing `_gait_w` in more
   slowly; (c) the cycle tables may want one more in-between key at mid-stance;
   (d) `_gait_w`'s `moved/dt` term quantises at low speed. **Measure per-frame joint deltas
   across a walk start before changing any number.**
2. **Sit from behind: the hind legs trail instead of tucking.** `_bake`'s `+0.13 X` paw
   shift on the hinds did not move them — either the IK cannot reach from its seed, or the
   shift axis is wrong for the hind chain. Check `pose_sit_rear.png` in CatBlendShot.
3. **No runtime foot-lock.** Paws drift on turns and in-place rotation. `_ik_leg` already
   exists for bake time; a cheap runtime variant would pin only the 1–2 stance-phase paws
   per frame, 2 CCD iterations each.
4. **Turn-in-place is a turntable.** `_face` lerps yaw with the feet planted. Add a small
   step-in-place gait tick while yaw delta is large and speed ≈ 0.
5. **The tail is unboned** (Tripo's template ends at the pelvis) and rides the hip. Tail is
   a large part of cat body language — worth one honest attempt (appended bone chain, or a
   shader-bent cone).
6. **The stretch pose exists but no behaviour plays it.** Play it on wake from SLEEP
   (sleep → stretch → stand over ~2 s) and occasionally after long sits.
7. **The jump has never been filmed.** The state exists (rises 0.62–1.25 m trigger it).
   Add a film beat that lures the cat onto a crate and verify the arc and pose.
8. **Groom reads oddly from above** (owner, s36). Re-judge after 1–2.
9. **The showcase drives poses with the state machine off.** If CatFilm stays a permanent
   instrument (it should), move the beat list to script arguments.
10. **CatProbe has an intermittent failure — roughly 1 run in 6.** Observed once at the s37
    close; six consecutive re-runs then passed, so the failing assertion was not captured.
    It is most likely the sleep/settle branch (timing-dependent: the cat has to walk to a
    chosen spot inside a fixed frame budget). **Do not dismiss it as noise** — this repo has
    twice found a real defect behind an "intermittent" probe, most recently the sleep spot
    that could oscillate forever. Run it in a loop of 20 capturing the FAIL line, then fix
    the cause rather than widening the window.

## Rules of engagement
- **Render, read back, then claim.** The s37 "sleeping cat" frame that went out unread was
  the cat inside a wall.
- **Measure before authoring** — axis atlas for any new bone work.
- One windowed Godot at a time; batch verification; commit per completed item; push after each.
- The suite must stay green: the cat shares `creature_anim.gd` with every other animal, and
  `attach_rigged`/`custom_aabb` affect all future rigged species.
