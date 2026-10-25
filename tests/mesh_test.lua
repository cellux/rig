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

local function float_data(value)
   return ffi.cast("const float *", ffi.cast("const char *", value))
end

local function index_data(value)
   return ffi.cast("const uint32_t *", ffi.cast("const char *", value))
end

test.case("mesh layouts expose stable attribute roles and offsets", function()
   local lit = mesh.layout("position_normal_color_uv_f32")
   test.equal(lit.stride, 44)
   test.equal(lit.attributes.position.offset, 0)
   test.equal(lit.attributes.normal.offset, 12)
   test.equal(lit.attributes.color.offset, 24)
   test.equal(lit.attributes.uv.offset, 36)
   test.equal(lit.attributes.position.location, 0)
   test.equal(lit.attributes.color.location, 1)
   test.equal(lit.attributes.uv.location, 2)
   test.equal(lit.attributes.normal.location, 3)

   local tangent = mesh.layout("position_normal_tangent_color_uv_f32")
   test.equal(tangent.stride, 60)
   test.equal(tangent.attributes.tangent.offset, 24)
   test.equal(tangent.attributes.tangent.location, 4)

   local ok, err = pcall(function()
      mesh.layout("does_not_exist")
   end)
   test.falsey(ok)
   test.match(tostring(err), "unknown mesh layout")
end)

