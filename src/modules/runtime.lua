local M = ... or {}
local rig = require("rig")
local sched = require("sched")

local raise = rig.raise

--[ plugin values ]

local PLUGIN_TABLE_FIELDS = {
   "components",
   "capabilities",
   "requirements",
   "extension_points",
   "schemas",
   "resources",
}

local function plugin_label(plugin)
   if type(plugin) == "table" and type(plugin.id) == "string" and plugin.id ~= "" then
      return plugin.id
   end
   return tostring(plugin)
end

local function validate_capability_declarations(plugin, declarations)
   for id, declaration in pairs(declarations) do
      if type(id) ~= "string" or id == "" then
         raise(
            "runtime plugin '%s' capability ids must be non-empty strings",
            plugin.id
         )
      end
      if type(declaration) ~= "table" then
         raise(
            "runtime plugin '%s' capability '%s' declaration must be a table",
            plugin.id,
            id
         )
      end
   end
end

local function validate_extension_point_declaration(name, declaration, prefix)
   if type(name) ~= "string" or name == "" then
      raise("%s extension point names must be non-empty strings", prefix)
   end
   if type(declaration) ~= "table" then
      raise("%s extension point '%s' declaration must be a table", prefix, name)
   end

   local cardinality = declaration.cardinality
   if cardinality ~= nil and cardinality ~= "single" and cardinality ~= "many" then
      raise(
         "%s extension point '%s' cardinality must be 'single' or 'many'",
         prefix,
         name
      )
   end

   local order = declaration.order
   if order ~= nil and order ~= "registration" and order ~= "reverse" then
      raise(
         "%s extension point '%s' order must be 'registration' or 'reverse'",
         prefix,
         name
      )
   end

   local method = declaration.method
   if method ~= nil and (type(method) ~= "string" or method == "") then
      raise(
         "%s extension point '%s' method must be a non-empty string",
         prefix,
         name
      )
   end

   local payload = declaration.payload
   if payload ~= nil
      and (type(payload) ~= "table" or type(payload.assert) ~= "function") then
      raise(
         "%s extension point '%s' payload must be a schema object",
         prefix,
         name
      )
   end
end

local function validate_extension_point_declarations(plugin, declarations)
   local prefix = ("runtime plugin '%s'"):format(plugin.id)
   for name, declaration in pairs(declarations) do
      validate_extension_point_declaration(name, declaration, prefix)
   end
end

local function validate_plugin(plugin)
   if type(plugin) ~= "table" then
      raise("runtime plugin must be a table")
   end
   if type(plugin.id) ~= "string" or plugin.id == "" then
      raise("runtime plugin requires a non-empty string id")
   end

   for i = 1, #PLUGIN_TABLE_FIELDS do
      local field = PLUGIN_TABLE_FIELDS[i]
      local value = plugin[field]
      if value ~= nil and type(value) ~= "table" then
         raise(
            "runtime plugin '%s' field '%s' must be a table if provided",
            plugin.id,
            field
         )
      end
   end

   if plugin.capabilities ~= nil then
      validate_capability_declarations(plugin, plugin.capabilities)
   end
   if plugin.extension_points ~= nil then
      validate_extension_point_declarations(plugin, plugin.extension_points)
   end

   return plugin
end

function M.plugin(spec)
   return validate_plugin(spec)
end

--[ component descriptors ]

local function validate_descriptor_spec(spec)
   if spec == nil then
      return {}
   end
   if type(spec) ~= "table" then
      raise("runtime descriptor expects a spec table")
   end
   if spec.name ~= nil and (type(spec.name) ~= "string" or spec.name == "") then
      raise("runtime descriptor spec.name expects a non-empty string")
   end
   return spec
end

function M.descriptor(plugin, spec)
   validate_plugin(plugin)
   spec = validate_descriptor_spec(spec)

   local descriptor = {}
   for key, value in pairs(spec) do
      descriptor[key] = value
   end
   descriptor.plugin = plugin
   return descriptor
end

--[ core extension points ]

local CORE_EXTENSION_POINTS = {
   ["core.before_setup"] = { cardinality = "many", method = "before_setup" },
   ["core.after_setup"] = { cardinality = "many", method = "after_setup" },
   ["core.before_frame"] = { cardinality = "many", method = "before_frame" },
   ["core.after_frame"] = { cardinality = "many", method = "after_frame" },
   ["core.before_shutdown"] = { cardinality = "many", method = "before_shutdown" },
   ["core.after_shutdown"] = { cardinality = "many", method = "after_shutdown" },
}

--[ component normalization ]

local function component_label(descriptor, index)
   if type(descriptor.name) == "string" and descriptor.name ~= "" then
      return descriptor.name
   end
   if type(descriptor.kind) == "string" and descriptor.kind ~= "" then
      return descriptor.kind
   end
   return "component#" .. tostring(index)
end

