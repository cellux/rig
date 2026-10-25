# `mesh`

Procedural mesh generators and index-aware composition.

The module produces CPU-side, backend-neutral mesh data. Backend `render.mesh`
factories turn it into GL/GPU buffers. Existing unlit generators keep their
layouts; architectural generators add normals and (optionally) tangents, and all
new architectural generators emit indexed triangles.

## API

### Basic generators

- `mesh.make_cube(options?)`
  - Non-indexed cube in `position_color_uv_f32` with six face colors.
  - `size` defaults to `2.0`; `colors` is `"face"` or six `color.Color` values.
- `mesh.make_quad(options?)`
  - Centered XY rectangle facing +Z with top-left UVs.
  - `size`, or `width`/`height`; `color`.
- `mesh.make_triangle(options?)`
  - Centered equilateral triangle in the XY plane.
- `mesh.make_line(options?)`
  - Line segment; `from`/`to`, or a centered `length`.
- `mesh.make_lines(options?)`
  - A connected polyline through `points` (an array of `{ x, y, z }`).
- `mesh.make_line_segments(options?)`
  - Disjoint line segments. `points` is a flat array of `{ x, y, z }` entries in
    pairs; unlike `make_lines`, consecutive pairs are not connected.
- `mesh.make_grid(options?)`
  - Ground-plane grid on XZ; `size`, `divisions`, `color`.
- `mesh.make_fullscreen_quad()`
  - Clip-space quad with top-left UVs for fullscreen passes.
- `mesh.parse_obj(text, options?)`
  - Parses OBJ positions and UVs into a non-indexed
    `position_color_uv_f32` triangle mesh. Normals and materials are ignored;
    polygons are triangulated as fans; negative indices are supported.

### Architectural generators

All architectural generators emit indexed `position_normal_color_uv_f32`
triangles unless the builder is asked for another layout.

- `mesh.make_box(options?)`
  - Centered box with per-face normals and UVs.
  - `size`, or `width`/`height`/`depth`; `center`; `color` or a six-entry
    `colors` table; `uv_scale`.
- `mesh.make_cylinder(options?)`
  - Cylinder or truncated cone along Y, centered on `center`.
  - `radius`, `top_radius`, `height`, `segments`, `caps`, `color`, `uv_scale`.
- `mesh.make_capital(options?)`
  - Flared capital (truncated cone) with an optional square abacus, built upward
    from `y = 0`.
  - `radius`, `top_radius`, `height`, `abacus_height`, `abacus_width`,
    `segments`, `color`, `abacus_color`.
- `mesh.make_column(options?)`
  - Column assembled from an optional base, shaft, and optional capital. The
    returned mesh starts at `y = 0`; `height` is the shaft height.
  - `radius`, `height`, `base_height`, `base_radius`, `capital_height`,
    `capital_radius`, `abacus_height`, `abacus_width`, `segments`, colors.
- `mesh.make_arch_ring(options?)`
  - Curved arch band in the XY plane, extruded along Z.
  - `radius`, `thickness`, `depth`, `segments`, `start_angle`, `end_angle`
    (radians; +X is 0), `color`, `stripe_colors`, `stripe_size`.
  - Defaults span a round upper half-arch (`0` to `pi`).
- `mesh.make_round_arch(options?)`
  - `make_arch_ring` with defaults `0` to `pi`.
- `mesh.make_horseshoe_arch(options?)`
  - `make_arch_ring` with defaults `-20°` to `200°`, producing a horseshoe that
    extends below the spring line.
- `mesh.make_pointed_arch(options?)`
  - A two-centred pointed (Gothic) arch ring in the XY plane, extruded along Z.
  - `span` (clear opening; `width` is accepted as an alias), `radius` (must be at
    least half the span; larger values point more sharply), `thickness`, `depth`,
    `segments`, `color`, `stripe_colors`, `stripe_size`. The spring line is at
    `y = 0` and the mesh is centered on X.
- `mesh.make_voussoir_band(options?)`
  - `make_arch_ring` with alternating red/cream stripes by default.
- `mesh.make_wall(options?)`
  - Rectangular wall in the XY plane from `y = 0` to `height`, centered on X,
    extruded through `thickness` on Z.
  - `openings` are rectangular holes measured from the wall's left edge and
    bottom: `{ x, y, width, height }`. The generator cuts the front/back faces
    into a grid and adds reveal faces around each opening.
  - `color`, `reveal_color`, `uv_scale`, `center_z`.
- `mesh.make_floor_bay(options?)` / `mesh.make_floor`
  - Indexed XZ floor grid centered on the origin at `y = 0`.
  - `width`, `depth`, `segments`, or `segments_x`/`segments_z`; `color`,
    `uv_scale`.
- `mesh.make_barrel_vault(options?)`
  - Hollow barrel-vault section with its axis along Z.
  - `radius`, `thickness`, `length`, `segments`, `start_angle`, `end_angle`,
    `color`, `uv_scale`. The default span is the upper half (`0` to `pi`).
- `mesh.make_dome(options?)`
  - Hollow half-ellipsoid dome of revolution around Y, springing at `y = 0` and
    opening downward so the concave inner surface faces the interior.
  - `radius`, `height` (defaults to `radius`), `thickness`, `segments` (around),
    `rings` (base to apex), `color`, `uv_scale`.
- `mesh.make_grille(options?)`
  - Flat ironwork grille/reja panel in the XY plane from `y = 0` to `height`,
    centered on X and extruded through `depth` on Z.
  - `width`, `height`, `depth`, `frame_size`, `bar_size`, `spacing`, `rails`
    (horizontal crossbars; default `2`), `frame_color`, `bar_color`, `color`.
