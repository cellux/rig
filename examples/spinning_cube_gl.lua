local ffi = require("ffi")

local gl = require("gl")
local mathx = require("mathx")
local mesh = require("mesh")
local shader = require("shader")
local sdl3 = require("sdl3")
local time = require("time")

local function fail(message)
   error(message, 0)
end

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

local function build_mvp(out, aspect, time_seconds)
   mathx.mat4_rotation_x(rotation_x, time_seconds * 0.7)
   mathx.mat4_rotation_y(rotation_y, time_seconds)
   mathx.mat4_multiply(model, rotation_x, rotation_y)
   mathx.mat4_look_at_lh(view, eye, target, up)
   mathx.mat4_multiply(model, model, view)
   mathx.mat4_perspective_lh(projection, math.rad(60.0), aspect, 0.1, 100.0)
   return mathx.mat4_multiply(out, model, projection)
end

local cube_mesh = mesh.make_cube {
   size = 2.0,
   colors = "face",
}

local program = 0
local vao = 0
local vbo = 0
local mvp_location = -1
-- Populated by the initial sdl3_gl on_resize callback before rendering starts.
local viewport_width
local viewport_height
local gl_vertex_arrays = ffi.new("GLuint[1]")
local gl_buffers = ffi.new("GLuint[1]")

local function release_resources()
   if program ~= 0 then
      gl.DeleteProgram(program)
      program = 0
   end
   if vbo ~= 0 then
      gl_buffers[0] = vbo
      gl.DeleteBuffers(1, gl_buffers)
      vbo = 0
   end
   if vao ~= 0 then
      gl_vertex_arrays[0] = vao
      gl.DeleteVertexArrays(1, gl_vertex_arrays)
      vao = 0
   end
end

local function on_resize(info)
   viewport_width = math.max(1, info.pixel_width)
   viewport_height = math.max(1, info.pixel_height)
end

local function on_render()
   build_mvp(mvp, viewport_width / viewport_height, time.monotonic())

   gl.Viewport(0, 0, viewport_width, viewport_height)
   gl.ClearColor(0.07, 0.08, 0.11, 1.0)
   gl.Clear(gl.COLOR_BUFFER_BIT + gl.DEPTH_BUFFER_BIT)

   gl.UseProgram(program)
   gl.UniformMatrix4fv(mvp_location, 1, gl.FALSE, mvp)
   gl.BindVertexArray(vao)
   gl.DrawArrays(gl.TRIANGLES, 0, cube_mesh.vertex_count)
end

local function after_setup()
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
      error(linked_or_err, 0)
   end
   program = linked_or_err

   gl.GenVertexArrays(1, gl_vertex_arrays)
   gl.GenBuffers(1, gl_buffers)
   vao = tonumber(gl_vertex_arrays[0]) or 0
   vbo = tonumber(gl_buffers[0]) or 0
   if vao == 0 or vbo == 0 then
      fail("failed to create OpenGL vertex objects")
   end

   gl.BindVertexArray(vao)
   gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
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

   mvp_location = gl.get_uniform_location(program, "u_mvp")
   if mvp_location < 0 then
      fail("failed to locate OpenGL uniform 'u_mvp'")
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
      after_setup = after_setup,
      before_shutdown = release_resources,
   },
}