local function normalize_provides(label, raw)
   if raw == nil then
      return {}
   end
   if type(raw) ~= "table" then
      raise(
         "runtime compile: component '%s' field 'provides' must be a table",
         label
      )
   end

   local result = {}
   for i = 1, #raw do
      local entry = raw[i]
      local capability = nil
      local priority = nil
      local properties = nil

      if type(entry) == "string" then
         capability = entry
      elseif type(entry) == "table" then
         capability = entry.capability
         priority = entry.priority
         properties = entry.properties
      else
         raise(
            "runtime compile: component '%s' provides[%d] must be a string or table",
            label,
            i
         )
      end

      if type(capability) ~= "string" or capability == "" then
         raise(
            "runtime compile: component '%s' provides[%d].capability expects a non-empty string",
            label,
            i
         )
      end
      if priority == nil then
         priority = 0
      end
      if type(priority) ~= "number" then
         raise(
            "runtime compile: component '%s' provides[%d].priority expects a number",
            label,
            i
         )
      end
      if properties ~= nil and type(properties) ~= "table" then
         raise(
            "runtime compile: component '%s' provides[%d].properties expects a table",
            label,
            i
         )
      end

      result[#result + 1] = {
         capability = capability,
         priority = priority,
         properties = properties or {},
      }
   end
   return result
end

local function normalize_requires(label, raw)
   if raw == nil then
      return {}
   end
   if type(raw) ~= "table" then
      raise(
         "runtime compile: component '%s' field 'requires' must be a table",
         label
      )
   end

   local result = {}
   for i = 1, #raw do
      local entry = raw[i]
      local capability = nil
      local properties = nil
      local predicate = nil
      local optional = nil

      if type(entry) == "string" then
         capability = entry
      elseif type(entry) == "table" then
         capability = entry.capability
         properties = entry.properties
         predicate = entry.predicate
         optional = entry.optional
      else
         raise(
            "runtime compile: component '%s' requires[%d] must be a string or table",
            label,
            i
         )
      end

      if type(capability) ~= "string" or capability == "" then
         raise(
            "runtime compile: component '%s' requires[%d].capability expects a non-empty string",
            label,
            i
         )
      end
      if properties ~= nil and type(properties) ~= "table" then
         raise(
            "runtime compile: component '%s' requires[%d].properties expects a table",
            label,
            i
         )
      end
      if predicate ~= nil and type(predicate) ~= "function" then
         raise(
            "runtime compile: component '%s' requires[%d].predicate expects a function",
            label,
            i
         )
      end
      if optional ~= nil and type(optional) ~= "boolean" then
         raise(
            "runtime compile: component '%s' requires[%d].optional expects a boolean",
            label,
            i
         )
      end

      result[#result + 1] = {
         capability = capability,
         properties = properties or {},
         predicate = predicate,
         optional = optional == true,
      }
   end
   return result
end

