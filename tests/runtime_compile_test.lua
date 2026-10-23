local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local schema = require("schema")

local function plugin(id, spec)
   spec = spec or {}
   spec.id = id
   return runtime.plugin(spec)
end

local function compile(builder)
   if not builder:has_execution() and not builder:has_handlers() then
      builder:execute(function() end)
   end
   return builder:compile()
end

test.case("compile resolves capabilities and orders providers first", function()
   local core = plugin("core", {
      capabilities = { bus = {} },
   })
   local provider = runtime.descriptor(core, {
      name = "provider",
      provides = { "bus" },
   })
   local consumer = runtime.descriptor(core, {
      name = "consumer",
      requires = { "bus" },
   })

   local compiled = compile(
      rig.runtime()
         :use(core)
         :add(consumer)
         :add(provider)
   )

   local bindings = compiled.plan.bindings
   test.equal(#compiled.plan.order, 2)
   test.equal(compiled.plan.order[1], bindings.provider)
   test.equal(compiled.plan.order[2], bindings.consumer)
   test.equal(compiled.plan.resolved[bindings.consumer][1].provider, bindings.provider)
end)

test.case("compile rejects a requirement with no provider", function()
   local core = plugin("core", {
      capabilities = { bus = {} },
   })
   local consumer = runtime.descriptor(core, {
      name = "consumer",
      requires = { "bus" },
   })

   local ok, err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :add(consumer)
      )
   end)

   test.falsey(ok)
   test.match(tostring(err), "requires capability 'bus' but no component provides it")
end)

test.case("compile allows optional requirements with no provider", function()
   local core = plugin("core", {
      capabilities = { bus = {} },
   })
   local consumer = runtime.descriptor(core, {
      name = "consumer",
      requires = {
         { capability = "bus", optional = true },
      },
   })

   local compiled = compile(
      rig.runtime()
         :use(core)
         :add(consumer)
   )

   local component = compiled.plan.components[1]
   test.equal(#compiled.plan.resolved[component], 1)
   test.equal(compiled.plan.resolved[component][1].provider, nil)
end)

test.case("compile distinguishes constraint conflicts from absence", function()
   local core = plugin("core", {
      capabilities = { graphics = {} },
   })
   local provider = runtime.descriptor(core, {
      name = "gl",
      provides = {
         { capability = "graphics", properties = { backend = "gl" } },
      },
   })
   local consumer = runtime.descriptor(core, {
      name = "app",
      requires = {
         { capability = "graphics", properties = { backend = "gpu" } },
      },
   })

   local ok, err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :add(provider)
            :add(consumer)
      )
   end)

   test.falsey(ok)
   test.match(tostring(err), "no candidate matches its constraints")
end)

test.case("compile selects the highest-priority provider", function()
   local core = plugin("core", {
      capabilities = { graphics = {} },
   })
   local low = runtime.descriptor(core, {
      name = "low",
      provides = {
         { capability = "graphics", priority = 1 },
      },
   })
   local high = runtime.descriptor(core, {
      name = "high",
      provides = {
         { capability = "graphics", priority = 5 },
      },
   })
   local consumer = runtime.descriptor(core, {
      name = "app",
      requires = { "graphics" },
   })

   local compiled = compile(
      rig.runtime()
         :use(core)
         :add(low)
         :add(high)
         :add(consumer)
   )

   local bindings = compiled.plan.bindings
   test.equal(compiled.plan.resolved[bindings.app][1].provider, bindings.high)
end)

test.case("compile rejects an equal-priority tie", function()
   local core = plugin("core", {
      capabilities = { graphics = {} },
   })
   local first = runtime.descriptor(core, {
      name = "first",
      provides = {
         { capability = "graphics", priority = 2 },
      },
   })
   local second = runtime.descriptor(core, {
      name = "second",
      provides = {
         { capability = "graphics", priority = 2 },
      },
   })
   local consumer = runtime.descriptor(core, {
      name = "app",
      requires = { "graphics" },
   })

   local ok, err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :add(first)
            :add(second)
            :add(consumer)
      )
   end)

   test.falsey(ok)
   test.match(tostring(err), "multiple components with equal priority")
end)

test.case("compile applies requirement predicates", function()
   local core = plugin("core", {
      capabilities = { graphics = {} },
   })
   local first = runtime.descriptor(core, {
      name = "first",
      provides = { "graphics" },
   })
   local second = runtime.descriptor(core, {
      name = "second",
      provides = { "graphics" },
   })
   local consumer = runtime.descriptor(core, {
      name = "app",
      requires = {
         {
            capability = "graphics",
            predicate = function(descriptor)
               return descriptor.name == "second"
            end,
         },
      },
   })

   local compiled = compile(
      rig.runtime()
         :use(core)
         :add(first)
         :add(second)
         :add(consumer)
   )

   local bindings = compiled.plan.bindings
   test.equal(compiled.plan.resolved[bindings.app][1].provider, bindings.second)
end)

test.case("compile rejects references to undeclared capabilities", function()
   local core = plugin("core", {
      capabilities = {},
   })
   local provider = runtime.descriptor(core, {
      name = "provider",
      provides = { "missing" },
   })

   local ok, err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :add(provider)
      )
   end)

   test.falsey(ok)
   test.match(tostring(err), "unknown capability 'missing' provided by component 'provider'")

   local consumer = runtime.descriptor(core, {
      name = "consumer",
      requires = { "missing" },
   })

   local ok2, err2 = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :add(consumer)
      )
   end)

   test.falsey(ok2)
   test.match(tostring(err2), "unknown capability 'missing' required by component 'consumer'")
