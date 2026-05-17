local sdl3 = require("sdl3")
local time = require("time")
local font = require("font")
local ffi = ffi

local window_width = 1280
local window_height = 720
local perf_frequency = tonumber(sdl3.GetPerformanceFrequency())

local draw_rect = ffi.new("SDL_FRect[1]")

local scene = {
   start_time = nil,
   font_path = nil,
   face = nil,
   profiler_face = nil,
   profiler_atlas = nil,
   profiler_textures = nil,
   profiler_cpu_ms = 0.0,
   profiler_cpu_max_1s_ms = 0.0,
   profiler_cpu_max_ms = 0.0,
   profiler_present_ms = 0.0,
   profiler_present_max_1s_ms = 0.0,
   profiler_present_max_ms = 0.0,
   profiler_total_ms = 0.0,
   profiler_total_max_1s_ms = 0.0,
   profiler_total_max_ms = 0.0,
   profiler_interval_ms = 0.0,
   profiler_interval_max_1s_ms = 0.0,
   profiler_interval_max_ms = 0.0,
   profiler_gap_ms = 0.0,
   profiler_gap_max_1s_ms = 0.0,
   profiler_gap_max_ms = 0.0,
   profiler_overruns = 0,
   profiler_last_frame_counter = nil,
   profiler_frame_start_counter = nil,
   profiler_cpu_history = {},
   profiler_present_history = {},
   profiler_total_history = {},
   profiler_interval_history = {},
   profiler_gap_history = {},
   profiler_enabled = true,
   vsync_enabled = true,
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

local function upload_gray_page_texture(renderer, page)
   local texture = sdl3.CreateTexture(
      renderer,
      sdl3.PIXELFORMAT_RGBA32,
      sdl3.TEXTUREACCESS_STATIC,
      page.width,
      page.height
   )
   if texture == nil then
      error("failed to create SDL texture: " .. ffi.string(sdl3.GetError()), 0)
   end

   local rgba = ffi.new("uint8_t[?]", page.width * page.height * 4)
   for i = 0, (page.width * page.height) - 1 do
      local alpha = page.buffer[i]
      local base = i * 4
      rgba[base + 0] = 255
      rgba[base + 1] = 255
      rgba[base + 2] = 255
      rgba[base + 3] = alpha
   end

   if not sdl3.UpdateTexture(texture, nil, rgba, page.width * 4) then
      error("failed to upload SDL texture: " .. ffi.string(sdl3.GetError()), 0)
   end
   if not sdl3.SetTextureBlendMode(texture, sdl3.BLENDMODE_BLEND) then
      error("failed to set SDL texture blend mode: " .. ffi.string(sdl3.GetError()), 0)
   end

   return texture
end

local function upload_atlas_textures(renderer, atlas)
   local textures = {}
   local pages = atlas.pages
   for i = 1, #pages do
      textures[i] = upload_gray_page_texture(renderer, pages[i])
   end
   return textures
end

local function destroy_textures(textures)
   if textures == nil then
      return
   end
   for i = 1, #textures do
      if textures[i] ~= nil and textures[i] ~= ffi.NULL then
         sdl3.DestroyTexture(textures[i])
      end
   end
end

local function build_text_run(sized_face, atlas, text)
   local shaped = font.shape(sized_face, text)
   local entries = {}
   local pen_x = 0.0
   local pen_y = 0.0

   for i = 1, #shaped.glyphs do
      local glyph = shaped.glyphs[i]
      local packed = atlas:get_glyph(glyph.glyph_id)
      entries[#entries + 1] = {
         packed = packed,
         layout_x = pen_x + glyph.x_offset + packed.left,
         layout_y = pen_y - glyph.y_offset - packed.top,
      }
      pen_x = pen_x + glyph.x_advance
      pen_y = pen_y + glyph.y_advance
   end

   return {
      entries = entries,
      width = shaped.x_advance,
   }
end

local function warm_atlas_text(sized_face, atlas, text)
   local shaped = font.shape(sized_face, text)
   for i = 1, #shaped.glyphs do
      atlas:get_glyph(shaped.glyphs[i].glyph_id)
   end
end

local src_rect = ffi.new("SDL_FRect[1]")
local dst_rect = ffi.new("SDL_FRect[1]")

local function draw_packed_glyph(renderer, textures, packed, x, y, scale, r, g, b, a)
   if packed.width <= 0 or packed.height <= 0 then
      return
   end

   local texture = textures[packed.page_index]
   if texture == nil or texture == ffi.NULL then
      return
   end

   src_rect[0].x = packed.x
   src_rect[0].y = packed.y
   src_rect[0].w = packed.width
   src_rect[0].h = packed.height

   dst_rect[0].x = x
   dst_rect[0].y = y
   dst_rect[0].w = packed.width * scale
   dst_rect[0].h = packed.height * scale

   if not sdl3.SetTextureColorMod(texture, r, g, b) then
      error("failed to set SDL texture color mod: " .. ffi.string(sdl3.GetError()), 0)
   end
   if not sdl3.SetTextureAlphaMod(texture, a) then
      error("failed to set SDL texture alpha mod: " .. ffi.string(sdl3.GetError()), 0)
   end
   if not sdl3.RenderTexture(renderer, texture, src_rect, dst_rect) then
      error("failed to render SDL texture: " .. ffi.string(sdl3.GetError()), 0)
   end
end

local function draw_text_run(renderer, textures, run, base_x, baseline_y, r, g, b, a)
   for i = 1, #run.entries do
      local entry = run.entries[i]
      draw_packed_glyph(
         renderer,
         textures,
         entry.packed,
         base_x + entry.layout_x,
         baseline_y + entry.layout_y,
         1.0,
         r,
         g,
         b,
         a
      )
   end
end

local function draw_label(renderer, text, x, baseline_y, r, g, b, a)
   local run = build_text_run(scene.profiler_face, scene.profiler_atlas, text)
   draw_text_run(renderer, scene.profiler_textures, run, x, baseline_y, r, g, b, a)
end

local function update_metric_history(history, now_seconds, value)
   history[#history + 1] = {
      t = now_seconds,
      v = value,
   }

   local cutoff = now_seconds - 1.0
   while history[1] ~= nil and history[1].t < cutoff do
      table.remove(history, 1)
   end

   local max_1s = 0.0
   for i = 1, #history do
      if history[i].v > max_1s then
         max_1s = history[i].v
      end
   end
   return max_1s
end

local function set_vsync(enabled)
   local renderer = sdl3.get_renderer()
   local interval = enabled and 1 or 0
   if not sdl3.SetRenderVSync(renderer, interval) then
      error("failed to set renderer vsync: " .. ffi.string(sdl3.GetError()), 0)
   end
   scene.vsync_enabled = enabled
end

local function toggle_vsync()
   set_vsync(not scene.vsync_enabled)
end

local function on_key(key_info)
   if key_info.action ~= "down" or key_info["repeat"] then
      return
   end

   if key_info.key == "0" then
      scene.profiler_enabled = not scene.profiler_enabled
   elseif key_info.key == "1" then
      scene.animation_enabled = not scene.animation_enabled
   elseif key_info.key == "V" or key_info.key == "v" then
      toggle_vsync()
   end
end

local function draw_profiler(renderer)
   local panel_x = 18
   local panel_y = 16
   local panel_w = 378
   local panel_h = 162

   set_draw_color(renderer, 0, 0, 0, 150)
   fill_rect(renderer, panel_x, panel_y, panel_w, panel_h)

   local text_x = panel_x + 10
   local header = "      CUR / 1S / MAX"
   local line_1 = ("CPU %.2f / %.2f / %.2f"):format(scene.profiler_cpu_ms, scene.profiler_cpu_max_1s_ms, scene.profiler_cpu_max_ms)
   local line_2 = ("PRS %.2f / %.2f / %.2f"):format(scene.profiler_present_ms, scene.profiler_present_max_1s_ms, scene.profiler_present_max_ms)
   local line_3 = ("TOT %.2f / %.2f / %.2f"):format(scene.profiler_total_ms, scene.profiler_total_max_1s_ms, scene.profiler_total_max_ms)
   local line_4 = ("INT %.2f / %.2f / %.2f"):format(scene.profiler_interval_ms, scene.profiler_interval_max_1s_ms, scene.profiler_interval_max_ms)
   local line_5 = ("GAP %.2f / %.2f / %.2f"):format(scene.profiler_gap_ms, scene.profiler_gap_max_1s_ms, scene.profiler_gap_max_ms)
   local line_6 = ("OVR %d"):format(scene.profiler_overruns)
   local line_7 = scene.vsync_enabled and "VSYNC ON [V]" or "VSYNC OFF [V]"
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

local function initialize_scene()
   local renderer = sdl3.get_renderer()
   scene.start_time = time.monotonic()
   scene.font_path = find_font_path()
   scene.face = font.load_face(scene.font_path)
   scene.profiler_face = scene.face:create_sized_face(14)
   scene.profiler_atlas = scene.profiler_face:create_atlas {
      page_width = 256,
      page_height = 128,
      padding = 1,
   }
   warm_atlas_text(
      scene.profiler_face,
      scene.profiler_atlas,
      "CPU PRS TOT INT GAP OVR CUR MAX VSYNC ANIM PROFILER ON OFF [] 0123456789./-"
   )
   scene.profiler_textures = upload_atlas_textures(renderer, scene.profiler_atlas)
end

local function release_scene()
   destroy_textures(scene.profiler_textures)
   scene.profiler_textures = nil

   if scene.profiler_atlas ~= nil then
      scene.profiler_atlas:release()
      scene.profiler_atlas = nil
   end
   if scene.profiler_face ~= nil then
      scene.profiler_face:release()
      scene.profiler_face = nil
   end
   if scene.face ~= nil then
      scene.face:release()
      scene.face = nil
   end
end

local function begin_frame_profile()
   local frame_start = tonumber(sdl3.GetPerformanceCounter())
   local frame_start_seconds = frame_start / perf_frequency
   local last_frame_counter = scene.profiler_last_frame_counter

   if last_frame_counter ~= nil then
      scene.profiler_interval_ms = (frame_start - last_frame_counter) * 1000.0 / perf_frequency
      if scene.profiler_interval_ms > scene.profiler_interval_max_ms then
         scene.profiler_interval_max_ms = scene.profiler_interval_ms
      end
      scene.profiler_interval_max_1s_ms =
         update_metric_history(scene.profiler_interval_history, frame_start_seconds, scene.profiler_interval_ms)

      local gap_ms = scene.profiler_interval_ms - scene.profiler_total_ms
      if gap_ms < 0.0 then
         gap_ms = 0.0
      end
      scene.profiler_gap_ms = gap_ms
      if scene.profiler_gap_ms > scene.profiler_gap_max_ms then
         scene.profiler_gap_max_ms = scene.profiler_gap_ms
      end
      scene.profiler_gap_max_1s_ms =
         update_metric_history(scene.profiler_gap_history, frame_start_seconds, scene.profiler_gap_ms)
   end

   scene.profiler_last_frame_counter = frame_start
   scene.profiler_frame_start_counter = frame_start
end

local function end_frame_profile()
   local frame_start = scene.profiler_frame_start_counter
   if frame_start == nil then
      return
   end

   local frame_end = tonumber(sdl3.GetPerformanceCounter())
   local frame_end_seconds = frame_end / perf_frequency

   scene.profiler_total_ms = (frame_end - frame_start) * 1000.0 / perf_frequency
   if scene.profiler_total_ms > scene.profiler_total_max_ms then
      scene.profiler_total_max_ms = scene.profiler_total_ms
   end
   scene.profiler_total_max_1s_ms =
      update_metric_history(scene.profiler_total_history, frame_end_seconds, scene.profiler_total_ms)

   local present_ms = scene.profiler_total_ms - scene.profiler_cpu_ms
   if present_ms < 0.0 then
      present_ms = 0.0
   end
   scene.profiler_present_ms = present_ms
   if scene.profiler_present_ms > scene.profiler_present_max_ms then
      scene.profiler_present_max_ms = scene.profiler_present_ms
   end
   scene.profiler_present_max_1s_ms =
      update_metric_history(scene.profiler_present_history, frame_end_seconds, scene.profiler_present_ms)

   if scene.profiler_total_ms > 16.67 then
      scene.profiler_overruns = scene.profiler_overruns + 1
   end

   scene.profiler_frame_start_counter = nil
end

local function render_frame()
   local frame_start = tonumber(sdl3.GetPerformanceCounter())
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

   if scene.profiler_enabled then
      draw_profiler(renderer)
   end

   local frame_end = tonumber(sdl3.GetPerformanceCounter())
   local frame_end_seconds = frame_end / perf_frequency
   scene.profiler_cpu_ms = (frame_end - frame_start) * 1000.0 / perf_frequency
   if scene.profiler_cpu_ms > scene.profiler_cpu_max_ms then
      scene.profiler_cpu_max_ms = scene.profiler_cpu_ms
   end
   scene.profiler_cpu_max_1s_ms =
      update_metric_history(scene.profiler_cpu_history, frame_end_seconds, scene.profiler_cpu_ms)
end

rig.run {
   mode = "sdl3",
   sdl3 = {
      window_props = {
         [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig SDL Renderer Baseline",
         [sdl3.PROP_WINDOW_CREATE_WIDTH_NUMBER] = window_width,
         [sdl3.PROP_WINDOW_CREATE_HEIGHT_NUMBER] = window_height,
      },
      on_key = on_key,
      on_render = render_frame,
   },
   hooks = {
      after_setup = initialize_scene,
      before_frame = begin_frame_profile,
      after_frame = end_frame_profile,
      before_shutdown = release_scene,
   },
}
