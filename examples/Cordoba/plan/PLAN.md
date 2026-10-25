# Córdoba Mosque-Cathedral Walk-In — Initial Implementation Plan

## Purpose

This document is the milestone specification for a photorealistic, walkable present-day simulation of the Mezquita-Catedral of Córdoba in Rig. It is an initial plan for review, not an implementation log. The implementation will live primarily under `examples/Cordoba/`, while planning documents live in `examples/Cordoba/plan/`.

## Vision and goals

Create a visually striking Rig example in which a visitor can walk through the present-day interior of the Córdoba Mosque-Cathedral using WASD and look around with the mouse. The scene should represent the coexistence of the Islamic hypostyle mosque and the later Christian cathedral and chapels, rather than choosing one historical period or presenting a purely abstract architectural study.

The project has two purposes:

1. Demonstrate a compelling real-time architectural visualization in Rig.
2. Extend Rig with reusable capabilities needed by this and future visualizations, especially first-person navigation with collision, richer asset/mesh handling, materials and lighting, reflections where practical, and large-scene organization.

Visual quality and “wow factor” are the primary goals. The application may accept a low frame rate on Intel Haswell-class graphics hardware in exchange for richer geometry, lighting, and reflective materials, but it must remain runnable and navigable on that machine.

## Confirmed user experience

- A first-person, walk-in experience rather than a detached orbit viewer.
- WASD movement on the floor plane.
- Mouse look.
- Collision against walls and columns; the visitor should not pass through the architecture.
- No requirement for jumping, crouching, sprinting, doors, or other gameplay mechanics in the MVP.
- A present-day combined scene containing both the Islamic mosque architecture and Christian additions.
- The full building should be represented if a reliable floor plan and practical production path can be established.
- The MVP may model one representative portion in detail while the remaining building is developed in later phases.
- External reference material is permitted. Public floor plans, measurements, photographs, and pre-existing textures may be gathered and placed in the example’s asset directory. Runtime geometry is generated from parameters; pre-existing 3D meshes are not part of the production pipeline.

## Reference observations from the supplied photographs

The supplied reference photographs, copied into `examples/Cordoba/plan/images/`, establish the desired visual vocabulary and the main reconstruction risks:

- Repeated red-and-cream striped horseshoe and round arches are the dominant long-range pattern.
- The mosque areas contain dense rows of slender columns, varied reused capitals, layered arches, warm stone, and relatively low horizontal visual rhythm beneath much taller upper arches.
- The present-day interior includes a very different Christian cathedral inserted into the hypostyle field: large pale carved portals, ribbed and star-like vaults, tall windows, stained glass, chapels, altarpieces, paintings, sculpture, gold-colored metalwork, and dark wood.
- Floors vary between terracotta-colored tile, patterned stone or marble, black-and-white checkerboard areas, and darker polished surfaces. These are important to reflections and to the sense of place.
- Railings, grilles, pews, chairs, signs, donation boxes, display panels, lamps, and tourist barriers are visible and materially significant even when they are not architectural structure.
- Lighting is predominantly interior daylight mixed with warm artificial or devotional light. Bright windows and darker side aisles create a high dynamic range problem.
- The visual target is photorealistic, but a complete one-to-one reproduction of every carved ornament and artwork is not required for the first milestone. Repetition, instancing, trim materials, normal/detail maps, and carefully chosen hero assets should carry much of the effect.

The photographs are visual references rather than sufficient geometric survey data. Architectural dimensions, floor-plan topology, and historical/current room boundaries must therefore be established from public reference sources and recorded with uncertainty where sources disagree.

## Scope boundaries and working assumptions

- The initial and long-term scene covers the walkable interior only. The courtyard, exterior façades, bell tower, roofs, and other exterior areas are out of scope.
- The scene is the current combined interior, not a historical toggle or a reconstruction with later additions removed.
- The plan treats the whole interior as the long-term scene boundary, while explicitly staging the work so that a smaller high-quality area can become the first demonstrable release.
- OpenGL is the sole reference backend for this project because it is the only backend properly supported on the target Intel Haswell machine. SDL GPU parity is deferred.
- Geometry is generated from parameters by Rig’s procedural generation facilities. Blender and other offline modeling tools are not part of the production pipeline.
- Pre-existing textures may be used to improve realism. This is a private project, so the plan does not impose licensing enforcement or a committed asset-size budget; asset provenance should still be recorded when practical.
- Materials and lighting should degrade gracefully. If hardware or shader support prevents true screen-space or planar reflections, the fallback should use authored roughness, environment/reflection probes, or carefully chosen baked-looking approximations rather than blocking the project.
- The project should prefer reusable Rig modules over one-off hacks inside the Córdoba example. A new feature needed by Córdoba but generally useful belongs in `src/modules/FEATURE.lua` and its module documentation/tests, not only in `examples/Cordoba/`. The unified `examples/Cordoba/cordoba.lua` showcase should demonstrate the developed features through an on-screen overlay; an isolated `examples/FEATURE.lua` demonstration/test is added when a feature needs independent verification.
- Runtime assets and generated data should live under `examples/Cordoba/assets/`, with parameter/source metadata sufficient to regenerate them from the procedural pipeline.

