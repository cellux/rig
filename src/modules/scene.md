# scene

`scene` provides a backend-agnostic render container and the `render.scene`
capability used to compose drawables into a runtime.

It is intentionally separate from the legacy `scenegraph` module: `scenegraph` is a
tree of retained objects with its own activation and drawing traversal, while `scene`
is a thin per-frame container that backend components can specialize.

## Exports

- `scene.RenderScene`
  - Base container class. Instances expose `graphics`, `background_color`,
    `drawables`, and `name`.
  - `surface:add(drawable)` — appends a drawable (any table with a `draw` method) and
    returns it.
  - `surface:remove(drawable)` — removes a drawable, returning `true` when it was
    present.
  - `surface:render(...)` — calls `begin_frame(...)`, then `drawable:draw(surface, ...)`
    for each drawable in insertion order, then `end_frame(...)`.
  - `surface:begin_frame(...)` / `surface:end_frame(...)` — no-op hooks that backend
    specializations override (for example to set the viewport and clear the
    framebuffer for OpenGL).
- `scene.plugin(spec?)`
  - Returns a runtime plugin declaring the `render.scene` capability.
  - `spec.id` overrides the default `"scene"` plugin id.
- `scene.container_component(plugin, options)`
  - Returns a descriptor that provides `render.scene` and requires
    `graphics.context`.
  - `options.name` binds the scene into `ctx`.
  - `options.scene_class` overrides `RenderScene` (for example a backend-specific
    subclass).
  - `options.background_color` is stored on the instance for specializations to use.

## Composition

`render.scene` is a single-slot capability: the frame loop uses the first provider as
the render callback when no explicit `options.render` and no class `render` method are
supplied. Drawables are responsible for their own backend resources and register
themselves with the scene from their component `create` function:

```lua
local scene_plugin = scene.plugin()

builder:use(scene_plugin)
builder:add(scene.container_component(scene_plugin, {
   name = "scene",
   scene_class = MyGlScene,
   background_color = color.rgbaf(0.07, 0.08, 0.11, 1.0),
}))
builder:add(my_mesh_component(scene_plugin, {
   name = "mesh",
   -- parameters are validated at compile time and resolved into the exact backend.
}))
```

The runtime's frame component specializes the assembly: capability resolution selects
the graphics backend, the compiler validates each component's parameters, and startup
acquires resources provider-first. The builder itself contains only declarations.