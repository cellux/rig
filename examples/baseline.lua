local asset = require("asset")
local color = require("color")
local font = require("font")
local profiler = require("profiler")
local rig = require("rig")

-- A small, controlled rendering baseline for comparing frame timing and
-- presentation behavior across Rig backends. It draws the same moving square,
-- center rule, and profiler overlay on every backend, so the only variable is
-- the graphics backend underneath `draw`/`font`.
--
-- Pick a backend with RIG_BACKEND (see examples/backend.lua); the default is
-- `gl`:
--
--    RIG_BACKEND=renderer ./build/rig examples/baseline.lua
--    RIG_BACKEND=gl       ./build/rig examples/baseline.lua
--    RIG_BACKEND=gpu      ./build/rig examples/baseline.lua
--
-- Controls:
--   0  toggle the profiler overlay
--   1  toggle the moving square animation
--   V  toggle vsync (where the backend supports it)

local backend = rig.require("./backend").select {
   backends = { renderer = true, gl = true, gpu = true },
}

local face_path = asset.path("../assets/DejaVuSans.ttf")

local background_color = color.rgb(6, 8, 18)
local midline_color = color.rgb(24, 28, 44)
local square_color = color.rgb(240, 246, 255)
local panel_color = color.rgba(0, 0, 0, 150)
local profiler_header_color = color.rgb(255, 184, 150)
local profiler_body_color = color.rgb(255, 248, 224)
local profiler_warn_color = color.rgb(255, 214, 160)
local profiler_toggle_color = color.rgb(196, 220, 255)

local surface_width = 1
local surface_height = 1
local elapsed = 0.0
local anim_enabled = true
local profiler_enabled = true
local vsync_enabled = true
local vsync_supported = true

local canvas
local profiler_style
local frame_profiler

local function draw_label(text, x, baseline_y, draw_color)
   profiler_style:draw_text(text, x, baseline_y, function()
      return draw_color
   end)
end

local function draw_scene()
   canvas:rect(0, surface_height * 0.5 - 1, surface_width, 2, midline_color)

   local orbit = 0.5 + 0.5 * math.sin(elapsed * 1.15)
   local bob = 0.5 + 0.5 * math.sin(elapsed * 2.4)
   local size = 92 + 28 * math.sin(elapsed * 1.8 + 0.6)
   local x = orbit * (surface_width - size)
   local y = (surface_height * 0.5 - size * 0.5) + (bob - 0.5) * 180

   canvas:rect(x, y, size, size, square_color)
end

local function draw_profiler()
   local snapshot = frame_profiler:snapshot()
   local panel_x = 18
   local panel_y = 16
   local panel_w = math.min(378, math.max(220, surface_width - panel_x * 2))
   local panel_h = 162

   canvas:rect(panel_x, panel_y, panel_w, panel_h, panel_color)

   local text_x = panel_x + 10
   local header = "      CUR / 1S / MAX"
   local line_1 = ("CPU %.2f / %.2f / %.2f"):format(
      snapshot.cpu_ms,
      snapshot.cpu_window_max_ms,
      snapshot.cpu_peak_ms
   )
   local line_2 = ("PRS %.2f / %.2f / %.2f"):format(
      snapshot.present_ms,
      snapshot.present_window_max_ms,
      snapshot.present_peak_ms
   )
   local line_3 = ("TOT %.2f / %.2f / %.2f"):format(
      snapshot.total_ms,
      snapshot.total_window_max_ms,
      snapshot.total_peak_ms
   )
   local line_4 = ("INT %.2f / %.2f / %.2f"):format(
      snapshot.interval_ms,
      snapshot.interval_window_max_ms,
      snapshot.interval_peak_ms
   )
   local line_5 = ("GAP %.2f / %.2f / %.2f"):format(
      snapshot.gap_ms,
      snapshot.gap_window_max_ms,
      snapshot.gap_peak_ms
   )
   local line_6 = ("OVR %d"):format(snapshot.overruns)
   local line_7 = vsync_supported
      and (vsync_enabled and "VSYNC ON [V]" or "VSYNC OFF [V]")
      or "VSYNC N/A"
   local line_8 = anim_enabled and "ANIM ON [1]" or "ANIM OFF [1]"
   local line_9 = "PROFILER ON [0]"

   draw_label(header, text_x, panel_y + 16, profiler_header_color)
   draw_label(line_1, text_x, panel_y + 32, profiler_body_color)
   draw_label(line_2, text_x, panel_y + 48, profiler_body_color)
   draw_label(line_3, text_x, panel_y + 64, profiler_body_color)
   draw_label(line_4, text_x, panel_y + 80, profiler_body_color)
   draw_label(line_5, text_x, panel_y + 96, profiler_body_color)
   draw_label(line_6, text_x, panel_y + 112, profiler_warn_color)
   draw_label(line_7, text_x, panel_y + 128, profiler_toggle_color)
   draw_label(line_8, text_x, panel_y + 144, profiler_toggle_color)
   draw_label(line_9, text_x + 150, panel_y + 144, profiler_toggle_color)
end

local function set_vsync(app, enabled)
   local graphics = app.ctx.graphics
   if type(graphics.set_vsync) == "function" then
      graphics:set_vsync(enabled)
   elseif type(graphics.set_swap_interval) == "function" then
      graphics:set_swap_interval(enabled and 1 or 0)
   else
      vsync_supported = false
      return
   end
   vsync_supported = true
   vsync_enabled = enabled
end

local function on_key(app, key_info)
   if key_info.action ~= "down" or key_info["repeat"] then
      return
   end

   local key = key_info.key
   if key == "0" then
      profiler_enabled = not profiler_enabled
   elseif key == "1" then
      anim_enabled = not anim_enabled
   elseif key == "v" or key == "V" then
      set_vsync(app, not vsync_enabled)
   end
end

local function update(app, frame)
   surface_width = math.max(1, frame.surface.width or 1)
   surface_height = math.max(1, frame.surface.height or 1)

   frame_profiler:begin_frame()
   if anim_enabled then
      elapsed = elapsed + frame.dt
   end
end

local function draw_overlay(app, frame)
   surface_width = math.max(1, frame.surface.width or 1)
   surface_height = math.max(1, frame.surface.height or 1)
   canvas = app.ctx.draw

   frame_profiler:begin_cpu()
   draw_scene()
   if profiler_enabled then
      draw_profiler()
   end
   frame_profiler:end_cpu()
   frame_profiler:end_frame()
end

local function start(app)
   local face = font.load_face(face_path)
   profiler_style = app.ctx.font:create_style(face, {
      pixel_size = 14,
      page_width = 256,
      page_height = 128,
      padding = 1,
   })
   profiler_style:warm_text(
      "CPU PRS TOT INT GAP OVR CUR MAX VSYNC ANIM PROFILER ON OFF [] 0123456789./-"
   )
   frame_profiler = profiler.FrameProfiler { fps = 60 }
end

rig.run {
   title = "Rig " .. backend.label .. " Baseline",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
   background = background_color,
   build = function(app)
      app:on_update(update)
      app:on_overlay(draw_overlay)
      app:on_key(on_key)
   end,
   start = start,
}
