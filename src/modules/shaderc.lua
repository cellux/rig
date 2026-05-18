local M = ... or {}
local ffi = require("ffi")

ffi.cdef[[
typedef struct shaderc_compiler* shaderc_compiler_t;
typedef struct shaderc_compile_options* shaderc_compile_options_t;
typedef struct shaderc_compilation_result* shaderc_compilation_result_t;

typedef enum {
  shaderc_source_language_glsl,
  shaderc_source_language_hlsl,
} shaderc_source_language;

typedef enum {
  shaderc_vertex_shader,
  shaderc_fragment_shader,
  shaderc_compute_shader,
} shaderc_shader_kind;

typedef enum {
  shaderc_profile_none,
  shaderc_profile_core,
  shaderc_profile_compatibility,
  shaderc_profile_es,
} shaderc_profile;

typedef enum {
  shaderc_optimization_level_zero,
  shaderc_optimization_level_size,
  shaderc_optimization_level_performance,
} shaderc_optimization_level;

typedef enum {
  shaderc_target_env_vulkan,
  shaderc_target_env_opengl,
  shaderc_target_env_opengl_compat,
  shaderc_target_env_webgpu,
  shaderc_target_env_default = shaderc_target_env_vulkan
} shaderc_target_env;

typedef enum {
  shaderc_env_version_vulkan_1_0 = ((1u << 22)),
  shaderc_env_version_vulkan_1_1 = ((1u << 22) | (1 << 12)),
  shaderc_env_version_vulkan_1_2 = ((1u << 22) | (2 << 12)),
  shaderc_env_version_vulkan_1_3 = ((1u << 22) | (3 << 12)),
  shaderc_env_version_vulkan_1_4 = ((1u << 22) | (4 << 12)),
  shaderc_env_version_opengl_4_5 = 450,
  shaderc_env_version_webgpu,
} shaderc_env_version;

typedef enum {
  shaderc_spirv_version_1_0 = 0x010000u,
  shaderc_spirv_version_1_1 = 0x010100u,
  shaderc_spirv_version_1_2 = 0x010200u,
  shaderc_spirv_version_1_3 = 0x010300u,
  shaderc_spirv_version_1_4 = 0x010400u,
  shaderc_spirv_version_1_5 = 0x010500u,
  shaderc_spirv_version_1_6 = 0x010600u
} shaderc_spirv_version;

typedef enum {
  shaderc_compilation_status_success = 0,
  shaderc_compilation_status_invalid_stage = 1,
  shaderc_compilation_status_compilation_error = 2,
  shaderc_compilation_status_internal_error = 3,
  shaderc_compilation_status_null_result_object = 4,
  shaderc_compilation_status_invalid_assembly = 5,
  shaderc_compilation_status_validation_error = 6,
  shaderc_compilation_status_transformation_error = 7,
  shaderc_compilation_status_configuration_error = 8,
} shaderc_compilation_status;

shaderc_compiler_t shaderc_compiler_initialize(void);
void shaderc_compiler_release(shaderc_compiler_t compiler);
shaderc_compile_options_t shaderc_compile_options_initialize(void);
void shaderc_compile_options_release(shaderc_compile_options_t options);
void shaderc_compile_options_set_source_language(
   shaderc_compile_options_t options, shaderc_source_language lang
);
void shaderc_compile_options_set_generate_debug_info(
   shaderc_compile_options_t options
);
void shaderc_compile_options_set_optimization_level(
   shaderc_compile_options_t options, shaderc_optimization_level level
);
void shaderc_compile_options_set_forced_version_profile(
   shaderc_compile_options_t options, int version, shaderc_profile profile
);
void shaderc_compile_options_set_target_env(
   shaderc_compile_options_t options, shaderc_target_env target, uint32_t version
);
void shaderc_compile_options_set_target_spirv(
   shaderc_compile_options_t options, shaderc_spirv_version version
);
void shaderc_compile_options_set_preserve_bindings(
   shaderc_compile_options_t options, bool preserve_bindings
);
void shaderc_compile_options_set_auto_bind_uniforms(
   shaderc_compile_options_t options, bool auto_bind
);
void shaderc_compile_options_set_auto_map_locations(
   shaderc_compile_options_t options, bool auto_map
);
void shaderc_compile_options_add_macro_definition(
   shaderc_compile_options_t options,
   const char* name, size_t name_length,
   const char* value, size_t value_length
);
shaderc_compilation_result_t shaderc_compile_into_spv(
   const shaderc_compiler_t compiler,
   const char* source_text,
   size_t source_text_size,
   shaderc_shader_kind shader_kind,
   const char* input_file_name,
   const char* entry_point_name,
   const shaderc_compile_options_t additional_options
);
void shaderc_result_release(shaderc_compilation_result_t result);
size_t shaderc_result_get_length(const shaderc_compilation_result_t result);
size_t shaderc_result_get_num_warnings(const shaderc_compilation_result_t result);
size_t shaderc_result_get_num_errors(const shaderc_compilation_result_t result);
shaderc_compilation_status shaderc_result_get_compilation_status(
   const shaderc_compilation_result_t result
);
const char* shaderc_result_get_bytes(const shaderc_compilation_result_t result);
const char* shaderc_result_get_error_message(const shaderc_compilation_result_t result);
]]

M.SHADERSTAGE_VERTEX = "vertex"
M.SHADERSTAGE_FRAGMENT = "fragment"
M.SHADERSTAGE_COMPUTE = "compute"

local SHADER_KIND = {
   vertex = 0,
   fragment = 1,
   compute = 2,
}

