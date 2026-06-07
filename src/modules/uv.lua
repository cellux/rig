local M = ... or {}
local ffi = require("ffi")
local sched = require("sched")
local schema = require("schema")
require("time")

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

M._loop = M._loop or nil
M._scheduler = M._scheduler or nil
M._active_exit_callbacks = M._active_exit_callbacks or {}
M._active_scandir_callbacks = M._active_scandir_callbacks or {}
M._active_timer_callbacks = M._active_timer_callbacks or {}

local non_empty_string_schema = schema.non_empty_string()
local string_array_schema = schema.array(schema.string())
local uv_module_config_schema = schema.record({
   main = schema.func():optional(),
})
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

local function normalize_module_config(options)
   if options == nil then
      return {}
   end
   return schema.assert(
      uv_module_config_schema,
      options,
      "uv module configuration"
   )
end

local function get_uv_module_config(options)
   local module_config = options.module_config
   if module_config == nil then
      return {}
   end
   if type(module_config) ~= "table" then
      error("rig.run expects options.module_config to be a table if provided", 0)
   end

   local uv_config = module_config.uv
   if uv_config == nil then
      return {}
   end
   return normalize_module_config(uv_config)
end

local function read_clock(clock_id, label)
   local seconds = ffi.new("int64_t[1]")
   local nanoseconds = ffi.new("int32_t[1]")
   local rc = ffi.C.rig_uv_clock_read(clock_id, seconds, nanoseconds)
   if rc ~= 0 then
      error(label .. " failed: " .. uv_error_string(rc), 0)
   end

   return tonumber(seconds[0]), tonumber(nanoseconds[0])
end

local function clear_callback_references()
   M._active_exit_callbacks = {}
   M._active_scandir_callbacks = {}
   M._active_timer_callbacks = {}
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
      error("uv.scandir expects path to be a non-empty string", 0)
   end
   return path
end

