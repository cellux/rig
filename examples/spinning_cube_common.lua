local color = require("color")
local mesh = require("mesh")
local motion = require("motion")
local rig = require("rig")

local M = {}

M.cube_face_colors = {
   color.rgb(255, 96, 96),
   color.rgb(96, 224, 128),
   color.rgb(96, 144, 255),
   color.rgb(255, 220, 96),
   color.rgb(240, 112, 255),
   color.rgb(112, 232, 255),
}

-- options:
--   title          window title
--   bundle         sdl3x.bundle_sdl3_gl or sdl3x.bundle_sdl3_gpu (the backend hint)
--   bundle_options extra options forwarded to the bundle
function M.run(options)
   options = options or {}

   rig.run {
      title = options.title or "Rig Spinning Cube",
      bundle = options.bundle,
      bundle_options = options.bundle_options,
      build = function(app)
         app:add_entity {
            mesh = mesh.make_cube {
               size = 2.0,
               colors = M.cube_face_colors,
            },
            motion = motion.spin { x = 0.7, y = 1.0 },
         }
      end,
   }
end

return M