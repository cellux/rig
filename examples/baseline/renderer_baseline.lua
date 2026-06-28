local animator = require("animator")
local color = require("color")
local font = require("font")
local profiler = require("profiler")
local scenegraph = require("scenegraph")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")
local ffi = require("ffi")

local Object = scenegraph.Object
local MovingSquare = rig.Class(Object)
local ProfilerOverlay = rig.Class(Object)
local Scene = rig.Class(Object)
local App = rig.Class(animator.App)

local window_width
local window_height
local font_path
local face
local profiler_style
local frame_profiler
local profiler_enabled = true
local vsync_enabled = true
local profiler_header_color = color.rgb(255, 184, 150)
local profiler_body_color = color.rgb(255, 248, 224)
local profiler_warn_color = color.rgb(255, 214, 160)
local profiler_toggle_color = color.rgb(196, 220, 255)

local draw_rect = ffi.new("SDL_FRect[1]")
local find_font_path

local function file_exists(path)
   local file = io.open(path, "rb")
   if file == nil then
      return false
   end
   file:close()
   return true
end

find_font_path = function()
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

   rig.raise("could not find a system DejaVuSans.ttf font")
end

local function set_draw_color(renderer, r, g, b, a)
   if not sdl3.SetRenderDrawColor(renderer, r, g, b, a) then
      rig.raise("failed to set draw color: " .. sdl3x.get_error())
   end
end

local function fill_rect(renderer, x, y, w, h)
   draw_rect[0].x = x
   draw_rect[0].y = y
   draw_rect[0].w = w
   draw_rect[0].h = h
   if not sdl3.RenderFillRect(renderer, draw_rect) then
      rig.raise("failed to fill rect: " .. sdl3x.get_error())
   end
end

local function draw_label(style, renderer, text, x, baseline_y, draw_color)
   local run = style:build_run(text)
   style:draw_run(run, x, baseline_y, function()
      return draw_color
   end)
end

local function set_vsync(enabled)
   local renderer = sdl3x.get_renderer()
   local interval = enabled and 1 or 0
   if not sdl3.SetRenderVSync(renderer, interval) then
      rig.raise("failed to set renderer vsync: " .. sdl3x.get_error())
   end
   vsync_enabled = enabled
end

local function toggle_vsync()
   set_vsync(not vsync_enabled)
end

function MovingSquare:init()
   self:super().init(self)
   self.elapsed = 0.0
end

function MovingSquare:update(dt)
   self.elapsed = self.elapsed + dt
end

function MovingSquare:draw(context)
   local renderer = context.renderer
   local orbit = 0.5 + 0.5 * math.sin(self.elapsed * 1.15)
   local bob = 0.5 + 0.5 * math.sin(self.elapsed * 2.4)
   local size = 92 + 28 * math.sin(self.elapsed * 1.8 + 0.6)
   local x = orbit * (window_width - size)
   local y = (window_height * 0.5 - size * 0.5) + (bob - 0.5) * 180

   set_draw_color(renderer, 240, 246, 255, 255)
   fill_rect(renderer, x, y, size, size)
end

function ProfilerOverlay:init()
   self:super().init(self)
end

