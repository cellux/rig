local M = ... or {}
local ffi = ffi
local bit = bit

ffi.cdef[[
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef unsigned char Uint8;
typedef uint16_t Uint16;
typedef uint32_t Uint32;
typedef uint64_t Uint64;
typedef int32_t Sint32;
typedef int64_t Sint64;
typedef uint32_t SDL_EventType;
typedef uint32_t SDL_WindowID;
typedef uint32_t SDL_KeyboardID;
typedef int32_t SDL_Scancode;
typedef uint32_t SDL_Keycode;
typedef uint16_t SDL_Keymod;
typedef uint32_t SDL_PropertiesID;
typedef struct SDL_KeyboardEvent {
   SDL_EventType type;
   Uint32 reserved;
   Uint64 timestamp;
   SDL_WindowID windowID;
   SDL_KeyboardID which;
   SDL_Scancode scancode;
   SDL_Keycode key;
   SDL_Keymod mod;
   Uint16 raw;
   bool down;
   bool repeat;
} SDL_KeyboardEvent;
typedef struct SDL_QuitEvent {
   SDL_EventType type;
   Uint32 reserved;
   Uint64 timestamp;
} SDL_QuitEvent;
typedef union SDL_Event {
   Uint32 type;
   SDL_KeyboardEvent key;
   SDL_QuitEvent quit;
   Uint8 padding[128];
} SDL_Event;
bool SDL_SetRenderDrawColor(SDL_Renderer *renderer, Uint8 r, Uint8 g, Uint8 b, Uint8 a);
bool SDL_RenderClear(SDL_Renderer *renderer);
SDL_Window *SDL_CreateWindowWithProperties(SDL_PropertiesID props);
SDL_Renderer *SDL_CreateRenderer(SDL_Window *window, const char *name);
bool SDL_SetRenderVSync(SDL_Renderer *renderer, int vsync);
bool SDL_RenderPresent(SDL_Renderer *renderer);
void SDL_DestroyRenderer(SDL_Renderer *renderer);
void SDL_DestroyWindow(SDL_Window *window);
bool SDL_Init(Uint32 flags);
void SDL_QuitSubSystem(Uint32 flags);
Uint32 SDL_WasInit(Uint32 flags);
SDL_PropertiesID SDL_CreateProperties(void);
void SDL_DestroyProperties(SDL_PropertiesID props);
bool SDL_SetPointerProperty(SDL_PropertiesID props, const char *name, void *value);
bool SDL_SetStringProperty(SDL_PropertiesID props, const char *name, const char *value);
bool SDL_SetNumberProperty(SDL_PropertiesID props, const char *name, Sint64 value);
bool SDL_SetFloatProperty(SDL_PropertiesID props, const char *name, float value);
bool SDL_SetBooleanProperty(SDL_PropertiesID props, const char *name, bool value);
bool SDL_PollEvent(SDL_Event *event);
const char *SDL_GetError(void);
const char *SDL_GetKeyName(SDL_Keycode key);
]]

