local M = ... or {}
local freetype = require("freetype")
local harfbuzz = require("harfbuzz")
local rig = require("rig")
local ffi = require("ffi")
local bit = bit

local face_mt = {}
face_mt.__index = face_mt

local sized_face_mt = {}
sized_face_mt.__index = sized_face_mt

local atlas_mt = {}
atlas_mt.__index = atlas_mt

local text_renderer_mt = {}
text_renderer_mt.__index = text_renderer_mt

local style_mt = {}
style_mt.__index = style_mt

local freetype_library = M._freetype_library or nil

local function normalize_face_index(face_index)
   if face_index == nil then
      return 0
   end

   local value = tonumber(face_index)
   if value == nil or value < 0 then
      error("font.load_face expects face_index to be a non-negative number if provided", 0)
   end

   value = math.floor(value)
   if value < 0 then
      value = 0
   end

   return value
end

local function normalize_pixel_size(pixel_size)
   local value = tonumber(pixel_size)
   if value == nil or value <= 0 then
      error("font.create_sized_face expects pixel_size to be a positive number", 0)
   end

   value = math.floor(value)
   if value < 1 then
      value = 1
   end

   return value
end

local function normalize_atlas_dimension(name, value, default_value)
   if value == nil then
      return default_value
   end

   local normalized = tonumber(value)
   if normalized == nil or normalized <= 0 then
      error(("font.create_atlas expects options.%s to be a positive number if provided"):format(name), 0)
   end

   normalized = math.floor(normalized)
   if normalized < 1 then
      normalized = 1
   end

   return normalized
end

local function ensure_freetype_library()
   if freetype_library ~= nil and freetype_library ~= ffi.NULL then
      return freetype_library
   end

   local library_out = ffi.new("FT_Library[1]")
   local rc = freetype.Init_FreeType(library_out)
   if rc ~= 0 then
      error(("freetype.Init_FreeType failed with error %d"):format(rc), 0)
   end

   freetype_library = library_out[0]
   M._freetype_library = freetype_library
   return freetype_library
end

local function copy_bitmap_data(bitmap)
   local rows = tonumber(bitmap.rows) or 0
   if rows <= 0 or bitmap.buffer == nil or bitmap.buffer == ffi.NULL then
      return ""
   end

   local pitch = tonumber(bitmap.pitch) or 0
   local byte_count = math.abs(pitch) * rows
   if byte_count <= 0 then
      return ""
   end

   return ffi.string(bitmap.buffer, byte_count)
end

local function wrap_face(path, face_index, ft_face)
   return setmetatable({
      path = path,
      face_index = face_index,
      family_name = ft_face.family_name ~= nil and ft_face.family_name ~= ffi.NULL
         and ffi.string(ft_face.family_name) or nil,
      style_name = ft_face.style_name ~= nil and ft_face.style_name ~= ffi.NULL
         and ffi.string(ft_face.style_name) or nil,
      num_glyphs = tonumber(ft_face.num_glyphs) or 0,
      units_per_em = tonumber(ft_face.units_per_EM) or 0,
      face_flags = tonumber(ft_face.face_flags) or 0,
      style_flags = tonumber(ft_face.style_flags) or 0,
      _ft_face = ffi.gc(ft_face, freetype.Done_Face),
      _released = false,
   }, face_mt)
end

local function open_face(path, face_index)
   local face_out = ffi.new("FT_Face[1]")
   local rc = freetype.New_Face(ensure_freetype_library(), path, face_index, face_out)
   if rc ~= 0 then
      error(
         ("freetype.New_Face failed for '%s' (face %d) with error %d"):format(
            path,
            face_index,
            rc
         ),
         0
      )
   end

   return face_out[0]
end

local function ensure_face(face)
   if getmetatable(face) ~= face_mt then
      error("font.create_sized_face expects a face returned by font.load_face", 0)
   end
   if face._released then
      error("font face has been released", 0)
   end
end

