local test = require("test")
local shader = require("shader")

local function fake_provider(record)
   return {
      create_stage = function(spec)
         record.seen_spec = spec
         return {
            fake_stage = true,
            stage = spec.stage,
         }
      end,
      destroy_stage = function(stage)
         record.destroyed_stage = stage
      end,
   }
end

test.case("shader.create_stage normalizes source specs before provider dispatch", function()
   local record = {}
   local provider = fake_provider(record)

   local stage = shader.create_stage({
      language = "glsl",
      stage = "vertex",
      source_name = "shader_test.vert.glsl",
      source = "void main() {}",
   }, provider)

   test.truthy(stage.fake_stage)
   shader.destroy_stage(stage, provider)

   local seen_spec = record.seen_spec
   test.truthy(type(seen_spec) == "table")
   test.equal(seen_spec.artifact_kind, "source")
   test.equal(seen_spec.language, "glsl")
   test.equal(seen_spec.stage, "vertex")
   test.equal(seen_spec.source_name, "shader_test.vert.glsl")
   test.equal(seen_spec.source, "void main() {}")
   test.truthy(type(record.destroyed_stage) == "table")
   test.truthy(record.destroyed_stage.fake_stage)
end)

test.case("shader.create_stage validates source specs through schema", function()
   local record = {}
   local provider = fake_provider(record)

   local ok, err = pcall(function()
      shader.create_stage({
         language = "glsl",
         stage = "vertex",
         source = "void main() {}",
         extra_args = "bad",
      }, provider)
   end)

   test.falsey(ok)
   test.match(tostring(err), "shader operation%.extra_args expects a table")
end)

test.case("shader.create_stage requires a provider", function()
   local ok, err = pcall(function()
      shader.create_stage({
         language = "glsl",
         stage = "vertex",
         source = "void main() {}",
      })
   end)

   test.falsey(ok)
   test.match(tostring(err), "requires a shader%.stage provider")
end)