local function normalize_excludes(label, raw)
   if raw == nil then
      return {}
   end
   if type(raw) ~= "table" then
      raise(
         "runtime compile: component '%s' field 'excludes' must be a table",
         label
      )
   end

   local result = {}
   for i = 1, #raw do
      local capability = raw[i]
      if type(capability) ~= "string" or capability == "" then
         raise(
            "runtime compile: component '%s' excludes[%d] expects a non-empty string",
            label,
            i
         )
      end
      result[#result + 1] = capability
   end
   return result
end

local function normalize_component(descriptor, index)
   local label = component_label(descriptor, index)

   if descriptor.create ~= nil and type(descriptor.create) ~= "function" then
      raise("runtime compile: component '%s' create must be a function", label)
   end
   if descriptor.release ~= nil and type(descriptor.release) ~= "function" then
      raise("runtime compile: component '%s' release must be a function", label)
   end

   return {
      descriptor = descriptor,
      index = index,
      label = label,
      name = descriptor.name,
      provides = normalize_provides(label, descriptor.provides),
      requires = normalize_requires(label, descriptor.requires),
      excludes = normalize_excludes(label, descriptor.excludes),
   }
end

--[ registries ]

local function collect_capabilities(plugins)
   local capabilities = {}
   for i = 1, #plugins do
      local plugin = plugins[i]
      local declarations = plugin.capabilities
      if declarations ~= nil then
         for id, declaration in pairs(declarations) do
            if capabilities[id] == nil then
               capabilities[id] = {
                  id = id,
                  owner = plugin,
                  declaration = declaration,
               }
            end
         end
      end
   end
   return capabilities
end

local function collect_extension_points(plugins)
   local extension_points = {}
   for i = 1, #plugins do
      local plugin = plugins[i]
      local declarations = plugin.extension_points
      if declarations ~= nil then
         for name, declaration in pairs(declarations) do
            if extension_points[name] ~= nil then
               raise(
                  "runtime compile: extension point '%s' is declared more than once",
                  name
               )
            end
            validate_extension_point_declaration(
               name,
               declaration,
               ("runtime plugin '%s'"):format(plugin.id)
            )
            extension_points[name] = declaration
         end
      end
   end

   for name, declaration in pairs(CORE_EXTENSION_POINTS) do
      if extension_points[name] ~= nil then
         raise(
            "runtime compile: extension point '%s' redeclares a core extension point",
            name
         )
      end
      validate_extension_point_declaration(name, declaration, "runtime core")
      extension_points[name] = declaration
   end

   return extension_points
end

--[ capability resolution ]

local function matches_requirement(requirement, provider_entry, provider_component)
   for key, value in pairs(requirement.properties) do
      if provider_entry.properties[key] ~= value then
         return false
      end
   end
   if requirement.predicate ~= nil then
      return requirement.predicate(provider_component.descriptor) and true or false
   end
   return true
end

local function resolve_requirements(components, capabilities)
   local providers_by_capability = {}

   for i = 1, #components do
      local component = components[i]
      for j = 1, #component.provides do
         local entry = component.provides[j]
         if capabilities[entry.capability] == nil then
            raise(
               "runtime compile: unknown capability '%s' provided by component '%s'",
               entry.capability,
               component.label
            )
         end
         local list = providers_by_capability[entry.capability]
         if list == nil then
            list = {}
            providers_by_capability[entry.capability] = list
         end
         list[#list + 1] = {
            component = component,
            entry = entry,
         }
      end
   end

   local resolved = {}
   for i = 1, #components do
      local component = components[i]
      local list = {}

      for j = 1, #component.requires do
         local requirement = component.requires[j]
         if capabilities[requirement.capability] == nil then
            raise(
               "runtime compile: unknown capability '%s' required by component '%s'",
               requirement.capability,
               component.label
            )
         end

         local candidates = providers_by_capability[requirement.capability] or {}
         local matched = {}
         for k = 1, #candidates do
            local candidate = candidates[k]
            if candidate.component ~= component
               and matches_requirement(
                  requirement,
                  candidate.entry,
                  candidate.component
               ) then
               matched[#matched + 1] = candidate
            end
         end

         if #matched == 0 then
            if requirement.optional then
               list[#list + 1] = {
                  requirement = requirement,
                  provider = nil,
               }
            elseif #candidates == 0 then
               raise(
                  "runtime compile: component '%s' requires capability '%s' but no component provides it",
                  component.label,
                  requirement.capability
               )
            else
               raise(
                  "runtime compile: component '%s' requires capability '%s' but no candidate matches its constraints",
                  component.label,
                  requirement.capability
               )
            end
         else
            local best = nil
            local best_priority = nil
            local ties = {}
            for k = 1, #matched do
               local candidate = matched[k]
               local priority = candidate.entry.priority
               if best_priority == nil or priority > best_priority then
                  best_priority = priority
                  best = candidate
                  ties = { candidate }
               elseif priority == best_priority then
                  ties[#ties + 1] = candidate
               end
            end

            if #ties > 1 then
               local labels = {}
               for k = 1, #ties do
                  labels[k] = "'" .. ties[k].component.label .. "'"
               end
               raise(
                  "runtime compile: capability '%s' required by component '%s' is provided by multiple components with equal priority: %s",
                  requirement.capability,
                  component.label,
                  table.concat(labels, ", ")
               )
            end

            list[#list + 1] = {
               requirement = requirement,
               provider = best.component,
               provider_entry = best.entry,
            }
         end
      end

      resolved[component] = list
   end

   return resolved, providers_by_capability
end

local function check_excludes(components, providers_by_capability)
   for i = 1, #components do
      local component = components[i]
      for j = 1, #component.excludes do
         local capability = component.excludes[j]
         local providers = providers_by_capability[capability] or {}
         for k = 1, #providers do
            local provider = providers[k]
            if provider.component ~= component then
               raise(
                  "runtime compile: component '%s' excludes capability '%s' provided by '%s'",
                  component.label,
                  capability,
                  provider.component.label
               )
            end
         end
      end
   end
end

--[ dependency ordering ]

local function build_edges(components, resolved)
   local dependencies = {}
   local dependents = {}
   for i = 1, #components do
      dependencies[components[i]] = {}
      dependents[components[i]] = {}
   end

   for i = 1, #components do
      local component = components[i]
      local list = resolved[component] or {}
      for j = 1, #list do
         local provider = list[j].provider
         if provider ~= nil and provider ~= component then
            dependencies[component][provider] = true
            dependents[provider][component] = true
         end
      end
   end

   return dependencies, dependents
end

local function topological_order(components, dependencies, dependents)
   local indegree = {}
   local remaining = {}
   for i = 1, #components do
      local component = components[i]
      local count = 0
      for _ in pairs(dependencies[component]) do
         count = count + 1
      end
      indegree[component] = count
      remaining[component] = true
   end

   local order = {}
   while #order < #components do
      local chosen = nil
      for i = 1, #components do
         local component = components[i]
         if remaining[component] and indegree[component] == 0 then
            chosen = component
            break
         end
      end

      if chosen == nil then
         local cycle = {}
         for i = 1, #components do
            local component = components[i]
            if remaining[component] then
               cycle[#cycle + 1] = "'" .. component.label .. "'"
            end
         end
         raise(
            "runtime compile: dependency cycle detected among %s",
            table.concat(cycle, ", ")
         )
      end

      remaining[chosen] = false
      order[#order + 1] = chosen

      for dependent in pairs(dependents[chosen]) do
         if remaining[dependent] then
            indegree[dependent] = indegree[dependent] - 1
         end
      end
   end

   return order
end

--[ compilation ]

local function build_bindings(components)
   local bindings = {}
   for i = 1, #components do
      local component = components[i]
      if component.name ~= nil then
         if type(component.name) ~= "string" or component.name == "" then
            raise(
               "runtime compile: component '%s' binding name must be a non-empty string",
               component.label
            )
         end
         if bindings[component.name] ~= nil then
            raise(
               "runtime compile: duplicate context binding name '%s'",
               component.name
            )
         end
         bindings[component.name] = component
      end
   end
   return bindings
end

local function validate_component_config(component)
   local config_schema = component.descriptor.config_schema
   if config_schema == nil then
      return
   end
   if type(config_schema) ~= "table" or type(config_schema.assert) ~= "function" then
      raise(
         "runtime compile: component '%s' config_schema must be a schema object",
         component.label
      )
   end

   local config = component.descriptor.config
   if config == nil then
      config = {}
   end
   if type(config) ~= "table" then
      raise(
         "runtime compile: component '%s' config must be a table",
         component.label
      )
   end

   local ok, normalized = pcall(
      config_schema.assert,
      config_schema,
      config,
      ("component '%s' config"):format(component.label)
   )
   if not ok then
      raise("runtime compile: %s", tostring(normalized))
   end
   component.config = normalized
end

local function collect_handlers(registrations, extension_points)
   local handlers = {}
   for i = 1, #registrations do
      local registration = registrations[i]
      local declaration = extension_points[registration.name]
      if declaration == nil then
         raise(
            "runtime compile: unknown extension point '%s'",
            registration.name
         )
      end

      local list = handlers[registration.name]
      if list == nil then
         list = {}
         handlers[registration.name] = list
      end
      list[#list + 1] = registration.handler
   end

   for name, list in pairs(handlers) do
      local declaration = extension_points[name]
      if declaration.cardinality == "single" and #list > 1 then
         raise(
            "runtime compile: extension point '%s' accepts a single handler",
            name
         )
      end
   end

   return handlers
end

local function compile_plan(plugins, descriptors, registrations)
   local capabilities = collect_capabilities(plugins)
   local extension_points = collect_extension_points(plugins)

   local components = {}
   for i = 1, #descriptors do
      local component = normalize_component(descriptors[i], i)
      validate_component_config(component)
      components[i] = component
   end

   local bindings = build_bindings(components)
   local resolved, providers_by_capability =
      resolve_requirements(components, capabilities)
   check_excludes(components, providers_by_capability)

   local dependencies, dependents = build_edges(components, resolved)
   local order = topological_order(components, dependencies, dependents)
   local handlers = collect_handlers(registrations, extension_points)

   local class_methods = {}
   for name, declaration in pairs(extension_points) do
      local method = declaration.method
      if method ~= nil then
         local existing = class_methods[method]
         if existing ~= nil then
            raise(
               "runtime compile: extension points '%s' and '%s' both map to class method '%s'",
               existing,
               name,
               method
            )
         end
         if method == "init" or method == "super" then
            raise(
               "runtime compile: extension point '%s' maps to reserved class method '%s'",
               name,
               method
            )
         end
         class_methods[method] = name
      end
   end

   local event_sources = {}
   for i = 1, #components do
      local component = components[i]
      local source = component.descriptor.event_source
      if source ~= nil then
         if type(source) ~= "table" then
            raise(
               "runtime compile: component '%s' event_source must be a table",
               component.label
            )
         end
         if source.poll ~= nil and type(source.poll) ~= "function" then
            raise(
               "runtime compile: component '%s' event_source.poll must be a function",
               component.label
            )
         end
         if source.events ~= nil then
            if type(source.events) ~= "table" then
               raise(
                  "runtime compile: component '%s' event_source.events must be a table",
                  component.label
               )
            end
            for j = 1, #source.events do
               local event_name = source.events[j]
               if type(event_name) ~= "string" or event_name == "" then
                  raise(
                     "runtime compile: component '%s' event_source.events[%d] expects a non-empty string",
                     component.label,
                     j
                  )
               end
               if extension_points[event_name] == nil then
                  raise(
                     "runtime compile: component '%s' event_source declares unknown event '%s'",
                     component.label,
                     event_name
                  )
               end
            end
         end
         event_sources[#event_sources + 1] = {
            component = component,
            source = source,
         }
      end
   end

   local progress = {}
   for i = 1, #components do
      local component = components[i]
      local operations = component.descriptor.progress
      if operations ~= nil then
         if type(operations) ~= "table" then
            raise(
               "runtime compile: component '%s' progress must be a table",
               component.label
            )
         end
         for key, handler in pairs(operations) do
            if type(handler) ~= "function" then
               raise(
                  "runtime compile: component '%s' progress.%s must be a function",
                  component.label,
                  tostring(key)
               )
            end
         end
         progress[#progress + 1] = {
            component = component,
            handlers = operations,
         }
      end
   end

   return {
      order = order,
      components = components,
      bindings = bindings,
      capabilities = capabilities,
      providers = providers_by_capability,
      resolved = resolved,
      dependencies = dependencies,
      dependents = dependents,
      extension_points = extension_points,
      handlers = handlers,
      class_methods = class_methods,
      event_sources = event_sources,
      progress = progress,
   }
end

--[ execution selection ]

local function resolve_execution(execution, execution_set, registrations)
   local has_handlers = #registrations > 0

   if execution_set and has_handlers then
      raise(
         "runtime compile: cannot mix builder handlers with a function or class execution form"
      )
   end
   if execution_set then
      if type(execution) == "function" then
         return { form = "function", value = execution }
      end
      return { form = "class", value = execution }
   end
   if has_handlers then
      return { form = "hooks", value = nil }
   end

   raise(
      "runtime compile: missing execution configuration; use :execute(...) or :on(...)"
   )
end

--[ progress engine ]

M.ProgressEngine = rig.Class()

function M.ProgressEngine:init(plan)
   self.plan = plan
   self.operations = plan.progress
end

function M.ProgressEngine:_context(runtime, component, step)
   return {
      runtime = runtime,
      plan = self.plan,
      component = component,
      form = self.plan.execution.form,
      ctx = runtime.ctx,
      step = step,
      emit = function(name, payload)
         return runtime:emit(name, payload)
      end,
   }
end

function M.ProgressEngine:should_stop(runtime, step)
   for i = 1, #self.operations do
      local entry = self.operations[i]
      local handler = entry.handlers.should_stop
      if handler ~= nil
         and handler(self:_context(runtime, entry.component, step)) then
         return true
      end
   end
   return false
end

function M.ProgressEngine:step(runtime, step)
   for i = 1, #self.plan.event_sources do
      local entry = self.plan.event_sources[i]
      local poll = entry.source.poll
      if poll ~= nil then
         poll(self:_context(runtime, entry.component, step))
      end
   end

   for i = 1, #self.operations do
      local entry = self.operations[i]
      local handlers = entry.handlers
      local context = self:_context(runtime, entry.component, step)

      if handlers.poll ~= nil then
         handlers.poll(context)
      end
      if handlers.drain ~= nil then
         handlers.drain(context)
      end
      if handlers.frame ~= nil then
         handlers.frame(context)
      end
      if handlers.wait ~= nil then
         handlers.wait(context)
      end
   end
end

function M.ProgressEngine:run(runtime)
   local step = 0
   while not runtime._stop_requested do
      if self:should_stop(runtime, step) then
         break
      end
      step = step + 1
      self:step(runtime, step)
   end
end

--[ resource ownership ]

M.ResourceScope = rig.Class()

function M.ResourceScope:init(label)
   self.label = label or "runtime resource scope"
   self._entries = {}
   self._released = false
end

function M.ResourceScope:adopt(owner, resource, release_fn)
   if self._released then
      raise("cannot adopt into a released %s", self.label)
   end
   if type(release_fn) ~= "function" then
      raise("resource adoption requires a release function")
   end

   self._entries[#self._entries + 1] = {
      owner = owner,
      resource = resource,
      release_fn = release_fn,
   }
   return resource
end

function M.ResourceScope:release()
   if self._released then
      return {}
   end

   local errors = {}
   for i = #self._entries, 1, -1 do
      local entry = self._entries[i]
      local ok, err = pcall(entry.release_fn, entry.resource)
      if not ok then
         local label = "unknown component"
         if entry.owner ~= nil and entry.owner.label ~= nil then
            label = ("component '%s'"):format(entry.owner.label)
         end
         errors[#errors + 1] = ("%s: %s"):format(label, tostring(err))
      end
      self._entries[i] = nil
   end

   self._released = true
   return errors
end

local function format_cleanup_errors(errors)
   local lines = {
      ("runtime cleanup failed with %d error(s):"):format(#errors),
   }
   for i = 1, #errors do
      lines[#lines + 1] = "  " .. errors[i]
   end
   return table.concat(lines, "\n")
end

--[ clock, timer, and scheduler components ]

M.CANCELLED = {}

M.Clock = rig.Class()

function M.Clock:init(options)
   options = options or {}
   self._now = options.now or function()
      return os.time()
   end
   self._monotonic = options.monotonic or function()
      return os.clock()
   end
   self._wait = options.wait
end

function M.Clock:now()
   return self._now()
end

function M.Clock:monotonic()
   return self._monotonic()
end

function M.Clock:wait(seconds)
   if self._wait ~= nil then
      return self._wait(seconds)
   end
end

M.ManualClock = rig.Class()

function M.ManualClock:init(initial)
   self._time = initial or 0.0
end

function M.ManualClock:now()
   return self._time
end

function M.ManualClock:monotonic()
   return self._time
end

function M.ManualClock:advance(seconds)
   self._time = self._time + seconds
end

function M.ManualClock:wait(seconds)
   self:advance(seconds)
end

M.Timer = rig.Class()

function M.Timer:init()
   self._entries = {}
end

function M.Timer:schedule(deadline, callback)
   if type(deadline) ~= "number" then
      raise("timer schedule expects a numeric deadline")
   end
   if type(callback) ~= "function" then
      raise("timer schedule expects a callback function")
   end

   local entry = {
      deadline = deadline,
      callback = callback,
   }
   self._entries[#self._entries + 1] = entry
   return entry
end

function M.Timer:cancel(entry)
   if entry ~= nil then
      entry.callback = nil
   end
end

function M.Timer:next_deadline()
   local best = nil
   for i = 1, #self._entries do
      local entry = self._entries[i]
      if entry.callback ~= nil and (best == nil or entry.deadline < best) then
         best = entry.deadline
      end
   end
   return best
end

function M.Timer:advance(now)
   local fired = 0
   while true do
      local chosen_index = nil
      local chosen = nil
      for i = 1, #self._entries do
         local entry = self._entries[i]
         if entry.callback ~= nil
            and entry.deadline <= now
            and (chosen == nil or entry.deadline < chosen.deadline) then
            chosen = entry
            chosen_index = i
         end
      end

      if chosen == nil then
         break
      end

      local callback = chosen.callback
      chosen.callback = nil
      self._entries[chosen_index] = self._entries[#self._entries]
      self._entries[#self._entries] = nil

      callback()
      fired = fired + 1
   end

   return fired
end

M.Scheduler = rig.Class()

function M.Scheduler:init(spec)
   self.clock = spec.clock
   self.timer = spec.timer
   self.inner = sched.Scheduler(spec.label)
   self._foreground = {}
   self._background = {}
   self.foreground_count = 0
   self.had_foreground = false

   self.inner:set_handler("sched.sleep", function(scheduler, task, seconds)
      local ticket = scheduler:start_async(task)
      self.timer:schedule(self.clock:monotonic() + seconds, function()
         ticket:wake()
      end)
   end)
end

function M.Scheduler:activate()
   self.inner:activate()
end

function M.Scheduler:spawn(fn, ...)
   local task = self.inner:spawn(fn, ...)
   self._foreground[task] = true
   self.foreground_count = self.foreground_count + 1
   self.had_foreground = true
   return task
end

function M.Scheduler:spawn_background(fn, ...)
   local task = self.inner:spawn(fn, ...)
   self._background[task] = true
   return task
end

function M.Scheduler:sleep(seconds)
   return sched.sleep(seconds)
end

function M.Scheduler:yield()
   return sched.yield()
end

function M.Scheduler:park()
   return sched.park()
end

function M.Scheduler:join(tasks)
   return sched.join(tasks)
end

function M.Scheduler:now()
   return self.clock:now()
end

function M.Scheduler:monotonic()
   return self.clock:monotonic()
end

function M.Scheduler:_reap()
   for task in pairs(self._foreground) do
      if task:is_done() then
         self._foreground[task] = nil
         self.foreground_count = self.foreground_count - 1
      end
   end
   for task in pairs(self._background) do
      if task:is_done() then
         self._background[task] = nil
      end
   end
end

function M.Scheduler:step()
   local now = self.clock:monotonic()
   self.timer:advance(now)
   self.inner:drain()
   self:_reap()

   if self.foreground_count > 0
      and not self.inner:has_ready_work()
      and self.inner:pending_async() == 0
      and self.timer:next_deadline() == nil then
      raise(
         "runtime scheduler deadlocked: tasks are waiting but no progress is pending"
      )
   end
end

function M.Scheduler:wait()
   self:_reap()
   if self.inner:has_ready_work() then
      return
   end
   if self.foreground_count == 0 and not self.inner:has_active_tasks() then
      return
   end

   local deadline = self.timer:next_deadline()
   if deadline == nil then
      return
   end

   local now = self.clock:monotonic()
   if deadline > now and self.clock.wait ~= nil then
      self.clock:wait(deadline - now)
   end
end

function M.Scheduler:should_stop()
   self:_reap()
   return self.had_foreground and self.foreground_count == 0
end

function M.Scheduler:cancel_background()
   for task in pairs(self._background) do
      if not task:is_done() then
         pcall(function()
            self.inner:wake_task(task, M.CANCELLED)
         end)
      end
   end
end

function M.Scheduler:shutdown()
   self:cancel_background()
   local ok, err = pcall(function()
      self.inner:drain()
   end)
   self.inner:deactivate()
   if not ok then
      raise(err)
   end
end

--[ scheduler component helpers ]

function M.scheduler_plugin(spec)
   spec = spec or {}
   return M.plugin {
      id = spec.id or "runtime.sched",
      capabilities = {
         ["sched.clock"] = {},
         ["sched.timer"] = {},
         ["sched.scheduler"] = {},
      },
   }
end

function M.clock_component(plugin, options)
   options = options or {}
   local clock = options.clock or M.Clock(options)
   return M.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "sched.clock", properties = { protocol = "sched" } },
      },
      create = function()
         return clock
      end,
   })
end

function M.timer_component(plugin, options)
   options = options or {}
   local timer = options.timer or M.Timer()
   return M.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "sched.timer", properties = { protocol = "sched" } },
      },
      create = function()
         return timer
      end,
   })
end

local function find_requirement_value(context, capability)
   for i = 1, #context.requires do
      local entry = context.requires[i]
      if entry.requirement.capability == capability then
         return entry.value
      end
   end
   return nil
end

function M.scheduler_component(plugin, options)
   options = options or {}
   return M.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "sched.scheduler", properties = { protocol = "sched" } },
      },
      requires = {
         { capability = "sched.clock", properties = { protocol = "sched" } },
         { capability = "sched.timer", properties = { protocol = "sched" } },
      },
      create = function(context)
         return M.Scheduler {
            clock = find_requirement_value(context, "sched.clock"),
            timer = find_requirement_value(context, "sched.timer"),
            label = options.label,
         }
      end,
      progress = {
         drain = function(context)
            local scheduler = context.runtime.scheduler
            if scheduler ~= nil then
               scheduler:step()
            end
         end,
         should_stop = function(context)
            local scheduler = context.runtime.scheduler
            if scheduler ~= nil then
               return scheduler:should_stop()
            end
            return false
         end,
         wait = function(context)
            local scheduler = context.runtime.scheduler
            if scheduler ~= nil then
               scheduler:wait()
            end
         end,
      },
   })
