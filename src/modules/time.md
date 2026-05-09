# `time`

Wall-clock and monotonic clocks through `clock_gettime`.

## API

- `time.now()`
  - Returns epoch seconds as a Lua number.
- `time.monotonic()`
  - Returns monotonic seconds as a Lua number.
- `time.now_ns()`
  - Returns epoch nanoseconds as a Lua number.
- `time.monotonic_ns()`
  - Returns monotonic nanoseconds as a Lua number.

## Constants

- `time.CLOCK_REALTIME`
- `time.CLOCK_MONOTONIC`

## Notes

- Use `time.monotonic()` or `time.monotonic_ns()` for animation and frame timing.
- `time.now()` is wall-clock time and may jump if the system clock changes.
