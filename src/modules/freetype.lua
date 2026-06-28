local M = ... or {}
local ffi = require("ffi")
local rig = require("rig")

ffi.cdef[[
typedef unsigned char FT_Bool;
typedef signed char FT_Char;
typedef unsigned char FT_Byte;
typedef char FT_String;
typedef signed short FT_Short;
typedef unsigned short FT_UShort;
typedef signed int FT_Int;
typedef unsigned int FT_UInt;
typedef signed long FT_Long;
typedef unsigned long FT_ULong;
typedef signed long FT_F26Dot6;
typedef signed long FT_Fixed;
typedef signed long FT_Pos;
typedef int FT_Error;
typedef int32_t FT_Int32;

typedef struct FT_LibraryRec_ *FT_Library;
typedef struct FT_FaceRec_ *FT_Face;
typedef struct FT_SizeRec_ *FT_Size;
typedef struct FT_GlyphSlotRec_ *FT_GlyphSlot;
typedef struct FT_CharMapRec_ *FT_CharMap;
typedef struct FT_DriverRec_ *FT_Driver;
typedef struct FT_MemoryRec_ *FT_Memory;
typedef struct FT_StreamRec_ *FT_Stream;
typedef struct FT_Face_InternalRec_ *FT_Face_Internal;
typedef struct FT_Size_InternalRec_ *FT_Size_Internal;
typedef struct FT_Slot_InternalRec_ *FT_Slot_Internal;
typedef struct FT_SubGlyphRec_ *FT_SubGlyph;
typedef struct FT_ListNodeRec_ *FT_ListNode;

typedef void (*FT_Generic_Finalizer)(void *object);

typedef struct FT_Vector_ {
   FT_Pos x;
   FT_Pos y;
} FT_Vector;

typedef struct FT_BBox_ {
   FT_Pos xMin;
   FT_Pos yMin;
   FT_Pos xMax;
   FT_Pos yMax;
} FT_BBox;

typedef struct FT_Generic_ {
   void *data;
   FT_Generic_Finalizer finalizer;
} FT_Generic;

typedef struct FT_ListRec_ {
   FT_ListNode head;
   FT_ListNode tail;
} FT_ListRec;

typedef struct FT_Bitmap_ {
   unsigned int rows;
   unsigned int width;
   int pitch;
   unsigned char *buffer;
   unsigned short num_grays;
   unsigned char pixel_mode;
   unsigned char palette_mode;
   void *palette;
} FT_Bitmap;

typedef struct FT_Outline_ {
   unsigned short n_contours;
   unsigned short n_points;
   FT_Vector *points;
   unsigned char *tags;
   unsigned short *contours;
   int flags;
} FT_Outline;

typedef struct FT_Bitmap_Size_ {
   FT_Short height;
   FT_Short width;
   FT_Pos size;
   FT_Pos x_ppem;
   FT_Pos y_ppem;
} FT_Bitmap_Size;

typedef struct FT_Glyph_Metrics_ {
   FT_Pos width;
   FT_Pos height;
   FT_Pos horiBearingX;
   FT_Pos horiBearingY;
   FT_Pos horiAdvance;
   FT_Pos vertBearingX;
   FT_Pos vertBearingY;
   FT_Pos vertAdvance;
} FT_Glyph_Metrics;

typedef struct FT_Size_Metrics_ {
   FT_UShort x_ppem;
   FT_UShort y_ppem;
   FT_Fixed x_scale;
   FT_Fixed y_scale;
   FT_Pos ascender;
   FT_Pos descender;
   FT_Pos height;
   FT_Pos max_advance;
} FT_Size_Metrics;

typedef struct FT_SizeRec_ {
   FT_Face face;
   FT_Generic generic;
   FT_Size_Metrics metrics;
   FT_Size_Internal internal;
} FT_SizeRec;

typedef struct FT_GlyphSlotRec_ {
   FT_Library library;
   FT_Face face;
   FT_GlyphSlot next;
   FT_UInt glyph_index;
   FT_Generic generic;
   FT_Glyph_Metrics metrics;
   FT_Fixed linearHoriAdvance;
   FT_Fixed linearVertAdvance;
   FT_Vector advance;
   FT_Int format;
   FT_Bitmap bitmap;
   FT_Int bitmap_left;
   FT_Int bitmap_top;
   FT_Outline outline;
   FT_UInt num_subglyphs;
   FT_SubGlyph subglyphs;
   void *control_data;
   long control_len;
   FT_Pos lsb_delta;
   FT_Pos rsb_delta;
   void *other;
   FT_Slot_Internal internal;
} FT_GlyphSlotRec;

typedef struct FT_FaceRec_ {
   FT_Long num_faces;
   FT_Long face_index;
   FT_Long face_flags;
   FT_Long style_flags;
   FT_Long num_glyphs;
   FT_String *family_name;
   FT_String *style_name;
   FT_Int num_fixed_sizes;
   FT_Bitmap_Size *available_sizes;
   FT_Int num_charmaps;
   FT_CharMap *charmaps;
   FT_Generic generic;
   FT_BBox bbox;
   FT_UShort units_per_EM;
   FT_Short ascender;
   FT_Short descender;
   FT_Short height;
   FT_Short max_advance_width;
   FT_Short max_advance_height;
   FT_Short underline_position;
   FT_Short underline_thickness;
   FT_GlyphSlot glyph;
   FT_Size size;
   FT_CharMap charmap;
   FT_Driver driver;
   FT_Memory memory;
   FT_Stream stream;
   FT_ListRec sizes_list;
   FT_Generic autohint;
   void *extensions;
   FT_Face_Internal internal;
} FT_FaceRec;

FT_Error FT_Init_FreeType(FT_Library *alibrary);
FT_Error FT_Done_FreeType(FT_Library library);
void FT_Library_Version(FT_Library library, FT_Int *amajor, FT_Int *aminor, FT_Int *apatch);

FT_Error FT_New_Face(FT_Library library, const char *filepathname, FT_Long face_index, FT_Face *aface);
FT_Error FT_Done_Face(FT_Face face);
FT_Error FT_Reference_Face(FT_Face face);

FT_Error FT_Set_Char_Size(FT_Face face, FT_F26Dot6 char_width, FT_F26Dot6 char_height, FT_UInt horz_resolution, FT_UInt vert_resolution);
FT_Error FT_Set_Pixel_Sizes(FT_Face face, FT_UInt pixel_width, FT_UInt pixel_height);

FT_UInt FT_Get_Char_Index(FT_Face face, FT_ULong charcode);
FT_Error FT_Load_Glyph(FT_Face face, FT_UInt glyph_index, FT_Int32 load_flags);
FT_Error FT_Load_Char(FT_Face face, FT_ULong char_code, FT_Int32 load_flags);
FT_Error FT_Render_Glyph(FT_GlyphSlot slot, FT_Int render_mode);
FT_Error FT_Get_Kerning(FT_Face face, FT_UInt left_glyph, FT_UInt right_glyph, FT_UInt kern_mode, FT_Vector *akerning);
]]