end

--[ compiled runtime ]

M.Compiled = rig.Class()

function M.Compiled:init(spec)
   self.state = "compiled"
   self.plugins = spec.plugins
   self.descriptors = spec.descriptors
   self.handlers = spec.handlers
   self.execution = spec.execution
   self.execution_form = spec.plan.execution.form
   self.plan = spec.plan
   self.ctx = nil
   self.instance = nil
   self.engine = nil
   self.error = nil
   self.resources = M.ResourceScope("runtime resources")
   self.scheduler = nil
   self.clock = nil
   self.timer = nil
   self.capability_values = {}
   self._stop_requested = false
end

function M.Compiled:stop()
   if self.state ~= "running" then
      raise("runtime cannot stop in state '%s'", self.state)
   end
   self._stop_requested = true
end

function M.Compiled:_component_context(component, values)
   local requirements = {}
   local resolved = self.plan.resolved[component] or {}
   for i = 1, #resolved do
      local entry = resolved[i]
      requirements[#requirements + 1] = {
         requirement = entry.requirement,
         provider = entry.provider,
         value = entry.provider ~= nil and values[entry.provider] or nil,
         binding = entry.provider ~= nil and entry.provider.name or nil,
      }
   end

   return {
      plan = self.plan,
      ctx = self.ctx,
      values = values,
      component = component,
      requires = requirements,
      runtime = self,
      adopt = function(resource, release_fn)
         return self.resources:adopt(component, resource, release_fn)
      end,
      capability = function(self, capability_id)
         for i = 1, #requirements do
            if requirements[i].requirement.capability == capability_id then
               return requirements[i].value
            end
         end
         return nil
      end,
   }
