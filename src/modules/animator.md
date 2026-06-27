# animator

`animator` provides a fixed-step scene animator with scene-time sleeping for `drive()` coroutines.

## Exports

- `animator.Animator`
- `animator.App`
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

## `App`

`animator.App` extends `rig.App` with the common scene-root and animator lifecycle:

```lua
local animator = require("animator")

local App = rig.Class(animator.App)

function App:init()
   self:super().init(self)
   self.root = Scene()
end

rig.run {
   mode = "sdl3_gpu",
   app = App,
}
```

Subclasses may override:

- `init(options)`
- `create_root()`
- `create_scene_animator(root)`
- `after_setup()`
- `release(root, scene_animator)`

The base class expects either `self.root` to be set or `create_root()` to return a root before `self:super().after_setup(self)` runs. `rig.run { app = SomeAppClass }` instantiates the app class after driver setup, so `init(...)` may use runtime facilities if needed. The inherited animator behavior wires `self.root` to an animator in `after_setup`, runs `root:activate_tree()` before the animator starts, ticks it in `before_drain`, and releases the root tree in `before_shutdown`.
