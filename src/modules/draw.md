# `draw`

Backend-neutral immediate 2D drawing.

`draw` owns the public screen-space API and its validation; a `draw.renderer`
provider supplies the backend implementation. Providers are selected by the active
`graphics.context` backend (SDL_Renderer, OpenGL, or SDL_GPU) through
`graphics.provider_component`, mirroring the `font.renderer` capability.

Coordinates are screen-space pixels with the origin at the top-left, matching the
scene surface returned to callbacks as `frame.surface`.

## API

- `draw.create(provider)`
  - Creates a canvas bound to a validated `draw.renderer` provider.
- `draw.rect(canvas, x, y, width, height[, color])`
  - Fills the screen-space rectangle. `color` defaults to white.
- `draw.line(canvas, x1, y1, x2, y2[, color])`
  - Draws a one-pixel line. `color` defaults to white.
- `draw.release(canvas)`
- `draw.bind(provider)` — builds the bound facade exposed by `draw.component` and the
  provider components.
- `draw.plugin([spec])` — declares the `draw.renderer` capability.
- `draw.component(plugin, options)` — requires `draw.renderer` and exposes a bound
  canvas as `ctx.<name>`.

## Canvas Object

Canvases returned by `draw.create(...)` provide:

- `canvas:rect(x, y, width, height[, color])`
- `canvas:line(x1, y1, x2, y2[, color])`
- `canvas:release()`

## `draw.renderer` provider

A `draw.renderer` provider is a table:

- `draw_rect(canvas, x, y, width, height, color)` (required)
- `draw_line(canvas, x1, y1, x2, y2, color)` (required)
- `create_canvas(canvas) -> state` (optional)
  - The returned `state` is stored as `canvas._state`.
- `release_canvas(canvas)` (optional)

Colors are always a `color.Color`. Screen-space coordinates are pixels.

## Backends

- `sdl3x.bundle_sdl3` provides an SDL_Renderer-backed `draw.renderer`.
- `sdl3x.bundle_sdl3_gl` provides an OpenGL-backed one (an attribute-less quad
  pipeline driven by `gl_VertexID` and uniforms).
- `sdl3x.bundle_sdl3_gpu` provides an SDL_GPU-backed one that records into the active
  render pass of the GPU render scene.

The GPU provider needs the scene's active pass, so GPU draws must happen from the
scene's `on_overlay` hook or a node's draw call; drawing with no active pass raises a
clear error.

## Example

```lua
local color = require("color")

rig.run {
   bundle = sdl3x.bundle_sdl3_gl,
   build = function(app)
      app:on_overlay(function(_, frame)
         local w = frame.surface.width
         app.ctx.draw:rect(0, 0, w, 4, color.rgb(255, 198, 120))
      end)
   end,
}
```
