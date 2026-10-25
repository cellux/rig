local M = ... or {}

local color = require("color")
local mathx = require("mathx")
local rig = require("rig")
local runtime = require("runtime")
local scene = require("scene")
local schema = require("schema")

-- An entity is a scene node that renders a mesh. Transform animation is not
-- hard-coded here: entities accept motion contributors, and the node base class
-- composes them in `build_local`. Children inherit its world transform. The
-- camera and view/projection live on the scene, so all entities share one view.
-- Shaders, pipelines, and buffers are delegated to a `render.mesh` factory.
local Entity = rig.Class(scene.Node)
M.Entity = Entity

function Entity:init(options)
   self:super().init(self)
   options = options or {}

   self.backend = options.backend
   self.mesh = options.mesh
   self.mvp = mathx.mat4()
   self:set_motions(options.motion)
end

-- Accepts a single motion, a list of motions, or nil. Motions are transform
-- contributors composed by `Node:build_local`.
function Entity:set_motions(motions)
   self:clear_motions()
   if motions == nil then
      return self.motions
   end

   if type(motions.contribute) == "function" then
      self:add_motion(motions)
   else
      for i = 1, #motions do
         self:add_motion(motions[i])
      end
   end
   return self.motions
end

function Entity:draw_node(surface, world, frame)
   mathx.mat4_multiply(self.mvp, world, surface:view_projection())
   self.backend:draw(surface, self.mvp, world, frame)
end

function Entity:release()
   self.backend = nil
   self.mesh = nil
end

-- A texture value describes an image to upload. `image` is a decoded image
-- (`{ width, height, channels, pixels }`, for example from `asset.image`).
-- Backend `render.texture` factories turn the value into a GL/GPU texture.
--
-- options (or a decoded image directly):
--   image    decoded image table (required)
--   name     label used in backend resource names
--   filter   "linear" (default) or "nearest"
--   wrap     "repeat" (default), "clamp", or "mirror"
function M.texture(options)
   options = options or {}

   local image = options.image
   if image == nil and type(options.width) == "number" and options.pixels ~= nil then
      image = options
      options = {}
   end

   if type(image) ~= "table" or image.pixels == nil then
      rig.raise("render.texture requires an image with width, height, and pixels")
   end

   local filter = options.filter or "linear"
   if filter ~= "linear" and filter ~= "nearest" then
      rig.raise("render.texture filter must be 'linear' or 'nearest'")
   end

   local wrap = options.wrap or "repeat"
   if wrap ~= "repeat" and wrap ~= "clamp" and wrap ~= "mirror" then
      rig.raise("render.texture wrap must be 'repeat', 'clamp', or 'mirror'")
   end

   return {
      kind = "render.texture",
      image = image,
      name = options.name,
      filter = filter,
      wrap = wrap,
   }
end

-- A render target is an offscreen surface a pass renders into and a material
-- samples. `width`/`height` size it (default 512x512); `depth` (default true)
-- attaches a depth buffer so 3D geometry renders correctly; `filter`/`wrap`
-- control sampling, defaulting to `"linear"`/`"clamp"`. Backend `render.target`
-- factories create one surface per value and expose it as `.texture`, usable as
-- a material texture and as a `draw_fullscreen` source.
function M.target(options)
   options = options or {}

   local width = math.floor(tonumber(options.width) or 512)
   local height = math.floor(tonumber(options.height) or 512)
   if width < 1 or height < 1 then
      rig.raise("render.target width and height must be positive")
   end

   local filter = options.filter or "linear"
   if filter ~= "linear" and filter ~= "nearest" then
      rig.raise("render.target filter must be 'linear' or 'nearest'")
   end

   local wrap = options.wrap or "clamp"
   if wrap ~= "repeat" and wrap ~= "clamp" and wrap ~= "mirror" then
      rig.raise("render.target wrap must be 'repeat', 'clamp', or 'mirror'")
   end

   return {
      kind = "render.target",
      width = width,
      height = height,
      name = options.name,
      filter = filter,
      wrap = wrap,
      depth = options.depth ~= false,
   }
