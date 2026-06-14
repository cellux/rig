# animator

`animator` provides a fixed-step scene animator with scene-time sleeping for `drive()` coroutines.

## Exports

- `animator.Animator`
- `animator.DEFAULT_FIXED_DT`
- `animator.DEFAULT_MAX_DT`
- `animator.DEFAULT_MAX_STEPS_PER_FRAME`
- `animator.make_hooks(options)`

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

## `make_hooks`

`animator.make_hooks(...)` builds the common `rig.run(...)` hook trio for scene creation, ticking, and teardown.

```lua
local animator = require("animator")

local runtime = animator.make_hooks {
   create_root = function()
      return Scene()
   end,
   setup = function(root, scene_animator)
      root:initialize_resources()
   end,
   release = function(root, scene_animator)
      -- Optional extra cleanup after root:release_tree().
   end,
}

rig.run {
   hooks = runtime.hooks,
}
```

The returned table exposes:

- `runtime.root`
- `runtime.animator`
- `runtime.hooks.after_setup`
- `runtime.hooks.before_drain`
- `runtime.hooks.before_shutdown`
