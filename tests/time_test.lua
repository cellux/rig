local test = require("test")
local time = require("time")
local uv = require("uv")

local outside_runtime_ok, outside_runtime_err = pcall(time.now)

test.case("time requires an active runtime service", function()
   test.falsey(outside_runtime_ok)
   test.match(tostring(outside_runtime_err), "requires an active runtime mode")
end)

test.case("time can use the uv service inside uv mode", function()
   local observed_now
   local observed_monotonic

   rig.run {
      mode = "uv",
      uv = {
         main = function()
            observed_now = time.now()
            observed_monotonic = time.monotonic()
            uv.stop()
         end,
      },
   }

   test.equal(type(observed_now), "number")
   test.equal(type(observed_monotonic), "number")
   test.truthy(observed_now > 0)
   test.truthy(observed_monotonic > 0)
end)
