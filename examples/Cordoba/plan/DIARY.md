# Implementation Diary

## Purpose

This file is an append-only log of completed work on the Córdoba project. Every entry will include a timestamp. Earlier entries must never be edited. Pending work and the information needed to resume work are maintained in the single `HANDOFF` section at the end of this file.

## 2026-10-25 — Phase 0 planning baseline

Reviewed `PLAN.md` and turned it into an ordered implementation programme.

Completed work:

- Wrote `PHASES.md` with Phases 0–10, mapping every PLAN milestone to at least one independently testable phase. The first engine work is split into a throwaway technical spike (Phase 1), procedural mesh (Phase 2), lit materials (Phase 3), walk/collision (Phase 4), and the architectural shell (Phase 5) so each can be verified separately.
- Wrote `DECISIONS.md` with D1–D24 covering the resolved plan constraints plus the coordinate, source, collision, material, quality, and verification decisions needed to start implementation. Open technical choices are explicitly deferred to the phase that must resolve them.
- Wrote `SOURCES.md` with a provenance inventory, confidence levels, licence notes, the dimension constraints, and a catalogue of the supplied reference photographs.
- Wrote `FLOORPLAN.md` with the metre-based coordinate convention, interior-only boundary, provisional zone map, structural grid, first route, collision baseline, and open measurement questions.
- Copied four public-domain/CC-licensed reference plans into `plan/reference/` for topology study. These are planning references, not runtime assets.

Reference findings:

- The published building envelope is 178 m north–south by 125 m east–west (Spanish Wikipedia infobox, cross-checked against the plan drawings). The whole envelope includes the Courtyard of the Oranges; the interior-only prayer hall is provisionally 125 m wide by ~118 m deep. The depth is an estimate and is marked Low–Medium confidence.
- The current plan (S4) and the 1868 survey (S1) agree on the main topology: courtyard on the north, 19-aisle hypostyle field, cathedral insertion in the western/central part of the field, Villaviciosa/Capilla Real cluster, maqsura/mihrab on the qibla wall, and perimeter chapels. The 1868 plan is rotated about 90° from S4 and predates modern restoration.
- The structural grid is not measured yet. Provisional values: ~6.5 m aisle spacing across 19 aisles, ~4.5–5.0 m north–south bay spacing, lower arcade springing ~4.5–5.5 m, upper arcade springing ~8–9 m. These are estimates from the plans/photographs and must be checked against a section reference before Phase 5 freezes the arch generators.
- The supplied photographs confirm the visual priorities: red/cream striped arches dominate long views; chapel retables and grilles provide warm focal points; the cathedral insertion is much taller and paler than the mosque fabric; floors are terracotta, patterned stone, and darker polished areas; daylight creates strong high-dynamic-range contrast in side aisles.
- No source provides a reliable current measured plan or section. The project therefore proceeds with a documented proportional reconstruction, as allowed by the plan, rather than blocking on survey data.

Verification:

- `make test` was run before the documentation work: 54/54 test files passed. No source or build files were changed in this phase, so no rebuild or `./build/rig` smoke test was required.
- Phase 0 review: every dimension in `FLOORPLAN.md` is either cited in `SOURCES.md` or marked as an estimate; the coordinate convention and scene boundary are explicit; the first route is bounded and named; open measurement questions are listed.

No implementation code was written in this phase. The next phase is the OpenGL technical spike (Phase 1).

## 2026-10-25 — Phase 1 spike and screenshot facility

Implemented the Phase 1 technical spike and the optional screenshot facility that made headless visual verification possible.

Screenshot facility:

- Added `src/modules/screenshot.lua` + `screenshot.md`: queued captures, immediate capture, PNG write, auto-named `screenshot-NNNN.png`, and explicit `clear`/`flush`. The whole facility is gated by `RIG_ENABLE_SCREENSHOTS` (D25); when disabled, sketches do not run the per-frame flush.
- Added `png.encode` using libpng's `png_image_write_to_memory`; the decoder was already present.
- Added `gl.PixelStorei`, `gl.ReadPixels`, and `gl.PACK_ALIGNMENT`, plus `glx.RenderScene:capture_image` (top-down RGBA by default, raw bottom-up on request).
- Wired `sketch.App:screenshot(...)` and an end-of-overlay flush before presentation, so captures include the finished scene and HUD.
- Added `tests/png_test.lua` encode round-trip coverage and `tests/screenshot_test.lua` for save/queue/flush/error behavior.

