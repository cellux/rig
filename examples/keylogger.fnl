(local sdl3 (require "sdl3"))

(set sdl3.callback.on_key
  (fn [key-info]
    (rig.println key-info)))

(set sdl3.callback.on_render
  (fn []
    (sdl3.clear 0 0 0 1)))

(sdl3.run)
