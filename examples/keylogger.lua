local sdl3x = require("sdl3x")

local App = rig.Class(sdl3x.App)

function App:on_key(key_info)
   rig.println(key_info)
end

function App:render()
   sdl3x.clear(0, 0, 0, 1)
end

local builder = rig.runtime()
sdl3x.bundle_sdl3(builder)
builder:execute(App):compile():start()
