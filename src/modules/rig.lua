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
      self._entries[index] = nil
   end

   self._named_entries = {}
   self._released = true
end

M.App = M.class()

function M.App:build_hooks(allowed_phases)
   if type(allowed_phases) ~= "table" then
      raise("rig.App:build_hooks requires an allowed phase map")
   end

   local hooks = {}
   for phase in pairs(allowed_phases) do
      local hook = self[phase]
      if type(hook) == "function" then
         hooks[phase] = function(...)
            return hook(self, ...)
         end
      end
   end

   return hooks
end

function M.App:build_event_handlers(allowed_events)
   if type(allowed_events) ~= "table" then
      raise("rig.App:build_event_handlers requires an allowed event map")
   end

   local handlers = {}
   for event_name in pairs(allowed_events) do
      local handler = self["on_" .. event_name]
      if type(handler) == "function" then
         handlers[event_name] = function(...)
            return handler(self, ...)
         end
      end
   end

   return handlers
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

local function build_allowed_phase_map(driver)
   local allowed_phases = {}

   for i = 1, #core_runtime_phase_names do
      allowed_phases[core_runtime_phase_names[i]] = true
   end

   for i = 1, #driver.phases do
      allowed_phases[driver.phases[i]] = true
   end

   return allowed_phases
end

local function build_allowed_event_map(driver)
   local allowed_events = {}
   local driver_events = driver.events or {}

   for i = 1, #driver_events do
      allowed_events[driver_events[i]] = true
   end

   return allowed_events
end

local function compose_hooks(first, second)
   if first == nil then
      return second
   end
   if second == nil then
      return first
   end

   return function(...)
      first(...)
      second(...)
   end
end

local function compose_event_handlers(first, second)
   if first == nil then
      return second
   end
   if second == nil then
      return first
   end

   return function(...)
      first(...)
      second(...)
   end
end

local function validate_app_spec(app_spec)
   if app_spec == nil then
      return
   end
   if type(app_spec) ~= "table" then
      raise("rig.run expects options.app to be a rig.App class or instance")
   end

   if M.App:is_instance(app_spec) or app_spec:is_descendant(M.App) then
      return
   end

   raise("rig.run expects options.app to be a rig.App class or instance")
end

local function instantiate_app(app_spec, options)
   if app_spec == nil then
      return nil
   end
   validate_app_spec(app_spec)

   if M.App:is_instance(app_spec) then
      return app_spec
   end

   return app_spec(options)
end

local function merge_run_hooks(app_hooks, option_hooks)
   if app_hooks == nil then
      return option_hooks
   end
   if option_hooks == nil then
      return app_hooks
   end

   local merged = {}
   for phase, hook in pairs(app_hooks) do
      merged[phase] = hook
   end

   for phase, hook in pairs(option_hooks) do
      if phase == "before_shutdown" then
         merged[phase] = compose_hooks(hook, merged[phase])
      else
         merged[phase] = compose_hooks(merged[phase], hook)
      end
   end

   return merged
end

local function merge_event_handlers(app_handlers, option_handlers)
   if app_handlers == nil then
      return option_handlers
   end
   if option_handlers == nil then
      return app_handlers
   end

   local merged = {}
   for event_name, handler in pairs(app_handlers) do
      merged[event_name] = handler
   end

   for event_name, handler in pairs(option_handlers) do
      merged[event_name] = compose_event_handlers(merged[event_name], handler)
   end

   return merged
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

   local methods = schema.assert(
      unique_non_empty_string_array_schema,
      method_names,
      "rig.create_service method_names"
   )
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
   self.providers = spec.providers or {}
   self.app_spec = spec.app
   self.app = nil
   self.option_event_handlers = self:normalize_option_event_handlers(spec.option_event_handlers)
   self.option_hooks = self:normalize_option_hooks(spec.option_hooks)

   local ok, service_providers_or_err = pcall(function()
      return self.service_registry:resolve_service_providers(self.providers)
   end)
   if ok then
      self.service_providers = service_providers_or_err
      return
   end

   raise(
      "rig.run runtime '%s' %s",
      self:runtime_id(),
      service_providers_or_err
   )
end

function M.ActiveRuntime:runtime_id()
   return self.mode_id or self.driver_id
end

function M.ActiveRuntime:require_service(service_id)
   local provider = self.service_providers[service_id]
   if provider == nil then
      raise(
         "rig.require_service('%s') has no provider for active runtime '%s'",
         service_id,
         self:runtime_id()
      )
   end

   return provider
end

local option_hooks_schema = schema.map(
   non_empty_string_schema,
   schema.func()
)
local option_event_handlers_schema = schema.map(
   non_empty_string_schema,
   schema.func()
)

