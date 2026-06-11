local ffi = require("ffi")
local profiler = require("profiler")
local test = require("test")
local time = require("time")

test.case("profiler.FrameProfiler applies defaults and coercion", function()
   local frame_profiler = profiler.FrameProfiler {
      budget_ms = "20",
      history_window_seconds = "2.5",
      fps_smoothing_seconds = "0.5",
   }

   test.equal(type(frame_profiler.begin_frame), "function")
   test.equal(frame_profiler.budget_ms, 20)
   test.equal(frame_profiler.history_window_seconds, 2.5)
   test.equal(frame_profiler.fps_smoothing_seconds, 0.5)
end)

test.case("profiler.FrameProfiler leaves budget_ms unset by default", function()
   local frame_profiler = profiler.FrameProfiler()

   test.equal(frame_profiler.budget_ms, nil)
   test.equal(frame_profiler.history_frames, 300)
   test.equal(type(frame_profiler.past_frames), "cdata")
   test.equal(frame_profiler.past_frames.capacity, 300)
   test.equal(frame_profiler.past_frames.count, 0)
end)

test.case("profiler.FrameProfiler allocates FFI past frame ring buffers", function()
   local frame_profiler = profiler.FrameProfiler {
      history_frames = "2",
   }

   test.equal(frame_profiler.history_frames, 2)
   test.equal(type(frame_profiler.past_frames), "cdata")
   test.equal(ffi.typeof(frame_profiler.past_frames), ffi.typeof("rig_profiler_past_frames"))
   test.equal(frame_profiler.past_frames.capacity, 2)
   test.equal(frame_profiler.past_frames.count, 0)
   test.equal(frame_profiler.past_frames.next_index, 0)
   test.truthy(frame_profiler.past_frames.frame_start_seconds ~= nil)
   test.truthy(frame_profiler.past_frames.frame_end_seconds ~= nil)
end)

test.case("profiler.FrameProfiler derives budget_ms from budget_fps", function()
   local frame_profiler = profiler.FrameProfiler {
      budget_fps = "60",
   }

   test.truthy(math.abs(frame_profiler.budget_ms - (1000.0 / 60.0)) < 0.000001)
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

   local conflicting_ok, conflicting_err = pcall(function()
      profiler.FrameProfiler {
         budget_ms = 20,
         budget_fps = 60,
      }
   end)
   test.falsey(conflicting_ok)
   test.match(
      tostring(conflicting_err),
      "profiler%.FrameProfiler options%.budget_ms and options%.budget_fps are mutually exclusive"
   )

   local bad_history_ok, bad_history_err = pcall(function()
      profiler.FrameProfiler {
         history_frames = 0,
      }
   end)
   test.falsey(bad_history_ok)
   test.match(
      tostring(bad_history_err),
      "profiler%.FrameProfiler options%.history_frames expects a positive integer"
   )
end)

test.case("profiler.FrameProfiler records past frame measurements in a ring buffer", function()
   local frame_profiler = profiler.FrameProfiler {
      budget_ms = 10,
      history_frames = 2,
      fps_smoothing_seconds = 0.5,
   }

   local original_monotonic = time.monotonic
   local samples = {
      0.000,
      0.001,
      0.003,
      0.005,
      0.010,
      0.011,
      0.014,
      0.018,
      0.026,
      0.027,
      0.033,
      0.038,
   }
   local sample_index = 0

   time.monotonic = function()
      sample_index = sample_index + 1
      return samples[sample_index]
   end

   local ok, err = pcall(function()
      for _ = 1, 3 do
         frame_profiler:begin_frame()
         frame_profiler:begin_cpu()
         frame_profiler:end_cpu()
         frame_profiler:end_frame()
      end
   end)

   time.monotonic = original_monotonic

   test.truthy(ok, tostring(err))
   test.equal(frame_profiler.overruns, 1)
   test.equal(frame_profiler.past_frames.capacity, 2)
   test.equal(frame_profiler.past_frames.count, 2)
   test.equal(frame_profiler.past_frames.next_index, 1)
   test.truthy(math.abs(frame_profiler.past_frames.frame_start_seconds[0] - 0.026) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.frame_end_seconds[0] - 0.038) < 0.000001)

   test.truthy(math.abs(frame_profiler.past_frames.cpu_ms[0] - 6.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.present_ms[0] - 6.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.total_ms[0] - 12.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.interval_ms[0] - 16.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.gap_ms[0] - 8.0) < 0.000001)
   test.truthy(frame_profiler.past_frames.total_ms[0] > frame_profiler.budget_ms)

   test.truthy(math.abs(frame_profiler.past_frames.frame_start_seconds[1] - 0.010) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.frame_end_seconds[1] - 0.018) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.cpu_ms[1] - 3.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.present_ms[1] - 5.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.total_ms[1] - 8.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.interval_ms[1] - 10.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames.gap_ms[1] - 5.0) < 0.000001)
   test.falsey(frame_profiler.past_frames.total_ms[1] > frame_profiler.budget_ms)
   local expected_smoothed_interval_ms = 10.0
      + (16.0 - 10.0) * (1.0 - math.exp(-0.016 / frame_profiler.fps_smoothing_seconds))
   test.truthy(math.abs(frame_profiler.fps_instant - 62.5) < 0.000001)
   test.truthy(math.abs(frame_profiler.fps - (1000.0 / expected_smoothed_interval_ms)) < 0.000001)
   test.truthy(math.abs(frame_profiler.cpu_max_1s_ms - 6.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.present_max_1s_ms - 6.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.total_max_1s_ms - 12.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.interval_max_1s_ms - 16.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.gap_max_1s_ms - 8.0) < 0.000001)
end)
