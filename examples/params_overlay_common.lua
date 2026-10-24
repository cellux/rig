local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local overlay = require("overlay")
local params = require("params")
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

-- A live parameter overlay over the sketch facade. Up/Down select, Left/Right
-- adjust, Space toggles, click/drag a number bar to set it, and H shows/hides
-- the overlay. The parameters drive the spinning cube and the ground grid.
--
-- options:
--   title          window title
--   bundle         sdl3x.bundle_sdl3_gl or sdl3x.bundle_sdl3_gpu (the backend hint)
--   bundle_options extra options forwarded to the bundle
function M.run(options)
   options = options or {}

   local values = params.params {
      { name = "spin", min = 0.0, max = 3.0, step = 0.1, value = 0.8 },
      { name = "tilt", min = -1.0, max = 1.0, step = 0.05, value = 0.35 },
      { name = "grid", kind = "boolean", value = true },
      {
         name = "palette",
         kind = "enum",
         values = { "slate", "rose", "moss" },
         value = 1,
      },
   }

   local cube = mesh.make_cube { size = 1.8, colors = CUBE_COLORS }
   local grids = {
      mesh.make_grid { size = 8.0, divisions = 8, color = color.rgb(70, 80, 100) },
      mesh.make_grid { size = 8.0, divisions = 8, color = color.rgb(110, 70, 84) },
      mesh.make_grid { size = 8.0, divisions = 8, color = color.rgb(74, 104, 78) },
   }
   local grid_transform = mathx.mat4_translation(mathx.mat4(), 0.0, -1.6, 0.0)

   rig.run {
      title = options.title or "Rig Params Overlay",
      bundle = options.bundle,
      bundle_options = options.bundle_options,
      build = function(app)
         local view = app:add_overlay(overlay.overlay(values))

         app:on_key(function(_, info)
            if info.action == "down" and string.upper(info.key or "") == "H" then
               view.visible = not view.visible
            end
         end)

         app:on_draw(function(_, frame)
            local spin = mathx.mat4()
            mathx.mat4_rotation_y(spin, frame.time * values:get("spin"))
            local tilt = mathx.mat4_rotation_x(mathx.mat4(), values:get("tilt"))
            mathx.mat4_multiply(spin, tilt, spin)

            frame.surface:draw_mesh(cube, spin)
            if values:get("grid") then
               frame.surface:draw_mesh(grids[values:get("palette")], grid_transform)
            end
         end)
      end,
   }
end

return M
