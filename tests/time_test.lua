local test = require("test")
local sdl3 = require("sdl3")
local time = require("time")

test.case("time can use the sdl3 backend", function()
   test.equal(type(sdl3.GetCurrentTime), "function")

   local now = time.now()
   local monotonic = time.monotonic()

   test.equal(type(now), "number")
   test.equal(type(monotonic), "number")
   test.truthy(now > 0)
   test.truthy(monotonic > 0)
end)