Spike:

- Added `examples/Cordoba/spike.lua` with a throwaway parameterized mesh builder: nine-by-nine column field, lower horseshoe arches, upper round arches with alternating brick/cream voussoirs, a timber ceiling proposal, boundary walls, and a reflective-floor shader.
- Added `examples/Cordoba/assets/spike_lit.*` and `spike_floor.*`; the floor loads the existing `examples/assets/checker.png` and uses a stylised Fresnel/reflection approximation. This is a Phase 1 experiment, not the final reflection technique.
- The spike uses focused-window mouse movement for look, WASD for movement, fixed eye height, and a simple scene-bounds clamp. Collision is intentionally absent (Phase 4).

Verification:

- `make test`: 55/55 test files passed.
- `RIG_ENABLE_SCREENSHOTS=1 ./build/rig examples/Cordoba/spike.lua` under a 1024×576 Xvfb display produced a valid 1024×576 RGBA PNG via `app:screenshot`. The capture shows the arcade, columns, ceiling, and floor reflection participating.
- The spike exits cleanly with `CORDOBA_SPIKE_EXIT=1` after the capture.
- Host performance timing on the Intel Haswell class is still pending; the sandbox confirmed functionality, not the frame-rate target.

Phase 1 findings / engine gaps for later phases:

- The local mesh builder is now the main procedural gap: it should become the Phase 2 `mesh` builder with normals, indices, material ranges, and shared/indexed buffers.
- Custom materials still receive a limited uniform contract (`u_mvp`, optional `u_texture`). Lighting is currently hard-coded in the spike shaders; Phase 3 must expose a documented lit-material uniform/scene-parameter contract.
- The floor reflection is an authored approximation, not a planar/screen-space reflection. Phase 6 must evaluate the real options and measure them.
- The screenshot backend is OpenGL-only. The SDL renderer and GPU scenes need their own `capture_image` methods if they are to support the same facility.
- Collision and a reusable walk controller remain Phase 4 work.

## 2026-10-25 — Screenshot capture moved to a capability provider

Refactored the screenshot facility so capture is a capability rather than a check for
a surface method.

- `screenshot.plugin` declares `screenshot.capture`; `screenshot.component` consumes
  it and installs the active provider. `screenshot.bind`/`set_provider`/
  `clear_provider`/`provider` support hand-built runtimes and tests.
- `sdl3x` now provides three backend providers: OpenGL (`gl.ReadPixels` with row
  flipping), SDL renderer (`SDL_RenderReadPixels` with `SDL_PIXELFORMAT_RGBA32`), and
  SDL GPU (ends the scene pass, downloads the swapchain into a transfer buffer,
  submits/waits, and swizzles BGRA to RGBA). Each is attached by the matching SDL
  bundle.
- The GPU graphics context gained `submit_frame()`: the frame loop submits at most
  once, so a capture can submit early when it needs a readback. Multiple GPU requests
  in one frame share one readback.
- Removed the OpenGL scene's `capture_image` method; backend readback now lives in the
  provider. Updated `screenshot.md`, `sdl3x.md`, `graphics.md`, `sketch.md`, and D25.
- Tests: screenshot tests now use a fake provider, verify the missing-provider error,
  and verify that `screenshot.component` consumes a provided capability and clears it
  on release.

Verification: `make test` — 55/55 files passed. The Córdoba spike still produces a
valid 1024×576 PNG with `RIG_ENABLE_SCREENSHOTS=1` through the new capability path.

## 2026-10-25 — Screenshot providers verified on all three SDL backends

- OpenGL: the Córdoba Phase 1 spike still produces a valid 1024×576 RGBA PNG through
  `screenshot.component` + `sdl3x.gl_screenshot_component`.
