local M = ... or {}
local rig = require("rig")
local schema = require("schema")
local stat = require("stat")
local time = require("time")

local positive_number_schema = schema.positive_number {
   coerce = true,
}

local frame_profiler_options_schema = schema.record({
   fps = positive_number_schema,
   history_seconds = positive_number_schema:optional(1.0),
})

M.FrameProfiler = rig.class()

local function create_past_frames(capacity, window_seconds)
   return stat.MetricBundle {
      capacity = capacity,
      stored_metrics = {
         "frame_start_seconds",
         "frame_end_seconds",
         { name = "cpu_ms", time = "frame_start_seconds" },
         { name = "total_ms", time = "frame_start_seconds" },
         { name = "interval_ms", time = "frame_start_seconds" },
         { name = "gap_ms", time = "frame_start_seconds" },
      },
      derived_metrics = {
         {
            name = "present_ms",
            deps = { "total_ms", "cpu_ms" },
            calc = function(total_ms, cpu_ms) return math.max(total_ms - cpu_ms, 0.0) end,
         },
      },
      window_metrics = {
         {
            name = "cpu_window_max_ms",
            source = "cpu_ms",
            window_seconds = window_seconds,
            reduce = "max",
         },
         {
            name = "present_window_max_ms",
            source = "present_ms",
            window_seconds = window_seconds,
            reduce = "max",
         },
         {
            name = "total_window_max_ms",
            source = "total_ms",
            window_seconds = window_seconds,
            reduce = "max",
         },
         {
            name = "interval_window_max_ms",
            source = "interval_ms",
            window_seconds = window_seconds,
            reduce = "max",
         },
         {
            name = "gap_window_max_ms",
            source = "gap_ms",
            window_seconds = window_seconds,
            reduce = "max",
         },
      },
   }
end

local function latest_or_zero(bundle, name)
   return bundle:latest(name) or 0.0
end

local function new_frame_metrics()
   return {
      overruns = 0,
      fps = 0.0,
      fps_instant = 0.0,
      cpu_ms = 0.0,
      cpu_window_max_ms = 0.0,
      cpu_peak_ms = 0.0,
      present_ms = 0.0,
      present_window_max_ms = 0.0,
      present_peak_ms = 0.0,
      total_ms = 0.0,
      total_window_max_ms = 0.0,
      total_peak_ms = 0.0,
      interval_ms = 0.0,
      interval_window_max_ms = 0.0,
      interval_peak_ms = 0.0,
      gap_ms = 0.0,
      gap_window_max_ms = 0.0,
      gap_peak_ms = 0.0,
   }
end

local function new_pending_frame()
   return {
      frame_start_seconds = 0.0,
      frame_end_seconds = 0.0,
      cpu_ms = 0.0,
      present_ms = 0.0,
      total_ms = 0.0,
   }
end

local function reset_frame_metrics(metrics)
   metrics.overruns = 0
   metrics.fps = 0.0
   metrics.fps_instant = 0.0
   metrics.cpu_ms = 0.0
   metrics.cpu_window_max_ms = 0.0
   metrics.cpu_peak_ms = 0.0
   metrics.present_ms = 0.0
   metrics.present_window_max_ms = 0.0
   metrics.present_peak_ms = 0.0
   metrics.total_ms = 0.0
   metrics.total_window_max_ms = 0.0
   metrics.total_peak_ms = 0.0
   metrics.interval_ms = 0.0
   metrics.interval_window_max_ms = 0.0
   metrics.interval_peak_ms = 0.0
   metrics.gap_ms = 0.0
   metrics.gap_window_max_ms = 0.0
   metrics.gap_peak_ms = 0.0
end

function M.FrameProfiler:init(options)
   local settings = schema.assert(
      frame_profiler_options_schema,
      options or {},
      "profiler.FrameProfiler options"
   )

   self.expected_fps = settings.fps
   self.history_seconds = settings.history_seconds
   self.budget_ms = 1000.0 / settings.fps
   self.history_frames = math.max(1, math.ceil(settings.fps * settings.history_seconds))
   self.history_window_seconds = settings.history_seconds
   self.fps_smoothing_seconds = settings.history_seconds
   self.past_frames = create_past_frames(self.history_frames, self.history_window_seconds)
   self:reset()
end

function M.FrameProfiler:reset()
   self.overruns = 0
   self._last_completed_frame = self._last_completed_frame or new_frame_metrics()
   self._next_completed_frame = self._next_completed_frame or new_frame_metrics()
   self._pending_frame = self._pending_frame or new_pending_frame()
   reset_frame_metrics(self._last_completed_frame)
   reset_frame_metrics(self._next_completed_frame)
   self.pending_frame = nil

   self._frame_start_seconds = nil
   self._cpu_section_start_seconds = nil
   self._cpu_accumulator_ms = 0.0
   self._smoothed_interval_ms = nil
   self.past_frames:reset()
end

