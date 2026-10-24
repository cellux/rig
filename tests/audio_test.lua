local test = require("test")
local audio = require("audio")
local ffi = require("ffi")

test.case("audio.Clip reports its duration from the spec", function()
   local spec = ffi.new("SDL_AudioSpec[1]")
   spec[0].format = 0x8010 -- SDL_AUDIO_S16LSB (16-bit, little endian)
   spec[0].channels = 2
   spec[0].freq = 48000

   -- 48000 stereo 16-bit frames = 192000 bytes = 1 second.
   local data = ffi.new("uint8_t[?]", 192000)
   local clip = audio.Clip {
      name = "synthetic",
      spec = spec,
      data = data,
      length = 192000,
   }

   test.equal(clip:duration(), 1.0)
   test.equal(clip.length, 192000)
end)

test.case("audio.Scope releases its resources", function()
   local released = 0
   local first = {
      release = function()
         released = released + 1
      end,
   }
   local second = {
      release = function()
         released = released + 1
      end,
   }

   local scope = audio.Scope()
   scope:add(first)
   scope:add(second)
   scope:release()

   test.equal(released, 2)
end)

test.case("audio.load degrades gracefully for a missing file", function()
   local clip, err = audio.load("fixtures/assets/does-not-exist.wav")

   test.equal(clip, nil)
   test.truthy(type(err) == "string")
end)

test.case("audio exposes clips, voices, and scoped lifetimes", function()
   test.truthy(audio.Clip ~= nil)
   test.truthy(audio.Voice ~= nil)
   test.truthy(audio.Scope ~= nil)
   test.truthy(type(audio.update) == "function")
   test.truthy(type(audio.stop_all) == "function")
end)
