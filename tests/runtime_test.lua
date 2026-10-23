local test = require("test")
local runtime = require("runtime")
local rig = require("rig")

local function new_plugin(id)
   return runtime.plugin {
      id = id,
   }
end

test.case("rig.runtime returns a fresh mutable builder", function()
   local first = rig.runtime()
   local second = rig.runtime()

   test.truthy(runtime.Builder:is_instance(first))
   test.truthy(runtime.Builder:is_instance(second))
   test.falsey(first == second)
   test.equal(first.state, "building")
   test.equal(second.state, "building")
end)

test.case("runtime.plugin validates plugin shape eagerly", function()
   local plugin = runtime.plugin {
      id = "demo",
      components = {},
      capabilities = {},
   }
   test.equal(plugin.id, "demo")

   local missing_id_ok, missing_id_err = pcall(function()
      runtime.plugin {}
   end)
   test.falsey(missing_id_ok)
   test.match(tostring(missing_id_err), "requires a non%-empty string id")

   local bad_field_ok, bad_field_err = pcall(function()
      runtime.plugin {
         id = "demo",
         components = 1,
      }
   end)
   test.falsey(bad_field_ok)
   test.match(tostring(bad_field_err), "field 'components' must be a table")
end)

test.case("runtime.descriptor tags the originating plugin", function()
   local plugin = new_plugin("demo")
   local descriptor = runtime.descriptor(plugin, {
      name = "window",
      kind = "window",
   })

   test.equal(descriptor.plugin, plugin)
   test.equal(descriptor.name, "window")
   test.equal(descriptor.kind, "window")

   local bad_name_ok, bad_name_err = pcall(function()
      runtime.descriptor(plugin, {
         name = "",
      })
   end)
   test.falsey(bad_name_ok)
   test.match(tostring(bad_name_err), "spec%.name expects a non%-empty string")
end)

test.case("runtime builder attaches plugins and rejects duplicates", function()
   local builder = rig.runtime()
   local plugin = new_plugin("demo")

   test.equal(builder:use(plugin), builder)

   local duplicate_ok, duplicate_err = pcall(function()
      builder:use(plugin)
   end)
   test.falsey(duplicate_ok)
   test.match(tostring(duplicate_err), "already attached plugin 'demo'")

   local duplicate_id_ok, duplicate_id_err = pcall(function()
      builder:use(new_plugin("demo"))
   end)
   test.falsey(duplicate_id_ok)
   test.match(tostring(duplicate_id_err), "already attached a plugin with id 'demo'")
end)

test.case("runtime builder validates plugin shape on use", function()
   local not_a_plugin_ok, not_a_plugin_err = pcall(function()
      rig.runtime():use("demo")
   end)
   test.falsey(not_a_plugin_ok)
   test.match(tostring(not_a_plugin_err), "plugin must be a table")

   local missing_id_ok, missing_id_err = pcall(function()
      rig.runtime():use {}
   end)
   test.falsey(missing_id_ok)
   test.match(tostring(missing_id_err), "requires a non%-empty string id")
end)

test.case("runtime builder adds descriptors only from attached plugins", function()
   local builder = rig.runtime()
   local plugin = new_plugin("demo")
   local other = new_plugin("other")
   local descriptor = runtime.descriptor(plugin, {
      name = "window",
   })

   local unattached_ok, unattached_err = pcall(function()
      builder:add(descriptor)
   end)
   test.falsey(unattached_ok)
   test.match(tostring(unattached_err), "plugin 'demo' that is not attached")

   builder:use(plugin)
   test.equal(builder:add(descriptor), builder)

   local no_plugin_ok, no_plugin_err = pcall(function()
      builder:add {}
   end)
   test.falsey(no_plugin_ok)
   test.match(tostring(no_plugin_err), "created by an attached plugin")

   local unknown_ok, unknown_err = pcall(function()
      builder:add(runtime.descriptor(other, {
         name = "panel",
      }))
   end)
   test.falsey(unknown_ok)
   test.match(tostring(unknown_err), "plugin 'other' that is not attached")

   local not_a_table_ok, not_a_table_err = pcall(function()
      builder:add("window")
   end)
   test.falsey(not_a_table_ok)
   test.match(tostring(not_a_table_err), "expects a component descriptor table")

   local bad_name_ok, bad_name_err = pcall(function()
      builder:add {
         plugin = plugin,
         name = "",
      }
   end)
   test.falsey(bad_name_ok)
   test.match(tostring(bad_name_err), "descriptor%.name expects a non%-empty string")
end)

