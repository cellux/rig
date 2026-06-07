local M = ... or {}

local rig = require("rig")
local schema = require("schema")
local dxc = require("dxc")
local shaderc = require("shaderc")
local spirvcross = require("spirvcross")

local non_empty_string_schema = schema.non_empty_string()
local source_artifact_options_schema = schema.record({
   language = schema.enum({ "hlsl", "glsl" }):optional("hlsl"),
   stage = schema.enum({ "vertex", "fragment", "compute" }),
   source = schema.string():optional(),
   path = non_empty_string_schema:optional(),
   source_name = schema.string():optional(),
   entrypoint = schema.string():optional(),
   extra_args = schema.array(schema.string()):optional(),
   preserve_bindings = schema.boolean():optional(),
   preserve_interface = schema.boolean():optional(),
   glsl_version = schema.integer {
      min = 0,
   }:optional(),
   optimization = schema.string():optional(),
   debug_info = schema.boolean():optional(),
   macro_definitions = schema.map(non_empty_string_schema, schema.any()):optional(),
   props = schema.any():optional(),
})

local stage_artifact_spec_schema = schema.record({
   artifact_kind = non_empty_string_schema:optional(),
}, {
   allow_extra = true,
})

local function read_file(path)
   local file, open_err = io.open(path, "rb")
   if file == nil then
      return nil, ("failed to open '%s': %s"):format(
         path,
         tostring(open_err or "unknown error")
      )
   end

   local contents, read_err = file:read("*all")
   file:close()
   if contents == nil then
      return nil, ("failed to read '%s': %s"):format(
         path,
         tostring(read_err or "unknown error")
      )
   end

   return contents
end

local function load_source(options)
   if type(options.source) == "string" then
      return options.source, options.path == nil and options.source_name or options.path
   end
   if type(options.path) == "string" then
      local source, err = read_file(options.path)
      if source == nil then
         return nil, err
      end
      return source, options.path
   end
   return nil, "shader source must be provided via source or path"
end

local function normalize_source_artifact(options)
   local normalized = schema.assert(
      source_artifact_options_schema,
      options,
      "shader operation"
   )

   local source, source_name_or_err = load_source(normalized)
   if source == nil then
      error(source_name_or_err, 0)
   end

   local source_name = normalized.source_name or source_name_or_err
   if type(source_name) ~= "string" or source_name == "" then
      if normalized.language == "hlsl" then
         source_name = "shader.hlsl"
      else
         source_name = "shader.glsl"
      end
   end

   return {
      artifact_kind = "source",
      language = normalized.language,
      stage = normalized.stage,
      source = source,
      source_name = source_name,
      entrypoint = normalized.entrypoint,
      extra_args = normalized.extra_args,
      preserve_bindings = normalized.preserve_bindings,
      preserve_interface = normalized.preserve_interface,
      glsl_version = normalized.glsl_version,
      optimization = normalized.optimization,
      debug_info = normalized.debug_info,
      macro_definitions = normalized.macro_definitions,
      props = normalized.props,
   }
end

local function normalize_stage_artifact(spec)
   local normalized = schema.assert(
      stage_artifact_spec_schema,
      spec,
      "shader stage specification"
   )

   if normalized.artifact_kind ~= nil then
      return normalized
   end

   return normalize_source_artifact(normalized)
end

function M.compile(options)
   local source_artifact = normalize_source_artifact(options)

   local compiled
   local compile_err
   if source_artifact.language == "hlsl" then
      compiled, compile_err = dxc.compile_spirv {
         source = source_artifact.source,
         stage = source_artifact.stage,
         entrypoint = source_artifact.entrypoint,
         source_name = source_artifact.source_name,
         extra_args = source_artifact.extra_args,
         preserve_bindings = source_artifact.preserve_bindings,
         preserve_interface = source_artifact.preserve_interface,
      }
   else
      compiled, compile_err = shaderc.compile_spirv {
         source = source_artifact.source,
         stage = source_artifact.stage,
         entrypoint = source_artifact.entrypoint,
         source_name = source_artifact.source_name,
         glsl_version = source_artifact.glsl_version,
         optimization = source_artifact.optimization,
         debug_info = source_artifact.debug_info,
         preserve_bindings = source_artifact.preserve_bindings,
         macro_definitions = source_artifact.macro_definitions,
      }
   end
   if compiled == nil then
      error(tostring(compile_err or "shader compilation failed"), 0)
   end

   local reflection, reflection_err = spirvcross.reflect_spirv(compiled)
   if reflection == nil then
      error(tostring(reflection_err or "SPIR-V reflection failed"), 0)
   end

   return {
      artifact_kind = "spirv",
      source_language = source_artifact.language,
      language = source_artifact.language,
      stage = source_artifact.stage,
      entrypoint = compiled.entrypoint or source_artifact.entrypoint or "main",
      source_name = source_artifact.source_name,
      bytecode = compiled.bytecode,
      format = "spirv",
      reflection = reflection,
      props = source_artifact.props,
   }
end

rig.create_service("shader.stage", {
   "create_stage",
   "destroy_stage",
})

function M.create_stage(spec)
   return rig.require_service("shader.stage").create_stage(
      normalize_stage_artifact(spec)
   )
end

function M.destroy_stage(stage)
   return rig.require_service("shader.stage").destroy_stage(stage)
end

return M
