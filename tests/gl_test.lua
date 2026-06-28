local test = require("test")
local ffi = require("ffi")
local gl = require("gl")

local observed_name = nil
local observed_args = nil
local fake_viewport = ffi.cast("rig_gl__Viewport", function(x, y, width, height)
   observed_args = {
      tonumber(x),
      tonumber(y),
      tonumber(width),
      tonumber(height),
   }
end)

test.case("gl resolves entry points through the gl.resolver service", function()
   rig.register_service_provider("gl.resolver", "gl_test_provider", {
      get_gl_proc_address = function(name)
         observed_name = name
         return ffi.cast("void *", fake_viewport)
      end,
   })

   rig.register_runtime_driver("gl_test_driver", {
      loop = function()
         gl.Viewport(1, 2, 320, 200)
      end,
   })

   rig.run {
      driver = "gl_test_driver",
      providers = {
         ["gl.resolver"] = "gl_test_provider",
      },
   }

   test.equal(observed_name, "glViewport")
   test.equal(observed_args[1], 1)
   test.equal(observed_args[2], 2)
   test.equal(observed_args[3], 320)
   test.equal(observed_args[4], 200)
end)
