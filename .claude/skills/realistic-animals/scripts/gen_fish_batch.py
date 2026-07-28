#!/usr/bin/env python3
"""Generate a 3-D model for EVERY catchable fish in data/fish.json, plus the upgraded
hammerhead — in PARALLEL (6 concurrent jobs) because 21 sequential generations would
take ~3 hours. Defaults to Tripo3D; pass --provider meshy for the original path.

Prompts are hand-written per species from the fish table's name + note, all in the
Bloom's mutated Avatar aesthetic. Resumable: skips slugs whose .glb already exists.

--preview and --model are Meshy-only credit levers (see meshy_text_to_3d's docstring)
and only apply with --provider meshy; they're rejected up front for Tripo rather than
silently ignored.
"""
from __future__ import annotations
import json
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_animal import load_key, generate_mesh, download_model, meshy_text_to_3d, download_glb  # noqa: E402

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

# ---------------------------------------------------------------------------
# s16 (2026-07-27): the owner's standing art direction for EVOLVED BLOOM fauna,
# replacing the grim NORTH_SEA tail for the six species still unmodelled:
#
#   "Evolution is positive, not corruptive. Mutations are adaptive and often
#    beautiful: bioluminescence, mineral armor, new symbioses, increased
#    intelligence and sociability. No gore, no body horror. Awe and beauty of
#    nature."
#
# So the negatives here are doing real work: the old prompts for these six were
# written the other way round and said things like "grotesque and skeletal",
# "fangs too big for its mouth" and "wrinkled slimy skin". Those descriptors are
# gone from the bodies below, and the tail actively pushes against them, because
# a generator will happily reintroduce deep-sea-horror tropes for these species
# from its own priors unless told not to.
#
# SAME 600-CHARACTER CEILING AS NORTH_SEA — Meshy truncates silently past it and
# the negatives live at the tail, so an over-long prompt loses exactly the part
# that keeps the fish beautiful. There is an assertion below that enforces this.
BLOOM_EVOLVED = (", photoreal evolved deep-sea fish, adaptive beautiful mutation, "
                 "iridescent bioluminescence, nacre mineral armour, healthy elegant "
                 "animal, single subject, whole body, side profile, plain background, "
                 "no base, no plinth, no ground, no rock, no hands, "
                 "not grotesque, no gore, not skeletal, not diseased")

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
        "a grenadier rattail, a smooth domed head with large gentle intelligent eyes, "
        "body tapering to a long elegant whip tail, big iridescent silver-lilac scales, "
        "one neat triangular dorsal fin" + NPOSE,

    # ---- tier 3: deep-drop pool, only ever seen landed on the deck ----
    "fish_gulper_eel":
        "a pelican gulper eel, a great graceful hinged pouch jaw, a slender ribbon body "
        "tapering to a fine tail, deep violet-black skin with a luminous pearl-blue seam "
        "along the jaw and a softly lit tail tip" + NPOSE,
    "fish_trench_hagfish":
        "a hagfish, a smooth primitive jawless eel-shaped animal, a soft round mouth "
        "ringed with fine barbels, glossy rose-pearl skin with a faint opal sheen, a low "
        "fin fold running along the tail" + NPOSE,
    "fish_bloom_dragon":
        "a deep-sea dragonfish, a slender iridescent body, a long chin barbel tipped with "
        "a bright teal glowing lure, neat rows of blue-green photophores along the flank, "
        "fine opal scales" + NPOSE,
    "fish_fathom_sturgeon":
        "a huge ancient sturgeon, five rows of polished nacre scutes down an armoured "
        "body, a flat shovel snout with four barbels beneath, an upturned shark-like "
        "tail, pearl and jade sheen" + NPOSE,
    "fish_giant_oarfish":
        "a giant oarfish, an immensely long flat silver ribbon body, a brilliant crimson "
        "dorsal fin running its whole length, a tall crest of red rays on a small head, "
        "two long red pelvic oars, blue-black dashes on polished silver" + NPOSE,
}

# The six s16 species take the evolved-bloom tail rather than the grim North-Sea one.
BLOOM_FISH: set[str] = {
    "fish_abyss_grenadier", "fish_gulper_eel", "fish_trench_hagfish",
    "fish_bloom_dragon", "fish_fathom_sturgeon", "fish_giant_oarfish",
}

# One namespace for the runner. Every s15 slug carries the North-Sea tail instead of the
# Pandora one; the original wave keeps the look it shipped with; the six s16 species that
# are still unmodelled carry the evolved-bloom tail (see BLOOM_EVOLVED).
PROMPTS: dict[str, str] = {s: p + STYLE for s, p in FISH.items()}
PROMPTS.update({s: p + (BLOOM_EVOLVED if s in BLOOM_FISH else NORTH_SEA)
                for s, p in NEW_FISH.items()})

