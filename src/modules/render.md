# render

`render` provides the backend-neutral entity (a mesh-rendering scene node) and the
`render.mesh` capability used to compose renderable meshes into a `scene` runtime.

It is the interface half of a two-part split: `render` owns mesh instances and
rendering, while backend modules (currently `sdl3x`) provide `render.mesh`
factories that own shaders, pipelines, and buffers. Transform animation is not
hard-coded into entities: they accept `motion` contributors (see `motion.md`), and
the `scene.Node` base class composes them. The camera lives on the scene, so all
entities share one view. User code names only `render` and `scene`, and picks a
backend through the bundle it attaches.

## Exports

- `render.Entity`
  - A `scene.Node` that renders a mesh. It inherits its parent's world transform and
    composes any attached motions through the base `scene.Node` transform pipeline.
  - On top of the `scene.Node` API (`add_child`, `remove_child`, `set_local_matrix`,
    `add_motion`, `parent`, `children`), it exposes:
    - `entity:set_motions(motions)` — installs a single motion, a list of motions,
      or none.
    - `entity:draw_node(surface, world, frame)` — combines `world` with the
      scene's view/projection and dispatches to the backend drawable.
    - `entity:release()` — drops backend references.
- `render.plugin(spec?)`
  - Returns a runtime plugin declaring the `render.mesh`, `render.texture`, and
    `render.target` capabilities.
  - `spec.id` overrides the default `"render"` plugin id.
- `render.texture(options?)`
  - A backend-neutral texture value. `options.image` (or a decoded image passed
    directly) is required: a `{ width, height, channels, pixels }` table, such as
    the result of `asset.image`. `pixels` is top-down RGBA8, so texture coordinate
    `(0, 0)` is the image's top-left.
  - `options.name` labels the value; `options.filter` is `"linear"` (default) or
    `"nearest"`; `options.wrap` is `"repeat"` (default), `"clamp"`, or `"mirror"`.
  - The value is uploaded lazily by the backend `render.texture` factory; one
    backend texture is shared per value.
- `render.target(options?)`
  - A backend-neutral offscreen surface a pass renders into and a material samples.
    `options.width`/`options.height` size it (default 512x512); `options.depth`
    (default true) attaches a depth buffer; `options.filter` (default `"linear"`)
    and `options.wrap` (default `"clamp"`) control sampling.
  - The backend `render.target` factory creates one `SDL_GPU`/GL surface per value and
    exposes it as `.texture`, a texture handle usable as a `render.material` texture.
    `scene.RenderScene:render_to(target, draw)` renders into it and
    `draw_fullscreen` consumes it.
- `render.entity_component(plugin, options)`
  - Composes a mesh entity and adds it to the scene root as a child.
  - Requires `render.scene` and `render.mesh`.
  - `options.name` binds the entity into `ctx`.
  - `options.mesh` (required) is a mesh table such as `mesh.make_cube(...)`.
  - `options.material` is an optional `render.material` drawn with the mesh.
  - `options.motion` is a motion (or list of motions) from the `motion` module;
    omitted means no animation. See `motion.md`.
  - Configuration is validated through a schema at compile time.
- `render.material(options)`
  - Describes the shader used to draw a mesh. Passing no material selects the
    backend's built-in unlit position/color material.
  - `options.vertex` and `options.fragment` (optional, but together) are GLSL source
    strings that consume the same `u_mvp`/camera uniform contract as the built-in
    material.
  - `options.texture` is an optional `render.texture`, `render.target`, already-
    created backend texture handle, or a decoded image (which is wrapped
    automatically). When present, the backend binds it to texture/sampler slot 0.
    The built-in textured material samples it through a `u_texture` uniform using
    the mesh's UV attribute; custom shaders receive the same binding contract.
  - A material needs either shader sources or a texture.
  - `options.name` labels the material (used in shader source names);
    `options.language` defaults to `"glsl"`.

## Backend factories

A `render.mesh` provider is a table with `create(mesh, material) -> drawable`:

```lua
{
   create = function(mesh, material)
      -- material is nil for the built-in unlit material, or a `render.material`.
      return {
         draw = function(self, surface, mvp)
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

A `render.texture` provider is a table with `create(texture) -> handle`, where the
handle exposes `:bind(unit)` (GL) or `:bind(pass, slot)` (GPU), plus `width` and
`height`. Mesh factories resolve it from the composition; a mesh factory without a
`render.texture` provider simply cannot draw textured materials.

A `render.target` provider is a table with `create(target) -> handle`, where the
handle exposes `width`, `height`, `flip_v` (whether the sampled texture is bottom-up
and needs a clip-space Y flip when rendering into it), `texture` (a texture handle),
and backend render fields. `scene.RenderScene:render_to` and the mesh factories both
resolve the same handle, so the surface a pass renders into is the texture a later
material samples.

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
   motion = motion.spin { x = 0.7, y = 1.0 },
}))
builder:execute(sdl3x.App):compile():start()
```

Switching `bundle_sdl3_gl` for `bundle_sdl3_gpu` is the only change: the compiler
resolves the matching scene implementation and mesh factory from the composition.