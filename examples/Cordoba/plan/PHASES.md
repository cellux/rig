# Implementation Phases

## Purpose

This file turns the milestone specification in `PLAN.md` into an ordered set of independently implementable and testable phases. Each phase defines its own scope, prerequisites, implementation work, verification, and completion criteria. Progress belongs in `DIARY.md`; enduring design choices belong in `DECISIONS.md`.

## Conventions

- Phases are ordered and cumulative; a phase must not depend on later work.
- A phase is complete only when its verification passes and no earlier phase regresses.
- Final verification is `make test`. A change to C code, build files, or embedded module sources under `src/modules/` also requires a rebuild before any supplemental `./build/rig ...` smoke test, per `AGENTS.md`.
- `PLAN.md` is the specification. This file may split a milestone into several implementable phases but must not silently narrow the milestone's acceptance criteria.
- Reusable engine work is implemented in `src/modules/FEATURE.lua` with documentation and tests. Córdoba-specific scene data and composition live under `examples/Cordoba/`. Isolated runnable demonstrations live directly under `examples/`.
- Procedural geometry only. No Blender, glTF authoring, or other offline modeling pipeline.
- Backward compatibility is not a requirement; in-repo callers are migrated when an API changes.

## Phase 0 — Research, provenance, and spatial baseline

**Status:** Complete (2026-10-25)

**Goal.** Establish a defensible reference base, coordinate convention, interior-only boundary, and first walking route before writing rendering code.

**Deliverables.**

- `SOURCES.md`: source and provenance inventory for floor plans, dimensions, historical descriptions, and the supplied photographs, with licence/access notes and confidence.
- `FLOORPLAN.md`: metre-based coordinate convention, interior boundary, zone naming, approximate dimensions and column-grid assumptions, the first route, and known uncertainties.
- Reference floor-plan copies under `plan/reference/` (not runtime assets).
- Decisions D1–D12 in `DECISIONS.md`.

**Out of scope.** Precise measured survey; runtime assets; any engine change.

**Dependencies.** None.

**Verification.** Review: every dimension used later can be traced to a source or explicitly marked as an estimate; the route is bounded and named; the coordinate convention is unambiguous.

## Phase 1 — OpenGL technical spike

**Status:** Complete (2026-10-25; sandbox verification, host performance timing pending)

**Goal.** Prove on the reference OpenGL path that Rig can load a pre-existing texture, generate a parameterized mesh, accept camera input, and render a plausible reflective surface.

**Deliverables.**

- `examples/Cordoba/spike.lua` (plus shaders under `examples/Cordoba/assets/`), runnable directly with `./build/rig`.
- One loaded photographic or generated texture, one parameterized generated mesh, a first-person or free camera, and a reflective-floor experiment (screen-space, planar, or a documented approximation).
- The optional `screenshot` module (`RIG_ENABLE_SCREENSHOTS`) with PNG encode support, used to verify the spike headlessly.
- A short performance note for the target Intel Haswell class and a list of engine gaps discovered.
- Findings added to `DIARY.md`; any resulting design choice added to `DECISIONS.md`.

**Out of scope.** Final materials, collision, architectural accuracy, reusable module APIs.

**Dependencies.** Phase 0.

**Verification.** `make test` (55/55 files); the spike runs under `./build/rig` and writes a valid 1024×576 PNG through the screenshot facility; texture, mesh parameter, camera, and reflection all visibly participate. Host performance timing remains to be recorded.

## Phase 2 — Procedural mesh contract and architectural generators

**Status:** Complete (2026-10-25)

**Goal.** Give Rig a reusable, backend-neutral procedural mesh foundation rich enough for the architectural shell.

**Deliverables.**

