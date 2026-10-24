local M = ... or {}

local ffi = require("ffi")
local rig = require("rig")
local sdl3 = require("sdl3")

-- Minimal audio playback over SDL3: load a WAV, play it, loop it, and set its
-- volume. There is no mixer or DSP graph; each voice owns one audio stream.
-- Resources are refcounted (`Clip`) or owned by a `Scope` for deterministic
-- lifetimes.
--
-- Playback needs the SDL audio subsystem; `audio` initializes it lazily on first
-- use. When no device is available, `audio.load`/`audio.play` return `nil, error`
-- instead of raising, so demos degrade gracefully.

local voices = {}

local function clamp(value, low, high)
   if value < low then
      return low
   end
   if value > high then
      return high
   end
   return value
end

-- SDL error strings come back as `const char *` cdata; normalize to a Lua string.
local function error_string(fallback)
   local err = sdl3.GetError()
   if err == nil or err == ffi.NULL then
      return fallback
   end
   if err[0] == 0 then
      return fallback
   end
   return ffi.string(err)
end

local function caller_directory()
   -- user -> audio.<fn> -> caller_directory
   local source = rig.source_of(debug.getinfo(3, "S"))
   if source == nil then
      return ""
   end
   return rig.dirname(source)
end

local function resolve_relative(directory, path)
   if type(path) ~= "string" or path == "" then
      rig.raise("audio paths must be non-empty strings")
   end

   local resolved = rig.join_path(directory, path)
   local key = resolved
   if type(rig.realpath) == "function" then
      key = rig.realpath(resolved) or resolved
   end
   return resolved, key
end

local audio_ready = false
local function ensure_audio()
   if audio_ready then
      return true
   end
   if sdl3.WasInit(sdl3.INIT_AUDIO) == 0 then
      if not sdl3.InitSubSystem(sdl3.INIT_AUDIO) then
         return false, error_string("failed to initialize SDL audio")
      end
   end
   audio_ready = true
   return true
end

local clip_cache = {}
local clip_refcounts = setmetatable({}, { __mode = "k" })

local Clip = rig.Class()
M.Clip = Clip

function Clip:init(options)
   self.name = options.name
   self.spec = options.spec
   self.data = options.data
   self.length = options.length
   self.key = options.key
   self._freed = false
   clip_refcounts[self] = 1
end

-- Seconds of PCM in the clip.
function Clip:duration()
   local spec = self.spec[0]
   local channels = tonumber(spec.channels) or 0
   local freq = tonumber(spec.freq) or 0
   local bytes = tonumber(spec.format) % 256 / 8
   local frame_bytes = channels * bytes
   if frame_bytes <= 0 or freq <= 0 then
      return 0.0
   end
   return self.length / frame_bytes / freq
end

function Clip:retain()
   clip_refcounts[self] = (clip_refcounts[self] or 0) + 1
   return self
end

function Clip:release()
   if self._freed then
      return
   end
   local refs = (clip_refcounts[self] or 1) - 1
   clip_refcounts[self] = refs
   if refs <= 0 then
      if self.data ~= nil then
         sdl3.free(self.data)
         self.data = nil
      end
      self._freed = true
      if self.key ~= nil then
         clip_cache[self.key] = nil
      end
   end
end

local Voice = rig.Class()
M.Voice = Voice

function Voice:init(options)
   self.clip = options.clip
   self.loop = options.loop and true or false
   self.volume = clamp(options.volume or 1.0, 0.0, 1.0)
   self.playing = false
   self.released = false
   self.error = nil

   local device = options.device or sdl3.AUDIO_DEVICE_DEFAULT_PLAYBACK
   local stream = sdl3.OpenAudioDeviceStream(device, self.clip.spec, nil, nil)
   if stream == nil then
      self.error = error_string("failed to open audio stream")
      return
   end

   self.stream = stream
   self.clip:retain()
   sdl3.SetAudioStreamGain(self.stream, self.volume)
   self:_enqueue()
   sdl3.ResumeAudioStreamDevice(self.stream)
   self.playing = true
end

function Voice:_enqueue()
   if self.clip.length > 0 and self.clip.data ~= nil then
      sdl3.PutAudioStreamData(self.stream, self.clip.data, self.clip.length)
   end
end

