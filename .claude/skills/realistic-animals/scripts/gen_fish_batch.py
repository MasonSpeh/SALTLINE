#!/usr/bin/env python3
"""Generate a 3-D model for EVERY catchable fish in data/fish.json, plus the upgraded
hammerhead — in PARALLEL (6 concurrent Meshy jobs) because 21 sequential generations
would take ~3 hours.

Prompts are hand-written per species from the fish table's name + note, all in the
Bloom's mutated Avatar aesthetic. Resumable: skips slugs whose .glb already exists.
"""
from __future__ import annotations
import json
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_animal import load_key, meshy_text_to_3d, download_glb  # noqa: E402

OUT = Path("assets/models/fauna")

STYLE = (", photoreal cinematic creature design, Avatar Pandora bioluminescent "
         "aesthetic, single subject, full body, plain background, no base, no plinth, "
         "no ground plane")
POSE = ", straight neutral swimming pose"

# ---------------------------------------------------------------------------
# s15 (2026-07-26): the fourteen species the fish table gained after the first
# batch shipped. The owner's direction for THIS wave is explicitly NOT the
# Pandora look above: "a grim North-Sea/deep-trench setting — the fish should
# read as real, plausible marine animals, not bright tropical cartoons." So
# they get their own style tail. Bioluminescence appears only where the fish
# table's own note demands it (the dragonfish's lure, the dogfish's lit belly)
# and stays a small cold light on an otherwise drab animal.
#
# The negatives are all scar tissue from earlier waves: Meshy will happily
# invent a display PLINTH under a subject, and will bed a bottom-dweller into a
# patch of rock/coral that then travels with the mesh into the player's hand.
#
# KEEP THE WHOLE PROMPT UNDER 600 CHARACTERS. Meshy's text-to-3d caps the prompt there
# and does NOT error on a longer one — it truncates, which silently eats the negatives
# at the tail and hands back a fish on a display plinth. The first two of this wave went
# out at ~730 chars before that was caught.
NORTH_SEA = (", photoreal REAL fish, wet skin, drab muted North Atlantic colouring, cold "
             "grey light, single subject, whole body, side profile, plain background, "
             "no base, no plinth, no ground, no rock, no coral, no hands, "
             "not cartoon, not tropical")
# Held straight and level: the shader's UNDULATE body wave and the movement code's
# look_at both assume the animal was authored as one straight line nose-to-tail. A
# model frozen mid-curve swims like a banana forever.
NPOSE = ", stretched out straight and level in a neutral horizontal swimming pose"

