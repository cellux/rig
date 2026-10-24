# Diary

Running log of discussion, discoveries, and progress for the demo-engine evolution.
Enduring decisions live in `DECISIONS.md`; ordered work lives in `PHASES.md`.

## 2026-10-24 — Movement/animation model

Discussed what "movement/animation" is. Conclusion: it is not one system. Separate the
axes — **observable** (what changes), **signal** (time/input/state), **mapping**
(closed-form vs integrated/keyframe), **composition** (order/space), and **time model**
(wall clock vs fixed step vs phase). "Movement" is kinematics-integrated; "animation" is
authored/procedural-sampled; both are `value = f(time, state)`. Spin is the simplest
motion: observable = local rotation, signal = time, mapping = closed form, composition =
transform multiply.

Key observation: `render.Entity` hard-coded spin even though nothing in that code needs
a mesh or GPU. Transform animation is a **node-level** concern, and the litmus test is
"can you spin a non-rendering empty node?". The seam already existed: `Node:build_local`
and `Node:step`.

## 2026-10-24 — Full-engine discussion and product reframe

Asked what people typically do to build a full game engine: layered architecture,
data-model fork (OOP scene graph vs component model vs ECS, with hybrids in practice),
fixed-step loop with interpolation, simulation/render extraction split, RHI + render
graph + materials, resources/handles/async, reflection+serialization as the editor
backbone, tooling as the differentiator, and a typical evolution order.

Reframed to the actual vision: Rig is a **code-first creative-coding runtime** (LÖVE /
raylib / p5 / nannou family), not Unity. "Full-fledged" here means complete media
coverage plus a live workflow. Explicitly out: editor, ECS, reflection, networking,
asset cooking. The DI/component/bundle machinery is a power tool, not the front door.

## 2026-10-24 — Reactive worlds vs closed-form

Question: does closed-form animation block reactive, walk-through worlds? No. Expression
and source are orthogonal. A reactive world is state plus functions that read it; a
door is `f(time - state.opened_at)`, still closed-form. What reactive worlds need is
mostly *outside* animation: mutable state, ordered behaviors, events/picking, local
clocks, world queries. Determinism comes from fixed timestep + recorded input, not from
avoiding state; closed-form buys scrubbing. Design consequence: the motion interface
takes a context `(time, dt, state)`, and anchored local time bridges interaction into
closed-form.

## 2026-10-24 — Phase 1 and 2 implemented

Implemented the core seam and the facade:

- `src/modules/motion.lua` + `motion.md`: `Motion`, `Spin`/`motion.spin`, closed-form
  `contribute`, `anchor`/`local_time`.
- `src/modules/scene.lua`: `Node.motions` + `add/remove/clear`, `build_local(out, frame)`,
  frame threading through `step`/`draw_node`/`render_tree`/`render_children`;
  `RenderScene` clock/`time`/`dt`/`advance_time`/`frame`, `on_update`/`on_draw`, restructured
  `render`; `container_component` optional `sched.clock` and hook forwarding.
- `src/modules/render.lua`: `Entity` consumes `options.motion`, drops spin/update/step/
  build_local; `entity_component` forwards `motion`.
- `src/modules/sketch.lua` + `sketch.md` and `rig.run` in `rig.lua` (+`rig.md`).
- `examples/spinning_cube_common.lua` rewritten to `rig.run` + `motion.spin`.
- Tests: `motion_test.lua`, `sketch_test.lua`, extended `scene_test.lua`, updated
  `render_test.lua`.

Discovery — **mathx matrices are row-major** (`out[i*4+j]`, translation in `out[12..14]`,
row-vector points). "Spin" therefore needs to **pre-multiply** onto the base
(`local = m * base`) to rotate a node about its own origin; post-multiplying would orbit
the parent. `Node:build_local` iterates motions in reverse so list order equals
application order.

Discovery — an optional requirement still errors if the capability is **unknown** to the
composition. `scene.plugin` now declares `sched.clock` so a scene without a scheduler
resolves the optional requirement to `nil`.

Bug — `RenderScene:render` initially called `render_children(frame)`, dropping `self`;
corrected to `self:render_children(self, frame)`.

Verification: `make test` — 48/48 files passed. GL example runs (timeout exit 124); GPU
example assembles and fails only on the sandbox's missing Vulkan ICD (validated by the
author on the host).

## 2026-10-24 — GPU path unblocked in the sandbox

