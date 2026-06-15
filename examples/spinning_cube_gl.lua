local ffi = require("ffi")

local animator = require("animator")
local color = require("color")
local gl = require("gl")
local mathx = require("mathx")
local mesh = require("mesh")
local scenegraph = require("scenegraph")
local shader = require("shader")
local sdl3 = require("sdl3")

local Object = scenegraph.Object
local Animator = animator.Animator
local Cube = rig.class(Object)
local Scene = rig.class(Object)

local vertex_shader_source = [[
#version 330 core

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_color;

out vec3 out_color;

uniform mat4 u_mvp;

void main()
{
   gl_Position = u_mvp * vec4(in_position, 1.0);
   out_color = in_color;
}
]]

local fragment_shader_source = [[
#version 330 core

in vec3 out_color;
out vec4 frag_color;

void main()
{
   frag_color = vec4(out_color, 1.0);
}
]]

local rotation_x = mathx.mat4()
local rotation_y = mathx.mat4()
local model = mathx.mat4()
local view = mathx.mat4()
local projection = mathx.mat4()
local mvp = mathx.mat4()
local eye = mathx.vec3(0.0, 0.0, -4.5)
local target = mathx.vec3(0.0, 0.0, 0.0)
local up = mathx.vec3(0.0, 1.0, 0.0)
local background_color = color.rgbaf(0.07, 0.08, 0.11, 1.0)
local cube_face_colors = {
   color.rgb(255, 96, 96),
   color.rgb(96, 224, 128),
   color.rgb(96, 144, 255),
   color.rgb(255, 220, 96),
   color.rgb(240, 112, 255),
   color.rgb(112, 232, 255),
}

local cube_mesh = mesh.make_cube {
   size = 2.0,
   colors = cube_face_colors,
}

local scene = nil
local animation_runtime = animator.make_hooks {
   create_root = function()
      scene = Scene()
      return scene
   end,

   setup = function(root)
      root:initialize_resources()
   end,

   release = function()
      scene = nil
   end,
}
local viewport_width
local viewport_height
local gl_vertex_arrays = ffi.new("GLuint[1]")
local gl_buffers = ffi.new("GLuint[1]")

local function fail(message)
   rig.raise(message)
end

local function build_mvp(out, aspect, x_angle, y_angle)
   mathx.mat4_rotation_x(rotation_x, x_angle)
   mathx.mat4_rotation_y(rotation_y, y_angle)
   mathx.mat4_multiply(model, rotation_x, rotation_y)
   mathx.mat4_look_at_lh(view, eye, target, up)
   mathx.mat4_multiply(model, model, view)
   mathx.mat4_perspective_lh(projection, math.rad(60.0), aspect, 0.1, 100.0)
   return mathx.mat4_multiply(out, model, projection)
end

function Cube:init()
   self:super().init(self)
   self.program = 0
   self.vao = 0
   self.vbo = 0
   self.mvp_location = -1
   self.rotation_x_angle = 0.0
   self.rotation_y_angle = 0.0
end