function M.FrameProfiler:begin_frame()
   local frame_start_seconds = time.monotonic()
   local last_completed_frame = self._last_completed_frame
   local pending_frame = self.pending_frame

   if pending_frame ~= nil then
      local interval_seconds = frame_start_seconds - pending_frame.frame_start_seconds
      local interval_ms = interval_seconds * 1000.0
      local fps_instant = 1000.0 / interval_ms

      if self._smoothed_interval_ms == nil then
         self._smoothed_interval_ms = interval_ms
      else
         local alpha = 1.0 - math.exp(-interval_seconds / self.fps_smoothing_seconds)
         self._smoothed_interval_ms = self._smoothed_interval_ms
            + (interval_ms - self._smoothed_interval_ms) * alpha
      end
      local fps = 1000.0 / self._smoothed_interval_ms
      local gap_ms = math.max(interval_ms - pending_frame.total_ms, 0.0)

      self.past_frames:begin_sample()
      self.past_frames:set("frame_start_seconds", pending_frame.frame_start_seconds)
      self.past_frames:set("frame_end_seconds", pending_frame.frame_end_seconds)
      self.past_frames:set("cpu_ms", pending_frame.cpu_ms)
      self.past_frames:set("total_ms", pending_frame.total_ms)
      self.past_frames:set("interval_ms", interval_ms)
      self.past_frames:set("gap_ms", gap_ms)
      self.past_frames:commit()

      local completed_frame = self._next_completed_frame
      completed_frame.overruns = self.overruns
      completed_frame.fps = fps
      completed_frame.fps_instant = fps_instant
      completed_frame.cpu_ms = pending_frame.cpu_ms
      completed_frame.cpu_window_max_ms = latest_or_zero(self.past_frames, "cpu_window_max_ms")
      completed_frame.cpu_peak_ms = math.max(last_completed_frame.cpu_peak_ms, pending_frame.cpu_ms)
      completed_frame.present_ms = latest_or_zero(self.past_frames, "present_ms")
      completed_frame.present_window_max_ms = latest_or_zero(
         self.past_frames,
         "present_window_max_ms"
      )
      completed_frame.present_peak_ms = math.max(
         last_completed_frame.present_peak_ms,
         pending_frame.present_ms
      )
      completed_frame.total_ms = pending_frame.total_ms
      completed_frame.total_window_max_ms = latest_or_zero(self.past_frames, "total_window_max_ms")
      completed_frame.total_peak_ms = math.max(
         last_completed_frame.total_peak_ms,
         pending_frame.total_ms
      )
      completed_frame.interval_ms = interval_ms
      completed_frame.interval_window_max_ms = latest_or_zero(
         self.past_frames,
         "interval_window_max_ms"
      )
      completed_frame.interval_peak_ms = math.max(
         last_completed_frame.interval_peak_ms,
         interval_ms
      )
      completed_frame.gap_ms = latest_or_zero(self.past_frames, "gap_ms")
      completed_frame.gap_window_max_ms = latest_or_zero(self.past_frames, "gap_window_max_ms")
      completed_frame.gap_peak_ms = math.max(last_completed_frame.gap_peak_ms, gap_ms)

      self._next_completed_frame = self._last_completed_frame
      self._last_completed_frame = completed_frame
      self.pending_frame = nil
   end

   self._frame_start_seconds = frame_start_seconds
   self._cpu_section_start_seconds = nil
   self._cpu_accumulator_ms = 0.0
end

function M.FrameProfiler:end_frame()
   local frame_start_seconds = self._frame_start_seconds
   if frame_start_seconds == nil then
      rig.raise("frame profiler end_frame called without a matching begin_frame")
   end
   if self._cpu_section_start_seconds ~= nil then
      rig.raise("frame profiler end_frame called while a CPU section is still open")
   end

   local cpu_ms = self._cpu_accumulator_ms
   local frame_end_seconds = time.monotonic()
   local total_ms = (frame_end_seconds - frame_start_seconds) * 1000.0
   local present_ms = math.max(total_ms - cpu_ms, 0.0)

   local did_overrun = self.budget_ms ~= nil and total_ms > self.budget_ms
   if did_overrun then
      self.overruns = self.overruns + 1
   end

   local pending_frame = self._pending_frame
   pending_frame.frame_start_seconds = frame_start_seconds
   pending_frame.frame_end_seconds = frame_end_seconds
   pending_frame.cpu_ms = cpu_ms
   pending_frame.present_ms = present_ms
   pending_frame.total_ms = total_ms
   self.pending_frame = pending_frame

   self._frame_start_seconds = nil
end

function M.FrameProfiler:begin_cpu()
   if self._frame_start_seconds == nil then
      rig.raise("frame profiler begin_cpu called without an active frame")
   end
   if self._cpu_section_start_seconds ~= nil then
      rig.raise("frame profiler begin_cpu called while a CPU section is already open")
   end

   self._cpu_section_start_seconds = time.monotonic()
end

function M.FrameProfiler:end_cpu()
   local cpu_section_start_seconds = self._cpu_section_start_seconds
   if cpu_section_start_seconds == nil then
      rig.raise("frame profiler end_cpu called without a matching begin_cpu")
   end

   self._cpu_accumulator_ms =
      self._cpu_accumulator_ms + (time.monotonic() - cpu_section_start_seconds) * 1000.0
   self._cpu_section_start_seconds = nil
end

function M.FrameProfiler:snapshot()
   return self._last_completed_frame
end

function M.FrameProfiler:before_frame_hook()
   return function()
      self:begin_frame()
   end
end

function M.FrameProfiler:after_frame_hook()
   return function()
      self:end_frame()
   end
end

return M
