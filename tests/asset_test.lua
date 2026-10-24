local test = require("test")
local asset = require("asset")

test.case("asset.text resolves relative to the script and caches", function()
   local text = asset.text("fixtures/assets/hello.txt")

   test.equal(text, "hello assets\n")
   test.equal(asset.bytes("fixtures/assets/hello.txt"), text)
   test.match(asset.path("fixtures/assets/hello.txt"), "hello%.txt$")
end)

test.case("asset.image decodes a relative PNG", function()
   local image = asset.image("fixtures/assets/tiny.png")

   test.equal(image.width, 2)
   test.equal(image.height, 2)
   test.equal(image.channels, 4)
end)

test.case("asset.material loads GLSL sources relative to the script", function()
   local material = asset.material {
      name = "tint",
      vertex = "fixtures/assets/tint.vert",
      fragment = "fixtures/assets/tint.frag",
   }

   test.equal(material.kind, "render.material")
   test.match(material.vertex, "u_mvp")
   test.match(material.fragment, "frag_color")
   test.equal(asset.material {
      name = "tint",
      vertex = "fixtures/assets/tint.vert",
      fragment = "fixtures/assets/tint.frag",
   }, material)
end)

test.case("asset.mesh loads and parses an OBJ relative to the script", function()
   local triangle = asset.mesh("fixtures/assets/triangle.obj")

   test.equal(triangle.layout, "position_color_uv_f32")
   test.equal(triangle.vertex_count, 3)
   test.equal(asset.mesh("fixtures/assets/triangle.obj"), triangle)
end)

test.case("asset raises for missing files", function()
   local ok = pcall(function()
      asset.text("fixtures/assets/missing.txt")
   end)
   test.falsey(ok)
end)