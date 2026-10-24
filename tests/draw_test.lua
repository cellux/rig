local test = require("test")
local color = require("color")
local draw = require("draw")

local function fake_provider(observed)
   return {
      draw_rect = function(_, x, y, width, height, draw_color)
         observed.x = x
         observed.y = y
         observed.width = width
         observed.height = height
         observed.color = draw_color
      end,
      draw_line = function(_, x1, y1, x2, y2, draw_color)
         observed.x1 = x1
         observed.y1 = y1
         observed.x2 = x2
         observed.y2 = y2
         observed.color = draw_color
      end,
   }
end

test.case("draw.rect forwards geometry and color to the provider", function()
   local observed = {}
   local canvas = draw.create(fake_provider(observed))
   local draw_color = color.rgba(12, 34, 56, 78)

   canvas:rect(10, 20, 30, 40, draw_color)

   test.equal(observed.x, 10)
   test.equal(observed.y, 20)
   test.equal(observed.width, 30)
   test.equal(observed.height, 40)
   test.truthy(color.is(observed.color))
   test.equal(observed.color.r, 12)
   test.equal(observed.color.g, 34)
   test.equal(observed.color.b, 56)
   test.equal(observed.color.a, 78)

   canvas:release()
end)

test.case("draw.line forwards endpoints and color to the provider", function()
   local observed = {}
   local canvas = draw.create(fake_provider(observed))

   canvas:line(1, 2, 3, 4, color.rgb(90, 100, 110))

   test.equal(observed.x1, 1)
   test.equal(observed.y1, 2)
   test.equal(observed.x2, 3)
   test.equal(observed.y2, 4)
   test.truthy(color.is(observed.color))
   test.equal(observed.color.r, 90)

   canvas:release()
end)

test.case("draw defaults a missing color to white", function()
   local observed = {}
   local canvas = draw.create(fake_provider(observed))

   canvas:rect(0, 0, 1, 1)

   test.truthy(color.is(observed.color))
   test.equal(observed.color.r, 255)
   test.equal(observed.color.g, 255)
   test.equal(observed.color.b, 255)
   test.equal(observed.color.a, 255)

   canvas:release()
end)

test.case("draw rejects a non-color color argument", function()
   local canvas = draw.create(fake_provider({}))

   local ok = pcall(function()
      canvas:rect(0, 0, 1, 1, "red")
   end)

   test.falsey(ok)
   canvas:release()
end)

test.case("draw.create requires a draw.renderer provider", function()
   local ok, err = pcall(function()
      draw.create({ draw_rect = function() end })
   end)

   test.falsey(ok)
   test.match(tostring(err), "draw_line")
end)

test.case("a released canvas rejects further draws", function()
   local canvas = draw.create(fake_provider({}))
   canvas:release()

   local ok, err = pcall(function()
      canvas:rect(0, 0, 1, 1)
   end)

   test.falsey(ok)
   test.match(tostring(err), "released")
end)

local function texture_provider(observed)
   local provider = fake_provider(observed)
   provider.create_texture = function(_, spec)
      observed.spec = spec
      return { kind = "handle", width = spec.width, height = spec.height }
   end
   provider.destroy_texture = function(_, handle)
      observed.destroyed = handle
   end
   provider.draw_texture = function(_, handle, sx, sy, sw, sh, dx, dy, dw, dh, draw_color)
      observed.handle = handle
      observed.sx = sx
      observed.sy = sy
      observed.sw = sw
      observed.sh = sh
      observed.dx = dx
      observed.dy = dy
      observed.dw = dw
      observed.dh = dh
      observed.color = draw_color
   end
   return provider
end

