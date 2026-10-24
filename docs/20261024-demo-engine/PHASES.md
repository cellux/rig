# Implementation Phases

## Purpose

This document turns `PLAN.md` into ordered, independently testable phases. Progress
belongs in `DIARY.md`; enduring choices belong in `DECISIONS.md`.

## Conventions

- Phases are ordered and cumulative; a phase must not depend on later work.
- Each phase lists goal, deliverables, out of scope, dependencies, and verification.
- A phase is complete only when its verification passes via `make test` (rebuilding
  first when C code, build inputs, or embedded module sources change) and no earlier
  phase regresses.
- New module sources under `src/modules/` require a rebuild before any
  `./build/rig ...` smoke test, per `AGENTS.md`.
- No backward compatibility layer is required; old APIs are removed once in-repo
  callers are migrated.

## Phase 0 — Inventory and product definition (documentation only)

**Status:** Complete (2026-10-24)

**Goal.** Freeze the product shape and the surface affected by the code-first facade
and the motion model.

**Deliverables.** `INVENTORY.md`, `PLAN.md`, `DECISIONS.md`, `PHASES.md`, `DIARY.md`.

**Verification.** Review: every current public knob touched by the effort is listed in
`INVENTORY.md` with a retained/reshaped/dropped classification.

## Phase 1 — Motion and unified frame context

**Status:** Complete (2026-10-24)

**Goal.** Make transform animation a node-level concern and give the whole frame one
clock.

**Deliverables.**

- `motion` module + `motion.md`: `Motion` base, `Spin`/`motion.spin`, closed-form
  `contribute(out, node, frame)`, `anchor`/`local_time`.
- `scene.Node` gains `motions`, `add_motion`, `remove_motion`, `clear_motions`, and
  `build_local(out, frame)` that pre-multiplies motions in list order.
- `Node:step(surface, frame)`, `draw_node(surface, world, frame)`,
  `render_tree(surface, parent_world, frame)`, `render_children(surface, frame)` thread
  the frame context.
- `scene.RenderScene` owns `clock`/`time`/`dt`, `advance_time()`, `frame()`,
  `on_update`/`on_draw`; `render` sequences time, update, backend frame, view/projection,
  draw, children, end.
- `scene.container_component` requires `sched.clock` optionally and forwards
  `clock`/`on_update`/`on_draw`; `scene.plugin` declares `sched.clock`.
- Tests: `tests/motion_test.lua`, extended `tests/scene_test.lua`.

**Out of scope.** Any change to `render.Entity` or the facade; drawing primitives.

**Dependencies.** None.

**Verification.** `make test`; verified with 48/48 files passing on 2026-10-24.

## Phase 2 — Entity as motion consumer, and the `rig.run` facade

**Status:** Complete (2026-10-24)

**Goal.** Remove hard-coded spin from `render.Entity` and expose a one-file entrypoint.

**Deliverables.**

- `render.Entity` takes `options.motion` (single or list) via `set_motions`, drops
  `spin`/`update`/`step`/`build_local`; `entity_component` forwards `motion`.
- `sketch` module + `sketch.md`: `sketch.App` (`add_entity`, `on_update`, `on_draw`)
  and `sketch.run(options?, build?)` assembling the default bundle/scene/camera and
  wiring frame callbacks.
- `rig.run(options?, build?)` in `rig.lua`, requiring `sketch` lazily.
- `examples/spinning_cube_common.lua` rewritten to use `rig.run` + `motion`.
- Tests: `tests/sketch_test.lua`, updated `tests/render_test.lua`.

**Out of scope.** Drawing primitives beyond mesh entities; live component mutation
after startup.

**Dependencies.** Phase 1.

**Verification.** `make test` (48 files); `./build/rig examples/spinning_cube_gl.lua`
runs (exits on timeout); GPU example assembles and fails only on the sandbox's missing
Vulkan ICD. Verified 2026-10-24.

## Phase 3 — Immediate mesh drawing

**Status:** Complete (2026-10-24)

**Goal.** Let `on_draw` submit geometry directly, not only through retained entities.

**Deliverables.**

