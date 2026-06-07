local ffi = require("ffi")

local font = require("font")
local gl = require("gl")
local profiler = require("profiler")
local sdl3 = require("sdl3")
local time = require("time")

-- Populated by the initial sdl3_gl on_resize callback before after_setup runs.
local window_width
local window_height
local font_path
local face
local profiler_style
local frame_profiler
local profiler_enabled = true
local vsync_enabled = true

local gl_vertex_arrays = ffi.new("GLuint[1]")
local gl_buffers = ffi.new("GLuint[1]")
local rect_vertices = ffi.new("float[12]")

local scene = {
   start_time = nil,
   rect_program = 0,
   rect_vao = 0,
   rect_vbo = 0,
   rect_view_size_location = -1,
   rect_color_location = -1,
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
   local run = profiler_style:build_run(text)
   profiler_style:draw_run(run, x, baseline_y, function()
      return r, g, b, a
   end)
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
   gl.UseProgram(scene.rect_program)
   gl.Uniform2f(scene.rect_view_size_location, window_width, window_height)
   gl.Uniform4f(scene.rect_color_location, r / 255.0, g / 255.0, b / 255.0, a / 255.0)
   gl.BindVertexArray(scene.rect_vao)
   gl.BindBuffer(gl.ARRAY_BUFFER, scene.rect_vbo)
   gl.BufferData(gl.ARRAY_BUFFER, ffi.sizeof(rect_vertices), rect_vertices, gl.DYNAMIC_DRAW)
   gl.DrawArrays(gl.TRIANGLES, 0, 6)
end

local function set_vsync(enabled)
   local interval = enabled and 1 or 0
   if not sdl3.GL_SetSwapInterval(interval) then
      error("failed to set OpenGL swap interval: " .. ffi.string(sdl3.GetError()), 0)
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

local function draw_profiler()
   local profile = frame_profiler:snapshot()
   local panel_x = 18
   local panel_y = 16
   local panel_w = math.min(378, math.max(220, window_width - panel_x * 2))
   local panel_h = 162

   draw_rect(panel_x, panel_y, panel_w, panel_h, 0, 0, 0, 150)

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
   font_path = find_font_path()
   face = font.load_face(font_path)
   frame_profiler = profiler.create_frame_profiler()
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

local function initialize_gl_resources()
   scene.rect_program = gl.create_program {
      vertex_source = rect_vertex_shader_source,
      fragment_source = rect_fragment_shader_source,
   }

   gl.GenVertexArrays(1, gl_vertex_arrays)
   gl.GenBuffers(1, gl_buffers)
   scene.rect_vao = tonumber(gl_vertex_arrays[0]) or 0
   scene.rect_vbo = tonumber(gl_buffers[0]) or 0

   if scene.rect_vao == 0 or scene.rect_vbo == 0 then
      error("failed to create OpenGL rectangle resources", 0)
   end

   gl.BindVertexArray(scene.rect_vao)
   gl.BindBuffer(gl.ARRAY_BUFFER, scene.rect_vbo)
   gl.EnableVertexAttribArray(0)
   gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, ffi.sizeof("float") * 2, ffi.cast("const void *", 0))

   scene.rect_view_size_location = gl.get_uniform_location(scene.rect_program, "u_view_size")
   scene.rect_color_location = gl.get_uniform_location(scene.rect_program, "u_color")
   if scene.rect_view_size_location < 0 or scene.rect_color_location < 0 then
      error("failed to locate OpenGL rectangle uniforms", 0)
   end
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

local function release_gl_resources()
   if scene.rect_vbo ~= 0 then
      gl_buffers[0] = scene.rect_vbo
      gl.DeleteBuffers(1, gl_buffers)
      scene.rect_vbo = 0
   end
   if scene.rect_vao ~= 0 then
      gl_vertex_arrays[0] = scene.rect_vao
      gl.DeleteVertexArrays(1, gl_vertex_arrays)
      scene.rect_vao = 0
   end
   if scene.rect_program ~= 0 then
      gl.DeleteProgram(scene.rect_program)
      scene.rect_program = 0
   end
   scene.rect_view_size_location = -1
   scene.rect_color_location = -1
end

local function render_frame()
   frame_profiler:begin_cpu()

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

   if profiler_enabled then
      draw_profiler()
   end
   frame_profiler:end_cpu()
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
   event_handlers = {
      key = on_key,
      resize = on_resize,
   },
   driver_config = {
      sdl3_gl = {
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig OpenGL Baseline",
            [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
         },
         gl_attributes = {
            context_major_version = 4,
            context_minor_version = 5,
            context_profile = "core",
            doublebuffer = true,
         },
         swap_interval = 1,
         render = render_frame,
      },
   },
   hooks = {
      after_setup = after_setup,
      before_frame = function()
         frame_profiler:begin_frame()
      end,
      after_frame = function()
         frame_profiler:end_frame()
      end,
      before_shutdown = before_shutdown,
   },
}
