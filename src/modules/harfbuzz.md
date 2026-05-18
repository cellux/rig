# `harfbuzz`

Lazy HarfBuzz binding built on LuaJIT FFI.

The HarfBuzz shared library is loaded only when the module is required.

## Scope

`harfbuzz` is a raw binding layer.

- C API names are mirrored after removing the `hb_` prefix.
- Lowercase names stay lowercase.
- Example:
  - `hb_buffer_create` -> `harfbuzz.buffer_create`
  - `hb_shape` -> `harfbuzz.shape`
  - `hb_ft_font_create_referenced` -> `harfbuzz.ft_font_create_referenced`

## Exported Types

The module defines the main HarfBuzz pointer and struct types in `ffi.cdef`, including:

- `hb_buffer_t`
- `hb_font_t`
- `hb_face_t`
- `hb_blob_t`
- `hb_glyph_info_t`
- `hb_glyph_position_t`
- `hb_feature_t`

It also defines `FT_Face` so the FreeType bridge functions can be used directly.

## Exported Functions

Core text and shaping:

- `harfbuzz.tag_from_string(str, len)`
- `harfbuzz.tag_to_string(tag, buf)`
- `harfbuzz.language_from_string(str, len)`
- `harfbuzz.language_to_string(language)`
- `harfbuzz.buffer_create()`
- `harfbuzz.buffer_reset(buffer)`
- `harfbuzz.buffer_reference(buffer)`
- `harfbuzz.buffer_destroy(buffer)`
- `harfbuzz.buffer_set_direction(buffer, direction)`
- `harfbuzz.buffer_get_direction(buffer)`
- `harfbuzz.buffer_set_script(buffer, script)`
- `harfbuzz.buffer_get_script(buffer)`
- `harfbuzz.buffer_set_language(buffer, language)`
- `harfbuzz.buffer_get_language(buffer)`
- `harfbuzz.buffer_guess_segment_properties(buffer)`
- `harfbuzz.buffer_set_cluster_level(buffer, cluster_level)`
- `harfbuzz.buffer_get_cluster_level(buffer)`
- `harfbuzz.buffer_add_utf8(buffer, text, text_length, item_offset, item_length)`
- `harfbuzz.buffer_get_length(buffer)`
- `harfbuzz.buffer_get_glyph_infos(buffer, length_out)`
- `harfbuzz.buffer_get_glyph_positions(buffer, length_out)`
- `harfbuzz.shape(font, buffer, features, num_features)`
- `harfbuzz.shape_full(font, buffer, features, num_features, shaper_list)`

FreeType bridge:

- `harfbuzz.ft_face_create_referenced(ft_face)`
- `harfbuzz.ft_font_create_referenced(ft_face)`
- `harfbuzz.ft_font_get_ft_face(font)`
- `harfbuzz.ft_font_set_load_flags(font, load_flags)`
- `harfbuzz.ft_font_get_load_flags(font)`
- `harfbuzz.ft_font_changed(font)`

Font lifetime:

- `harfbuzz.font_reference(font)`
- `harfbuzz.font_destroy(font)`
- `harfbuzz.font_get_face(font)`

## Exported Constants

Constants are exported from `harfbuzz.c`, not hard-coded in Lua.

Currently exported groups include:

- `TAG_*`
- `DIRECTION_*`
- `SCRIPT_*`
- `BUFFER_CONTENT_TYPE_*`
- `BUFFER_CLUSTER_LEVEL_*`

## Example

```lua
local freetype = require("freetype")
local harfbuzz = require("harfbuzz")
local ffi = require("ffi")

local library_out = ffi.new("FT_Library[1]")
assert(freetype.Init_FreeType(library_out) == 0)

local face_out = ffi.new("FT_Face[1]")
assert(freetype.New_Face(library_out[0], "font.ttf", 0, face_out) == 0)
assert(freetype.Set_Pixel_Sizes(face_out[0], 0, 16) == 0)

local font = harfbuzz.ft_font_create_referenced(face_out[0])
local buffer = harfbuzz.buffer_create()

harfbuzz.buffer_add_utf8(buffer, "Hello", -1, 0, -1)
harfbuzz.buffer_set_direction(buffer, harfbuzz.DIRECTION_LTR)
harfbuzz.buffer_set_script(buffer, harfbuzz.SCRIPT_LATIN)
harfbuzz.buffer_guess_segment_properties(buffer)
harfbuzz.shape(font, buffer, nil, 0)
```
