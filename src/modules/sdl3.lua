local M = ... or {}
local ffi = require("ffi")
local rig = require("rig")

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
void SDL_free(void *mem);
SDL_PropertiesID SDL_CreateProperties(void);
void SDL_DestroyProperties(SDL_PropertiesID props);
bool SDL_SetPointerProperty(SDL_PropertiesID props, const char *name, void *value);
bool SDL_SetStringProperty(SDL_PropertiesID props, const char *name, const char *value);
bool SDL_SetNumberProperty(SDL_PropertiesID props, const char *name, Sint64 value);
bool SDL_SetFloatProperty(SDL_PropertiesID props, const char *name, float value);
bool SDL_SetBooleanProperty(SDL_PropertiesID props, const char *name, bool value);
bool SDL_ClearProperty(SDL_PropertiesID props, const char *name);
bool SDL_PollEvent(SDL_Event *event);
Uint32 SDL_GetMouseState(float *x, float *y);
bool SDL_GetWindowSize(SDL_Window *window, int *w, int *h);
bool SDL_GetWindowSizeInPixels(SDL_Window *window, int *w, int *h);
bool SDL_SetWindowFullscreen(SDL_Window *window, bool fullscreen);
bool SDL_SyncWindow(SDL_Window *window);
bool SDL_SetCurrentThreadPriority(int priority);
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
typedef struct SDL_GPUComputePipeline SDL_GPUComputePipeline;
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

local load_sdl_library = rig.create_ffi_library_loader({
   label = "SDL3",
   candidates = {
      "SDL3",
      "libSDL3.so.0",
      "libSDL3.so",
      "SDL3.dll",
      "libSDL3.dylib",
   },
})

local function export_sdl_function(export_name, symbol_name)
   local resolved_symbol_name = symbol_name or ("SDL_" .. export_name)
   M[export_name] = function(...)
      return load_sdl_library()[resolved_symbol_name](...)
   end
end

export_sdl_function("SetRenderDrawColor")
export_sdl_function("RenderClear")
export_sdl_function("RenderPoint")
export_sdl_function("RenderLine")
export_sdl_function("RenderFillRect")
export_sdl_function("CreateTexture")
export_sdl_function("UpdateTexture")
export_sdl_function("SetTextureColorMod")
export_sdl_function("SetTextureAlphaMod")
export_sdl_function("SetTextureBlendMode")
export_sdl_function("RenderTexture")
export_sdl_function("DestroyTexture")
export_sdl_function("CreateWindowWithProperties")
export_sdl_function("CreateRenderer")
export_sdl_function("GetPrimaryDisplay")
export_sdl_function("GetDisplayUsableBounds")
export_sdl_function("SetRenderVSync")
export_sdl_function("RenderPresent")
export_sdl_function("DestroyRenderer")
export_sdl_function("DestroyWindow")
export_sdl_function("Init")
export_sdl_function("QuitSubSystem")
export_sdl_function("WasInit")
export_sdl_function("free")
export_sdl_function("CreateProperties")
export_sdl_function("DestroyProperties")
export_sdl_function("SetPointerProperty")
export_sdl_function("SetStringProperty")
export_sdl_function("SetNumberProperty")
export_sdl_function("SetFloatProperty")
export_sdl_function("SetBooleanProperty")
export_sdl_function("ClearProperty")
export_sdl_function("PollEvent")
export_sdl_function("GetMouseState")
export_sdl_function("GetWindowSize")
export_sdl_function("GetWindowSizeInPixels")
export_sdl_function("SetWindowFullscreen")
export_sdl_function("SyncWindow")
export_sdl_function("SetCurrentThreadPriority")
export_sdl_function("GetError")
export_sdl_function("GetKeyName")
export_sdl_function("GetCurrentTime")
export_sdl_function("GetTicks")
export_sdl_function("GetTicksNS")
export_sdl_function("GetPerformanceCounter")
export_sdl_function("GetPerformanceFrequency")
export_sdl_function("Delay")
export_sdl_function("DelayNS")
export_sdl_function("DelayPrecise")
export_sdl_function("GL_ResetAttributes")
export_sdl_function("GL_SetAttribute")
export_sdl_function("GL_CreateContext")
export_sdl_function("GL_MakeCurrent")
export_sdl_function("GL_SetSwapInterval")
export_sdl_function("GL_SwapWindow")
export_sdl_function("GL_DestroyContext")
export_sdl_function("GL_GetProcAddress")
export_sdl_function("GPUSupportsShaderFormats")
export_sdl_function("CreateGPUDevice")
export_sdl_function("DestroyGPUDevice")
export_sdl_function("GetNumGPUDrivers")
export_sdl_function("GetGPUDriver")
export_sdl_function("GetGPUShaderFormats")
export_sdl_function("GetGPUDeviceDriver")
export_sdl_function("ClaimWindowForGPUDevice")
export_sdl_function("ReleaseWindowFromGPUDevice")
export_sdl_function("GetGPUSwapchainTextureFormat")
export_sdl_function("CreateGPUShader")
export_sdl_function("ReleaseGPUShader")
export_sdl_function("CreateGPUGraphicsPipeline")
export_sdl_function("ReleaseGPUGraphicsPipeline")
export_sdl_function("CreateGPUBuffer")
export_sdl_function("ReleaseGPUBuffer")
export_sdl_function("CreateGPUTransferBuffer")
export_sdl_function("ReleaseGPUTransferBuffer")
export_sdl_function("MapGPUTransferBuffer")
export_sdl_function("UnmapGPUTransferBuffer")
export_sdl_function("CreateGPUTexture")
export_sdl_function("ReleaseGPUTexture")
export_sdl_function("GPUTextureSupportsFormat")
export_sdl_function("AcquireGPUCommandBuffer")
export_sdl_function("PushGPUVertexUniformData")
export_sdl_function("PushGPUFragmentUniformData")
export_sdl_function("BeginGPUCopyPass")
export_sdl_function("UploadToGPUBuffer")
export_sdl_function("EndGPUCopyPass")
export_sdl_function("WaitAndAcquireGPUSwapchainTexture")
export_sdl_function("BeginGPURenderPass")
export_sdl_function("BindGPUGraphicsPipeline")
export_sdl_function("BindGPUVertexBuffers")
export_sdl_function("BindGPUIndexBuffer")
export_sdl_function("DrawGPUPrimitives")
export_sdl_function("DrawGPUIndexedPrimitives")
export_sdl_function("EndGPURenderPass")
export_sdl_function("SubmitGPUCommandBuffer")
export_sdl_function("WaitForGPUIdle")

return M
