local ffi = ffi

local math3d = require("math3d")
local mesh3d = require("mesh3d")
local sdl3 = require("sdl3")
local shader = require("shader")
local time = require("time")

sdl3.config.window_props = {
   [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig SDL GPU Spinning Cube",
   [sdl3.PROP_WINDOW_CREATE_WIDTH_NUMBER] = 960,
   [sdl3.PROP_WINDOW_CREATE_HEIGHT_NUMBER] = 540,
   [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
}

local function fail(message)
   error(message, 0)
end

local function sdl_error(prefix)
   return ("%s: %s"):format(prefix, ffi.string(sdl3.GetError()))
end

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

local rotation_x = math3d.mat4()
local rotation_y = math3d.mat4()
local model = math3d.mat4()
local view = math3d.mat4()
local projection = math3d.mat4()
local mvp = math3d.mat4()
local eye = math3d.vec3(0.0, 0.0, -4.5)
local target = math3d.vec3(0.0, 0.0, 0.0)
local up = math3d.vec3(0.0, 1.0, 0.0)

local function build_mvp(out, aspect, time_seconds)
   math3d.mat4_rotation_x(rotation_x, time_seconds * 0.7)
   math3d.mat4_rotation_y(rotation_y, time_seconds)
   math3d.mat4_multiply(model, rotation_x, rotation_y)
   math3d.mat4_look_at_lh(view, eye, target, up)
   math3d.mat4_multiply(model, model, view)
   math3d.mat4_perspective_lh(projection, math.rad(60.0), aspect, 0.1, 100.0)
   return math3d.mat4_multiply(out, model, projection)
end

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

local cube_mesh = mesh3d.make_cube {
   size = 2.0,
   colors = "face",
}

local vertex_uniform_data = math3d.mat4()
local vertex_input = sdl3.build_vertex_input_state_from_mesh(cube_mesh)

local resource_scope = nil

local function release_resources()
   if resource_scope ~= nil then
      resource_scope:release()
      resource_scope = nil
   end
end

local vertex_buffer = nil
local pipeline = nil
local depth_texture = nil

local ok, err = pcall(function()
   sdl3.setup_gpu {
      shader_formats = sdl3.GPU_SHADERFORMAT_SPIRV,
   }

   local device = sdl3.get_gpu_device()
   local window = sdl3.get_window()
   if device == nil or window == nil then
      fail("sdl3.setup_gpu did not produce a device and window")
   end

   local scope = sdl3.resource_scope(device)
   resource_scope = scope

   local vertex_shader = scope:create_gpu_shader(vertex_compiled)
   local fragment_shader = scope:create_gpu_shader(fragment_compiled)

   local swapchain_format = sdl3.GetGPUSwapchainTextureFormat(device, window)
   local depth_format = sdl3.choose_depth_format(device)

   vertex_buffer = scope:create_gpu_buffer {
      usage = sdl3.GPU_BUFFERUSAGE_VERTEX,
      size = #cube_mesh.vertex_blob,
      props = 0,
   }
   sdl3.upload_to_gpu_buffer(
      device,
      vertex_buffer,
      cube_mesh.vertex_blob
   )

   pipeline = scope:create_graphics_pipeline {
      vertex_shader = vertex_shader,
      fragment_shader = fragment_shader,
      vertex_input = vertex_input,
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
         depth_stencil_format = depth_format,
         has_depth_stencil_target = true,
      },
      props = 0,
   }

   local depth_width = 0
   local depth_height = 0

   local function ensure_depth_texture(width, height)
      if depth_texture ~= nil and depth_width == width and depth_height == height then
         return
      end

      depth_texture = resource_scope:replace("depth_texture",
         sdl3.create_depth_texture(device, width, height, depth_format),
         function(scope_device, resource)
         sdl3.ReleaseGPUTexture(scope_device, resource)
      end)
      depth_width = width
      depth_height = height
   end

   local vertex_binding = ffi.new("SDL_GPUBufferBinding[1]")
   vertex_binding[0].buffer = vertex_buffer
   vertex_binding[0].offset = 0

   while sdl3.pump_events() do
      local command_buffer = sdl3.AcquireGPUCommandBuffer(device)
      if command_buffer == nil then
         fail(sdl_error("failed to acquire GPU command buffer"))
      end

      local swapchain_texture_out = ffi.new("SDL_GPUTexture *[1]")
      local width_out = ffi.new("Uint32[1]")
      local height_out = ffi.new("Uint32[1]")
      if not sdl3.WaitAndAcquireGPUSwapchainTexture(
         command_buffer,
         window,
         swapchain_texture_out,
         width_out,
         height_out
      ) then
         fail(sdl_error("failed to acquire swapchain texture"))
      end

      local swapchain_texture = swapchain_texture_out[0]
      if swapchain_texture ~= nil then
         local width = tonumber(width_out[0])
         local height = tonumber(height_out[0])
         ensure_depth_texture(width, height)

         build_mvp(vertex_uniform_data, width / height, time.monotonic())
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
         color_target_info[0].clear_color.r = 0.07
         color_target_info[0].clear_color.g = 0.08
         color_target_info[0].clear_color.b = 0.11
         color_target_info[0].clear_color.a = 1.0
         color_target_info[0].load_op = sdl3.GPU_LOADOP_CLEAR
         color_target_info[0].store_op = sdl3.GPU_STOREOP_STORE
         color_target_info[0].resolve_texture = nil
         color_target_info[0].resolve_mip_level = 0
         color_target_info[0].resolve_layer = 0
         color_target_info[0].cycle = false
         color_target_info[0].cycle_resolve_texture = false

         local depth_target_info = ffi.new("SDL_GPUDepthStencilTargetInfo[1]")
         depth_target_info[0].texture = depth_texture
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
         sdl3.BindGPUGraphicsPipeline(render_pass, pipeline)
         sdl3.BindGPUVertexBuffers(render_pass, 0, vertex_binding, 1)
         sdl3.DrawGPUPrimitives(render_pass, cube_mesh.vertex_count, 1, 0, 0)
         sdl3.EndGPURenderPass(render_pass)
      end

      if not sdl3.SubmitGPUCommandBuffer(command_buffer) then
         fail(sdl_error("failed to submit GPU command buffer"))
      end
   end
end)

release_resources()
sdl3.shutdown()

if not ok then
   fail(err)
end
