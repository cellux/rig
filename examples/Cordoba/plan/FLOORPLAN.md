# Floor Plan and Coordinate Baseline

## Purpose

This document fixes the metre-based coordinate convention, the interior-only boundary, the provisional zone map, and the first walking route used by Phases 1–5. It is a working baseline, not a measured survey. Dimensions are traceable to `SOURCES.md` or explicitly marked as estimates; later phases may refine them without changing the coordinate convention.

## Coordinate convention

- **Units:** metres everywhere (scene data, collision, camera, generators).
- **Up:** +Y.
- **East–west:** +X east. The building's published 125 m width runs along X.
- **North–south:** +Z south. North is negative Z; the qibla wall and mihrab are at positive Z.
- **Origin:** centre of the prayer-hall interior at floor level (Y = 0). The courtyard and exterior envelope are outside this origin.
- **Handedness / winding:** follow Rig's existing math convention; generated triangle winding must be consistent with back-face culling once it is enabled.

The orientation matches the current-building plan S4 when the plan is read as north at the top: the Courtyard of the Oranges is at low Z, the qibla wall at high Z, and Al-Mansur's eastward expansion is towards +X. The 1868 plans S1/S2 are rotated approximately 90° from this view and are used for topology after rotation.

## Interior boundary

The scene envelope is the interior of the prayer hall only:

- North boundary: the wall between the prayer hall and the Courtyard of the Oranges. The courtyard itself is outside the scene.
- South boundary: the qibla wall, including the mihrab projection and maqsura.
- West boundary: the west perimeter wall and its chapels.
- East boundary: the Al-Mansur east wall and its chapels.
- Roof/ceiling: included as the upper interior envelope; roofs and exterior surfaces are outside the scene.
- Bell tower, courtyard, exterior doors, and façades: outside the scene. A door opening may be represented as a blocked or dark recess, not as an exterior space.

Provisional interior envelope:

| Dimension | Value | Confidence | Basis |
| --- | --- | --- | --- |
| Width, X | 125 m | Medium | Published building width (S6), used for the full east–west wall span. |
| Prayer-hall depth, Z | 118 m | Low–Medium | Published 178 m overall length minus an estimated ~60 m courtyard depth, calibrated against S4. |
| Floor level | Y = 0 | High | Project convention. |
| Column-field ceiling zone | ~10 m lower arcade / ~14–16 m upper arcade | Low | Estimated from photographs; must be measured against a section drawing in Phase 5. |
| Cathedral vault apex | ~30–35 m | Low | Estimated from photographs; the published 54 m is the exterior tower/height figure, not the interior vault. |

The scene should keep the north wall and courtyard threshold visible from inside, so the visitor understands where they entered, but must not allow walking into the courtyard.

## Provisional zone map

Zone bounds are axis-aligned working bounds in metres, relative to the prayer-hall centre. They are deliberately coarse; exact room outlines and chapel partitions are authored in Phase 5 from the plans. `x0/x1` and `z0/z1` are minimum/maximum bounds.

| Zone | Name | Approx. X | Approx. Z | Purpose / contents |
| --- | --- | --- | --- | --- |
| Z0 | North hypostyle field | −62.5 … +62.5 | −59 … −38 | Entry area from the courtyard side; dense column field; first view of two-tier arches. |
| Z1 | West hypostyle field | −62.5 … −32 | −38 … +20 | West aisles and perimeter chapels; quieter side aisles. |
| Z2 | East / Al-Mansur field | +18 … +62.5 | −38 … +38 | Later eastward expansion; repeated column field; shallower visual detail outside the route. |
| Z3 | Cathedral insertion (Capilla Mayor, choir, transept) | −32 … +18 | −38 … −6 | Christian cruciform core: nave, transept, choir enclosure, main altar, ribbed/star vaults, tall windows. |
| Z4 | Villaviciosa / Capilla Real cluster | −50 … −18 | −22 … +6 | Transition chapels embedded in the mosque fabric; ribbed dome, royal chapel, grilles. |
| Z5 | Central nave / maqsura approach | −8 … +12 | −6 … +38 | Wider central aisle towards the mihrab; layered arches and maqsura domes. |
| Z6 | Maqsura and mihrab | −12 … +20 | +38 … +59 | Mihrab projection, maqsura, qibla wall; terminal focal point. |
| Z7 | South perimeter / qibla chapels | −62.5 … +62.5 | +38 … +59 | Perimeter chapels and blocked doors along the south wall outside the mihrab. |
| Z8 | North perimeter chapels | −62.5 … +62.5 | −59 … −45 | Chapels and blocked openings along the courtyard wall. |
| Z9 | West perimeter chapels | −62.5 … −52 | −38 … +38 | Deep chapels along the west wall. |
| Z10 | East perimeter chapels | +52 … +62.5 | −38 … +38 | Chapels along the Al-Mansur east wall. |