end

local function normalize_material_texture(value)
   if value == nil then
      return nil
   end
   if type(value) ~= "table" then
      rig.raise("render.material texture must be a render.texture, a render.target, or a decoded image")
   end
   if value.kind == "render.texture" or value.kind == "render.target" then
      return value
   end
   if value.pixels ~= nil then
      return M.texture(value)
   end
   if type(value.bind) == "function" then
      -- An already-created backend texture handle (for example a target's
      -- texture).
      return value
   end
   rig.raise("render.material texture must be a render.texture, a render.target, or a decoded image")
end

local function normalize_texture_scale(value, label)
   if value == nil then
      return 1.0, 1.0
   end
   if type(value) == "number" then
      local scale = tonumber(value)
      if scale == nil or scale <= 0.0 then
         rig.raise(label .. " must be positive")
      end
      return scale, scale
   end
   if type(value) ~= "table" or #value < 2 then
      rig.raise(label .. " must be a positive number or a {u, v} pair")
   end
   local u = tonumber(value[1])
   local v = tonumber(value[2])
   if u == nil or v == nil or u <= 0.0 or v <= 0.0 then
      rig.raise(label .. " must be a positive number or a {u, v} pair")
   end
   return u, v
end

local function validate_color(value, default, label)
   if value == nil then
      return default
   end
   if not color.is(value) then
      rig.raise(label .. " must be a Color value")
   end
   return value
end

local function normalize3(x, y, z, label)
   local length = math.sqrt(x * x + y * y + z * z)
   if length < 1e-12 then
      rig.raise(label .. " must not be a zero-length vector")
   end
   local inv = 1.0 / length
   return x * inv, y * inv, z * inv
end

local DEFAULT_ALBEDO = color.rgbf(1.0, 1.0, 1.0)
local DEFAULT_EMISSIVE = color.rgbf(0.0, 0.0, 0.0)
local DEFAULT_AMBIENT = color.rgbf(0.16, 0.17, 0.19)
local DEFAULT_SUN_COLOR = color.rgbf(1.0, 0.94, 0.84)

local VALID_CULL_MODES = {
   none = true,
   back = true,
   front = true,
   front_and_back = true,
}

local VALID_ALPHA_MODES = {
   opaque = true,
   blend = true,
   cutout = true,
}

local function normalize_cull_mode(value)
   local mode = value or "none"
   if not VALID_CULL_MODES[mode] then
      rig.raise("render.material cull_mode must be 'none', 'back', 'front', or 'front_and_back'")
   end
   return mode
end

local function normalize_alpha_mode(value, opacity)
   local mode = value
   if mode == nil then
      mode = opacity < 1.0 and "blend" or "opaque"
   end
   if not VALID_ALPHA_MODES[mode] then
      rig.raise("render.material alpha_mode must be 'opaque', 'blend', or 'cutout'")
   end
   return mode
end

