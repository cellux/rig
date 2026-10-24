# `font`

Provider-neutral font shaping and rasterization built on top of `freetype` and `harfbuzz`.

The `font` module owns the backend-neutral font pipeline:
- shaping
- glyph rasterization
- atlas packing
- text-run construction
- atlas page → RGBA conversion and per-renderer page-texture caching
- run walking and drawing (`font.draw_text_run`)

Backends implement only the `font.renderer` capability: uploading/destroying a page
texture and issuing a single packed-glyph draw.

## API

- `font.load_face(path[, face_index])`
  - Loads a font face from a TTF/OTF file.
  - Returns a face object with metadata fields such as:
    - `path`
    - `face_index`
    - `family_name`
    - `style_name`
    - `num_glyphs`
    - `units_per_em`
    - `face_flags`
    - `style_flags`
- `font.create_sized_face(face, pixel_size)`
  - Opens a size-specific face instance and configures it for the given pixel size.
  - Returns a sized-face object with:
    - `pixel_size`
    - `ascender`
    - `descender`
    - `height`
    - `max_advance`
    - `x_ppem`
    - `y_ppem`
- `font.create_style(face, options)`
  - Creates a higher-level text style bundle for one pixel size.
  - Requires:
    - `options.pixel_size`
  - Optional atlas options:
    - `page_width`
    - `page_height`
    - `padding`
  - Returns a style object that owns:
    - `sized_face`
    - `atlas`
    - `text_renderer`
- `font.shape(sized_face, text[, options])`
  - Shapes UTF-8 text through HarfBuzz.
  - Returns:
    - `text`
    - `glyphs`
    - `glyph_count`
    - `x_advance`
    - `y_advance`
  - Each glyph entry has:
    - `glyph_id`
    - `cluster`
    - `x_advance`
    - `y_advance`
    - `x_offset`
    - `y_offset`
- `font.rasterize_glyph(sized_face, glyph_id[, options])`
  - Loads and renders a glyph bitmap through FreeType.
  - Returns:
    - `glyph_id`
    - `width`
    - `height`
    - `pitch`
    - `left`
    - `top`
    - `pixel_mode`
    - `num_grays`
    - `advance_x`
    - `advance_y`
    - `data`
- `font.get_cached_glyph(sized_face, glyph_id)`
  - Returns the cached default rasterization for a glyph.
  - Uses the normal grayscale render path.
- `font.create_atlas(sized_face[, options])`
  - Creates a lazy grayscale atlas for one sized face.
  - Supported options:
    - `page_width`
    - `page_height`
    - `padding`
- `font.build_text_run(atlas, text[, options])`
  - Shapes text against the atlas sized face and packs referenced glyphs.
  - Returns:
    - `text`
    - `width`
    - `glyph_count`
    - `entries`
  - Each entry has:
    - `packed`
    - `layout_x`
    - `layout_y`
    - `cluster`
- `font.warm_text(atlas, text[, options])`
  - Shapes text and ensures all referenced glyphs are packed into the atlas.
- `font.create_text_renderer(atlas, provider)`
  - Requires a `font.renderer` provider.
  - Returns a text-renderer object tied to that atlas.
- `font.draw_packed_glyph(text_renderer, packed, x, y[, color[, scale]])`
  - Draws one packed glyph through the active provider.
- `font.draw_text_run(text_renderer, run, base_x, baseline_y[, color_fn])`
  - Draws a text run through the active provider.
  - `color_fn(index, entry, run)` may return a `color.Color`.

## Face Object

Faces returned by `font.load_face(...)` also provide:

- `face:create_sized_face(pixel_size)`
- `face:release()`

## Sized Face Object

Sized faces returned by `font.create_sized_face(...)` also provide:

- `sized_face:release()`
- `sized_face:get_cached_glyph(glyph_id)`
- `sized_face:create_atlas(options?)`

## Style Object

Styles returned by `font.create_style(...)` provide:

- `style.face`
- `style.sized_face`
- `style.atlas`
- `style.text_renderer`
- `style.pixel_size`
- `style:get_glyph(glyph_id)`
- `style:build_run(text[, options])`
- `style:warm_text(text[, options])`
- `style:draw_packed_glyph(packed, x, y[, color[, scale]])`
- `style:draw_run(run, base_x, baseline_y[, color_fn])`
- `style:draw_text(text, base_x, baseline_y[, color_fn[, options]])`
- `style:release()`

## Atlas Object

Atlas objects returned by `font.create_atlas(...)` provide:

- `atlas:get_glyph(glyph_id)`
  - Packs the glyph into an atlas page on first use and returns:
    - `glyph_id`
    - `page_index`
    - `x`
    - `y`
    - `width`
    - `height`
    - `left`
    - `top`
    - `advance_x`
    - `advance_y`
    - `u0`
    - `v0`
    - `u1`
    - `v1`
    - `glyph`
- `atlas:get_page_data(page_index)`
  - Returns the grayscale page bytes as a Lua string.
- `atlas:release()`
- `atlas:build_text_run(text[, options])`
- `atlas:warm_text(text[, options])`
- `atlas:create_text_renderer()`

## Text Renderer Object

Text renderers returned by `font.create_text_renderer(...)` provide:

- `text_renderer:draw_packed_glyph(packed, x, y[, color[, scale]])`
- `text_renderer:draw_text_run(run, base_x, baseline_y[, color_fn])`
- `text_renderer:release()`

The text renderer owns the backend-neutral page-texture cache (keyed by
`(page_index, page.revision)`) and walks runs itself; it delegates only texture
creation/update/destruction and the single-glyph draw to the provider.

## `font.renderer` provider

A `font.renderer` provider is a table:

- `upload_page_texture(text_renderer, texture, page, rgba) -> texture` (required)
  - Creates the page texture when `texture` is `nil`, otherwise updates it.
  - `rgba` is a `uint8_t[width * height * 4]` buffer of white RGB with the page's
    grayscale coverage in the alpha channel; `font` builds it.
- `destroy_page_texture(text_renderer, texture)` (required)
- `draw_packed_glyph(text_renderer, texture, packed, x, y, color, scale)` (required)
  - `color` is always a `color.Color`.
- `create_text_renderer(text_renderer) -> state` (optional)
  - The returned `state` is stored as `text_renderer._state`.
- `release_text_renderer(text_renderer)` (optional)

Atlas objects also expose:

- `atlas.pages`
  - Page descriptors with:
    - `index`
    - `width`
    - `height`
    - `pixel_mode`

## Notes

- `font.load_face(path)` opens the face through FreeType's own file I/O and is
  **synchronous**. It is a setup/startup operation, not an async asset read; font file
  bytes are not routed through `asset`/`uv.fs_read`.
- `font.shape(...)` returns positions in pixel units as Lua numbers.
- `font.rasterize_glyph(...)` copies bitmap bytes into the returned `data` string.
- `font.get_cached_glyph(...)` caches only the default render path.
- `font.create_sized_face(...)` opens a separate FreeType face per size instance.
  - This avoids size mutation conflicts between independently sized faces.
- `font.create_atlas(...)` currently produces a single-channel grayscale atlas.
  - `FT_PIXEL_MODE_MONO` glyphs are expanded to 8-bit grayscale while packing.
- `font.create_text_renderer(...)` requires a `font.renderer` provider argument that
  implements `upload_page_texture`, `destroy_page_texture`, and `draw_packed_glyph`;
  `create_text_renderer` and `release_text_renderer` are optional.
- `font.create_style(face, options, provider)` forwards the provider to `font.create_text_renderer`.
- `font.draw_text_run(...)` is backend-neutral: it walks the run and calls
  `text_renderer:draw_packed_glyph(...)` for each entry.
- `sdl3x.bundle_sdl3` provides a renderer-backed `font.renderer` provider;
  `sdl3x.bundle_sdl3_gl` provides an OpenGL-backed one; `sdl3x.bundle_sdl3_gpu`
  provides an SDL_GPU-backed one.
- The GPU provider records glyph draws into the active render pass of the GPU render
  scene, so text must be drawn from the scene's `on_overlay` hook or a scene node's
  draw call. Drawing text with no active pass raises a clear error.

## Example

```lua
local font = require("font")

local face = font.load_face("font.ttf")
local sized = font.create_sized_face(face, 16)

local shaped = font.shape(sized, "Hello")
local first = shaped.glyphs[1]
local atlas = sized:create_atlas()
local packed = atlas:get_glyph(first.glyph_id)
local run = atlas:build_text_run("Hello")
```

## Runtime Components

`font.plugin([spec])` declares the `font.renderer` capability for the compositional runtime.

`font.component(plugin, options)` requires `font.renderer` and exposes a bound facade as
`ctx.<name>`. `font.bind(provider)` builds it, with `:create_text_renderer(atlas)` and
`:create_style(face, options)` delegating to the validated module entry points:

```lua
local fp = font.plugin()
local compiled = rig.runtime()
   :use(fp)
   :add(provider)
   :add(font.component(fp, { name = "font" }))
   :execute(function(ctx)
      local renderer = ctx.font:create_text_renderer(atlas)
      local style = ctx.font:create_style(face, { pixel_size = 16 })
   end)
   :compile()
```
