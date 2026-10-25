local M = ... or {}

local rig = require("rig")

-- Optional camera controllers. They are plain, backend-agnostic values: feed
-- them input events and `dt`, then `apply(scene)` to drive the scene camera.
-- Nothing enables them automatically; a sketch opts in with
-- `app:add_camera_controls { kind = "orbit" | "fly" | "walk", ... }` (or by using
-- the controllers directly next to a hand-built `sdl3x.App`).

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
   self.mouse_grab = options.mouse_grab == true
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

function Orbit:on_focus(info)
   if info == nil or info.focused == false then
      self.dragging = false
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
   self.mouse_grab = options.mouse_grab ~= false
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

function Fly:on_focus(info)
   if info == nil or info.focused == false then
      self.looking = false
      for action in pairs(self.move) do
         self.move[action] = false
      end
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

-- A ground-constrained first-person walk controller. Mouse look is active while
-- the window has focus (or while `look_button` is held when configured); WASD
-- moves on the XZ plane at a fixed eye height. When a collision world is
-- supplied, movement goes through its swept circle resolution.
local Walk = rig.Class()
M.Walk = Walk

local function copy_position(position)
   return {
      position[1] or 0.0,
      position[2] or 0.0,
      position[3] or 0.0,
   }
end

function Walk:init(options)
   options = options or {}
   local default_position = { 0.0, 0.0, -4.5 }
   local initial = copy_position(options.position or options.spawn or default_position)
   local spawn = copy_position(options.spawn or initial)

   self.position = initial
   self.spawn_position = spawn
   self.floor_y = tonumber(options.floor_y) or initial[2] or 0.0
   self.position[2] = self.floor_y
   self.eye_height = tonumber(options.eye_height) or 1.65
   self.speed = tonumber(options.speed) or 2.4
   self.sensitivity = tonumber(options.sensitivity) or 0.0025
   -- Optional ground-plane movement smoothing: a time constant in seconds.
   -- Zero keeps the original instant response.
   self.smoothing = tonumber(options.smoothing) or 0.0
   self.velocity = { 0.0, 0.0 }
   self.yaw = tonumber(options.yaw) or 0.0
   self.pitch = tonumber(options.pitch) or 0.0
   self.spawn_yaw = tonumber(options.spawn_yaw) or self.yaw
   self.spawn_pitch = tonumber(options.spawn_pitch) or self.pitch
   self.look_button = options.look_button
   self.mouse_grab = options.mouse_grab ~= false
   self.focused = options.focused ~= false
   self.looking = false
   self.collision = options.collision or options.world
   self.radius = tonumber(options.radius) or 0.3
   self.reset_key = options.reset_key or "R"
   self.keys = options.keys or {
      forward = { "W" },
      back = { "S" },
      left = { "A" },
      right = { "D" },
   }
   self.move = {
      forward = false,
      back = false,
      left = false,
      right = false,
   }

   if self.eye_height < 0.0 then
      rig.raise("camera.walk eye_height must not be negative")
   end
   if self.speed < 0.0 then
      rig.raise("camera.walk speed must not be negative")
   end
   if self.radius < 0.0 then
      rig.raise("camera.walk radius must not be negative")
   end
   if self.smoothing < 0.0 then
      rig.raise("camera.walk smoothing must not be negative")
   end
end

function Walk:clear_move()
   for action in pairs(self.move) do
      self.move[action] = false
   end
end

function Walk:on_focus(info)
   if info == nil or info.focused == false then
      self.focused = false
      self.looking = false
      self:clear_move()
   else
      self.focused = true
   end
end

function Walk:on_mouse(info)
   local button = info.button or 0
   if info.action == "down" then
      if self.look_button ~= nil and button == self.look_button then
         self.looking = true
      end
   elseif info.action == "up" then
      if self.look_button ~= nil and button == self.look_button then
         self.looking = false
      end
   elseif info.action == "move"
      and self.focused
      and (self.look_button == nil or self.looking) then
      self.yaw = self.yaw + (info.xrel or 0) * self.sensitivity
      self.pitch = clamp(
         self.pitch - (info.yrel or 0) * self.sensitivity,
         -PITCH_LIMIT,
         PITCH_LIMIT
      )
   end
end

function Walk:on_key(info)
   local key = info.key and string.upper(info.key)
   if key == nil then
      return
   end

   local down = info.action == "down"
   if key == self.reset_key then
      if down and not info["repeat"] then
         self:reset()
      end
      return
   end

   for action, keys in pairs(self.keys) do
      for i = 1, #keys do
         if keys[i] == key then
            self.move[action] = down
            return
         end
      end
   end
end

function Walk:forward()
   local cos_pitch = math.cos(self.pitch)
   return {
      math.sin(self.yaw) * cos_pitch,
      math.sin(self.pitch),
      math.cos(self.yaw) * cos_pitch,
   }
end

function Walk:eye()
   return {
      self.position[1],
      self.position[2] + self.eye_height,
      self.position[3],
   }
end

function Walk:reset()
   self.position[1] = self.spawn_position[1]
   self.position[2] = self.spawn_position[2]
   self.position[3] = self.spawn_position[3]
   self.floor_y = self.spawn_position[2]
   self.yaw = self.spawn_yaw
   self.pitch = self.spawn_pitch
   self.velocity[1] = 0.0
   self.velocity[2] = 0.0
   self:clear_move()
   self.looking = false
   return self
end

function Walk:set_collision(collision)
   self.collision = collision
   return self
end

function Walk:update(dt)
   local forward_x = math.sin(self.yaw)
   local forward_z = math.cos(self.yaw)
   local right_x = forward_z
   local right_z = -forward_x
   local dx, dz = 0.0, 0.0

   if self.move.forward then
      dx = dx + forward_x
      dz = dz + forward_z
   end
   if self.move.back then
      dx = dx - forward_x
      dz = dz - forward_z
   end
   if self.move.right then
      dx = dx + right_x
      dz = dz + right_z
   end
   if self.move.left then
      dx = dx - right_x
      dz = dz - right_z
   end

   local length = math.sqrt(dx * dx + dz * dz)
   local desired_x, desired_z = 0.0, 0.0
   if length > 0.0 then
      desired_x = dx / length * self.speed
      desired_z = dz / length * self.speed
   end

   if self.smoothing > 0.0 then
      local step = dt or 0.0
      local alpha = 1.0 - math.exp(-step / self.smoothing)
      self.velocity[1] = self.velocity[1] + (desired_x - self.velocity[1]) * alpha
      self.velocity[2] = self.velocity[2] + (desired_z - self.velocity[2]) * alpha
   else
      self.velocity[1] = desired_x
      self.velocity[2] = desired_z
   end

   local move_x = self.velocity[1] * (dt or 0.0)
   local move_z = self.velocity[2] * (dt or 0.0)
   if move_x ~= 0.0 or move_z ~= 0.0 then
      if self.collision ~= nil then
         self.collision:move(self.position, move_x, move_z, { radius = self.radius })
      else
         self.position[1] = self.position[1] + move_x
         self.position[3] = self.position[3] + move_z
      end
   end

   self.position[2] = self.floor_y
end

function Walk:apply(scene)
   local forward = self:forward()
   local eye = self:eye()
   apply_camera(scene, eye, {
      eye[1] + forward[1],
      eye[2] + forward[2],
      eye[3] + forward[3],
   })
end

function M.orbit(options)
   return Orbit(options)
end

function M.fly(options)
   return Fly(options)
end

function M.walk(options)
   return Walk(options)
end

return M