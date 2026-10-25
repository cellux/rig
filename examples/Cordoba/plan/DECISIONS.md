# Design Decisions

## Purpose

This file records the design decisions that shape the implementation of the Córdoba project’s milestones. Decisions remain in force until explicitly superseded; a changed decision is retained and marked as superseded rather than deleted. Progress and the circumstances in which a decision was resolved belong in `DIARY.md`, while ordered implementation work belongs in `PHASES.md`.

## Status key

- **Accepted** — in force.
- **Superseded by Dn** — retained for history, no longer in force.
- **Proposed** — under review or deliberately deferred to a named phase; not yet binding.

---

## D1 — The scene is the present-day interior only

**Status:** Accepted (2026-10-25)

The long-term scene is the current combined interior of the Mosque-Cathedral. The courtyard, exterior façades, bell tower, roofs, and other exterior areas are outside the scene boundary. The scene is not a historical toggle: Islamic and Christian architecture coexist as they do today.

## D2 — OpenGL is the reference backend

**Status:** Accepted (2026-10-25)

OpenGL is the only backend that must work for this project because it is the only properly supported backend on the target Intel Haswell machine. SDL GPU parity is deferred and must not block OpenGL progress. Features that are OpenGL-only are labelled as such rather than weakening the OpenGL result for parity.

## D3 — Geometry is generated from parameters

**Status:** Accepted (2026-10-25)

All runtime geometry is generated procedurally by Rig from parameterized scene data. Blender and other offline modeling tools are not part of the production pipeline. Pre-existing textures are permitted; pre-existing 3D meshes are not used for the architectural pipeline.

## D4 — Reusable engine work lives in `src/modules/`, not in the example

**Status:** Accepted (2026-10-25)

A capability needed by Córdoba but generally useful to Rig belongs in `src/modules/FEATURE.lua` with its own documentation and tests. Córdoba-specific composition and parameter data stay under `examples/Cordoba/`. Isolated demonstrations of a developed feature live directly under `examples/FEATURE.lua`; they do not live under `examples/Cordoba/`.

## D5 — One unified Córdoba showcase, with an overlay from the start

**Status:** Accepted (2026-10-25)

`examples/Cordoba/cordoba.lua` is the public entry point. It demonstrates the developed features in context through an on-screen overlay exposing renderer/material modes, reflection and shadow options, HDR/tone-mapping choices, geometry detail, and collision/debug visualization as those features become available. An isolated `examples/FEATURE.lua` demo is added only when independent verification is useful.

## D6 — The first route is the hypostyle-to-cathedral corridor

**Status:** Accepted (2026-10-25)

The first detailed release is a central route beginning in the red/cream hypostyle hall, passing dense columns and grilles, and opening into the Christian cathedral/chapel volume. The route must show the repeated two-tier arches, contrasting floor materials, and at least one hero chapel or altarpiece. The rest of the building is developed later around this detailed zone.

## D7 — All modelled interior areas are explorable

**Status:** Accepted (2026-10-25)

The simulation imposes no present-day visitor-access restrictions. Modelled chapels and interior areas remain explorable even when the real visitor route is barred. Railings and grilles are collision-relevant when physically obstructive; visitor-management barriers do not artificially prevent exploration.

## D8 — Only permanent or semi-permanent contents are modelled

**Status:** Accepted (2026-10-25)

Chapels, retables, paintings, sculpture, organs, fixed signs, display elements, lamps, pews/chairs, rails, and grilles are in scope. Tourists, crowds, temporary speakers, event equipment, temporary movable barriers, and ambient audio are out of scope for the milestone.

## D9 — Units, axes, and origin are fixed

**Status:** Accepted (2026-10-25)

All scene coordinates are in metres. Rig's world convention is Y up. Córdoba uses +X east and +Z south (towards the qibla wall and mihrab), so the building's long north–south axis is Z and its 125 m east–west width is X. The origin is the centre of the prayer-hall interior at floor level, not the courtyard or the exterior envelope. See `FLOORPLAN.md` for the derived bounds and uncertainty.

