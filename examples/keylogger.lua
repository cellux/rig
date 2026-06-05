local sdl3 = require("sdl3")

rig.run {
  preset = "sdl3",
  event_handlers = {
    key = function(key_info)
      rig.println(key_info)
    end,
  },
  driver_config = {
    sdl3 = {
      render = function()
        sdl3.clear(0, 0, 0, 1)
      end,
    },
  },
}