- SDL renderer: `sdl3x.renderer_screenshot_component` was corrected for the SDL3 API
  (`SDL_RenderReadPixels` returns an owned `SDL_Surface`, not an SDL2-style
  format/pixels/pitch call). The provider converts the surface to RGBA32, copies rows
  honouring pitch, and destroys both surfaces. A 1024×576 probe captured the expected
  clear colour.
- SDL GPU: `sdl3x.gpu_screenshot_component` captured a spinning cube from the Vulkan
  swapchain on the sandbox's Mesa Intel Haswell driver. The decoded PNG has the
  expected blue background and red cube; BGRA→RGBA swizzling is correct. The
  `graphics:submit_frame()` early-submit path does not disturb normal GPU frames.
- GPU captures are limited to one capture configuration per frame; repeated requests
  with the same crop share one readback.

Verification: `make test` 55/55; manual GL, renderer, and GPU screenshot probes all
produced decodable PNGs with expected pixels.

## 2026-10-25 — Phase 2 mesh contract and architectural generators

Implemented the Phase 2 procedural mesh foundation.

- Added two lit-capable layouts: `position_normal_color_uv_f32` (stride 44) and
  `position_normal_tangent_color_uv_f32` (stride 60). Attribute locations are stable:
  position 0, color 1, uv 2, normal 3, tangent 4. The existing unlit layouts and
  generators are unchanged.
- Added optional indexed geometry to the mesh contract (`index_blob`, `index_count`,
  `index_type`, `index_stride`) with zero-based uint32 indices. The GL factory now
  binds an element-array buffer and uses `glDrawElements`; the SDL GPU factory uploads
  an index buffer and uses `SDL_DrawGPUIndexedPrimitives`. Non-indexed meshes keep
  array draws.
- Added generators: `make_box`, `make_cylinder`, `make_capital`, `make_column`,
  `make_arch_ring`, `make_round_arch`, `make_horseshoe_arch`, `make_voussoir_band`,
  `make_wall` (rectangular openings plus reveals), `make_floor_bay`/`make_floor`, and
  `make_barrel_vault`.
- Added `mesh.builder` / `mesh.merge` with transforms, inverse-transpose normals,
  optional generated normals/tangents, UV adjustment, and zero-based per-section
  material ranges. The current unlit material ignores the ranges; they are ready for
  the Phase 3 material path.
- Added `examples/procedural_mesh.lua` as an indexed primitive gallery and expanded
  `tests/mesh_test.lua` with layout, generator, index, wall-opening, builder, normal,
  tangent, and material-range coverage.
- Added the GL `ELEMENT_ARRAY_BUFFER`, `UNSIGNED_SHORT`, `UNSIGNED_INT`, and
  `glDrawElements` bindings, plus `glx.VertexArray:element_buffer`.
- Updated `mesh.md`, `render.md`, `glx.md`, `sdl3x.md`, and D26.

Verification: `make test` — 55/55 files passed. `examples/procedural_mesh.lua`
rendered the gallery under Xvfb on both OpenGL and SDL GPU; each run captured a valid
1024×576 RGBA PNG with the same visible geometry, confirming the indexed draw paths.

## 2026-10-25 — Phase 3 material and lit shading foundation

Implemented the Phase 3 lit-material path with OpenGL as the reference backend.

- Extended `render.material` with `shading = "unlit" | "lit"` and explicit fields:
  albedo, roughness, specular, emissive, opacity, alpha mode/cutoff, depth test/write,
  and cull mode. Base and optional normal textures bind to slots 0 and 1.
- Added `render.lighting`: ambient, one directional daylight, up to four bounded
  local point lights, and exposure. Scenes store it via `surface:set_lighting(...)`,
  `options.lighting` on `scene.container_component`, or `rig.run`.
- Added an OpenGL built-in lit shader with world-space normals, optional tangent-space
  normal mapping, Lambert diffuse, Blinn-Phong-style specular response, bounded local
  light attenuation, exposure, and a Reinhard display curve.
- Documented the plain-uniform contract (`u_mvp`, `u_model`, material fields, camera
  position, directional/ambient light, four local lights, exposure) so Córdoba can
  add scene-specific parameters without forking the backend shader.
