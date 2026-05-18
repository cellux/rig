local M = ... or {}
local time = require("time")

local frame_profiler_mt = {}
frame_profiler_mt.__index = frame_profiler_mt

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

local function ensure_frame_profiler(frame_profiler)
   if getmetatable(frame_profiler) ~= frame_profiler_mt then
      error("profiler operation expects a frame profiler created by profiler.create_frame_profiler", 0)
   end
end

function frame_profiler_mt:reset()
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
end

function frame_profiler_mt:begin_frame()
   local frame_start_seconds = time.monotonic()
   local last_frame_seconds = self._last_frame_seconds

   if last_frame_seconds ~= nil then
      self.interval_ms = (frame_start_seconds - last_frame_seconds) * 1000.0
      if self.interval_ms > self.interval_max_ms then
         self.interval_max_ms = self.interval_ms
      end
      self.interval_max_1s_ms = update_metric_history(
         self._interval_history,
         frame_start_seconds,
         self.interval_ms,
         self.history_window_seconds
      )

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

function frame_profiler_mt:end_frame()
   local frame_start_seconds = self._frame_start_seconds
   if frame_start_seconds == nil then
      error("frame profiler end_frame called without a matching begin_frame", 0)
   end
   if self._cpu_section_start_seconds ~= nil then
      error("frame profiler end_frame called while a CPU section is still open", 0)
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

function frame_profiler_mt:begin_cpu()
   if self._frame_start_seconds == nil then
      error("frame profiler begin_cpu called without an active frame", 0)
   end
   if self._cpu_section_start_seconds ~= nil then
      error("frame profiler begin_cpu called while a CPU section is already open", 0)
   end

   self._cpu_section_start_seconds = time.monotonic()
end

function frame_profiler_mt:end_cpu()
   local cpu_section_start_seconds = self._cpu_section_start_seconds
   if cpu_section_start_seconds == nil then
      error("frame profiler end_cpu called without a matching begin_cpu", 0)
   end

   self._cpu_accumulator_ms =
      self._cpu_accumulator_ms + (time.monotonic() - cpu_section_start_seconds) * 1000.0
   self._cpu_section_start_seconds = nil
end

function frame_profiler_mt:snapshot()
   return self
end

function frame_profiler_mt:before_frame_hook()
   return function()
      self:begin_frame()
   end
end

function frame_profiler_mt:after_frame_hook()
   return function()
      self:end_frame()
   end
end

function M.create_frame_profiler(options)
   local settings = options
   if settings == nil then
      settings = {}
   end
   if type(settings) ~= "table" then
      error("profiler.create_frame_profiler expects options to be a table if provided", 0)
   end

   local budget_ms = settings.budget_ms
   if budget_ms == nil then
      budget_ms = 16.67
   end
   budget_ms = tonumber(budget_ms)
   if budget_ms == nil or budget_ms <= 0 then
      error("profiler.create_frame_profiler expects options.budget_ms to be a positive number if provided", 0)
   end

   local history_window_seconds = settings.history_window_seconds
   if history_window_seconds == nil then
      history_window_seconds = 1.0
   end
   history_window_seconds = tonumber(history_window_seconds)
   if history_window_seconds == nil or history_window_seconds <= 0 then
      error(
         "profiler.create_frame_profiler expects options.history_window_seconds to be a positive number if provided",
         0
      )
   end

   local frame_profiler = setmetatable({
      budget_ms = budget_ms,
      history_window_seconds = history_window_seconds,
   }, frame_profiler_mt)
   frame_profiler:reset()
   return frame_profiler
end

return M
