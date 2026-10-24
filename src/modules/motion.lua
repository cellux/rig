local M = ... or {}

local mathx = require("mathx")
local rig = require("rig")

-- Motions are transform contributors. A node composes its motion list inside
-- `build_local`, in list order, each applied before (pre-multiplied onto) the
-- stored base local matrix:
--     local = m1 * m2 * ... * base
-- so a rotation motion spins a node about its own origin rather than orbiting
-- the parent. Each motion sees the frame context `{ time, dt, scene, surface }`
-- and may be closed-form (a pure function of time) or read accumulated state.
-- A motion with an `anchor` evaluates relative to that anchor, which is the
-- bridge an interaction uses to start a local, event-driven animation.
local Motion = rig.Class()
M.Motion = Motion

function Motion:init(options)
   options = options or {}
   self.anchor = options.anchor
end

-- Sets the time (in scene seconds) that this motion counts from. Reactive code
-- calls this when an interaction starts the motion.
function Motion:set_anchor(time)
   self.anchor = time
   return self
end

-- The motion's local time: scene time minus its anchor when present.
function Motion:local_time(frame)
   local t = 0.0
   if frame ~= nil and frame.time ~= nil then
      t = frame.time
   end
   if self.anchor ~= nil then
      return t - self.anchor
   end
   return t
end

-- Override: pre-multiply this motion's contribution onto `out` and return it.
function Motion:contribute(out, node, frame)
   return out
end

-- Closed-form rotation around the x, y, and z axes. Speed is radians per
-- second; when no axis is given the defaults match the classic demo spin.
local Spin = rig.Class(Motion)
M.Spin = Spin

function Spin:init(options)
   options = options or {}
   self:super().init(self, options)

   local x = options.x
   local y = options.y
   local z = options.z
   if x == nil and y == nil and z == nil then
      x = 0.7
      y = 1.0
   end

   self.x = x or 0.0
   self.y = y or 0.0
   self.z = z or 0.0
   self.angle = options.angle or 0.0

   self._rx = mathx.mat4()
   self._ry = mathx.mat4()
   self._rz = mathx.mat4()
end

function Spin:contribute(out, node, frame)
   local t = self:local_time(frame) + self.angle

   if self.x ~= 0.0 then
      mathx.mat4_rotation_x(self._rx, t * self.x)
      mathx.mat4_multiply(out, self._rx, out)
   end
   if self.y ~= 0.0 then
      mathx.mat4_rotation_y(self._ry, t * self.y)
      mathx.mat4_multiply(out, self._ry, out)
   end
   if self.z ~= 0.0 then
      mathx.mat4_rotation_z(self._rz, t * self.z)
      mathx.mat4_multiply(out, self._rz, out)
   end

   return out
end

function M.spin(options)
   return Spin(options)
end

return M