With Vulkan deps present, `examples/spinning_cube_gpu.lua` now initializes the SDL_GPU
device but failed loading shaderc: the loader only tried `libshaderc_shared.so*`
(Fedora/Windows naming), while Debian/Ubuntu's `libshaderc1`/`libshaderc-dev` provide
`libshaderc.so.1`. Added `libshaderc.so.1` and `libshaderc.so` to the candidate list in
`shaderc.lua`. The GPU example now runs to timeout (exit 124) with only the non-fatal
Mesa "Haswell Vulkan support is incomplete" warnings. `make test` stays green (48/48).

## 2026-10-24 — Phase 3 implemented (immediate mesh drawing)

Added `draw_mesh(mesh, transform?)` to `scene.RenderScene`, plus a world-transform
stack (`push_transform`/`pop_transform`/`current_transform`) and a lazy per-mesh
`mesh_drawable` cache. `scene.container_component` now optionally resolves the
composition's `render.mesh` factory into `mesh_factory`, and `scene.plugin` declares
`render.mesh`. Drawing uses the same mesh factory and backend drawables as retained
entities — no parallel path.

Usage is `frame.surface:draw_mesh(mesh, world)` from an `on_draw` hook. Verified with a
`scene_test` drawing case and an end-to-end probe that draws a cube immediately through
the facade. Primitives, materials, and render targets remain Phase 3b/6.

## 2026-10-24 — Phase 3b implemented (primitives and materials)

Added primitive generators (`make_quad`, `make_triangle`, `make_line`, `make_lines`,
`make_grid`) and a `topology` field on meshes. GL/GPU factories now select the primitive
type from topology, and `render.material { vertex, fragment }` provides an optional
shader override; drawables are cached per `(mesh, material)`. `draw_mesh` gained a
third `material` argument.

Discovery — GL constants live in `src/modules/gl.c` (`SET_GL_CONST`), not `gl.lua`;
`gl.LINES`/`gl.LINE_STRIP`/`gl.POINTS` were missing and are now declared.

Verified with a GL probe drawing a grid, quad, line, and a custom-material quad, plus
extended mesh/render/scene tests. `make test` stays green, and the GPU example still
runs to timeout.

## 2026-10-24 — Phase 4 implemented (optional camera controls)

Added a backend-agnostic `camera` module with `Orbit` and `Fly` controllers
(`on_key`/`on_mouse`/`update(dt)`/`apply(scene)`; `apply` preserves fov/near/far). The
sketch facade gained input callbacks (`app:on_key`/`on_mouse`/`on_resize`) and opt-in
camera controls (`app:add_camera_controls` / `rig.run { camera_controls = ... }`).
Input is delivered by a per-run execution subclass of `sdl3x.App` that closes over the
sketch, so nothing is enabled unless the user asks for it. Added
`examples/orbit_grid.lua` (grid + spinning cube + orbit controls).

Mouse-wheel zoom is not implemented because the `sdl3` binding does not yet expose
wheel events; orbit zoom uses keys (Q/E) for now. `make test` is green (49 files) and
the new example runs.

## 2026-10-24 — Phase 5 implemented (assets)

Exposed `rig.source_of`/`dirname`/`join_path`/`file_exists`/`read_file` (previously
private to `rig.require`) and added the `asset` module: caller-relative, canonical-path
cached `path`/`text`/`bytes`/`image`/`material`. Images decode through a `png` module
(libpng simplified `png_image` API via FFI — it reports errors through return codes, so
no C helper is needed) and a `jpeg` module.

JPEG was the interesting case: libjpeg exits fatally via `longjmp`, which pure FFI
cannot express safely. Per the author's guidance, `jpeg.c` holds *only* the
`setjmp`-guarded `rig_jpeg_decode`; `jpeg.lua` does everything else through FFI and
calls the helper with `ffi.C`. The build detects libjpeg with `find_package(JPEG)` and
compiles a stub otherwise, so builds without libjpeg headers stay green. libpng was
bound directly through `ffi.cdef` + dynamic `dl` loading, no C.

Added tests (`png_test`, `jpeg_test`, `asset_test`) and fixtures, plus
`examples/shader_asset.lua` (GLSL loaded from files, drawn with `draw_mesh`). `make
test` is green (52 files). JPEG currently exercises the not-built stub in the sandbox;
it verifies once `libjpeg62-turbo-dev` is installed.

