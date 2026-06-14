# `profiler`

Small profiling helpers.

The first version provides frame-timing collection only. It does not draw anything on its own.

## API

- `profiler.FrameProfiler(options?)`
  - Callable class constructor for frame profiler objects.
  - Fields:
    - `fps`
      - Expected runtime FPS for the program.
      - Used to derive `budget_ms` as `1000 / fps`.
      - Also used with `history_seconds` to size `frame_profiler.past_frames`.
    - `history_seconds`
      - Lookback window used for `past_frames` retention and the rolling max metrics.
      - Optional.
      - Defaults to `1.0`.
      - Also used as the EMA time constant for the smoothed `fps` field.

## Frame Profiler Object

- `frame_profiler:begin_frame()`
  - Marks the start of a frame.
  - Finalizes the previous pending frame into the current snapshot and `past_frames`.
- `frame_profiler:end_frame()`
  - Marks the end of a frame.
  - Captures the current frame as `pending_frame`.
  - Finalizes `cpu_ms`, `present_ms`, `total_ms`, and `overruns` for that pending frame.
- `frame_profiler:begin_cpu()`
  - Starts a CPU-measured section inside the current frame.
- `frame_profiler:end_cpu()`
  - Ends the current CPU-measured section and accumulates it into the frame CPU total.
- `frame_profiler:snapshot()`
  - Returns the most recent fully finalized frame snapshot for read-only metric access.
- `frame_profiler:reset()`
  - Clears all accumulated state and history.
  - Resets `past_frames` and its retained samples.
- `frame_profiler:before_frame_hook()`
  - Returns a hook closure that calls `begin_frame()`.
- `frame_profiler:after_frame_hook()`
  - Returns a hook closure that calls `end_frame()`.

## Profiler State

The frame profiler object exposes these fields directly:

- `expected_fps`
- `history_seconds`
- `budget_ms`
- `history_frames`
- `history_window_seconds`
- `fps_smoothing_seconds`
- `overruns`
- `pending_frame`
  - The most recently ended frame, before its `interval_ms` and `gap_ms` are known.
  - Set by `end_frame()`.
- `past_frames`
  - Always present.
  - `stat.MetricBundle` with:
    - stored metrics:
      - `frame_start_seconds`
      - `frame_end_seconds`
      - `cpu_ms`
      - `total_ms`
      - `interval_ms`
      - `gap_ms`
    - derived metrics:
      - `present_ms`
    - window metrics:
      - `cpu_window_max_ms`
      - `present_window_max_ms`
      - `total_window_max_ms`
      - `interval_window_max_ms`
      - `gap_window_max_ms`
  - The bundle still exposes `capacity`, `count`, and `next_index`.

## Snapshot Metrics

`frame_profiler:snapshot()` exposes:

- `fps`
- `fps_instant`
- `cpu_ms`
- `cpu_window_max_ms`
- `cpu_peak_ms`
- `present_ms`
- `present_window_max_ms`
- `present_peak_ms`
- `total_ms`
- `total_window_max_ms`
- `total_peak_ms`
- `interval_ms`
- `interval_window_max_ms`
- `interval_peak_ms`
- `gap_ms`
- `gap_window_max_ms`
- `gap_peak_ms`

## Notes

- The profiler uses `time.monotonic()`, so it works in runtime modes that provide the `"time"` service.
- `fps` is computed from an exponentially smoothed `interval_ms`, while `fps_instant` is derived directly from the most recent `interval_ms`.
- The frame profiler measures only what the caller brackets with `begin_cpu()` / `end_cpu()` as CPU work.
- `present_ms` is computed as `total_ms - cpu_ms`, so the caller should end the CPU section before presentation occurs.
- `past_frames` uses `stat.MetricBundle` ring-buffer semantics. `next_index` is the slot that will be written by the next completed frame.
- `history_frames` is derived as `ceil(fps * history_seconds)`.
- `*_window_max_ms` tracks the configured `history_seconds` window, while `*_peak_ms` tracks the since-reset lifetime peak.
- All profiler history metrics use `frame_start_seconds` as their time axis.
- `snapshot()` and `past_frames` are intentionally one frame behind: a frame is only committed when the next `begin_frame()` supplies its `interval_ms` and `gap_ms`.
- The configured `history_seconds` window is only as complete as the retained frame history. If the actual frame rate exceeds `fps`, older samples can drop out before they age out of the time window.
