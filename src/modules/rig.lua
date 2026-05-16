local M = ... or {}
local lua_tostring = _G.tostring

local function is_identifier(key)
   return type(key) == "string" and key:match("^[_%a][_%w]*$") ~= nil
end

local function serialize_lua(value, seen)
   local value_type = type(value)

   if value_type ~= "table" then
      if value_type == "string" then
         return string.format("%q", value)
      end
      return tostring(value)
   end

   if seen[value] then
      return "{ --[[cycle]] }"
   end
   seen[value] = true

   local parts = {}
   for k, v in pairs(value) do
      local val_repr = serialize_lua(v, seen)
      local key_repr
      if is_identifier(k) then
         key_repr = k
      else
         key_repr = "[" .. serialize_lua(k, seen) .. "]"
      end
      table.insert(parts, key_repr .. " = " .. val_repr)
   end

   seen[value] = nil
   return "{" .. table.concat(parts, ", ") .. "}"
end

function M.tostring(value)
   if type(value) == "table" then
      return serialize_lua(value, {})
   end
   return lua_tostring(value)
end

local function write_values(with_newline, ...)
   local parts = {}
   local stringify = M.tostring

   if type(stringify) ~= "function" then
      stringify = lua_tostring
   end

   for i = 1, select("#", ...) do
      local text = stringify(select(i, ...))
      if type(text) ~= "string" then
         error("'tostring' must return a string to 'rig.print'", 0)
      end
      parts[i] = text
   end

   local output = table.concat(parts, " ")
   if with_newline then
      output = output .. "\n"
   end

   local ok, err = io.stdout:write(output)
   if not ok then
      error(tostring(err or "failed to write to stdout"), 0)
   end

   io.stdout:flush()
end

function M.print(...)
   write_values(false, ...)
end

function M.println(...)
   write_values(true, ...)
end

local resource_scope_mt = {}
resource_scope_mt.__index = resource_scope_mt

local function add_scope_entry(scope, resource, release_fn)
   local entry = {
      resource = resource,
      release_fn = release_fn,
      key = nil,
   }
   table.insert(scope._entries, entry)
   return entry
end

function resource_scope_mt:adopt(resource, release_fn)
   if self._released then
      error("cannot adopt a resource into a released " .. self._scope_label, 0)
   end
   if resource == nil then
      error("rig.resource_scope:adopt requires a resource", 0)
   end
   if type(release_fn) ~= "function" then
      error("rig.resource_scope:adopt requires a release function", 0)
   end

   add_scope_entry(self, resource, release_fn)
   return resource
end

function resource_scope_mt:replace(key, resource, release_fn)
   if self._released then
      error("cannot replace a resource in a released " .. self._scope_label, 0)
   end
   if type(key) ~= "string" or key == "" then
      error("rig.resource_scope:replace requires a non-empty string key", 0)
   end
   if resource == nil then
      error("rig.resource_scope:replace requires a resource", 0)
   end
   if type(release_fn) ~= "function" then
      error("rig.resource_scope:replace requires a release function", 0)
   end

   local existing = self._named_entries[key]
   if existing ~= nil then
      if existing.resource ~= nil then
         existing.release_fn(self.context, existing.resource)
      end
      existing.resource = nil
      existing.release_fn = nil
      self._named_entries[key] = nil
   end

   local entry = add_scope_entry(self, resource, release_fn)
   entry.key = key
   self._named_entries[key] = entry
   return resource
end

function resource_scope_mt:release()
   if self._released then
      return
   end

   for index = #self._entries, 1, -1 do
      local entry = self._entries[index]
      if entry.resource ~= nil then
         entry.release_fn(self.context, entry.resource)
      end
      if entry.key ~= nil and self._named_entries[entry.key] == entry then
         self._named_entries[entry.key] = nil
      end
      self._entries[index] = nil
   end

   self._released = true
end

function M.resource_scope(context, label)
   if context == nil then
      error("rig.resource_scope requires a context value", 0)
   end
   if label ~= nil and (type(label) ~= "string" or label == "") then
      error("rig.resource_scope expects label to be a non-empty string if provided", 0)
   end

   return setmetatable({
      context = context,
      _entries = {},
      _named_entries = {},
      _released = false,
      _scope_label = label or "resource scope",
   }, resource_scope_mt)
end

M._runtime_modes = M._runtime_modes or {}
M._runtime_hooks = M._runtime_hooks or {}

function M.register_runtime_mode(name, mode)
   if type(name) ~= "string" or name == "" then
      error("rig.register_runtime_mode expects name to be a non-empty string", 0)
   end
   if type(mode) ~= "table" then
      error("rig.register_runtime_mode expects mode to be a table", 0)
   end

   M._runtime_modes[name] = mode
end

function M.register_runtime_hook(phase, hook)
   if type(phase) ~= "string" or phase == "" then
      error("rig.register_runtime_hook expects phase to be a non-empty string", 0)
   end
   if type(hook) ~= "function" then
      error("rig.register_runtime_hook expects hook to be a function", 0)
   end

   local hooks = M._runtime_hooks[phase]
   if hooks == nil then
      hooks = {}
      M._runtime_hooks[phase] = hooks
   end
   table.insert(hooks, hook)