- Extend the mesh layout contract with optional normals and tangents, and with indexed geometry where it materially reduces memory or draw overhead. Keep the existing unlit layouts working.
- Shared/indexed vertex and index buffers in the OpenGL mesh factory; matching SDL GPU support when it does not block the OpenGL path.
- Generators and composition helpers for boxes, cylinders/columns, capitals, horseshoe and round arch rings, striped voussoir bands, wall panels, floor bays, window openings, and vault sections.
- A `mesh` builder that merges generated primitives into a larger mesh with per-section material ranges, plus UV/normal generation.
- `examples/procedural_mesh.lua` primitive gallery and `tests/mesh_test.lua` coverage.
- Documentation in `mesh.md`.

**Out of scope.** Lit shading itself; scene-specific Córdoba geometry; LOD and streaming.

**Dependencies.** Phase 1 findings.

**Verification.** `make test` (55/55 files); `examples/procedural_mesh.lua` renders the generated gallery on OpenGL and SDL GPU; deterministic tests cover layouts, vertex/index counts, normals, tangents, openings, and merge/material ranges.

## Phase 3 — Material and lit shading foundation

**Status:** Complete (2026-10-25)

**Goal.** Replace the unlit-only look with a small, controllable lit material path and a backend-neutral material contract.

**Deliverables.**

- Backend-neutral material fields for albedo/base colour, optional normal/detail texture, roughness/specular response, emissive contribution, opacity/cutout, depth, and culling policy, with explicit defaults.
- An OpenGL built-in lit material (or a documented material-template mechanism) supporting a directional daylight, a small bounded set of local warm lights, ambient contribution, and a controlled exposure/colour workflow.
- A documented uniform contract so Córdoba can add scene-specific parameters without forking the backend material.
- `examples/material_lighting.lua` (lit, textured, normal-mapped test objects) and `tests/render_test.lua`/shader coverage.
- Documentation in `render.md` and `mesh.md`.

**Out of scope.** Shadows, HDR, tone mapping, true reflections, and full PBR. Those are evaluated in Phase 6.

**Dependencies.** Phase 2.

**Verification.** `make test` (55/55 files); `examples/material_lighting.lua` renders indexed generated geometry with normals, a base texture, a normal map, directional daylight, local warm lights, and exposure on OpenGL; unlit and textured fallback paths still pass their tests. SDL GPU rejects built-in lit materials with a clear error, as documented.

## Phase 4 — First-person walk controller and collision

**Status:** Complete (2026-10-25)

**Goal.** Provide a safe, reusable ground-constrained walk mode with static collision.

**Deliverables.**

- A `camera` walk controller: WASD on the floor plane, mouse look on focused-window movement, fixed eye height, configurable speed, and a stable reset pose.
- A reusable collision layer (circles/capsules against circles, axis-aligned or oriented boxes, segments, and polygons) with swept resolution that prevents tunneling at normal speeds and avoids corner jitter.
- Collision data kept independent of render meshes, with an optional debug draw.
- `examples/collision_walk.lua` and deterministic `tests/collision_test.lua`/camera tests.
- Documentation in `camera.md` and the new collision module documentation.

**Out of scope.** Jumping, crouching, sprinting, doors, dynamic bodies, and general physics.

**Dependencies.** Phase 3 (for the debug-draw path); may start after Phase 2 if material work is deferred.

**Verification.** `make test` (56/56 files); deterministic collision tests cover walls, thin walls at high speed, sliding, circles, segments, polygons, initial penetration, capsule aliasing, and debug lines; camera tests cover fixed-height movement, focus-gated mouse look, reset, and blocking through a real collision world. `examples/collision_walk.lua` runs on OpenGL and SDL GPU with live debug proxies.

## Phase 5 — Architectural shell of the first route

**Status:** Complete (2026-10-25)

**Goal.** Build the first walkable Córdoba shell without decorative contents.

**Deliverables.**

- `examples/Cordoba/cordoba.lua` as the unified entry point, with a small on-screen overlay for quality and debug toggles from the start.
- Córdoba scene modules for floor plan, zone bounds, materials, and generated architecture.
- Floors with the major material regions; interior boundary walls and openings; repeated columns, capitals, lower horseshoe arches, and upper round arches with red/cream stripes; representative ceilings, vaults, windows, and daylight openings.
- Collision proxies for walls and columns, and a known camera start on the first route.
- The route from the hypostyle hall, past grilles, into the Christian cathedral/chapel volume at shell level.

