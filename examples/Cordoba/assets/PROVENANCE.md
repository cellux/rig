# Córdoba asset provenance

The production scene generates all of its surface textures in `scene/textures.lua`.
No photographic texture, 3D mesh, or other external art asset is loaded at runtime.

| Texture | Size | Generator | Seed | Notes |
| --- | --- | --- | --- | --- |
| `limestone` | 128×128 | `textures.lua:limestone` | 11 | pale limestone grain and pits |
| `plaster` | 128×128 | `textures.lua:plaster` | 31 | warm fine plaster |
| `brick` | 128×128 | `textures.lua:brick` | 41 | staggered brick courses and mortar |
| `terracotta_floor` | 256×256 | `textures.lua:terracotta_floor` | 53 | staggered warm floor tiles, wear, replacement tiles |
| `marble` | 128×128 | `textures.lua:marble` | 71 | veined pale marble/limestone |
| `wood` | 128×128 | `textures.lua:wood` | 83 | dark timber planks and grain |
| `granite` | 128×128 | `textures.lua:granite` | 97 | dark speckled stone (available for future column variants) |
| `metal` | 128×128 | `textures.lua:metal` | 109 | brushed dark iron with patina |
| `stained_glass` | 128×256 | `textures.lua:stained_glass` | 127 | jewel-toned leaded panes with a central medallion |
| `painting` | 128×192 | `textures.lua:painting` | 151 | dark old-master canvas with a central figure mass |

All textures are deterministic, tileable, generated in-repo, and licensed with the
project. `scene/textures.lua` exposes the same metadata as `M.provenance`, which the
scene attaches to the material set at runtime.

The throwaway Phase 1 spike (`spike.lua`, D24) still references the pre-existing
`examples/assets/checker.png` and the shaders in this directory. The production
Córdoba entry point does not use them.
