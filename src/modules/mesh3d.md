# `mesh3d`

Procedural 3D mesh generators.

This first version is intentionally narrow: it generates CPU-side mesh data in explicit built-in vertex layouts. It does not create SDL GPU objects directly.

## API

- `mesh3d.make_cube(options?)`
  - Generates a cube mesh in the `position_color_f32` layout.
  - Returns a table containing:
    - `layout`
    - `vertex_stride`
    - `vertex_count`
    - `attribute_offsets`
    - `vertex_blob`

When `mesh3d` is loaded, it also installs `sdl3.build_vertex_input_state_from_mesh(mesh)` as a convenience bridge for known `mesh3d` layouts.

## `make_cube` Options

- `size`
  - Full cube size.
  - Defaults to `2.0`, matching coordinates in the `[-1, 1]` range.
- `colors`
  - Either `"face"` for the builtin six-face color set, or a table of six `{r, g, b}` colors.

## Notes

- The current cube is emitted as 36 non-indexed vertices so each face can carry its own color cleanly.
- This module is meant to complement `math3d`:
  - `math3d` handles transforms
  - `mesh3d` handles geometry generation
