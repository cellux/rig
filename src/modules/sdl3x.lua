local M = ... or {}
local animator = require("animator")
local bit = bit
local color = require("color")
local font = require("font")
local ffi = require("ffi")
local profiler = require("profiler")
local rig = require("rig")
local sched = require("sched")
local schema = require("schema")
local sdl3 = require("sdl3")
require("gl")
require("mesh")
local shader = require("shader")
require("time")

--[ error handling ]

function M.get_error(fallback)
   local err = sdl3.GetError()
   if err == nil or err == ffi.NULL or err[0] == 0 then
      return fallback or "unknown SDL error"
   end
   return ffi.string(err)
end

--[ utilities ]

function M.free(ptr)
   if ptr ~= nil and ptr ~= ffi.NULL then
      sdl3.free(ffi.cast("void *", ptr))
   end
end

--[ properties ]

local Properties = rig.Class()
local Window = rig.Class()

function M.normalize_properties_id(props)
   if props == nil then
      return 0
   end

   local value_type = type(props)
   if value_type == "number" or value_type == "cdata" then
      return props
   end

   if Properties:is_instance(props) then
      return props.id
   end

   rig.raise("props must be a number, cdata SDL_PropertiesID, or sdl3x.Properties")
end

local function ensure_properties(properties)
   if not Properties:is_instance(properties) then
      rig.raise("sdl3x.Properties operation expects an sdl3x.Properties instance")
   end
   if properties._released then
      rig.raise("sdl3x.Properties has been released")
   end
end

local function copy_property_values(values)
   local copy = {}
   for key, value in pairs(values) do
      copy[key] = value
   end
   return copy
end

local function set_property_value(properties, name, value)
   if type(name) ~= "string" or name == "" then
      rig.raise("sdl3x.Properties expects property names to be non-empty strings")
   end

   if value == nil then
      if not sdl3.ClearProperty(properties.id, name) then
         rig.raise(("failed to clear property '%s': %s"):format(
            name,
            M.get_error()
         ))
      end
      properties._values[name] = nil
      return properties
   end

   local ok = nil
   local value_type = type(value)
   if value_type == "boolean" then
      ok = sdl3.SetBooleanProperty(properties.id, name, value)
   elseif value_type == "number" then
      if value == math.floor(value) then
         ok = sdl3.SetNumberProperty(properties.id, name, value)
      else
         ok = sdl3.SetFloatProperty(properties.id, name, value)
      end
   elseif value_type == "string" then
      ok = sdl3.SetStringProperty(properties.id, name, value)
   elseif value_type == "cdata" then
      ok = sdl3.SetPointerProperty(properties.id, name, ffi.cast("void *", value))
   else
      rig.raise(
         ("unsupported SDL property value type for '%s': %s"):format(
            name,
            value_type
         )
      )
   end

   if not ok then
      rig.raise(("failed to set property '%s': %s"):format(
         name,
         M.get_error()
      ))
   end

   properties._values[name] = value
   return properties
end

M.Properties = Properties

function Properties:init(values)
   if values ~= nil and type(values) ~= "table" then
      rig.raise("sdl3x.Properties expects a table if initialized with values")
   end

   self.id = sdl3.CreateProperties()
   if self.id == 0 then
      rig.raise("failed to create SDL properties: " .. M.get_error())
   end

   self._released = false
   self._values = {}

   local initial_values = values
   if Properties:is_instance(values) then
      initial_values = values._values
   end

   local ok, err = pcall(function()
      if initial_values ~= nil then
         self:merge(initial_values)
      end
   end)
   if not ok then
      self:release()
      rig.raise(err)
   end
end

function Properties:set(name, value)
   ensure_properties(self)
   return set_property_value(self, name, value)
end

function Properties:clear(name)
   return self:set(name, nil)
end

function Properties:merge(values)
   ensure_properties(self)

   local source = values
   if Properties:is_instance(values) then
      source = values._values
   elseif type(values) ~= "table" then
      rig.raise("sdl3x.Properties:merge expects a table or sdl3x.Properties")
   end

   for key, value in pairs(source) do
      set_property_value(self, key, value)
   end
   return self
end

function Properties:get(name, default)
   ensure_properties(self)
   local value = self._values[name]
   if value == nil then
      return default
   end
   return value
end

function Properties:has(name)
   ensure_properties(self)
   return self._values[name] ~= nil
end

function Properties:to_table()
   ensure_properties(self)
   return copy_property_values(self._values)
end

function Properties:clone()
   ensure_properties(self)
   return Properties(self._values)
end

function Properties:release()
   if self._released then
      return
   end

   if self.id ~= nil and self.id ~= 0 then
      sdl3.DestroyProperties(self.id)
   end

   self.id = 0
   self._values = {}
   self._released = true
end

--[ Window ]

local function ensure_window(window)
   if not Window:is_instance(window) then
      rig.raise("sdl3x.Window operation expects an sdl3x.Window instance")
   end
   if window._released then
      rig.raise("sdl3x.Window has been released")
   end
end

M.Window = Window

local DEFAULT_WINDOW_WIDTH = 640
local DEFAULT_WINDOW_HEIGHT = 360