**Out of scope.** Hero chapel contents, paintings, altarpieces, pews, detailed carving, and the rest of the building.

**Dependencies.** Phases 1–4.

**Verification.** `make test` (56/56 files); `examples/Cordoba/cordoba.lua` builds and renders the bounded route shell on OpenGL; the straight route starts at the north threshold, passes through the cathedral portal, stops against the altar platform, and exits through the south portal; collision proxies cover columns, boundary walls, cathedral wall segments, grilles, and the altar. The HUD, lighting toggle, and collision debug toggle work. Visual checks were captured from the north threshold, inside the cathedral vault, and with collision proxies enabled.

## Phase 6 — Architectural materials, lighting, and reflections

**Status:** Complete (2026-10-25)

**Goal.** Make the shell read as the warm, pale-stone, red-striped, highly reflective interior in the references.

**Deliverables.**

- Stone, plaster, brick, terracotta, marble, wood, and metal materials generated or textured with provenance metadata.
- Controlled exposure, ambient fill, warm local lights, and the first deliberate reflection solution for floors and polished stone; evaluate screen-space, planar, probe/environment, and baked-looking approximations and retain the best OpenGL trade-off.
- Documented fallback path when advanced material or reflection features are unavailable.
- Quality switches exposed through the Córdoba overlay.
- Performance measurements on the target class in `DIARY.md`.

**Out of scope.** Full real-time global illumination; production-quality normal maps for every ornament.

**Dependencies.** Phase 5.

**Verification.** `make test` (56/56 files); `examples/Cordoba/cordoba.lua` renders the textured, warm-lit, reflective route shell on OpenGL; the high, balanced, and fallback quality tiers were captured and inspected; `examples/reflection.lua` verifies the reusable planar-reflection path independently. The reference photographs were compared for terracotta floor tone, dark polished column shafts, pale limestone/plaster, red/cream arches, and warm window/local-light contrast. Sandbox software-OpenGL timings at the observed 1366×712 framebuffer were ≈17.4 fps (high), ≈19.1 fps (balanced), and ≈24.4 fps (fallback); target Haswell timing remains pending.

## Phase 7 — Christian cathedral core and hero chapel

**Status:** Complete (2026-10-25)

**Goal.** Insert the visually dominant Christian architecture and give the route a hero destination.

**Deliverables.**

- The Capilla Mayor / cruciform cathedral core: nave and transept volumes, ribbed and star-like vaults, tall windows, stained glass, portals, choir enclosure, and the main altar/retablo silhouette.
- At least one additional hero chapel or portal with convincing scale and ornament, plus the Villaviciosa transition.
- Collision coverage for every approachable element.
- Zone identity and level-of-detail parameters for the new architecture.

**Out of scope.** Every side chapel and every individual artwork; the whole-building expansion.

**Dependencies.** Phases 5–6.

**Verification.** `make test` (57/57 files); manual OpenGL walks from the hypostyle threshold into the nave, crossing, Capilla Mayor, and Villaviciosa chapel. Captured hero views show the pointed nave arcade, transept ribs, gilded retablo, stained glass, and chapel portal/vault with distinct scale, lighting, and materials. Authored collision checks confirm the central altar stop, the two south side exits, and the Villaviciosa portal route. Sandbox software-OpenGL timings at 1366×712 were ≈16.9 fps (high) and ≈23.7 fps (fallback); target Haswell timing remains pending.

## Phase 8 — Permanent contents and visitor route

**Status:** Complete (2026-10-25)

**Goal.** Make the selected route feel like the present-day combined building rather than an empty shell.

**Deliverables.**

