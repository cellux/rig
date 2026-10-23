# `gl`

Minimal raw OpenGL binding for Rig.

This module does not create windows or contexts. It expects a current OpenGL context, such as the one created by `sdl3x.bundle_sdl3_gl`.

`gl` resolves OpenGL entry points through a resolver installed on the module; the `gl.resolver` capability supports this via `sdl3x.gl_resolver_component` / `gl.component`.

## API

- Raw OpenGL constants defined by `gl.c`
- Raw OpenGL entry points resolved lazily on first access
  - Example: `gl.Viewport(...)`, `gl.BufferData(...)`, `gl.UseProgram(...)`
- Resolver installation:
  - `gl.set_resolver(provider)` / `gl.clear_resolver()`

The module lazily resolves OpenGL entry points through the installed resolver on first access.

## Notes

- High-level OpenGL helpers live in `glx`.
- `sdl3x.bundle_sdl3_gl` includes the `gl.resolver` capability and `shader.stage`.
  - `shader.create_stage({ language = "glsl", ... }, ctx.shader)` returns `glx.Shader` objects.
- Context creation and buffer swapping remain owned by the graphics context component.
- Accessing OpenGL functions still requires an active current OpenGL context.

## Runtime Components

`gl.plugin([spec])` declares the `gl.resolver` capability for the compositional runtime.

`gl.component(plugin, options)` requires `gl.resolver` and exposes the resolved provider as
`ctx.<name>`. The installed resolver is used by `gl.*` entry points; the `gl`
component also installs a module-level resolver for the duration of the run:

```lua
local gp = gl.plugin()
local compiled = rig.runtime()
   :use(gp)
   :add(provider)
   :add(gl.component(gp, { name = "gl" }))
   :compile()

-- gl.* entry points then resolve through the installed resolver during the run.
```
