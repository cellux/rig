local M = ... or {}
local ffi = ffi

ffi.cdef[[
typedef struct SDL_Renderer SDL_Renderer;
typedef unsigned char Uint8;
typedef uint16_t Uint16;
typedef uint32_t Uint32;
typedef uint64_t Uint64;
typedef uint32_t SDL_EventType;
typedef uint32_t SDL_WindowID;
typedef uint32_t SDL_KeyboardID;
typedef int32_t SDL_Scancode;
typedef uint32_t SDL_Keycode;
typedef uint16_t SDL_Keymod;
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
bool SDL_SetRenderDrawColor(SDL_Renderer *renderer, Uint8 r, Uint8 g, Uint8 b, Uint8 a);
bool SDL_RenderClear(SDL_Renderer *renderer);
const char *SDL_GetError(void);
const char *SDL_GetKeyName(int key);
]]

local KMOD_SHIFT = 0x0003
local KMOD_CTRL = 0x00C0
local KMOD_ALT = 0x0300
local KMOD_GUI = 0x0C00

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
   local renderer_ud = M.renderer
   if renderer_ud == nil then
      error("sdl3.clear can only be called during on_render callback")
   end

   local renderer = ffi.cast("SDL_Renderer *", renderer_ud)
   local rr = color_component(r, 0)
   local gg = color_component(g, 0)
   local bb = color_component(b, 0)
   local aa = color_component(a, 1)

   if not ffi.C.SDL_SetRenderDrawColor(renderer, rr, gg, bb, aa) then
      error("failed to set draw color: " .. ffi.string(ffi.C.SDL_GetError()))
   end
   if not ffi.C.SDL_RenderClear(renderer) then
      error("failed to clear render target: " .. ffi.string(ffi.C.SDL_GetError()))
   end
end

local function has_any_bits(value, mask)
   local v = tonumber(value) or 0
   local m = mask

   while v ~= 0 and m ~= 0 do
      if (v % 2) == 1 and (m % 2) == 1 then
         return true
      end
      v = math.floor(v / 2)
      m = math.floor(m / 2)
   end

   return false
end

function M._dispatch_key(key_event_ptr)
   local handler = _G.on_key
   if type(handler) ~= "function" then
      return
   end

   if key_event_ptr == nil then
      return
   end

   local event = ffi.cast("const SDL_KeyboardEvent*", key_event_ptr)[0]
   local key_name = ffi.C.SDL_GetKeyName(event.key)
   local key = "Unknown"
   local mods = tonumber(event.mod) or 0

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
      timestamp_ms = tonumber(event.timestamp),
      mods = {
         shift = has_any_bits(mods, KMOD_SHIFT),
         ctrl = has_any_bits(mods, KMOD_CTRL),
         alt = has_any_bits(mods, KMOD_ALT),
         super = has_any_bits(mods, KMOD_GUI),
      },
   })
end

function M._dispatch_render()
   local handler = _G.on_render
   if type(handler) ~= "function" then
      return
   end
   handler()
end

function M._should_run()
   return type(_G.on_render) == "function"
end

return M
