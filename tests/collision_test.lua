local test = require("test")
local collision = require("collision")

local function near(a, b, eps)
   return math.abs(a - b) <= (eps or 1e-4)
end

test.case("collision shape constructors compute bounds and outward edges", function()
   local circle = collision.circle { x = 1.0, z = 2.0, radius = 0.5 }
   test.equal(circle.type, "circle")
   test.equal(circle.min_x, 0.5)
   test.equal(circle.max_x, 1.5)
   test.equal(circle.min_z, 1.5)
   test.equal(circle.max_z, 2.5)

   local box = collision.box {
      x = 2.0,
      z = 3.0,
      width = 4.0,
      depth = 2.0,
      angle = math.rad(45),
   }
   test.equal(box.type, "box")
   test.truthy(box.min_x < box.max_x)
   test.truthy(box.min_z < box.max_z)

   local segment = collision.segment {
      from = { 0.0, -1.0 },
      to = { 0.0, 1.0 },
      thickness = 0.4,
   }
   test.equal(segment.radius, 0.2)
   test.equal(segment.min_x, -0.2)
   test.equal(segment.max_x, 0.2)

   local polygon = collision.polygon {
      points = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } },
   }
   test.equal(polygon.type, "polygon")
   test.equal(#polygon.edges, 4)
   test.truthy(near(polygon.edges[1].nx, 0.0))
   test.truthy(near(polygon.edges[1].nz, -1.0))
end)

test.case("collision rejects malformed shapes", function()
   test.falsey(pcall(function()
      collision.circle { x = 0, z = 0, radius = 0 }
   end))
   test.falsey(pcall(function()
      collision.segment { from = { 0, 0 }, to = { 0, 0 } }
   end))
   test.falsey(pcall(function()
      collision.polygon { points = { { 0, 0 }, { 1, 0 } } }
   end))
   test.falsey(pcall(function()
      collision.polygon { points = { { 0, 0 }, { 1, 0 }, { 2, 0 } } }
   end))
end)

test.case("collision sweep stops a circle at an AABB", function()
   local world = collision.world()
   world:add_box { x = 0.0, z = 0.0, width = 2.0, depth = 2.0 }

   local x, z, hit = world:sweep_circle(-2.0, 0.0, 10.0, 0.0, 0.3)
   test.truthy(hit)
   test.truthy(near(x, -1.3001))
   test.truthy(near(z, 0.0))
end)

test.case("collision sweep cannot tunnel through a thin wall", function()
   local world = collision.world()
   world:add_box { x = 0.0, z = 0.0, width = 0.2, depth = 10.0 }

   local x, z, hit = world:sweep_circle(-20.0, 0.0, 40.0, 0.0, 0.3)
   test.truthy(hit)
   test.truthy(near(x, -0.4001))
   test.truthy(near(z, 0.0))
end)

test.case("collision sweep slides along a wall", function()
   local world = collision.world()
   world:add_box { x = 0.0, z = 0.0, width = 2.0, depth = 20.0 }

   local x, z, hit = world:sweep_circle(-2.0, 0.0, 6.0, 3.0, 0.3)
   test.truthy(hit)
   test.truthy(near(x, -1.3001))
   test.truthy(near(z, 3.0))
end)

test.case("collision sweep handles circles, segments, and polygons", function()
   local circle_world = collision.world()
   circle_world:add_circle { x = 0.0, z = 0.0, radius = 1.0 }
   local x, z, hit = circle_world:sweep_circle(-3.0, 0.0, 10.0, 0.0, 0.3)
   test.truthy(hit)
   test.truthy(near(x, -1.3001))
   test.truthy(near(z, 0.0))

   local segment_world = collision.world()
   segment_world:add_segment {
      from = { 0.0, -2.0 },
      to = { 0.0, 2.0 },
      thickness = 0.2,
   }
   x, z, hit = segment_world:sweep_circle(-1.0, 0.0, 5.0, 0.0, 0.3)
   test.truthy(hit)
   test.truthy(near(x, -0.4001))

   local polygon_world = collision.world()
   polygon_world:add_polygon {
      points = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } },
   }
   x, z, hit = polygon_world:sweep_circle(-2.0, 0.0, 10.0, 0.0, 0.3)
   test.truthy(hit)
   test.truthy(near(x, -1.3001))
end)

test.case("collision resolves initial penetration", function()
   local world = collision.world()
   world:add_box { x = 0.0, z = 0.0, width = 2.0, depth = 2.0 }

   local x, z, resolved = world:resolve_circle(0.0, 0.0, 0.3)
   test.truthy(resolved)
   test.truthy(near(x, 0.0))
   test.truthy(near(math.abs(z), 1.3001))
end)

test.case("collision move updates array and field positions and capsules", function()
   local world = collision.world()
   world:add_box { x = 0.0, z = 0.0, width = 2.0, depth = 10.0 }

   local array_position = { -2.0, 0.0, 0.0 }
   world:move(array_position, 5.0, 0.0, { radius = 0.3 })
   test.truthy(near(array_position[1], -1.3001))
   test.truthy(near(array_position[3], 0.0))

   local field_position = { x = -2.0, z = 0.0 }
   world:move_capsule(
      field_position,
      5.0,
      0.0,
      { capsule = { radius = 0.4, height = 1.8 } }
   )
   test.truthy(near(field_position.x, -1.4001))
   test.truthy(near(field_position.z, 0.0))
end)

test.case("collision debug mesh emits disjoint line segments", function()
   local world = collision.world()
   world:add_box { x = 0.0, z = 0.0, width = 2.0, depth = 2.0 }
   world:add_circle { x = 4.0, z = 0.0, radius = 0.5 }

   local debug = world:debug_mesh { circle_segments = 8 }
   test.truthy(debug ~= nil)
   test.equal(debug.layout, "position_color_f32")
   test.equal(debug.topology, "lines")
   test.equal(debug.vertex_count, 4 * 2 + 8 * 2)
end)