## D10 — The floor-plan base is documented, not treated as a precise survey

**Status:** Accepted (2026-10-25)

The plan uses the public-domain 1868 Mariano López y Sánchez plan for room topology and the current-building Commons plan for present-day Christian insertions, calibrated against the published 178 m × 125 m building dimensions. Sources disagree and the drawings predate modern restoration, so dimensions are recorded with confidence levels and refined during Phase 2 rather than presented as a measured survey.

## D11 — Collision is authored separately from render geometry

**Status:** Accepted (2026-10-25)

Collision uses simple proxies (circles/capsules, boxes, segments, polygons) authored per zone and kept independent of detailed render meshes. Render geometry must never be required for movement to be correct or cheap. A debug visualization is part of the collision phase.

## D12 — Navigation is a ground-constrained walk, not a fly camera

**Status:** Accepted (2026-10-25)

The MVP has WASD movement on the floor plane, mouse look whenever the focused window receives mouse movement, a fixed eye height, configurable speed, and collision against static architecture. Jumping, crouching, sprinting, doors, and other gameplay mechanics are out of scope. A known start pose and reset path are provided for testing.

## D13 — Mesh contract grows progressively and stays provider-neutral

**Status:** Accepted (2026-10-25)

The backend-neutral mesh contract gains optional normals and tangents, indexed geometry, primitive/topology metadata, and material ranges as the renderer needs them. Existing unlit layouts remain valid. The GL mesh factory consumes the expanded contract first; SDL GPU support follows when it does not block the OpenGL path. See Phase 2.

## D14 — Materials have an explicit backend-neutral contract

**Status:** Accepted (2026-10-25)

Material values express albedo/base colour, optional normal/detail information, roughness/specular response, emissive contribution, opacity/cutout, depth policy, and culling policy. Backends choose the useful subset and document unsupported fields instead of silently ignoring them. An unlit/textured fallback remains available. See Phase 3.

## D15 — Lighting starts small and grows by measurement

**Status:** Accepted (2026-10-25)

The first lit path uses a bounded light model suitable for Haswell-class hardware: directional daylight, ambient fill, and a limited number of local warm lights. HDR, tone mapping, shadows, baked/static contributions, and reflections are evaluated progressively and retained only when their measured visual gain justifies their cost. No commitment to real-time global illumination is made before the simpler baseline is measured.

## D16 — Reflections degrade gracefully

**Status:** Accepted (2026-10-25)

Reflective floors, polished stone, metal railings, gold details, and dark wood are visual priorities. The implementation evaluates screen-space, planar, environment/probe, and baked-looking approximations and keeps the best practical OpenGL trade-off. If hardware or shader support prevents a technique, the fallback uses authored roughness and reflection probes/approximations rather than blocking the project.

## D17 — Quality settings are explicit and comparable

**Status:** Accepted (2026-10-25)

At least two progressively enhanced visual configurations are selectable through the Córdoba overlay by the final phase. Quality tiers may reduce shadow/reflection resolution, local lights, texture size, or ornament density without changing the scene description. Trade-offs and performance measurements are documented.

## D18 — Zones and culling are part of the scene data from the start

**Status:** Accepted (2026-10-25)

The floor plan is divided into named zones with bounds and level-of-detail/quality parameters. This enables coarse visibility culling, streaming, and a reduced MVP scene later without rewriting scene data. Zone identity is documented for every major area in Phase 9.

## D19 — Texture assets are permitted, with provenance and regeneration metadata

**Status:** Accepted (2026-10-25)

This is a private project with no licensing enforcement gate or fixed asset-size budget. Pre-existing photographic textures may be used. Source, dimensions, scale, conversion steps, and generator versions are recorded where practical under `examples/Cordoba/assets/`. Generated/tiled material data is preferred for large repetitive surfaces.

## D20 — Verification is automated first, manual second

**Status:** Accepted (2026-10-25)