function Cube:initialize_resources()
   local vertex_shader = shader.create_stage {
      language = "glsl",
      stage = "vertex",
      source_name = "spinning_cube_gl.vert.glsl",
      source = vertex_shader_source,
   }
   local fragment_shader = shader.create_stage {
      language = "glsl",
      stage = "fragment",
      source_name = "spinning_cube_gl.frag.glsl",
      source = fragment_shader_source,
   }

   local ok, linked_or_err = pcall(function()
      return gl.link_program {
         vertex_shader,
         fragment_shader,
      }
   end)
   shader.destroy_stage(vertex_shader)
   shader.destroy_stage(fragment_shader)
   if not ok then
      rig.raise(linked_or_err)
   end
   self.program = linked_or_err

   gl.GenVertexArrays(1, gl_vertex_arrays)
   gl.GenBuffers(1, gl_buffers)
   self.vao = tonumber(gl_vertex_arrays[0]) or 0
   self.vbo = tonumber(gl_buffers[0]) or 0
   if self.vao == 0 or self.vbo == 0 then
      fail("failed to create OpenGL vertex objects")
   end

   gl.BindVertexArray(self.vao)
   gl.BindBuffer(gl.ARRAY_BUFFER, self.vbo)
   gl.buffer_data(gl.ARRAY_BUFFER, cube_mesh.vertex_blob, gl.STATIC_DRAW)

   gl.EnableVertexAttribArray(0)
   gl.VertexAttribPointer(
      0,
      3,
      gl.FLOAT,
      gl.FALSE,
      cube_mesh.vertex_stride,
      ffi.cast("const void *", cube_mesh.attribute_offsets.position)
   )

   gl.EnableVertexAttribArray(1)
   gl.VertexAttribPointer(
      1,
      3,
      gl.FLOAT,
      gl.FALSE,
      cube_mesh.vertex_stride,
      ffi.cast("const void *", cube_mesh.attribute_offsets.color)
   )

   gl.Enable(gl.DEPTH_TEST)
   gl.DepthFunc(gl.LEQUAL)

   self.mvp_location = gl.get_uniform_location(self.program, "u_mvp")
   if self.mvp_location < 0 then
      fail("failed to locate OpenGL uniform 'u_mvp'")
   end
end

function Cube:update(dt)
   self.rotation_x_angle = self.rotation_x_angle + dt * 0.7
   self.rotation_y_angle = self.rotation_y_angle + dt
end

function Cube:draw(context)
   build_mvp(mvp, context.viewport_width / context.viewport_height, self.rotation_x_angle, self.rotation_y_angle)

   gl.Viewport(0, 0, context.viewport_width, context.viewport_height)
   gl.ClearColor(background_color:unpackf())
   gl.Clear(gl.COLOR_BUFFER_BIT + gl.DEPTH_BUFFER_BIT)

   gl.UseProgram(self.program)
   gl.UniformMatrix4fv(self.mvp_location, 1, gl.FALSE, mvp)
   gl.BindVertexArray(self.vao)
   gl.DrawArrays(gl.TRIANGLES, 0, cube_mesh.vertex_count)
end

function Cube:release()
   if self.program ~= 0 then
      gl.DeleteProgram(self.program)
      self.program = 0
   end
   if self.vbo ~= 0 then
      gl_buffers[0] = self.vbo
      gl.DeleteBuffers(1, gl_buffers)
      self.vbo = 0
   end
   if self.vao ~= 0 then
      gl_vertex_arrays[0] = self.vao
      gl.DeleteVertexArrays(1, gl_vertex_arrays)
      self.vao = 0
   end
   self.mvp_location = -1
end

function Scene:init()
   self:super().init(self)
   self.cube = self:add_child(Cube())
   self.animator = nil
end

function Scene:initialize_resources()
   self.cube:initialize_resources()
end

function Scene:on_resize(info)
   viewport_width = math.max(1, info.pixel_width)
   viewport_height = math.max(1, info.pixel_height)
end

function Scene:release()
   self.animator = nil
   self.cube = nil
end

local function on_resize(info)
   if scene == nil then
      viewport_width = math.max(1, info.pixel_width)
      viewport_height = math.max(1, info.pixel_height)
      return
   end
   scene:on_resize(info)
end

local function on_render()
   if scene ~= nil then
      scene:draw_tree({
         viewport_width = viewport_width,
         viewport_height = viewport_height,
      })
   end
end

rig.run {
   mode = "sdl3_gl",
   event_handlers = {
      resize = on_resize,
   },
   driver_config = {
      sdl3_gl = {
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig OpenGL Spinning Cube",
            [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
         },
         gl_attributes = {
            context_major_version = 4,
            context_minor_version = 5,
            context_profile = "core",
            doublebuffer = true,
            depth_size = 24,
         },
         swap_interval = 1,
         render = on_render,
      },
   },
   hooks = {
      after_setup = animation_runtime.hooks.after_setup,
      before_drain = animation_runtime.hooks.before_drain,
      before_shutdown = animation_runtime.hooks.before_shutdown,
   },
}