- `scene.RenderScene:draw_mesh(mesh, transform?)`, `push_transform` / `pop_transform` /
  `current_transform`, and `mesh_drawable(mesh)` (lazy per-mesh cache).
- `scene.container_component` optionally resolves the composition's `render.mesh`
  factory into `mesh_factory`; `scene.plugin` declares `render.mesh`.
- Tests: `tests/scene_test.lua` drawing case.

**Out of scope.** Primitive helpers, material/shader binding, render targets (Phase 3b
and Phase 6).

**Dependencies.** Phase 1–2.

**Verification.** `make test`; an `on_draw` probe drawing a mesh through
`frame.surface:draw_mesh` runs. Verified 2026-10-24.

## Phase 3b — Drawing primitives and materials

**Status:** Complete (2026-10-24)

**Goal.** Round out immediate drawing with built-in geometry and material binding.

**Deliverables.**

- `mesh.make_quad`, `mesh.make_triangle`, `mesh.make_line`, `mesh.make_lines`, and
  `mesh.make_grid`; every mesh carries a `topology` (`"triangles"` / `"lines"`).
- GL/GPU `render.mesh` factories honor `topology` (triangles vs lines).
- `render.material { vertex, fragment, name?, language? }` and material-keyed
  drawable caching; `draw_mesh(mesh, transform?, material?)`.
- GL primitive constants (`LINES`, `LINE_STRIP`, `POINTS`) added in `gl.c`.
- Tests: extended `mesh_test.lua`, `render_test.lua`, `scene_test.lua`.

**Out of scope.** Render graph, automatic batching, material parameters/uniforms
beyond the `u_mvp` contract.

**Dependencies.** Phase 3.

**Verification.** `make test`; an `on_draw` probe drawing a grid, quad, line, and a
custom-material quad through `frame.surface:draw_mesh` runs on GL. Verified 2026-10-24.

## Phase 4 — Optional camera controls

**Status:** Complete (2026-10-24)

**Goal.** Make walk-through/architectural viewing ergonomic **without** imposing it on
every sketch.

**Deliverables.**

- `camera` module + `camera.md`: backend-agnostic `camera.Orbit` and `camera.Fly`
  controllers (`on_key`, `on_mouse`, `update(dt)`, `apply(scene)`).
- Facade input callbacks (`app:on_key`/`on_mouse`/`on_resize`) and opt-in camera
  controls (`app:add_camera_controls`, `rig.run { camera_controls = ... }`); the
  per-run execution subclass forwards `sdl3.key`/`sdl3.mouse`/`sdl3.resize`.
- An example (`examples/orbit_grid.lua`) combining primitives with orbit controls.
- Tests: `tests/camera_test.lua`, extended `tests/sketch_test.lua`.

**Out of scope.** Collision-aware movement; mouse-wheel zoom (the `sdl3` binding does
not expose wheel events yet).

**Dependencies.** Phase 3 (drawing), Phase 1 (frame `dt`).

**Verification.** `make test` (49 files); `examples/orbit_grid.lua` runs. Verified
2026-10-24.

## Phase 5 — Assets (files, shaders, image decoding)

**Status:** Complete (2026-10-24)

**Goal.** Load external assets by path, resolved relative to the script, with caching.

**Deliverables.**

- `rig` path/file helpers: `source_of`, `dirname`, `join_path`, `file_exists`,
  `read_file`.
- `asset` module + `asset.md`: `path`/`text`/`bytes`/`image`/`material`, resolved
  against the calling script and cached by canonical path (`rig.realpath`).
- `png` module + `png.md`: libpng simplified (`png_image`) API via FFI, dynamically
  loaded — no C helper and no `setjmp`.
- `jpeg` module + `jpeg.md`: a minimal `jpeg.c` (the only `setjmp`-guarded libjpeg
  call) plus `jpeg.lua` FFI. Optional build via `find_package(JPEG)`; a stub keeps the
  build green without libjpeg headers.
- Tests: `png_test.lua`, `jpeg_test.lua`, `asset_test.lua`; fixtures under
  `tests/fixtures/assets/`; `examples/shader_asset.lua`.

