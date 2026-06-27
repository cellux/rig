local M = ... or {}
local ffi = require("ffi")
local rig = require("rig")
local schema = require("schema")

local non_empty_string_schema = schema.non_empty_string()
local positive_integer_schema = schema.positive_integer {
   coerce = true,
}
local positive_number_schema = schema.positive_number {
   coerce = true,
}
local metric_names_schema = schema.array(non_empty_string_schema, { unique = true })
local reduce_kind_schema = schema.enum({
   "count",
   "max",
   "mean",
   "min",
   "sum",
})
local optional_metric_name_schema = schema.optional(non_empty_string_schema)
local stored_metric_schema = schema.record({
   name = non_empty_string_schema,
   time = optional_metric_name_schema,
})
local stored_metric_item_schema = schema.one_of({
   non_empty_string_schema,
   stored_metric_schema,
}, "a metric name string or stored metric table")
local derived_metric_schema = schema.record({
   name = non_empty_string_schema,
   deps = metric_names_schema,
   calc = schema.func(),
   time = optional_metric_name_schema,
})
local window_metric_schema = schema.record({
   name = non_empty_string_schema,
   source = non_empty_string_schema,
   time = optional_metric_name_schema,
   window_seconds = positive_number_schema,
   reduce = reduce_kind_schema,
})
local function make_empty_array() return {} end
local metric_bundle_options_schema = schema.record({
   capacity = positive_integer_schema,
   stored_metrics = schema.optional_with(schema.array(stored_metric_item_schema), make_empty_array),
   derived_metrics = schema.optional_with(schema.array(derived_metric_schema), make_empty_array),
   window_metrics = schema.optional_with(schema.array(window_metric_schema), make_empty_array),
})
local window_entry_array_type = ffi.typeof([[
   struct {
      double sequence;
      double time;
      double value;
   }[?]
]])
local write_marker_array_type = ffi.typeof("uint8_t[?]")

M.MetricBundle = rig.Class()
local Deque = rig.Class()

function Deque:init(capacity)
   self.capacity = capacity
   self._entries = ffi.new(window_entry_array_type, capacity)
   self._head = 0
   self._size = 0
end

function Deque:clear()
   self._head = 0
   self._size = 0
end

function Deque:empty()
   return self._size == 0
end

function Deque:front()
   return self._entries[self._head]
end

function Deque:back()
   local slot = self._head + self._size - 1
   while slot >= self.capacity do
      slot = slot - self.capacity
   end
   return self._entries[slot]
end

function Deque:push_back(sequence, time, value)
   if self._size >= self.capacity then
      rig.raise("stat.Deque push_back overflow")
   end

   local slot = self._head + self._size
   while slot >= self.capacity do
      slot = slot - self.capacity
   end
   local entry = self._entries[slot]
   entry.sequence = sequence
   entry.time = time
   entry.value = value
   self._size = self._size + 1
end

function Deque:pop_front()
   if self._size == 0 then
      rig.raise("stat.Deque pop_front underflow")
   end

   self._head = self._head + 1
   if self._head >= self.capacity then
      self._head = 0
   end
   self._size = self._size - 1
end

function Deque:pop_back()
   if self._size == 0 then
      rig.raise("stat.Deque pop_back underflow")
   end

   self._size = self._size - 1
end

local function build_stored_metric(value, index)
   if type(value) == "string" then
      return {
         kind = "stored",
         name = value,
         time = nil,
         marker_index = nil,
      }
   end

   return {
      kind = "stored",
      name = value.name,
      time = value.time,
      marker_index = nil,
   }
end

local function build_derived_metric(value, index)
   return {
      kind = "derived",
      name = value.name,
      deps = value.deps,
      calc = value.calc,
      time = value.time,
   }
end

local function build_window_metric(value, index)
   return {
      kind = "window",
      name = value.name,
      source = value.source,
      time = value.time,
      window_seconds = value.window_seconds,
      reduce = value.reduce,
      values = nil,
      _window_state = nil,
   }
