local M = ... or {}

local ffi = require("ffi")
local rig = require("rig")

-- PNG decoding through libpng's simplified (`png_image`) API, which reports
-- errors through return codes instead of setjmp/longjmp, so it is safe to bind
-- with FFI. The library is loaded dynamically like the other system-backed
-- modules.

ffi.cdef[[
typedef unsigned int png_uint_32;
typedef int png_int_32;
typedef size_t png_alloc_size_t;
typedef struct png_control *png_controlp;

typedef struct png_image {
   png_controlp opaque;
   png_uint_32 version;
   png_uint_32 width;
   png_uint_32 height;
   png_uint_32 format;
   png_uint_32 flags;
   png_uint_32 colormap_entries;
   png_uint_32 warning_or_error;
   char message[64];
} png_image;

int png_image_begin_read_from_memory(png_image *image, const void *memory, size_t size);
int png_image_finish_read(
   png_image *image,
   void *background,
   void *buffer,
   png_int_32 row_stride,
   void *colormap
);
int png_image_write_to_memory(
   png_image *image,
   void *buffer,
   png_alloc_size_t *memory,
   int convert_to_8bit,
   const void *pixels,
   png_int_32 row_stride,
   const void *colormap
);
void png_image_free(png_image *image);
]]

local load_png_library = rig.create_ffi_library_loader({
   label = "libpng",
   candidates = {
      "png16",
      "libpng16.so.16",
      "libpng16.so",
      "libpng16.16.dylib",
      "libpng16.dll",
   },
})

local PNG_IMAGE_VERSION = 1
local PNG_FORMAT_RGBA = 0x03

local function message_of(image)
   local message = ffi.string(image[0].message)
   if message == "" then
      return "unknown libpng error"
   end
   return message
end

-- Decodes PNG `bytes` into top-down RGBA8 pixels.
-- Returns `{ width, height, channels = 4, pixels = <byte string> }` or
-- `nil, message`.
function M.decode(bytes, label)
   if type(bytes) ~= "string" then
      rig.raise("png.decode expects a byte string")
   end
   label = label or "image"

   local lib = load_png_library()
   local image = ffi.new("png_image[1]")
   image[0].opaque = nil
   image[0].version = PNG_IMAGE_VERSION

   if lib.png_image_begin_read_from_memory(image, bytes, #bytes) == 0 then
      local message = message_of(image)
      lib.png_image_free(image)
      return nil, ("png: failed to read %s: %s"):format(label, message)
   end

   image[0].format = PNG_FORMAT_RGBA
   local width = tonumber(image[0].width) or 0
   local height = tonumber(image[0].height) or 0

   if width == 0 or height == 0 then
      lib.png_image_free(image)
      return nil, ("png: %s has zero size"):format(label)
   end

   local size = width * height * 4
   local pixels = ffi.new("unsigned char[?]", size)

   if lib.png_image_finish_read(image, nil, pixels, 0, nil) == 0 then
      local message = message_of(image)
      lib.png_image_free(image)
      return nil, ("png: failed to decode %s: %s"):format(label, message)
   end
   lib.png_image_free(image)

   return {
      width = width,
      height = height,
      channels = 4,
      pixels = ffi.string(pixels, size),
   }
end

-- Encodes top-down RGBA8 pixels as a PNG byte string. Returns `nil, message`
-- when libpng rejects the image. `label` names the image in error messages.
function M.encode(image, label)
   if type(image) ~= "table"
      or type(image.width) ~= "number"
      or type(image.height) ~= "number"
      or image.pixels == nil
   then
      rig.raise("png.encode expects an image with width, height, and pixels")
   end

   label = label or "image"
   local width = math.floor(image.width)
   local height = math.floor(image.height)
   if width <= 0 or height <= 0 then
      rig.raise("png.encode image dimensions must be positive")
   end

   local lib = load_png_library()
   local png_image = ffi.new("png_image[1]")
   png_image[0].opaque = nil
   png_image[0].version = PNG_IMAGE_VERSION
   png_image[0].width = width
   png_image[0].height = height
   png_image[0].format = PNG_FORMAT_RGBA
   png_image[0].flags = 0
   png_image[0].colormap_entries = 0

   local size = ffi.new("png_alloc_size_t[1]", 0)
   if lib.png_image_write_to_memory(png_image, nil, size, 0, image.pixels, 0, nil) == 0 then
      local message = message_of(png_image)
      lib.png_image_free(png_image)
      return nil, ("png: failed to size %s: %s"):format(label, message)
   end

   local capacity = tonumber(size[0]) or 0
   if capacity == 0 then
      lib.png_image_free(png_image)
      return nil, ("png: encoder returned zero size for %s"):format(label)
   end

   local buffer = ffi.new("unsigned char[?]", capacity)
   if lib.png_image_write_to_memory(png_image, buffer, size, 0, image.pixels, 0, nil) == 0 then
      local message = message_of(png_image)
      lib.png_image_free(png_image)
      return nil, ("png: failed to encode %s: %s"):format(label, message)
   end
   lib.png_image_free(png_image)

   return ffi.string(buffer, tonumber(size[0]) or capacity)
end

return M
