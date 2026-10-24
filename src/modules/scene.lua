local M = ... or {}

local mathx = require("mathx")
local rig = require("rig")
local runtime = require("runtime")

-- A scene node is a node in a transform tree. Children inherit the world
-- transform computed by combining their local matrix with their parent's world
-- matrix, so nested entities follow their parents.
local Node = rig.Class()
M.Node = Node

function Node:init()
   self.parent = nil
   self.children = {}

   self.local_transform = mathx.mat4()
   self.local_matrix = mathx.mat4()
   mathx.mat4_identity(self.local_matrix)
   self.world_matrix = mathx.mat4()
   mathx.mat4_identity(self.world_matrix)
end

function Node:add_child(child)
   if child == nil then
      rig.raise("Node:add_child requires a child")
   end
   if child == self then
      rig.raise("Node:add_child cannot add a node to itself")
   end

   child.parent = self
   self.children[#self.children + 1] = child
   return child
end

function Node:remove_child(child)
   for i = #self.children, 1, -1 do
      if self.children[i] == child then
         table.remove(self.children, i)
         child.parent = nil
         return true
      end
   end
   return false
end

function Node:set_local_matrix(matrix)
   if matrix == nil then
      rig.raise("Node:set_local_matrix requires a matrix")
   end
   mathx.mat4_copy(self.local_matrix, matrix)
   return self.local_matrix
end

-- Produces the node's local transform. Subclasses override this to add
-- animation on top of the stored local matrix.
function Node:build_local(out)
   return mathx.mat4_copy(out, self.local_matrix)
end

-- Per-frame hook, called before the node's transform is computed.
function Node:step(surface)
end

-- Draws this node's own content in world space. Subclasses override it.
function Node:draw_node(surface, world, ...)
end

function Node:render_children(surface, ...)
   if surface == nil then
      rig.raise("Node:render_children requires a surface")
   end

   for i = 1, #self.children do
      local child = self.children[i]
      if type(child.render_tree) == "function" then
         child:render_tree(surface, self.world_matrix, ...)
      elseif type(child.draw) == "function" then
         child:draw(surface, ...)
      end
   end
end

-- Draws this subtree: the node's world matrix is its parent's world matrix
-- combined with its local transform, then each child recurses with it.
function Node:render_tree(surface, parent_world, ...)
   self:step(surface)
   self:build_local(self.local_transform)
   mathx.mat4_multiply(self.world_matrix, parent_world, self.local_transform)
   self:draw_node(surface, self.world_matrix, ...)
   self:render_children(surface, ...)
end

-- Interface for a render scene: the root node of a transform tree, with a
-- camera. It sequences a frame as `begin_frame`, updates the shared
-- view/projection, renders its children, then `end_frame`.
--
-- Concrete implementations (`render.scene.impl` providers) subclass RenderScene
-- and specialize the backend hooks. The runtime selects the implementation from
-- the assembled composition, so user code only names the interface.
local RenderScene = rig.Class(Node)
M.RenderScene = RenderScene

local DEFAULT_CAMERA = {
   eye = { 0.0, 0.0, -4.5 },
   target = { 0.0, 0.0, 0.0 },
   up = { 0.0, 1.0, 0.0 },
   fov_degrees = 60.0,
   near = 0.1,
   far = 100.0,
}

local function normalize_camera(camera)
   camera = camera or {}
   return {
      eye = camera.eye or DEFAULT_CAMERA.eye,
      target = camera.target or DEFAULT_CAMERA.target,
      up = camera.up or DEFAULT_CAMERA.up,
      fov_degrees = camera.fov_degrees or DEFAULT_CAMERA.fov_degrees,
      near = camera.near or DEFAULT_CAMERA.near,
      far = camera.far or DEFAULT_CAMERA.far,
   }
end

function RenderScene:init(options)
   self:super().init(self)
   options = options or {}

   self.name = options.name
   self.graphics = options.graphics
   self.background_color = options.background_color
   -- Runtime adoption hook for backend resources created lazily after startup.
   self.adopt = options.adopt

   self.width = 1
   self.height = 1
   self:set_camera(options.camera)

   self._view = mathx.mat4()
   self._projection = mathx.mat4()
   self._view_projection = mathx.mat4()
   self:update_view_projection()
end

function RenderScene:set_camera(camera)
   self.camera = normalize_camera(camera)
   self._eye = mathx.vec3(
      self.camera.eye[1],
      self.camera.eye[2],
      self.camera.eye[3]
   )
   self._target = mathx.vec3(
      self.camera.target[1],
      self.camera.target[2],
      self.camera.target[3]
   )
   self._up = mathx.vec3(
      self.camera.up[1],
      self.camera.up[2],
      self.camera.up[3]
   )
   return self.camera
end

-- Recomputes the shared view*projection matrix for the current viewport. The
-- scene calls this once per frame, after begin_frame has set width/height.
function RenderScene:update_view_projection()
   local width = self.width
   local height = self.height
   if width == nil or width <= 0 or height == nil or height <= 0 then
      width, height = 1, 1
   end

   mathx.mat4_look_at_lh(self._view, self._eye, self._target, self._up)
   mathx.mat4_perspective_lh(
      self._projection,
      math.rad(self.camera.fov_degrees),
      width / height,
      self.camera.near,
      self.camera.far
   )
   return mathx.mat4_multiply(self._view_projection, self._view, self._projection)
end

-- The view*projection matrix drawables combine with their world matrix.
function RenderScene:view_projection()
   return self._view_projection
end

function RenderScene:begin_frame(...)
end

function RenderScene:end_frame(...)
end

function RenderScene:render(...)
   self:begin_frame(...)
   self:update_view_projection()
   self:render_children(self, ...)
   self:end_frame(...)
end

M.plugin = function(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "scene",
      capabilities = {
         ["render.scene"] = {},
         ["render.scene.impl"] = {},
      },
   }
end

-- Composes a render scene from the assembled runtime.
--
-- Without `options.scene_class` the compiler resolves a `render.scene.impl`
-- provider (for example the implementation shipped beside the active graphics
-- backend) and instantiates it. Providing `scene_class` pins a specific class
-- and skips implementation resolution.
M.container_component = function(plugin, options)
   options = options or {}
   local scene_class = options.scene_class
   if scene_class ~= nil and not rig.is_class(scene_class) then
      rig.raise("scene.container_component options.scene_class must be a class")
   end

   local requires = {
      { capability = "graphics.context" },
   }
   if options.backend ~= nil then
      requires[1].properties = { backend = options.backend }
   end
   if scene_class == nil then
      local impl_requirement = { capability = "render.scene.impl" }
      if options.backend ~= nil then
         impl_requirement.properties = { backend = options.backend }
      end
      requires[#requires + 1] = impl_requirement
   end

   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "render.scene" },
      },
      requires = requires,
      create = function(context)
         local resolved = scene_class or context:capability("render.scene.impl")
         if not rig.is_class(resolved) then
            rig.raise(
               "render.scene.impl provider must be a RenderScene class"
            )
         end

         return resolved {
            name = options.name,
            graphics = context:capability("graphics.context"),
            background_color = options.background_color,
            camera = options.camera,
            adopt = context.adopt,
         }
      end,
   })
end

return M