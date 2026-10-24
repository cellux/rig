local asset = require("asset")
local mathx = require("mathx")
local mesh = require("mesh")
local render = require("render")
local rig = require("rig")

local M = {}

-- Loads a PNG next to this script and draws a textured quad through the
-- built-in textured material. The material carries a render.texture value; the
-- backend uploads it and samples it through the mesh's UV attribute. The async
-- read happens in `start`, before the first frame.
local quad = mesh.make_quad { size = 3.0 }
local checker = nil

-- Pick the backend with RIG_BACKEND (see examples/backend.lua); the default is
-- `gl`.
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
      start = function()
         local texture = render.texture {
            image = asset.image("assets/checker.png"),
            name = "checker",
            filter = "nearest",
         }
         checker = render.material { name = "checker", texture = texture }
      end,
   }
end

local backend = rig.require("./backend").select {
   backends = { gl = true, gpu = true },
}

M.run {
   title = "Rig " .. backend.label .. " Textured Quad",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
}
