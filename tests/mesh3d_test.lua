local test = require("test")
local mesh3d = require("mesh3d")
require("sdl3")

test.case("mesh3d.make_cube returns a backend-neutral mesh layout", function()
   local mesh = mesh3d.make_cube()

   test.equal(mesh.layout, "position_color_f32")
   test.equal(mesh.vertex_stride, 24)
   test.equal(mesh.vertex_count, 36)
   test.equal(mesh.attribute_offsets.position, 0)
   test.equal(mesh.attribute_offsets.color, 12)
   test.truthy(type(mesh.vertex_blob) == "string")
   test.truthy(#mesh.vertex_blob > 0)
end)

test.case("mesh3d.build_vertex_input resolves through the active provider", function()
   local mesh = mesh3d.make_cube()

   rig.register_runtime_driver("mesh3d_test_driver", {
      loop = function()
         _G.mesh3d_test_vertex_input = mesh3d.build_vertex_input(mesh)
      end,
   })

   rig.run {
      driver = "mesh3d_test_driver",
      providers = {
         ["mesh3d.vertex_input"] = "sdl3_gpu",
      },
   }

   local vertex_input = mesh3d_test_vertex_input
   test.truthy(type(vertex_input) == "table")
   test.truthy(vertex_input.state ~= nil)
   test.truthy(vertex_input.vertex_buffer_descriptions ~= nil)
   test.truthy(vertex_input.vertex_attributes ~= nil)
   test.equal(tonumber(vertex_input.state[0].num_vertex_buffers), 1)
   test.equal(tonumber(vertex_input.state[0].num_vertex_attributes), 2)
end)
