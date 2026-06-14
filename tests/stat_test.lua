local stat = require("stat")
local test = require("test")

test.case("stat.MetricBundle stores fixed-capacity sampled metrics", function()
   local bundle = stat.MetricBundle {
      capacity = 3,
      stored_metrics = {
         "frame_start_seconds",
         "frame_end_seconds",
         { name = "cpu_ms", time = "frame_end_seconds" },
         { name = "total_ms", time = "frame_end_seconds" },
      },
   }

   test.equal(bundle.capacity, 3)
   test.equal(bundle.count, 0)
   test.equal(bundle:metric_kind("cpu_ms"), "stored")
   test.equal(bundle:time_axis("cpu_ms"), "frame_end_seconds")

   bundle:begin_sample()
   bundle:set("frame_start_seconds", 0.0)
   bundle:set("frame_end_seconds", 0.010)
   bundle:set("cpu_ms", 4.0)
   bundle:set("total_ms", 8.0)
   bundle:commit()

   bundle:begin_sample()
   bundle:set("frame_start_seconds", 0.010)
   bundle:set("frame_end_seconds", 0.020)
   bundle:set("cpu_ms", 5.0)
   bundle:set("total_ms", 9.0)
   bundle:commit()

   test.equal(bundle.count, 2)
   test.truthy(math.abs(bundle:get("cpu_ms", 1) - 4.0) < 0.000001)
   test.truthy(math.abs(bundle:get("cpu_ms", 0) - 5.0) < 0.000001)
   test.truthy(math.abs(bundle:latest("total_ms") - 9.0) < 0.000001)
end)

test.case("stat.MetricBundle evaluates pointwise derived metrics on demand", function()
   local bundle = stat.MetricBundle {
      capacity = 4,
      stored_metrics = {
         "frame_start_seconds",
         "frame_end_seconds",
         { name = "cpu_ms", time = "frame_end_seconds" },
         { name = "total_ms", time = "frame_end_seconds" },
         { name = "interval_ms", time = "frame_start_seconds" },
      },
      derived_metrics = {
         {
            name = "present_ms",
            deps = { "total_ms", "cpu_ms" },
            calc = function(total_ms, cpu_ms)
               local value = total_ms - cpu_ms
               if value < 0.0 then
                  return 0.0
               end
               return value
            end,
         },
         {
            name = "gap_ms",
            deps = { "interval_ms", "total_ms" },
            time = "frame_start_seconds",
            calc = function(interval_ms, total_ms)
               local value = interval_ms - total_ms
               if value < 0.0 then
                  return 0.0
               end
               return value
            end,
         },
      },
   }

   bundle:begin_sample()
   bundle:set("frame_start_seconds", 0.0)
   bundle:set("frame_end_seconds", 0.010)
   bundle:set("cpu_ms", 4.0)
   bundle:set("total_ms", 9.0)
   bundle:set("interval_ms", 11.0)
   bundle:commit()

   test.equal(bundle:metric_kind("present_ms"), "derived")
   test.equal(bundle:time_axis("present_ms"), "frame_end_seconds")
   test.equal(bundle:time_axis("gap_ms"), "frame_start_seconds")
   test.truthy(math.abs(bundle:get("present_ms") - 5.0) < 0.000001)
   test.truthy(math.abs(bundle:get("gap_ms") - 2.0) < 0.000001)
end)

test.case("stat.MetricBundle maintains window metrics incrementally", function()
   local bundle = stat.MetricBundle {
      capacity = 4,
      stored_metrics = {
         "frame_start_seconds",
         "frame_end_seconds",
         { name = "cpu_ms", time = "frame_end_seconds" },
         { name = "total_ms", time = "frame_end_seconds" },
      },
      derived_metrics = {
         {
            name = "present_ms",
            deps = { "total_ms", "cpu_ms" },
            calc = function(total_ms, cpu_ms)
               local value = total_ms - cpu_ms
               if value < 0.0 then
                  return 0.0
               end
               return value
            end,
         },
      },
      window_metrics = {
         {
            name = "cpu_max_1s_ms",
            source = "cpu_ms",
            time = "frame_end_seconds",
            window_seconds = 1.0,
            reduce = "max",
         },
         {
            name = "present_mean_1s_ms",
            source = "present_ms",
            window_seconds = 1.0,
            reduce = "mean",
         },
      },
   }

   local samples = {
      { frame_start_seconds = 0.0, frame_end_seconds = 0.2, cpu_ms = 2.0, total_ms = 5.0 },
      { frame_start_seconds = 0.5, frame_end_seconds = 0.8, cpu_ms = 5.0, total_ms = 9.0 },
      { frame_start_seconds = 1.2, frame_end_seconds = 1.5, cpu_ms = 3.0, total_ms = 8.0 },
      { frame_start_seconds = 1.7, frame_end_seconds = 1.9, cpu_ms = 1.0, total_ms = 4.0 },
   }

   for i = 1, #samples do
      local sample = samples[i]
      bundle:begin_sample()
      bundle:set("frame_start_seconds", sample.frame_start_seconds)
      bundle:set("frame_end_seconds", sample.frame_end_seconds)
      bundle:set("cpu_ms", sample.cpu_ms)
      bundle:set("total_ms", sample.total_ms)
      bundle:commit()
   end

   test.equal(bundle:metric_kind("cpu_max_1s_ms"), "window")
   test.equal(bundle:time_axis("cpu_max_1s_ms"), "frame_end_seconds")
   test.equal(bundle:time_axis("present_mean_1s_ms"), "frame_end_seconds")

   test.truthy(math.abs(bundle:get("cpu_max_1s_ms", 3) - 2.0) < 0.000001)
   test.truthy(math.abs(bundle:get("cpu_max_1s_ms", 2) - 5.0) < 0.000001)
   test.truthy(math.abs(bundle:get("cpu_max_1s_ms", 1) - 5.0) < 0.000001)
   test.truthy(math.abs(bundle:get("cpu_max_1s_ms", 0) - 3.0) < 0.000001)

   test.truthy(math.abs(bundle:get("present_mean_1s_ms", 3) - 3.0) < 0.000001)
   test.truthy(math.abs(bundle:get("present_mean_1s_ms", 2) - 3.5) < 0.000001)
   test.truthy(math.abs(bundle:get("present_mean_1s_ms", 1) - 4.5) < 0.000001)
   test.truthy(math.abs(bundle:get("present_mean_1s_ms", 0) - 4.0) < 0.000001)
end)

test.case("stat.MetricBundle reset clears retained samples and window state", function()
   local bundle = stat.MetricBundle {
      capacity = 2,
      stored_metrics = {
         "frame_end_seconds",
         { name = "cpu_ms", time = "frame_end_seconds" },
      },
      window_metrics = {
         {
            name = "cpu_sum_1s_ms",
            source = "cpu_ms",
            time = "frame_end_seconds",
            window_seconds = 1.0,
            reduce = "sum",
         },
      },
   }

   bundle:begin_sample()
   bundle:set("frame_end_seconds", 0.2)
   bundle:set("cpu_ms", 2.0)
   bundle:commit()

   test.truthy(math.abs(bundle:get("cpu_sum_1s_ms") - 2.0) < 0.000001)
   bundle:reset()
   test.equal(bundle.count, 0)
   test.equal(bundle:get("cpu_ms"), nil)
   test.equal(bundle:get("cpu_sum_1s_ms"), nil)
end)