-- A material selects the shader used to draw a mesh. Passing no material (nil)
-- selects the backend's built-in unlit position/color material. Setting
-- `shading = "lit"` selects the backend's built-in lit material; it requires a
-- mesh with normals, and a normal-mapped material additionally requires
-- tangents. Custom `vertex`/`fragment` sources take precedence over both.
--
-- Material fields (explicit defaults):
--   albedo       Color, default white
--   roughness    0..1, default 0.7
--   specular     0..1, default 0.1
--   emissive     Color, default black
--   opacity      0..1, default 1
--   alpha_mode   "opaque" | "blend" | "cutout"; defaults to "blend" when
--                opacity < 1, otherwise "opaque"
--   alpha_cutoff cutoff for "cutout", default 0.5
--   depth_test   boolean, default true
--   depth_write  boolean, default true
--   cull_mode    "none" | "back" | "front" | "front_and_back", default "none"
--   texture_scale positive number or {u, v}, default 1
--   reflection_strength 0..1, default 0.25 when a reflection map is present
--   environment_strength 0..1, default 0
--
-- `texture` is the base-colour map and `normal_texture` the optional tangent-
-- space normal/detail map. `reflection_texture` is an optional planar reflection
-- map sampled in screen space. All three accept a `render.texture`, a
-- `render.target`, an already-created backend texture handle, or a decoded image.
function M.material(options)
   options = options or {}

   local vertex = options.vertex
   local fragment = options.fragment
   if (vertex == nil) ~= (fragment == nil) then
      rig.raise("render.material requires both vertex and fragment, or neither")
   end
   if vertex ~= nil and (type(vertex) ~= "string" or type(fragment) ~= "string") then
      rig.raise("render.material vertex and fragment must be GLSL source strings")
   end

   local texture = normalize_material_texture(options.texture)
   local normal_texture = normalize_material_texture(options.normal_texture)
   local reflection_texture = normalize_material_texture(options.reflection_texture)
   local texture_scale_u, texture_scale_v = normalize_texture_scale(
      options.texture_scale,
      "render.material texture_scale"
   )
   local shading = options.shading or "unlit"
   if shading ~= "unlit" and shading ~= "lit" then
      rig.raise("render.material shading must be 'unlit' or 'lit'")
   end
   if vertex == nil and texture == nil and shading ~= "lit" then
      rig.raise(
         "render.material requires vertex and fragment GLSL sources, a texture, or shading = 'lit'"
      )
   end

   local roughness = tonumber(options.roughness)
   if roughness == nil then
      roughness = 0.7
   end
   if roughness < 0.0 or roughness > 1.0 then
      rig.raise("render.material roughness must be between 0 and 1")
   end

   local specular = tonumber(options.specular)
   if specular == nil then
      specular = 0.1
   end
   if specular < 0.0 or specular > 1.0 then
      rig.raise("render.material specular must be between 0 and 1")
   end

   local opacity = tonumber(options.opacity)
   if opacity == nil then
      opacity = 1.0
   end
   if opacity < 0.0 or opacity > 1.0 then
      rig.raise("render.material opacity must be between 0 and 1")
   end

   local reflection_strength = tonumber(options.reflection_strength)
   if reflection_strength == nil then
      reflection_strength = reflection_texture ~= nil and 0.25 or 0.0
   end
   if reflection_strength < 0.0 or reflection_strength > 1.0 then
      rig.raise("render.material reflection_strength must be between 0 and 1")
   end

   local environment_strength = tonumber(options.environment_strength)
   if environment_strength == nil then
      environment_strength = 0.0
   end
   if environment_strength < 0.0 or environment_strength > 1.0 then
      rig.raise("render.material environment_strength must be between 0 and 1")
   end

   local alpha_cutoff = tonumber(options.alpha_cutoff)
   if alpha_cutoff == nil then
      alpha_cutoff = 0.5
   end
   if alpha_cutoff < 0.0 or alpha_cutoff > 1.0 then
      rig.raise("render.material alpha_cutoff must be between 0 and 1")
   end

   return {
      kind = "render.material",
      name = options.name,
      language = options.language or "glsl",
      shading = shading,
      vertex = vertex,
      fragment = fragment,
      texture = texture,
      normal_texture = normal_texture,
      reflection_texture = reflection_texture,
      texture_scale = { texture_scale_u, texture_scale_v },
      reflection_strength = reflection_strength,
      environment_strength = environment_strength,
      albedo = validate_color(options.albedo, DEFAULT_ALBEDO, "render.material albedo"),
      roughness = roughness,
      specular = specular,
      emissive = validate_color(
         options.emissive,
         DEFAULT_EMISSIVE,
         "render.material emissive"
      ),
      opacity = opacity,
      alpha_mode = normalize_alpha_mode(options.alpha_mode, opacity),
      alpha_cutoff = alpha_cutoff,
      depth_test = options.depth_test ~= false,
      depth_write = options.depth_write ~= false,
      cull_mode = normalize_cull_mode(options.cull_mode),
   }
