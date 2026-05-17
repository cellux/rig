local test = require("test")
local freetype = require("freetype")
local harfbuzz = require("harfbuzz")
local ffi = ffi

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

test.case("harfbuzz exposes core constants and helpers", function()
   test.truthy(type(harfbuzz.DIRECTION_LTR) == "number")
   test.truthy(type(harfbuzz.SCRIPT_LATIN) == "number")
   test.truthy(type(harfbuzz.BUFFER_CLUSTER_LEVEL_DEFAULT) == "number")

   local language = harfbuzz.language_from_string("en", -1)
   test.truthy(language ~= nil and language ~= ffi.NULL)
   test.equal(ffi.string(harfbuzz.language_to_string(language)), "en")
end)

test.case("harfbuzz can shape utf8 text with a freetype-backed font", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local library_out = ffi.new("FT_Library[1]")
   test.equal(freetype.Init_FreeType(library_out), 0)

   local face_out = ffi.new("FT_Face[1]")
   test.equal(freetype.New_Face(library_out[0], font_path, 0, face_out), 0)
   test.equal(freetype.Set_Pixel_Sizes(face_out[0], 0, 18), 0)

   local hb_font = harfbuzz.ft_font_create_referenced(face_out[0])
   test.truthy(hb_font ~= nil and hb_font ~= ffi.NULL)

   local hb_buffer = harfbuzz.buffer_create()
   test.truthy(hb_buffer ~= nil and hb_buffer ~= ffi.NULL)

   harfbuzz.buffer_add_utf8(hb_buffer, "office", -1, 0, -1)
   harfbuzz.buffer_set_direction(hb_buffer, harfbuzz.DIRECTION_LTR)
   harfbuzz.buffer_set_script(hb_buffer, harfbuzz.SCRIPT_LATIN)
   harfbuzz.buffer_set_language(
      hb_buffer,
      harfbuzz.language_from_string("en", -1)
   )
   harfbuzz.shape(hb_font, hb_buffer, nil, 0)

   local length_out = ffi.new("unsigned int[1]")
   local infos = harfbuzz.buffer_get_glyph_infos(hb_buffer, length_out)
   local positions = harfbuzz.buffer_get_glyph_positions(hb_buffer, length_out)
   local glyph_count = tonumber(length_out[0]) or 0

   test.truthy(infos ~= nil and infos ~= ffi.NULL)
   test.truthy(positions ~= nil and positions ~= ffi.NULL)
   test.truthy(glyph_count > 0)
   test.truthy(tonumber(infos[0].codepoint) > 0)
   test.truthy(
      tonumber(positions[0].x_advance) ~= 0
         or tonumber(positions[0].y_advance) ~= 0
   )

   harfbuzz.buffer_destroy(hb_buffer)
   harfbuzz.font_destroy(hb_font)
   test.equal(freetype.Done_Face(face_out[0]), 0)
   test.equal(freetype.Done_FreeType(library_out[0]), 0)
end)
