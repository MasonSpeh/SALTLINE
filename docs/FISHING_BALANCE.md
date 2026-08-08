# SALTLINE — fishing balance dump

Generated from `data/fish.json` (46 species) + `scripts/world/fish_table.gd`.
All percentages are REAL roll shares, computed by reimplementing `weight_for()`.

## 1. The three pools

| pool membership | species |
|---|---|
| `rod` | 15 |
| `rod` + `net` | 14 |
| `deep` | 8 |
| `net` | 6 |
| `rod` + `deep` | 3 |

- rod: 32 · net: 20 · deep: 11

## 2. Every species

`w` = phase weights dawn/day/dusk/night (raw, pre-modifier). `req` = the gates. `kg` = landed weight range, median in brackets.

| # | name | pools | w d/d/d/n | storm | rain | fog | light | water | drop_m | kg (median) | fillets | fight | pull |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Copper Sprat | RN | 30/32/30/20 | ok | ok | ok | any | any | — | — | 1 | 0.5 | 0.4 |
| 2 | Lantern Herring | RN | 28/26/26/26 | ok | ok | ok | any | any | — | — | 1 | 0.8 | 0.65 |
| 3 | Sable Hake | RN | 5/2/12/28 | ok | ok | ok | drawn | near | — | — | 1 | 1.1 | 1.0 |
| 4 | Slate Cod | RN | 10/26/10/4 | bonus | bonus | ok | any | any | — | — | 1 | 1.25 | 0.9 |
| 5 | Mirrorjack | R | 26/4/22/2 | ok | bonus | ok | any | open | — | — | 1 | 1.0 | 1.35 |
| 6 | Gannet Mackerel | RN | 26/6/24/2 | never | never | ok | any | open | — | — | 1 | 1.05 | 1.2 |
| 7 | Skipjack Tuna | R | 22/26/20/4 | ok | bonus | ok | any | open | — | 3.0–12.0 (4.7) | 3–6 | 1.5 | 1.5 |
| 8 | Gutter Prawn | N | 20/16/20/24 | ok | ok | ok | any | any | — | — | 1 | 0.4 | 0.3 |
| 9 | Bilge Blenny | RN | 22/24/22/18 | ok | ok | ok | any | near | — | — | 1 | 0.45 | 0.35 |
| 10 | Silver Ladder | R | 22/3/2/1 | ok | never | bonus | any | open | — | — | 1 | 1.0 | 1.0 |
| 11 | Mahi-Mahi | R | 20/22/18/3 | bonus | bonus | ok | any | open | — | 5.0–25.0 (8.8) | 5–10 | 2.0 | 1.8 |
| 12 | Tallow Pollock | RN | 18/20/12/4 | bonus | bonus | ok | any | any | — | — | 1 | 1.2 | 0.95 |
| 13 | Lantern Dogfish | R | 3/1/8/20 | ok | ok | ok | drawn | open | — | — | 1 | 1.6 | 1.45 |
| 14 | Yellowfin Tuna | R | 16/20/16/3 | bonus | ok | ok | any | open | — | 20.0–90.0 (33.3) | 8–16 | 2.2 | 1.9 |
| 15 | Swallowtail Angelfish | R | 16/20/16/4 | never | ok | ok | any | near | — | 0.2–1.0 (0.4) | 1–2 | 0.8 | 0.9 |
| 16 | Rust Wrasse | RN | 8/18/10/1 | ok | ok | ok | any | near | — | — | 1 | 0.85 | 0.7 |
| 17 | Kelp Pipefish | N | 16/18/14/6 | never | never | ok | any | near | — | — | 1 | 0.35 | 0.25 |
| 18 | Bluelined Grouper | R | 14/18/14/6 | never | ok | ok | any | near | — | 1.0–5.0 (1.8) | 2–4 | 1.2 | 1.2 |
| 19 | Lodestone Bream | R | 6/16/6/2 | ok | ok | ok | any | open | — | — | 1 | 1.3 | 1.1 |
| 20 | Inkwell Squid | RN | 3/1/6/16 | ok | ok | ok | drawn | any | — | — | 1 | 1.2 | 1.25 |
| 21 | Bigeye Tuna | RD | 12/4/12/16 | bonus | ok | ok | shy | open | 22 | 30.0–120.0 (47.1) | 10–20 | 2.5 | 2.0 |
| 22 | Peacock Grouper | R | 12/16/14/8 | never | ok | ok | any | near | — | 2.0–10.0 (3.5) | 3–6 | 1.4 | 1.3 |
| 23 | Ember Snapper | RN | 6/14/14/4 | ok | ok | ok | any | near | — | — | 1 | 1.1 | 1.0 |
| 24 | Ghost Sole | RN | 2/0/4/14 | ok | ok | ok | drawn | near | — | — | 1 | 0.9 | 0.7 |
| 25 | Stone Crab | N | 8/6/10/14 | ok | ok | ok | any | any | — | — | 1 | 1.0 | 0.8 |
| 26 | Miller's Flounder | N | 8/14/8/4 | ok | ok | ok | any | near | — | — | 1 | 0.9 | 0.7 |
| 27 | Bloom Dragonfish | D | 2/1/7/14 | ok | ok | ok | drawn | any | 38 | — | 1 | 2.0 | 1.55 |
| 28 | Albacore Tuna | R | 14/10/14/6 | ok | bonus | ok | any | open | — | 8.0–30.0 (12.2) | 5–10 | 1.9 | 1.7 |
| 29 | Gulper Eel | D | 4/2/6/13 | ok | ok | ok | any | any | 34 | — | 1 | 2.2 | 1.7 |
| 30 | Leopard Coral Grouper | R | 10/13/12/7 | ok | ok | ok | any | near | — | 3.0–20.0 (6.2) | 4–9 | 1.9 | 1.6 |
| 31 | Glasspike | R | 2/0/3/12 | never | never | ok | shy | open | — | — | 1 | 1.15 | 1.2 |
| 32 | Ribbon Eel | RD | 2/0/5/12 | ok | bonus | ok | any | open | 8 | — | 1 | 1.5 | 1.4 |
| 33 | Trench Hagfish | D | 5/4/7/12 | ok | ok | ok | any | any | 28 | — | 1 | 1.7 | 1.3 |
| 34 | Humpback Grouper | R | 9/12/10/5 | never | bonus | ok | any | near | — | 2.0–15.0 (4.5) | 3–7 | 1.5 | 1.4 |
| 35 | Abyss Grenadier | D | 6/11/5/3 | ok | ok | ok | any | open | 24 | 5.0–16.0 (7.1) | 3–6 | 1.9 | 1.5 |
| 36 | Chimefish | RN | 8/10/8/6 | never | never | bonus | any | any | — | — | 1 | 0.9 | 0.8 |
| 37 | Drum Croaker | RN | 10/10/10/10 | only | bonus | ok | any | any | — | — | 1 | 1.3 | 1.15 |
| 38 | Anchor Ray | N | 4/3/6/10 | ok | bonus | ok | any | near | — | — | 1 | 1.75 | 1.4 |
| 39 | Squall Garfish | RN | 9/9/9/9 | only | ok | never | any | open | — | — | 1 | 1.35 | 1.5 |
| 40 | Bluefin Tuna | RD | 7/3/8/9 | bonus | ok | ok | any | open | 30 | 60.0–250.0 (96.1) | 16–30 | 3.0 | 2.4 |
| 41 | Fathom Sturgeon | D | 7/8/7/6 | bonus | ok | ok | any | any | 44 | 30.0–95.0 (42.4) | 5–9 | 3.0 | 2.1 |
| 42 | Fathom Halibut | N | 1/0/2/5 | ok | ok | ok | any | any | — | 20.0–70.0 (29.5) | 1–3 | 2.0 | 1.5 |
| 43 | Swordfish | D | 3/2/4/3 | ok | bonus | ok | any | open | 22 | 35.0–120.0 (51.1) | 6–13 | 2.8 | 2.0 |
| 44 | The Looker | R | 1/1/2/3 | ok | ok | bonus | any | any | — | — | 1 | 1.3 | 1.1 |
| 45 | Goliath Grouper | D | 2/1/2/2 | bonus | ok | ok | any | open | 26 | 28.0–48.0 (31.8) | 6–12 | 2.3 | 1.7 |
| 46 | Coelacanth | D | 1/0/1/2 | ok | ok | ok | shy | any | 20 | 15.0–35.0 (18.8) | 4–4 | 2.5 | 1.9 |

