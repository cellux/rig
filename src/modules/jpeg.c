/* Minimal C helper for `jpeg.lua`.
 *
 * libjpeg reports fatal errors through a `longjmp` out of its error handler,
 * which cannot be expressed safely in pure LuaJIT FFI. This file contains only
 * that guarded decode; path handling, caching and pixel wrapping live in
 * `jpeg.lua`.
 */

#include <lua.h>

#include <stdlib.h>

#if defined(RIG_HAVE_JPEG) && RIG_HAVE_JPEG

#include <setjmp.h>
#include <stdio.h>
#include <string.h>

#include <jpeglib.h>

typedef struct {
  struct jpeg_error_mgr pub;
  jmp_buf jump;
} rig_jpeg_error;

static void rig_jpeg_error_exit(j_common_ptr cinfo) {
  rig_jpeg_error *error = (rig_jpeg_error *)cinfo->err;
  (*cinfo->err->output_message)(cinfo);
  longjmp(error->jump, 1);
}

/* Decodes `size` bytes of JPEG data into a malloc'd top-down RGBA8 buffer.
 * Returns 0 on success, -1 on decode failure. */
int rig_jpeg_decode(const void *data, size_t size, unsigned char **out_pixels,
                    int *out_width, int *out_height) {
  struct jpeg_decompress_struct cinfo;
  rig_jpeg_error error;
  unsigned char *rgba = NULL;
  unsigned char *row = NULL;
  int width;
  int height;

  memset(&cinfo, 0, sizeof(cinfo));
  cinfo.err = jpeg_std_error(&error.pub);
  error.pub.error_exit = rig_jpeg_error_exit;

  if (setjmp(error.jump)) {
    jpeg_destroy_decompress(&cinfo);
    free(row);
    free(rgba);
    return -1;
  }

  jpeg_create_decompress(&cinfo);
  jpeg_mem_src(&cinfo, (const unsigned char *)data, (unsigned long)size);
  jpeg_read_header(&cinfo, TRUE);
  cinfo.out_color_space = JCS_RGB;
  jpeg_start_decompress(&cinfo);

  width = (int)cinfo.output_width;
  height = (int)cinfo.output_height;
  if (width <= 0 || height <= 0) {
    jpeg_destroy_decompress(&cinfo);
    return -1;
  }

  rgba = (unsigned char *)malloc((size_t)width * (size_t)height * 4u);
  row = (unsigned char *)malloc((size_t)width * 3u);
  if (rgba == NULL || row == NULL) {
    jpeg_destroy_decompress(&cinfo);
    free(row);
    free(rgba);
    return -1;
  }

  while (cinfo.output_scanline < cinfo.output_height) {
    unsigned char *rows[1];
    size_t y;
    unsigned char *dst;
    int x;

    rows[0] = row;
    jpeg_read_scanlines(&cinfo, rows, 1);
    y = (size_t)cinfo.output_scanline - 1u;
    dst = rgba + y * (size_t)width * 4u;
    for (x = 0; x < width; x++) {
      dst[x * 4 + 0] = row[x * 3 + 0];
      dst[x * 4 + 1] = row[x * 3 + 1];
      dst[x * 4 + 2] = row[x * 3 + 2];
      dst[x * 4 + 3] = 255u;
    }
  }

  jpeg_finish_decompress(&cinfo);
  jpeg_destroy_decompress(&cinfo);

  free(row);
  *out_pixels = rgba;
  *out_width = width;
  *out_height = height;
  return 0;
}

void rig_jpeg_free(void *pixels) { free(pixels); }

#else /* !RIG_HAVE_JPEG */

/* Stub so the module builds and registers identically without libjpeg headers;
 * `jpeg.lua` reports the missing support to the caller. */

int rig_jpeg_decode(const void *data, size_t size, unsigned char **out_pixels,
                    int *out_width, int *out_height) {
  (void)data;
  (void)size;
  (void)out_pixels;
  (void)out_width;
  (void)out_height;
  return -2;
}

void rig_jpeg_free(void *pixels) { (void)pixels; }

#endif

void rig_register_jpeg(lua_State *L) { (void)L; }
