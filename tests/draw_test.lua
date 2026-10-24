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
