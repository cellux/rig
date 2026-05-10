local M = ... or {}
local ffi = ffi

ffi.cdef[[
typedef unsigned char Uint8;
typedef uint32_t Uint32;
typedef uint64_t Uint64;
typedef uint32_t SDL_PropertiesID;
typedef uint32_t SDL_GPUShaderFormat;
typedef struct SDL_GPUDevice SDL_GPUDevice;
typedef struct SDL_GPUShader SDL_GPUShader;
typedef struct SDL_GPUComputePipeline SDL_GPUComputePipeline;

typedef enum SDL_ShaderCross_IOVarType {
   SDL_SHADERCROSS_IOVAR_TYPE_UNKNOWN,
   SDL_SHADERCROSS_IOVAR_TYPE_INT8,
   SDL_SHADERCROSS_IOVAR_TYPE_UINT8,
   SDL_SHADERCROSS_IOVAR_TYPE_INT16,
   SDL_SHADERCROSS_IOVAR_TYPE_UINT16,
   SDL_SHADERCROSS_IOVAR_TYPE_INT32,
   SDL_SHADERCROSS_IOVAR_TYPE_UINT32,
   SDL_SHADERCROSS_IOVAR_TYPE_INT64,
   SDL_SHADERCROSS_IOVAR_TYPE_UINT64,
   SDL_SHADERCROSS_IOVAR_TYPE_FLOAT16,
   SDL_SHADERCROSS_IOVAR_TYPE_FLOAT32,
   SDL_SHADERCROSS_IOVAR_TYPE_FLOAT64
} SDL_ShaderCross_IOVarType;

typedef enum SDL_ShaderCross_ShaderStage {
   SDL_SHADERCROSS_SHADERSTAGE_VERTEX,
   SDL_SHADERCROSS_SHADERSTAGE_FRAGMENT,
   SDL_SHADERCROSS_SHADERSTAGE_COMPUTE
} SDL_ShaderCross_ShaderStage;

typedef struct SDL_ShaderCross_IOVarMetadata {
   char *name;
   Uint32 location;
   SDL_ShaderCross_IOVarType vector_type;
   Uint32 vector_size;
} SDL_ShaderCross_IOVarMetadata;

typedef struct SDL_ShaderCross_GraphicsShaderResourceInfo {
   Uint32 num_samplers;
   Uint32 num_storage_textures;
   Uint32 num_storage_buffers;
   Uint32 num_uniform_buffers;
} SDL_ShaderCross_GraphicsShaderResourceInfo;

typedef struct SDL_ShaderCross_GraphicsShaderMetadata {
   SDL_ShaderCross_GraphicsShaderResourceInfo resource_info;
   Uint32 num_inputs;
   SDL_ShaderCross_IOVarMetadata *inputs;
   Uint32 num_outputs;
   SDL_ShaderCross_IOVarMetadata *outputs;
} SDL_ShaderCross_GraphicsShaderMetadata;

typedef struct SDL_ShaderCross_ComputePipelineMetadata {
   Uint32 num_samplers;
   Uint32 num_readonly_storage_textures;
   Uint32 num_readonly_storage_buffers;
   Uint32 num_readwrite_storage_textures;
   Uint32 num_readwrite_storage_buffers;
   Uint32 num_uniform_buffers;
   Uint32 threadcount_x;
   Uint32 threadcount_y;
   Uint32 threadcount_z;
} SDL_ShaderCross_ComputePipelineMetadata;

typedef struct SDL_ShaderCross_SPIRV_Info {
   const Uint8 *bytecode;
   size_t bytecode_size;
   const char *entrypoint;
   SDL_ShaderCross_ShaderStage shader_stage;
   SDL_PropertiesID props;
} SDL_ShaderCross_SPIRV_Info;

typedef struct SDL_ShaderCross_HLSL_Define {
   char *name;
   char *value;
} SDL_ShaderCross_HLSL_Define;

typedef struct SDL_ShaderCross_HLSL_Info {
   const char *source;
   const char *entrypoint;
   const char *include_dir;
   SDL_ShaderCross_HLSL_Define *defines;
   SDL_ShaderCross_ShaderStage shader_stage;
   SDL_PropertiesID props;
} SDL_ShaderCross_HLSL_Info;

bool SDL_ShaderCross_Init(void);
void SDL_ShaderCross_Quit(void);
SDL_GPUShaderFormat SDL_ShaderCross_GetSPIRVShaderFormats(void);
SDL_GPUShaderFormat SDL_ShaderCross_GetHLSLShaderFormats(void);
void *SDL_ShaderCross_CompileSPIRVFromHLSL(
   const SDL_ShaderCross_HLSL_Info *info,
   size_t *size
);
SDL_ShaderCross_GraphicsShaderMetadata *SDL_ShaderCross_ReflectGraphicsSPIRV(
   const Uint8 *bytecode,
   size_t bytecode_size,
   SDL_PropertiesID props
);
SDL_ShaderCross_ComputePipelineMetadata *SDL_ShaderCross_ReflectComputeSPIRV(
   const Uint8 *bytecode,
   size_t bytecode_size,
   SDL_PropertiesID props
);
SDL_GPUShader *SDL_ShaderCross_CompileGraphicsShaderFromSPIRV(
   SDL_GPUDevice *device,
   const SDL_ShaderCross_SPIRV_Info *info,
   const SDL_ShaderCross_GraphicsShaderResourceInfo *resource_info,
   SDL_PropertiesID props
);
SDL_GPUComputePipeline *SDL_ShaderCross_CompileComputePipelineFromSPIRV(
   SDL_GPUDevice *device,
   const SDL_ShaderCross_SPIRV_Info *info,
   const SDL_ShaderCross_ComputePipelineMetadata *metadata,
   SDL_PropertiesID props
);

const char *SDL_GetError(void);
void SDL_free(void *mem);
]]

