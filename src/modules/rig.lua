local M = ... or {}
local prelude = require("prelude")
local repr = require("repr")
local schema = require("schema")

M.repr = repr.repr
M.class = prelude.class
M.raise = prelude.raise

local raise = M.raise

function M.tostring(value)
   if type(value) == "table" then
      local mt = getmetatable(value)
      if type(mt) == "table" and type(rawget(mt, "__tostring")) == "function" then
         return tostring(value)
      end
      return M.repr(value)
   end
   return tostring(value)
end

local function print_values(stream, with_newline, ...)
   local parts = {}
   local stringify = M.tostring

   for i = 1, select("#", ...) do
      local text = stringify(select(i, ...))
      if type(text) ~= "string" then
         raise("'tostring' must return a string to 'rig.print'")
      end
      parts[i] = text
   end

   local output = table.concat(parts, " ")
   if with_newline then
      output = output .. "\n"
   end

   local ok, err = stream:write(output)
   if not ok then
      raise(err or "failed to write output")
   end

   if type(stream.flush) == "function" then
      ok, err = stream:flush()
      if not ok then
         raise(err or "failed to flush output")
      end
   end
end

function M.print(...)
   print_values(io.stdout, false, ...)
end

function M.printf(format_string, ...)
   M.print(string.format(format_string, ...))
end

function M.println(...)
   print_values(io.stdout, true, ...)
end

function M.eprint(...)
   print_values(io.stderr, false, ...)
end

function M.eprintf(format_string, ...)
   M.eprint(string.format(format_string, ...))
end

function M.eprintln(...)
   print_values(io.stderr, true, ...)
end

function M.fprint(stream, ...)
   print_values(stream, false, ...)
end

function M.fprintf(stream, format_string, ...)
   M.fprint(stream, string.format(format_string, ...))
end

function M.fprintln(stream, ...)
   print_values(stream, true, ...)
end

M.ResourceScope = M.class()

local function add_scope_entry(scope, resource, release_fn)
   local entry = {
      resource = resource,
      release_fn = release_fn,
      key = nil,
   }
   table.insert(scope._entries, entry)
   return entry
end

function M.ResourceScope:init(context, label)
   if context == nil then
      raise("rig.ResourceScope requires a context value")
   end
   if label ~= nil and (type(label) ~= "string" or label == "") then
      raise("rig.ResourceScope expects label to be a non-empty string if provided")
   end

   self.context = context
   self._entries = {}
   self._named_entries = {}
   self._released = false
   self._scope_label = label or "resource scope"
end

function M.ResourceScope:adopt(resource, release_fn)
   if self._released then
      raise("cannot adopt a resource into a released " .. self._scope_label)
   end
   if resource == nil then
      raise("rig.ResourceScope:adopt requires a resource")
   end
   if type(release_fn) ~= "function" then
      raise("rig.ResourceScope:adopt requires a release function")
   end

   add_scope_entry(self, resource, release_fn)
   return resource
end

function M.ResourceScope:replace(key, resource, release_fn)
   if self._released then
      raise("cannot replace a resource in a released " .. self._scope_label)
   end
   if type(key) ~= "string" or key == "" then
      raise("rig.ResourceScope:replace requires a non-empty string key")
   end
   if resource == nil then
      raise("rig.ResourceScope:replace requires a resource")
   end
   if type(release_fn) ~= "function" then
      raise("rig.ResourceScope:replace requires a release function")
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

function M.ResourceScope:release()
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

local _runtime_drivers = {}
local _runtime_presets = {}
local _runtime_hooks = {}

local core_runtime_phase_names = {
   "before_setup",
   "after_setup",
   "before_shutdown",
   "after_shutdown",
}

local core_runtime_phases = {}
for i = 1, #core_runtime_phase_names do
   core_runtime_phases[core_runtime_phase_names[i]] = true
end

local non_empty_string_schema = schema.non_empty_string()
local unique_non_empty_string_array_schema = schema.array(
   non_empty_string_schema,
   { unique = true }
)
local string_to_string_map_schema = schema.map(
   non_empty_string_schema,
   non_empty_string_schema
)
local option_hooks_schema = schema.map(
   non_empty_string_schema,
   schema.func()
)
local resolve_runtime_options_schema = schema.record({
   mode = non_empty_string_schema:optional(),
   driver = non_empty_string_schema:optional(),
   providers = string_to_string_map_schema:optional(),
}, {
   allow_extra = true,
})

local function normalize_service_method_names(method_names)
   return schema.assert(
      unique_non_empty_string_array_schema,
      method_names,
      "rig.create_service method_names"
   )
end

local function normalize_service_provider_map(map, label)
   if map == nil then
      return {}
   end

   return schema.assert(string_to_string_map_schema, map, label)
end

local function normalize_driver_phase_names(phase_names, label)
   if phase_names == nil then
      return {}
   end

   local copied = schema.assert(
      unique_non_empty_string_array_schema,
      phase_names,
      label
   )

   for i = 1, #copied do
      local phase_name = copied[i]
      if core_runtime_phases[phase_name] then
         raise(
            "%s ('%s' is a core runtime phase and must not be redeclared)",
            label,
            phase_name
         )
      end
   end

   return copied