## Proposed technical direction

### Example organization

Create an example package with a small executable entry point and separable data/content layers, approximately:

- `examples/Cordoba/cordoba.lua` as the unified Córdoba showcase entry point.
- `examples/Cordoba/` for Córdoba-specific Lua modules and parameterized scene data.
- New reusable Rig feature modules developed for this project belong in `src/modules/FEATURE.lua`, even when Córdoba is their first consumer; they must not be hidden inside `examples/Cordoba/`.
- `examples/Cordoba/assets/` for pre-existing textures, generated runtime data, shaders, reference data, and regeneration metadata.
- `examples/Cordoba/plan/images/` for copies of the supplied reference photographs cited by the planning documents. The current set has been copied there.
- The repository-level `examples/` directory for demonstrations/tests of individually developed Rig features, using the feature-specific naming convention `examples/FEATURE.lua` (for example, `examples/procedural_mesh.lua`, `examples/material_lighting.lua`, and `examples/collision_walk.lua`). These demos must be directly under `examples/`, not under `examples/Cordoba/`.
- `examples/Cordoba/plan/` for this plan and the phase/decision/diary documents.

The exact launcher shape should follow the repository’s existing `rig.run`/`sketch` conventions rather than introducing a custom runtime entry point.

### Scene representation

Use a data-driven scene description built from reusable architectural primitives and imported hero assets:

- A measured coordinate system with one documented unit convention.
- A floor-plan layer describing bounds, rooms/chapels, aisles, entrances, blocked areas, and navigation surfaces.
- Repeated procedural modules for columns, capitals, lower arches, upper arches, striped voussoirs, walls, floor bays, windows, and roof/vault sections.
- Instancing or shared mesh/material values for repeated columns and arch bays to control memory and draw overhead.
- Imported meshes for distinctive Christian cathedral volumes, major chapels, altarpieces, grilles, and other hero objects where procedural geometry would be unproductive.
- A separate collision representation that is simpler than the render geometry: walls, columns, railings, barriers, and forbidden areas represented by capsules, circles, boxes, or polygons.
- Logical zones or cells so that future streaming, visibility culling, or quality tiers can be added without rewriting the scene description.

The first detailed route is a central corridor selected for maximum visual payoff and navigational value. It begins in the red/white hypostyle hall, passes through dense columns and grilles, and opens into the Christian cathedral/chapel volume. It must show the repeated arches, contrasting flooring, and at least one hero chapel or altarpiece.

### Navigation and collision

Extend the existing camera/input path rather than creating an unrelated controller:

- Add or adapt a ground-constrained first-person controller with WASD movement and mouse look.
- Use mouse movement for look whenever the window has focus; no button modifier or explicit pointer-capture mode is required for the MVP.
- Keep a fixed eye height and configurable movement speed for the MVP.
- Implement collision resolution for a player capsule or circle against static wall/column/rail geometry.
- Prevent tunneling at normal movement speeds and avoid jitter at corners.
- Keep collision data independent of render meshes so highly detailed art does not make movement prohibitively expensive.
- Provide a known starting location in the detailed area and a safe reset path for testing, even if no visible teleport UI is required.

### Rendering, materials, and reflections

The current rendering stack is deliberately small and currently exposes unlit/basic textured materials. The project should grow it incrementally through progressively enhanced OpenGL examples:

- Add a material representation that can express at least base color/albedo, normal or detail information where supported, roughness/specular response, opacity/cutout as needed, and emissive contribution.
- Add a lit shader path with a small, explicit light model suitable for the hardware target: directional/daylight plus a limited number of local warm lights, or a baked/clustered compromise if required by the backend.
- Establish a physically plausible color and exposure workflow before fine art tuning.
- Add ambient/environment contribution so deep aisles do not become black.
- Prioritize reflective floors, polished stone, metal railings, gold details, and dark wood. Evaluate progressively richer reflection techniques and keep the best practical OpenGL solution rather than committing in advance to screen-space, planar, or global-illumination rendering.
- Evaluate shadows, HDR, tone mapping, and baked/static lighting as scalable alternatives. Each meaningful renderer capability should have a focused example that demonstrates it independently.
- Keep an unlit/textured fallback and progressively enhanced quality variants so users can select the example or quality level that fits their configuration.
- Add depth testing, back-face/culling, alpha policy, and shadow policy explicitly to the material/backend contract rather than relying on accidental defaults.

### Asset pipeline

Use existing `asset.image` facilities for permitted pre-existing textures, while making all scene geometry and generated material data procedural:

- Build a first-class parameterized mesh-generation pipeline in Rig for architectural primitives, repeated motifs, UVs, normals/tangents, shared/indexed geometry, and composition into larger generated meshes.
- Support the required image formats and reasonable texture dimensions for the target machine.
- Add mipmap generation, texture resizing/compression or streaming if large photographic textures otherwise exhaust memory.
- Extend mesh/material support as needed for normals, tangents, material groups, indexed geometry, multiple primitives, and procedural texture generation.
- Prefer generated/tiled material data for large walls and arches, with pre-existing photographic textures reserved for surfaces where they materially improve realism.
- Record parameter sets, generator versions, texture sources, dimensions, scale, and conversion steps when practical, without treating licensing metadata as a project gate.

### Lighting and scene performance

- Produce progressively enhanced OpenGL examples/variants, beginning with the simplest stable path and adding lighting, reflections, shadows, HDR/tone mapping, and baked/static contributions as experiments prove useful.
- Measure memory, draw count, CPU time, and GPU time on the available Intel Haswell-class machine after each major rendering change.
- Use repeated geometry instancing/shared resources, frustum culling, and coarse zone visibility before reducing visual detail.
- Consider baked light information or static lightmaps for the large, mostly static architecture if dynamic lighting is too expensive.
- Keep quality settings or separately runnable variants that reduce shadow/reflection resolution, local lights, texture size, or ornament density without changing the scene data.
- Avoid committing to full real-time global illumination until a simpler lighting baseline has been evaluated.

## Milestones and acceptance criteria

### Milestone 0 — Research, measurement, and technical spike

Collect and compare public floor plans, sections, photographs, and available 3D references. Select a coordinate system and document the interior-only boundary. Use the supplied photographs to establish material, lighting, and composition references. The implementation agent should select the most useful public floor-plan source and record approximations where sources disagree. The first detailed route is the central corridor from the hypostyle hall through grilles into the Christian cathedral/chapel volume.

Build a small rendering spike that proves texture loading, parameter passing into a procedural generator, camera control, and a reflective-surface experiment on the actual target hardware.

Acceptance criteria:

- A source/provenance inventory exists.
- A floor-plan source and scale assumptions are documented.
- The interior-only boundary and central detailed route are named and bounded.
- A minimal OpenGL Rig scene can load a pre-existing texture, generate a parameterized mesh, and show the proposed rendering experiment.
- Engine gaps are separated into required, useful, and deferrable work.

### Milestone 1 — Rig procedural and OpenGL foundation (first engine implementation phase)

Extend Rig before building the Córdoba shell. This milestone is independently testable and every developed capability must have a focused accompanying example.

Include:

- Parameterized procedural mesh primitives and composition helpers for walls, floors, columns, capitals, arches, vaults, windows, repeated trim, and other architectural motifs.
- Provider-neutral mesh attributes for normals and tangents, UVs, shared/indexed geometry, and any required material groups or primitive ranges.
- OpenGL vertex input, buffer, shader, and draw support for the expanded mesh contract.
- A backend-neutral material contract covering albedo, normal/detail, roughness/specular, emissive, opacity/cutout, depth, culling, and lighting inputs as the useful subset is established.
- A stable first-person camera mode with WASD movement, mouse look whenever the focused window receives mouse movement, fixed eye height, and configurable speed.
- Reusable collision primitives and player-vs-static-geometry resolution suitable for walls and columns.
- Procedural texture/material-data generation facilities where they improve the architectural pipeline.
- A focused demonstration directly under the repository-level `examples/` directory for each meaningful feature when isolated verification is useful: a generated primitive gallery, indexed/normal-mapped mesh, material/light test, reflection test, and collision/navigation test as appropriate.
- `examples/Cordoba/cordoba.lua` as a unified Córdoba showcase with an on-screen overlay that can toggle or select the progressively enhanced visual features and quality settings, so the final demo itself demonstrates the feature set in context. The overlay should expose the available renderer/material modes, reflection and shadow options, HDR/tone-mapping choices, geometry/detail density, and collision/debug visualization as those capabilities become available.

