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

test.case("gl resolves entry points through an installed resolver", function()
   gl.set_resolver({
      get_gl_proc_address = function(name)
         observed_name = name
         return ffi.cast("void *", fake_viewport)
      end,
   })

   gl.Viewport(1, 2, 320, 200)

   test.equal(observed_name, "glViewport")
   test.equal(observed_args[1], 1)
   test.equal(observed_args[2], 2)
   test.equal(observed_args[3], 320)
   test.equal(observed_args[4], 200)

   gl.clear_resolver()
end)

test.case("changing the gl resolver drops cached entry points", function()
   gl.set_resolver({
      get_gl_proc_address = function()
         return ffi.cast("void *", fake_viewport)
      end,
   })

   -- Normal indexing resolves and caches the entry point.
   test.truthy(gl.Viewport ~= nil)
   test.truthy(rawget(gl, "Viewport") ~= nil)

   gl.clear_resolver()
   test.equal(rawget(gl, "Viewport"), nil)
end)

test.case("gl reports a missing resolver", function()
   gl.clear_resolver()

   local ok, err = pcall(function()
      gl.ClearColor(0, 0, 0, 1)
   end)

   test.falsey(ok)
   test.match(tostring(err), "require a gl%.resolver")
end)