M.SHADERSTAGE_VERTEX = 0
M.SHADERSTAGE_FRAGMENT = 1
M.SHADERSTAGE_COMPUTE = 2

M.IOVAR_TYPE_UNKNOWN = 0
M.IOVAR_TYPE_INT8 = 1
M.IOVAR_TYPE_UINT8 = 2
M.IOVAR_TYPE_INT16 = 3
M.IOVAR_TYPE_UINT16 = 4
M.IOVAR_TYPE_INT32 = 5
M.IOVAR_TYPE_UINT32 = 6
M.IOVAR_TYPE_INT64 = 7
M.IOVAR_TYPE_UINT64 = 8
M.IOVAR_TYPE_FLOAT16 = 9
M.IOVAR_TYPE_FLOAT32 = 10
M.IOVAR_TYPE_FLOAT64 = 11

M.PROP_SHADER_DEBUG_ENABLE_BOOLEAN =
   "SDL_shadercross.spirv.debug.enable"
M.PROP_SHADER_DEBUG_NAME_STRING =
   "SDL_shadercross.spirv.debug.name"
M.PROP_SHADER_CULL_UNUSED_BINDINGS_BOOLEAN =
   "SDL_shadercross.spirv.cull_unused_bindings"
M.PROP_SPIRV_PSSL_COMPATIBILITY_BOOLEAN =
   "SDL_shadercross.spirv.pssl.compatibility"
M.PROP_SPIRV_MSL_VERSION_STRING =
   "SDL_shadercross.spirv.msl.version"
M.PROP_HLSL_SKIP_SPIRV_ROUNDTRIP_BOOLEAN =
   "SDL_shadercross.hlsl.skip_spirv_roundtrip"

local shadercross_state = {
   library = nil,
   error = nil,
}

local sdl_state = {
   library = nil,
   error = nil,
}

local SHADER_STAGE_NAMES = {
   [M.SHADERSTAGE_VERTEX] = "vertex",
   [M.SHADERSTAGE_FRAGMENT] = "fragment",
   [M.SHADERSTAGE_COMPUTE] = "compute",
}