end)

test.case("compile detects dependency cycles", function()
   local core = plugin("core", {
      capabilities = { alpha = {}, beta = {} },
   })
   local first = runtime.descriptor(core, {
      name = "first",
      provides = { "alpha" },
      requires = { "beta" },
   })
   local second = runtime.descriptor(core, {
      name = "second",
      provides = { "beta" },
      requires = { "alpha" },
   })

   local ok, err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :add(first)
            :add(second)
      )
   end)

   test.falsey(ok)
   test.match(tostring(err), "dependency cycle detected")
   test.match(tostring(err), "'first'")
   test.match(tostring(err), "'second'")
end)

test.case("compile rejects duplicate context binding names", function()
   local core = plugin("core")
   local first = runtime.descriptor(core, { name = "same" })
   local second = runtime.descriptor(core, { name = "same" })

   local ok, err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :add(first)
            :add(second)
      )
   end)

   test.falsey(ok)
   test.match(tostring(err), "duplicate context binding name 'same'")
end)

test.case("compile validates extension-point handlers", function()
   local core = plugin("core", {
      extension_points = {
         ["demo.single"] = { cardinality = "single" },
         ["demo.many"] = { cardinality = "many" },
      },
   })

   local unknown_ok, unknown_err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :on("demo.missing", function() end)
      )
   end)
   test.falsey(unknown_ok)
   test.match(tostring(unknown_err), "unknown extension point 'demo.missing'")

   local single_ok, single_err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :on("demo.single", function() end)
            :on("demo.single", function() end)
      )
   end)
   test.falsey(single_ok)
   test.match(tostring(single_err), "accepts a single handler")

   local compiled = compile(
      rig.runtime()
         :use(core)
         :on("demo.many", function() end)
         :on("demo.many", function() end)
   )
   test.equal(#compiled.plan.handlers["demo.many"], 2)
end)

test.case("compile accepts core extension points", function()
   local observer = function() end
   local compiled = compile(
      rig.runtime()
         :on("core.after_setup", observer)
   )

   test.equal(#compiled.plan.handlers["core.after_setup"], 1)
   test.equal(compiled.plan.handlers["core.after_setup"][1], observer)
end)

test.case("compile validates component config against its schema", function()
   local core = plugin("core")
   local component = runtime.descriptor(core, {
      name = "window",
      config = { width = "bad" },
      config_schema = schema.record({
         width = schema.integer { coerce = true },
      }),
   })

   local ok, err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :add(component)
      )
   end)

   test.falsey(ok)
   test.match(tostring(err), "component 'window' config")
end)

test.case("compile normalizes component config with schema defaults", function()
   local core = plugin("core")
   local component = runtime.descriptor(core, {
      name = "window",
      config = {},
      config_schema = schema.record({
         resizable = schema.boolean():optional(true),
      }),
   })

   local compiled = compile(
      rig.runtime()
         :use(core)
         :add(component)
   )

   test.equal(compiled.plan.components[1].config.resizable, true)
end)

test.case("compile rejects unsupported capability combinations", function()
   local core = plugin("core", {
      capabilities = { graphics = {} },
   })
   local provider = runtime.descriptor(core, {
      name = "gl",
      provides = { "graphics" },
   })
   local consumer = runtime.descriptor(core, {
      name = "app",
      excludes = { "graphics" },
   })

   local ok, err = pcall(function()
      compile(
         rig.runtime()
            :use(core)
            :add(provider)
            :add(consumer)
      )
   end)

   test.falsey(ok)
   test.match(
      tostring(err),
      "component 'app' excludes capability 'graphics' provided by 'gl'"
   )
end)

test.case("compile failure leaves the builder in building state", function()
   local core = plugin("core", {
      capabilities = { bus = {} },
   })
   local consumer = runtime.descriptor(core, {
      name = "consumer",
      requires = { "bus" },
   })

   local builder = rig.runtime()
      :use(core)
      :add(consumer)
      :execute(function() end)

   local ok = pcall(function()
      builder:compile()
   end)
   test.falsey(ok)
   test.equal(builder.state, "building")

   builder:add(runtime.descriptor(core, {
      name = "provider",
      provides = { "bus" },
   }))

   local compiled = builder:compile()
   test.equal(compiled.state, "compiled")
   local bindings = compiled.plan.bindings
   test.equal(compiled.plan.order[1], bindings.provider)
end)

test.case("compile produces a deterministic order", function()
   local core = plugin("core", {
      capabilities = { bus = {} },
   })
   local provider = runtime.descriptor(core, {
      name = "provider",
      provides = { "bus" },
   })
   local first = runtime.descriptor(core, {
      name = "first",
      requires = { "bus" },
   })
   local second = runtime.descriptor(core, {
      name = "second",
      requires = { "bus" },
   })

   local function compile_once()
      return compile(
         rig.runtime()
            :use(core)
            :add(first)
            :add(second)
            :add(provider)
      )
   end

   local a = compile_once()
   local b = compile_once()

   test.equal(#a.plan.order, #b.plan.order)
   for i = 1, #a.plan.order do
      test.equal(a.plan.order[i].name, b.plan.order[i].name)
   end
end)