test.case("draw.create_texture validates and forwards the pixel spec", function()
   local observed = {}
   local canvas = draw.create(texture_provider(observed))

   local texture = canvas:create_texture {
      width = 2,
      height = 3,
      pixels = string.rep("\0", 2 * 3 * 4),
   }

   test.equal(texture.width, 2)
   test.equal(texture.height, 3)
   test.equal(observed.spec.width, 2)
   test.equal(observed.spec.height, 3)
   test.equal(#observed.spec.pixels, 24)
   test.equal(observed.spec.filter, "linear")
   test.equal(observed.spec.wrap, "clamp")

   canvas:release()
end)

test.case("draw.create_texture rejects a wrong pixel byte count", function()
   local canvas = draw.create(texture_provider({}))

   local ok, err = pcall(function()
      canvas:create_texture { width = 2, height = 2, pixels = "too short" }
   end)

   test.falsey(ok)
   test.match(tostring(err), "pixel bytes")
   test.falsey(ok)

   canvas:release()
end)

test.case("draw.draw_texture forwards the full source region", function()
   local observed = {}
   local canvas = draw.create(texture_provider(observed))
   local texture = canvas:create_texture {
      width = 4,
      height = 6,
      pixels = string.rep("\0", 4 * 6 * 4),
      filter = "nearest",
   }

   canvas:draw_texture(texture, 11, 22)

   test.truthy(observed.handle)
   test.equal(observed.sx, 0)
   test.equal(observed.sy, 0)
   test.equal(observed.sw, 4)
   test.equal(observed.sh, 6)
   test.equal(observed.dx, 11)
   test.equal(observed.dy, 22)
   test.equal(observed.dw, 4)
   test.equal(observed.dh, 6)
   test.equal(observed.color.a, 255)
   test.equal(observed.spec.filter, "nearest")

   canvas:release()
end)

test.case("draw.draw_texture_region forwards the region and modulation color", function()
   local observed = {}
   local canvas = draw.create(texture_provider(observed))
   local texture = canvas:create_texture {
      width = 8,
      height = 8,
      pixels = string.rep("\0", 8 * 8 * 4),
   }

   canvas:draw_texture_region(
      texture,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      color.rgba(10, 20, 30, 40)
   )

   test.equal(observed.sx, 1)
   test.equal(observed.sy, 2)
   test.equal(observed.sw, 3)
   test.equal(observed.sh, 4)
   test.equal(observed.dx, 5)
   test.equal(observed.dy, 6)
   test.equal(observed.dw, 7)
   test.equal(observed.dh, 8)
   test.equal(observed.color.r, 10)
   test.equal(observed.color.a, 40)

   canvas:release()
end)

test.case("draw.draw_texture_region skips empty regions", function()
   local observed = {}
   local canvas = draw.create(texture_provider(observed))
   local texture = canvas:create_texture {
      width = 1,
      height = 1,
      pixels = string.rep("\0", 4),
   }

   canvas:draw_texture_region(texture, 0, 0, 0, 1, 0, 0, 1, 1)

   test.equal(observed.handle, nil)

   canvas:release()
end)

test.case("a released texture rejects further draws", function()
   local observed = {}
   local canvas = draw.create(texture_provider(observed))
   local texture = canvas:create_texture {
      width = 1,
      height = 1,
      pixels = string.rep("\0", 4),
   }

   texture:release()
   test.truthy(observed.destroyed)

   local ok, err = pcall(function()
      canvas:draw_texture(texture, 0, 0)
   end)
   test.falsey(ok)
   test.match(tostring(err), "released")

   canvas:release()
end)

test.case("releasing a canvas releases its outstanding textures", function()
   local observed = {}
   local canvas = draw.create(texture_provider(observed))
   canvas:create_texture { width = 1, height = 1, pixels = string.rep("\0", 4) }

   canvas:release()

   test.truthy(observed.destroyed)
end)

test.case("textures require a provider that implements create_texture", function()
   local canvas = draw.create(fake_provider({}))

   local ok, err = pcall(function()
      canvas:create_texture { width = 1, height = 1, pixels = string.rep("\0", 4) }
   end)

   test.falsey(ok)
   test.match(tostring(err), "create_texture")

   canvas:release()
end)
