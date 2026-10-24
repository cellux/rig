local asset = require("asset")
local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local render = require("render")
local rig = require("rig")

local M = {}

local CUBE_COLORS = {
   color.rgb(255, 96, 96),
   color.rgb(96, 224, 128),
   color.rgb(96, 144, 255),
   color.rgb(255, 220, 96),
   color.rgb(240, 112, 255),
   color.rgb(112, 232, 255),
}

-- Renders a spinning cube into an offscreen target, then feeds that target to a
-- fullscreen post shader. This is the smallest chained pass: render to texture,
-- sample it, draw to the window.
--
-- options:
--   title          window title
--   bundle         sdl3x.bundle_sdl3_gl or sdl3x.bundle_sdl3_gpu (the backend hint)
--   bundle_options extra options forwarded to the bundle
--   post_vertex    path (relative to this script) of the post vertex shader
--   post_fragment  path of the post fragment shader
function M.run(options)
   options = options or {}

   local target = render.target { width = 512, height = 512, name = "scene" }
   local cube = mesh.make_cube { size = 1.6, colors = CUBE_COLORS }

   local post = render.material {
      name = "post",
      vertex = asset.text(options.post_vertex or "assets/post.vert"),
      fragment = asset.text(options.post_fragment or "assets/post.frag"),
      texture = target,
   }

   rig.run {
      title = options.title or "Rig Post Process",
      bundle = options.bundle,
      bundle_options = options.bundle_options,
      build = function(app)
         app:on_draw(function(_, frame)
            local spin = mathx.mat4()
            mathx.mat4_rotation_y(spin, frame.time * 0.9)
            local tilt = mathx.mat4_rotation_x(mathx.mat4(), frame.time * 0.4)
            mathx.mat4_multiply(spin, tilt, spin)

            frame.surface:render_to(target, function(inner)
               inner.surface:draw_mesh(cube, spin)
            end)
            frame.surface:draw_fullscreen(post)
         end)
      end,
   }
end

return M
