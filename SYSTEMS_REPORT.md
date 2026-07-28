# SALTLINE — Fishing, Weather & Fauna Systems Reference

**Snapshot:** repo `/Users/mjspeh/SALTLINE`, git HEAD `769e5c9`, working tree **dirty** (22 modified scripts). All `data/*.json` are clean at HEAD; `scripts/components/fishing_rod.gd` and `scripts/world/fish_table.gd` are *modified in the working tree* and grew during this analysis (bait-effect table + trophy jolt were added mid-read). Everything below describes the **working-tree** state, which is what runs.

Every claim is cited `file:line`. Where behaviour is derived (probability tables, fight-timing), the derivation is from the actual constants and is reproducible.

---

## 0. KEY FINDINGS — things that look wrong

### Uncatchable species: the verdict
**No species in `data/fish.json` is literally uncatchable.** All 35 entries resolve to a non-zero weight in at least one pool under at least one reachable condition. But four things are effectively broken:

| # | Finding | Severity |
|---|---|---|
| **A** | **Giant Oarfish is un-landable by the fight maths, not by the roll.** With `fight 3.2 / pull 2.3` (`data/fish.json:1085-1086`) the *maximum sustainable* net reel progress is **negative** (−0.00101 /s) for any surge-blind strategy. Only a razor-thin surge-phase-exploiting strategy wins, and simulation puts that at **850–1140 s (14–19 minutes)** of frame-perfect play. In practice the line snaps or the fish spits the hook. See §1.6. | **Critical** |
| **B** | **`deep: true` is documented as "deep-drop RIG pool ONLY … never rolls on the surface rod/net" (`data/fish.json:2`) but the code never enforces it.** `FishTable.weight_for` only checks `def.get(kind, false)` (`scripts/world/fish_table.gd:146`). `fish_ribbon_eel` and `fish_barrel_grouper` are `rod: true` **and** `deep: true`, so **both roll on the plain surface rod with no depth gate at all** (`data/fish.json:429-431`, `464-465`). A Barrel Grouper — 12–48 kg, 6–12 fillets, the stated "whole reason for the deep rig" — is obtainable at **1.9 % per cast** from the topside rail in open water on day one with the starter rod. | **Critical** |
| **C** | **The Angler's Notes readable is hand-written static text (`data/readables.json:anglers_notes`), NOT generated from `fish.json`** despite `fish.json:2` claiming "the Angler's Notes readable are ALL generated from this table". It is now stale in three ways: it says Fathom Halibut gives "6-11 FILLETS" (real value `[1,3]`, `data/fish.json:603`); it **omits Coelacanth and Giant Oarfish entirely** (both absent from the species list *and* from the printed drop-depth ladder); and it says the bait "is spent the moment the lead hits the water", which the code contradicts (`fishing_rod.gd:492-493` spends it at the take). | **High** |
| **D** | **15 of 35 species have no `data/journal.json` entry**, so `Journal.discover(id)` silently does nothing for them (`scripts/autoload/journal.gd:59` — `if … not data.has(id): return`). Missing: gulper_eel, bloom_dragon, fathom_sturgeon, abyss_grenadier, bilge_blenny, tallow_pollock, gannet_mackerel, rust_wrasse, kelp_pipefish, lantern_dogfish, squall_garfish, anchor_ray, trench_hagfish, giant_oarfish, coelacanth. Note the new `Journal.record_catch` (`journal.gd:137`, called from `fishing_rod.gd:738`) rewrites `data[species_id]` — verify whether it creates missing entries or also no-ops. | **High** |
| **E** | **Holding LMB — the thing the on-screen prompt literally tells you to do — snaps the line on 34 of the 35 species.** `_fight()` prints `"[hold LMB] reel"` (`fishing_rod.gd:672`), but continuous reeling drives tension from 0.30 to the 1.0 break point in 0.6–1.7 s for everything except the net-only Kelp Pipefish. See §1.6 table. | **High** |
| **F** | **The fight's own design comment is backwards.** `fishing_rod.gd:648` says "reel the lulls, respect the surges", but progress *loss while resting* is proportional to surge (`fishing_rod.gd:653`) while tension gain while reeling is also proportional to surge (`:651`). Numerically, **reeling into the surge and resting in the lull is strictly faster** for every mid/large species (e.g. Barrel Grouper 55 s vs 109 s). | Medium |
| **G** | **Weather has ZERO effect on player survival stats.** There is no wetness/exposure stat anywhere. `PlayerState._process` (`player_state.gd:167-181`) derives warmth only from `warmth_zone` (set solely by `WarmthZone` volumes, `warmth_zone.gd:31`) and from `GameClock.current_phase == NIGHT`. Standing in a full squall on an open deck is thermally identical to standing indoors at the same phase. Rain's only gameplay coupling is the Rain Catcher (`rain_catcher.gd`). | **High** |
| **H** | **`fish_giant_oarfish` peaks at 1.75 % of the deep pool** (42 m, night, open water) and is zero at dawn and day (`data/fish.json:1075-1078`). Combined with finding A it is de-facto unobtainable content. **`the_looker`** sits at 0.4–1.1 % of the rod pool in every condition — deliberate, but note it is `rod: true` with **no depth or condition gate at all**, so it can turn up on the very first cast. | Medium |
| **I** | **Trophy classification misses the headline deep species.** `FishTable.is_trophy` (`fish_table.gd:312-319`) fires on `size_kg[1] ≥ 20` or `pull ≥ 1.6`. **Bloom Dragonfish (`pull 1.55`) misses by 0.05** and gets no jolt/flash, despite being the 38 m band's headline fish and the single largest share of the deep pool (38–55 %). Abyss Grenadier (`pull 1.5`, 16 kg) also misses. | Medium |
| **J** | **A 48 kg Barrel Grouper and a 70 kg Fathom Halibut are legal deep-rig BAIT.** `_is_small_bait_fish` (`fishing_rod.gd:306-308`) uses `ItemVisual.FISH_SIZE < 2.0`; grouper is 1.8 and halibut 1.7 (`item_visual.gd:37`). Any species **missing** from `FISH_SIZE` defaults to 1.0 and is therefore also bait — that covers `fish_stone_crab`, `fish_gutter_prawn`, `fish_inkwell_squid`, `fish_trench_hagfish`. Only Fathom Sturgeon (2.0) and Giant Oarfish (3.5) are excluded. | Medium |
| **K** | **Glow-worm bait is a Bloom Dragonfish bait, not a deep bait.** `BAIT_TABLE` gives glow worm `deep 1.9` **and** `drawn 1.6` (`fish_table.gd:68-69`), which *multiply* with the existing `light: drawn` ×2 from floodlights (`fish_table.gd:165-166`). Net ×6.08 for Bloom Dragonfish. At 44 m/night/lit it **lowers** Fathom Sturgeon's share (9.96 % → 8.94 %) and Giant Oarfish's (1.55 % → 1.39 %) by crowding. | Medium |
| **L** | **The drop net reads the wrong moment for weather and light.** `drop_net._haul()` builds the context at haul time (`drop_net.gd:117`) then force-overrides `phase = "night"` if any of the soak was dark (`:118-119`) — but leaves `storming` and `lit` at their haul-instant values. A net that soaked all night through a storm and is hauled at calm noon gets night species, no storm species, and no `light: drawn` bonus. | Medium |
| **M** | **The drop-net "spool's end" refusal in the deep rig is dead code.** `_hold_the_spool(false)` → `_abort_msg = "Spool's end at %d m, above the lot of them"` (`fishing_rod.gd:567`) can only fire if the pool is empty at the stopping depth. `DEEP_MAX_DEPTH = 48` (`:56`) exceeds the deepest `drop_m` of 44, and `DEEP_MAX_RANGE = 95` (`:54`) is never reached from any spot on the rig (highest drop spends ~89 m). | Low |
| **N** | **`fight`/`pull` are dead data for the six net-only species.** `DropNet` has no minigame at all — `_haul()` just calls `FISH.roll` and `add_item` (`drop_net.gd:124-128`). Stone Crab, Gutter Prawn, Miller's Flounder, Fathom Halibut, Kelp Pipefish and Anchor Ray carry `fight`/`pull` values that nothing reads. | Low |
| **O** | **`school.active` for `storm: "only"` species is an empty array used as a sentinel.** `underwater_world.gd:1031` treats an empty `active` list as "visible only while storming". This is deliberate and commented, but it means the two arrays for Drum Croaker and Squall Garfish (`fish.json:390`, `:1001`) mean something entirely different from every other species' array. | Low |
| **P** | **There is no economy.** `data/items.json` contains **zero `value`/price fields**. Species flavour text repeatedly says "worth more traded than eaten, someday" (chimefish, `fish.json:169`). Fish have no monetary value in the implemented game. | Info |
| **Q** | **There are no rod tiers, no line strength, and no upgrade path.** Two rod items exist (`fishing_rod`, `deep_rig_pole`); both are found in the world, neither is craftable, and neither has any stat. `TENSION_DECAY`, `REEL_RATE` and the 1.0 break point are hard constants on the FishingRod class. | Info |
| **R** | **`deep_rig_pole` is missing from `PlayerState.EQUIPMENT`** (`player_state.gd:293-300`), so unlike `fishing_rod` it stacks to 16 per slot. | Low |
| **S** | **Storm scheduling never sleeps.** `CALM_MIN/MAX = 220/450 s`, `RAGE_MIN/MAX = 90/210 s`, plus 22 s ramp-in and 32 s ramp-out (`storm_system.gd:40-47`). A full cycle averages ~477 s, of which ~172 s reads as storming — **roughly 36 % of all playtime is a squall**, and a GameClock day is 60 min (`game_clock.gd:17-22`), so ~7.5 squalls per in-game day. | Medium |
| **T** | **Two `crab.gd` numbers drifted from `tuning.json`.** The in-code fallback for `pursue_speed` is still `4.4` (`crab.gd:337`) while the shipped tuning value is `4.0` (`tuning.json:14`); three comments still cite 4.4. Also `crab.gd:207` declares `L_OPS` which nothing references, and `State.GONE` is never assigned in either crab script. | Low |

---

# SECTION 1 — FISH & FISHING

## 1.1 Complete species table

35 species. All numbers quoted directly from `data/fish.json` (and `data/items.json` for food value). Columns:

- **Pools** — which rollers can select it: R = surface rod (`rod:true`), N = drop net (`net:true`), D = deep-drop rig (`deep:true`). *These are independent booleans; `deep` does not exclude `rod`.*
- **Depth band** — `depth` field. **This is cosmetic only**: it drives the visible school's y-band in `underwater_world.gd:15` (`DEPTH_BAND = {surface: −1.2, mid: −4.5, deep: −9.5}`). It is **never read by the catch algorithm**.
- **Drop m** — real depth gate, deep pool only (`fish_table.gd:169-173`).
- **Hours** — the `w` weights, dawn/day/dusk/night.
- **Weather / Water / Light** — the `storm` / `water` / `light` fields.
- **kg** — `size_kg` landed weight range; blank = species has no weight (`roll_size` returns 0.0, `fish_table.gd:258-264`).
- **Fillets** — `fillets` range; blank = one raw → one cooked.
- **Cooked → (hunger)** — `cooked_to` and the target item's `hunger` value from `items.json`.

