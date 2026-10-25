# Sources and Provenance

## Purpose

This inventory records the reference material used to define the Córdoba scene: where it came from, what it is used for, its licence/access status, and how much confidence to place in it. It follows the Phase 0 acceptance criterion in `PLAN.md`. Runtime asset provenance is tracked separately under `examples/Cordoba/assets/` when assets are added.

## Confidence key

- **High** — primary or well-documented source; suitable for dimensions or topology unless contradicted.
- **Medium** — useful secondary source or a drawing whose scale/orientation needs calibration.
- **Low** — visual or historical reference only; not used for measurements.

## Floor plans and measured references

| ID | Source | Date | Use | Confidence | Licence/access |
| --- | --- | --- | --- | --- | --- |
| S1 | Mariano López y Sánchez, *Planta de la mezquita-catedral de Córdoba*, Academia Colecciones MA-0525. Copy: `plan/reference/Planta_de_la_mezquita-catedral_de_Cordoba.jpg`. Wikimedia Commons: <https://commons.wikimedia.org/wiki/File:Planta_de_la_mezquita-catedral_de_C%C3%B3rdoba.jpg> | 1868 | Primary room topology and Christian-insertion layout: courtyard, prayer hall, Capilla Mayor, choir, transept, perimeter chapels, mihrab/maqsura. | High for topology; Medium for dimensions | Public domain |
| S2 | Mariano López Sánchez, *Planta de la catedral-mezquita de Córdoba*, Academia Colecciones MA-0163. Copy: `plan/reference/Planta_de_la_catedral-mezquita_de_Cordoba.jpg`. Wikimedia Commons: <https://commons.wikimedia.org/wiki/File:Planta_de_la_catedral-mezquita_de_C%C3%B3rdoba.jpg> | 1868 | Cross-check of S1; second survey drawing of the same state. | Medium | Public domain |
| S3 | *Planta de la Catedral de Córdoba*, from P. de Madrazo, *Recuerdos y Bellezas de España: Córdoba*. Copy: `plan/reference/Planta_de_la_Catedral_de_Cordoba.png`. Wikimedia Commons: <https://commons.wikimedia.org/wiki/File:Planta_de_la_Catedral_de_C%C3%B3rdoba.png> | 1855 | Historical cross-check of the cathedral insertion; not a current survey. | Low–Medium | Public domain |
| S4 | Américo Toledano (minor edits by R Prazeres), *Floor plan of Mosque of Córdoba (rotated and labelled)*. Copy: `plan/reference/Floor_plan_of_Mosque_of_Cordoba_(rotated_and_labelled).png`. Wikimedia Commons: <https://commons.wikimedia.org/wiki/File:Floor_plan_of_Mosque_of_C%C3%B3rdoba_(rotated_and_labelled).png> | 2020 | Current-building topology: courtyard boundary, 19-aisle field, Capilla Mayor insertion, Villaviciosa, perimeter chapels. | High for topology; Medium for scale | CC BY-SA 4.0; attribution required if redistributed |
| S5 | Azahara22, revised by R Prazeres, *Plano de la Mezquita de Córdoba (revised with labels and dates)*. Copy: `plan/reference/Plano_de_la_Mezquita_de_Cordoba_(revised_with_labels_and_dates).jpg`. Wikimedia Commons: <https://commons.wikimedia.org/wiki/File:Plano_de_la_Mezquita_de_C%C3%B3rdoba_(revised_with_labels_and_dates).jpg> | 2020 | Historical construction phases (Abd ar-Rahman I/II/III, Al-Hakam II, Al-Mansur) used to understand the column field and expansion seams. | Medium | CC BY-SA 4.0; attribution required if redistributed |
| S6 | Wikipedia (Spanish), *Mezquita-catedral de Córdoba*, infobox and architecture sections. <https://es.wikipedia.org/wiki/Mezquita-catedral_de_C%C3%B3rdoba> | accessed 2026-10-25 | Overall published dimensions (178 m length, 125 m width), 19 aisles, original 11 aisles, courtyard/prayer-hall relationship, construction phases. | Medium | CC BY-SA; cite if quoted |
| S7 | Wikipedia (English), *Mosque–Cathedral of Córdoba*, architecture sections. <https://en.wikipedia.org/wiki/Mosque%E2%80%93Cathedral_of_C%C3%B3rdoba> | accessed 2026-10-25 | Cross-check of 19 aisles, ~850 columns, two-tier arch description, 64 m prayer-hall length after an early expansion, cathedral insertion history. | Medium | CC BY-SA; cite if quoted |
| S8 | Official Mosque-Cathedral of Córdoba site. <https://www.mezquita-catedraldecordoba.es/> | accessed 2026-10-25 | Current use, named chapels, visitor route context, present-day photographs/descriptions. | Medium | Site terms apply; use as reference only |
| S9 | UNESCO World Heritage List, *Historic Centre of Córdoba* (ref. 313). <https://whc.unesco.org/en/list/313/> | accessed 2026-10-25 | Heritage context and general description; not a dimensional source. | Low–Medium | UNESCO terms |

