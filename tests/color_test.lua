local test = require("test")
local color = require("color")
local ffi = require("ffi")

local function approx(actual, expected)
   return math.abs(actual - expected) < 1e-12
end

test.case("color module constructs rgba8 colors", function()
   local value = color.Color(6, 8, 18)

   test.truthy(ffi.istype(color.Color, value))
   test.equal(value.r, 6)
   test.equal(value.g, 8)
   test.equal(value.b, 18)
   test.equal(value.a, 255)
   test.equal(value[1], nil)
   test.truthy(color.is(value))
   test.equal(color.WHITE, color.rgb(255, 255, 255))
   test.equal(color.BLACK, color.rgb(0, 0, 0))
   test.equal(color.TRANSPARENT, color.rgba(0, 0, 0, 0))
end)

test.case("color module accepts table and hex constructors", function()
   local from_array = color.Color({ 6, 8, 18, 128 })
   local from_named = color.Color({
      r = 6,
      g = 8,
      b = 18,
      a = 128,
   })
   local from_hex = color.hex("#06081280")

   test.equal(from_array, from_named)
   test.equal(from_named, from_hex)
   test.equal(rig.tostring(from_hex), "Color(6, 8, 18, 128)")
end)

test.case("__eq handles non-color comparisons safely", function()
   local value = color.rgba(6, 8, 18, 128)

   test.falsey(value == nil)
   test.falsey(value == false)
   test.falsey(value == 0)
   test.falsey(value == {})
   test.truthy(value == color.rgba(6, 8, 18, 128))
   test.falsey(value == color.rgba(6, 8, 18, 255))
end)

test.case("color module exposes float and packed conversions", function()
   local value = color.rgbaf(6 / 255.0, 8 / 255.0, 18 / 255.0, 0.5)
   local r, g, b, a = value:to_rgba()
   local rf, gf, bf, af = value:to_rgbaf()

   test.equal(r, 6)
   test.equal(g, 8)
   test.equal(b, 18)
   test.equal(a, 128)
   test.truthy(approx(rf, 6 / 255.0))
   test.truthy(approx(gf, 8 / 255.0))
   test.truthy(approx(bf, 18 / 255.0))
   test.truthy(approx(af, 128 / 255.0))
   test.equal(value:to("rgb")[1], 6)
   test.equal(value:to("rgba")[4], 128)
   test.truthy(approx(value:to("rgbf")[2], 8 / 255.0))
   test.truthy(approx(value:to("rgbaf")[4], 128 / 255.0))
   test.equal(value:to("hex_rgb"), "#060812")
   test.equal(value:to("hex"), "#06081280")
   test.equal(value:to("u32_rgba"), 0x06081280)
   test.equal(value:to("u32_argb"), 0x80060812)
   test.equal(value:to("u32_abgr"), 0x80120806)
   test.equal(value:to("u32_bgra"), 0x12080680)
end)

test.case("color module round-trips supported formats through factories", function()
   local rgba = color.from({
      6,
      8,
      18,
      128,
   }, "rgba")
   local rgbf = color.from({
      6 / 255.0,
      8 / 255.0,
      18 / 255.0,
   }, "rgbf")
   local packed = color.u32_argb(0x80060812)

   test.equal(rgba, color.hex("#06081280"))
   test.equal(rgbf, color.rgba(6, 8, 18, 255))
   test.equal(packed, rgba)
   test.equal(rgba:to("hex"), "#06081280")
   test.equal(rgba:to("u32_rgba"), 0x06081280)
   test.equal(rgba:to("rgba")[3], 18)
   test.truthy(approx(rgba:to("rgbaf")[4], 128 / 255.0))
end)

test.case("color module supports mutation, copies, and buffer writes", function()
   local value = color.Color("#060812")
   local copy = value:copy():with_alpha(80)
   local buffer = ffi.new("uint8_t[8]")
   local ok = pcall(function()
      value[2] = 9
   end)

   test.falsey(ok)
   value.g = 9
   value.a = 64
   value:setf(0.5, 0.25, 0.0, 1.0)
   value:write_rgba8(buffer, 2)

   test.equal(copy.r, 6)
   test.equal(copy.g, 8)
   test.equal(copy.b, 18)
   test.equal(copy.a, 80)
   test.equal(value.r, 128)
   test.equal(value.g, 64)
   test.equal(value.b, 0)
   test.equal(value.a, 255)
   test.equal(buffer[2], 128)
   test.equal(buffer[3], 64)
   test.equal(buffer[4], 0)
   test.equal(buffer[5], 255)
   test.equal(value:to("rgba")[1], 128)
   test.truthy(value:is_opaque())
end)

test.case("color module mixes colors into an output instance", function()
   local out = color.TRANSPARENT:copy()
   local first = color.rgba(16, 32, 64, 96)
   local second = color.rgba(240, 224, 192, 160)
   local mixed = first:mix(second, 0.25)

   test.equal(mixed, color.rgba(72, 80, 96, 112))
   test.equal(first, color.rgba(16, 32, 64, 96))
   test.falsey(mixed == first)
   test.equal(out:set_mix(first, second, 0.25), out)
   test.equal(out, color.rgba(72, 80, 96, 112))

   out:set_mix(first, second, -1)
   test.equal(out, first)

   out:set_mix(first, second, 2)
   test.equal(out, second)
end)
