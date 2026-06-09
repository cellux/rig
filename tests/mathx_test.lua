local ffi = require("ffi")
local mathx = require("mathx")
local test = require("test")

local function approx_equal(actual, expected, epsilon, label)
   epsilon = epsilon or 1e-6
   test.truthy(
      math.abs(actual - expected) <= epsilon,
      string.format(
         "%s\nexpected: %.9f\nactual:   %.9f",
         label or "expected values to be approximately equal",
         expected,
         actual
      )
   )
end

local function assert_mat4(mat, expected, label)
   for i = 1, 16 do
      approx_equal(
         tonumber(mat[i - 1]),
         expected[i],
         1e-6,
         string.format("%s at index %d", label, i - 1)
      )
   end
end

local function assert_vec3(vec, expected, label)
   for i = 1, 3 do
      approx_equal(
         tonumber(vec[i - 1]),
         expected[i],
         1e-6,
         string.format("%s at index %d", label, i - 1)
      )
   end
end

test.case("mathx constructors allocate zeroed ffi arrays", function()
   local mat = mathx.mat4()
   local vec = mathx.vec3()

   test.equal(type(mat), "cdata")
   test.equal(type(vec), "cdata")
   test.match(tostring(ffi.typeof(mat)), "float %[%d+%]")
   test.match(tostring(ffi.typeof(vec)), "float %[%d+%]")

   assert_mat4(mat, {
      0, 0, 0, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
   }, "mathx.mat4 returns a zeroed matrix")
   assert_vec3(vec, { 0, 0, 0 }, "mathx.vec3 returns a zeroed vector")
   assert_vec3(
      mathx.vec3(1.25, -2.5, 3.75),
      { 1.25, -2.5, 3.75 },
      "mathx.vec3 applies initial values"
   )
end)

test.case("mathx scalar helpers cover common interpolation and clamping", function()
   test.equal(mathx.clamp(-2, 0, 10), 0)
   test.equal(mathx.clamp(12, 0, 10), 10)
   test.equal(mathx.clamp(4, 0, 10), 4)
   test.equal(mathx.clamp01(-0.5), 0.0)
   test.equal(mathx.clamp01(1.5), 1.0)
   approx_equal(mathx.clamp01(0.25), 0.25, 1e-6, "clamp01 preserves in-range values")
   approx_equal(mathx.lerp(10, 20, 0.25), 12.5, 1e-6, "lerp interpolates linearly")
end)

test.case("mathx matrix helpers produce the documented layouts", function()
   local out = mathx.mat4()
   local src = mathx.mat4()

   mathx.mat4_identity(src)
   src[0] = 9
   src[5] = 8
   src[10] = 7
   src[15] = 6

   assert_mat4(mathx.mat4_identity(out), {
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
   }, "mat4_identity")

   assert_mat4(mathx.mat4_copy(out, src), {
      9, 0, 0, 0,
      0, 8, 0, 0,
      0, 0, 7, 0,
      0, 0, 0, 6,
   }, "mat4_copy")

   assert_mat4(mathx.mat4_translation(out, 2, 3, 4), {
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      2, 3, 4, 1,
   }, "mat4_translation")

   assert_mat4(mathx.mat4_scale(out, 2, 3, 4), {
      2, 0, 0, 0,
      0, 3, 0, 0,
      0, 0, 4, 0,
      0, 0, 0, 1,
   }, "mat4_scale")

   assert_mat4(mathx.mat4_rotation_x(out, math.pi * 0.5), {
      1, 0, 0, 0,
      0, 0, 1, 0,
      0, -1, 0, 0,
      0, 0, 0, 1,
   }, "mat4_rotation_x")

   assert_mat4(mathx.mat4_rotation_y(out, math.pi * 0.5), {
      0, 0, -1, 0,
      0, 1, 0, 0,
      1, 0, 0, 0,
      0, 0, 0, 1,
   }, "mat4_rotation_y")

   assert_mat4(mathx.mat4_rotation_z(out, math.pi * 0.5), {
      0, 1, 0, 0,
      -1, 0, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
   }, "mat4_rotation_z")
end)

