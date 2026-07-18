# Prompting for a game-ready animal mesh

The generator gives you what you describe. For a model that rigs and animates cleanly and
drops into SALTLINE, the prompt has to fight three default failure modes: dramatic poses,
scene clutter, and stylization.

## Template

> a [size] [animal], [material/colour/texture], [distinguishing features], **photoreal,
> neutral standing/T pose, legs slightly apart, full body visible, symmetrical, plain
> background, single subject, no base, no ground plane**

## Rules that matter for rigging + import

- **Neutral pose.** "Standing, legs slightly apart, neutral pose." A curled/leaping animal
  auto-rigs badly and clips through itself when animated.
- **Full body, single subject.** "full body, one animal, plain background." Kills extra
  props, terrain chunks, and duplicated limbs that wreck the skeleton.
- **Symmetry.** "symmetrical" helps the auto-rigger find a clean spine + paired limbs.
- **No base / no ground.** Generators love to weld the animal to a rock or plinth — say
  "no base, no ground plane, floating" so you get just the animal.
- **Real materials, not "cute/lowpoly/cartoon."** Say "photoreal, PBR, detailed skin/chitin/fur."
- **Reference image beats text** for likeness — pass `--image`. A clear side-or-3/4 photo of
  the real animal in a neutral stance gives dramatically better anatomy than words.

## SALTLINE species starters

- **lamplight_crab** — "a large deep-sea crab, mottled dark olive-brown chitin, long jointed
  walking legs, two raised pincer claws, one glowing bioluminescent lure on a thin stalk
  above the shell, photoreal, neutral pose legs apart, full body, symmetrical, plain
  background, no base." Animate: `walk idle`.
- **harbor_seal** — "a harbor seal, sleek wet grey-spotted fur, streamlined body, front and
  rear flippers, whiskered face, photoreal, neutral resting pose, full body, plain
  background, no base." Animate: `swim idle` (and a haul-out `rest`).
- **hammerhead** — "a hammerhead shark, grey dorsal white belly, wide flat cephalofoil head,
  tall dorsal fin, photoreal, neutral straight swimming pose, full body, plain background."
  Animate: `swim`.
- **gull** — "a herring gull, white body grey wings folded, yellow beak, photoreal, standing
  neutral pose, full body, plain background, no base." Animate: `idle` + a wings-out `fly`.
- **lamp_eel / jelly / whale** — same recipe; for the jelly ask for "translucent bell,
  trailing tentacles" and expect to keep a lot of the existing shader glow.

## Iterate cheaply

Generate the **preview** first (fast, low credits), eyeball the silhouette, and only
**refine + animate** the one you like. If the anatomy is wrong, fix the prompt or switch to
`--image` before spending credits on textures + animation.
