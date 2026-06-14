local M = ... or {}
local color = require("color")
local ffi = require("ffi")
local bit = bit
local rig = require("rig")
local sched = require("sched")
local schema = require("schema")
require("font")
require("mesh")
local shader = require("shader")
require("time")

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

ffi.cdef[[
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct SDL_Texture SDL_Texture;
typedef struct SDL_Rect SDL_Rect;
typedef unsigned char Uint8;
typedef uint16_t Uint16;
typedef uint32_t Uint32;
typedef uint64_t Uint64;
typedef int32_t Sint32;
typedef int64_t Sint64;
typedef void* SDL_GLContext;
typedef uint32_t SDL_EventType;
typedef uint32_t SDL_DisplayID;
typedef uint32_t SDL_WindowID;
typedef uint32_t SDL_KeyboardID;
typedef uint32_t SDL_MouseID;
typedef int32_t SDL_Scancode;
typedef uint32_t SDL_Keycode;
typedef uint16_t SDL_Keymod;
typedef uint32_t SDL_PropertiesID;
typedef int SDL_GLAttr;
typedef Uint32 SDL_PixelFormat;
typedef Uint32 SDL_TextureAccess;
typedef Uint32 SDL_BlendMode;
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
typedef struct SDL_WindowEvent {
   SDL_EventType type;
   Uint32 reserved;
   Uint64 timestamp;
   SDL_WindowID windowID;
   Sint32 data1;
   Sint32 data2;
} SDL_WindowEvent;
typedef struct SDL_QuitEvent {
   SDL_EventType type;
   Uint32 reserved;
   Uint64 timestamp;
} SDL_QuitEvent;
typedef struct SDL_MouseMotionEvent {
   SDL_EventType type;
   Uint32 reserved;
   Uint64 timestamp;
   SDL_WindowID windowID;
   SDL_MouseID which;
   Uint32 state;
   float x;
   float y;
   float xrel;
   float yrel;
} SDL_MouseMotionEvent;
typedef struct SDL_MouseButtonEvent {
   SDL_EventType type;
   Uint32 reserved;
   Uint64 timestamp;
   SDL_WindowID windowID;
   SDL_MouseID which;
   Uint8 button;
   bool down;
   Uint8 clicks;
   Uint8 padding;
   float x;
   float y;
} SDL_MouseButtonEvent;
typedef union SDL_Event {
   Uint32 type;
   SDL_WindowEvent window;
   SDL_KeyboardEvent key;
   SDL_QuitEvent quit;
   SDL_MouseMotionEvent motion;
   SDL_MouseButtonEvent button;
   Uint8 padding[128];
} SDL_Event;
bool SDL_SetRenderDrawColor(SDL_Renderer *renderer, Uint8 r, Uint8 g, Uint8 b, Uint8 a);
bool SDL_RenderClear(SDL_Renderer *renderer);
bool SDL_RenderPoint(SDL_Renderer *renderer, float x, float y);
bool SDL_RenderLine(SDL_Renderer *renderer, float x1, float y1, float x2, float y2);
bool SDL_RenderFillRect(SDL_Renderer *renderer, const struct SDL_FRect *rect);
SDL_Texture *SDL_CreateTexture(SDL_Renderer *renderer, SDL_PixelFormat format, SDL_TextureAccess access, int w, int h);
bool SDL_UpdateTexture(SDL_Texture *texture, const SDL_Rect *rect, const void *pixels, int pitch);
bool SDL_SetTextureColorMod(SDL_Texture *texture, Uint8 r, Uint8 g, Uint8 b);
bool SDL_SetTextureAlphaMod(SDL_Texture *texture, Uint8 alpha);
bool SDL_SetTextureBlendMode(SDL_Texture *texture, SDL_BlendMode blendMode);
bool SDL_RenderTexture(SDL_Renderer *renderer, SDL_Texture *texture, const struct SDL_FRect *srcrect, const struct SDL_FRect *dstrect);
void SDL_DestroyTexture(SDL_Texture *texture);
SDL_Window *SDL_CreateWindowWithProperties(SDL_PropertiesID props);
SDL_Renderer *SDL_CreateRenderer(SDL_Window *window, const char *name);
SDL_DisplayID SDL_GetPrimaryDisplay(void);
bool SDL_GetDisplayUsableBounds(SDL_DisplayID displayID, SDL_Rect *rect);
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
Uint32 SDL_GetMouseState(float *x, float *y);
bool SDL_GetWindowSize(SDL_Window *window, int *w, int *h);
bool SDL_GetWindowSizeInPixels(SDL_Window *window, int *w, int *h);
bool SDL_SetWindowFullscreen(SDL_Window *window, bool fullscreen);
bool SDL_SyncWindow(SDL_Window *window);
const char *SDL_GetError(void);
const char *SDL_GetKeyName(SDL_Keycode key);
bool SDL_GetCurrentTime(Sint64 *ticks);
Uint64 SDL_GetTicks(void);
Uint64 SDL_GetTicksNS(void);
Uint64 SDL_GetPerformanceCounter(void);
Uint64 SDL_GetPerformanceFrequency(void);
void SDL_Delay(Uint32 ms);
void SDL_DelayNS(Uint64 ns);
void SDL_DelayPrecise(Uint64 ns);
void SDL_GL_ResetAttributes(void);
bool SDL_GL_SetAttribute(SDL_GLAttr attr, int value);
SDL_GLContext SDL_GL_CreateContext(SDL_Window *window);
bool SDL_GL_MakeCurrent(SDL_Window *window, SDL_GLContext context);
bool SDL_GL_SetSwapInterval(int interval);
bool SDL_GL_SwapWindow(SDL_Window *window);
bool SDL_GL_DestroyContext(SDL_GLContext context);
void *SDL_GL_GetProcAddress(const char *proc);
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
typedef struct SDL_FRect {
   float x;
   float y;
   float w;
   float h;
} SDL_FRect;
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

local sdl_library = nil
local sdl_library_error = nil

local function load_sdl_library()
   if sdl_library ~= nil then
      return sdl_library
   end
   if sdl_library_error ~= nil then
      rig.raise(sdl_library_error)
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
      table.insert(failures, tostring(lib))
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
export_sdl_function("RenderPoint", "SDL_RenderPoint")
export_sdl_function("RenderLine", "SDL_RenderLine")
export_sdl_function("RenderFillRect", "SDL_RenderFillRect")
export_sdl_function("CreateTexture", "SDL_CreateTexture")
export_sdl_function("UpdateTexture", "SDL_UpdateTexture")
export_sdl_function("SetTextureColorMod", "SDL_SetTextureColorMod")
export_sdl_function("SetTextureAlphaMod", "SDL_SetTextureAlphaMod")
export_sdl_function("SetTextureBlendMode", "SDL_SetTextureBlendMode")
export_sdl_function("RenderTexture", "SDL_RenderTexture")
export_sdl_function("DestroyTexture", "SDL_DestroyTexture")
export_sdl_function("CreateWindowWithProperties", "SDL_CreateWindowWithProperties")
export_sdl_function("CreateRenderer", "SDL_CreateRenderer")
export_sdl_function("GetPrimaryDisplay", "SDL_GetPrimaryDisplay")
export_sdl_function("GetDisplayUsableBounds", "SDL_GetDisplayUsableBounds")
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
export_sdl_function("GetMouseState", "SDL_GetMouseState")
export_sdl_function("GetWindowSize", "SDL_GetWindowSize")
export_sdl_function("GetWindowSizeInPixels", "SDL_GetWindowSizeInPixels")
export_sdl_function("SetWindowFullscreen", "SDL_SetWindowFullscreen")
export_sdl_function("SyncWindow", "SDL_SyncWindow")
export_sdl_function("GetError", "SDL_GetError")
export_sdl_function("GetKeyName", "SDL_GetKeyName")
export_sdl_function("GetCurrentTime", "SDL_GetCurrentTime")
export_sdl_function("GetTicks", "SDL_GetTicks")
export_sdl_function("GetTicksNS", "SDL_GetTicksNS")
export_sdl_function("GetPerformanceCounter", "SDL_GetPerformanceCounter")
export_sdl_function("GetPerformanceFrequency", "SDL_GetPerformanceFrequency")
export_sdl_function("Delay", "SDL_Delay")
export_sdl_function("DelayNS", "SDL_DelayNS")
export_sdl_function("DelayPrecise", "SDL_DelayPrecise")
export_sdl_function("GL_ResetAttributes", "SDL_GL_ResetAttributes")
export_sdl_function("GL_SetAttribute", "SDL_GL_SetAttribute")
export_sdl_function("GL_CreateContext", "SDL_GL_CreateContext")
export_sdl_function("GL_MakeCurrent", "SDL_GL_MakeCurrent")
export_sdl_function("GL_SetSwapInterval", "SDL_GL_SetSwapInterval")
export_sdl_function("GL_SwapWindow", "SDL_GL_SwapWindow")
export_sdl_function("GL_DestroyContext", "SDL_GL_DestroyContext")
export_sdl_function("GL_GetProcAddress", "SDL_GL_GetProcAddress")
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
local event_handlers_schema = schema.record({
   key = schema.func():optional(),
   mouse = schema.func():optional(),
   resize = schema.func():optional(),
})

local DEFAULT_WINDOW_WIDTH = 640
local DEFAULT_WINDOW_HEIGHT = 360

M.default_window_props = {
   [M.PROP_WINDOW_CREATE_TITLE_STRING] = "rig",
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

local function default_create_window(options)
   local merged_props, merge_error =
      merge_props(M.default_window_props, options.window_props)
   if merged_props == nil then
      return nil, merge_error
   end

   local width_key = M.PROP_WINDOW_CREATE_WIDTH_NUMBER
   local height_key = M.PROP_WINDOW_CREATE_HEIGHT_NUMBER
   if merged_props[width_key] == nil or merged_props[height_key] == nil then
      local default_width = DEFAULT_WINDOW_WIDTH
      local default_height = DEFAULT_WINDOW_HEIGHT
      local primary_display = M.GetPrimaryDisplay()
      if primary_display ~= nil and primary_display ~= 0 then
         local usable_bounds = ffi.new("SDL_Rect[1]")
         if M.GetDisplayUsableBounds(primary_display, usable_bounds) then
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

      if merged_props[width_key] == nil then
         merged_props[width_key] = default_width
      end
      if merged_props[height_key] == nil then
         merged_props[height_key] = default_height
      end
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

local function default_create_renderer(window_ptr)
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

local VERTEX_INPUT_RATES = {
   vertex = M.GPU_VERTEXINPUTRATE_VERTEX,
   instance = M.GPU_VERTEXINPUTRATE_INSTANCE,
}

local VERTEX_ATTRIBUTE_FORMATS = {
   float = M.GPU_VERTEXELEMENTFORMAT_FLOAT,
   float2 = M.GPU_VERTEXELEMENTFORMAT_FLOAT2,
   float3 = M.GPU_VERTEXELEMENTFORMAT_FLOAT3,
   float4 = M.GPU_VERTEXELEMENTFORMAT_FLOAT4,
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

local GPUVertexBufferDescription = ffi.metatype("SDL_GPUVertexBufferDescription", {
   __new = function(ct, spec)
      if type(spec) ~= "table" then
         rig.raise("vertex buffer descriptions must be tables")
      end

      local description = ffi.new(ct)
      description.slot = tonumber(spec.slot or 0) or 0
      description.pitch =
         assert(tonumber(spec.pitch), "vertex buffer pitch must be a number")
      description.input_rate = normalize_vertex_input_rate(
         spec.input_rate or "vertex"
      )
      description.instance_step_rate =
         tonumber(spec.instance_step_rate or 0) or 0
      return description
   end,
})

local GPUVertexAttribute = ffi.metatype("SDL_GPUVertexAttribute", {
   __new = function(ct, spec)
      if type(spec) ~= "table" then
         rig.raise("vertex attributes must be tables")
      end

      local attribute = ffi.new(ct)
      attribute.location =
         assert(tonumber(spec.location), "vertex attribute location must be a number")
      attribute.buffer_slot =
         tonumber(spec.buffer_slot or spec.slot or 0) or 0
      attribute.format = normalize_vertex_attribute_format(spec.format)
      attribute.offset =
         assert(tonumber(spec.offset), "vertex attribute offset must be a number")
      return attribute
   end,
})

local GPUBufferCreateInfo = ffi.metatype("SDL_GPUBufferCreateInfo", {
   __new = function(ct, spec)
      if type(spec) ~= "table" then
         rig.raise("sdl3.build_gpu_buffer_create_info expects a table")
      end

      local create_info = ffi.new(ct)
      create_info.usage =
         assert(tonumber(spec.usage), "GPU buffer usage must be a number")
      create_info.size =
         assert(tonumber(spec.size), "GPU buffer size must be a number")
      create_info.props = tonumber(spec.props or 0) or 0
      return create_info
   end,
})

local function apply_color_target_blend_state(state, blend_state)
   if type(blend_state) ~= "table" then
      return
   end

   if blend_state.src_color_blendfactor ~= nil then
      state.src_color_blendfactor =
         tonumber(blend_state.src_color_blendfactor) or 0
   end
   if blend_state.dst_color_blendfactor ~= nil then
      state.dst_color_blendfactor =
         tonumber(blend_state.dst_color_blendfactor) or 0
   end
   if blend_state.color_blend_op ~= nil then
      state.color_blend_op = tonumber(blend_state.color_blend_op) or 0
   end
   if blend_state.src_alpha_blendfactor ~= nil then
      state.src_alpha_blendfactor =
         tonumber(blend_state.src_alpha_blendfactor) or 0
   end
   if blend_state.dst_alpha_blendfactor ~= nil then
      state.dst_alpha_blendfactor =
         tonumber(blend_state.dst_alpha_blendfactor) or 0
   end
   if blend_state.alpha_blend_op ~= nil then
      state.alpha_blend_op = tonumber(blend_state.alpha_blend_op) or 0
   end
   if blend_state.color_write_mask ~= nil then
      state.color_write_mask = tonumber(blend_state.color_write_mask) or 0
   end
   if blend_state.enable_blend ~= nil then
      state.enable_blend = not not blend_state.enable_blend
   end
   if blend_state.enable_color_write_mask ~= nil then
      state.enable_color_write_mask =
         not not blend_state.enable_color_write_mask
   end
end

local GPUColorTargetDescription = ffi.metatype("SDL_GPUColorTargetDescription", {
   __new = function(ct, spec)
      if type(spec) ~= "table" then
         rig.raise("color target descriptions must be tables")
      end

      local description = ffi.new(ct)
      description.format =
         assert(tonumber(spec.format), "color target format must be a number")
      apply_color_target_blend_state(
         description.blend_state,
         spec.blend_state
      )
      return description
   end,
})

local STAGE_TO_SDL = {
   vertex = M.GPU_SHADERSTAGE_VERTEX,
   fragment = M.GPU_SHADERSTAGE_FRAGMENT,
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

function M.build_vertex_buffer_descriptions(buffers)
   if type(buffers) ~= "table" then
      error("sdl3.build_vertex_buffer_descriptions expects a table")
   end

   local descriptions = ffi.new("SDL_GPUVertexBufferDescription[?]", #buffers)
   for i, buffer in ipairs(buffers) do
      local spec = {}
      for key, value in pairs(buffer) do
         spec[key] = value
      end
      if spec.slot == nil then
         spec.slot = i - 1
      end
      descriptions[i - 1] = GPUVertexBufferDescription(spec)
   end

   return descriptions
end

function M.build_vertex_attributes(attributes)
   if type(attributes) ~= "table" then
      error("sdl3.build_vertex_attributes expects a table")
   end

   local ffi_attributes = ffi.new("SDL_GPUVertexAttribute[?]", #attributes)
   for i, attribute in ipairs(attributes) do
      ffi_attributes[i - 1] = GPUVertexAttribute(attribute)
   end

   return ffi_attributes
end

function M.build_vertex_input_state(layout)
   if type(layout) ~= "table" then
      error("sdl3.build_vertex_input_state expects a table")
   end
   if type(layout.buffers) ~= "table" then
      error("sdl3.build_vertex_input_state requires a buffers table")
   end

   local attribute_specs = {}
   for i, buffer in ipairs(layout.buffers) do
      if type(buffer) ~= "table" then
         rig.raise("vertex input buffers must be tables")
      end
      local buffer_slot = tonumber(buffer.slot or (i - 1)) or 0
      local attributes = buffer.attributes
      if type(attributes) ~= "table" then
         rig.raise("each vertex input buffer requires an attributes table")
      end
      for _, attribute in ipairs(attributes) do
         local spec = {}
         for key, value in pairs(attribute) do
            spec[key] = value
         end
         spec.buffer_slot = buffer_slot
         table.insert(attribute_specs, spec)
      end
   end

   local descriptions = M.build_vertex_buffer_descriptions(layout.buffers)
   local attributes = M.build_vertex_attributes(attribute_specs)
   local state = ffi.new("SDL_GPUVertexInputState[1]")
   state[0].vertex_buffer_descriptions = descriptions
   state[0].num_vertex_buffers = #layout.buffers
   state[0].vertex_attributes = attributes
   state[0].num_vertex_attributes = #attribute_specs

   return {
      state = state,
      vertex_buffer_descriptions = descriptions,
      vertex_attributes = attributes,
   }
end

function M.build_gpu_buffer_create_info(spec)
   local create_info = ffi.new("SDL_GPUBufferCreateInfo[1]")
   create_info[0] = GPUBufferCreateInfo(spec)
   return create_info
end

function M.build_color_target_descriptions(specs)
   if type(specs) ~= "table" then
      rig.raise("sdl3.build_color_target_descriptions expects a table")
   end

   local descriptions = ffi.new("SDL_GPUColorTargetDescription[?]", #specs)
   for i, spec in ipairs(specs) do
      descriptions[i - 1] = GPUColorTargetDescription(spec)
   end

   return descriptions
end

function M.build_graphics_pipeline_create_info(spec)
   if type(spec) ~= "table" then
      rig.raise("sdl3.build_graphics_pipeline_create_info expects a table")
   end

   local create_info = ffi.new("SDL_GPUGraphicsPipelineCreateInfo[1]")
   create_info[0].vertex_shader = spec.vertex_shader
   create_info[0].fragment_shader = spec.fragment_shader
   create_info[0].primitive_type =
      assert(tonumber(spec.primitive_type), "graphics pipeline primitive_type must be a number")

   local vertex_input = spec.vertex_input
   if vertex_input ~= nil then
      if type(vertex_input) == "table" and vertex_input.state ~= nil then
         create_info[0].vertex_input_state = vertex_input.state[0]
      else
         create_info[0].vertex_input_state = vertex_input
      end
   end

   local rasterizer_state = spec.rasterizer_state
   if type(rasterizer_state) == "table" then
      local state = create_info[0].rasterizer_state
      if rasterizer_state.fill_mode ~= nil then
         state.fill_mode = tonumber(rasterizer_state.fill_mode) or 0
      end
      if rasterizer_state.cull_mode ~= nil then
         state.cull_mode = tonumber(rasterizer_state.cull_mode) or 0
      end
      if rasterizer_state.front_face ~= nil then
         state.front_face = tonumber(rasterizer_state.front_face) or 0
      end
      if rasterizer_state.depth_bias_constant_factor ~= nil then
         state.depth_bias_constant_factor =
            tonumber(rasterizer_state.depth_bias_constant_factor) or 0
      end
      if rasterizer_state.depth_bias_clamp ~= nil then
         state.depth_bias_clamp =
            tonumber(rasterizer_state.depth_bias_clamp) or 0
      end
      if rasterizer_state.depth_bias_slope_factor ~= nil then
         state.depth_bias_slope_factor =
            tonumber(rasterizer_state.depth_bias_slope_factor) or 0
      end
      if rasterizer_state.enable_depth_bias ~= nil then
         state.enable_depth_bias = not not rasterizer_state.enable_depth_bias
      end
      if rasterizer_state.enable_depth_clip ~= nil then
         state.enable_depth_clip = not not rasterizer_state.enable_depth_clip
      end
   end

   local multisample_state = spec.multisample_state
   if type(multisample_state) == "table" then
      local state = create_info[0].multisample_state
      if multisample_state.sample_count ~= nil then
         state.sample_count = tonumber(multisample_state.sample_count) or 0
      end
      if multisample_state.sample_mask ~= nil then
         state.sample_mask = tonumber(multisample_state.sample_mask) or 0
      end
      if multisample_state.enable_mask ~= nil then
         state.enable_mask = not not multisample_state.enable_mask
      end
      if multisample_state.enable_alpha_to_coverage ~= nil then
         state.enable_alpha_to_coverage =
            not not multisample_state.enable_alpha_to_coverage
      end
   end

   local depth_stencil_state = spec.depth_stencil_state
   if type(depth_stencil_state) == "table" then
      local state = create_info[0].depth_stencil_state
      if depth_stencil_state.compare_op ~= nil then
         state.compare_op = tonumber(depth_stencil_state.compare_op) or 0
      end
      if depth_stencil_state.enable_depth_test ~= nil then
         state.enable_depth_test = not not depth_stencil_state.enable_depth_test
      end
      if depth_stencil_state.enable_depth_write ~= nil then
         state.enable_depth_write = not not depth_stencil_state.enable_depth_write
      end
      if depth_stencil_state.enable_stencil_test ~= nil then
         state.enable_stencil_test = not not depth_stencil_state.enable_stencil_test
      end
      if depth_stencil_state.compare_mask ~= nil then
         state.compare_mask = tonumber(depth_stencil_state.compare_mask) or 0
      end
      if depth_stencil_state.write_mask ~= nil then
         state.write_mask = tonumber(depth_stencil_state.write_mask) or 0
      end
   end

   local color_target_descriptions = nil
   local target_info = spec.target_info
   if type(target_info) == "table" then
      if type(target_info.color_target_descriptions) == "table" then
         color_target_descriptions =
            M.build_color_target_descriptions(target_info.color_target_descriptions)
         create_info[0].target_info.color_target_descriptions =
            color_target_descriptions
         create_info[0].target_info.num_color_targets =
            #target_info.color_target_descriptions
      end
      if target_info.depth_stencil_format ~= nil then
         create_info[0].target_info.depth_stencil_format =
            tonumber(target_info.depth_stencil_format) or 0
      end
      if target_info.has_depth_stencil_target ~= nil then
         create_info[0].target_info.has_depth_stencil_target =
            not not target_info.has_depth_stencil_target
      end
   end

   create_info[0].props = tonumber(spec.props or 0) or 0

   return {
      create_info = create_info,
      color_target_descriptions = color_target_descriptions,
   }
end

local function normalize_gpu_shader_format(compiled)
   local format = compiled.format
   if format == nil or format == "spirv" then
      return M.GPU_SHADERFORMAT_SPIRV
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
   if normalize_gpu_shader_format(compiled) ~= M.GPU_SHADERFORMAT_SPIRV then
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
      rig.raise("sdl3.create_gpu_shader requires an SDL_GPUDevice*")
   end
   if type(compiled) ~= "table" then
      error("sdl3.create_gpu_shader requires a compiled shader table")
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
   create_info[0].props = props or 0

   local shader_handle = M.CreateGPUShader(device, create_info)
   if shader_handle == nil then
      rig.raise(ffi.string(M.GetError()))
   end

   return shader_handle
end

local function get_error_string()
   return ffi.string(M.GetError())
end

local sdl3_resource_scope_methods = {}

function sdl3_resource_scope_methods:create_gpu_shader(compiled, props)
   local shader = M.create_gpu_shader(self.context, compiled, props)
   return self:adopt(shader, function(device, resource)
      M.ReleaseGPUShader(device, resource)
   end)
end

function sdl3_resource_scope_methods:create_gpu_buffer(create_info)
   local normalized = create_info
   if type(create_info) == "table" then
      normalized = M.build_gpu_buffer_create_info(create_info)
   end

   local buffer = M.CreateGPUBuffer(self.context, normalized)
   if buffer == nil then
      rig.raise("failed to create GPU buffer: " .. get_error_string())
   end

   return self:adopt(buffer, function(device, resource)
      M.ReleaseGPUBuffer(device, resource)
   end)
end

function sdl3_resource_scope_methods:create_graphics_pipeline(create_info)
   local normalized = create_info
   if type(create_info) == "table" then
      local bundle = M.build_graphics_pipeline_create_info(create_info)
      normalized = bundle.create_info
   end

   local pipeline = M.CreateGPUGraphicsPipeline(self.context, normalized)
   if pipeline == nil then
      rig.raise("failed to create GPU graphics pipeline: " .. get_error_string())
   end

   return self:adopt(pipeline, function(device, resource)
      M.ReleaseGPUGraphicsPipeline(device, resource)
   end)
end

function sdl3_resource_scope_methods:create_depth_texture(width, height, format)
   local texture, chosen_format =
      M.create_depth_texture(self.context, width, height, format)
   self:adopt(texture, function(device, resource)
      M.ReleaseGPUTexture(device, resource)
   end)
   return texture, chosen_format
end

function M.resource_scope(device)
   if device == nil then
      rig.raise("sdl3.resource_scope requires an SDL_GPUDevice*")
   end

   local scope = rig.ResourceScope(device, "sdl3 resource scope")
   for name, method in pairs(sdl3_resource_scope_methods) do
      scope[name] = method
   end
   return scope
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
         table.insert(names, entry[2])
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

   if has_any_bits(format_flags, M.GPU_SHADERFORMAT_SPIRV) then
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

local function get_event_handlers(options)
   local event_handlers = options.event_handlers
   if event_handlers == nil then
      return {}
   end
   return schema.assert(
      event_handlers_schema,
      event_handlers,
      "rig.run options.event_handlers"
   )
end

local shutdown
local destroy_gl_font_backend_state
local window_size_width = ffi.new("int[1]")
local window_size_height = ffi.new("int[1]")
local gl_font_vertex_arrays = ffi.new("unsigned int[1]")
local gl_font_buffers = ffi.new("unsigned int[1]")
local gl_font_textures = ffi.new("unsigned int[1]")
local gl_font_quad_vertices = ffi.new("float[24]")
local gl_font_window_width = ffi.new("int[1]")
local gl_font_window_height = ffi.new("int[1]")
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
      rig.raise("sdl3.get_gl_proc_address expects a non-empty string")
   end

   local ptr = M.GL_GetProcAddress(name)
   if ptr == nil or ptr == ffi.NULL then
      return nil, get_error_string()
   end

   return ptr
end

local function get_window_size()
   if runtime_window == nil then
      rig.raise("an SDL window must exist before querying window size")
   end

   if not M.GetWindowSize(runtime_window, window_size_width, window_size_height) then
      rig.raise("failed to query window size: " .. get_error_string())
   end

   return tonumber(window_size_width[0]) or 0,
      tonumber(window_size_height[0]) or 0
end

local function initialize_windowed_sdl(options)
   if runtime_renderer ~= nil or runtime_window ~= nil or runtime_gpu_device ~= nil or runtime_gl_context ~= nil then
      shutdown()
   end

   options = normalize_driver_config(options)

   local required =
      normalize_init_flags(options.init_flags or (M.INIT_VIDEO + M.INIT_EVENTS))
   local initialized = M.WasInit(required)
   local owned_init_flags = nil

   if not has_all_bits(initialized, required) then
      if not M.Init(required) then
         error("failed to initialize SDL: " .. get_error_string())
      end
      owned_init_flags = required
   end

   return options, owned_init_flags
end

local function create_window_or_fail(options, owned_init_flags)
   local create_window = options.create_window or default_create_window
   if type(create_window) ~= "function" then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      rig.raise("sdl3 create_window must be a function")
   end

   local window_ptr, window_err = create_window(options)
   if window_ptr == nil then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error(format_factory_error(
         "sdl3 create_window",
         window_err,
         "expected SDL_Window* cdata"
      ))
   end
   if type(window_ptr) ~= "cdata" then
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      rig.raise("sdl3 create_window must return SDL_Window* cdata")
   end

   return window_ptr, owned_init_flags
end

local function setup(options)
   options, owned_init_flags = initialize_windowed_sdl(options)
   local window_ptr = create_window_or_fail(options, owned_init_flags)
   local create_renderer = options.create_renderer or default_create_renderer
   if type(create_renderer) ~= "function" then
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      rig.raise("sdl3 create_renderer must be a function")
   end

   local renderer_ptr, renderer_err = create_renderer(window_ptr)
   if renderer_ptr == nil then
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      error(format_factory_error(
         "sdl3 create_renderer",
         renderer_err,
         "expected SDL_Renderer* cdata"
      ))
   end
   if type(renderer_ptr) ~= "cdata" then
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      rig.raise("sdl3 create_renderer must return SDL_Renderer* cdata")
   end

   runtime_window = window_ptr
   runtime_renderer = renderer_ptr
   runtime_owned_init_flags = owned_init_flags
   resize_state = nil
end

local function setup_gpu(options)
   if options ~= nil and type(options) ~= "table" then
      error("sdl3.setup_gpu expects a table if options are provided")
   end

   options, owned_init_flags = initialize_windowed_sdl(options)
   local window_ptr = create_window_or_fail(options, owned_init_flags)

   local format_flags = options and options.shader_formats
   if format_flags == nil then
      format_flags = M.GPU_SHADERFORMAT_SPIRV
   end
   local debug_mode = options and options.debug_mode and true or false
   local backend_name = options and options.backend_name or nil

   if not M.GPUSupportsShaderFormats(format_flags, backend_name) then
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

   runtime_window = window_ptr
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
      return M[field]
   end
   return gl_attribute_int(value)
end

local function apply_gl_attributes(attributes)
   M.GL_ResetAttributes()

   local requested = attributes
   if requested == nil then
      requested = {
         context_major_version = 3,
         context_minor_version = 3,
         context_profile = "core",
         doublebuffer = true,
         depth_size = 24,
      }
   end
   if type(requested) ~= "table" then
      rig.raise("sdl3_gl gl_attributes must be a table")
   end

   for key, value in pairs(requested) do
      local field = GL_ATTRIBUTE_VALUES[key]
      if field == nil then
         rig.raise("unsupported OpenGL attribute '%s'", key)
      end

      local normalized = value
      if key == "context_profile" then
         normalized = normalize_gl_profile(value)
      else
         normalized = gl_attribute_int(value)
      end

      if not M.GL_SetAttribute(M[field], normalized) then
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
      [M.PROP_WINDOW_CREATE_OPENGL_BOOLEAN] = true,
   })
   if window_props == nil then
      rig.raise(props_err)
   end

   local window_options = {}
   for key, value in pairs(options) do
      window_options[key] = value
   end
   window_options.window_props = window_props

   window_options, owned_init_flags = initialize_windowed_sdl(window_options)
   apply_gl_attributes(options.gl_attributes)
   local window_ptr = create_window_or_fail(window_options, owned_init_flags)
   local gl_context = M.GL_CreateContext(window_ptr)
   if gl_context == nil then
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      rig.raise("failed to create OpenGL context: " .. get_error_string())
   end

   if not M.GL_MakeCurrent(window_ptr, gl_context) then
      M.GL_DestroyContext(gl_context)
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      rig.raise("failed to make OpenGL context current: " .. get_error_string())
   end

   local swap_interval = options.swap_interval
   if swap_interval == nil then
      swap_interval = 1
   end
   if not M.GL_SetSwapInterval(gl_attribute_int(swap_interval)) then
      M.GL_DestroyContext(gl_context)
      M.DestroyWindow(window_ptr)
      if owned_init_flags ~= nil then
         M.QuitSubSystem(owned_init_flags)
      end
      rig.raise("failed to set OpenGL swap interval: " .. get_error_string())
   end

   runtime_window = window_ptr
   runtime_gl_context = gl_context
   runtime_owned_init_flags = owned_init_flags
   resize_state = nil
end

shutdown = function()
   destroy_gl_font_backend_state()
   if runtime_gl_context ~= nil then
      M.GL_DestroyContext(runtime_gl_context)
      runtime_gl_context = nil
   end
   if runtime_gpu_device ~= nil then
      M.WaitForGPUIdle(runtime_gpu_device)
      if runtime_window ~= nil then
         M.ReleaseWindowFromGPUDevice(runtime_gpu_device, runtime_window)
      end
      M.DestroyGPUDevice(runtime_gpu_device)
      runtime_gpu_device = nil
   end
   if runtime_renderer ~= nil then
      M.DestroyRenderer(runtime_renderer)
      runtime_renderer = nil
   end
   if runtime_window ~= nil then
      M.DestroyWindow(runtime_window)
      runtime_window = nil
   end
   resize_state = nil
   if runtime_owned_init_flags ~= nil then
      M.QuitSubSystem(runtime_owned_init_flags)
      runtime_owned_init_flags = nil
   end
end

local function present()
   if runtime_renderer == nil then
      rig.raise("SDL renderer is not initialized")
   end
   if not M.RenderPresent(runtime_renderer) then
      error("failed to present renderer: " .. ffi.string(M.GetError()))
   end
end

local function present_gl()
   if runtime_window == nil or runtime_gl_context == nil then
      rig.raise("an OpenGL window and context must be initialized before presenting")
   end
   if not M.GL_SwapWindow(runtime_window) then
      rig.raise("failed to swap OpenGL window: " .. get_error_string())
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

   local gl = state.gl

   if state.vbo ~= 0 then
      gl_font_buffers[0] = state.vbo
      gl.DeleteBuffers(1, gl_font_buffers)
   end
   if state.vao ~= 0 then
      gl_font_vertex_arrays[0] = state.vao
      gl.DeleteVertexArrays(1, gl_font_vertex_arrays)
   end
   if state.program ~= 0 then
      gl.DeleteProgram(state.program)
   end

   gl_font_backend_state = nil
end

local function ensure_gl_font_backend_state()
   if gl_font_backend_state ~= nil then
      return gl_font_backend_state
   end

   local gl = require("gl")
   local program = gl.create_program {
      vertex_source = gl_font_vertex_source,
      fragment_source = gl_font_fragment_source,
   }

   gl.GenVertexArrays(1, gl_font_vertex_arrays)
   gl.GenBuffers(1, gl_font_buffers)

   local vao = tonumber(gl_font_vertex_arrays[0]) or 0
   local vbo = tonumber(gl_font_buffers[0]) or 0
   if vao == 0 or vbo == 0 then
      if vbo ~= 0 then
         gl_font_buffers[0] = vbo
         gl.DeleteBuffers(1, gl_font_buffers)
      end
      if vao ~= 0 then
         gl_font_vertex_arrays[0] = vao
         gl.DeleteVertexArrays(1, gl_font_vertex_arrays)
      end
      gl.DeleteProgram(program)
      rig.raise("failed to create OpenGL font vertex objects")
   end

   gl.BindVertexArray(vao)
   gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
   gl.BufferData(
      gl.ARRAY_BUFFER,
      ffi.sizeof(gl_font_quad_vertices),
      nil,
      gl.DYNAMIC_DRAW
   )

   gl.EnableVertexAttribArray(0)
   gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 16, ffi.cast("const void *", 0))
   gl.EnableVertexAttribArray(1)
   gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 16, ffi.cast("const void *", 8))

   local atlas_location = gl.get_uniform_location(program, "u_atlas")
   local view_size_location = gl.get_uniform_location(program, "u_view_size")
   local color_location = gl.get_uniform_location(program, "u_color")
   if atlas_location < 0 or view_size_location < 0 or color_location < 0 then
      gl_font_buffers[0] = vbo
      gl.DeleteBuffers(1, gl_font_buffers)
      gl_font_vertex_arrays[0] = vao
      gl.DeleteVertexArrays(1, gl_font_vertex_arrays)
      gl.DeleteProgram(program)
      rig.raise("failed to locate OpenGL font shader uniforms")
   end

   gl.UseProgram(program)
   gl.Uniform1i(atlas_location, 0)

   gl_font_backend_state = {
      gl = gl,
      program = program,
      vao = vao,
      vbo = vbo,
      atlas_location = atlas_location,
      view_size_location = view_size_location,
      color_location = color_location,
   }

   return gl_font_backend_state
end

local function get_window_size_in_pixels()
   if runtime_window == nil then
      rig.raise("an SDL window must exist before querying pixel size")
   end

   if not M.GetWindowSizeInPixels(runtime_window, gl_font_window_width, gl_font_window_height) then
      rig.raise("failed to query window size in pixels: " .. get_error_string())
   end

   return tonumber(gl_font_window_width[0]) or 0,
      tonumber(gl_font_window_height[0]) or 0
end

local function dispatch_resize_if_changed(handler, event_name, timestamp_ns)
   if type(handler) ~= "function" then
      return
   end

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
   handler({
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
   local state = ensure_gl_font_backend_state()
   local gl = state.gl
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

   local texture_id = texture
   if texture_id == nil or texture_id == 0 then
      gl.GenTextures(1, gl_font_textures)
      texture_id = tonumber(gl_font_textures[0]) or 0
      if texture_id == 0 then
         rig.raise("failed to create OpenGL font texture")
      end
   end

   gl.ActiveTexture(gl.TEXTURE0)
   gl.BindTexture(gl.TEXTURE_2D, texture_id)
   gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
   gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
   gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
   gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
   gl.TexImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RGBA,
      page.width,
      page.height,
      0,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      rgba
   )

   return texture_id
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
      page_texture = M.CreateTexture(
         runtime_renderer,
         M.PIXELFORMAT_RGBA32,
         M.TEXTUREACCESS_STATIC,
         page.width,
         page.height
      )
      if page_texture == nil or page_texture == ffi.NULL then
         rig.raise("failed to create SDL texture: " .. ffi.string(M.GetError()))
      end

      if not M.SetTextureBlendMode(page_texture, M.BLENDMODE_BLEND) then
         M.DestroyTexture(page_texture)
         rig.raise("failed to set SDL texture blend mode: " .. ffi.string(M.GetError()))
      end
   end

   if not M.UpdateTexture(page_texture, nil, rgba, page.width * 4) then
      if texture == nil or texture == ffi.NULL then
         M.DestroyTexture(page_texture)
      end
      rig.raise("failed to upload SDL texture: " .. ffi.string(M.GetError()))
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
         M.DestroyTexture(texture)
      end
      state.textures[i] = nil
      state.revisions[i] = nil
   end
end

function sdl3_font_provider.draw_packed_glyph(text_renderer, packed, x, y, draw_color, scale)
   if packed.width <= 0 or packed.height <= 0 then
      return
   end

   local glyph_color = resolve_font_draw_color(draw_color)
   local texture = ensure_font_page_texture(text_renderer, packed.page_index)
   if not M.SetTextureColorMod(texture, glyph_color.r, glyph_color.g, glyph_color.b) then
      rig.raise("failed to set texture color modulation: " .. ffi.string(M.GetError()))
   end
   if not M.SetTextureAlphaMod(texture, glyph_color.a) then
      rig.raise("failed to set texture alpha modulation: " .. ffi.string(M.GetError()))
   end

   font_src_rect[0].x = packed.x
   font_src_rect[0].y = packed.y
   font_src_rect[0].w = packed.width
   font_src_rect[0].h = packed.height

   font_dst_rect[0].x = x
   font_dst_rect[0].y = y
   font_dst_rect[0].w = packed.width * scale
   font_dst_rect[0].h = packed.height * scale

   if not M.RenderTexture(runtime_renderer, texture, font_src_rect, font_dst_rect) then
      rig.raise("failed to render SDL texture: " .. ffi.string(M.GetError()))
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

   local backend_state = gl_font_backend_state
   if backend_state == nil then
      return
   end

   local gl = backend_state.gl
   for i = 1, #state.textures do
      local texture = state.textures[i]
      if texture ~= nil and texture ~= 0 then
         gl_font_textures[0] = texture
         gl.DeleteTextures(1, gl_font_textures)
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
   gl.UseProgram(backend_state.program)
   gl.Uniform2f(backend_state.view_size_location, window_width, window_height)
   gl.Uniform4f(
      backend_state.color_location,
      glyph_color.r / 255.0,
      glyph_color.g / 255.0,
      glyph_color.b / 255.0,
      glyph_color.a / 255.0
   )
   gl.ActiveTexture(gl.TEXTURE0)
   gl.BindTexture(gl.TEXTURE_2D, texture)
   gl.BindVertexArray(backend_state.vao)
   gl.BindBuffer(gl.ARRAY_BUFFER, backend_state.vbo)
   gl.BufferData(
      gl.ARRAY_BUFFER,
      ffi.sizeof(gl_font_quad_vertices),
      gl_font_quad_vertices,
      gl.DYNAMIC_DRAW
   )
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
      rig.raise("sdl3.upload_to_gpu_buffer requires an SDL_GPUDevice*")
   end
   if buffer == nil then
      rig.raise("sdl3.upload_to_gpu_buffer requires an SDL_GPUBuffer*")
   end
   if type(data) ~= "string" then
      rig.raise("sdl3.upload_to_gpu_buffer requires data to be a string")
   end

   local transfer_info = ffi.new("SDL_GPUTransferBufferCreateInfo[1]")
   transfer_info[0].usage = M.GPU_TRANSFERBUFFERUSAGE_UPLOAD
   transfer_info[0].size = #data
   transfer_info[0].props = 0

   local transfer_buffer = M.CreateGPUTransferBuffer(device, transfer_info)
   if transfer_buffer == nil then
      rig.raise("failed to create GPU transfer buffer: " .. get_error_string())
   end

   local mapped = M.MapGPUTransferBuffer(device, transfer_buffer, false)
   if mapped == nil then
      M.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to map GPU transfer buffer: " .. get_error_string())
   end
   ffi.copy(mapped, data, #data)
   M.UnmapGPUTransferBuffer(device, transfer_buffer)

   local command_buffer = M.AcquireGPUCommandBuffer(device)
   if command_buffer == nil then
      M.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to acquire GPU command buffer: " .. get_error_string())
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
      rig.raise("failed to submit GPU upload command buffer: " .. get_error_string())
   end

   M.ReleaseGPUTransferBuffer(device, transfer_buffer)
end

function M.choose_depth_format(device)
   if device == nil then
      rig.raise("sdl3.choose_depth_format requires an SDL_GPUDevice*")
   end

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

   rig.raise("no supported depth texture format found")
end

function M.create_depth_texture(device, width, height, format)
   if device == nil then
      rig.raise("sdl3.create_depth_texture requires an SDL_GPUDevice*")
   end

   if format == nil then
      format = M.choose_depth_format(device)
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
      rig.raise("sdl3.clear requires an active SDL renderer")
   end

   local renderer = ffi.cast("SDL_Renderer *", renderer_ptr)
   local rr = color_component(r)
   local gg = color_component(g, 0)
   local bb = color_component(b, 0)
   local aa = color_component(a, 1)

   if not M.SetRenderDrawColor(renderer, rr, gg, bb, aa) then
      rig.raise("failed to set draw color: " .. ffi.string(M.GetError()))
   end
   if not M.RenderClear(renderer) then
      error("failed to clear render target: " .. ffi.string(M.GetError()))
   end
end

local function dispatch_keyboard_event(event, handler)
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

local function dispatch_mouse_motion_event(event, handler)
   if type(handler) ~= "function" then
      return
   end

   local timestamp_ns = tonumber(event.timestamp) or 0

   handler({
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

local function dispatch_mouse_button_event(event, handler)
   if type(handler) ~= "function" then
      return
   end

   local timestamp_ns = tonumber(event.timestamp) or 0

   handler({
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

local function pump_events(on_key, on_mouse, on_resize)
   if runtime_window == nil then
      error("an SDL window must be initialized before sdl3.pump_events")
   end

   local event = ffi.new("SDL_Event[1]")
   while M.PollEvent(event) do
      local current = event[0]
      local event_type = tonumber(current.type) or 0

      if event_type == M.EVENT_QUIT then
         return false
      end

      if event_type == M.EVENT_KEY_DOWN or event_type == M.EVENT_KEY_UP then
         dispatch_keyboard_event(current.key, on_key)
      elseif event_type == M.EVENT_WINDOW_RESIZED then
         dispatch_resize_if_changed(
            on_resize,
            "resized",
            tonumber(current.window.timestamp) or 0
         )
      elseif event_type == M.EVENT_WINDOW_PIXEL_SIZE_CHANGED then
         dispatch_resize_if_changed(
            on_resize,
            "pixel_size_changed",
            tonumber(current.window.timestamp) or 0
         )
      elseif event_type == M.EVENT_MOUSE_MOTION then
         dispatch_mouse_motion_event(current.motion, on_mouse)
      elseif event_type == M.EVENT_MOUSE_BUTTON_DOWN or event_type == M.EVENT_MOUSE_BUTTON_UP then
         dispatch_mouse_button_event(current.button, on_mouse)
      end
   end

   return true
end

local function render_frame(render_fn)
   if type(render_fn) ~= "function" then
      rig.raise("sdl3.render_frame requires a render function")
   end
   if runtime_renderer == nil then
      rig.raise("an SDL renderer must be initialized before sdl3.render_frame")
   end

   render_fn()
   present()
end

local function render_gpu_frame(render_fn)
   if type(render_fn) ~= "function" then
      rig.raise("sdl3.render_gpu_frame requires a render function")
   end
   if runtime_gpu_device == nil then
      rig.raise("an SDL GPU device must be initialized before sdl3.render_gpu_frame")
   end
   if runtime_window == nil then
      rig.raise("an SDL window must be initialized before sdl3.render_gpu_frame")
   end

   local command_buffer = M.AcquireGPUCommandBuffer(runtime_gpu_device)
   if command_buffer == nil then
      rig.raise("failed to acquire GPU command buffer: " .. get_error_string())
   end

   local swapchain_texture_out = ffi.new("SDL_GPUTexture *[1]")
   local width_out = ffi.new("Uint32[1]")
   local height_out = ffi.new("Uint32[1]")
   if not M.WaitAndAcquireGPUSwapchainTexture(
      command_buffer,
      runtime_window,
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

   if not M.SubmitGPUCommandBuffer(command_buffer) then
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
   local counter = tonumber(M.GetPerformanceCounter())
   local frequency = tonumber(M.GetPerformanceFrequency())
   if frequency == nil or frequency <= 0 then
      rig.raise("sdl3.GetPerformanceFrequency returned an invalid value")
   end
   return counter / frequency
end

local function current_time_seconds()
   local ticks = ffi.new("int64_t[1]")
   if not M.GetCurrentTime(ticks) then
      local err = M.GetError()
      rig.raise("sdl3.GetCurrentTime failed: " .. ffi.string(err))
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
      M.ReleaseGPUShader(device, stage)
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

      local gl = require("gl")
      local shader_type = nil
      if spec.stage == "vertex" then
         shader_type = gl.VERTEX_SHADER
      elseif spec.stage == "fragment" then
         shader_type = gl.FRAGMENT_SHADER
      elseif spec.stage == "compute" then
         shader_type = rawget(gl, "COMPUTE_SHADER")
      end
      if shader_type == nil then
         rig.raise(
            "shader stage '%s' is not supported by the OpenGL runtime provider",
            tostring(spec.stage)
         )
      end

      return gl.create_shader(shader_type, spec.source)
   end,
   destroy_stage = function(stage)
      require("gl").DeleteShader(stage)
   end,
}

rig.register_service_provider("time", "sdl3", sdl3_time_service)
rig.register_service_provider("font.renderer", "sdl3", sdl3_font_provider)
rig.register_service_provider("font.renderer", "sdl3_gl", sdl3_gl_font_provider)
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

local function require_render_callback(mode_options, mode_key)
   local callback = mode_options.render
   if type(callback) ~= "function" then
      rig.raise(
         "rig.run requires " .. mode_key .. ".render to be a function")
   end
   return callback
end

rig.register_runtime_driver("sdl3", {
   phases = {
      "before_poll",
      "after_poll",
      "before_frame",
      "after_frame",
   },
   setup = function(options)
      local sdl3_options = get_driver_config(options, "sdl3")
      local event_handlers = get_event_handlers(options)
      require_render_callback(sdl3_options, "options.driver_config.sdl3")
      setup(sdl3_options)
      setup_scheduler("sdl3 scheduler")
      dispatch_resize_if_changed(event_handlers.resize, "initial", 0)
   end,
   loop = function(options, run_hooks)
      local sdl3_options = get_driver_config(options, "sdl3")
      local event_handlers = get_event_handlers(options)
      local on_render = require_render_callback(sdl3_options, "options.driver_config.sdl3")
      local on_key = event_handlers.key
      local on_mouse = event_handlers.mouse
      local on_resize = event_handlers.resize
      while true do
         run_hooks("before_poll", options)
         if pump_events(on_key, on_mouse, on_resize) == false then
            break
         end
         run_hooks("after_poll", options)
         drain_scheduler()
         run_hooks("before_frame", options)
         render_frame(on_render)
         run_hooks("after_frame", options)
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
   phases = {
      "before_poll",
      "after_poll",
      "before_frame",
      "after_frame",
   },
   setup = function(options)
      local sdl3_options = get_driver_config(options, "sdl3_gpu")
      local event_handlers = get_event_handlers(options)
      require_render_callback(sdl3_options, "options.driver_config.sdl3_gpu")
      setup_gpu {
         init_flags = sdl3_options.init_flags,
         window_props = sdl3_options.window_props,
         create_window = sdl3_options.create_window,
         shader_formats = sdl3_options.shader_formats,
         debug_mode = sdl3_options.debug_mode,
         backend_name = sdl3_options.backend_name,
      }
      setup_scheduler("sdl3_gpu scheduler")
      dispatch_resize_if_changed(event_handlers.resize, "initial", 0)
   end,
   loop = function(options, run_hooks)
      local sdl3_options = get_driver_config(options, "sdl3_gpu")
      local event_handlers = get_event_handlers(options)
      local on_render = require_render_callback(sdl3_options, "options.driver_config.sdl3_gpu")
      local on_key = event_handlers.key
      local on_mouse = event_handlers.mouse
      local on_resize = event_handlers.resize
      while true do
         run_hooks("before_poll", options)
         if pump_events(on_key, on_mouse, on_resize) == false then
            break
         end
         run_hooks("after_poll", options)
         drain_scheduler()
         run_hooks("before_frame", options)
         render_gpu_frame(on_render)
         run_hooks("after_frame", options)
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
   phases = {
      "before_poll",
      "after_poll",
      "before_frame",
      "after_frame",
   },
   setup = function(options)
      local sdl3_options = get_driver_config(options, "sdl3_gl")
      local event_handlers = get_event_handlers(options)
      require_render_callback(sdl3_options, "options.driver_config.sdl3_gl")
      setup_gl(sdl3_options)
      setup_scheduler("sdl3_gl scheduler")
      dispatch_resize_if_changed(event_handlers.resize, "initial", 0)
   end,
   loop = function(options, run_hooks)
      local sdl3_options = get_driver_config(options, "sdl3_gl")
      local event_handlers = get_event_handlers(options)
      local on_render = require_render_callback(sdl3_options, "options.driver_config.sdl3_gl")
      local on_key = event_handlers.key
      local on_mouse = event_handlers.mouse
      local on_resize = event_handlers.resize
      while true do
         run_hooks("before_poll", options)
         if pump_events(on_key, on_mouse, on_resize) == false then
            break
         end
         run_hooks("after_poll", options)
         drain_scheduler()
         run_hooks("before_frame", options)
         render_gl_frame(on_render)
         run_hooks("after_frame", options)
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
      ["shader.stage"] = "sdl3_gl",
   },
})

return M
