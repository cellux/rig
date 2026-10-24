# Inventory

## Purpose

Freeze the surface affected by the demo-engine evolution and classify each entry as
**retained**, **reshaped**, **added**, or **dropped**. Search scope: `src/`, `tests/`,
`examples/`, `scripts/` (not `src/` alone), per `AGENTS.md`.

## Runtime entrypoints

| Surface | Classification | Rationale |
|---|---|---|
| `rig.run` (legacy immediate driver) | **Dropped** (2026-10-23 redesign) | Replaced by builder/compiler/start. |
| `rig.run(options?, build?)` (new) | **Added** | Code-first facade over the builder; lazily requires `sketch`. |
| `rig.runtime()` | **Retained** | The builder remains the full-control path. |
| `rig.require` caller-relative loading | **Retained** | Basis for script-relative asset resolution. |

## Scene

| Surface | Classification | Rationale |
|---|---|---|
| `scene.Node` transform tree (`parent`, `children`, `local_*`, `world_matrix`) | **Retained** | Light core, no DI required. |
| `Node:add_child` / `remove_child` / `set_local_matrix` | **Retained** | Unchanged. |
| `Node:build_local(out)` | **Reshaped** | Now `build_local(out, frame)`; composes motions. |
| `Node:step(surface)` | **Reshaped** | Now `step(surface, frame)`; the behavior/state hook. |
| `Node:draw_node` / `render_tree` / `render_children` | **Reshaped** | Variadic args replaced by an explicit frame context. |
| `Node.motions`, `add_motion`, `remove_motion`, `clear_motions` | **Added** | Node-level transform contributors (D4). |
| `scene.RenderScene` camera/view-projection | **Retained** | Unchanged. |
| `RenderScene.clock`, `time`, `dt`, `advance_time`, `frame()` | **Added** | One clock per scene (D3). |
| `RenderScene.on_update` / `on_draw` | **Added** | Frame hooks for sketches and larger apps. |
| `RenderScene:render(...)` sequencing | **Reshaped** | Advances time and invokes hooks; backend args forwarded. |
| `scene.plugin` capabilities | **Reshaped** | Also declares `sched.clock` so the optional requirement is known. |
| `scene.container_component` | **Reshaped** | Optional `sched.clock` and `render.mesh` requirements; forwards `clock`/`mesh_factory`/hooks. |
| `RenderScene.mesh_factory` (from `render.mesh`) | **Added** | Resolved optionally by the container; enables immediate drawing. |
| `RenderScene:draw_mesh` / `push_transform` / `pop_transform` / `current_transform` / `mesh_drawable` | **Added** | Immediate drawing over the resolved mesh factory (D11). |
| `RenderScene:render_to` / `enter_target` / `leave_target` | **Added** | Offscreen pass into a `render.target` (D16). |
| `RenderScene:draw_fullscreen` | **Added** | Identity-transform clip-space quad pass consuming a target. |
| `RenderScene:draw_screen` | **Added** | Pixel-rect screen-space drawing for overlays and HUDs. |
| `RenderScene.on_overlay` / render sequencing | **Reshaped** | Runs after the children, before `end_frame`. |

## Render

| Surface | Classification | Rationale |
|---|---|---|
| `render.Entity` mesh + backend draw | **Retained** | Still the entity. |
| `render.Entity.spin*`, `update`, `step`, `build_local` | **Dropped** | Spin is now a `motion`; behavior lives on `Node:step`. |
| `render.Entity:set_motions`, `options.motion` | **Added** | Entity consumes motions (D4). |
| `render.entity_component` `options.spin` | **Dropped** | Replaced by `options.motion`. |
| `render.entity_component` `options.motion` | **Added** | Schema validated; forwarded to the entity. |
| `render.mesh` factory capability | **Retained (reshaped)** | `create(mesh, material)` is now topology-aware and texture-aware. |
| `render.material` | **Added** | Optional GLSL shader override and/or `texture` (image, `render.texture`, `render.target`, or backend handle); `nil` selects the built-in unlit material. |
| `render.texture` value + capability | **Added** | Backend-neutral image value; GL/GPU factories upload it (D15). |
| `render.target` value + capability | **Added** | Backend-neutral offscreen surface; `.texture` is material-samplable (D16). |
| `render.entity_component` `options.material` | **Added** | Forwarded to the mesh factory. |
| `mesh.make_quad` / `make_triangle` / `make_line` / `make_lines` / `make_grid` | **Added** | Primitive generators in `position_color_f32`. |
| `mesh.make_quad` / `make_cube` UVs | **Reshaped** | Now emit `position_color_uv_f32` (stride 32, `uv` at 24). |
| `mesh.parse_obj(text, options?)` | **Added** | Wavefront OBJ loader (positions + UVs, fan triangulation, negative indices). |
| `mesh.make_fullscreen_quad()` | **Added** | Clip-space quad with top-left UVs for `draw_fullscreen`. |
| mesh `topology` field | **Added** | `"triangles"` / `"lines"`; backend factories select the primitive type. |
| mesh `position_color_uv_f32` layout | **Added** | Textured layout consumed by the built-in textured material. |

## Motion

