# Baseline Examples

These examples are small, controlled rendering baselines for comparing frame timing and presentation behavior across Rig backends.

- [renderer_baseline.lua](/home/muci/Projektek/rig/examples/baseline/renderer_baseline.lua)
  - Uses `mode = "sdl3"` and the SDL renderer path.
- [gl_baseline.lua](/home/muci/Projektek/rig/examples/baseline/gl_baseline.lua)
  - Uses `mode = "sdl3_gl"` and a minimal OpenGL path.

Both examples intentionally render the same simple scene and expose the same profiler overlay and key toggles, so they can be used for side-by-side backend comparisons.

Controls:

- `0`
  - Toggle the profiler overlay.
- `1`
  - Toggle the moving square animation.
- `V`
  - Toggle vsync.

The main purpose of these examples is to help separate scene-cost issues from backend or presentation-path behavior when diagnosing jitter, frame pacing, and present latency.
