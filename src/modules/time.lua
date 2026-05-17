local M = ... or {}
local ffi = ffi

local function resolve_backend()
   local uv_mod = rawget(_G, "uv")
   if type(uv_mod) == "table"
      and type(uv_mod.now) == "function"
      and type(uv_mod.monotonic) == "function" then
      return "uv", uv_mod
   end

   local sdl3_mod = rawget(_G, "sdl3")
   if type(sdl3_mod) == "table"
      and type(sdl3_mod.GetCurrentTime) == "function"
      and type(sdl3_mod.GetPerformanceCounter) == "function"
      and type(sdl3_mod.GetPerformanceFrequency) == "function"
      and type(sdl3_mod.GetError) == "function" then
      return "sdl3", sdl3_mod
   end

   error("time requires either uv or sdl3 to be loaded first", 0)
end

local function read_sdl3_now(sdl3_mod)
   local ticks = ffi.new("int64_t[1]")
   if not sdl3_mod.GetCurrentTime(ticks) then
      local err = sdl3_mod.GetError()
      error("sdl3.GetCurrentTime failed: " .. ffi.string(err), 0)
   end
   return tonumber(ticks[0]) / 1000000000.0
end

local function read_sdl3_monotonic(sdl3_mod)
   local counter = tonumber(sdl3_mod.GetPerformanceCounter())
   local frequency = tonumber(sdl3_mod.GetPerformanceFrequency())
   if frequency == nil or frequency <= 0 then
      error("sdl3.GetPerformanceFrequency returned an invalid value", 0)
   end
   return counter / frequency
end

function M.now()
   local backend_name, backend = resolve_backend()
   if backend_name == "uv" then
      return backend.now()
   end
   return read_sdl3_now(backend)
end

function M.monotonic()
   local backend_name, backend = resolve_backend()
   if backend_name == "uv" then
      return backend.monotonic()
   end
   return read_sdl3_monotonic(backend)
end

return M