-- Tops up loops and detects the end of one-shot voices. `audio.update()` calls
-- this once per frame.
function Voice:update()
   if self.released or self.stream == nil or not self.playing then
      return
   end

   local queued = sdl3.GetAudioStreamQueued(self.stream)
   if self.loop then
      if queued < self.clip.length then
         self:_enqueue()
      end
   elseif queued <= 0 then
      self.playing = false
      self:release()
   end
end

function Voice:set_volume(value)
   self.volume = clamp(tonumber(value) or self.volume, 0.0, 1.0)
   if self.stream ~= nil then
      sdl3.SetAudioStreamGain(self.stream, self.volume)
   end
   return self.volume
end

function Voice:set_loop(enabled)
   self.loop = enabled and true or false
   return self.loop
end

function Voice:pause()
   if self.stream ~= nil and self.playing then
      sdl3.PauseAudioStreamDevice(self.stream)
      self.playing = false
   end
   return self
end

function Voice:resume()
   if self.stream ~= nil and not self.playing then
      self.playing = true
      sdl3.ResumeAudioStreamDevice(self.stream)
   end
   return self
end

function Voice:stop()
   if self.stream ~= nil then
      sdl3.ClearAudioStream(self.stream)
      sdl3.PauseAudioStreamDevice(self.stream)
   end
   self.playing = false
   return self
end

function Voice:is_playing()
   return self.playing and not self.released
end

function Voice:release()
   if self.released then
      return
   end
   self.released = true
   self.playing = false
   if self.stream ~= nil then
      sdl3.DestroyAudioStream(self.stream)
      self.stream = nil
   end
   if self.clip ~= nil then
      self.clip:release()
      self.clip = nil
   end
end

-- Loads a WAV relative to the calling script (path-relative, like `asset`).
-- Returns a refcounted `Clip`, or `nil, error` when the file or device is
-- unavailable. Repeated loads of the same path share one clip.
function M.load(path)
   local ok, err = ensure_audio()
   if not ok then
      return nil, err
   end

   local resolved, key = resolve_relative(caller_directory(), path)
   local cached = clip_cache[key]
   if cached ~= nil and not cached._freed then
      return cached:retain()
   end

   local spec = ffi.new("SDL_AudioSpec[1]")
   local buffer = ffi.new("Uint8 *[1]")
   local length = ffi.new("Uint32[1]")
   if not sdl3.LoadWAV(resolved, spec, buffer, length) then
      return nil, error_string(("failed to load audio '%s'"):format(resolved))
   end

   local clip = Clip {
      name = path,
      spec = spec,
      data = buffer[0],
      length = tonumber(length[0]) or 0,
      key = key,
   }
   clip_cache[key] = clip
   return clip
end

-- Plays `clip`. `options.loop` loops it and `options.volume` sets its gain
-- (0-1). Returns a `Voice`, or `nil, error` when no device is available.
function M.play(clip, options)
   options = options or {}
   local ok, err = ensure_audio()
   if not ok then
      return nil, err
   end
   if not Clip:is_instance(clip) or clip._freed then
      rig.raise("audio.play expects a live audio.Clip")
   end

   local voice = Voice {
      clip = clip,
      loop = options.loop,
      volume = options.volume,
      device = options.device,
   }
   if voice.stream == nil then
      clip:release()
      return nil, voice.error
   end

   voices[#voices + 1] = voice
   return voice
end

-- Tops up loops and reaps finished one-shot voices. Called once per frame by the
-- sketch facade; hand-built apps call it from their own frame hook.
function M.update()
   for i = #voices, 1, -1 do
      local voice = voices[i]
      if voice.released then
         table.remove(voices, i)
      else
         voice:update()
      end
   end
end

-- Releases every live voice (for example at shutdown).
function M.stop_all()
   for i = #voices, 1, -1 do
      voices[i]:release()
   end
   voices = {}
end

-- Deterministic ownership for clips and voices.
local Scope = rig.Class()
M.Scope = Scope

function Scope:init()
   self.resources = {}
end

function Scope:add(resource)
   self.resources[#self.resources + 1] = resource
   return resource
end

function Scope:load(path)
   local clip, err = M.load(path)
   if clip ~= nil then
      self:add(clip)
   end
   return clip, err
end

function Scope:play(clip, options)
   local voice, err = M.play(clip, options)
   if voice ~= nil then
      self:add(voice)
   end
   return voice, err
end

function Scope:release()
   for i = #self.resources, 1, -1 do
      local resource = self.resources[i]
      if resource ~= nil and type(resource.release) == "function" then
         resource:release()
      end
      self.resources[i] = nil
   end
end

return M
