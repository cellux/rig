# `overlay`

A lightweight live-parameter overlay for `params` stores. It is not a retained UI
toolkit: it draws screen-space bars through the scene's immediate drawing API and
edits values from the shared `input` state.

The sketch draws registered overlays after the scene's children, so they land on
top. Register one with `app:add_overlay(overlay.overlay(params))`.

## API

- `overlay.overlay(params, options?)` / `overlay.Overlay(params, options?)`
  - Creates an overlay over a `params` store.
  - Options:
    - `position` — `"top-left"` (default), `"top-right"`, `"bottom-left"`,
      `"bottom-right"`.
    - `row_height`, `width`, `margin`, `gap`, `bar_height`, `label_width` — layout.
    - `track_color`, `fill_color`, `selected_color`, `text_color` — `color` values.
    - `visible` — initial visibility (default true; `view.visible` is writable).
    - `draw_text(scene, x, y, text, color)` — optional; draws row labels (for
      example through the `font` module). Without it the overlay is bars only.
  - Methods:
    - `view:update(input, scene)` — edits parameters from the keyboard/mouse.
      `scene` only supplies the viewport size for hit-testing.
    - `view:draw(scene)` — draws the rows.
    - `view:select(index)` / `view:selected_name()`.

## Interaction

- Up/Down select a row (wrapping).
- Left/Right adjust the selected value; Space/Return toggles it.
- Click a row to select it; drag a number row to set its value.

## Example

```lua
local overlay = require("overlay")
local params = require("params")

rig.run(function(app)
   local values = params.params {
      { name = "spin", min = 0.0, max = 3.0, step = 0.1, value = 0.8 },
      { name = "grid", kind = "boolean", value = true },
   }
   local view = app:add_overlay(overlay.overlay(values))

   app:on_key(function(_, info)
      if info.action == "down" and string.upper(info.key or "") == "H" then
         view.visible = not view.visible
      end
   end)
end)
```
