# `time`

Thin clock wrapper over the `uv` module.

## API

- `time.now()`
  - Returns epoch seconds as a Lua number.
- `time.monotonic()`
  - Returns monotonic seconds as a Lua number.

## Notes

- Use `time.monotonic()` for animation and frame timing.
- `time.now()` is wall-clock time and may jump if the system clock changes.
- `time` delegates to `uv.now()` and `uv.monotonic()`.