test.case("runtime builder records handlers and validates them", function()
   local builder = rig.runtime()

   test.equal(builder:on("core.after_setup", function() end), builder)

   local bad_name_ok, bad_name_err = pcall(function()
      builder:on("", function() end)
   end)
   test.falsey(bad_name_ok)
   test.match(tostring(bad_name_err), "non%-empty string name")

   local bad_handler_ok, bad_handler_err = pcall(function()
      builder:on("core.after_setup", nil)
   end)
   test.falsey(bad_handler_ok)
   test.match(tostring(bad_handler_err), "expects a handler function")
end)

test.case("runtime builder records a single execution form", function()
   local builder = rig.runtime()

   test.equal(builder:execute(function() end), builder)

   local duplicate_ok, duplicate_err = pcall(function()
      builder:execute(function() end)
   end)
   test.falsey(duplicate_ok)
   test.match(tostring(duplicate_err), "already has an execution form")

   local bad_ok, bad_err = pcall(function()
      rig.runtime():execute(42)
   end)
   test.falsey(bad_ok)
   test.match(tostring(bad_err), "expects a function or class")

   local class_ok = pcall(function()
      rig.runtime():execute(rig.Class())
   end)
   test.truthy(class_ok)
end)

test.case("runtime builder compiles into a compiled runtime", function()
   local builder = rig.runtime()
   local plugin = new_plugin("demo")
   local descriptor = runtime.descriptor(plugin, {
      name = "window",
   })
   local execution = function() end

   builder:use(plugin)
      :add(descriptor)
      :execute(execution)

   local compiled = builder:compile()

   test.truthy(runtime.Compiled:is_instance(compiled))
   test.equal(compiled.state, "compiled")
   test.equal(#compiled.plugins, 1)
   test.equal(compiled.plugins[1], plugin)
   test.equal(#compiled.descriptors, 1)
   test.equal(compiled.descriptors[1], descriptor)
   test.equal(#compiled.handlers, 0)
   test.equal(compiled.execution, execution)
   test.equal(compiled.execution_form, "function")
   test.equal(builder.state, "compiled")

   test.truthy(compiled.plan ~= nil)
   test.equal(#compiled.plan.components, 1)
   test.equal(compiled.plan.components[1].name, "window")
   test.equal(compiled.plan.bindings.window, compiled.plan.components[1])
   test.equal(compiled.plan.execution.form, "function")
end)

test.case("runtime builder stores an independent plugin snapshot", function()
   local builder = rig.runtime()
   local plugin = new_plugin("demo")
   builder:use(plugin)
   builder:execute(function() end)

   local compiled = builder:compile()
   table.insert(compiled.plugins, new_plugin("later"))

   test.equal(#compiled.plugins, 2)
end)

test.case("runtime builder rejects mutation after compile", function()
   local builder = rig.runtime()
   local plugin = new_plugin("demo")
   builder:use(plugin)
   builder:execute(function() end)
   builder:compile()

   local use_ok, use_err = pcall(function()
      builder:use(new_plugin("again"))
   end)
   test.falsey(use_ok)
   test.match(tostring(use_err), "cannot attach a plugin")

   local add_ok, add_err = pcall(function()
      builder:add(runtime.descriptor(plugin, {
         name = "panel",
      }))
   end)
   test.falsey(add_ok)
   test.match(tostring(add_err), "cannot add a component")

   local on_ok, on_err = pcall(function()
      builder:on("demo.tick", function() end)
   end)
   test.falsey(on_ok)
   test.match(tostring(on_err), "cannot register a handler")

   local execute_ok, execute_err = pcall(function()
      builder:execute(function() end)
   end)
   test.falsey(execute_ok)
   test.match(tostring(execute_err), "cannot select an execution form")

   local compile_ok, compile_err = pcall(function()
      builder:compile()
   end)
   test.falsey(compile_ok)
   test.match(tostring(compile_err), "cannot compile")
end)

test.case("runtime builder compile performs no plugin work", function()
   local calls = 0
   local plugin = runtime.plugin {
      id = "counter",
   }
   setmetatable(plugin, {
      __index = function(_, key)
         if key == "components" then
            calls = calls + 1
            return {}
         end
         return nil
      end,
   })

   local builder = rig.runtime()
   builder:use(plugin)
   builder:execute(function() end)
   local before_compile = calls
   builder:compile()

   test.equal(calls, before_compile)
end)
