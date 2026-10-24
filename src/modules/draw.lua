local M = ... or {}
local color = require("color")
local rig = require("rig")
local runtime = require("runtime")

-- Backend-neutral 2D drawing. `draw` owns the public immediate API and the
-- validation; a `draw.renderer` provider supplies the backend implementation
-- (SDL_Renderer, OpenGL, or SDL_GPU). Providers are selected by the active
-- `graphics.context` backend through `graphics.provider_component`.
--
-- Coordinates are screen-space pixels with the origin at the top-left, matching
-- the scene surface returned to callbacks as `frame.surface`.

local canvas_mt = {}
canvas_mt.__index = canvas_mt

local function ensure_canvas(canvas)
   if getmetatable(canvas) ~= canvas_mt then
      rig.raise("draw operation expects a canvas created by draw.create")
   end
   if canvas._released then
      rig.raise("draw canvas has been released")
   end
end

local function ensure_number(label, value)
   if type(value) ~= "number" then
      rig.raise("%s expects a number", label)
   end
end

local function normalize_color(label, value)
   if value == nil then
      return color.WHITE
   end
   if not color.is(value) then
      rig.raise("%s expects a color.Color if provided", label)
   end
   return value
end

-- Creates a canvas bound to a `draw.renderer` provider.
function M.create(provider)
   if type(provider) ~= "table" then
      rig.raise("draw.create expects a draw.renderer provider")
   end
   if type(provider.draw_rect) ~= "function" then
      rig.raise("draw.renderer provider must implement draw_rect")
   end
   if type(provider.draw_line) ~= "function" then
      rig.raise("draw.renderer provider must implement draw_line")
   end

   local canvas = setmetatable({
      _provider = provider,
      _released = false,
   }, canvas_mt)

   if type(provider.create_canvas) == "function" then
      canvas._state = provider.create_canvas(canvas)
   end

   return canvas
end

function M.release(canvas)
   ensure_canvas(canvas)

   local provider = canvas._provider
   if type(provider.release_canvas) == "function" then
      provider.release_canvas(canvas)
   end

   canvas._state = nil
   canvas._released = true
end

function canvas_mt:release()
   return M.release(self)
end

-- Fills the screen-space rectangle (`x`, `y`, `width`, `height`) with `color`.
function M.rect(canvas, x, y, width, height, draw_color)
   ensure_canvas(canvas)
   ensure_number("draw.rect expects x", x)
   ensure_number("draw.rect expects y", y)
   ensure_number("draw.rect expects width", width)
   ensure_number("draw.rect expects height", height)

   canvas._provider.draw_rect(
      canvas,
      x,
      y,
      width,
      height,
      normalize_color("draw.rect expects color", draw_color)
   )
end

function canvas_mt:rect(x, y, width, height, draw_color)
   return M.rect(self, x, y, width, height, draw_color)
end

-- Draws a one-pixel line from (`x1`, `y1`) to (`x2`, `y2`).
function M.line(canvas, x1, y1, x2, y2, draw_color)
   ensure_canvas(canvas)
   ensure_number("draw.line expects x1", x1)
   ensure_number("draw.line expects y1", y1)
   ensure_number("draw.line expects x2", x2)
   ensure_number("draw.line expects y2", y2)

   canvas._provider.draw_line(
      canvas,
      x1,
      y1,
      x2,
      y2,
      normalize_color("draw.line expects color", draw_color)
   )
end

function canvas_mt:line(x1, y1, x2, y2, draw_color)
   return M.line(self, x1, y1, x2, y2, draw_color)
end

-- Builds the bound facade exposed by `draw.component` / provider components.
function M.bind(provider)
   if type(provider) ~= "table" then
      rig.raise("draw.bind expects a draw.renderer provider")
   end

   return M.create(provider)
end

function M.plugin(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "draw",
      capabilities = {
         ["draw.renderer"] = {},
      },
   }
end

function M.component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      requires = {
         { capability = "draw.renderer" },
      },
      create = function(context)
         return M.bind(context:capability("draw.renderer"))
      end,
   })
end

return M