Acceptance criteria:

- The new mesh and material contracts are covered by deterministic tests and focused runnable examples.
- The OpenGL backend can render at least one generated, lit, textured mesh with depth testing and the intended attribute data.
- A camera/collision example demonstrates WASD movement, focused-window mouse look, fixed eye height, and blocking against simple walls/columns.
- The foundation does not depend on Blender or other offline modeling tools.
- `make test` remains green after the engine changes.

### Milestone 2 — Architectural shell

Build the first walkable architectural shell from measured/proportional data. This is the first Córdoba scene phase and should be independently testable without decorative content.

Include:

- Floor-plan bounds and navigation surface for the central detailed route.
- Floors with the major material regions.
- Interior/zone boundary walls and openings needed to guide the walk; no exterior architecture.
- Repeated columns and the signature two-level red/cream arches.
- Representative ceiling, vault, window, and daylight openings.
- Basic collision against walls and columns.
- First-person WASD/mouse navigation.
- Neutral but readable lighting and a stable camera start point.

Acceptance criteria:

- The user can walk through the zone without falling through or passing through walls/columns.
- The major aisle spacing, column rhythm, arch proportions, floor boundaries, and transition into the Christian volume are recognizable against the floor plan and reference photographs.
- The shell is generated from parameters at runtime or through a reproducible Rig generation step and does not require editor-only setup.
- Collision geometry can be inspected or debug-drawn during development.

### Milestone 3 — Architectural materials and lighting

Replace placeholder colors with physically plausible stone, plaster, brick, terracotta, marble, wood, and metal materials. Add daylight, warm interior lights, ambient contribution, depth handling, and the first reflective surfaces.

Acceptance criteria:

- The scene reads as the warm, pale-stone and red-striped interior shown in the photographs under a controlled exposure.
- Reflective floors and metal elements visibly respond to the environment or scene lights.
- The visual result remains navigable on Intel Haswell, with documented quality/performance measurements.
- A fallback path exists when advanced material features are unavailable.

### Milestone 4 — Christian cathedral insertion and hero architecture

Model or import the major Christian cathedral volume and its visually dominant chapels, portals, ribbed/vaulted ceilings, windows, stained glass, altarpieces, and transition zones. Preserve the present-day coexistence with the mosque structure.

Acceptance criteria:

- A visitor can walk from the mosque’s repeated hypostyle areas into at least one clearly recognizable Christian cathedral/chapel area.
- At least one hero view has convincing scale, ornament silhouette, lighting contrast, and material differentiation.
- Imported or procedural assets have collision coverage where the visitor can approach them.

### Milestone 5 — Present-day permanent contents and visitor route

Add the permanent or semi-permanent contents visible in the photographs: chapels, railings/grilles, pews and chairs, lamps, altarpieces, paintings, sculptures, organs, fixed signs, and architectural display elements. Do not add tourists, crowds, ambient audio, temporary speakers, event equipment, or temporary movable barriers. The simulation intentionally imposes no present-day access restrictions: modeled chapels and interior areas remain explorable even when the real visitor route would be barred.

Acceptance criteria:

- The selected route feels like the present-day combined building rather than an empty archaeological shell.
- Permanent objects that are physically obstructive participate in collision or navigation boundaries; decorative barriers do not unnecessarily prevent exploration.
- Repeated props are shared/instanced and do not cause uncontrolled resource growth.
- No crowd or audio system is required for the milestone.

### Milestone 6 — Whole-building interior expansion

Extend the floor-plan representation across the full interior, prioritizing connectivity and recognizable district/chapel identity before maximizing ornament density. Add zone-level culling, quality tiers, and content prioritization as needed. The scope ends at the interior envelope; the courtyard, exterior façades, bell tower, roofs, and other exterior areas remain excluded.

Acceptance criteria:

- The full planned interior is traversable without artificial access restrictions, including modeled chapels and areas that are normally closed to visitors.
- Every major zone has a documented level of detail and procedural parameter/source metadata.
- The scene remains testable and can be reduced to the detailed MVP zone for development.

### Milestone 7 — Progressive quality, performance, and example packaging

Polish camera feel, exposure, reflections, shadow/light quality, texture memory, culling, loading, and documentation. Produce progressively enhanced OpenGL variants or quality settings so users can choose the best fit for their machine. Add a short README with controls, build/run commands, the private-project asset policy, known limitations, and quality settings.

