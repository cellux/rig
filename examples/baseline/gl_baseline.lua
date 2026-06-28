local animator = require("animator")
local color = require("color")
local ffi = require("ffi")
local font = require("font")
local gl = require("gl")
local glx = require("glx")
local profiler = require("profiler")
local scenegraph = require("scenegraph")
local sdl3 = require("sdl3")

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

local gl_vertex_arrays = ffi.new("GLuint[1]")
local rect_vertices = ffi.new("float[12]")
local find_font_path

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

local function draw_label(style, text, x, baseline_y, draw_color)
   local run = style:build_run(text)
   style:draw_run(run, x, baseline_y, function()
      return draw_color
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

local function draw_rect(scene, x, y, w, h, r, g, b, a)
   write_rect_vertices(x, y, w, h)

   gl.Enable(gl.BLEND)
   gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
   scene.rect_program:use()
   gl.Uniform2f(scene.rect_view_size_location, window_width, window_height)
   gl.Uniform4f(scene.rect_color_location, r / 255.0, g / 255.0, b / 255.0, a / 255.0)
   gl.BindVertexArray(scene.rect_vao)
   scene.rect_vbo:set_data(rect_vertices, gl.DYNAMIC_DRAW)
   gl.DrawArrays(gl.TRIANGLES, 0, 6)
end

local function set_vsync(enabled)
   local interval = enabled and 1 or 0
   if not sdl3.GL_SetSwapInterval(interval) then
      rig.raise("failed to set OpenGL swap interval: " .. ffi.string(sdl3.GetError()))
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

function MovingSquare:draw()
   local orbit = 0.5 + 0.5 * math.sin(self.elapsed * 1.15)
   local bob = 0.5 + 0.5 * math.sin(self.elapsed * 2.4)
   local size = 92 + 28 * math.sin(self.elapsed * 1.8 + 0.6)
   local x = orbit * (window_width - size)
   local y = (window_height * 0.5 - size * 0.5) + (bob - 0.5) * 180

   draw_rect(self.parent, x, y, size, size, 240, 246, 255, 255)
end

function ProfilerOverlay:init()
   self:super().init(self)
end

function ProfilerOverlay:draw(context)
   local profile = context.frame_profiler:snapshot()
   local panel_x = 18
   local panel_y = 16
   local panel_w = math.min(378, math.max(220, window_width - panel_x * 2))
   local panel_h = 162

   draw_rect(context.scene, panel_x, panel_y, panel_w, panel_h, 0, 0, 0, 150)

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

   draw_label(context.profiler_style, header, text_x, panel_y + 16, profiler_header_color)
   draw_label(context.profiler_style, line_1, text_x, panel_y + 32, profiler_body_color)
   draw_label(context.profiler_style, line_2, text_x, panel_y + 48, profiler_body_color)
   draw_label(context.profiler_style, line_3, text_x, panel_y + 64, profiler_body_color)
   draw_label(context.profiler_style, line_4, text_x, panel_y + 80, profiler_body_color)
   draw_label(context.profiler_style, line_5, text_x, panel_y + 96, profiler_body_color)
   draw_label(context.profiler_style, line_6, text_x, panel_y + 112, profiler_warn_color)
   draw_label(context.profiler_style, line_7, text_x, panel_y + 128, profiler_toggle_color)
   draw_label(context.profiler_style, line_8, text_x, panel_y + 144, profiler_toggle_color)
   draw_label(context.profiler_style, line_9, text_x + 150, panel_y + 144, profiler_toggle_color)
end

function Scene:init()
   self:super().init(self)
   self.rect_program = nil
   self.rect_vao = 0
   self.rect_vbo = nil
   self.rect_view_size_location = -1
   self.rect_color_location = -1
   self.moving_square = self:add_child(MovingSquare())
   self.profiler_overlay = self:add_child(ProfilerOverlay())
end

function Scene:activate()
   self.rect_program = self:replace_owned("rect_program", glx.Program {
      vertex_source = rect_vertex_shader_source,
      fragment_source = rect_fragment_shader_source,
   }, function(_, program)
      program:release()
   end)

   self.rect_vbo = self:replace_owned("rect_vbo", glx.Buffer {
      target = gl.ARRAY_BUFFER,
   }, function(_, vbo)
      vbo:release()
   end)

   gl.GenVertexArrays(1, gl_vertex_arrays)
   self.rect_vao = self:replace_owned("rect_vao", tonumber(gl_vertex_arrays[0]) or 0, function(_, vao)
      if vao ~= 0 then
         gl_vertex_arrays[0] = vao
         gl.DeleteVertexArrays(1, gl_vertex_arrays)
      end
   end)

   if self.rect_vao == 0 then
      rig.raise("failed to create OpenGL rectangle resources")
   end

   gl.BindVertexArray(self.rect_vao)
   self.rect_vbo:bind()
   gl.EnableVertexAttribArray(0)
   gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, ffi.sizeof("float") * 2, ffi.cast("const void *", 0))

   self.rect_view_size_location = self.rect_program:uniform_location("u_view_size")
   self.rect_color_location = self.rect_program:uniform_location("u_color")
   if self.rect_view_size_location < 0 or self.rect_color_location < 0 then
      rig.raise("failed to locate OpenGL rectangle uniforms")
   end
end

function Scene:draw()
   gl.Viewport(0, 0, window_width, window_height)
   gl.ClearColor(6.0 / 255.0, 8.0 / 255.0, 18.0 / 255.0, 1.0)
   gl.Clear(gl.COLOR_BUFFER_BIT)

   draw_rect(self, 0, window_height * 0.5 - 1, window_width, 2, 24, 28, 44, 255)
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

function Scene:on_resize(info)
   window_width = math.max(1, info.pixel_width)
   window_height = math.max(1, info.pixel_height)
end

function Scene:release()
   self.rect_vbo = nil
   self.rect_vao = 0
   self.rect_program = nil
   self.rect_view_size_location = -1
   self.rect_color_location = -1
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
   window_width = math.max(1, info.pixel_width)
   window_height = math.max(1, info.pixel_height)
   if self.root ~= nil then
      self.root:on_resize(info)
   end
end

function App:render()
   self.frame_profiler:begin_cpu()
   if self.root ~= nil then
      self.root:draw_tree({
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
   mode = "sdl3_gl",
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
      },
   },
   app = App,
}
