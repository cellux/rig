# `font`

Backend-neutral font shaping and rasterization built on top of `freetype` and `harfbuzz`.

This first version stops before atlas generation or backend texture upload.

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

## Face Object

Faces returned by `font.load_face(...)` also provide:

- `face:create_sized_face(pixel_size)`
- `face:release()`

## Sized Face Object

Sized faces returned by `font.create_sized_face(...)` also provide:

- `sized_face:release()`
- `sized_face:get_cached_glyph(glyph_id)`
- `sized_face:create_atlas(options?)`

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

Atlas objects also expose:

- `atlas.pages`
  - Page descriptors with:
    - `index`
    - `width`
    - `height`
    - `pixel_mode`

## Notes

- `font.shape(...)` returns positions in pixel units as Lua numbers.
- `font.rasterize_glyph(...)` copies bitmap bytes into the returned `data` string.
- `font.get_cached_glyph(...)` caches only the default render path.
- `font.create_sized_face(...)` opens a separate FreeType face per size instance.
  - This avoids size mutation conflicts between independently sized faces.
- `font.create_atlas(...)` currently produces a single-channel grayscale atlas.
  - `FT_PIXEL_MODE_MONO` glyphs are expanded to 8-bit grayscale while packing.
- This version does not yet:
  - upload textures to `sdl3`, `sdl3_gpu`, or `sdl3_gl`
  - draw text directly

## Example

```lua
local font = require("font")

local face = font.load_face("font.ttf")
local sized = font.create_sized_face(face, 16)

local shaped = font.shape(sized, "Hello")
local first = shaped.glyphs[1]
local atlas = sized:create_atlas()
local packed = atlas:get_glyph(first.glyph_id)
```
