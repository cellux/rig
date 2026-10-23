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
- `time` is a thin wrapper over `uv.now()` / `uv.monotonic()` and does not require an active runtime.
