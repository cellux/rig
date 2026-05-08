local sdl3 = require("sdl3")

function hooks.handle_key(key_info)
  rig.println(key_info)
end

function hooks.render()
  sdl3.clear(0, 0, 0, 1)
end

sdl3.run()
