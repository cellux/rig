local color = require("color")
local mesh = require("mesh")
local motion = require("motion")
local rig = require("rig")
local sdl3x = require("sdl3x")

-- Camera controls are optional: this sketch opts in with `camera_controls`.
-- Drag with the primary mouse button to orbit, Q/E to dolly in and out.
local grid = mesh.make_grid {
   size = 12.0,
   divisions = 12,
   color = color.rgb(90, 100, 130),
}

rig.run {
   title = "Rig Orbit Grid",
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
   camera_controls = {
      kind = "orbit",
      distance = 10.0,
      pitch = 0.5,
   },
   build = function(app)
      app:add_entity {
         mesh = mesh.make_cube { size = 1.5 },
         motion = motion.spin { y = 0.7 },
      }
      app:on_draw(function(_, frame)
         frame.surface:draw_mesh(grid)
      end)
   end,
}