local STATUS_NAMES = {
   [0] = "success",
   [1] = "invalid_stage",
   [2] = "compilation_error",
   [3] = "internal_error",
   [4] = "null_result_object",
   [5] = "invalid_assembly",
   [6] = "validation_error",
   [7] = "transformation_error",
   [8] = "configuration_error",
}

local library_state = {
   library = nil,
   error = nil,
}

local function load_library()
   if library_state.library ~= nil then
      return library_state.library
   end
   if library_state.error ~= nil then
      error(library_state.error)
   end

   local candidates = {
      "shaderc_shared",
      "libshaderc_shared.so.1",
      "libshaderc_shared.so",
      "shaderc_shared.dll",
      "libshaderc_shared.dylib",
   }
   local failures = {}

   for _, name in ipairs(candidates) do
      local ok, lib = pcall(ffi.load, name)
      if ok then
         library_state.library = lib
         return lib
      end
      table.insert(failures, tostring(lib))
   end

   library_state.error = "failed to load shaderc library: "
      .. table.concat(failures, "; ")
   error(library_state.error)
end

local function status_name(status)
   return STATUS_NAMES[tonumber(status)] or tostring(tonumber(status))
end

local function compilation_message(lib, result)
   local message_ptr = lib.shaderc_result_get_error_message(result)
   if message_ptr == nil or message_ptr == ffi.NULL then
      return ""
   end
   return ffi.string(message_ptr)
end

local function apply_macro_definitions(lib, compile_options, macros)
   if macros == nil then
      return
   end
   if type(macros) ~= "table" then
      error("shaderc macro_definitions must be a table", 0)
   end

   for name, value in pairs(macros) do
      if type(name) ~= "string" then
         error("shaderc macro definition names must be strings", 0)
      end
      local macro_value = value
      if macro_value ~= nil then
         macro_value = tostring(macro_value)
      end
      lib.shaderc_compile_options_add_macro_definition(
         compile_options,
         name,
         #name,
         macro_value,
         macro_value and #macro_value or 0
      )
   end
end

function M.compile_spirv(options)
   if type(options) ~= "table" then
      error("shaderc.compile_spirv expects a table")
   end

   local stage = options.stage
   local shader_kind = SHADER_KIND[stage]
   if shader_kind == nil then
      error("shaderc.compile_spirv requires stage to be 'vertex', 'fragment', or 'compute'")
   end

   local source = options.source
   if type(source) ~= "string" then
      error("shaderc.compile_spirv requires source to be a string")
   end

   local lib = load_library()
   local compiler = lib.shaderc_compiler_initialize()
   if compiler == nil or compiler == ffi.NULL then
      return nil, "failed to initialize shaderc compiler"
   end

   local compile_options = lib.shaderc_compile_options_initialize()
   if compile_options == nil or compile_options == ffi.NULL then
      lib.shaderc_compiler_release(compiler)
      return nil, "failed to initialize shaderc compile options"
   end

   lib.shaderc_compile_options_set_source_language(compile_options, 0)
   lib.shaderc_compile_options_set_target_env(compile_options, 0, 1 * 2^22)
   lib.shaderc_compile_options_set_target_spirv(compile_options, 0x010000)
   lib.shaderc_compile_options_set_auto_bind_uniforms(compile_options, false)
   lib.shaderc_compile_options_set_auto_map_locations(compile_options, false)
   lib.shaderc_compile_options_set_preserve_bindings(
      compile_options,
      options.preserve_bindings and true or false
   )

   if options.glsl_version ~= nil then
      lib.shaderc_compile_options_set_forced_version_profile(
         compile_options,
         options.glsl_version,
         0
      )
   end

   if options.debug_info then
      lib.shaderc_compile_options_set_generate_debug_info(compile_options)
   end

   if options.optimization == "size" then
      lib.shaderc_compile_options_set_optimization_level(compile_options, 1)
   elseif options.optimization == "performance" then
      lib.shaderc_compile_options_set_optimization_level(compile_options, 2)
   else
      lib.shaderc_compile_options_set_optimization_level(compile_options, 0)
   end

   apply_macro_definitions(lib, compile_options, options.macro_definitions)

   local source_name = options.source_name or "shader.glsl"
   local entrypoint = options.entrypoint or "main"
   local result = lib.shaderc_compile_into_spv(
      compiler,
      source,
      #source,
      shader_kind,
      source_name,
      entrypoint,
      compile_options
   )

   lib.shaderc_compile_options_release(compile_options)
   lib.shaderc_compiler_release(compiler)

   if result == nil or result == ffi.NULL then
      return nil, "shaderc did not return a compilation result"
   end

   local ok, payload_or_err = pcall(function()
      local status = tonumber(lib.shaderc_result_get_compilation_status(result))
      local messages = compilation_message(lib, result)
      if status ~= 0 then
         local detail = messages
         if detail == "" then
            detail = ("shaderc returned status '%s'"):format(status_name(status))
         else
            detail = ("%s (%s)"):format(detail, status_name(status))
         end
         return nil, detail
      end

      local length = tonumber(lib.shaderc_result_get_length(result)) or 0
      local byte_ptr = lib.shaderc_result_get_bytes(result)
      if byte_ptr == nil or byte_ptr == ffi.NULL or length == 0 then
         return nil, "shaderc produced empty SPIR-V output"
      end

      return {
         bytecode = ffi.string(byte_ptr, length),
         entrypoint = entrypoint,
         stage = stage,
         source_name = source_name,
         warnings = tonumber(lib.shaderc_result_get_num_warnings(result)) or 0,
         errors = tonumber(lib.shaderc_result_get_num_errors(result)) or 0,
         messages = messages,
      }
   end)

   lib.shaderc_result_release(result)

   if not ok then
      error(payload_or_err)
   end

   return payload_or_err
end

return M