Geometry generators, floor-plan conversion, collision primitives, collision resolution, and camera movement have deterministic tests. Renderer capabilities have focused runnable examples and, where practical, headless smoke tests. `make test` is the final gate; `./build/rig ...` smoke tests are supplemental. Manual visual checks on the target class are recorded in `DIARY.md`.

## D21 — Backward compatibility is not a requirement

**Status:** Accepted (2026-10-25)

Rig has a single author and in-repo callers only. APIs are reshaped or removed once callers are migrated. No compatibility shims are added for the Córdoba work.

## D22 — No crowds, audio, or gameplay systems in the MVP

**Status:** Accepted (2026-10-25)

The experience is a quiet architectural walk. The project does not add crowd simulation, ambient audio, objectives, inventory, or interaction beyond navigation. This keeps the milestone focused on architecture, materials, and light.

## D23 — Reference photographs are visual evidence, not survey data

**Status:** Accepted (2026-10-25)

The supplied photographs in `plan/images/` define material, lighting, and composition references. They do not provide reliable dimensions. Architectural dimensions and topology come from documented plan/source data, with uncertainty recorded where sources disagree.

## D24 — The technical spike may use throwaway code

**Status:** Accepted (2026-10-25)

Phase 1 exists to discover engine gaps quickly. Its code may be replaced by the reusable Phase 2–4 APIs. It still runs from the repository and still obeys `make test`/rebuild rules, but it is not a compatibility surface.

## D25 — Screenshots are opt-in behind `RIG_ENABLE_SCREENSHOTS`

**Status:** Accepted (2026-10-25)

Frame capture is a verification and authoring tool, not part of the normal render path. It is enabled only when `RIG_ENABLE_SCREENSHOTS` is truthy; sketches skip the per-frame screenshot flush otherwise. The backend-neutral API is `screenshot`, PNG encoding is provided by `png.encode`, and capture is a capability (`screenshot.capture`) with one provider per backend: OpenGL (`gl.ReadPixels`), SDL renderer (`SDL_RenderReadPixels`), and SDL GPU (swapchain download). Missing providers raise a clear error rather than silently producing empty images.


## D26 — Mesh layouts carry roles, and indexed geometry is a first-class mesh field

**Status:** Accepted (2026-10-25)

Mesh layouts are explicit role maps with stable attribute locations: position 0, color 1, uv 2, normal 3, tangent 4. New architectural layouts append normals and optional tangents without changing the existing unlit layouts. Indexed meshes carry `index_blob`, `index_count`, `index_type`, and `index_stride`; index buffers are zero-based and backends choose indexed draws when present. Architectural generators emit indexed triangles by default.

The `mesh.builder` merges triangle meshes into one indexed mesh and records zero-based per-section material ranges (`index_offset`, `index_count`, `vertex_offset`, `vertex_count`, `name`, `material`). The current unlit material ignores those ranges and draws the merged mesh once; the ranges are metadata for the Phase 3 material path. Builder normals are generated smooth over shared vertices, and tangents are generated only when the target layout asks for them.


## D27 — Lit materials are OpenGL-first with a documented plain-uniform contract

**Status:** Accepted (2026-10-25)

`render.material { shading = "lit" }` uses the OpenGL backend's built-in lit shader and a backend-neutral `render.lighting` value stored on the scene. Material fields have explicit defaults: albedo, roughness, specular, emissive, opacity, alpha mode/cutoff, depth test/write, and cull mode. Base and normal textures bind to slots 0 and 1. Lit meshes require normals; normal-mapped lit meshes require tangents and UVs.

The shader contract is plain GLSL uniforms (`u_mvp`, `u_model`, `u_base_color`, `u_emissive`, roughness/specular/cutoff, camera position, ambient/directional light, four local point lights, exposure). Córdoba may add scene-specific uniforms through a custom material template that follows the same conventions rather than forking the backend shader. The SDL GPU backend rejects built-in lit materials with a clear error while keeping unlit/textured materials working; GPU lit parity remains deferred behind OpenGL.


