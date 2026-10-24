local test = require("test")
local color = require("color")
local ffi = require("ffi")
local mesh = require("mesh")

test.case("mesh.make_cube returns a provider-neutral mesh layout", function()
   local cube = mesh.make_cube()

   test.equal(cube.layout, "position_color_uv_f32")
   test.equal(cube.vertex_stride, 32)
   test.equal(cube.vertex_count, 36)
   test.equal(cube.attribute_offsets.position, 0)
   test.equal(cube.attribute_offsets.color, 12)
   test.equal(cube.attribute_offsets.uv, 24)
   test.truthy(type(cube.vertex_blob) == "string")
   test.truthy(#cube.vertex_blob > 0)
end)

test.case("mesh.build_vertex_input dispatches through a provider", function()
   local cube = mesh.make_cube()
   local seen = nil

   local vertex_input = mesh.build_vertex_input(cube, {
      build_vertex_input = function(value)
         seen = value
         return {
            cdata = { [0] = { num_vertex_buffers = 1, num_vertex_attributes = 2 } },
            vertex_buffer_descriptions = {},
            vertex_attributes = {},
         }
      end,
   })

   test.equal(seen, cube)
   test.truthy(type(vertex_input) == "table")
   test.equal(tonumber(vertex_input.cdata[0].num_vertex_buffers), 1)
   test.equal(tonumber(vertex_input.cdata[0].num_vertex_attributes), 2)
end)

test.case("mesh.build_vertex_input requires a provider", function()
   local ok, err = pcall(function()
      mesh.build_vertex_input(mesh.make_cube())
   end)

   test.falsey(ok)
   test.match(tostring(err), "requires a mesh%.vertex_input provider")
end)

test.case("mesh.make_cube accepts Color face colors", function()
   local cube = mesh.make_cube {
      colors = {
         color.rgb(255, 0, 0),
         color.rgb(0, 255, 0),
         color.rgb(0, 0, 255),
         color.rgb(255, 255, 0),
         color.rgb(255, 0, 255),
         color.rgb(0, 255, 255),
      },
   }
   local vertex_data = ffi.cast(
      "const float *",
      ffi.cast("const char *", cube.vertex_blob)
   )

   -- Vertex 0 (front face) is red.
   test.equal(vertex_data[3], 1)
   test.equal(vertex_data[4], 0)
   test.equal(vertex_data[5], 0)
   -- Vertex 6 (first vertex of the back face) is green.
   test.equal(vertex_data[6 * 8 + 3], 0)
   test.equal(vertex_data[6 * 8 + 4], 1)
   test.equal(vertex_data[6 * 8 + 5], 0)
end)

test.case("mesh primitives carry UVs where they can be textured", function()
   local quad = mesh.make_quad { size = 2.0 }
   test.equal(quad.layout, "position_color_uv_f32")
   test.equal(quad.vertex_stride, 32)
   test.equal(quad.attribute_offsets.uv, 24)
   test.equal(quad.vertex_count, 6)

   local triangle = mesh.make_triangle { size = 1.0 }
   test.equal(triangle.layout, "position_color_f32")
end)

test.case("mesh primitive generators share the position/color layout", function()
   local quad = mesh.make_quad { size = 2.0 }
   test.equal(quad.layout, "position_color_uv_f32")
   test.equal(quad.topology, "triangles")
   test.equal(quad.vertex_count, 6)

   local triangle = mesh.make_triangle { size = 1.0 }
   test.equal(triangle.topology, "triangles")
   test.equal(triangle.vertex_count, 3)

   local line = mesh.make_line { length = 4.0 }
   test.equal(line.topology, "lines")
   test.equal(line.vertex_count, 2)

   local polyline = mesh.make_lines { points = { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 1, 0 } } }
   test.equal(polyline.topology, "lines")
   test.equal(polyline.vertex_count, 4)

   local grid = mesh.make_grid { size = 2.0, divisions = 2 }
   test.equal(grid.topology, "lines")
   test.equal(grid.vertex_count, 12)

   test.equal(mesh.make_cube().topology, "triangles")
end)

test.case("mesh.make_line accepts explicit endpoints", function()
   local line = mesh.make_line { from = { 0, 1, 2 }, to = { 3, 4, 5 } }
   test.equal(line.vertex_count, 2)
end)

test.case("mesh.make_fullscreen_quad spans clip space with top-left UVs", function()
   local quad = mesh.make_fullscreen_quad()

   test.equal(quad.layout, "position_color_uv_f32")
   test.equal(quad.topology, "triangles")
   test.equal(quad.vertex_count, 6)

   local data = ffi.cast(
      "const float *",
      ffi.cast("const char *", quad.vertex_blob)
   )
   -- First vertex is the bottom-left corner with uv (0, 1).
   test.equal(data[0], -1)
   test.equal(data[1], -1)
   test.equal(data[6], 0)
   test.equal(data[7], 1)
   -- Third vertex is the top-right corner with uv (1, 0).
   test.equal(data[2 * 8 + 0], 1)
   test.equal(data[2 * 8 + 1], 1)
   test.equal(data[2 * 8 + 6], 1)
   test.equal(data[2 * 8 + 7], 0)
end)

test.case("mesh.parse_obj builds a UV triangle mesh from OBJ text", function()
   local obj = mesh.parse_obj [[
      # a single quad
      v 0 0 0
      v 1 0 0
      v 1 1 0
      v 0 1 0
      vt 0 0
      vt 1 0
      vt 1 1
      vt 0 1
      f 1/1 2/2 3/3 4/4
   ]]

   test.equal(obj.layout, "position_color_uv_f32")
   test.equal(obj.topology, "triangles")
   test.equal(obj.vertex_count, 6)
   test.equal(obj.attribute_offsets.uv, 24)

   local data = ffi.cast(
      "const float *",
      ffi.cast("const char *", obj.vertex_blob)
   )
   -- vertex 0 position, color (white), uv
   test.equal(data[0], 0)
   test.equal(data[4], 1)
   test.equal(data[6], 0)
   test.equal(data[7], 0)
   -- vertex 2 maps to vt 3 (1, 1)
   test.equal(data[2 * 8 + 6], 1)
   test.equal(data[2 * 8 + 7], 1)
end)

test.case("mesh.parse_obj resolves negative indices and triangulates", function()
   local obj = mesh.parse_obj [[
      v 0 0 0
      v 1 0 0
      v 1 1 0
      v 0 1 0
      f -4 -3 -2 -1
   ]]

   test.equal(obj.vertex_count, 6)
   local data = ffi.cast(
      "const float *",
      ffi.cast("const char *", obj.vertex_blob)
   )
   test.equal(data[0], 0)
   test.equal(data[8], 1)
end)

test.case("mesh.parse_obj rejects sources without faces", function()
   local ok, err = pcall(function()
      mesh.parse_obj("v 0 0 0\n")
   end)
   test.falsey(ok)
   test.match(tostring(err), "no faces")
end)
