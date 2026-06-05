# `sdl3`

Lazy SDL3 binding built on LuaJIT FFI.

The SDL shared library is loaded only when the module is required.

## Runtime Integration

When loaded, `sdl3` registers three `rig.run(...)` presets and drivers:
- `"sdl3"`
  - Owns the SDL window/renderer lifecycle through `rig.run(...)`.
- `"sdl3_gl"`
  - Owns the SDL window/OpenGL-context lifecycle through `rig.run(...)`.
- `"sdl3_gpu"`
  - Owns the SDL window/GPU-device lifecycle through `rig.run(...)`.

## `rig.run` Options

Use SDL-specific runtime configuration under:
- `options.driver_config.sdl3` for `preset = "sdl3"`
- `options.driver_config.sdl3_gl` for `preset = "sdl3_gl"`
- `options.driver_config.sdl3_gpu` for `preset = "sdl3_gpu"`
- `options.event_handlers.key`
- `options.event_handlers.mouse`
- `options.event_handlers.resize`

Shared fields accepted by the SDL runtime presets as applicable:
- All SDL runtime presets create and own a scheduler.
- The scheduler is drained once per frame after event polling and before rendering.
- `sched.sleep(seconds)` is supported and resumes tasks on the first frame after the requested deadline has passed.

- `init_flags`
  - Defaults to `sdl3.INIT_VIDEO + sdl3.INIT_EVENTS`.
- `window_props`
  - Optional window property overrides merged into `sdl3.default_window_props`.
  - If width or height are not provided, the builtin window factory defaults each missing dimension to 75% of the primary display's usable size.
  - If SDL cannot report the usable display size, the fallback remains `640x360`.
- `create_window(options) -> window_ptr | nil, err`
  - Overrides window creation.
  - Defaults to the builtin `SDL_CreateWindowWithProperties` path.
- `create_renderer(window_ptr) -> renderer_ptr | nil, err`
  - Overrides renderer creation for `preset = "sdl3"`.
  - Defaults to the builtin SDL renderer path.
- `render`
  - Mandatory render callback for the selected SDL driver.
- `event_handlers.key(key_info)`
  - Optional keyboard event callback.
- `event_handlers.mouse(mouse_info)`
  - Optional mouse event callback.
- `event_handlers.resize(resize_info)`
  - Optional window resize callback.
  - Called once during setup with `resize_info.initial == true`.
  - Called again when the window size or pixel size changes.
  - `resize_info` currently includes:
    - `type = "resize"`
    - `event`
      - `"initial"`
      - `"resized"`
      - `"pixel_size_changed"`
    - `width`
    - `height`
    - `pixel_width`
    - `pixel_height`
    - `timestamp_ns`
    - `timestamp_ms`

Additional fields accepted by `options.driver_config.sdl3_gl`:

- `gl_attributes`
  - OpenGL context attributes to apply before window creation.
  - Supported keys currently include:
    - `context_major_version`
    - `context_minor_version`
    - `context_profile`
    - `context_flags`
    - `doublebuffer`
    - `depth_size`
    - `stencil_size`
    - `red_size`
    - `green_size`
    - `blue_size`
    - `alpha_size`
    - `multisamplebuffers`
    - `multisamplesamples`
    - `accelerated_visual`
- `swap_interval`
  - OpenGL swap interval passed after context creation.

Additional fields accepted by `options.driver_config.sdl3_gpu`:

- `shader_formats`
  - Passed to the SDL GPU runtime preset during device creation.
- `debug_mode`
  - Passed to the SDL GPU runtime preset during device creation.
- `backend_name`
  - Passed to the SDL GPU runtime preset during device creation.

## Window Properties

- `sdl3.default_window_props`
  - Default property table used by the builtin SDL window factory.
  - The builtin defaults only force the window title.
  - Width and height are filled in dynamically at window-creation time when omitted.
- `sdl3.build_properties(props)`
  - Converts a Lua table into `SDL_PropertiesID`.
- `sdl3.destroy_properties(properties_id)`
  - Releases a properties object built through SDL.

## Time Helpers

- `sdl3.GetCurrentTime(ticks_ptr)`
  - Raw SDL realtime clock call.
- `sdl3.GetTicks()`
  - Milliseconds since SDL initialization.
- `sdl3.GetTicksNS()`
  - Nanoseconds since SDL initialization.
- `sdl3.GetPerformanceCounter()`
  - Raw high-resolution performance counter value.
- `sdl3.GetPerformanceFrequency()`
  - Frequency for `sdl3.GetPerformanceCounter()`.
- `sdl3.Delay(ms)`
  - Sleeps for at least the requested milliseconds.
- `sdl3.DelayNS(ns)`
  - Sleeps for at least the requested nanoseconds.
- `sdl3.DelayPrecise(ns)`
  - Higher-precision SDL delay helper.

## Renderer Helpers

- `sdl3.get_renderer()`
  - Returns the current `SDL_Renderer*` when `preset = "sdl3"` owns the runtime.
- `preset = "sdl3"` also provides the `"font.renderer"` service used by `font.create_text_renderer(...)`.
  - Atlas pages are uploaded lazily as SDL textures.
  - Updated atlas pages are re-uploaded automatically when their page revision changes.
- `preset = "sdl3_gl"` also provides the `"font.renderer"` service used by `font.create_text_renderer(...)`.
  - Atlas pages are uploaded lazily as OpenGL textures.
  - Updated atlas pages are re-uploaded automatically when their page revision changes.
  - Text is drawn through a small OpenGL shader pipeline owned by the runtime.
- `sdl3.SetRenderDrawColor(renderer, r, g, b, a)`
  - Raw SDL renderer color setter.
