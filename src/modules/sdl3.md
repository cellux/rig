# `sdl3`

Lazy SDL3 binding built on LuaJIT FFI.

The SDL shared library is loaded only when the module is required.

## Runtime Integration

When loaded, `sdl3` registers three `rig.run(...)` modes:
- `"sdl3"`
  - Owns the SDL window/renderer lifecycle through `rig.run(...)`.
- `"sdl3_gl"`
  - Owns the SDL window/OpenGL-context lifecycle through `rig.run(...)`.
- `"sdl3_gpu"`
  - Owns the SDL window/GPU-device lifecycle through `rig.run(...)`.

## `rig.run` Options

Use SDL-specific runtime configuration under:
- `options.sdl3` for `mode = "sdl3"`
- `options.sdl3_gl` for `mode = "sdl3_gl"`
- `options.sdl3_gpu` for `mode = "sdl3_gpu"`

Shared fields accepted by the SDL runtime modes as applicable:

- `init_flags`
  - Defaults to `sdl3.INIT_VIDEO + sdl3.INIT_EVENTS`.
- `window_props`
  - Optional window property overrides merged into `sdl3.default_window_props`.
- `create_window(options) -> window_ptr | nil, err`
  - Overrides window creation.
  - Defaults to the builtin `SDL_CreateWindowWithProperties` path.
- `create_renderer(window_ptr) -> renderer_ptr | nil, err`
  - Overrides renderer creation for `mode = "sdl3"`.
  - Defaults to the builtin SDL renderer path.
- `on_render`
  - Mandatory for both modes.
- `on_key(key_info)`
  - Optional keyboard event callback.

Additional fields accepted by `options.sdl3_gl`:

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

Additional fields accepted by `options.sdl3_gpu`:

- `shader_formats`
  - Passed to the SDL GPU runtime mode during device creation.
- `debug_mode`
  - Passed to the SDL GPU runtime mode during device creation.
- `backend_name`
  - Passed to the SDL GPU runtime mode during device creation.

## Window Properties

- `sdl3.default_window_props`
  - Default property table used by the builtin SDL window factory.
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
- `sdl3.get_gl_context()`
  - Returns the current `SDL_GLContext`.
- `sdl3.get_gl_proc_address(name)`
  - Resolves an OpenGL entry point through SDL.
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

- The SDL runtime modes report backend diagnostics before GPU device creation when SDL rejects the requested shader format/backend combination.
- On Linux, SDL GPU currently means Vulkan. Old Intel Haswell systems often expose only partial Vulkan support and may still be rejected.
