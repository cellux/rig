# `sdl3x`

Higher-level SDL helpers layered on top of `sdl3`.

Unlike `sdl3`, this module owns Rig-specific runtime integration and Lua-side convenience APIs.

## Scope

`sdl3x` owns:

- SDL runtime components and convenience bundles for `rig.runtime()`
  - `sdl3x.bundle_sdl3`
  - `sdl3x.bundle_sdl3_gl`
  - `sdl3x.bundle_sdl3_gpu`
- default SDL window creation
- `sdl3x.Properties`
- SDL error/string helpers
- SDL renderer and window convenience accessors
- SDL GPU builders and resource scopes
- SDL/OpenGL font renderer providers
- SDL GPU and OpenGL runtime support helpers

Requiring `sdl3x` makes its components and bundles available.

## Exports

- `sdl3x.get_error([fallback])`
- `sdl3x.free(ptr)`
- `sdl3x.normalize_properties_id(props)`
- `sdl3x.GPUShaderFormat(value[, path])`
- `sdl3x.GPUShaderStage(value[, path])`
- `sdl3x.GPUPrimitiveType(value[, path])`
- `sdl3x.GPUSampleCount(value[, path])`
- `sdl3x.GPUFillMode(value[, path])`
- `sdl3x.GPUCullMode(value[, path])`
- `sdl3x.GPUFrontFace(value[, path])`
- `sdl3x.GPUCompareOp(value[, path])`
- `sdl3x.GPUStencilOp(value[, path])`
- `sdl3x.GPUBlendOp(value[, path])`
- `sdl3x.GPUBlendFactor(value[, path])`
- `sdl3x.GPUColorComponentFlags(value[, path])`
- `sdl3x.GPUBufferUsageFlags(value[, path])`
- `sdl3x.GPUVertexInputRate(value[, path])`
- `sdl3x.GPUVertexElementFormat(value[, path])`
- `sdl3x.GPUTextureFormat(value[, path])`
- `sdl3x.Properties`
- `sdl3x.Window`
- `sdl3x.GPUShader`
- `sdl3x.ResourceScope`
- `sdl3x.get_gl_proc_address(name)`
- `sdl3x.get_gpu_driver_names()`
- `sdl3x.upload_to_gpu_buffer(device, buffer, data_string)`
- `sdl3x.choose_depth_format(device)`
- `sdl3x.create_depth_texture(device, width, height[, format])`
- `sdl3x.build_vertex_buffer_descriptions(buffers)`
- `sdl3x.build_vertex_attributes(attributes)`
- `sdl3x.build_vertex_input_state(layout)`
- `sdl3x.build_color_target_descriptions(specs)`
- `sdl3x.build_gpu_buffer_create_info(spec)`
- `sdl3x.build_graphics_pipeline_create_info(spec)`
- `sdl3x.create_gpu_shader(device, compiled[, props])`
- `sdl3x.App`
- `sdl3x.SceneApp`

## Runtime Integration

This module provides the SDL runtime components, provider components, and
convenience bundles used by `rig.runtime()`.

The bundles accept a shared options table:

```lua
local builder = rig.runtime()
sdl3x.bundle_sdl3(builder, {
   window_props = { ... },
   render = function() end,
})
builder:execute(App):compile():start()
```

Shared fields accepted by the SDL bundles as applicable:

- `init_flags`
  - Defaults to `sdl3.INIT_VIDEO + sdl3.INIT_EVENTS`.
- `window_props`
  - Passed through to `sdl3x.Window(...)`.
  - The builtin `sdl3x.Window(...)` path accepts a plain table or `sdl3x.Properties`.
- `create_renderer(window) -> renderer_ptr | nil, err`
  - Overrides renderer creation for `bundle_sdl3`.
  - `window` is an `sdl3x.Window`.
- `render`
  - Optional; when omitted the execution class's `render(...)` method is used.
- `frame_profiler`
  - `true` or an options table to attach a frame profiler.

Additional `bundle_sdl3_gl` fields:

- `gl_attributes`
- `swap_interval`

Additional `sdl3_gpu` fields:

