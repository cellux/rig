local M = ... or {}
local ffi = ffi

ffi.cdef[[
typedef struct SDL_Renderer SDL_Renderer;
typedef unsigned char Uint8;
bool SDL_SetRenderDrawColor(SDL_Renderer *renderer, Uint8 r, Uint8 g, Uint8 b, Uint8 a);
bool SDL_RenderClear(SDL_Renderer *renderer);
const char *SDL_GetError(void);
]]

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

return M
