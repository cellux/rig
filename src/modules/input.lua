local M = ... or {}

local rig = require("rig")

-- Backend-agnostic input state. Feed it the `sdl3.key`/`sdl3.mouse` payloads the
-- runtime already emits (the sketch facade does this automatically), then query
-- held/pressed/released keys and the mouse. `begin_frame()` clears the per-frame
-- edges and relative deltas; the sketch calls it at the end of each frame so
-- `on_update`/`on_draw`/overlays all see the same frame's edges.
--
-- Keys are addressed either by scancode (a number) or by name (a string such as
-- `"W"`, `"Space"`, `"Escape"`), matching the `sdl3` event payload. Names are
-- case-insensitive.

local function key_id(id)
   if type(id) == "number" then
      return "scancode:" .. id
   end
   return "name:" .. string.upper(tostring(id))
end

local Input = rig.Class()
M.Input = Input

function Input:init()
   self.down = {}
   self.pressed = {}
   self.released = {}
   self.mouse_x = 0
   self.mouse_y = 0
   self.mouse_dx = 0
   self.mouse_dy = 0
   self.buttons = {}
   self.buttons_pressed = {}
   self.buttons_released = {}
   self.shift = false
   self.ctrl = false
   self.alt = false
   self.super = false
end

-- Clears per-frame edges and relative deltas.
function Input:begin_frame()
   self.pressed = {}
   self.released = {}
   self.buttons_pressed = {}
   self.buttons_released = {}
   self.mouse_dx = 0
   self.mouse_dy = 0
end

function Input:on_key(event)
   if type(event) ~= "table" then
      return
   end

   local ids = {}
   if event.scancode ~= nil then
      ids[#ids + 1] = key_id(event.scancode)
   end
   if event.key ~= nil then
      ids[#ids + 1] = key_id(event.key)
   end

   if event.mods ~= nil then
      self.shift = event.mods.shift and true or false
      self.ctrl = event.mods.ctrl and true or false
      self.alt = event.mods.alt and true or false
      self.super = event.mods.super and true or false
   end

   if event.action == "down" then
      for i = 1, #ids do
         if not self.down[ids[i]] then
            self.pressed[ids[i]] = true
         end
         self.down[ids[i]] = true
      end
   elseif event.action == "up" then
      for i = 1, #ids do
         if self.down[ids[i]] then
            self.released[ids[i]] = true
         end
         self.down[ids[i]] = nil
      end
   end
end

function Input:on_mouse(event)
   if type(event) ~= "table" then
      return
   end

   if event.action == "move" then
      self.mouse_x = event.x or self.mouse_x
      self.mouse_y = event.y or self.mouse_y
      self.mouse_dx = self.mouse_dx + (event.xrel or 0)
      self.mouse_dy = self.mouse_dy + (event.yrel or 0)
   elseif event.action == "down" then
      local button = event.button or 1
      if event.x ~= nil then
         self.mouse_x = event.x
      end
      if event.y ~= nil then
         self.mouse_y = event.y
      end
      if not self.buttons[button] then
         self.buttons_pressed[button] = true
      end
      self.buttons[button] = true
   elseif event.action == "up" then
      local button = event.button or 1
      if event.x ~= nil then
         self.mouse_x = event.x
      end
      if event.y ~= nil then
         self.mouse_y = event.y
      end
      if self.buttons[button] then
         self.buttons_released[button] = true
      end
      self.buttons[button] = nil
   end
end

-- Held/pressed/released queries. `id` is a scancode or a key name.
function Input:key_down(id)
   return self.down[key_id(id)] == true
end

function Input:key_pressed(id)
   return self.pressed[key_id(id)] == true
end

function Input:key_released(id)
   return self.released[key_id(id)] == true
end

-- Mouse queries; `button` defaults to the primary button.
function Input:mouse_position()
   return self.mouse_x, self.mouse_y
end

function Input:mouse_delta()
   return self.mouse_dx, self.mouse_dy
end

function Input:mouse_down(button)
   return self.buttons[button or 1] == true
end

function Input:mouse_pressed(button)
   return self.buttons_pressed[button or 1] == true
end

function Input:mouse_released(button)
   return self.buttons_released[button or 1] == true
end

-- `-1`/`0`/`1` from a pair of keys, useful for movement.
function Input:axis(negative, positive)
   local value = 0
   if self:key_down(negative) then
      value = value - 1
   end
   if self:key_down(positive) then
      value = value + 1
   end
   return value
end

return M