**Out of scope (Phase 5b).** Mesh files (OBJ/glTF); texture upload and material
sampling; async loading.

**Dependencies.** Phase 3 (materials).

**Verification.** `make test` (52 files); `examples/shader_asset.lua` runs. PNG is
verified in every build; JPEG verifies once `libjpeg62-turbo-dev` is present (the
stub path is exercised otherwise). Verified 2026-10-24.

## Phase 5b — Textures and mesh files

**Status:** Complete (2026-10-24)

**Goal.** Turn decoded images and mesh files into drawable resources.

**Deliverables.**

- `render.texture(options?)` values and the `render.texture` capability with GL and
  GPU factories (`sdl3x.gl_texture_component`, `sdl3x.gpu_texture_component`),
  sharing one backend texture per value.
- Material sampling: `render.material { texture = ... }` (raw images are wrapped),
  texture binding at slot 0, a `u_texture` uniform, and built-in textured GLSL/SPIR-V
  shaders for meshes with UVs. `render.entity_component` forwards `options.material`.
- A `position_color_uv_f32` mesh layout; `mesh.make_quad`/`mesh.make_cube` now carry
  UVs, and `mesh.parse_obj` parses Wavefront OBJ (positions + texture coordinates,
  fan triangulation, negative indices).
- `asset.mesh(path)` loads and caches an OBJ relative to the script;
  `asset.material` forwards `spec.texture`.
- `sdl3` gains the SDL_GPU sampler/texture bindings (`SDL_CreateGPUSampler`,
  `SDL_UploadToGPUTexture`, `SDL_BindGPUFragmentSamplers`, ...).
- Tests: extended `mesh_test.lua`, `render_test.lua`, `asset_test.lua`; new
  `examples/textured_quad_common.lua` + `_gl`/`_gpu` and `examples/assets/checker.png`.

**Out of scope.** Async loading through `uv` (deferred to a later phase); offline
asset cooking.

**Dependencies.** Phase 3b (materials), Phase 5 (decoders).

**Verification.** `make test` (52 files) plus `examples/textured_quad_gl.lua` and
`examples/textured_quad_gpu.lua` (both to timeout, exit 124). Verified 2026-10-24.

## Phase 6 — Render targets and post-processing

**Status:** Complete (2026-10-24)

**Goal.** Make shaders and render-to-texture composable for effects.

**Deliverables.**

- `render.target(options?)` values and the `render.target` capability with GL and
  GPU factories (`sdl3x.gl_target_component`, `sdl3x.gpu_target_component`), sharing
  one surface per value. The handle's `.texture` is a material-samplable texture.
- `scene.RenderScene:render_to(target, draw)` renders an offscreen pass (sizing the
  view/projection), with backend `enter_target`/`leave_target` hooks; the GL hook
  flips clip-space Y so its bottom-up textures sample top-down like images.
- `scene.RenderScene:draw_fullscreen(material)` and `mesh.make_fullscreen_quad()` for
  the screen-space pass that consumes a target.
- Materials may name a `render.target` (or a backend handle) as their `texture`; mesh
  factories resolve it through the target factory so the pass and the sampling share
  the texture.
- `glx.Framebuffer` and the GL framebuffer/renderbuffer bindings and constants.
- Tests: extended `scene_test.lua`, `render_test.lua`, `mesh_test.lua`; new
  `examples/post_process_common.lua` + `_gl`/`_gpu` and post shaders.

**Out of scope.** A general render graph; multi-target/MRT; mip generation.

**Dependencies.** Phase 3.

**Verification.** `make test` (52 files) plus `examples/post_process_gl.lua` and
`examples/post_process_gpu.lua` (both to timeout, exit 124). Verified 2026-10-24.

## Phase 7 — Input and parameter overlay

**Status:** Complete (2026-10-24)

**Goal.** Ergonomic input and live value tweaking.

**Deliverables.**

- `input` module + `input.md`: a backend-agnostic `input.Input` state built from the
  `sdl3.key`/`sdl3.mouse` payloads, with held/pressed/released key and mouse
  queries, axes, and modifiers. The sketch owns one (`app.input`) and every frame
  carries it as `frame.input`.