- `shader_formats`
- `debug_mode`
- `backend_name`

## Helpers

- `sdl3x.get_error([fallback])`
  - Returns the current SDL error string.
  - Returns `fallback` when SDL has no current error string.
  - Defaults to `"unknown SDL error"` when no fallback is provided.
- `sdl3x.free(ptr)`
  - Frees SDL-owned memory returned by SDL APIs that require `SDL_free(...)`.
  - Ignores `nil` and `ffi.NULL`.
- `sdl3x.normalize_properties_id(props)`
  - Accepts `nil`, a raw numeric/cdata `SDL_PropertiesID`, or an `sdl3x.Properties` instance.
  - Returns the normalized SDL properties handle.
- `sdl3x.GPUShaderFormat(value[, path])`
  - Accepts an SDL-style shader format name like `"SPIRV"` or the corresponding `sdl3.GPU_SHADERFORMAT_*` numeric constant.
  - Returns the normalized numeric SDL shader format value.
- `sdl3x.GPUShaderStage(value[, path])`
  - Accepts an SDL-style shader stage name like `"VERTEX"` or the corresponding `sdl3.GPU_SHADERSTAGE_*` numeric constant.
  - Returns the normalized numeric SDL shader stage value.
- `sdl3x.GPUPrimitiveType(value[, path])`
  - Accepts an SDL-style primitive type name like `"TRIANGLELIST"` or the corresponding `sdl3.GPU_PRIMITIVETYPE_*` numeric constant.
  - Returns the normalized numeric SDL primitive type value.
- `sdl3x.GPUSampleCount(value[, path])`
  - Accepts `"1"`, `"2"`, `"4"`, `"8"`, or the corresponding `sdl3.GPU_SAMPLECOUNT_*` numeric constant.
  - Returns the normalized numeric SDL sample count value.
- `sdl3x.GPUFillMode(value[, path])`
  - Accepts an SDL-style fill mode name like `"FILL"` or the corresponding `sdl3.GPU_FILLMODE_*` numeric constant.
  - Returns the normalized numeric SDL fill mode value.
- `sdl3x.GPUCullMode(value[, path])`
  - Accepts an SDL-style cull mode name like `"BACK"` or the corresponding `sdl3.GPU_CULLMODE_*` numeric constant.
  - Returns the normalized numeric SDL cull mode value.
- `sdl3x.GPUFrontFace(value[, path])`
  - Accepts an SDL-style front-face name like `"COUNTER_CLOCKWISE"` or the corresponding `sdl3.GPU_FRONTFACE_*` numeric constant.
  - Returns the normalized numeric SDL front-face value.
- `sdl3x.GPUCompareOp(value[, path])`
  - Accepts an SDL-style compare-op name like `"LESS"` or the corresponding `sdl3.GPU_COMPAREOP_*` numeric constant.
  - Returns the normalized numeric SDL compare-op value.
- `sdl3x.GPUStencilOp(value[, path])`
  - Accepts an SDL-style stencil-op name like `"KEEP"` or the corresponding `sdl3.GPU_STENCILOP_*` numeric constant.
  - Returns the normalized numeric SDL stencil-op value.
- `sdl3x.GPUBlendOp(value[, path])`
  - Accepts an SDL-style blend-op name like `"ADD"` or the corresponding `sdl3.GPU_BLENDOP_*` numeric constant.
  - Returns the normalized numeric SDL blend-op value.
- `sdl3x.GPUBlendFactor(value[, path])`
  - Accepts an SDL-style blend-factor name like `"SRC_ALPHA"` or the corresponding `sdl3.GPU_BLENDFACTOR_*` numeric constant.
  - Returns the normalized numeric SDL blend-factor value.
- `sdl3x.GPUColorComponentFlags(value[, path])`
  - Accepts a numeric bitmask composed from exposed `sdl3.GPU_COLORCOMPONENT_*` constants.
  - Rejects unknown bits.
  - Returns the normalized numeric SDL color-component flags value.