local load_freetype_library = rig.create_ffi_library_loader({
   label = "FreeType",
   candidates = {
      "freetype",
      "libfreetype.so.6",
      "libfreetype.so",
      "freetype.dll",
      "libfreetype.dylib",
   },
})

local function export_freetype_function(export_name, symbol_name)
   M[export_name] = function(...)
      return load_freetype_library()[symbol_name](...)
   end
end

export_freetype_function("Init_FreeType", "FT_Init_FreeType")
export_freetype_function("Done_FreeType", "FT_Done_FreeType")
export_freetype_function("Library_Version", "FT_Library_Version")
export_freetype_function("New_Face", "FT_New_Face")
export_freetype_function("Done_Face", "FT_Done_Face")
export_freetype_function("Reference_Face", "FT_Reference_Face")
export_freetype_function("Set_Char_Size", "FT_Set_Char_Size")
export_freetype_function("Set_Pixel_Sizes", "FT_Set_Pixel_Sizes")
export_freetype_function("Get_Char_Index", "FT_Get_Char_Index")
export_freetype_function("Load_Glyph", "FT_Load_Glyph")
export_freetype_function("Load_Char", "FT_Load_Char")
export_freetype_function("Render_Glyph", "FT_Render_Glyph")
export_freetype_function("Get_Kerning", "FT_Get_Kerning")

return M
