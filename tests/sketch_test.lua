local test = require("test")
local rig = require("rig")
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