# Enforce the truncation ceiling rather than trusting it. A prompt that creeps past 600
# loses its tail — which is where every negative lives — and the failure is SILENT: you
# get a plausible-looking fish on a display plinth and no error anywhere. Two of the s15
# wave shipped at ~730 chars before this was caught by hand.
_OVERLONG = {s: len(p) for s, p in PROMPTS.items() if len(p) > 600}
assert not _OVERLONG, f"prompt(s) over the 600-char truncation ceiling: {_OVERLONG}"

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
    """Classify a task failure as 'the account is out of money' so the batch stops
    cleanly instead of grinding every remaining species into the same wall.

    Providers disagree on how they say it. Meshy uses 402. Tripo returns a bare HTTP
    403 whose ONLY signal is the JSON body (`code 2010`, "You don't have enough credit
    to create this task") — which is why gen_animal._tripo_raise folds the body into
    the exception message; without that this function sees just "403 Client Error:
    Forbidden" and misclassifies an empty account as a transient error.
    """
    low = msg.lower()
    return ("402" in low or "403" in low or "2010" in low
            or "credit" in low or "quota" in low
            or "insufficient" in low or "payment" in low)


def one(slug: str, prompt: str, key: str, provider: str, refine: bool = True,
        ai_model: str = "") -> tuple[str, str]:
    dest = OUT / slug / f"{slug}.glb"
    if dest.exists():
        return slug, "skip (exists)"
    if _BROKE.is_set():
        return slug, "skip (out of credits)"
    try:
        if provider == "meshy":
            task = meshy_text_to_3d(key, prompt, refine, ai_model)
            download_glb(task, dest)
            if not refine:
                # Keep the preview task id: it is the ONLY handle that can be refined
                # into PBR textures later, and it is unrecoverable once this exits.
                _note_preview(slug, task.get("id", ""))
            return slug, f"ok ({dest.stat().st_size / 1e6:.1f} MB){'' if refine else ' [untextured preview]'}"
        result = generate_mesh(provider, key, prompt=prompt)
        download_model(result, dest)
        return slug, f"ok ({dest.stat().st_size / 1e6:.1f} MB)"
    except Exception as e:  # keep the batch going
        msg = f"{e}"
        if _is_credit_error(msg):
            _BROKE.set()
            return slug, f"FAILED (OUT OF CREDITS): {msg}"
        return slug, f"FAILED: {msg}"


def main() -> None:
    args = sys.argv[1:]
    provider = "tripo"
    if "--provider" in args:
        i = args.index("--provider")
        provider = args[i + 1]
        del args[i:i + 2]
    key = load_key(provider)
    # --preview: geometry only, no PBR pass. Six species for the price of one (see
    # meshy_text_to_3d). Meshy-only — Tripo doesn't split preview/refine into two
    # billable passes, so there's no equivalent lever.
    refine = "--preview" not in args
    if "--preview" in args and provider != "meshy":
        sys.exit("--preview is a Meshy-only credit lever (see gen_fish_batch.py's "
                 "docstring); it has no Tripo equivalent. Drop it or add --provider meshy.")
    args = [a for a in args if a != "--preview"]
    # --model meshy-5: THE budget lever, and by a mile. Measured 2026-07-26 on the live
    # account, a preview costs 20 credits on the default (latest = meshy-6) and 5 on
    # meshy-5 — four species for the price of one, on meshes that read the same at the
    # distance a school swims past. This is how the s15 wave got past three fish.
    # Meshy-only, same reasoning as --preview.
    ai_model = ""
    if "--model" in args:
        i = args.index("--model")
        ai_model = args[i + 1]
        del args[i:i + 2]
        if provider != "meshy":
            sys.exit("--model is a Meshy-only lever; drop it or add --provider meshy.")
    # Honour the ORDER the slugs were given on the command line — with a hard credit
    # ceiling that matters more than throughput, "which six start first" is the whole
    # decision. No args = everything, in table order.
    jobs = [(s, PROMPTS[s]) for s in args if s in PROMPTS] if args else list(PROMPTS.items())
    unknown = [s for s in args if s not in PROMPTS]
    if unknown:
        sys.exit("Unknown slug(s): " + ", ".join(unknown))
    print(f"{len(jobs)} generations, 6 concurrent ({provider}){'' if refine else ', PREVIEW ONLY'}"
          f"{', ' + ai_model if ai_model else ''}")
    ok, bad = [], []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futs = {pool.submit(one, s, p, key, provider, refine, ai_model): s for s, p in jobs}
        for fut in as_completed(futs):
            slug, status = fut.result()
            print(f"  {slug}: {status}", flush=True)
            (bad if "FAILED" in status else ok).append(slug)
    print(f"\nDONE  {len(ok)} ok, {len(bad)} failed")
    if bad:
        print("  failed: " + ", ".join(bad) + "   (re-run to retry)")
    if _BROKE.is_set():
        print(f"  ** stopped early: {provider} reported no credits left. **")


if __name__ == "__main__":
    main()