local IOVAR_TYPE_NAMES = {
   [M.IOVAR_TYPE_UNKNOWN] = "unknown",
   [M.IOVAR_TYPE_INT8] = "int8",
   [M.IOVAR_TYPE_UINT8] = "uint8",
   [M.IOVAR_TYPE_INT16] = "int16",
   [M.IOVAR_TYPE_UINT16] = "uint16",
   [M.IOVAR_TYPE_INT32] = "int32",
   [M.IOVAR_TYPE_UINT32] = "uint32",
   [M.IOVAR_TYPE_INT64] = "int64",
   [M.IOVAR_TYPE_UINT64] = "uint64",
   [M.IOVAR_TYPE_FLOAT16] = "float16",
   [M.IOVAR_TYPE_FLOAT32] = "float32",
   [M.IOVAR_TYPE_FLOAT64] = "float64",
}

local function load_library(candidates, state, label)
   if state.library ~= nil then
      return state.library
   end
   if state.error ~= nil then
      error(state.error)
   end

   local failures = {}

   for _, name in ipairs(candidates) do
      local ok, lib = pcall(ffi.load, name)
      if ok then
         state.library = lib
         return lib
      end
      table.insert(failures, tostring(lib))
   end

   state.error = ("failed to load %s library: %s"):format(
      label,
      table.concat(failures, "; ")
   )
   error(state.error)
end

local function load_shadercross_library()
   return load_library(
      {
         "SDL3_shadercross",
         "libSDL3_shadercross.so.0",
         "libSDL3_shadercross.so",
         "SDL3_shadercross.dll",
         "libSDL3_shadercross.dylib",
      },
      shadercross_state,
      "SDL3_shadercross"
   )
end

local function load_sdl_library()
   return load_library(
      {
         "SDL3",
         "libSDL3.so.0",
         "libSDL3.so",
         "SDL3.dll",
         "libSDL3.dylib",
      },
      sdl_state,
      "SDL3"
   )
end

local function get_sdl_error(fallback)
   local error_ptr = load_sdl_library().SDL_GetError()
   if error_ptr ~= nil and error_ptr[0] ~= 0 then
      return ffi.string(error_ptr)
   end
   return fallback or "unknown SDL error"
end

local function free_sdl_memory(ptr)
   if ptr ~= nil then
      load_sdl_library().SDL_free(ffi.cast("void *", ptr))
   end
end

local function normalize_properties_id(props)
   if props == nil then
      return 0
   end

   local value_type = type(props)
   if value_type == "number" or value_type == "cdata" then
      return props
   end

   error("props must be a number or cdata SDL_PropertiesID")
end

local function normalize_shader_stage(shader_stage)
   local value = shader_stage

   if type(value) == "string" then
      local normalized = value:lower()
      if normalized == "vertex" then
         value = M.SHADERSTAGE_VERTEX
      elseif normalized == "fragment" or normalized == "pixel" then
         value = M.SHADERSTAGE_FRAGMENT
      elseif normalized == "compute" then
         value = M.SHADERSTAGE_COMPUTE
      else
         error(("unknown shader stage '%s'"):format(value))
      end
   end

   if type(value) ~= "number" then
      error("shader_stage must be a number or one of 'vertex', 'fragment', 'compute'")
   end

   local integer = math.floor(value)
   if value ~= integer or SHADER_STAGE_NAMES[integer] == nil then
      error("shader_stage must be a valid SDL_ShaderCross_ShaderStage value")
   end

   return integer
end

