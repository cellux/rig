local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local scene = require("scene")

test.case("scene plugin declares the render.scene capability", function()
   local plugin = scene.plugin()

   test.truthy(plugin.capabilities["render.scene"] ~= nil)
end)

test.case("scene container requires graphics.context and provides render.scene", function()
   local provider_plugin = runtime.plugin {
      id = "scene.test.provider",
      capabilities = {
         ["graphics.context"] = {},
      },
   }
   local scene_plugin = scene.plugin()
   local graphics = { backend = "test" }

   local compiled = rig.runtime()
      :use(provider_plugin)
      :use(scene_plugin)
      :add(runtime.descriptor(provider_plugin, {
         name = "graphics",
         provides = {
            { capability = "graphics.context", properties = { backend = "test" } },
         },
         create = function()
            return graphics
         end,
      }))
      :add(scene.container_component(scene_plugin, { name = "scene" }))
      :execute(function() end)
      :compile()

   local component = compiled.plan.bindings.scene
   test.equal(component.provides[1].capability, "render.scene")
   test.equal(compiled.plan.resolved[component][1].provider, compiled.plan.bindings.graphics)
end)

test.case("RenderScene sequences drawables in insertion order", function()
   local surface = scene.RenderScene {}
   local events = {}

   surface:add({
      draw = function()
         events[#events + 1] = "first"
      end,
   })
   surface:add({
      draw = function()
         events[#events + 1] = "second"
      end,
   })

   surface:render()
   test.equal(table.concat(events, ","), "first,second")

   surface:render()
   test.equal(table.concat(events, ","), "first,second,first,second")
end)

test.case("RenderScene remove stops drawing a drawable", function()
   local surface = scene.RenderScene {}
   local calls = 0
   local drawable = {
      draw = function()
         calls = calls + 1
      end,
   }

   surface:add(drawable)
   test.equal(surface:remove(drawable), true)
   test.equal(surface:remove(drawable), false)
   surface:render()
   test.equal(calls, 0)
end)

test.case("RenderScene specialization hooks wrap the drawables", function()
   local order = {}
   local Specialized = rig.Class(scene.RenderScene)

   function Specialized:begin_frame()
      order[#order + 1] = "begin"
   end

   function Specialized:end_frame()
      order[#order + 1] = "end"
   end

   local surface = Specialized {}
   surface:add({
      draw = function()
         order[#order + 1] = "draw"
      end,
   })
   surface:render()

   test.equal(table.concat(order, ","), "begin,draw,end")
end)