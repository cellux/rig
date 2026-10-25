# camera

`camera` provides optional, backend-agnostic camera controllers. They are plain
values: feed them input events and `dt`, then `apply(scene)` to drive the scene camera.
Nothing enables them automatically; a sketch opts in.

## Exports

- `camera.orbit(options?)` / `camera.Orbit`
  - Orbits a target: drag with the primary button to rotate, hold the zoom keys to
    dolly.
  - `target`, `distance`, `yaw`, `pitch`, `sensitivity`, `zoom_speed`,
    `min_distance`, `max_distance`, `drag_button`, `mouse_grab` (default `false`),
    `zoom_in_key` (default `E`), `zoom_out_key` (default `Q`).
- `camera.fly(options?)` / `camera.Fly`
  - First-person fly camera.
  - `position`, `yaw`, `pitch`, `speed`, `sensitivity`, `look_button` (default `3`),
    `mouse_grab` (default `true`), and `keys` mapping movement actions to key names
    (defaults: WASD, `E` up, `Q` down).
- Controllers implement `on_key(info)`, `on_mouse(info)`, `update(dt)`, and
  `apply(scene)`. They may also implement `on_focus(info)`; sketches forward focus
  events to controllers that provide it.

## Notes

- Input info comes straight from `sdl3x`'s `sdl3.key` / `sdl3.mouse` events:
  `action` (`"down"` / `"up"` / `"move"`), `key`, `button`, `xrel`, `yrel`.
- `apply(scene)` calls `scene:set_camera`, preserving the scene's `fov_degrees`,
  `near`, and `far`.
- In a sketch, opt in with `app:add_camera_controls { kind = "orbit" | "fly", ... }`
  or the `camera_controls` run option. See `sketch.md`.

## Example

```lua
local camera = require("camera")
local controller = camera.orbit { distance = 10.0 }

-- next to a hand-built `sdl3x.App`:
function App:on_mouse(info) controller:on_mouse(info) end
function App:on_key(info) controller:on_key(info) end
-- each frame, before rendering:
controller:update(dt)
controller:apply(scene)
```
## Walk controller

- `camera.walk(options?)` / `camera.Walk`
  - Ground-constrained first-person controller.
  - `position` (feet position, default `{ 0, 0, -4.5 }`), `spawn`, `eye_height`
    (default `1.65`), `speed` (default `2.4`), `sensitivity` (default `0.0025`),
    `yaw`, `pitch`, `radius` (default `0.3`), and `collision` (a `collision.world`).
  - `smoothing` (default `0`) is an optional ground-plane movement time constant in
    seconds. Zero keeps the instant response; a small value eases acceleration and
    deceleration. `reset()` also clears the smoothed velocity.
  - Default keys: `W`/`A`/`S`/`D`; `reset_key` defaults to `R`.
  - `look_button` is optional. When nil (default), mouse motion rotates the view
    whenever the window is focused. When set, the button must be held.
  - `mouse_grab` (default `true`) marks the controller as wanting relative mouse
    mode. A sketch grabs by default when it has a walk or fly controller; see
    `sketch.md`.
  - `reset()` restores the spawn position, yaw, and pitch, and clears held movement
    keys.
  - `on_focus(info)` clears held keys and mouse look when focus is lost; focus gain
    re-enables mouse look.
  - `update(dt)` moves on the XZ plane only and keeps `position[2]` at the configured
    floor height. With a collision world, movement uses `world:move(...)`. When
    `smoothing` is set, the horizontal velocity is eased toward the input direction
    before it is applied.
  - `apply(scene)` places the eye at `position + (0, eye_height, 0)` and preserves
    the scene's FOV/near/far values.
