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

test.case("render.material exposes tiling, reflection, and environment fields", function()
   local image = { width = 1, height = 1, channels = 4, pixels = "\0\0\0\0" }
   local reflection = render.target { width = 64, height = 32, name = "reflection" }
   local material = render.material {
      name = "polished",
      shading = "lit",
      texture = render.texture { image = image },
      texture_scale = { 0.5, 2.0 },
      reflection_texture = reflection,
      reflection_strength = 0.3,
      environment_strength = 0.2,
   }

   test.equal(material.texture_scale[1], 0.5)
   test.equal(material.texture_scale[2], 2.0)
   test.equal(material.reflection_texture, reflection)
   test.equal(material.reflection_strength, 0.3)
   test.equal(material.environment_strength, 0.2)

   test.equal(render.material { shading = "lit" }.reflection_strength, 0.0)
   test.equal(
      render.material { shading = "lit", reflection_texture = reflection }.reflection_strength,
      0.25
   )

   test.falsey(pcall(function()
      render.material { shading = "lit", texture_scale = 0.0 }
   end))
   test.falsey(pcall(function()
      render.material { shading = "lit", environment_strength = 1.1 }
   end))
   test.falsey(pcall(function()
      render.material { shading = "lit", reflection_strength = -0.1 }
   end))
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

test.case("render.material exposes lit shading defaults and validation", function()
   local material = render.material { shading = "lit" }

   test.equal(material.shading, "lit")
   test.equal(material.roughness, 0.7)
   test.equal(material.specular, 0.1)
   test.equal(material.opacity, 1.0)
   test.equal(material.alpha_mode, "opaque")
   test.equal(material.alpha_cutoff, 0.5)
   test.equal(material.depth_test, true)
   test.equal(material.depth_write, true)
   test.equal(material.cull_mode, "none")
   test.truthy(color.is(material.albedo))
   test.truthy(color.is(material.emissive))

   local blended = render.material { shading = "lit", opacity = 0.4 }
   test.equal(blended.alpha_mode, "blend")

   local cutout = render.material { shading = "lit", alpha_mode = "cutout" }
   test.equal(cutout.alpha_mode, "cutout")

   test.falsey(pcall(function()
      render.material { shading = "glossy" }
   end))
   test.falsey(pcall(function()
      render.material { shading = "lit", roughness = 2.0 }
   end))
   test.falsey(pcall(function()
      render.material { shading = "lit", cull_mode = "both" }
   end))
   test.falsey(pcall(function()
      render.material { shading = "lit", alpha_mode = "mask" }
   end))
end)

test.case("render.material accepts base and normal textures", function()
   local image = { width = 1, height = 1, channels = 4, pixels = "\255\255\255\255" }
   local material = render.material {
      shading = "lit",
      texture = image,
      normal_texture = render.texture { image = image },
   }

   test.equal(material.texture.kind, "render.texture")
   test.equal(material.normal_texture.kind, "render.texture")
end)

test.case("render.material_sources selects and validates the lit path", function()
   local builtin = {
      unlit = { vertex = "unlit-v", fragment = "unlit-f" },
      textured = { vertex = "textured-v", fragment = "textured-f" },
      lit = { vertex = "lit-v", fragment = "lit-f" },
   }
   local lit = render.material { shading = "lit" }

   local vertex, fragment, label = render.material_sources(
      mesh.make_box {},
      lit,
      false,
      builtin
   )
   test.equal(vertex, "lit-v")
   test.equal(fragment, "lit-f")
   test.equal(label, "rig.render.mesh.lit")

   local ok, err = pcall(function()
      render.material_sources(mesh.make_quad {}, lit, false, builtin)
   end)
   test.falsey(ok)
   test.match(tostring(err), "requires a mesh with normals")

   local normal_mapped = render.material {
      shading = "lit",
      normal_texture = {
         width = 1,
         height = 1,
         bind = function() end,
      },
   }
   ok, err = pcall(function()
      render.material_sources(mesh.make_box {}, normal_mapped, false, builtin)
   end)
   test.falsey(ok)
   test.match(tostring(err), "requires a mesh with tangents")

   local tangent_box = mesh.builder { tangents = true }
      :add(mesh.make_box {})
      :build()
   assert(render.material_sources(tangent_box, normal_mapped, false, builtin))

   local no_lit = {
      unlit = builtin.unlit,
      textured = builtin.textured,
   }
   ok, err = pcall(function()
      render.material_sources(mesh.make_box {}, lit, false, no_lit)
   end)
   test.falsey(ok)
   test.match(tostring(err), "not implemented for this render backend")
end)

test.case("render.lighting normalizes daylight and validates local lights", function()
   local lighting = render.lighting {
      ambient = color.rgb(40, 44, 52),
      directional = {
         direction = { 0.0, 2.0, 0.0 },
         color = color.rgb(255, 240, 210),
         intensity = 1.5,
      },
      local_lights = {
         {
            position = { 1.0, 2.0, 3.0 },
            color = color.rgb(255, 160, 90),
            intensity = 2.0,
            range = 6.0,
         },
      },
      exposure = 1.2,
   }

   test.equal(lighting.kind, "render.lighting")
   test.equal(lighting.exposure, 1.2)
   test.equal(lighting.directional.intensity, 1.5)
   test.truthy(math.abs(lighting.directional.direction[1]) < 1e-6)
   test.truthy(math.abs(lighting.directional.direction[2] - 1.0) < 1e-6)
   test.equal(#lighting.local_lights, 1)
   test.equal(lighting.local_lights[1].range, 6.0)

   test.equal(render.MAX_LOCAL_LIGHTS, 4)
   test.falsey(pcall(function()
      render.lighting {
         directional = { direction = { 0.0, 0.0, 0.0 } },
      }
   end))
   test.falsey(pcall(function()
      render.lighting {
         local_lights = {
            { position = { 0, 0, 0 } },
            { position = { 0, 0, 0 } },
            { position = { 0, 0, 0 } },
            { position = { 0, 0, 0 } },
            { position = { 0, 0, 0 } },
         },
      }
   end))
end)
