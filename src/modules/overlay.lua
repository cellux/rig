local M = ... or {}

local color = require("color")
local mesh = require("mesh")
local rig = require("rig")

-- A lightweight live-parameter overlay. It is not a retained UI toolkit: it
-- draws screen-space bars for a `params` store through the scene's immediate
-- drawing API and edits them with the keyboard/mouse. Feed it the shared
-- `input` state once per frame (`overlay:update(input, scene)`) and draw it from
-- an `on_overlay` hook (`overlay:draw(scene)`), where it lands on top.
--
-- Interaction: Up/Down select, Left/Right adjust, Space/Return toggle, click
-- selects and drags number bars. `options.draw_text(scene, x, y, text, color)`
-- draws the optional labels (for example through the `font` module); without it
-- the overlay is bars only.

local Overlay = rig.Class()
M.Overlay = Overlay

local function clamp(value, low, high)
   if value < low then
      return low
   end
   if value > high then
      return high
   end
   return value
end

function Overlay:init(parameters, options)
   options = options or {}
   if parameters == nil then
      rig.raise("overlay.Overlay requires a params store")
   end

   self.params = parameters
   self.row_height = tonumber(options.row_height) or 20.0
   self.width = tonumber(options.width) or 260.0
   self.margin = tonumber(options.margin) or 12.0
   self.gap = tonumber(options.gap) or 4.0
   self.bar_height = tonumber(options.bar_height) or 10.0
   self.label_width = tonumber(options.label_width) or 96.0
   self.position = options.position or "top-left"
   self.draw_text = options.draw_text

   self.colors = {
      track = options.track_color or color.rgbaf(0.16, 0.18, 0.22),
      fill = options.fill_color or color.rgbaf(0.35, 0.75, 1.0),
      selected = options.selected_color or color.rgbaf(1.0, 0.85, 0.35),
      text = options.text_color or color.rgbaf(0.92, 0.94, 0.98),
   }

   self.selected = 1
   self.dragging = nil
   self.visible = options.visible ~= false
   self._quads = {}
end

function Overlay:quad(fill_color)
   local quad = self._quads[fill_color]
   if quad == nil then
      quad = mesh.make_quad { size = 1.0, color = fill_color }
      self._quads[fill_color] = quad
   end
   return quad
end

function Overlay:selected_name()
   return self.params:name_at(self.selected)
end

function Overlay:select(index)
   local count = self.params:count()
   if count == 0 then
      self.selected = 1
      return self.selected
   end
   while index < 1 do
      index = index + count
   end
   while index > count do
      index = index - count
   end
   self.selected = index
   return self.selected
end

-- Top-left origin of the overlay given the viewport and row count.
function Overlay:origin(view_width, view_height)
   local total_height =
      self.params:count() * (self.row_height + self.gap) - self.gap
   local x, y = self.margin, self.margin
   if self.position == "top-right" then
      x = view_width - self.margin - self.width
   elseif self.position == "bottom-left" then
      y = view_height - self.margin - total_height
   elseif self.position == "bottom-right" then
      x = view_width - self.margin - self.width
      y = view_height - self.margin - total_height
   end
   return x, y
end

function Overlay:row_at(mouse_x, mouse_y, origin_x, origin_y, count)
   if mouse_x < origin_x or mouse_x > origin_x + self.width then
      return nil
   end
   for i = 1, count do
      local row_y = origin_y + (i - 1) * (self.row_height + self.gap)
      if mouse_y >= row_y and mouse_y <= row_y + self.row_height then
         return i
      end
   end
   return nil
end

function Overlay:_drag_to(mouse_x, origin_x, definition)
   local bar_x = origin_x + self.label_width + self.gap
   local bar_width = self.width - self.label_width - self.gap
   local fraction = clamp((mouse_x - bar_x) / bar_width, 0.0, 1.0)
   self.params:set(
      definition.name,
      definition.min + fraction * (definition.max - definition.min)
   )
end

-- Edits parameters from the shared input state. `scene` only supplies the
-- viewport size for hit-testing.
function Overlay:update(input, scene)
   local count = self.params:count()
   if count == 0 or input == nil or not self.visible then
      return self
   end

   local view_width = scene and scene.width or 1
   local view_height = scene and scene.height or 1
   local origin_x, origin_y = self:origin(view_width, view_height)

   if input:key_pressed("Down") then
      self:select(self.selected + 1)
   end
   if input:key_pressed("Up") then
      self:select(self.selected - 1)
   end

   local name = self:selected_name()
   if name ~= nil then
      if input:key_pressed("Right") then
         self.params:adjust(name, 1)
      end
      if input:key_pressed("Left") then
         self.params:adjust(name, -1)
      end
      if input:key_pressed("Space") or input:key_pressed("Return") then
         self.params:toggle(name)
      end
   end

   local mouse_x, mouse_y = input:mouse_position()
   local row = self:row_at(mouse_x, mouse_y, origin_x, origin_y, count)

   if input:mouse_pressed(1) and row ~= nil then
      self.selected = row
      local definition = self.params:definition(self.params:name_at(row))
      if definition.kind == "number" then
         self.dragging = row
         self:_drag_to(mouse_x, origin_x, definition)
      end
   end

   if self.dragging ~= nil then
      if input:mouse_down(1) then
         local definition = self.params:definition(self.params:name_at(self.dragging))
         self:_drag_to(mouse_x, origin_x, definition)
      else
         self.dragging = nil
      end
   end

   return self
end

function Overlay:draw(scene)
   local count = self.params:count()
   if count == 0 or not self.visible then
      return self
   end

   local view_width = scene.width or 1
   local view_height = scene.height or 1
   local origin_x, origin_y = self:origin(view_width, view_height)

   local bar_x = origin_x + self.label_width + self.gap
   local bar_width = self.width - self.label_width - self.gap

   for i = 1, count do
      local name = self.params:name_at(i)
      local definition = self.params:definition(name)
      local row_y = origin_y + (i - 1) * (self.row_height + self.gap)
      local bar_y = row_y + (self.row_height - self.bar_height) * 0.5

      scene:draw_screen(
         self:quad(self.colors.track),
         bar_x,
         bar_y,
         bar_width,
         self.bar_height
      )

      local fraction = self.params:fraction(name)
      if fraction > 0.0 then
         scene:draw_screen(
            self:quad(self.colors.fill),
            bar_x,
            bar_y,
            math.max(1.0, bar_width * fraction),
            self.bar_height
         )
      end

      if i == self.selected then
         scene:draw_screen(
            self:quad(self.colors.selected),
            bar_x,
            row_y,
            bar_width,
            2.0
         )
      end

      if self.draw_text ~= nil then
         self.draw_text(
            scene,
            origin_x,
            row_y + self.row_height * 0.5,
            definition.label .. " = " .. self.params:format(name),
            self.colors.text
         )
      end
   end

   return self
end

M.overlay = function(parameters, options)
   return Overlay(parameters, options)
end

return M
