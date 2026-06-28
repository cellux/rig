# `gl`

Minimal raw OpenGL binding for Rig.

This module does not create windows or contexts. It expects the `sdl3_gl` runtime mode to have already created a current OpenGL context.

`gl` owns the `"gl.resolver"` runtime service, which supplies `get_gl_proc_address(name)` for resolving OpenGL entry points.

## API

- Raw OpenGL constants defined by `gl.c`
- Raw OpenGL entry points resolved lazily on first access
  - Example: `gl.Viewport(...)`, `gl.BufferData(...)`, `gl.UseProgram(...)`
- Service ownership:
  - `gl` owns the `"gl.resolver"` runtime service namespace

The module lazily resolves OpenGL entry points through the active `"gl.resolver"` service on first access.

## Notes

- High-level OpenGL helpers live in `glx`.
- The `sdl3_gl` runtime mode provides the `shader.stage` service.
  - `shader.create_stage{ language="glsl", ... }` returns `glx.Shader` objects.
- Context creation and buffer swapping remain owned by the `sdl3_gl` runtime mode.
- Accessing OpenGL functions still requires an active current OpenGL context.
