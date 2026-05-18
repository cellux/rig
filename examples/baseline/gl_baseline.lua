local ffi = require("ffi")

local font = require("font")
local gl = require("gl")
local sdl3 = require("sdl3")
local time = require("time")

local window_width = 1280
local window_height = 720
local perf_frequency = tonumber(sdl3.GetPerformanceFrequency())

local rect_program = 0
local rect_vao = 0
local rect_vbo = 0
local rect_view_size_location = -1
local rect_color_location = -1

local gl_vertex_arrays = ffi.new("GLuint[1]")
local gl_buffers = ffi.new("GLuint[1]")
local rect_vertices = ffi.new("float[12]")

local scene = {
   start_time = nil,
   font_path = nil,
   face = nil,
   profiler_face = nil,
   profiler_atlas = nil,
   profiler_text_renderer = nil,
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

local rect_vertex_shader_source = [[
#version 330 core

layout(location = 0) in vec2 in_position;

uniform vec2 u_view_size;

void main()
{
   vec2 clip = vec2(
      (in_position.x / u_view_size.x) * 2.0 - 1.0,
      1.0 - (in_position.y / u_view_size.y) * 2.0
   );
   gl_Position = vec4(clip, 0.0, 1.0);
}
]]

local rect_fragment_shader_source = [[
#version 330 core

uniform vec4 u_color;

out vec4 frag_color;

void main()
{
   frag_color = u_color;
}
]]

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

local function draw_label(text, x, baseline_y, r, g, b, a)
   local run = scene.profiler_atlas:build_text_run(text)
   scene.profiler_text_renderer:draw_text_run(run, x, baseline_y, function()
      return r, g, b, a
   end)
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

local function write_rect_vertices(x, y, w, h)
   local x1 = x
   local y1 = y
   local x2 = x + w
   local y2 = y + h

   rect_vertices[0] = x1
   rect_vertices[1] = y1
   rect_vertices[2] = x2
   rect_vertices[3] = y1
   rect_vertices[4] = x2
   rect_vertices[5] = y2
   rect_vertices[6] = x1
   rect_vertices[7] = y1
   rect_vertices[8] = x2
   rect_vertices[9] = y2
   rect_vertices[10] = x1
   rect_vertices[11] = y2
end

local function draw_rect(x, y, w, h, r, g, b, a)
   write_rect_vertices(x, y, w, h)

   gl.Enable(gl.BLEND)
   gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
   gl.UseProgram(rect_program)
   gl.Uniform2f(rect_view_size_location, window_width, window_height)
   gl.Uniform4f(rect_color_location, r / 255.0, g / 255.0, b / 255.0, a / 255.0)
   gl.BindVertexArray(rect_vao)
   gl.BindBuffer(gl.ARRAY_BUFFER, rect_vbo)
   gl.BufferData(gl.ARRAY_BUFFER, ffi.sizeof(rect_vertices), rect_vertices, gl.DYNAMIC_DRAW)
   gl.DrawArrays(gl.TRIANGLES, 0, 6)
end

local function set_vsync(enabled)
   local interval = enabled and 1 or 0
   if not sdl3.GL_SetSwapInterval(interval) then
      error("failed to set OpenGL swap interval: " .. ffi.string(sdl3.GetError()), 0)
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

local function draw_profiler()
   local panel_x = 18
   local panel_y = 16
   local panel_w = math.min(378, math.max(220, window_width - panel_x * 2))
   local panel_h = 162

   draw_rect(panel_x, panel_y, panel_w, panel_h, 0, 0, 0, 150)

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

   draw_label(header, text_x, panel_y + 16, 255, 184, 150, 255)
   draw_label(line_1, text_x, panel_y + 32, 255, 248, 224, 255)
   draw_label(line_2, text_x, panel_y + 48, 255, 248, 224, 255)
   draw_label(line_3, text_x, panel_y + 64, 255, 248, 224, 255)
   draw_label(line_4, text_x, panel_y + 80, 255, 248, 224, 255)
   draw_label(line_5, text_x, panel_y + 96, 255, 248, 224, 255)
   draw_label(line_6, text_x, panel_y + 112, 255, 214, 160, 255)
   draw_label(line_7, text_x, panel_y + 128, 196, 220, 255, 255)
   draw_label(line_8, text_x, panel_y + 144, 196, 220, 255, 255)
   draw_label(line_9, text_x + 150, panel_y + 144, 196, 220, 255, 255)
end

local function on_resize(info)
   window_width = math.max(1, info.pixel_width)
   window_height = math.max(1, info.pixel_height)
end

local function initialize_scene()
   scene.start_time = time.monotonic()
   scene.font_path = find_font_path()
   scene.face = font.load_face(scene.font_path)
   scene.profiler_face = scene.face:create_sized_face(14)
   scene.profiler_atlas = scene.profiler_face:create_atlas {
      page_width = 256,
      page_height = 128,
      padding = 1,
   }
   scene.profiler_atlas:warm_text(
      "CPU PRS TOT INT GAP OVR CUR MAX VSYNC ANIM PROFILER ON OFF [] 0123456789./-"
   )
   scene.profiler_text_renderer = scene.profiler_atlas:create_text_renderer()
end

local function initialize_gl_resources()
   rect_program = gl.create_program {
      vertex_source = rect_vertex_shader_source,
      fragment_source = rect_fragment_shader_source,
   }

   gl.GenVertexArrays(1, gl_vertex_arrays)
   gl.GenBuffers(1, gl_buffers)
   rect_vao = tonumber(gl_vertex_arrays[0]) or 0
   rect_vbo = tonumber(gl_buffers[0]) or 0

   if rect_vao == 0 or rect_vbo == 0 then
      error("failed to create OpenGL rectangle resources", 0)
   end

   gl.BindVertexArray(rect_vao)
   gl.BindBuffer(gl.ARRAY_BUFFER, rect_vbo)
   gl.EnableVertexAttribArray(0)
   gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, ffi.sizeof("float") * 2, ffi.cast("const void *", 0))

   rect_view_size_location = gl.get_uniform_location(rect_program, "u_view_size")
   rect_color_location = gl.get_uniform_location(rect_program, "u_color")
   if rect_view_size_location < 0 or rect_color_location < 0 then
      error("failed to locate OpenGL rectangle uniforms", 0)
   end
