# `mesh`

Procedural mesh generators.

This first version is intentionally narrow: it generates CPU-side mesh data in explicit built-in vertex layouts. It does not create SDL GPU objects directly.

## API

- `mesh.make_cube(options?)`
  - Generates a cube mesh in the `position_color_uv_f32` layout.
  - Returns a table containing:
    - `layout`
    - `topology`
    - `vertex_stride`
    - `vertex_count`
    - `attribute_offsets`
    - `vertex_blob`
- `mesh.make_quad(options?)`
  - Centered rectangle in the XY plane facing +Z, with UVs where `(0, 0)` is the
    top-left corner.
  - `size`, or `width`/`height`; `color`; defaults to a 1x1 white quad.
  - `topology = "triangles"`.
- `mesh.make_triangle(options?)`
  - Centered equilateral triangle in the XY plane.
  - `size` (circumscribed diameter), `color`; `topology = "triangles"`.
- `mesh.make_line(options?)`
  - A line segment. Without `from`/`to` it is centered on the origin along +X and
    sized by `length`. `color`; `topology = "lines"`.
- `mesh.make_lines(options?)`
  - A polyline through `points` (an array of `{ x, y, z }`). `color`;
    `topology = "lines"`.
- `mesh.make_grid(options?)`
  - A ground-plane grid on XZ. `size`, `divisions`, `color`; `topology = "lines"`.
- `mesh.make_fullscreen_quad()`
  - A quad spanning clip space (`[-1, 1]` on X/Y) with top-left UVs, drawn with an
    identity transform as a fullscreen pass. `scene.RenderScene:draw_fullscreen`
    uses it.
- `mesh.parse_obj(text, options?)`
  - Parses Wavefront OBJ source into a `position_color_uv_f32` triangle mesh.
    Positions (`v`) and texture coordinates (`vt`) are read; normals and materials
    are ignored because the built-in materials are unlit. Polygons are triangulated
    as fans, and negative indices are resolved relative to the end of each list.
  - `options.color` (default white) tints the whole mesh so a bound texture is
    sampled unchanged. Faces without a texture coordinate get `(0, 0)`.
  - Raises if the source has malformed records or no faces.
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

## Layouts and Topology

Meshes use one of two explicit, interleaved-float layouts:

- `position_color_f32` (stride 24): `position` at 0, `color` at 12. Used by
  generators without meaningful texture coordinates (`make_triangle`, `make_line`,
  `make_lines`, `make_grid`).
- `position_color_uv_f32` (stride 32): `position` at 0, `color` at 12, `uv` at 24.
  Used by textured meshes (`make_quad`, `make_cube`, `parse_obj`).

Every generator also carries a `topology` field: `"triangles"` (default) or
`"lines"` (and `"line_strip"` for backend-specific use). Backend `render.mesh`
factories choose the matching primitive type, so line meshes render as lines rather
than degenerate triangles. The built-in textured material requires a mesh with a UV
attribute.

## Notes

- The current cube is emitted as 36 non-indexed vertices so each face can carry its own color cleanly.
- This module complements `mathx`: `mathx` handles transforms, `mesh` handles
  geometry generation.
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
