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
-- Pick the backend with RIG_BACKEND (see examples/backend.lua); the default is
-- `gl`. The SDL_GPU backend uses the `post_gpu` shader pair.
function M.run(options)
   options = options or {}

   local target = render.target { width = 512, height = 512, name = "scene" }
   local cube = mesh.make_cube { size = 1.6, colors = CUBE_COLORS }
   local post = nil

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
      start = function()
         post = render.material {
            name = "post",
            vertex = asset.text(options.post_vertex or "assets/post.vert"),
            fragment = asset.text(options.post_fragment or "assets/post.frag"),
            texture = target,
         }
      end,
   }
end

local backend = rig.require("./backend").select {
   backends = { gl = true, gpu = true },
}

local options = {
   title = "Rig " .. backend.label .. " Post Process",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
}
if backend.name == "gpu" then
   options.post_vertex = "assets/post_gpu.vert"
   options.post_fragment = "assets/post_gpu.frag"
end

M.run(options)