| Display name | id | Pools | Depth band (cosmetic) | Drop m | dawn/day/dusk/night | Weather | Water | Light | fight | pull | kg | Fillets | Cooked → (hunger) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Copper Sprat | `fish_copper_sprat` | R N | surface (−1.2) | — | 30/32/30/20 | ok | any | any | 0.50 | 0.40 | — | — | `cooked_fish_copper_sprat` (0.30) |
| Lantern Herring | `fish_herring` | R N | surface | — | 28/26/26/26 | ok | any | any | 0.80 | 0.65 | — | — | `cooked_fish_herring` (0.45) |
| Slate Cod | `fish_slate_cod` | R N | mid (−4.5) | — | 10/26/10/4 | **bonus** ×2 | any | any | 1.25 | 0.90 | — | — | `cooked_fish_slate_cod` (0.55) |
| Mirrorjack | `fish_mirrorjack` | R | surface | — | 26/4/22/2 | ok | **open** | any | 1.00 | 1.35 | — | — | `cooked_fish_mirrorjack` (0.48) |
| Chimefish | `fish_chimefish` | R N | mid | — | 8/10/8/6 | **never** | any | any | 0.90 | 0.80 | — | — | `cooked_fish_chimefish` (0.42) |
| Silver Ladder | `fish_silver_ladder` | R | mid | — | 22/3/2/1 | ok | **open** | any | 1.00 | 1.00 | — | — | `cooked_fish_silver_ladder` (0.42) |
| Ember Snapper | `fish_ember_snapper` | R N | mid | — | 6/14/14/4 | ok | **near** | any | 1.10 | 1.00 | — | — | `cooked_fish_ember_snapper` (0.50) |
| Sable Hake | `fish_sable_hake` | R N | mid | — | 5/2/12/28 | ok | **near** | **drawn** ×2 | 1.10 | 1.00 | — | — | `cooked_fish_sable_hake` (0.46) |
| Ghost Sole | `fish_ghost_sole` | R N | mid | — | 2/**0**/4/14 | ok | **near** | **drawn** | 0.90 | 0.70 | — | — | `cooked_fish_ghost_sole` (0.42) |
| Glasspike | `fish_glasspike` | R | surface | — | 2/**0**/3/12 | **never** | **open** | any | 1.15 | 1.20 | — | — | `cooked_fish_glasspike` (0.50) |
| Lodestone Bream | `fish_lodestone_bream` | R | deep (−9.5) | — | 6/16/6/2 | ok | **open** | any | 1.30 | 1.10 | — | — | `cooked_fish_lodestone_bream` (0.50) |
| Drum Croaker | `fish_drum_croaker` | R N | mid | — | 10/10/10/10 | **only** (×3, floor 4) | any | any | 1.30 | 1.15 | — | — | `cooked_fish_drum_croaker` (0.52) |
| Inkwell Squid | `fish_inkwell_squid` | R N | mid | — | 3/1/6/16 | ok | any | **drawn** | 1.20 | 1.25 | — | — | `cooked_fish_inkwell_squid` (0.48) |
| **Ribbon Eel** | `fish_ribbon_eel` | **R** D | deep | 8 | 2/**0**/5/12 | ok | **open** | any | 1.50 | 1.40 | — | — | `cooked_fish_ribbon_eel` (0.65) |
| **Barrel Grouper** | `fish_barrel_grouper` | **R** D | deep | 16 | 4/3/4/5 | **bonus** | **open** | any | 2.30 | 1.70 | **12–48** | **6–12** | `cooked_fish_barrel_grouper` (0.45 **per fillet**) |
| Stone Crab | `fish_stone_crab` | N | deep | — | 8/6/10/14 | ok | any | any | *1.00* | *0.80* | — | — | `cooked_fish_stone_crab` (0.50) |
| Gutter Prawn | `fish_gutter_prawn` | N | mid | — | 20/16/20/24 | ok | any | any | *0.40* | *0.30* | — | — | `cooked_fish_gutter_prawn` (0.32) |
| Miller's Flounder | `fish_miller_flounder` | N | deep | — | 8/14/8/4 | ok | **near** | any | *0.90* | *0.70* | — | — | `cooked_fish_miller_flounder` (0.46) |
| Fathom Halibut | `fish_fathom_halibut` | N | deep | — | 1/**0**/2/5 | ok | any | any | *2.00* | *1.50* | **20–70** | **1–3** | `cooked_fish_fathom_halibut` (0.50) |
| **The Looker** | `the_looker` | R | deep | — | 1/1/1/2 | ok | any | any | 1.30 | 1.10 | — | — | **never kept** (`release: true`) |
| Gulper Eel | `fish_gulper_eel` | D | deep | **34** | 4/2/6/13 | ok | any | any | 2.20 | 1.70 | — | — | `cooked_fish_prime` (0.70) |
| Bloom Dragonfish | `fish_bloom_dragon` | D | deep | **38** | 2/1/7/14 | ok | any | **drawn** | 2.00 | 1.55 | — | — | `cooked_fish_prime` (0.70) |
| Fathom Sturgeon | `fish_fathom_sturgeon` | D | deep | **44** | 7/8/7/6 | **bonus** | any | any | 3.00 | 2.10 | **30–95** | **5–9** | `cooked_fish_prime` (0.70) |
| Abyss Grenadier | `fish_abyss_grenadier` | D | deep | **24** | 6/11/5/3 | ok | **open** | any | 1.90 | 1.50 | **5–16** | **3–6** | `cooked_fish_prime` (0.70) |
| Bilge Blenny | `fish_bilge_blenny` | R N | surface | — | 22/24/22/18 | ok | **near** | any | 0.45 | 0.35 | — | — | `cooked_fish_bilge_blenny` (0.28) |
| Tallow Pollock | `fish_tallow_pollock` | R N | mid | — | 18/20/12/4 | **bonus** | any | any | 1.20 | 0.95 | — | — | `cooked_fish_tallow_pollock` (0.58) |
| Gannet Mackerel | `fish_gannet_mackerel` | R N | surface | — | 26/6/24/2 | **never** | **open** | any | 1.05 | 1.20 | — | — | `cooked_fish_gannet_mackerel` (0.46) |
| Rust Wrasse | `fish_rust_wrasse` | R N | mid | — | 8/18/10/1 | ok | **near** | any | 0.85 | 0.70 | — | — | `cooked_fish_rust_wrasse` (0.40) |
| Kelp Pipefish | `fish_kelp_pipefish` | N | surface | — | 16/18/14/6 | **never** | **near** | any | *0.35* | *0.25* | — | — | `cooked_fish_kelp_pipefish` (0.26) |
| Lantern Dogfish | `fish_lantern_dogfish` | R | deep | — | 3/1/8/20 | ok | **open** | **drawn** | 1.60 | 1.45 | — | — | `cooked_fish_lantern_dogfish` (0.55) |
| Squall Garfish | `fish_squall_garfish` | R N | surface | — | 9/9/9/9 | **only** | **open** | any | 1.35 | 1.50 | — | — | `cooked_fish_squall_garfish` (0.50) |
| Anchor Ray | `fish_anchor_ray` | N | deep | — | 4/3/6/10 | ok | **near** | any | *1.75* | *1.40* | — | — | `cooked_fish_anchor_ray` (0.62) |
| Trench Hagfish | `fish_trench_hagfish` | D | deep | **28** | 5/4/7/12 | ok | any | any | 1.70 | 1.30 | — | — | `cooked_fish_prime` (0.70) |
| **Giant Oarfish** | `fish_giant_oarfish` | D | deep | **42** | **0/0**/1/1 | ok | **open** | any | 3.20 | 2.30 | **40–85** | **4–4** | `cooked_fish_prime` (0.70) |
| Coelacanth | `fish_coelacanth` | D | deep | **20** | 1/1/2/6 | ok | **open** | any | 2.50 | 1.90 | **15–35** | **4–4** | `cooked_fish_prime` (0.70) |

*Italic* fight/pull = never used (net-only species have no minigame; see finding N).

**Raw fish are all identical as food:** every `fish_*` id in `items.json` is `{"use":"eat","hunger":0.08,"side_effect":"sick"}` (e.g. `items.json` `fish_herring`, `fish_barrel_grouper`, …). `the_looker` has no item entry at all — correct, since `release` short-circuits before `add_item` (`fishing_rod.gd:684-689`).

**Every `cooked_to` id exists in `items.json`** — verified for all 34 cookable species. The comment in `cook_stove.gd:69-71` claiming "the deep oddities … resolve to the generic meal" is **stale**: `cooked_fish_prime` exists (hunger 0.70), so the deep species get the best meal in the game.

**Rarity/spawn weight** is not a separate field — it is the `w` map, modified by the multipliers in §1.3.

---

## 1.2 The catch algorithm, end to end

### Surface rod (`item "fishing_rod"`)

**1. Cast.** `player_controller.gd:349-355` spawns a `FishingRod` when LMB is pressed with either rod item selected (`ROD_ITEMS`, `player_controller.gd:121`). `setup()` launches the float from the camera at `CAST_SPEED = 13.0` m/s along the look vector plus `CAST_LIFT = 4.0` m/s up (`fishing_rod.gd:26-27, 148-150`).

**2. Flight.** `State.CASTING` integrates ballistics at `GRAVITY = 9.8` and raycasts each frame from the previous to the current position (`fishing_rod.gd:406-419`). Any hit = fouled cast → `"No open water there."` Waterline is `Gyre.wave_height(xz, t) * 0.85` (`:420`). Beyond `MAX_RANGE = 45.0` m from the hand the line dies silently.

**3. Wait timer (`_schedule_bite`, `fishing_rod.gd:384-392`).**
```
mean       = 12.0 * bite_pace(ctx)            # ×1.1 more for the deep rig
_bite_timer = randf_range(mean*0.45, mean*1.5)
_nibbles    = randi_range(0, 2)
```
`bite_pace` (`fish_table.gd:342-348`): `×0.55` if storming, `×0.75` if dawn or dusk (they stack).

| Condition | mean | timer range | expected first event |
|---|---|---|---|
| day / night, calm | 12.0 s | 5.4 – 18.0 s | 11.7 s |
| dawn / dusk, calm | 9.0 s | 4.05 – 13.5 s | 8.8 s |
| day / night, storm | 6.6 s | 2.97 – 9.9 s | 6.4 s |
| dawn / dusk, storm | 4.95 s | 2.23 – 7.43 s | 4.8 s |

Each **nibble** (0–2, mean 1) consumes one timer expiry, dips the float 0.16 m, and re-rolls the timer to `randf_range(1.8, 5.0)` (`fishing_rod.gd:452-456`). Expected extra wait ≈ **+3.4 s**. So expected time to a real take on a calm day ≈ **15 s**.

**4. The take (`_take`, `fishing_rod.gd:586-590`).** The species is rolled **at the take**, not at the strike — this changed in the working tree. If `FishTable.is_trophy` the game fires a gamepad jolt (`JOLT_WEAK 0.7 / JOLT_STRONG 0.9 / JOLT_SEC 0.35`) and a full-screen pale flash (`FLASH_PEAK 0.5`, 0.04 s in, 0.19 s out) (`fishing_rod.gd:65-71, 602-621`). The prompt changes to `"!!! THAT IS A BIG ONE [LMB] STRIKE"`.

**5. Strike window.** `BITE_WINDOW = 1.3` s (`fishing_rod.gd:30`). Miss it and `_pending` is cleared, the state returns to DRIFT/SINK, and `_schedule_bite()` re-rolls (`:505-513`).

