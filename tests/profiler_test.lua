local profiler = require("profiler")
local test = require("test")

test.case("profiler.FrameProfiler applies defaults and coercion", function()
   local frame_profiler = profiler.FrameProfiler {
      budget_ms = "20",
      history_window_seconds = "2.5",
      fps_window_seconds = "0.5",
   }

   test.equal(type(frame_profiler.begin_frame), "function")
   test.equal(frame_profiler.budget_ms, 20)
   test.equal(frame_profiler.history_window_seconds, 2.5)
   test.equal(frame_profiler.fps_window_seconds, 0.5)
end)

test.case("profiler.FrameProfiler validates options through schema", function()
   local missing_ok, missing_err = pcall(function()
      profiler.FrameProfiler {
         budget_ms = 0,
      }
   end)
   test.falsey(missing_ok)
   test.match(
      tostring(missing_err),
      "profiler%.FrameProfiler options%.budget_ms expects a positive number"
   )

   local bad_type_ok, bad_type_err = pcall(function()
      profiler.FrameProfiler("bad")
   end)
   test.falsey(bad_type_ok)
   test.match(
      tostring(bad_type_err),
      "profiler%.FrameProfiler options expects a table"
   )
end)
