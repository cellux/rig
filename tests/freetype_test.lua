local test = require("test")
local freetype = require("freetype")
local ffi = require("ffi")
local bit = bit

local function find_font_path()
   local candidates = {
      "/usr/share/fonts/TTF/DejaVuSans.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
      "/usr/share/fonts/dejavu/DejaVuSans.ttf",
   }

   for i = 1, #candidates do
      local path = candidates[i]
      local file = io.open(path, "rb")
      if file ~= nil then
         file:close()
         return path
      end
   end

   return nil
end

test.case("freetype initializes and exposes core constants", function()
   local library_out = ffi.new("FT_Library[1]")
   test.equal(freetype.Init_FreeType(library_out), 0)
   test.truthy(library_out[0] ~= nil and library_out[0] ~= ffi.NULL)

   local major_out = ffi.new("FT_Int[1]")
   local minor_out = ffi.new("FT_Int[1]")
   local patch_out = ffi.new("FT_Int[1]")
   freetype.Library_Version(library_out[0], major_out, minor_out, patch_out)

   test.truthy(tonumber(major_out[0]) >= 2)
   test.truthy(type(freetype.LOAD_RENDER) == "number")
   test.truthy(type(freetype.PIXEL_MODE_GRAY) == "number")
   test.truthy(type(freetype.FACE_FLAG_SCALABLE) == "number")

   test.equal(freetype.Done_FreeType(library_out[0]), 0)
end)

test.case("freetype can load a face and render a glyph when a system font is available", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local library_out = ffi.new("FT_Library[1]")
   test.equal(freetype.Init_FreeType(library_out), 0)

   local face_out = ffi.new("FT_Face[1]")
   test.equal(freetype.New_Face(library_out[0], font_path, 0, face_out), 0)

   local face = face_out[0]
   test.truthy(face ~= nil and face ~= ffi.NULL)
   test.truthy(tonumber(face.num_glyphs) > 0)
   test.truthy(face.glyph ~= nil and face.glyph ~= ffi.NULL)

   if face.family_name ~= nil and face.family_name ~= ffi.NULL then
      test.truthy(#ffi.string(face.family_name) > 0)
   end

   test.equal(freetype.Set_Pixel_Sizes(face, 0, 16), 0)

   local glyph_index = freetype.Get_Char_Index(face, string.byte("A"))
   test.truthy(tonumber(glyph_index) > 0)

   local load_flags = bit.bor(freetype.LOAD_RENDER, freetype.LOAD_TARGET_NORMAL)
   test.equal(freetype.Load_Char(face, string.byte("A"), load_flags), 0)

   local glyph = face.glyph
   test.truthy(glyph ~= nil and glyph ~= ffi.NULL)
   test.truthy(tonumber(glyph.bitmap.width) > 0)
   test.truthy(tonumber(glyph.bitmap.rows) > 0)
   test.truthy(glyph.bitmap.buffer ~= nil and glyph.bitmap.buffer ~= ffi.NULL)
   test.truthy(
      glyph.bitmap.pixel_mode == freetype.PIXEL_MODE_GRAY
         or glyph.bitmap.pixel_mode == freetype.PIXEL_MODE_MONO
   )

   test.equal(freetype.Done_Face(face), 0)
   test.equal(freetype.Done_FreeType(library_out[0]), 0)
end)
