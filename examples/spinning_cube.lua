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

local function assert_ok(value, err)
   if value == nil or value == false then
      fail(err or "operation failed")
   end
   return value
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

local vertex_compiled = shader.compile({
   language = "glsl",
   stage = "vertex",
   source_name = "spinning_cube.vert.glsl",
   source = vertex_shader_source,
})

local fragment_compiled = shader.compile({
   language = "glsl",
   stage = "fragment",
   source_name = "spinning_cube.frag.glsl",
   source = fragment_shader_source,
})

local cube_mesh = mesh3d.make_cube({
   size = 2.0,
   colors = "face",
})

local vertex_uniform_data = math3d.mat4()
local vertex_input = sdl3.build_vertex_input_state_from_mesh(cube_mesh)

local resources = {
   depth_texture = nil,
   vertex_buffer = nil,
   fragment_shader = nil,
   vertex_shader = nil,
   pipeline = nil,
}

local function release_resources()
   local device = sdl3.get_gpu_device()
   if device == nil then
      return
   end

   if resources.depth_texture ~= nil then
      sdl3.ReleaseGPUTexture(device, resources.depth_texture)
      resources.depth_texture = nil
   end
   if resources.vertex_buffer ~= nil then
      sdl3.ReleaseGPUBuffer(device, resources.vertex_buffer)
      resources.vertex_buffer = nil
   end
   if resources.pipeline ~= nil then
      sdl3.ReleaseGPUGraphicsPipeline(device, resources.pipeline)
      resources.pipeline = nil
   end
   if resources.fragment_shader ~= nil then
      sdl3.ReleaseGPUShader(device, resources.fragment_shader)
      resources.fragment_shader = nil
   end
   if resources.vertex_shader ~= nil then
      sdl3.ReleaseGPUShader(device, resources.vertex_shader)
      resources.vertex_shader = nil
   end
end

local ok, err = pcall(function()
   sdl3.setup_gpu({
      shader_formats = sdl3.GPU_SHADERFORMAT_SPIRV,
   })

   local device = sdl3.get_gpu_device()
   local window = sdl3.get_window()
   if device == nil or window == nil then
      fail("sdl3.setup_gpu did not produce a device and window")
   end

   resources.vertex_shader = sdl3.create_gpu_shader(device, vertex_compiled)
   resources.fragment_shader = sdl3.create_gpu_shader(device, fragment_compiled)

   local swapchain_format = sdl3.GetGPUSwapchainTextureFormat(device, window)
   local depth_format = assert_ok(sdl3.choose_depth_format(device))

   local vertex_buffer_info = ffi.new("SDL_GPUBufferCreateInfo[1]")
   vertex_buffer_info[0].usage = sdl3.GPU_BUFFERUSAGE_VERTEX
   vertex_buffer_info[0].size = #cube_mesh.vertex_blob
   vertex_buffer_info[0].props = 0
   resources.vertex_buffer = sdl3.CreateGPUBuffer(device, vertex_buffer_info)
   if resources.vertex_buffer == nil then
      fail(sdl_error("failed to create GPU vertex buffer"))
   end
   assert_ok(sdl3.upload_to_gpu_buffer(
      device,
      resources.vertex_buffer,
      cube_mesh.vertex_blob
   ))

   local color_target_description = ffi.new("SDL_GPUColorTargetDescription[1]")
   color_target_description[0].format = swapchain_format

   local pipeline_info = ffi.new("SDL_GPUGraphicsPipelineCreateInfo[1]")
   pipeline_info[0].vertex_shader = resources.vertex_shader
   pipeline_info[0].fragment_shader = resources.fragment_shader
   pipeline_info[0].vertex_input_state.vertex_buffer_descriptions =
      vertex_input.state[0].vertex_buffer_descriptions
   pipeline_info[0].vertex_input_state.num_vertex_buffers =
      vertex_input.state[0].num_vertex_buffers
   pipeline_info[0].vertex_input_state.vertex_attributes =
      vertex_input.state[0].vertex_attributes
   pipeline_info[0].vertex_input_state.num_vertex_attributes =
      vertex_input.state[0].num_vertex_attributes
   pipeline_info[0].primitive_type = sdl3.GPU_PRIMITIVETYPE_TRIANGLELIST
   pipeline_info[0].rasterizer_state.fill_mode = sdl3.GPU_FILLMODE_FILL
   pipeline_info[0].rasterizer_state.cull_mode = sdl3.GPU_CULLMODE_NONE
   pipeline_info[0].rasterizer_state.front_face =
      sdl3.GPU_FRONTFACE_COUNTER_CLOCKWISE
   pipeline_info[0].rasterizer_state.enable_depth_bias = false
   pipeline_info[0].rasterizer_state.enable_depth_clip = true
   pipeline_info[0].multisample_state.sample_count = sdl3.GPU_SAMPLECOUNT_1
   pipeline_info[0].multisample_state.sample_mask = 0
   pipeline_info[0].multisample_state.enable_mask = false
   pipeline_info[0].multisample_state.enable_alpha_to_coverage = false
   pipeline_info[0].depth_stencil_state.compare_op = sdl3.GPU_COMPAREOP_LESS
   pipeline_info[0].depth_stencil_state.enable_depth_test = true
   pipeline_info[0].depth_stencil_state.enable_depth_write = true
   pipeline_info[0].depth_stencil_state.enable_stencil_test = false
   pipeline_info[0].target_info.color_target_descriptions = color_target_description
   pipeline_info[0].target_info.num_color_targets = 1
   pipeline_info[0].target_info.depth_stencil_format = depth_format
   pipeline_info[0].target_info.has_depth_stencil_target = true
   pipeline_info[0].props = 0

   resources.pipeline = sdl3.CreateGPUGraphicsPipeline(device, pipeline_info)
   if resources.pipeline == nil then
      fail(sdl_error("failed to create GPU graphics pipeline"))
   end

   local depth_width = 0
   local depth_height = 0

   local function ensure_depth_texture(width, height)
      if resources.depth_texture ~= nil
         and depth_width == width
         and depth_height == height
      then
         return
      end

      if resources.depth_texture ~= nil then
         sdl3.ReleaseGPUTexture(device, resources.depth_texture)
         resources.depth_texture = nil
      end

      resources.depth_texture = assert_ok(
         sdl3.create_depth_texture(device, width, height, depth_format)
      )
      depth_width = width
      depth_height = height
   end

   local vertex_binding = ffi.new("SDL_GPUBufferBinding[1]")
   vertex_binding[0].buffer = resources.vertex_buffer
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
         depth_target_info[0].texture = resources.depth_texture
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
         sdl3.BindGPUGraphicsPipeline(render_pass, resources.pipeline)
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