local function ensure_sized_face(sized_face)
   if getmetatable(sized_face) ~= sized_face_mt then
      error("font operation expects a sized face created by font.create_sized_face", 0)
   end
   if sized_face._released then
      error("font sized face has been released", 0)
   end
end

local function ensure_atlas(atlas)
   if getmetatable(atlas) ~= atlas_mt then
      error("font operation expects an atlas created by font.create_atlas", 0)
   end
   if atlas._released then
      error("font atlas has been released", 0)
   end
end

local function ensure_text_renderer(text_renderer)
   if getmetatable(text_renderer) ~= text_renderer_mt then
      error("font operation expects a text renderer created by font.create_text_renderer", 0)
   end
   if text_renderer._released then
      error("font text renderer has been released", 0)
   end
end

local function ensure_style(style)
   if getmetatable(style) ~= style_mt then
      error("font operation expects a style created by font.create_style", 0)
   end
   if style._released then
      error("font style has been released", 0)
   end
end

function face_mt:release()
   if self._released then
      return
   end

   local ft_face = self._ft_face
   if ft_face ~= nil and ft_face ~= ffi.NULL then
      ffi.gc(ft_face, nil)
      freetype.Done_Face(ft_face)
   end
   self._ft_face = nil
   self._released = true
end

function face_mt:create_sized_face(pixel_size)
   return M.create_sized_face(self, pixel_size)
end

function sized_face_mt:release()
   if self._released then
      return
   end

   local hb_font = self._hb_font
   if hb_font ~= nil and hb_font ~= ffi.NULL then
      ffi.gc(hb_font, nil)
      harfbuzz.font_destroy(hb_font)
   end

   local ft_face = self._ft_face
   if ft_face ~= nil and ft_face ~= ffi.NULL then
      ffi.gc(ft_face, nil)
      freetype.Done_Face(ft_face)
   end

   self._hb_font = nil
   self._ft_face = nil
   self._glyph_cache = nil
   self._released = true
end

function sized_face_mt:get_cached_glyph(glyph_id)
   return M.get_cached_glyph(self, glyph_id)
end

function sized_face_mt:create_atlas(options)
   return M.create_atlas(self, options)
end

function atlas_mt:release()
   if self._released then
      return
   end

   self.pages = {}
   self._glyphs = {}
   self._released = true
end

function atlas_mt:get_glyph(glyph_id)
   return M.atlas_get_glyph(self, glyph_id)
end

function atlas_mt:get_page_data(page_index)
   if self._released then
      error("font atlas has been released", 0)
   end

   local page = self.pages[page_index]
   if page == nil then
      return nil
   end

   return ffi.string(page.buffer, page.width * page.height)
end

function atlas_mt:build_text_run(text, options)
   return M.build_text_run(self, text, options)
end

function atlas_mt:warm_text(text, options)
   return M.warm_text(self, text, options)
end

function atlas_mt:create_text_renderer()
   return M.create_text_renderer(self)
end

function text_renderer_mt:release()
   return M.release_text_renderer(self)
end

function text_renderer_mt:draw_packed_glyph(packed, x, y, scale, r, g, b, a)
   return M.draw_packed_glyph(self, packed, x, y, scale, r, g, b, a)
end

function text_renderer_mt:draw_text_run(run, base_x, baseline_y, color_fn)
   return M.draw_text_run(self, run, base_x, baseline_y, color_fn)
end

function style_mt:release()
   return M.release_style(self)
end

function style_mt:get_glyph(glyph_id)
   ensure_style(self)
   return self.atlas:get_glyph(glyph_id)
end

function style_mt:build_run(text, options)
   ensure_style(self)
   return self.atlas:build_text_run(text, options)
end

function style_mt:warm_text(text, options)
   ensure_style(self)
   return self.atlas:warm_text(text, options)
end

function style_mt:draw_packed_glyph(packed, x, y, scale, r, g, b, a)
   ensure_style(self)
   return self.text_renderer:draw_packed_glyph(packed, x, y, scale, r, g, b, a)