function ProfilerOverlay:draw(context)
   local renderer = context.renderer
   local profile = context.frame_profiler:snapshot()
   local panel_x = 18
   local panel_y = 16
   local panel_w = math.min(378, math.max(220, window_width - panel_x * 2))
   local panel_h = 162

   set_draw_color(renderer, 0, 0, 0, 150)
   fill_rect(renderer, panel_x, panel_y, panel_w, panel_h)

   local text_x = panel_x + 10
   local header = "      CUR / 1S / MAX"
   local line_1 = ("CPU %.2f / %.2f / %.2f"):format(profile.cpu_ms, profile.cpu_window_max_ms, profile.cpu_peak_ms)
   local line_2 = ("PRS %.2f / %.2f / %.2f"):format(profile.present_ms, profile.present_window_max_ms, profile.present_peak_ms)
   local line_3 = ("TOT %.2f / %.2f / %.2f"):format(profile.total_ms, profile.total_window_max_ms, profile.total_peak_ms)
   local line_4 = ("INT %.2f / %.2f / %.2f"):format(profile.interval_ms, profile.interval_window_max_ms, profile.interval_peak_ms)
   local line_5 = ("GAP %.2f / %.2f / %.2f"):format(profile.gap_ms, profile.gap_window_max_ms, profile.gap_peak_ms)
   local line_6 = ("OVR %d"):format(profile.overruns)
   local line_7 = vsync_enabled and "VSYNC ON [V]" or "VSYNC OFF [V]"
   local line_8 = context.scene.animator.animate_enabled and "ANIM ON [1]" or "ANIM OFF [1]"
   local line_9 = "PROFILER ON [0]"

   draw_label(context.profiler_style, renderer, header, text_x, panel_y + 16, profiler_header_color)
   draw_label(context.profiler_style, renderer, line_1, text_x, panel_y + 32, profiler_body_color)
   draw_label(context.profiler_style, renderer, line_2, text_x, panel_y + 48, profiler_body_color)
   draw_label(context.profiler_style, renderer, line_3, text_x, panel_y + 64, profiler_body_color)
   draw_label(context.profiler_style, renderer, line_4, text_x, panel_y + 80, profiler_body_color)
   draw_label(context.profiler_style, renderer, line_5, text_x, panel_y + 96, profiler_body_color)
   draw_label(context.profiler_style, renderer, line_6, text_x, panel_y + 112, profiler_warn_color)
   draw_label(context.profiler_style, renderer, line_7, text_x, panel_y + 128, profiler_toggle_color)
   draw_label(context.profiler_style, renderer, line_8, text_x, panel_y + 144, profiler_toggle_color)
   draw_label(context.profiler_style, renderer, line_9, text_x + 150, panel_y + 144, profiler_toggle_color)
end

function Scene:init()
   self:super().init(self)
   self.moving_square = self:add_child(MovingSquare())
   self.profiler_overlay = self:add_child(ProfilerOverlay())
end

function Scene:draw(context)
   local renderer = context.renderer

   set_draw_color(renderer, 6, 8, 18, 255)
   if not sdl3.RenderClear(renderer) then
      rig.raise("failed to clear SDL renderer: " .. sdl3x.get_error())
   end

   set_draw_color(renderer, 24, 28, 44, 255)
   fill_rect(renderer, 0, window_height * 0.5 - 1, window_width, 2)
end

function Scene:set_animation_enabled(enabled)
   self.moving_square.enabled = enabled
   self.animator:set_enabled(enabled)
end

function Scene:on_key(key_info)
   if key_info.action ~= "down" or key_info["repeat"] then
      return
   end

   if key_info.key == "0" then
      profiler_enabled = not profiler_enabled
      self.profiler_overlay.enabled = profiler_enabled
   elseif key_info.key == "1" then
      self:set_animation_enabled(not self.animator.animate_enabled)
   elseif key_info.key == "V" or key_info.key == "v" then
      toggle_vsync()
   end
end

function Scene:release()
   self.moving_square = nil
   self.profiler_overlay = nil
end

function App:init()
   self:super().init(self)

   font_path = find_font_path()
   face = font.load_face(font_path)
   frame_profiler = profiler.FrameProfiler {
      fps = 60,
   }
   profiler_style = font.create_style(face, {
      pixel_size = 14,
      page_width = 256,
      page_height = 128,
      padding = 1,
   })
   profiler_style:warm_text(
      "CPU PRS TOT INT GAP OVR CUR MAX VSYNC ANIM PROFILER ON OFF [] 0123456789./-"
   )

   self.frame_profiler = frame_profiler
   self.profiler_style = profiler_style
   self.root = Scene()
end

function App:before_frame()
   self.frame_profiler:begin_frame()
end

function App:after_frame()
   self.frame_profiler:end_frame()
end

function App:on_key(key_info)
   if self.root ~= nil then
      self.root:on_key(key_info)
   end
end

function App:on_resize(info)
   window_width = math.max(1, info.width)
   window_height = math.max(1, info.height)
end

function App:render()
   self.frame_profiler:begin_cpu()
   local renderer = sdl3x.get_renderer()
   if self.root ~= nil then
      self.root:draw_tree({
         renderer = renderer,
         frame_profiler = self.frame_profiler,
         profiler_style = self.profiler_style,
         scene = self.root,
      })
   end
   self.frame_profiler:end_cpu()
end

function App:release()
   self.frame_profiler = nil
   self.profiler_style = nil
   profiler_style:release()
   profiler_style = nil
   face:release()
   face = nil
   frame_profiler = nil
   font_path = nil
end

rig.run {
   mode = "sdl3",
   driver_config = {
      sdl3 = {
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig SDL Renderer Baseline",
            [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
         },
      },
   },
   app = App,
}