end

local function clear_double_array(values, capacity)
   ffi.fill(values, ffi.sizeof("double") * capacity, 0)
end

local function clear_write_markers(markers, count)
   ffi.fill(markers, ffi.sizeof("uint8_t") * count, 0)
end

local function metric_slot(bundle, index)
   if bundle.count == 0 then
      return nil
   end

   local logical_index = index
   if logical_index == nil then
      logical_index = 0
   end
   if type(logical_index) ~= "number" or logical_index ~= math.floor(logical_index) then
      rig.raise("stat.MetricBundle:get expects index to be an integer if provided")
   end
   if logical_index < 0 or logical_index >= bundle.count then
      rig.raise(
         ("stat.MetricBundle:get index must be between 0 and %d"):format(bundle.count - 1)
      )
   end

   local slot = bundle.next_index - logical_index - 1
   while slot < 0 do
      slot = slot + bundle.capacity
   end
   while slot >= bundle.capacity do
      slot = slot - bundle.capacity
   end
   return slot
end

local function ensure_metric_exists(bundle, name, path)
   local metric = bundle._metrics_by_name[name]
   if metric == nil then
      rig.raise(path .. " references unknown metric '" .. name .. "'")
   end
   return metric
end

local function expect_metric_name(name, path)
   if type(name) ~= "string" or name == "" then
      rig.raise(path .. " name must be a non-empty string")
   end
   return name
end

local function ensure_non_window_dependency(metric, dependency_name, path)
   if metric.kind == "window" then
      rig.raise(path .. " cannot reference window metric '" .. dependency_name .. "'")
   end
end

local function resolve_metric_time(bundle, metric, resolved_times, visiting)
   if resolved_times[metric.name] then
      return metric.time
   end

   local visiting_set = visiting or {}
   if visiting_set[metric.name] then
      rig.raise(
         "stat.MetricBundle metric time resolution found a cycle at '"
            .. metric.name
            .. "'"
      )
   end
   visiting_set[metric.name] = true

   if metric.kind == "stored" then
      if metric.time ~= nil then
         local time_metric = ensure_metric_exists(
            bundle,
            metric.time,
            "stat.MetricBundle stored metric '" .. metric.name .. "'"
         )
         if time_metric.kind ~= "stored" then
            rig.raise(
               "stat.MetricBundle stored metric '"
                  .. metric.name
                  .. "' time axis must reference a stored metric"
            )
         end
      end
      resolved_times[metric.name] = true
      visiting_set[metric.name] = nil
      return metric.time
   end

   if metric.kind == "derived" then
      if metric.time ~= nil then
         local time_metric = ensure_metric_exists(
            bundle,
            metric.time,
            "stat.MetricBundle derived metric '" .. metric.name .. "'"
         )
         ensure_non_window_dependency(
            time_metric,
            metric.time,
            "stat.MetricBundle derived metric '" .. metric.name .. "' time axis"
         )
         resolved_times[metric.name] = true
         visiting_set[metric.name] = nil
         return metric.time
      end

      local inferred_time = nil
      for i = 1, #metric.deps do
         local dependency = ensure_metric_exists(
            bundle,
            metric.deps[i],
            "stat.MetricBundle derived metric '" .. metric.name .. "'"
         )
         ensure_non_window_dependency(
            dependency,
            metric.deps[i],
            "stat.MetricBundle derived metric '" .. metric.name .. "'"
         )
         local dependency_time = resolve_metric_time(
            bundle,
            dependency,
            resolved_times,
            visiting_set
         )
         if dependency_time == nil then
            rig.raise(
               "stat.MetricBundle derived metric '"
                  .. metric.name
                  .. "' must declare time because dependency '"
                  .. metric.deps[i]
                  .. "' has no time axis"
            )
         end
         if inferred_time == nil then
            inferred_time = dependency_time
         elseif inferred_time ~= dependency_time then
            rig.raise(
               "stat.MetricBundle derived metric '"
                  .. metric.name
                  .. "' must declare time because dependencies use different time axes"
            )
         end
      end

      metric.time = inferred_time
      resolved_times[metric.name] = true
      visiting_set[metric.name] = nil
      return metric.time
   end

   if metric.kind == "window" then
      local source_metric = ensure_metric_exists(
         bundle,
         metric.source,
         "stat.MetricBundle window metric '" .. metric.name .. "'"
      )
      ensure_non_window_dependency(
         source_metric,
         metric.source,
         "stat.MetricBundle window metric '" .. metric.name .. "' source"
      )
      resolve_metric_time(bundle, source_metric, resolved_times, visiting_set)

      if metric.time ~= nil then
         local time_metric = ensure_metric_exists(
            bundle,
            metric.time,
            "stat.MetricBundle window metric '" .. metric.name .. "'"
         )
         ensure_non_window_dependency(
            time_metric,
            metric.time,
            "stat.MetricBundle window metric '" .. metric.name .. "' time axis"
         )
         resolve_metric_time(bundle, time_metric, resolved_times, visiting_set)
      else
         metric.time = source_metric.time
         if metric.time == nil then
            rig.raise(
               "stat.MetricBundle window metric '"
                  .. metric.name
                  .. "' must declare time because source '"
                  .. metric.source
                  .. "' has no time axis"
            )
         end
      end

      resolved_times[metric.name] = true
      visiting_set[metric.name] = nil
      return metric.time
   end

   visiting_set[metric.name] = nil
   return nil