end

function M.Compiled:_instantiate()
   local values = {}

   for i = 1, #self.plan.order do
      local component = self.plan.order[i]
      local create = component.descriptor.create
      local value = nil

      if create ~= nil then
         local ok, created = pcall(
            create,
            self:_component_context(component, values)
         )
         if not ok then
            raise(
               "runtime component '%s' failed during startup: %s",
               component.label,
               tostring(created)
            )
         end
         value = created
      end

      values[component] = value
      if value ~= nil then
         for j = 1, #component.provides do
            local capability = component.provides[j].capability
            if self.capability_values[capability] == nil then
               self.capability_values[capability] = value
            end
            if capability == "sched.scheduler" then
               self.scheduler = value
            elseif capability == "sched.clock" then
               self.clock = value
            elseif capability == "sched.timer" then
               self.timer = value
            end
         end
      end
      if value ~= nil and component.name ~= nil then
         self.ctx[component.name] = value
      end

      local release = component.descriptor.release
      if value ~= nil and release ~= nil then
         self.resources:adopt(component, value, function(resource)
            return release(resource)
         end)
      end
   end
end

function M.Compiled:_run_progress_engine()
   local engine = M.ProgressEngine(self.plan)
   self.engine = engine
   engine:run(self)
end

function M.Compiled:_shutdown_scheduler()
   local scheduler = self.scheduler
   if scheduler == nil then
      return
   end
   self.scheduler = nil
   scheduler:shutdown()