- Added GL depth/write/blend/culling state handling for materials. Extended GL with
  `Uniform1f`, `Uniform4fv`, `DepthMask`, `CullFace`, `CULL_FACE`, and related
  constants; `glx.Program` gained `set_uniform1f` and `set_uniform4fv`.
- The SDL GPU mesh factory rejects built-in lit materials with a clear error. Unlit
  and textured materials remain available on both backends.
- Added `examples/material_lighting.lua`: lit floor, columns, wall, arches, vault,
  base-textured normal-mapped panel, directional daylight, two warm local lights,
  and exposure. Expanded `tests/render_test.lua` and `tests/scene_test.lua`.

Verification: `make test` — 55/55 files passed. `examples/material_lighting.lua`
rendered under Xvfb on OpenGL and produced a valid 1024×576 RGBA PNG showing lit
geometry, texture detail, normal-map grooves, local warm light, and the unlit/textured
fallbacks still compile. GPU lit parity remains intentionally deferred.

## 2026-10-25 — Phase 4 walk controller and collision

Implemented the Phase 4 navigation foundation.

- Added the `collision` module: a static XZ world with circles, optionally rotated
  boxes, thickness segments, and polygons. Shapes precompute AABB bounds for
  broadphase checks.
- Movement uses adaptive substepping tied to the player radius plus per-shape
  depenetration. Deterministic tests cover walls, thin walls at high speed, sliding,
  circles, segments, polygons, initial overlap, and capsule aliasing.
- Added `mesh.make_line_segments` for disjoint debug lines; `world:debug_mesh`
  uses it so separate proxies are not connected by stray lines.
- Added `camera.walk`: WASD on the ground plane, fixed eye height, focus-gated mouse
  look with an optional look button, configurable speed/radius, collision
  integration, and `R` reset. Focus loss clears held movement and look state.
- Extended `sketch` with `kind = "walk"` and focus-event forwarding via
  `app:on_focus` and controller `on_focus` methods.
- Added `examples/collision_walk.lua`: outer walls, a column grid, an oriented wall,
  a segment fence, and a polygon plinth with matching collision proxies and toggleable
  debug lines.
- Updated `camera.md`, `sketch.md`, `mesh.md`, `README.md`, and added `collision.md`.

Verification: `make test` — 56/56 files passed. `examples/collision_walk.lua` ran
under Xvfb on both OpenGL and SDL GPU; both produced valid 1024×576 RGBA PNGs showing
the walk scene and debug proxies.

## 2026-10-25 — Phase 5 architectural shell of the first route

Implemented the first present-day Córdoba route shell.

- Added `examples/Cordoba/cordoba.lua` and scene modules under
  `examples/Cordoba/scene/`:
  - `config.lua` — bounded envelope, column grid, cathedral bounds, route start,
    zones, and provisional shell dimensions.
  - `materials.lua` — lit stone/floor/timber/glass/gold/iron/dark materials plus full
    and simple lighting presets.
  - `architecture.lua` — generated floors, column/arch field, split-height timber
    ceilings, boundary walls, cathedral portals/walls/windows/vault/ribs/altar,
    grilles, collision proxies, and debug lines.
- The hypostyle field uses 18 column lines with a 10 m central nave and 5 m side
  aisles, two-tier striped horseshoe/round arches, capitals, and split ceilings.
- The cathedral shell has north/south portals, four side windows per wall, a
  barrel-vaulted high ceiling with ribs, an upper clerestory wall, an altar platform,
  gold cross panel, and flanking grilles.
- Added a HUD with route zone, controls, lighting state, and working `C` collision
  debug, `F` full/simple lighting, and `H` HUD toggles.
- Added `mesh.make_line_segments` support for the authored collision debug mesh.
- Recorded the bounded shell proportions and remaining uncertainty in
  `FLOORPLAN.md`; added D29.

Verification: `make test` — 56/56 files passed. `examples/Cordoba/cordoba.lua`
rendered under Xvfb/OpenGL; captures were checked from the north threshold, inside
the cathedral vault, and with collision proxies visible. A straight collision sweep
from the start enters the cathedral portal, stops against the altar platform at
Z ≈ 5.7 m, and the south portal/return route remains open.

