local test = require("test")
local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local render = require("render")
local rig = require("rig")
local runtime = require("runtime")
local scene = require("scene")

local function provider_plugin()
   return runtime.plugin {
      id = "render.test.provider",
      capabilities = {
         ["render.scene"] = {},
         ["render.mesh"] = {},
      },
   }
end

local function translation(x, y, z)
   return mathx.mat4_translation(mathx.mat4(), x, y, z)
end

test.case("render plugin declares the render.mesh capability", function()
   local plugin = render.plugin()

   test.truthy(plugin.capabilities["render.mesh"] ~= nil)
end)

test.case("entity component resolves a factory and registers an entity", function()
   local pp = provider_plugin()
   local rp = render.plugin()
   local created = {}

   local FakeScene = rig.Class(scene.RenderScene)
   function FakeScene:begin_frame()
      self.width = 2
      self.height = 1
   end

   local factory = {
      create = function(mesh_value)
         local drawable = {
            mesh = mesh_value,
            draws = 0,
         }
         function drawable:draw(_, mvp)
            self.draws = self.draws + 1
            self.last_mvp = mvp
         end
         created[#created + 1] = drawable
         return drawable
      end,
   }

   local built_mesh = mesh.make_cube { size = 2.0 }
   local rendered = false

   local compiled = rig.runtime()
      :use(pp)
      :use(rp)
      :add(runtime.descriptor(pp, {
         name = "scene",
         provides = {
            { capability = "render.scene" },
         },
         create = function()
            return FakeScene {
               background_color = color.rgbaf(0, 0, 0, 1),
            }
         end,
      }))
      :add(runtime.descriptor(pp, {
         provides = {
            { capability = "render.mesh" },
         },
         create = function()
            return factory
         end,
      }))
      :add(render.entity_component(rp, {
         name = "cube",
         mesh = built_mesh,
         spin = { x = 1.0, y = 2.0 },
      }))
      :execute(function(ctx)
         ctx.scene:render()
         rendered = true
      end)
      :compile()

   compiled:start()

   test.truthy(rendered)
   test.equal(#created, 1)
   test.equal(created[1].mesh, built_mesh)
   test.equal(created[1].draws, 1)
   test.truthy(created[1].last_mvp ~= nil)
end)

test.case("entity component validates its configuration at compile time", function()
   local pp = provider_plugin()
   local rp = render.plugin()

   local ok, err = pcall(function()
      rig.runtime()
         :use(pp)
         :use(rp)
         :add(runtime.descriptor(pp, {
            provides = {
               { capability = "render.scene" },
            },
            create = function()
               return scene.RenderScene {}
            end,
         }))
         :add(runtime.descriptor(pp, {
            provides = {
               { capability = "render.mesh" },
            },
            create = function()
               return {
                  create = function()
                     return { draw = function() end }
                  end,
               }
            end,
         }))
         :add(render.entity_component(rp, {
            name = "cube",
         }))
         :execute(function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(tostring(err), "mesh")
end)

test.case("entity world transforms accumulate through children", function()
   local surface = scene.RenderScene { camera = { eye = { 0.0, 0.0, -1.0 } } }
   local identity = mathx.mat4()
   mathx.mat4_identity(identity)
   surface.view_projection = function()
      return identity
   end

   local recorded = {}
   local function backend(tag)
      return {
         draw = function(_, _, mvp)
            recorded[tag] = mathx.mat4_copy(mathx.mat4(), mvp)
         end,
      }
   end

   local parent = render.Entity {
      backend = backend("parent"),
      spin = { x = 0.0, y = 0.0 },
   }
   local child = render.Entity {
      backend = backend("child"),
      spin = { x = 0.0, y = 0.0 },
   }
   parent:set_local_matrix(translation(1.0, 0.0, 0.0))
   child:set_local_matrix(translation(0.0, 2.0, 0.0))
   parent:add_child(child)
   surface:add_child(parent)

   surface:render()

   test.equal(recorded.parent[12], 1.0)
   test.equal(recorded.parent[13], 0.0)
   test.equal(recorded.child[12], 1.0)
   test.equal(recorded.child[13], 2.0)
end)