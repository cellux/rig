# `stat`

Statistical helpers for sampled metric collection.

The first version provides a `MetricBundle` abstraction with:

- stored metrics backed by fixed-capacity FFI `double` arrays
- pointwise derived metrics computed on demand
- window metrics materialized incrementally at `commit()` time

## API

- `stat.MetricBundle(options)`
  - Callable class constructor.
  - Required fields:
    - `capacity`
      - Positive integer ring-buffer capacity.
  - Optional fields:
    - `stored_metrics`
      - Array of stored metric definitions.
      - Each entry may be:
        - a metric name string
        - or `{ name = "...", time? = "..." }`
      - `time` names the timestamp metric that anchors this metric.
    - `derived_metrics`
      - Array of pointwise derived metric definitions:
        - `name`
        - `deps`
        - `calc`
        - `time?`
      - If `time` is omitted, it is inferred only when all dependencies share the same non-`nil` time axis.
    - `window_metrics`
      - Array of incremental window metric definitions:
        - `name`
        - `source`
        - `window_seconds`
        - `reduce`
        - `time?`
      - `reduce` currently supports:
        - `count`
        - `max`
        - `mean`
        - `min`
        - `sum`

## MetricBundle Methods

- `bundle:begin_sample()`
  - Opens a new sample slot.
- `bundle:set(name, value)`
  - Writes a stored metric value into the current open sample.
- `bundle:commit()`
  - Finalizes the current sample and advances the ring buffer.
  - All stored metrics must be written before commit.
- `bundle:reset()`
  - Clears stored state, derived caches, and window state.
- `bundle:get(name[, index])`
  - Returns the metric value for a retained sample.
  - `index` is 0-based from newest retained sample backward.
  - `0` means the newest retained sample.
  - `1` means one sample before the newest retained sample.
  - If `index` is omitted, it defaults to `0`.
- `bundle:latest(name)`
  - Shortcut for `bundle:get(name)`.
- `bundle:metric_kind(name)`
  - Returns `stored`, `derived`, or `window`.
- `bundle:time_axis(name)`
  - Returns the metric name used as the time axis for this metric, or `nil`.

## Notes

- Window metrics are updated incrementally on `commit()`. They do not rescan the full retained history at query time.
- Window metrics require non-decreasing timestamps on their declared time axis.
- Window metrics may depend on stored or pointwise derived metrics, but pointwise derived metrics may not depend on window metrics.