Known deliberate limits: the full building envelope, precise chapel/chancel
partitions, detailed cathedral transept/choir, hero altarpiece, paintings, pews,
and final material/reflection work remain for Phases 6–9.

## 2026-10-25 — Phase 6 architectural materials, lighting, and reflections

Replaced the flat Phase 5 palette with generated architectural materials, warm
interior lighting, and the first retained reflection solution.

**Engine (reusable):**
- `render.material` gained `texture_scale`, `reflection_texture`,
  `reflection_strength`, and `environment_strength`.
- The OpenGL built-in lit shader now supports UV-scaled base/normal maps, a
  screen-space planar reflection sampler, and a cheap analytic sky/ground
  environment response for polished surfaces.
- `render.resolve_material_reflection_texture` resolves planar targets; the GL
  mesh factory binds reflection maps to sampler slot 2 and uploads viewport size,
  texture scale, reflection strength, and environment strength.
- `scene.RenderScene:render_to` accepts `options.camera`, temporarily swaps the
  scene camera for a pass, and restores it. This is the primitive used for planar
  reflection passes; `examples/reflection.lua` verifies it independently.
- Updated `render.md`, `scene.md`, and `sdl3x.md`; added deterministic render and
  scene tests.

**Córdoba:**
- Added `scene/textures.lua`: deterministic tileable limestone, plaster, brick,
  terracotta floor, marble, wood, granite, and metal textures with provenance
  metadata. Added `assets/PROVENANCE.md`.
- Split the hypostyle into polished dark column shafts and striped limestone
  arches; boundary walls use plaster, the cathedral uses pale marble, ceilings use
  timber, the altar base uses brick, and iron uses a metal map.
- Added 640×360 and 384×216 reflection targets and high/balanced/fallback floor
  materials. `Q` cycles quality; `F` still toggles full/simple lighting.
- The HUD now reports quality, lighting, viewport size, and smoothed frame rate.
- Tuned ambient fill, warm local lights, exposure, wood/terracotta/glass response,
  and the column shaft/capital contrast against the reference photographs.

**Reflection decision:** retain planar floor reflection with a mirrored camera and
screen-space sampling, plus the analytic environment response for polished stone
and metal. Screen-space ray-marched reflections are deferred because they need a
depth/normal prepass and are riskier on Haswell; cubemap/probe capture is deferred
until the cathedral volume exists. The no-target/all-fallback path uses an authored
floor material and simple lighting.

**Verification:** `make test` — 56/56 files passed. OpenGL/Xvfb captures were
inspected for the start view, cathedral interior, high/balanced/fallback quality,
and the isolated reflection example. Software-OpenGL benchmark at the observed
1366×712 framebuffer: high ≈17.4 fps, balanced ≈19.1 fps, fallback ≈24.4 fps.
These are sandbox numbers, not Haswell-class hardware results.

**Known deliberate limits:** texture detail is modest and generated; ornamental
carving, stained glass, the cathedral transept/choir, hero altarpieces, and
furniture remain for Phase 7–8. Reflection targets are fixed 16:9 sizes, so a
non-16:9 window can show slight aspect distortion until the Phase 9 polish pass.

## 2026-10-25 — Phase 7 Christian cathedral core and Villaviciosa chapel

Gave the route a recognizable Christian insertion and a hero destination.

**Engine:**
- Added `mesh.make_pointed_arch`, a two-centred Gothic arch ring in the XY plane
  with configurable span, radius, thickness, depth, segments, and colors.
- Documented it in `mesh.md` and covered it in `mesh_test.lua`.

**Cathedral core:**
- Added a pointed-arch nave arcade at X = ±12 m, with piers skipping the
  Villaviciosa opening.
- Added the crossing/transept bay at Z = −4…+4 m: pointed transverse arches,
  side-aisle transept arches, two diagonal ribs, and a gilded boss.
