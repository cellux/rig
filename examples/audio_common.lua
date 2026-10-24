local audio = require("audio")
local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local overlay = require("overlay")
local params = require("params")
local rig = require("rig")

local M = {}

local CUBE_COLORS = {
   color.rgb(255, 96, 96),
   color.rgb(96, 224, 128),
   color.rgb(96, 144, 255),
   color.rgb(255, 220, 96),
   color.rgb(240, 112, 255),
   color.rgb(112, 232, 255),
}

-- Plays a looping WAV while a cube spins. The overlay tweaks playback volume and
-- a mute toggle. If no audio device is available, it prints a notice and runs
-- silently rather than failing.
--
-- options:
--   title          window title
--   bundle         sdl3x.bundle_sdl3_gl or sdl3x.bundle_sdl3_gpu (the backend hint)
--   bundle_options extra options forwarded to the bundle
function M.run(options)
   options = options or {}

   local values = params.params {
      { name = "volume", min = 0.0, max = 1.0, step = 0.05, value = 0.5 },
      { name = "muted", kind = "boolean", value = false },
   }

   local clip, load_err = audio.load("assets/beep.wav")
   local voice = nil
   if clip ~= nil then
      local play_err
      voice, play_err = audio.play(clip, {
         loop = true,
         volume = values:get("volume"),
      })
      if voice == nil then
         print("audio unavailable: " .. tostring(play_err or "unknown error"))
      end
   else
      print("audio unavailable: " .. tostring(load_err or "unknown error"))
   end

   local cube = mesh.make_cube { size = 1.8, colors = CUBE_COLORS }

   rig.run {
      title = options.title or "Rig Audio",
      bundle = options.bundle,
      bundle_options = options.bundle_options,
      build = function(app)
         app:add_overlay(overlay.overlay(values))

         app:on_update(function()
            if voice ~= nil then
               local volume = values:get("muted") and 0.0 or values:get("volume")
               voice:set_volume(volume)
            end
         end)

         app:on_draw(function(_, frame)
            local spin = mathx.mat4()
            mathx.mat4_rotation_y(spin, frame.time * 0.8)
            local tilt = mathx.mat4_rotation_x(mathx.mat4(), 0.4)
            mathx.mat4_multiply(spin, tilt, spin)
            frame.surface:draw_mesh(cube, spin)
         end)
      end,
   }
end

return M
