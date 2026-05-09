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
- `sdl3.render_frame()`
  - Calls `sdl3.callback.on_render()` and presents the frame.
- `sdl3.shutdown()`
  - Destroys owned renderer/window state and releases initialized SDL subsystems.
- `sdl3.run()`
  - Convenience wrapper around `setup`, the event/render loop, and `shutdown`.

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
- `sdl3.create_gpu_shader(device, compiled, props?)`
  - Builds an `SDL_GPUShader` from a compiled shader descriptor returned by `shader.compile(...)`.
- `sdl3.build_vertex_buffer_descriptions(buffers)`
  - Builds `SDL_GPUVertexBufferDescription[]` from Lua tables.
- `sdl3.build_vertex_attributes(attributes)`
  - Builds `SDL_GPUVertexAttribute[]` from Lua tables.
- `sdl3.build_vertex_input_state(layout)`
  - Builds a full `SDL_GPUVertexInputState` plus the backing FFI arrays it points to.
- `sdl3.choose_depth_format(device)`
  - Selects a supported depth format for the current device.
- `sdl3.create_depth_texture(device, width, height, format?)`
  - Creates a depth texture suitable for render passes.

## Notes

- `sdl3.setup_gpu()` reports backend diagnostics before device creation when SDL rejects the requested shader format/backend combination.
- On Linux, SDL GPU currently means Vulkan. Old Intel Haswell systems often expose only partial Vulkan support and may still be rejected.