- Added a large gilded retablo in the Capilla Mayor, with a central niche,
  pointed gold arch, statue, side columns, upper tier, and candlesticks.
- Added dark timber choir stalls framing the central aisle without blocking it.
- Replaced the central south portal as the route exit with two side exits at
  X = ±18 m; the central portal is now the retablo backdrop.
- Extended the cathedral barrel vault to the end walls and opened the west side
  aisle roof over the chapel so the chapel vault is visible.
- Made the side windows taller and switched them to the generated stained-glass
  texture; improved the stained-glass generator with a central medallion.

**Villaviciosa chapel:**
- Added the X = −28…−12 m, Z = −24…−12 m chapel with pointed portal, stone
  portal frame, blind arcade, corner pilasters, ribbed barrel vault, stained
  window, gilded retable, altar cloth, candlesticks, and iron/stone details.
- Added a local warm light in the chapel and recentred the cathedral light to
  brighten the crossing vault.

**Zones and LOD:**
- `scene/config.lua` now defines ordered subzones (Villaviciosa, Capilla Mayor,
  Crossing, Cathedral nave, Cathedral aisles) and `hero`/`detail`/`shell` LOD
  parameter sets.
- The HUD reports the new zone names and Phase 7 state.

**Verification:** `make test` — 57/57 files passed. OpenGL/Xvfb captures were
inspected for the start view, nave, altar/retablo, crossing vault, and chapel.
Collision sweeps confirmed the central altar stop, the south side exits, and the
Villaviciosa portal route. Sandbox software-OpenGL timings at 1366×712: high
≈16.9 fps, fallback ≈23.7 fps; target Haswell timing remains pending.

**Known deliberate limits:** the retablo and chapel statues are simplified
silhouettes; carved ornament, paintings, detailed stained-glass leading, organs,
pews, rails, and the full transept/choir are Phase 8–9 work. LOD parameters are
metadata only until Phase 9 implements culling/streaming.

## 2026-10-25 — Mouse grab default and toggle

- Added SDL3 bindings for `SetWindowRelativeMouseMode`, `GetWindowRelativeMouseMode`,
  `SetWindowMouseGrab`, and `GetWindowMouseGrab`, exposed on `sdl3x.Window`.
- `app.App` gained `can_mouse_grab`, `set_mouse_grab`, `toggle_mouse_grab`, and
  `apply_mouse_grab`. Grab is requested state plus focus: losing focus releases the
  cursor, regaining focus restores it, and shutdown releases it before the window
  closes.
- `camera.walk` and `camera.fly` default to `mouse_grab = true`; `camera.orbit`
  defaults to `false`.
- `sketch` now grabs by default when any controller wants it, with
  `options.mouse_grab` to override and `options.mouse_grab_key` (default `"G"`) to
  toggle at runtime. The key is consumed before controllers and `app.key`.
- The Córdoba HUD shows `grab on/off` and lists `G grab`; `cordoba.lua` sets
  `mouse_grab = true` explicitly.
- Added `tests/app_test.lua` and camera defaults coverage; test baseline is 57/57
  files.

## 2026-10-25 — Phase 8 permanent contents and visitor route

Gave the present-day route permanent contents so it reads as the combined
mosque-cathedral rather than an empty shell.

**Engine:**
- Added three reusable prop generators to `mesh`: `make_grille` (framed bar field),
  `make_railing` (base rail, turned balusters, cap rail), and `make_pew` (seat,
  backrest, end panels, kneeler). All emit indexed `position_normal_color_uv_f32`
  geometry and are covered by `tests/mesh_test.lua`.

**Textures and materials:**
- Added a deterministic `painting` old-master canvas texture with provenance and
  mirrored it in `assets/PROVENANCE.md`.
- Added bronze, organ-pipe, painting, and interpretation-panel materials plus the
  supporting palette entries.

**Contents (`scene/contents.lua`):**
- Hanging bronze mosque lamps under the central hypostyle ceiling and crossing,
  and one in the Villaviciosa chapel.
- Villaviciosa reja panels flanking the 6 m gate with gilded cresting, and a chapel
  altar rail.
- A two-part Capilla Mayor altar rail with a central opening in front of the
  retablo.