end

function M.Compiled:_validate_payload(name, declaration, payload)
   local payload_schema = declaration.payload
   if payload_schema == nil then
      return payload
   end
   return payload_schema:assert(
      payload,
      ("extension point '%s' payload"):format(name)
   )
end

function M.Compiled:emit(name, payload)
   if type(name) ~= "string" or name == "" then
      raise("runtime:emit expects a non-empty string event name")
   end

   local declaration = self.plan.extension_points[name]
   if declaration == nil then
      raise("runtime cannot emit unknown extension point '%s'", name)
   end

   payload = self:_validate_payload(name, declaration, payload)

   local handlers = self.plan.handlers[name]
   if handlers ~= nil then
      if declaration.order == "reverse" then
         for i = #handlers, 1, -1 do
            handlers[i](payload)
         end
      else
         for i = 1, #handlers do
            handlers[i](payload)
         end
      end
   end

   if self.execution_form == "class" and self.instance ~= nil then
      local method = declaration.method
      if method ~= nil and type(self.instance[method]) == "function" then
         self.instance[method](self.instance, payload)
      end
   end
end

function M.Compiled:_emit_phase(name)
   return self:emit(name, {
      runtime = self,
      ctx = self.ctx,
   })
end

function M.Compiled:_teardown()
   local errors = {}

   local before_ok, before_err = pcall(function()
      self:_emit_phase("core.before_shutdown")
   end)
   if not before_ok then
      errors[#errors + 1] = tostring(before_err)
   end

   local scheduler_ok, scheduler_err = pcall(function()
      self:_shutdown_scheduler()
   end)
   if not scheduler_ok then
      errors[#errors + 1] = tostring(scheduler_err)
   end

   local cleanup_errors = self.resources:release()
   for i = 1, #cleanup_errors do
      errors[#errors + 1] = cleanup_errors[i]
   end

   local after_ok, after_err = pcall(function()
      self:_emit_phase("core.after_shutdown")
   end)
   if not after_ok then
      errors[#errors + 1] = tostring(after_err)
   end

   return errors
end

function M.Compiled:_run()
   self.ctx = {}
   self:_emit_phase("core.before_setup")
   self:_instantiate()
   if self.scheduler ~= nil then
      self.scheduler:activate()
   end
   self.state = "running"

   local execution = self.plan.execution
   if execution.form == "class" then
      self.instance = execution.value(self.ctx)
      if type(self.instance) == "table" then
         self.instance.ctx = self.ctx
      end
   end

   self:_emit_phase("core.after_setup")

   if execution.form == "function" then
      if self.scheduler ~= nil then
         self.scheduler:spawn(execution.value, self.ctx)
         self:_run_progress_engine()
      else
         execution.value(self.ctx)
      end
      return
   end

   self:_run_progress_engine()
end

function M.Compiled:start()
   if self.state ~= "compiled" then
      raise("runtime cannot start in state '%s'", self.state)
   end

   self.state = "starting"
   self._stop_requested = false

   local ok, err = pcall(function()
      self:_run()
   end)

   if not ok then
      local errors = {}
      if self.state == "running" then
         errors = self:_teardown()
      else
         local cleanup_errors = self.resources:release()
         for i = 1, #cleanup_errors do
            errors[#errors + 1] = cleanup_errors[i]
         end
      end

      self.state = "failed"
      self.error = err
      if #errors > 0 then
         self.error = ("%s\n%s"):format(tostring(err), format_cleanup_errors(errors))
      end
      error(self.error, 0)
   end

   self.state = "stopping"
   local errors = self:_teardown()

   if #errors > 0 then
      self.state = "failed"
      self.error = format_cleanup_errors(errors)
      error(self.error, 0)
   end

   self.state = "stopped"
   return self
end

--[ builder ]

M.Builder = rig.Class()

local function ensure_building(self, action)
   if self.state ~= "building" then
      raise(
         "runtime builder is in state '%s' and cannot %s",
         self.state,
         action
      )
   end
end

local function copy_array(source)
   local copy = {}
   for i = 1, #source do
      copy[i] = source[i]
   end
   return copy
end

function M.Builder:init()
   self.state = "building"
   self._plugins = {}
   self._plugin_set = {}
   self._plugin_ids = {}
   self._descriptors = {}
   self._handlers = {}
   self._execution = nil
   self._execution_set = false
end

function M.Builder:use(plugin)
   ensure_building(self, "attach a plugin")
   validate_plugin(plugin)

   if self._plugin_set[plugin] then
      raise("runtime builder already attached plugin '%s'", plugin.id)
   end
   if self._plugin_ids[plugin.id] ~= nil then
      raise(
         "runtime builder already attached a plugin with id '%s'",
         plugin.id
      )
   end

   self._plugin_set[plugin] = true
   self._plugin_ids[plugin.id] = plugin
   table.insert(self._plugins, plugin)
   return self
end

function M.Builder:add(descriptor)
   ensure_building(self, "add a component")

   if type(descriptor) ~= "table" then
      raise("runtime builder:add expects a component descriptor table")
   end

   local plugin = descriptor.plugin
   if plugin == nil then
      raise(
         "runtime builder:add expects a descriptor created by an attached plugin"
      )
   end
   if not self._plugin_set[plugin] then
      raise(
         "runtime builder:add received a descriptor from plugin '%s' that is not attached",
         plugin_label(plugin)
      )
   end
   if descriptor.name ~= nil
      and (type(descriptor.name) ~= "string" or descriptor.name == "") then
      raise("runtime builder:add descriptor.name expects a non-empty string")
   end

   table.insert(self._descriptors, descriptor)
   return self
end

function M.Builder:on(name, handler)
   ensure_building(self, "register a handler")

   if type(name) ~= "string" or name == "" then
      raise("runtime builder:on expects a non-empty string name")
   end
   if type(handler) ~= "function" then
      raise("runtime builder:on expects a handler function")
   end

   table.insert(self._handlers, {
      name = name,
      handler = handler,
   })
   return self
end

function M.Builder:execute(execution)
   ensure_building(self, "select an execution form")

   if type(execution) ~= "function" and not rig.is_class(execution) then
      raise("runtime builder:execute expects a function or class")
   end
   if self._execution_set then
      raise("runtime builder:execute already has an execution form")
   end

   self._execution = execution
   self._execution_set = true
   return self
end

function M.Builder:has_execution()
   return self._execution_set
end

function M.Builder:has_handlers()
   return #self._handlers > 0
end

function M.Builder:compile()
   if self.state ~= "building" then
      raise("runtime builder is in state '%s' and cannot compile", self.state)
   end

   local plugins = copy_array(self._plugins)
   local descriptors = copy_array(self._descriptors)
   local registrations = copy_array(self._handlers)

   local execution =
      resolve_execution(self._execution, self._execution_set, registrations)
   local plan = compile_plan(plugins, descriptors, registrations)
   plan.execution = execution

   self.state = "compiled"

   return M.Compiled {
      plugins = plugins,
      descriptors = descriptors,
      handlers = registrations,
      execution = self._execution,
      plan = plan,
   }
end

--[ convenience bundles ]

function M.headless_bundle(builder, options)
   options = options or {}
   local core = M.scheduler_plugin()

   builder:use(core)
   builder:add(M.clock_component(core, {
      name = "clock",
      clock = options.clock,
   }))
   builder:add(M.timer_component(core, {
      name = "timer",
      timer = options.timer,
   }))
   builder:add(M.scheduler_component(core, { name = "scheduler" }))
   return builder
end

return M