end

M.ServiceRegistry = M.class()

function M.ServiceRegistry:init()
   self._by_id = {}
end

function M.ServiceRegistry:get(service_id)
   return self._by_id[service_id]
end

function M.ServiceRegistry:create_service(service_id, method_names)
   if type(service_id) ~= "string" or service_id == "" then
      raise("rig.create_service expects service_id to be a non-empty string")
   end

   local methods = normalize_service_method_names(method_names)
   local existing = self:get(service_id)
   if existing ~= nil then
      raise("rig.create_service already has a service '%s'", service_id)
   end

   local service = {
      id = service_id,
      methods = methods,
      providers = {},
   }
   self._by_id[service_id] = service
   return service
end

function M.ServiceRegistry:register_service_provider(service_id, provider_id, provider)
   if type(service_id) ~= "string" or service_id == "" then
      raise("rig.register_service_provider expects service_id to be a non-empty string")
   end
   if type(provider_id) ~= "string" or provider_id == "" then
      raise("rig.register_service_provider expects provider_id to be a non-empty string")
   end
   if type(provider) ~= "table" then
      raise("rig.register_service_provider expects provider to be a table")
   end

   local service = self:get(service_id)
   if service == nil then
      raise("rig.register_service_provider does not know service '%s'", service_id)
   end
   if service.providers[provider_id] ~= nil then
      raise(
         "rig.register_service_provider already has a provider for service '%s' with id '%s'",
         service_id,
         provider_id
      )
   end

   for i = 1, #service.methods do
      local method_name = service.methods[i]
      if type(provider[method_name]) ~= "function" then
         raise(
            "rig.register_service_provider requires provider '%s' for service '%s' to implement method '%s'",
            provider_id,
            service_id,
            method_name
         )
      end
   end

   service.providers[provider_id] = provider
   return provider
end

function M.ServiceRegistry:resolve_service_providers(providers)
   local service_providers = {}

   for service_id, provider_id in pairs(providers) do
      local service = self:get(service_id)
      if service == nil then
         raise("references unknown service '%s'", service_id)
      end

      local provider = service.providers[provider_id]
      if provider == nil then
         raise(
            "selects provider '%s' for service '%s', but no such provider is registered",
            provider_id,
            service_id
         )
      end

      service_providers[service_id] = provider
   end

   return service_providers
end

local _service_registry = M.ServiceRegistry()

function M.register_runtime_hook(phase, hook)
   if type(phase) ~= "string" or phase == "" then
      raise("rig.register_runtime_hook expects phase to be a non-empty string")
   end
   if type(hook) ~= "function" then
      raise("rig.register_runtime_hook expects hook to be a function")
   end

   local hooks = _runtime_hooks[phase]
   if hooks == nil then
      hooks = {}
      _runtime_hooks[phase] = hooks
   end
   table.insert(hooks, hook)
end

local function run_runtime_hooks(phase, ...)
   local hooks = _runtime_hooks[phase]
   if hooks == nil then
      return
   end

   for i = 1, #hooks do
      hooks[i](...)
   end
end

M.ActiveRuntime = M.class()

function M.ActiveRuntime:init(spec)
   if type(spec) ~= "table" then
      raise("rig.ActiveRuntime expects a table")
   end

   self.service_registry = spec.service_registry
   self.driver = spec.driver
   self.driver_id = spec.driver_id
   self.mode_id = spec.mode_id
   self.runtime_id = spec.runtime_id
   self.providers = spec.providers or {}
   self.option_hooks = self:normalize_option_hooks(spec.option_hooks)

   local ok, service_providers_or_err = pcall(function()
      return self.service_registry:resolve_service_providers(self.providers)
   end)
   if ok then
      self.service_providers = service_providers_or_err
      return
   end

   raise("rig.run runtime '%s' %s", self.runtime_id, tostring(service_providers_or_err))
end

function M.ActiveRuntime:require_service(service_id)
   local provider = self.service_providers[service_id]
   if provider == nil then
      raise(
         "rig.require_service('%s') has no provider for active runtime '%s'",
         service_id,
         self.runtime_id
      )
   end

   return provider
end

function M.ActiveRuntime:build_phase_set()
   local phases = {}

   for i = 1, #core_runtime_phase_names do
      phases[core_runtime_phase_names[i]] = true
   end
   for i = 1, #self.driver.phases do
      phases[self.driver.phases[i]] = true
   end

   return phases
end

function M.ActiveRuntime:normalize_option_hooks(hooks)
   if hooks == nil then
      return nil
   end

   local allowed_phases = self:build_phase_set()
   local normalized = schema.assert(
      option_hooks_schema,
      hooks,
      "rig.run options.hooks"
   )

   for phase in pairs(normalized) do
      if not allowed_phases[phase] then
         raise(
            "rig.run runtime '%s' does not know hook phase '%s'",
            self.runtime_id,
            phase
         )
      end
   end

   return normalized
end

function M.ActiveRuntime:run_hooks(phase, ...)
   run_runtime_hooks(phase, ...)

   local hook_function = self.option_hooks and self.option_hooks[phase]
   if hook_function ~= nil then
      hook_function(...)
   end
