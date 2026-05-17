local sdl3 = require("sdl3")
local time = require("time")

assert(type(sdl3.GetCurrentTime) == "function")
assert(type(sdl3.GetTicks) == "function")
assert(type(sdl3.GetTicksNS) == "function")
assert(type(sdl3.GetPerformanceCounter) == "function")
assert(type(sdl3.GetPerformanceFrequency) == "function")
assert(type(sdl3.Delay) == "function")
assert(type(sdl3.DelayNS) == "function")
assert(type(sdl3.DelayPrecise) == "function")

local now = time.now()
local monotonic = time.monotonic()

assert(type(now) == "number")
assert(type(monotonic) == "number")
assert(now > 0)
assert(monotonic > 0)
