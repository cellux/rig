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
test.case("first-person controllers request mouse grab by default", function()
   test.equal(camera.walk {}.mouse_grab, true)
   test.equal(camera.fly {}.mouse_grab, true)
   test.equal(camera.orbit {}.mouse_grab, false)
   test.equal(camera.walk { mouse_grab = false }.mouse_grab, false)
   test.equal(camera.fly { mouse_grab = false }.mouse_grab, false)
end)

test.case("camera.walk moves on the ground plane at fixed eye height", function()
   local walk = camera.walk {
      position = { 0.0, 0.0, 0.0 },
      yaw = 0.0,
      speed = 2.0,
      eye_height = 1.7,
   }

   walk:on_key { action = "down", key = "W" }
   walk:update(0.5)
   walk:on_key { action = "up", key = "W" }

   test.truthy(near(walk.position[1], 0.0))
   test.truthy(near(walk.position[2], 0.0))
   test.truthy(near(walk.position[3], 1.0))
   test.truthy(near(walk:eye()[2], 1.7))

   local surface = scene.RenderScene {}
   walk:apply(surface)
   test.truthy(near(surface.camera.eye[2], 1.7))
   test.truthy(surface.camera.target[3] > surface.camera.eye[3])
end)

test.case("camera.walk smooths movement when a time constant is set", function()
   local walk = camera.walk {
      position = { 0.0, 0.0, 0.0 },
      yaw = 0.0,
      speed = 2.0,
      smoothing = 0.1,
   }

   walk:on_key { action = "down", key = "W" }
   walk:update(0.1)
   local first = walk.position[3]
   test.truthy(first > 0.0)
   test.truthy(first < 2.0 * 0.1)

   walk:update(0.1)
   test.truthy(walk.position[3] > first)

   -- Releasing the key decelerates instead of stopping instantly.
   walk:on_key { action = "up", key = "W" }
   local before = walk.position[3]
   walk:update(0.1)
   test.truthy(walk.position[3] > before)

   test.falsey(pcall(function()
      camera.walk { smoothing = -1.0 }
   end))
end)

test.case("camera.walk looks only while focused and resets its pose", function()
   local walk = camera.walk {
      position = { 1.0, 0.0, 2.0 },
      yaw = 0.5,
      pitch = 0.2,
   }

   walk:on_mouse { action = "move", xrel = 100, yrel = 50 }
   test.truthy(walk.yaw ~= 0.5)

   walk:on_focus { focused = false }
   local yaw, pitch = walk.yaw, walk.pitch
   walk:on_mouse { action = "move", xrel = 100, yrel = 50 }
   test.equal(walk.yaw, yaw)
   test.equal(walk.pitch, pitch)

   walk:on_key { action = "down", key = "W" }
   walk:on_focus { focused = false }
   test.equal(walk.move.forward, false)

   walk:on_focus { focused = true }
   walk:on_key { action = "down", key = "R" }
   test.truthy(near(walk.position[1], 1.0))
   test.truthy(near(walk.position[3], 2.0))
   test.truthy(near(walk.yaw, 0.5))
   test.truthy(near(walk.pitch, 0.2))
end)

test.case("camera.walk uses collision movement and clears held keys on focus loss", function()
   local moves = {}
   local fake_collision = {
      move = function(_, position, dx, dz, options)
         moves[#moves + 1] = { dx = dx, dz = dz, radius = options.radius }
         position[1] = position[1] + dx
         position[3] = position[3] + dz
      end,
   }
   local walk = camera.walk {
      position = { 0.0, 0.0, 0.0 },
      yaw = math.pi * 0.5,
      speed = 4.0,
      radius = 0.35,
      collision = fake_collision,
   }

   walk:on_key { action = "down", key = "W" }
   walk:update(0.5)
   test.equal(#moves, 1)
   test.truthy(near(moves[1].dx, 2.0))
   test.truthy(near(moves[1].dz, 0.0))
   test.equal(moves[1].radius, 0.35)

   walk:on_focus { focused = false }
   test.equal(walk.move.forward, false)
end)

test.case("camera.walk blocks against a collision world", function()
   local collision = require("collision")
   local world = collision.world()
   world:add_box { x = 0.0, z = 2.0, width = 6.0, depth = 0.4 }

   local walk = camera.walk {
      position = { 0.0, 0.0, 0.0 },
      yaw = 0.0,
      speed = 20.0,
      radius = 0.3,
      collision = world,
   }

   walk:on_key { action = "down", key = "W" }
   walk:update(0.5)
   walk:on_key { action = "up", key = "W" }

   -- Wall front face is z = 1.8; the player stops one radius before it.
   test.truthy(near(walk.position[3], 1.5, 1e-3))
end)