**6. The roll (`FishTable.roll`, `fish_table.gd:191-207`).** Straight linear-scan weighted draw over the whole table: `_pool()` computes `weight_for` for every id and keeps the positives; `randf_range(0, total)` walks the list.

**7. Fight → land.** See §1.6.

### Deep-drop rig (`item "deep_rig_pole"`) — the differences

- **Bait gate.** `setup()` refuses outright unless the static `_baited_id` is armed **and** still in the pack (`fishing_rod.gd:156-164`). The refusal is deferred one physics frame via `_abort_msg` because `player.fishing` is assigned after `setup()` returns.
- **Baiting is `[B]`** (`try_bait_now`, `fishing_rod.gd:370-382`). `_find_bait()` scans `hotbar + inventory` in slot order and takes the first legal bait (`fishing_rod.gd:287-291`). Legality (`_is_bait_item`): the three named specials `snail_live`, `fish_rotten`, `crab_leg`; the `BAIT_SCRAPS` list (`raw_fillet`, `raw_sea_bird`, `cooked_sea_bird`, `dried_fish`, `crab_leg_seared`, `escargot`, `glow_worm`, `glow_worm_cooked`, `cooked_fish`, `cooked_fish_prime` — `fishing_rod.gd:86-90`); or any `fish_*` whose `ItemVisual.FISH_SIZE` is `< BAIT_FISH_MAX_M = 2.0` (`fishing_rod.gd:79`). **See finding J.**
- **Heave, not cast.** Pitch is discarded; only the flattened look direction is used. `DEEP_CAST_SPEED = 6.0`, `DEEP_CAST_LIFT = 1.9` (`fishing_rod.gd:52-53, 171-175`).
- **Sink.** `DEEP_SINK_RATE = 3.2` m/s to `DEEP_MAX_DEPTH = 48.0` m (`fishing_rod.gd:55-56, 538-540`). Nothing can bite above `FishTable.min_drop_depth()` = **8 m** (the shallowest `deep` species' `drop_m`, `fish_table.gd:221-229`) — so the first ~2.5 s of sink is dead time.
- **Bite clock is bait- and depth-modulated:** `_bite_timer -= delta * FishTable.bait_rate(_bait_id, _depth)` (`fishing_rod.gd:476`). Only glow worm / cooked glow worm have entries (`fish_table.gd:61-73`); glow worm is ×1.35 below 24 m depth-of-lead and ×0.75 above it.
- **Bait is consumed at the take**, not at the splash and not at the strike (`fishing_rod.gd:492-493`).
- **Depth is a choice.** LMB while sinking calls `_hold_the_spool(true)` (`fishing_rod.gd:558-573`); if the pool at that depth is empty the hold is *refused* and the line keeps running.
- **Fight lifts the lead:** `y = −(depth + DEEP_FIGHT_SURGE × surge) × (1 − progress)`, `DEEP_FIGHT_SURGE = 1.6` (`fishing_rod.gd:58, 656`).

---

## 1.3 The weight formula (`FishTable.weight_for`, `fish_table.gd:144-177`)

```
w = def.w[phase]                                  # 0 → species out entirely

storm == "only"   : w = (storming ? max(w,4.0)*3.0 : 0.0)
storm == "never"  : w = (storming ? 0.0 : w)
storm == "bonus"  : w = (storming ? w*2.0 : w)

water == "near"   : if ctx.open  → w *= 0.15
water == "open"   : if !ctx.open → w *= 0.15

light == "drawn"  : if ctx.lit   → w *= 2.0

if depth_m >= 0 (deep rig only):
    if depth_m < drop_m: return 0.0
    w /= 1.0 + (depth_m - drop_m) * DROP_FADE_PER_M     # DROP_FADE_PER_M = 0.035

w *= bait_mult(ctx.bait, def)
```

**Context (`fish_table.gd:120-137`):**
- `phase` — from `GameClock.current_phase`.
- `storming` — `scene.storm.is_storming()`, i.e. `StormSystem._intensity > 0.25` (`storm_system.gd:94-95`).
- `lit` — `(phase == night or dusk) AND PowerGrid.is_powered("topside_floodlights")`. **Never true in daylight**, so `light: drawn` species can never receive the ×2 by day.
- `open` — `rim_dist > 10.0`, where `rim_dist` is the XZ distance outside the rectangle `x ∈ [−32,32], z ∈ [−24,24]`. **Only the position of the float/lead/net matters, not the player's.**
  - The surface rod at 13 m/s + 4 m/s lift from a rail easily clears 10 m → **open** from the topside deck.
  - The deep lead at 6 m/s from the wet deck (y≈2) travels only ~5 m before splashing → **rig shadow**. From the topside deck (y≈18) it travels ~12.7 m → **open**. **Drop height silently determines your open/near multiplier.**
  - The **drop net always hangs inside the rectangle** → `open` is always false → open-water species are permanently ×0.15 in the net pool.

**Bait multiplier (`fish_table.gd:82-90`)** — a table of *exceptions*; anything not listed is ×1.0.

| bait | `deep_from` | ≥ deep_from | < deep_from | extra if `light: drawn` | bite rate ≥ / < deep_from |
|---|---|---|---|---|---|
| `glow_worm` | 24 m | ×1.9 | ×0.7 | ×1.6 | 1.35 / 0.75 |
| `glow_worm_cooked` | 24 m | ×1.15 | ×0.85 | ×1.0 | 1.0 / 1.0 |
| everything else | — | ×1.0 | ×1.0 | ×1.0 | 1.0 |

Note `bait_mult` keys off the **species' own `drop_m`**, not the lead's current depth, while `bait_rate` keys off the **lead's depth**.

---

## 1.4 Resulting probabilities

### Surface rod

**Day · calm · rig shadow** (17 species, total 178.95)

| % | species | | % | species |
|---|---|---|---|---|
| 17.88 | Copper Sprat | | 1.34 | Lodestone Bream |
| 14.53 | Slate Cod | | 1.12 | Sable Hake |
| 14.53 | Lantern Herring | | 0.56 | **The Looker** |
| 13.41 | Bilge Blenny | | 0.56 | Inkwell Squid |
| 11.18 | Tallow Pollock | | 0.50 | Gannet Mackerel |
| 10.06 | Rust Wrasse | | 0.34 | Mirrorjack |
| 7.82 | Ember Snapper | | 0.25 | Silver Ladder |
| 5.59 | Chimefish | | **0.25** | **Barrel Grouper** |
| | | | 0.08 | Lantern Dogfish |

**Day · calm · open water** (total 157.70): Copper Sprat 20.29, Slate Cod 16.49, Herring 16.49, Tallow Pollock 12.68, Lodestone Bream 10.15, Chimefish 6.34, Gannet Mackerel 3.80, Mirrorjack 2.54, Bilge Blenny 2.28, Silver Ladder 1.90, **Barrel Grouper 1.90**, Rust Wrasse 1.71, Ember Snapper 1.33, The Looker 0.63, Lantern Dogfish 0.63, Inkwell Squid 0.63, Sable Hake 0.19.

**Night · calm · open · floodlights on** (total 186.05): Lantern Dogfish 21.50, Inkwell Squid 17.20, Herring 13.97, Copper Sprat 10.75, **Ribbon Eel 6.45**, Glasspike 6.45, Sable Hake 4.51, Chimefish 3.22, **Barrel Grouper 2.69**, Ghost Sole 2.26, Tallow Pollock 2.15, Slate Cod 2.15, Bilge Blenny 1.45, The Looker 1.07, Mirrorjack 1.07, Lodestone Bream 1.07, Gannet Mackerel 1.07, Silver Ladder 0.54, Ember Snapper 0.32, Rust Wrasse 0.08.

**Night · calm · rig shadow · lit** (total 212.40): Sable Hake 26.37, Inkwell Squid 15.07, Ghost Sole 13.18, Herring 12.24, Copper Sprat 9.42, Bilge Blenny 8.47, Lantern Dogfish 2.82, Chimefish 2.82, Tallow Pollock 1.88, Slate Cod 1.88, Ember Snapper 1.88, The Looker 0.94, Ribbon Eel 0.85, Glasspike 0.85, Rust Wrasse 0.47, Barrel Grouper 0.35, remainder ≤0.14.

**Dawn · calm · open** (total 195.45): Copper Sprat 15.35, Herring 14.33, Mirrorjack 13.30, Gannet Mackerel 13.30, Silver Ladder 11.26, Tallow Pollock 9.21, Slate Cod 5.12, Chimefish 4.09, Lodestone Bream 3.07, **Barrel Grouper 2.05**, Bilge Blenny 1.69, Lantern Dogfish 1.53, Inkwell Squid 1.53, Ribbon Eel 1.02, Glasspike 1.02, Rust Wrasse 0.61, The Looker 0.51, Ember Snapper 0.46, Sable Hake 0.38, Ghost Sole 0.15.

**Day · STORM · open** (total 247.70): Slate Cod 20.99, Tallow Pollock 16.15, Copper Sprat 12.92, **Drum Croaker 12.11**, **Squall Garfish 10.90**, Herring 10.50, Lodestone Bream 6.46, **Barrel Grouper 2.42**, rest ≤1.61. (Chimefish, Gannet Mackerel, Kelp Pipefish drop to zero — `storm: never`.)

### Drop net

**Day soak** (16 species, total 230.90): Copper Sprat 13.86, Slate Cod 11.26, Herring 11.26, Bilge Blenny 10.39, Tallow Pollock 8.66, Rust Wrasse 7.80, Kelp Pipefish 7.80, Gutter Prawn 6.93, Miller's Flounder 6.06, Ember Snapper 6.06, Chimefish 4.33, Stone Crab 2.60, Anchor Ray 1.30, Sable Hake 0.87, Inkwell Squid 0.43, Gannet Mackerel 0.39.

**Dark soak (`phase` forced to night)** (18 species, total 204.30): Sable Hake 13.71, Herring 12.73, Gutter Prawn 11.75, Copper Sprat 9.79, Bilge Blenny 8.81, Inkwell Squid 7.83, Stone Crab 6.85, Ghost Sole 6.85, Anchor Ray 4.89, Kelp Pipefish 2.94, Chimefish 2.94, **Fathom Halibut 2.45**, Tallow Pollock 1.96, Slate Cod 1.96, Miller's Flounder 1.96, Ember Snapper 1.96, Rust Wrasse 0.49, Gannet Mackerel 0.15.

**Fathom Halibut is the net's only trophy and only appears on a dark soak** (`day: 0`). At 2.45 % per fish and 1–3 fish per haul, expect one every ~15 night hauls.

### Deep rig — the drop ladder (night · calm · open · lit · neutral bait)

| lead depth | species in the pool, by share |
|---|---|
| 8 m | Ribbon Eel 100 % |
| 16 m | Ribbon Eel 65.2, Barrel Grouper 34.8 |
| 20 m | Ribbon Eel 44.9, Coelacanth 31.9, Barrel Grouper 23.3 |
| 24 m | Ribbon Eel 38.7, Coelacanth 26.5, Grouper 19.7, Abyss Grenadier 15.1 |
| 28 m | Trench Hagfish 40.1, Ribbon Eel 23.6, Coelacanth 15.7, Grouper 11.8, Grenadier 8.8 |
| 34 m | Gulper Eel 33.8, Hagfish 25.8, Ribbon Eel 16.3, Coelacanth 10.5, Grouper 8.0, Grenadier 5.8 |
| 38 m | **Bloom Dragonfish 44.7**, Gulper 18.2, Hagfish 14.2, Ribbon Eel 9.3, Coelacanth 5.9, Grouper 4.5, Grenadier 3.2 |
| 42 m | Dragonfish 43.0, Gulper 17.8, Hagfish 14.1, Ribbon Eel 9.6, Coelacanth 5.9, Grouper 4.6, Grenadier 3.2, **Giant Oarfish 1.75** |
| 44 m | Dragonfish 38.4, Gulper 16.0, Hagfish 12.8, **Sturgeon 9.96**, Ribbon Eel 8.8, Coelacanth 5.4, Grouper 4.2, Grenadier 2.9, Oarfish 1.55 |
| 48 m (spool end) | Dragonfish 38.0, Gulper 16.0, Hagfish 12.9, Sturgeon 9.6, Ribbon Eel 9.2, Coelacanth 5.6, Grouper 4.3, Grenadier 3.0, Oarfish 1.51 |

**Day · calm · open · 48 m** (total only 19.35 vs 54.63 at night): Sturgeon 36.3, Grenadier 30.9, Hagfish 12.2, Grouper 7.3, Gulper 6.9, Dragonfish 3.8, Coelacanth 2.6, **Oarfish 0** (`dawn:0, day:0`). Daylight is actually the *best* time to target Sturgeon by share, worst by total bite volume.

**Night · 48 m · rig shadow (no floodlights)** — the `open` penalty destroys the open-water species: Dragonfish 31.1, Gulper 26.2, Hagfish 21.2, Sturgeon 15.8, then Ribbon Eel 2.25, Coelacanth 1.36, Grouper 1.06, Grenadier 0.73, Oarfish 0.37.

**With glow worm at 44 m / night / lit:** Dragonfish 55.2 (up from 38.4), Gulper 14.3, Hagfish 11.5, **Sturgeon 8.9 (down)**, Ribbon Eel 2.9, Grenadier 2.6, Coelacanth 1.8, **Oarfish 1.39 (down)**, Grouper 1.4. Total weight more than doubles (60.3 → 127.6) and the bite clock runs ×1.35 faster, so raw catch rate rises — but the *composition* shifts toward the one drawn species.

---

## 1.5 Uncatchable / unreachable content — the definitive answer

**Method:** every species was evaluated for `weight_for()` across all 3 pools × 4 phases × storm on/off × lit on/off × open on/off × (for `deep`) every metre 0–48. Results:

**No species is structurally uncatchable.** Every one of the 35 reaches a positive weight somewhere. There is no orphan in the data, no species missing from the roller's table (the roller iterates `FishTable.all()`, which is the whole file minus `_schema`), and no mutually contradictory condition set (`storm:"only"` + `light:"drawn"` never co-occur; `storm:"never"` + `storm`-gated hours never co-occur).

**But the following are effectively unreachable:**

| Species | Why | Best-case share |
|---|---|---|
| **Giant Oarfish** | Winnable roll (1.75 % at 42 m, night/dusk, open water only) but the **fight is mathematically unwinnable** under any surge-blind strategy (net progress −0.001/s) and takes 14–19 min at best under perfect surge exploitation. See §1.6. Also has **no journal entry** and **no Angler's Notes entry**. | 1.75 % of one deep roll, then a fight you almost certainly lose |
| **Fathom Sturgeon** | Roll is fine (9.6–36 % depending on light). The fight is **185 s of perfect duty-cycle play minimum**, simulated at 228–348 s depending on timing. No journal entry. | Reachable but brutal |
| **Coelacanth** | Reachable from 20 m. But **absent from the Angler's Notes ladder and species list**, and has **no journal entry** — the player is never told it exists. | 5.4 % at 44 m night |
| **Fathom Halibut** | Night-soak net only (`day: 0`, `net`-only). Fine — but the Notes describe its yield as 6–11 fillets when the data says 1–3. | 2.45 % per netted fish, dark soak only |
| **Ghost Sole / Glasspike** | `day: 0` — genuinely night/dusk fish, working as designed. | — |
| **The Looker** | 0.4–1.1 % everywhere, `release: true`, never kept. Working as designed; note it needs **no depth and no conditions** despite `depth: "deep"` in data. | 1.07 % night |

**Species that exist in two pools by accident:** `fish_ribbon_eel` and `fish_barrel_grouper` (finding B). The `deep` flag is additive, not exclusive.

---

## 1.6 The reel / struggle minigame

`_fight(delta, t)` — `fishing_rod.gd:637-676`.

```
_fight_t += delta
surge = 0.5 + 0.5 * sin(_fight_t * (1.1 + pull * 0.5))

if reeling:                                     # LMB held
    progress += (REEL_RATE / fight) * delta     # REEL_RATE = 0.14
    tension  += (0.28 + surge * pull * 0.55) * delta
else:
    tension  -= TENSION_DECAY * delta           # TENSION_DECAY = 0.8
    progress -= surge * pull * 0.035 * delta

tension  = clamp(tension,  0.0, 1.2)
progress = clamp(progress, 0.0, 1.0)

tension  >= 1.0  →  "The line parts. Gone."         (line break)
progress <= 0.0  →  "It spat the hook and ran."     (escape)
progress >= 1.0  →  _land()
```

Initial state: `tension = 0.30`, `progress = 0.35` (`fishing_rod.gd:625-627`). Surge period = `TAU / (1.1 + 0.5·pull)` — 3.5 s for a sprat, 2.8 s for a sturgeon.

**Steady-state analysis.** Sustainable reel duty cycle `f` (mean surge 0.5):

```
f = 0.8 / (1.08 + 0.275 · pull)
net progress rate = f · (0.14 / fight) − (1 − f) · 0.0175 · pull
```

This model matches the discrete simulation to within 1 % for every species tested.

| Species | fight | pull | duty f | net prog/s | **theoretical land time** | hold-LMB result | banded play (sim) |
|---|---|---|---|---|---|---|---|
| Giant Oarfish | 3.20 | 2.30 | 0.467 | **−0.00101** | **IMPOSSIBLE (surge-blind)** | SNAP @ 0.6 s | LOST @ 169 s |
| Fathom Sturgeon | 3.00 | 2.10 | 0.483 | 0.00351 | **185 s** | SNAP @ 0.6 s | LAND @ 228 s |
| Coelacanth | 2.50 | 1.90 | 0.499 | 0.01131 | 57 s | SNAP @ 0.6 s | LAND @ 58 s |
| Barrel Grouper | 2.30 | 1.70 | 0.517 | 0.01710 | 38 s | SNAP @ 0.7 s | LAND @ 38 s |
| Gulper Eel | 2.20 | 1.70 | 0.517 | 0.01853 | 35 s | SNAP @ 0.7 s | LAND @ 35 s |
| Bloom Dragonfish | 2.00 | 1.55 | 0.531 | 0.02446 | 27 s | SNAP @ 0.7 s | LAND @ 26 s |
| Fathom Halibut* | 2.00 | 1.50 | 0.536 | 0.02534 | 26 s | — | — |
| Abyss Grenadier | 1.90 | 1.50 | 0.536 | 0.02732 | 24 s | SNAP @ 0.8 s | LAND @ 23 s |
| Anchor Ray* | 1.75 | 1.40 | 0.546 | 0.03256 | 20 s | — | — |
| Trench Hagfish | 1.70 | 1.30 | 0.557 | 0.03574 | 18 s | SNAP @ 0.8 s | LAND @ 17 s |
| Lantern Dogfish | 1.60 | 1.45 | 0.541 | 0.03569 | 18 s | SNAP @ 0.8 s | LAND @ 17 s |
| Ribbon Eel | 1.50 | 1.40 | 0.546 | 0.03985 | 16 s | SNAP @ 0.8 s | LAND @ 16 s |
| Squall Garfish | 1.35 | 1.50 | 0.536 | 0.04341 | 15 s | SNAP @ 0.8 s | LAND @ 14 s |
| Drum Croaker | 1.30 | 1.15 | 0.573 | 0.05311 | 12 s | SNAP @ 0.9 s | LAND @ 11 s |
| Lodestone Bream / The Looker | 1.30 | 1.10 | 0.579 | 0.05421 | 12 s | SNAP @ 0.9 s | LAND @ 11 s |
| Inkwell Squid | 1.20 | 1.25 | 0.562 | 0.05597 | 12 s | SNAP @ 0.8 s | LAND @ 11 s |
| Glasspike | 1.15 | 1.20 | 0.567 | 0.05999 | 11 s | SNAP @ 0.9 s | LAND @ 10 s |
| Slate Cod | 1.25 | 0.90 | 0.603 | 0.06124 | 11 s | SNAP @ 1.0 s | LAND @ 10 s |
| Tallow Pollock | 1.20 | 0.95 | 0.596 | 0.06288 | 10 s | SNAP @ 1.0 s | LAND @ 10 s |
| Gannet Mackerel | 1.05 | 1.20 | 0.567 | 0.06657 | 10 s | SNAP @ 0.9 s | LAND @ 9 s |
| Mirrorjack | 1.00 | 1.35 | 0.551 | 0.06657 | 10 s | SNAP @ 0.8 s | LAND @ 10 s |
| Ember Snapper / Sable Hake | 1.10 | 1.00 | 0.590 | 0.06797 | 10 s | SNAP @ 1.0 s | LAND @ 9 s |
| Silver Ladder | 1.00 | 1.00 | 0.590 | 0.07549 | 9 s | SNAP @ 1.0 s | LAND @ 8 s |
| Stone Crab* | 1.00 | 0.80 | 0.615 | 0.08077 | 8 s | — | — |
| Chimefish | 0.90 | 0.80 | 0.615 | 0.09034 | 7 s | SNAP @ 1.1 s | LAND @ 7 s |
| Ghost Sole / Miller's Flounder* | 0.90 | 0.70 | 0.629 | 0.09325 | 7 s | SNAP @ 1.2 s | LAND @ 6 s |
| Rust Wrasse | 0.85 | 0.70 | 0.629 | 0.09900 | 7 s | SNAP @ 1.2 s | LAND @ 6 s |
| Lantern Herring | 0.80 | 0.65 | 0.636 | 0.10708 | 6 s | SNAP @ 1.2 s | LAND @ 5 s |
| Copper Sprat | 0.50 | 0.40 | 0.672 | 0.18594 | 3 s | SNAP @ 1.5 s | LAND @ 3 s |
| Bilge Blenny | 0.45 | 0.35 | 0.680 | 0.20964 | 3 s | SNAP @ 1.6 s | LAND @ 3 s |
| Gutter Prawn* | 0.40 | 0.30 | 0.688 | 0.23922 | 3 s | SNAP @ 1.7 s | — |
| Kelp Pipefish* | 0.35 | 0.25 | 0.696 | 0.27724 | 2 s | **LAND @ 1.6 s** | — |

\* net-only — these never reach the minigame.

**Line break** = `tension >= 1.0`. **Escape** = `progress <= 0.0`. The only escape route while *not* fighting is the strike-window timeout (1.3 s), or `_finish("")` triggered by walking >`CANCEL_DISTANCE = 6.0` m from the cast origin (`fishing_rod.gd:31, 519-521`), opening a UI panel, entering build mode, or losing power/blackout (`:401-403`).

**A separate, cosmetic bug fixed in-tree:** pressing LMB to strike now also sets `_reeling` immediately (`fishing_rod.gd:818`), so hold-through works.

---

## 1.7 The drop net (`scripts/components/drop_net.gd`)

Built from the `drop_net_kit` structure recipe (`recipes.json:drop_net_kit`: 2× rope + 1× driftwood, 3.0 s work).

| Constant | Value | Line |
|---|---|---|
| `DROP_MAX` | 26.0 m | `drop_net.gd:9` |
| `SOAK_MIN_SEC` / `SOAK_MAX_SEC` | 70.0 / 115.0 s | `:10-11` |

**States:** `UP_EMPTY → SOAKING → READY`. Verbs: `LOWER` when up, `HAUL` when soaking or ready (`:32-41`).

**LOWER** (`:59-89`) raycasts straight down `DROP_MAX`; `floor_dist = hit.y − 1.35` (basket hangs 1.1 m below the ring), `water_dist = max(from.y − 0.4, 0.5)`, and `_wet = water_dist <= floor_dist + 0.01`. A net hung over deck comes up dry with a toast. Soak time re-rolls 70–115 s. `_soaked_dark` is set immediately if `BloomFauna.is_dark_phase()` (NIGHT **or** DUSK, `bloom_fauna.gd:413-415`) and is latched true if it ever becomes true during `_process` (`:52-57`).

**HAUL** (`:91-131`):
- `soaked = 1.0` if READY else `1 − _soak_left/_soak_total`.
- Not wet → nothing. `soaked < 0.5` → nothing ("Too soon").
- Count = `1 + randi(0,1) + (1 if _soaked_dark)`, i.e. **1–3**, but forced to **1** if `soaked < 1.0`.
- Each fish is an independent `FISH.roll("net", ctx)`. `ctx["phase"]` is forced to `"night"` if `_soaked_dark`. **No depth argument** — the net never consults `drop_m`, so `deep`-only species are unreachable via net.
- On a full pack `add_item` fails and the fish is **silently discarded** (`:126`) — no ground drop, unlike the stove.

**Differences from the rod:** no bait, no minigame, no depth, no fouling, no cast, no escape, no size roll at the rail (weights are rolled lazily at cook/dry time via `FishTable.take_size`). It is the only route to Stone Crab, Gutter Prawn, Miller's Flounder, Kelp Pipefish, Anchor Ray and Fathom Halibut.

**Third method — hand grabs.** `BloomFauna.FiddlerShoal` GRAB yields `fish_herring` within 1.4 m from the deck; `BloomFauna.ReefFish` GRAB yields `fish_copper_sprat` within 1.2 m while swimming (see §3). These bypass the fish table entirely.

## 1.8 Gear, tiers and line strength

**There are none.** Two rod items exist:

| Item | Where | Craftable? | Stats |
|---|---|---|---|
| `fishing_rod` | 3 world placements: wet deck `(11.0, y+0.05, −17.2)` and `(16.5, y+0.05, −16.75)` (`wet_deck_detail.gd:499, 506`), plus `(27.0, y+0.05, 9.5)` (`rig_builder.gd:2429`) | No | none |
| `deep_rig_pole` | 1 placement, on the crane machinery deck `(CRANE_X+2.0, CRANE_DECK_TOP+0.12, CRANE_Z−1.4)` (`rig_builder.gd:1631`) — "a reward for making the climb" | No | none |

`items.json` gives both `{"use":"tool"}` with no numeric fields. All fight constants (`REEL_RATE`, `TENSION_DECAY`, the 1.0 break threshold, `BITE_WINDOW`) are class constants on `FishingRod`. There is **no line-strength stat, no durability, no bait quality tier beyond the two glow-worm entries, and no upgrade path**.

## 1.9 Size, yield and preservation

- **Weight is rolled at the rail only for rod catches** (`fishing_rod.gd:696`), using `t = randf() * randf()` — a strongly small-skewed distribution, mean t = 0.25, so mean weight = `lo + 0.25·(hi−lo)`. A 48 kg grouper has ~1 in 100 odds at the top decile.
- Weights are stored in a **static FIFO queue per species** (`FishTable._sizes`, `fish_table.gd:255`) and popped by the stove/drying line. **Not saved** — a reload re-rolls, which is documented (`fish_table.gd:252-254`).
- `fillets_for(id, kg)` linearly maps kg across `size_kg` onto `fillets` (`fish_table.gd:289-300`).
- **Stove** (`cook_stove.gd`): 6.0 s cook, requires circuit `topside_floodlights`, produces `n` portions; surplus beyond the pack is dropped as real world items (`:222-230`).
- **Drying line** (`hang_line.gd`): 4.0 game hours; raw → `fish_rotten`, cooked → `dried_fish`, **but a `is_big()` species cures straight from raw into `n × dried_fish`** (`hang_line.gd:7-12`). Only Barrel Grouper, Fathom Halibut, Fathom Sturgeon, Abyss Grenadier, Giant Oarfish and Coelacanth qualify (`fillets[1] > 1`).
- **Cold store** (`cold_store.gd`): powered = spoil clock frozen; unpowered = won't open and turns after `FRESH_HOURS = 4.0` warm game hours.
- One game hour = `24 / (60 min × 60) = 0.4` real seconds… precisely: `_game_hour_per_sec = 24 / total_day_seconds = 24/3600 = 0.006667` game-hours per real second, i.e. **1 game hour = 150 real seconds**, so 4 game hours = **10 real minutes**.

---

# SECTION 2 — WEATHER & ENVIRONMENT

## 2.1 Weather states

There is exactly **one** weather system: `StormSystem` (`scripts/world/storm_system.gd`), plus a derived post-squall **sea fog**. There is no wind-only state, no snow, no calm/overcast distinction — "clear" is the absence of storm.

`enum StormPhase { CLEAR, RAMP_IN, RAGING, RAMP_OUT }` (`storm_system.gd:8`).

| Constant | Value | Line |
|---|---|---|
| `RAMP_IN_SEC` | 22.0 | `:40` |
| `RAMP_OUT_SEC` | 32.0 | `:41` |
| `FIRST_DELAY_MIN/MAX` | 45.0 / 100.0 s | `:42-43` |
| `CALM_MIN/MAX` | 220.0 / 450.0 s | `:44-45` |
| `RAGE_MIN/MAX` | 90.0 / 210.0 s | `:46-47` |
| `FOG_CHANCE` | 0.55 | `:69` |
| `FOG_HOLD_MIN/MAX` | 120.0 / 260.0 s | `:70-71` |

**Transitions (`_advance_schedule`, `:228-255`)** — a pure timer chain, **not** driven by time of day, player action, or anything else:

```
CLEAR    → (timer 220–450 s) → RAMP_IN, timer = 22 s, wind re-rolled
RAMP_IN  → intensity → 1.0 at 1/22 per s → (22 s) → RAGING, timer = 90–210 s
RAGING   → intensity → 1.0 at 0.5/s; wind wanders at 0.15/s
         → (90–210 s) → RAMP_OUT, timer = 32 s; roll fog (55 %)
RAMP_OUT → intensity → 0.0 at 1/32 per s → (32 s) → CLEAR, timer = 220–450 s
```

First storm arrives within **45–100 s of a new game**. `trigger_storm()` (`:88-92`) is a debug hook bound to `debug.gd:41`.

`is_storming()` is `_intensity > 0.25` (`:94-95`), which is reached ~5.5 s into RAMP_IN and lost ~8 s into RAMP_OUT. **Expected cycle: 22 + 150 + 32 + 335 = 539 s, of which ~172 s reads as storming ≈ 32 %.**

**Fog** (`_advance_fog`, `:260-265`) is independent: builds at 0.05/s, lifts at 0.02/s, held for 120–260 s. It is pushed to `SunController.set_fog()`.

**Wind** is a `Vector2`, re-rolled at each storm start and drifting during RAGING. It only affects rain slant, rain-box offset, and ambience mixing.

## 2.2 What weather actually affects

| System | Effect | Citation |
|---|---|---|
| **Fishing — species pool** | `storm: only` → `w = max(w,4)×3`, else 0. `storm: never` → 0 while storming. `storm: bonus` → ×2. | `fish_table.gd:149-157` |
| **Fishing — bite rate** | `bite_pace ×0.55` while storming (nearly twice as fast) | `fish_table.gd:344-345` |
| **Sea state / waves** | `sea_state = lerp(0.4, 1.0, intensity)` pushed to the ocean shader **and** to `Gyre.set_sea_state()` so CPU and GPU seas agree. Gerstner amplitude scales `0.18 + 0.92·ss`, steepness `0.35 + 0.65·ss` — full storm is **~2× wave height** vs calm. | `sun_controller.gd:16-39`, `gyre.gd:77-79` |
| **Sky / lighting** | `sun.light_energy ×= (1 − 0.9·storm)`; moon energy `×(1 − 0.8·storm)` and hidden above `storm 0.9`; ambient lerps to slate `(0.18,0.2,0.24)`; ambient energy floor drops to 0.14; volumetric fog density `lerp(0.012, 0.05, storm)`; `fog_density lerp(0.0008, 0.004, storm)`; stars extinguished via the `storm` shader uniform | `sun_controller.gd:136, 150-151, 176-184` |
| **Sun shadows** | Cascade auto-disables when `light_energy < 0.03`, re-enables at `> 0.08` — a heavy storm turns it off (a documented 41 %-of-frame saving) | `sun_controller.gd:187-208` |
| **Post-squall fog** | `volumetric_fog_density += 0.05·fog`, `fog_density += 0.0068·fog`, `sun.light_energy ×= 1 − 0.38·fog` | `sun_controller.gd:181-185` |
| **Rain visuals** | 5000-particle GPU emitter pinned above the player, `amount_ratio = intensity`, `wind_drift = wind × 11 × i`, culled inside 16 hand-authored `COVER_BOXES` by the shader | `storm_system.gd:99-136, 270-280, 298-311` |
| **Rain visibility** | Hidden entirely below the waterline (`eye.y > wave_height × 0.85`) | `storm_system.gd:309-311` |
| **Lightning** | Only above `intensity 0.4`. Flash energy `lerp(1.6, 4.5, near)` + a secondary flicker at 0.09 s; thunder delayed `lerp(2.6, 0.3, near)` s at `lerp(−16, +2)` dB; recharge `randf(5,15) × (1.5 − intensity)` | `storm_system.gd:313-337` |
| **Ambient audio** | 5 crossfaded beds; `wind_open ×(1 + 1.1·storm)`, `wind_howl ×(0.55 + 0.85·storm)`, `sea_swell ×(0.75 + 0.6·storm)`, `hull_groan ×(0.65 + 0.75·storm)` and ×1.25 at night | `ambience.gd:250-284` |
| **Rain audio** | Separate `RainAudio` bed fed `(intensity, roof_dist, cover_frac, submerged)`; ducked entirely when submerged | `storm_system.gd:291-296` |
| **Rain Catcher** | The only *gameplay* rain coupling: a docked empty vessel fills only while a squall is on **and** the cradle is outside every `COVER_BOX` | `rain_catcher.gd:15-21` |
| **Marine snow / underwater FX** | `underwater_world.gd:993`, `underwater_fx.gd:278` scale with intensity | — |
| **Visible fish schools** | `storm: only` species' schools become visible **only** while `_storm_intensity() > 0.15` (empty `active` array as sentinel) | `underwater_world.gd:1021-1032` |
| **Player warmth / wetness / life** | **NOTHING.** No wetness stat exists; `PlayerState._process` reads only `warmth_zone` and `GameClock.current_phase == NIGHT` | `player_state.gd:167-181` |
| **Crab / king crab / shark / all Bloom fauna** | **NOTHING.** No fauna script references storm state at all | verified across `crab.gd`, `king_crab.gd`, `shark.gd`, `bloom_fauna.gd`, `reef_life.gd`, `harvest_nodes.gd` |

## 2.3 Shelter probing and the rain-cover model

Two independent probes exist:

1. **`StormSystem._update_shelter()`** (`:203-226`) — 5 upward rays (centre + ±2.5 m in x/z), 40 m reach, mask 1. Produces `_cover_frac` (0–1) and `_roof_dist`. **These now only shape rain AUDIO** — the comment at `:64-67` is explicit that they no longer gate visuals.
2. **`Ambience`'s own cone** (`ambience.gd:46-50`) — same idea, ±1.5 m offsets, re-probed 8×/s, driving the 5 audio beds.

Rain **visuals** are gated by 16 axis-aligned `COVER_BOXES` baked into the particle shader with a 0.35 m lateral/downward margin (never upward) (`storm_system.gd:21-38, 161-172`). Box #4 — `[−30,−1.5,−20] .. [30,17,20]` — roofs the entire shadow of the topside plate, so the wet deck, boat approach lanes and pontoon walkway are all treated as indoors.

**This is a whole-volume test with no fidelity**: any position inside a box is dry regardless of walls or openings. There is no drop-by-drop collision (the project is `gl_compatibility`, which has no particle collision).

## 2.4 Day/night cycle

`GameClock` (autoload, `scripts/autoload/game_clock.gd`).

| Phase | Duration | Sun elevation curve | Night blend |
|---|---|---|---|
| DAWN | **5.0 min** | `lerp(−8°, 16°, f)` | `1 − smoothstep(0, 0.5, f)` |
| DAY | **34.0 min** | `16° + 40°·sin(f·π)` (peak 56°) | 0 |
| DUSK | **8.0 min** | `lerp(16°, −12°, f)` | `smoothstep(0.55, 1.0, f)` |
| NIGHT | **13.0 min** | `lerp(−12°, −8°, f)` | 1 |

`phase_durations_minutes` at `game_clock.gd:17-22`; elevation at `sun_controller.gd:90-99`; night blend at `:101-110`.

- **A full day is 60 real minutes.** DAY is 57 % of it, NIGHT 22 %.
- **A new game starts in DAY at f = 0** (`game_clock.gd:30`), deliberately, because DAWN at f = 0 renders as night.
- `day_count` increments when NIGHT *completes* (`:50-51`).
- Azimuth sweeps `lerp(80°, 280°, global_day_fraction)`, where the fraction is DAWN 0–0.12, DAY 0.12–0.84, DUSK 0.84–1.0, NIGHT pinned at 0.999 (`sun_controller.gd:132, 216-225`). **The sun's azimuth freezes for the whole of NIGHT.**
- Moon runs its own arc: elevation `6° + 48°·sin(π·mf)`, azimuth `lerp(95°, 265°, mf)`, where `mf` is 0–0.14 across DUSK, 0.14–0.86 across NIGHT, 0.86–1.0 across DAWN (`:115-124, 146-149`). Moon energy `0.28 · night`.
- **What changes at night:** warmth drains at `warmth_per_sec_night = −0.0015` (`tuning.json:9`, read `player_state.gd:172-173`); ambient collapses to `AMBIENT_NIGHT (0.1, 0.14, 0.24)`; `spill_lights` (interior daylight spill) track `0.55 × sun energy` so interiors go black; crab aggression goes to 1.0 and crabs may emerge; jellies, glow worms, lamp eel, barnacles, the mantle ray, the whale and the lamp snails all activate; `lit` becomes possible for `light: drawn` fish.

## 2.5 Storms: hazards to the player

**There are none.** Nothing in `storm_system.gd` touches `PlayerState`. Lightning is a light + a sound; there is no strike target, no damage, no wind force on the player, no slippery deck, no wave knockback.

The *only* survival hazards in the game are:
- Hunger/thirst reaching 0 → `LIFE_DRAIN_PER_SEC` (`player_state.gd:190-191`).
- Cold: `warmth_per_sec_cold = −0.004` inside a `WarmthZone(mode −1)` (flooded pump room), `−0.0015` at night, offset by `patched_boots` `cold_relief` and by `warmth_per_sec_heated = +0.02` in a powered heater zone (`tuning.json:6-10`, `player_state.gd:167-181`).
- Swimming: `SWIM_WARMTH_DRAIN = 0.016/s` — **11× the night cold rate** (`player_controller.gd:82` (`SWIM_WARMTH_DRAIN`)).
- Drowning: oxygen `1/28` per second submerged, `1/16` below `DEEP_UNEASE_M = 16.0` m, `DROWN_GRACE_SEC = 1.2` (`player_controller.gd:87-91`). Surfacing recovers at 0.5/s, land at 1.5/s. **There is no fixed depth death line any more.**
- Crab bite (−0.2 life), king crab bite (−0.34 life), shark bite (−0.5 life and −0.1 warmth).
- Raw food `side_effect: sick`; bare-hand barnacle scraping (−0.02 life).

---

# SECTION 3 — ANIMAL / NPC BEHAVIOUR

## 3.1 Roster

Two spawners: `BloomFauna` (added by `main.gd:31`) and `main.gd:37-38` for the sharks. `ReefLife` is added under the seabed (`seabed.gd:116` ← `reef_detail.gd:36`). `UnderwaterWorld` adds the decorative deep giants.

| Species | Count | Where | Harms player | Player interaction |
|---|---|---|---|---|
| Giant Crab | 8 | Caisson-leg roosts, underwater by day | **Yes, −0.2 life** | Kill (6 hp) → HARVEST 8× `crab_leg` |
| King Crab | 2 | Deep water at SE caisson foot `(27, −8, −9.5 / −12.5)` | **Yes, −0.34 life** | Cannot be killed; beat back only. **No reward.** |
| Ultra Hammerhead | 3 | Three ellipse patrols in open water | **Yes, −0.5 life, −0.1 warmth — only while swimming** | None |
| Gull (high flyer) | 5 | y 40–52, circling | No | None |
| Deck Gull | 4 | Wet deck ×2, topside ×2 | No | GRAB → `raw_sea_bird`, 60–120 s regen |
| Corvid Gull | 3 | Rails; one is a thief | No | None (steals your deck items) |
| Jelly Drifter | 7 | Surface orbit, night/dusk | No | None |
| Lamp Eel | 1 | North surface, night only | No | None |
| Fiddler Shoal | 18 fish | Surface near-rig, all phases but night | No | GRAB → `fish_herring`, 50–110 s |
| Reef Fish | 2 × 9 | −1.6…−4.2 m around two legs | No | GRAB → `fish_copper_sprat` (**must be swimming**) |
| Mantle Ray | 1 | Aerial night flyover, 45 s pass | No | None |
| Epic 4-Eyed Whale | 1 | Aerial night flyover, 60 s pass | No | None |
| Harbor Seal | 2 | 1 hauls out on the wet deck, 1 permanently in water | No | **PET / FEED** |
| Lamp Snail | 6 | Pontoon tops at leg bases | No | GRAB / **HARVEST** (`glow_mucus`, 150 s cd) / FEED / COLLECT |
| Rust Snail | 4 | Splash-zone seams | No | GRAB / FEED / COLLECT |
| Glass Snail | 4 | Submerged plate `y −1.3` under the wet-deck lip | No | GRAB / FEED / COLLECT |
| Anchor Limpet | 5 | Splash-zone leg faces | No | **PRY** (needs `prybar`) → `limpet_shell`, **one-shot** |
| Barnacle Cluster | 5 | Waterline leg faces | No | None (the harvestable crust is a separate salvage node) |
| Tide Worm | 5 | Tide line, dawn/dusk only | No | None |
| Glow Worm | 8 dens, 2 live/night | Wet deck + 2 topside | No | GRAB → `glow_worm`, 90–150 s (dark-only timer) |
| Flora (kelp/creeper/anemone) | 10 patches | 3 creeper splash zone, 4 kelp `y −4.2`, 3 anemone | No | **None — not harvestable** |
| Reef life (corals, sponges, urchins, nudibranch, isopod, octopus, deep angler, salps…) | many | Sea-floor shelves −6 m and below | No | **None — no colliders at all** |
| Deep giants (grouper ×4, halibut ×3, coelacanth, Leviathan) | 8 + 45 % chance | −12 to −29 m circuits; Leviathan at **−76 m** | No | None (decorative) |

## 3.2 The Giant Crab in detail (`scripts/world/crab.gd`, 1547 lines)

### Spawn
- `CRAB_COUNT = 8` (`bloom_fauna.gd:50`), placed on 8 of 10 authored cling loops across the four caisson legs (`bloom_fauna.gd:69-97`). At count 8 the SE(3) + NE(2) + SW(3) roosts are used; the NW pair is unpopulated dead data.
- Each is injected with `roost_loop`, `roost_up`, `leg_climb`, `emerge_path`, `patrol_loop`, `patrol_offset`, `spawn_index` (`bloom_fauna.gd:196-228`).
- The SE leg has **no** support climb (the wet deck is built through that caisson), so those three crabs use the east-rim lane on `CRAB_EMERGE_Z = [−8,−11,−14,−17,−20,−22]` (`bloom_fauna.gd:65, 99-101, 158-177`).

### Night no-show roll
`SURFACE_CHANCE = 0.5` (`crab.gd:92`), rolled per crab on the `GameClock.night` signal (`crab.gd:350, 739-740`). Two consequences:
- `_surface_tonight` **defaults to `true`** (`crab.gd:127`), and `_wants_up()` is true in the back half of DUSK (`phase_fraction() > 0.45`, `crab.gd:731-736`), so **on the very first dusk of a run all 8 crabs come up unrolled**.
- If NIGHT then rolls false, a crab already on deck turns round and goes home (`crab.gd:810-812`).

### State machine
`enum State { ROOST, EMERGE, PATROL, PURSUE, FLEE, GONE, CLIMB, DEAD }` (`crab.gd:45`). **`GONE` is never assigned** — dead enum value.

| State | Entry | Behaviour | Exit |
|---|---|---|---|
| ROOST | initial / end of flee / respawn | Free wander on the leg face at `ROOST_SPEED 0.5`, 0.6–3.0 s holds, 35 % sidle flip | `_wants_up()` && !`_beaten` && `_scare_cd<=0` → CLIMB (leg route) or EMERGE |
| EMERGE | ROOST | Free 3D swim along `emerge_path` at `SWIM_SPEED 3.4` | Path end → wet deck, PATROL |
| PATROL | after emerge/climb/give-up | `_sense(player)`, else roam at `_roam_speed()` = `patrol_speed × 1.0` at night, `× 0.8` otherwise | sense hit → PURSUE or CLIMB |
| CLIMB | `_begin_climb_toward` / `_begin_leg_climb` | Walk the authored link at `CLIMB_SPEED 2.2` | buffer done → re-target or PATROL + `_hunt_cd` 2–6 s |
| PURSUE | `_sense` same-level hit, or surviving a melee hit | Straight at the player's x/z at `pursue_speed`; `_try_bite` inside `contact_radius` | player gone / aggression 0 → FLEE; past `give_up_dist` for `COMMIT_TIME 4.0` s → PATROL + `_hunt_cd` 4–12 s |
| FLEE | light scare / rout / dawn | Two behaviours: scare-retreat 4 m away at `pursue_speed × 0.8` for `RETREAT_TIME 3.2` s; or full rout home (descend at `CLIMB_SPEED × 1.2`, walk `emerge_path` backwards, swim home at `SWIM_SPEED × 0.7`) | scare over → PATROL; home → ROOST |
| DEAD | `_die()` | Flop (`DEATH_FLOP 3.0`), curl `(0.9, 0.82, 0.9)`, corpse collider goes live | respawn on the next `GameClock.dusk` |

### Tuning — every `crab_*` key in `tuning.json` **is** read, once, in `_ready`

| key | value | read at | field | used at |
|---|---|---|---|---|
| `crab_patrol_speed` | **1.6** | `crab.gd:336` | `patrol_speed` | `_roam_speed()` `:835-836` |
| `crab_chase_speed` | **4.0** | `crab.gd:337` (fallback **4.4 — stale**) | `pursue_speed` | `_pursue` `:898`, retreat ×0.8 `:922` |
| `crab_sense_radius` | **11.0** | `crab.gd:338` | `detect_radius` | `_sense` `:854` |
| `crab_hunt_radius` | **46.0** | `crab.gd:339` | `hunt_radius` | cross-deck hunt gate `:864` |
| `crab_give_up_dist` | **26.0** | `crab.gd:340` | `give_up_dist` | `:882` |
| `crab_bite_reach` | **1.45** | `crab.gd:341` | `contact_radius` | bite `:908`, boxed-in ×1.8 `:899` |
| `crab_light_scare_bright` | **2.35** | `crab.gd:342` | `scare_bright` | `:1238` |

Other constants: `MAX_HP 6.0` (`:88`), `HARVEST_LEGS 8` (`:89`), `BITE_DAMAGE 0.2` (`:96`), `BITE_COOLDOWN 1.6` (`:97`), `BITE_SHOVE 7.0` (`:98`), `SCARE_TIME 0.55` (`:99`), `SAME_LEVEL_Y 2.6` (`:100`), `COMMIT_TIME 4.0` (`:101`), `FLARE_DETER 5.0` (`:102`), `RETREAT_TIME 3.2` (`:103`), `EMERGE_STAGGER 2.0 × spawn_index` (`:104`) — so crab 7 waits 14 s after the cue.

### What it reacts to
- **Time of day.** `_aggression()` (`:718-727`): NIGHT 1.0, DUSK 0.65, DAWN 0.35, **DAY 0.0**. Effective detection radius = `11.0 × aggression × player.detection_factor()` → 11.0 night, 7.15 dusk, 3.85 dawn, **0 by day**.
- **Posture.** `detection_factor` = 1.0 standing / 0.5 crouched / 0.3 prone (`player_controller.gd:196-205`).
- **Deck level.** Same-level requires `|dy| < 2.6`. Cross-deck hunting requires `flat < 46`, `aggression ≥ 0.6` (night or dusk only) and `_hunt_cd ≤ 0`; failure re-arms `_hunt_cd` to 6–26 s.
- **Light — three separate mechanisms.**
  1. *Brightness scare*: `light_pressure_at` measured at body + 0.3 m against `2.35`, held **0.55 s**. Flashlight contributes `4.0 × falloff(d, 22 m) × cone(32°)`; the storm lantern maxes at **1.5 and can never trip the bar**; burning flares are read from their real `OmniLight3D` (2.6 energy / 8 m). Deliberately not checked during CLIMB (`:1232-1236`).
  2. *No-go volumes*: any powered `LightZone` containing the point, or any lit flare within `FLARE_DETER 5.0` m (`:1165-1171`). Blocked, the crab tries both tangents and otherwise **holds at the edge facing you — it does not forget you** (`:1307-1317`).
  3. The scare puts it in FLEE for 3.2 s and re-arms `_scare_cd` to **8–14 s**.
- **Noise: nothing.** **Storms/weather: nothing.** **Player swimming: nothing** — detection is pure XZ distance plus `|dy|`.

### Damage
`_try_bite` (`:656-672`) at `d < 1.45` m: `PlayerState.life −= 0.2`, cooldown 1.6 s (**0.125 life/s sustained — five bites kill from full**), knockback `dir × 7.0 + UP × 2.0`, `"crab_snap"` at −6 dB, 0.5 s self-recoil, HUD toast. **No warmth/hunger/status effect.**

### Player interactions
- **Melee.** In group `"hittable"`; `player_controller._melee_attack` (`:467-496`) passes `melee_damage` through `repel(from, damage)` (`crab.gd:460-482`). Requires target inside `melee_reach` and `dot > 0.4` of the swing arc, rate-limited by `swing_sec`. 6.0 hp → crude_knife (1.0) ×6, honed_knife (1.6) ×4, crude_spear (1.7) ×4, honed_spear (2.6) ×3. Each surviving hit: 0.4 s recoil, 0.55 m shove, forces PURSUE with a fresh 4 s commit.
- **Death** (`:490-517`): `_legs_left = 8`, corpse collider `collision_layer = 1`, `Journal.discover("creature_lamplight_crab")`.
- **HARVEST** (`:544-568`): the corpse's only verb; loops `add_item("crab_leg")` until the pack is full or the shell is bare. **No cooldown.** `crab_leg` = hunger 0.1 + sick raw; `crab_leg_seared` = 0.45 (2.5 s recipe); also legal deep-rig bait.
- **Respawn** on the next `GameClock.dusk` only (`:579-585`) — a kill removes that crab for the rest of the night **and** the whole following day; the corpse stays harvestable through daylight.
- **No pet, no feed, no pry, no tame.**

### Movement / animation notes
- **Sidle**: with no focus the body faces 90° off heading, side alternating per `_sidle_sign` (seeded even/odd by `spawn_index`), flipped 35 % of the time at each roam leg (`:1272-1282, 344, 758-759`).
- **No claw overlay** — menace is expressed on the generated mesh: −0.30 rad rear-back in PURSUE, +0.11 m stand height, a `0.34·sin(26t)` snap lurch (`:392-398, 1489-1503`).
- **Surface seating** via `FaunaMove.seat`; CLIMB and the FLEE descent own their own `up` and stay unseated (`:1348-1360`).
- **Three shader beats only**, written once per state change: 0.45/0.02 resting, 3.6/0.07 pursuing, 1.6/0.045 otherwise (`:1476-1481`), guarded because a live rate change teleports the shader phase.
- **Unstick guard** (`:1423-1447`): after 3.0 s of moving < 0.05 m, CLIMB skips a waypoint, EMERGE relocates, otherwise it snaps onto the nearest `patrol_loop` anchor — and `_relocate` refuses to teleport if the player is within 45 m and it is not behind the camera.
- **Navigable rig graph** = 12 levels (`crab.gd:210-297`). **Deck C (25.1), Deck D (28.6) and the stack roof (32.1) are not authored**, so a crab hunting you up there climbs to Deck B and holds.

### Dead / stale in crab.gd
`L_OPS` (`:207`) unreferenced; `State.GONE` never assigned; `_dead_t` write-only; `_gait_t` only feeds the procedural fallback legs (dead once the .glb loads); `_beaten` only ever set inside `_die` and read in a state a dead crab never runs; `_resume_state` is always `PATROL`; the 4.4 fallback and three comments citing it; `crab.gd:331-335` describes tuning keys that no longer exist.

## 3.3 King Crab (`scripts/world/king_crab.gd`)

- **2 only** (`bloom_fauna.gd:255`), dens at `(27.0, −8.0, −9.5)` and `(27.0, −8.0, −12.5)`.
- **Never hauls out on night one**: `if GameClock.day_count == 0: _committed = false` (`king_crab.gd:269-271`). Otherwise `HUNT_CHANCE = 0.5` per night, then a haul-out delay of `randf(8, 90) + spawn_index × 25` s.
- States `DEN → RISE → HUNT ⇄ CLIMB ⇄ PURSUE → RETREAT → DEN`; `GONE` never assigned.
- `SHELL_M 3.0`, `HUNT_SPEED 1.05`, `CHASE_SPEED 3.0` (deliberately slower than the 3.2 m/s walk), `SWIM 2.8`, `CLIMB 1.5`, `DETECT 15.0`, `HUNT_RADIUS 46.0`, `GIVE_UP 34.0`, `CONTACT 2.35`, `BITE_DAMAGE 0.34`, `BITE_COOLDOWN 2.4`, `BITE_SHOVE 11.0`, `MAX_HP 9.0`, `SCARE_BRIGHT 3.4`, `SCARE_TIME 1.4`, `COMMIT_TIME 6.0` (`king_crab.gd:50-89`). **It reads no `tuning.json` keys at all.**
- Its `_sense` has **no aggression scaling and no `_hunt_cd`** — it always commits to the stairs.
- **It cannot be killed.** At `hp ≤ 0` it sets `_beaten`, clears `_committed` and goes home; hp is restored the next night (`:263, 325-330`). **No corpse, no FaunaTouch, no harvest, no reward of any kind.**
- Avoidance: outrun past 34 m for 6 s; stand in a powered `LightZone` or flare pool; hold the beam on it for 1.4 s (2.4 s backoff + 5–9 s cooldown); climb to Deck C/D/roof (unauthored); or wait for dawn.
- Joins group `"giant_crab"` only while up on the rig (`:292-305`).
- Stale docstring at `:12` says the ordinary crab's pool is three (it is 6).

## 3.4 Ultra Hammerhead (`scripts/world/shark.gd`)

- **3 sharks**, spawned by `main.gd:37-38`. Per-index ellipse: centres `(0,0,−38)`, `(30,0,8)`, `(−34,0,−4)`; radii 14/18/22 m; depths −2.6/−3.8/−5.0 m (`shark.gd:41-43`).
- `NOTICE_RADIUS 9.0`, `BITE_RADIUS 1.6`, `ATTACK_CHANCE 0.7`, `BITE_DAMAGE 0.5`, `PATROL_SPEED 3.6`, `CHARGE_SPEED 8.5`, cooldown 12–22 s (`:10-17`).
- **Every aggression path is gated on `player.swimming`.** Leave the water and a charge aborts instantly (`:192-195`). Surface swimming counts; there is no depth requirement.
- On notice it rolls once per approach: 70 % CHARGE, 30 % CIRCLE (one slow 5 m ring, ≤7 s).
- `_bite` (`:205-220`): `life −= 0.5` **and** `warmth −= 0.1`, knockback `away × 6 + UP × 2`, then a **mandatory flee** to a point 18 m off and a 12–22 s cooldown — **one bite per pass, by design**.
- Not in `"hittable"`, no `repel()` — **cannot be attacked**. No light, weather or time-of-day reaction. Only interaction is `Journal.discover("creature_hammerhead")`.

## 3.5 The rest of the fauna — condensed

**Gull (5)** `bloom_fauna.gd:685-798` — parametric circles at y 40–52, radius `10 + idx×3.5`. DAY/DAWN only; `_leave` eases the radius out by 220 m and the altitude by 60 m otherwise. No AI, no interaction.

**Deck Gull (4)** `:2162-2341` — strut/peck loop at **0.55 m/s** within ±2.2 m of home; targets re-pick every 2.5–6.0 s. Flush roll `gull_flush_roll(range 10 m, chance 0.34, crouch ×0.3)` fires each time you creep another whole metre closer than ever before; non-crouched inside 1.5 m always flushes. Flies at 6.5 m/s + 3.2 m/s climb, vanishes after 3 s, respawns in 45–90 s. **GRAB** within 1.6 m → `raw_sea_bird`, then 60–120 s regen.

**Corvid Gull (3)** `:2914-3159` — perched, DAY/DAWN. Watches you within 20 m. One of the three (`i == 1`, bunkhouse rail) is a **thief**: every 90–160 s it looks for any `Takeable` on the open topside deck (`y 17.9–19.6`, `|x|<30`, `|z|<22`) within 26 m whose id is not in `NEVER_STEAL = [cable_spool, fishing_rod, throwing_hook, prybar]`, flies to it at 6.0 m/s, frees it, carries it to the **gull nest LootContainer at `(−20, 21.25, 12)`** and appends it to that container's items. Fleeing mid-heist destroys the carried visual. Not grabbable.

**Jelly Drifter (7)** `:800-877` — dark-phase (`is_dark_phase()` = NIGHT **or** DUSK) surface orbit, radius `15 + idx×3.2 ± 2`. Cosmetic.

**Lamp Eel (1)** `:959-1078` — **NIGHT only**, 9-segment follow-the-leader chain doing figure-eights off the north edge, riding the real Gerstner surface. Cosmetic.

**Fiddler Shoal (18)** `:1080-1203` — visible every phase **except NIGHT**; shoal centre orbits `x = 19 + 8cos`, `z = −10 + 7sin`, at the surface. **GRAB within 1.4 m from the deck** → `fish_herring`; that fish hides for 50–110 s then returns. No repeat limit.

**Reef Fish (2 × 9)** `:2343-2435` — around two legs at `(19,0,−12)` and `(22,0,9)`, each fish at `−4.2…−1.6` m, orbit radius 1.2–3.2 m, half the shoal counter-rotating. Three colour lineages by `i % 3`. **GRAB requires `player.swimming` and 1.2 m** → `fish_copper_sprat`, 50–110 s rejoin. Always present, no day/night gate.

**Mantle Ray (1)** `:1205-1302` — NIGHT only; a 360 m straight pass at altitude 38–50 m taking exactly 45 s, then 90–150 s cooldown. Seeing it *and* having read `roof_mark` unlocks `codex_the_count`.

**Epic 4-Eyed Whale (1)** `:1532-1664` — NIGHT only; 480 m pass at 45–55 m altitude over 60 s, 120–180 s apart. Four eyes blinking on uneven clocks.

**Harbor Seal (2)** `:1666-1863` — only the even-index seal ever hauls out (`_idx_zero()`); the other is a permanent water patroller porpoising for breath on a loop south of the rig. Haul-out is re-rolled every 35–70 s: DAY **and** 55 % **and** even index → `HAUL_SPOT (9.0, 2.25, −21.2)`. Within 18 m the head tracks you. **FaunaTouch: `PET` always (deck-side only — the verb list is empty while it is swimming); `FEED` added if you carry any of `[fish_herring, fish_slate_cod, fish_mirrorjack, fish_chimefish, fish_sable_hake]`.** FEED consumes one fish and sets `_fed` permanently (glow floor 0.3 → 0.65); PET gives a 2.0 s wiggle bump. **Neither has a cooldown or a limit.**

**Snails** — three species, all sharing `bloom_fauna.gd:418-605`:
| | Lamp Snail (6) | Rust Snail (4) | Glass Snail (4) |
|---|---|---|---|
| Where | Leg bases on the pontoon tops | Splash-zone seams (4 authored segments) | Submerged plate `y −1.3` under the wet-deck lip |
| Crawl | FREE disc, leash 4.2, speed **0.13** | SEAM patrol along an axis, speed **0.1** | FREE disc, leash 3.0, speed **0.08** |
| Night | Spots glow 2.0 + an `OmniLight3D` (0.65 energy, 3 m) | No gate — active all phases | No gate |
| Reacts | — | — | Within **7 m** turns its lit gut coil toward you |
| Verbs | **COLLECT** (crouching) → `snail_live`, animal freed permanently · **HARVEST** (NIGHT, `_harvest_cd ≤ 0`) → `glow_mucus`, **150 s cooldown** (glow visibly regrows) · **FEED** (`kelp_bundle`) · **GRAB** | COLLECT / FEED / GRAB (**no HARVEST**) | COLLECT / FEED / GRAB |

Shared: `GREENS = ["kelp_bundle"]`, `BREED_RADIUS 4.0`, `BABY_SCALE 0.4`, `GROW_HOURS 48.0` (≈2 game days). Two **fed** snails of the *same script class* within 4 m breed at the midpoint and both parents' `_fed` resets. Babies cannot be fed but can be COLLECTed. Carrying a fed snail to another fed one is the intended breeding loop. `snail_live` → `escargot` at the stove; also legal deep-rig bait.

**Anchor Limpet (5)** `:2823-2912` — never moves. Within **3.2 m** it clamps (rim light out, shell squashed to 0.82, BREATHE animation stops). **PRY only while holding a `prybar`** → `limpet_shell` ×1 and the animal is **freed permanently — one-shot, no respawn**.

**Barnacle Cluster (5)** `:879-957` — sessile, feeds only at NIGHT; snaps its cirri shut if the player is within 4.5 m. No interaction.

**Tide Worm (5)** `:1304-1360` — emerges only at DAWN or DUSK; retracts at 2.5/s within 2.5 m, re-emerges at 0.35/s. No interaction.

**Glow Worm (8 dens, exactly 2 live per night)** `:1362-1530` — den pair re-rolled on `GameClock.dusk` and nudged off the previous pair. Catchable only when active, not regenerating, in a dark phase, and `_presence > 0.6`. **Trigger radius 4.5 m standing, 1.8 m crouched; retreat 1.25/s standing vs 0.5/s crouched — crouch-sneaking is the whole mechanic.** GRAB → `glow_worm`; den closes for 90–150 s **and that timer only ticks during dark phases**.

**Flora (10 patches)** `:2437-2475` — 3 `glow_creeper` in the splash zone, 4 `glow_kelp` at `y −4.2`, 3 `bloom_anemone` under the barnacle faces. Static; motion is entirely the `SWAY`/`CIRRI` vertex shader. **Not harvestable — `kelp_bundle` comes only from the Kelp Growth salvage nodes.**

**Reef life** (`reef_life.gd`, deterministic seed 60640) — coral fans, sponges, brain corals, urchins, seastars, sea cucumbers, tube worms, sea grass, salp chains, a Nudibranch (brightens within 5 m), a FurlStar (unfurls in dark phases), an Isopod (**freezes when watched** — within 2.4 m, or 2.4–12 m with camera dot > 0.985), a Denning Octopus (emerges after dark), a Deep Angler (body at glow 0.04, lure at 1.6 energy). **Nothing here has a collider, an `Interactable`, or an `add_item` call — it is entirely look-only.**

**Deep giants** (`underwater_world.gd:321-385`) — 4 groupers, 3 halibuts and 1 coelacanth on slow orbits from −12 to −29 m, plus a **45 %-chance Leviathan** (a 12.8–15.2 m grouper) orbiting the SE caisson axis at **−76 m**, one lap per 58 s. Decorative; not catchable.

## 3.6 Harvest system (`scripts/world/harvest_nodes.gd`)

All are `Salvage` nodes; semantics in `scripts/components/salvage.gd`: `required_tools` (any one opens it, empty = bare hands), `speed_tools` **halve the work time and spare your hands**, `yields` granted whole or not at all, `regrow_sec > 0` = renewable, `bare_hand_risk` costs life, `NEAR_M 4.0` lapse distance, `TICK_SEC 0.55` blow cadence.

| Node | ×N | Verb | Work | Required | Speed tools (→ half) | Respawn | Yield | Risk |
|---|---|---|---|---|---|---|---|---|
| **Tar Seam** | 5 | SCRAPE | 2.6 s | none | `prybar`, `hand_file` → 1.3 s | **240 s** | `tar_lump` ×1 | — |
| **Barnacle Crust** | 5 | SCRAPE | 2.2 s | none | `hammer_tool`, `prybar` → 1.1 s | **300 s** | `shell_grit` ×1 | **−0.02 life bare-handed** |
| **Snagged Float** | 3 | CUT FREE | 1.8 s | none | `crude_knife` → 0.9 s | **never (one-shot)** | `float_buoy` ×1 + `rope` ×1 | — |
| **Kelp Growth** | 4 | GATHER | 1.6 s | none | `crude_knife` → 0.8 s | **200 s** | `kelp_bundle` ×1 | — |
| **Fish-Cleaning Board** | 1 | CLEAN | 2.6 s | **`crude_knife` required** | none | **300 s** | `fish_bone` ×1 | — |

Positions (`WET_Y = 2.0`, `harvest_nodes.gd:18`): tar seams at `(20.6,−6.2)`, `(14.2,−4.4)`, `(26.2,−9.6)`, `(9.8,−2.6)`, `(18.4,−14.4)`; barnacle crust three up the SE caisson west face at `x 18.93` (`z −13.4/−12.0/−10.6`) plus two on the seaward lip `(23.6,−21.8)` and `(10.6,−21.8)`; snagged floats `(16.6,−21.9)`, `(22.6,−21.9)`, `(24.8,−21.6)`; kelp growth `(28.8,0.95,−20.4)`, `(8.5,0.95,−14.2)`, `(28.9,0.55,−1.4)`, `(8.5,0.55,−5.6)`; cleaning board `(13.2, 2.0, −19.4)`.

**Kelp Growth is the only source of `kelp_bundle`**, which is in turn the only snail-feeding item and an ingredient in kelp fiber, bloom tonic and fish stew.

**Fauna-sourced yields for cross-reference:** `crab_leg` (dead crab, 8 per corpse), `glow_mucus` (lamp snail, 150 s), `limpet_shell` (limpet, one-shot), `snail_live` (any snail COLLECT, permanent), `glow_worm` (worm den, 90–150 s), `raw_sea_bird` (deck gull, 60–120 s), `fish_herring` (bait shoal, 50–110 s), `fish_copper_sprat` (reef fish while swimming, 50–110 s), plus the **Gyre** debris ring (`gyre.gd:13-20`: driftwood w3, scrap_metal w2, rope w2, tarp w1, sealed_tin w2, kelp_bundle w3, max 14 pieces, spiralling into an eye at `(0,0,−52)`).

---

## Appendix — reproducibility

Pool percentages, the fight-timing table and the steady-state duty-cycle model were computed with scripts in
`/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/3a1fdfbb-2f00-4108-9969-13805825a6fc/scratchpad/` (`an.py`, `pools.py`, `fight.py`, `opt.py`), each a direct transcription of `FishTable.weight_for` / `FishingRod._fight`. The steady-state model reproduces the discrete simulation to within 1 % for every species, which is the basis for calling the Giant Oarfish's fight structurally unwinnable.
