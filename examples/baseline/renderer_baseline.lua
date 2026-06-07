local sdl3 = require("sdl3")
local time = require("time")
local font = require("font")
local profiler = require("profiler")
local ffi = require("ffi")

-- Populated by the initial sdl3 on_resize callback before after_setup runs.
local window_width
local window_height
local font_path
local face
local profiler_style
local frame_profiler
local profiler_enabled = true
local vsync_enabled = true

local draw_rect = ffi.new("SDL_FRect[1]")

local scene = {
   start_time = nil,
   animation_enabled = true,
}

local function file_exists(path)
   local file = io.open(path, "rb")
   if file == nil then
      return false
   end
   file:close()
   return true
end

local function find_font_path()
   local candidates = {
      "/usr/share/fonts/TTF/DejaVuSans.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
      "/usr/share/fonts/dejavu/DejaVuSans.ttf",
   }

   for i = 1, #candidates do
      if file_exists(candidates[i]) then
         return candidates[i]
      end
   end

   error("could not find a system DejaVuSans.ttf font", 0)
end

local function set_draw_color(renderer, r, g, b, a)
   if not sdl3.SetRenderDrawColor(renderer, r, g, b, a) then
      error("failed to set draw color: " .. ffi.string(sdl3.GetError()), 0)
   end
end

local function fill_rect(renderer, x, y, w, h)
   draw_rect[0].x = x
   draw_rect[0].y = y
   draw_rect[0].w = w
   draw_rect[0].h = h
   if not sdl3.RenderFillRect(renderer, draw_rect) then
      error("failed to fill rect: " .. ffi.string(sdl3.GetError()), 0)
   end
end

local function draw_label(renderer, text, x, baseline_y, r, g, b, a)
   local run = profiler_style:build_run(text)
   profiler_style:draw_run(run, x, baseline_y, function()
      return r, g, b, a
   end)
end

local function set_vsync(enabled)
   local renderer = sdl3.get_renderer()
   local interval = enabled and 1 or 0
   if not sdl3.SetRenderVSync(renderer, interval) then
      error("failed to set renderer vsync: " .. ffi.string(sdl3.GetError()), 0)
   end
   vsync_enabled = enabled
end

local function toggle_vsync()
   set_vsync(not vsync_enabled)
end

local function on_key(key_info)
   if key_info.action ~= "down" or key_info["repeat"] then
      return
   end

   if key_info.key == "0" then
      profiler_enabled = not profiler_enabled
   elseif key_info.key == "1" then
      scene.animation_enabled = not scene.animation_enabled
   elseif key_info.key == "V" or key_info.key == "v" then
      toggle_vsync()
   end
end

local function draw_profiler(renderer)
   local profile = frame_profiler:snapshot()
   local panel_x = 18
   local panel_y = 16
   local panel_w = math.min(378, math.max(220, window_width - panel_x * 2))
   local panel_h = 162

   set_draw_color(renderer, 0, 0, 0, 150)
   fill_rect(renderer, panel_x, panel_y, panel_w, panel_h)

   local text_x = panel_x + 10
   local header = "      CUR / 1S / MAX"
   local line_1 = ("CPU %.2f / %.2f / %.2f"):format(profile.cpu_ms, profile.cpu_max_1s_ms, profile.cpu_max_ms)
   local line_2 = ("PRS %.2f / %.2f / %.2f"):format(profile.present_ms, profile.present_max_1s_ms, profile.present_max_ms)
   local line_3 = ("TOT %.2f / %.2f / %.2f"):format(profile.total_ms, profile.total_max_1s_ms, profile.total_max_ms)
   local line_4 = ("INT %.2f / %.2f / %.2f"):format(profile.interval_ms, profile.interval_max_1s_ms, profile.interval_max_ms)
   local line_5 = ("GAP %.2f / %.2f / %.2f"):format(profile.gap_ms, profile.gap_max_1s_ms, profile.gap_max_ms)
   local line_6 = ("OVR %d"):format(profile.overruns)
   local line_7 = vsync_enabled and "VSYNC ON [V]" or "VSYNC OFF [V]"
   local line_8 = scene.animation_enabled and "ANIM ON [1]" or "ANIM OFF [1]"
   local line_9 = "PROFILER ON [0]"

   draw_label(renderer, header, text_x, panel_y + 16, 255, 184, 150, 255)
   draw_label(renderer, line_1, text_x, panel_y + 32, 255, 248, 224, 255)
   draw_label(renderer, line_2, text_x, panel_y + 48, 255, 248, 224, 255)
   draw_label(renderer, line_3, text_x, panel_y + 64, 255, 248, 224, 255)
   draw_label(renderer, line_4, text_x, panel_y + 80, 255, 248, 224, 255)
   draw_label(renderer, line_5, text_x, panel_y + 96, 255, 248, 224, 255)
   draw_label(renderer, line_6, text_x, panel_y + 112, 255, 214, 160, 255)
   draw_label(renderer, line_7, text_x, panel_y + 128, 196, 220, 255, 255)
   draw_label(renderer, line_8, text_x, panel_y + 144, 196, 220, 255, 255)
   draw_label(renderer, line_9, text_x + 150, panel_y + 144, 196, 220, 255, 255)
end

local function on_resize(info)
   window_width = math.max(1, info.width)
   window_height = math.max(1, info.height)
end

local function initialize_scene()
   scene.start_time = time.monotonic()
   font_path = find_font_path()
   face = font.load_face(font_path)
   frame_profiler = profiler.FrameProfiler()
   profiler_style = font.create_style(face, {
      pixel_size = 14,
      page_width = 256,
      page_height = 128,
      padding = 1,
   })
   profiler_style:warm_text(
      "CPU PRS TOT INT GAP OVR CUR MAX VSYNC ANIM PROFILER ON OFF [] 0123456789./-"
   )
end

local function release_scene()
   frame_profiler = nil
   if profiler_style ~= nil then
      profiler_style:release()
      profiler_style = nil
   end
   if face ~= nil then
      face:release()
      face = nil
   end
   font_path = nil
end

local function render_frame()
   frame_profiler:begin_cpu()
   local renderer = sdl3.get_renderer()

   set_draw_color(renderer, 6, 8, 18, 255)
   if not sdl3.RenderClear(renderer) then
      error("failed to clear SDL renderer: " .. ffi.string(sdl3.GetError()), 0)
   end

   set_draw_color(renderer, 24, 28, 44, 255)
   fill_rect(renderer, 0, window_height * 0.5 - 1, window_width, 2)

   if scene.animation_enabled then
      local t = time.monotonic() - scene.start_time
      local orbit = 0.5 + 0.5 * math.sin(t * 1.15)
      local bob = 0.5 + 0.5 * math.sin(t * 2.4)
      local size = 92 + 28 * math.sin(t * 1.8 + 0.6)
      local x = orbit * (window_width - size)
      local y = (window_height * 0.5 - size * 0.5) + (bob - 0.5) * 180

      set_draw_color(renderer, 240, 246, 255, 255)
      fill_rect(renderer, x, y, size, size)
   end

   if profiler_enabled then
      draw_profiler(renderer)
   end
   frame_profiler:end_cpu()
end

rig.run {
   mode = "sdl3",
   event_handlers = {
      key = on_key,
      resize = on_resize,
   },
   driver_config = {
      sdl3 = {
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig SDL Renderer Baseline",
            [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
         },
         render = render_frame,
      },
   },
   hooks = {
      after_setup = initialize_scene,
      before_frame = function()
         frame_profiler:begin_frame()
      end,
      after_frame = function()
         frame_profiler:end_frame()
      end,
      before_shutdown = release_scene,
   },
}
