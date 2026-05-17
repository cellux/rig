# `freetype`

Lazy FreeType binding built on LuaJIT FFI.

The FreeType shared library is loaded only when the module is required.

## Scope

`freetype` is a raw binding layer.

- C API names are mirrored after removing the `FT_` prefix.
- Example:
  - `FT_Init_FreeType` -> `freetype.Init_FreeType`
  - `FT_Load_Char` -> `freetype.Load_Char`

## Core Types

The module defines the main FreeType pointer and struct types in `ffi.cdef`, including:

- `FT_Library`
- `FT_Face`
- `FT_Size`
- `FT_GlyphSlot`
- `FT_FaceRec`
- `FT_GlyphSlotRec`
- `FT_SizeRec`
- `FT_Bitmap`
- `FT_Vector`

## Exported Functions

- `freetype.Init_FreeType(alibrary_out)`
- `freetype.Done_FreeType(library)`
- `freetype.Library_Version(library, major_out, minor_out, patch_out)`
- `freetype.New_Face(library, filepathname, face_index, face_out)`
- `freetype.Done_Face(face)`
- `freetype.Reference_Face(face)`
- `freetype.Set_Char_Size(face, char_width, char_height, horz_resolution, vert_resolution)`
- `freetype.Set_Pixel_Sizes(face, pixel_width, pixel_height)`
- `freetype.Get_Char_Index(face, charcode)`
- `freetype.Load_Glyph(face, glyph_index, load_flags)`
- `freetype.Load_Char(face, char_code, load_flags)`
- `freetype.Render_Glyph(slot, render_mode)`
- `freetype.Get_Kerning(face, left_glyph, right_glyph, kern_mode, kerning_out)`

These functions return the raw `FT_Error` status where applicable.

## Exported Constants

Constants are exported from `freetype.c`, not hard-coded in Lua.

Currently exported groups include:

- `FACE_FLAG_*`
- `STYLE_FLAG_*`
- `LOAD_*`
- `RENDER_MODE_*`
- `PIXEL_MODE_*`
- `KERNING_*`

## Example

```lua
local freetype = require("freetype")
local ffi = ffi

local library_out = ffi.new("FT_Library[1]")
assert(freetype.Init_FreeType(library_out) == 0)

local face_out = ffi.new("FT_Face[1]")
assert(freetype.New_Face(library_out[0], "font.ttf", 0, face_out) == 0)
assert(freetype.Set_Pixel_Sizes(face_out[0], 0, 16) == 0)
assert(freetype.Load_Char(face_out[0], string.byte("A"), freetype.LOAD_RENDER) == 0)

local glyph = face_out[0].glyph
local bitmap = glyph.bitmap
```
