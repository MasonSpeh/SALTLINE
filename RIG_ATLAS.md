# RIG ATLAS — SALTLINE main rig, sonar scan briefing

*Generated 2026-07-22 02:28 · 666,631 tris · 468 manifest props · regenerate with `~/SALTLINE/tools/export_rig.sh`*

## Coordinate contract (verified exact)

```
godot (x, y, z) meters  →  sonar (1000·x, −1000·z, 1000·y) mm
sonar (X, Y, Z) mm      →  godot (X/1000, Z/1000, −Y/1000) m
```
Sonar frame is Z-up right-handed millimeters. Top of ASCII plans = godot −z (north).

Scan bounds (mm): x[-41839,60532] y[-23276,37540] z[-3050,51720]

## Deck elevations (godot y / sonar z)

| deck | y (m) | z (mm) | what |
|---|---|---|---|
| boat landing | −3–1 | −3000–1000 | water line, mooring |
| wet deck (Z1) | 2 | 2000 | pumps, salvage, SPHL, player start |
| topside (Z4) | 18 | 18000 | machine shop, bunkhouse, galley, rec |
| deck B/C/D | 21.6/25.1/28.6 | 21600/25100/28600 | accommodation stack |
| stack roof | 32.1 | 32100 | comms mast |
| ops lookout | 38 | 38000 | glass lookout atop stair tower |
| high iron | 32–52 | 32000–52000 | derrick, crane |

## Zones (rooms & areas)

| zone | godot x | godot z | y | props |
|---|---|---|---|---|
| store_room | [10,16] | [-22,-16] | [1.8,5.4] | 21 |
| pump_ready_room | [10,18] | [-14,-6] | [1.8,5.4] | 10 |
| sphl_pod | [12,21] | [-28,-21] | [1.0,6.0] | 14 |
| rec_room | [18,28] | [8,18] | [18.0,21.2] | 43 |
| ops_lookout | [21,31] | [-7,3] | [36.0,41.0] | 0 |
| galley | [-2,14] | [8,18] | [18.0,21.2] | 63 |
| machine_shop | [-28,-14] | [-18,-6] | [18.0,21.2] | 25 |
| bunkhouse | [-28,-8] | [4,18] | [18.0,21.2] | 82 |
| deck_d_cabins | [8,30] | [4,19] | [28.6,32.0] | 38 |
| stair_tower | [22,30] | [-6,2] | [2.0,21.2] | 0 |
| deck_b_cabins | [-2,30] | [4,19] | [21.6,25.0] | 54 |
| deck_c_cabins | [-2,30] | [4,19] | [25.1,28.5] | 42 |
| stack_roof | [-2,30] | [4,19] | [32.1,36.0] | 3 |
| wet_deck | [6,32] | [-28,-4] | [1.0,6.5] | 80 |
| boat_landing | [6,34] | [-30,0] | [-3.5,1.0] | 2 |
| topside_deck | [-30,30] | [-20,20] | [17.5,21.4] | 223 |
| high_iron | [-12,12] | [-12,12] | [32.0,52.0] | 0 |

## Key locations (godot meters)

- player spawn: (20.0, 2.2, −24.7) — facing the SPHL hatch
- wet-deck respawn: (15.0, 2.6, −10.5) — inside the pump ready room, open archway east
- PA speaker: (14, 21.0, 7)
- topside stair hole: x[21.9,30.1] z[−6.1,2.1]

## Tool cookbook — which question maps to which tool

| You want to know… | Call |
|---|---|
| what is this scene / orient me | `scene_brief` (this document) |
| what named places exist | `scene_zones` |
| where is item X / what's in room Y | `props_find {query:"wrench"}` / `{zone:"galley"}` |
| what's at point P (occupied? which zone?) | `spatial_probe {points:[[x,y,z]]}` |
| floor plan at elevation | `spatial_slice {axis:"z", coord:<mm>}` |
| distance to nearest surface along a line | `spatial_raycast` |
| does A fit / clearance between things | `spatial_measure`, or probe a grid |
| overview stats of all objects | `scene_summary` |

## Placement-check recipe (interior design loop)

1. `props_find {zone:"<room>"}` — what's already there.
2. `spatial_probe` at the candidate footprint corners at floor+300 mm —
   all must read `empty` (not INSIDE rig) and in the right zone.
3. `spatial_raycast` straight down from each corner — confirms floor height.
4. Convert the chosen sonar point back to Godot (`x=X/1000, z=−Y/1000,
   y=Z/1000`) and edit the spawn in the SALTLINE script.
5. Re-run `~/SALTLINE/tools/export_rig.sh`, then re-probe to verify the
   item landed where intended.

## Freshness

This atlas describes the scan in `~/SALTLINE/.sonar-rig`, captured from the live RigBuilder tree. If SALTLINE's rig code changed since the timestamp above, re-run `~/SALTLINE/tools/export_rig.sh` before trusting coordinates.
