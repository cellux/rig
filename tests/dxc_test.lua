local dxc = require("dxc")
local test = require("test")

test.case("dxc.compile_spirv validates options through schema", function()
   local missing_source_ok, missing_source_err = pcall(function()
      dxc.compile_spirv {
         stage = dxc.SHADERSTAGE_VERTEX,
      }
   end)
   test.falsey(missing_source_ok)
   test.match(
      tostring(missing_source_err),
      "dxc%.compile_spirv options%.source expects a string"
   )

   local bad_args_ok, bad_args_err = pcall(function()
      dxc.compile_spirv {
         source = "float4 main() : SV_Target { return 0; }",
         extra_args = { "-Zi", 1 },
      }
   end)
   test.falsey(bad_args_ok)
   test.match(
      tostring(bad_args_err),
      "dxc%.compile_spirv options%.extra_args%[2%] expects a string"
   )
end)