## 3. Catch odds by context (real roll shares)

### rod: day, calm, no lights, rig shadow
*27 species in pool, total weight 270.2*

| species | % |
|---|---|
| Copper Sprat | 11.84 |
| Lantern Herring | 9.62 |
| Slate Cod | 9.62 |
| Bilge Blenny | 8.88 |
| Tallow Pollock | 7.40 |
| Swallowtail Angelfish | 7.40 |
| Rust Wrasse | 6.66 |
| Bluelined Grouper | 6.66 |
| Peacock Grouper | 5.92 |
| Ember Snapper | 5.18 |
| Leopard Coral Grouper | 4.81 |
| Humpback Grouper | 4.44 |
| Chimefish | 3.70 |
| Skipjack Tuna | 1.44 |
| Mahi-Mahi | 1.22 |
| Yellowfin Tuna | 1.11 |
| Lodestone Bream | 0.89 |
| Sable Hake | 0.74 |
| Albacore Tuna | 0.56 |
| Inkwell Squid | 0.37 |
| The Looker | 0.37 |
| Gannet Mackerel | 0.33 |
| Mirrorjack | 0.22 |
| Bigeye Tuna | 0.22 |
| Silver Ladder | 0.17 |
| Bluefin Tuna | 0.17 |
| Lantern Dogfish | 0.06 |

