local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local schema = require("schema")

local function plugin(id, spec)
   spec = spec or {}
   spec.id = id
   return runtime.plugin(spec)
end

local function stopping_component(core, limit)
   return runtime.descriptor(core, {
      name = "stop",
      progress = {
         should_stop = function(context)
            return context.step >= limit
         end,
      },
   })
end

test.case("hook handlers are dispatched for core phases", function()
   local core = plugin("core")
   local observed = {}

   local compiled = rig.runtime()
      :use(core)
      :add(stopping_component(core, 1))
      :on("core.before_setup", function(payload)
         observed[#observed + 1] = "before_setup"
         test.truthy(payload.runtime ~= nil)
      end)
      :on("core.after_setup", function()
         observed[#observed + 1] = "after_setup"
      end)
      :on("core.before_shutdown", function()
         observed[#observed + 1] = "before_shutdown"
      end)
      :on("core.after_shutdown", function()
         observed[#observed + 1] = "after_shutdown"
      end)
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(observed[1], "before_setup")
   test.equal(observed[2], "after_setup")
   test.equal(observed[3], "before_shutdown")
   test.equal(observed[4], "after_shutdown")
end)

test.case("class execution dispatches lifecycle methods", function()
   local core = plugin("core")
   local observed = {}

   local App = rig.Class()
   function App:init(ctx)
      self.ctx = ctx
   end
   function App:after_setup(payload)
      observed[#observed + 1] = "after_setup"
      test.truthy(payload.runtime ~= nil)
   end
   function App:before_shutdown()
      observed[#observed + 1] = "before_shutdown"
   end

   local compiled = rig.runtime()
      :use(core)
      :add(stopping_component(core, 1))
      :execute(App)
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(observed[1], "after_setup")
   test.equal(observed[2], "before_shutdown")
end)

test.case("class execution dispatches plugin events by method", function()
   local core = plugin("core", {
      extension_points = {
         ["demo.tick"] = { method = "on_tick" },
      },
   })
   local observed = {}

   local source = runtime.descriptor(core, {
      name = "source",
      event_source = {
         events = { "demo.tick" },
         poll = function(context)
            context.emit("demo.tick", { value = 7 })
         end,
      },
      progress = {
         should_stop = function(context)
            return context.step >= 2
         end,
      },
   })

   local App = rig.Class()
   function App:on_tick(payload)
      observed[#observed + 1] = payload.value
   end

   local compiled = rig.runtime()
      :use(core)
      :add(source)
      :execute(App)
      :compile()

   compiled:start()

   test.equal(observed[1], 7)
   test.equal(observed[2], 7)
end)

test.case("event sources emit events into handler dispatch", function()
   local core = plugin("core", {
      extension_points = {
         ["demo.ping"] = {},
      },
   })
   local observed = {}

   local source = runtime.descriptor(core, {
      name = "source",
      event_source = {
         events = { "demo.ping" },
         poll = function(context)
            context.emit("demo.ping", { n = context.step })
         end,
      },
      progress = {
         should_stop = function(context)
            return context.step >= 2
         end,
      },
   })

   local compiled = rig.runtime()
      :use(core)
      :add(source)
      :on("demo.ping", function(payload)
         observed[#observed + 1] = payload.n
      end)
      :compile()

   compiled:start()

   test.equal(observed[1], 1)
   test.equal(observed[2], 2)
end)

test.case("extension points honor reverse ordering", function()
   local core = plugin("core", {
      extension_points = {
         ["demo.many"] = { order = "reverse" },
      },
   })
   local observed = {}

   local compiled = rig.runtime()
      :use(core)
      :add(stopping_component(core, 0))
      :on("demo.many", function()
         observed[#observed + 1] = 1
      end)
      :on("demo.many", function()
         observed[#observed + 1] = 2
      end)
      :compile()

   compiled:emit("demo.many")

   test.equal(observed[1], 2)
   test.equal(observed[2], 1)
end)

test.case("emit validates extension point payloads", function()
   local core = plugin("core", {
      extension_points = {
         ["demo.count"] = {
            payload = schema.record({
               count = schema.integer { coerce = true },
            }),
         },
      },
   })

   local compiled = rig.runtime()
      :use(core)
      :add(stopping_component(core, 0))
      :on("demo.count", function() end)
      :compile()

   local ok, err = pcall(function()
      compiled:emit("demo.count", { count = "bad" })
   end)

   test.falsey(ok)
   test.match(tostring(err), "extension point 'demo.count' payload")
end)

test.case("emit rejects unknown extension points", function()
   local core = plugin("core")
   local compiled = rig.runtime()
      :use(core)
      :add(stopping_component(core, 0))
      :on("core.after_setup", function() end)
      :compile()

   local ok, err = pcall(function()
      compiled:emit("demo.missing")
   end)

   test.falsey(ok)
   test.match(tostring(err), "unknown extension point 'demo.missing'")
end)

test.case("compile rejects duplicate class method mappings", function()
   local core = plugin("core", {
      extension_points = {
         ["demo.a"] = { method = "on_event" },
         ["demo.b"] = { method = "on_event" },
      },
   })

   local ok, err = pcall(function()
      rig.runtime()
         :use(core)
         :add(stopping_component(core, 0))
         :on("demo.a", function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(tostring(err), "both map to class method 'on_event'")
end)

test.case("compile rejects reserved class method mappings", function()
   local core = plugin("core", {
      extension_points = {
         ["demo.init"] = { method = "init" },
      },
   })

   local ok, err = pcall(function()
      rig.runtime()
         :use(core)
         :add(stopping_component(core, 0))
         :on("demo.init", function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(tostring(err), "reserved class method 'init'")
end)

test.case("compile validates event source declarations", function()
   local core = plugin("core")
   local source = runtime.descriptor(core, {
      name = "source",
      event_source = {
         events = { "demo.missing" },
      },
   })

   local ok, err = pcall(function()
      rig.runtime()
         :use(core)
         :add(source)
         :execute(function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(tostring(err), "declares unknown event 'demo.missing'")
end)

test.case("compile rejects invalid extension point order and payload", function()
   local ok, err = pcall(function()
      runtime.plugin {
         id = "bad",
         extension_points = {
            ["demo.order"] = { order = "sideways" },
         },
      }
   end)
   test.falsey(ok)
   test.match(tostring(err), "order must be 'registration' or 'reverse'")

   local ok2, err2 = pcall(function()
      runtime.plugin {
         id = "bad2",
         extension_points = {
            ["demo.payload"] = { payload = {} },
         },
      }
   end)
   test.falsey(ok2)
   test.match(tostring(err2), "payload must be a schema object")
end)