## D28 — Collision is a 2D static layer with adaptive substepped sweeping

**Status:** Accepted (2026-10-25)

The walk layer is ground-constrained, so collision lives on the XZ plane. The player is a circle; a capsule reduces to its XZ projection because there is no jump, crouch, or vertical movement. Static shapes are circles, optionally rotated boxes, thickness segments, and polygons. Each shape precomputes AABB bounds for broadphase checks.

Movement is split into adaptive substeps tied to the player radius, then penetration is resolved against the deepest overlapping shape. This prevents tunnelling through thin walls at high speed and slides along surfaces without a separate ray/TOI implementation. Collision data is authored independently of render meshes. `world:debug_mesh` emits disjoint lines via the new `mesh.make_line_segments`.

The walk controller uses WASD on the plane, mouse look while the window is focused (or while an optional look button is held), fixed eye height, a reset action, and clears held keys on focus loss.


## D29 — Phase 5 uses a bounded route shell with explicit provisional proportions

**Status:** Accepted (2026-10-25)

The first architectural shell is a bounded MVP envelope (X −50…+50 m, Z −59…+47 m) rather than the full 125 m × 118 m interior. It uses 18 column lines with no column on the central axis, a 10 m central nave, 5 m side aisles, two-tier striped arches, split-height hypostyle ceilings, and a cathedral insertion with portals, side windows, a barrel vault, ribs, and an altar platform. These dimensions are recorded in `FLOORPLAN.md` as provisional visual estimates, not a survey.

Córdoba-specific plan, grid, materials, and generated architecture live under `examples/Cordoba/scene/`; the entry point is `examples/Cordoba/cordoba.lua`. The scene uses the Phase 2 mesh builders, Phase 3 lit materials/lighting, and Phase 4 walk/collision layer. Collision proxies are authored separately from render meshes and are debug-drawn. Full-building expansion, precise chapel geometry, and hero contents remain later-phase work.


## D30 — Phase 6 uses procedural textures, planar floor reflections, and an analytic environment fallback

**Status:** Accepted (2026-10-25)

**Materials.** The production Córdoba scene loads no external textures. `scene/textures.lua` generates deterministic, tileable limestone, plaster, brick, terracotta floor, marble, wood, granite, and metal images at startup. `M.provenance` records generator, seed, size, and license for each image, mirrored in `assets/PROVENANCE.md`. Materials split into limestone arches, pale plaster boundary walls, marble cathedral stone, polished dark column shafts with pale capitals, terracotta floors, timber ceilings, brick altar base, glass, gold, and iron. UV scaling is a material property so one texture can serve different world scales.

**Reflections.** The retained primary solution is a planar reflection for the floor: the scene renders all non-floor geometry from a camera mirrored across Y = 0 into a `render.target` (640×360 high, 384×216 balanced), and the floor's built-in lit material samples that target in screen space after tone mapping. `scene.RenderScene:render_to` gained an optional temporary camera for this pass. Polished columns, gold, iron, and the no-target fallback use a cheap analytic sky/ground environment response driven by Fresnel and `environment_strength`. A no-reflection floor material with the analytic response is the fallback when the target capability is unavailable.

**Why not screen-space reflections or probes now.** SSR needs a depth/normal prepass and per-pixel ray marching that is risky on Haswell and much larger than the Phase 6 shell justifies. A cubemap/probe pipeline needs reflection capture, filtering, and blending infrastructure that is better evaluated after the cathedral volume exists. The planar pass is predictable, has a hard resolution knob, and degrades to an authored material without changing scene data.

**Quality tiers.** `Q` cycles high (640×360 planar + full lighting), balanced (384×216 planar + full lighting), and fallback (no reflection pass + simple lighting + analytic environment). `F` still toggles full/simple lighting independently.

