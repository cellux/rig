local M = ... or {}

local dxc = require("dxc")
local shaderc = require("shaderc")
local spirvcross = require("spirvcross")
local sdl3 = require("sdl3")
local ffi = ffi

local STAGE_TO_SDL = {
   vertex = sdl3.GPU_SHADERSTAGE_VERTEX,
   fragment = sdl3.GPU_SHADERSTAGE_FRAGMENT,
}

local GRAPHICS_SPIRV_EXPECTED_SETS = {
   vertex = {
      sampled_images = 0,
      separate_samplers = 0,
      separate_images = 0,
      storage_images = 0,
      storage_buffers = 0,
      uniform_buffers = 1,
   },
   fragment = {
      sampled_images = 2,
      separate_samplers = 2,
      separate_images = 2,
      storage_images = 2,
      storage_buffers = 2,
      uniform_buffers = 3,
   },
}

local function read_file(path)
   local file, open_err = io.open(path, "rb")
   if file == nil then
      return nil, ("failed to open '%s': %s"):format(
         path,
         tostring(open_err or "unknown error")
      )
   end

   local contents, read_err = file:read("*all")
   file:close()
   if contents == nil then
      return nil, ("failed to read '%s': %s"):format(
         path,
         tostring(read_err or "unknown error")
      )
   end

   return contents
end

local function load_source(options)
   if type(options.source) == "string" then
      return options.source
   end
   if type(options.path) == "string" then
      return read_file(options.path)
   end
   return nil, "shader source must be provided via source or path"
end

local function validate_graphics_spirv_layout(compiled)
   if compiled.format ~= sdl3.GPU_SHADERFORMAT_SPIRV then
      return true
   end

   local expected_sets = GRAPHICS_SPIRV_EXPECTED_SETS[compiled.stage]
   if expected_sets == nil then
      return true
   end

   local resources = compiled.reflection and compiled.reflection.resources
   if type(resources) ~= "table" then
      return nil, "compiled shader is missing reflection.resources"
   end

   for kind, expected_set in pairs(expected_sets) do
      local list = resources[kind]
      if type(list) == "table" then
         for _, item in ipairs(list) do
            if item.set ~= expected_set then
               return nil, (
                  "SPIR-V %s shader %s resource '%s' is in descriptor set %s, expected %d for SDL_GPU"
               ):format(
                  compiled.stage,
                  kind,
                  tostring(item.name or "<unnamed>"),
                  tostring(item.set),
                  expected_set
               )
            end
         end
      end
   end

   return true
end

function M.compile(options)
   if type(options) ~= "table" then
      error("shader.compile expects a table")
   end

   local language = options.language or "hlsl"
   if language ~= "hlsl" and language ~= "glsl" then
      error("shader.compile currently supports only language='hlsl' or language='glsl'")
   end

   local stage = options.stage
   if stage ~= "vertex" and stage ~= "fragment" and stage ~= "compute" then
      error("shader.compile requires stage to be 'vertex', 'fragment', or 'compute'")
   end

   local source, source_err = load_source(options)
   if source == nil then
      return nil, source_err
   end

   local compiled
   local compile_err
   if language == "hlsl" then
      compiled, compile_err = dxc.compile_spirv({
         source = source,
         stage = stage,
         entrypoint = options.entrypoint,
         source_name = options.source_name or options.path or "shader.hlsl",
         extra_args = options.extra_args,
         preserve_bindings = options.preserve_bindings,
         preserve_interface = options.preserve_interface,
      })
   else
      compiled, compile_err = shaderc.compile_spirv({
         source = source,
         stage = stage,
         entrypoint = options.entrypoint,
         source_name = options.source_name or options.path or "shader.glsl",
         glsl_version = options.glsl_version,
         optimization = options.optimization,
         debug_info = options.debug_info,
         preserve_bindings = options.preserve_bindings,
         macro_definitions = options.macro_definitions,
      })
   end
   if compiled == nil then
      return nil, compile_err
   end

   local reflection, reflection_err = spirvcross.reflect_spirv(compiled)
   if reflection == nil then
      return nil, reflection_err
   end

   compiled.language = language
   compiled.format = sdl3.GPU_SHADERFORMAT_SPIRV
   compiled.reflection = reflection

   local valid_layout, layout_err = validate_graphics_spirv_layout(compiled)
   if not valid_layout then
      return nil, layout_err
   end

   return compiled
end

function M.create_sdl_shader(device, compiled, props)
   if device == nil then
      error("shader.create_sdl_shader requires an SDL_GPUDevice*")
   end
   if type(compiled) ~= "table" then
      error("shader.create_sdl_shader requires a compiled shader table")
   end

   local shader_stage = STAGE_TO_SDL[compiled.stage]
   if shader_stage == nil then
      return nil, ("shader stage '%s' is not a graphics shader stage"):format(
         tostring(compiled.stage)
      )
   end

   local reflection = compiled.reflection
   if type(reflection) ~= "table" or type(reflection.resource_info) ~= "table" then
      return nil, "compiled shader is missing reflection.resource_info"
   end

   local code_buffer = ffi.new("Uint8[?]", #compiled.bytecode)
   ffi.copy(code_buffer, compiled.bytecode, #compiled.bytecode)

   local create_info = ffi.new("SDL_GPUShaderCreateInfo[1]")
   create_info[0].code_size = #compiled.bytecode
   create_info[0].code = code_buffer
   create_info[0].entrypoint = compiled.entrypoint or "main"
   create_info[0].format = compiled.format or sdl3.GPU_SHADERFORMAT_SPIRV
   create_info[0].stage = shader_stage
   create_info[0].num_samplers = reflection.resource_info.num_samplers or 0
   create_info[0].num_storage_textures =
      reflection.resource_info.num_storage_textures or 0
   create_info[0].num_storage_buffers =
      reflection.resource_info.num_storage_buffers or 0
   create_info[0].num_uniform_buffers =
      reflection.resource_info.num_uniform_buffers or 0
   create_info[0].props = props or 0

   local shader_handle = sdl3.CreateGPUShader(device, create_info)
   if shader_handle == nil then
      return nil, ffi.string(sdl3.GetError())
   end

   return shader_handle
end

return M