### rod: night, calm, floodlights ON
*30 species in pool, total weight 245.2*

| species | % |
|---|---|
| Sable Hake | 22.84 |
| Inkwell Squid | 13.05 |
| Ghost Sole | 11.42 |
| Lantern Herring | 10.60 |
| Copper Sprat | 8.16 |
| Bilge Blenny | 7.34 |
| Peacock Grouper | 3.26 |
| Leopard Coral Grouper | 2.85 |
| Chimefish | 2.45 |
| Lantern Dogfish | 2.45 |
| Bluelined Grouper | 2.45 |
| Humpback Grouper | 2.04 |
| Slate Cod | 1.63 |
| Ember Snapper | 1.63 |
| Tallow Pollock | 1.63 |
| Swallowtail Angelfish | 1.63 |
| The Looker | 1.22 |
| Ribbon Eel | 0.73 |
| Bluefin Tuna | 0.55 |
| Rust Wrasse | 0.41 |
| Albacore Tuna | 0.37 |
| Skipjack Tuna | 0.24 |
| Yellowfin Tuna | 0.18 |
| Mahi-Mahi | 0.18 |
| Bigeye Tuna | 0.15 |
| Mirrorjack | 0.12 |
| Lodestone Bream | 0.12 |
| Gannet Mackerel | 0.12 |
| Glasspike | 0.11 |
| Silver Ladder | 0.06 |

### rod: night, calm, floodlights OFF
*30 species in pool, total weight 187.8*

| species | % |
|---|---|
| Sable Hake | 14.91 |
| Lantern Herring | 13.84 |
| Copper Sprat | 10.65 |
| Bilge Blenny | 9.58 |
| Inkwell Squid | 8.52 |
| Ghost Sole | 7.45 |
| Peacock Grouper | 4.26 |
| Leopard Coral Grouper | 3.73 |
| Chimefish | 3.19 |
| Bluelined Grouper | 3.19 |
| Humpback Grouper | 2.66 |
| Slate Cod | 2.13 |
| Ember Snapper | 2.13 |
| Tallow Pollock | 2.13 |
| Swallowtail Angelfish | 2.13 |
| The Looker | 1.60 |
| Lantern Dogfish | 1.60 |
| Bigeye Tuna | 1.28 |
| Glasspike | 0.96 |
| Ribbon Eel | 0.96 |
| Bluefin Tuna | 0.72 |
| Rust Wrasse | 0.53 |
| Albacore Tuna | 0.48 |
| Skipjack Tuna | 0.32 |
| Yellowfin Tuna | 0.24 |
| Mahi-Mahi | 0.24 |
| Mirrorjack | 0.16 |
| Lodestone Bream | 0.16 |
| Gannet Mackerel | 0.16 |
| Silver Ladder | 0.08 |

### rod: day, SQUALL
*23 species in pool, total weight 280.8*

| species | % |
|---|---|
| Slate Cod | 18.52 |
| Tallow Pollock | 14.25 |
| Copper Sprat | 11.40 |
| Drum Croaker | 10.69 |
| Lantern Herring | 9.26 |
| Bilge Blenny | 8.55 |
| Rust Wrasse | 6.41 |
| Ember Snapper | 4.99 |
| Leopard Coral Grouper | 4.63 |
| Mahi-Mahi | 2.35 |
| Yellowfin Tuna | 2.14 |
| Squall Garfish | 1.44 |
| Skipjack Tuna | 1.39 |
| Lodestone Bream | 0.85 |
| Sable Hake | 0.71 |
| Albacore Tuna | 0.53 |
| Bigeye Tuna | 0.43 |
| Inkwell Squid | 0.36 |
| The Looker | 0.36 |
| Bluefin Tuna | 0.32 |
| Mirrorjack | 0.21 |
| Silver Ladder | 0.16 |
| Lantern Dogfish | 0.05 |

