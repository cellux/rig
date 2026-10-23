local test = require("test")
local runtime = require("runtime")
local rig = require("rig")

local function plugin(id, spec)
   spec = spec or {}
   spec.id = id
   return runtime.plugin(spec)
end

test.case("runtime releases resources in reverse acquisition order", function()
   local core = plugin("core")
   local released = {}

   local function make(name)
      return runtime.descriptor(core, {
         name = name,
         create = function()
            return { name = name }
         end,
         release = function(value)
            released[#released + 1] = value.name
         end,
      })
   end

   local compiled = rig.runtime()
      :use(core)
      :add(make("a"))
      :add(make("b"))
      :add(make("c"))
      :execute(function() end)
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(#released, 3)
   test.equal(released[1], "c")
   test.equal(released[2], "b")
   test.equal(released[3], "a")
end)

test.case("startup failure rolls back acquired resources", function()
   local core = plugin("core")
   local released = {}

   local first = runtime.descriptor(core, {
      name = "first",
      create = function()
         return {}
      end,
      release = function()
         released[#released + 1] = "first"
      end,
   })
   local second = runtime.descriptor(core, {
      name = "second",
      create = function()
         rig.raise("second exploded")
      end,
   })

   local compiled = rig.runtime()
      :use(core)
      :add(first)
      :add(second)
      :execute(function() end)
      :compile()

   local ok, err = pcall(function()
      compiled:start()
   end)

   test.falsey(ok)
   test.match(tostring(err), "component 'second' failed during startup")
   test.match(tostring(err), "second exploded")
   test.equal(released[1], "first")
   test.equal(compiled.state, "failed")
end)

test.case("execution failure releases resources", function()
   local core = plugin("core")
   local released = 0

   local component = runtime.descriptor(core, {
      name = "resource",
      create = function()
         return {}
      end,
      release = function()
         released = released + 1
      end,
   })

   local compiled = rig.runtime()
      :use(core)
      :add(component)
      :execute(function()
         rig.raise("run boom")
      end)
      :compile()

   local ok = pcall(function()
      compiled:start()
   end)

   test.falsey(ok)
   test.equal(released, 1)
   test.equal(compiled.state, "failed")
end)

test.case("cleanup errors are aggregated and release continues", function()
   local core = plugin("core")
   local released = {}

   local function make(name, fail)
      return runtime.descriptor(core, {
         name = name,
         create = function()
            return {}
         end,
         release = function()
            released[#released + 1] = name
            if fail then
               rig.raise(name .. " release failed")
            end
         end,
      })
   end

   local compiled = rig.runtime()
      :use(core)
      :add(make("a"))
      :add(make("b", true))
      :add(make("c"))
      :execute(function() end)
      :compile()

   local ok, err = pcall(function()
      compiled:start()
   end)

   test.falsey(ok)
   test.match(tostring(err), "runtime cleanup failed with 1 error")
   test.match(tostring(err), "component 'b'")
   test.match(tostring(err), "b release failed")
   test.equal(#released, 3)
   test.equal(released[1], "c")
   test.equal(released[2], "b")
   test.equal(released[3], "a")
   test.equal(compiled.state, "failed")
end)

test.case("startup and cleanup errors are combined", function()
   local core = plugin("core")

   local first = runtime.descriptor(core, {
      name = "first",
      create = function()
         return {}
      end,
      release = function()
         rig.raise("first release failed")
      end,
   })
   local second = runtime.descriptor(core, {
      name = "second",
      create = function()
         rig.raise("second create failed")
      end,
   })

   local compiled = rig.runtime()
      :use(core)
      :add(first)
      :add(second)
      :execute(function() end)
      :compile()

   local ok, err = pcall(function()
      compiled:start()
   end)

   test.falsey(ok)
   test.match(tostring(err), "second create failed")
   test.match(tostring(err), "runtime cleanup failed")
   test.match(tostring(err), "first release failed")
   test.equal(compiled.state, "failed")
end)

test.case("component create can adopt resources through the context", function()
   local core = plugin("core")
   local released = {}

   local component = runtime.descriptor(core, {
      name = "owner",
      create = function(context)
         context.adopt({ tag = "extra" }, function(resource)
            released[#released + 1] = resource.tag
         end)
         return {}
      end,
   })

   local compiled = rig.runtime()
      :use(core)
      :add(component)
      :execute(function() end)
      :compile()

   compiled:start()

   test.equal(released[1], "extra")
   test.equal(compiled.state, "stopped")
end)

test.case("compile validates create and release types", function()
   local core = plugin("core")

   local create_ok, create_err = pcall(function()
      rig.runtime()
         :use(core)
         :add(runtime.descriptor(core, {
            name = "bad",
            create = 5,
         }))
         :execute(function() end)
         :compile()
   end)
   test.falsey(create_ok)
   test.match(tostring(create_err), "component 'bad' create must be a function")

   local release_ok, release_err = pcall(function()
      rig.runtime()
         :use(core)
         :add(runtime.descriptor(core, {
            name = "bad",
            release = 5,
         }))
         :execute(function() end)
         :compile()
   end)
   test.falsey(release_ok)
   test.match(tostring(release_err), "component 'bad' release must be a function")
end)

test.case("resource scope release is idempotent", function()
   local scope = runtime.ResourceScope("test scope")
   local count = 0

   scope:adopt(nil, {}, function()
      count = count + 1
   end)

   test.equal(#scope:release(), 0)
   test.equal(#scope:release(), 0)
   test.equal(count, 1)
end)
