# `time`

Backend-selecting clock wrapper over `uv` or `sdl3`.

## API

- `time.now()`
  - Returns epoch seconds as a Lua number.
- `time.monotonic()`
  - Returns monotonic seconds as a Lua number.

## Notes

- Use `time.monotonic()` for animation and frame timing.
- `time.now()` is wall-clock time and may jump if the system clock changes.
- `time` checks already-loaded modules at call time.
- If `uv` is loaded, it uses `uv.now()` and `uv.monotonic()`.
- Otherwise, if `sdl3` is loaded, it uses `sdl3.GetCurrentTime()` and `sdl3.GetPerformanceCounter()` / `sdl3.GetPerformanceFrequency()`.
- If neither module is loaded, `time` raises an error.
