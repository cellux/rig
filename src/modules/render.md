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
  - Describes the shader and surface response used to draw a mesh. Passing no
    material selects the backend's built-in unlit position/color material.
  - `options.vertex` and `options.fragment` (optional, but together) are GLSL source
    strings that take precedence over built-in shading and consume the same
    `u_mvp`/camera contract.
  - `options.shading` is `"unlit"` (default) or `"lit"`. A lit material requires a
    mesh with normals; a normal-mapped lit material additionally requires tangents.
  - Material fields:
    - `albedo` — `Color`, default white.
    - `roughness` — `0..1`, default `0.7`.
    - `specular` — `0..1`, default `0.1`.
    - `emissive` — `Color`, default black.
    - `opacity` — `0..1`, default `1`.
    - `alpha_mode` — `"opaque"`, `"blend"`, or `"cutout"`; defaults to `"blend"`
      when `opacity < 1`, otherwise `"opaque"`.
    - `alpha_cutoff` — cutoff for `"cutout"`, default `0.5`.
    - `depth_test` / `depth_write` — booleans, both default `true`.
    - `cull_mode` — `"none"` (default), `"back"`, `"front"`, or
      `"front_and_back"`.
    - `texture_scale` — positive number or `{ u, v }` pair, default `1`. Multiplies
      the base/normal-map UVs, so a shared tiling texture can be reused at different
      world scales.
    - `reflection_strength` — `0..1`, default `0.25` when `reflection_texture` is
      present, otherwise `0`. Controls screen-space planar reflection compositing.
    - `environment_strength` — `0..1`, default `0`. Adds a cheap analytic
      sky/ground environment response for polished stone and metal when planar
      reflection is unavailable.
  - `options.texture` is the optional base-colour map; `options.normal_texture` is
    the optional tangent-space normal/detail map; `options.reflection_texture` is an
    optional screen-space planar reflection map. Each accepts a `render.texture`, a
    `render.target`, an already-created backend texture handle, or a decoded image.
    The base map binds to texture/sampler slot 0, the normal map to slot 1, and the
    reflection map to slot 2 on the GL lit path.
  - A material needs shader sources, a texture, or `shading = "lit"`.
  - `options.name` labels the material; `options.language` defaults to `"glsl"`.
- `render.lighting(options)`
  - Backend-neutral scene lighting for the built-in lit material. Store it with
    `surface:set_lighting(...)` or `options.lighting` in `rig.run` /
    `scene.container_component`.
  - `ambient` — `Color`, default dark neutral.
  - `directional` — `{ direction = { x, y, z }, color = Color, intensity = number }`.
    `direction` points from the surface toward the light and is normalized.
  - `local_lights` — up to `render.MAX_LOCAL_LIGHTS` (`4`) point lights:
    `{ position = { x, y, z }, color = Color, intensity = number, range = number }`.
  - `exposure` — positive multiplier, default `1.0`.
  - `render.default_lighting` is the fallback used when a scene has no lighting.

## Backend factories

A `render.mesh` provider is a table with `create(mesh, material) -> drawable`:

```lua
{
   create = function(mesh, material)
      -- material is nil for the built-in unlit material, or a `render.material`.
      return {
         draw = function(self, surface, mvp, world, frame)
            -- issue the backend draw call
         end,
      }
   end,
}
```

`world` is the object's world matrix (the same matrix that produced `mvp`); lit
materials use it for world-space normals and view direction. It may be `nil` for
screen-space passes.

The factory's capability `properties` record its backend (`{ backend = "gl" }`,
`"gpu"`, ...), and the factory creates and owns its resources through a runtime
resource scope. `sdl3x` ships the GL and SDL_GPU factories and bundles them beside
the matching graphics context.

A mesh with `index_blob`/`index_count`/`index_type` is drawn with indexed
primitives (`glDrawElements` or `SDL_DrawGPUIndexedPrimitives`); meshes without
index data keep using array draws. `material_ranges` are carried as metadata but
the current unlit material draws the whole mesh in one call.

Mesh factories share two backend-neutral helpers from `render`:

- `render.resolve_material_texture(material, texture_factory, target_factory)`
  - Resolves `material.texture` into a backend handle through the texture or target
    factory, or returns an already-created handle. Returns `nil` when the material
    has no texture.
- `render.material_sources(mesh, material, has_texture, builtin)`
  - Returns `vertex_source, fragment_source, label` for the drawable. A custom
    material supplies its own sources; otherwise `shading = "lit"` selects
    `builtin.lit`, and the unlit path selects `builtin.textured` or
    `builtin.unlit`. A built-in textured material raises when the mesh has no UVs;
    a lit material raises when normals are missing, and a normal-mapped lit material
    raises when tangents or UVs are missing.
- `render.resolve_material_normal_texture(material, texture_factory, target_factory)`
  - Resolves `material.normal_texture` the same way as the base texture.
- `render.resolve_material_reflection_texture(material, texture_factory, target_factory)`
  - Resolves `material.reflection_texture`, normally a `render.target`, the same way.

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

## Built-in lit uniform contract

The OpenGL built-in lit material uses the following plain uniforms. Córdoba may
add scene-specific uniforms by using a custom material template with the same role
and light conventions rather than forking the backend shader.

Vertex:

- `u_mvp` — model * view * projection.
- `u_model` — world matrix, used for world position and normals.

Fragment:

- `u_texture`, `u_has_texture` — base map and enable flag (slot 0).
- `u_normal_texture`, `u_has_normal_texture` — normal/detail map and enable flag
  (slot 1).
- `u_reflection_texture`, `u_has_reflection_texture` — screen-space planar
  reflection map and enable flag (slot 2).
- `u_texture_scale` — `vec2` UV multiplier for base/normal maps.
- `u_reflection_strength` — strength of the planar reflection composite.
- `u_environment_strength` — strength of the analytic environment response.
- `u_view_size` — `vec2` viewport size used to derive screen-space reflection UVs.
- `u_base_color` — `vec4` albedo RGB with opacity in alpha.
- `u_emissive` — `vec4` emissive RGB.
- `u_roughness`, `u_specular`, `u_alpha_cutoff`.
- `u_camera_position` — `vec4` world-space camera position.
- `u_ambient`, `u_light_direction`, `u_light_color` — `vec4`; directional RGB in
  `.rgb`, intensity in `.a`.
- `u_local_light_count`, `u_local_light_position[4]`,
  `u_local_light_color[4]` — point lights; position `.w` is range, color `.a` is
  intensity.
- `u_exposure`.

The shader applies Lambert diffuse, Blinn-Phong-style specular response driven by
`roughness`, bounded local-light attenuation, exposure, and a Reinhard display
curve. Opacity, alpha mode/cutoff, normal mapping, UV scaling, planar reflection,
and the analytic environment response are implemented by the built-in lit
material; depth and culling state apply to all GL materials. Planar reflections are
sampled in screen space after tone mapping, so the offscreen pass should be rendered
with the same viewport aspect and commonly at a reduced resolution. The SDL GPU
backend currently rejects built-in lit materials with a clear error. Unlit and
textured materials remain available on both backends.

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