- `sdl3x.GPUBufferUsageFlags(value[, path])`
  - Accepts a numeric bitmask composed from exposed `sdl3.GPU_BUFFERUSAGE_*` constants.
  - Rejects zero and any unknown bits.
  - Returns the normalized numeric SDL buffer-usage flags value.
- `sdl3x.GPUVertexInputRate(value[, path])`
  - Accepts `"vertex"`, `"instance"`, or the corresponding SDL numeric constants.
  - Returns the normalized numeric SDL vertex input rate value.
- `sdl3x.GPUVertexElementFormat(value[, path])`
  - Accepts an SDL-style vertex element format name like `"INT2"` or `"HALF4"`, or the corresponding SDL numeric constant.
  - Returns the normalized numeric SDL vertex element format value.
- `sdl3x.GPUTextureFormat(value[, path])`
  - Accepts an SDL-style texture format name like `"R8G8B8A8_UNORM"` or the corresponding `sdl3.GPU_TEXTUREFORMAT_*` numeric constant.
  - Returns the normalized numeric SDL texture format value.

## `sdl3x.ResourceScope`

`sdl3x.ResourceScope` is a subclass of `rig.ResourceScope` specialized for SDL GPU resources.

Instantiate it as:

- `local scope = sdl3x.ResourceScope(device[, label])`

It supports generic `adopt`, `replace`, and `release`, plus:

- `scope:create_gpu_shader(...)`
- `scope:create_gpu_buffer(...)`
- `scope:create_graphics_pipeline(...)`
- `scope:create_depth_texture(...)`

`scope:create_gpu_shader(...)` returns an `sdl3x.GPUShader`.

## `sdl3x.GPUShader`

`sdl3x.GPUShader` is an owning wrapper around `SDL_GPUShader *`.

Instantiate it through:

- `local shader = sdl3x.GPUShader(device, compiled[, props])`
- `local shader = sdl3x.create_gpu_shader(device, compiled[, props])`

Instances expose:

- `shader.device`
- `shader.ptr`
- `shader.stage`
- `shader.format`
- `shader.entrypoint`

Methods:

- `shader:release()`

## `sdl3x.Properties`

`sdl3x.Properties` is an owning wrapper around `SDL_PropertiesID`.

Instances expose the live SDL handle directly as:

- `props.id`

Methods:

- `props:set(name, value)`
- `props:clear(name)`
- `props:merge(values_or_props)`
- `props:get(name[, default])`
- `props:has(name)`
- `props:to_table()`
- `props:clone()`
- `props:release()`

Supported value types:

- `boolean`
- integer or floating-point `number`
- `string`
- pointer-like `cdata`

## `sdl3x.Window`

`sdl3x.Window` is an owning wrapper around `SDL_Window *`.

Instantiate windows through:

- `local window = sdl3x.Window(options)`

Instances expose the live SDL handle directly as:

- `window.ptr`

Methods:

- `window:get_size()`
- `window:get_size_in_pixels()`
- `window:set_fullscreen(enabled)`
- `window:sync()`
- `window:release()`

Construction uses temporary `sdl3x.Properties`, merges builtin default window properties with `options.window_props`, fills default width/height when omitted, and calls `SDL_CreateWindowWithProperties(...)`.

## `sdl3x.App`

`sdl3x.App` extends `rig.Class()` with SDL window/event/render conveniences. It is
instantiated as a runtime execution class, so `init(context)` receives the runtime
context and `context.window` / `context.graphics`:

- `window_width`
- `window_height`
- `pixel_width`
- `pixel_height`
- `fullscreen_enabled`
- `vsync_enabled`
- `frame_profiler`
- `frame_profiler_enabled`
- `font_faces`
- `owned_resources`

Methods:

- `app:set_vsync(enabled)`
- `app:toggle_vsync()`
- `app:set_fullscreen(enabled)`
- `app:toggle_fullscreen()`
- `app:set_frame_profiler_enabled(enabled)`
- `app:toggle_frame_profiler()`
- `app:own(resource, release_fn)`
- `app:replace_owned(key, resource, release_fn)`
- `app:create_owned_scope(label?)`
- `app:release_owned_resources()`
- `app:load_font_face(name, path[, face_index])`
- `app:get_font_face(name)`
- `app:invoke_render(...)`