The route (below) deliberately crosses Z0 → Z5/Z3 → Z4 → Z3. The other zones are present from Phase 5 as shell geometry and are populated in Phases 7–9.

## Provisional structural grid

The published plan describes 19 aisles across the width, with a wider central aisle. The following is a starting parameter set, not a measured grid:

- **Aisles:** 19 east–west bays. Nominal spacing ~6.5 m, with the central aisle wider (~7.5–8 m) and the two edge aisles narrower (~5–6 m). The exact widths are tuned in Phase 5 against S1/S4.
- **Bays north–south:** nominal column spacing ~4.5–5.0 m. The original mosque had 12 intercolumniations; later expansions add eight bays to the south (S6/S7).
- **Column height:** lower arcade springing estimated at ~4.5–5.5 m above the floor; upper arcade springing estimated at ~8–9 m; ceiling zone above ~10 m. Confirm from a section reference before freezing arch generators.
- **Arch vocabulary:** lower horseshoe arch and upper semicircular arch, both built from alternating red brick and cream limestone voussoirs. The lower arch acts as a tie; the upper arch carries the ceiling.
- **Central axis:** the wider nave runs north–south at approximately X = 0 and terminates at the mihrab/maqsura area.

All column positions are generated from the aisle/bay parameters, not hand-placed one by one. A zone may override the global grid where the Christian insertion interrupts the field.

## First walking route

The route is the detailed MVP and must remain walkable while the rest of the shell is coarse. Waypoints are provisional positions; the camera start is a known safe pose.

1. **Start — north hypostyle threshold (Z0):** near X ≈ 0, Z ≈ −54, facing south. The visitor sees the red/cream arcade receding and the courtyard wall behind them.
2. **Central nave (Z0 → Z5):** walk south along X ≈ 0 through the column field. The two-tier arches, capitals, floor tiles, and side-chapel grilles frame the view.
3. **Grille / chapel threshold (Z4/Z3):** pass a gated side chapel or the Villaviciosa cluster; the route may bend slightly east or west to follow the real opening. The threshold is a visual and collision event, not a locked door.
4. **Cathedral insertion (Z3):** cross into the Capilla Mayor/cruciform core. The ceiling changes from the low timber mosque roof to tall ribbed/star vaults; windows and stained glass introduce a different light palette.
5. **Hero view — Capilla Mayor altar:** the main retable, sculpture, balustrade, and vault form the first hero composition. The visitor may continue into the choir/transept.
6. **Return path:** leave the cathedral core through a parallel aisle, passing the Villaviciosa/Capilla Real cluster, and return north along a west or east aisle. This makes the route a loop rather than a dead end and exercises more of the shell.

The MVP is allowed to model only this route in detail. It must not wall off the rest of the interior artificially; coarse zones may be visually simple but must remain traversable where modelled.

## Collision baseline

- The player is a vertical capsule/circle of radius ~0.30 m with a fixed eye height of ~1.65 m.
- Columns are circles or capsules of radius ~0.25–0.35 m at their base, expanded to the rendered capital only if the capital is low enough to obstruct the head/body.
- Walls are segments or boxes; chapel partitions and grilles are boxes/segments when physically obstructive.
- The floor is a flat navigation plane at Y = 0 for the MVP. Steps, thresholds, and the mihrab platform are represented as blocked or walkable polygons once they are modelled.
- Collision proxies are authored per zone and debug-drawn; they are not generated from render triangles.

## Phase 5 implemented shell parameters

The Phase 5 shell is a bounded route MVP, not the full 125 m × 118 m interior. It
uses the same coordinate convention and deliberately records these values as
provisional until Phase 9 expands the plan.

- Envelope: X −50 … +50 m, Z −59 … +47 m.
- Hypostyle grid: 18 column lines with no column on the central axis, at
  X = ±5, ±10, …, ±45 m; Z lines at −54, −48, …, +42 m (6 m bays).
- Central nave: 10 m clear between X = −5 and +5 m; side aisles: 5 m.
- Column height: 4.2 m to the lower arch spring; lower horseshoe spring 4.2 m,
  upper round arch spring 6.8 m.
- Hypostyle ceiling: side aisles 10.2 m, central nave 12.2 m, with a fascia at the
  height change.
- Cathedral shell: X −28 … +28 m, Z −32 … +14 m; 18 m walls, 8 m × 12 m north and
  south portals, 14 m vault spring, 26 m vault apex, four glass windows per side.
- Route start: (0, 0, −51) facing +Z. The straight central path enters the
  cathedral at Z = −32, passes the altar platform at Z = 6 … 10, exits through the
  south portal at Z = +14, and returns through either side field.
- Collision: 0.30 m player radius; columns at 0.44 m; boundary walls, cathedral
  wall segments, grilles, and the altar platform use static boxes.

The aisle count and several arch/ceiling heights remain visual estimates. The
full plan and measured section work belong to later phases.

## Phase 7 implemented cathedral core