end

local function release_scene()
   if scene.profiler_text_renderer ~= nil then
      scene.profiler_text_renderer:release()
      scene.profiler_text_renderer = nil
   end

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

local function release_gl_resources()
   if rect_vbo ~= 0 then
      gl_buffers[0] = rect_vbo
      gl.DeleteBuffers(1, gl_buffers)
      rect_vbo = 0
   end
   if rect_vao ~= 0 then
      gl_vertex_arrays[0] = rect_vao
      gl.DeleteVertexArrays(1, gl_vertex_arrays)
      rect_vao = 0
   end
   if rect_program ~= 0 then
      gl.DeleteProgram(rect_program)
      rect_program = 0
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

   gl.Viewport(0, 0, window_width, window_height)
   gl.ClearColor(6.0 / 255.0, 8.0 / 255.0, 18.0 / 255.0, 1.0)
   gl.Clear(gl.COLOR_BUFFER_BIT)

   draw_rect(0, window_height * 0.5 - 1, window_width, 2, 24, 28, 44, 255)

   if scene.animation_enabled then
      local t = time.monotonic() - scene.start_time
      local orbit = 0.5 + 0.5 * math.sin(t * 1.15)
      local bob = 0.5 + 0.5 * math.sin(t * 2.4)
      local size = 92 + 28 * math.sin(t * 1.8 + 0.6)
      local x = orbit * (window_width - size)
      local y = (window_height * 0.5 - size * 0.5) + (bob - 0.5) * 180

      draw_rect(x, y, size, size, 240, 246, 255, 255)
   end

   if scene.profiler_enabled then
      draw_profiler()
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

local function after_setup()
   initialize_scene()
   initialize_gl_resources()
end

local function before_shutdown()
   release_gl_resources()
   release_scene()
end

rig.run {
   mode = "sdl3_gl",
   sdl3_gl = {
      window_props = {
         [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig OpenGL Baseline",
         [sdl3.PROP_WINDOW_CREATE_WIDTH_NUMBER] = window_width,
         [sdl3.PROP_WINDOW_CREATE_HEIGHT_NUMBER] = window_height,
         [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
      },
      gl_attributes = {
         context_major_version = 4,
         context_minor_version = 5,
         context_profile = "core",
         doublebuffer = true,
      },
      swap_interval = 1,
      on_key = on_key,
      on_resize = on_resize,
      on_render = render_frame,
   },
   hooks = {
      after_setup = after_setup,
      before_frame = begin_frame_profile,
      after_frame = end_frame_profile,
      before_shutdown = before_shutdown,
   },
}