**Measurements.** On the sandbox software OpenGL path at the observed 1366×712 framebuffer: high ≈17.4 fps, balanced ≈19.1 fps, fallback ≈24.4 fps. These are not Haswell-class hardware results; target-host timing remains pending.


## D31 — Phase 7 uses a bounded cruciform core, a retablo hero view, and one hero chapel

**Status:** Accepted (2026-10-25)

**Core scope.** The cathedral insertion is deliberately bounded rather than a full transept reconstruction. A pointed-arch nave arcade at X = ±12 m separates the central vessel from the side aisles; the crossing spans Z = −4…+4 m with pointed transverse arches, two diagonal ribs, and a gilded boss. The Capilla Mayor keeps the existing altar platform and adds a large gilded retablo silhouette at Z ≈ 12.8 m. The central south portal becomes the retablo backdrop and two side exits at X = ±18 m preserve the loop route. Choir stalls frame the central aisle without blocking it.

**Hero chapel.** The Villaviciosa chapel occupies X = −28…−12 m, Z = −24…−12 m, opens west from the aisle through a 6 m pointed portal, and has a ribbed barrel vault, stained-glass window, gilded retable, altar, and blind arcade. It is intentionally a single hero chapel, not a perimeter-chapel row.

**Reusable geometry.** `mesh.make_pointed_arch` was added as a two-centred Gothic arch generator and is used by the nave arcade, transept, chapel portal, and retablo niche. The rest of the core reuses the existing mesh/material/collision contracts.

**Zones and LOD.** `scene/config.lua` now defines ordered cathedral subzones and `hero`/`detail`/`shell` LOD parameter sets. These are metadata for Phase 9 culling and streaming; Phase 7 does not yet implement runtime LOD switching.

**Collision.** New piers, chapel walls/portal, retablo, choir stalls, side-exit wall segments, and chapel altar use authored collision proxies independent of render meshes. Verified routes: start → altar stops at Z ≈ 5.7; side exit at X = 18 continues through the south hypostyle; nave → Villaviciosa portal reaches X ≈ −23.7; chapel → nave returns through the portal.

**Measurements.** Sandbox software OpenGL at the observed 1366×712 framebuffer: high ≈16.9 fps, fallback ≈23.7 fps. Target Haswell timing remains pending.

**Known limits.** The retablo and chapel statues are simplified silhouettes; carved ornament, paintings, stained-glass leading detail, choir stalls, and the full transept/choir are Phase 8–9 work.


## D32 — First-person controllers request mouse grab by default

**Status:** Accepted (2026-10-25)

`camera.walk` and `camera.fly` default to `mouse_grab = true`; `camera.orbit` stays
`false`. A sketch grabs automatically when any attached controller wants it, unless
`options.mouse_grab` overrides the choice. `options.mouse_grab_key` defaults to `"G"`
and toggles the state; setting it to `false` disables the shortcut.

The runtime applies **relative mouse mode** and **mouse grab** together through
`sdl3x.Window`, so the cursor is hidden and confined for first-person look. Focus
loss releases the actual grab while preserving the requested state; focus gain
reapplies it; shutdown releases it before window destruction. `app.App` exposes
`can_mouse_grab`, `set_mouse_grab`, `toggle_mouse_grab`, `apply_mouse_grab`, and
`mouse_grab_enabled`; the sketch facade forwards the same conveniences.

## D33 — Phase 8 permanent contents are shared source meshes merged per material

**Status:** Accepted (2026-10-25)

**Reusable primitives.** Three prop generators were promoted into `mesh` because they
are generic furniture/architectural forms rather than Córdoba-specific composition:
`mesh.make_grille` (framed bar field), `mesh.make_railing` (base rail, balusters, cap
rail), and `mesh.make_pew` (seat, backrest, end panels, kneeler). They emit indexed
`position_normal_color_uv_f32` geometry and are covered by `tests/mesh_test.lua`.

