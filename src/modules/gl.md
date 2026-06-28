# `gl`

Minimal OpenGL binding for Rig.

This module does not create windows or contexts. It expects the `sdl3_gl` runtime mode to have already created a current OpenGL context.

`gl` owns the `"gl.resolver"` runtime service, which supplies `get_gl_proc_address(name)` for resolving OpenGL entry points.

## API

- `gl.create_shader(shader_type, source)`
  - Compiles a shader and raises on failure.
- `gl.link_program(shaders)`
  - Links a program from one or more compiled shader objects and raises on failure.
- `gl.create_program { vertex_source = ..., fragment_source = ... }`
  - Compiles and links a shader program and raises on failure.
- `gl.buffer_data(target, data, usage)`
  - Uploads a Lua string into the currently bound buffer.
- `gl.get_uniform_location(program, name)`
- `gl.get_version_string()`

The module lazily resolves OpenGL entry points through the active `"gl.resolver"` service on first access.

## Notes

- This first version is intentionally small and targets a modern shader-based OpenGL path.
- Raw OpenGL entry points are also exposed lazily on demand.
  - This includes texture, blending, buffer, vertex-array, draw, and uniform calls used by the `sdl3_gl` font provider.
- The `sdl3_gl` runtime mode provides the `shader.stage` service.
- The `sdl3_gl` runtime mode also provides the `"gl.resolver"` service.
  - `shader.create_stage{ language="glsl", ... }` returns OpenGL shader objects that can be linked through `gl.link_program(...)` or the raw OpenGL entry points.
- Context creation and buffer swapping remain owned by the `sdl3_gl` runtime mode.
- Accessing OpenGL functions still requires an active current OpenGL context.