### rod: day, rain
*24 species in pool, total weight 326.2*

| species | % |
|---|---|
| Slate Cod | 15.94 |
| Tallow Pollock | 12.26 |
| Copper Sprat | 9.81 |
| Lantern Herring | 7.97 |
| Bilge Blenny | 7.36 |
| Humpback Grouper | 7.36 |
| Swallowtail Angelfish | 6.13 |
| Rust Wrasse | 5.52 |
| Bluelined Grouper | 5.52 |
| Peacock Grouper | 4.90 |
| Ember Snapper | 4.29 |
| Leopard Coral Grouper | 3.99 |
| Skipjack Tuna | 2.39 |
| Mahi-Mahi | 2.02 |
| Yellowfin Tuna | 0.92 |
| Albacore Tuna | 0.92 |
| Lodestone Bream | 0.74 |
| Sable Hake | 0.61 |
| Mirrorjack | 0.37 |
| Inkwell Squid | 0.31 |
| The Looker | 0.31 |
| Bigeye Tuna | 0.18 |
| Bluefin Tuna | 0.14 |
| Lantern Dogfish | 0.05 |

### rod: day, FOG BANK
*27 species in pool, total weight 293.1*

| species | % |
|---|---|
| Copper Sprat | 10.92 |
| Chimefish | 10.23 |
| Lantern Herring | 8.87 |
| Slate Cod | 8.87 |
| Bilge Blenny | 8.19 |
| Tallow Pollock | 6.82 |
| Swallowtail Angelfish | 6.82 |
| Rust Wrasse | 6.14 |
| Bluelined Grouper | 6.14 |
| Peacock Grouper | 5.46 |
| Ember Snapper | 4.78 |
| Leopard Coral Grouper | 4.43 |
| Humpback Grouper | 4.09 |
| Skipjack Tuna | 1.33 |
| Mahi-Mahi | 1.13 |
| The Looker | 1.02 |
| Yellowfin Tuna | 1.02 |
| Lodestone Bream | 0.82 |
| Sable Hake | 0.68 |
| Albacore Tuna | 0.51 |
| Silver Ladder | 0.46 |
| Inkwell Squid | 0.34 |
| Gannet Mackerel | 0.31 |
| Mirrorjack | 0.20 |
| Bigeye Tuna | 0.20 |
| Bluefin Tuna | 0.15 |
| Lantern Dogfish | 0.05 |

### rod: day, calm, OPEN water (>10m off rim)
*27 species in pool, total weight 251.6*

| species | % |
|---|---|
| Copper Sprat | 12.72 |
| Lantern Herring | 10.34 |
| Slate Cod | 10.34 |
| Skipjack Tuna | 10.34 |
| Mahi-Mahi | 8.75 |
| Tallow Pollock | 7.95 |
| Yellowfin Tuna | 7.95 |
| Lodestone Bream | 6.36 |
| Chimefish | 3.98 |
| Albacore Tuna | 3.98 |
| Gannet Mackerel | 2.39 |
| Mirrorjack | 1.59 |
| Bigeye Tuna | 1.59 |
| Bilge Blenny | 1.43 |
| Silver Ladder | 1.19 |
| Bluefin Tuna | 1.19 |
| Swallowtail Angelfish | 1.19 |
| Rust Wrasse | 1.07 |
| Bluelined Grouper | 1.07 |
| Peacock Grouper | 0.95 |
| Ember Snapper | 0.83 |
| Leopard Coral Grouper | 0.78 |
| Humpback Grouper | 0.72 |
| Inkwell Squid | 0.40 |
| The Looker | 0.40 |
| Lantern Dogfish | 0.40 |
| Sable Hake | 0.12 |

### net: day, calm
*16 species in pool, total weight 230.9*