## `sdl3x.SceneApp`

`sdl3x.SceneApp` extends `animator.App` with the same SDL/window/render conveniences as `sdl3x.App`.

Typical usage:

```lua
local sdl3x = require("sdl3x")

local App = rig.Class(sdl3x.SceneApp)

function App:render()
   if self.root ~= nil then
      self.root:draw_tree({
         renderer = self.ctx.graphics.renderer,
         graphics = self.ctx.graphics,
      })
   end
end
```

## Runtime Components

`sdl3x` also exposes composable components for the new runtime model (see
`runtime.md`):

- `sdl3x.plugin([spec])`
  - Declares the `sdl3.subsystem`, `sdl3.window`, and `sdl3.input` capabilities and
    the `sdl3.key`, `sdl3.mouse`, `sdl3.resize`, `sdl3.close`, and `sdl3.focus`
    extension points, mapping each to a class method (`on_key`, `on_mouse`,
    `on_resize`, `on_close`, `on_focus`).
- `sdl3x.subsystem_component(plugin, options)`
  - Provides `sdl3.subsystem`; owns SDL init flags and quits only the subsystems it
    initialized.
  - `options.init_flags` defaults to `sdl3.INIT_VIDEO + sdl3.INIT_EVENTS`.
- `sdl3x.window_component(plugin, options)`
  - Provides `sdl3.window` and requires `sdl3.subsystem`.
  - `options.window_props` is passed to `sdl3x.Window(...)`.
- `sdl3x.input_component(plugin, options)`
  - Provides `sdl3.input` and requires `sdl3.subsystem` and `sdl3.window`.
  - Polls SDL events each step and emits normalized `sdl3.*` events. It emits an
    initial `sdl3.resize` on the first poll unless `options.initial_resize` is false.

Example:

```lua
local rig = require("rig")
local runtime = require("runtime")
local sdl3x = require("sdl3x")

local sdl_plugin = sdl3x.plugin()

local compiled = rig.runtime()
   :use(sdl_plugin)
   :add(sdl3x.subsystem_component(sdl_plugin, { name = "sdl" }))
   :add(sdl3x.window_component(sdl_plugin, { name = "window" }))
   :add(sdl3x.input_component(sdl_plugin, { name = "input" }))
   :execute(function(ctx)
      -- ctx.window and ctx.input are available.
   end)
   :compile()
```

## Graphics Context Components

Graphics contexts provide the `graphics.context` capability (declared by
`sdl3x.plugin`) and require `sdl3.window`. Each provider records its backend in the
capability `properties`, so consumers can require a specific backend
(`{ capability = "graphics.context", properties = { backend = "gl" } }`) without
naming a component.

- `sdl3x.renderer_context_component(plugin, options)`
  - Provides `backend = "renderer"`; wraps `SDL_Renderer*`.
  - `options.create_renderer` optionally overrides the default creation.
  - Object exposes `renderer`, `clear(r, g, b, a)`, `present()`, `set_vsync(enabled)`,
    `render_frame(render_fn)`, `window`, and `release()`.
- `sdl3x.gl_context_component(plugin, options)`
  - Provides `backend = "gl"`; the window must be created with the OpenGL window
    property.
  - `options.gl_attributes` and `options.swap_interval` are applied.
  - Object exposes `context`, `present()`, `set_swap_interval(interval)`,
    `get_proc_address(name)`, `render_frame(render_fn)`, `window`, and `release()`.
- `sdl3x.gpu_context_component(plugin, options)`
  - Provides `backend = "gpu"`; wraps `SDL_GPUDevice*` and claims the window.
  - `options.shader_formats`, `options.debug_mode`, and `options.backend_name` are
    honored.
  - Object exposes `device`, `render_frame(render_fn)`, `window`, and `release()`.

All graphics components release their own resources during rollback if creation fails,
so a partially initialized context never leaks.

## Frame Component

`sdl3x.frame_component(plugin, options)` provides the per-frame loop:

