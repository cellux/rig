local test = require("test")
local camera = require("camera")
local scene = require("scene")

local function near(a, b, eps)
   return math.abs(a - b) <= (eps or 1e-6)
end

test.case("camera.orbit places the eye from yaw/pitch/distance", function()
   local orbit = camera.orbit { distance = 4.5, yaw = math.pi }
   local eye = orbit:eye()

   test.truthy(near(eye[1], 0.0))
   test.truthy(near(eye[2], 0.0))
   test.truthy(near(eye[3], -4.5))
end)

test.case("camera.orbit drags to rotate and applies to the scene", function()
   local orbit = camera.orbit { distance = 4.5, yaw = math.pi }

   orbit:on_mouse { action = "move", xrel = 100, yrel = 0 }
   test.equal(orbit.yaw, math.pi)

   orbit:on_mouse { action = "down", button = 1 }
   orbit:on_mouse { action = "move", xrel = 100, yrel = 0 }

   test.truthy(orbit.yaw ~= math.pi)

   local surface = scene.RenderScene {
      camera = {
         eye = { 0.0, 0.0, -4.5 },
         target = { 0.0, 0.0, 0.0 },
         fov_degrees = 60.0,
         near = 0.1,
         far = 100.0,
      },
   }
   orbit:apply(surface)

   test.truthy(surface.camera.eye[1] ~= 0.0)
   test.equal(surface.camera.fov_degrees, 60.0)
end)

test.case("camera.orbit zooms while its key is held", function()
   local orbit = camera.orbit { distance = 4.5, zoom_speed = 1.0 }

   orbit:on_key { action = "down", key = "E" }
   orbit:update(1.0)
   test.truthy(orbit.distance < 4.5)

   local held = orbit.distance
   orbit:on_key { action = "up", key = "E" }
   orbit:update(1.0)
   test.equal(orbit.distance, held)
end)

test.case("camera.fly moves along its facing while keys are held", function()
   local fly = camera.fly { position = { 0.0, 0.0, -4.5 }, yaw = 0.0, speed = 2.0 }

   fly:on_key { action = "down", key = "W" }
   fly:update(0.5)

   test.truthy(near(fly.position[1], 0.0))
   test.truthy(near(fly.position[2], 0.0))
   test.truthy(near(fly.position[3], -3.5))

   fly:on_key { action = "up", key = "W" }
   local z = fly.position[3]
   fly:update(1.0)
   test.equal(fly.position[3], z)
end)

test.case("camera.fly looks only while the secondary button is held", function()
   local fly = camera.fly { yaw = 0.0 }

   fly:on_mouse { action = "move", xrel = 100 }
   test.equal(fly.yaw, 0.0)

   fly:on_mouse { action = "down", button = 3 }
   fly:on_mouse { action = "move", xrel = 100 }
   test.truthy(fly.yaw ~= 0.0)
end)

test.case("camera.fly apply targets ahead of the eye", function()
   local fly = camera.fly { position = { 0.0, 0.0, 0.0 }, yaw = 0.0 }
   local surface = scene.RenderScene {}

   fly:apply(surface)

   test.truthy(surface.camera.target[3] > 0.0)
end)