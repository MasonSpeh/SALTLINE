# Texture Library — Licensing & Sources

All texture sets in this directory are from **ambientCG** (https://ambientcg.com),
licensed **CC0 1.0 Universal** (public domain — no attribution required, commercial
use OK). Downloaded 2026-07-15 as 1K JPG variants (mobile-friendly per GDD §21).

Each folder = one ambientCG asset ID (traceable at https://ambientcg.com/view?id=<ID>).
Maps kept: `_Color` (albedo, sRGB) · `_NormalGL` (OpenGL-Y normal) · `_Roughness` ·
`_AmbientOcclusion` (where shipped) · `_Metalness` (where shipped) · `_Opacity`
(grating/nets). The `<ID>.png` file is the ambientCG preview sphere, for reference.

## Role assignments (see scripts/world/mat_lib.gd)

| Asset | Look | Rig role |
|---|---|---|
| Rust004 | deep pitted red-brown rust | derrick, trusses, rust_steel |
| Rust007 | rust variation | rusty_metal accents |
| CorrugatedSteel005 | weathered galvanized corrugated | shed walls/roofs |
| CorrugatedSteel007B | pale-blue peeling paint over rust | container/hut walls |
| DiamondPlate002 | clean treadplate | checker_plate (dock apron etc.) |
| DiamondPlate008B | dark worn treadplate | deck_plate (main decks) |
| MetalPlates006 | dark overlapping plates | machinery housings |
| MetalPlates013 | dark grungy riveted plates | caisson/hull, dark_metal |
| PaintedMetal004 | scratched red paint | SPHL, fire barrel, red trim |
| PaintedMetal006 | peeling teal over rust | Bloom-teal accents, doors |
| PaintedMetal013 | heavily peeled white | accommodation exterior walls |
| PaintedMetal016 | rusted yellow/black hazard stripes | hazard edges, crane bases |
| Metal032 | brushed/galvanized steel | galvanized fittings |
| MetalWalkway013 | open steel grating (opacity) | catwalks, stair treads |
| Concrete012 | rough weathered concrete | concrete_floor |
| Concrete046 | pale smooth concrete | caisson upper, interior_wall base |
| Planks037A | warm worn plank floor | wood, tables, pallets |
| Rope001 | coiled rope fiber | rope props, bollard lines |
| Net002A | knotted netting (opacity) | nets, gyre debris |
| Fabric062 | woven canvas | tarps, lean-to, bunks |

Adding more: `curl -L "https://ambientcg.com/get?file=<ID>_1K-JPG.zip"` — see
https://ambientcg.com/api/v2/full_json?type=Material&q=<query> to search.