ffi.cdef[[
typedef struct SDL_GPUDevice SDL_GPUDevice;
typedef struct SDL_GPUTexture SDL_GPUTexture;
typedef struct SDL_GPUBuffer SDL_GPUBuffer;
typedef struct SDL_GPUTransferBuffer SDL_GPUTransferBuffer;
typedef struct SDL_GPUShader SDL_GPUShader;
typedef struct SDL_GPUGraphicsPipeline SDL_GPUGraphicsPipeline;
typedef struct SDL_GPUCommandBuffer SDL_GPUCommandBuffer;
typedef struct SDL_GPUCopyPass SDL_GPUCopyPass;
typedef struct SDL_GPURenderPass SDL_GPURenderPass;
typedef uint32_t SDL_GPUShaderFormat;
typedef uint32_t SDL_GPUBufferUsageFlags;
typedef uint32_t SDL_GPUTextureUsageFlags;
typedef int SDL_GPUTextureType;
typedef int SDL_GPUSampleCount;
typedef int SDL_GPUTransferBufferUsage;
typedef int SDL_GPUShaderStage;
typedef int SDL_GPUPrimitiveType;
typedef int SDL_GPUIndexElementSize;
typedef int SDL_GPUVertexElementFormat;
typedef int SDL_GPUVertexInputRate;
typedef int SDL_GPUFillMode;
typedef int SDL_GPUCullMode;
typedef int SDL_GPUFrontFace;
typedef int SDL_GPUCompareOp;
typedef int SDL_GPUTextureFormat;
typedef int SDL_GPULoadOp;
typedef int SDL_GPUStoreOp;
typedef struct SDL_FColor {
   float r;
   float g;
   float b;
   float a;
} SDL_FColor;
typedef struct SDL_Rect {
   int x;
   int y;
   int w;
   int h;
} SDL_Rect;
typedef struct SDL_GPUViewport {
   float x;
   float y;
   float w;
   float h;
   float min_depth;
   float max_depth;
} SDL_GPUViewport;
typedef struct SDL_GPUShaderCreateInfo {
   size_t code_size;
   const Uint8 *code;
   const char *entrypoint;
   SDL_GPUShaderFormat format;
   SDL_GPUShaderStage stage;
   Uint32 num_samplers;
   Uint32 num_storage_textures;
   Uint32 num_storage_buffers;
   Uint32 num_uniform_buffers;
   SDL_PropertiesID props;
} SDL_GPUShaderCreateInfo;
typedef struct SDL_GPUBufferCreateInfo {
   SDL_GPUBufferUsageFlags usage;
   Uint32 size;
   SDL_PropertiesID props;
} SDL_GPUBufferCreateInfo;
typedef struct SDL_GPUTransferBufferCreateInfo {
   SDL_GPUTransferBufferUsage usage;
   Uint32 size;
   SDL_PropertiesID props;
} SDL_GPUTransferBufferCreateInfo;
typedef struct SDL_GPUTextureCreateInfo {
   SDL_GPUTextureType type;
   SDL_GPUTextureFormat format;
   SDL_GPUTextureUsageFlags usage;
   Uint32 width;
   Uint32 height;
   Uint32 layer_count_or_depth;
   Uint32 num_levels;
   SDL_GPUSampleCount sample_count;
   SDL_PropertiesID props;
} SDL_GPUTextureCreateInfo;
typedef struct SDL_GPUTransferBufferLocation {
   SDL_GPUTransferBuffer *transfer_buffer;
   Uint32 offset;
} SDL_GPUTransferBufferLocation;
typedef struct SDL_GPUBufferRegion {
   SDL_GPUBuffer *buffer;
   Uint32 offset;
   Uint32 size;
} SDL_GPUBufferRegion;
typedef struct SDL_GPUBufferBinding {
   SDL_GPUBuffer *buffer;
   Uint32 offset;
} SDL_GPUBufferBinding;
typedef struct SDL_GPUVertexBufferDescription {
   Uint32 slot;
   Uint32 pitch;
   SDL_GPUVertexInputRate input_rate;
   Uint32 instance_step_rate;
} SDL_GPUVertexBufferDescription;
typedef struct SDL_GPUVertexAttribute {
   Uint32 location;
   Uint32 buffer_slot;
   SDL_GPUVertexElementFormat format;
   Uint32 offset;
} SDL_GPUVertexAttribute;
typedef struct SDL_GPUVertexInputState {
   const SDL_GPUVertexBufferDescription *vertex_buffer_descriptions;
   Uint32 num_vertex_buffers;
   const SDL_GPUVertexAttribute *vertex_attributes;
   Uint32 num_vertex_attributes;
} SDL_GPUVertexInputState;
typedef struct SDL_GPURasterizerState {
   SDL_GPUFillMode fill_mode;
   SDL_GPUCullMode cull_mode;
   SDL_GPUFrontFace front_face;
   float depth_bias_constant_factor;
   float depth_bias_clamp;
   float depth_bias_slope_factor;
   bool enable_depth_bias;
   bool enable_depth_clip;
   Uint8 padding1;
   Uint8 padding2;
} SDL_GPURasterizerState;
typedef struct SDL_GPUMultisampleState {
   SDL_GPUSampleCount sample_count;
   Uint32 sample_mask;
   bool enable_mask;
   bool enable_alpha_to_coverage;
   Uint8 padding2;
   Uint8 padding3;
} SDL_GPUMultisampleState;
typedef struct SDL_GPUStencilOpState {
   int fail_op;
   int pass_op;
   int depth_fail_op;
   SDL_GPUCompareOp compare_op;
} SDL_GPUStencilOpState;
typedef struct SDL_GPUDepthStencilState {
   SDL_GPUCompareOp compare_op;
   SDL_GPUStencilOpState back_stencil_state;
   SDL_GPUStencilOpState front_stencil_state;
   Uint8 compare_mask;
   Uint8 write_mask;
   bool enable_depth_test;
   bool enable_depth_write;
   bool enable_stencil_test;
   Uint8 padding1;
   Uint8 padding2;
   Uint8 padding3;
} SDL_GPUDepthStencilState;
typedef struct SDL_GPUColorTargetBlendState {
   int src_color_blendfactor;
   int dst_color_blendfactor;
   int color_blend_op;
   int src_alpha_blendfactor;
   int dst_alpha_blendfactor;
   int alpha_blend_op;
   Uint8 color_write_mask;
   bool enable_blend;
   bool enable_color_write_mask;
   Uint8 padding1;
   Uint8 padding2;
} SDL_GPUColorTargetBlendState;
typedef struct SDL_GPUColorTargetDescription {
   SDL_GPUTextureFormat format;
   SDL_GPUColorTargetBlendState blend_state;
} SDL_GPUColorTargetDescription;
typedef struct SDL_GPUGraphicsPipelineTargetInfo {
   const SDL_GPUColorTargetDescription *color_target_descriptions;
   Uint32 num_color_targets;
   SDL_GPUTextureFormat depth_stencil_format;
   bool has_depth_stencil_target;
   Uint8 padding1;
   Uint8 padding2;
   Uint8 padding3;
} SDL_GPUGraphicsPipelineTargetInfo;
typedef struct SDL_GPUGraphicsPipelineCreateInfo {
   SDL_GPUShader *vertex_shader;
   SDL_GPUShader *fragment_shader;
   SDL_GPUVertexInputState vertex_input_state;
   SDL_GPUPrimitiveType primitive_type;
   SDL_GPURasterizerState rasterizer_state;
   SDL_GPUMultisampleState multisample_state;
   SDL_GPUDepthStencilState depth_stencil_state;
   SDL_GPUGraphicsPipelineTargetInfo target_info;
   SDL_PropertiesID props;
} SDL_GPUGraphicsPipelineCreateInfo;
typedef struct SDL_GPUColorTargetInfo {
   SDL_GPUTexture *texture;
   Uint32 mip_level;
   Uint32 layer_or_depth_plane;
   SDL_FColor clear_color;
   SDL_GPULoadOp load_op;
   SDL_GPUStoreOp store_op;
   SDL_GPUTexture *resolve_texture;
   Uint32 resolve_mip_level;
   Uint32 resolve_layer;
   bool cycle;
   bool cycle_resolve_texture;
   Uint8 padding1;
   Uint8 padding2;
} SDL_GPUColorTargetInfo;
typedef struct SDL_GPUDepthStencilTargetInfo {
   SDL_GPUTexture *texture;
   float clear_depth;
   SDL_GPULoadOp load_op;
   SDL_GPUStoreOp store_op;
   SDL_GPULoadOp stencil_load_op;
   SDL_GPUStoreOp stencil_store_op;
   bool cycle;
   Uint8 clear_stencil;
   Uint8 mip_level;
   Uint8 layer;
} SDL_GPUDepthStencilTargetInfo;
bool SDL_GPUSupportsShaderFormats(SDL_GPUShaderFormat format_flags, const char *name);
SDL_GPUDevice *SDL_CreateGPUDevice(SDL_GPUShaderFormat format_flags, bool debug_mode, const char *name);
void SDL_DestroyGPUDevice(SDL_GPUDevice *device);
int SDL_GetNumGPUDrivers(void);
const char *SDL_GetGPUDriver(int index);
SDL_GPUShaderFormat SDL_GetGPUShaderFormats(SDL_GPUDevice *device);
const char *SDL_GetGPUDeviceDriver(SDL_GPUDevice *device);
bool SDL_ClaimWindowForGPUDevice(SDL_GPUDevice *device, SDL_Window *window);
void SDL_ReleaseWindowFromGPUDevice(SDL_GPUDevice *device, SDL_Window *window);
SDL_GPUTextureFormat SDL_GetGPUSwapchainTextureFormat(SDL_GPUDevice *device, SDL_Window *window);
SDL_GPUShader *SDL_CreateGPUShader(SDL_GPUDevice *device, const SDL_GPUShaderCreateInfo *createinfo);
void SDL_ReleaseGPUShader(SDL_GPUDevice *device, SDL_GPUShader *shader);
SDL_GPUGraphicsPipeline *SDL_CreateGPUGraphicsPipeline(SDL_GPUDevice *device, const SDL_GPUGraphicsPipelineCreateInfo *createinfo);
void SDL_ReleaseGPUGraphicsPipeline(SDL_GPUDevice *device, SDL_GPUGraphicsPipeline *graphics_pipeline);
SDL_GPUBuffer *SDL_CreateGPUBuffer(SDL_GPUDevice *device, const SDL_GPUBufferCreateInfo *createinfo);
void SDL_ReleaseGPUBuffer(SDL_GPUDevice *device, SDL_GPUBuffer *buffer);
SDL_GPUTransferBuffer *SDL_CreateGPUTransferBuffer(SDL_GPUDevice *device, const SDL_GPUTransferBufferCreateInfo *createinfo);
void SDL_ReleaseGPUTransferBuffer(SDL_GPUDevice *device, SDL_GPUTransferBuffer *transfer_buffer);
void *SDL_MapGPUTransferBuffer(SDL_GPUDevice *device, SDL_GPUTransferBuffer *transfer_buffer, bool cycle);
void SDL_UnmapGPUTransferBuffer(SDL_GPUDevice *device, SDL_GPUTransferBuffer *transfer_buffer);
SDL_GPUTexture *SDL_CreateGPUTexture(SDL_GPUDevice *device, const SDL_GPUTextureCreateInfo *createinfo);
void SDL_ReleaseGPUTexture(SDL_GPUDevice *device, SDL_GPUTexture *texture);
bool SDL_GPUTextureSupportsFormat(SDL_GPUDevice *device, SDL_GPUTextureFormat format, SDL_GPUTextureType type, SDL_GPUTextureUsageFlags usage);
SDL_GPUCommandBuffer *SDL_AcquireGPUCommandBuffer(SDL_GPUDevice *device);
void SDL_PushGPUVertexUniformData(SDL_GPUCommandBuffer *command_buffer, Uint32 slot_index, const void *data, Uint32 length);
void SDL_PushGPUFragmentUniformData(SDL_GPUCommandBuffer *command_buffer, Uint32 slot_index, const void *data, Uint32 length);
SDL_GPUCopyPass *SDL_BeginGPUCopyPass(SDL_GPUCommandBuffer *command_buffer);
void SDL_UploadToGPUBuffer(SDL_GPUCopyPass *copy_pass, const SDL_GPUTransferBufferLocation *source, const SDL_GPUBufferRegion *destination, bool cycle);
void SDL_EndGPUCopyPass(SDL_GPUCopyPass *copy_pass);
bool SDL_WaitAndAcquireGPUSwapchainTexture(SDL_GPUCommandBuffer *command_buffer, SDL_Window *window, SDL_GPUTexture **swapchain_texture, Uint32 *swapchain_texture_width, Uint32 *swapchain_texture_height);
SDL_GPURenderPass *SDL_BeginGPURenderPass(SDL_GPUCommandBuffer *command_buffer, const SDL_GPUColorTargetInfo *color_target_infos, Uint32 num_color_targets, const SDL_GPUDepthStencilTargetInfo *depth_stencil_target_info);
void SDL_BindGPUGraphicsPipeline(SDL_GPURenderPass *render_pass, SDL_GPUGraphicsPipeline *graphics_pipeline);
void SDL_BindGPUVertexBuffers(SDL_GPURenderPass *render_pass, Uint32 first_slot, const SDL_GPUBufferBinding *bindings, Uint32 num_bindings);
void SDL_BindGPUIndexBuffer(SDL_GPURenderPass *render_pass, const SDL_GPUBufferBinding *binding, SDL_GPUIndexElementSize index_element_size);
void SDL_DrawGPUPrimitives(SDL_GPURenderPass *render_pass, Uint32 num_vertices, Uint32 num_instances, Uint32 first_vertex, Uint32 first_instance);
void SDL_DrawGPUIndexedPrimitives(SDL_GPURenderPass *render_pass, Uint32 num_indices, Uint32 num_instances, Uint32 first_index, Sint32 vertex_offset, Uint32 first_instance);
void SDL_EndGPURenderPass(SDL_GPURenderPass *render_pass);
bool SDL_SubmitGPUCommandBuffer(SDL_GPUCommandBuffer *command_buffer);
bool SDL_WaitForGPUIdle(SDL_GPUDevice *device);
]]

