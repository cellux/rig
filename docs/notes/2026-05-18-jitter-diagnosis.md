# Jitter Diagnosis: `examples/scroller.lua`

## Scope

This note records what was learned while investigating occasional visible stutter in:

- `examples/scroller.lua`
- `examples/baseline/renderer_baseline.lua`

The goal was to determine whether the visible jumps came from Rig's Lua-side frame work, the scheduler, a specific visual effect, or from lower-level presentation behavior on this host.

## Profiler Metrics

The profiler used the following metrics:

- `CPU`
  - Time spent inside the demo's render callback body.
- `PRS`
  - Estimated present-time cost.
  - Computed effectively as `TOT - CPU`.
- `TOT`
  - Total frame time from frame-begin hook to frame-end hook.
  - Includes the render callback body and presentation.
- `INT`
  - Interval between consecutive frame starts.
- `GAP`
  - Time outside the measured frame body before the next frame begins.
  - Computed as `INT - TOT`.
- `OVR`
  - Count of frames where total frame time exceeded the nominal 60 Hz frame budget.

The overlays in the examples show `CURRENT / MAX_1S / MAX` for each metric.

## Observed Behavior

In the scroller example:

- `CPU` stayed well below the 60 Hz frame budget.
- `PRS`, `TOT`, and `INT` tended to move together.
- `GAP` stayed small, typically around `0.4 ms`.
- `PRS` sometimes spiked into ranges such as `20-30 ms`.
- `INT` maxima could reach roughly `40-50 ms`.

That relationship is important:

- `PRS < TOT < INT`
- `CPU` remained low while the other timing metrics still spiked

This strongly suggested that the main visible jitter was not caused by the Lua-side demo code overrunning its budget.

## Diagnostic Steps Performed

### 1. Scene-level profiling in `examples/scroller.lua`

The scroller example gained a TTF-based profiler overlay showing:

- `CPU`
- `PRS`
- `TOT`
- `INT`
- `GAP`
- `OVR`
- runtime toggles

This established that the visible hitching did not correlate with high `CPU`.

### 2. Vsync toggle test

A live `V` toggle was added so the example could switch vsync on and off.

Observation:

- With vsync off, visible jumps still occurred.

This weakened the hypothesis that the issue was only classic missed-vblank behavior.

### 3. Fixed-step animation experiment

`animate_scroller()` was converted from raw variable-`dt` stepping to a fixed-step accumulator.

Reason:

- If the animation loop was amplifying small timing irregularities, fixed-step updates should have reduced the visible jumps.

Observation:

- The visible jumping still remained.

Conclusion:

- Variable-`dt` motion may have made jitter easier to see, but it was not the root cause.

### 4. Runtime effect toggles in the scroller

The scroller gained toggles for major passes:

- `1`: raster splits
- `2`: multiplexer sprites
- `3`: multiplexer outline
- `4`: DYCP scroller
- `0`: profiler
- `5`: animation coroutine park/resume

Observation:

- Even with the scene heavily stripped down, `PRS` spikes remained.
- The problem did not isolate cleanly to one visual effect.

### 5. Minimal baseline comparison

A separate baseline example was built:

- `examples/baseline/renderer_baseline.lua`

It reduces the workload to:

- clear
- optional simple animation
- the same profiler overlay
- present

Observation:

- `PRS` spikes still happened in the baseline.
- They still happened with animation disabled.

This was the key control experiment.

## What Was Ruled Out

The investigation gives strong evidence against the following as primary causes:

- Lua-side frame CPU overrun in the scroller
- the scheduler itself
- one specific scroller effect such as:
  - raster splits
  - multiplexer letters
  - multiplexer outline
  - DYCP scrolltext
- raw variable-`dt` animation logic as the root cause

## What Remains Likely

On this host, the most likely remaining causes are outside the scene logic:

- SDL renderer/backend presentation behavior
- desktop compositor / window manager pacing
- graphics driver timing
- OS scheduling jitter around frame presentation

The strongest evidence for that conclusion is:

- `CPU` remained low
- `GAP` remained low
- `PRS`, `TOT`, and `INT` moved together
- the simplified baseline still showed the same kind of spikes
- the spikes remained even with animation disabled

## Renderer Backend Comparison

The baseline was also tried with SDL renderer backend changes, including:

- `SDL_RENDER_DRIVER=opengl`
- `SDL_RENDER_DRIVER=software`

Observation:

- Both still showed `PRS` spikes.

This suggests the issue is not specific to just one SDL renderer backend on this host.

## Practical Conclusion

The occasional visible jitter seen in the scroller is very likely environmental or presentation-path related on this machine.

It should not currently be treated as evidence that:

- the font path is too slow
- the scheduler is misbehaving
- the scroller effect code is fundamentally too expensive

That does not mean rendering cost is irrelevant in general. It means that the specific spikes diagnosed here do not appear to be primarily caused by Rig's Lua scene logic.

## Follow-up Work

The next meaningful comparison is:

- implement `examples/baseline/gl_baseline.lua`
- run the same profiler model under `mode = "sdl3_gl"`
- compare whether the same presentation spikes appear there

If the OpenGL path behaves materially differently, that would help separate:

- SDL renderer presentation behavior
- from broader compositor / driver / system timing issues

## Related Files

- `examples/scroller.lua`
- `examples/baseline/renderer_baseline.lua`
- `src/modules/sdl3.lua`
- `src/modules/font.lua`
