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

M._runtime_drivers = M._runtime_drivers or {}
M._runtime_presets = M._runtime_presets or {}
M._runtime_hooks = M._runtime_hooks or {}
M._services = M._services or {}
M._active_runtime = M._active_runtime or nil

local function normalize_method_names(method_names)
   if type(method_names) ~= "table" then
      error("rig.create_service expects method_names to be a table", 0)
   end

   local copied = {}
   local seen = {}

   for i = 1, #method_names do
      local method_name = method_names[i]
      if type(method_name) ~= "string" or method_name == "" then
         error(
            ("rig.create_service expects method_names[%d] to be a non-empty string"):format(i),
            0
         )
      end
      if seen[method_name] then
         error(
            ("rig.create_service received duplicate method name '%s'"):format(method_name),
            0
         )
      end
      copied[i] = method_name
      seen[method_name] = true
   end

   return copied
end

function M.create_service(service_id, method_names)
   if type(service_id) ~= "string" or service_id == "" then
      error("rig.create_service expects service_id to be a non-empty string", 0)
   end

   local methods = normalize_method_names(method_names)
   local existing = M._services[service_id]
   if existing ~= nil then
      error(
         ("rig.create_service already has a service '%s'"):format(service_id),
         0
      )
   end

   local service = {
      id = service_id,
      methods = methods,
      impls = {},
   }
   M._services[service_id] = service
   return service
end

function M.register_service_impl(service_id, mode, impl)
   if type(service_id) ~= "string" or service_id == "" then
      error("rig.register_service_impl expects service_id to be a non-empty string", 0)
   end
   if type(mode) ~= "string" or mode == "" then
      error("rig.register_service_impl expects provider_id to be a non-empty string", 0)
   end
   if type(impl) ~= "table" then
      error("rig.register_service_impl expects impl to be a table", 0)
   end

   local service = M._services[service_id]
   if service == nil then
      error(
         ("rig.register_service_impl does not know service '%s'"):format(service_id),
         0
      )
   end
   if service.impls[mode] ~= nil then
      error(
         ("rig.register_service_impl already has an implementation for service '%s' in provider '%s'"):format(
            service_id,
            mode
         ),
         0
      )
   end

   for i = 1, #service.methods do
      local method_name = service.methods[i]
      if type(impl[method_name]) ~= "function" then
         error(
            ("rig.register_service_impl requires service '%s' for provider '%s' to implement method '%s'"):format(
               service_id,
               mode,
               method_name
            ),
            0
         )
      end
   end

   service.impls[mode] = impl
   return impl
end

local function copy_service_provider_map(map, label)
   if map == nil then
      return {}
   end
   if type(map) ~= "table" then
      error(label, 0)
   end

   local copied = {}
   for service_id, provider_id in pairs(map) do
      if type(service_id) ~= "string" or service_id == "" then
         error(label .. " (service ids must be non-empty strings)", 0)
      end
      if type(provider_id) ~= "string" or provider_id == "" then
         error(label .. " (provider ids must be non-empty strings)", 0)
      end
      copied[service_id] = provider_id
   end

   return copied
end

local function validate_runtime_providers(runtime_id, providers)
   for service_id, provider_id in pairs(providers) do
      local service = M._services[service_id]
      if service == nil then
         error(
            ("rig.run runtime '%s' references unknown service '%s'"):format(
               runtime_id,
               service_id
            ),
            0
         )
      end

      if service.impls[provider_id] == nil then
         error(
            ("rig.run runtime '%s' selects provider '%s' for service '%s', but no such implementation is registered"):format(
               runtime_id,
               provider_id,
               service_id
            ),
            0
         )
      end
   end
end

local function resolve_runtime_service_impls(runtime_id, providers)
   local service_impls = {}

   for service_id, provider_id in pairs(providers) do
      local service = M._services[service_id]
      if service == nil then
         error(
            ("rig.run runtime '%s' references unknown service '%s'"):format(
               runtime_id,
               service_id
            ),
            0
         )
      end

      local impl = service.impls[provider_id]
      if impl == nil then
         error(
            ("rig.run runtime '%s' selects provider '%s' for service '%s', but no such implementation is registered"):format(
               runtime_id,
               provider_id,
               service_id
            ),
            0
         )
      end

      service_impls[service_id] = impl
   end

   return service_impls
end

