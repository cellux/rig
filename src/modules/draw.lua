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

local texture_mt = {}
texture_mt.__index = texture_mt

local function ensure_canvas(canvas)
   if getmetatable(canvas) ~= canvas_mt then
      rig.raise("draw operation expects a canvas created by draw.create")
   end
   if canvas._released then
      rig.raise("draw canvas has been released")
   end
end

local function ensure_texture(texture)
   if getmetatable(texture) ~= texture_mt then
      rig.raise("draw operation expects a texture created by draw.create_texture")
   end
   if texture._released then
      rig.raise("draw texture has been released")
   end
end

local function provider_method(canvas, name)
   local method = canvas._provider[name]
   if type(method) ~= "function" then
      rig.raise("the active draw.renderer provider does not implement %s", name)
   end
   return method
end

local function ensure_number(label, value)
   if type(value) ~= "number" then
      rig.raise("%s expects a number", label)
   end
end

local function ensure_integer_size(label, value)
   if type(value) ~= "number" or value <= 0 or value % 1 ~= 0 then
      rig.raise("%s expects a positive integer", label)
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
      _textures = {},
      _released = false,
   }, canvas_mt)

   if type(provider.create_canvas) == "function" then
      canvas._state = provider.create_canvas(canvas)
   end

   return canvas
end

function M.release(canvas)
   ensure_canvas(canvas)

   local textures = canvas._textures
   for i = #textures, 1, -1 do
      local texture = textures[i]
      if not texture._released then
         canvas._provider.destroy_texture(canvas, texture._handle)
         texture._released = true
         texture._handle = nil
      end
      textures[i] = nil
   end
   canvas._textures = nil

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

-- Creates a backend texture from RGBA8 pixels. `options` fields:
--   width, height  pixel dimensions (positive integers)
--   pixels         a `width * height * 4` byte string, top-down, row-major
--   filter         "linear" (default) or "nearest"
--   wrap           "clamp" (default), "repeat", or "mirror"
function M.create_texture(canvas, options)
   ensure_canvas(canvas)
   if type(options) ~= "table" then
      rig.raise("draw.create_texture expects an options table")
   end

   ensure_integer_size("draw.create_texture expects width", options.width)
   ensure_integer_size("draw.create_texture expects height", options.height)
   if type(options.pixels) ~= "string" then
      rig.raise("draw.create_texture expects pixels to be a byte string")
   end
   local expected = options.width * options.height * 4
   if #options.pixels ~= expected then
      rig.raise(
         "draw.create_texture expects %d pixel bytes, got %d",
         expected,
         #options.pixels
      )
   end

   local create_texture = provider_method(canvas, "create_texture")
   provider_method(canvas, "destroy_texture")
   local handle = create_texture(canvas, {
      width = options.width,
      height = options.height,
      pixels = options.pixels,
      filter = options.filter or "linear",
      wrap = options.wrap or "clamp",
   })
   if handle == nil then
      rig.raise("draw.renderer provider returned no texture handle")
   end

   local texture = setmetatable({
      width = options.width,
      height = options.height,
      filter = options.filter or "linear",
      wrap = options.wrap or "clamp",
      _canvas = canvas,
      _handle = handle,
      _released = false,
   }, texture_mt)

   canvas._textures[#canvas._textures + 1] = texture
   return texture
end

function canvas_mt:create_texture(options)
   return M.create_texture(self, options)
end

-- Releases a texture created by `draw.create_texture`. Textures still alive when
-- their canvas is released are released automatically.
function M.release_texture(texture)
   ensure_texture(texture)

   local canvas = texture._canvas
   if canvas ~= nil and not canvas._released then
      canvas._provider.destroy_texture(canvas, texture._handle)
   end
   texture._handle = nil
   texture._released = true
end

function texture_mt:release()
   return M.release_texture(self)
end

-- Draws the whole texture at (`x`, `y`), optionally tinted and alpha-modulated by
-- `draw_color` (defaults to white, so the pixels pass through unchanged).
function M.draw_texture(canvas, texture, x, y, draw_color)
   ensure_canvas(canvas)
   ensure_texture(texture)
   ensure_number("draw.draw_texture expects x", x)
   ensure_number("draw.draw_texture expects y", y)

   canvas._provider.draw_texture(
      canvas,
      texture._handle,
      0,
      0,
      texture.width,
      texture.height,
      x,
      y,
      texture.width,
      texture.height,
      normalize_color("draw.draw_texture expects color", draw_color)
   )
end

function canvas_mt:draw_texture(texture, x, y, draw_color)
   return M.draw_texture(self, texture, x, y, draw_color)
end

-- Draws the source region (`sx`, `sy`, `sw`, `sh`) of `texture` scaled into the
-- destination rectangle (`dx`, `dy`, `dw`, `dh`), modulated by `draw_color`.
function M.draw_texture_region(canvas, texture, sx, sy, sw, sh, dx, dy, dw, dh, draw_color)
   ensure_canvas(canvas)
   ensure_texture(texture)
   ensure_number("draw.draw_texture_region expects sx", sx)
   ensure_number("draw.draw_texture_region expects sy", sy)
   ensure_number("draw.draw_texture_region expects sw", sw)
   ensure_number("draw.draw_texture_region expects sh", sh)
   ensure_number("draw.draw_texture_region expects dx", dx)
   ensure_number("draw.draw_texture_region expects dy", dy)
   ensure_number("draw.draw_texture_region expects dw", dw)
   ensure_number("draw.draw_texture_region expects dh", dh)

   if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0 then
      return
   end

   canvas._provider.draw_texture(
      canvas,
      texture._handle,
      sx,
      sy,
      sw,
      sh,
      dx,
      dy,
      dw,
      dh,
      normalize_color("draw.draw_texture_region expects color", draw_color)
   )
end

function canvas_mt:draw_texture_region(texture, sx, sy, sw, sh, dx, dy, dw, dh, draw_color)
   return M.draw_texture_region(
      self,
      texture,
      sx,
      sy,
      sw,
      sh,
      dx,
      dy,
      dw,
      dh,
      draw_color
   )
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