**Sharing.** Córdoba's permanent contents live in `scene/contents.lua`. Every repeated
prop is generated once (lamp, candelabra, statue, sign stand/panel, organ case/pipes,
pew, altar/chapel railing, reja) and added to per-material `mesh.builder` buffers with
a transform per instance. The merged result is one drawable per material, so instance
count grows while vertex/index growth stays proportional to the number of unique parts
plus their transforms. `contents.stats` records the instance count and merged
vertex/index totals.

**Contents.** Hanging mosque lamps in the central hypostyle and crossing,
Villaviciosa reja panels and chapel altar rail, a two-part Capilla Mayor altar rail
with a central opening, fourteen shared pews facing the altar, a wall organ with two
graduated pipe ranks, framed paintings using a new generated `painting` texture, two
crossing candelabra, two statues on plinths, and three interpretation panels.

**Collision and access.** Collision proxies are authored only for physically
obstructive contents (pews, organ, signs, candelabra, statues, rejas, rails).
Visitor-management-only elements and the route gate are left non-blocking: the
Villaviciosa opening keeps a 6 m clear gate between its flanking reja panels, and the
Capilla Mayor altar rail has a central opening. Verified sweeps: central route stops
at the altar platform (Z ≈ 5.7), the south side exit reaches the south hypostyle at
Z = 40, and the Villaviciosa route reaches X ≈ −23.7 through the open gate.

**Verification hooks.** `cordoba.lua` gained inert, environment-gated headless hooks:
`CORDOBA_CAMERA="x,y,z,yaw,pitch"` overrides the start pose, `CORDOBA_SCREENSHOT`
plus `CORDOBA_CAPTURE_FRAME` queues a capture, `CORDOBA_EXIT=1` stops after the
capture frame, and `CORDOBA_SWEEP=1` prints the collision route sweeps.

## D34 — Phase 9 expands to the full envelope with region-partitioned culling

**Status:** Accepted (2026-10-25)

**Envelope.** The interior is the full published prayer hall: X −62.5 … +62.5 m
(125 m east–west) by Z −59 … +59 m (118 m north–south), centred on the origin. The
grid is 19 aisles (a 10 m central nave plus nine ~6.39 m aisles per side) and 6 m
north–south bays from Z = −54 to +54. The cathedral insertion keeps its Phase 7
footprint; the maqsura/mihrab occupies X −18 … +18, Z 38 … 59 at the qibla end;
perimeter chapel bands run along the west, east, north, and south walls.

**Culling contract.** `scene/config.lua` partitions the envelope into a 4×4 grid of
16 axis-aligned regions, each with centre/radius, a `lod` (`hero`/`detail`/`shell`),
and a `cull_radius`. `mesh.partition` (new reusable engine API) splits each merged
material mesh into per-region submeshes by triangle centroid, preserving vertex
sharing and operating directly on the vertex/index bytes so building-scale meshes
are not materialised as Lua tables. The runtime draws a drawable only when its
region is visible: within `cull_radius + region.radius` and not fully behind the
camera. The camera's own region is always included.

**Watertight shell.** The floor, ceilings, and boundary walls are emitted as
`region = "global"` drawables that are never culled, so culling can never open a
hole to the background. Partitioned geometry is columns, arches, cathedral, core,
maqsura, perimeter chapels, and contents.

**MVP reduction.** `CORDOBA_MVP=1` (or the `M` key) intersects the visible set with
`config.mvp_region_ids`, the central north–south band (regions r21/r31/r22/r32/
r23/r33). This satisfies the Phase 9 development-reduction deliverable.

**Maqsura and mihrab.** Two ribbed-bay domes (`mesh.make_dome`, new reusable
generator) spring under the hypostyle ceiling over the central axis, a gilded
screen with a central opening leads to the mihrab, and the qibla-wall mihrab is a
dark recess with a horseshoe arch, flanking marble columns, gilded surround and
finial, and a gilded niche panel. A local light was moved from the retablo to the
maqsura; the retablo remains lit by the crossing light.