- `params` module + `params.md`: a live-parameter store (clamped numbers, booleans,
  and wrapping enums) with declaration order, normalized fractions, and formatting.
- `overlay` module + `overlay.md`: a lightweight live editor drawing screen-space
  bars through the drawing surface, driven by keyboard (select/adjust/toggle) and
  mouse (click/drag). Optional `draw_text` callback; not a retained UI toolkit.
- `scene.RenderScene:draw_screen(mesh, x, y, w, h, material?)` and an `on_overlay`
  frame hook that runs after the children, so overlays land on top.
- `sketch.App:add_overlay` / `on_overlay` and `frame.input` wiring; input edges are
  reset after the overlay phase.
- Tests: `input_test.lua`, `params_test.lua`, `overlay_test.lua`, extended
  `scene_test.lua`; `examples/params_overlay_common.lua` + `_gl`/`_gpu`.

**Out of scope.** A retained UI toolkit; text labels (the optional `draw_text`
callback is the seam; the example is bars only).

**Dependencies.** Phase 3–4.

**Verification.** `make test` (55 files) plus `examples/params_overlay_gl.lua` and
`examples/params_overlay_gpu.lua` (both to timeout, exit 124). Verified 2026-10-24.

## Phase 8 — Recording and headless rendering

**Status:** Deferred (deferred by the author 2026-10-24)

**Goal.** Produce deterministic frames/stills/panoramas without a visible window.

**Deliverables.** Frame capture to disk, fixed-time stepping, and a headless run mode
(offscreen video driver) for high-resolution stills and image sequences.

**Out of scope.** Video muxing.

**Dependencies.** Phase 1 (single clock).

**Verification.** `make test` plus a headless smoke run writing frames.

## Phase 9 — Hot reload and REPL

**Status:** Deferred (deferred by the author 2026-10-24)

**Goal.** Fast iteration.

**Deliverables.** Watch the running script via `uv` and re-run on change, preserving
what is safe to preserve; a REPL-style evaluation path over the live runtime.

**Out of scope.** State migration across arbitrary code changes.

**Dependencies.** Phase 1–3.

**Verification.** `make test` plus a scripted reload check.

## Phase 10 — Audio

**Status:** Complete (2026-10-24)

**Goal.** Complete the media coverage.

**Deliverables.**

- `audio` module + `audio.md`: `audio.load` (path-relative, refcounted `Clip`),
  `audio.play` (`Voice` with play/loop/volume/pause/resume/stop), `audio.update`,
  `audio.stop_all`, and an `audio.Scope` for deterministic lifetimes.
- Lazy `SDL_InitSubSystem(SDL_INIT_AUDIO)`; `audio.load`/`audio.play` return
  `nil, error` when no device is available so demos degrade gracefully.
- `sdl3` bindings: `SDL_InitSubSystem`, `SDL_LoadWAV`, `SDL_OpenAudioDeviceStream`,
  `SDL_DestroyAudioStream`, `SDL_PutAudioStreamData`, `SDL_ClearAudioStream`,
  `SDL_GetAudioStreamQueued`, `SDL_Pause/ResumeAudioStreamDevice`,
  `SDL_SetAudioStreamGain`, the `SDL_AudioSpec`/`SDL_AudioStream` types, and the
  default playback/recording device constants.
- The sketch facade calls `audio.update()` each frame; `examples/audio_common.lua` +
  `_gl`/`_gpu` loop a WAV and tweak volume/mute through the params overlay.
- Tests: `tests/audio_test.lua`; `examples/assets/beep.wav`.

**Out of scope.** A mixer/DSP graph; decoding beyond WAV; recording.

**Dependencies.** None beyond the existing SDL3 layer.

**Verification.** `make test` (56 files) plus `examples/audio_gl.lua` and
`examples/audio_gpu.lua` (both to timeout, exit 124) with `SDL_AUDIODRIVER=dummy`,
and a clean manual exit probe. Verified 2026-10-24.