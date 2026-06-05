# `time`

Runtime-service clock wrapper.

## API

- `time.now()`
  - Returns epoch seconds as a Lua number.
- `time.monotonic()`
  - Returns monotonic seconds as a Lua number.

## Notes

- Use `time.monotonic()` for animation and frame timing.
- `time.now()` is wall-clock time and may jump if the system clock changes.
- `time` resolves the `"time"` service through `rig.require_service("time")`.
- The service implementation depends on the currently active runtime provider configuration.
- The built-in `uv` preset selects provider `"uv"` for `"time"`.
- The built-in `sdl3`, `sdl3_gl`, and `sdl3_gpu` presets all select provider `"sdl3"` for `"time"`.
- Calling `time.now()` or `time.monotonic()` without an active runtime raises an error.
