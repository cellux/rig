local test = require("test")
local jpeg = require("jpeg")
local rig = require("rig")

local function read_fixture()
   local bytes = rig.read_file("tests/fixtures/assets/tiny.jpg")
   test.truthy(bytes ~= nil)
   return bytes
end

test.case("jpeg decodes a fixture when support is built", function()
   local image, err = jpeg.decode(read_fixture(), "tiny.jpg")

   if image == nil then
      -- rig was built without libjpeg headers; the stub reports this.
      test.match(tostring(err), "not built")
      return
   end

   test.equal(image.width, 2)
   test.equal(image.height, 2)
   test.equal(image.channels, 4)
   test.equal(#image.pixels, 2 * 2 * 4)
end)

test.case("jpeg.decode reports malformed input", function()
   local image, err = jpeg.decode("not a jpeg", "junk")

   if image == nil and type(err) == "string" and err:match("not built") then
      return
   end

   test.equal(image, nil)
   test.truthy(type(err) == "string")
end)