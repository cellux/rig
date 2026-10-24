# camera

`camera` provides optional, backend-agnostic camera controllers. They are plain
values: feed them input events and `dt`, then `apply(scene)` to drive the scene camera.
Nothing enables them automatically; a sketch opts in.

## Exports

- `camera.orbit(options?)` / `camera.Orbit`
  - Orbits a target: drag with the primary button to rotate, hold the zoom keys to
    dolly.
  - `target`, `distance`, `yaw`, `pitch`, `sensitivity`, `zoom_speed`,
    `min_distance`, `max_distance`, `drag_button`, `zoom_in_key` (default `E`),
    `zoom_out_key` (default `Q`).
- `camera.fly(options?)` / `camera.Fly`
  - First-person fly camera.
  - `position`, `yaw`, `pitch`, `speed`, `sensitivity`, `look_button` (default `3`),
    and `keys` mapping movement actions to key names (defaults: WASD, `E` up, `Q`
    down).
- Controllers implement `on_key(info)`, `on_mouse(info)`, `update(dt)`, and
  `apply(scene)`.

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