local test = require("test")
local mathx = require("mathx")
local runtime = require("runtime")
local rig = require("rig")
local scene = require("scene")

local function provider_plugin()
   return runtime.plugin {
      id = "scene.test.provider",
      capabilities = {
         ["graphics.context"] = {},
         ["render.scene.impl"] = {},
      },
   }
end

test.case("scene plugin declares the scene capabilities", function()
   local plugin = scene.plugin()

   test.truthy(plugin.capabilities["render.scene"] ~= nil)
   test.truthy(plugin.capabilities["render.scene.impl"] ~= nil)
end)

test.case("scene container resolves the implementation for its graphics backend", function()
   local pp = provider_plugin()
   local sp = scene.plugin()
   local FakeScene = rig.Class(scene.RenderScene)
   local built = nil

   local compiled = rig.runtime()
      :use(pp)
      :use(sp)
      :add(runtime.descriptor(pp, {
         name = "graphics",
         provides = {
            { capability = "graphics.context", properties = { backend = "test" } },
         },
         create = function()
            return { backend = "test" }
         end,
      }))
      :add(runtime.descriptor(pp, {
         provides = {
            { capability = "render.scene.impl", properties = { backend = "test" } },
         },
         create = function()
            return FakeScene
         end,
      }))
      :add(scene.container_component(sp, { name = "scene", background_color = "bg" }))
      :execute(function(ctx)
         built = ctx.scene
      end)
      :compile()

   compiled:start()

   test.equal(compiled.plan.bindings.scene.provides[1].capability, "render.scene")
   test.truthy(FakeScene:is_instance(built))
end)

test.case("scene container accepts an explicit scene_class without an implementation", function()
   local pp = provider_plugin()
   local sp = scene.plugin()
   local Explicit = rig.Class(scene.RenderScene)
   local built = nil

   local compiled = rig.runtime()
      :use(pp)
      :use(sp)
      :add(runtime.descriptor(pp, {
         name = "graphics",
         provides = {
            { capability = "graphics.context", properties = { backend = "test" } },
         },
         create = function()
            return { backend = "test" }
         end,
      }))
      :add(scene.container_component(sp, {
         name = "scene",
         scene_class = Explicit,
      }))
      :execute(function(ctx)
         built = ctx.scene
      end)
      :compile()

   compiled:start()

   test.truthy(Explicit:is_instance(built))
end)

test.case("scene exposes a view projection from its camera", function()
   local surface = scene.RenderScene {
      camera = {
         eye = { 0.0, 0.0, -5.0 },
         target = { 0.0, 0.0, 0.0 },
         up = { 0.0, 1.0, 0.0 },
         fov_degrees = 45.0,
         near = 1.0,
         far = 50.0,
      },
   }

   test.truthy(surface:view_projection() ~= nil)
   test.equal(surface.camera.fov_degrees, 45.0)
   test.equal(surface.camera.eye[3], -5.0)
end)

test.case("RenderScene sequences children in insertion order", function()
   local surface = scene.RenderScene {}
   local events = {}

   surface:add_child({
      draw = function()
         events[#events + 1] = "first"
      end,
   })
   surface:add_child({
      draw = function()
         events[#events + 1] = "second"
      end,
   })

   surface:render()
   test.equal(table.concat(events, ","), "first,second")

   surface:render()
   test.equal(table.concat(events, ","), "first,second,first,second")
end)

test.case("remove_child stops rendering a node", function()
   local surface = scene.RenderScene {}
   local calls = 0
   local drawable = {
      draw = function()
         calls = calls + 1
      end,
   }

   surface:add_child(drawable)
   test.equal(surface:remove_child(drawable), true)
   test.equal(surface:remove_child(drawable), false)
   surface:render()
   test.equal(calls, 0)
end)

test.case("RenderScene specialization hooks wrap the children", function()
   local order = {}
   local Specialized = rig.Class(scene.RenderScene)

   function Specialized:begin_frame()
      order[#order + 1] = "begin"
   end

   function Specialized:end_frame()
      order[#order + 1] = "end"
   end

   local surface = Specialized {}
   surface:add_child({
      draw = function()
         order[#order + 1] = "draw"
      end,
   })
   surface:render()

   test.equal(table.concat(order, ","), "begin,draw,end")
end)

test.case("child world transforms accumulate through the tree", function()
   local surface = scene.RenderScene { camera = { eye = { 0.0, 0.0, -1.0 } } }

   local parent = scene.Node {}
   local child = scene.Node {}
   parent:set_local_matrix(mathx.mat4_translation(mathx.mat4(), 1.0, 0.0, 0.0))
   child:set_local_matrix(mathx.mat4_translation(mathx.mat4(), 0.0, 2.0, 0.0))
   parent:add_child(child)
   surface:add_child(parent)

   local worlds = {}
   parent.draw_node = function(_, _, world)
      worlds.parent = mathx.mat4_copy(mathx.mat4(), world)
   end
   child.draw_node = function(_, _, world)
      worlds.child = mathx.mat4_copy(mathx.mat4(), world)
   end

   surface:render()

   test.equal(worlds.parent[12], 1.0)
   test.equal(worlds.parent[13], 0.0)
   test.equal(worlds.child[12], 1.0)
   test.equal(worlds.child[13], 2.0)
end)