# scene

`scene` provides the backend-agnostic render scene and its transform tree, plus the
`render.scene` capability used to compose entities into a runtime. Implementations of
the scene interface are selected by the runtime, so user code names only the
interface.

It is intentionally separate from the legacy `scenegraph` module: `scenegraph` is a
retained-object tree with its own activation and resource lifecycle, while `scene` is
a lightweight per-frame transform tree that backend modules specialize.

## Exports

- `scene.Node`
  - Base transform-tree node. Instances expose `parent`, `children`,
    `local_matrix`, `local_transform`, and `world_matrix`.
  - `node:add_child(child)` / `node:remove_child(child)`
  - `node:set_local_matrix(matrix)` — copies `matrix` into the node's local
    transform.
  - `node:build_local(out)` — produces the local transform; subclasses (e.g.
    `render.Entity`) add animation on top.
  - `node:step(surface)` — per-frame hook, called before the transform is computed.
  - `node:draw_node(surface, world, ...)` — draws the node's own content in world
    space; base is a no-op.
  - `node:render_tree(surface, parent_world, ...)` — computes
    `world = parent_world * local`, draws the node, then renders children.
  - `node:render_children(surface, ...)` — renders direct children using this node's
    `world_matrix` as their parent.
- `scene.RenderScene`
  - A `scene.Node` and the root of the transform tree. Instances expose `graphics`,
    `background_color`, `camera`, `width`, `height`, and `name`.
  - `surface:set_camera(camera)` — installs `{ eye, target, up, fov_degrees, near,
    far }` (defaults to a left-handed camera at `(0, 0, -4.5)` looking at the
    origin).
  - `surface:update_view_projection()` — recomputes the shared view*projection for
    the current viewport; called once per frame.
  - `surface:view_projection()` — the view*projection matrix drawables combine with
    their world matrix.
  - `surface:render(...)` — calls `begin_frame(...)`, `update_view_projection()`,
    renders its children, then `end_frame(...)`.
  - `surface:begin_frame(...)` / `surface:end_frame(...)` — no-op hooks that backend
    implementations override (for example to set the viewport and clear the
    framebuffer for OpenGL, or to open/close a GPU render pass).
- `scene.plugin(spec?)`
  - Returns a runtime plugin declaring the `render.scene` and `render.scene.impl`
    capabilities.
  - `spec.id` overrides the default `"scene"` plugin id.
- `scene.container_component(plugin, options)`
  - Returns a descriptor that provides `render.scene` and requires
    `graphics.context`.
  - `options.name` binds the scene into `ctx`.
  - `options.background_color` is stored on the instance for implementations to use.
  - `options.camera` is the scene camera (viewed by every entity).
  - Without `options.scene_class` the compiler resolves a `render.scene.impl`
    provider from the composition and instantiates it. This is how the runtime wires
    the active graphics backend's scene shape without user code naming it.
  - `options.scene_class` pins a specific `RenderScene` subclass directly and skips
    implementation resolution.
  - `options.backend` optionally constrains both `graphics.context` and
    `render.scene.impl` to the given backend when several are composed.

## Implementation selection

A backend module ships a scene implementation beside the graphics context it owns and
registers a `render.scene.impl` provider whose capability `properties` record the
backend (`{ backend = "gl" }`, `"gpu"`, ...). Bundles add the implementation matching
their graphics backend; `scene.container_component` then resolves that provider at
compile time. The example script therefore only chooses a backend through its bundle
(`bundle_sdl3_gl` versus `bundle_sdl3_gpu`) and never references a concrete scene
class.

## Composition

`render.scene` is a single-slot capability: the frame loop uses the first provider as
the render callback when no explicit `options.render` and no class `render` method are
supplied. Entities are responsible for their own backend resources and register
themselves with the scene from their component `create` function:

```lua
local scene_plugin = scene.plugin()

builder:use(scene_plugin)
builder:add(scene.container_component(scene_plugin, {
   name = "scene",
   background_color = color.rgbaf(0.07, 0.08, 0.11, 1.0),
   camera = { eye = { 0.0, 0.0, -4.5 }, fov_degrees = 60.0 },
}))
builder:add(my_entity_component(scene_plugin, {
   name = "cube",
   -- parameters are validated at compile time and resolved into the exact backend.
}))
```

The runtime's frame component specializes the assembly: capability resolution selects
the graphics backend and its scene implementation, the compiler validates each
component's parameters, and startup acquires resources provider-first. The builder
itself contains only declarations.