function M.ActiveRuntime:normalize_option_event_handlers(event_handlers)
   if event_handlers == nil then
      return nil
   end

   local allowed_events = build_allowed_event_map(self.driver)
   local normalized = schema.assert(
      option_event_handlers_schema,
      event_handlers,
      "rig.run options.event_handlers"
   )

   for event_name in pairs(normalized) do
      if not allowed_events[event_name] then
         raise(
            "rig.run runtime '%s' does not know event handler '%s'",
            self:runtime_id(),
            event_name
         )
      end
   end

   return normalized
end

function M.ActiveRuntime:normalize_option_hooks(hooks)
   if hooks == nil then
      return nil
   end

   local allowed_phases = build_allowed_phase_map(self.driver)

   local normalized = schema.assert(
      option_hooks_schema,
      hooks,
      "rig.run options.hooks"
   )

   for phase in pairs(normalized) do
      if not allowed_phases[phase] then
         raise(
            "rig.run runtime '%s' does not know hook phase '%s'",
            self:runtime_id(),
            phase
         )
      end
   end

   return normalized
end

function M.ActiveRuntime:event_handler(event_name)
   if self.option_event_handlers == nil then
      return nil
   end

   return self.option_event_handlers[event_name]
end

function M.ActiveRuntime:run_hooks(phase, ...)
   run_runtime_hooks(phase, ...)

   local hook_function = self.option_hooks and self.option_hooks[phase]
   if hook_function ~= nil then
      hook_function(...)
   end
end

function M.ActiveRuntime:activate_app(options)
   if self.app_spec == nil or self.app ~= nil then
      return
   end

   local allowed_phases = build_allowed_phase_map(self.driver)
   local allowed_events = build_allowed_event_map(self.driver)
   self.app = instantiate_app(self.app_spec, options)
   self.option_event_handlers = merge_event_handlers(
      self.app:build_event_handlers(allowed_events),
      self.option_event_handlers
   )
   self.option_hooks = merge_run_hooks(
      self.app:build_hooks(allowed_phases),
      self.option_hooks
   )
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

   if not _active_runtime then
      raise("rig.require_service('%s') requires an active runtime", service_id)
   end

   return _active_runtime:require_service(service_id)
end

local runtime_driver_schema = schema.record({
   events = unique_non_empty_string_array_schema:optional(),
   phases = unique_non_empty_string_array_schema:optional(),
   setup = schema.func():optional(),
   loop = schema.func(),
   shutdown = schema.func():optional(),
})

function M.register_runtime_driver(name, driver)
   if type(name) ~= "string" or name == "" then
      raise("rig.register_runtime_driver expects name to be a non-empty string")
   end

   local normalized = schema.assert(
      runtime_driver_schema,
      driver,
      "rig.register_runtime_driver driver"
   )
   normalized.events = normalized.events or {}
   normalized.phases = normalized.phases or {}
   for i = 1, #normalized.phases do
      local phase_name = normalized.phases[i]
      if core_runtime_phases[phase_name] then
         raise(
            "rig.register_runtime_driver driver.phases ('%s' is a core runtime phase and must not be redeclared)",
            phase_name
         )
      end
   end

   _runtime_drivers[name] = normalized
   return normalized
end

local runtime_preset_schema = schema.record({
   driver = non_empty_string_schema,
   providers = string_to_string_map_schema:optional(),
})

function M.register_runtime_preset(name, preset)
   if type(name) ~= "string" or name == "" then
      raise("rig.register_runtime_preset expects name to be a non-empty string")
   end
   if _runtime_presets[name] ~= nil then
      raise("rig.register_runtime_preset already has a runtime preset '%s'", name)
   end

   local normalized = schema.assert(
      runtime_preset_schema,
      preset,
      "rig.register_runtime_preset preset"
   )
   normalized.providers = normalized.providers or {}

   _runtime_presets[name] = normalized
   return normalized
end

local resolve_runtime_options_schema = schema.record({
   mode = non_empty_string_schema:optional(),
   driver = non_empty_string_schema:optional(),
   providers = string_to_string_map_schema:optional(),
}, {
   allow_extra = true,
})

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
   validate_app_spec(options.app)

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

   return driver, M.ActiveRuntime {
      service_registry = _service_registry,
      driver = driver,
      driver_id = driver_id,
      mode_id = mode_id,
      providers = providers,
      app = options.app,
      option_event_handlers = options.event_handlers,
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
         driver.setup(options, resolved_runtime)
      end
      resolved_runtime:activate_app(options)
      resolved_runtime:run_hooks("after_setup", options)

      driver.loop(options, function(phase, ...)
         resolved_runtime:run_hooks(phase, ...)
      end, resolved_runtime)

      resolved_runtime:run_hooks("before_shutdown", options)
      if type(driver.shutdown) == "function" then
         driver.shutdown(options, resolved_runtime)
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
