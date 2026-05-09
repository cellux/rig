local M = ... or {}
local ffi = ffi

ffi.cdef[[
typedef uint32_t SpvId;
typedef int SpvExecutionModel;
typedef int SpvExecutionMode;
typedef int SpvDecoration;

typedef struct spvc_context_s *spvc_context;
typedef struct spvc_parsed_ir_s *spvc_parsed_ir;
typedef struct spvc_compiler_s *spvc_compiler;
typedef struct spvc_resources_s *spvc_resources;
typedef const struct spvc_type_s *spvc_type;
typedef const struct spvc_set_s *spvc_set;
typedef SpvId spvc_type_id;
typedef SpvId spvc_variable_id;
typedef unsigned char spvc_bool;

typedef struct spvc_reflected_resource {
   spvc_variable_id id;
   spvc_type_id base_type_id;
   spvc_type_id type_id;
   const char *name;
} spvc_reflected_resource;

typedef enum spvc_result {
   SPVC_SUCCESS = 0,
   SPVC_ERROR_INVALID_SPIRV = -1,
   SPVC_ERROR_UNSUPPORTED_SPIRV = -2,
   SPVC_ERROR_OUT_OF_MEMORY = -3,
   SPVC_ERROR_INVALID_ARGUMENT = -4
} spvc_result;

typedef enum spvc_capture_mode {
   SPVC_CAPTURE_MODE_COPY = 0,
   SPVC_CAPTURE_MODE_TAKE_OWNERSHIP = 1
} spvc_capture_mode;

typedef enum spvc_backend {
   SPVC_BACKEND_NONE = 0,
   SPVC_BACKEND_GLSL = 1,
   SPVC_BACKEND_HLSL = 2,
   SPVC_BACKEND_MSL = 3,
   SPVC_BACKEND_CPP = 4,
   SPVC_BACKEND_JSON = 5
} spvc_backend;

typedef enum spvc_resource_type {
   SPVC_RESOURCE_TYPE_UNKNOWN = 0,
   SPVC_RESOURCE_TYPE_UNIFORM_BUFFER = 1,
   SPVC_RESOURCE_TYPE_STORAGE_BUFFER = 2,
   SPVC_RESOURCE_TYPE_STAGE_INPUT = 3,
   SPVC_RESOURCE_TYPE_STAGE_OUTPUT = 4,
   SPVC_RESOURCE_TYPE_SUBPASS_INPUT = 5,
   SPVC_RESOURCE_TYPE_STORAGE_IMAGE = 6,
   SPVC_RESOURCE_TYPE_SAMPLED_IMAGE = 7,
   SPVC_RESOURCE_TYPE_ATOMIC_COUNTER = 8,
   SPVC_RESOURCE_TYPE_PUSH_CONSTANT = 9,
   SPVC_RESOURCE_TYPE_SEPARATE_IMAGE = 10,
   SPVC_RESOURCE_TYPE_SEPARATE_SAMPLERS = 11
} spvc_resource_type;

typedef enum spvc_basetype {
   SPVC_BASETYPE_UNKNOWN = 0,
   SPVC_BASETYPE_VOID = 1,
   SPVC_BASETYPE_BOOLEAN = 2,
   SPVC_BASETYPE_INT8 = 3,
   SPVC_BASETYPE_UINT8 = 4,
   SPVC_BASETYPE_INT16 = 5,
   SPVC_BASETYPE_UINT16 = 6,
   SPVC_BASETYPE_INT32 = 7,
   SPVC_BASETYPE_UINT32 = 8,
   SPVC_BASETYPE_INT64 = 9,
   SPVC_BASETYPE_UINT64 = 10,
   SPVC_BASETYPE_ATOMIC_COUNTER = 11,
   SPVC_BASETYPE_FP16 = 12,
   SPVC_BASETYPE_FP32 = 13,
   SPVC_BASETYPE_FP64 = 14,
   SPVC_BASETYPE_STRUCT = 15,
   SPVC_BASETYPE_IMAGE = 16,
   SPVC_BASETYPE_SAMPLED_IMAGE = 17,
   SPVC_BASETYPE_SAMPLER = 18
} spvc_basetype;

void spvc_get_version(unsigned *major, unsigned *minor, unsigned *patch);
const char *spvc_get_commit_revision_and_timestamp(void);
spvc_result spvc_context_create(spvc_context *context);
void spvc_context_destroy(spvc_context context);
const char *spvc_context_get_last_error_string(spvc_context context);
spvc_result spvc_context_parse_spirv(
   spvc_context context,
   const SpvId *spirv,
   size_t word_count,
   spvc_parsed_ir *parsed_ir
);
spvc_result spvc_context_create_compiler(
   spvc_context context,
   spvc_backend backend,
   spvc_parsed_ir parsed_ir,
   spvc_capture_mode mode,
   spvc_compiler *compiler
);
spvc_result spvc_compiler_get_active_interface_variables(
   spvc_compiler compiler,
   spvc_set *set
);
spvc_result spvc_compiler_create_shader_resources_for_active_variables(
   spvc_compiler compiler,
   spvc_resources *resources,
   spvc_set active
);
spvc_result spvc_resources_get_resource_list_for_type(
   spvc_resources resources,
   spvc_resource_type type,
   const spvc_reflected_resource **resource_list,
   size_t *resource_size
);
spvc_bool spvc_compiler_has_decoration(
   spvc_compiler compiler,
   SpvId id,
   SpvDecoration decoration
);
unsigned spvc_compiler_get_decoration(
   spvc_compiler compiler,
   SpvId id,
   SpvDecoration decoration
);
SpvExecutionModel spvc_compiler_get_execution_model(spvc_compiler compiler);
unsigned spvc_compiler_get_execution_mode_argument_by_index(
   spvc_compiler compiler,
   SpvExecutionMode mode,
   unsigned index
);
spvc_type spvc_compiler_get_type_handle(spvc_compiler compiler, spvc_type_id id);
spvc_basetype spvc_type_get_basetype(spvc_type type);
unsigned spvc_type_get_bit_width(spvc_type type);
unsigned spvc_type_get_vector_size(spvc_type type);
unsigned spvc_type_get_columns(spvc_type type);
unsigned spvc_type_get_num_array_dimensions(spvc_type type);
spvc_bool spvc_type_array_dimension_is_literal(spvc_type type, unsigned dimension);
SpvId spvc_type_get_array_dimension(spvc_type type, unsigned dimension);
]]

