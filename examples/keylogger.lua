local sdl3x = require("sdl3x")

local App = rig.class(sdl3x.App)

function App:on_key(key_info)
   rig.println(key_info)
end

function App:render()
   sdl3.clear(0, 0, 0, 1)
end

rig.run {
  mode = "sdl3",
  app = App,
}
