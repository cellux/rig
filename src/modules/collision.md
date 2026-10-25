# `collision`

Backend-agnostic static collision for ground-constrained walking.

Shapes live on the `XZ` plane. The player is a circle in that plane; a vertical
capsule reduces to the same circle because the walk controller has a fixed eye
height and does not jump. Collision data is authored separately from render
meshes and may be much simpler.

## World

- `collision.world()` / `collision.World`
  - Creates an empty static world.
- `world:add(shape)`
  - Adds a shape created by one of the constructors below. Returns the shape.
- `world:add_circle(options)`
- `world:add_box(options)`
- `world:add_segment(options)`
- `world:add_polygon(options)`
- `world:add_all(shapes)`
- `world:clear()` / `world:count()`

## Shapes

- `collision.circle { x, z, radius }`
- `collision.box { x, z, width, depth, angle? }`
  - `x`/`z` is the centre; `angle` is a rotation around Y in radians. A zero angle
    is an axis-aligned box.
- `collision.segment { from = { x, z }, to = { x, z }, radius?, thickness? }`
  - `thickness` is the full wall thickness (`radius = thickness / 2`).
- `collision.polygon { points = { { x, z }, ... } }`
  - At least three non-collinear points. Convex polygons are recommended; the
    inside/outside and nearest-edge tests also work for simple concave polygons.
  - Outward normals are derived from the polygon winding, so either winding is
    accepted.

All constructors validate their input and precompute AABB bounds for broadphase
checks.

## Moving a circle

- `world:sweep_circle(x, z, dx, dz, radius?, options?)`
  - Returns `x, z, hit`.
  - Movement is split into adaptive substeps tied to the player radius, then any
    penetration is resolved against the deepest overlapping shape. This prevents
    tunnelling through thin walls even at high speed and slides naturally along
    walls and around columns.
  - `options.max_step` overrides the substep size (default
    `max(radius * 0.5, 0.05)`).
  - `options.iterations` and `options.final_iterations` control depenetration.
- `world:resolve_circle(x, z, radius?, iterations?)`
  - Pushes an already-overlapping circle out of the static shapes. Returns
    `x, z, resolved`.
- `world:move(position, dx, dz, options?)`
  - Moves a position table in place and returns `position, resolved`.
  - `position` may be an array (`position[1]`, `position[3]`) or a table with
    `position.x`/`position.z`.
  - `options.radius` is the player radius. `options.capsule = { radius, height }`
    is accepted as a convenience; the XZ projection uses the capsule radius.
- `world:move_capsule(position, dx, dz, options?)`
  - Alias for `move`; vertical capsule extent does not affect the walk plane.

## Debug draw

- `world:debug_mesh(options?)`
  - Returns a `position_color_f32` `"lines"` mesh of disjoint line segments, or
    `nil` when the world is empty. Uses `mesh.make_line_segments`, so separate
    shapes are not connected by stray lines.
  - `options.y` (default `0.02`), `options.circle_segments` (default `20`), and
    `options.color` control the output.

## Notes

- The current broadphase is a per-shape AABB check; this is adequate for the first
  Córdoba route, which has a bounded number of columns and walls. A spatial hash or
  grid can be added later without changing the shape API.
- The collision layer is intentionally independent of rendering. Do not derive it
  from high-resolution render geometry.
- `examples/collision_walk.lua` demonstrates circles, boxes, an oriented box, a
  segment fence, and a polygon plinth with live walk collision and debug lines.
