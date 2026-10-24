local color = require("color")
local gl = require("gl")
local glx = require("glx")
local mathx = require("mathx")
local mesh = require("mesh")
local runtime = require("runtime")
local scene = require("scene")
local schema = require("schema")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")

local GlScene = rig.Class(scene.RenderScene)
local GlCube = rig.Class()

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

-- The scene specialization: OpenGL needs a viewport and a framebuffer clear
-- before its drawables run.
function GlScene:begin_frame()
   local pixel_width, pixel_height = self.graphics.window:get_size_in_pixels()
   self.width = math.max(1, tonumber(pixel_width) or 1)
   self.height = math.max(1, tonumber(pixel_height) or 1)

   gl.Viewport(0, 0, self.width, self.height)
   local r, g, b, a = self.background_color:to_rgbaf()
   gl.ClearColor(r, g, b, a)
   gl.Clear(gl.COLOR_BUFFER_BIT + gl.DEPTH_BUFFER_BIT)
end

local cube_options_schema = schema.record({
   size = schema.number():optional(),
   colors = schema.any():optional(),
   spin_x = schema.number():optional(),
   spin_y = schema.number():optional(),
   eye = schema.array(schema.number()):optional(),
   target = schema.array(schema.number()):optional(),
   up = schema.array(schema.number()):optional(),
   fov_degrees = schema.number():optional(),
   near = schema.number():optional(),
   far = schema.number():optional(),
}, {
   allow_extra = true,
})

local function normalize_cube_options(options)
   options = options or {}
   return {
      size = options.size or 2.0,
      colors = options.colors or "face",
      spin_x = options.spin_x or 0.7,
      spin_y = options.spin_y or 1.0,
      eye = options.eye or { 0.0, 0.0, -4.5 },
      target = options.target or { 0.0, 0.0, 0.0 },
      up = options.up or { 0.0, 1.0, 0.0 },
      fov_degrees = options.fov_degrees or 60.0,
      near = options.near or 0.1,
      far = options.far or 100.0,
   }
end

function GlCube:init(options)
   self.clock = options.clock
   self.options = normalize_cube_options(options.options)
   self.mesh = mesh.make_cube {
      size = self.options.size,
      colors = self.options.colors,
   }
   self.rotation_x_angle = 0.0
   self.rotation_y_angle = 0.0
   self.last_time = self.clock ~= nil and self.clock:monotonic() or nil
   self.rotation_x = mathx.mat4()
   self.rotation_y = mathx.mat4()
   self.model = mathx.mat4()
   self.view = mathx.mat4()
   self.projection = mathx.mat4()
   self.mvp = mathx.mat4()
   self:create_resources(options.shader)
end

function GlCube:create_resources(shader_provider)
   local vertex_shader = shader_provider:create_stage({
      language = "glsl",
      stage = "vertex",
      source_name = "spinning_cube_gl.vert.glsl",
      source = vertex_shader_source,
   })
   local fragment_shader = shader_provider:create_stage({
      language = "glsl",
      stage = "fragment",
      source_name = "spinning_cube_gl.frag.glsl",
      source = fragment_shader_source,
   })

   self.program = glx.Program {
      shaders = {
         vertex_shader,
         fragment_shader,
      },
   }
   self.vbo = glx.Buffer {
      target = gl.ARRAY_BUFFER,
   }
   self.vao = glx.VertexArray()

   self.vao:bind()
   self.vbo:set_data(self.mesh.vertex_blob, gl.STATIC_DRAW)
   self.vao:attribute(
      0,
      3,
      gl.FLOAT,
      gl.FALSE,
      self.mesh.vertex_stride,
      self.mesh.attribute_offsets.position
   )
   self.vao:attribute(
      1,
      3,
      gl.FLOAT,
      gl.FALSE,
      self.mesh.vertex_stride,
      self.mesh.attribute_offsets.color
   )

   gl.Enable(gl.DEPTH_TEST)
   gl.DepthFunc(gl.LEQUAL)
end

function GlCube:build_mvp(out, aspect)
   mathx.mat4_rotation_x(self.rotation_x, self.rotation_x_angle)
   mathx.mat4_rotation_y(self.rotation_y, self.rotation_y_angle)
   mathx.mat4_multiply(self.model, self.rotation_x, self.rotation_y)

   local options = self.options
   local eye = mathx.vec3(options.eye[1], options.eye[2], options.eye[3])
   local target = mathx.vec3(options.target[1], options.target[2], options.target[3])
   local up = mathx.vec3(options.up[1], options.up[2], options.up[3])
   mathx.mat4_look_at_lh(self.view, eye, target, up)
   mathx.mat4_multiply(self.model, self.model, self.view)
   mathx.mat4_perspective_lh(
      self.projection,
      math.rad(options.fov_degrees),
      aspect,
      options.near,
      options.far
   )
   return mathx.mat4_multiply(out, self.model, self.projection)
end

function GlCube:update(dt)
   self.rotation_x_angle = self.rotation_x_angle + dt * self.options.spin_x
   self.rotation_y_angle = self.rotation_y_angle + dt * self.options.spin_y
end

function GlCube:draw(surface)
   if self.clock ~= nil then
      local now = self.clock:monotonic()
      local dt = self.last_time == nil and 0.0 or (now - self.last_time)
      self.last_time = now
      if dt > 0.0 then
         self:update(dt)
      end
   end

   self:build_mvp(self.mvp, surface.width / surface.height)

   self.program:use()
   self.program:set_uniform_matrix4fv("u_mvp", self.mvp)
   self.vao:bind()
   gl.DrawArrays(gl.TRIANGLES, 0, self.mesh.vertex_count)
end

function GlCube:release()
   if self.program ~= nil then
      self.program:release()
      self.program = nil
   end
   if self.vbo ~= nil then
      self.vbo:release()
      self.vbo = nil
   end
   if self.vao ~= nil then
      self.vao:release()
      self.vao = nil
   end
   self.mesh = nil
end

-- The cube is a parametrized component template: `options` specialize its
-- geometry, camera, and spin, and the compiler resolves its capabilities.
local function cube_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      config = options,
      config_schema = cube_options_schema,
      requires = {
         { capability = "render.scene" },
         { capability = "graphics.context", properties = { backend = "gl" } },
         { capability = "gl.resolver" },
         { capability = "shader.stage" },
      },
      create = function(context)
         local cube = GlCube {
            shader = context:capability("shader.stage"),
            clock = context.runtime.clock,
            options = context.component.config,
         }
         context:capability("render.scene"):add(cube)
         return cube
      end,
      release = function(cube)
         cube:release()
      end,
   })
end

local scene_plugin = scene.plugin()

local builder = rig.runtime()
sdl3x.bundle_sdl3_gl(builder, {
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
})
builder:use(scene_plugin)
builder:add(scene.container_component(scene_plugin, {
   name = "scene",
   scene_class = GlScene,
   background_color = color.rgbaf(0.07, 0.08, 0.11, 1.0),
}))
builder:add(cube_component(scene_plugin, {
   name = "cube",
   size = 2.0,
   colors = cube_face_colors,
   spin_x = 0.7,
   spin_y = 1.0,
}))
builder:execute(sdl3x.App):compile():start()