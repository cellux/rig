local test = require("test")
local sdl3 = require("sdl3")

test.case("sdl3 runtime options validate event handlers and driver config shapes", function()
   local bad_handlers_ok, bad_handlers_err = pcall(function()
      rig.run {
         driver = "sdl3",
         event_handlers = {
            key = "bad",
         },
      }
   end)
   test.falsey(bad_handlers_ok)
   test.match(
      tostring(bad_handlers_err),
      "rig%.run options%.event_handlers%.key expects a function"
   )

   local bad_config_ok, bad_config_err = pcall(function()
      rig.run {
         driver = "sdl3",
         driver_config = {
            sdl3 = "bad",
         },
      }
   end)
   test.falsey(bad_config_ok)
   test.match(
      tostring(bad_config_err),
      "rig%.run options%.driver_config%.sdl3 expects a table"
   )
end)

test.case("sdl3 exposes time-related SDL APIs", function()
   test.equal(type(sdl3.GetCurrentTime), "function")
   test.equal(type(sdl3.GetTicks), "function")
   test.equal(type(sdl3.GetTicksNS), "function")
   test.equal(type(sdl3.GetPerformanceCounter), "function")
   test.equal(type(sdl3.GetPerformanceFrequency), "function")
   test.equal(type(sdl3.Delay), "function")
   test.equal(type(sdl3.DelayNS), "function")
   test.equal(type(sdl3.DelayPrecise), "function")
end)

test.case("sdl3 exposes thread-priority SDL APIs", function()
   test.equal(type(sdl3.SetCurrentThreadPriority), "function")
   test.truthy(type(sdl3.THREAD_PRIORITY_LOW) == "number")
   test.truthy(type(sdl3.THREAD_PRIORITY_NORMAL) == "number")
   test.truthy(type(sdl3.THREAD_PRIORITY_HIGH) == "number")
   test.truthy(type(sdl3.THREAD_PRIORITY_TIME_CRITICAL) == "number")
   test.equal(type(sdl3.HINT_THREAD_PRIORITY_POLICY), "string")
end)

test.case("sdl3 exposes SDL renderer drawing APIs", function()
   test.equal(type(sdl3.SetRenderDrawColor), "function")
   test.equal(type(sdl3.RenderClear), "function")
   test.equal(type(sdl3.RenderPoint), "function")
   test.equal(type(sdl3.RenderLine), "function")
   test.equal(type(sdl3.RenderFillRect), "function")
   test.equal(type(sdl3.CreateTexture), "function")
   test.equal(type(sdl3.UpdateTexture), "function")
   test.equal(type(sdl3.SetTextureColorMod), "function")
   test.equal(type(sdl3.SetTextureAlphaMod), "function")
   test.equal(type(sdl3.SetTextureBlendMode), "function")
   test.equal(type(sdl3.RenderTexture), "function")
   test.equal(type(sdl3.DestroyTexture), "function")
   test.equal(type(sdl3.get_renderer), "function")
end)

test.case("sdl3 exposes renderer texture constants", function()
   test.truthy(type(sdl3.PIXELFORMAT_RGBA8888) == "number")
   test.truthy(type(sdl3.PIXELFORMAT_RGBA32) == "number")
   test.truthy(type(sdl3.TEXTUREACCESS_STATIC) == "number")
   test.truthy(type(sdl3.TEXTUREACCESS_STREAMING) == "number")
   test.truthy(type(sdl3.TEXTUREACCESS_TARGET) == "number")
   test.truthy(type(sdl3.BLENDMODE_NONE) == "number")
   test.truthy(type(sdl3.BLENDMODE_BLEND) == "number")
   test.truthy(type(sdl3.BLENDMODE_ADD) == "number")
   test.truthy(type(sdl3.BLENDMODE_MOD) == "number")
   test.truthy(type(sdl3.BLENDMODE_MUL) == "number")
end)

test.case("sdl3 exposes mouse event constants", function()
   test.truthy(type(sdl3.EVENT_MOUSE_MOTION) == "number")
   test.truthy(type(sdl3.EVENT_MOUSE_BUTTON_DOWN) == "number")
   test.truthy(type(sdl3.EVENT_MOUSE_BUTTON_UP) == "number")
   test.truthy(type(sdl3.EVENT_WINDOW_RESIZED) == "number")
   test.truthy(type(sdl3.EVENT_WINDOW_PIXEL_SIZE_CHANGED) == "number")
   test.truthy(type(sdl3.BUTTON_LEFT) == "number")
   test.truthy(type(sdl3.BUTTON_MIDDLE) == "number")
   test.truthy(type(sdl3.BUTTON_RIGHT) == "number")
   test.equal(type(sdl3.GetMouseState), "function")
   test.equal(type(sdl3.GetWindowSize), "function")
   test.equal(type(sdl3.GetWindowSizeInPixels), "function")
end)

test.case("sdl3 GPU descriptor builders populate FFI structs", function()
   local vertex_buffers = sdl3.build_vertex_buffer_descriptions({
      {
         pitch = 24,
      },
   })
   test.equal(tonumber(vertex_buffers[0].slot), 0)
   test.equal(tonumber(vertex_buffers[0].pitch), 24)

   local attributes = sdl3.build_vertex_attributes({
      {
         location = 3,
         format = "float3",
         offset = 12,
      },
   })
   test.equal(tonumber(attributes[0].location), 3)
   test.equal(tonumber(attributes[0].offset), 12)

   local buffer_info = sdl3.build_gpu_buffer_create_info({
      usage = 5,
      size = 64,
      props = 7,
   })
   test.equal(tonumber(buffer_info[0].usage), 5)
   test.equal(tonumber(buffer_info[0].size), 64)
   test.equal(tonumber(buffer_info[0].props), 7)

   local color_targets = sdl3.build_color_target_descriptions({
      {
         format = 9,
         blend_state = {
            enable_blend = true,
         },
      },
   })
   test.equal(tonumber(color_targets[0].format), 9)
   test.truthy(color_targets[0].blend_state.enable_blend)
end)