- Fourteen shared pews facing the altar, kept clear of the central aisle.
- A two-rank wall organ in the east transept arm, a wall of framed paintings along
  the cathedral aisles and chapel, two crossing candelabra, two plinth statues,
  and three interpretation panels.
- Repeated props share one source mesh and merge into one drawable per material;
  `contents.stats` records instance and merged vertex/index totals.

**Collision and route:**
- Collision proxies are authored only for obstructive contents (pews, organ,
  signs, candelabra, statues, rejas, rails). The Villaviciosa gate and the central
  altar-rail opening stay clear.
- `cordoba.lua` gained inert environment-gated verification hooks:
  `CORDOBA_CAMERA`, `CORDOBA_SCREENSHOT`, `CORDOBA_CAPTURE_FRAME`, `CORDOBA_EXIT`,
  and `CORDOBA_SWEEP`. The HUD header now reports Phase 8.

**Verification:**
- `make test` — 57/57 files passed.
- OpenGL/Xvfb captures were inspected from the north threshold, the nave/altar,
  the crossing and organ, the Villaviciosa gate, the chapel interior, the pews,
  and a lamp view. The contents read at route scale and the new materials behave.
- Collision sweeps: central route stops at the altar platform
  (Z ≈ 5.70), the south side exit reaches the south hypostyle (Z = 40), and the
  Villaviciosa route reaches X ≈ −23.70 through the open gate.
- Sandbox software-OpenGL frame rates at the observed 1024×576 framebuffer stayed
  in the Phase 7 range (roughly 14–31 fps by view). Target Haswell timing remains
  pending.

**Known deliberate limits:** the retablo, statues, and organ are simplified
silhouettes; paintings are a single repeated generated canvas; the whole-building
content distribution and per-zone LOD culling are Phase 9 work.

## 2026-10-25 — Phase 9 whole-building interior expansion

Expanded the scene to the full published prayer-hall interior and made it
affordable with region-partitioned culling.

**Engine:**
- Added `mesh.partition(mesh, classify)`, a byte-level splitter that groups
triangles into per-region submeshes while preserving vertex sharing. This is the
primitive behind zone culling; it avoids materialising Lua vertex tables for a
building-scale mesh.
- Added `mesh.make_dome`, a hollow half-ellipsoid dome generator with outer, inner,
and rim surfaces. Both are documented in `mesh.md` and covered in
`tests/mesh_test.lua`.

**Envelope and geometry (`scene/`):**
- `config.lua` now defines the full 125 × 118 m envelope (X ±62.5, Z ±59), a
  19-aisle grid (10 m central nave plus nine ~6.39 m aisles per side) with 6 m N–S
  bays, the maqsura, and a 4×4 region/culling grid with `hero`/`detail`/`shell`
  LOD and an MVP region set.
- `architecture.lua` extends the hypostyle and ceilings automatically, and adds
  `build_maqsura` (raised platform, two axis domes, gilded screen, qibla-wall
  mihrab niche with horseshoe arch, flanking columns, gilded surround/finial, and
a gilded niche panel) and `build_perimeter_chapels` (striped horseshoe arcade plus
  partition-wall chapel compartments on the west/east walls and shallower bays on
  the north/south walls). The qibla wall is now solid; the mihrab supplies the
  niche. A local light moved from the retablo to the maqsura.
- `architecture.build` partitions every non-shell drawable by region and emits the
  floor, ceilings, and boundary as global drawables so culling can never open a
  hole to the background. It returns drawable, region, vertex, and triangle stats.

**Runtime (`cordoba.lua`):**
- Per-frame visibility uses `config.visible_regions` (bubble + behind-camera) to
  draw only visible regions, plus the always-global shell. The reflection pass
  uses the same set.
- `CORDOBA_MVP=1` or the `M` key intersects the visible set with the MVP regions.
  The HUD reports the visible/total draw count, zone, and frame rate.

**Verification:**
- `make test` — 57/57 files passed.
- Collision sweeps: central altar stop (Z ≈ 5.70), south side exit reaches the
  south hypostyle, Villaviciosa reaches X ≈ −23.70, maqsura route reaches the qibla
  wall (Z ≈ 58.35) through the screen opening, and a west chapel bay stops at its
  partition (Z ≈ 3.50).
