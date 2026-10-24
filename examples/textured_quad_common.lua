local asset = require("asset")
local mathx = require("mathx")
local mesh = require("mesh")
local render = require("render")
local rig = require("rig")

local M = {}

-- Loads a PNG next to this script and draws a textured quad through the
-- built-in textured material. The material carries a render.texture value; the
-- backend uploads it and samples it through the mesh's UV attribute.
local texture = render.texture {
   image = asset.image("assets/checker.png"),
   name = "checker",
   filter = "nearest",
}

local quad = mesh.make_quad { size = 3.0 }
local checker = render.material { name = "checker", texture = texture }

-- options:
--   title          window title
--   bundle         sdl3x.bundle_sdl3_gl or sdl3x.bundle_sdl3_gpu (the backend hint)
--   bundle_options extra options forwarded to the bundle
function M.run(options)
   options = options or {}

   rig.run {
      title = options.title or "Rig Textured Quad",
      bundle = options.bundle,
      bundle_options = options.bundle_options,
      build = function(app)
         app:on_draw(function(_, frame)
            local rotation = mathx.mat4()
            mathx.mat4_rotation_y(rotation, frame.time * 0.7)
            frame.surface:draw_mesh(quad, rotation, checker)
         end)
      end,
   }
end

return M