| species | % |
|---|---|
| Copper Sprat | 13.86 |
| Lantern Herring | 11.26 |
| Slate Cod | 11.26 |
| Bilge Blenny | 10.39 |
| Tallow Pollock | 8.66 |
| Rust Wrasse | 7.80 |
| Kelp Pipefish | 7.80 |
| Gutter Prawn | 6.93 |
| Ember Snapper | 6.06 |
| Miller's Flounder | 6.06 |
| Chimefish | 4.33 |
| Stone Crab | 2.60 |
| Anchor Ray | 1.30 |
| Sable Hake | 0.87 |
| Inkwell Squid | 0.43 |
| Gannet Mackerel | 0.39 |

### net: night, calm
*18 species in pool, total weight 204.3*

| species | % |
|---|---|
| Sable Hake | 13.71 |
| Lantern Herring | 12.73 |
| Gutter Prawn | 11.75 |
| Copper Sprat | 9.79 |
| Bilge Blenny | 8.81 |
| Inkwell Squid | 7.83 |
| Ghost Sole | 6.85 |
| Stone Crab | 6.85 |
| Anchor Ray | 4.89 |
| Chimefish | 2.94 |
| Kelp Pipefish | 2.94 |
| Fathom Halibut | 2.45 |
| Slate Cod | 1.96 |
| Ember Snapper | 1.96 |
| Miller's Flounder | 1.96 |
| Tallow Pollock | 1.96 |
| Rust Wrasse | 0.49 |
| Gannet Mackerel | 0.15 |

### deep @ 8 m, day, no bait
*0 species in pool, total weight 0.0*

| species | % |
|---|---|

### deep @ 24 m, day, no bait
*3 species in pool, total weight 2.5*

| species | % |
|---|---|
| Abyss Grenadier | 66.24 |
| Bigeye Tuna | 22.51 |
| Swordfish | 11.25 |

### deep @ 48 m (spool end), day, no bait
*9 species in pool, total weight 13.2*

| species | % |
|---|---|
| Fathom Sturgeon | 53.23 |
| Trench Hagfish | 17.85 |
| Gulper Eel | 10.18 |
| Abyss Grenadier | 6.80 |
| Bloom Dragonfish | 5.62 |
| Bigeye Tuna | 2.38 |
| Bluefin Tuna | 2.09 |
| Swordfish | 1.19 |
| Goliath Grouper | 0.64 |

### deep @ 48 m, day, GLOW WORM
*9 species in pool, total weight 28.6*

| species | % |
|---|---|
| Fathom Sturgeon | 46.62 |
| Bloom Dragonfish | 15.75 |
| Trench Hagfish | 15.63 |
| Gulper Eel | 12.49 |
| Abyss Grenadier | 5.96 |
| Bluefin Tuna | 1.83 |
| Bigeye Tuna | 0.77 |
| Goliath Grouper | 0.56 |
| Swordfish | 0.38 |

### deep @ 20 m, NIGHT, lights OFF
*2 species in pool, total weight 3.3*

| species | % |
|---|---|
| Coelacanth | 61.21 |
| Ribbon Eel | 38.79 |

### deep @ 48 m, NIGHT, lights OFF, glow worm
*11 species in pool, total weight 114.3*

| species | % |
|---|---|
| Bloom Dragonfish | 55.16 |
| Gulper Eel | 20.30 |
| Trench Hagfish | 11.73 |
| Fathom Sturgeon | 8.75 |
| Bluefin Tuna | 1.38 |
| Bigeye Tuna | 0.77 |
| Coelacanth | 0.62 |
| Ribbon Eel | 0.46 |
| Abyss Grenadier | 0.41 |
| Goliath Grouper | 0.28 |
| Swordfish | 0.14 |

### deep @ 48 m, NIGHT, lights ON
*11 species in pool, total weight 44.4*

| species | % |
|---|---|
| Bloom Dragonfish | 46.76 |
| Gulper Eel | 19.67 |
| Trench Hagfish | 15.91 |
| Fathom Sturgeon | 11.87 |
| Bluefin Tuna | 1.87 |
| Ribbon Eel | 1.69 |
| Abyss Grenadier | 0.55 |
| Swordfish | 0.53 |
| Bigeye Tuna | 0.42 |
| Goliath Grouper | 0.38 |
| Coelacanth | 0.34 |

## 4. Rarity tiers — rarest thing in the game, and where

Each species at its BEST context out of the 12 sampled above:

| species | best % | in which context |
|---|---|---|
| Goliath Grouper | 0.64 | deep @ 48 m (spool end), day, no bait |
| Glasspike | 0.96 | rod: night, calm, floodlights OFF |
| Silver Ladder | 1.19 | rod: day, calm, OPEN water (>10m off rim) |
| Squall Garfish | 1.44 | rod: day, SQUALL |
| Mirrorjack | 1.59 | rod: day, calm, OPEN water (>10m off rim) |
| The Looker | 1.60 | rod: night, calm, floodlights OFF |
| Bluefin Tuna | 2.09 | deep @ 48 m (spool end), day, no bait |
| Gannet Mackerel | 2.39 | rod: day, calm, OPEN water (>10m off rim) |
| Lantern Dogfish | 2.45 | rod: night, calm, floodlights ON |
| Fathom Halibut | 2.45 | net: night, calm |
| Albacore Tuna | 3.98 | rod: day, calm, OPEN water (>10m off rim) |
| Leopard Coral Grouper | 4.81 | rod: day, calm, no lights, rig shadow |
| Anchor Ray | 4.89 | net: night, calm |
| Peacock Grouper | 5.92 | rod: day, calm, no lights, rig shadow |
| Ember Snapper | 6.06 | net: day, calm |
| Miller's Flounder | 6.06 | net: day, calm |
| Lodestone Bream | 6.36 | rod: day, calm, OPEN water (>10m off rim) |
| Bluelined Grouper | 6.66 | rod: day, calm, no lights, rig shadow |
| Stone Crab | 6.85 | net: night, calm |
| Humpback Grouper | 7.36 | rod: day, rain |
| Swallowtail Angelfish | 7.40 | rod: day, calm, no lights, rig shadow |
| Rust Wrasse | 7.80 | net: day, calm |
| Kelp Pipefish | 7.80 | net: day, calm |
| Yellowfin Tuna | 7.95 | rod: day, calm, OPEN water (>10m off rim) |
| Mahi-Mahi | 8.75 | rod: day, calm, OPEN water (>10m off rim) |
| Chimefish | 10.23 | rod: day, FOG BANK |
| Skipjack Tuna | 10.34 | rod: day, calm, OPEN water (>10m off rim) |
| Bilge Blenny | 10.39 | net: day, calm |
| Drum Croaker | 10.69 | rod: day, SQUALL |
| Swordfish | 11.25 | deep @ 24 m, day, no bait |
| Ghost Sole | 11.42 | rod: night, calm, floodlights ON |
| Gutter Prawn | 11.75 | net: night, calm |
| Inkwell Squid | 13.05 | rod: night, calm, floodlights ON |
| Lantern Herring | 13.84 | rod: night, calm, floodlights OFF |
| Copper Sprat | 13.86 | net: day, calm |
| Tallow Pollock | 14.25 | rod: day, SQUALL |
| Trench Hagfish | 17.85 | deep @ 48 m (spool end), day, no bait |
| Slate Cod | 18.52 | rod: day, SQUALL |
| Gulper Eel | 20.30 | deep @ 48 m, NIGHT, lights OFF, glow worm |
| Bigeye Tuna | 22.51 | deep @ 24 m, day, no bait |
| Sable Hake | 22.84 | rod: night, calm, floodlights ON |
| Ribbon Eel | 38.79 | deep @ 20 m, NIGHT, lights OFF |
| Fathom Sturgeon | 53.23 | deep @ 48 m (spool end), day, no bait |
| Bloom Dragonfish | 55.16 | deep @ 48 m, NIGHT, lights OFF, glow worm |
| Coelacanth | 61.21 | deep @ 20 m, NIGHT, lights OFF |
| Abyss Grenadier | 66.24 | deep @ 24 m, day, no bait |

## 5. Size economy

`is_trophy()` — species worth a controller jolt (size_kg[1] >= 20.0 OR pull >= 1.6):

- **Bluefin Tuna** — 250.0 kg / pull 2.4
- **Swordfish** — 120.0 kg / pull 2.0
- **Bigeye Tuna** — 120.0 kg / pull 2.0
- **Fathom Sturgeon** — 95.0 kg / pull 2.1
- **Yellowfin Tuna** — 90.0 kg / pull 1.9
- **Fathom Halibut** — 70.0 kg
- **Goliath Grouper** — 48.0 kg / pull 1.7
- **Coelacanth** — 35.0 kg / pull 1.9
- **Albacore Tuna** — 30.0 kg / pull 1.7
- **Mahi-Mahi** — 25.0 kg / pull 1.8
- **Leopard Coral Grouper** — 20.0 kg / pull 1.6
- **Gulper Eel** — pull 1.7

