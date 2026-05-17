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
- The service implementation depends on the currently active runtime mode.
- `uv` registers the `"time"` service for `mode = "uv"`.
- `sdl3` registers the `"time"` service for:
  - `mode = "sdl3"`
  - `mode = "sdl3_gl"`
  - `mode = "sdl3_gpu"`
- Calling `time.now()` or `time.monotonic()` without an active runtime mode raises an error.