local function build_define_entries(defines)
   if defines == nil then
      return nil, nil
   end
   if type(defines) ~= "table" then
      error("defines must be a table if set")
   end

   local entries = {}
   local keepalive = {}

   if #defines > 0 then
      for i, define in ipairs(defines) do
         if type(define) ~= "table" then
            error(("defines[%d] must be a table"):format(i))
         end
         if type(define.name) ~= "string" then
            error(("defines[%d].name must be a string"):format(i))
         end
         if define.value ~= nil and type(define.value) ~= "string" then
            error(("defines[%d].value must be a string if set"):format(i))
         end
         table.insert(entries, {
            name = define.name,
            value = define.value,
         })
      end
   else
      for name, value in pairs(defines) do
         if type(name) ~= "string" then
            error("define keys must be strings")
         end
         if value ~= nil and type(value) ~= "string" then
            error(("define '%s' must have a string value if set"):format(name))
         end
         table.insert(entries, {
            name = name,
            value = value,
         })
      end
   end

   local define_array = ffi.new("SDL_ShaderCross_HLSL_Define[?]", #entries + 1)
   for i, entry in ipairs(entries) do
      define_array[i - 1].name = entry.name
      define_array[i - 1].value = entry.value
      table.insert(keepalive, entry.name)
      if entry.value ~= nil then
         table.insert(keepalive, entry.value)
      end
   end

   return define_array, keepalive
end

local function build_hlsl_info(options)
   if type(options) ~= "table" then
      error("compile_spirv_from_hlsl expects a table")
   end
   if type(options.source) ~= "string" then
      error("compile_spirv_from_hlsl requires source to be a string")
   end

   local entrypoint = options.entrypoint or "main"
   if type(entrypoint) ~= "string" then
      error("entrypoint must be a string if set")
   end

   local include_dir = options.include_dir
   if include_dir ~= nil and type(include_dir) ~= "string" then
      error("include_dir must be a string if set")
   end

   local define_array, define_keepalive = build_define_entries(options.defines)
   local info = ffi.new("SDL_ShaderCross_HLSL_Info[1]")
   local keepalive = {
      options.source,
      entrypoint,
      include_dir,
      define_keepalive,
   }

   info[0].source = options.source
   info[0].entrypoint = entrypoint
   info[0].include_dir = include_dir
   info[0].defines = define_array
   info[0].shader_stage = normalize_shader_stage(options.shader_stage)
   info[0].props = normalize_properties_id(options.props)

   return info, keepalive
end

local function build_spirv_buffer(bytecode)
   if type(bytecode) ~= "string" then
      error("bytecode must be a string")
   end

   local length = #bytecode
   local buffer = ffi.new("Uint8[?]", length > 0 and length or 1)
   if length > 0 then
      ffi.copy(buffer, bytecode, length)
   end
   return buffer
end

local function build_spirv_info(options)
   if type(options) ~= "table" then
      error("SPIR-V shader info must be a table")
   end
   if type(options.bytecode) ~= "string" then
      error("SPIR-V shader info requires bytecode to be a string")
   end

   local entrypoint = options.entrypoint or "main"
   if type(entrypoint) ~= "string" then
      error("entrypoint must be a string if set")
   end

   local bytecode_buffer = build_spirv_buffer(options.bytecode)
   local info = ffi.new("SDL_ShaderCross_SPIRV_Info[1]")
   info[0].bytecode = bytecode_buffer
   info[0].bytecode_size = #options.bytecode
   info[0].entrypoint = entrypoint
   info[0].shader_stage = normalize_shader_stage(options.shader_stage)
   info[0].props = normalize_properties_id(options.props)

   return info, {
      bytecode_buffer,
      entrypoint,
   }
end

local function copy_iovar_metadata(items_ptr, count)
   local items = {}
   local total = tonumber(count) or 0

   for index = 0, total - 1 do
      local item = items_ptr[index]
      local vector_type = tonumber(item.vector_type) or M.IOVAR_TYPE_UNKNOWN
      table.insert(items, {
         name = item.name ~= nil and ffi.string(item.name) or nil,
         location = tonumber(item.location) or 0,
         vector_type = vector_type,
         vector_type_name = IOVAR_TYPE_NAMES[vector_type] or "unknown",
         vector_size = tonumber(item.vector_size) or 0,
      })
   end

   return items
end

local function copy_graphics_resource_info(resource_info)
   return {
      num_samplers = tonumber(resource_info.num_samplers) or 0,
      num_storage_textures = tonumber(resource_info.num_storage_textures) or 0,
      num_storage_buffers = tonumber(resource_info.num_storage_buffers) or 0,
      num_uniform_buffers = tonumber(resource_info.num_uniform_buffers) or 0,
   }
end

local function build_graphics_resource_info(resource_info)
   if type(resource_info) ~= "table" then
      error("resource_info must be a table")
   end

   local resource_info_c = ffi.new("SDL_ShaderCross_GraphicsShaderResourceInfo[1]")
   resource_info_c[0].num_samplers = resource_info.num_samplers or 0
   resource_info_c[0].num_storage_textures = resource_info.num_storage_textures or 0
   resource_info_c[0].num_storage_buffers = resource_info.num_storage_buffers or 0
   resource_info_c[0].num_uniform_buffers = resource_info.num_uniform_buffers or 0
   return resource_info_c
end

local function copy_compute_metadata(metadata_ptr)
   return {
      num_samplers = tonumber(metadata_ptr.num_samplers) or 0,
      num_readonly_storage_textures = tonumber(metadata_ptr.num_readonly_storage_textures) or 0,
      num_readonly_storage_buffers = tonumber(metadata_ptr.num_readonly_storage_buffers) or 0,
      num_readwrite_storage_textures = tonumber(metadata_ptr.num_readwrite_storage_textures) or 0,
      num_readwrite_storage_buffers = tonumber(metadata_ptr.num_readwrite_storage_buffers) or 0,
      num_uniform_buffers = tonumber(metadata_ptr.num_uniform_buffers) or 0,
      threadcount_x = tonumber(metadata_ptr.threadcount_x) or 0,
      threadcount_y = tonumber(metadata_ptr.threadcount_y) or 0,
      threadcount_z = tonumber(metadata_ptr.threadcount_z) or 0,
   }
end

local function build_compute_metadata(metadata)
   if type(metadata) ~= "table" then
      error("metadata must be a table")
   end

   local metadata_c = ffi.new("SDL_ShaderCross_ComputePipelineMetadata[1]")
   metadata_c[0].num_samplers = metadata.num_samplers or 0
   metadata_c[0].num_readonly_storage_textures = metadata.num_readonly_storage_textures or 0
   metadata_c[0].num_readonly_storage_buffers = metadata.num_readonly_storage_buffers or 0
   metadata_c[0].num_readwrite_storage_textures = metadata.num_readwrite_storage_textures or 0
   metadata_c[0].num_readwrite_storage_buffers = metadata.num_readwrite_storage_buffers or 0
   metadata_c[0].num_uniform_buffers = metadata.num_uniform_buffers or 0
   metadata_c[0].threadcount_x = metadata.threadcount_x or 0
   metadata_c[0].threadcount_y = metadata.threadcount_y or 0
   metadata_c[0].threadcount_z = metadata.threadcount_z or 0
   return metadata_c
end

function M.Init()
   return load_shadercross_library().SDL_ShaderCross_Init()
end

function M.Quit()
   load_shadercross_library().SDL_ShaderCross_Quit()
end

function M.GetSPIRVShaderFormats()
   return load_shadercross_library().SDL_ShaderCross_GetSPIRVShaderFormats()
end

function M.GetHLSLShaderFormats()
   return load_shadercross_library().SDL_ShaderCross_GetHLSLShaderFormats()
end

function M.init()
   if M._initialized then
      return true
   end
   if not M.Init() then
      return nil, get_sdl_error("failed to initialize SDL_shadercross")
   end
   M._initialized = true
   return true
end

function M.quit()
   if M._initialized then
      M.Quit()
      M._initialized = false
   end
end

function M.compile_spirv_from_hlsl(options)
   local ok, init_err = M.init()
   if not ok then
      return nil, init_err
   end

   local info, _ = build_hlsl_info(options)
   local size_out = ffi.new("size_t[1]")
   local bytecode_ptr = load_shadercross_library().SDL_ShaderCross_CompileSPIRVFromHLSL(
      info,
      size_out
   )

   if bytecode_ptr == nil then
      return nil, get_sdl_error("failed to compile SPIR-V from HLSL")
   end

   local bytecode = ffi.string(bytecode_ptr, tonumber(size_out[0]))
   free_sdl_memory(bytecode_ptr)
   return bytecode
end

function M.reflect_graphics_spirv(bytecode, props)
   local ok, init_err = M.init()
   if not ok then
      return nil, init_err
   end

   local bytecode_buffer = build_spirv_buffer(bytecode)
   local metadata_ptr = load_shadercross_library().SDL_ShaderCross_ReflectGraphicsSPIRV(
      bytecode_buffer,
      #bytecode,
      normalize_properties_id(props)
   )

   if metadata_ptr == nil then
      return nil, get_sdl_error("failed to reflect graphics SPIR-V")
   end

   local metadata = {
      resource_info = copy_graphics_resource_info(metadata_ptr.resource_info),
      inputs = copy_iovar_metadata(metadata_ptr.inputs, metadata_ptr.num_inputs),
      outputs = copy_iovar_metadata(metadata_ptr.outputs, metadata_ptr.num_outputs),
   }

   free_sdl_memory(metadata_ptr)
   return metadata
end

function M.reflect_compute_spirv(bytecode, props)
   local ok, init_err = M.init()
   if not ok then
      return nil, init_err
   end

   local bytecode_buffer = build_spirv_buffer(bytecode)
   local metadata_ptr = load_shadercross_library().SDL_ShaderCross_ReflectComputeSPIRV(
      bytecode_buffer,
      #bytecode,
      normalize_properties_id(props)
   )

   if metadata_ptr == nil then
      return nil, get_sdl_error("failed to reflect compute SPIR-V")
   end

   local metadata = copy_compute_metadata(metadata_ptr)
   free_sdl_memory(metadata_ptr)
   return metadata
end

function M.compile_graphics_shader_from_spirv(options)
   local ok, init_err = M.init()
   if not ok then
      return nil, init_err
   end
   if type(options) ~= "table" then
      error("compile_graphics_shader_from_spirv expects a table")
   end
   if type(options.device) ~= "cdata" then
      error("compile_graphics_shader_from_spirv requires device to be SDL_GPUDevice* cdata")
   end
   if type(options.resource_info) ~= "table" then
      error("compile_graphics_shader_from_spirv requires resource_info to be a table")
   end

   local info, _ = build_spirv_info(options)
   local resource_info = build_graphics_resource_info(options.resource_info)
   local shader_ptr = load_shadercross_library().SDL_ShaderCross_CompileGraphicsShaderFromSPIRV(
      ffi.cast("SDL_GPUDevice *", options.device),
      info,
      resource_info,
      normalize_properties_id(options.shader_props)
   )

   if shader_ptr == nil then
      return nil, get_sdl_error("failed to compile graphics shader from SPIR-V")
   end

   return shader_ptr
end

function M.compile_compute_pipeline_from_spirv(options)
   local ok, init_err = M.init()
   if not ok then
      return nil, init_err
   end
   if type(options) ~= "table" then
      error("compile_compute_pipeline_from_spirv expects a table")
   end
   if type(options.device) ~= "cdata" then
      error("compile_compute_pipeline_from_spirv requires device to be SDL_GPUDevice* cdata")
   end
   if type(options.metadata) ~= "table" then
      error("compile_compute_pipeline_from_spirv requires metadata to be a table")
   end

   local info, _ = build_spirv_info(options)
   local metadata = build_compute_metadata(options.metadata)
   local pipeline_ptr = load_shadercross_library().SDL_ShaderCross_CompileComputePipelineFromSPIRV(
      ffi.cast("SDL_GPUDevice *", options.device),
      info,
      metadata,
      normalize_properties_id(options.pipeline_props)
   )

   if pipeline_ptr == nil then
      return nil, get_sdl_error("failed to compile compute pipeline from SPIR-V")
   end

   return pipeline_ptr
end

return M