`is_big()` — fillets out into >1 portion, cures raw on the line:

- Goliath Grouper — 6–12 portions
- Fathom Halibut — 1–3 portions
- Fathom Sturgeon — 5–9 portions
- Abyss Grenadier — 3–6 portions
- Coelacanth — 4–4 portions
- Swordfish — 6–13 portions
- Skipjack Tuna — 3–6 portions
- Yellowfin Tuna — 8–16 portions
- Albacore Tuna — 5–10 portions
- Bigeye Tuna — 10–20 portions
- Bluefin Tuna — 16–30 portions
- Bluelined Grouper — 2–4 portions
- Peacock Grouper — 3–6 portions
- Humpback Grouper — 3–7 portions
- Leopard Coral Grouper — 4–9 portions
- Mahi-Mahi — 5–10 portions
- Swallowtail Angelfish — 1–2 portions

**17 of 46 species carry a weight range.** The other 29 land as unsized items with no weight and 1 fillet.

## 6. Bait matrix

| bait | deep_from | deep x | shallow x | drawn x | rate deep | rate shallow |
|---|---|---|---|---|---|---|
| `glow_worm` | 24.0 | 1.9 | 0.7 | 1.6 | 1.35 | 0.75 |
| `glow_worm_cooked` | 24.0 | 1.15 | 0.85 | 1.0 | 1.0 | 1.0 |
| `crab_leg` | 16.0 | 1.7 | 0.55 | 0.9 | 0.85 | 0.7 |
| `fish_rotten` | 0.0 | 1.15 | 1.15 | 0.85 | 1.45 | 1.45 |
| `snail_live` | 24.0 | 0.6 | 1.55 | 1.0 | 0.95 | 1.2 |

Per-species bait opinions (on top of the table above):

- **`crab_leg`** — Fathom Sturgeon x2.4, Coelacanth x2.2, Goliath Grouper x2.0, Leopard Coral Grouper x2.0, Ribbon Eel x1.9, Peacock Grouper x1.9, Bluelined Grouper x1.8, Abyss Grenadier x1.7, Humpback Grouper x1.5, Bigeye Tuna x1.2, Swordfish x0.45
- **`fish_rotten`** — Trench Hagfish x2.6, Gulper Eel x2.0, Goliath Grouper x1.3, Swordfish x1.3
- **`glow_worm`** — Bloom Dragonfish x2.0, Gulper Eel x1.4
- **`fish_herring`** — Bigeye Tuna x1.9, Swordfish x1.8, Albacore Tuna x1.8, Yellowfin Tuna x1.7, Bluefin Tuna x1.7, Skipjack Tuna x1.6, Mahi-Mahi x1.6
- **`fish_copper_sprat`** — Mahi-Mahi x2.0, Yellowfin Tuna x1.9, Skipjack Tuna x1.8, Swordfish x1.6, Albacore Tuna x1.5, Leopard Coral Grouper x1.5
- **`fish_mirrorjack`** — Bluefin Tuna x2.0, Yellowfin Tuna x1.4
- **`fish_slate_cod`** — Bigeye Tuna x1.5, Bluefin Tuna x1.4
- **`mussels`** — Swallowtail Angelfish x1.7, Bluelined Grouper x1.5
- **`fish_gutter_prawn`** — Humpback Grouper x1.9, Peacock Grouper x1.6, Swallowtail Angelfish x1.5

## 7. Every fishing-related variable in the codebase

### `scripts/world/fish_table.gd` — the rules engine
| const | value | what it does |
|---|---|---|
| `DROP_FADE_PER_M` | 0.035 | past its own `drop_m`, a species thins as the lead sinks (half weight ~29 m below) |
| `RAIN_MIN` | 0.06 | storm intensity at/above which there is rain in the water |
| `FOG_MIN` | 0.25 | fog level that counts as a bank |
| `RAIN_BONUS` | 2.0 | multiplier for `rain: "bonus"` species |
| `RAIN_ONLY_FLOOR` / `RAIN_ONLY_MULT` | 4.0 / 2.5 | floor+mult for `rain: "only"` |
| `FOG_BONUS` | 3.0 | multiplier for `fog: "bonus"` |
| `FOG_ONLY_FLOOR` / `FOG_ONLY_MULT` | 4.0 / 3.0 | floor+mult for `fog: "only"` |
| `LIGHT_SHY_MULT` | 0.15 | penalty when floodlights burn and species is `light: "shy"` |
| *(storm, inline)* | floor 4.0, x3.0 / x2.0 | `storm: "only"` floor+mult; `storm: "bonus"` mult |
| *(water, inline)* | 0.15 | wrong-water penalty for `near` / `open` |
| *(light drawn, inline)* | 2.0 | bonus when lit and `light: "drawn"` |
| `TROPHY_KG` / `TROPHY_PULL` | 20.0 / 1.6 | species-level "is this a monster" for the jolt+flash |
| `TROPHY_T` / `TROPHY_CHANCE` | 0.85 / 0.03 | the per-fish trophy band, and how often a roll draws inside it |
| `MEDIAN_T` | 0.19 | median of the small-skewed weight roll |