The cathedral insertion now has a readable cruciform core inside the bounded
shell. These values are still visual estimates and do not change the Phase 5
coordinate convention.

- Nave arcade: pointed-arch piers at X = −12 m and X = +12 m, with pier lines at
  Z = −28, −20, −12, −4, +4, +12 m. The west line skips the Villaviciosa chapel
  opening.
- Crossing/transept: bay from Z = −4 m to +4 m, with pointed transverse arches,
  two diagonal ribs, and a gilded boss near the vault apex. Side-aisle transept
  arches span 16 m.
- Capilla Mayor: Z = +4 … +14 m; the existing altar platform remains at Z = 6 …
  10 m, with a new gilded retablo at Z ≈ 12.8 m. The central south portal is now
  a backdrop; two 4 m side exits at X = ±18 m preserve the loop route.
- Choir enclosure: dark timber stalls at X ≈ ±4.35 m, Z = −10 … +2 m, leaving the
  central aisle open.
- Villaviciosa chapel: X = −28 … −12 m, Z = −24 … −12 m, opening west from the
  cathedral aisle through a 6 m pointed portal. It has a ribbed barrel vault at
  a 10 m spring, a 15 m apex, a stained-glass west window, a small gilded
  retable, and an altar platform.
- Stained glass: four tall side windows per wall, using the generated
  `stained_glass` texture.
- LOD/zones: `scene/config.lua` defines `hero`, `detail`, and `shell` LOD
  parameter sets and identifies Villaviciosa, Capilla Mayor, Crossing, Cathedral
  nave, Cathedral aisles, and the hypostyle zones. Runtime culling and streaming
  are later work; the parameters are metadata for Phase 9.

## Phase 9 full-envelope interior

Phase 9 replaces the bounded MVP envelope with the full published prayer-hall
interior. These values remain proportional estimates where no measured survey is
available; they do not change the coordinate convention.

- Envelope: X −62.5 … +62.5 m (125 m) by Z −59 … +59 m (118 m).
- Grid: 19 aisles — a 10 m central nave plus nine ~6.39 m aisles per side (columns
  at X = ±5, ±11.39, …, ±56.11); 6 m N–S bays from Z = −54 to +54.
- Maqsura/mihrab: X −18 … +18, Z 38 … 59; raised platform, two axis domes at ~8.6 m
  spring, a gilded screen with a central opening at Z = 38, and a qibla-wall mihrab
  niche at X = 0, Z ≈ 59.
- Perimeter chapels: shallow compartments behind a striped horseshoe arcade along
  the west/east walls (3.2 m deep, 8 m bays from Z = −52 to +52) and shallower bays
  on the north/south walls outside the entrance and maqsura.
- Culling regions: a 4×4 grid cut at X = −31, 0, 31 and Z = −30, 0, 30. Region
  `lod` is `hero` for the central 2×2, `detail` for edge cells, and `shell` for
  corners. The MVP reduction set is the central band r21/r31/r22/r32/r23/r33.

The cathedral insertion keeps its Phase 7 footprint. Foreign detail — the exact
number of bays, chapel depths, and the maqsura domes — is a documented visual
approximation pending a section/survey source.

## Phase 8 permanent contents

Phase 8 keeps the Phase 5–7 envelope and coordinate convention and populates the
route with shared furniture. Positions are composition choices, not survey data.

- Hanging bronze lamps under the central hypostyle ceiling at Z = −46, −40 and
  Z = 20, 26, 32, 38, at the crossing, and over the Villaviciosa altar.
- Villaviciosa gate: reja panels at X ≈ −11.65, Z ≈ −23.4 and −12.6, leaving the
  clear gate between Z = −21 and Z = −15. Chapel altar rail at X ≈ −26.6.
- Capilla Mayor altar rail: two 5 m segments at X ≈ ±3.5, Z = 5.5, with a central
  opening onto the altar platform (Z = 6 … 10).
- Pews: shared 1.9 m benches at X ≈ ±8.6, Z = −26 … −8 in 3 m rows, facing +Z.
- Organ: X ≈ 26.4 in the east transept arm, 6.7 m wide along Z, two pipe ranks.
- Framed paintings on the cathedral side walls and chapel west wall; candelabra at
  X ≈ ±6.6, Z = 6.6; statues on plinths at X = ±16; interpretation panels near the
  north threshold and Villaviciosa approach.

## Open questions for Phase 5

- Exact prayer-hall depth and courtyard threshold position after calibrating S1/S4 against the 178 m published length.
- Exact aisle widths and column spacing; current values are visual estimates.
- Which chapel openings the route uses, and where the cathedral enclosure/grille actually sits relative to the central nave.
- Lower/upper arcade springing heights and ceiling profile, preferably from a section drawing or photogrammetric reference.
- Where the present-day floor-material boundaries fall (terracotta, checkerboard, marble) and how they relate to the zone map.

These must be resolved or explicitly left uncertain in `DIARY.md` before Phase 5 geometry is considered stable.
