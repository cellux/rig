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
  - Calls `hooks.render()` and presents the frame.
- `sdl3.shutdown()`
  - Destroys owned renderer/window state and releases initialized SDL subsystems.
- `sdl3.run()`
  - Convenience wrapper around `setup`, the event/render loop, and `shutdown`.

## Hooks

The module uses the global `hooks` table for application policy.

- `hooks.sdl_init_flags`
  - Defaults to `sdl3.INIT_VIDEO + sdl3.INIT_EVENTS`.
- `hooks.create_window() -> window_ptr | nil, err`
  - Defaults to `SDL_CreateWindowWithProperties`.
- `hooks.create_renderer(window_ptr) -> renderer_ptr | nil, err`
  - Defaults to the normal SDL renderer path.
- `hooks.render()`
  - Called by `sdl3.render_frame()`.
- `hooks.handle_key(key_info)`
  - Called by `sdl3.pump_events()` for keyboard events.

User scripts may override these before entering the loop.

## Window Properties

- `sdl3.default_window_props`
  - Default property table used by the builtin `hooks.create_window`.
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
- `sdl3.choose_depth_format(device)`
  - Selects a supported depth format for the current device.
- `sdl3.create_depth_texture(device, width, height, format?)`
  - Creates a depth texture suitable for render passes.

## Notes

- `sdl3.setup_gpu()` reports backend diagnostics before device creation when SDL rejects the requested shader format/backend combination.
- On Linux, SDL GPU currently means Vulkan. Old Intel Haswell systems often expose only partial Vulkan support and may still be rejected.
