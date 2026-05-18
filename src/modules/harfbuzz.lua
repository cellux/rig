local M = ... or {}
local ffi = require("ffi")

ffi.cdef[[
typedef int hb_bool_t;
typedef uint32_t hb_codepoint_t;
typedef int32_t hb_position_t;
typedef uint32_t hb_mask_t;
typedef uint32_t hb_tag_t;
typedef const struct hb_language_impl_t *hb_language_t;

typedef struct FT_FaceRec_ *FT_Face;

typedef union _hb_var_int_t {
   uint32_t u32;
   int32_t i32;
   uint16_t u16[2];
   int16_t i16[2];
   uint8_t u8[4];
   int8_t i8[4];
} hb_var_int_t;

typedef struct hb_feature_t {
   hb_tag_t tag;
   uint32_t value;
   unsigned int start;
   unsigned int end;
} hb_feature_t;

typedef struct hb_glyph_info_t {
   hb_codepoint_t codepoint;
   hb_mask_t mask;
   uint32_t cluster;
   hb_var_int_t var1;
   hb_var_int_t var2;
} hb_glyph_info_t;

typedef struct hb_glyph_position_t {
   hb_position_t x_advance;
   hb_position_t y_advance;
   hb_position_t x_offset;
   hb_position_t y_offset;
   hb_var_int_t var;
} hb_glyph_position_t;

typedef struct hb_blob_t hb_blob_t;
typedef struct hb_face_t hb_face_t;
typedef struct hb_font_t hb_font_t;
typedef struct hb_buffer_t hb_buffer_t;

hb_tag_t hb_tag_from_string(const char *str, int len);
void hb_tag_to_string(hb_tag_t tag, char *buf);

hb_language_t hb_language_from_string(const char *str, int len);
const char *hb_language_to_string(hb_language_t language);

hb_buffer_t *hb_buffer_create(void);
void hb_buffer_reset(hb_buffer_t *buffer);
hb_buffer_t *hb_buffer_reference(hb_buffer_t *buffer);
void hb_buffer_destroy(hb_buffer_t *buffer);
void hb_buffer_set_direction(hb_buffer_t *buffer, int direction);
int hb_buffer_get_direction(const hb_buffer_t *buffer);
void hb_buffer_set_script(hb_buffer_t *buffer, hb_tag_t script);
hb_tag_t hb_buffer_get_script(const hb_buffer_t *buffer);
void hb_buffer_set_language(hb_buffer_t *buffer, hb_language_t language);
hb_language_t hb_buffer_get_language(const hb_buffer_t *buffer);
void hb_buffer_guess_segment_properties(hb_buffer_t *buffer);
void hb_buffer_set_cluster_level(hb_buffer_t *buffer, int cluster_level);
int hb_buffer_get_cluster_level(const hb_buffer_t *buffer);
void hb_buffer_add_utf8(hb_buffer_t *buffer, const char *text, int text_length, unsigned int item_offset, int item_length);
unsigned int hb_buffer_get_length(const hb_buffer_t *buffer);
hb_glyph_info_t *hb_buffer_get_glyph_infos(hb_buffer_t *buffer, unsigned int *length);
hb_glyph_position_t *hb_buffer_get_glyph_positions(hb_buffer_t *buffer, unsigned int *length);

void hb_shape(hb_font_t *font, hb_buffer_t *buffer, const hb_feature_t *features, unsigned int num_features);
hb_bool_t hb_shape_full(hb_font_t *font, hb_buffer_t *buffer, const hb_feature_t *features, unsigned int num_features, const char * const *shaper_list);

hb_font_t *hb_font_reference(hb_font_t *font);
void hb_font_destroy(hb_font_t *font);
hb_face_t *hb_font_get_face(hb_font_t *font);

hb_face_t *hb_ft_face_create_referenced(FT_Face ft_face);
hb_font_t *hb_ft_font_create_referenced(FT_Face ft_face);
FT_Face hb_ft_font_get_ft_face(hb_font_t *font);
void hb_ft_font_set_load_flags(hb_font_t *font, int load_flags);
int hb_ft_font_get_load_flags(hb_font_t *font);
void hb_ft_font_changed(hb_font_t *font);
]]

