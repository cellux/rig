local ffi = require("ffi")
local shadercross = require("shadercross")
local test = require("test")

test.case("shadercross.compile_spirv_from_hlsl validates options through schema", function()
   local missing_source_ok, missing_source_err = pcall(function()
      shadercross.compile_spirv_from_hlsl({
         shader_stage = "vertex",
      })
   end)
   test.falsey(missing_source_ok)
   test.match(
      tostring(missing_source_err),
      "compile_spirv_from_hlsl options%.source expects a string"
   )

   local bad_defines_ok, bad_defines_err = pcall(function()
      shadercross.compile_spirv_from_hlsl({
         source = "float4 main() : SV_Target { return 0; }",
         shader_stage = "fragment",
         defines = "bad",
      })
   end)
   test.falsey(bad_defines_ok)
   test.match(
      tostring(bad_defines_err),
      "compile_spirv_from_hlsl options%.defines expects a define array or string%-to%-string map"
   )
end)

test.case("shadercross.compile_graphics_shader_from_spirv validates resource_info through schema", function()
   local bad_ok, bad_err = pcall(function()
      shadercross.compile_graphics_shader_from_spirv({
         device = ffi.new("uint8_t[1]"),
         bytecode = "spirv",
         resource_info = {
            num_samplers = "bad",
         },
      })
   end)
   test.falsey(bad_ok)
   test.match(
      tostring(bad_err),
      "compile_graphics_shader_from_spirv options%.resource_info%.num_samplers expects a number"
   )
end)

test.case("shadercross.compile_compute_pipeline_from_spirv validates metadata through schema", function()
   local bad_ok, bad_err = pcall(function()
      shadercross.compile_compute_pipeline_from_spirv({
         device = ffi.new("uint8_t[1]"),
         bytecode = "spirv",
         metadata = {
            threadcount_x = "bad",
         },
      })
   end)
   test.falsey(bad_ok)
   test.match(
      tostring(bad_err),
      "compile_compute_pipeline_from_spirv options%.metadata%.threadcount_x expects a number"
   )
end)
