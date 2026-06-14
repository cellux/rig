local ffi = require("ffi")

local animator = require("animator")
local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local scenegraph = require("scenegraph")
local sdl3 = require("sdl3")
local shader = require("shader")

local Object = scenegraph.Object
local Animator = animator.Animator
local Cube = rig.class(Object)
local Scene = rig.class(Object)

local rotation_x = mathx.mat4()
local rotation_y = mathx.mat4()
local model = mathx.mat4()
local view = mathx.mat4()
local projection = mathx.mat4()
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

local vertex_shader_source = [[
#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_color;

layout(location = 0) out vec3 out_color;

layout(set = 1, binding = 0) uniform Camera {
   mat4 mvp;
} camera;

void main()
{
   gl_Position = camera.mvp * vec4(in_position, 1.0);
   out_color = in_color;
}
]]

local fragment_shader_source = [[
#version 450

layout(location = 0) in vec3 in_color;
layout(location = 0) out vec4 out_color;

void main()
{
   out_color = vec4(in_color, 1.0);
}
]]

local vertex_compiled = shader.compile {
   language = "glsl",
   stage = "vertex",
   source_name = "spinning_cube.vert.glsl",
   source = vertex_shader_source,
}

local fragment_compiled = shader.compile {
   language = "glsl",
   stage = "fragment",
   source_name = "spinning_cube.frag.glsl",
   source = fragment_shader_source,
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
local vertex_uniform_data = mathx.mat4()
local vertex_binding = ffi.new("SDL_GPUBufferBinding[1]")

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
   Object.init(self)
   self.rotation_x_angle = 0.0
   self.rotation_y_angle = 0.0
   self.resource_scope = nil
   self.vertex_input = nil
   self.vertex_buffer = nil
   self.pipeline = nil
   self.depth_texture = nil
   self.depth_format = nil
   self.depth_width = 0
   self.depth_height = 0
end

function Cube:initialize_resources()
   local device = sdl3.get_gpu_device()
   local window = sdl3.get_window()
   if device == nil or window == nil then
      fail("sdl3_gpu runtime mode did not produce a device and window")
   end

   local scope = sdl3.resource_scope(device)
   self.resource_scope = scope
   self.vertex_input = mesh.build_vertex_input(cube_mesh)

   local vertex_shader = scope:adopt(
      shader.create_stage(vertex_compiled),
      function(_, resource)
         shader.destroy_stage(resource)
      end
   )
   local fragment_shader = scope:adopt(
      shader.create_stage(fragment_compiled),
      function(_, resource)
         shader.destroy_stage(resource)
      end
   )
   local swapchain_format = sdl3.GetGPUSwapchainTextureFormat(device, window)
   self.depth_format = sdl3.choose_depth_format(device)

   self.vertex_buffer = scope:create_gpu_buffer {
      usage = sdl3.GPU_BUFFERUSAGE_VERTEX,
      size = #cube_mesh.vertex_blob,
      props = 0,
   }
   sdl3.upload_to_gpu_buffer(device, self.vertex_buffer, cube_mesh.vertex_blob)

   self.pipeline = scope:create_graphics_pipeline {
      vertex_shader = vertex_shader,
      fragment_shader = fragment_shader,
      vertex_input = self.vertex_input,
      primitive_type = sdl3.GPU_PRIMITIVETYPE_TRIANGLELIST,
      rasterizer_state = {
         fill_mode = sdl3.GPU_FILLMODE_FILL,
         cull_mode = sdl3.GPU_CULLMODE_NONE,
         front_face = sdl3.GPU_FRONTFACE_COUNTER_CLOCKWISE,
         enable_depth_bias = false,
         enable_depth_clip = true,
      },
      multisample_state = {
         sample_count = sdl3.GPU_SAMPLECOUNT_1,
         sample_mask = 0,
         enable_mask = false,
         enable_alpha_to_coverage = false,
      },
      depth_stencil_state = {
         compare_op = sdl3.GPU_COMPAREOP_LESS,
         enable_depth_test = true,
         enable_depth_write = true,
         enable_stencil_test = false,
      },
      target_info = {
         color_target_descriptions = {
            { format = swapchain_format },
         },
         depth_stencil_format = self.depth_format,
         has_depth_stencil_target = true,
      },
      props = 0,
   }

   vertex_binding[0].buffer = self.vertex_buffer
   vertex_binding[0].offset = 0
end

function Cube:ensure_depth_texture(width, height)
   if self.depth_texture ~= nil and self.depth_width == width and self.depth_height == height then
      return
   end

   self.depth_texture = self.resource_scope:replace("depth_texture",
      sdl3.create_depth_texture(sdl3.get_gpu_device(), width, height, self.depth_format),
      function(scope_device, resource)
         sdl3.ReleaseGPUTexture(scope_device, resource)
      end)
   self.depth_width = width
   self.depth_height = height
end

function Cube:update(dt)
   self.rotation_x_angle = self.rotation_x_angle + dt * 0.7
   self.rotation_y_angle = self.rotation_y_angle + dt
end

function Cube:draw(context)
   local command_buffer = context.command_buffer
   local swapchain_texture = context.swapchain_texture
   local width = context.width
   local height = context.height

   self:ensure_depth_texture(width, height)
   build_mvp(vertex_uniform_data, width / height, self.rotation_x_angle, self.rotation_y_angle)
   sdl3.PushGPUVertexUniformData(
      command_buffer,
      0,
      vertex_uniform_data,
      ffi.sizeof(vertex_uniform_data)
   )

   local color_target_info = ffi.new("SDL_GPUColorTargetInfo[1]")
   color_target_info[0].texture = swapchain_texture
   color_target_info[0].mip_level = 0
   color_target_info[0].layer_or_depth_plane = 0
   color_target_info[0].clear_color.r = background_color.r / 255.0
   color_target_info[0].clear_color.g = background_color.g / 255.0
   color_target_info[0].clear_color.b = background_color.b / 255.0
   color_target_info[0].clear_color.a = background_color.a / 255.0
   color_target_info[0].load_op = sdl3.GPU_LOADOP_CLEAR
   color_target_info[0].store_op = sdl3.GPU_STOREOP_STORE
   color_target_info[0].resolve_texture = nil
   color_target_info[0].resolve_mip_level = 0
   color_target_info[0].resolve_layer = 0
   color_target_info[0].cycle = false
   color_target_info[0].cycle_resolve_texture = false

   local depth_target_info = ffi.new("SDL_GPUDepthStencilTargetInfo[1]")
   depth_target_info[0].texture = self.depth_texture
   depth_target_info[0].clear_depth = 1.0
   depth_target_info[0].load_op = sdl3.GPU_LOADOP_CLEAR
   depth_target_info[0].store_op = sdl3.GPU_STOREOP_DONT_CARE
   depth_target_info[0].stencil_load_op = sdl3.GPU_LOADOP_DONT_CARE
   depth_target_info[0].stencil_store_op = sdl3.GPU_STOREOP_DONT_CARE
   depth_target_info[0].cycle = false
   depth_target_info[0].clear_stencil = 0
   depth_target_info[0].mip_level = 0
   depth_target_info[0].layer = 0

   local render_pass = sdl3.BeginGPURenderPass(
      command_buffer,
      color_target_info,
      1,
      depth_target_info
   )
   sdl3.BindGPUGraphicsPipeline(render_pass, self.pipeline)
   sdl3.BindGPUVertexBuffers(render_pass, 0, vertex_binding, 1)
   sdl3.DrawGPUPrimitives(render_pass, cube_mesh.vertex_count, 1, 0, 0)
   sdl3.EndGPURenderPass(render_pass)
end

function Cube:release()
   self.depth_texture = nil
   self.pipeline = nil
   self.vertex_buffer = nil
   self.vertex_input = nil
   self.depth_format = nil
   self.depth_width = 0
   self.depth_height = 0
   if self.resource_scope ~= nil then
      self.resource_scope:release()
      self.resource_scope = nil
   end
end

function Scene:init()
   Object.init(self)
   self.cube = self:add_child(Cube())
   self.animator = nil
end

function Scene:initialize_resources()
   self.cube:initialize_resources()
end

function Scene:release()
   self.animator = nil
   self.cube = nil
end

local function on_render(command_buffer, swapchain_texture, width, height)
   if scene ~= nil then
      scene:draw_tree({
         command_buffer = command_buffer,
         swapchain_texture = swapchain_texture,
         width = width,
         height = height,
      })
   end
end

rig.run {
   mode = "sdl3_gpu",
   driver_config = {
      sdl3_gpu = {
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig SDL GPU Spinning Cube",
            [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
         },
         render = on_render,
         shader_formats = sdl3.GPU_SHADERFORMAT_SPIRV,
      },
   },
   hooks = {
      after_setup = animation_runtime.hooks.after_setup,
      before_drain = animation_runtime.hooks.before_drain,
      before_shutdown = animation_runtime.hooks.before_shutdown,
   },
}
