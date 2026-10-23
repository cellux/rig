# `mesh`

Procedural mesh generators.

This first version is intentionally narrow: it generates CPU-side mesh data in explicit built-in vertex layouts. It does not create SDL GPU objects directly.

## API

- `mesh.make_cube(options?)`
  - Generates a cube mesh in the `position_color_f32` layout.
  - Returns a table containing:
    - `layout`
    - `vertex_stride`
    - `vertex_count`
    - `attribute_offsets`
    - `vertex_blob`
- `mesh.build_vertex_input(mesh, provider)`
  - Dispatches through a `mesh.vertex_input` provider and translates a provider-neutral mesh layout into a provider-specific vertex-input descriptor.
  - The provider argument is required.

## `make_cube` Options

- `size`
  - Full cube size.
  - Defaults to `2.0`, matching coordinates in the `[-1, 1]` range.
- `colors`
  - Either `"face"` for the builtin six-face color set, or a table of six `color.Color` face colors.
  - Face colors are written into the mesh as normalized RGB floats; alpha is ignored.

## Notes

- The current cube is emitted as 36 non-indexed vertices so each face can carry its own color cleanly.
- This module is meant to complement `mathx`:
  - `mathx` handles transforms
- `mesh` handles geometry generation
- `mesh` declares the `mesh.vertex_input` capability.
  - `sdl3x.mesh_vertex_input_component` provides an SDL GPU provider that returns vertex-input state objects.

## Runtime Components

`mesh.plugin([spec])` declares the `mesh.vertex_input` capability for the compositional runtime.

`mesh.component(plugin, options)` requires `mesh.vertex_input` and exposes a bound facade
as `ctx.<name>`. `mesh.bind(provider)` builds that facade, whose `:build_vertex_input(mesh)`
delegates to the validated `mesh.build_vertex_input(...)` entry point:

```lua
local mp = mesh.plugin()
local compiled = rig.runtime()
   :use(mp)
   :add(provider)
   :add(mesh.component(mp, { name = "mesh" }))
   :execute(function(ctx)
      local vertex_input = ctx.mesh:build_vertex_input(cube)
   end)
   :compile()
```
