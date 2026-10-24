# `audio`

Minimal audio playback over SDL3: load a WAV, play it, loop it, and set its
volume. There is no mixer or DSP graph; each voice owns one audio stream. Resources
are refcounted (`Clip`) or owned by a `Scope` for deterministic lifetimes.

Playback needs the SDL audio subsystem, which `audio` initializes lazily on first
use. When no device is available, `audio.load`/`audio.play` return `nil, error`
instead of raising, so demos degrade gracefully.

## API

- `audio.load(path)`
  - Loads a WAV relative to the calling script (path-relative, like `asset`).
  - Returns a refcounted `Clip`, or `nil, error`. Repeated loads of the same path
    share one clip.
- `audio.Clip`
  - `clip:duration()` — seconds of PCM.
  - `clip:retain()` / `clip:release()` — refcount; releases the decoded buffer when
    the count reaches zero.
- `audio.play(clip, options?)`
  - Starts a `Voice`. `options.loop` loops it; `options.volume` sets its gain
    (0–1); `options.device` overrides the playback device (defaults to
    `sdl3.AUDIO_DEVICE_DEFAULT_PLAYBACK`).
  - Returns a `Voice`, or `nil, error` when no device is available.
- `audio.Voice`
  - `voice:set_volume(value)` / `voice:set_loop(enabled)`
  - `voice:pause()` / `voice:resume()` / `voice:stop()`
  - `voice:is_playing()` / `voice:release()`
- `audio.update()`
  - Tops up looping voices and reaps finished one-shot voices. Called once per
    frame by the sketch facade; hand-built apps call it from their own frame hook.
- `audio.stop_all()` — releases every live voice.
- `audio.Scope()`
  - Deterministic ownership: `scope:load(path)` and `scope:play(clip, options)`
    register their result; `scope:release()` releases everything it holds.

## Example

```lua
local audio = require("audio")

local clip = audio.load("assets/beep.wav")
local voice = audio.play(clip, { loop = true, volume = 0.4 })
voice:set_volume(0.2)
```

Under the sketch facade, `audio.update()` runs automatically each frame.