- Permanent or semi-permanent contents visible in the photographs: chapel retables, paintings, sculpture, organs, fixed signs, display elements, lamps, pews/chairs, rails, and grilles.
- Shared/instanced props; collision for physically obstructive objects; no gameplay restrictions from barriers that are only visitor-management devices.
- No tourists, crowds, temporary equipment, or ambient audio.

**Out of scope.** Temporary exhibitions, event furniture, crowd simulation, audio.

**Dependencies.** Phases 6–7.

**Verification.** `make test` (57/57 files); manual OpenGL/Xvfb route review from the north threshold, nave, crossing, organ, Villaviciosa gate, and chapel interior; shared props keep resource growth bounded and `contents.stats` reports the merged totals; collision sweeps confirm the central altar stop, the south side exit, and the open Villaviciosa gate while obstructing only physically obstructive contents.

## Phase 9 — Whole-building interior expansion

**Status:** Complete (2026-10-25)

**Goal.** Extend the walkable scene across the full interior envelope without losing the detailed MVP zone.

**Deliverables.**

- Complete interior floor-plan representation: all mosque expansions, the cathedral insertion, chapels, maqsura/mihrab area, and perimeter chapels.
- Zone-level connectivity, culling, quality tiers, and content prioritisation.
- A documented level of detail and parameter/source metadata for every major zone.
- A switch that reduces the scene to the detailed MVP route for development.

**Out of scope.** Courtyard, exterior façades, bell tower, roofs, and other exterior areas.

**Dependencies.** Phase 8.

**Verification.** `make test` (57/57 files); collision sweeps confirm the central altar stop, the south side exit, the Villaviciosa route, the maqsura/mihrab approach through the screen opening, and a west perimeter chapel stop at its partition. OpenGL/Xvfb captures were inspected from the north threshold, the maqsura screen and mihrab, the domes, a corner overview, the west arcade, and MVP mode. The full scene is 130 drawables over 16 regions, 459,705 vertices, and 253,626 triangles; region culling draws 30–108 of them by view and MVP mode reduces the visible set to the central band. Target Haswell timing remains pending.

## Phase 10 — Quality, performance, packaging, and final verification

**Status:** Complete (2026-10-25)

**Goal.** Make the example repeatable, documented, and usable on the target machine.

**Deliverables.**

- Camera feel, exposure, reflection/shadow/light quality, texture memory, culling, and loading polish.
- At least two progressively enhanced visual configurations selectable through the overlay, with documented trade-offs.
- `examples/Cordoba/README.md` with controls, run commands, asset policy, known limitations, and quality settings.
- A clean run from the repository without the original host photo directory.
- Final `make test`, supplemental smoke runs, and a manual Intel Haswell check at 1280×720.

**Out of scope.** New architectural content; SDL GPU parity.

**Dependencies.** Phase 9.

**Verification.** `make test` (57/57 files); the example has a repeatable run command (`make && ./build/rig examples/Cordoba/cordoba.lua`); a run with `plan/images/` moved away succeeded, confirming no host photo dependency; the three presets (Rich / Balanced / Performance) were captured from the north threshold and the maqsura and render correctly, with the reflection pass as the dominant cost; `examples/Cordoba/README.md` documents controls, presets, asset policy, verification hooks, and limitations. Per the project owner's direction there is no Haswell-specific tuning pass; sandbox software-OpenGL numbers (~20–45 fps at 1024×576) are recorded as observations, not a hardware guarantee.

## Milestone mapping

| PLAN milestone | Phases |
| --- | --- |
| Milestone 0 — Research, measurement, spike | 0–1 |
| Milestone 1 — Rig procedural/OpenGL foundation | 2–5 |
| Milestone 2 — Architectural shell | 5 |
| Milestone 3 — Materials and lighting | 6 |
| Milestone 4 — Christian cathedral and hero architecture | 7 |
| Milestone 5 — Permanent contents and route | 8 |
| Milestone 6 — Whole-building interior | 9 |
| Milestone 7 — Progressive quality and packaging | 10 |
