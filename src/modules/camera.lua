local M = ... or {}

local rig = require("rig")

-- Optional camera controllers. They are plain, backend-agnostic values: feed
-- them input events and `dt`, then `apply(scene)` to drive the scene camera.
-- Nothing enables them automatically; a sketch opts in with
-- `app:add_camera_controls { kind = "orbit" | "fly", ... }` (or by using the
-- controllers directly next to a hand-built `sdl3x.App`).

local HALF_PI = math.pi * 0.5
local PITCH_LIMIT = HALF_PI - 0.01

local function clamp(value, low, high)
   if value < low then
      return low
   end
   if value > high then
      return high
   end
   return value
end

local function apply_camera(scene, eye, target)
   local current = scene.camera or {}
   scene:set_camera {
      eye = eye,
      target = target,
      up = { 0.0, 1.0, 0.0 },
      fov_degrees = current.fov_degrees or 60.0,
      near = current.near or 0.1,
      far = current.far or 100.0,
   }
end

-- Orbits a target: drag with the primary button to rotate, zoom keys to dolly.
local Orbit = rig.Class()
M.Orbit = Orbit

function Orbit:init(options)
   options = options or {}
   self.target = options.target or { 0.0, 0.0, 0.0 }
   self.distance = options.distance or 4.5
   self.yaw = options.yaw or math.pi
   self.pitch = options.pitch or 0.0
   self.sensitivity = options.sensitivity or 0.005
   self.zoom_speed = options.zoom_speed or 1.5
   self.min_distance = options.min_distance or 0.25
   self.max_distance = options.max_distance or 500.0
   self.drag_button = options.drag_button or 1
   self.zoom_in_key = options.zoom_in_key or "E"
   self.zoom_out_key = options.zoom_out_key or "Q"
   self.dragging = false
   self.zoom_in = false
   self.zoom_out = false
end

function Orbit:on_mouse(info)
   local button = info.button or 0
   if info.action == "down" then
      if button == self.drag_button then
         self.dragging = true
      end
   elseif info.action == "up" then
      if button == self.drag_button then
         self.dragging = false
      end
   elseif info.action == "move" and self.dragging then
      self.yaw = self.yaw - (info.xrel or 0) * self.sensitivity
      self.pitch = clamp(
         self.pitch + (info.yrel or 0) * self.sensitivity,
         -PITCH_LIMIT,
         PITCH_LIMIT
      )
   end
end

function Orbit:on_key(info)
   local key = info.key and string.upper(info.key)
   local down = info.action == "down"
   if key == self.zoom_in_key then
      self.zoom_in = down
   elseif key == self.zoom_out_key then
      self.zoom_out = down
   end
end

function Orbit:update(dt)
   local direction = 0
   if self.zoom_in then
      direction = direction - 1
   end
   if self.zoom_out then
      direction = direction + 1
   end
   if direction ~= 0 then
      self.distance = clamp(
         self.distance * (1.0 + direction * self.zoom_speed * (dt or 0.0)),
         self.min_distance,
         self.max_distance
      )
   end
end

function Orbit:eye()
   local cos_pitch = math.cos(self.pitch)
   return {
      self.target[1] + self.distance * cos_pitch * math.sin(self.yaw),
      self.target[2] + self.distance * math.sin(self.pitch),
      self.target[3] + self.distance * cos_pitch * math.cos(self.yaw),
   }
end

function Orbit:apply(scene)
   apply_camera(scene, self:eye(), self.target)
end

-- A fly camera: WASD to move, Q/E down/up, hold the secondary button to look.
local Fly = rig.Class()
M.Fly = Fly

function Fly:init(options)
   options = options or {}
   self.position = options.position or { 0.0, 0.0, -4.5 }
   self.yaw = options.yaw or 0.0
   self.pitch = options.pitch or 0.0
   self.speed = options.speed or 4.0
   self.sensitivity = options.sensitivity or 0.003
   self.look_button = options.look_button or 3
   self.keys = options.keys or {
      forward = { "W" },
      back = { "S" },
      left = { "A" },
      right = { "D" },
      up = { "E" },
      down = { "Q" },
   }
   self.looking = false
   self.move = {
      forward = false,
      back = false,
      left = false,
      right = false,
      up = false,
      down = false,
   }
end

function Fly:on_mouse(info)
   local button = info.button or 0
   if info.action == "down" then
      if button == self.look_button then
         self.looking = true
      end
   elseif info.action == "up" then
      if button == self.look_button then
         self.looking = false
      end
   elseif info.action == "move" and self.looking then
      self.yaw = self.yaw + (info.xrel or 0) * self.sensitivity
      self.pitch = clamp(
         self.pitch - (info.yrel or 0) * self.sensitivity,
         -PITCH_LIMIT,
         PITCH_LIMIT
      )
   end
end

function Fly:on_key(info)
   local key = info.key and string.upper(info.key)
   if key == nil then
      return
   end

   local down = info.action == "down"
   for action, keys in pairs(self.keys) do
      for i = 1, #keys do
         if keys[i] == key then
            self.move[action] = down
            return
         end
      end
   end
end

function Fly:forward()
   local cos_pitch = math.cos(self.pitch)
   return {
      math.sin(self.yaw) * cos_pitch,
      math.sin(self.pitch),
      math.cos(self.yaw) * cos_pitch,
   }
end

function Fly:right()
   local forward = self:forward()
   return { forward[3], 0.0, -forward[1] }
end

function Fly:update(dt)
   local forward = self:forward()
   local right = self:right()
   local dx, dy, dz = 0.0, 0.0, 0.0

   local function add(vector, scale)
      dx = dx + vector[1] * scale
      dy = dy + vector[2] * scale
      dz = dz + vector[3] * scale
   end

   if self.move.forward then
      add(forward, 1.0)
   end
   if self.move.back then
      add(forward, -1.0)
   end
   if self.move.right then
      add(right, 1.0)
   end
   if self.move.left then
      add(right, -1.0)
   end
   if self.move.up then
      dy = dy + 1.0
   end
   if self.move.down then
      dy = dy - 1.0
   end

   local length = math.sqrt(dx * dx + dy * dy + dz * dz)
   if length > 0.0 then
      local scale = self.speed * (dt or 0.0) / length
      self.position[1] = self.position[1] + dx * scale
      self.position[2] = self.position[2] + dy * scale
      self.position[3] = self.position[3] + dz * scale
   end
end

function Fly:apply(scene)
   local forward = self:forward()
   apply_camera(scene, self.position, {
      self.position[1] + forward[1],
      self.position[2] + forward[2],
      self.position[3] + forward[3],
   })
end

function M.orbit(options)
   return Orbit(options)
end

function M.fly(options)
   return Fly(options)
end

return M