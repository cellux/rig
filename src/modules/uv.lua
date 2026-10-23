local M = ... or {}
local ffi = require("ffi")
local rig = require("rig")
local sched = require("sched")
local schema = require("schema")
local runtime = require("runtime")

ffi.cdef[[
typedef struct rig_uv_loop rig_uv_loop_t;

typedef void (*rig_uv_spawn_exit_cb)(
   int64_t exit_status,
   int term_signal,
   const char *stdout_data,
   size_t stdout_len,
   const char *stderr_data,
   size_t stderr_len
);
typedef void (*rig_uv_scandir_cb)(
   int status,
   const char *entries_data,
   size_t entries_len
);
typedef void (*rig_uv_timer_cb)(void);

rig_uv_loop_t *rig_uv_loop_new(void);
int rig_uv_loop_delete(rig_uv_loop_t *loop);
int rig_uv_run(rig_uv_loop_t *loop);
int rig_uv_run_nowait(rig_uv_loop_t *loop);
void rig_uv_stop(rig_uv_loop_t *loop);
const char *rig_uv_strerror(int err);
int rig_uv_spawn_capture(
   rig_uv_loop_t *loop,
   const char *file,
   const char *const *args,
   const char *cwd,
   rig_uv_spawn_exit_cb on_exit
);
int rig_uv_scandir(
   rig_uv_loop_t *loop,
   const char *path,
   rig_uv_scandir_cb on_done
);
int rig_uv_sleep_once(
   rig_uv_loop_t *loop,
   uint64_t timeout_ms,
   rig_uv_timer_cb on_done
);
int rig_uv_clock_read(
   int clock_id,
   int64_t *seconds,
   int32_t *nanoseconds
);
int rig_uv_hrtime_read(uint64_t *value);
]]

local non_empty_string_schema = schema.non_empty_string()
local string_array_schema = schema.array(schema.string())
local spawn_spec_schema = schema.record({
   file = non_empty_string_schema,
   args = string_array_schema:optional(),
   cwd = non_empty_string_schema:optional(),
})

local function uv_error_string(err)
   local ptr = ffi.C.rig_uv_strerror(err)
   if ptr == nil or ptr == ffi.NULL then
      return "unknown libuv error"
   end
   return ffi.string(ptr)
end

local function read_clock(clock_id, label)
   local seconds = ffi.new("int64_t[1]")
   local nanoseconds = ffi.new("int32_t[1]")
   local rc = ffi.C.rig_uv_clock_read(clock_id, seconds, nanoseconds)
   if rc ~= 0 then
      rig.raise(label .. " failed: " .. uv_error_string(rc))
   end

   return tonumber(seconds[0]), tonumber(nanoseconds[0])
end

local function normalize_spawn_spec(spec)
   local normalized = schema.assert(spawn_spec_schema, spec, "uv.spawn spec")
   local args_list = normalized.args
   if args_list == nil then
      args_list = { normalized.file }
   end

   return {
      file = normalized.file,
      args = args_list,
      cwd = normalized.cwd,
   }
end

local function normalize_scandir_path(path)
   if type(path) ~= "string" or path == "" then
      rig.raise("uv.scandir expects path to be a non-empty string")
   end
   return path
end

local function parse_scandir_entries(entries_data, entries_len)
   local entries = {}
   local data = ffi.string(entries_data, tonumber(entries_len) or 0)
   local i = 1

   while i <= #data do
      local type_code = string.byte(data, i)
      i = i + 1

      local terminator = string.find(data, "\0", i, true)
      if terminator == nil then
         rig.raise("uv.scandir received malformed entry data")
      end

      table.insert(entries, {
         type = type_code,
         name = string.sub(data, i, terminator - 1),
      })
      i = terminator + 1
   end

   return entries
end

function M.spawn(spec)
   return sched.await("uv.spawn", normalize_spawn_spec(spec))
end

function M.scandir(path)
   return sched.await("uv.scandir", normalize_scandir_path(path))
end

function M.sleep(seconds)
   return sched.sleep(seconds)
end

function M.now()
   local seconds, nanoseconds = read_clock(M.CLOCK_REALTIME, "uv.now")
   return seconds + nanoseconds / 1000000000.0
end

function M.monotonic()
   local value = ffi.new("uint64_t[1]")
   local rc = ffi.C.rig_uv_hrtime_read(value)
   if rc == 0 then
      return tonumber(value[0]) / 1000000000.0
   end

   local seconds, nanoseconds = read_clock(M.CLOCK_MONOTONIC, "uv.monotonic")
   return seconds + nanoseconds / 1000000000.0
end

--[ compositional runtime components ]

local UvLoop = rig.Class()
M.UvLoop = UvLoop

function M.plugin(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "uv",
      capabilities = {
         ["sched.clock"] = {},
         ["uv.loop"] = {},
      },
   }
end

function M.clock_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "sched.clock", properties = { protocol = "sched" } },
      },
      create = function()
         return runtime.Clock {
            now = function()
               return M.now()
            end,
            monotonic = function()
               return M.monotonic()
            end,
         }
      end,
   })
end

function UvLoop:init()
   local handle = ffi.C.rig_uv_loop_new()
   if handle == nil or handle == ffi.NULL then
      rig.raise("failed to create uv loop")
   end

   self.handle = handle
   self.pending = 0
   self.released = false
   self._callbacks = {}
end

function UvLoop:run()
   if self.released then
      return
   end

   local rc = ffi.C.rig_uv_run(self.handle)
   if rc < 0 then
      rig.raise("uv loop failed: " .. uv_error_string(rc))
   end
