local test = require("test")
local color = require("color")
local ffi = require("ffi")
local mesh = require("mesh")
require("sdl3x")

test.case("mesh.make_cube returns a provider-neutral mesh layout", function()
   local cube = mesh.make_cube()

   test.equal(cube.layout, "position_color_f32")
   test.equal(cube.vertex_stride, 24)
   test.equal(cube.vertex_count, 36)
   test.equal(cube.attribute_offsets.position, 0)
   test.equal(cube.attribute_offsets.color, 12)
   test.truthy(type(cube.vertex_blob) == "string")
   test.truthy(#cube.vertex_blob > 0)
end)

test.case("mesh.build_vertex_input resolves through the active provider", function()
   local cube = mesh.make_cube()

   rig.register_runtime_driver("mesh_test_driver", {
      loop = function()
         _G.mesh_test_vertex_input = mesh.build_vertex_input(cube)
      end,
   })

   rig.run {
      driver = "mesh_test_driver",
      providers = {
         ["mesh.vertex_input"] = "sdl3_gpu",
      },
   }

   local vertex_input = mesh_test_vertex_input
   test.truthy(type(vertex_input) == "table")
   test.truthy(vertex_input.state ~= nil)
   test.truthy(vertex_input.vertex_buffer_descriptions ~= nil)
   test.truthy(vertex_input.vertex_attributes ~= nil)
   test.equal(tonumber(vertex_input.state[0].num_vertex_buffers), 1)
   test.equal(tonumber(vertex_input.state[0].num_vertex_attributes), 2)
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

   test.equal(vertex_data[3], 1)
   test.equal(vertex_data[4], 0)
   test.equal(vertex_data[5], 0)
   test.equal(vertex_data[39], 0)
   test.equal(vertex_data[40], 1)
   test.equal(vertex_data[41], 0)
end)
