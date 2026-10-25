# scene

`scene` provides the backend-agnostic render scene and its transform tree, plus the
`render.scene` capability used to compose entities into a runtime. Implementations of
the scene interface are selected by the runtime, so user code names only the
interface.

`scene` is a lightweight per-frame transform tree that backend modules specialize;
resource ownership lives at the application level (`app.App:own` and
`rig.ResourceScope`).

## Exports

- `scene.Node`
  - Base transform-tree node. Instances expose `parent`, `children`, `motions`,
    `local_matrix`, `local_transform`, and `world_matrix`.
  - `node:add_child(child)` / `node:remove_child(child)`
  - `node:set_local_matrix(matrix)` — copies `matrix` into the node's local
    transform.
  - `node:add_motion(motion)` / `node:remove_motion(motion)` / `node:clear_motions()`
    — manage transform contributors (see `motion`). Motions are pre-multiplied in
    list order, so `local = m1 * m2 * ... * base` and a spin rotates a node about
    its own origin.
  - `node:build_local(out, frame)` — produces the local transform: the stored base
    matrix with each motion applied. `frame` is `{ time, dt, scene, surface }`.
  - `node:step(surface, frame)` — per-frame hook, called before the transform is
    computed; behavior that accumulates state lives here.
  - `node:draw_node(surface, world, frame)` — draws the node's own content in world
    space; base is a no-op.
  - `node:render_tree(surface, parent_world, frame)` — computes
    `world = parent_world * local`, draws the node, then renders children.
  - `node:render_children(surface, frame)` — renders direct children using this
    node's `world_matrix` as their parent.
- `scene.RenderScene`
  - A `scene.Node` and the root of the transform tree. Instances expose `graphics`,
    `background_color`, `camera`, `lighting`, `width`, `height`, `name`, `clock`,
    `time`, `dt`, `on_update`, and `on_draw`.
  - The scene is the single source of frame time: `clock` is an optional object with
    `:monotonic()`, and `advance_time()` accumulates `time`/`dt` from it. Without a
    clock the scene stays frozen at time 0 (useful for stills and tests).
  - `surface:frame()` — builds the frame context `{ scene, surface, time, dt }`
    handed to motions, behaviors, and callbacks.
  - `surface:set_camera(camera)` — installs `{ eye, target, up, fov_degrees, near,
    far }` (defaults to a left-handed camera at `(0, 0, -4.5)` looking at the
    origin).
  - `surface:set_lighting(lighting)` — installs or clears a `render.lighting` value
    used by the built-in lit material. The scene does not interpret the table; the
    backend material does.
  - `surface:update_view_projection()` — recomputes the shared view*projection for
    the current viewport; called once per frame.
  - `surface:view_projection()` — the view*projection matrix drawables combine with
    their world matrix.
  - `surface:push_transform(matrix?)` / `surface:pop_transform()` /
    `surface:current_transform()` — a world-transform stack for immediate drawing.
    Pushing multiplies the current transform by `matrix` (a child transform).
  - `surface:draw_mesh(mesh, transform?, material?)` — immediately draws `mesh` with
    `world = current_transform * transform` and the scene's view/projection. Pass a
    `render.material` to override the built-in unlit material. Must run while the
    backend frame is open, for example from an `on_draw` hook. Backend drawables are
    created lazily from the resolved `render.mesh` factory and cached per
    `(mesh, material)` (`surface:mesh_drawable(mesh, material?)`).
  - `surface:draw_fullscreen(material)` — draws `material` over the whole viewport
    with an identity transform (ignoring the camera), using a lazily-created
    clip-space quad (`mesh.make_fullscreen_quad`). This is the final screen-space
    pass that consumes a render target's texture.
  - `surface:draw_screen(mesh, x, y, width, height, material?)` — immediately draws
    `mesh` (typically a unit-sized `mesh.make_quad`) into a screen-space pixel
    rectangle with a top-left origin, for overlays and HUDs. It lands at clip z = 0,
    so drawing it last passes the depth test.
  - `surface:render_to(target, draw, options?)` — renders `draw(frame)` into a
    `render.target` value as an offscreen pass, sizing the view/projection to the
    target, then restores the window target and camera. `options.camera` temporarily
    replaces the scene camera for the pass, which supports planar/mirror passes such
    as `render_to(reflection_target, draw, { camera = mirrored_camera })`; the
    camera is restored afterwards. Returns the target handle whose `.texture` can be
    sampled afterwards. Backend scenes override `enter_target(handle)` /
    `leave_target(handle)` to switch surfaces; the base scene has no offscreen
    surface.
  - `surface:render(...)` — advances time, calls `on_update(frame)`, calls
    `begin_frame(...)`, updates the view/projection, calls `on_draw(frame)`, renders
    its children, calls `on_overlay(frame)`, then `end_frame(...)`. Backend frame
    arguments are forwarded to `begin_frame`/`end_frame`.
  - `surface:begin_frame(...)` / `surface:end_frame(...)` — no-op hooks that backend
    implementations override (for example to set the viewport and clear the
    framebuffer for OpenGL, or to open/close a GPU render pass).
  - `options.clock` supplies the animation clock; `options.on_update` and
    `options.on_draw` are `function(frame)` hooks; `options.on_overlay` runs after
    the children for overlays.
- `scene.plugin(spec?)`
  - Returns a runtime plugin declaring the `render.scene` and `render.scene.impl`
    capabilities.
  - `spec.id` overrides the default `"scene"` plugin id.
  - Also declares `render.mesh`, `render.target`, and `sched.clock` so optional
    requirements resolve when the composition does not provide them.
- `scene.container_component(plugin, options)`
  - Returns a descriptor that provides `render.scene`, requires `graphics.context`,
    and optionally requires `sched.clock`.
  - `options.name` binds the scene into `ctx`.
  - `options.background_color` is stored on the instance for implementations to use.
  - `options.camera` is the scene camera (viewed by every entity).
  - `options.lighting` is an optional `render.lighting` value for the built-in lit
    material.
  - `options.clock` (or the resolved `sched.clock` capability) drives `time`/`dt`.
  - The composition's `render.mesh` factory is resolved into `mesh_factory` so the
    scene can draw meshes immediately; it is optional.
  - The composition's `render.target` factory is resolved into `target_factory` so
    `render_to` can create offscreen surfaces; it is optional.
  - `options.on_update` / `options.on_draw` are `function(frame)` hooks.
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