/* Minimal C helper for `jpeg.lua`.
 *
 * libjpeg reports fatal errors through a `longjmp` out of its error handler,
 * which cannot be expressed safely in pure LuaJIT FFI. This file contains only
 * that guarded decode; path handling, caching and pixel wrapping live in
 * `jpeg.lua`.
 *
 * libjpeg is resolved at runtime through the `dl` loader, so rig has no hard
 * runtime dependency on a particular libjpeg soname. The headers remain a
 * compile-time dependency (struct layout and `JPEG_LIB_VERSION`).
 */

#include <lua.h>

#include <stdlib.h>

#if defined(RIG_HAVE_JPEG) && RIG_HAVE_JPEG

#include <setjmp.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include <jpeglib.h>

/* Entry points provided by `dl.c`. */
extern void *rig_dl_open(const char *path);
extern void *rig_dl_sym(void *handle, const char *name);
extern int rig_dl_close(void *handle);

typedef struct jpeg_error_mgr *(*rig_jpeg__std_error_fn)(
    struct jpeg_error_mgr *);
typedef void (*rig_jpeg__create_decompress_fn)(j_decompress_ptr, int, size_t);
typedef void (*rig_jpeg__destroy_decompress_fn)(j_decompress_ptr);
typedef void (*rig_jpeg__mem_src_fn)(j_decompress_ptr, const unsigned char *,
                                     unsigned long);
typedef int (*rig_jpeg__read_header_fn)(j_decompress_ptr, int);
typedef int (*rig_jpeg__start_decompress_fn)(j_decompress_ptr);
typedef unsigned int (*rig_jpeg__read_scanlines_fn)(j_decompress_ptr,
                                                    JSAMPARRAY, JDIMENSION);
typedef int (*rig_jpeg__finish_decompress_fn)(j_decompress_ptr);

static rig_jpeg__std_error_fn rig_jpeg__jpeg_std_error;
static rig_jpeg__create_decompress_fn rig_jpeg__jpeg_CreateDecompress;
static rig_jpeg__destroy_decompress_fn rig_jpeg__jpeg_destroy_decompress;
static rig_jpeg__mem_src_fn rig_jpeg__jpeg_mem_src;
static rig_jpeg__read_header_fn rig_jpeg__jpeg_read_header;
static rig_jpeg__start_decompress_fn rig_jpeg__jpeg_start_decompress;
static rig_jpeg__read_scanlines_fn rig_jpeg__jpeg_read_scanlines;
static rig_jpeg__finish_decompress_fn rig_jpeg__jpeg_finish_decompress;

static int rig_jpeg_load_attempted = 0;
static int rig_jpeg_loaded = 0;

static const char *rig_jpeg_candidates[] = {
    "libjpeg.so.62",   "libjpeg.so",     "libjpeg.62.dylib",
    "libjpeg.dylib",   "libjpeg-62.dll", "jpeg.dll",
    NULL,
};

static int rig_jpeg_bind_all(void *handle) {
  void *symbol;

#define RIG_JPEG_BIND(field, symbol_name)                                      \
  do {                                                                         \
    symbol = rig_dl_sym(handle, symbol_name);                                  \
    if (symbol == NULL) {                                                      \
      return 0;                                                                \
    }                                                                          \
    *(void **)(&(field)) = symbol;                                             \
  } while (0)

  RIG_JPEG_BIND(rig_jpeg__jpeg_std_error, "jpeg_std_error");
  RIG_JPEG_BIND(rig_jpeg__jpeg_CreateDecompress, "jpeg_CreateDecompress");
  RIG_JPEG_BIND(rig_jpeg__jpeg_destroy_decompress, "jpeg_destroy_decompress");
  RIG_JPEG_BIND(rig_jpeg__jpeg_mem_src, "jpeg_mem_src");
  RIG_JPEG_BIND(rig_jpeg__jpeg_read_header, "jpeg_read_header");
  RIG_JPEG_BIND(rig_jpeg__jpeg_start_decompress, "jpeg_start_decompress");
  RIG_JPEG_BIND(rig_jpeg__jpeg_read_scanlines, "jpeg_read_scanlines");
  RIG_JPEG_BIND(rig_jpeg__jpeg_finish_decompress, "jpeg_finish_decompress");

#undef RIG_JPEG_BIND
  return 1;
}

static int rig_jpeg_load(void) {
  size_t i;

  if (rig_jpeg_load_attempted) {
    return rig_jpeg_loaded;
  }
  rig_jpeg_load_attempted = 1;

  for (i = 0; rig_jpeg_candidates[i] != NULL; i++) {
    void *handle = rig_dl_open(rig_jpeg_candidates[i]);
    if (handle == NULL) {
      continue;
    }
    if (rig_jpeg_bind_all(handle)) {
      rig_jpeg_loaded = 1;
      return 1;
    }
    rig_dl_close(handle);
  }

  return 0;
}

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
 * Returns 0 on success, -1 on decode failure, -2 when libjpeg is unavailable. */
int rig_jpeg_decode(const void *data, size_t size, unsigned char **out_pixels,
                    int *out_width, int *out_height) {
  struct jpeg_decompress_struct cinfo;
  rig_jpeg_error error;
  unsigned char *rgba = NULL;
  unsigned char *row = NULL;
  int width;
  int height;

  if (!rig_jpeg_load()) {
    return -2;
  }

  memset(&cinfo, 0, sizeof(cinfo));
  cinfo.err = rig_jpeg__jpeg_std_error(&error.pub);
  error.pub.error_exit = rig_jpeg_error_exit;

  if (setjmp(error.jump)) {
    rig_jpeg__jpeg_destroy_decompress(&cinfo);
    free(row);
    free(rgba);
    return -1;
  }

  rig_jpeg__jpeg_CreateDecompress(&cinfo, JPEG_LIB_VERSION, sizeof(cinfo));
  rig_jpeg__jpeg_mem_src(&cinfo, (const unsigned char *)data,
                         (unsigned long)size);
  rig_jpeg__jpeg_read_header(&cinfo, TRUE);
  cinfo.out_color_space = JCS_RGB;
  rig_jpeg__jpeg_start_decompress(&cinfo);

  width = (int)cinfo.output_width;
  height = (int)cinfo.output_height;
  if (width <= 0 || height <= 0) {
    rig_jpeg__jpeg_destroy_decompress(&cinfo);
    return -1;
  }

  rgba = (unsigned char *)malloc((size_t)width * (size_t)height * 4u);
  row = (unsigned char *)malloc((size_t)width * 3u);
  if (rgba == NULL || row == NULL) {
    rig_jpeg__jpeg_destroy_decompress(&cinfo);
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
    rig_jpeg__jpeg_read_scanlines(&cinfo, rows, 1);
    y = (size_t)cinfo.output_scanline - 1u;
    dst = rgba + y * (size_t)width * 4u;
    for (x = 0; x < width; x++) {
      dst[x * 4 + 0] = row[x * 3 + 0];
      dst[x * 4 + 1] = row[x * 3 + 1];
      dst[x * 4 + 2] = row[x * 3 + 2];
      dst[x * 4 + 3] = 255u;
    }
  }

  rig_jpeg__jpeg_finish_decompress(&cinfo);
  rig_jpeg__jpeg_destroy_decompress(&cinfo);

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
