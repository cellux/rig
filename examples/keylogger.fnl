(local sdl3x (require "sdl3x"))

(local App (rig.Class sdl3x.App))

(fn App.on_key [self key-info]
  (rig.println key-info))

(fn App.render [self]
  (sdl3x.clear 0 0 0 1))

(rig.run {:mode "sdl3" :app App})
