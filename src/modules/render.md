# render

`render` provides the backend-neutral entity (a mesh-rendering scene node) and the
`render.mesh` capability used to compose renderable meshes into a `scene` runtime.

It is the interface half of a two-part split: `render` owns mesh instances,
transforms, and animation, while backend modules (currently `sdl3x`) provide
`render.mesh` factories that own shaders, pipelines, and buffers. The camera lives
on the scene, so all entities share one view. User code names only `render` and
`scene`, and picks a backend through the bundle it attaches.

## Exports

- `render.Entity`
  - A `scene.Node` that renders a mesh. It owns the mesh instance's `local_matrix`
    and spin animation, and inherits its parent's world transform.
  - On top of the `scene.Node` API (`add_child`, `remove_child`,
    `set_local_matrix`, `parent`, `children`), it exposes:
    - `entity:update(dt)` — advances the spin angles.
    - `entity:step(surface)` — samples the runtime clock and applies `update`.
    - `entity:build_local(out)` — local matrix combined with the spin rotation.
    - `entity:draw_node(surface, world, ...)` — combines `world` with the
      scene's view/projection and dispatches to the backend drawable.
    - `entity:release()` — drops backend references.
- `render.plugin(spec?)`
  - Returns a runtime plugin declaring the `render.mesh` capability.
  - `spec.id` overrides the default `"render"` plugin id.
- `render.entity_component(plugin, options)`
  - Composes a mesh entity and adds it to the scene root as a child.
  - Requires `render.scene` and `render.mesh`.
  - `options.name` binds the entity into `ctx`.
  - `options.mesh` (required) is a mesh table such as `mesh.make_cube(...)`.
  - `options.spin` is `{ x?, y? }` radians per second; defaults to `x = 0.7, y = 1.0`.
  - Configuration is validated through a schema at compile time.

## Backend factories

A `render.mesh` provider is a table with `create(mesh) -> drawable`:

```lua
{
   create = function(mesh)
      return {
         draw = function(self, surface, mvp, ...)
            -- issue the backend draw call
         end,
      }
   end,
}
```

The factory's capability `properties` record its backend (`{ backend = "gl" }`,
`"gpu"`, ...), and the factory creates and owns its resources through a runtime
resource scope. `sdl3x` ships the GL and SDL_GPU factories and bundles them beside
the matching graphics context.

## Trees

Entities are scene nodes, so they nest. A child's world matrix is its parent's
world matrix combined with its own local transform, and the scene renders each
subtree from the root:

```lua
local parent = render.Entity { backend = ..., mesh = ... }
local child = render.Entity { backend = ..., mesh = ... }
child:set_local_matrix(mathx.mat4_translation(mathx.mat4(), 1.0, 0.0, 0.0))
parent:add_child(child)
```

## Example

```lua
local render = require("render")
local scene = require("scene")

local scene_plugin = scene.plugin()
local render_plugin = render.plugin()

sdl3x.bundle_sdl3_gl(builder, { ... })   -- the backend hint
builder:use(scene_plugin)
builder:use(render_plugin)
builder:add(scene.container_component(scene_plugin, {
   name = "scene",
   background_color = color.rgbaf(0.07, 0.08, 0.11, 1.0),
   camera = { eye = { 0.0, 0.0, -4.5 }, fov_degrees = 60.0 },
}))
builder:add(render.entity_component(render_plugin, {
   name = "cube",
   mesh = mesh.make_cube { size = 2.0, colors = ... },
   spin = { x = 0.7, y = 1.0 },
}))
builder:execute(sdl3x.App):compile():start()
```

Switching `bundle_sdl3_gl` for `bundle_sdl3_gpu` is the only change: the compiler
resolves the matching scene implementation and mesh factory from the composition.