end

local function resolve_texture_spec(spec, texture_factory, target_factory)
   if spec == nil then
      return nil
   end
   if spec.kind == "render.texture" then
      if texture_factory == nil then
         rig.raise("textured material requires a render.texture provider")
      end
      return texture_factory.create(spec)
   end
   if spec.kind == "render.target" then
      if target_factory == nil then
         rig.raise("a material sampling a render target requires a render.target provider")
      end
      return target_factory.create(spec).texture
   end
   return spec
end

-- Resolves a material's `texture` into a backend texture handle. It accepts a
-- `render.texture` value (uploaded by the texture factory), a `render.target`
-- value (whose color surface is already a texture handle), or an already-created
-- backend handle. Returns nil when the material has no texture.
function M.resolve_material_texture(material, texture_factory, target_factory)
   if material == nil then
      return nil
   end
   return resolve_texture_spec(material.texture, texture_factory, target_factory)
end

-- Resolves a material's optional `normal_texture` into a backend texture handle.
function M.resolve_material_normal_texture(material, texture_factory, target_factory)
   if material == nil then
      return nil
   end
   return resolve_texture_spec(material.normal_texture, texture_factory, target_factory)
end

-- Resolves a material's optional planar `reflection_texture` into a backend
-- texture handle. Planar reflection maps are usually `render.target` values.
function M.resolve_material_reflection_texture(material, texture_factory, target_factory)
   if material == nil then
      return nil
   end
   return resolve_texture_spec(
      material.reflection_texture,
      texture_factory,
      target_factory
   )
end

-- Selects the vertex/fragment sources and resource label for a mesh drawable.
-- A custom material supplies its own sources. Otherwise `shading = "lit"`
-- selects `builtin.lit`; the unlit path selects `builtin.textured` or
-- `builtin.unlit`. `builtin` supplies:
--   builtin.unlit    = { vertex = ..., fragment = ... }
--   builtin.textured = { vertex = ..., fragment = ... }
--   builtin.lit      = { vertex = ..., fragment = ... }  (optional per backend)
-- A built-in textured material requires a mesh with UVs. A built-in lit material
-- requires normals, and a normal-mapped lit material requires tangents.
function M.material_sources(mesh, material, has_texture, builtin)
   if material ~= nil and material.vertex ~= nil then
      return material.vertex, material.fragment,
         "rig.render.material." .. (material.name or "unnamed")
   end
   if material ~= nil and material.shading == "lit" then
      if builtin.lit == nil then
         rig.raise("lit materials are not implemented for this render backend")
      end
      if mesh.attribute_offsets.normal == nil then
         rig.raise("the built-in lit material requires a mesh with normals")
      end
      if (has_texture or material.normal_texture ~= nil)
         and mesh.attribute_offsets.uv == nil then
         rig.raise("a textured lit material requires a mesh with UVs")
      end
      if material.normal_texture ~= nil and mesh.attribute_offsets.tangent == nil then
         rig.raise("a normal-mapped lit material requires a mesh with tangents")
      end
      return builtin.lit.vertex, builtin.lit.fragment, "rig.render.mesh.lit"
   end
   if has_texture then
      if mesh.attribute_offsets.uv == nil then
         rig.raise(
            "the built-in textured material requires a mesh with UVs (for example mesh.make_quad or mesh.parse_obj)"
         )
      end
      return builtin.textured.vertex, builtin.textured.fragment,
         "rig.render.mesh.textured"
   end
   return builtin.unlit.vertex, builtin.unlit.fragment, "rig.render.mesh"
end

M.MAX_LOCAL_LIGHTS = 4

