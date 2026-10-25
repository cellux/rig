# Córdoba Mosque-Cathedral

A first-person, procedural OpenGL walkthrough of the present-day Mosque-Cathedral
of Córdoba. The interior is the full published prayer hall (about 125 m east-west
by 118 m north-south): the hypostyle field of striped two-tier arches, the
Christian cathedral insertion, the Villaviciosa chapel, the Capilla Mayor and
crossing, the maqsura and mihrab at the qibla wall, and the perimeter chapel bands.

Everything is generated in code at startup. There is no Blender/glTF pipeline and
no photographic texture loaded at runtime.

## Build and run

From the repository root:

```
make
./build/rig examples/Cordoba/cordoba.lua
```

The example uses the OpenGL backend. A window opens; click it to focus, then use
the controls below. There is no dependency on the original host photo directory:
the only repo assets used are the bundled `assets/DejaVuSans.ttf` font and, for the
separate throwaway spike, `examples/assets/checker.png`.

## Controls

| Key | Action |
| --- | --- |
| `W` `A` `S` `D` | Walk on the ground plane |
| Mouse | Look while the window is focused |
| `R` | Reset to the route start |
| `C` | Toggle the collision-proxy debug view |
| `F` | Toggle full/simple lighting (overrides the active preset) |
| `Q` | Cycle the visual preset (Rich → Balanced → Performance) |
| `M` | Reduce the scene to the detailed MVP route |
| `G` | Toggle mouse grab |
| `H` | Toggle the HUD |

Movement is collision-constrained and eased with a short smoothing time constant.

## Visual presets

`Q` cycles three progressively enhanced configurations. Their trade-offs are
explicit in the HUD summary line and in code (`examples/Cordoba/cordoba.lua`).

| Preset | Floor reflection | Lighting | Contents | Reflection range |
| --- | --- | --- | --- | --- |
| Rich | 640×360 planar reflection | Full (4 local lights, warm ambient) | All permanent contents | 95 m |
| Balanced | 384×216 planar reflection | Full | All permanent contents | 65 m |
| Performance | No reflection pass; analytic environment fallback floor | Simple (directional + ambient only) | Structure only | off |

The main-pass region culling (forward cone + always-visible shell) is always on and
independent of the preset. `M` is also independent: it intersects the visible
region set with the central MVP route band for fast development.

## Verification hooks

These environment variables are inert unless set; they exist for headless
verification and are not needed for normal use.

| Variable | Effect |
| --- | --- |
| `RIG_ENABLE_SCREENSHOTS=1` | Enables the screenshot facility |
| `CORDOBA_SCREENSHOT=/path.png` | Queue a PNG capture |
| `CORDOBA_CAPTURE_FRAME=N` | Capture on frame `N` (default 45) |
| `CORDOBA_EXIT=1` | Stop shortly after the capture frame |
| `CORDOBA_CAMERA="x,y,z,yaw,pitch"` | Override the start pose |
| `CORDOBA_MVP=1` | Start in MVP-reduction mode |
| `CORDOBA_PRESET=rich\|balanced\|performance` | Start in a named preset (or `1`–`3`) |
| `CORDOBA_SWEEP=1` | Print route collision sweeps and scene stats, then exit |

Example headless capture on a machine with an X display:

```
DISPLAY=:0 RIG_ENABLE_SCREENSHOTS=1 \
  CORDOBA_SCREENSHOT=/tmp/cordoba.png CORDOBA_EXIT=1 \
  ./build/rig examples/Cordoba/cordoba.lua
```

## Scene scale and performance

The full scene builds to about 130 region-tagged drawables over 16 culling regions,
roughly 460k vertices and 254k triangles, plus 66 shared content instances. From the
north threshold, Rich draws ~124 of 130 drawables, Balanced ~124 (with a shorter
reflection pass), and Performance ~86 (no reflection, no contents).

Sandbox software-OpenGL frame rates at 1024×576 are in the ~20–45 fps range
depending on view and preset. These are software-renderer numbers, not a hardware
target. The example was designed so that disabling the reflection pass
(`Performance`) recovers most of the cost on weaker GPUs.

## Assets and licensing

- All surface textures are generated deterministically in
  `examples/Cordoba/scene/textures.lua`; the generator, seed, size, and licence are
  recorded in `examples/Cordoba/assets/PROVENANCE.md` and in `M.provenance`.
- The HUD font is the repository's `assets/DejaVuSans.ttf`.
- The Phase 1 spike (`spike.lua` and `assets/spike_*.*`) is a throwaway experiment
  and is not used by the production entry point.

This is a private project with no external asset budget.

## Known limitations

- Proportions are a documented proportional reconstruction, not a measured survey.
  Aisle widths, bay counts, dome heights, and perimeter chapel depths are visual
  estimates. See `plan/FLOORPLAN.md` and `plan/SOURCES.md`.
- Perimeter chapels and the maqsura are simplified: a blind arcade and shallow
  compartments rather than fully detailed chapels.
- Ornament, carved detail, paintings, and statues are silhouettes or a single
  generated canvas, not per-object artworks.
- Contents are concentrated along the MVP route; the outer field is largely empty
  structure.
- The reflection targets are fixed 16:9 sizes, so a strongly non-16:9 window can
  show slight aspect distortion.
- SDL GPU lit-material parity is out of scope; OpenGL is the reference and only
  backend for this example.

## Planning documents

The phased build history, decisions, and floor-plan baseline live under
`examples/Cordoba/plan/`: `PLAN.md`, `PHASES.md`, `DECISIONS.md`, `DIARY.md`,
`FLOORPLAN.md`, and `SOURCES.md`.