local function spawn_internal(spec, on_exit)
   if M._loop == nil then
      error("uv.spawn requires an active uv loop", 0)
   end
   if type(on_exit) ~= "function" then
      error("uv internal spawn requires an exit callback", 0)
   end

   local args = ffi.new("const char *[?]", #spec.args + 1)
   for i = 1, #spec.args do
      args[i - 1] = spec.args[i]
   end
   args[#spec.args] = nil

   local exit_callback
   exit_callback = ffi.cast("rig_uv_spawn_exit_cb", function(exit_status, term_signal, stdout_data, stdout_len, stderr_data, stderr_len)
      M._active_exit_callbacks[exit_callback] = nil

      local result = {
         exit_status = tonumber(exit_status) or 0,
         term_signal = tonumber(term_signal) or 0,
         stdout = stdout_data ~= nil and stdout_data ~= ffi.NULL
            and ffi.string(stdout_data, tonumber(stdout_len) or 0) or "",
         stderr = stderr_data ~= nil and stderr_data ~= ffi.NULL
            and ffi.string(stderr_data, tonumber(stderr_len) or 0) or "",
      }
      result.success = result.exit_status == 0 and result.term_signal == 0

      on_exit(result)
   end)
   M._active_exit_callbacks[exit_callback] = true

   local rc = ffi.C.rig_uv_spawn_capture(
      M._loop,
      spec.file,
      args,
      spec.cwd,
      exit_callback
   )
   if rc ~= 0 then
      M._active_exit_callbacks[exit_callback] = nil
      error(
         ("uv.spawn failed for '%s': %s"):format(spec.file, uv_error_string(rc)),
         0
      )
   end
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
         error("uv.scandir received malformed entry data", 0)
      end

      table.insert(entries, {
         type = type_code,
         name = string.sub(data, i, terminator - 1),
      })
      i = terminator + 1
   end

   return entries
end

local function scandir_internal(path, on_done)
   if M._loop == nil then
      error("uv.scandir requires an active uv loop", 0)
   end
   if type(on_done) ~= "function" then
      error("uv internal scandir requires a completion callback", 0)
   end

   local completion_callback
   completion_callback = ffi.cast("rig_uv_scandir_cb", function(status, entries_data, entries_len)
      M._active_scandir_callbacks[completion_callback] = nil

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
   M._active_scandir_callbacks[completion_callback] = true

   local rc = ffi.C.rig_uv_scandir(M._loop, path, completion_callback)
   if rc ~= 0 then
      M._active_scandir_callbacks[completion_callback] = nil
      error(("uv.scandir failed for '%s': %s"):format(path, uv_error_string(rc)), 0)
   end
end

local function sleep_internal(seconds, on_done)
   if M._loop == nil then
      error("uv.sleep requires an active uv loop", 0)
   end
   if type(on_done) ~= "function" then
      error("uv internal sleep requires a completion callback", 0)
   end

   local timeout_ms = math.ceil(seconds * 1000.0)
   if timeout_ms < 0 then
      timeout_ms = 0
   end

   local completion_callback
   completion_callback = ffi.cast("rig_uv_timer_cb", function()
      M._active_timer_callbacks[completion_callback] = nil
      on_done()
   end)
   M._active_timer_callbacks[completion_callback] = true

   local rc = ffi.C.rig_uv_sleep_once(M._loop, timeout_ms, completion_callback)
   if rc ~= 0 then
      M._active_timer_callbacks[completion_callback] = nil
      error(
         ("uv.sleep failed for %.6f seconds: %s"):format(
            seconds,
            uv_error_string(rc)
         ),
         0
      )
   end
end

function M.get_loop()
   return M._loop
end

function M.stop()
   if M._loop == nil then
      error("uv.stop requires an active uv loop", 0)
   end
   ffi.C.rig_uv_stop(M._loop)
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

rig.register_service_provider("time", "uv", {
   now = function()
      return M.now()
   end,
   monotonic = function()
      return M.monotonic()
   end,
})

local function setup(options)
   options = normalize_module_config(options)

   if M._loop ~= nil then
      local rc = ffi.C.rig_uv_loop_delete(M._loop)
      if rc ~= 0 then
         error("failed to close previous uv loop: " .. uv_error_string(rc), 0)
      end
      M._loop = nil
   end

   clear_callback_references()
   local loop = ffi.C.rig_uv_loop_new()
   if loop == nil or loop == ffi.NULL then
      error("failed to create uv loop", 0)
   end

   M._loop = loop
   M._scheduler = sched.create("uv scheduler")
   M._scheduler:set_handler("sched.sleep", function(scheduler, task, seconds)
      scheduler:begin_async()

      local ok, err = pcall(sleep_internal, seconds, function()
         scheduler:end_async()
         scheduler:wake(task)
         ffi.C.rig_uv_stop(M._loop)
      end)

      if not ok then
         scheduler:end_async()
         error(err, 0)
      end
   end)
end

local function run_scheduler_loop(runtime_options, outer_options)
   local options = normalize_module_config(runtime_options)
   local main = options.main
   if main ~= nil and type(main) ~= "function" then
      error("uv.main must be a function if provided", 0)
   end

   local scheduler = M._scheduler
   if scheduler == nil then
      error("uv scheduler is not initialized", 0)
   end

   scheduler:activate()
   if type(main) == "function" then
      scheduler:spawn(main, outer_options)
   end

   while scheduler:has_live_tasks() do
      scheduler:drain()
      if not scheduler:has_live_tasks() then
         break
      end

      if scheduler:has_ready_work() then
         -- continue immediately; draining will pick it up on the next iteration
      elseif scheduler:pending_async() > 0 then
         local rc = ffi.C.rig_uv_run(M._loop)
         if rc < 0 then
            scheduler:deactivate()
            error("uv loop failed: " .. uv_error_string(rc), 0)
         end
      else
         scheduler:deactivate()
         error(
            "uv scheduler deadlocked: tasks are waiting but no async operations are pending",
            0
         )
      end
   end

   scheduler:deactivate()
end

local function shutdown()
   M._scheduler = nil

   if M._loop == nil then
      clear_callback_references()
      return
   end

   local loop_handle = M._loop
   M._loop = nil
   clear_callback_references()

   while true do
      local rc = ffi.C.rig_uv_run_nowait(loop_handle)
      if rc < 0 then
         error("uv loop failed during shutdown: " .. uv_error_string(rc), 0)
      end
      if rc == 0 then
         break
      end
   end

   local rc = ffi.C.rig_uv_loop_delete(loop_handle)
   if rc ~= 0 then
      error("failed to close uv loop: " .. uv_error_string(rc), 0)
   end
end

sched.register_handler("uv.spawn", function(scheduler, task, spec)
   scheduler:begin_async()

   local ok, err = pcall(spawn_internal, spec, function(result)
      scheduler:end_async()
      scheduler:wake(task, result)
      ffi.C.rig_uv_stop(M._loop)
   end)

   if not ok then
      scheduler:end_async()
      error(err, 0)
   end
end)

sched.register_handler("uv.scandir", function(scheduler, task, path)
   scheduler:begin_async()

   local ok, err = pcall(scandir_internal, path, function(entries, callback_err)
      scheduler:end_async()
      if callback_err ~= nil then
         scheduler:wake(task, nil, callback_err)
      else
         scheduler:wake(task, entries)
      end
      ffi.C.rig_uv_stop(M._loop)
   end)

   if not ok then
      scheduler:end_async()
      error(err, 0)
   end
end)

rig.register_runtime_driver("uv", {
   setup = function(options)
      setup(get_uv_module_config(options))
   end,
   loop = function(options)
      run_scheduler_loop(get_uv_module_config(options), options)
   end,
   shutdown = function()
      shutdown()
   end,
})

rig.register_runtime_preset("uv", {
   driver = "uv",
   providers = {
      time = "uv",
   },
})

return M
