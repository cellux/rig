(local sdl3 (require "sdl3"))

(rig.run
  {:preset "sdl3"
   :event_handlers {:key (fn [key-info]
                           (rig.println key-info))}
   :driver_config {:sdl3 {:render (fn []
                                    (sdl3.clear 0 0 0 1))}}})