FISH: dict[str, str] = {
    "fish_copper_sprat":
        "a tiny slender alien sprat fish, burnished copper scales, a line of faint "
        "teal spark dots along the flank, delicate translucent fins" + POSE,
    "fish_herring":
        "a slender silver alien herring, a row of small glowing teal lantern orbs "
        "along its lateral line, translucent fins, luminous eye" + POSE,
    "fish_slate_cod":
        "a heavy-bodied alien cod, slate-grey stone-mottled hide like wet rock, a pale "
        "chin barbel with a softly glowing teal tip, big honest mouth, thick fins" + POSE,
    "fish_mirrorjack":
        "a sleek fast alien jack fish, chrome MIRROR scales like polished metal "
        "reflecting rainbow iridescence, deeply forked tail, long trailing fin "
        "filaments" + POSE,
    "fish_chimefish":
        "a delicate translucent alien fish with a bell-shaped glassy body, fins shaped "
        "like hanging glass chimes, a glowing pearl core visible inside, ethereal" + POSE,
    "fish_silver_ladder":
        "an elongated silver alien fish patterned with glowing ladder-rung stripes of "
        "faint teal down its whole length, slim ribbon fins" + POSE,
    "fish_ember_snapper":
        "a stocky alien snapper, dark charcoal back, warm EMBER-ORANGE glow smoldering "
        "from its gill plates and belly like coals inside, sturdy fins" + POSE,
    "fish_sable_hake":
        "a long velvet-black alien hake, sable sheen, faint teal underglow along the "
        "belly, oversized moth-like reflective eyes" + POSE,
    "fish_ghost_sole":
        "a flat alien sole fish, near-transparent ghostly body with faint pearl "
        "outlines of its organs showing through, both eyes on one side, pale" + POSE,
    "fish_glasspike":
        "a long alien pike with a completely transparent glass body, its glowing teal "
        "spine and organs clearly visible inside, needle teeth, predatory profile" + POSE,
    "fish_lodestone_bream":
        "a deep-bodied alien bream, iron-dark scales with small magnetite crystal "
        "growths, faint blue arc-light glimmers between the crystals" + POSE,
    "fish_drum_croaker":
        "a barrel-chested alien croaker fish, storm-grey with lightning-pale bands, a "
        "drum-taut glowing throat sac, blunt powerful head" + POSE,
    "fish_inkwell_squid":
        "an alien squid, ink-black mantle with a luminous teal sheen like wet ink, "
        "large intelligent eye, trailing webbed arms, mantle fins" + POSE,
    "fish_ribbon_eel":
        "a long alien ribbon eel, dark body with crackling static-blue filaments "
        "running its length, flowing ribbon dorsal fin, stretched straight" + POSE,
    "fish_barrel_grouper":
        "a huge heavy alien grouper, barrel body, massive underslung maw, mottled "
        "bronze-green hide, thick ragged fins, ancient and strong" + POSE,
    "fish_stone_crab":
        "a heavy alien crab with a ceramic-hard granite-textured shell like carved "
        "stone, thick blunt claws, short stony legs, neutral standing pose",
    "fish_gutter_prawn":
        "a pearly translucent alien prawn, glowing orange roe visible through its "
        "shell, long antennae, delicate swimming legs, curled neutral pose",
    "fish_miller_flounder":
        "a flat alien flounder camouflaged in a RUSTED STEEL DIAMOND-PLATE tread "
        "pattern like an oil rig deck, both eyes up, ragged fin fringe, lying flat "
        "neutral pose",
    "fish_fathom_halibut":
        "a door-sized colossal alien halibut, abyssal dark topside, pale glowing "
        "underside, ancient scarred hide, huge and flat and slow" + POSE,
    "the_looker":
        "a pale smooth deep-sea alien fish with ONE enormous forward-facing "
        "human-like eye filling most of its head, faint white glow, unsettling and "
        "serene, small trailing fins" + POSE,
    # The hammerhead, evolved: the Bloom kept working on it.
    "ultra_hammerhead":
        "a massive mutated alien hammerhead shark, wide flat cephalofoil with FOUR "
        "glowing eyes, two on each end of the hammer, TALL twin dorsal fins, extra "
        "oversized sweeping pectoral fins with trailing luminous filaments, deep "
        "indigo-violet body laced with branching teal vein glow, pearl belly, "
        "iridescent edge light" + POSE,
}

