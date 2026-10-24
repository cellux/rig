local asset = require("asset")
local color = require("color")
local font = require("font")
local rig = require("rig")

-- Typography stress test for the font stack. A handful of large words drift
-- right-to-left at different sizes, colors, speeds, and alphas, so a single run
-- exercises shaping, rasterization, atlas packing, and per-backend drawing.
--
-- Pick the rendering backend with RIG_BACKEND (see examples/backend.lua); the
-- default is `gl`.

local backend = rig.require("./backend").select {
   backends = { renderer = true, gl = true, gpu = true },
}

local face_path = asset.path("../assets/DejaVuSans.ttf")

-- text, pixel size, RGB, horizontal speed (px/s), vertical lane (0..1),
-- initial scroll phase (0..1), alpha pulse speed, and alpha phase.
local WORDS = {
   {
      text = "RIG",
      size = 176,
      rgb = { 255, 198, 120 },
      speed = 68,
      lane = 0.15,
      start = 0.00,
      pulse = 0.9,
      phase = 0.0,
   },
   {
      text = "typography",
      size = 132,
      rgb = { 120, 214, 255 },
      speed = 52,
      lane = 0.34,
      start = 0.42,
      pulse = 1.3,
      phase = 1.1,
   },
   {
      text = "FONTS",
      size = 156,
      rgb = { 255, 118, 182 },
      speed = 94,
      lane = 0.51,
      start = 0.74,
      pulse = 1.1,
      phase = 2.4,
   },
   {
      text = "everywhere",
      size = 96,
      rgb = { 166, 255, 150 },
      speed = 44,
      lane = 0.68,
      start = 0.18,
      pulse = 0.7,
      phase = 0.6,
   },
   {
      text = "SDL_GPU",
      size = 76,
      rgb = { 255, 240, 150 },
      speed = 122,
      lane = 0.86,
      start = 0.56,
      pulse = 1.6,
      phase = 3.0,
   },
   {
      text = "OpenGL",
      size = 88,
      rgb = { 196, 168, 255 },
      speed = 62,
      lane = 0.43,
      start = 0.90,
      pulse = 1.0,
      phase = 4.2,
   },
   {
      text = "SDL_Renderer",
      size = 58,
      rgb = { 150, 240, 240 },
      speed = 82,
      lane = 0.79,
      start = 0.30,
      pulse = 1.8,
      phase = 2.0,
   },
}

local styles = {}
local canvas = nil

local top_rule_color = color.rgb(255, 198, 120):with_alpha(190)
local bottom_rule_color = color.rgb(120, 214, 255):with_alpha(190)

local function ensure_style(app, word)
   local style = styles[word.size]
   if style == nil then
      style = app.ctx.font:create_style(app.face, {
         pixel_size = word.size,
         page_width = 512,
         page_height = 512,
         padding = 2,
      })
      styles[word.size] = style
   end
   return style
end

local function draw_words(frame)
   local surface = frame.surface
   local width = surface.width or 1
   local height = surface.height or 1
   local time = frame.time

   -- Screen-space rules through the backend-neutral 2D API.
   if canvas ~= nil then
      canvas:rect(0, 0, width, 4, top_rule_color)
      canvas:rect(0, height - 4, width, 4, bottom_rule_color)
   end

   for i = 1, #WORDS do
      local word = WORDS[i]
      local run = word.run
      if run ~= nil then
         local span = width + run.width
         local travel = (time * word.speed + word.start * span) % span
         local x = width - travel
         local baseline = height * word.lane + word.size * 0.34

         local wave = 0.5 + 0.5 * math.sin(time * word.pulse + word.phase)
         local alpha = math.floor((0.12 + 0.88 * wave) * 255 + 0.5)
         local draw_color = color.rgb(word.rgb[1], word.rgb[2], word.rgb[3])
            :with_alpha(alpha)

         word.style:draw_run(run, x, baseline, function()
            return draw_color
         end)
      end
   end
end

rig.run {
   title = "Rig " .. backend.label .. " Typography",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
   background = color.rgb(9, 11, 18),
   build = function(app)
      app:on_overlay(function(_, frame)
         draw_words(frame)
      end)
   end,
   start = function(app)
      app.face = font.load_face(face_path)
      canvas = app.ctx.draw

      for i = 1, #WORDS do
         local word = WORDS[i]
         word.style = ensure_style(app, word)
         word.run = word.style:build_run(word.text)
      end
   end,
}