- `sdl3.RenderClear(renderer)`
  - Raw SDL renderer clear call.
- `sdl3.RenderPoint(renderer, x, y)`
  - Raw SDL point draw call.
- `sdl3.RenderLine(renderer, x1, y1, x2, y2)`
  - Raw SDL line draw call.
- `sdl3.RenderFillRect(renderer, rect_ptr)`
  - Raw SDL filled-rectangle draw call.
- `sdl3.CreateTexture(renderer, format, access, w, h)`
  - Raw SDL texture creation call.
  - For byte-ordered `R,G,B,A` upload buffers, `sdl3.PIXELFORMAT_RGBA32` is the safer choice than `sdl3.PIXELFORMAT_RGBA8888`.
- `sdl3.UpdateTexture(texture, rect_ptr, pixels_ptr, pitch)`
  - Raw SDL texture upload/update call.
- `sdl3.SetTextureColorMod(texture, r, g, b)`
  - Raw SDL texture color modulation call.
- `sdl3.SetTextureAlphaMod(texture, alpha)`
  - Raw SDL texture alpha modulation call.
- `sdl3.SetTextureBlendMode(texture, blend_mode)`
  - Raw SDL texture blend mode call.
- `sdl3.RenderTexture(renderer, texture, src_rect_ptr, dst_rect_ptr)`
  - Raw SDL textured quad draw call.
- `sdl3.DestroyTexture(texture)`
  - Raw SDL texture destruction call.
- `sdl3.clear(r, g, b, a)`
  - Convenience clear helper that uses the active SDL renderer.

## GPU Helpers

- `sdl3.get_gpu_driver_names()`
  - Returns the SDL GPU backends compiled into the library.
- `sdl3.get_window()`
  - Returns the current `SDL_Window*`.
- `sdl3.get_gpu_device()`
  - Returns the current `SDL_GPUDevice*`.
- `sdl3.get_gl_context()`
  - Returns the current `SDL_GLContext`.
- `sdl3.get_gl_proc_address(name)`
  - Resolves an OpenGL entry point through SDL.
- `sdl3.GetWindowSizeInPixels(window, w_out, h_out)`
  - Raw SDL pixel-size query for windows.
- `sdl3.upload_to_gpu_buffer(device, buffer, data_string)`
  - Uploads raw byte data into an SDL GPU buffer.
  - Raises an error if upload staging or submission fails.
- `sdl3.create_gpu_shader(device, compiled, props?)`
  - Builds an `SDL_GPUShader` from a compiled shader descriptor returned by `shader.compile(...)`.
- `sdl3.build_gpu_buffer_create_info(spec)`
  - Builds `SDL_GPUBufferCreateInfo[1]` from a Lua table.
- `sdl3.build_color_target_descriptions(specs)`
  - Builds `SDL_GPUColorTargetDescription[]` from Lua tables.
- `sdl3.build_graphics_pipeline_create_info(spec)`
  - Builds `SDL_GPUGraphicsPipelineCreateInfo[1]` from a Lua table and keeps any backing arrays alive in the returned bundle.
- `sdl3.resource_scope(device)`
  - Creates an SDL GPU-specific wrapper over `rig.resource_scope(device, "sdl3 resource scope")`.
  - The returned scope still supports the generic `adopt`, `replace`, and `release` methods, plus the SDL-specific helpers below.
- `scope:create_gpu_shader(compiled, props?)`
  - Creates an `SDL_GPUShader` and attaches it to the scope.
- `scope:create_gpu_buffer(create_info)`
  - Creates an `SDL_GPUBuffer` and attaches it to the scope.
  - Accepts either `SDL_GPUBufferCreateInfo[1]` or a Lua table matching `sdl3.build_gpu_buffer_create_info(...)`.
- `scope:create_graphics_pipeline(create_info)`
  - Creates an `SDL_GPUGraphicsPipeline` and attaches it to the scope.
  - Accepts either `SDL_GPUGraphicsPipelineCreateInfo[1]` or a Lua table matching `sdl3.build_graphics_pipeline_create_info(...)`.
- `scope:create_depth_texture(width, height, format?)`
  - Creates a depth texture and attaches it to the scope.
- `scope:adopt(resource, release_fn)`
  - Attaches an existing resource to the scope with a custom release function.
- `scope:replace(key, resource, release_fn)`
  - Replaces a previously tracked named resource, releasing the old one immediately before storing the new one.
- `scope:release()`
  - Releases all tracked resources in reverse order.
- `sdl3.build_vertex_buffer_descriptions(buffers)`
  - Builds `SDL_GPUVertexBufferDescription[]` from Lua tables.
- `sdl3.build_vertex_attributes(attributes)`
  - Builds `SDL_GPUVertexAttribute[]` from Lua tables.
- `sdl3.build_vertex_input_state(layout)`
  - Builds a full `SDL_GPUVertexInputState` plus the backing FFI arrays it points to.
- `sdl3.choose_depth_format(device)`
  - Selects a supported depth format for the current device.
  - Raises an error if no supported depth format exists.
- `sdl3.create_depth_texture(device, width, height, format?)`
  - Creates a depth texture suitable for render passes.
  - Raises an error if no suitable format exists or SDL texture creation fails.

## Notes

- The SDL runtime presets report backend diagnostics before GPU device creation when SDL rejects the requested shader format/backend combination.
- On Linux, SDL GPU currently means Vulkan. Old Intel Haswell systems often expose only partial Vulkan support and may still be rejected.
- The `sdl3_gpu` preset also provides the `mesh3d.vertex_input` service, so `mesh3d.build_vertex_input(mesh)` returns an SDL GPU vertex-input descriptor under that runtime.
