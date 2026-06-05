local M = ... or {}

local rig = require("rig")
local dxc = require("dxc")
local shaderc = require("shaderc")
local spirvcross = require("spirvcross")

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

local function normalize_language(language)
   local normalized = language or "hlsl"
   if normalized ~= "hlsl" and normalized ~= "glsl" then
      error("shader operation currently supports only language='hlsl' or language='glsl'", 0)
   end
   return normalized
end

local function normalize_stage(stage)
   if stage ~= "vertex" and stage ~= "fragment" and stage ~= "compute" then
      error("shader operation requires stage to be 'vertex', 'fragment', or 'compute'", 0)
   end
   return stage
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
   if type(options) ~= "table" then
      error("shader operation expects a table", 0)
   end

   local language = normalize_language(options.language)
   local stage = normalize_stage(options.stage)
   local source, source_name_or_err = load_source(options)
   if source == nil then
      error(source_name_or_err, 0)
   end

   local source_name = options.source_name or source_name_or_err
   if type(source_name) ~= "string" or source_name == "" then
      if language == "hlsl" then
         source_name = "shader.hlsl"
      else
         source_name = "shader.glsl"
      end
   end

   return {
      artifact_kind = "source",
      language = language,
      stage = stage,
      source = source,
      source_name = source_name,
      entrypoint = options.entrypoint,
      extra_args = options.extra_args,
      preserve_bindings = options.preserve_bindings,
      preserve_interface = options.preserve_interface,
      glsl_version = options.glsl_version,
      optimization = options.optimization,
      debug_info = options.debug_info,
      macro_definitions = options.macro_definitions,
      props = options.props,
   }
end

local function normalize_stage_artifact(spec)
   if type(spec) ~= "table" then
      error("shader stage specification expects a table", 0)
   end

   if type(spec.artifact_kind) == "string" and spec.artifact_kind ~= "" then
      return spec
   end

   return normalize_source_artifact(spec)
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