| Surface | Classification | Rationale |
|---|---|---|
| `motion.Motion` (`contribute`, `anchor`, `set_anchor`, `local_time`) | **Added** | Closed-form `f(time, state)` contributor (D5, D6). |
| `motion.Spin` / `motion.spin { x, y, z, angle, anchor }` | **Added** | Closed-form rotation; defaults `x = 0.7, y = 1.0`. |
| Integrated behavior | **Retained (moved)** | Belongs on `Node:step`, not in a motion. |

## Assets

| Surface | Classification | Rationale |
|---|---|---|
| `rig.source_of` / `dirname` / `join_path` / `file_exists` / `read_file` | **Added** | Shared path/file helpers (previously private to `rig.require`). |
| `asset.path` / `text` / `bytes` / `image` / `material` | **Added** | Path-relative cached loading (D14). |
| `asset.mesh` | **Added** | Path-relative OBJ loading through `mesh.parse_obj`. |
| `asset.material` `spec.texture` | **Added** | Forwarded to `render.material`. |
| `png` module (`png.decode`) | **Added** | libpng simplified API via FFI; no C helper. |
| `jpeg` module (`jpeg.decode`) + `jpeg.c` | **Added** | Minimal setjmp-guarded C helper + FFI; optional build. |
| `examples/shader_asset.lua` + `examples/assets/` | **Added** | External GLSL material demo. |

## Sketch facade

| Surface | Classification | Rationale |
|---|---|---|
| `sketch.App` (`add_entity`, `on_update`, `on_draw`, fields) | **Added** | Registration + callbacks (D2). |
| `sketch.run(options?, build?)` | **Added** | Default bundle/scene/camera assembly. |
| `sketch.App:on_key` / `on_mouse` / `on_resize` | **Added** | Raw input callbacks in a sketch. |
| `sketch.App:add_camera_controls` / `options.camera_controls` | **Added** | Opt-in `camera` controllers (D13). |
| `sketch.App:add_overlay` / `on_overlay` | **Added** | Registered overlays draw after the scene (D17). |
| `frame.input` / `app.input` | **Added** | Shared `input.Input` state (D17). |
| `camera.Orbit` / `camera.Fly` (+ `camera.orbit`/`camera.fly`) | **Added** | Backend-agnostic camera controllers. |
| `examples/orbit_grid.lua` | **Added** | Primitives + optional orbit controls. |
| `sdl3x.bundle_sdl3_gl` / `bundle_sdl3_gpu` | **Retained** | The backend hint; still the only backend choice. |
| `sdl3x` GL/GPU texture factories (`gl_texture_component` / `gpu_texture_component`) | **Added** | Provide `render.texture` (D15). |
| `sdl3` SDL_GPU sampler/texture bindings | **Added** | `CreateGPUSampler`, `UploadToGPUTexture`, `BindGPUFragmentSamplers`, structs, constants. |
| `sdl3x` GL/GPU target factories (`gl_target_component` / `gpu_target_component`) | **Added** | Provide `render.target` (D16). |
| `glx.Framebuffer` + GL framebuffer/renderbuffer bindings | **Added** | Offscreen GL rendering for render targets. |
| `sdl3x.App` | **Retained** | Still the execution class used by the facade. |

## Examples

| Surface | Classification | Rationale |
|---|---|---|
| `examples/spinning_cube_common.lua` | **Reshaped** | Now uses `rig.run` + `motion.spin`. |
| `examples/spinning_cube_gl.lua` / `_gpu.lua` | **Retained** | Still differ only by bundle. |
| `examples/shader_asset.lua` + `examples/assets/` | **Retained** | External GLSL material demo. |
| `examples/textured_quad_common.lua` / `_gl.lua` / `_gpu.lua` | **Added** | Built-in textured material over `asset.image`. |
| `examples/post_process_common.lua` / `_gl.lua` / `_gpu.lua` | **Added** | Render target chained through a fullscreen post shader. |
| `examples/params_overlay_common.lua` / `_gl.lua` / `_gpu.lua` | **Added** | Live `params`/`overlay` driving a sketch. |
| `examples/audio_common.lua` / `_gl.lua` / `_gpu.lua` | **Added** | Looping WAV with volume/mute through the params overlay.

## Input, parameters, and overlays

| Surface | Classification | Rationale |
|---|---|---|
| `input.Input` (`on_key`/`on_mouse`, held/pressed/released, mouse, axes, modifiers) | **Added** | Consolidated input state exposed as `frame.input` (D17). |
| `params.Params` / `params.params` | **Added** | Clamped number/boolean/enum live value store (D17). |
| `overlay.Overlay` / `overlay.overlay` | **Added** | Immediate screen-space parameter editor (D17). |

## Audio

| Surface | Classification | Rationale |
|---|---|---|
| `audio.load` / `audio.Clip` (refcounted) | **Added** | Path-relative WAV loading (D18). |
| `audio.play` / `audio.Voice` (play/loop/volume/pause/resume/stop) | **Added** | One stream per voice; no mixer (D18). |
| `audio.update` / `audio.stop_all` / `audio.Scope` | **Added** | Frame refill and deterministic lifetimes (D18). |
| `sdl3` audio bindings (`InitSubSystem`, `LoadWAV`, `OpenAudioDeviceStream`, ...) | **Added** | Minimal SDL3 audio surface. |

## Planned (not yet present)

Recording/headless mode and hot reload/REPL (Phases 8–9, deferred) and async asset
loading. These are out of scope for the current inventory.