Acceptance criteria:

- `make test` passes for the repository.
- The example has a repeatable run command and clear controls.
- A clean run can be performed from the repository without relying on the original host photo directory.
- On the target Intel Haswell machine, the visual MVP operates stably at 1280×720 at approximately 10–15 FPS or better, without crashes, severe stutter, or unusably sluggish navigation. This is a practical floor, not a smoothness guarantee.
- At least two progressively enhanced visual configurations can be compared through the on-screen overlay, with their tradeoffs documented.
- Performance and known visual compromises are documented.

## Testing and verification strategy

- Add unit tests for geometry generators, floor-plan conversion, collision primitives, collision resolution, and camera movement where the existing test infrastructure permits.
- Add deterministic tests for player movement against walls, columns, corners, and narrow passages.
- Add asset/mesh/material smoke tests that work headlessly where possible.
- Add a small offscreen render or snapshot test for the architectural shell once the render path supports it.
- Run `make test` for final verification, following the repository instructions.
- Because changes to C code, build files, embedded modules, or `src/modules/` assets require a rebuild, rebuild before any supplemental `./build/rig ...` smoke test after such changes. Do not treat a smoke test as a substitute for `make test`.
- Record manual visual checks on the Intel Haswell-class machine, including startup, navigation, collision, reflections, and fallback quality mode.

## Risks and mitigations

- **No sufficiently complete floor plan:** compare multiple public sources, use a consistent approximate plan, and mark uncertain dimensions instead of blocking the MVP.
- **Asset licensing or download instability:** keep a manifest, prefer redistributable assets, and ship generated/procedural substitutes for non-redistributable references.
- **Renderer is currently too unlit/basic:** implement the smallest useful lit material path first and preserve a fallback rather than attempting a complete modern renderer in one step.
- **Large scene exceeds GPU memory:** use shared meshes, texture sizing/mipmaps, zone loading/culling, and a detailed-zone-first strategy.
- **High ornament cost:** use hero assets near the route, repeated instancing, trim/detail textures, and lower-density geometry outside focal areas.
- **Collision becomes inaccurate in irregular architecture:** author simple collision proxies per zone and provide a debug visualization; do not derive all collision from high-resolution render meshes initially.
- **Photorealism expectation exceeds available references:** prioritize silhouette, scale, material response, exposure, and lighting composition before attempting every individual carving or artwork.
- **Backend divergence:** define the feature contract at the backend-neutral material/mesh level and explicitly label features that initially require OpenGL.

## Resolved constraints and remaining implementation choices

The following constraints were resolved during plan review:

- Scope is the interior only; exterior architecture is excluded.
- The first detailed route is the central hypostyle-to-Christian-cathedral corridor.
- All modeled interior areas are explorable; present-day barriers are not gameplay restrictions.
- Only permanent or semi-permanent contents are modeled; crowds, tourists, temporary equipment, and ambient audio are excluded.
- Geometry is parameter-generated by Rig; Blender and other offline modeling tools are not used.
- Pre-existing textures may be used; this is a private project with no licensing enforcement or asset-size budget imposed by the plan.
- OpenGL is the reference backend.
- Mouse look responds whenever the focused window receives mouse movement, without requiring a held button.
- The unified showcase is `examples/Cordoba/cordoba.lua`; reusable feature implementations use `src/modules/FEATURE.lua`; isolated feature demonstrations/tests use `examples/FEATURE.lua` directly under `examples/` when needed.
- A practical target is stable 1280×720 operation at approximately 10–15 FPS or better on Intel Haswell, with progressively enhanced alternatives.
- Reflections, shadows, HDR, tone mapping, and baked/static lighting are evaluated progressively rather than fixed to one algorithm in advance.
- The supplied reference photographs cited by the plan are copied into `examples/Cordoba/plan/images/`.

The remaining implementation choices are deliberately delegated to the implementation phases:

1. Select and document the most useful public floor-plan and measurement sources; record approximation where sources conflict.
2. Experiment with reflection, shadow, HDR, tone-mapping, and static-lighting techniques and retain the best OpenGL tradeoff.
3. Determine the exact procedural primitive and material-generator APIs from the needs of the first renderer and shell examples.
4. Determine which individual `examples/FEATURE.lua` files are worthwhile after the unified overlay showcase and automated tests are in place.

The higher-weight review has been incorporated. The resolved constraints, sequencing, and acceptance criteria are complete, and this plan is ready for implementation.
