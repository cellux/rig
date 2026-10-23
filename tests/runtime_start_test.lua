local test = require("test")
local runtime = require("runtime")
local rig = require("rig")

local function plugin(id, spec)
   spec = spec or {}
   spec.id = id
   return runtime.plugin(spec)
end

local function stopping_component(core, name, limit)
   return runtime.descriptor(core, {
      name = name,
      create = function()
         return {}
      end,
      progress = {
         should_stop = function(context)
            return context.step >= limit
         end,
      },
   })
end

test.case("compile rejects missing execution configuration", function()
   local core = plugin("core")

   local ok, err = pcall(function()
      rig.runtime()
         :use(core)
         :compile()
   end)

   test.falsey(ok)
   test.match(tostring(err), "missing execution configuration")
end)

test.case("compile rejects mixing handlers with an execution form", function()
   local core = plugin("core", {
      extension_points = {
         ["demo.tick"] = {},
      },
   })

   local ok, err = pcall(function()
      rig.runtime()
         :use(core)
         :on("demo.tick", function() end)
         :execute(function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(tostring(err), "cannot mix builder handlers")
end)

test.case("function execution receives ctx and stops when it returns", function()
   local core = plugin("core")
   local component = runtime.descriptor(core, {
      name = "counter",
      create = function()
         return { id = "counter" }
      end,
   })

   local seen = nil
   local compiled = rig.runtime()
      :use(core)
      :add(component)
      :execute(function(ctx)
         seen = ctx.counter
      end)
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(compiled.execution_form, "function")
   test.truthy(seen ~= nil)
   test.equal(seen.id, "counter")
end)

test.case("component create sees previously initialized bindings", function()
   local core = plugin("core", {
      capabilities = { bus = {} },
   })
   local provider = runtime.descriptor(core, {
      name = "provider",
      provides = { "bus" },
      create = function()
         return { pid = 1 }
      end,
   })

   local observed = nil
   local consumer = runtime.descriptor(core, {
      name = "consumer",
      requires = { "bus" },
      create = function(context)
         observed = {
            provider = context.ctx.provider,
            resolved = context.requires[1],
         }
         return {}
      end,
   })

   local compiled = rig.runtime()
      :use(core)
      :add(consumer)
      :add(provider)
      :execute(function() end)
      :compile()

   compiled:start()

   test.truthy(observed ~= nil)
   test.equal(observed.provider.pid, 1)
   test.equal(observed.resolved.binding, "provider")
   test.equal(observed.resolved.value.pid, 1)
end)

test.case("class execution constructs the instance with ctx", function()
   local core = plugin("core")
   local stop = stopping_component(core, "stop", 0)

   local captured = nil
   local TestClass = rig.Class()
   function TestClass:init(ctx)
      captured = ctx
      self.ctx = ctx
   end

   local compiled = rig.runtime()
      :use(core)
      :add(stop)
      :execute(TestClass)
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(compiled.execution_form, "class")
   test.truthy(compiled.instance ~= nil)
   test.equal(compiled.instance.ctx, captured)
   test.equal(captured.stop, compiled.ctx.stop)
end)

test.case("hook execution is inferred from handlers", function()
   local core = plugin("core", {
      extension_points = {
         ["demo.tick"] = {},
      },
   })
   local stop = stopping_component(core, "stop", 0)

   local compiled = rig.runtime()
      :use(core)
      :add(stop)
      :on("demo.tick", function() end)
      :compile()

   test.equal(compiled.execution_form, "hooks")

   compiled:start()
   test.equal(compiled.state, "stopped")
end)

test.case("progress engine runs poll, drain, and frame each step", function()
   local core = plugin("core")
   local observed = { poll = 0, drain = 0, frame = 0 }
   local component = runtime.descriptor(core, {
      name = "loop",
      create = function()
         return {}
      end,
      progress = {
         poll = function()
            observed.poll = observed.poll + 1
         end,
         drain = function()
            observed.drain = observed.drain + 1
         end,
         frame = function()
            observed.frame = observed.frame + 1
         end,
         should_stop = function(context)
            return context.step >= 3
         end,
      },
   })

   local compiled = rig.runtime()
      :use(core)
      :add(component)
      :execute(rig.Class())
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(observed.poll, 3)
   test.equal(observed.drain, 3)
   test.equal(observed.frame, 3)
end)

test.case("components can request stop through the runtime", function()
   local core = plugin("core")
   local steps = 0
   local component = runtime.descriptor(core, {
      name = "loop",
      create = function()
         return {}
      end,
      progress = {
         poll = function(context)
            steps = steps + 1
            if steps >= 2 then
               context.runtime:stop()
            end
         end,
      },
   })

   local compiled = rig.runtime()
      :use(core)
      :add(component)
      :execute(rig.Class())
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(steps, 2)
end)

test.case("compile validates progress operations", function()
   local core = plugin("core")
   local component = runtime.descriptor(core, {
      name = "bad",
      progress = {
         poll = 42,
      },
   })

   local ok, err = pcall(function()
      rig.runtime()
         :use(core)
         :add(component)
         :execute(function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(tostring(err), "progress%.poll must be a function")
end)

test.case("runtime rejects double start and start after stopped", function()
   local core = plugin("core")
   local compiled = rig.runtime()
      :use(core)
      :execute(function() end)
      :compile()

   compiled:start()
   test.equal(compiled.state, "stopped")

   local ok, err = pcall(function()
      compiled:start()
   end)
   test.falsey(ok)
   test.match(tostring(err), "cannot start in state 'stopped'")
end)

test.case("runtime stop is only valid while running", function()
   local core = plugin("core")
   local compiled = rig.runtime()
      :use(core)
      :execute(function() end)
      :compile()

   local ok, err = pcall(function()
      compiled:stop()
   end)
   test.falsey(ok)
   test.match(tostring(err), "cannot stop in state 'compiled'")
end)

test.case("startup failure transitions the runtime to failed", function()
   local core = plugin("core")
   local component = runtime.descriptor(core, {
      name = "bad",
      create = function()
         rig.raise("create boom")
      end,
   })

   local compiled = rig.runtime()
      :use(core)
      :add(component)
      :execute(function() end)
      :compile()

   local ok, err = pcall(function()
      compiled:start()
   end)

   test.falsey(ok)
   test.match(tostring(err), "create boom")
   test.equal(compiled.state, "failed")
end)

test.case("execution failure transitions the runtime to failed", function()
   local core = plugin("core")
   local compiled = rig.runtime()
      :use(core)
      :execute(function()
         rig.raise("run boom")
      end)
      :compile()

   local ok, err = pcall(function()
      compiled:start()
   end)

   test.falsey(ok)
   test.match(tostring(err), "run boom")
   test.equal(compiled.state, "failed")
end)
