local test = require("test")
local png = require("png")
local rig = require("rig")

test.case("png decodes an RGBA fixture", function()
   local bytes = rig.read_file("tests/fixtures/assets/tiny.png")
   test.truthy(bytes ~= nil)

   local image = png.decode(bytes, "tiny.png")
   test.truthy(image ~= nil)
   test.equal(image.width, 2)
   test.equal(image.height, 2)
   test.equal(image.channels, 4)
   test.equal(#image.pixels, 2 * 2 * 4)

   -- top-left pixel is opaque red
   test.equal(string.byte(image.pixels, 1), 255)
   test.equal(string.byte(image.pixels, 2), 0)
   test.equal(string.byte(image.pixels, 3), 0)
   test.equal(string.byte(image.pixels, 4), 255)
end)

test.case("png.decode reports malformed input", function()
   local image, err = png.decode("not a png", "junk")
   test.equal(image, nil)
   test.truthy(type(err) == "string")
end)
test.case("png.encode round-trips RGBA pixels", function()
   local pixels = string.char(
      255, 0, 0, 255,
      0, 255, 0, 255,
      0, 0, 255, 255,
      255, 255, 0, 128
   )
   local bytes = png.encode({
      width = 2,
      height = 2,
      pixels = pixels,
   }, "roundtrip")

   test.truthy(type(bytes) == "string")
   test.truthy(#bytes > 0)

   local image = png.decode(bytes, "roundtrip")
   test.equal(image.width, 2)
   test.equal(image.height, 2)
   test.equal(image.pixels, pixels)
end)
