local M = ... or {}
local ffi = ffi

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
]]

M._loop = M._loop or nil
M._pending_error = M._pending_error or nil
M._active_exit_callbacks = M._active_exit_callbacks or {}

local function uv_error_string(err)
   local ptr = ffi.C.rig_uv_strerror(err)
   if ptr == nil or ptr == ffi.NULL then
      return "unknown libuv error"
   end
   return ffi.string(ptr)
end

local function normalize_options(options)
   if options == nil then
      return {}
   end
   if type(options) ~= "table" then
      error("uv runtime options must be a table if provided", 0)
   end
   return options
end

local function clear_callback_references()
   M._active_exit_callbacks = {}
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
   if M._loop == nil then
      error("uv.spawn requires an active uv loop", 0)
   end
   if type(spec) ~= "table" then
      error("uv.spawn expects a table", 0)
   end
   if type(spec.file) ~= "string" or spec.file == "" then
      error("uv.spawn requires spec.file to be a non-empty string", 0)
   end
   if type(spec.on_exit) ~= "function" then
      error("uv.spawn requires spec.on_exit to be a function", 0)
   end
   if spec.cwd ~= nil and (type(spec.cwd) ~= "string" or spec.cwd == "") then
      error("uv.spawn expects spec.cwd to be a non-empty string if provided", 0)
   end

   local args_list = spec.args
   if args_list == nil then
      args_list = { spec.file }
   elseif type(args_list) ~= "table" then
      error("uv.spawn expects spec.args to be a table if provided", 0)
   end

   local args = ffi.new("const char *[?]", #args_list + 1)
   for i = 1, #args_list do
      if type(args_list[i]) ~= "string" then
         error(("uv.spawn expects spec.args[%d] to be a string"):format(i), 0)
      end
      args[i - 1] = args_list[i]
   end
   args[#args_list] = nil

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

      local ok, err = pcall(spec.on_exit, result)
      if not ok and M._pending_error == nil then
         M._pending_error = err
      end
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

   return true
end

local function setup(options)
   options = normalize_options(options)

   if M._loop ~= nil then
      local rc = ffi.C.rig_uv_loop_delete(M._loop)
      if rc ~= 0 then
         error("failed to close previous uv loop: " .. uv_error_string(rc), 0)
      end
      M._loop = nil
   end

   clear_callback_references()
   M._pending_error = nil

   local loop = ffi.C.rig_uv_loop_new()
   if loop == nil or loop == ffi.NULL then
      error("failed to create uv loop", 0)
   end

   M._loop = loop
end

local function loop(runtime_options, outer_options)
   local options = normalize_options(runtime_options)
   local main = options.main
   if main ~= nil and type(main) ~= "function" then
      error("uv.main must be a function if provided", 0)
   end

   if type(main) == "function" then
      main(outer_options)
   end

   local rc = ffi.C.rig_uv_run(M._loop)
   if rc ~= 0 then
      error("uv loop failed: " .. uv_error_string(rc), 0)
   end

   if M._pending_error ~= nil then
      local err = M._pending_error
      M._pending_error = nil
      error(err, 0)
   end
end

local function shutdown()
   if M._loop == nil then
      clear_callback_references()
      M._pending_error = nil
      return
   end

   local loop_handle = M._loop
   M._loop = nil
   clear_callback_references()
   M._pending_error = nil

   local rc = ffi.C.rig_uv_loop_delete(loop_handle)
   if rc ~= 0 then
      error("failed to close uv loop: " .. uv_error_string(rc), 0)
   end
end

rig.register_runtime_mode("uv", {
   setup = function(options)
      setup(options.uv)
   end,
   loop = function(options)
      loop(options.uv, options)
   end,
   shutdown = function()
      shutdown()
   end,
})

return M