## 2026-10-24 — Phase 5b implemented (textures and mesh files)

Added texture values and sampling, and an OBJ loader.

- `render.texture { image = ..., name?, filter?, wrap? }` is a backend-neutral value.
  Backend `render.texture` factories upload it once per value: the GL factory folds
  filter/wrap into a `glx.Texture2D`; the GPU factory creates an `SDL_GPUTexture`
  plus an `SDL_GPUSampler`. Binding is `handle:bind(unit)` on GL and
  `handle:bind(pass, slot)` on GPU.
- `render.material` now accepts `texture` (a `render.texture` or a decoded image)
  and treats `vertex`/`fragment` as optional so a material can be "built-in +
  texture". Mesh factories bind the texture at slot 0 and set `u_texture` when the
  program declares it. `render.entity_component` forwards `options.material`.
- Texturing needs UVs, so a second interleaved layout `position_color_uv_f32`
  (stride 32, `uv` at 24) was added. `make_quad` and `make_cube` emit it; the other
  generators stay on `position_color_f32`. The built-in textured material requires a
  UV layout.
- `mesh.parse_obj` parses Wavefront OBJ (positions + `vt`, fan triangulation,
  negative indices, malformed/no-face errors) into a `position_color_uv_f32` mesh;
  `asset.mesh(path)` loads and caches it relative to the script. `asset.material`
  forwards `spec.texture`.

Discovery — the SDL_GPU binding lacked samplers and texture uploads, so `sdl3`
 gained `SDL_CreateGPUSampler`/`SDL_ReleaseGPUSampler`,
`SDL_UploadToGPUTexture`, `SDL_BindGPUFragmentSamplers`, the sampler/region/
-binding structs, and the `GPU_FILTER`/`GPU_SAMPLER*` constants in `sdl3.c` and
`gl.c`.

Bug — `jpeg.c` failed to compile once real libjpeg headers were present
(`libjpeg62-turbo-dev` installed): `jpeglib.h` needs `<stdio.h>` for `FILE`.
Added the include; `jpeg_test` now exercises the real decoder (2/2).

Verification: `make test` — 52/52 files passed. `examples/textured_quad_gl.lua`
and `examples/textured_quad_gpu.lua` both run to timeout (exit 124); the SDL_GPU
path uploads the straightforward RGBA8 texture, compiles the textured SPIR-V
(sampler at descriptor set 2), and binds it, so the new GPU bindings are exercised
end to end. The Mesa `Haswell Vulkan support is incomplete` warnings are non-fatal.

## 2026-10-24 — Phase 6 implemented (render targets and post-processing)

Added offscreen targets and the screen-space pass that consumes them.

- `render.target { width, height, depth?, filter?, wrap? }` is a backend-neutral
  value. Backend `render.target` factories create one surface per value: the GL one
  attaches a `glx.Texture2D` to a new `glx.Framebuffer` (optional depth renderbuffer),
  the GPU one creates an `SDL_GPUTexture` (swapchain format, `COLOR_TARGET |
  SAMPLER`) plus an optional depth texture and a sampler. Both expose a `.texture`
  handle that materials sample.
- `scene.RenderScene:render_to(target, draw)` renders the callback offscreen, sizing
  the view/projection to the target and restoring the window afterwards. Backend
  scenes override `enter_target`/`leave_target`: GL binds the framebuffer and
  viewport; GPU ends the swapchain pass, begins a target pass, and re-begins the
  swapchain pass afterwards.
- `scene.RenderScene:draw_fullscreen(material)` draws a clip-space quad
  (`mesh.make_fullscreen_quad`) with an identity transform, so a pass is "render to
  texture, feed to a shader".
- Materials may name a `render.target` as their `texture`; the mesh factories resolve
  it through the same target factory, so the pass surface and the sampled texture are
  one object.

Discovery — GL offscreen textures are bottom-up (framebuffer row 0 is the bottom)
while uploaded images and SDL_GPU targets are top-down. To keep a single fullscreen
UV convention, GL `render_to` negates the clip-space Y column of the view/projection
while rendering into a target, so the stored texture is top-down; the fullscreen quad
maps its top to `v = 0` for both backends.

Discovery — SDL_GPU pipelines are tied to their color target format, and mesh
pipelines were built for the swapchain. Targets therefore use the swapchain format
(not a fixed RGBA8) so the same pipeline renders into both the window and the target;
the target pass also supplies a depth buffer with the scene's chosen depth format.

