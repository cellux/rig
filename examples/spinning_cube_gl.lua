local animator = require("animator")
local color = require("color")
local gl = require("gl")
local glx = require("glx")
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
   self.program = nil
   self.vao = nil
   self.vbo = nil
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

   self.program = self:replace_owned("program", glx.Program {
      shaders = {
         vertex_shader,
         fragment_shader,
      },
   }, function(_, program)
      program:release()
   end)

   self.vbo = self:replace_owned("vbo", glx.Buffer {
      target = gl.ARRAY_BUFFER,
   }, function(_, vbo)
      vbo:release()
   end)

   self.vao = self:replace_owned("vao", glx.VertexArray(), function(_, vao)
      vao:release()
   end)
   if self.vao.id == 0 then
      rig.raise("failed to create OpenGL vertex objects")
   end

   self.vao:bind()
   self.vbo:set_data(cube_mesh.vertex_blob, gl.STATIC_DRAW)
   self.vao:attribute(
      0,
      3,
      gl.FLOAT,
      gl.FALSE,
      cube_mesh.vertex_stride,
      cube_mesh.attribute_offsets.position
   )
   self.vao:attribute(
      1,
      3,
      gl.FLOAT,
      gl.FALSE,
      cube_mesh.vertex_stride,
      cube_mesh.attribute_offsets.color
   )

   gl.Enable(gl.DEPTH_TEST)
   gl.DepthFunc(gl.LEQUAL)
end

function Cube:update(dt)
   self.rotation_x_angle = self.rotation_x_angle + dt * 0.7
   self.rotation_y_angle = self.rotation_y_angle + dt
end

function Cube:draw(context)
   self:build_mvp(self.mvp, context.viewport_width / context.viewport_height)

   gl.Viewport(0, 0, context.viewport_width, context.viewport_height)
   gl.ClearColor(context.background_color:to_rgbaf())
   gl.Clear(gl.COLOR_BUFFER_BIT + gl.DEPTH_BUFFER_BIT)

   self.program:use()
   self.program:set_uniform_matrix4fv("u_mvp", self.mvp)
   self.vao:bind()
   gl.DrawArrays(gl.TRIANGLES, 0, cube_mesh.vertex_count)
end

function Cube:release()
   self.program = nil
   self.vbo = nil
   self.vao = nil
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