end

local function run_runtime_hooks(phase, ...)
   local hooks = M._runtime_hooks[phase]
   if hooks == nil then
      return
   end

   for i = 1, #hooks do
      hooks[i](...)
   end
end

local function run_option_hooks(options, phase, ...)
   local hooks = options.hooks
   if hooks == nil then
      return
   end
   if type(hooks) ~= "table" then
      error("rig.run expects options.hooks to be a table", 0)
   end

   local phase_hooks = hooks[phase]
   if phase_hooks == nil then
      return
   end

   if type(phase_hooks) == "function" then
      phase_hooks(...)
      return
   end

   if type(phase_hooks) ~= "table" then
      error(
         ("rig.run expects options.hooks.%s to be a function or a table of functions"):format(
            phase
         ),
         0
      )
   end

   for i = 1, #phase_hooks do
      local hook = phase_hooks[i]
      if type(hook) ~= "function" then
         error(
            ("rig.run expects options.hooks.%s[%d] to be a function"):format(
               phase,
               i
            ),
            0
         )
      end
      hook(...)
   end
end

local function run_all_hooks(options, phase, ...)
   run_runtime_hooks(phase, ...)
   run_option_hooks(options, phase, ...)
end

function M.run(options)
   if type(options) ~= "table" then
      error("rig.run expects a table", 0)
   end
   if type(options.mode) ~= "string" or options.mode == "" then
      error("rig.run requires options.mode to be a non-empty string", 0)
   end

   local mode = M._runtime_modes[options.mode]
   if mode == nil then
      error(
         ("rig.run does not know runtime mode '%s'"):format(options.mode),
         0
      )
   end
   if type(mode.loop) ~= "function" then
      error(
         ("runtime mode '%s' is missing loop()"):format(options.mode),
         0
      )
   end

   run_all_hooks(options, "before_setup", options)
   if type(mode.setup) == "function" then
      mode.setup(options)
   end
   run_all_hooks(options, "after_setup", options)

   local ok, err = pcall(function()
      mode.loop(options, function(phase, ...)
         run_all_hooks(options, phase, ...)
      end)
   end)

   run_all_hooks(options, "before_shutdown", options)
   if type(mode.shutdown) == "function" then
      mode.shutdown(options)
   end
   run_all_hooks(options, "after_shutdown", options)

   if not ok then
      error(err, 0)
   end
end

local function load_lua_script(script_path, source)
   local chunk, err = loadstring(source, script_path)
   if chunk ~= nil then
      return chunk
   end
   return nil, "Lua: " .. tostring(err or "unknown error")
end

local function load_fennel_script(script_path, source)
   local fennel_mod = _G.fennel
   if type(fennel_mod) ~= "table" then
      return nil, "Fennel: global 'fennel' module is not available"
   end

   local compile_string = fennel_mod.compileString
   if type(compile_string) ~= "function" then
      return nil, "Fennel: fennel.compileString is not available"
   end

   local ok, compiled_source_or_err = pcall(compile_string, source, {
      filename = script_path,
   })
   if not ok then
      return nil, "Fennel: " .. tostring(compiled_source_or_err)
   end

   if compiled_source_or_err == nil then
      return nil, "Fennel: compiler did not return Lua source"
   end

   local chunk, load_err = loadstring(compiled_source_or_err, script_path)
   if chunk ~= nil then
      return chunk
   end

   return nil, "Fennel: " .. tostring(load_err or "unknown error")
end

M.script_loaders = {
   load_lua_script,
   load_fennel_script,
}

function M.load_script(script_path, source)
   if type(script_path) ~= "string" then
      error("rig.load_script expects script_path to be a string")
   end
   if type(source) ~= "string" then
      error("rig.load_script expects source to be a string")
   end

   local loader_errors = {}

   for i, loader in ipairs(M.script_loaders) do
      if type(loader) ~= "function" then
         loader_errors[i] = "script loader entry is not a function"
      else
         local chunk, err = loader(script_path, source)
         if type(chunk) == "function" then
            return chunk()
         end
         loader_errors[i] = tostring(err or "script loader rejected the script")
      end
   end

   error(
      ("failed to load script '%s' with any registered loader\n%s"):format(
         script_path,
         table.concat(loader_errors, "\n")
      ),
      0
   )
end

function M.run_script_file(script_path)
   if type(script_path) ~= "string" then
      error("rig.run_script_file expects script_path to be a string")
   end

   local file, open_err = io.open(script_path, "rb")
   if file == nil then
      error(
         ("failed to open '%s': %s"):format(
            script_path,
            tostring(open_err or "unknown error")
         ),
         0
      )
   end

   local source, read_err = file:read("*all")
   file:close()

   if source == nil then
      error(
         ("failed to read '%s': %s"):format(
            script_path,
            tostring(read_err or "unknown error")
         ),
         0
      )
   end

   return M.load_script(script_path, source)
end

return M
