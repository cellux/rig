local M = ... or {}
local rig = require("rig")
local schema = require("schema")
local time = require("time")

local positive_number_schema = schema.positive_number {
   coerce = true,
}

local frame_profiler_options_schema = schema.record({
   budget_ms = positive_number_schema:optional(16.67),
   history_window_seconds = positive_number_schema:optional(1.0),
   fps_window_seconds = positive_number_schema:optional(0.25),
})

M.FrameProfiler = rig.class()

local function update_metric_history(history, now_seconds, value, window_seconds)
   history[#history + 1] = {
      t = now_seconds,
      v = value,
   }

   local cutoff = now_seconds - window_seconds
   while history[1] ~= nil and history[1].t < cutoff do
      table.remove(history, 1)
   end

   local max_window = 0.0
   for i = 1, #history do
      if history[i].v > max_window then
         max_window = history[i].v
      end
   end
   return max_window
end

function M.FrameProfiler:init(options)
   local settings = schema.assert(
      frame_profiler_options_schema,
      options or {},
      "profiler.FrameProfiler options"
   )

   self.budget_ms = settings.budget_ms
   self.history_window_seconds = settings.history_window_seconds
   self.fps_window_seconds = settings.fps_window_seconds
   self:reset()
end

function M.FrameProfiler:reset()
   self.fps = 0.0
   self.fps_instant = 0.0
   self.cpu_ms = 0.0
   self.cpu_max_1s_ms = 0.0
   self.cpu_max_ms = 0.0
   self.present_ms = 0.0
   self.present_max_1s_ms = 0.0
   self.present_max_ms = 0.0
   self.total_ms = 0.0
   self.total_max_1s_ms = 0.0
   self.total_max_ms = 0.0
   self.interval_ms = 0.0
   self.interval_max_1s_ms = 0.0
   self.interval_max_ms = 0.0
   self.gap_ms = 0.0
   self.gap_max_1s_ms = 0.0
   self.gap_max_ms = 0.0
   self.overruns = 0

   self._last_frame_seconds = nil
   self._frame_start_seconds = nil
   self._cpu_section_start_seconds = nil
   self._cpu_accumulator_ms = 0.0
   self._cpu_history = {}
   self._present_history = {}
   self._total_history = {}
   self._interval_history = {}
   self._gap_history = {}
   self._fps_sample_start_seconds = nil
   self._fps_sample_frame_count = 0
end

function M.FrameProfiler:begin_frame()
   local frame_start_seconds = time.monotonic()
   local last_frame_seconds = self._last_frame_seconds

   if last_frame_seconds ~= nil then
      self.interval_ms = (frame_start_seconds - last_frame_seconds) * 1000.0
      self.fps_instant = 1000.0 / self.interval_ms
      if self.interval_ms > self.interval_max_ms then
         self.interval_max_ms = self.interval_ms
      end
      self.interval_max_1s_ms = update_metric_history(
         self._interval_history,
         frame_start_seconds,
         self.interval_ms,
         self.history_window_seconds
      )

      if self._fps_sample_start_seconds == nil then
         self._fps_sample_start_seconds = last_frame_seconds
         self._fps_sample_frame_count = 0
      end
      self._fps_sample_frame_count = self._fps_sample_frame_count + 1

      local fps_elapsed_seconds = frame_start_seconds - self._fps_sample_start_seconds
      if fps_elapsed_seconds >= self.fps_window_seconds then
         self.fps = self._fps_sample_frame_count / fps_elapsed_seconds
         self._fps_sample_start_seconds = frame_start_seconds
         self._fps_sample_frame_count = 0
      elseif self.fps == 0.0 then
         self.fps = self.fps_instant
      end

      local gap_ms = self.interval_ms - self.total_ms
      if gap_ms < 0.0 then
         gap_ms = 0.0
      end
      self.gap_ms = gap_ms
      if self.gap_ms > self.gap_max_ms then
         self.gap_max_ms = self.gap_ms
      end
      self.gap_max_1s_ms = update_metric_history(
         self._gap_history,
         frame_start_seconds,
         self.gap_ms,
         self.history_window_seconds
      )
   end

   self._last_frame_seconds = frame_start_seconds
   self._frame_start_seconds = frame_start_seconds
   self._cpu_section_start_seconds = nil
   self._cpu_accumulator_ms = 0.0
   self.cpu_ms = 0.0
end

function M.FrameProfiler:end_frame()
   local frame_start_seconds = self._frame_start_seconds
   if frame_start_seconds == nil then
      rig.raise("frame profiler end_frame called without a matching begin_frame")
   end
   if self._cpu_section_start_seconds ~= nil then
      rig.raise("frame profiler end_frame called while a CPU section is still open")
   end

   self.cpu_ms = self._cpu_accumulator_ms
   local frame_end_seconds = time.monotonic()

   if self.cpu_ms > self.cpu_max_ms then
      self.cpu_max_ms = self.cpu_ms
   end
   self.cpu_max_1s_ms = update_metric_history(
      self._cpu_history,
      frame_end_seconds,
      self.cpu_ms,
      self.history_window_seconds
   )

   self.total_ms = (frame_end_seconds - frame_start_seconds) * 1000.0
   if self.total_ms > self.total_max_ms then
      self.total_max_ms = self.total_ms
   end
   self.total_max_1s_ms = update_metric_history(
      self._total_history,
      frame_end_seconds,
      self.total_ms,
      self.history_window_seconds
   )

   local present_ms = self.total_ms - self.cpu_ms
   if present_ms < 0.0 then
      present_ms = 0.0
   end
   self.present_ms = present_ms
   if self.present_ms > self.present_max_ms then
      self.present_max_ms = self.present_ms
   end
   self.present_max_1s_ms = update_metric_history(
      self._present_history,
      frame_end_seconds,
      self.present_ms,
      self.history_window_seconds
   )

   if self.total_ms > self.budget_ms then
      self.overruns = self.overruns + 1
   end

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
   return self
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
