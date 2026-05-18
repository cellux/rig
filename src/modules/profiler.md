# `profiler`

Small profiling helpers.

The first version provides frame-timing collection only. It does not draw anything on its own.

## API

- `profiler.create_frame_profiler(options?)`
  - Creates a frame profiler object.
  - Optional fields:
    - `budget_ms`
      - Frame budget used for `overruns`.
      - Defaults to `16.67`.
    - `history_window_seconds`
      - Rolling window used for `*_max_1s_ms` style metrics.
      - Defaults to `1.0`.

## Frame Profiler Object

- `frame_profiler:begin_frame()`
  - Marks the start of a frame.
  - Updates `interval_ms` and `gap_ms` against the previous frame.
- `frame_profiler:end_frame()`
  - Marks the end of a frame.
  - Finalizes `cpu_ms`, `present_ms`, `total_ms`, and `overruns`.
- `frame_profiler:begin_cpu()`
  - Starts a CPU-measured section inside the current frame.
- `frame_profiler:end_cpu()`
  - Ends the current CPU-measured section and accumulates it into the frame CPU total.
- `frame_profiler:snapshot()`
  - Returns the profiler object itself for read-only metric access.
- `frame_profiler:reset()`
  - Clears all accumulated state and history.
- `frame_profiler:before_frame_hook()`
  - Returns a hook closure that calls `begin_frame()`.
- `frame_profiler:after_frame_hook()`
  - Returns a hook closure that calls `end_frame()`.

## Metrics

The frame profiler exposes these fields directly:

- `cpu_ms`
- `cpu_max_1s_ms`
- `cpu_max_ms`
- `present_ms`
- `present_max_1s_ms`
- `present_max_ms`
- `total_ms`
- `total_max_1s_ms`
- `total_max_ms`
- `interval_ms`
- `interval_max_1s_ms`
- `interval_max_ms`
- `gap_ms`
- `gap_max_1s_ms`
- `gap_max_ms`
- `overruns`

## Notes

- The profiler uses `time.monotonic()`, so it works in runtime modes that provide the `"time"` service.
- The frame profiler measures only what the caller brackets with `begin_cpu()` / `end_cpu()` as CPU work.
- `present_ms` is computed as `total_ms - cpu_ms`, so the caller should end the CPU section before presentation occurs.