local harfbuzz_library = nil
local harfbuzz_library_error = nil

local function load_harfbuzz_library()
   if harfbuzz_library ~= nil then
      return harfbuzz_library
   end
   if harfbuzz_library_error ~= nil then
      error(harfbuzz_library_error)
   end

   local candidates = {
      "harfbuzz",
      "libharfbuzz.so.0",
      "libharfbuzz.so",
      "harfbuzz.dll",
      "libharfbuzz.dylib",
   }
   local failures = {}

   for _, name in ipairs(candidates) do
      local ok, lib = pcall(ffi.load, name)
      if ok then
         harfbuzz_library = lib
         return lib
      end
      table.insert(failures, tostring(lib))
   end

   harfbuzz_library_error = "failed to load HarfBuzz library: "
      .. table.concat(failures, "; ")
   error(harfbuzz_library_error)
end

local function export_harfbuzz_function(export_name, symbol_name)
   M[export_name] = function(...)
      return load_harfbuzz_library()[symbol_name](...)
   end
end

export_harfbuzz_function("tag_from_string", "hb_tag_from_string")
export_harfbuzz_function("tag_to_string", "hb_tag_to_string")
export_harfbuzz_function("language_from_string", "hb_language_from_string")
export_harfbuzz_function("language_to_string", "hb_language_to_string")
export_harfbuzz_function("buffer_create", "hb_buffer_create")
export_harfbuzz_function("buffer_reset", "hb_buffer_reset")
export_harfbuzz_function("buffer_reference", "hb_buffer_reference")
export_harfbuzz_function("buffer_destroy", "hb_buffer_destroy")
export_harfbuzz_function("buffer_set_direction", "hb_buffer_set_direction")
export_harfbuzz_function("buffer_get_direction", "hb_buffer_get_direction")
export_harfbuzz_function("buffer_set_script", "hb_buffer_set_script")
export_harfbuzz_function("buffer_get_script", "hb_buffer_get_script")
export_harfbuzz_function("buffer_set_language", "hb_buffer_set_language")
export_harfbuzz_function("buffer_get_language", "hb_buffer_get_language")
export_harfbuzz_function("buffer_guess_segment_properties", "hb_buffer_guess_segment_properties")
export_harfbuzz_function("buffer_set_cluster_level", "hb_buffer_set_cluster_level")
export_harfbuzz_function("buffer_get_cluster_level", "hb_buffer_get_cluster_level")
export_harfbuzz_function("buffer_add_utf8", "hb_buffer_add_utf8")
export_harfbuzz_function("buffer_get_length", "hb_buffer_get_length")
export_harfbuzz_function("buffer_get_glyph_infos", "hb_buffer_get_glyph_infos")
export_harfbuzz_function("buffer_get_glyph_positions", "hb_buffer_get_glyph_positions")
export_harfbuzz_function("shape", "hb_shape")
export_harfbuzz_function("shape_full", "hb_shape_full")
export_harfbuzz_function("font_reference", "hb_font_reference")
export_harfbuzz_function("font_destroy", "hb_font_destroy")
export_harfbuzz_function("font_get_face", "hb_font_get_face")
export_harfbuzz_function("ft_face_create_referenced", "hb_ft_face_create_referenced")
export_harfbuzz_function("ft_font_create_referenced", "hb_ft_font_create_referenced")
export_harfbuzz_function("ft_font_get_ft_face", "hb_ft_font_get_ft_face")
export_harfbuzz_function("ft_font_set_load_flags", "hb_ft_font_set_load_flags")
export_harfbuzz_function("ft_font_get_load_flags", "hb_ft_font_get_load_flags")
export_harfbuzz_function("ft_font_changed", "hb_ft_font_changed")

return M
