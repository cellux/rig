# sketch

`sketch` is the code-first front door to the runtime composition machinery. It
assembles a default composition — bundle, clock, scene with camera, entities, and
frame callbacks — so a demo can be a single Lua file, while still using the same
builder/compiler/component runtime that larger systems use directly. `rig.run`
delegates to `sketch.run`.

## Exports

- `sketch.App`
  - `app:add_entity(options)` — queues an entity spec (`mesh`, `motion`, `name`)
    to be composed into the scene at startup.
  - `app:on_start(fn)` — registers `fn(app, sched)`, run once as a background
    coroutine after setup and before the first frame. It may await scheduler
    operations (for example `sched.sleep` or, later, async asset loads); the frame
    loop is gated until it returns, and finishing it does not stop the app.
  - `app:on_update(fn)` — registers `fn(app, frame)`, run once per frame before the
    frame is drawn.
  - `app:on_draw(fn)` — registers `fn(app, frame)`, run once per frame after the
    camera is current.
  - `app:on_overlay(fn)` — registers `fn(app, frame)`, run once per frame after the
    scene's children, for screen-space overlays and HUDs.
  - `app:add_overlay(value)` — registers an overlay value (see `overlay.md`); its
    `:update(input, scene)` and `:draw(scene)` run each frame. Returns the overlay.
  - `app:on_key(fn)` / `app:on_mouse(fn)` / `app:on_resize(fn)` — register input
    callbacks receiving the raw `sdl3.key` / `sdl3.mouse` / `sdl3.resize` payloads.
  - `app:add_camera_controls(options)` — opts into a `camera` controller
    (`options.kind` is `"orbit"` or `"fly"`); returns the controller. Never added
    automatically.
  - Fields: `app.entities`, `app.camera_controllers`, `app.overlays`, `app.input`,
    `app.scene`, `app.surface`, `app.runtime`, `app.ctx`.
  - Every frame context also carries `frame.input`, the shared `input.Input` state
    (see `input.md`); pressed/released edges are reset after the overlay phase.
- `sketch.run(options?, build?)`
  - Builds and runs a sketch; blocks until it exits.
  - `run(build)` is shorthand for `run { build = build }`.
  - `options.bundle` is the backend bundle, defaulting to
    `sdl3x.bundle_sdl3_gl`.
  - `options.bundle_options` is forwarded to the bundle.
  - `options.camera`, `options.background`, and `options.title` override defaults.
  - `options.camera_controls` (a spec or list) opts into optional camera controls,
    equivalent to calling `app:add_camera_controls` in `build`.
  - `options.start`, `options.update`, and `options.draw` are shorthand for
    `app:on_start` / `app:on_update` / `app:on_draw`; they are applied after
    `build`, so they take precedence over callbacks registered there.
  - `build(app)` runs before compilation, so `app:add_entity` and the callback
    registrations take effect.
  - Every sketch runtime assembles the default libuv I/O backend on top of the
    bundle's scheduler, so `app.ctx.uv` (a `uv.UvLoop`) and
    `sched.active_scheduler()` are available from within frame callbacks.
  - `app.runtime` and `app.ctx` are populated once setup completes, so callbacks
    can reach the live runtime (for example `app.runtime:stop()`).

## Relationship to the builder

`sketch.run` uses `rig.runtime()`, the `scene` and `render` plugins/components, and
`sdl3x.App`, exactly as a hand-written assembly does; it only fills in defaults, adds
the `uv` loop component (`uv.plugin()` + `uv.loop_component()`), and wires the frame
callbacks. Use `uv.bundle_uv` or `uv.loop_component` directly when assembling a
runtime by hand. `rig.run` requires `sketch` lazily, so core `rig` stays independent
of the graphics backends at load time. Use the builder directly when you need
components or backends that the facade does not expose.

## Example

```lua
local rig = require("rig")
local motion = require("motion")
local mesh = require("mesh")

rig.run {
   title = "Spinning Cube",
   build = function(app)
      app:add_entity {
         mesh = mesh.make_cube { size = 2.0, colors = ... },
         motion = motion.spin { x = 0.7, y = 1.0 },
      }
   end,
}
```