function M.require_service(service_id)
   if type(service_id) ~= "string" or service_id == "" then
      error("rig.require_service expects service_id to be a non-empty string", 0)
   end

   local service = M._services[service_id]
   if service == nil then
      error(
         ("rig.require_service does not know service '%s'"):format(service_id),
         0
      )
   end

   local active_runtime = M._active_runtime
   if type(active_runtime) ~= "table" then
      error(
         ("rig.require_service('%s') requires an active runtime"):format(
            service_id
         ),
         0
      )
   end

   local impl = active_runtime.service_impls[service_id]
   if impl == nil then
      error(
         ("rig.require_service('%s') has no implementation for active runtime '%s'"):format(
            service_id,
            active_runtime.runtime_id
         ),
         0
      )
   end

   return impl
end

function M.register_runtime_driver(name, driver)
   if type(name) ~= "string" or name == "" then
      error("rig.register_runtime_driver expects name to be a non-empty string", 0)
   end
   if type(driver) ~= "table" then
      error("rig.register_runtime_driver expects driver to be a table", 0)
   end

   M._runtime_drivers[name] = driver
   return driver
end

function M.register_runtime_preset(name, preset)
   if type(name) ~= "string" or name == "" then
      error("rig.register_runtime_preset expects name to be a non-empty string", 0)
   end
   if type(preset) ~= "table" then
      error("rig.register_runtime_preset expects preset to be a table", 0)
   end

   local driver_id = preset.driver
   if driver_id == nil then
      driver_id = name
   end
   if type(driver_id) ~= "string" or driver_id == "" then
      error("rig.register_runtime_preset expects preset.driver to be a non-empty string", 0)
   end

   local normalized = {
      driver = driver_id,
      providers = copy_service_provider_map(
         preset.providers,
         "rig.register_runtime_preset expects preset.providers to be a table if provided"
      ),
   }

   M._runtime_presets[name] = normalized
   return normalized
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

local function resolve_runtime(options)
   local preset_id = options.preset
   if preset_id ~= nil and (type(preset_id) ~= "string" or preset_id == "") then
      error("rig.run expects options.preset to be a non-empty string if provided", 0)
   end

   local preset = nil
   if preset_id ~= nil then
      preset = M._runtime_presets[preset_id]
      if preset == nil then
         error(
            ("rig.run does not know runtime preset '%s'"):format(preset_id),
            0
         )
      end
   end

   local driver_id = options.driver
   if driver_id ~= nil and (type(driver_id) ~= "string" or driver_id == "") then
      error("rig.run expects options.driver to be a non-empty string if provided", 0)
   end
   if driver_id == nil and preset ~= nil then
      driver_id = preset.driver
   end
   if type(driver_id) ~= "string" or driver_id == "" then
      error("rig.run requires options.driver or options.preset to be a non-empty string", 0)
   end

   local driver = M._runtime_drivers[driver_id]
   if driver == nil then
      error(
         ("rig.run does not know runtime driver '%s'"):format(driver_id),
         0
      )
   end
   if type(driver.loop) ~= "function" then
      error(
         ("runtime driver '%s' is missing loop()"):format(driver_id),
         0
      )
   end

   local providers = {}
   if preset ~= nil then
      for service_id, provider_id in pairs(preset.providers) do
         providers[service_id] = provider_id
      end
   end

   local override_providers = copy_service_provider_map(
      options.providers,
      "rig.run expects options.providers to be a table if provided"
   )
   for service_id, provider_id in pairs(override_providers) do
      providers[service_id] = provider_id
   end

   local runtime_id = preset_id or driver_id
   validate_runtime_providers(runtime_id, providers)
   local service_impls = resolve_runtime_service_impls(runtime_id, providers)

   return driver, {
      driver_id = driver_id,
      preset_id = preset_id,
      runtime_id = runtime_id,
      providers = providers,
      service_impls = service_impls,
   }
end

function M.run(options)
   if type(options) ~= "table" then
      error("rig.run expects a table", 0)
   end
   local driver, active_runtime = resolve_runtime(options)

   local previous_runtime = M._active_runtime
   M._active_runtime = active_runtime

   local ok, err = pcall(function()
      run_all_hooks(options, "before_setup", options)
      if type(driver.setup) == "function" then
         driver.setup(options)
      end
      run_all_hooks(options, "after_setup", options)

      driver.loop(options, function(phase, ...)
         run_all_hooks(options, phase, ...)
      end)

      run_all_hooks(options, "before_shutdown", options)
      if type(driver.shutdown) == "function" then
         driver.shutdown(options)
      end
      run_all_hooks(options, "after_shutdown", options)
   end)

   M._active_runtime = previous_runtime

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

   local result = M.load_script(script_path, source)

   if script_path:match("_test%.lua$") ~= nil
      or script_path:match("_test%.fnl$") ~= nil then
      local test_mod = require("test")
      if type(test_mod) == "table"
         and type(test_mod.run_registered_cases) == "function" then
         test_mod.run_registered_cases {
            script_path = script_path,
         }
      end
   end

   return result
end

return M