-- Backend-neutral scene lighting for the built-in lit material. `directional`
-- is the main daylight; local lights are point lights with a finite range.
-- Direction points from the surface toward the light. Colors are `color.Color`
-- values. `exposure` multiplies the linear-lit result before the display curve.
function M.lighting(options)
   options = options or {}

   local directional = options.directional or {}
   local direction = directional.direction or { 0.35, 0.8, -0.45 }
   if type(direction) ~= "table" or #direction < 3 then
      rig.raise("render.lighting directional.direction must have three components")
   end
   local dx, dy, dz = normalize3(
      tonumber(direction[1]) or 0.0,
      tonumber(direction[2]) or 0.0,
      tonumber(direction[3]) or 0.0,
      "render.lighting directional.direction"
   )

   local directional_intensity = tonumber(directional.intensity)
   if directional_intensity == nil then
      directional_intensity = 1.3
   end
   if directional_intensity < 0.0 then
      rig.raise("render.lighting directional.intensity must not be negative")
   end

   local local_lights = {}
   for i, light in ipairs(options.local_lights or {}) do
      if i > M.MAX_LOCAL_LIGHTS then
         rig.raise(
            "render.lighting supports at most %d local lights",
            M.MAX_LOCAL_LIGHTS
         )
      end
      local position = light.position
      if type(position) ~= "table" or #position < 3 then
         rig.raise("render.lighting local light %d needs a three-component position", i)
      end
      local intensity = tonumber(light.intensity)
      if intensity == nil then
         intensity = 1.0
      end
      if intensity < 0.0 then
         rig.raise("render.lighting local light %d intensity must not be negative", i)
      end
      local range = tonumber(light.range)
      if range == nil then
         range = 8.0
      end
      if range <= 0.0 then
         rig.raise("render.lighting local light %d range must be positive", i)
      end
      local_lights[i] = {
         position = {
            tonumber(position[1]) or 0.0,
            tonumber(position[2]) or 0.0,
            tonumber(position[3]) or 0.0,
         },
         color = validate_color(
            light.color,
            DEFAULT_SUN_COLOR,
            "render.lighting local light color"
         ),
         intensity = intensity,
         range = range,
      }
   end

   local exposure = tonumber(options.exposure)
   if exposure == nil then
      exposure = 1.0
   end
   if exposure <= 0.0 then
      rig.raise("render.lighting exposure must be positive")
   end

   return {
      kind = "render.lighting",
      ambient = validate_color(options.ambient, DEFAULT_AMBIENT, "render.lighting ambient"),
      directional = {
         direction = { dx, dy, dz },
         color = validate_color(
            directional.color,
            DEFAULT_SUN_COLOR,
            "render.lighting directional.color"
         ),
         intensity = directional_intensity,
      },
      local_lights = local_lights,
      exposure = exposure,
   }
end

M.default_lighting = M.lighting()

M.plugin = function(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "render",
      capabilities = {
         ["render.mesh"] = {},
         ["render.texture"] = {},
         ["render.target"] = {},
      },
   }
end

local entity_schema = schema.record({
   mesh = schema.table(),
   motion = schema.any():optional(),
   material = schema.any():optional(),
}, {
   allow_extra = true,
})

-- Composes a mesh-rendering entity and adds it to the scene as a child of the
-- scene root. The `render.mesh` factory owns shaders/pipeline/buffers; the
-- scene owns the camera.
M.entity_component = function(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      config = options,
      config_schema = entity_schema,
      requires = {
         { capability = "render.scene" },
         { capability = "render.mesh" },
      },
      create = function(context)
         local config = context.component.config
         local factory = context:capability("render.mesh")
         local backend = factory.create(config.mesh, config.material)
         local entity = Entity {
            backend = backend,
            mesh = config.mesh,
            material = config.material,
            motion = config.motion,
         }
         context:capability("render.scene"):add_child(entity)
         return entity
      end,
      release = function(entity)
         entity:release()
      end,
   })
end

return M