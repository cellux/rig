local M = ... or {}

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
   self.backend:draw(surface, self.mvp)
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

-- A material selects the shader used to draw a mesh. Passing no material (nil)
-- selects the backend's built-in unlit position/color material. Custom materials
-- supply GLSL `vertex` and `fragment` sources that consume the same
-- `u_mvp`/camera uniform contract as the built-in material.
--
-- A material may also carry a `texture` (a `render.texture` or a decoded image).
-- When it does, the backend binds it to texture/sampler slot 0 and, for the
-- built-in textured material, samples it through a `u_texture` uniform using the
-- mesh's UV attribute. Custom shaders receive the same binding contract.
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
   if vertex == nil and texture == nil then
      rig.raise("render.material requires vertex and fragment GLSL sources or a texture")
   end

   return {
      kind = "render.material",
      name = options.name,
      language = options.language or "glsl",
      vertex = vertex,
      fragment = fragment,
      texture = texture,
   }
end

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