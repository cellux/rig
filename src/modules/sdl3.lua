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

M._window = nil
M._renderer = nil
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

local function format_hook_error(hook_name, detail, fallback)
   if detail == nil then
      return ("%s failed: %s"):format(hook_name, fallback)
   end
   return ("%s failed: %s"):format(hook_name, tostring(detail))
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

function M.setup()
   if M._renderer ~= nil or M._window ~= nil then
      M.shutdown()
   end

   ensure_creation_hooks()

   local hooks = _G.hooks
   local required = normalize_init_flags(hooks.sdl_init_flags)
   local initialized = M.WasInit(required)
   local owned_init_flags = nil

   if not has_all_bits(initialized, required) then
      if not M.Init(required) then
         error("failed to initialize SDL: " .. ffi.string(M.GetError()))
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
      error(
         format_hook_error(
            "hooks.create_window",
            window_err,
            "expected SDL_Window* cdata"
         )
      )
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
      error(
         format_hook_error(
            "hooks.create_renderer",
            renderer_err,
            "expected SDL_Renderer* cdata"
         )
      )
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

function M.shutdown()
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
   if M._window == nil or M._renderer == nil then
      error("sdl3.setup must be called before sdl3.pump_events")
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