test.case("mesh.make_box emits indexed triangles with normals and UVs", function()
   local box = mesh.make_box {
      width = 2.0,
      height = 4.0,
      depth = 6.0,
      color = color.rgb(255, 0, 0),
   }

   test.equal(box.layout, "position_normal_color_uv_f32")
   test.equal(box.topology, "triangles")
   test.equal(box.vertex_stride, 44)
   test.equal(box.vertex_count, 24)
   test.equal(box.index_count, 36)
   test.equal(box.index_type, "uint32")
   test.equal(box.index_stride, 4)
   test.equal(box.attribute_offsets.normal, 12)
   test.equal(#box.index_blob, 36 * 4)

   local vertices = float_data(box.vertex_blob)
   -- First front-face vertex: (-1, -2, -3), normal (0, 0, -1), uv (0, 0).
   test.equal(vertices[0], -1)
   test.equal(vertices[1], -2)
   test.equal(vertices[2], -3)
   test.equal(vertices[3], 0)
   test.equal(vertices[4], 0)
   test.equal(vertices[5], -1)
   test.equal(vertices[6], 1)
   test.equal(vertices[7], 0)
   test.equal(vertices[8], 0)
   test.equal(vertices[9], 0)
   test.equal(vertices[10], 0)

   local indices = index_data(box.index_blob)
   test.equal(indices[0], 0)
   test.equal(indices[1], 1)
   test.equal(indices[2], 2)
end)

test.case("mesh.make_cylinder emits sides and caps", function()
   local cylinder = mesh.make_cylinder {
      radius = 1.0,
      top_radius = 0.5,
      height = 2.0,
      segments = 8,
   }

   test.equal(cylinder.layout, "position_normal_color_uv_f32")
   test.equal(cylinder.index_count, 96)
   test.equal(cylinder.vertex_count, 36)
   test.equal(cylinder.index_type, "uint32")

   local vertices = float_data(cylinder.vertex_blob)
   -- First side vertex is at +X on the bottom ring.
   test.truthy(math.abs(vertices[0] - 1.0) < 1e-6)
   test.truthy(math.abs(vertices[1] + 1.0) < 1e-6)
   test.truthy(math.abs(vertices[2]) < 1e-6)
   -- Its normal points outward and slightly upward for this truncated cone.
   test.truthy(vertices[3] > 0.0)
   test.truthy(vertices[4] > 0.0)
end)

test.case("mesh arch helpers emit striped voussoirs and indexed geometry", function()
   local arch = mesh.make_voussoir_band {
      radius = 1.0,
      thickness = 0.2,
      depth = 0.3,
      segments = 4,
   }

   test.equal(arch.layout, "position_normal_color_uv_f32")
   test.equal(arch.vertex_count, 96)
   test.equal(arch.index_count, 144)
   test.equal(arch.index_type, "uint32")

   local vertices = float_data(arch.vertex_blob)
   local floats_per_vertex = arch.vertex_stride / 4
   -- First segment starts red; second segment starts cream.
   test.truthy(math.abs(vertices[6] - 150 / 255) < 1e-6)
   test.truthy(math.abs(vertices[7] - 48 / 255) < 1e-6)
   test.truthy(math.abs(vertices[8] - 38 / 255) < 1e-6)
   local second = 24 * floats_per_vertex + 6
   test.truthy(math.abs(vertices[second] - 226 / 255) < 1e-6)
   test.truthy(math.abs(vertices[second + 1] - 207 / 255) < 1e-6)
   test.truthy(math.abs(vertices[second + 2] - 174 / 255) < 1e-6)

   local round = mesh.make_round_arch { segments = 4 }
   local horseshoe = mesh.make_horseshoe_arch { segments = 4 }
   test.equal(round.vertex_count, 96)
   test.equal(horseshoe.vertex_count, 96)

   local pointed = mesh.make_pointed_arch {
      span = 4.0,
      radius = 2.6,
      thickness = 0.3,
      depth = 0.4,
      segments = 8,
   }
   test.equal(pointed.layout, "position_normal_color_uv_f32")
   test.truthy(pointed.vertex_count > 0)
   test.truthy(pointed.index_count > 0)
   test.falsey(pcall(function()
      mesh.make_pointed_arch { span = 4.0, radius = 1.9 }
   end))
end)

test.case("mesh.make_wall cuts openings and adds reveals", function()
   local wall = mesh.make_wall {
      width = 4.0,
      height = 3.0,
      thickness = 0.2,
      openings = {
         { x = 1.0, y = 1.0, width = 1.0, height = 1.0 },
      },
   }

   test.equal(wall.layout, "position_normal_color_uv_f32")
   test.equal(wall.vertex_count, 96)
   test.equal(wall.index_count, 144)
   test.equal(wall.index_type, "uint32")

   local ok, err = pcall(function()
      mesh.make_wall {
         width = 2.0,
         height = 2.0,
         openings = { { x = 1.5, y = 0.5, width = 1.0, height = 1.0 } },
      }
   end)
   test.falsey(ok)
   test.match(tostring(err), "outside the wall")
end)

test.case("mesh.make_grille builds a framed bar field and validates sizes", function()
   local grille = mesh.make_grille {
      width = 2.0,
      height = 2.0,
      depth = 0.1,
      frame_size = 0.1,
      bar_size = 0.05,
      spacing = 0.2,
      rails = 1,
   }

   test.equal(grille.layout, "position_normal_color_uv_f32")
   test.equal(grille.index_type, "uint32")
   -- Four frame boxes, nine vertical bars, one horizontal rail.
   test.equal(grille.vertex_count, 14 * 24)
   test.equal(grille.index_count, 14 * 36)

   test.falsey(pcall(function()
      mesh.make_grille { width = 0.1, height = 2.0, frame_size = 0.1 }
   end))
end)

test.case("mesh.make_railing spaces balusters between base and cap rails", function()
   local railing = mesh.make_railing {
      length = 2.0,
      height = 1.0,
      base_height = 0.1,
      cap_height = 0.1,
      spacing = 0.5,
   }

   test.equal(railing.layout, "position_normal_color_uv_f32")
   test.equal(railing.index_type, "uint32")
   -- Two box rails and four uncapped eight-segment baluster cylinders.
   test.equal(railing.vertex_count, 2 * 24 + 4 * 18)
   test.equal(railing.index_count, 2 * 36 + 4 * 48)

   test.falsey(pcall(function()
      mesh.make_railing { height = 0.2, base_height = 0.1, cap_height = 0.1 }
   end))
end)

test.case("mesh.make_pew emits seat, back, panels, and kneelers", function()
   local pew = mesh.make_pew { length = 1.8 }

   test.equal(pew.layout, "position_normal_color_uv_f32")
   test.equal(pew.index_type, "uint32")
   -- Seat, back, two end panels, and two kneeler rails.
   test.equal(pew.vertex_count, 6 * 24)
   test.equal(pew.index_count, 6 * 36)

   local plain = mesh.make_pew { length = 1.8, kneeler = false }
   test.equal(plain.vertex_count, 4 * 24)

   test.falsey(pcall(function()
      mesh.make_pew { seat_height = 0.5, back_height = 0.4 }
   end))
end)

test.case("mesh.make_floor_bay builds an indexed XZ grid", function()
   local floor = mesh.make_floor_bay {
      width = 4.0,
      depth = 2.0,
      segments = 2,
   }

   test.equal(floor.layout, "position_normal_color_uv_f32")
   test.equal(floor.vertex_count, 9)
   test.equal(floor.index_count, 24)
   test.equal(floor.index_type, "uint32")

   local vertices = float_data(floor.vertex_blob)
   test.equal(vertices[3], 0)
   test.equal(vertices[4], 1)
   test.equal(vertices[5], 0)
end)

test.case("mesh.make_barrel_vault emits a hollow indexed shell", function()
   local vault = mesh.make_barrel_vault {
      radius = 2.0,
      thickness = 0.2,
      length = 3.0,
      segments = 8,
   }

   test.equal(vault.layout, "position_normal_color_uv_f32")
   test.equal(vault.vertex_count, 136)
   test.equal(vault.index_count, 204)
   test.equal(vault.index_type, "uint32")
end)

test.case("mesh.make_dome emits outer, inner, and rim surfaces", function()
   local dome = mesh.make_dome {
      radius = 4.0,
      height = 3.0,
      thickness = 0.4,
      segments = 4,
      rings = 2,
   }

   test.equal(dome.layout, "position_normal_color_uv_f32")
   test.equal(dome.index_type, "uint32")
   -- Segments * rings * (outer + inner) quads, plus one rim quad per segment.
   test.equal(dome.vertex_count, 4 * 2 * 2 * 4 + 4 * 4)
   test.equal(dome.index_count, 4 * 2 * 2 * 6 + 4 * 6)

   test.falsey(pcall(function()
      mesh.make_dome { radius = 1.0, thickness = 1.0 }
   end))
end)

test.case("mesh.partition splits a mesh by triangle centroid", function()
   local merged = mesh.merge {
      { mesh = mesh.make_box { width = 1.0, height = 1.0, depth = 1.0 } },
      {
         mesh = mesh.make_box { width = 1.0, height = 1.0, depth = 1.0 },
         transform = require("mathx").mat4_translation(require("mathx").mat4(), 4.0, 0.0, 0.0),
      },
   }

   local buckets, order = mesh.partition(merged, function(x)
      if x < 2.0 then
         return "left"
      end
      return "right"
   end)

   test.equal(#order, 2)
   test.equal(order[1], "left")
   test.equal(order[2], "right")
   test.equal(buckets.left.layout, merged.layout)
   test.equal(buckets.left.vertex_count, 24)
   test.equal(buckets.left.index_count, 36)
   test.equal(buckets.right.vertex_count, 24)
   test.equal(buckets.right.index_count, 36)

   -- Triangles can be dropped by returning nil.
   local dropped = mesh.partition(merged, function()
      return nil
   end)
   test.equal(#dropped, 0)
end)

test.case("mesh.builder merges sections, transforms, and material ranges", function()
   local mathx = require("mathx")
   local builder = mesh.builder()
   local transform = mathx.mat4_translation(mathx.mat4(), 2.0, 0.0, 0.0)

   builder:add(
      mesh.make_box { width = 1.0, height = 1.0, depth = 1.0 },
      { name = "first", material = "stone", transform = transform }
   )
   builder:add(
      mesh.make_box { width = 1.0, height = 1.0, depth = 1.0 },
      { name = "second", material = "brick" }
   )

   local merged = builder:build()
   test.equal(merged.layout, "position_normal_color_uv_f32")
   test.equal(merged.vertex_count, 48)
   test.equal(merged.index_count, 72)
   test.equal(#merged.material_ranges, 2)

   test.equal(merged.material_ranges[1].name, "first")
   test.equal(merged.material_ranges[1].material, "stone")
   test.equal(merged.material_ranges[1].index_offset, 0)
   test.equal(merged.material_ranges[1].index_count, 36)
   test.equal(merged.material_ranges[1].vertex_offset, 0)
   test.equal(merged.material_ranges[1].vertex_count, 24)

   test.equal(merged.material_ranges[2].name, "second")
   test.equal(merged.material_ranges[2].material, "brick")
   test.equal(merged.material_ranges[2].index_offset, 36)
   test.equal(merged.material_ranges[2].index_count, 36)
   test.equal(merged.material_ranges[2].vertex_offset, 24)

   local vertices = float_data(merged.vertex_blob)
   test.truthy(math.abs(vertices[0] - 1.5) < 1e-6)
   local indices = index_data(merged.index_blob)
   test.equal(indices[36], 24)
end)

test.case("mesh.builder generates normals and optional tangents", function()
   local builder = mesh.builder { tangents = true }
   builder:add(mesh.make_quad { size = 2.0 })
   local merged = builder:build()

   test.equal(merged.layout, "position_normal_tangent_color_uv_f32")
   test.equal(merged.vertex_stride, 60)
   test.equal(merged.attribute_offsets.normal, 12)
   test.equal(merged.attribute_offsets.tangent, 24)

   local vertices = float_data(merged.vertex_blob)
   -- make_quad faces +Z, so the generated normal is (0, 0, 1).
   test.truthy(math.abs(vertices[3]) < 1e-6)
   test.truthy(math.abs(vertices[4]) < 1e-6)
   test.truthy(math.abs(vertices[5] - 1.0) < 1e-6)
   -- Its UV-aligned tangent is +X with the standard handedness.
   test.truthy(vertices[6] > 0.9)
   test.equal(vertices[9], 1)
end)

test.case("mesh.builder can produce the unlit layout", function()
   local builder = mesh.builder { normals = false }
   builder:add(mesh.make_quad { size = 2.0 })
   local merged = builder:build()

   test.equal(merged.layout, "position_color_uv_f32")
   test.equal(merged.vertex_stride, 32)
   test.equal(merged.attribute_offsets.normal, nil)
end)

test.case("mesh.merge and builder reject invalid inputs", function()
   local merged = mesh.merge {
      { mesh = mesh.make_quad {}, material = "a" },
      { mesh = mesh.make_quad {}, material = "b" },
   }
   test.equal(#merged.material_ranges, 2)

   local ok, err = pcall(function()
      mesh.merge { { mesh = mesh.make_line {} } }
   end)
   test.falsey(ok)
   test.match(tostring(err), "only accepts triangle meshes")

   local empty = mesh.builder()
   ok, err = pcall(function()
      empty:build()
   end)
   test.falsey(ok)
   test.match(tostring(err), "no geometry")
end)

test.case("mesh.make_line_segments does not connect separate segments", function()
   local lines = mesh.make_line_segments {
      points = {
         { 0.0, 0.0, 0.0 },
         { 1.0, 0.0, 0.0 },
         { 5.0, 0.0, 0.0 },
         { 6.0, 0.0, 0.0 },
      },
   }

   test.equal(lines.layout, "position_color_f32")
   test.equal(lines.topology, "lines")
   test.equal(lines.vertex_count, 4)
end)