### Dimension constraints used by the plan

- Published overall building envelope: **178 m (north–south) × 125 m (east–west)**, from S6.
- The whole building includes the courtyard. The interior-only scene therefore uses an approximate prayer-hall envelope of **125 m east–west × 118 m north–south**, derived by subtracting the courtyard depth from the published length and calibrated against the current plan (S4). This is an estimate, not a survey.
- Current hypostyle field: **19 aisles**, with a wider central aisle leading to the mihrab; the original mosque had 11 (S6, S7).
- Current column count: approximately **850** (S7). The plan does not require modelling every column in the MVP zone at full detail, but the whole-building phase must preserve the field's rhythm.
- Original mosque: roughly **74–79 m per side**, split between courtyard and prayer hall (S6, S7).
- The historical plans (S1–S3) predate modern restoration and do not show every current barrier or chapel use. They are used for structure, not for present-day furnishing.

## Supplied photographs

The files below are the visual reference set copied into `plan/images/`. They are supplied by the project author and are used for visual vocabulary, material, lighting, and composition. They are not dimensional evidence (D23). The subject notes come from a contact-sheet review on 2026-10-25 and are intentionally descriptive rather than art-historical attributions.

| File | Visual subject / use |
| --- | --- |
| `20251016_160704.jpg` | Hypostyle columns and striped arches framing a gated side chapel with a painting, terracotta floor, red rope barrier. Reference for gated chapel composition and floor tile. |
| `20251016_160719.jpg` | Gilded retable behind a dark grille under two-tier arches; warm artificial light against pale stone. Reference for chapel retable and grille layering. |
| `20251016_160804.jpg` | View through hypostyle arches into the cathedral's ribbed/vaulted upper volume and choir stalls. Reference for mosque/cathedral layering. |
| `20251016_160915.jpg` | Upward view of pale carved vault, windows, and lantern/oculus. Reference for cathedral vault and daylight. |
| `20251016_161327.jpg` | Capilla Mayor main altar and large gilded retablo, sculpture, balustrade, and visitors. Reference for the hero view's scale and contrast. |
| `20251016_161342.jpg` | Elevated cathedral interior view: arches, carved gallery, gilded rail, windows. Reference for the cathedral's layered vertical composition. |
| `20251016_162130.jpg` | Small chapel altarpiece behind a grille within the hypostyle field. Reference for side-chapel density and warm focal light. |
| `20251016_162212.jpg` | Close hypostyle detail: arches, grille, capital, visitors, floor. Reference for arch/grille proportions and material contrast. |
| `20251016_162244.jpg` | Hypostyle aisle with pews, gated chapel, columns, and tiled floor. Reference for permanent contents and aisle framing. |
| `20251016_162418.jpg` | Column capitals and double arches with strong side daylight and deep shadows. Reference for the two-tier arch rhythm and high dynamic range. |
| `20251016_162503.jpg` | Long hypostyle nave with repeated arches, timber ceiling, columns, and people. Reference for the forest-of-columns effect and scale. |
| `P_20251016_162339.jpg` | Wide cathedral nave/vault view towards a lit altar and gilded rail, with people. Reference for the route's terminal hero composition. |

## Operational sources and tools

- Wikimedia Commons API was used on 2026-10-25 to obtain the plan images and their licence metadata.
- The supplied photographs were reviewed as a single contact sheet generated with ImageMagick for cataloguing; the originals remain unchanged in `plan/images/`.
- No source is copied into runtime assets at this phase. If a floor plan or photograph is later used as a texture or decal, its licence and attribution are recorded in the asset manifest under `examples/Cordoba/assets/`.

## Known gaps and follow-up research

- No measured architectural survey or reliable section drawings have been acquired. Column spacing, arch rise, ceiling height, and chapel dimensions are provisional.
- The current visitor route and barrier locations are not documented beyond photographs; the plan deliberately ignores access restrictions (D7).
- The exact relationship between the 1868 drawings and the current plan should be checked against a recent official plan before Phase 5 geometry is frozen.
- No texture source set has been selected yet. Phase 1/6 must record provenance before textures become runtime assets.
