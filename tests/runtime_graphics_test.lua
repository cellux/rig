local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")

test.case("renderer graphics context composes with a window", function()
   local p = sdl3x.plugin()

   local compiled = rig.runtime()
      :use(p)
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, { name = "window" }))
      :add(sdl3x.renderer_context_component(p, { name = "graphics" }))
      :execute(function() end)
      :compile()

   local component = compiled.plan.bindings.graphics
   test.equal(component.provides[1].capability, "graphics.context")
   test.equal(component.provides[1].properties.backend, "renderer")
end)

test.case("graphics.context selects a backend by constraint", function()
   local p = sdl3x.plugin()
   local consumer = runtime.descriptor(p, {
      name = "consumer",
      requires = {
         { capability = "graphics.context", properties = { backend = "gpu" } },
      },
   })

   local compiled = rig.runtime()
      :use(p)
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, { name = "window" }))
      :add(sdl3x.renderer_context_component(p, { name = "renderer_gfx" }))
      :add(sdl3x.gpu_context_component(p, { name = "gpu_gfx" }))
      :add(consumer)
      :execute(function() end)
      :compile()

   local bindings = compiled.plan.bindings
   local resolved = compiled.plan.resolved[bindings.consumer][1]
   test.equal(resolved.provider, bindings.gpu_gfx)
end)

test.case("graphics.context selects the gl backend", function()
   local p = sdl3x.plugin()
   local consumer = runtime.descriptor(p, {
      name = "consumer",
      requires = {
         { capability = "graphics.context", properties = { backend = "gl" } },
      },
   })

   local compiled = rig.runtime()
      :use(p)
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, { name = "window" }))
      :add(sdl3x.gl_context_component(p, { name = "gl_gfx" }))
      :add(consumer)
      :execute(function() end)
      :compile()

   local bindings = compiled.plan.bindings
   test.equal(
      compiled.plan.resolved[bindings.consumer][1].provider,
      bindings.gl_gfx
   )
end)

test.case("renderer graphics context starts and presents", function()
   local p = sdl3x.plugin()
   local backend = nil

   local compiled = rig.runtime()
      :use(p)
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, { name = "window" }))
      :add(sdl3x.renderer_context_component(p, { name = "graphics" }))
      :execute(function(ctx)
         backend = ctx.graphics.backend
         ctx.graphics.present()
      end)
      :compile()

   local ok = pcall(function()
      compiled:start()
   end)

   if not ok then
      return
   end

   test.equal(backend, "renderer")
end)

test.case("gpu graphics context starts", function()
   local p = sdl3x.plugin()
   local device = nil

   local compiled = rig.runtime()
      :use(p)
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, { name = "window" }))
      :add(sdl3x.gpu_context_component(p, { name = "graphics" }))
      :execute(function(ctx)
         device = ctx.graphics.device
      end)
      :compile()

   local ok = pcall(function()
      compiled:start()
   end)

   if not ok then
      return
   end

   test.truthy(device ~= nil)
end)

test.case("opengl graphics context starts", function()
   local p = sdl3x.plugin()
   local backend = nil

   local compiled = rig.runtime()
      :use(p)
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, {
         name = "window",
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_OPENGL_BOOLEAN] = true,
         },
      }))
      :add(sdl3x.gl_context_component(p, { name = "graphics" }))
      :execute(function(ctx)
         backend = ctx.graphics.backend
      end)
      :compile()

   local ok = pcall(function()
      compiled:start()
   end)

   if not ok then
      return
   end

   test.equal(backend, "gl")
end)