# s15 wave, listed in the order the owner asked for them: the shallow rod-and-net
# species the player meets every day first, then the deep-drop pool, then the rarities.
# Credits are finite (84 on the account the day this ran, ~15 a model), so the ORDER IS
# THE BUDGET — whatever the balance covers gets spent on what shows up most on screen.
NEW_FISH: dict[str, str] = {
    # ---- tier 1: shallow, rod + net, seen constantly ----
    "fish_bilge_blenny":
        "a small ugly blenny fish, blunt rounded head with bulging eyes set high, thick "
        "fleshy lips, a long low continuous dorsal fin running the whole back, drab "
        "olive-brown and grey mottled camouflage, short stubby body, scaleless slimy "
        "skin" + NPOSE,
    "fish_tallow_pollock":
        "a pollock, torpedo-shaped cod-family fish, three separate dorsal fins and two "
        "anal fins, protruding lower jaw, pale lateral line curving over the pectoral "
        "fin, greenish-brown back fading to a fat waxy yellow-cream belly, heavy through "
        "the shoulder" + NPOSE,
    "fish_gannet_mackerel":
        "an Atlantic mackerel, streamlined spindle body, deeply forked tail, small "
        "finlets between the second dorsal fin and the tail, steel-blue-green back "
        "marked with dark wavy tiger stripes, bright silver flanks and belly, small "
        "scales, sleek and fast" + NPOSE,
    "fish_rust_wrasse":
        "a ballan wrasse, deep-bodied stocky fish, thick rubbery lips and prominent "
        "grazing teeth, a long spiny dorsal fin along the back, large rounded tail, "
        "rust-orange and burnt-brown mottling over heavy scales, coarse and blunt" + NPOSE,
    "fish_kelp_pipefish":
        "a pipefish, extremely long thin rigid stick-like body no thicker than a pencil, "
        "armoured bony ring segments, a long narrow tubular snout with a tiny mouth, one "
        "small dorsal fin near the middle, a tiny fan tail, dull olive-green weed "
        "camouflage" + NPOSE,
    "fish_squall_garfish":
        "a garfish, extremely elongated needle-thin body, very long slender beak jaws "
        "lined with fine sharp teeth like a needlefish, dorsal and anal fins set far "
        "back near the tail, forked tail, brilliant polished silver flank, dark "
        "blue-green back" + NPOSE,

    # ---- tier 2: deep, but seen in the water or netted ----
    "fish_lantern_dogfish":
        "a small deep-sea lantern shark, slender dogfish shark body about a metre long, "
        "two small spined dorsal fins, no anal fin, huge dark green reflective eyes, "
        "rough dark slate-grey skin, and a BELLY covered in faint cold blue-green "
        "bioluminescent glow, sleek and muscular" + NPOSE,
    "fish_anchor_ray":
        "a thornback skate lying perfectly FLAT and level like a kite, a broad flat "
        "diamond-shaped disc of pectoral wings spread out to each side, blunt snout, "
        "eyes on top of the disc, rows of small thorns down the spine, a long thin "
        "tail trailing straight behind, drab silt-grey and brown speckled camouflage, "
        "pale underside, seen from above, wings held flat and horizontal",
    "fish_abyss_grenadier":
        "a grenadier rattail deep-sea fish, big blunt bulbous head with huge eyes and a "
        "downturned mouth, body tapering to an extremely long thin whip-like rattail "
        "with no tail fin at all, large fragile pale grey-brown scales, one small "
        "triangular dorsal fin near the head" + NPOSE,

    # ---- tier 3: deep-drop pool, only ever seen landed on the deck ----
    "fish_gulper_eel":
        "a gulper eel pelican eel, an ENORMOUS loose hinged pouch-like jaw far bigger "
        "than the rest of the animal, tiny eyes right at the snout tip, a thin whip-like "
        "black eel body tapering away behind it to a threadlike tail, soft scaleless "
        "matte black skin, grotesque and skeletal" + NPOSE,
    "fish_trench_hagfish":
        "a hagfish, a primitive jawless eel-shaped animal, no fins and no jaws, a blunt "
        "round mouth ringed with short barbels, no eyes, uniform pinkish-grey wrinkled "
        "slimy skin, a low fin fold along the tail, coated in thick clear slime" + NPOSE,
    "fish_bloom_dragon":
        "a deep-sea dragonfish, long slim black eel-like body, an oversized head with "
        "huge needle fangs too big for its mouth, a long barbel hanging from its chin "
        "tipped with a small COLD BLUE-GREEN glowing lure, rows of tiny blue-green "
        "photophore dots along its flank, matte black scaleless skin" + NPOSE,
    "fish_fathom_sturgeon":
        "a huge ancient sturgeon, long armoured body ridged with five rows of bony "
        "scutes, a flat pointed shovel snout with four barbels underneath, a "
        "shark-like upturned asymmetrical tail, small eyes, olive-grey armoured hide, "
        "prehistoric and massive" + NPOSE,
    "fish_giant_oarfish":
        "a giant oarfish, an immensely long flat ribbon-shaped silver body, a brilliant "
        "crimson-red dorsal fin running its entire length, a tall crest of long red rays "
        "rising from the top of its small horse-like head, two long red pelvic rays "
        "hanging like oars, blue-black dashes on polished silver skin" + NPOSE,
}

# One namespace for the runner. Every s15 slug carries the North-Sea tail instead of the
# Pandora one; the original wave keeps the look it shipped with.
PROMPTS: dict[str, str] = {s: p + STYLE for s, p in FISH.items()}
PROMPTS.update({s: p + NORTH_SEA for s, p in NEW_FISH.items()})

