local test = require("test")
local shader = require("shader")

test.case("shader.create_stage normalizes source specs before service dispatch", function()
   local seen_spec = nil
   local destroyed_stage = nil

   rig.register_service_provider("shader.stage", "shader_test_provider", {
      create_stage = function(spec)
         seen_spec = spec
         return {
            fake_stage = true,
            stage = spec.stage,
         }
      end,
      destroy_stage = function(stage)
         destroyed_stage = stage
      end,
   })

   rig.register_runtime_driver("shader_test_driver", {
      loop = function()
         local stage = shader.create_stage {
            language = "glsl",
            stage = "vertex",
            source_name = "shader_test.vert.glsl",
            source = "void main() {}",
         }
         test.truthy(stage.fake_stage)
         shader.destroy_stage(stage)
      end,
   })

   rig.run {
      driver = "shader_test_driver",
      providers = {
         ["shader.stage"] = "shader_test_provider",
      },
   }

   test.truthy(type(seen_spec) == "table")
   test.equal(seen_spec.artifact_kind, "source")
   test.equal(seen_spec.language, "glsl")
   test.equal(seen_spec.stage, "vertex")
   test.equal(seen_spec.source_name, "shader_test.vert.glsl")
   test.equal(seen_spec.source, "void main() {}")
   test.truthy(type(destroyed_stage) == "table")
   test.truthy(destroyed_stage.fake_stage)
end)

test.case("shader.create_stage validates source specs through schema", function()
   rig.register_service_provider("shader.stage", "shader_test_provider_validation", {
      create_stage = function()
         error("create_stage should not be reached", 0)
      end,
      destroy_stage = function() end,
   })

   rig.register_runtime_driver("shader_test_validation_driver", {
      loop = function()
         shader.create_stage {
            language = "glsl",
            stage = "vertex",
            source = "void main() {}",
            extra_args = "bad",
         }
      end,
   })

   local ok, err = pcall(function()
      rig.run {
         driver = "shader_test_validation_driver",
         providers = {
            ["shader.stage"] = "shader_test_provider_validation",
         },
      }
   end)

   test.falsey(ok)
   test.match(tostring(err), "shader operation%.extra_args expects a table")
end)
