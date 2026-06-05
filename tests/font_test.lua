local test = require("test")
local font = require("font")
local freetype = require("freetype")

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

test.case("font can load a face and expose metadata", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local face = font.load_face(font_path)
   test.equal(face.path, font_path)
   test.truthy(type(face.face_index) == "number")
   test.truthy(type(face.num_glyphs) == "number")
   test.truthy(face.num_glyphs > 0)
   test.truthy(type(face.units_per_em) == "number")
   test.truthy(face.units_per_em > 0)
   if face.family_name ~= nil then
      test.truthy(type(face.family_name) == "string")
      test.truthy(face.family_name ~= "")
   end

   face:release()
end)

test.case("font can create a sized face and shape text", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local face = font.load_face(font_path)
   local sized = font.create_sized_face(face, 18)

   test.equal(sized.pixel_size, 18)
   test.truthy(type(sized.height) == "number")
   test.truthy(sized.height > 0)
   test.truthy(type(sized.ascender) == "number")
   test.truthy(type(sized.descender) == "number")

   local shaped = font.shape(sized, "Hello")
   test.equal(shaped.text, "Hello")
   test.truthy(type(shaped.glyph_count) == "number")
   test.truthy(shaped.glyph_count > 0)
   test.equal(#shaped.glyphs, shaped.glyph_count)
   test.truthy(type(shaped.x_advance) == "number")
   test.truthy(shaped.x_advance > 0)

   local glyph = shaped.glyphs[1]
   test.truthy(type(glyph.glyph_id) == "number")
   test.truthy(glyph.glyph_id > 0)
   test.truthy(type(glyph.cluster) == "number")
   test.truthy(type(glyph.x_advance) == "number")
   test.truthy(type(glyph.x_offset) == "number")

   sized:release()
   face:release()
end)

test.case("font can build a text run from an atlas", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local face = font.load_face(font_path)
   local sized = face:create_sized_face(18)
   local atlas = sized:create_atlas()
   local run = atlas:build_text_run("Hello")

   test.equal(run.text, "Hello")
   test.truthy(type(run.width) == "number")
   test.truthy(run.width > 0)
   test.truthy(type(run.glyph_count) == "number")
   test.truthy(run.glyph_count > 0)
   test.equal(#run.entries, run.glyph_count)
   test.truthy(type(run.entries[1].layout_x) == "number")
   test.truthy(type(run.entries[1].layout_y) == "number")
   test.truthy(type(run.entries[1].packed) == "table")

   atlas:release()
   sized:release()
   face:release()
end)

test.case("font can rasterize a shaped glyph", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local face = font.load_face(font_path)
   local sized = face:create_sized_face(20)
   local shaped = font.shape(sized, "A")
   local glyph = shaped.glyphs[1]
   local bitmap = font.rasterize_glyph(sized, glyph.glyph_id)

   test.equal(bitmap.glyph_id, glyph.glyph_id)
   test.truthy(type(bitmap.width) == "number")
   test.truthy(type(bitmap.height) == "number")
   test.truthy(bitmap.width > 0)
   test.truthy(bitmap.height > 0)
   test.truthy(type(bitmap.left) == "number")
   test.truthy(type(bitmap.top) == "number")
   test.truthy(type(bitmap.advance_x) == "number")
   test.truthy(type(bitmap.data) == "string")
   test.truthy(#bitmap.data > 0)

   sized:release()
   face:release()
end)

test.case("font caches default rasterized glyphs on sized faces", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local face = font.load_face(font_path)
   local sized = face:create_sized_face(18)
   local shaped = font.shape(sized, "A")
   local glyph_id = shaped.glyphs[1].glyph_id

   local first = sized:get_cached_glyph(glyph_id)
   local second = sized:get_cached_glyph(glyph_id)

   test.truthy(first == second)
   test.truthy(type(first.data) == "string")
   test.truthy(#first.data > 0)

   sized:release()
   face:release()
end)

test.case("font atlas packs glyphs into grayscale pages", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local face = font.load_face(font_path)
   local sized = face:create_sized_face(18)
   local atlas = sized:create_atlas {
      page_width = 64,
      page_height = 64,
      padding = 1,
   }

   local shaped = font.shape(sized, "AB")
   local a = atlas:get_glyph(shaped.glyphs[1].glyph_id)
   local b = atlas:get_glyph(shaped.glyphs[2].glyph_id)

   test.equal(a.page_index, 1)
   test.equal(b.page_index, 1)
   test.truthy(a.width > 0)
   test.truthy(a.height > 0)
   test.truthy(b.width > 0)
   test.truthy(b.height > 0)
   test.truthy(a.u0 >= 0.0)
   test.truthy(a.v0 >= 0.0)
   test.truthy(a.u1 <= 1.0)
   test.truthy(a.v1 <= 1.0)
   test.truthy(b.x >= a.x)

   local a_again = atlas:get_glyph(shaped.glyphs[1].glyph_id)
   test.truthy(a == a_again)

   local page = atlas.pages[1]
   test.truthy(page ~= nil)
   test.equal(page.pixel_mode, freetype.PIXEL_MODE_GRAY)
   local page_data = atlas:get_page_data(1)
   test.equal(type(page_data), "string")
   test.equal(#page_data, page.width * page.height)

   atlas:release()
   sized:release()
   face:release()
end)

test.case("font text renderer requires an active runtime service", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local face = font.load_face(font_path)
   local sized = face:create_sized_face(18)
   local atlas = sized:create_atlas()
   atlas:warm_text("Hello")

   local ok, err = pcall(function()
      atlas:create_text_renderer()
   end)

   test.falsey(ok)
    test.match(tostring(err), "font.backend")

   atlas:release()
   sized:release()
   face:release()
end)