local default_window_props = {
   [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "rig",
}

local function resolve_default_window_size()
   local default_width = DEFAULT_WINDOW_WIDTH
   local default_height = DEFAULT_WINDOW_HEIGHT
   local primary_display = sdl3.GetPrimaryDisplay()

   if primary_display ~= nil and primary_display ~= 0 then
      local usable_bounds = ffi.new("SDL_Rect[1]")
      if sdl3.GetDisplayUsableBounds(primary_display, usable_bounds) then
         default_width = math.max(
            1,
            math.floor((tonumber(usable_bounds[0].w) or default_width) * 0.75)
         )
         default_height = math.max(
            1,
            math.floor((tonumber(usable_bounds[0].h) or default_height) * 0.75)
         )
      end
   end

   return default_width, default_height
end

local function build_window_properties(options)
   local props = Properties(default_window_props)
   local ok, result_or_err = pcall(function()
      local window_props = options.window_props
      if window_props ~= nil then
         props:merge(window_props)
      end

      local width_key = sdl3.PROP_WINDOW_CREATE_WIDTH_NUMBER
      local height_key = sdl3.PROP_WINDOW_CREATE_HEIGHT_NUMBER
      if not props:has(width_key) or not props:has(height_key) then
         local default_width, default_height = resolve_default_window_size()
         if not props:has(width_key) then
            props:set(width_key, default_width)
         end
         if not props:has(height_key) then
            props:set(height_key, default_height)
         end
      end
   end)

   if not ok then
      props:release()
      return nil, result_or_err
   end

   return props
end

function Window:init(options)
   if options ~= nil and type(options) ~= "table" then
      rig.raise("sdl3x.Window expects a table if initialized with options")
   end

   local props, props_err = build_window_properties(options or {})
   if props == nil then
      rig.raise(props_err)
   end

   local window_ptr = sdl3.CreateWindowWithProperties(props.id)
   props:release()

   if window_ptr == nil then
      rig.raise("failed to create SDL window: " .. M.get_error())
   end

   self.ptr = window_ptr
   self._released = false
end

function Window:get_size()
   ensure_window(self)

   local width_out = ffi.new("int[1]")
   local height_out = ffi.new("int[1]")
   if not sdl3.GetWindowSize(self.ptr, width_out, height_out) then
      rig.raise("failed to query window size: " .. M.get_error())
   end

   return tonumber(width_out[0]) or 0,
      tonumber(height_out[0]) or 0
end

function Window:get_size_in_pixels()
   ensure_window(self)

   local width_out = ffi.new("int[1]")
   local height_out = ffi.new("int[1]")
   if not sdl3.GetWindowSizeInPixels(self.ptr, width_out, height_out) then
      rig.raise("failed to query window size in pixels: " .. M.get_error())
   end

   return tonumber(width_out[0]) or 0,
      tonumber(height_out[0]) or 0
end

function Window:set_fullscreen(enabled)
   ensure_window(self)
   if type(enabled) ~= "boolean" then
      rig.raise("sdl3x.Window:set_fullscreen expects enabled to be a boolean")
   end

   if not sdl3.SetWindowFullscreen(self.ptr, enabled) then
      rig.raise("failed to set window fullscreen: " .. M.get_error())
   end

   return enabled
end

function Window:sync()
   ensure_window(self)

   if not sdl3.SyncWindow(self.ptr) then
      rig.raise("failed to synchronize window state: " .. M.get_error())
   end
end

function Window:release()
   if self._released then
      return
   end

   if self.ptr ~= nil and self.ptr ~= ffi.NULL then
      sdl3.DestroyWindow(self.ptr)
   end

   self.ptr = nil
   self._released = true
end

local VERTEX_INPUT_RATES = {
   vertex = sdl3.GPU_VERTEXINPUTRATE_VERTEX,
   instance = sdl3.GPU_VERTEXINPUTRATE_INSTANCE,
}

local VERTEX_ATTRIBUTE_FORMATS = {
   float = sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT,
   float2 = sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT2,
   float3 = sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT3,
   float4 = sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT4,
}

local function normalize_vertex_input_rate(value)
   if type(value) == "string" then
      local normalized = VERTEX_INPUT_RATES[value]
      if normalized == nil then
         rig.raise("unsupported vertex input rate '" .. value .. "'")
      end
      return normalized
   end
   if type(value) ~= "number" then
      rig.raise("vertex input rate must be a string or number")
   end
   return value
end

local function normalize_vertex_attribute_format(value)
   if type(value) == "string" then
      local normalized = VERTEX_ATTRIBUTE_FORMATS[value]
      if normalized == nil then
         rig.raise("unsupported vertex attribute format '" .. value .. "'")
      end
      return normalized
   end
   if type(value) ~= "number" then
      rig.raise("vertex attribute format must be a string or number")
   end
   return value
end

local function schema_path_label(path)
   if type(path) == "string" and path ~= "" then
      return path
   end
   return "value"
end

local function shallow_copy_table(values)
   local copy = {}
   for key, value in pairs(values) do
      copy[key] = value
   end
   return copy
end

local number_like_schema = schema.number({
   coerce = true,
})

local non_negative_integer_schema = schema.integer({
   coerce = true,
   min = 0,
})

local properties_instance_schema = schema.instance_of(
   Properties,
   "an sdl3x.Properties"
)

local properties_id_schema = schema.optional(schema.any(), 0):transform(function(value, path)
   if value == 0 then
      return 0
   end

   local value_type = type(value)
   if value_type == "number" or value_type == "cdata" then
      return value
   end
   if properties_instance_schema:check(value) then
      return value.id
   end

   rig.raise(
      schema_path_label(path)
         .. " expects a number, cdata SDL_PropertiesID, or sdl3x.Properties"
   )
end)

local vertex_input_rate_schema = schema.one_of({
   schema.non_empty_string():transform(function(value)
      return normalize_vertex_input_rate(value)
   end),
   number_like_schema,
}, "a string or number")

local vertex_attribute_format_schema = schema.one_of({
   schema.non_empty_string():transform(function(value)
      return normalize_vertex_attribute_format(value)
   end),
   number_like_schema,
}, "a string or number")

local gpu_vertex_buffer_description_schema = schema.ffi.struct(
   "SDL_GPUVertexBufferDescription",
   {
      slot = non_negative_integer_schema,
      pitch = non_negative_integer_schema,
      input_rate = vertex_input_rate_schema:optional(
         normalize_vertex_input_rate("vertex")
      ),
      instance_step_rate = non_negative_integer_schema:optional(0),
   }
)

local gpu_vertex_attribute_source_schema = schema.record({
   location = non_negative_integer_schema,
   buffer_slot = non_negative_integer_schema:optional(),
   slot = non_negative_integer_schema:optional(),
   format = vertex_attribute_format_schema,
   offset = non_negative_integer_schema,
}):transform(function(value)
   value.buffer_slot = value.buffer_slot or value.slot or 0
   value.slot = nil
   return value
end)

local gpu_vertex_attribute_schema = schema.ffi.struct("SDL_GPUVertexAttribute", {
   location = non_negative_integer_schema,
   buffer_slot = non_negative_integer_schema:optional(0),
   format = vertex_attribute_format_schema,
   offset = non_negative_integer_schema,
})

local gpu_color_target_blend_state_schema = schema.ffi.struct(
   "SDL_GPUColorTargetBlendState",
   {
      src_color_blendfactor = number_like_schema:optional(),
      dst_color_blendfactor = number_like_schema:optional(),
      color_blend_op = number_like_schema:optional(),
      src_alpha_blendfactor = number_like_schema:optional(),
      dst_alpha_blendfactor = number_like_schema:optional(),
      alpha_blend_op = number_like_schema:optional(),
      color_write_mask = number_like_schema:optional(),
      enable_blend = schema.boolean():optional(),
      enable_color_write_mask = schema.boolean():optional(),
   }
)

local gpu_color_target_description_schema = schema.ffi.struct(
   "SDL_GPUColorTargetDescription",
   {
      format = number_like_schema,
      blend_state = gpu_color_target_blend_state_schema:optional(),
   }
)

local gpu_vertex_buffer_descriptions_schema = schema.ffi.array(
   "SDL_GPUVertexBufferDescription",
   gpu_vertex_buffer_description_schema
)

local gpu_vertex_attributes_schema = schema.ffi.array(
   "SDL_GPUVertexAttribute",
   gpu_vertex_attribute_schema
)

local gpu_color_target_descriptions_schema = schema.ffi.array(
   "SDL_GPUColorTargetDescription",
   gpu_color_target_description_schema
)

local gpu_buffer_create_info_schema = schema.ffi.struct(
   "SDL_GPUBufferCreateInfo",
   {
      usage = number_like_schema,
      size = non_negative_integer_schema,
      props = properties_id_schema,
   }
)

local graphics_pipeline_rasterizer_state_schema = schema.ffi.struct(
   "SDL_GPURasterizerState",
   {
      fill_mode = number_like_schema:optional(),
      cull_mode = number_like_schema:optional(),
      front_face = number_like_schema:optional(),
      depth_bias_constant_factor = number_like_schema:optional(),
      depth_bias_clamp = number_like_schema:optional(),
      depth_bias_slope_factor = number_like_schema:optional(),
      enable_depth_bias = schema.boolean():optional(),
      enable_depth_clip = schema.boolean():optional(),
   }
)

local graphics_pipeline_multisample_state_schema = schema.ffi.struct(
   "SDL_GPUMultisampleState",
   {
      sample_count = number_like_schema:optional(),
      sample_mask = number_like_schema:optional(),
      enable_mask = schema.boolean():optional(),
      enable_alpha_to_coverage = schema.boolean():optional(),
   }
)

local graphics_pipeline_depth_stencil_state_schema = schema.ffi.struct(
   "SDL_GPUDepthStencilState",
   {
      compare_op = number_like_schema:optional(),
      enable_depth_test = schema.boolean():optional(),
      enable_depth_write = schema.boolean():optional(),
      enable_stencil_test = schema.boolean():optional(),
      compare_mask = number_like_schema:optional(),
      write_mask = number_like_schema:optional(),
   }
)

local graphics_pipeline_target_info_schema = schema.ffi.struct(
   "SDL_GPUGraphicsPipelineTargetInfo",
   {
      color_target_descriptions = {
         schema = gpu_color_target_descriptions_schema:optional(),
         count_field = "num_color_targets",
      },
      depth_stencil_format = number_like_schema:optional(),
      has_depth_stencil_target = schema.boolean():optional(),
   }
)

local graphics_pipeline_create_info_schema = schema.ffi.struct(
   "SDL_GPUGraphicsPipelineCreateInfo",
   {
      vertex_shader = schema.any():optional(),
      fragment_shader = schema.any():optional(),
      primitive_type = number_like_schema,
      vertex_input = {
         schema = schema.any():optional(),
         assign = function(dst, value, bundle)
            if type(value) == "table" and value.state ~= nil then
               dst.vertex_input_state = value.state[0]
               bundle:retain(value)
               return
            end
            dst.vertex_input_state = value
         end,
      },
      rasterizer_state = graphics_pipeline_rasterizer_state_schema:optional(),
      multisample_state = graphics_pipeline_multisample_state_schema:optional(),
      depth_stencil_state = graphics_pipeline_depth_stencil_state_schema:optional(),
      target_info = graphics_pipeline_target_info_schema:optional(),
      props = properties_id_schema,
   }
)

local vertex_input_layout_buffer_schema = schema.record({
   slot = non_negative_integer_schema:optional(),
   pitch = non_negative_integer_schema,
   input_rate = vertex_input_rate_schema:optional(
      normalize_vertex_input_rate("vertex")
   ),
   instance_step_rate = non_negative_integer_schema:optional(0),
   attributes = schema.array(gpu_vertex_attribute_source_schema),
})

local vertex_input_layout_schema = schema.record({
   buffers = schema.array(vertex_input_layout_buffer_schema),
})

function M.build_vertex_buffer_descriptions(buffers)
   local raw_buffers = schema.assert(
      schema.array(schema.table()),
      buffers,
      "sdl3x.build_vertex_buffer_descriptions buffers"
   )
   local normalized = {}

   for i = 1, #raw_buffers do
      local spec = shallow_copy_table(raw_buffers[i])
      if spec.slot == nil then
         spec.slot = i - 1
      end
      normalized[i] = spec
   end

   return schema.assert(
      gpu_vertex_buffer_descriptions_schema,
      normalized,
      "sdl3x.build_vertex_buffer_descriptions buffers"
   ).cdata
end

function M.build_vertex_attributes(attributes)
   local normalized = schema.assert(
      schema.array(gpu_vertex_attribute_source_schema),
      attributes,
      "sdl3x.build_vertex_attributes attributes"
   )

   return schema.assert(
      gpu_vertex_attributes_schema,
      normalized,
      "sdl3x.build_vertex_attributes attributes"
   ).cdata
end

function M.build_vertex_input_state(layout)
   local decoded = schema.assert(
      vertex_input_layout_schema,
      layout,
      "sdl3x.build_vertex_input_state layout"
   )

   local attribute_specs = {}
   local buffer_specs = {}
   for i = 1, #decoded.buffers do
      local buffer = shallow_copy_table(decoded.buffers[i])
      local buffer_slot = buffer.slot
      if buffer_slot == nil then
         buffer_slot = i - 1
         buffer.slot = buffer_slot
      end
      buffer.attributes = nil
      buffer_specs[i] = buffer

      for j = 1, #decoded.buffers[i].attributes do
         local spec = shallow_copy_table(decoded.buffers[i].attributes[j])
         spec.buffer_slot = buffer_slot
         attribute_specs[#attribute_specs + 1] = spec
      end
   end

   local descriptions = schema.assert(
      gpu_vertex_buffer_descriptions_schema,
      buffer_specs,
      "sdl3x.build_vertex_input_state buffers"
   )
   local attributes = schema.assert(
      gpu_vertex_attributes_schema,
      attribute_specs,
      "sdl3x.build_vertex_input_state attributes"
   )
   local state = ffi.new("SDL_GPUVertexInputState[1]")
   state[0].vertex_buffer_descriptions = descriptions.cdata
   state[0].num_vertex_buffers = descriptions.length
   state[0].vertex_attributes = attributes.cdata
   state[0].num_vertex_attributes = attributes.length

   local bundle = schema.ffi.Bundle("struct", state, state[0], 1)
   bundle.state = state
   bundle.vertex_buffer_descriptions = descriptions.cdata
   bundle.vertex_attributes = attributes.cdata
   bundle:retain(descriptions)
   bundle:retain(attributes)
   return bundle
end

function M.build_color_target_descriptions(specs)
   return schema.assert(
      gpu_color_target_descriptions_schema,
      specs,
      "sdl3x.build_color_target_descriptions specs"
   ).cdata
end

function M.build_gpu_buffer_create_info(spec)
   return schema.assert(
      gpu_buffer_create_info_schema,
      spec,
      "sdl3x.build_gpu_buffer_create_info spec"
   ).cdata
end

function M.build_graphics_pipeline_create_info(spec)
   local bundle = schema.assert(
      graphics_pipeline_create_info_schema,
      spec,
      "sdl3x.build_graphics_pipeline_create_info spec"
   )
   bundle.create_info = bundle.cdata
   return bundle
end

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

local function normalize_gpu_shader_format(compiled)
   local format = compiled.format
   if format == nil or format == "spirv" then
      return sdl3.GPU_SHADERFORMAT_SPIRV
   end

   local numeric = tonumber(format)
   if numeric == nil then
      error(("compiled shader format '%s' is not supported by SDL GPU"):format(
         format
      ))
   end

   return numeric
end

local function validate_graphics_spirv_layout(compiled)
   if normalize_gpu_shader_format(compiled) ~= sdl3.GPU_SHADERFORMAT_SPIRV then
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
                  item.name or "<unnamed>",
                  item.set,
                  expected_set
               )
            end
         end
      end
   end

   return true
end

function M.create_gpu_shader(device, compiled, props)
   if device == nil then
      rig.raise("sdl3x.create_gpu_shader requires an SDL_GPUDevice*")
   end
   if type(compiled) ~= "table" then
      error("sdl3x.create_gpu_shader requires a compiled shader table")
   end

   local shader_stage = STAGE_TO_SDL[compiled.stage]
   if shader_stage == nil then
      error(("shader stage '%s' is not a graphics shader stage"):format(
         compiled.stage
      ))
   end

   local valid_layout, layout_err = validate_graphics_spirv_layout(compiled)
   if not valid_layout then
      rig.raise(layout_err or "shader layout validation failed")
   end

   local reflection = compiled.reflection
   if type(reflection) ~= "table" or type(reflection.resource_info) ~= "table" then
      rig.raise("compiled shader is missing reflection.resource_info")
   end

   local code_buffer = ffi.new("Uint8[?]", #compiled.bytecode)
   ffi.copy(code_buffer, compiled.bytecode, #compiled.bytecode)

   local create_info = ffi.new("SDL_GPUShaderCreateInfo[1]")
   create_info[0].code_size = #compiled.bytecode
   create_info[0].code = code_buffer
   create_info[0].entrypoint = compiled.entrypoint or "main"
   create_info[0].format = normalize_gpu_shader_format(compiled)
   create_info[0].stage = shader_stage
   create_info[0].num_samplers = reflection.resource_info.num_samplers or 0
   create_info[0].num_storage_textures =
      reflection.resource_info.num_storage_textures or 0
   create_info[0].num_storage_buffers =
      reflection.resource_info.num_storage_buffers or 0
   create_info[0].num_uniform_buffers =
      reflection.resource_info.num_uniform_buffers or 0
   create_info[0].props = M.normalize_properties_id(props)

   local shader_handle = sdl3.CreateGPUShader(device, create_info)
   if shader_handle == nil then
      rig.raise(M.get_error())
   end

   return shader_handle
end

local sdl3x_resource_scope_methods = {}

function sdl3x_resource_scope_methods:create_gpu_shader(compiled, props)
   local shader_handle = M.create_gpu_shader(self.context, compiled, props)
   return self:adopt(shader_handle, function(device, resource)
      sdl3.ReleaseGPUShader(device, resource)
   end)
end

function sdl3x_resource_scope_methods:create_gpu_buffer(create_info)
   local normalized = create_info
   if type(create_info) == "table" then
      normalized = M.build_gpu_buffer_create_info(create_info)
   end

   local buffer = sdl3.CreateGPUBuffer(self.context, normalized)
   if buffer == nil then
      rig.raise("failed to create GPU buffer: " .. M.get_error())
   end

   return self:adopt(buffer, function(device, resource)
      sdl3.ReleaseGPUBuffer(device, resource)
   end)
end

function sdl3x_resource_scope_methods:create_graphics_pipeline(create_info)
   local normalized = create_info
   if type(create_info) == "table" then
      local bundle = M.build_graphics_pipeline_create_info(create_info)
      normalized = bundle.create_info
   end

   local pipeline = sdl3.CreateGPUGraphicsPipeline(self.context, normalized)
   if pipeline == nil then
      rig.raise("failed to create GPU graphics pipeline: " .. M.get_error())
   end

   return self:adopt(pipeline, function(device, resource)
      sdl3.ReleaseGPUGraphicsPipeline(device, resource)
   end)
end

function sdl3x_resource_scope_methods:create_depth_texture(width, height, format)
   local texture, chosen_format =
      M.create_depth_texture(self.context, width, height, format)
   self:adopt(texture, function(device, resource)
      sdl3.ReleaseGPUTexture(device, resource)
   end)
   return texture, chosen_format
end

function M.resource_scope(device)
   if device == nil then
      rig.raise("sdl3x.resource_scope requires an SDL_GPUDevice*")
   end

   local scope = rig.ResourceScope(device, "sdl3x resource scope")
   for name, method in pairs(sdl3x_resource_scope_methods) do
      scope[name] = method
   end
   return scope
end

local runtime_window = nil
local runtime_renderer = nil
local runtime_gpu_device = nil
local runtime_gl_context = nil
local runtime_owned_init_flags = nil
local runtime_scheduler = nil

local driver_config_entry_schema = schema.table()
local driver_config_schema = schema.map(
   schema.non_empty_string(),
   driver_config_entry_schema
)

local function merge_props(base_props, override_props)
   local merged = {}

   if type(base_props) == "table" then
      for key, value in pairs(base_props) do
         merged[key] = value
      end
   end

   if override_props ~= nil then
      if type(override_props) ~= "table" then
         return nil, "override_props must be a table if set"
      end

      for key, value in pairs(override_props) do
         merged[key] = value
      end
   end

   return merged
end

local function default_create_renderer(window)
   local renderer_ptr = sdl3.CreateRenderer(window.ptr, nil)
   if renderer_ptr == nil then
      return nil, M.get_error()
   end

   if not sdl3.SetRenderVSync(renderer_ptr, 1) then
      sdl3.DestroyRenderer(renderer_ptr)
      return nil, M.get_error()
   end

   return renderer_ptr
end

local function get_error_string()
   return M.get_error()
end

local function has_all_bits(value, mask)
   local v = tonumber(value) or 0
   local m = tonumber(mask) or 0
   return bit.band(v, m) == bit.tobit(m)
end

local function has_any_bits(value, mask)
   local v = tonumber(value) or 0
   local m = tonumber(mask) or 0
   return bit.band(v, m) ~= 0
end

local function format_gpu_shader_formats(flags)
   local names = {}
   local value = tonumber(flags) or 0

   if value == 0 then
      return "INVALID"
   end

   local mapping = {
      { sdl3.GPU_SHADERFORMAT_PRIVATE, "PRIVATE" },
      { sdl3.GPU_SHADERFORMAT_SPIRV, "SPIRV" },
      { sdl3.GPU_SHADERFORMAT_DXBC, "DXBC" },
      { sdl3.GPU_SHADERFORMAT_DXIL, "DXIL" },
      { sdl3.GPU_SHADERFORMAT_MSL, "MSL" },
      { sdl3.GPU_SHADERFORMAT_METALLIB, "METALLIB" },
   }

   for _, entry in ipairs(mapping) do
      if has_any_bits(value, entry[1]) then
         table.insert(names, entry[2])
      end
   end

   if #names == 0 then
      return tostring(value)
   end
   return table.concat(names, "|")
end

function M.get_gpu_driver_names()
   local count = tonumber(sdl3.GetNumGPUDrivers()) or 0
   local names = {}

   for i = 0, count - 1 do
      local ptr = sdl3.GetGPUDriver(i)
      if ptr ~= nil and ptr ~= ffi.NULL and ptr[0] ~= 0 then
         table.insert(names, ffi.string(ptr))
      end
   end

   return names
end

local function build_gpu_support_error(format_flags, backend_name, detail)
   local lines = {}
   table.insert(lines, "no supported SDL_GPU backend is available")
   table.insert(
      lines,
      "requested shader formats: " .. format_gpu_shader_formats(format_flags)
   )

   if backend_name ~= nil then
      table.insert(lines, "requested backend: " .. tostring(backend_name))
   else
      table.insert(lines, "requested backend: automatic")
   end

   local driver_names = M.get_gpu_driver_names()
   if #driver_names > 0 then
      table.insert(
         lines,
         "SDL compiled GPU drivers: " .. table.concat(driver_names, ", ")
      )
   else
      table.insert(lines, "SDL compiled GPU drivers: none reported")
   end

   if detail ~= nil and detail ~= "" then
      table.insert(lines, "SDL error: " .. tostring(detail))
   end

   if has_any_bits(format_flags, sdl3.GPU_SHADERFORMAT_SPIRV) then
      table.insert(lines, "SPIR-V requires a Vulkan-capable SDL_GPU backend.")
      table.insert(
         lines,
         "Check that a Vulkan ICD is installed and that the GPU exposes enough Vulkan support."
      )
      table.insert(
         lines,
         "Older Intel Haswell GPUs often expose only incomplete Vulkan support through Mesa hasvk and may still be rejected by SDL_GPU."
      )
   end

   return table.concat(lines, "\n")
end

local function format_factory_error(factory_name, detail, fallback)
   if detail == nil then
      return ("%s failed: %s"):format(factory_name, fallback)
   end
   return ("%s failed: %s"):format(factory_name, detail)
end

local function normalize_init_flags(flags_number)
   if type(flags_number) ~= "number" then
      rig.raise("sdl3 init_flags must be a number")
   end

   local flags_integer = math.floor(flags_number)
   if flags_number < 0.0 or flags_number ~= flags_integer then
      error("sdl3 init_flags must be a non-negative integer")
   end
   if flags_number > 4294967295.0 then
      error("sdl3 init_flags exceeds Uint32 range")
   end

   return ffi.cast("Uint32", flags_integer)
end

local function normalize_driver_config(options)
   if options == nil then
      return {}
   end
   return schema.assert(
      driver_config_entry_schema,
      options,
      "sdl3 driver configuration"
   )
end

local function get_driver_config(options, driver_id)
   local driver_config = options.driver_config
   if driver_config == nil then
      return {}
   end
   driver_config = schema.assert(
      driver_config_schema,
      driver_config,
      "rig.run options.driver_config"
   )

   local config = driver_config[driver_id]
   if config == nil then
      return {}
   end
   return normalize_driver_config(config)
end

local shutdown
local destroy_gl_font_backend_state
local gl_font_quad_vertices = ffi.new("float[24]")
local gl_font_backend_state = nil
local resize_state = nil

function M.get_window()
   return runtime_window
end

function M.get_renderer()
   return runtime_renderer
end

function M.get_gpu_device()
   return runtime_gpu_device
end

function M.get_gl_context()
   return runtime_gl_context
end

function M.get_gl_proc_address(name)
   if type(name) ~= "string" or name == "" then
      rig.raise("sdl3x.get_gl_proc_address expects a non-empty string")
   end

   local ptr = sdl3.GL_GetProcAddress(name)
   if ptr == nil or ptr == ffi.NULL then
      return nil, get_error_string()
   end

   return ptr
end

local function get_window_size()
   if runtime_window == nil then
      rig.raise("an SDL window must exist before querying window size")
   end

   return runtime_window:get_size()
end

local function initialize_windowed_sdl(options)
   if runtime_renderer ~= nil or runtime_window ~= nil or runtime_gpu_device ~= nil or runtime_gl_context ~= nil then
      shutdown()
   end

   options = normalize_driver_config(options)

   local required =
      normalize_init_flags(options.init_flags or (sdl3.INIT_VIDEO + sdl3.INIT_EVENTS))
   local initialized = sdl3.WasInit(required)
   local owned_init_flags = nil

   if not has_all_bits(initialized, required) then
      if not sdl3.Init(required) then
         error("failed to initialize SDL: " .. get_error_string())
      end
      owned_init_flags = required
   end

   return options, owned_init_flags
end

local function create_window_or_fail(options, owned_init_flags)
   local ok, window_or_err = pcall(Window, options)
   if not ok then
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      error(window_or_err, 0)
   end

   return window_or_err, owned_init_flags
end

local function setup(options)
   local owned_init_flags = nil
   options, owned_init_flags = initialize_windowed_sdl(options)
   local window = create_window_or_fail(options, owned_init_flags)
   local create_renderer = options.create_renderer or default_create_renderer
   if type(create_renderer) ~= "function" then
      window:release()
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      rig.raise("sdl3 create_renderer must be a function")
   end

   local renderer_ptr, renderer_err = create_renderer(window)
   if renderer_ptr == nil then
      window:release()
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      error(format_factory_error(
         "sdl3 create_renderer",
         renderer_err,
         "expected SDL_Renderer* cdata"
      ))
   end
   if type(renderer_ptr) ~= "cdata" then
      window:release()
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      rig.raise("sdl3 create_renderer must return SDL_Renderer* cdata")
   end

   runtime_window = window
   runtime_renderer = renderer_ptr
   runtime_owned_init_flags = owned_init_flags
   resize_state = nil
end

local function setup_gpu(options)
   if options ~= nil and type(options) ~= "table" then
      error("sdl3x.setup_gpu expects a table if options are provided")
   end

   local owned_init_flags = nil
   options, owned_init_flags = initialize_windowed_sdl(options)
   local window = create_window_or_fail(options, owned_init_flags)

   local format_flags = options and options.shader_formats
   if format_flags == nil then
      format_flags = sdl3.GPU_SHADERFORMAT_SPIRV
   end
   local debug_mode = options and options.debug_mode and true or false
   local backend_name = options and options.backend_name or nil

   if not sdl3.GPUSupportsShaderFormats(format_flags, backend_name) then
      window:release()
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      error(build_gpu_support_error(
         format_flags,
         backend_name,
         get_error_string()
      ))
   end

   local gpu_device = sdl3.CreateGPUDevice(format_flags, debug_mode, backend_name)
   if gpu_device == nil then
      window:release()
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      error(build_gpu_support_error(
         format_flags,
         backend_name,
         get_error_string()
      ))
   end

   if not sdl3.ClaimWindowForGPUDevice(gpu_device, window.ptr) then
      sdl3.DestroyGPUDevice(gpu_device)
      window:release()
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      error("failed to claim SDL window for GPU device: " .. get_error_string())
   end

   runtime_window = window
   runtime_gpu_device = gpu_device
   runtime_owned_init_flags = owned_init_flags
   resize_state = nil
end

local GL_PROFILE_VALUES = {
   core = "GL_CONTEXT_PROFILE_CORE",
   compatibility = "GL_CONTEXT_PROFILE_COMPATIBILITY",
   es = "GL_CONTEXT_PROFILE_ES",
}

local GL_ATTRIBUTE_VALUES = {
   red_size = "GL_ATTR_RED_SIZE",
   green_size = "GL_ATTR_GREEN_SIZE",
   blue_size = "GL_ATTR_BLUE_SIZE",
   alpha_size = "GL_ATTR_ALPHA_SIZE",
   buffer_size = "GL_ATTR_BUFFER_SIZE",
   doublebuffer = "GL_ATTR_DOUBLEBUFFER",
   depth_size = "GL_ATTR_DEPTH_SIZE",
   stencil_size = "GL_ATTR_STENCIL_SIZE",
   multisamplebuffers = "GL_ATTR_MULTISAMPLEBUFFERS",
   multisamplesamples = "GL_ATTR_MULTISAMPLESAMPLES",
   accelerated_visual = "GL_ATTR_ACCELERATED_VISUAL",
   context_major_version = "GL_ATTR_CONTEXT_MAJOR_VERSION",
   context_minor_version = "GL_ATTR_CONTEXT_MINOR_VERSION",
   context_flags = "GL_ATTR_CONTEXT_FLAGS",
   context_profile = "GL_ATTR_CONTEXT_PROFILE_MASK",
   share_with_current_context = "GL_ATTR_SHARE_WITH_CURRENT_CONTEXT",
   framebuffer_srgb_capable = "GL_ATTR_FRAMEBUFFER_SRGB_CAPABLE",
}

local function gl_attribute_int(value)
   if type(value) == "boolean" then
      return value and 1 or 0
   end
   local normalized = tonumber(value)
   if normalized == nil then
      rig.raise("OpenGL attribute values must be booleans or numbers")
   end
   return normalized
end

local function normalize_gl_profile(value)
   if type(value) == "string" then
      local field = GL_PROFILE_VALUES[value]
      if field == nil then
         rig.raise("unsupported OpenGL context profile '" .. value .. "'")
      end
      return sdl3[field]
   end
   return gl_attribute_int(value)
end

local gl_attribute_value_schema = schema.one_of({
   schema.boolean(),
   number_like_schema,
}, "a boolean or number"):transform(function(value)
   return gl_attribute_int(value)
end)

local gl_context_profile_schema = schema.one_of({
   schema.non_empty_string():transform(function(value)
      return normalize_gl_profile(value)
   end),
   gl_attribute_value_schema,
}, "a supported OpenGL context profile or boolean/number")

local gl_attributes_schema = schema.record({
   red_size = gl_attribute_value_schema:optional(),
   green_size = gl_attribute_value_schema:optional(),
   blue_size = gl_attribute_value_schema:optional(),
   alpha_size = gl_attribute_value_schema:optional(),
   buffer_size = gl_attribute_value_schema:optional(),
   doublebuffer = gl_attribute_value_schema:optional(),
   depth_size = gl_attribute_value_schema:optional(),
   stencil_size = gl_attribute_value_schema:optional(),
   multisamplebuffers = gl_attribute_value_schema:optional(),
   multisamplesamples = gl_attribute_value_schema:optional(),
   accelerated_visual = gl_attribute_value_schema:optional(),
   context_major_version = gl_attribute_value_schema:optional(),
   context_minor_version = gl_attribute_value_schema:optional(),
   context_flags = gl_attribute_value_schema:optional(),
   context_profile = gl_context_profile_schema:optional(),
   share_with_current_context = gl_attribute_value_schema:optional(),
   framebuffer_srgb_capable = gl_attribute_value_schema:optional(),
})

local default_gl_attributes = {
   context_major_version = 3,
   context_minor_version = 3,
   context_profile = "core",
   doublebuffer = true,
   depth_size = 24,
}

local function apply_gl_attributes(attributes)
   sdl3.GL_ResetAttributes()

   local requested = schema.assert(
      gl_attributes_schema,
      attributes or default_gl_attributes,
      "sdl3_gl gl_attributes"
   )

   for key, value in pairs(requested) do
      local field = GL_ATTRIBUTE_VALUES[key]

      if not sdl3.GL_SetAttribute(sdl3[field], value) then
         error(
            ("failed to set OpenGL attribute '%s': %s"):format(
               key,
               get_error_string()
            ))
      end
   end
end

local function setup_gl(options)
   if options ~= nil and type(options) ~= "table" then
      rig.raise("sdl3_gl options must be a table if provided")
   end

   options = normalize_driver_config(options)
   local window_props, props_err = merge_props(options.window_props, {
      [sdl3.PROP_WINDOW_CREATE_OPENGL_BOOLEAN] = true,
   })
   if window_props == nil then
      rig.raise(props_err)
   end

   local window_options = {}
   for key, value in pairs(options) do
      window_options[key] = value
   end
   window_options.window_props = window_props

   local owned_init_flags = nil
   window_options, owned_init_flags = initialize_windowed_sdl(window_options)
   apply_gl_attributes(options.gl_attributes)
   local window = create_window_or_fail(window_options, owned_init_flags)
   local gl_context = sdl3.GL_CreateContext(window.ptr)
   if gl_context == nil then
      window:release()
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      rig.raise("failed to create OpenGL context: " .. get_error_string())
   end

   if not sdl3.GL_MakeCurrent(window.ptr, gl_context) then
      sdl3.GL_DestroyContext(gl_context)
      window:release()
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      rig.raise("failed to make OpenGL context current: " .. get_error_string())
   end

   local swap_interval = options.swap_interval
   if swap_interval == nil then
      swap_interval = 1
   end
   if not sdl3.GL_SetSwapInterval(gl_attribute_int(swap_interval)) then
      sdl3.GL_DestroyContext(gl_context)
      window:release()
      if owned_init_flags ~= nil then
         sdl3.QuitSubSystem(owned_init_flags)
      end
      rig.raise("failed to set OpenGL swap interval: " .. get_error_string())
   end

   runtime_window = window
   runtime_gl_context = gl_context
   runtime_owned_init_flags = owned_init_flags
   resize_state = nil
end

shutdown = function()
   destroy_gl_font_backend_state()
   if runtime_gl_context ~= nil then
      sdl3.GL_DestroyContext(runtime_gl_context)
      runtime_gl_context = nil
   end
   if runtime_gpu_device ~= nil then
      sdl3.WaitForGPUIdle(runtime_gpu_device)
      if runtime_window ~= nil then
         sdl3.ReleaseWindowFromGPUDevice(runtime_gpu_device, runtime_window.ptr)
      end
      sdl3.DestroyGPUDevice(runtime_gpu_device)
      runtime_gpu_device = nil
   end
   if runtime_renderer ~= nil then
      sdl3.DestroyRenderer(runtime_renderer)
      runtime_renderer = nil
   end
   if runtime_window ~= nil then
      runtime_window:release()
      runtime_window = nil
   end
   resize_state = nil
   if runtime_owned_init_flags ~= nil then
      sdl3.QuitSubSystem(runtime_owned_init_flags)
      runtime_owned_init_flags = nil
   end
end

local function present()
   if runtime_renderer == nil then
      rig.raise("SDL renderer is not initialized")
   end
   if not sdl3.RenderPresent(runtime_renderer) then
      error("failed to present renderer: " .. get_error_string())
   end
end

local function present_gl()
   if runtime_window == nil or runtime_gl_context == nil then
      rig.raise("an OpenGL window and context must be initialized before presenting")
   end
   if not sdl3.GL_SwapWindow(runtime_window.ptr) then
      rig.raise("failed to swap OpenGL window: " .. M.get_error())
   end
end

local font_src_rect = ffi.new("SDL_FRect[1]")
local font_dst_rect = ffi.new("SDL_FRect[1]")

local gl_font_vertex_source = [[
#version 330 core

layout(location = 0) in vec2 in_position;
layout(location = 1) in vec2 in_uv;

out vec2 out_uv;

uniform vec2 u_view_size;

void main()
{
   vec2 normalized = vec2(
      (in_position.x / u_view_size.x) * 2.0 - 1.0,
      1.0 - (in_position.y / u_view_size.y) * 2.0
   );
   gl_Position = vec4(normalized, 0.0, 1.0);
   out_uv = in_uv;
}
]]

local gl_font_fragment_source = [[
#version 330 core

in vec2 out_uv;
out vec4 frag_color;

uniform sampler2D u_atlas;
uniform vec4 u_color;

void main()
{
   vec4 sample = texture(u_atlas, out_uv);
   frag_color = vec4(u_color.rgb, u_color.a * sample.a);
}
]]

destroy_gl_font_backend_state = function()
   local state = gl_font_backend_state
   if state == nil then
      return
   end

   if state.vbo ~= nil then
      state.vbo:release()
   end
   if state.vao ~= nil then
      state.vao:release()
   end
   if state.program ~= nil then
      state.program:release()
   end

   gl_font_backend_state = nil
end

local function ensure_gl_font_backend_state()
   if gl_font_backend_state ~= nil then
      return gl_font_backend_state
   end

   local gl = require("gl")
   local glx = require("glx")
   local program = glx.Program {
      vertex_source = gl_font_vertex_source,
      fragment_source = gl_font_fragment_source,
   }
   local vao = glx.VertexArray()
   local vbo = glx.Buffer {
      target = gl.ARRAY_BUFFER,
   }
   if vbo.id == 0 then
      vao:release()
      program:release()
      rig.raise("failed to create OpenGL font vertex objects")
   end

   vao:bind()
   vbo:set_data(nil, gl.DYNAMIC_DRAW, ffi.sizeof(gl_font_quad_vertices))
   vao:attribute(0, 2, gl.FLOAT, gl.FALSE, 16, 0)
   vao:attribute(1, 2, gl.FLOAT, gl.FALSE, 16, 8)

   local atlas_location = program:uniform_location("u_atlas")
   local view_size_location = program:uniform_location("u_view_size")
   local color_location = program:uniform_location("u_color")
   if atlas_location < 0 or view_size_location < 0 or color_location < 0 then
      vbo:release()
      vao:release()
      program:release()
      rig.raise("failed to locate OpenGL font shader uniforms")
   end

   program:use()
   program:set_uniform1i("u_atlas", 0)

   gl_font_backend_state = {
      gl = gl,
      program = program,
      vao = vao,
      vbo = vbo,
   }

   return gl_font_backend_state
end

local function get_window_size_in_pixels()
   if runtime_window == nil then
      rig.raise("an SDL window must exist before querying pixel size")
   end

   return runtime_window:get_size_in_pixels()
end

local function dispatch_resize_if_changed(runtime, event_name, timestamp_ns)
   local width, height = get_window_size()
   local pixel_width, pixel_height = get_window_size_in_pixels()
   local previous = resize_state

   if previous ~= nil
      and previous.width == width
      and previous.height == height
      and previous.pixel_width == pixel_width
      and previous.pixel_height == pixel_height
      and event_name ~= "initial" then
      return
   end

   resize_state = {
      width = width,
      height = height,
      pixel_width = pixel_width,
      pixel_height = pixel_height,
   }

   local ns = timestamp_ns or 0
   runtime:handle_event("resize", {
      type = "resize",
      event = event_name,
      width = width,
      height = height,
      pixel_width = pixel_width,
      pixel_height = pixel_height,
      initial = event_name == "initial",
      timestamp_ns = ns,
      timestamp_ms = math.floor(ns / 1000000),
   })
end

local function upload_gl_font_page_texture(page, texture)
   local pixel_count = page.width * page.height
   local rgba = ffi.new("uint8_t[?]", pixel_count * 4)

   for i = 0, pixel_count - 1 do
      local alpha = page.buffer[i]
      local base = i * 4
      rgba[base] = 255
      rgba[base + 1] = 255
      rgba[base + 2] = 255
      rgba[base + 3] = alpha
   end

   local gl = require("gl")
   local texture_2d = texture
   if texture_2d == nil then
      texture_2d = require("glx").Texture2D()
   end

   texture_2d:bind(0)
   texture_2d:parameter(gl.TEXTURE_MIN_FILTER, gl.LINEAR)
   texture_2d:parameter(gl.TEXTURE_MAG_FILTER, gl.LINEAR)
   texture_2d:parameter(gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
   texture_2d:parameter(gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
   texture_2d:image(
      0,
      gl.RGBA,
      page.width,
      page.height,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      rgba,
      0
   )

   return texture_2d
end

local function ensure_gl_font_page_texture(text_renderer, page_index)
   local atlas = text_renderer.atlas
   local state = text_renderer._state
   local page = atlas.pages[page_index]
   if page == nil then
      rig.raise("font atlas has no page %d", page_index)
   end

   local revision = page.revision or 0
   if state.revisions[page_index] == revision and state.textures[page_index] ~= nil then
      return state.textures[page_index]
   end

   local texture = upload_gl_font_page_texture(page, state.textures[page_index])
   state.textures[page_index] = texture
   state.revisions[page_index] = revision
   return texture
end

local function write_gl_font_quad_vertices(packed, x, y, scale)
   local x0 = x
   local y0 = y
   local x1 = x + packed.width * scale
   local y1 = y + packed.height * scale

   gl_font_quad_vertices[0] = x0
   gl_font_quad_vertices[1] = y0
   gl_font_quad_vertices[2] = packed.u0
   gl_font_quad_vertices[3] = packed.v0

   gl_font_quad_vertices[4] = x1
   gl_font_quad_vertices[5] = y0
   gl_font_quad_vertices[6] = packed.u1
   gl_font_quad_vertices[7] = packed.v0

   gl_font_quad_vertices[8] = x1
   gl_font_quad_vertices[9] = y1
   gl_font_quad_vertices[10] = packed.u1
   gl_font_quad_vertices[11] = packed.v1

   gl_font_quad_vertices[12] = x0
   gl_font_quad_vertices[13] = y0
   gl_font_quad_vertices[14] = packed.u0
   gl_font_quad_vertices[15] = packed.v0

   gl_font_quad_vertices[16] = x1
   gl_font_quad_vertices[17] = y1
   gl_font_quad_vertices[18] = packed.u1
   gl_font_quad_vertices[19] = packed.v1

   gl_font_quad_vertices[20] = x0
   gl_font_quad_vertices[21] = y1
   gl_font_quad_vertices[22] = packed.u0
   gl_font_quad_vertices[23] = packed.v1
end

local function upload_font_page_texture(page, texture)
   local pixel_count = page.width * page.height
   local rgba = ffi.new("uint8_t[?]", pixel_count * 4)

   for i = 0, pixel_count - 1 do
      local alpha = page.buffer[i]
      local base = i * 4
      rgba[base] = 255
      rgba[base + 1] = 255
      rgba[base + 2] = 255
      rgba[base + 3] = alpha
   end

   local page_texture = texture
   if page_texture == nil or page_texture == ffi.NULL then
      page_texture = sdl3.CreateTexture(
         runtime_renderer,
         sdl3.PIXELFORMAT_RGBA32,
         sdl3.TEXTUREACCESS_STATIC,
         page.width,
         page.height
      )
      if page_texture == nil or page_texture == ffi.NULL then
         rig.raise("failed to create SDL texture: " .. get_error_string())
      end

      if not sdl3.SetTextureBlendMode(page_texture, sdl3.BLENDMODE_BLEND) then
         sdl3.DestroyTexture(page_texture)
         rig.raise("failed to set SDL texture blend mode: " .. get_error_string())
      end
   end

   if not sdl3.UpdateTexture(page_texture, nil, rgba, page.width * 4) then
      if texture == nil or texture == ffi.NULL then
         sdl3.DestroyTexture(page_texture)
      end
      rig.raise("failed to upload SDL texture: " .. get_error_string())
   end

   return page_texture
end

local function ensure_font_page_texture(text_renderer, page_index)
   local atlas = text_renderer.atlas
   local state = text_renderer._state
   local page = atlas.pages[page_index]
   if page == nil then
      rig.raise("font atlas has no page %d", page_index)
   end

   local revision = page.revision or 0
   if state.revisions[page_index] == revision and state.textures[page_index] ~= nil then
      return state.textures[page_index]
   end

   local texture = upload_font_page_texture(page, state.textures[page_index])
   state.textures[page_index] = texture
   state.revisions[page_index] = revision
   return texture
end

local sdl3_font_provider = {}
local sdl3_gl_font_provider = {}

function sdl3_font_provider.create_text_renderer(text_renderer)
   return {
      textures = {},
      revisions = {},
   }
end

function sdl3_font_provider.release_text_renderer(text_renderer)
   local state = text_renderer._state
   if state == nil then
      return
   end

   for i = 1, #state.textures do
      local texture = state.textures[i]
      if texture ~= nil and texture ~= ffi.NULL then
         sdl3.DestroyTexture(texture)
      end
      state.textures[i] = nil
      state.revisions[i] = nil
   end
end

local default_font_draw_color = color.WHITE

local function resolve_font_draw_color(value)
   if value == nil then
      return default_font_draw_color
   end
   if color.is(value) then
      return value
   end

   rig.raise("font draw color must be a color.Color if provided")
end

function sdl3_font_provider.draw_packed_glyph(text_renderer, packed, x, y, draw_color, scale)
   if packed.width <= 0 or packed.height <= 0 then
      return
   end

   local glyph_color = resolve_font_draw_color(draw_color)
   local texture = ensure_font_page_texture(text_renderer, packed.page_index)
   if not sdl3.SetTextureColorMod(texture, glyph_color.r, glyph_color.g, glyph_color.b) then
      rig.raise("failed to set texture color modulation: " .. get_error_string())
   end
   if not sdl3.SetTextureAlphaMod(texture, glyph_color.a) then
      rig.raise("failed to set texture alpha modulation: " .. get_error_string())
   end

   font_src_rect[0].x = packed.x
   font_src_rect[0].y = packed.y
   font_src_rect[0].w = packed.width
   font_src_rect[0].h = packed.height

   font_dst_rect[0].x = x
   font_dst_rect[0].y = y
   font_dst_rect[0].w = packed.width * scale
   font_dst_rect[0].h = packed.height * scale

   if not sdl3.RenderTexture(runtime_renderer, texture, font_src_rect, font_dst_rect) then
      rig.raise("failed to render SDL texture: " .. get_error_string())
   end
end

function sdl3_font_provider.draw_text_run(text_renderer, run, base_x, baseline_y, color_fn)
   for i = 1, #run.entries do
      local entry = run.entries[i]
      local draw_color = default_font_draw_color

      if color_fn ~= nil then
         draw_color = color_fn(i, entry, run)
      end

      sdl3_font_provider.draw_packed_glyph(
         text_renderer,
         entry.packed,
         base_x + entry.layout_x,
         baseline_y + entry.layout_y,
         resolve_font_draw_color(draw_color),
         1.0
      )
   end
end

function sdl3_gl_font_provider.create_text_renderer(text_renderer)
   return {
      textures = {},
      revisions = {},
   }
end

function sdl3_gl_font_provider.release_text_renderer(text_renderer)
   local state = text_renderer._state
   if state == nil then
      return
   end

   for i = 1, #state.textures do
      local texture = state.textures[i]
      if texture ~= nil then
         texture:release()
      end
      state.textures[i] = nil
      state.revisions[i] = nil
   end
end

function sdl3_gl_font_provider.draw_packed_glyph(text_renderer, packed, x, y, draw_color, scale)
   if packed.width <= 0 or packed.height <= 0 then
      return
   end

   local glyph_color = resolve_font_draw_color(draw_color)
   local backend_state = ensure_gl_font_backend_state()
   local gl = backend_state.gl
   local texture = ensure_gl_font_page_texture(text_renderer, packed.page_index)
   local window_width, window_height = get_window_size_in_pixels()
   if window_width <= 0 or window_height <= 0 then
      return
   end

   write_gl_font_quad_vertices(packed, x, y, scale)

   gl.Enable(gl.BLEND)
   gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
   backend_state.program:use()
   backend_state.program:set_uniform2f("u_view_size", window_width, window_height)
   backend_state.program:set_uniform4f(
      "u_color",
      glyph_color.r / 255.0,
      glyph_color.g / 255.0,
      glyph_color.b / 255.0,
      glyph_color.a / 255.0
   )
   texture:bind(0)
   backend_state.vao:bind()
   backend_state.vbo:set_data(gl_font_quad_vertices, gl.DYNAMIC_DRAW)
   gl.DrawArrays(gl.TRIANGLES, 0, 6)
end

function sdl3_gl_font_provider.draw_text_run(text_renderer, run, base_x, baseline_y, color_fn)
   for i = 1, #run.entries do
      local entry = run.entries[i]
      local draw_color = default_font_draw_color

      if color_fn ~= nil then
         draw_color = color_fn(i, entry, run)
      end

      sdl3_gl_font_provider.draw_packed_glyph(
         text_renderer,
         entry.packed,
         base_x + entry.layout_x,
         baseline_y + entry.layout_y,
         resolve_font_draw_color(draw_color),
         1.0
      )
   end
end

function M.upload_to_gpu_buffer(device, buffer, data)
   if device == nil then
      rig.raise("sdl3x.upload_to_gpu_buffer requires an SDL_GPUDevice*")
   end
   if buffer == nil then
      rig.raise("sdl3x.upload_to_gpu_buffer requires an SDL_GPUBuffer*")
   end
   if type(data) ~= "string" then
      rig.raise("sdl3x.upload_to_gpu_buffer requires data to be a string")
   end

   local transfer_info = ffi.new("SDL_GPUTransferBufferCreateInfo[1]")
   transfer_info[0].usage = sdl3.GPU_TRANSFERBUFFERUSAGE_UPLOAD
   transfer_info[0].size = #data
   transfer_info[0].props = 0

   local transfer_buffer = sdl3.CreateGPUTransferBuffer(device, transfer_info)
   if transfer_buffer == nil then
      rig.raise("failed to create GPU transfer buffer: " .. get_error_string())
   end

   local mapped = sdl3.MapGPUTransferBuffer(device, transfer_buffer, false)
   if mapped == nil then
      sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to map GPU transfer buffer: " .. get_error_string())
   end
   ffi.copy(mapped, data, #data)
   sdl3.UnmapGPUTransferBuffer(device, transfer_buffer)

   local command_buffer = sdl3.AcquireGPUCommandBuffer(device)
   if command_buffer == nil then
      sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to acquire GPU command buffer: " .. get_error_string())
   end

   local copy_pass = sdl3.BeginGPUCopyPass(command_buffer)
   local source = ffi.new("SDL_GPUTransferBufferLocation[1]")
   source[0].transfer_buffer = transfer_buffer
   source[0].offset = 0

   local destination = ffi.new("SDL_GPUBufferRegion[1]")
   destination[0].buffer = buffer
   destination[0].offset = 0
   destination[0].size = #data

   sdl3.UploadToGPUBuffer(copy_pass, source, destination, false)
   sdl3.EndGPUCopyPass(copy_pass)

   if not sdl3.SubmitGPUCommandBuffer(command_buffer) then
      sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to submit GPU upload command buffer: " .. get_error_string())
   end

   sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
end

function M.choose_depth_format(device)
   if device == nil then
      rig.raise("sdl3x.choose_depth_format requires an SDL_GPUDevice*")
   end

   local candidates = {
      sdl3.GPU_TEXTUREFORMAT_D32_FLOAT,
      sdl3.GPU_TEXTUREFORMAT_D24_UNORM,
      sdl3.GPU_TEXTUREFORMAT_D16_UNORM,
   }

   for _, format in ipairs(candidates) do
      if sdl3.GPUTextureSupportsFormat(
         device,
         format,
         sdl3.GPU_TEXTURETYPE_2D,
         sdl3.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET
      ) then
         return format
      end
   end

   rig.raise("no supported depth texture format found")
end

function M.create_depth_texture(device, width, height, format)
   if device == nil then
      rig.raise("sdl3x.create_depth_texture requires an SDL_GPUDevice*")
   end

   if format == nil then
      format = M.choose_depth_format(device)
   end

   local create_info = ffi.new("SDL_GPUTextureCreateInfo[1]")
   create_info[0].type = sdl3.GPU_TEXTURETYPE_2D
   create_info[0].format = format
   create_info[0].usage = sdl3.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET
   create_info[0].width = width
   create_info[0].height = height
   create_info[0].layer_count_or_depth = 1
   create_info[0].num_levels = 1
   create_info[0].sample_count = sdl3.GPU_SAMPLECOUNT_1
   create_info[0].props = 0

   local texture = sdl3.CreateGPUTexture(device, create_info)
   if texture == nil then
      rig.raise("failed to create GPU depth texture: " .. get_error_string())
   end

   return texture, format
end

local function color_component(value, default_value)
   local v = value
   if v == nil then
      v = default_value
   end
   v = tonumber(v) or default_value
   if v < 0 then
      v = 0
   elseif v > 1 then
      v = 1
   end
   return math.floor(v * 255 + 0.5)
end

function M.clear(r, g, b, a)
   local renderer_ptr = runtime_renderer

   if renderer_ptr == nil then
      rig.raise("sdl3x.clear requires an active SDL renderer")
   end

   local renderer = ffi.cast("SDL_Renderer *", renderer_ptr)
   local rr = color_component(r)
   local gg = color_component(g, 0)
   local bb = color_component(b, 0)
   local aa = color_component(a, 1)

   if not sdl3.SetRenderDrawColor(renderer, rr, gg, bb, aa) then
      rig.raise("failed to set draw color: " .. get_error_string())
   end
   if not sdl3.RenderClear(renderer) then
      error("failed to clear render target: " .. get_error_string())
   end
end

local function dispatch_keyboard_event(event, runtime)
   local key_name = sdl3.GetKeyName(event.key)
   local key = "Unknown"
   local mods = tonumber(event.mod) or 0
   local timestamp_ns = tonumber(event.timestamp) or 0

   if key_name ~= nil and key_name[0] ~= 0 then
      key = ffi.string(key_name)
   end

   runtime:handle_event("key", {
      type = "key",
      action = event.down and "down" or "up",
      key = key,
      code = tonumber(event.key),
      scancode = tonumber(event.scancode),
      ["repeat"] = event["repeat"] and true or false,
      timestamp_ns = timestamp_ns,
      timestamp_ms = math.floor(timestamp_ns / 1000000),
      mods = {
         shift = has_any_bits(mods, sdl3.KMOD_SHIFT),
         ctrl = has_any_bits(mods, sdl3.KMOD_CTRL),
         alt = has_any_bits(mods, sdl3.KMOD_ALT),
         super = has_any_bits(mods, sdl3.KMOD_GUI),
      },
   })
end

local function dispatch_mouse_motion_event(event, runtime)
   local timestamp_ns = tonumber(event.timestamp) or 0

   runtime:handle_event("mouse", {
      type = "mouse",
      action = "move",
      x = tonumber(event.x) or 0,
      y = tonumber(event.y) or 0,
      xrel = tonumber(event.xrel) or 0,
      yrel = tonumber(event.yrel) or 0,
      buttons = tonumber(event.state) or 0,
      timestamp_ns = timestamp_ns,
      timestamp_ms = math.floor(timestamp_ns / 1000000),
   })
end

local function dispatch_mouse_button_event(event, runtime)
   local timestamp_ns = tonumber(event.timestamp) or 0

   runtime:handle_event("mouse", {
      type = "mouse",
      action = event.down and "down" or "up",
      button = tonumber(event.button) or 0,
      clicks = tonumber(event.clicks) or 0,
      x = tonumber(event.x) or 0,
      y = tonumber(event.y) or 0,
      timestamp_ns = timestamp_ns,
      timestamp_ms = math.floor(timestamp_ns / 1000000),
   })
end

local function pump_events(runtime)
   if runtime_window == nil then
      error("an SDL window must be initialized before sdl3.pump_events")
   end

   local event = ffi.new("SDL_Event[1]")
   while sdl3.PollEvent(event) do
      local current = event[0]
      local event_type = tonumber(current.type) or 0

      if event_type == sdl3.EVENT_QUIT then
         return false
      end

      if event_type == sdl3.EVENT_KEY_DOWN or event_type == sdl3.EVENT_KEY_UP then
         dispatch_keyboard_event(current.key, runtime)
      elseif event_type == sdl3.EVENT_WINDOW_RESIZED then
         dispatch_resize_if_changed(
            runtime,
            "resized",
            tonumber(current.window.timestamp) or 0
         )
      elseif event_type == sdl3.EVENT_WINDOW_PIXEL_SIZE_CHANGED then
         dispatch_resize_if_changed(
            runtime,
            "pixel_size_changed",
            tonumber(current.window.timestamp) or 0
         )
      elseif event_type == sdl3.EVENT_MOUSE_MOTION then
         dispatch_mouse_motion_event(current.motion, runtime)
      elseif event_type == sdl3.EVENT_MOUSE_BUTTON_DOWN or event_type == sdl3.EVENT_MOUSE_BUTTON_UP then
         dispatch_mouse_button_event(current.button, runtime)
      end
   end

   return true
end

local function render_frame(render_fn)
   if type(render_fn) ~= "function" then
      rig.raise("sdl3x.render_frame requires a render function")
   end
   if runtime_renderer == nil then
      rig.raise("an SDL renderer must be initialized before sdl3x.render_frame")
   end

   render_fn()
   present()
end

local function render_gpu_frame(render_fn)
   if type(render_fn) ~= "function" then
      rig.raise("sdl3x.render_gpu_frame requires a render function")
   end
   if runtime_gpu_device == nil then
      rig.raise("an SDL GPU device must be initialized before sdl3x.render_gpu_frame")
   end
   if runtime_window == nil then
      rig.raise("an SDL window must be initialized before sdl3x.render_gpu_frame")
   end

   local command_buffer = sdl3.AcquireGPUCommandBuffer(runtime_gpu_device)
   if command_buffer == nil then
      rig.raise("failed to acquire GPU command buffer: " .. get_error_string())
   end

   local swapchain_texture_out = ffi.new("SDL_GPUTexture *[1]")
   local width_out = ffi.new("Uint32[1]")
   local height_out = ffi.new("Uint32[1]")
   if not sdl3.WaitAndAcquireGPUSwapchainTexture(
      command_buffer,
      runtime_window.ptr,
      swapchain_texture_out,
      width_out,
      height_out
   ) then
      rig.raise("failed to acquire swapchain texture: " .. get_error_string())
   end

   local swapchain_texture = swapchain_texture_out[0]
   if swapchain_texture ~= nil then
      render_fn(
         command_buffer,
         swapchain_texture,
         tonumber(width_out[0]) or 0,
         tonumber(height_out[0]) or 0
      )
   end

   if not sdl3.SubmitGPUCommandBuffer(command_buffer) then
      rig.raise("failed to submit GPU command buffer: " .. get_error_string())
   end

   return swapchain_texture ~= nil
end

local function render_gl_frame(render_fn)
   if type(render_fn) ~= "function" then
      rig.raise("sdl3_gl render requires a render function")
   end
   if runtime_window == nil or runtime_gl_context == nil then
      rig.raise("an SDL OpenGL context must be initialized before rendering")
   end

   render_fn()
   present_gl()
end

local function current_monotonic_seconds()
   local counter = tonumber(sdl3.GetPerformanceCounter())
   local frequency = tonumber(sdl3.GetPerformanceFrequency())
   if frequency == nil or frequency <= 0 then
      rig.raise("sdl3.GetPerformanceFrequency returned an invalid value")
   end
   return counter / frequency
end

local function current_time_seconds()
   local ticks = ffi.new("int64_t[1]")
   if not sdl3.GetCurrentTime(ticks) then
      rig.raise("sdl3.GetCurrentTime failed: " .. M.get_error())
   end
   return tonumber(ticks[0]) / 1000000000.0
end

local sdl3_time_service = {
   now = function()
      return current_time_seconds()
   end,
   monotonic = function()
      return current_monotonic_seconds()
   end,
}

local sdl3_gpu_mesh_service = {
   build_vertex_input = function(mesh)
      if type(mesh) ~= "table" then
         rig.raise("mesh.vertex_input provider expects a mesh table")
      end

      if mesh.layout == "position_color_f32" then
         return M.build_vertex_input_state {
            buffers = {
               {
                  slot = 0,
                  pitch = mesh.vertex_stride,
                  input_rate = "vertex",
                  attributes = {
                     {
                        location = 0,
                        format = "float3",
                        offset = mesh.attribute_offsets.position,
                     },
                     {
                        location = 1,
                        format = "float3",
                        offset = mesh.attribute_offsets.color,
                     },
                  },
               },
            },
         }
      end

      rig.raise("unsupported mesh layout '%s'", mesh.layout)
   end,
}

local shader_stage_service_sdl3_gpu = {
   create_stage = function(spec)
      local artifact = spec
      if artifact.artifact_kind == "source" then
         artifact = shader.compile(artifact)
      end
      if artifact.artifact_kind ~= "spirv" then
         error(
            ("shader.stage provider 'sdl3_gpu' requires a SPIR-V artifact, got '%s'"):format(
               tostring(artifact.artifact_kind)
            ))
      end

      local device = M.get_gpu_device()
      if device == nil then
         rig.raise("shader.create_stage requires an active SDL GPU device")
      end

      return M.create_gpu_shader(device, artifact, spec.props)
   end,
   destroy_stage = function(stage)
      local device = M.get_gpu_device()
      if device == nil then
         rig.raise("shader.destroy_stage requires an active SDL GPU device")
      end
      sdl3.ReleaseGPUShader(device, stage)
   end,
}

local shader_stage_service_sdl3_gl = {
   create_stage = function(spec)
      if spec.artifact_kind ~= "source" then
         rig.raise(
            "shader.stage provider 'sdl3_gl' requires a source artifact, got '%s'",
            tostring(spec.artifact_kind)
         )
      end
      if spec.language ~= "glsl" then
         rig.raise(
            "shader.stage provider 'sdl3_gl' currently supports only GLSL source, got '%s'",
            tostring(spec.language)
         )
      end

      return require("glx").Shader {
         stage = spec.stage,
         source = spec.source,
         source_name = spec.source_name,
      }
   end,
   destroy_stage = function(stage)
      stage:release()
   end,
}

local gl_resolver_service_sdl3_gl = {
   get_gl_proc_address = function(name)
      return M.get_gl_proc_address(name)
   end,
}

rig.register_service_provider("time", "sdl3", sdl3_time_service)
rig.register_service_provider("font.renderer", "sdl3", sdl3_font_provider)
rig.register_service_provider("font.renderer", "sdl3_gl", sdl3_gl_font_provider)
rig.register_service_provider("gl.resolver", "sdl3_gl", gl_resolver_service_sdl3_gl)
rig.register_service_provider("mesh.vertex_input", "sdl3_gpu", sdl3_gpu_mesh_service)
rig.register_service_provider("shader.stage", "sdl3_gpu", shader_stage_service_sdl3_gpu)
rig.register_service_provider("shader.stage", "sdl3_gl", shader_stage_service_sdl3_gl)

local function setup_scheduler(label)
   runtime_scheduler = sched.Scheduler(label)
   runtime_scheduler:set_handler("sched.sleep", function(scheduler, task, seconds)
      scheduler:sleep_until(task, current_monotonic_seconds() + seconds)
   end)
   runtime_scheduler:activate()
end

local function drain_scheduler()
   runtime_scheduler:wake_due_sleepers(current_monotonic_seconds())
   runtime_scheduler:drain()
end

local function shutdown_scheduler()
   runtime_scheduler:deactivate()
   runtime_scheduler = nil
end

local function require_render_callback(mode_options, mode_key, runtime)
   local callback = mode_options.render
   if callback == nil and runtime.app ~= nil then
      if type(runtime.app.invoke_render) == "function" then
         callback = function(...)
            return runtime.app:invoke_render(...)
         end
      elseif type(runtime.app.render) == "function" then
         callback = function(...)
            return runtime.app:render(...)
         end
      end
   end

   if type(callback) ~= "function" then
      rig.raise(
         "rig.run requires " .. mode_key .. ".render to be a function")
   end
   return callback
end

rig.register_runtime_driver("sdl3", {
   events = {
      "key",
      "mouse",
      "resize",
   },
   driver_phases = {
      "before_poll",
      "after_poll",
      "before_drain",
      "after_drain",
      "before_frame",
      "after_frame",
   },
   setup = function(options)
      local sdl3_options = get_driver_config(options, "sdl3")
      setup(sdl3_options)
      setup_scheduler("sdl3 scheduler")
   end,
   loop = function(options, runtime)
      local sdl3_options = get_driver_config(options, "sdl3")
      local on_render = require_render_callback(sdl3_options, "options.driver_config.sdl3", runtime)
      dispatch_resize_if_changed(runtime, "initial", 0)
      while true do
         runtime:run_hooks("before_poll", options)
         if pump_events(runtime) == false then
            break
         end
         runtime:run_hooks("after_poll", options)
         runtime:run_hooks("before_drain", options)
         drain_scheduler()
         runtime:run_hooks("after_drain", options)
         runtime:run_hooks("before_frame", options)
         render_frame(on_render)
         runtime:run_hooks("after_frame", options)
      end
   end,
   shutdown = function()
      shutdown_scheduler()
      shutdown()
   end,
})

rig.register_runtime_preset("sdl3", {
   driver = "sdl3",
   providers = {
      time = "sdl3",
      ["font.renderer"] = "sdl3",
   },
})

rig.register_runtime_driver("sdl3_gpu", {
   events = {
      "key",
      "mouse",
      "resize",
   },
   driver_phases = {
      "before_poll",
      "after_poll",
      "before_drain",
      "after_drain",
      "before_frame",
      "after_frame",
   },
   setup = function(options)
      local sdl3_options = get_driver_config(options, "sdl3_gpu")
      setup_gpu {
         init_flags = sdl3_options.init_flags,
         window_props = sdl3_options.window_props,
         shader_formats = sdl3_options.shader_formats,
         debug_mode = sdl3_options.debug_mode,
         backend_name = sdl3_options.backend_name,
      }
      setup_scheduler("sdl3_gpu scheduler")
   end,
   loop = function(options, runtime)
      local sdl3_options = get_driver_config(options, "sdl3_gpu")
      local on_render = require_render_callback(sdl3_options, "options.driver_config.sdl3_gpu", runtime)
      dispatch_resize_if_changed(runtime, "initial", 0)
      while true do
         runtime:run_hooks("before_poll", options)
         if pump_events(runtime) == false then
            break
         end
         runtime:run_hooks("after_poll", options)
         runtime:run_hooks("before_drain", options)
         drain_scheduler()
         runtime:run_hooks("after_drain", options)
         runtime:run_hooks("before_frame", options)
         render_gpu_frame(on_render)
         runtime:run_hooks("after_frame", options)
      end
   end,
   shutdown = function()
      shutdown_scheduler()
      shutdown()
   end,
})

rig.register_runtime_preset("sdl3_gpu", {
   driver = "sdl3_gpu",
   providers = {
      time = "sdl3",
      ["mesh.vertex_input"] = "sdl3_gpu",
      ["shader.stage"] = "sdl3_gpu",
   },
})

rig.register_runtime_driver("sdl3_gl", {
   events = {
      "key",
      "mouse",
      "resize",
   },
   driver_phases = {
      "before_poll",
      "after_poll",
      "before_drain",
      "after_drain",
      "before_frame",
      "after_frame",
   },
   setup = function(options)
      local sdl3_options = get_driver_config(options, "sdl3_gl")
      setup_gl(sdl3_options)
      setup_scheduler("sdl3_gl scheduler")
   end,
   loop = function(options, runtime)
      local sdl3_options = get_driver_config(options, "sdl3_gl")
      local on_render = require_render_callback(sdl3_options, "options.driver_config.sdl3_gl", runtime)
      dispatch_resize_if_changed(runtime, "initial", 0)
      while true do
         runtime:run_hooks("before_poll", options)
         if pump_events(runtime) == false then
            break
         end
         runtime:run_hooks("after_poll", options)
         runtime:run_hooks("before_drain", options)
         drain_scheduler()
         runtime:run_hooks("after_drain", options)
         runtime:run_hooks("before_frame", options)
         render_gl_frame(on_render)
         runtime:run_hooks("after_frame", options)
      end
   end,
   shutdown = function()
      shutdown_scheduler()
      shutdown()
   end,
})

rig.register_runtime_preset("sdl3_gl", {
   driver = "sdl3_gl",
   providers = {
      time = "sdl3",
      ["font.renderer"] = "sdl3_gl",
      ["gl.resolver"] = "sdl3_gl",
      ["shader.stage"] = "sdl3_gl",
   },
})

local module_config_schema = schema.record({
   frame_profiler = schema.one_of({
      schema.boolean(),
      schema.table(),
   }, "a boolean or table"):optional(),
   fullscreen = schema.boolean():optional(),
   vsync = schema.boolean():optional(),
})

local function get_module_config(runtime_options)
   return rig.get_module_config(
      runtime_options,
      "sdl3x",
      module_config_schema,
      "sdl3x module configuration"
   )
end

local function create_frame_profiler(spec)
   if spec == nil or spec == false then
      return nil
   end
   if spec == true then
      return profiler.FrameProfiler()
   end
   return profiler.FrameProfiler(spec)
end

local function init_common_state(self, runtime_options, scope_label)
   local config = get_module_config(runtime_options or {})

   self.window_width = 0
   self.window_height = 0
   self.pixel_width = 0
   self.pixel_height = 0
   self.fullscreen_enabled = config.fullscreen == true
   self.vsync_enabled = config.vsync ~= false
   self.frame_profiler = create_frame_profiler(config.frame_profiler)
   self.frame_profiler_enabled = self.frame_profiler ~= nil
   self.font_faces = {}
   self.owned_resources = rig.ResourceScope(self, scope_label)
   self._sdl3x_module_config = config
end

local function release_common_state(self)
   if self.owned_resources ~= nil then
      self.owned_resources:release()
      self.owned_resources = nil
   end

   self.font_faces = {}
   self.frame_profiler = nil
   self.frame_profiler_enabled = false
end

local function apply_runtime_toggles(self)
   local config = self._sdl3x_module_config or {}

   if config.vsync ~= nil then
      self:set_vsync(config.vsync)
   end
   if config.fullscreen ~= nil then
      self:set_fullscreen(config.fullscreen)
   end
end

local function before_frame_common(self)
   if self.frame_profiler ~= nil and self.frame_profiler_enabled then
      self.frame_profiler:begin_frame()
   end
end

local function after_frame_common(self)
   if self.frame_profiler ~= nil and self.frame_profiler_enabled then
      self.frame_profiler:end_frame()
   end
end

local function invoke_render_common(self, ...)
   if type(self.render) ~= "function" then
      return
   end

   if self.frame_profiler ~= nil and self.frame_profiler_enabled then
      self.frame_profiler:begin_cpu()
      local ok, result_or_err = pcall(self.render, self, ...)
      self.frame_profiler:end_cpu()
      if not ok then
         rig.raise(result_or_err)
      end
      return result_or_err
   end

   return self:render(...)
end

local function set_vsync_common(self, enabled)
   if type(enabled) ~= "boolean" then
      rig.raise("sdl3x.App:set_vsync expects enabled to be a boolean")
   end

   local renderer = M.get_renderer()
   if renderer ~= nil then
      local interval = enabled and 1 or 0
      if not sdl3.SetRenderVSync(renderer, interval) then
         rig.raise("failed to set renderer vsync: " .. M.get_error())
      end
      self.vsync_enabled = enabled
      return enabled
   end

   if M.get_gl_context() ~= nil then
      local interval = enabled and 1 or 0
      if not sdl3.GL_SetSwapInterval(interval) then
         rig.raise("failed to set OpenGL swap interval: " .. M.get_error())
      end
      self.vsync_enabled = enabled
      return enabled
   end

   rig.raise("sdl3x.App:set_vsync is not supported by the active SDL runtime")
end

local function toggle_vsync_common(self)
   return self:set_vsync(not self.vsync_enabled)
end

local function set_fullscreen_common(self, enabled)
   if type(enabled) ~= "boolean" then
      rig.raise("sdl3x.App:set_fullscreen expects enabled to be a boolean")
   end

   local window = M.get_window()
   if window == nil then
      rig.raise("sdl3 runtime did not provide a window")
   end
   window:set_fullscreen(enabled)
   window:sync()

   self.fullscreen_enabled = enabled
   return enabled
end

local function toggle_fullscreen_common(self)
   return self:set_fullscreen(not self.fullscreen_enabled)
end

local function set_frame_profiler_enabled_common(self, enabled)
   if type(enabled) ~= "boolean" then
      rig.raise("sdl3x.App:set_frame_profiler_enabled expects enabled to be a boolean")
   end
   if self.frame_profiler == nil and enabled then
      self.frame_profiler = profiler.FrameProfiler()
   end
   self.frame_profiler_enabled = enabled and self.frame_profiler ~= nil
   return self.frame_profiler_enabled
end

local function toggle_frame_profiler_common(self)
   return self:set_frame_profiler_enabled(not self.frame_profiler_enabled)
end

local function own_common(self, resource, release_fn)
   if self.owned_resources == nil then
      rig.raise("sdl3x.App has already released its owned resources")
   end
   return self.owned_resources:adopt(resource, release_fn)
end

local function replace_owned_common(self, key, resource, release_fn)
   if self.owned_resources == nil then
      rig.raise("sdl3x.App has already released its owned resources")
   end
   return self.owned_resources:replace(key, resource, release_fn)
end

local function create_owned_scope_common(self, label)
   local scope = rig.ResourceScope(self, label or "sdl3x owned scope")
   return self:own(scope, function(_, owned_scope)
      owned_scope:release()
   end)
end

local function release_owned_resources_common(self)
   if self.owned_resources == nil then
      return
   end
   self.owned_resources:release()
   self.owned_resources = nil
   self.font_faces = {}
end

local function load_font_face_common(self, name, path, face_index)
   if type(name) ~= "string" or name == "" then
      rig.raise("sdl3x.App:load_font_face expects name to be a non-empty string")
   end

   local face = font.load_face(path, face_index)
   self.font_faces[name] = self:replace_owned(
      "font_face:" .. name,
      face,
      function(_, resource)
         resource:release()
      end
   )
   return self.font_faces[name]
end

local function get_font_face_common(self, name)
   if type(name) ~= "string" or name == "" then
      rig.raise("sdl3x.App:get_font_face expects name to be a non-empty string")
   end
   return self.font_faces[name]
end

local function on_resize_common(self, resize_info)
   self.window_width = resize_info.width or 0
   self.window_height = resize_info.height or 0
   self.pixel_width = resize_info.pixel_width or 0
   self.pixel_height = resize_info.pixel_height or 0
end

local App = rig.Class(rig.App)
local SceneApp = rig.Class(animator.App)

M.App = App
M.SceneApp = SceneApp

function App:init(options)
   init_common_state(self, options or {}, "sdl3x app resources")
end

function App:after_setup()
   apply_runtime_toggles(self)
end

function App:before_shutdown()
   release_common_state(self)
end

function SceneApp:init(options)
   animator.App.init(self, options)
   init_common_state(self, options or {}, "sdl3x scene app resources")
end

function SceneApp:after_setup()
   animator.App.after_setup(self)
   apply_runtime_toggles(self)
end

function SceneApp:before_shutdown()
   local ok, err = pcall(function()
      animator.App.before_shutdown(self)
   end)
   release_common_state(self)
   if not ok then
      rig.raise(err)
   end
end

App.before_frame = before_frame_common
App.after_frame = after_frame_common
App.invoke_render = invoke_render_common
App.set_vsync = set_vsync_common
App.toggle_vsync = toggle_vsync_common
App.set_fullscreen = set_fullscreen_common
App.toggle_fullscreen = toggle_fullscreen_common
App.set_frame_profiler_enabled = set_frame_profiler_enabled_common
App.toggle_frame_profiler = toggle_frame_profiler_common
App.own = own_common
App.replace_owned = replace_owned_common
App.create_owned_scope = create_owned_scope_common
App.release_owned_resources = release_owned_resources_common
App.load_font_face = load_font_face_common
App.get_font_face = get_font_face_common
App.on_resize = on_resize_common

SceneApp.before_frame = before_frame_common
SceneApp.after_frame = after_frame_common
SceneApp.invoke_render = invoke_render_common
SceneApp.set_vsync = set_vsync_common
SceneApp.toggle_vsync = toggle_vsync_common
SceneApp.set_fullscreen = set_fullscreen_common
SceneApp.toggle_fullscreen = toggle_fullscreen_common
SceneApp.set_frame_profiler_enabled = set_frame_profiler_enabled_common
SceneApp.toggle_frame_profiler = toggle_frame_profiler_common
SceneApp.own = own_common
SceneApp.replace_owned = replace_owned_common
SceneApp.create_owned_scope = create_owned_scope_common
SceneApp.release_owned_resources = release_owned_resources_common
SceneApp.load_font_face = load_font_face_common
SceneApp.get_font_face = get_font_face_common
SceneApp.on_resize = on_resize_common

return M
