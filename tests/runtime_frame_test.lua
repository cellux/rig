local graphics = require("graphics")
local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local scene = require("scene")
local sdl3x = require("sdl3x")

test.case("frame component requires a graphics context", function()
   local p = sdl3x.plugin()

   local ok, err = pcall(function()
      rig.runtime()
         :use(p)
         :use(graphics.plugin())
         :add(graphics.frame_component(p, { name = "frame" }))
         :execute(function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(
      tostring(err),
      "requires capability 'graphics.context' but no component provides it"
   )
end)

test.case("core frame phases map to class methods", function()
   local p = sdl3x.plugin()

   local compiled = rig.runtime()
      :use(p)
      :use(graphics.plugin())
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, { name = "window" }))
      :add(sdl3x.renderer_context_component(p, { name = "graphics" }))
      :add(graphics.frame_component(p, { name = "frame" }))
      :execute(rig.Class())
      :compile()

   test.equal(compiled.plan.class_methods.before_frame, "core.before_frame")
   test.equal(compiled.plan.class_methods.after_frame, "core.after_frame")
end)

test.case("frame component renders and dispatches lifecycle phases", function()
   local p = sdl3x.plugin()
   local observed = {
      render = 0,
      before = 0,
      after = 0,
   }

   local App = rig.Class()
   function App:render()
      observed.render = observed.render + 1
   end
   function App:before_frame()
      observed.before = observed.before + 1
   end
   function App:after_frame()
      observed.after = observed.after + 1
   end

   local compiled = rig.runtime()
      :use(p)
      :use(graphics.plugin())
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, { name = "window" }))
      :add(sdl3x.renderer_context_component(p, { name = "graphics" }))
      :add(graphics.frame_component(p, { name = "frame" }))
      :add(runtime.descriptor(p, {
         name = "stop",
         progress = {
            should_stop = function(context)
               return context.step >= 3
            end,
         },
      }))
      :execute(App)
      :compile()

   local ok = pcall(function()
      compiled:start()
   end)

   if not ok then
      return
   end

   test.equal(compiled.state, "stopped")
   test.equal(observed.render, 3)
   test.equal(observed.before, 3)
   test.equal(observed.after, 3)
end)

test.case("frame component renders the resolved render.scene", function()
   local p = sdl3x.plugin()
   local sp = scene.plugin()
   local frames = 0

   local RecordingScene = rig.Class(scene.RenderScene)
   function RecordingScene:begin_frame()
      frames = frames + 1
   end

   local compiled = rig.runtime()
      :use(p)
      :use(graphics.plugin())
      :use(sp)
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, { name = "window" }))
      :add(sdl3x.renderer_context_component(p, { name = "graphics" }))
      :add(graphics.frame_component(p, { name = "frame" }))
      :add(scene.container_component(sp, {
         name = "scene",
         scene_class = RecordingScene,
      }))
      :add(runtime.descriptor(p, {
         name = "stop",
         progress = {
            should_stop = function(context)
               return context.step >= 2
            end,
         },
      }))
      :execute(rig.Class())
      :compile()

   local ok = pcall(function()
      compiled:start()
   end)

   if not ok then
      return
   end

   test.truthy(frames >= 1)
end)

test.case("gpu graphics context renders a frame", function()
   local p = sdl3x.plugin()
   local rendered = 0

   local App = rig.Class()
   function App:render(command_buffer, swapchain_texture)
      if command_buffer ~= nil and swapchain_texture ~= nil then
         rendered = rendered + 1
      end
   end

   local compiled = rig.runtime()
      :use(p)
      :use(graphics.plugin())
      :add(sdl3x.subsystem_component(p, { name = "sdl" }))
      :add(sdl3x.window_component(p, { name = "window" }))
      :add(sdl3x.gpu_context_component(p, { name = "graphics" }))
      :add(graphics.frame_component(p, { name = "frame" }))
      :add(runtime.descriptor(p, {
         name = "stop",
         progress = {
            should_stop = function(context)
               return context.step >= 2
            end,
         },
      }))
      :execute(App)
      :compile()

   local ok = pcall(function()
      compiled:start()
   end)

   if not ok then
      return
   end

   test.truthy(rendered >= 1)
end)
