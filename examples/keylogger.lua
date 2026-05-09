local sdl3 = require("sdl3")

sdl3.callback.on_key = function(key_info)
  rig.println(key_info)
end

sdl3.callback.on_render = function()
  sdl3.clear(0, 0, 0, 1)
end

sdl3.run()
