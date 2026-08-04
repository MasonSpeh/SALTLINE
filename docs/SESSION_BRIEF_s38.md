# SESSION BRIEF s38 — cat animation polish (owner-approved work order)

**Paste-ready opening prompt for the new session:**

> Read `docs/SESSION_BRIEF_s38.md` FIRST — it is the complete work order and carries the
> full context. Then read `CLAUDE.md`, the LAST ~150 lines of `DEVLOG.md` (entries are
> appended at the bottom), the "Found rebuilding the cat" and "s37" sections of
> `docs/AGENT_TRAPS.md`, and `KNOWN_ISSUES.md`. The project is the Godot 4 game at
> `~/SALTLINE` (NOT ~/Desktop — TCC blocks Desktop). GitHub: MasonSpeh/SALTLINE, push
> after each verified commit. Work the flaw list in the brief top to bottom, one item at
> a time, verified by RENDERING before claiming anything.

---

## Where the cat stands after s37 (2026-08-03)

The cat is **ONE mesh, ONE skeleton, every pose blended** — the pose-per-mesh design is
gone. Know these files cold before touching anything:

| file | what it is |
|---|---|
| `scripts/world/cat_rig.gd` | THE ANIMATION CORE. Pose library (FK offsets from rest, legs solved by hinged-CCD IK at bake time), per-bone slerp blending, keyframed gait cycles (lateral walk / rotary gallop with a spine engine), breath, look. All state in `_cur_q`/`_cur_hip`; additive layers compose into `_out` per frame and are NEVER stored — that separation was bought with a shipped bug. |
| `scripts/world/ship_cat.gd` | Behaviour: states (GROOM/FOLLOW/RUN/SIT/SLEEP/FISH/PET/JUMP), volume-based movement clearance (`_step_clear` + slide), per-frame `_unbury`, sticky sleep spot, jump arc. Calls `rig.tick(dt, speed, moved)` once per frame. |
| `assets/models/fauna/_rigged/cat_stand_idle.glb` | The ONE body: neutral standing mesh, 41-bone Tripo rig, `custom_aabb` grown at attach (hand-driven skeletons corrupt the auto cull box — animal vanished from clear line of sight without it). |
| `tests/CatFilm.tscn` | **THE INSTRUMENT THAT SETTLES ARGUMENTS.** World-fixed-bearing tracking camera films the live cat: behaviour beats + directed pose showcase, one PNG per film frame + per-frame telemetry (pose, pitch, up_y, node vs drawn head bearing). Run `godot --path . tests/CatFilm.tscn -- /tmp/film` and READ THE FRAMES BACK. |
| `tests/CatBlendShot.tscn` | Pose stills + transition strips + walk/gallop gait strips on the raw rigged mesh, with a floor. Includes the rear-view sit. |
| `tests/CatAxisDiag.tscn` | The axis atlas: one bone, one axis, +0.6 rad per frame. Re-render before authoring any new pose — do not guess signs. |
| `tests/CatProbe.tscn` | Headless assertions incl. body-volume burial sweep and the continuity bound (worst paw step < 150 mm/frame — discriminates teleport from legitimate gallop speed). |

**Hard-won facts that must not be re-learned** (long form in AGENT_TRAPS):
pose transfer across auto-rig fits does NOT work (joint frames differ — sit arrived 70%,
sleep candy-wrapped); additive layers must never write blend state (shipped as a
permanent ~30° rear + measured 75° body yaw — the owner's "walks sideways / horror");
a per-tick `+=` without delta on an eased value reaches rate-ratio equilibrium;
`Hip +X` pitches the body, `Thigh +X` folds a hind leg forward, `Calf +X` flexes the
knee BACK, upperarms are MIRRORED L/R; rays/point queries starting inside CSG report
nothing (two camera framings were "probed clear" through this hole); the film camera must
derive its position per frame at world-fixed bearings with a clearance ray.

## The flaw list (owner-reviewed, work top to bottom)

1. **Walk is "still choppy."** Owner-confirmed on the latest film. Suspects, in order:
   (a) the film itself is 12 fps with 5 sim frames per film frame — capture at 30+ fps
   before judging anything else, the choppiness may be partly the instrument;
   (b) blend rate on FOLLOW entry (10.0) may pop the first strides — consider easing
   gait_w in slower; (c) the cycle keys may need one more in-between key at
   stance-mid; (d) `_gait_w`'s `moved/dt` term quantises at low speed. Measure per-frame
   joint deltas across a walk start before changing numbers.
2. **Sit from behind: hind legs trail instead of tucking.** `_bake`'s paw_shift
   `+0.13 X` on the hinds did NOT move them — either the IK cannot reach the target from
   its seed (add knee-fold seed before solving, or shift the target less far), or the
   anchor shift axis is wrong for the hind chain. Verify with `pose_sit_rear.png` in
   CatBlendShot. The owner suspects mesh-generation ambiguity from the rear — if the
   tuck cannot be made to read, consider a rear-specific silhouette fix (tail overlay?)
   or accept and document.
3. **No runtime foot-lock.** Paws drift on turns and during in-place rotation. The
   pose-bake IK exists (`_ik_leg`) — a cheap runtime variant: pin stance-phase paws to
   their world spots during the gait (only the 1-2 stance legs per frame, 2 CCD
   iterations each).
4. **Turn-in-place looks like a turntable.** `_face` lerps yaw while feet are planted.
   Add a small step-in-place gait tick while yaw delta is large and speed ~0.
5. **The tail is unboned** (Tripo's template ends at the pelvis) and rides the hip.
   Options: procedural tail as an attached bone chain built at attach time (own
   Skeleton3D appended? heavy), a shader-bent tail cone, or accept. The tail is a large
   part of cat body language — worth one honest attempt.
6. **Stretch pose exists but no behaviour plays it.** Play it on wake from SLEEP
   (blend sleep→stretch→stand over ~2 s) and occasionally after long sits.
7. **Jump was never filmed.** The state exists (rise 0.62–1.25 m triggers it). Build a
   film beat that lures the cat over a crate; verify the arc and the jump pose read.
8. **Groom from top-down reads odd** (owner, s36). Lower priority; re-judge on film
   after 1–2.
9. **CatFilm's showcase section** drives poses with the state machine off — if the film
   is kept as a permanent instrument (do), move the beat list to script args.

## Rules of engagement (unchanged, they are why the last three sessions converged)

- **Render, read back, then claim.** No exceptions — the s37 "sleeping" frame that went
  out unread was the cat inside a wall.
- **Measure before authoring** — axis atlas for any new bone work; telemetry
  (pitch/up_y/bearings) is already in the film log.
- One windowed Godot at a time; batch verification; TestRunner + CatProbe before every
  commit; commit per completed item; push to GitHub (MasonSpeh/SALTLINE) after each.
- The full suite must stay green — the cat shares `creature_anim.gd` with every other
  animal; `attach_rigged`/`custom_aabb` changes touch all future rigged species.

## Current verified state (so you know what "regressed" means)

- Walk/gallop: head-first (node & drawn agree, film log), level (+0-8° pitch walking),
  no roll (up_y 1.00), no accumulation (bone deltas from rest ≈ authored values only).
- Continuity: worst paw step 84 mm/frame through live transitions (bound 150).
- Burial sweep: 0/180 samples inside geometry, worst 0 mm.
- TestRunner FAILURES: 0, CatProbe FAILURES: 0 (twice consecutively) as of s37 close.
