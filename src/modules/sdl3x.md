# `sdl3x`

Higher-level SDL helpers layered on top of `sdl3`.

Unlike `sdl3`, this module owns Rig-specific runtime integration and Lua-side convenience APIs.

## Scope

`sdl3x` currently owns:

- `rig.run(...)` SDL runtime drivers and presets
  - `mode = "sdl3"`
  - `mode = "sdl3_gl"`
  - `mode = "sdl3_gpu"`
- default SDL window creation
- `sdl3x.Properties`
- SDL error/string helpers
- SDL renderer and window convenience accessors
- SDL GPU builders and resource scopes
- SDL/OpenGL font renderer providers
- SDL GPU and OpenGL runtime support helpers

Requiring `sdl3x` installs the default SDL runtime window factory used by those modes.

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
- `sdl3x.get_window()`
- `sdl3x.get_renderer()`
- `sdl3x.get_gpu_device()`
- `sdl3x.get_gl_context()`
- `sdl3x.get_gl_proc_address(name)`
- `sdl3x.clear(r, g, b, a)`
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

This module registers the SDL runtime drivers and presets used by `rig.run(...)`.

Use SDL-specific runtime configuration under:

- `options.driver_config.sdl3` for `mode = "sdl3"`
- `options.driver_config.sdl3_gl` for `mode = "sdl3_gl"`
- `options.driver_config.sdl3_gpu` for `mode = "sdl3_gpu"`

Shared fields accepted by the SDL runtime modes as applicable:

- `init_flags`
  - Defaults to `sdl3.INIT_VIDEO + sdl3.INIT_EVENTS`.
- `window_props`
  - Passed through to `sdl3x.Window(...)`.
  - The builtin `sdl3x.Window(...)` path accepts a plain table or `sdl3x.Properties`.
- `create_renderer(window) -> renderer_ptr | nil, err`
  - Overrides renderer creation for `mode = "sdl3"`.
  - `window` is an `sdl3x.Window`.
- `render`
  - Required unless `options.app` provides `render(...)` or `invoke_render(...)`.

Additional `sdl3_gl` fields:

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

`sdl3x.App` extends `rig.App` with SDL window/event/render conveniences:

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
         renderer = sdl3x.get_renderer(),
      })
   end
end
```
