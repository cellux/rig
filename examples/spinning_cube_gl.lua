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
local Cube = rig.Class(Object)
local Scene = rig.Class(Object)
local App = rig.Class(animator.App)

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

function Cube:init()
   self:super().init(self)
   self.program = 0
   self.vao = 0
   self.vbo = 0
   self.mvp_location = -1
   self.rotation_x_angle = 0.0
   self.rotation_y_angle = 0.0
   self.rotation_x = mathx.mat4()
   self.rotation_y = mathx.mat4()
   self.model = mathx.mat4()
   self.view = mathx.mat4()
   self.projection = mathx.mat4()
   self.mvp = mathx.mat4()
   self.eye = mathx.vec3(0.0, 0.0, -4.5)
   self.target = mathx.vec3(0.0, 0.0, 0.0)
   self.up = mathx.vec3(0.0, 1.0, 0.0)
   self.gl_vertex_arrays = ffi.new("GLuint[1]")
   self.gl_buffers = ffi.new("GLuint[1]")
end

function Cube:build_mvp(out, aspect)
   mathx.mat4_rotation_x(self.rotation_x, self.rotation_x_angle)
   mathx.mat4_rotation_y(self.rotation_y, self.rotation_y_angle)
   mathx.mat4_multiply(self.model, self.rotation_x, self.rotation_y)
   mathx.mat4_look_at_lh(self.view, self.eye, self.target, self.up)
   mathx.mat4_multiply(self.model, self.model, self.view)
   mathx.mat4_perspective_lh(self.projection, math.rad(60.0), aspect, 0.1, 100.0)
   return mathx.mat4_multiply(out, self.model, self.projection)
end

function Cube:activate()
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
   self.program = self:replace_owned("program", linked_or_err, function(_, program)
      if program ~= 0 then
         gl.DeleteProgram(program)
      end
   end)

   gl.GenVertexArrays(1, self.gl_vertex_arrays)
   gl.GenBuffers(1, self.gl_buffers)
   self.vao = self:replace_owned("vao", tonumber(self.gl_vertex_arrays[0]) or 0, function(self_ref, vao)
      if vao ~= 0 then
         self_ref.gl_vertex_arrays[0] = vao
         gl.DeleteVertexArrays(1, self_ref.gl_vertex_arrays)
      end
   end)
   self.vbo = self:replace_owned("vbo", tonumber(self.gl_buffers[0]) or 0, function(self_ref, vbo)
      if vbo ~= 0 then
         self_ref.gl_buffers[0] = vbo
         gl.DeleteBuffers(1, self_ref.gl_buffers)
      end
   end)
   if self.vao == 0 or self.vbo == 0 then
      rig.raise("failed to create OpenGL vertex objects")
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
      rig.raise("failed to locate OpenGL uniform 'u_mvp'")
   end
end

function Cube:update(dt)
   self.rotation_x_angle = self.rotation_x_angle + dt * 0.7
   self.rotation_y_angle = self.rotation_y_angle + dt
end

function Cube:draw(context)
   self:build_mvp(self.mvp, context.viewport_width / context.viewport_height)

   gl.Viewport(0, 0, context.viewport_width, context.viewport_height)
   gl.ClearColor(context.background_color:unpackf())
   gl.Clear(gl.COLOR_BUFFER_BIT + gl.DEPTH_BUFFER_BIT)

   gl.UseProgram(self.program)
   gl.UniformMatrix4fv(self.mvp_location, 1, gl.FALSE, self.mvp)
   gl.BindVertexArray(self.vao)
   gl.DrawArrays(gl.TRIANGLES, 0, cube_mesh.vertex_count)
end

function Cube:release()
   self.program = 0
   self.vbo = 0
   self.vao = 0
   self.mvp_location = -1
end

function Scene:init()
   self:super().init(self)
   self.background_color = color.rgbaf(0.07, 0.08, 0.11, 1.0)
   self.cube = self:add_child(Cube())
end

function Scene:release()
   self.background_color = nil
   self.cube = nil
end

function App:init()
   self:super().init(self)
   self.root = Scene()
   self.viewport_width = 1
   self.viewport_height = 1
end

function App:on_resize(info)
   self.viewport_width = math.max(1, info.pixel_width)
   self.viewport_height = math.max(1, info.pixel_height)
end

function App:render()
   if self.root ~= nil then
      self.root:draw_tree({
         viewport_width = self.viewport_width,
         viewport_height = self.viewport_height,
         background_color = self.root.background_color,
      })
   end
end

rig.run {
   mode = "sdl3_gl",
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
      },
   },
   app = App,
}