local SDL_EVENT_QUIT = 0x100
local SDL_EVENT_KEY_DOWN = 0x300
local SDL_EVENT_KEY_UP = 0x301

local sdl_library = nil
local sdl_library_error = nil

local function load_sdl_library()
   if sdl_library ~= nil then
      return sdl_library
   end
   if sdl_library_error ~= nil then
      error(sdl_library_error)
   end

   local candidates = {
      "SDL3",
      "libSDL3.so.0",
      "libSDL3.so",
      "SDL3.dll",
      "libSDL3.dylib",
   }
   local failures = {}

   for _, name in ipairs(candidates) do
      local ok, lib = pcall(ffi.load, name)
      if ok then
         sdl_library = lib
         return lib
      end
      failures[#failures + 1] = tostring(lib)
   end

   sdl_library_error = "failed to load SDL3 library: "
      .. table.concat(failures, "; ")
   error(sdl_library_error)
end

local function export_sdl_function(export_name, symbol_name)
   M[export_name] = function(...)
      return load_sdl_library()[symbol_name](...)
   end
end

export_sdl_function("SetRenderDrawColor", "SDL_SetRenderDrawColor")
export_sdl_function("RenderClear", "SDL_RenderClear")
export_sdl_function("CreateWindowWithProperties", "SDL_CreateWindowWithProperties")
export_sdl_function("CreateRenderer", "SDL_CreateRenderer")
export_sdl_function("SetRenderVSync", "SDL_SetRenderVSync")
export_sdl_function("RenderPresent", "SDL_RenderPresent")
export_sdl_function("DestroyRenderer", "SDL_DestroyRenderer")
export_sdl_function("DestroyWindow", "SDL_DestroyWindow")
export_sdl_function("Init", "SDL_Init")
export_sdl_function("QuitSubSystem", "SDL_QuitSubSystem")
export_sdl_function("WasInit", "SDL_WasInit")
export_sdl_function("CreateProperties", "SDL_CreateProperties")
export_sdl_function("DestroyProperties", "SDL_DestroyProperties")
export_sdl_function("SetPointerProperty", "SDL_SetPointerProperty")
export_sdl_function("SetStringProperty", "SDL_SetStringProperty")
export_sdl_function("SetNumberProperty", "SDL_SetNumberProperty")
export_sdl_function("SetFloatProperty", "SDL_SetFloatProperty")
export_sdl_function("SetBooleanProperty", "SDL_SetBooleanProperty")
export_sdl_function("PollEvent", "SDL_PollEvent")
export_sdl_function("GetError", "SDL_GetError")
export_sdl_function("GetKeyName", "SDL_GetKeyName")
export_sdl_function("GPUSupportsShaderFormats", "SDL_GPUSupportsShaderFormats")
export_sdl_function("CreateGPUDevice", "SDL_CreateGPUDevice")
export_sdl_function("DestroyGPUDevice", "SDL_DestroyGPUDevice")
export_sdl_function("GetNumGPUDrivers", "SDL_GetNumGPUDrivers")
export_sdl_function("GetGPUDriver", "SDL_GetGPUDriver")
export_sdl_function("GetGPUShaderFormats", "SDL_GetGPUShaderFormats")
export_sdl_function("GetGPUDeviceDriver", "SDL_GetGPUDeviceDriver")
export_sdl_function("ClaimWindowForGPUDevice", "SDL_ClaimWindowForGPUDevice")
export_sdl_function("ReleaseWindowFromGPUDevice", "SDL_ReleaseWindowFromGPUDevice")
export_sdl_function("GetGPUSwapchainTextureFormat", "SDL_GetGPUSwapchainTextureFormat")
export_sdl_function("CreateGPUShader", "SDL_CreateGPUShader")
export_sdl_function("ReleaseGPUShader", "SDL_ReleaseGPUShader")
export_sdl_function("CreateGPUGraphicsPipeline", "SDL_CreateGPUGraphicsPipeline")
export_sdl_function("ReleaseGPUGraphicsPipeline", "SDL_ReleaseGPUGraphicsPipeline")
export_sdl_function("CreateGPUBuffer", "SDL_CreateGPUBuffer")
export_sdl_function("ReleaseGPUBuffer", "SDL_ReleaseGPUBuffer")
export_sdl_function("CreateGPUTransferBuffer", "SDL_CreateGPUTransferBuffer")
export_sdl_function("ReleaseGPUTransferBuffer", "SDL_ReleaseGPUTransferBuffer")
export_sdl_function("MapGPUTransferBuffer", "SDL_MapGPUTransferBuffer")
export_sdl_function("UnmapGPUTransferBuffer", "SDL_UnmapGPUTransferBuffer")
export_sdl_function("CreateGPUTexture", "SDL_CreateGPUTexture")
export_sdl_function("ReleaseGPUTexture", "SDL_ReleaseGPUTexture")
export_sdl_function("GPUTextureSupportsFormat", "SDL_GPUTextureSupportsFormat")
export_sdl_function("AcquireGPUCommandBuffer", "SDL_AcquireGPUCommandBuffer")
export_sdl_function("PushGPUVertexUniformData", "SDL_PushGPUVertexUniformData")
export_sdl_function("PushGPUFragmentUniformData", "SDL_PushGPUFragmentUniformData")
export_sdl_function("BeginGPUCopyPass", "SDL_BeginGPUCopyPass")
export_sdl_function("UploadToGPUBuffer", "SDL_UploadToGPUBuffer")
export_sdl_function("EndGPUCopyPass", "SDL_EndGPUCopyPass")
export_sdl_function("WaitAndAcquireGPUSwapchainTexture", "SDL_WaitAndAcquireGPUSwapchainTexture")
export_sdl_function("BeginGPURenderPass", "SDL_BeginGPURenderPass")
export_sdl_function("BindGPUGraphicsPipeline", "SDL_BindGPUGraphicsPipeline")
export_sdl_function("BindGPUVertexBuffers", "SDL_BindGPUVertexBuffers")
export_sdl_function("BindGPUIndexBuffer", "SDL_BindGPUIndexBuffer")
export_sdl_function("DrawGPUPrimitives", "SDL_DrawGPUPrimitives")
export_sdl_function("DrawGPUIndexedPrimitives", "SDL_DrawGPUIndexedPrimitives")
export_sdl_function("EndGPURenderPass", "SDL_EndGPURenderPass")
export_sdl_function("SubmitGPUCommandBuffer", "SDL_SubmitGPUCommandBuffer")
export_sdl_function("WaitForGPUIdle", "SDL_WaitForGPUIdle")

M._window = nil
M._renderer = nil
M._gpu_device = nil
M._owned_init_flags = nil

M.default_window_props = {
   [M.PROP_WINDOW_CREATE_TITLE_STRING] = "rig",
   [M.PROP_WINDOW_CREATE_WIDTH_NUMBER] = 640,
   [M.PROP_WINDOW_CREATE_HEIGHT_NUMBER] = 360,
}

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

local function ensure_creation_hooks()
   local hooks = _G.hooks

   if type(hooks) ~= "table" then
      hooks = {}
      _G.hooks = hooks
   end

   if hooks.sdl_init_flags == nil then
      hooks.sdl_init_flags = M.INIT_VIDEO + M.INIT_EVENTS
   end

   if type(hooks.create_window) ~= "function" then
      hooks.create_window = function()
         local merged_props, merge_error =
            merge_props(M.default_window_props, hooks.window_props)
         if merged_props == nil then
            return nil, merge_error
         end

         local properties_id, props_error = M.build_properties(merged_props)
         if properties_id == nil then
            return nil, props_error
         end

         local window_ptr = M.CreateWindowWithProperties(properties_id)
         M.destroy_properties(properties_id)

         if window_ptr == nil then
            return nil, ffi.string(M.GetError())
         end

         return window_ptr
      end
   end

   if type(hooks.create_renderer) ~= "function" then
      hooks.create_renderer = function(window_ptr)
         local renderer_ptr = M.CreateRenderer(window_ptr, nil)
         if renderer_ptr == nil then
            return nil, ffi.string(M.GetError())
         end

         if not M.SetRenderVSync(renderer_ptr, 1) then
            M.DestroyRenderer(renderer_ptr)
            return nil, ffi.string(M.GetError())
         end

         return renderer_ptr
      end
   end
end

function M.destroy_properties(properties_id)
   if properties_id == nil then
      return
   end
   local props = tonumber(properties_id) or 0
   if props ~= 0 then
      M.DestroyProperties(props)
   end
end

function M.build_properties(props)
   if type(props) ~= "table" then
      return nil, "props must be a table"
   end

   local properties_id = M.CreateProperties()
   if properties_id == 0 then
      return nil, ffi.string(M.GetError())
   end

   for key, value in pairs(props) do
      if type(key) ~= "string" then
         M.destroy_properties(properties_id)
         return nil, "property keys must be strings"
      end

      local ok = true
      if value ~= nil then
         local value_type = type(value)
         if value_type == "boolean" then
            ok = M.SetBooleanProperty(properties_id, key, value)
         elseif value_type == "number" then
            if value == math.floor(value) then
               ok = M.SetNumberProperty(properties_id, key, value)
            else
               ok = M.SetFloatProperty(properties_id, key, value)
            end
         elseif value_type == "string" then
            ok = M.SetStringProperty(properties_id, key, value)
         elseif value_type == "cdata" then
            ok = M.SetPointerProperty(
               properties_id,
               key,
               ffi.cast("void *", value)
            )
         else
            M.destroy_properties(properties_id)
            return nil, ("unsupported property value type for '%s': %s"):format(
               key,
               value_type
            )
         end
      end

      if not ok then
         local error_text = ffi.string(M.GetError())
         M.destroy_properties(properties_id)
         return nil, ("failed to set property '%s': %s"):format(
            key,
            error_text
         )
      end
   end

   return properties_id, nil
end

local function get_error_string()
   return ffi.string(M.GetError())
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
      { M.GPU_SHADERFORMAT_PRIVATE, "PRIVATE" },
      { M.GPU_SHADERFORMAT_SPIRV, "SPIRV" },
      { M.GPU_SHADERFORMAT_DXBC, "DXBC" },
      { M.GPU_SHADERFORMAT_DXIL, "DXIL" },
      { M.GPU_SHADERFORMAT_MSL, "MSL" },
      { M.GPU_SHADERFORMAT_METALLIB, "METALLIB" },
   }

   for _, entry in ipairs(mapping) do
      if has_any_bits(value, entry[1]) then
         names[#names + 1] = entry[2]
      end
   end

   if #names == 0 then
      return tostring(value)
   end
   return table.concat(names, "|")
end

function M.get_gpu_driver_names()
   local count = tonumber(M.GetNumGPUDrivers()) or 0
   local names = {}

   for i = 0, count - 1 do
      local ptr = M.GetGPUDriver(i)
      if ptr ~= nil and ptr ~= ffi.NULL and ptr[0] ~= 0 then
         names[#names + 1] = ffi.string(ptr)
      end
   end

   return names
end

local function build_gpu_support_error(format_flags, backend_name, detail)
   local lines = {}
   lines[#lines + 1] = "no supported SDL_GPU backend is available"
   lines[#lines + 1] = "requested shader formats: "
      .. format_gpu_shader_formats(format_flags)

   if backend_name ~= nil then
      lines[#lines + 1] = "requested backend: " .. tostring(backend_name)
   else
      lines[#lines + 1] = "requested backend: automatic"
   end

   local driver_names = M.get_gpu_driver_names()
   if #driver_names > 0 then
      lines[#lines + 1] = "SDL compiled GPU drivers: "
         .. table.concat(driver_names, ", ")
   else
      lines[#lines + 1] = "SDL compiled GPU drivers: none reported"
   end

   if detail ~= nil and detail ~= "" then
      lines[#lines + 1] = "SDL error: " .. tostring(detail)
   end

   if has_any_bits(format_flags, M.GPU_SHADERFORMAT_SPIRV) then
      lines[#lines + 1] =
         "SPIR-V requires a Vulkan-capable SDL_GPU backend."
      lines[#lines + 1] =
         "Check that a Vulkan ICD is installed and that the GPU exposes enough Vulkan support."
      lines[#lines + 1] =
         "Older Intel Haswell GPUs often expose only incomplete Vulkan support through Mesa hasvk and may still be rejected by SDL_GPU."
   end

   return table.concat(lines, "\n")
end

local function format_hook_error(hook_name, detail, fallback)
   if detail == nil then
      return ("%s failed: %s"):format(hook_name, fallback)
   end
   return ("%s failed: %s"):format(hook_name, tostring(detail))
end

local function normalize_init_flags(flags_number)
   if type(flags_number) ~= "number" then
      error("hooks.sdl_init_flags must be a number")
   end

   local flags_integer = math.floor(flags_number)
   if flags_number < 0.0 or flags_number ~= flags_integer then
      error("hooks.sdl_init_flags must be a non-negative integer")
   end
   if flags_number > 4294967295.0 then
      error("hooks.sdl_init_flags exceeds Uint32 range")
   end

   return ffi.cast("Uint32", flags_integer)
end

function M.get_window()
   return M._window
end

function M.get_gpu_device()
   return M._gpu_device
end

function M.setup()
   if M._renderer ~= nil or M._window ~= nil or M._gpu_device ~= nil then
      M.shutdown()
   end

   ensure_creation_hooks()

   local hooks = _G.hooks
   local required = normalize_init_flags(hooks.sdl_init_flags)
   local initialized = M.WasInit(required)
   local owned_init_flags = nil

   if not has_all_bits(initialized, required) then
      if not M.Init(required) then
         error("failed to initialize SDL: " .. get_error_string())
      end
      owned_init_flags = required
   end

   local create_window = hooks.create_window
   if type(create_window) ~= "function" then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error("hooks.create_window is not available")
   end

   local create_renderer = hooks.create_renderer
   if type(create_renderer) ~= "function" then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error("hooks.create_renderer is not available")
   end

   local window_ptr, window_err = create_window()
   if window_ptr == nil then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
         error(format_hook_error(
            "hooks.create_window",
            window_err,
            "expected SDL_Window* cdata"
         ))
   end
   if type(window_ptr) ~= "cdata" then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error("hooks.create_window must return SDL_Window* cdata")
   end

   local renderer_ptr, renderer_err = create_renderer(window_ptr)
   if renderer_ptr == nil then
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
         error(format_hook_error(
            "hooks.create_renderer",
            renderer_err,
            "expected SDL_Renderer* cdata"
         ))
   end
   if type(renderer_ptr) ~= "cdata" then
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error("hooks.create_renderer must return SDL_Renderer* cdata")
   end

   M._window = window_ptr
   M._renderer = renderer_ptr
   M._owned_init_flags = owned_init_flags
end

function M.setup_gpu(options)
   if options ~= nil and type(options) ~= "table" then
      error("sdl3.setup_gpu expects a table if options are provided")
   end

   if M._renderer ~= nil or M._window ~= nil or M._gpu_device ~= nil then
      M.shutdown()
   end

   ensure_creation_hooks()

   local hooks = _G.hooks
   local required = normalize_init_flags(hooks.sdl_init_flags)
   local initialized = M.WasInit(required)
   local owned_init_flags = nil

   if not has_all_bits(initialized, required) then
      if not M.Init(required) then
         error("failed to initialize SDL: " .. get_error_string())
      end
      owned_init_flags = required
   end

   local create_window = hooks.create_window
   if type(create_window) ~= "function" then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error("hooks.create_window is not available")
   end

   local window_ptr, window_err = create_window()
   if window_ptr == nil then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error(format_hook_error(
         "hooks.create_window",
         window_err,
         "expected SDL_Window* cdata"
      ))
   end
   if type(window_ptr) ~= "cdata" then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error("hooks.create_window must return SDL_Window* cdata")
   end

   local format_flags = options and options.shader_formats
   if format_flags == nil then
      format_flags = M.GPU_SHADERFORMAT_SPIRV
   end
   local debug_mode = options and options.debug_mode and true or false
   local backend_name = options and options.backend_name or nil

   if not M.GPUSupportsShaderFormats(format_flags, backend_name) then
      error(build_gpu_support_error(
         format_flags,
         backend_name,
         get_error_string()
      ))
   end

   local gpu_device = M.CreateGPUDevice(format_flags, debug_mode, backend_name)
   if gpu_device == nil then
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error(build_gpu_support_error(
         format_flags,
         backend_name,
         get_error_string()
      ))
   end

   if not M.ClaimWindowForGPUDevice(gpu_device, window_ptr) then
      M.DestroyGPUDevice(gpu_device)
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error("failed to claim SDL window for GPU device: " .. get_error_string())
   end

   M._window = window_ptr
   M._gpu_device = gpu_device
   M._owned_init_flags = owned_init_flags
end

function M.shutdown()
   if M._gpu_device ~= nil then
      M.WaitForGPUIdle(M._gpu_device)
      if M._window ~= nil then
         M.ReleaseWindowFromGPUDevice(M._gpu_device, M._window)
      end
      M.DestroyGPUDevice(M._gpu_device)
      M._gpu_device = nil
   end
   if M._renderer ~= nil then
      M.DestroyRenderer(M._renderer)
      M._renderer = nil
   end
   if M._window ~= nil then
      M.DestroyWindow(M._window)
      M._window = nil
   end
   if M._owned_init_flags ~= nil then
      M.QuitSubSystem(M._owned_init_flags)
      M._owned_init_flags = nil
   end
end

function M.present()
   if M._renderer == nil then
      error("SDL renderer is not initialized")
   end
   if not M.RenderPresent(M._renderer) then
      error("failed to present renderer: " .. ffi.string(M.GetError()))
   end
end

function M.upload_to_gpu_buffer(device, buffer, data)
   if device == nil then
      error("sdl3.upload_to_gpu_buffer requires an SDL_GPUDevice*")
   end
   if buffer == nil then
      error("sdl3.upload_to_gpu_buffer requires an SDL_GPUBuffer*")
   end
   if type(data) ~= "string" then
      error("sdl3.upload_to_gpu_buffer requires data to be a string")
   end

   local transfer_info = ffi.new("SDL_GPUTransferBufferCreateInfo[1]")
   transfer_info[0].usage = M.GPU_TRANSFERBUFFERUSAGE_UPLOAD
   transfer_info[0].size = #data
   transfer_info[0].props = 0

   local transfer_buffer = M.CreateGPUTransferBuffer(device, transfer_info)
   if transfer_buffer == nil then
      return nil, "failed to create GPU transfer buffer: " .. get_error_string()
   end

   local mapped = M.MapGPUTransferBuffer(device, transfer_buffer, false)
   if mapped == nil then
      M.ReleaseGPUTransferBuffer(device, transfer_buffer)
      return nil, "failed to map GPU transfer buffer: " .. get_error_string()
   end
   ffi.copy(mapped, data, #data)
   M.UnmapGPUTransferBuffer(device, transfer_buffer)

   local command_buffer = M.AcquireGPUCommandBuffer(device)
   if command_buffer == nil then
      M.ReleaseGPUTransferBuffer(device, transfer_buffer)
      return nil, "failed to acquire GPU command buffer: " .. get_error_string()
   end

   local copy_pass = M.BeginGPUCopyPass(command_buffer)
   local source = ffi.new("SDL_GPUTransferBufferLocation[1]")
   source[0].transfer_buffer = transfer_buffer
   source[0].offset = 0

   local destination = ffi.new("SDL_GPUBufferRegion[1]")
   destination[0].buffer = buffer
   destination[0].offset = 0
   destination[0].size = #data

   M.UploadToGPUBuffer(copy_pass, source, destination, false)
   M.EndGPUCopyPass(copy_pass)

   if not M.SubmitGPUCommandBuffer(command_buffer) then
      M.ReleaseGPUTransferBuffer(device, transfer_buffer)
      return nil, "failed to submit GPU upload command buffer: " .. get_error_string()
   end

   M.ReleaseGPUTransferBuffer(device, transfer_buffer)
   return true
end

function M.choose_depth_format(device)
   local candidates = {
      M.GPU_TEXTUREFORMAT_D32_FLOAT,
      M.GPU_TEXTUREFORMAT_D24_UNORM,
      M.GPU_TEXTUREFORMAT_D16_UNORM,
   }

   for _, format in ipairs(candidates) do
      if M.GPUTextureSupportsFormat(
         device,
         format,
         M.GPU_TEXTURETYPE_2D,
         M.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET
      ) then
         return format
      end
   end

   return nil, "no supported depth texture format found"
end

function M.create_depth_texture(device, width, height, format)
   if format == nil then
      local chosen, err = M.choose_depth_format(device)
      if chosen == nil then
         return nil, err
      end
      format = chosen
   end

   local create_info = ffi.new("SDL_GPUTextureCreateInfo[1]")
   create_info[0].type = M.GPU_TEXTURETYPE_2D
   create_info[0].format = format
   create_info[0].usage = M.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET
   create_info[0].width = width
   create_info[0].height = height
   create_info[0].layer_count_or_depth = 1
   create_info[0].num_levels = 1
   create_info[0].sample_count = M.GPU_SAMPLECOUNT_1
   create_info[0].props = 0

   local texture = M.CreateGPUTexture(device, create_info)
   if texture == nil then
      return nil, "failed to create GPU depth texture: " .. get_error_string()
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
   local renderer_ptr = M._renderer

   if renderer_ptr == nil then
      error("sdl3.clear requires an active SDL renderer")
   end

   local renderer = ffi.cast("SDL_Renderer *", renderer_ptr)
   local rr = color_component(r, 0)
   local gg = color_component(g, 0)
   local bb = color_component(b, 0)
   local aa = color_component(a, 1)

   if not M.SetRenderDrawColor(renderer, rr, gg, bb, aa) then
      error("failed to set draw color: " .. ffi.string(M.GetError()))
   end
   if not M.RenderClear(renderer) then
      error("failed to clear render target: " .. ffi.string(M.GetError()))
   end
end

local function dispatch_keyboard_event(event)
   local hooks = _G.hooks
   local handler = hooks.handle_key
   if type(handler) ~= "function" then
      return
   end

   local key_name = M.GetKeyName(event.key)
   local key = "Unknown"
   local mods = tonumber(event.mod) or 0
   local timestamp_ns = tonumber(event.timestamp) or 0

   if key_name ~= nil and key_name[0] ~= 0 then
      key = ffi.string(key_name)
   end

   handler({
      type = "key",
      action = event.down and "down" or "up",
      key = key,
      code = tonumber(event.key),
      scancode = tonumber(event.scancode),
      ["repeat"] = event["repeat"] and true or false,
      timestamp_ns = timestamp_ns,
      timestamp_ms = math.floor(timestamp_ns / 1000000),
      mods = {
         shift = has_any_bits(mods, M.KMOD_SHIFT),
         ctrl = has_any_bits(mods, M.KMOD_CTRL),
         alt = has_any_bits(mods, M.KMOD_ALT),
         super = has_any_bits(mods, M.KMOD_GUI),
      },
   })
end

function M.pump_events()
   if M._window == nil then
      error("an SDL window must be initialized before sdl3.pump_events")
   end

   local event = ffi.new("SDL_Event[1]")
   while M.PollEvent(event) do
      local current = event[0]
      local event_type = tonumber(current.type) or 0

      if event_type == SDL_EVENT_QUIT then
         return false
      end

      if event_type == SDL_EVENT_KEY_DOWN or event_type == SDL_EVENT_KEY_UP then
         dispatch_keyboard_event(current.key)
      end
   end

   return true
end

function M.render_frame()
   local hooks = _G.hooks
   local handler = hooks.render
   if type(handler) ~= "function" then
      return false
   end

   handler()
   M.present()
   return true
end

function M.run()
   local hooks = _G.hooks
   if type(hooks.render) ~= "function" then
      error("hooks.render must be a function before calling sdl3.run")
   end

   M.setup()

   local ok, err = pcall(function()
      while M.pump_events() do
         M.render_frame()
      end
   end)

   M.shutdown()

   if not ok then
      error(err, 0)
   end
end

return M