M.EXECUTION_MODEL_VERTEX = 0
M.EXECUTION_MODEL_FRAGMENT = 4
M.EXECUTION_MODEL_COMPUTE = 5

M.DECORATION_LOCATION = 30
M.DECORATION_BINDING = 33
M.DECORATION_DESCRIPTOR_SET = 34

M.EXECUTION_MODE_LOCAL_SIZE = 17

M.RESOURCE_TYPE_UNIFORM_BUFFER = 1
M.RESOURCE_TYPE_STORAGE_BUFFER = 2
M.RESOURCE_TYPE_STAGE_INPUT = 3
M.RESOURCE_TYPE_STAGE_OUTPUT = 4
M.RESOURCE_TYPE_STORAGE_IMAGE = 6
M.RESOURCE_TYPE_SAMPLED_IMAGE = 7
M.RESOURCE_TYPE_SEPARATE_IMAGE = 10
M.RESOURCE_TYPE_SEPARATE_SAMPLERS = 11

local spirvcross_state = {
   library = nil,
   error = nil,
}

local EXECUTION_MODEL_NAMES = {
   [M.EXECUTION_MODEL_VERTEX] = "vertex",
   [M.EXECUTION_MODEL_FRAGMENT] = "fragment",
   [M.EXECUTION_MODEL_COMPUTE] = "compute",
}

local BASETYPE_NAMES = {
   [0] = "unknown",
   [1] = "void",
   [2] = "boolean",
   [3] = "int8",
   [4] = "uint8",
   [5] = "int16",
   [6] = "uint16",
   [7] = "int32",
   [8] = "uint32",
   [9] = "int64",
   [10] = "uint64",
   [11] = "atomic_counter",
   [12] = "float16",
   [13] = "float32",
   [14] = "float64",
   [15] = "struct",
   [16] = "image",
   [17] = "sampled_image",
   [18] = "sampler",
}

