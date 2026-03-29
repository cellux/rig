(fn _G.on_key [key-info]
  (rig.println key-info))

(fn _G.on_render []
  (sdl3.clear 0 0 0 1))
