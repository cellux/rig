(local sdl3 (require "sdl3"))

(fn hooks.handle_key [key-info]
  (rig.println key-info))

(fn hooks.render []
  (sdl3.clear 0 0 0 1))

(sdl3.run)
