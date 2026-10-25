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
test.case("RenderScene advances time from its clock and orders callbacks", function()
   local clock = runtime.ManualClock(0)
   local order = {}

   local surface = scene.RenderScene {
      clock = clock,
      on_update = function(frame)
         order[#order + 1] = "update:" .. tostring(frame.time)
      end,
      on_draw = function(frame)
         order[#order + 1] = "draw:" .. tostring(frame.time)
      end,
   }

   clock:advance(0.5)
   surface:render()
   clock:advance(0.25)
   surface:render()

   test.equal(
      table.concat(order, ","),
      "update:0.5,draw:0.5,update:0.75,draw:0.75"
   )
end)

test.case("RenderScene passes its frame context to node transforms", function()
   local clock = runtime.ManualClock(0)
   local surface = scene.RenderScene { clock = clock }
   local captured = {}

   local child = scene.Node {}
   child.build_local = function(self, out, frame)
      captured.time = frame.time
      captured.dt = frame.dt
      return scene.Node.build_local(self, out, frame)
   end
   surface:add_child(child)

   clock:advance(2.0)
   surface:render()

   test.equal(captured.time, 2.0)
   test.equal(captured.dt, 2.0)
end)

test.case("RenderScene draws meshes immediately with a transform stack", function()
   local identity = mathx.mat4()
   mathx.mat4_identity(identity)

   local draws = {}
   local factory = {
      create = function(mesh)
         return {
            mesh = mesh,
            draw = function(_, _, mvp)
               draws[#draws + 1] = mathx.mat4_copy(mathx.mat4(), mvp)
            end,
         }
      end,
   }

   local surface = scene.RenderScene { mesh_factory = factory }
   surface.view_projection = function()
      return identity
   end

   local mesh = { name = "cube" }
   surface:push_transform(mathx.mat4_translation(mathx.mat4(), 2.0, 0.0, 0.0))
   surface:draw_mesh(mesh)
   surface:pop_transform()
   surface:draw_mesh(mesh)

   test.equal(#draws, 2)
   test.equal(draws[1][12], 2.0)
   test.equal(draws[2][12], 0.0)
   test.equal(surface:mesh_drawable(mesh), surface:mesh_drawable(mesh))

   local ok = pcall(function()
      surface:pop_transform()
   end)
   test.falsey(ok)
end)

test.case("RenderScene keys drawables by mesh and material", function()
   local created = {}
   local factory = {
      create = function(mesh, material)
         local drawable = {
            mesh = mesh,
            material = material,
            draw = function() end,
         }
         created[#created + 1] = drawable
         return drawable
      end,
   }

   local surface = scene.RenderScene { mesh_factory = factory }
   local quad = { name = "quad" }
   local material = { name = "custom" }

   local default_drawable = surface:mesh_drawable(quad)
   test.equal(surface:mesh_drawable(quad), default_drawable)

   local custom_drawable = surface:mesh_drawable(quad, material)
   test.truthy(custom_drawable ~= default_drawable)
   test.equal(surface:mesh_drawable(quad, material), custom_drawable)

   test.equal(#created, 2)
   test.equal(created[1].material, nil)
   test.equal(created[2].material, material)
end)

test.case("RenderScene renders a pass into a target and restores its size", function()
   local target = { kind = "render.target", width = 320, height = 200, depth = true }
   local handle = {
      width = 320,
      height = 200,
      flip_v = false,
      texture = { bind = function() end },
   }
   local created = {}
   local target_factory = {
      create = function(value)
         created[#created + 1] = value
         return handle
      end,
   }

   local events = {}
   local Specialized = rig.Class(scene.RenderScene)
   function Specialized:enter_target(entered)
      events[#events + 1] = "enter:" .. tostring(entered == handle)
   end
   function Specialized:leave_target(left)
      events[#events + 1] = "leave:" .. tostring(left == handle)
   end

   local surface = Specialized { target_factory = target_factory }
   local inside_width, inside_height = nil, nil
   local returned = surface:render_to(target, function(frame)
      events[#events + 1] = "draw"
      inside_width = surface.width
      inside_height = surface.height
      test.equal(frame.scene, surface)
   end)

   test.equal(returned, handle)
   test.equal(#created, 1)
   test.equal(created[1], target)
   test.equal(inside_width, 320)
   test.equal(inside_height, 200)
   test.equal(surface.width, 1)
   test.equal(surface.height, 1)
   test.equal(table.concat(events, ","), "enter:true,draw,leave:true")
end)

test.case("render_to can use and restore a temporary camera", function()
   local handle = {
      width = 32,
      height = 16,
      flip_v = false,
      texture = { bind = function() end },
   }
   local surface = scene.RenderScene {
      target_factory = { create = function() return handle end },
      camera = {
         eye = { 0.0, 1.0, -2.0 },
         target = { 0.0, 1.0, 0.0 },
         up = { 0.0, 1.0, 0.0 },
      },
   }
   local inside = nil
   surface:render_to(
      { kind = "render.target" },
      function()
         inside = {
            eye = { surface.camera.eye[1], surface.camera.eye[2], surface.camera.eye[3] },
            target = {
               surface.camera.target[1],
               surface.camera.target[2],
               surface.camera.target[3],
            },
         }
      end,
      {
         camera = {
            eye = { 0.0, -1.0, -2.0 },
            target = { 0.0, -1.0, 0.0 },
            up = { 0.0, -1.0, 0.0 },
         },
      }
   )

   test.equal(inside.eye[2], -1.0)
   test.equal(inside.target[2], -1.0)
   test.equal(surface.camera.eye[2], 1.0)
   test.equal(surface.camera.target[2], 1.0)
end)

test.case("render_to flips clip-space Y for bottom-up targets", function()
   local handle = {
      width = 8,
      height = 8,
      flip_v = true,
      texture = { bind = function() end },
   }
   local surface = scene.RenderScene {
      target_factory = { create = function() return handle end },
   }

   local inside_y = nil
   surface:render_to({ kind = "render.target" }, function()
      inside_y = surface:view_projection()[5]
   end)
   local restored_y = surface:view_projection()[5]

   test.truthy(inside_y * restored_y < 0)
end)

test.case("render_to requires a target factory and a draw function", function()
   test.falsey(pcall(function()
      scene.RenderScene {}:render_to({ kind = "render.target" }, function() end)
   end))

   local surface = scene.RenderScene {
      target_factory = { create = function() return { width = 1, height = 1 } end },
   }
   test.falsey(pcall(function()
      surface:render_to({ kind = "render.target" }, nil)
   end))
end)

test.case("draw_fullscreen draws a clip-space quad with an identity transform", function()
   local seen = nil
   local factory = {
      create = function()
         return {
            draw = function(_, _, mvp)
               seen = mathx.mat4_copy(mathx.mat4(), mvp)
            end,
         }
      end,
   }

   local surface = scene.RenderScene { mesh_factory = factory }
   surface:draw_fullscreen({ name = "post" })

   test.equal(seen[0], 1.0)
   test.equal(seen[5], 1.0)
   test.equal(seen[12], 0.0)
   test.equal(seen[13], 0.0)
end)

test.case("draw_screen maps a unit quad to a pixel rectangle", function()
   local seen = nil
   local factory = {
      create = function()
         return {
            draw = function(_, _, mvp)
               seen = mathx.mat4_copy(mathx.mat4(), mvp)
            end,
         }
      end,
   }

   local surface = scene.RenderScene { mesh_factory = factory }
   surface.width = 800
   surface.height = 600
   surface:draw_screen({ name = "quad" }, 0, 0, 400, 300)

   test.equal(seen[0], 1.0)
   test.equal(seen[5], -1.0)
   test.equal(seen[12], -0.5)
   test.equal(seen[13], 0.5)
end)

test.case("RenderScene runs on_overlay after its children", function()
   local order = {}
   local surface = scene.RenderScene {
      on_overlay = function()
         order[#order + 1] = "overlay"
      end,
   }
   surface:add_child({
      draw = function()
         order[#order + 1] = "draw"
      end,
   })

   surface:render()
   test.equal(table.concat(order, ","), "draw,overlay")
end)

test.case("RenderScene stores and validates scene lighting", function()
   local lighting = { kind = "render.lighting", exposure = 1.0 }
   local surface = scene.RenderScene { lighting = lighting }

   test.equal(surface.lighting, lighting)

   local replacement = { kind = "render.lighting", exposure = 2.0 }
   test.equal(surface:set_lighting(replacement), replacement)
   test.equal(surface.lighting, replacement)
   test.equal(surface:set_lighting(nil), nil)

   test.falsey(pcall(function()
      surface:set_lighting("daylight")
   end))
end)
