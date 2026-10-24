local asset = require("asset")
local mathx = require("mathx")
local mesh = require("mesh")
local rig = require("rig")
local sdl3x = require("sdl3x")

-- Loads GLSL from files next to this script (relative to the script, so it runs
-- from anywhere) and draws a cube with the resulting material.
local tint = asset.material {
   name = "tint",
   vertex = "assets/tint.vert",
   fragment = "assets/tint.frag",
}

local cube = mesh.make_cube { size = 2.0 }

rig.run {
   title = "Rig Shader Asset",
   bundle = sdl3x.bundle_sdl3_gl,
   bundle_options = {
      gl_attributes = {
         context_major_version = 4,
         context_minor_version = 5,
         context_profile = "core",
         doublebuffer = true,
         depth_size = 24,
      },
      swap_interval = 1,
   },
   build = function(app)
      app:on_draw(function(_, frame)
         local rotation = mathx.mat4()
         mathx.mat4_rotation_y(rotation, frame.time * 0.7)
         frame.surface:draw_mesh(cube, rotation, tint)
      end)
   end,
}
