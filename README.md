# SALTLINE — v0.1 "First Night" vertical slice

First-person survival/mystery on an abandoned North Atlantic oil rig. One rig, one
in-game day: wake sealed in a hyperbaric lifeboat at dawn, climb the rig, scavenge,
restore one light circuit, survive the night, see the sunrise.

## Run
Open the project in **Godot 4.x** (4.7 tested) and press Play, or:

```sh
godot --path . 
```

## Controls
WASD move · mouse look · Shift sprint · **Space jump** · **Ctrl crouch** (half height,
slower, quieter, harder for creatures to detect) · **E interact** (context verb, also
grab/set down props) · **hold E on a ladder to climb** (E alone climbs up, E+S climbs
down, release to let go) · LMB throw a carried prop · **1–4 select an item to hand;
same number again eats/drinks/uses it** · **I inventory** · **J journal** · **H help** ·
**F throw the rigging hook** · Esc pause/settings

**Survival** — four bars, bottom-left: LIFE, HUNGER, THIRST, WARMTH. Eat for hunger,
drink water rations for thirst; starving or dehydration drains life, creature contact
hits it hard, fed + watered heals it back. Raw glow worms make you SICK — sneak up
crouched to grab one at night, then sear it at a rigging bench. Crates open a two-way
exchange panel (move items either direction, or TAKE ALL).

**The stack** — the accommodation block above the topside deck: ramp up from the deck
(follow QUARTERS ↑) to Deck B quarters, then the internal stairwell to Deck C control,
Deck D works (second rigging bench in the workshop), and the roof mast deck.

**Crafting** — E at the wet-deck rigging bench (or the Deck D workshop bench): click
parts from your pack to lay them on the bench; when they match a recipe, hold WORK
(or Space) to hammer it real. Partial layouts show what the parts *want* to become
and what's still missing.

**Building** — B with a crafted kit in your pack: ghost preview snapped to the deck
grid · LMB place · R rotate · Tab/scroll cycle kits · B/Esc done. Bloom lamps make
real crab-safe light; lean-tos make warmth; walkways extend the rig itself.

Debug keys: F1 next phase · F2 toggle power · F3 infinite stats · F4/F5 teleport ·
F6 toggle 20x time

## Verify
```sh
godot --headless res://tests/TestRunner.tscn   # 29-check integration test
godot --headless res://tests/SoakTest.tscn     # full day loop at 20x (~2.5 min)
godot res://tests/VerbRoom.tscn                # walkable verb demo room
godot res://tests/Screenshot.tscn              # renders vantage PNGs to /tmp
python3 tools/gen_audio.py                     # regenerate placeholder audio
```

Design canon: `SALTLINE_GDD.md` (not in repo yet) · slice scope: the v0.1 build brief.
Tunables: `TUNING.md` · caveats: `KNOWN_ISSUES.md`.