Added `glx.Framebuffer` and the GL framebuffer/renderbuffer bindings
(`GenFramebuffers`, `FramebufferTexture2D`, `CheckFramebufferStatus`, ...) plus
`FRAMEBUFFER`/`COLOR_ATTACHMENT0`/`DEPTH_ATTACHMENT`/`RENDERBUFFER`/
`DEPTH_COMPONENT24` constants.

Verification: `make test` — 52/52 files passed. `examples/post_process_gl.lua` and
`examples/post_process_gpu.lua` both run to timeout (exit 124), chaining a cube
rendered into a target through a grayscale/vignette fullscreen shader.

## 2026-10-24 — Phase 7 implemented (input and parameter overlay)

Added ergonomic input state and a live parameter overlay. Phases 8 (recording) and 9
(hot reload/REPL) were deferred by the author.

- `input.Input` tracks keys by scancode and by name (case-insensitive), held and
  per-frame pressed/released edges, mouse position/delta/buttons, and modifiers. The
  sketch owns one (`app.input`) and every frame carries it as `frame.input`. Input
  edges are cleared after the overlay phase so `on_update`, `on_draw`, and overlays
  all observe the same frame.
- `params.Params` is a clamped value store for numbers, booleans, and wrapping
  enums, with declaration order, normalized `fraction`, and `format`.
- `overlay.Overlay` draws a `params` store as screen-space bars and edits it: Up/Down
  select, Left/Right adjust, Space/Return toggle, click/drag numbers. An optional
  `draw_text` callback is the seam for labels; it is deliberately not a retained UI
  toolkit.
- `RenderScene:draw_screen` maps a unit quad to a pixel rectangle with a top-left
  origin at clip z = 0, and a new `on_overlay` hook runs after `render_children` so
  overlays land on top. The sketch wires `app:add_overlay`/`app:on_overlay`.

Discovery — the runtime step polls input events before the frame handler, so
clearing input edges at the start of `on_update` would discard the frame's events.
Clearing them at the end of the overlay phase keeps pressed/released valid for the
whole frame and starts the next poll clean.

Verification: `make test` — 55/55 files passed. `examples/params_overlay_gl.lua` and
`examples/params_overlay_gpu.lua` both run to timeout (exit 124).

## 2026-10-24 — Phase 10 implemented (audio)

Added minimal SDL3 audio playback, completing the media coverage.

- `audio.load(path)` resolves relative to the calling script (like `asset`) and
  returns a refcounted `Clip`; repeated loads share one. `audio.play(clip, opts)`
  opens one `SDL_AudioStream` per voice (no mixer) and returns a `Voice` with
  loop/volume/pause/resume/stop. `audio.update()` tops up loops and reaps finished
  one-shots; `audio.Scope` gives deterministic lifetimes.
- The audio subsystem is initialized lazily (`SDL_InitSubSystem(SDL_INIT_AUDIO)`),
  and `load`/`play` return `nil, error` when no device exists, so demos degrade
  gracefully instead of raising.
- New `sdl3` bindings: `InitSubSystem`, `LoadWAV`, `OpenAudioDeviceStream`,
  `DestroyAudioStream`, `PutAudioStreamData`, `ClearAudioStream`,
  `GetAudioStreamQueued`, `Pause/ResumeAudioStreamDevice`, `SetAudioStreamGain`,
  plus `SDL_AudioSpec`/`SDL_AudioStream` and the default device constants.
- The sketch facade calls `audio.update()` each frame. `examples/audio_common.lua`
  (+ `_gl`/`_gpu`) loops a generated `beep.wav` and tweaks volume/mute through the
  params overlay from Phase 7.

Discovery — SDL error strings return as `const char *` cdata, not Lua strings, so
`audio` normalizes them with `ffi.string`.

Verification: `make test` — 56/56 files passed. `examples/audio_gl.lua` and
`examples/audio_gpu.lua` run to timeout (exit 124) with `SDL_AUDIODRIVER=dummy`; a
manual probe that stops the runtime after 60 frames exits cleanly, and the example
runs silently (printing a notice) when no audio device is present.

## Next

All in-scope phases (0–7 and 10) are complete. Deferred: Phase 8 (recording and
headless rendering), Phase 9 (hot reload and REPL), and async asset loading through
`uv`.