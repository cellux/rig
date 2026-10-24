local test = require("test")
local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local motion = require("motion")
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
   test.truthy(plugin.capabilities["render.texture"] ~= nil)
   test.truthy(plugin.capabilities["render.target"] ~= nil)
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
         motion = motion.spin { x = 1.0, y = 2.0 },
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
      motion = motion.spin { x = 0.0, y = 0.0 },
   }
   local child = render.Entity {
      backend = backend("child"),
      motion = motion.spin { x = 0.0, y = 0.0 },
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
test.case("render.material validates shader sources", function()
   local material = render.material {
      name = "solid",
      vertex = "vertex source",
      fragment = "fragment source",
   }

   test.equal(material.kind, "render.material")
   test.equal(material.name, "solid")
   test.equal(material.language, "glsl")

   local ok = pcall(function()
      render.material { name = "missing sources" }
   end)
   test.falsey(ok)
end)

test.case("render.texture validates its image and options", function()
   local image = { width = 2, height = 2, channels = 4, pixels = string.rep("\0", 16) }
   local texture = render.texture { image = image, name = "checker", filter = "nearest" }

   test.equal(texture.kind, "render.texture")
   test.equal(texture.image, image)
   test.equal(texture.filter, "nearest")
   test.equal(texture.wrap, "repeat")

   test.truthy(pcall(function()
      render.texture(image)
   end))

   test.falsey(pcall(function()
      render.texture { image = image, filter = "cubic" }
   end))
   test.falsey(pcall(function()
      render.texture {}
   end))
end)

test.case("render.material accepts a texture without shader sources", function()
   local image = { width = 1, height = 1, channels = 4, pixels = "\0\0\0\0" }
   local material = render.material {
      name = "textured",
      texture = render.texture { image = image },
   }

   test.equal(material.texture.kind, "render.texture")
   test.equal(material.vertex, nil)
end)

test.case("render.material wraps a raw image into a texture", function()
   local image = { width = 1, height = 1, channels = 4, pixels = "\0\0\0\0" }
   local material = render.material {
      vertex = "v",
      fragment = "f",
      texture = image,
   }

   test.equal(material.texture.kind, "render.texture")
   test.equal(material.texture.image, image)
end)

test.case("render.target validates its size and options", function()
   local target = render.target { width = 256, height = 128, name = "scene" }

   test.equal(target.kind, "render.target")
   test.equal(target.width, 256)
   test.equal(target.height, 128)
   test.equal(target.filter, "linear")
   test.equal(target.wrap, "clamp")
   test.equal(target.depth, true)

   test.equal(render.target { depth = false }.depth, false)
   test.equal(render.target {}.width, 512)

   test.falsey(pcall(function()
      render.target { width = 0 }
   end))
   test.falsey(pcall(function()
      render.target { filter = "cubic" }
   end))
end)

test.case("render.material accepts a render target as a texture", function()
   local target = render.target { width = 64, height = 64 }
   local material = render.material { texture = target }

   test.equal(material.texture, target)
end)

test.case("render.material accepts an already-created texture handle", function()
   local handle = {
      width = 1,
      height = 1,
      bind = function() end,
   }
   local material = render.material { texture = handle }

   test.equal(material.texture, handle)
end)

test.case("entity component forwards a material to the mesh factory", function()
   local pp = provider_plugin()
   local rp = render.plugin()
   local seen_material = nil

   local FakeScene = rig.Class(scene.RenderScene)
   function FakeScene:begin_frame()
      self.width = 2
      self.height = 1
   end

   local factory = {
      create = function(_, material)
         seen_material = material
         return { draw = function() end }
      end,
   }

   local material = render.material {
      vertex = "v",
      fragment = "f",
   }

   local compiled = rig.runtime()
      :use(pp)
      :use(rp)
      :add(runtime.descriptor(pp, {
         name = "scene",
         provides = { { capability = "render.scene" } },
         create = function()
            return FakeScene { background_color = color.rgbaf(0, 0, 0, 1) }
         end,
      }))
      :add(runtime.descriptor(pp, {
         provides = { { capability = "render.mesh" } },
         create = function()
            return factory
         end,
      }))
      :add(render.entity_component(rp, {
         name = "quad",
         mesh = mesh.make_quad { size = 1.0 },
         material = material,
      }))
      :execute(function(ctx)
         ctx.scene:render()
      end)
      :compile()

   compiled:start()

   test.equal(seen_material, material)
end)
