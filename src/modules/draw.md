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
- `draw.create_texture(canvas, options)`
  - Creates a backend texture from RGBA8 pixels. `options` fields:
    - `width`, `height` — pixel dimensions (positive integers).
    - `pixels` — a `width * height * 4` byte string, top-down and row-major.
    - `filter` — `"linear"` (default) or `"nearest"`.
    - `wrap` — `"clamp"` (default), `"repeat"`, or `"mirror"`.
  - Returns a texture object (see below).
- `draw.draw_texture(canvas, texture, x, y[, color])`
  - Draws the whole texture at (`x`, `y`), modulated by `color` (default white).
- `draw.draw_texture_region(canvas, texture, sx, sy, sw, sh, dx, dy, dw, dh[, color])`
  - Draws the source region (`sx`, `sy`, `sw`, `sh`) of `texture` scaled into the
    destination rectangle (`dx`, `dy`, `dw`, `dh`), modulated by `color`. Empty
    regions (a non-positive source or destination size) are skipped.
- `draw.release_texture(texture)`
  - Destroys a texture early. Textures still alive when their canvas is released
    are released automatically.
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
- `canvas:create_texture(options)`
- `canvas:draw_texture(texture, x, y[, color])`
- `canvas:draw_texture_region(texture, sx, sy, sw, sh, dx, dy, dw, dh[, color])`
- `canvas:release()`

## Texture Object

Textures returned by `draw.create_texture(...)` provide:

- `texture.width`, `texture.height`
- `texture:release()`

## `draw.renderer` provider

A `draw.renderer` provider is a table:

- `draw_rect(canvas, x, y, width, height, color)` (required)
- `draw_line(canvas, x1, y1, x2, y2, color)` (required)
- `create_texture(canvas, spec) -> handle` (optional)
  - `spec` is `{ width, height, pixels, filter, wrap }`; `handle` is backend-specific.
  - Required by `draw.create_texture`, `draw.draw_texture`, and
    `draw.draw_texture_region`.
- `destroy_texture(canvas, handle)` (optional)
- `draw_texture(canvas, handle, sx, sy, sw, sh, dx, dy, dw, dh, color)` (optional)
  - The primitive behind `draw.draw_texture` / `draw.draw_texture_region`.
- `create_canvas(canvas) -> state` (optional)
  - The returned `state` is stored as `canvas._state`.
- `release_canvas(canvas)` (optional)

Colors are always a `color.Color`. Screen-space coordinates are pixels. `pixels` is
an RGBA8 byte string, matching `asset.image` and `render.texture`.

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
         local canvas = app.ctx.draw
         local w = frame.surface.width
         canvas:rect(0, 0, w, 4, color.rgb(255, 198, 120))
         canvas:draw_texture(app.texture, 24, 24)
      end)
   end,
   start = function(app)
      -- `pixels` is a width * height * 4 RGBA8 byte string.
      app.texture = app.ctx.draw:create_texture {
         width = 1,
         height = 1,
         pixels = "\255\255\255\255",
      }
   end,
}
```

See `examples/scroller.lua` for a full example: a scrolling `1 x N` raster texture
split into columns with `draw_texture_region`, plus `draw.rect` HUD panels.
