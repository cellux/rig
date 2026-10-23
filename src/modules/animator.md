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

`animator.App` extends `rig.Class()` with the common scene-root and animator lifecycle. It is
instantiated as a runtime execution class, so `init(context)` receives the runtime
context:

```lua
local animator = require("animator")
local sdl3x = require("sdl3x")

local App = rig.Class(animator.App)

function App:init(context)
   self:super().init(self, context)
   self.root = Scene()
end

local builder = rig.runtime()
sdl3x.bundle_sdl3_gpu(builder)
builder:execute(App):compile():start()
```

Animator app behavior may be configured through the bundle options at
`context.options.animator` (or `context.options` directly):

- `fixed_dt`, `max_dt`, and `max_steps_per_frame` forward to `animator.Animator(root, options)`
- `start = false` disables the default automatic `scene_animator:start()`

Subclasses may override:

- `init(context)`
- `create_root()`
- `create_scene_animator(root)`
- `after_setup()`
- `before_frame()`
- `release(root, scene_animator)`

The base class expects either `self.root` to be set or `create_root()` to return a root before `self:super().after_setup(self)` runs. The runtime instantiates the app class after component setup, so `init(context)` may use runtime facilities if needed. The inherited animator behavior wires `self.root` to an animator in `after_setup`, runs `root:activate_tree()` before the animator starts, ticks it in `before_frame`, and releases the root tree in `before_shutdown`.