end

function UvLoop:stop()
   if self.handle ~= nil and self.handle ~= ffi.NULL then
      ffi.C.rig_uv_stop(self.handle)
   end
end

function UvLoop:now()
   return M.now()
end

function UvLoop:monotonic()
   return M.monotonic()
end

function UvLoop:sleep(seconds)
   return sched.sleep(seconds)
end

function UvLoop:spawn(spec)
   return sched.await("uv.spawn", normalize_spawn_spec(spec))
end

function UvLoop:scandir(path)
   return sched.await("uv.scandir", normalize_scandir_path(path))
end

function UvLoop:_spawn(spec, on_done)
   local args = ffi.new("const char *[?]", #spec.args + 1)
   for i = 1, #spec.args do
      args[i - 1] = spec.args[i]
   end
   args[#spec.args] = nil

   self.pending = self.pending + 1

   local exit_callback
   exit_callback = ffi.cast("rig_uv_spawn_exit_cb", function(exit_status, term_signal, stdout_data, stdout_len, stderr_data, stderr_len)
      self._callbacks[exit_callback] = nil

      local result = {
         exit_status = tonumber(exit_status) or 0,
         term_signal = tonumber(term_signal) or 0,
         stdout = stdout_data ~= nil and stdout_data ~= ffi.NULL
            and ffi.string(stdout_data, tonumber(stdout_len) or 0) or "",
         stderr = stderr_data ~= nil and stderr_data ~= ffi.NULL
            and ffi.string(stderr_data, tonumber(stderr_len) or 0) or "",
      }
      result.success = result.exit_status == 0 and result.term_signal == 0

      on_done(result)
   end)
   self._callbacks[exit_callback] = true

   local rc = ffi.C.rig_uv_spawn_capture(
      self.handle,
      spec.file,
      args,
      spec.cwd,
      exit_callback
   )
   if rc ~= 0 then
      self._callbacks[exit_callback] = nil
      self.pending = self.pending - 1
      rig.raise("uv.spawn failed for '%s': %s", spec.file, uv_error_string(rc))
   end
end

function UvLoop:_scandir(path, on_done)
   self.pending = self.pending + 1

   local completion_callback
   completion_callback = ffi.cast("rig_uv_scandir_cb", function(status, entries_data, entries_len)
      self._callbacks[completion_callback] = nil

      if status ~= 0 then
         on_done(nil, ("uv.scandir failed for '%s': %s"):format(
            path,
            uv_error_string(status)
         ))
         return
      end

      local entries = {}
      if entries_data ~= nil and entries_data ~= ffi.NULL then
         entries = parse_scandir_entries(entries_data, entries_len)
      end
      on_done(entries)
   end)
   self._callbacks[completion_callback] = true

   local rc = ffi.C.rig_uv_scandir(self.handle, path, completion_callback)
   if rc ~= 0 then
      self._callbacks[completion_callback] = nil
      self.pending = self.pending - 1
      rig.raise("uv.scandir failed for '%s': %s", path, uv_error_string(rc))
   end
end

function UvLoop:install_handlers(scheduler)
   scheduler.inner:set_handler("uv.spawn", function(inner, task, spec)
      local ticket = inner:start_async(task)
      self:_spawn(spec, function(result)
         self.pending = self.pending - 1
         ticket:wake(result)
         self:stop()
      end)
   end)

   scheduler.inner:set_handler("uv.scandir", function(inner, task, path)
      local ticket = inner:start_async(task)
      self:_scandir(path, function(entries, err)
         self.pending = self.pending - 1
         if err ~= nil then
            ticket:wake(nil, err)
         else
            ticket:wake(entries)
         end
         self:stop()
      end)
   end)
end

function UvLoop:release()
   if self.released then
      return
   end

   self.released = true
   local handle = self.handle
   self.handle = nil
   self._callbacks = {}

   if handle == nil or handle == ffi.NULL then
      return
   end

   while true do
      local rc = ffi.C.rig_uv_run_nowait(handle)
      if rc < 0 then
         ffi.C.rig_uv_loop_delete(handle)
         rig.raise("uv loop failed during shutdown: " .. uv_error_string(rc))
      end
      if rc == 0 then
         break
      end
   end

   local rc = ffi.C.rig_uv_loop_delete(handle)
   if rc ~= 0 then
      rig.raise("failed to close uv loop: " .. uv_error_string(rc))
   end
end

function M.loop_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "uv.loop" },
      },
      requires = {
         { capability = "sched.scheduler" },
      },
      create = function(context)
         local loop = UvLoop()
         loop:install_handlers(context.runtime.scheduler)
         return loop
      end,
      release = function(loop)
         loop:release()
      end,
      progress = {
         wait = function(context)
            local loop = context.runtime.capability_values["uv.loop"]
            if loop ~= nil and loop.pending > 0 then
               loop:run()
            end
         end,
      },
   })
end

function M.bundle_uv(builder, options)
   options = options or {}
   local core = runtime.scheduler_plugin()
   local plugin = M.plugin(options)

   builder:use(core)
   builder:use(plugin)
   builder:add(M.clock_component(plugin, { name = "clock" }))
   builder:add(runtime.timer_component(core, { name = "timer", timer = options.timer }))
   builder:add(runtime.scheduler_component(core, { name = "scheduler" }))
   builder:add(M.loop_component(plugin, { name = "uv" }))
   return builder
end

return M
