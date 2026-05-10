# `sdl3`

Lazy SDL3 binding built on LuaJIT FFI.

The SDL shared library is loaded only when the module is required.

## Lifecycle

- `sdl3.setup()`
  - Initializes SDL and creates the window and renderer.
- `sdl3.setup_gpu(options?)`
  - Initializes SDL, creates the window, creates an `SDL_GPUDevice`, and claims the window for it.
- `sdl3.pump_events()`
  - Dispatches queued SDL events.
  - Returns `false` after a quit event.
- `sdl3.render_frame(render_fn)`
  - Calls `render_fn()` and then presents through the SDL renderer.
- `sdl3.render_gpu_frame(render_fn)`
  - Acquires a GPU command buffer and swapchain texture, calls `render_fn(command_buffer, swapchain_texture, width, height)`, and submits the frame.
- `sdl3.shutdown()`
  - Destroys owned renderer/window state and releases initialized SDL subsystems.
- `sdl3.run(options?)`
  - Convenience wrapper around setup, the event loop, and shutdown.
  - `mode = "renderer"` uses `sdl3.setup()` and `sdl3.render_frame(sdl3.callback.on_render)` each frame.
  - `mode = "gpu"` uses `sdl3.setup_gpu(options.gpu)` and calls `sdl3.render_gpu_frame(sdl3.callback.on_render)` each frame.

## Extension Points

The module exposes SDL-specific user extension points through nested tables:

- `sdl3.config.init_flags`
  - Defaults to `sdl3.INIT_VIDEO + sdl3.INIT_EVENTS`.
- `sdl3.config.window_props`
  - Optional window property overrides merged into `sdl3.default_window_props`.
- `sdl3.factory.create_window() -> window_ptr | nil, err`
  - Defaults to `SDL_CreateWindowWithProperties`.
- `sdl3.factory.create_renderer(window_ptr) -> renderer_ptr | nil, err`
  - Defaults to the normal SDL renderer path.
- `sdl3.callback.on_render()`
  - Called by `sdl3.render_frame()`.
- `sdl3.callback.on_key(key_info)`
  - Called by `sdl3.pump_events()` for keyboard events.

## Window Properties

- `sdl3.default_window_props`
  - Default property table used by the builtin `sdl3.factory.create_window`.
- `sdl3.build_properties(props)`
  - Converts a Lua table into `SDL_PropertiesID`.
- `sdl3.destroy_properties(properties_id)`
  - Releases a properties object built through SDL.

## GPU Helpers

- `sdl3.get_gpu_driver_names()`
  - Returns the SDL GPU backends compiled into the library.
- `sdl3.get_window()`
  - Returns the current `SDL_Window*`.
- `sdl3.get_gpu_device()`
  - Returns the current `SDL_GPUDevice*`.
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
  - Creates a scope object that tracks SDL GPU resources and releases them in reverse creation order.
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

- `sdl3.setup_gpu()` reports backend diagnostics before device creation when SDL rejects the requested shader format/backend combination.
- On Linux, SDL GPU currently means Vulkan. Old Intel Haswell systems often expose only partial Vulkan support and may still be rejected.