local function load_library()
   if spirvcross_state.library ~= nil then
      return spirvcross_state.library
   end
   if spirvcross_state.error ~= nil then
      error(spirvcross_state.error)
   end

   local candidates = {
      "spirv-cross-c-shared",
      "libspirv-cross-c-shared.so.0",
      "libspirv-cross-c-shared.so",
      "spirv-cross-c-shared.dll",
      "libspirv-cross-c-shared.dylib",
   }
   local failures = {}

   for _, name in ipairs(candidates) do
      local ok, lib = pcall(ffi.load, name)
      if ok then
         spirvcross_state.library = lib
         return lib
      end
      failures[#failures + 1] = tostring(lib)
   end

   spirvcross_state.error = "failed to load spirv-cross-c-shared library: "
      .. table.concat(failures, "; ")
   error(spirvcross_state.error)
end

local function result_ok(result)
   return tonumber(result) >= 0
end

local function normalize_bytecode(input)
   if type(input) == "table" then
      input = input.bytecode
   end

   if type(input) ~= "string" then
      error("SPIR-V bytecode must be a string or a table with a bytecode field")
   end
   if #input == 0 then
      error("SPIR-V bytecode must not be empty")
   end
   if (#input % 4) ~= 0 then
      error("SPIR-V bytecode length must be divisible by 4")
   end

   return input
end

local function context_error(lib, context, fallback)
   if context ~= nil and context ~= ffi.NULL then
      local error_ptr = lib.spvc_context_get_last_error_string(context)
      if error_ptr ~= nil and error_ptr[0] ~= 0 then
         return ffi.string(error_ptr)
      end
   end
   return fallback or "unknown SPIRV-Cross error"
end

local function describe_type(lib, compiler, type_id)
   local handle = lib.spvc_compiler_get_type_handle(compiler, type_id)
   local base_type = tonumber(lib.spvc_type_get_basetype(handle))
   local array_rank = tonumber(lib.spvc_type_get_num_array_dimensions(handle))
   local array_dimensions = {}

   for i = 0, array_rank - 1 do
      local literal = lib.spvc_type_array_dimension_is_literal(handle, i) ~= 0
      array_dimensions[#array_dimensions + 1] = {
         literal = literal,
         value = tonumber(lib.spvc_type_get_array_dimension(handle, i)),
      }
   end

   return {
      id = tonumber(type_id),
      base_type = BASETYPE_NAMES[base_type] or ("basetype_" .. tostring(base_type)),
      base_type_id = base_type,
      bit_width = tonumber(lib.spvc_type_get_bit_width(handle)),
      vector_size = tonumber(lib.spvc_type_get_vector_size(handle)),
      columns = tonumber(lib.spvc_type_get_columns(handle)),
      array_dimensions = array_dimensions,
   }
end

local function maybe_get_decoration(lib, compiler, id, decoration)
   if lib.spvc_compiler_has_decoration(compiler, id, decoration) == 0 then
      return nil
   end
   return tonumber(lib.spvc_compiler_get_decoration(compiler, id, decoration))
end

local function copy_resource_list(lib, compiler, resources, resource_type)
   local resource_ptr_out = ffi.new("const spvc_reflected_resource *[1]")
   local count_out = ffi.new("size_t[1]")
   local result = lib.spvc_resources_get_resource_list_for_type(
      resources,
      resource_type,
      resource_ptr_out,
      count_out
   )

   if not result_ok(result) then
      return nil, context_error(
         lib,
         nil,
         ("spvc_resources_get_resource_list_for_type(%d) failed: %d"):format(
            resource_type,
            tonumber(result)
         )
      )
   end

   local count = tonumber(count_out[0]) or 0
   local resource_ptr = resource_ptr_out[0]
   local list = {}

   for i = 0, count - 1 do
      local resource = resource_ptr[i]
      list[#list + 1] = {
         id = tonumber(resource.id),
         name = (
            resource.name ~= nil and resource.name ~= ffi.NULL
         ) and ffi.string(resource.name) or "",
         set = maybe_get_decoration(
            lib,
            compiler,
            resource.id,
            M.DECORATION_DESCRIPTOR_SET
         ),
         binding = maybe_get_decoration(
            lib,
            compiler,
            resource.id,
            M.DECORATION_BINDING
         ),
         location = maybe_get_decoration(
            lib,
            compiler,
            resource.id,
            M.DECORATION_LOCATION
         ),
         base_type = describe_type(lib, compiler, resource.base_type_id),
         type = describe_type(lib, compiler, resource.type_id),
      }
   end

   return list
end

local function classify_compute_storage(resources, kind)
   local readonly_count = 0
   local readwrite_count = 0

   for _, resource in ipairs(resources) do
      if resource.set == nil or resource.binding == nil then
         return nil, ("%s resources must have descriptor set and binding"):format(kind)
      end
      if resource.set == 0 then
         readonly_count = readonly_count + 1
      elseif resource.set == 1 then
         readwrite_count = readwrite_count + 1
      else
         return nil, (
            "%s descriptor set must be 0 (readonly) or 1 (readwrite), got %d"
         ):format(kind, resource.set)
      end
   end

   return {
      readonly = readonly_count,
      readwrite = readwrite_count,
   }
end

local function build_resource_summary(reflection)
   local sampled_images = reflection.resources.sampled_images
   local separate_samplers = reflection.resources.separate_samplers
   local separate_images = reflection.resources.separate_images
   local storage_images = reflection.resources.storage_images
   local storage_buffers = reflection.resources.storage_buffers
   local uniform_buffers = reflection.resources.uniform_buffers

   local num_samplers = #sampled_images
   local num_separate_samplers = #separate_samplers
   if num_samplers == 0 then
      num_samplers = num_separate_samplers
   end

   local num_storage_textures = #storage_images
      + math.max(#separate_images - num_separate_samplers, 0)

   local summary = {
      num_samplers = num_samplers,
      num_storage_textures = num_storage_textures,
      num_storage_buffers = #storage_buffers,
      num_uniform_buffers = #uniform_buffers,
   }

   if reflection.stage == "compute" then
      local storage_texture_resources = {}
      for i = 1, #storage_images do
         storage_texture_resources[#storage_texture_resources + 1] = storage_images[i]
      end
      for i = num_separate_samplers + 1, #separate_images do
         storage_texture_resources[#storage_texture_resources + 1] = separate_images[i]
      end

      local storage_texture_counts, err = classify_compute_storage(
         storage_texture_resources,
         "compute storage texture"
      )
      if storage_texture_counts == nil then
         return nil, err
      end

      local storage_buffer_counts, buffer_err = classify_compute_storage(
         storage_buffers,
         "compute storage buffer"
      )
      if storage_buffer_counts == nil then
         return nil, buffer_err
      end

      reflection.compute_resource_info = {
         num_samplers = num_samplers,
         num_readonly_storage_textures = storage_texture_counts.readonly,
         num_readwrite_storage_textures = storage_texture_counts.readwrite,
         num_readonly_storage_buffers = storage_buffer_counts.readonly,
         num_readwrite_storage_buffers = storage_buffer_counts.readwrite,
         num_uniform_buffers = #uniform_buffers,
         threadcount_x = reflection.threadcount_x,
         threadcount_y = reflection.threadcount_y,
         threadcount_z = reflection.threadcount_z,
      }
   end

   reflection.resource_info = summary
   return reflection
end

function M.reflect_spirv(input)
   local bytecode = normalize_bytecode(input)
   local lib = load_library()
   local context_out = ffi.new("spvc_context[1]")
   local result = lib.spvc_context_create(context_out)
   if not result_ok(result) then
      return nil, ("spvc_context_create failed: %d"):format(tonumber(result))
   end

   local context = context_out[0]
   local ok, reflection_or_err, maybe_err = pcall(function()
      local word_count = #bytecode / 4
      local bytecode_buffer = ffi.new("uint8_t[?]", #bytecode)
      ffi.copy(bytecode_buffer, bytecode, #bytecode)

      local parsed_ir_out = ffi.new("spvc_parsed_ir[1]")
      result = lib.spvc_context_parse_spirv(
         context,
         ffi.cast("const SpvId *", bytecode_buffer),
         word_count,
         parsed_ir_out
      )
      if not result_ok(result) then
         return nil, context_error(
            lib,
            context,
            ("spvc_context_parse_spirv failed: %d"):format(tonumber(result))
         )
      end

      local compiler_out = ffi.new("spvc_compiler[1]")
      result = lib.spvc_context_create_compiler(
         context,
         0,
         parsed_ir_out[0],
         1,
         compiler_out
      )
      if not result_ok(result) then
         return nil, context_error(
            lib,
            context,
            ("spvc_context_create_compiler failed: %d"):format(tonumber(result))
         )
      end

      local compiler = compiler_out[0]
      local active_out = ffi.new("spvc_set[1]")
      result = lib.spvc_compiler_get_active_interface_variables(compiler, active_out)
      if not result_ok(result) then
         return nil, context_error(
            lib,
            context,
            ("spvc_compiler_get_active_interface_variables failed: %d"):format(
               tonumber(result)
            )
         )
      end

      local resources_out = ffi.new("spvc_resources[1]")
      result = lib.spvc_compiler_create_shader_resources_for_active_variables(
         compiler,
         resources_out,
         active_out[0]
      )
      if not result_ok(result) then
         return nil, context_error(
            lib,
            context,
            ("spvc_compiler_create_shader_resources_for_active_variables failed: %d"):format(
               tonumber(result)
            )
         )
      end

      local resources = resources_out[0]
      local execution_model = tonumber(lib.spvc_compiler_get_execution_model(compiler))
      local stage = EXECUTION_MODEL_NAMES[execution_model]
      if stage == nil then
         return nil, ("unsupported SPIR-V execution model: %d"):format(execution_model)
      end

      local sampled_images, err = copy_resource_list(
         lib,
         compiler,
         resources,
         M.RESOURCE_TYPE_SAMPLED_IMAGE
      )
      if sampled_images == nil then
         return nil, err
      end

      local separate_samplers, sampler_err = copy_resource_list(
         lib,
         compiler,
         resources,
         M.RESOURCE_TYPE_SEPARATE_SAMPLERS
      )
      if separate_samplers == nil then
         return nil, sampler_err
      end

      local separate_images, separate_image_err = copy_resource_list(
         lib,
         compiler,
         resources,
         M.RESOURCE_TYPE_SEPARATE_IMAGE
      )
      if separate_images == nil then
         return nil, separate_image_err
      end

      local storage_images, storage_image_err = copy_resource_list(
         lib,
         compiler,
         resources,
         M.RESOURCE_TYPE_STORAGE_IMAGE
      )
      if storage_images == nil then
         return nil, storage_image_err
      end

      local storage_buffers, storage_buffer_err = copy_resource_list(
         lib,
         compiler,
         resources,
         M.RESOURCE_TYPE_STORAGE_BUFFER
      )
      if storage_buffers == nil then
         return nil, storage_buffer_err
      end

      local uniform_buffers, uniform_buffer_err = copy_resource_list(
         lib,
         compiler,
         resources,
         M.RESOURCE_TYPE_UNIFORM_BUFFER
      )
      if uniform_buffers == nil then
         return nil, uniform_buffer_err
      end

      local inputs, input_err = copy_resource_list(
         lib,
         compiler,
         resources,
         M.RESOURCE_TYPE_STAGE_INPUT
      )
      if inputs == nil then
         return nil, input_err
      end

      local outputs, output_err = copy_resource_list(
         lib,
         compiler,
         resources,
         M.RESOURCE_TYPE_STAGE_OUTPUT
      )
      if outputs == nil then
         return nil, output_err
      end

      local reflection = {
         bytecode_size = #bytecode,
         execution_model = execution_model,
         stage = stage,
         inputs = inputs,
         outputs = outputs,
         resources = {
            sampled_images = sampled_images,
            separate_samplers = separate_samplers,
            separate_images = separate_images,
            storage_images = storage_images,
            storage_buffers = storage_buffers,
            uniform_buffers = uniform_buffers,
         },
         threadcount_x = tonumber(lib.spvc_compiler_get_execution_mode_argument_by_index(
            compiler,
            M.EXECUTION_MODE_LOCAL_SIZE,
            0
         )),
         threadcount_y = tonumber(lib.spvc_compiler_get_execution_mode_argument_by_index(
            compiler,
            M.EXECUTION_MODE_LOCAL_SIZE,
            1
         )),
         threadcount_z = tonumber(lib.spvc_compiler_get_execution_mode_argument_by_index(
            compiler,
            M.EXECUTION_MODE_LOCAL_SIZE,
            2
         )),
      }

      return build_resource_summary(reflection)
   end)

   lib.spvc_context_destroy(context)

   if not ok then
      error(reflection_or_err)
   end

   if reflection_or_err == nil then
      return nil, maybe_err
   end

   return reflection_or_err
end

function M.reflect_graphics_spirv(input)
   local reflection, err = M.reflect_spirv(input)
   if reflection == nil then
      return nil, err
   end
   if reflection.stage == "compute" then
      return nil, "compute shader passed to reflect_graphics_spirv"
   end

   return {
      stage = reflection.stage,
      execution_model = reflection.execution_model,
      resource_info = reflection.resource_info,
      inputs = reflection.inputs,
      outputs = reflection.outputs,
      resources = reflection.resources,
   }
end

function M.reflect_compute_spirv(input)
   local reflection, err = M.reflect_spirv(input)
   if reflection == nil then
      return nil, err
   end
   if reflection.stage ~= "compute" then
      return nil, "non-compute shader passed to reflect_compute_spirv"
   end

   return {
      stage = reflection.stage,
      execution_model = reflection.execution_model,
      resource_info = reflection.resource_info,
      compute_resource_info = reflection.compute_resource_info,
      resources = reflection.resources,
   }
end

function M.get_version()
   local lib = load_library()
   local major = ffi.new("unsigned[1]")
   local minor = ffi.new("unsigned[1]")
   local patch = ffi.new("unsigned[1]")
   lib.spvc_get_version(major, minor, patch)
   return {
      major = tonumber(major[0]),
      minor = tonumber(minor[0]),
      patch = tonumber(patch[0]),
   }
end

function M.get_commit_revision_and_timestamp()
   local ptr = load_library().spvc_get_commit_revision_and_timestamp()
   if ptr == nil or ptr == ffi.NULL then
      return nil
   end
   return ffi.string(ptr)
end

return M