end

function style_mt:draw_run(run, base_x, baseline_y, color_fn)
   ensure_style(self)
   return self.text_renderer:draw_text_run(run, base_x, baseline_y, color_fn)
end

function style_mt:draw_text(text, base_x, baseline_y, color_fn, options)
   ensure_style(self)
   local run = self:build_run(text, options)
   return self:draw_run(run, base_x, baseline_y, color_fn)
end

function M.load_face(path, face_index)
   if type(path) ~= "string" or path == "" then
      error("font.load_face expects path to be a non-empty string", 0)
   end

   local normalized_face_index = normalize_face_index(face_index)
   local ft_face = open_face(path, normalized_face_index)
   return wrap_face(path, normalized_face_index, ft_face)
end

function M.create_sized_face(face, pixel_size)
   ensure_face(face)

   local normalized_pixel_size = normalize_pixel_size(pixel_size)
   local ft_face = open_face(face.path, face.face_index)
   local rc = freetype.Set_Pixel_Sizes(ft_face, 0, normalized_pixel_size)
   if rc ~= 0 then
      freetype.Done_Face(ft_face)
      error(
         ("freetype.Set_Pixel_Sizes failed for '%s' size %d with error %d"):format(
            face.path,
            normalized_pixel_size,
            rc
         ),
         0
      )
   end

   local hb_font = harfbuzz.ft_font_create_referenced(ft_face)
   if hb_font == nil or hb_font == ffi.NULL then
      freetype.Done_Face(ft_face)
      error("harfbuzz.ft_font_create_referenced returned nil", 0)
   end

   harfbuzz.ft_font_set_load_flags(
      hb_font,
      bit.bor(freetype.LOAD_DEFAULT, freetype.LOAD_TARGET_NORMAL)
   )

   return setmetatable({
      face = face,
      pixel_size = normalized_pixel_size,
      ascender = tonumber(ft_face.size.metrics.ascender) / 64.0,
      descender = tonumber(ft_face.size.metrics.descender) / 64.0,
      height = tonumber(ft_face.size.metrics.height) / 64.0,
      max_advance = tonumber(ft_face.size.metrics.max_advance) / 64.0,
      x_ppem = tonumber(ft_face.size.metrics.x_ppem) or normalized_pixel_size,
      y_ppem = tonumber(ft_face.size.metrics.y_ppem) or normalized_pixel_size,
      _glyph_cache = {},
      _ft_face = ffi.gc(ft_face, freetype.Done_Face),
      _hb_font = ffi.gc(hb_font, harfbuzz.font_destroy),
      _released = false,
   }, sized_face_mt)
end

function M.create_style(face, options)
   ensure_face(face)
   if type(options) ~= "table" then
      error("font.create_style expects options to be a table", 0)
   end

   local sized_face = M.create_sized_face(face, options.pixel_size)
   local atlas = nil
   local text_renderer = nil

   local ok, err = pcall(function()
      atlas = M.create_atlas(sized_face, {
         page_width = options.page_width,
         page_height = options.page_height,
         padding = options.padding,
      })
      text_renderer = M.create_text_renderer(atlas)
   end)

   if not ok then
      if atlas ~= nil then
         atlas:release()
      end
      sized_face:release()
      error(err, 0)
   end

   return setmetatable({
      face = face,
      sized_face = sized_face,
      atlas = atlas,
      text_renderer = text_renderer,
      pixel_size = sized_face.pixel_size,
      _released = false,
   }, style_mt)
end