- `mesh.make_railing(options?)`
  - Balustrade running along X, centered on the origin, from `y = 0` to `height`:
    a base rail, evenly spaced turned balusters (cylinders), and a cap rail.
  - `length`, `height`, `depth`, `baluster_radius`, `spacing`, `base_height`,
    `cap_height`, `cap_color`, `color`.
- `mesh.make_pew(options?)`
  - Bench pew facing +Z: seat, backrest on the `-Z` side, closed end panels, and
    an optional foot/kneeler rail. Built from `y = 0` to `back_height` and
    centered on X.
  - `length`, `seat_height`, `seat_depth`, `seat_thickness`, `back_height`,
    `back_thickness`, `panel_thickness`, `kneeler`, `seat_color`, `back_color`,
    `color`.

### Composition

- `mesh.builder(options?)`
  - Returns a merge builder. Every `:add` becomes one material range.
  - `options.layout` selects an explicit target layout.
  - Otherwise: `normals = false` selects `position_color_uv_f32`;
    `tangents = true` selects `position_normal_tangent_color_uv_f32`; the default
    is `position_normal_color_uv_f32`.
  - `options.generate_normals = false` preserves supplied normals and leaves
    missing normals at `(0, 1, 0)`. `options.generate_tangents = false` does the
    same for tangents. Generation is on by default when the target layout has the
    attribute.
- `builder:add(mesh, options?)`
  - Merges a triangle mesh. Options:
    - `transform` — a `float[16]` column-major matrix; positions and normals are
      transformed, including inverse-transpose handling for non-uniform scale.
    - `material` — stored in the emitted range (the backend may ignore it).
    - `name` — labels the range.
    - `color` — tints every vertex of this section.
    - `uv_scale`, `uv_offset_u`, `uv_offset_v` — adjust the source UVs.
  - Returns the builder for chaining.
- `builder:add_mesh(mesh, options?)` — alias for `:add`.
- `builder:build()`
  - Returns one indexed mesh plus `material_ranges`/`sections`.
  - Each range has `index_offset` (zero-based), `index_count`, `vertex_offset`,
    `vertex_count`, `name`, and `material`.
  - Generated normals are smooth over shared vertices; generated tangents are
    orthogonalized against the normal.
- `mesh.merge(parts, options?)`
  - Convenience around the builder:
    `mesh.merge({ { mesh = a, material = mat_a }, { mesh = b } })`.
- `mesh.partition(mesh, classify, options?)`
  - Splits an indexed triangle mesh into per-key submeshes. `classify(centroid_x,
    centroid_y, centroid_z)` returns the bucket key; triangles returning `nil` are
    dropped. Vertex sharing is preserved within each bucket and the source layout
    is kept.
  - Returns `buckets` (key → mesh) and `order`, the keys in first-seen order.
  - `options.layout` overrides the output layout. This is the primitive behind
    scene zone culling: build one mesh, partition it by spatial region, and draw
    only the visible regions.

### Runtime components

- `mesh.build_vertex_input(mesh, provider)`
  - Dispatches through a `mesh.vertex_input` provider.
- `mesh.plugin([spec])`
  - Declares `mesh.vertex_input`.
- `mesh.component(plugin, options)`
  - Requires `mesh.vertex_input` and exposes a bound facade as `ctx.<name>`.
- `mesh.bind(provider)`
  - Wraps a provider for custom runtimes.

## Layouts

`mesh.layouts` and `mesh.layout(name)` expose the built-in layouts. Attribute
locations are stable across layouts:

| role | location | components |
| --- | ---: | ---: |
| position | 0 | 3 |
| color | 1 | 3 |
| uv | 2 | 2 |
| normal | 3 | 3 |
| tangent | 4 | 4 |

Built-in layouts:

- `position_color_f32` (stride 24): position 0, color 12.
- `position_color_uv_f32` (stride 32): position 0, color 12, uv 24.
- `position_normal_color_uv_f32` (stride 44): position 0, normal 12, color 24,
  uv 36.
- `position_normal_tangent_color_uv_f32` (stride 60): position 0, normal 12,
  tangent 24, color 40, uv 52.

Every mesh also carries `topology` (`"triangles"`, `"lines"`, or
`"line_strip"`), `vertex_stride`, `vertex_count`, `attribute_offsets`, and
`vertex_blob`.

## Indexed geometry

When a mesh has `index_blob`, it also carries:

- `index_count`
- `index_type` — `"uint32"` (generators and builder) or `"uint16"` (supported by
  the backends)
- `index_stride` — currently `4` for uint32 meshes

Index buffers are zero-based. GL factories bind an element-array buffer and use
`glDrawElements`; SDL GPU factories create an index buffer and use
`SDL_DrawGPUIndexedPrimitives`. Non-indexed meshes keep using array draws.

`material_ranges` are metadata for a future multi-material path; the current
unlit material draws the whole merged mesh with one draw call.

## Notes

- Existing non-indexed unlit generators remain valid and unchanged.
- The legacy cube still emits 36 non-indexed vertices so each face can carry its
  own color cleanly; use `make_box` for indexed geometry with normals.
- Backend `render.mesh` factories select the primitive type from `topology`.
- The built-in textured material requires a UV attribute. The built-in lit material
  requires a normal attribute; normal-mapped lit materials also require tangents.
- Use `mesh.builder { tangents = true }` when a lit mesh will carry a
  `normal_texture`.
- `mesh` declares the `mesh.vertex_input` capability. The SDL GPU provider
  translates the layout registry into pipeline vertex attributes; the GL factory
  binds the same roles directly.
