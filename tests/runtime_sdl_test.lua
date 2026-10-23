local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local sdl3x = require("sdl3x")

test.case("window composition orders subsystem, window, and input", function()
   local sdl_plugin = sdl3x.plugin()

   local compiled = rig.runtime()
      :use(sdl_plugin)
      :add(sdl3x.input_component(sdl_plugin, { name = "input" }))
      :add(sdl3x.window_component(sdl_plugin, { name = "window" }))
      :add(sdl3x.subsystem_component(sdl_plugin, { name = "sdl" }))
      :execute(function() end)
      :compile()

   local bindings = compiled.plan.bindings
   test.equal(compiled.plan.order[1], bindings.sdl)
   test.equal(compiled.plan.order[2], bindings.window)
   test.equal(compiled.plan.order[3], bindings.input)
end)

test.case("sdl3x plugin maps events to class methods", function()
   local sdl_plugin = sdl3x.plugin()

   local compiled = rig.runtime()
      :use(sdl_plugin)
      :add(sdl3x.subsystem_component(sdl_plugin, {}))
      :add(sdl3x.window_component(sdl_plugin, {}))
      :add(sdl3x.input_component(sdl_plugin, {}))
      :execute(rig.Class())
      :compile()

   test.equal(compiled.plan.class_methods.on_key, "sdl3.key")
   test.equal(compiled.plan.class_methods.on_mouse, "sdl3.mouse")
   test.equal(compiled.plan.class_methods.on_resize, "sdl3.resize")
   test.equal(compiled.plan.class_methods.on_close, "sdl3.close")
   test.equal(compiled.plan.class_methods.on_focus, "sdl3.focus")
end)

test.case("a window can be composed without graphics", function()
   local sdl_plugin = sdl3x.plugin()

   local compiled = rig.runtime()
      :use(sdl_plugin)
      :add(sdl3x.subsystem_component(sdl_plugin, { name = "sdl" }))
      :add(sdl3x.window_component(sdl_plugin, { name = "window" }))
      :execute(function() end)
      :compile()

   test.equal(compiled.state, "compiled")
   test.truthy(compiled.plan.bindings.sdl ~= nil)
end)

test.case("window and input runtime starts and stops", function()
   local sdl_plugin = sdl3x.plugin()
   local saw_resize = false

   local compiled = rig.runtime()
      :use(sdl_plugin)
      :add(sdl3x.subsystem_component(sdl_plugin, { name = "sdl" }))
      :add(sdl3x.window_component(sdl_plugin, { name = "window" }))
      :add(sdl3x.input_component(sdl_plugin, { name = "input" }))
      :add(runtime.descriptor(sdl_plugin, {
         name = "stop",
         progress = {
            should_stop = function(context)
               return context.step >= 3
            end,
         },
      }))
      :on("sdl3.resize", function()
         saw_resize = true
      end)
      :compile()

   local ok = pcall(function()
      compiled:start()
   end)

   if not ok then
      -- No usable SDL video driver in this environment; skip the smoke portion.
      return
   end

   test.equal(compiled.state, "stopped")
   test.truthy(saw_resize)
end)
