local common = rig.require("./textured_quad_common")
local sdl3x = require("sdl3x")

common.run {
   title = "Rig OpenGL Textured Quad",
   bundle = sdl3x.bundle_sdl3_gl,
   bundle_options = {
      gl_attributes = {
         context_major_version = 4,
         context_minor_version = 5,
         context_profile = "core",
         doublebuffer = true,
         depth_size = 24,
      },
      swap_interval = 1,
   },
}