end

local function validate_derived_dependencies(bundle, metric, visiting, visited)
   if visited[metric.name] then
      return
   end
   if visiting[metric.name] then
      rig.raise(
         "stat.MetricBundle derived metric dependency cycle at '"
            .. metric.name
            .. "'"
      )
   end

   visiting[metric.name] = true
   for i = 1, #metric.deps do
      local dependency = ensure_metric_exists(
         bundle,
         metric.deps[i],
         "stat.MetricBundle derived metric '" .. metric.name .. "'"
      )
      if dependency.kind == "window" then
         rig.raise(
            "stat.MetricBundle derived metric '"
               .. metric.name
               .. "' cannot depend on window metric '"
               .. metric.deps[i]
               .. "'"
         )
      end
      if dependency.kind == "derived" then
         validate_derived_dependencies(bundle, dependency, visiting, visited)
      end
   end
   visiting[metric.name] = nil
   visited[metric.name] = true
end

local function evaluate_metric_at_slot(bundle, metric, slot, cache)
   local metric_cache = cache or {}
   if metric_cache[metric.name] ~= nil then
      return metric_cache[metric.name]
   end

   if metric.kind == "stored" or metric.kind == "window" then
      return metric.values[slot]
   end

   local args = {}
   for i = 1, #metric.deps do
      local dependency = bundle._metrics_by_name[metric.deps[i]]
      args[i] = evaluate_metric_at_slot(bundle, dependency, slot, metric_cache)
   end

   local value = tonumber(metric.calc(unpack(args, 1, #args)))
   if type(value) ~= "number" then
      rig.raise(
         "stat.MetricBundle derived metric '"
            .. metric.name
            .. "' calc must return a number"
      )
   end
   metric_cache[metric.name] = value
   return value
end

local function create_window_state(capacity, reduce)
   return {
      reduce = reduce,
      last_time = nil,
      entries = Deque(capacity),
      running_count = 0,
      running_sum = 0.0,
   }
end

local function reset_window_state(state)
   state.last_time = nil
   state.running_count = 0
   state.running_sum = 0.0
   state.entries:clear()
end

local function window_entry_expired(entry, cutoff_time, minimum_sequence)
   return entry.time < cutoff_time or entry.sequence < minimum_sequence
end

local function prune_window_state(state, cutoff_time, minimum_sequence)
   while not state.entries:empty() do
      local entry = state.entries:front()
      if not window_entry_expired(entry, cutoff_time, minimum_sequence) then
         break
      end
      if state.reduce == "sum" or state.reduce == "mean" then
         state.running_count = state.running_count - 1
         state.running_sum = state.running_sum - entry.value
      elseif state.reduce == "count" then
         state.running_count = state.running_count - 1
      end
      state.entries:pop_front()
   end
end

local function append_window_entry(state, sequence, time_value, source_value)
   if state.reduce == "max" then
      while not state.entries:empty() and state.entries:back().value <= source_value do
         state.entries:pop_back()
      end
   elseif state.reduce == "min" then
      while not state.entries:empty() and state.entries:back().value >= source_value do
         state.entries:pop_back()
      end
   elseif state.reduce == "sum" or state.reduce == "mean" then
      state.running_count = state.running_count + 1
      state.running_sum = state.running_sum + source_value
   elseif state.reduce == "count" then
      state.running_count = state.running_count + 1
   else
      rig.raise("stat.MetricBundle unknown window reduce kind '" .. tostring(state.reduce) .. "'")
   end

   state.entries:push_back(sequence, time_value, source_value)
end

local function current_window_value(state)
   if state.entries:empty() then
      return 0.0
   end
   if state.reduce == "max" or state.reduce == "min" then
      return state.entries:front().value
   end
   if state.reduce == "sum" then
      return state.running_sum
   end
   if state.reduce == "count" then
      return state.running_count
   end
   if state.reduce == "mean" then
      if state.running_count == 0 then
         return 0.0
      end
      return state.running_sum / state.running_count
   end
   rig.raise("stat.MetricBundle unknown window reduce kind '" .. tostring(state.reduce) .. "'")
end

local function update_window_metric(bundle, metric, slot, sequence)
   local cache = {}
   local source_metric = bundle._metrics_by_name[metric.source]
   local time_metric = bundle._metrics_by_name[metric.time]
   local source_value = evaluate_metric_at_slot(bundle, source_metric, slot, cache)
   local time_value = evaluate_metric_at_slot(bundle, time_metric, slot, cache)
   local state = metric._window_state

   if state.last_time ~= nil and time_value < state.last_time then
      rig.raise(
         "stat.MetricBundle window metric '"
            .. metric.name
            .. "' requires non-decreasing timestamps"
      )
   end
   state.last_time = time_value

   local cutoff_time = time_value - metric.window_seconds
   local minimum_sequence = sequence - bundle.capacity + 1

   prune_window_state(state, cutoff_time, minimum_sequence)
   append_window_entry(state, sequence, time_value, source_value)

   metric.values[slot] = current_window_value(state)
end

function M.MetricBundle:init(options)
   local settings = schema.assert(
      metric_bundle_options_schema,
      options or {},
      "stat.MetricBundle options"
   )

   self.capacity = settings.capacity
   self.count = 0
   self.next_index = 0
   self._sample_open = false
   self._commit_sequence = 0
   self._stored_metrics = {}
   self._window_metrics = {}
   self._metrics_by_name = {}
   self._write_markers = ffi.new(write_marker_array_type, #settings.stored_metrics)

   for i = 1, #settings.stored_metrics do
      local metric = build_stored_metric(settings.stored_metrics[i], i)
      if self._metrics_by_name[metric.name] ~= nil then
         rig.raise("stat.MetricBundle duplicate metric name '" .. metric.name .. "'")
      end
      metric.marker_index = i - 1
      metric.values = ffi.new("double[?]", self.capacity)
      self._metrics_by_name[metric.name] = metric
      table.insert(self._stored_metrics, metric)
   end

   for i = 1, #settings.derived_metrics do
      local metric = build_derived_metric(settings.derived_metrics[i], i)
      if self._metrics_by_name[metric.name] ~= nil then
         rig.raise("stat.MetricBundle duplicate metric name '" .. metric.name .. "'")
      end
      self._metrics_by_name[metric.name] = metric
   end

   for i = 1, #settings.window_metrics do
      local metric = build_window_metric(settings.window_metrics[i], i)
      if self._metrics_by_name[metric.name] ~= nil then
         rig.raise("stat.MetricBundle duplicate metric name '" .. metric.name .. "'")
      end
      metric.values = ffi.new("double[?]", self.capacity)
      metric._window_state = create_window_state(self.capacity, metric.reduce)
      self._metrics_by_name[metric.name] = metric
      table.insert(self._window_metrics, metric)
   end

   local visited = {}
   for _, metric in pairs(self._metrics_by_name) do
      if metric.kind == "derived" then
         validate_derived_dependencies(self, metric, {}, visited)
      end
   end
   local resolved_times = {}
   for _, metric in pairs(self._metrics_by_name) do
      resolve_metric_time(self, metric, resolved_times, {})
   end

   self:reset()
end

function M.MetricBundle:begin_sample()
   if self._sample_open then
      rig.raise("stat.MetricBundle begin_sample called while a sample is already open")
   end
   self._sample_open = true
   clear_write_markers(self._write_markers, #self._stored_metrics)
end

function M.MetricBundle:set(name, value)
   if not self._sample_open then
      rig.raise("stat.MetricBundle set called without begin_sample")
   end

   local metric_name = expect_metric_name(name, "stat.MetricBundle:set")
   local metric = ensure_metric_exists(self, metric_name, "stat.MetricBundle:set")
   if metric.kind ~= "stored" then
      rig.raise(
         "stat.MetricBundle:set can only write stored metrics, got '" .. metric_name .. "'"
      )
   end

   local numeric_value = tonumber(value)
   if type(numeric_value) ~= "number" then
      rig.raise("stat.MetricBundle:set value for '" .. metric_name .. "' must be a number")
   end

   metric.values[self.next_index] = numeric_value
   self._write_markers[metric.marker_index] = 1
end

function M.MetricBundle:commit()
   if not self._sample_open then
      rig.raise("stat.MetricBundle commit called without begin_sample")
   end

   local slot = self.next_index
   for i = 1, #self._stored_metrics do
      local metric = self._stored_metrics[i]
      if self._write_markers[metric.marker_index] == 0 then
         rig.raise(
            "stat.MetricBundle commit missing stored metric '" .. metric.name .. "'"
         )
      end
   end

   self._commit_sequence = self._commit_sequence + 1
   for i = 1, #self._window_metrics do
      update_window_metric(self, self._window_metrics[i], slot, self._commit_sequence)
   end

   slot = slot + 1
   if slot >= self.capacity then
      slot = 0
   end
   self.next_index = slot
   if self.count < self.capacity then
      self.count = self.count + 1
   end

   self._sample_open = false
end

function M.MetricBundle:reset()
   self.count = 0
   self.next_index = 0
   self._sample_open = false
   self._commit_sequence = 0
   clear_write_markers(self._write_markers, #self._stored_metrics)

   for i = 1, #self._stored_metrics do
      clear_double_array(self._stored_metrics[i].values, self.capacity)
   end
   for i = 1, #self._window_metrics do
      local metric = self._window_metrics[i]
      clear_double_array(metric.values, self.capacity)
      reset_window_state(metric._window_state)
   end
end

function M.MetricBundle:get(name, index)
   local metric_name = expect_metric_name(name, "stat.MetricBundle:get")
   local metric = ensure_metric_exists(self, metric_name, "stat.MetricBundle:get")
   local slot = metric_slot(self, index)
   if slot == nil then
      return nil
   end
   return evaluate_metric_at_slot(self, metric, slot, {})
end

function M.MetricBundle:latest(name)
   return self:get(name)
end

function M.MetricBundle:metric_kind(name)
   local metric_name = expect_metric_name(name, "stat.MetricBundle:metric_kind")
   return ensure_metric_exists(self, metric_name, "stat.MetricBundle:metric_kind").kind
end

function M.MetricBundle:time_axis(name)
   local metric_name = expect_metric_name(name, "stat.MetricBundle:time_axis")
   return ensure_metric_exists(self, metric_name, "stat.MetricBundle:time_axis").time
end

return M
