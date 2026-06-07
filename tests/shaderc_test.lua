local shaderc = require("shaderc")
local test = require("test")

test.case("shaderc.compile_spirv validates options through schema", function()
   local missing_stage_ok, missing_stage_err = pcall(function()
      shaderc.compile_spirv {
         source = "void main() {}",
      }
   end)
   test.falsey(missing_stage_ok)
   test.match(
      tostring(missing_stage_err),
      "shaderc%.compile_spirv options%.stage expects one of vertex, fragment, compute"
   )

   local bad_macros_ok, bad_macros_err = pcall(function()
      shaderc.compile_spirv {
         source = "void main() {}",
         stage = shaderc.SHADERSTAGE_VERTEX,
         macro_definitions = "bad",
      }
   end)
   test.falsey(bad_macros_ok)
   test.match(
      tostring(bad_macros_err),
      "shaderc%.compile_spirv options%.macro_definitions expects a table"
   )
end)