**Perimeter chapels.** A blind arcade of striped horseshoe arches with partition
walls forms shallow chapel compartments along the west/east walls (west/east) and
shallower bays on the north/south walls outside the entrance and maqsura. Recess
backs use a shadowed stone colour rather than the near-black `dark` material so the
compartments read under ambient light.

**Measured baselines.** Software OpenGL at 1024×576: total 130 drawables over 16
regions, 459,705 vertices, 253,626 triangles, 66 content instances. Visible draw
counts ranged from ~30 (mihrab view) to ~108 (north threshold) of 130, and frame
rates stayed in the Phase 7–8 range (~19–45 fps by view). Target Haswell timing
remains pending.

## D35 — Phase 10 uses forward-cone culling and three named visual presets

**Status:** Accepted (2026-10-25)

**Culling supersedes D34's distance bubble.** A radius bubble is wrong for a large
open hypostyle: from the north threshold it culled the far cathedral region and
punched a dark void at the end of the nave. `config.visible_regions` now uses a
forward cone: a region is drawn when its angular extent overlaps the camera's
horizontal view cone (half-angle derived from the camera FOV and window aspect,
plus a margin) and, optionally, within a `max_distance`. The main pass has no max
distance, so long sightlines stay intact; the reflection pass uses a 95 m (Rich) or
65 m (Balanced) limit because distant floor reflections are barely visible. The
camera's own region and the global floor/ceiling/boundary drawables are always
included.

**Visual presets.** `Q` cycles three named, progressively enhanced configurations
that bundle reflection target, reflection range, lighting, and content visibility:

- **Rich**: 640×360 planar reflection, 95 m reflection range, full lighting, all
  contents.
- **Balanced**: 384×216 planar reflection, 65 m reflection range, full lighting,
  all contents.
- **Performance**: no reflection pass (analytic environment fallback floor), simple
  lighting, structure only.

`F` remains an independent full/simple lighting override. `M` remains the
MVP-reduction switch. The HUD reports the active preset, its summary, the
visible/total draw count, and the frame rate.

**Camera feel.** `camera.walk` gained an optional `smoothing` time constant
(default `0`, preserving existing behavior). Córdoba enables `smoothing = 0.055`
and a slightly lower mouse sensitivity. `reset()` clears the smoothed velocity.

**Packaging.** Added `examples/Cordoba/README.md` (controls, presets, run commands,
asset policy, verification hooks, limitations). The production run loads no host
photo directory; a run with `plan/images/` moved away was verified. Added
`CORDOBA_PRESET` to select a preset headlessly.

**No Haswell-specific tuning.** Per the project owner's direction, Phase 10 keeps
the OpenGL-first quality tiers without a measured hardware pass. Recorded numbers
remain software-OpenGL sandbox observations, not a hardware target.

---

## Open technical choices (deferred, not yet binding)

These are deliberately unresolved and belong to the named phase. They must be recorded here when resolved.

- **Phase 1:** the first reflection experiment (screen-space, planar, probe, or approximation) and its measured cost.
- **Phase 2:** resolved by D26. Follow-up belongs to Phase 3: how material ranges map to backend draw ranges/draw calls.
- **Phase 3:** resolved by D27. Follow-ups for Phase 6: normal-map authoring strategy, local-light budget on Haswell, and whether a scene uniform block replaces plain uniforms.
- **Phase 4:** resolved by D28. Follow-ups for later phases: spatial partitioning for the full building and zone-level collision authoring. Phase 8 rail/barrier semantics recorded in D33.
- **Phase 8:** resolved by D33. Follow-up for Phase 9/10: whether contents need per-zone LOD reduction or culling beyond the current per-material merging.
- **Phase 6:** the final reflection and lighting compromise on the target hardware; Phase 5's split-height timber ceilings, vault, and lit-material palette are the starting point.
- **Phase 9:** resolved by D34 (4×4 regions, MVP reduction, global watertight shell).
- **Phase 10:** resolved by D35 (forward-cone culling, three named presets, camera smoothing, README). No further open engine choices are pending for the interior MVP.

