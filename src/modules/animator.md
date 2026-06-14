# animator

`animator` provides a fixed-step scene animator with scene-time sleeping for `drive()` coroutines.

## Exports

- `animator.Animator`
- `animator.DEFAULT_FIXED_DT`
- `animator.DEFAULT_MAX_DT`
- `animator.DEFAULT_MAX_STEPS_PER_FRAME`

## Usage

Create an animator with an optional root object and options table:

```lua
local animator = require("animator")

local scene_animator = animator.Animator(root, {
   fixed_dt = 1.0 / 120.0,
   max_dt = 0.05,
   max_steps_per_frame = 6,
})
```

Call `scene_animator:start()` once the object tree is ready, `scene_animator:tick()` once per frame, and `scene_animator:sleep(seconds)` from `drive()` coroutines that should wait in scene time.
