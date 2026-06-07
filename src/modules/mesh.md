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
- `mesh.build_vertex_input(mesh)`
  - Resolves the active `mesh.vertex_input` service provider and translates a provider-neutral mesh layout into a provider-specific vertex-input descriptor.
  - Requires an active runtime.

## `make_cube` Options

- `size`
  - Full cube size.
  - Defaults to `2.0`, matching coordinates in the `[-1, 1]` range.
- `colors`
  - Either `"face"` for the builtin six-face color set, or a table of six `{r, g, b}` colors.

## Notes

- The current cube is emitted as 36 non-indexed vertices so each face can carry its own color cleanly.
- This module is meant to complement `mathx`:
  - `mathx` handles transforms
- `mesh` handles geometry generation
- `mesh` owns the `mesh.vertex_input` service namespace.
  - The `sdl3_gpu` runtime preset installs one provider that returns SDL GPU vertex-input state objects.
