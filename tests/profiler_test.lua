local profiler = require("profiler")
local test = require("test")
local time = require("time")

test.case("profiler.FrameProfiler applies defaults and coercion", function()
   local frame_profiler = profiler.FrameProfiler {
      fps = "40",
      history_seconds = "2.5",
   }

   test.equal(type(frame_profiler.begin_frame), "function")
   test.equal(frame_profiler.expected_fps, 40)
   test.equal(frame_profiler.budget_ms, 25)
   test.equal(frame_profiler.history_seconds, 2.5)
   test.equal(frame_profiler.history_frames, 100)
   test.equal(frame_profiler.history_window_seconds, 2.5)
   test.equal(frame_profiler.fps_smoothing_seconds, 2.5)
end)

test.case("profiler.FrameProfiler derives default history sizing from fps", function()
   local frame_profiler = profiler.FrameProfiler {
      fps = 60,
   }
   local snapshot = frame_profiler:snapshot()

   test.truthy(math.abs(frame_profiler.budget_ms - (1000.0 / 60.0)) < 0.000001)
   test.equal(frame_profiler.history_seconds, 1.0)
   test.equal(frame_profiler.history_frames, 60)
   test.equal(type(frame_profiler.past_frames.begin_sample), "function")
   test.equal(frame_profiler.past_frames.capacity, 60)
   test.equal(frame_profiler.past_frames.count, 0)
   test.equal(snapshot.cpu_ms, 0.0)
end)

test.case("profiler.FrameProfiler allocates MetricBundle past frame history", function()
   local frame_profiler = profiler.FrameProfiler {
      fps = "4",
      history_seconds = "0.5",
   }

   test.equal(frame_profiler.history_frames, 2)
   test.equal(frame_profiler.past_frames.capacity, 2)
   test.equal(frame_profiler.past_frames.count, 0)
   test.equal(frame_profiler.past_frames.next_index, 0)
   test.equal(frame_profiler.past_frames:metric_kind("frame_start_seconds"), "stored")
   test.equal(frame_profiler.past_frames:metric_kind("frame_end_seconds"), "stored")
   test.equal(frame_profiler.past_frames:metric_kind("present_ms"), "derived")
   test.equal(frame_profiler.past_frames:metric_kind("cpu_window_max_ms"), "window")
   test.equal(frame_profiler.past_frames:time_axis("cpu_ms"), "frame_start_seconds")
   test.equal(frame_profiler.past_frames:time_axis("present_ms"), "frame_start_seconds")
   test.equal(frame_profiler.past_frames:time_axis("total_ms"), "frame_start_seconds")
   test.equal(frame_profiler.past_frames:time_axis("interval_ms"), "frame_start_seconds")
   test.equal(frame_profiler.past_frames:time_axis("gap_ms"), "frame_start_seconds")
end)

test.case("profiler.FrameProfiler validates options through schema", function()
   local missing_ok, missing_err = pcall(function()
      profiler.FrameProfiler {
         fps = 0,
      }
   end)
   test.falsey(missing_ok)
   test.match(
      tostring(missing_err),
      "profiler%.FrameProfiler options%.fps expects a positive number"
   )

   local bad_type_ok, bad_type_err = pcall(function()
      profiler.FrameProfiler("bad")
   end)
   test.falsey(bad_type_ok)
   test.match(
      tostring(bad_type_err),
      "profiler%.FrameProfiler options expects a table"
   )

   local missing_fps_ok, missing_fps_err = pcall(function()
      profiler.FrameProfiler {
         history_seconds = 1.0,
      }
   end)
   test.falsey(missing_fps_ok)
   test.match(
      tostring(missing_fps_err),
      "profiler%.FrameProfiler options%.fps expects a number"
   )

   local bad_history_ok, bad_history_err = pcall(function()
      profiler.FrameProfiler {
         fps = 60,
         history_seconds = 0,
      }
   end)
   test.falsey(bad_history_ok)
   test.match(
      tostring(bad_history_err),
      "profiler%.FrameProfiler options%.history_seconds expects a positive number"
   )
end)

test.case("profiler.FrameProfiler records past frame measurements in MetricBundle history", function()
   local frame_profiler = profiler.FrameProfiler {
      fps = 100,
      history_seconds = 0.5,
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
   test.truthy(frame_profiler.pending_frame ~= nil)
   test.equal(frame_profiler.past_frames.capacity, 50)
   test.equal(frame_profiler.past_frames.count, 2)
   test.equal(frame_profiler.past_frames.next_index, 2)
   test.truthy(math.abs(frame_profiler.past_frames:get("frame_start_seconds", 0) - 0.010) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("frame_end_seconds", 0) - 0.018) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("cpu_ms", 0) - 3.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("present_ms", 0) - 5.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("total_ms", 0) - 8.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("interval_ms", 0) - 16.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("gap_ms", 0) - 8.0) < 0.000001)
   test.falsey(frame_profiler.past_frames:get("total_ms", 0) > frame_profiler.budget_ms)

   test.truthy(math.abs(frame_profiler.past_frames:get("frame_start_seconds", 1) - 0.000) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("frame_end_seconds", 1) - 0.005) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("cpu_ms", 1) - 2.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("present_ms", 1) - 3.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("total_ms", 1) - 5.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("interval_ms", 1) - 10.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.past_frames:get("gap_ms", 1) - 5.0) < 0.000001)
   test.falsey(frame_profiler.past_frames:get("total_ms", 1) > frame_profiler.budget_ms)
   local expected_smoothed_interval_ms = 10.0
      + (16.0 - 10.0) * (1.0 - math.exp(-0.016 / frame_profiler.fps_smoothing_seconds))
   local snapshot = frame_profiler:snapshot()
   test.truthy(math.abs(snapshot.fps_instant - 62.5) < 0.000001)
   test.truthy(math.abs(snapshot.fps - (1000.0 / expected_smoothed_interval_ms)) < 0.000001)
   test.truthy(math.abs(snapshot.cpu_ms - 3.0) < 0.000001)
   test.truthy(math.abs(snapshot.present_ms - 5.0) < 0.000001)
   test.truthy(math.abs(snapshot.total_ms - 8.0) < 0.000001)
   test.truthy(math.abs(snapshot.interval_ms - 16.0) < 0.000001)
   test.truthy(math.abs(snapshot.gap_ms - 8.0) < 0.000001)
   test.truthy(math.abs(snapshot.cpu_window_max_ms - 3.0) < 0.000001)
   test.truthy(math.abs(snapshot.present_window_max_ms - 5.0) < 0.000001)
   test.truthy(math.abs(snapshot.total_window_max_ms - 8.0) < 0.000001)
   test.truthy(math.abs(snapshot.interval_window_max_ms - 16.0) < 0.000001)
   test.truthy(math.abs(snapshot.gap_window_max_ms - 8.0) < 0.000001)
   test.truthy(math.abs(snapshot.cpu_peak_ms - 3.0) < 0.000001)
   test.truthy(math.abs(snapshot.present_peak_ms - 5.0) < 0.000001)
   test.truthy(math.abs(snapshot.total_peak_ms - 8.0) < 0.000001)
   test.truthy(math.abs(snapshot.interval_peak_ms - 16.0) < 0.000001)
   test.truthy(math.abs(snapshot.gap_peak_ms - 8.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.pending_frame.cpu_ms - 6.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.pending_frame.present_ms - 6.0) < 0.000001)
   test.truthy(math.abs(frame_profiler.pending_frame.total_ms - 12.0) < 0.000001)
end)