test.case("mathx mat4_multiply supports expected composition and aliasing", function()
   local a = mathx.mat4()
   local b = mathx.mat4()
   local out = mathx.mat4()

   mathx.mat4_translation(a, 2, 3, 4)
   mathx.mat4_scale(b, 5, 6, 7)

   assert_mat4(mathx.mat4_multiply(out, a, b), {
      5, 0, 0, 0,
      0, 6, 0, 0,
      0, 0, 7, 0,
      10, 18, 28, 1,
   }, "mat4_multiply composition")

   mathx.mat4_translation(a, 2, 3, 4)
   mathx.mat4_scale(b, 5, 6, 7)
   assert_mat4(mathx.mat4_multiply(a, a, b), {
      5, 0, 0, 0,
      0, 6, 0, 0,
      0, 0, 7, 0,
      10, 18, 28, 1,
   }, "mat4_multiply aliasing with out == a")

   mathx.mat4_translation(a, 2, 3, 4)
   mathx.mat4_scale(b, 5, 6, 7)
   assert_mat4(mathx.mat4_multiply(b, a, b), {
      5, 0, 0, 0,
      0, 6, 0, 0,
      0, 0, 7, 0,
      10, 18, 28, 1,
   }, "mat4_multiply aliasing with out == b")
end)

test.case("mathx camera and projection helpers return expected canonical matrices", function()
   local out = mathx.mat4()
   local eye = mathx.vec3()
   local target = mathx.vec3()
   local up = mathx.vec3(0, 1, 0)

   mathx.vec3_set(eye, 0, 0, -5)
   mathx.vec3_set(target, 0, 0, 0)
   assert_mat4(mathx.mat4_look_at_lh(out, eye, target, up), {
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 5, 1,
   }, "mat4_look_at_lh")

   mathx.vec3_set(eye, 0, 0, 5)
   mathx.vec3_set(target, 0, 0, 0)
   assert_mat4(mathx.mat4_look_at_rh(out, eye, target, up), {
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, -5, 1,
   }, "mat4_look_at_rh")

   assert_mat4(mathx.mat4_perspective_lh(out, math.pi * 0.5, 2, 1, 11), {
      0.5, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1.1, 1,
      0, 0, -1.1, 0,
   }, "mat4_perspective_lh")

   assert_mat4(mathx.mat4_perspective_rh(out, math.pi * 0.5, 2, 1, 11), {
      0.5, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, -1.1, -1,
      0, 0, -1.1, 0,
   }, "mat4_perspective_rh")
end)

test.case("mathx vector helpers cover arithmetic and normalization behavior", function()
   local a = mathx.vec3(3, 4, 0)
   local b = mathx.vec3(1, 2, 3)
   local out = mathx.vec3()

   assert_vec3(mathx.vec3_set(out, -1, -2, -3), { -1, -2, -3 }, "vec3_set")
   assert_vec3(mathx.vec3_copy(out, a), { 3, 4, 0 }, "vec3_copy")

   approx_equal(mathx.vec3_dot(a, b), 11, 1e-6, "vec3_dot")
   approx_equal(mathx.vec3_length_squared(a), 25, 1e-6, "vec3_length_squared")
   approx_equal(mathx.vec3_length(a), 5, 1e-6, "vec3_length")

   assert_vec3(mathx.vec3_subtract(out, a, b), { 2, 2, -3 }, "vec3_subtract")
   assert_vec3(mathx.vec3_cross(out, a, b), { 12, -9, 2 }, "vec3_cross")
   assert_vec3(mathx.vec3_normalize(out, a), { 0.6, 0.8, 0.0 }, "vec3_normalize")

   assert_vec3(
      mathx.vec3_normalize(out, mathx.vec3(0, 0, 0)),
      { 0, 0, 0 },
      "vec3_normalize zero vector"
   )
end)

test.case("mathx validates cdata inputs and rejects degenerate look-at vectors", function()
   local mat = mathx.mat4()
   local vec = mathx.vec3(0, 1, 0)

   local ok, err = pcall(function()
      mathx.mat4_identity({})
   end)
   test.falsey(ok)
   test.match(tostring(err), "float%[16%] cdata matrix")

   ok, err = pcall(function()
      mathx.vec3_dot({}, vec)
   end)
   test.falsey(ok)
   test.match(tostring(err), "float%[3%] cdata vector")

   ok, err = pcall(function()
      mathx.mat4_look_at_lh(mat, mathx.vec3(1, 1, 1), mathx.vec3(1, 1, 1), vec)
   end)
   test.falsey(ok)
   test.match(tostring(err), "zero%-length vector")

   ok, err = pcall(function()
      mathx.mat4_look_at_rh(
         mat,
         mathx.vec3(0, 0, 5),
         mathx.vec3(0, 0, 0),
         mathx.vec3(0, 0, 1)
      )
   end)
   test.falsey(ok)
   test.match(tostring(err), "cross%(up, forward%)")
end)