# Set the moment a job comes back with a payment/quota error. Meshy bills per task, so
# retrying an out-of-credit batch just burns wall-clock against a wall — the owner's rule
# is stop cleanly and report, never loop on a credit failure.
_BROKE = threading.Event()


# Where the preview task ids land when we generate untextured (see _note_preview).
PREVIEW_LOG = Path(__file__).parent / "preview_ids.json"
_LOG_LOCK = threading.Lock()


def _note_preview(slug: str, task_id: str) -> None:
    """Record slug -> Meshy preview task id so a later credit top-up can run the refine
    pass on the EXISTING mesh (POST mode=refine, preview_task_id=<id>) rather than paying
    for a whole new generation that would also change the shape the player already knows."""
    if not task_id:
        return
    with _LOG_LOCK:
        data: dict = {}
        if PREVIEW_LOG.exists():
            try:
                data = json.loads(PREVIEW_LOG.read_text())
            except ValueError:
                data = {}
        data[slug] = task_id
        PREVIEW_LOG.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def _is_credit_error(msg: str) -> bool:
    low = msg.lower()
    return ("402" in low or "credit" in low or "quota" in low
            or "insufficient" in low or "payment" in low)


def one(slug: str, prompt: str, key: str, refine: bool = True,
        ai_model: str = "") -> tuple[str, str]:
    dest = OUT / slug / f"{slug}.glb"
    if dest.exists():
        return slug, "skip (exists)"
    if _BROKE.is_set():
        return slug, "skip (out of credits)"
    try:
        task = meshy_text_to_3d(key, prompt, refine, ai_model)
        download_glb(task, dest)
        if not refine:
            # Keep the preview task id: it is the ONLY handle that can be refined into
            # PBR textures later, and it is unrecoverable once this process exits.
            _note_preview(slug, task.get("id", ""))
        return slug, f"ok ({dest.stat().st_size / 1e6:.1f} MB){'' if refine else ' [untextured preview]'}"
    except Exception as e:  # keep the batch going
        msg = f"{e}"
        if _is_credit_error(msg):
            _BROKE.set()
            return slug, f"FAILED (OUT OF CREDITS): {msg}"
        return slug, f"FAILED: {msg}"


def main() -> None:
    key = load_key("meshy")
    args = sys.argv[1:]
    # --preview: geometry only, no PBR pass. Six species for the price of one (see
    # meshy_text_to_3d). Chosen 2026-07-26 when the account had 54 credits and 13
    # species still unmodelled.
    refine = "--preview" not in args
    args = [a for a in args if a != "--preview"]
    # --model meshy-5: THE budget lever, and by a mile. Measured 2026-07-26 on the live
    # account, a preview costs 20 credits on the default (latest = meshy-6) and 5 on
    # meshy-5 — four species for the price of one, on meshes that read the same at the
    # distance a school swims past. This is how the s15 wave got past three fish.
    ai_model = ""
    if "--model" in args:
        i = args.index("--model")
        ai_model = args[i + 1]
        del args[i:i + 2]
    # Honour the ORDER the slugs were given on the command line — with a hard credit
    # ceiling that matters more than throughput, "which six start first" is the whole
    # decision. No args = everything, in table order.
    jobs = [(s, PROMPTS[s]) for s in args if s in PROMPTS] if args else list(PROMPTS.items())
    unknown = [s for s in args if s not in PROMPTS]
    if unknown:
        sys.exit("Unknown slug(s): " + ", ".join(unknown))
    print(f"{len(jobs)} generations, 6 concurrent{'' if refine else ', PREVIEW ONLY'}"
          f"{', ' + ai_model if ai_model else ''}")
    ok, bad = [], []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futs = {pool.submit(one, s, p, key, refine, ai_model): s for s, p in jobs}
        for fut in as_completed(futs):
            slug, status = fut.result()
            print(f"  {slug}: {status}", flush=True)
            (bad if "FAILED" in status else ok).append(slug)
    print(f"\nDONE  {len(ok)} ok, {len(bad)} failed")
    if bad:
        print("  failed: " + ", ".join(bad) + "   (re-run to retry)")
    if _BROKE.is_set():
        print("  ** stopped early: Meshy reported no credits left. **")


if __name__ == "__main__":
    main()
