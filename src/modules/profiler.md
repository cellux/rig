# `profiler`

Small profiling helpers.

The first version provides frame-timing collection only. It does not draw anything on its own.

## API

- `profiler.FrameProfiler(options?)`
  - Callable class constructor for frame profiler objects.
  - Optional fields:
    - `budget_ms`
      - Frame budget used for `overruns`.
      - Optional. If omitted, `overruns` is not tracked.
    - `budget_fps`
      - Alternative frame budget expressed as a target FPS.
      - Converted to `budget_ms` as `1000 / budget_fps`.
      - Mutually exclusive with `budget_ms`.
    - `history_frames`
      - Capacity of the always-present `frame_profiler.past_frames` FFI ring buffer.
      - Defaults to `300`.
      - Stores per-frame measurements for the last `history_frames` completed frames.
    - `history_window_seconds`
      - Rolling time window used for `*_max_1s_ms` style metrics.
      - The rolling max scan reads from `past_frames`.
      - Defaults to `1.0`.
    - `fps_smoothing_seconds`
      - EMA time constant used for the smoothed `fps` field.
      - Higher values make the displayed FPS steadier but slower to react.
      - Defaults to `0.5`.

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
  - Resets `past_frames` metadata and zeroes its buffers.
- `frame_profiler:before_frame_hook()`
  - Returns a hook closure that calls `begin_frame()`.
- `frame_profiler:after_frame_hook()`
  - Returns a hook closure that calls `end_frame()`.

## Metrics

The frame profiler exposes these fields directly:

- `fps`
- `fps_instant`
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
- `past_frames`
  - Always present.
  - FFI struct with:
    - `capacity`
    - `count`
    - `next_index`
    - `frame_start_seconds`
    - `frame_end_seconds`
    - `cpu_ms`
    - `present_ms`
    - `total_ms`
    - `interval_ms`
    - `gap_ms`

## Notes

- The profiler uses `time.monotonic()`, so it works in runtime modes that provide the `"time"` service.
- `fps` is computed from an exponentially smoothed `interval_ms`, while `fps_instant` is derived directly from the most recent `interval_ms`.
- The frame profiler measures only what the caller brackets with `begin_cpu()` / `end_cpu()` as CPU work.
- `present_ms` is computed as `total_ms - cpu_ms`, so the caller should end the CPU section before presentation occurs.
- `past_frames` uses ring-buffer semantics. `next_index` is the slot that will be written by the next completed frame.
- `history_window_seconds` is only as complete as the retained frame history. If you reduce `history_frames` too far for your frame rate, older samples will drop out before they age out of the time window.