function M.shape(sized_face, text, options)
   ensure_sized_face(sized_face)
   if type(text) ~= "string" then
      error("font.shape expects text to be a string", 0)
   end
   if options ~= nil and type(options) ~= "table" then
      error("font.shape expects options to be a table if provided", 0)
   end

   local hb_buffer = ffi.gc(harfbuzz.buffer_create(), harfbuzz.buffer_destroy)
   if hb_buffer == nil or hb_buffer == ffi.NULL then
      error("harfbuzz.buffer_create returned nil", 0)
   end

   harfbuzz.buffer_add_utf8(hb_buffer, text, #text, 0, -1)

   local use_guess = true
   if options ~= nil then
      if options.direction ~= nil then
         harfbuzz.buffer_set_direction(hb_buffer, options.direction)
         use_guess = false
      end
      if options.script ~= nil then
         harfbuzz.buffer_set_script(hb_buffer, options.script)
         use_guess = false
      end
      if options.language ~= nil then
         if type(options.language) ~= "string" or options.language == "" then
            error("font.shape expects options.language to be a non-empty string if provided", 0)
         end
         harfbuzz.buffer_set_language(
            hb_buffer,
            harfbuzz.language_from_string(options.language, -1)
         )
         use_guess = false
      end
      if options.cluster_level ~= nil then
         harfbuzz.buffer_set_cluster_level(hb_buffer, options.cluster_level)
      end
   end

   if use_guess then
      harfbuzz.buffer_guess_segment_properties(hb_buffer)
   end

   harfbuzz.shape(sized_face._hb_font, hb_buffer, nil, 0)

   local length_out = ffi.new("unsigned int[1]")
   local infos = harfbuzz.buffer_get_glyph_infos(hb_buffer, length_out)
   local positions = harfbuzz.buffer_get_glyph_positions(hb_buffer, length_out)
   local glyph_count = tonumber(length_out[0]) or 0

   local glyphs = {}
   local x_advance = 0.0
   local y_advance = 0.0

   for i = 0, glyph_count - 1 do
      local info = infos[i]
      local position = positions[i]
      local glyph = {
         glyph_id = tonumber(info.codepoint) or 0,
         cluster = tonumber(info.cluster) or 0,
         x_advance = (tonumber(position.x_advance) or 0) / 64.0,
         y_advance = (tonumber(position.y_advance) or 0) / 64.0,
         x_offset = (tonumber(position.x_offset) or 0) / 64.0,
         y_offset = (tonumber(position.y_offset) or 0) / 64.0,
      }
      x_advance = x_advance + glyph.x_advance
      y_advance = y_advance + glyph.y_advance
      glyphs[#glyphs + 1] = glyph
   end

   ffi.gc(hb_buffer, nil)
   harfbuzz.buffer_destroy(hb_buffer)

   return {
      text = text,
      glyphs = glyphs,
      glyph_count = glyph_count,
      x_advance = x_advance,
      y_advance = y_advance,
   }
end

function M.build_text_run(atlas, text, options)
   ensure_atlas(atlas)
   if type(text) ~= "string" then
      error("font.build_text_run expects text to be a string", 0)
   end
   if options ~= nil and type(options) ~= "table" then
      error("font.build_text_run expects options to be a table if provided", 0)
   end

   local shaped = M.shape(atlas.sized_face, text, options)
   local entries = {}
   local pen_x = 0.0
   local pen_y = 0.0

   for i = 1, #shaped.glyphs do
      local glyph = shaped.glyphs[i]
      local packed = atlas:get_glyph(glyph.glyph_id)
      entries[#entries + 1] = {
         packed = packed,
         layout_x = pen_x + glyph.x_offset + packed.left,
         layout_y = pen_y - glyph.y_offset - packed.top,
         cluster = glyph.cluster,
      }
      pen_x = pen_x + glyph.x_advance
      pen_y = pen_y + glyph.y_advance
   end

   return {
      text = text,
      width = shaped.x_advance,
      glyph_count = shaped.glyph_count,
      entries = entries,
   }
end

function M.warm_text(atlas, text, options)
   ensure_atlas(atlas)
   if type(text) ~= "string" then
      error("font.warm_text expects text to be a string", 0)
   end
   if options ~= nil and type(options) ~= "table" then
      error("font.warm_text expects options to be a table if provided", 0)
   end

   local shaped = M.shape(atlas.sized_face, text, options)
   for i = 1, #shaped.glyphs do
      atlas:get_glyph(shaped.glyphs[i].glyph_id)
   end
end

function M.rasterize_glyph(sized_face, glyph_id, options)
   ensure_sized_face(sized_face)

   local normalized_glyph_id = tonumber(glyph_id)
   if normalized_glyph_id == nil or normalized_glyph_id < 0 then
      error("font.rasterize_glyph expects glyph_id to be a non-negative number", 0)
   end
   normalized_glyph_id = math.floor(normalized_glyph_id)

   if options ~= nil and type(options) ~= "table" then
      error("font.rasterize_glyph expects options to be a table if provided", 0)
   end

   local render_mode = freetype.RENDER_MODE_NORMAL
   local load_flags = bit.bor(freetype.LOAD_DEFAULT, freetype.LOAD_RENDER, freetype.LOAD_TARGET_NORMAL)

   if options ~= nil then
      if options.render_mode ~= nil then
         render_mode = options.render_mode
      end
      if options.load_flags ~= nil then
         load_flags = options.load_flags
      end
   end

   local rc = freetype.Load_Glyph(sized_face._ft_face, normalized_glyph_id, load_flags)
   if rc ~= 0 then
      error(
         ("freetype.Load_Glyph failed for glyph %d with error %d"):format(
            normalized_glyph_id,
            rc
         ),
         0
      )
   end

   local glyph = sized_face._ft_face.glyph
   if glyph == nil or glyph == ffi.NULL then
      error("freetype face did not provide a glyph slot", 0)
   end

   if bit.band(load_flags, freetype.LOAD_RENDER) == 0 then
      local render_rc = freetype.Render_Glyph(glyph, render_mode)
      if render_rc ~= 0 then
         error(
            ("freetype.Render_Glyph failed for glyph %d with error %d"):format(
               normalized_glyph_id,
               render_rc
            ),
            0
         )
      end
   end

   local bitmap = glyph.bitmap
   return {
      glyph_id = normalized_glyph_id,
      width = tonumber(bitmap.width) or 0,
      height = tonumber(bitmap.rows) or 0,
      pitch = tonumber(bitmap.pitch) or 0,
      left = tonumber(glyph.bitmap_left) or 0,
      top = tonumber(glyph.bitmap_top) or 0,
      pixel_mode = tonumber(bitmap.pixel_mode) or 0,
      num_grays = tonumber(bitmap.num_grays) or 0,
      advance_x = (tonumber(glyph.advance.x) or 0) / 64.0,
      advance_y = (tonumber(glyph.advance.y) or 0) / 64.0,
      data = copy_bitmap_data(bitmap),
   }
end

function M.get_cached_glyph(sized_face, glyph_id)
   ensure_sized_face(sized_face)

   local normalized_glyph_id = tonumber(glyph_id)
   if normalized_glyph_id == nil or normalized_glyph_id < 0 then
      error("font.get_cached_glyph expects glyph_id to be a non-negative number", 0)
   end
   normalized_glyph_id = math.floor(normalized_glyph_id)

   local cached = sized_face._glyph_cache[normalized_glyph_id]
   if cached ~= nil then
      return cached
   end

   local glyph = M.rasterize_glyph(sized_face, normalized_glyph_id)
   sized_face._glyph_cache[normalized_glyph_id] = glyph
   return glyph
end

local function create_atlas_page(page_index, width, height)
   return {
      index = page_index,
      width = width,
      height = height,
      pixel_mode = freetype.PIXEL_MODE_GRAY,
      buffer = ffi.new("uint8_t[?]", width * height),
      revision = 0,
      next_x = 0,
      next_y = 0,
      row_height = 0,
   }
end

local function choose_page_for_glyph(atlas, glyph_width, glyph_height)
   local padding = atlas.padding
   local needed_width = glyph_width + padding * 2
   local needed_height = glyph_height + padding * 2

   if needed_width > atlas.page_width or needed_height > atlas.page_height then
      error(
         ("glyph %dx%d does not fit into atlas page %dx%d"):format(
            glyph_width,
            glyph_height,
            atlas.page_width,
            atlas.page_height
         ),
         0
      )
   end

   for i = 1, #atlas.pages do
      local page = atlas.pages[i]
      local place_x = page.next_x
      local place_y = page.next_y
      local row_height = page.row_height

      if place_x == 0 and place_y == 0 and row_height == 0 then
         place_x = padding
         place_y = padding
      end

      if place_x + glyph_width + padding <= page.width then
         if place_y + glyph_height + padding <= page.height then
            return page, place_x, place_y
         end
      end

      local new_row_y = place_y + row_height + padding
      if new_row_y + glyph_height + padding <= page.height then
         if padding + glyph_width + padding <= page.width then
            return page, padding, new_row_y
         end
      end
   end

   local new_page = create_atlas_page(
      #atlas.pages + 1,
      atlas.page_width,
      atlas.page_height
   )
   atlas.pages[#atlas.pages + 1] = new_page
   return new_page, padding, padding
end

local function write_gray_glyph(page, glyph, dest_x, dest_y)
   local width = glyph.width
   local height = glyph.height
   if width <= 0 or height <= 0 or #glyph.data == 0 then
      return
   end

   local source_stride = math.abs(glyph.pitch)
   local dest_stride = page.width

   for row = 0, height - 1 do
      local source_row
      if glyph.pitch >= 0 then
         source_row = row
      else
         source_row = height - 1 - row
      end

      local source_offset = source_row * source_stride
      local dest_offset = (dest_y + row) * dest_stride + dest_x

      if glyph.pixel_mode == freetype.PIXEL_MODE_GRAY then
         ffi.copy(page.buffer + dest_offset, glyph.data:sub(source_offset + 1), width)
      elseif glyph.pixel_mode == freetype.PIXEL_MODE_MONO then
         for col = 0, width - 1 do
            local byte_index = source_offset + math.floor(col / 8) + 1
            local bit_index = 7 - (col % 8)
            local value = glyph.data:byte(byte_index) or 0
            local on = bit.band(value, bit.lshift(1, bit_index)) ~= 0
            page.buffer[dest_offset + col] = on and 255 or 0
         end
      else
         error(
            ("font atlas does not support pixel_mode %d"):format(glyph.pixel_mode),
            0
         )
      end
   end
end

function M.create_atlas(sized_face, options)
   ensure_sized_face(sized_face)
   if options ~= nil and type(options) ~= "table" then
      error("font.create_atlas expects options to be a table if provided", 0)
   end

   local page_width = nil
   local page_height = nil
   local padding = nil
   if options ~= nil then
      page_width = options.page_width
      page_height = options.page_height
      padding = options.padding
   end

   local atlas = setmetatable({
      sized_face = sized_face,
      page_width = normalize_atlas_dimension("page_width", page_width, 256),
      page_height = normalize_atlas_dimension("page_height", page_height, 256),
      padding = normalize_atlas_dimension("padding", padding, 1),
      pages = {},
      _glyphs = {},
      _released = false,
   }, atlas_mt)

   return atlas
end

function M.atlas_get_glyph(atlas, glyph_id)
   ensure_atlas(atlas)

   local normalized_glyph_id = tonumber(glyph_id)
   if normalized_glyph_id == nil or normalized_glyph_id < 0 then
      error("font.atlas_get_glyph expects glyph_id to be a non-negative number", 0)
   end
   normalized_glyph_id = math.floor(normalized_glyph_id)

   local cached = atlas._glyphs[normalized_glyph_id]
   if cached ~= nil then
      return cached
   end

   local glyph = M.get_cached_glyph(atlas.sized_face, normalized_glyph_id)
   local page, x, y = choose_page_for_glyph(atlas, glyph.width, glyph.height)
   write_gray_glyph(page, glyph, x, y)
   page.revision = page.revision + 1

   page.next_x = x + glyph.width + atlas.padding
   if y ~= page.next_y then
      page.next_y = y
      page.row_height = glyph.height
   elseif glyph.height > page.row_height then
      page.row_height = glyph.height
   end

   local page_index = page.index
   local packed = {
      glyph_id = normalized_glyph_id,
      page_index = page_index,
      x = x,
      y = y,
      width = glyph.width,
      height = glyph.height,
      left = glyph.left,
      top = glyph.top,
      advance_x = glyph.advance_x,
      advance_y = glyph.advance_y,
      u0 = x / page.width,
      v0 = y / page.height,
      u1 = (x + glyph.width) / page.width,
      v1 = (y + glyph.height) / page.height,
      glyph = glyph,
   }

   atlas._glyphs[normalized_glyph_id] = packed
   return packed
end

rig.create_service("font.renderer", {
   "create_text_renderer",
   "release_text_renderer",
   "draw_packed_glyph",
   "draw_text_run",
})

function M.create_text_renderer(atlas)
   ensure_atlas(atlas)

   local provider = rig.require_service("font.renderer")
   local text_renderer = setmetatable({
      atlas = atlas,
      _provider = provider,
      _released = false,
   }, text_renderer_mt)

   text_renderer._state = provider.create_text_renderer(text_renderer)
   return text_renderer
end

function M.release_text_renderer(text_renderer)
   ensure_text_renderer(text_renderer)
   text_renderer._provider.release_text_renderer(text_renderer)
   text_renderer._state = nil
   text_renderer._released = true
end

function M.release_style(style)
   ensure_style(style)

   if style.text_renderer ~= nil and not style.text_renderer._released then
      style.text_renderer:release()
   end
   if style.atlas ~= nil and not style.atlas._released then
      style.atlas:release()
   end
   if style.sized_face ~= nil and not style.sized_face._released then
      style.sized_face:release()
   end

   style.text_renderer = nil
   style.atlas = nil
   style.sized_face = nil
   style._released = true
end

function M.draw_packed_glyph(text_renderer, packed, x, y, scale, r, g, b, a)
   ensure_text_renderer(text_renderer)
   if type(packed) ~= "table" then
      error("font.draw_packed_glyph expects packed to be a table", 0)
   end
   if type(x) ~= "number" then
      error("font.draw_packed_glyph expects x to be a number", 0)
   end
   if type(y) ~= "number" then
      error("font.draw_packed_glyph expects y to be a number", 0)
   end

   local draw_scale = scale
   if draw_scale == nil then
      draw_scale = 1.0
   end
   if type(draw_scale) ~= "number" then
      error("font.draw_packed_glyph expects scale to be a number if provided", 0)
   end

   local draw_r = r
   local draw_g = g
   local draw_b = b
   local draw_a = a
   if draw_r == nil then
      draw_r = 255
   end
   if draw_g == nil then
      draw_g = 255
   end
   if draw_b == nil then
      draw_b = 255
   end
   if draw_a == nil then
      draw_a = 255
   end

   text_renderer._provider.draw_packed_glyph(
      text_renderer,
      packed,
      x,
      y,
      draw_scale,
      draw_r,
      draw_g,
      draw_b,
      draw_a
   )
end

function M.draw_text_run(text_renderer, run, base_x, baseline_y, color_fn)
   ensure_text_renderer(text_renderer)
   if type(run) ~= "table" then
      error("font.draw_text_run expects run to be a table", 0)
   end
   if type(base_x) ~= "number" then
      error("font.draw_text_run expects base_x to be a number", 0)
   end
   if type(baseline_y) ~= "number" then
      error("font.draw_text_run expects baseline_y to be a number", 0)
   end
   if color_fn ~= nil and type(color_fn) ~= "function" then
      error("font.draw_text_run expects color_fn to be a function if provided", 0)
   end

   text_renderer._provider.draw_text_run(
      text_renderer,
      run,
      base_x,
      baseline_y,
      color_fn
   )
end

return M