- It requires `graphics.context` and contributes a `frame` progress operation that:
  1. emits `core.before_frame`;
  2. calls the render callback;
  3. presents through the graphics context (`graphics:render_frame(render)`);
  4. emits `core.after_frame`.
- `options.render` is an optional render callback. When omitted, class execution uses
  `instance:render(...)`; if that is also absent, the runtime uses the component
  providing `render.scene` (see the `scene` module) as the render callback.
- `options.frame_profiler` may be `true` or a `profiler.FrameProfiler` options table;
  the frame profiler wraps the whole frame and the render call.

`core.before_frame` maps to the class method `before_frame`, and `core.after_frame` to
`after_frame`.

Each graphics context implements `render_frame(render_fn)`:

- renderer/OpenGL call `render_fn()` then present/swap;
- GPU acquires a command buffer and swapchain texture, calls
  `render_fn(command_buffer, swapchain_texture, width, height)`, then submits.

## Scene Implementation

`sdl3x` owns the backend-specific implementations of the `scene` interface and
provides the `render.scene.impl` capability:

- `sdl3x.GlRenderScene` — `scene.RenderScene` subclass whose `begin_frame` enables
  the depth test, sets the OpenGL viewport, and clears the color/depth buffers.
- `sdl3x.gl_scene_component(plugin, options)` — provides `render.scene.impl` with
  `properties = { backend = "gl" }` and requires the GL graphics context and
  `gl.resolver`; its value is `GlRenderScene`.
- `sdl3x.GpuRenderScene` — `scene.RenderScene` subclass that owns the depth target and
  the SDL_GPU render pass. `begin_frame(command_buffer, swapchain_texture, width,
  height)` opens the pass and exposes it (with the command buffer) to its drawables;
  `end_frame` closes it.
- `sdl3x.gpu_scene_component(plugin, options)` — provides `render.scene.impl` with
  `properties = { backend = "gpu" }` and requires the GPU graphics context; its value
  is `GpuRenderScene`.

The `bundle_sdl3_gl` and `bundle_sdl3_gpu` bundles add the matching implementation, so
an application using `scene.container_component` gets the right scene shape without
naming it.

## Mesh Factories

`sdl3x` provides the `render.mesh` factories consumed by `render.entity_component`:

- `sdl3x.gl_mesh_component(plugin, options)` — `properties = { backend = "gl" }`;
  requires the GL graphics context, `gl.resolver`, and `shader.stage`. Its factory
  compiles the built-in GLSL colored-mesh shaders into a `glx.Program` and owns a
  `glx.Buffer`/`glx.VertexArray` pair per mesh.
- `sdl3x.gpu_mesh_component(plugin, options)` — `properties = { backend = "gpu" }`;
  requires the GPU graphics context, `shader.stage`, and `mesh.vertex_input`. Its
  factory compiles the built-in GLSL shaders to SPIR-V, builds a graphics pipeline,
  and uploads each mesh into a GPU vertex buffer.

Both factories adopt their resources into the runtime ownership graph, so a partially
created mesh rolls back cleanly.

## Convenience Bundles

Bundles attach their own plugin and add components explicitly; `:use` alone never
changes behavior.

- `sdl3x.bundle_sdl3(builder, options)` — subsystem, window, input, renderer graphics
  context, renderer font provider, frame loop.
- `sdl3x.bundle_sdl3_gl(builder, options)` — subsystem, OpenGL window, input, GL
  context, GL font provider, GL resolver, GL shader stage, GL scene implementation, GL
  mesh factory, frame loop.
- `sdl3x.bundle_sdl3_gpu(builder, options)` — subsystem, window, input, GPU context,
  GPU mesh provider, GPU shader stage, GPU scene implementation, GPU mesh factory,
  frame loop.

Common options: `init_flags`, `window_props`, `render`, `frame_profiler`; GL adds
`gl_attributes`/`swap_interval`; GPU adds `shader_formats`/`debug_mode`/`backend_name`.

```lua
local builder = rig.runtime()
sdl3x.bundle_sdl3(builder, { render = function() end })
builder:execute(AppClass):compile():start()
```
