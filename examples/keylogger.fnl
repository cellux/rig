(local sdl3 (require "sdl3"))

(rig.run
  {:mode "sdl3"
   :sdl3 {:on_key (fn [key-info]
                     (rig.println key-info))
          :on_render (fn []
                       (sdl3.clear 0 0 0 1))}})
