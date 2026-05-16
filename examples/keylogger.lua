local sdl3 = require("sdl3")

rig.run {
  mode = "sdl3",
  sdl3 = {
    on_key = function(key_info)
      rig.println(key_info)
    end,
    on_render = function()
      sdl3.clear(0, 0, 0, 1)
    end,
  },
}
