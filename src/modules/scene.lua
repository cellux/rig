local M = ... or {}

local rig = require("rig")
local runtime = require("runtime")

-- A render scene is a backend-agnostic container of drawables. It sequences a
-- frame as `begin_frame`, each ordered `drawable:draw(scene, ...)`, then
-- `end_frame`. Backends specialize the hooks through a subclass (for example a
-- GL scene that sets the viewport and clears the framebuffer).
local RenderScene = rig.Class()
M.RenderScene = RenderScene

function RenderScene:init(options)
   options = options or {}

   self.name = options.name
   self.graphics = options.graphics
   self.background_color = options.background_color
   self.drawables = {}
end

function RenderScene:add(drawable)
   if drawable == nil then
      rig.raise("RenderScene:add requires a drawable")
   end
   if type(drawable.draw) ~= "function" then
      rig.raise("RenderScene:add expects a drawable with a draw method")
   end

   self.drawables[#self.drawables + 1] = drawable
   return drawable
end

function RenderScene:remove(drawable)
   for i = #self.drawables, 1, -1 do
      if self.drawables[i] == drawable then
         table.remove(self.drawables, i)
         return true
      end
   end
   return false
end

function RenderScene:begin_frame(...)
end

function RenderScene:end_frame(...)
end

function RenderScene:render(...)
   self:begin_frame(...)
   for i = 1, #self.drawables do
      self.drawables[i]:draw(self, ...)
   end
   self:end_frame(...)
end

M.plugin = function(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "scene",
      capabilities = {
         ["render.scene"] = {},
      },
   }
end

M.container_component = function(plugin, options)
   options = options or {}
   local scene_class = options.scene_class or RenderScene
   if not rig.is_class(scene_class) then
      rig.raise("scene.container_component options.scene_class must be a class")
   end

   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "render.scene" },
      },
      requires = {
         { capability = "graphics.context" },
      },
      create = function(context)
         return scene_class {
            name = options.name,
            graphics = context:capability("graphics.context"),
            background_color = options.background_color,
         }
      end,
   })
end

return M