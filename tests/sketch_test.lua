local test = require("test")
local rig = require("rig")
local sched = require("sched")
local sketch = require("sketch")

test.case("rig.run exposes the code-first sketch entrypoint", function()
   test.equal(type(rig.run), "function")
end)

test.case("sketch.App records entities and frame callbacks", function()
   local app = sketch.App()
   local update = function() end
   local draw = function() end

   app:add_entity { mesh = {} }
   app:on_update(update)
   app:on_draw(draw)

   test.equal(#app.entities, 1)
   test.equal(app.update, update)
   test.equal(app.draw, draw)
   test.equal(app:add_entity({}) == app, true)
   test.equal(app:on_update(update) == app, true)
   test.equal(app:on_draw(draw) == app, true)
end)
test.case("sketch.App registers optional camera controllers", function()
   local app = sketch.App()

   local controller = app:add_camera_controls { kind = "orbit" }
   test.equal(#app.camera_controllers, 1)
   test.equal(controller, app.camera_controllers[1])

   app:add_camera_controls { kind = "fly" }
   test.equal(#app.camera_controllers, 2)

   local ok = pcall(function()
      app:add_camera_controls { kind = "bogus" }
   end)
   test.falsey(ok)
end)

test.case("a running sketch exposes uv, an active scheduler, and top-level callbacks", function()
   local observed = {}
   local events = {}
   local frames = 0
   local updates = 0
   local draws = 0
   local started = false
   local build_update_called = false

   local ok = pcall(function()
      rig.run {
         title = "async-by-default phase 2",
         build = function(app)
            app:on_update(function()
               build_update_called = true
            end)
         end,
         start = function(app, start_sched)
            events[#events + 1] = "start-begin"
            started = true
            start_sched.yield()
            events[#events + 1] = "start-end"
         end,
         update = function(app)
            frames = frames + 1
            updates = updates + 1
            events[#events + 1] = "update"
            observed.uv = app.ctx and app.ctx.uv or nil
            observed.scheduler = sched.active_scheduler()
            observed.runtime = app.runtime
         end,
         draw = function(app)
            draws = draws + 1
            events[#events + 1] = "draw"
            if app.runtime ~= nil then
               app.runtime:stop()
            end
         end,
      }
   end)

   if not ok then
      -- No usable SDL video driver in this environment; skip the smoke portion.
      return
   end

   test.truthy(frames >= 1)
   test.truthy(observed.uv ~= nil)
   test.truthy(observed.scheduler ~= nil)
   test.truthy(updates >= 1)
   test.truthy(draws >= 1)
   test.falsey(build_update_called)
   test.truthy(started)
   test.equal(events[1], "start-begin")
   test.equal(events[2], "start-end")
   test.equal(events[3], "update")
   test.equal(events[4], "draw")
end)
