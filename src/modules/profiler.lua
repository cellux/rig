local M = ... or {}
local ffi = require("ffi")
local rig = require("rig")
local schema = require("schema")
local time = require("time")

local positive_number_schema = schema.positive_number {
   coerce = true,
}
local positive_integer_schema = schema.positive_integer {
   coerce = true,
}
local DEFAULT_HISTORY_FRAMES = 300
local DEFAULT_FPS_SMOOTHING_SECONDS = 0.5

ffi.cdef[[
typedef struct rig_profiler_past_frames {
   int capacity;
   int count;
   int next_index;
   double *frame_start_seconds;
   double *frame_end_seconds;
   double *cpu_ms;
   double *present_ms;
   double *total_ms;
   double *interval_ms;
   double *gap_ms;
} rig_profiler_past_frames;
]]

local frame_profiler_options_schema = schema.record({
   budget_ms = positive_number_schema:optional(),
   budget_fps = positive_number_schema:optional(),
   history_frames = positive_integer_schema:optional(DEFAULT_HISTORY_FRAMES),
   history_window_seconds = positive_number_schema:optional(1.0),
   fps_smoothing_seconds = positive_number_schema:optional(DEFAULT_FPS_SMOOTHING_SECONDS),
})

M.FrameProfiler = rig.class()

local function resolve_budget_ms(settings)
   if settings.budget_fps ~= nil then
      if settings.budget_ms ~= nil then
         rig.raise(
            "profiler.FrameProfiler options.budget_ms and options.budget_fps are mutually exclusive"
         )
      end
      return 1000.0 / settings.budget_fps
   end

   return settings.budget_ms
end

local function create_past_frames(capacity)
   local storage = {
      frame_start_seconds = ffi.new("double[?]", capacity),
      frame_end_seconds = ffi.new("double[?]", capacity),
      cpu_ms = ffi.new("double[?]", capacity),
      present_ms = ffi.new("double[?]", capacity),
      total_ms = ffi.new("double[?]", capacity),
      interval_ms = ffi.new("double[?]", capacity),
      gap_ms = ffi.new("double[?]", capacity),
   }

   local past_frames = ffi.new("rig_profiler_past_frames")
   past_frames.capacity = capacity
   past_frames.count = 0
   past_frames.next_index = 0
   past_frames.frame_start_seconds = storage.frame_start_seconds
   past_frames.frame_end_seconds = storage.frame_end_seconds
   past_frames.cpu_ms = storage.cpu_ms
   past_frames.present_ms = storage.present_ms
   past_frames.total_ms = storage.total_ms
   past_frames.interval_ms = storage.interval_ms
   past_frames.gap_ms = storage.gap_ms
   return past_frames, storage
end

local function clear_past_frames(past_frames)
   if past_frames == nil then
      return
   end

   past_frames.count = 0
   past_frames.next_index = 0

   local capacity = past_frames.capacity
   for i = 0, capacity - 1 do
      past_frames.frame_start_seconds[i] = 0.0
      past_frames.frame_end_seconds[i] = 0.0
      past_frames.cpu_ms[i] = 0.0
      past_frames.present_ms[i] = 0.0
      past_frames.total_ms[i] = 0.0
      past_frames.interval_ms[i] = 0.0
      past_frames.gap_ms[i] = 0.0
   end
end

local function compute_window_max(past_frames, values, timestamps, now_seconds, window_seconds, current_value)
   local max_window = current_value or 0.0
   local cutoff = now_seconds - window_seconds
   local capacity = past_frames.capacity
   local next_index = past_frames.next_index

   for offset = 0, past_frames.count - 1 do
      local index = next_index - offset - 1
      if index < 0 then
         index = index + capacity
      end

      local timestamp = timestamps[index]
      if timestamp < cutoff then
         break
      end

      local value = values[index]
      if value > max_window then
         max_window = value
      end
   end

   return max_window
end

