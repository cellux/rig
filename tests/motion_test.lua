local test = require("test")
local mathx = require("mathx")
local motion = require("motion")
local scene = require("scene")

local function near(a, b, eps)
   return math.abs(a - b) <= (eps or 1e-5)
end

local function identity()
   local m = mathx.mat4()
   mathx.mat4_identity(m)
   return m
end

local function assert_close_to_identity(value)
   local expect = identity()
   for i = 0, 15 do
      test.truthy(near(value[i], expect[i]), "matrix index " .. tostring(i))
   end
end

test.case("motion.spin defaults match the classic demo spin", function()
   local m = motion.spin()

   test.equal(m.x, 0.7)
   test.equal(m.y, 1.0)
   test.equal(m.z, 0.0)
end)

test.case("motion.spin is identity at time zero", function()
   local m = motion.spin { x = 0.7, y = 1.0 }
   local out = identity()

   m:contribute(out, nil, { time = 0.0 })
   assert_close_to_identity(out)
end)

test.case("motion.spin evaluates closed-form from frame time", function()
   local m = motion.spin { z = 1.0 }
   local out = identity()

   m:contribute(out, nil, { time = math.pi / 2 })

   test.truthy(near(out[0], 0.0))
   test.truthy(near(out[1], 1.0))
   test.truthy(near(out[4], -1.0))
   test.truthy(near(out[5], 0.0))
end)

test.case("motion anchor offsets local time", function()
   local m = motion.spin { z = 1.0 }

   m:set_anchor(math.pi / 2)

   local out = identity()
   m:contribute(out, nil, { time = math.pi })

   test.truthy(near(out[1], 1.0))
end)

test.case("node composes motions after the base local matrix", function()
   local node = scene.Node {}
   node:set_local_matrix(mathx.mat4_translation(mathx.mat4(), 1.0, 0.0, 0.0))
   node:add_motion(motion.spin { z = 1.0 })

   local out = mathx.mat4()
   node:build_local(out, { time = math.pi / 2 })

   test.truthy(near(out[12], 1.0))
   test.truthy(near(out[13], 0.0))
end)

test.case("node adds and removes motions", function()
   local node = scene.Node {}
   local m = motion.spin {}

   node:add_motion(m)
   test.equal(#node.motions, 1)

   test.equal(node:remove_motion(m), true)
   test.equal(node:remove_motion(m), false)
   test.equal(#node.motions, 0)
end)

test.case("node rejects motions without a contribute method", function()
   local node = scene.Node {}

   local ok = pcall(function()
      node:add_motion({})
   end)

   test.falsey(ok)
end)