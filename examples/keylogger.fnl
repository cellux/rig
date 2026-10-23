(local sdl3x (require "sdl3x"))

(local App (rig.Class sdl3x.App))

(fn App.on_key [self key-info]
  (rig.println key-info))

(fn App.render [self]
  (sdl3x.clear 0 0 0 1))

(local builder (rig.runtime))
(sdl3x.bundle_sdl3 builder)
(builder:execute App)
(local compiled (builder:compile))
(compiled:start)