local function record_past_frame(past_frames, profiler, frame_start_seconds, frame_end_seconds)
   local slot = past_frames.next_index
   past_frames.frame_start_seconds[slot] = frame_start_seconds
   past_frames.frame_end_seconds[slot] = frame_end_seconds
   past_frames.cpu_ms[slot] = profiler.cpu_ms
   past_frames.present_ms[slot] = profiler.present_ms
   past_frames.total_ms[slot] = profiler.total_ms
   past_frames.interval_ms[slot] = profiler.interval_ms
   past_frames.gap_ms[slot] = profiler.gap_ms

   slot = slot + 1
   if slot >= past_frames.capacity then
      slot = 0
   end
   past_frames.next_index = slot
   if past_frames.count < past_frames.capacity then
      past_frames.count = past_frames.count + 1
   end
end

function M.FrameProfiler:init(options)
   local settings = schema.assert(
      frame_profiler_options_schema,
      options or {},
      "profiler.FrameProfiler options"
   )

   self.budget_ms = resolve_budget_ms(settings)
   self.history_frames = settings.history_frames
   self.history_window_seconds = settings.history_window_seconds
   self.fps_smoothing_seconds = settings.fps_smoothing_seconds
   self.past_frames, self._past_frames_storage = create_past_frames(settings.history_frames)
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
   self._smoothed_interval_ms = nil
   clear_past_frames(self.past_frames)
end

function M.FrameProfiler:begin_frame()
   local frame_start_seconds = time.monotonic()
   local last_frame_seconds = self._last_frame_seconds

   if last_frame_seconds ~= nil then
      local interval_seconds = frame_start_seconds - last_frame_seconds
      self.interval_ms = interval_seconds * 1000.0
      self.fps_instant = 1000.0 / self.interval_ms
      if self.interval_ms > self.interval_max_ms then
         self.interval_max_ms = self.interval_ms
      end
      self.interval_max_1s_ms = compute_window_max(
         self.past_frames,
         self.past_frames.interval_ms,
         self.past_frames.frame_start_seconds,
         frame_start_seconds,
         self.history_window_seconds,
         self.interval_ms
      )

      if self._smoothed_interval_ms == nil then
         self._smoothed_interval_ms = self.interval_ms
      else
         local alpha = 1.0 - math.exp(-interval_seconds / self.fps_smoothing_seconds)
         self._smoothed_interval_ms = self._smoothed_interval_ms
            + (self.interval_ms - self._smoothed_interval_ms) * alpha
      end
      self.fps = 1000.0 / self._smoothed_interval_ms

      local gap_ms = self.interval_ms - self.total_ms
      if gap_ms < 0.0 then
         gap_ms = 0.0
      end
      self.gap_ms = gap_ms
      if self.gap_ms > self.gap_max_ms then
         self.gap_max_ms = self.gap_ms
      end
      self.gap_max_1s_ms = compute_window_max(
         self.past_frames,
         self.past_frames.gap_ms,
         self.past_frames.frame_start_seconds,
         frame_start_seconds,
         self.history_window_seconds,
         self.gap_ms
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
   self.cpu_max_1s_ms = compute_window_max(
      self.past_frames,
      self.past_frames.cpu_ms,
      self.past_frames.frame_end_seconds,
      frame_end_seconds,
      self.history_window_seconds,
      self.cpu_ms
   )

   self.total_ms = (frame_end_seconds - frame_start_seconds) * 1000.0
   if self.total_ms > self.total_max_ms then
      self.total_max_ms = self.total_ms
   end
   self.total_max_1s_ms = compute_window_max(
      self.past_frames,
      self.past_frames.total_ms,
      self.past_frames.frame_end_seconds,
      frame_end_seconds,
      self.history_window_seconds,
      self.total_ms
   )

   local present_ms = self.total_ms - self.cpu_ms
   if present_ms < 0.0 then
      present_ms = 0.0
   end
   self.present_ms = present_ms
   if self.present_ms > self.present_max_ms then
      self.present_max_ms = self.present_ms
   end
   self.present_max_1s_ms = compute_window_max(
      self.past_frames,
      self.past_frames.present_ms,
      self.past_frames.frame_end_seconds,
      frame_end_seconds,
      self.history_window_seconds,
      self.present_ms
   )

   local did_overrun = self.budget_ms ~= nil and self.total_ms > self.budget_ms
   if did_overrun then
      self.overruns = self.overruns + 1
   end
   record_past_frame(self.past_frames, self, frame_start_seconds, frame_end_seconds)

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
