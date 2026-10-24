local rig = require("rig")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")

-- Shared backend selection for the examples. `RIG_BACKEND` picks the rendering
-- backend and defaults to `gl`:
--
--    RIG_BACKEND=renderer ./build/rig examples/<name>.lua
--    RIG_BACKEND=gl       ./build/rig examples/<name>.lua
--    RIG_BACKEND=gpu      ./build/rig examples/<name>.lua
--
-- Examples that need meshes/scene rendering pass `{ backends = { gl = true,
-- gpu = true } }` so selecting the renderer backend fails with a clear message.

local M = {}

local GL_ATTRIBUTES = {
   context_major_version = 4,
   context_minor_version = 5,
   context_profile = "core",
   doublebuffer = true,
   depth_size = 24,
}

local BACKENDS = {
   renderer = {
      label = "SDL Renderer",
      bundle = sdl3x.bundle_sdl3,
      bundle_options = {},
   },
   gl = {
      label = "OpenGL",
      bundle = sdl3x.bundle_sdl3_gl,
      bundle_options = {
         gl_attributes = GL_ATTRIBUTES,
         swap_interval = 1,
      },
   },
   gpu = {
      label = "SDL GPU",
      bundle = sdl3x.bundle_sdl3_gpu,
      bundle_options = {
         shader_formats = sdl3.GPU_SHADERFORMAT_SPIRV,
      },
   },
}

-- Returns `{ name, label, bundle, bundle_options }` for the selected backend.
-- `options.backends` is an optional set of supported backend names.
function M.select(options)
   options = options or {}

   local name = os.getenv("RIG_BACKEND") or "gl"
   local entry = BACKENDS[name]
   if entry == nil then
      rig.raise("RIG_BACKEND must be 'renderer', 'gl', or 'gpu' (got '%s')", name)
   end

   local supported = options.backends
   if supported ~= nil and not supported[name] then
      rig.raise("RIG_BACKEND '%s' is not supported by this example", name)
   end

   return {
      name = name,
      label = entry.label,
      bundle = entry.bundle,
      bundle_options = entry.bundle_options,
   }
end

return M