Weight roll: `t = randf() * randf()` (small-skewed), replaced by `lerp(0.85, 1.0, randf())` on a 3% trophy draw.

### `scripts/components/fishing_rod.gd` — surface rod + deep rig
| const | value |
|---|---|
| `CAST_SPEED` / `CAST_LIFT` / `GRAVITY` | 13.0 / 4.0 / 9.8 |
| `MAX_RANGE` | 45.0 |
| `BITE_WINDOW` | 1.3 s to strike |
| `CANCEL_DISTANCE` | 6.0 m — walk away and the line comes in |
| `REEL_RATE` | 0.14 progress/s |
| `TENSION_DECAY` | 0.8 |
| `DEEP_CAST_LIFT` / `DEEP_CAST_SPEED` | 1.9 / 6.0 |
| `DEEP_MAX_RANGE` | 95.0 (whole spool: drop + sink) |
| `DEEP_SINK_RATE` | 3.2 m/s |
| `DEEP_MAX_DEPTH` | 48.0 m from waterline |
| `DEEP_BITE_FACTOR` | 1.1 |
| `DEEP_FIGHT_SURGE` | 1.6 m |
| `BAIT_FISH_MAX_M` | 2.0 |
| `JOLT_WEAK` / `JOLT_STRONG` / `JOLT_SEC` | 0.7 / 0.9 / 0.35 |
| `FLASH_PEAK` / `FLASH_IN` / `FLASH_OUT` | 0.5 / 0.04 / 0.19 |

Bite cadence: `bite_pace()` = storm x0.55, rain x0.8, dawn/dusk x0.75 (multiplicative).

### `scripts/components/drop_net.gd`
| const | value |
|---|---|
| `DROP_MAX` | 26.0 m |
| `SOAK_MIN_SEC` / `SOAK_MAX_SEC` | 70.0 / 115.0 |

### Spearfishing — `player_controller.gd` + `underwater_world.gd`
| const | value | where |
|---|---|---|
| `SPEAR_DOT` | 0.86 (~31 deg half-angle) | underwater_world |
| `SPEAR_BODY_BONUS` | 0.5 x body length added to hit radius | underwater_world |
| `SPEAR_SCATTER_R` | 4.5 m — how far the shoal feels a thrust | player_controller |
| `SPEAR_SCATTER_HIT` | 1.4 m — shove on a kill | player_controller |
| `SPEAR_SCATTER_MISS` | 2.1 m — a miss spooks HARDER | player_controller |
| `SPEAR_PROMPT_HZ` | 10.0 | player_controller |
| `ALARM_AMP` | 1.75 — startled fish flicks harder | reef_fish |

### Swim / dive envelope — `player_controller.gd`
| const | value |
|---|---|
| `SWIM_SPEED` / `SWIM_SPRINT_MULT` | 2.3 / 1.5 |
| `SWIM_WARMTH_DRAIN` | 0.016 /s |
| `OXYGEN_DRAIN` | 1/35 per s (~35 s of air) |
| `OXYGEN_RECOVER` / `OXYGEN_RECOVER_LAND` | 0.5 / 1.5 per s |

### Visible schools — `underwater_world.gd`
| const | value |
|---|---|
| `SCHOOL_PODS` | 2 |
| `SCHOOL_PODS_BY_BAND` | surface 3, mid 2, deep 2 |
| `FISH_RANGE_MIN` / `MAX` / `PER_M` / `FADE` | 20.0 / 62.0 / 62.0 / 0.18 |
| `FISH_EASE` / `FISH_TURN` / `FISH_PITCH` | 2.2 / 2.4 / 0.42 |
| `PONTOON_CLEAR` | 0.35 |
| `DIVE_DEATH_Y` | -13.0 (now fish maths only — stale name, see KNOWN_ISSUES) |