end

local _active_runtime = nil

function M.create_service(service_id, method_names)
   return _service_registry:create_service(service_id, method_names)
end

function M.register_service_provider(service_id, provider_id, provider)
   return _service_registry:register_service_provider(service_id, provider_id, provider)
end

function M.require_service(service_id)
   if type(service_id) ~= "string" or service_id == "" then
      raise("rig.require_service expects service_id to be a non-empty string")
   end

   if getmetatable(_active_runtime) ~= M.ActiveRuntime then
      raise("rig.require_service('%s') requires an active runtime", service_id)
   end

   return _active_runtime:require_service(service_id)
end

function M.register_runtime_driver(name, driver)
   if type(name) ~= "string" or name == "" then
      raise("rig.register_runtime_driver expects name to be a non-empty string")
   end
   if type(driver) ~= "table" then
      raise("rig.register_runtime_driver expects driver to be a table")
   end

   driver.phases = normalize_driver_phase_names(
      driver.phases,
      "rig.register_runtime_driver expects driver.phases to be a table of non-empty strings if provided"
   )

   _runtime_drivers[name] = driver
   return driver
end

function M.register_runtime_preset(name, preset)
   if type(name) ~= "string" or name == "" then
      raise("rig.register_runtime_preset expects name to be a non-empty string")
   end
   if type(preset) ~= "table" then
      raise("rig.register_runtime_preset expects preset to be a table")
   end

   local driver_id = preset.driver
   if driver_id == nil then
      driver_id = name
   end
   if type(driver_id) ~= "string" or driver_id == "" then
      raise("rig.register_runtime_preset expects preset.driver to be a non-empty string")
   end

   local normalized = {
      driver = driver_id,
      providers = normalize_service_provider_map(
         preset.providers,
         "rig.register_runtime_preset expects preset.providers to be a table if provided"
      ),
   }

   _runtime_presets[name] = normalized
   return normalized
end

local function resolve_runtime(options)
   options = schema.assert(
      resolve_runtime_options_schema,
      options,
      "rig.run options"
   )

   local mode_id = options.mode

   local preset = nil
   if mode_id ~= nil then
      preset = _runtime_presets[mode_id]
      if preset == nil then
         raise("rig.run does not know runtime mode '%s'", mode_id)
      end
   end

   local driver_id = options.driver
   if driver_id == nil and preset ~= nil then
      driver_id = preset.driver
   end
   if driver_id == nil then
      raise("rig.run requires options.driver or options.mode to be a non-empty string")
   end

   local driver = _runtime_drivers[driver_id]
   if driver == nil then
      raise("rig.run does not know runtime driver '%s'", driver_id)
   end
   if type(driver.loop) ~= "function" then
      raise("runtime driver '%s' is missing loop()", driver_id)
   end

   local providers = {}
   if preset ~= nil then
      for service_id, provider_id in pairs(preset.providers) do
         providers[service_id] = provider_id
      end
   end

   local override_providers = options.providers or {}
   for service_id, provider_id in pairs(override_providers) do
      providers[service_id] = provider_id
   end

   local runtime_id = mode_id or driver_id
   return driver, M.ActiveRuntime {
      service_registry = _service_registry,
      driver = driver,
      driver_id = driver_id,
      mode_id = mode_id,
      runtime_id = runtime_id,
      providers = providers,
      option_hooks = options.hooks,
   }
end

function M.run(options)
   if type(options) ~= "table" then
      raise("rig.run expects a table")
   end
   local driver, resolved_runtime = resolve_runtime(options)

   local previous_runtime = _active_runtime
   _active_runtime = resolved_runtime

   local ok, err = pcall(function()
      resolved_runtime:run_hooks("before_setup", options)
      if type(driver.setup) == "function" then
         driver.setup(options)
      end
      resolved_runtime:run_hooks("after_setup", options)

      driver.loop(options, function(phase, ...)
         resolved_runtime:run_hooks(phase, ...)
      end)

      resolved_runtime:run_hooks("before_shutdown", options)
      if type(driver.shutdown) == "function" then
         driver.shutdown(options)
      end
      resolved_runtime:run_hooks("after_shutdown", options)
   end)

   _active_runtime = previous_runtime

   if not ok then
      raise(err)
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
      raise("rig.load_script expects script_path to be a string")
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
      ))
end

function M.run_script_file(script_path)
   if type(script_path) ~= "string" then
      raise("rig.run_script_file expects script_path to be a string")
   end

   local file, open_err = io.open(script_path, "rb")
   if file == nil then
      raise(
         "failed to open '%s': %s",
         script_path,
         open_err or "unknown error"
      )
   end

   local source, read_err = file:read("*all")
   file:close()

   if source == nil then
      raise(
         "failed to read '%s': %s",
         script_path,
         read_err or "unknown error"
      )
   end

   local result = M.load_script(script_path, source)

   if script_path:match("_test%.lua$")
      or script_path:match("_test%.fnl$") then
      require("test").run_registered_cases {
         script_path = script_path,
      }
   end

   return result
end

return M
