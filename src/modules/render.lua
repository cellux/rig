local M = ... or {}

local mathx = require("mathx")
local rig = require("rig")
local runtime = require("runtime")
local scene = require("scene")
local schema = require("schema")

-- An entity is a scene node that renders a mesh. It owns the mesh instance's
-- local transform and spin animation; children inherit its world transform.
-- The camera and view/projection live on the scene, so all entities share one
-- view. Shaders, pipelines, and buffers are delegated to a `render.mesh`
-- factory.
local Entity = rig.Class(scene.Node)
M.Entity = Entity

function Entity:init(options)
   self:super().init(self)
   options = options or {}

   self.backend = options.backend
   self.mesh = options.mesh
   self.spin_x = options.spin and options.spin.x or 0.7
   self.spin_y = options.spin and options.spin.y or 1.0
   self.clock = options.clock
   self.last_time = self.clock ~= nil and self.clock:monotonic() or nil

   self.rotation_x_angle = 0.0
   self.rotation_y_angle = 0.0
   self.rotation_x = mathx.mat4()
   self.rotation_y = mathx.mat4()
   self.spin = mathx.mat4()
   self.mvp = mathx.mat4()
end

function Entity:step(surface)
   if self.clock == nil then
      return
   end

   local now = self.clock:monotonic()
   local dt = self.last_time == nil and 0.0 or (now - self.last_time)
   self.last_time = now
   if dt > 0.0 then
      self:update(dt)
   end
end

function Entity:update(dt)
   self.rotation_x_angle = self.rotation_x_angle + dt * self.spin_x
   self.rotation_y_angle = self.rotation_y_angle + dt * self.spin_y
end

function Entity:build_local(out)
   mathx.mat4_rotation_x(self.rotation_x, self.rotation_x_angle)
   mathx.mat4_rotation_y(self.rotation_y, self.rotation_y_angle)
   mathx.mat4_multiply(self.spin, self.rotation_x, self.rotation_y)
   return mathx.mat4_multiply(out, self.local_matrix, self.spin)
end

function Entity:draw_node(surface, world, ...)
   mathx.mat4_multiply(self.mvp, world, surface:view_projection())
   self.backend:draw(surface, self.mvp, ...)
end

function Entity:release()
   self.backend = nil
   self.mesh = nil
end

M.plugin = function(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "render",
      capabilities = {
         ["render.mesh"] = {},
      },
   }
end

local entity_schema = schema.record({
   mesh = schema.table(),
   spin = schema.record({
      x = schema.number():optional(),
      y = schema.number():optional(),
   }, {
      allow_extra = true,
   }):optional(),
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
         local backend = factory.create(config.mesh)
         local entity = Entity {
            backend = backend,
            mesh = config.mesh,
            spin = config.spin,
            clock = context.runtime.clock,
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