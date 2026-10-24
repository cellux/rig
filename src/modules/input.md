# `input`

Backend-agnostic input state built from the `sdl3.key`/`sdl3.mouse` payloads the
runtime already emits. The sketch facade owns one and updates it automatically, so
`input` is normally reached as `frame.input` (or `app.input`); it is also usable
directly next to a hand-built app.

Keys are addressed either by scancode (a number) or by name (a string such as `"W"`,
`"Space"`, `"Left"`). Names are case-insensitive. Held state persists; pressed and
released are per-frame edges, as are mouse relative deltas.

## API

- `input.Input()`
  - Creates an input state.
  - Methods:
    - `state:begin_frame()` — clears pressed/released edges and relative deltas.
      The sketch calls it at the end of each frame.
    - `state:on_key(event)` — feeds an `sdl3.key` payload.
    - `state:on_mouse(event)` — feeds an `sdl3.mouse` payload.
    - `state:key_down(id)` / `state:key_pressed(id)` / `state:key_released(id)`
    - `state:axis(negative, positive)` — `-1`, `0`, or `1` from two held keys.
    - `state:mouse_position()` — returns `x, y`.
    - `state:mouse_delta()` — returns this frame's `dx, dy`.
    - `state:mouse_down(button?)` / `state:mouse_pressed(button?)` /
      `state:mouse_released(button?)` — `button` defaults to the primary button.
  - Modifier fields: `shift`, `ctrl`, `alt`, `super`.

## Example

```lua
rig.run(function(app)
   app:on_update(function(_, frame)
      local move = frame.input:axis("A", "D")
      if frame.input:key_pressed("Space") then
         -- one-shot action
      end
   end)
end)
```