- OpenGL/Xvfb captures were inspected from the north threshold, the maqsura screen
  and mihrab, the domes, a NW corner overview, the west arcade, and MVP mode. The
  full hall reads as a continuous hypostyle with a distinct maqsura.
- Baseline: 130 drawables over 16 regions, 459,705 vertices, 253,626 triangles,
  66 content instances. Visible draw counts ranged ~30–108 of 130 by view; frame
  rates stayed in the Phase 7–8 range (~19–45 fps software OpenGL at 1024×576).
  Target Haswell timing remains pending.

**Known deliberate limits:** the perimeter chapel bays, maqsura domes, and exact
bay counts are proportional approximations; contents remain concentrated in the
MVP route.

## 2026-10-25 — Phase 10 quality configurations and packaging

Turned the example into a documented, repeatable, user-selectable showcase.

**Culling fix and presets:**
- Replaced the Phase 9 distance-bubble culling with a forward-cone test
  (`config.visible_regions`): a region is drawn when its angular extent overlaps
  the camera's horizontal view cone, optionally within a `max_distance`. This fixed
  a dark void that the Balanced preset exposed at the end of the long nave.
- Added three named presets selected with `Q`: Rich (640×360 reflection, 95 m
  reflection range, full lighting, all contents), Balanced (384×216 reflection,
  65 m range, full lighting, all contents), and Performance (no reflection pass,
  simple lighting, structure only). The main pass has no distance limit; only the
  reflection pass is distance-limited.
- `CORDOBA_PRESET` selects a preset headlessly.

**Camera feel:**
- `camera.walk` gained an optional `smoothing` time constant (default `0`, so
  existing behavior and tests are unchanged). Córdoba enables `smoothing = 0.055`
  and a slightly lower mouse sensitivity.

**Packaging:**
- Added `examples/Cordoba/README.md`: controls, presets and trade-offs, run
  commands, asset policy, verification hooks, and known limitations.
- Updated the HUD to report the active preset, its summary, and the visible/total
  draw count.

**Verification:**
- `make test` — 57/57 files passed.
- Preset captures from the north threshold and the maqsura: Rich and Balanced
  draw ~124 of 130 drawables, Performance ~86; the reflection pass is the dominant
  cost. The Balanced void is gone.
- Clean-run check: with `examples/Cordoba/plan/images/` moved away, the example
  still ran and captured a valid PNG, confirming no host-photo dependency.
- Sandbox software-OpenGL at 1024×576: ~20–45 fps by view/preset. Per the project
  owner's direction there was no Haswell-specific tuning pass.

**Known deliberate limits:** proportions remain a documented approximation; the
outer field is largely empty structure; the 16:9 reflection targets can distort in
strongly non-16:9 windows; SDL GPU lit parity is out of scope.

## HANDOFF

**Project state:** Phases 0–10 complete (2026-10-25). The repository test baseline
is green at 57/57 files. The example is `examples/Cordoba/cordoba.lua`, documented
in `examples/Cordoba/README.md`, with the full 125 × 118 m interior, maqsura/mihrab,
perimeter chapels, permanent contents, forward-cone region culling, three named
visual presets, an MVP reduction switch, and inert headless verification hooks.

**No pending phase work.** Future improvements, if any, would be new scope rather
than an existing phase: more faithful proportions from a measured survey, richer
chapel/ornament content, occlusion beyond the forward cone, and SDL GPU lit parity.

**Constraints to preserve:**

- Do not run `make` and `./build/rig ...` smoke tests in parallel.
- Build first; then run smoke tests. Use `make test` for final verification.
- Any change to C code, build files, or `src/modules/` sources requires a rebuild
  before `./build/rig ...`.
- Keep OpenGL as the reference path.
- Reuse the mesh/material/collision/reflection/culling contracts; promote only
  truly reusable features into `src/modules/`.
- No crowds, audio, temporary exhibition furniture, or exterior expansion.
