local common = rig.require("./textured_quad_common")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")

common.run {
   title = "Rig SDL GPU Textured Quad",
   bundle = sdl3x.bundle_sdl3_gpu,
   bundle_options = {
      shader_formats = sdl3.GPU_SHADERFORMAT_SPIRV,
   },
}
