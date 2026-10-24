local M = ... or {}

local ffi = require("ffi")
local rig = require("rig")

-- JPEG decoding. `jpeg.c` holds only the setjmp-guarded libjpeg call; everything
-- else lives here and reaches it through FFI. The decoder is optional: rig
-- compiles the helper only when libjpeg headers are available, and this module
-- reports that case at decode time.

ffi.cdef[[
int rig_jpeg_decode(
   const void *data,
   size_t size,
   unsigned char **out_pixels,
   int *out_width,
   int *out_height
);
void rig_jpeg_free(void *pixels);
]]

-- Decodes JPEG `bytes` into top-down RGBA8 pixels.
-- Returns `{ width, height, channels = 4, pixels = <byte string> }` or
-- `nil, message`.
function M.decode(bytes, label)
   if type(bytes) ~= "string" then
      rig.raise("jpeg.decode expects a byte string")
   end
   label = label or "image"

   local out_pixels = ffi.new("unsigned char *[1]")
   local width = ffi.new("int[1]")
   local height = ffi.new("int[1]")

   local status = ffi.C.rig_jpeg_decode(bytes, #bytes, out_pixels, width, height)
   if status == -2 then
      return nil, ("jpeg: JPEG support is not built into this rig (%s)"):format(label)
   end
   if status ~= 0 then
      return nil, ("jpeg: failed to decode %s"):format(label)
   end

   local w = tonumber(width[0]) or 0
   local h = tonumber(height[0]) or 0
   local pixels = ffi.string(out_pixels[0], w * h * 4)
   ffi.C.rig_jpeg_free(out_pixels[0])

   return {
      width = w,
      height = h,
      channels = 4,
      pixels = pixels,
   }
end

return M