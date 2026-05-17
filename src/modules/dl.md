# `dl`

Low-level dynamic loader helpers.

Current status:
- Unix-like and Windows implementation
- intended as a small primitive for runtime-loaded native integrations

## API

- `dl.SUPPORTED`
  - `true` on supported platforms
  - current implementation supports Unix-like platforms with `dlopen` and Windows with `LoadLibraryW`
- `dl.open(path[, flags])`
  - opens a shared object and returns a handle
  - `path` may be `nil` to open the current process image
  - if `flags` is omitted, the Linux implementation uses `RTLD_NOW | RTLD_LOCAL`
  - returns `nil, err` on failure
- `dl.sym(handle, name[, ctype])`
  - resolves a symbol from an open handle
  - on Unix-like platforms, if `name` is not found, the loader also retries with a leading underscore
  - returns the raw symbol pointer if `ctype` is omitted
  - if `ctype` is provided, casts the symbol through `ffi.cast(ctype, symbol)`
  - returns `nil, err` on failure
- `dl.close(handle)`
  - closes an open handle
  - returns `true` on success or `nil, err` on failure

## Notes

- This module is intentionally low-level.
- The current implementation exports these `dlopen` flags when available on Unix-like platforms:
  - `RTLD_LAZY`
  - `RTLD_NOW`
  - `RTLD_LOCAL`
  - `RTLD_GLOBAL`
- On Windows, `dl.open(path, flags)` accepts the same API shape but ignores `flags`.
