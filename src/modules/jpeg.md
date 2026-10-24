# jpeg

Decodes JPEG data to top-down RGBA8 pixels.

libjpeg signals fatal errors with `longjmp`, which pure LuaJIT FFI cannot express
safely, so `jpeg.c` holds only a tiny `setjmp`-guarded decoder and `jpeg.lua` reaches
it through FFI. Path handling and caching belong to `asset`.

## API

- `jpeg.decode(bytes, label?)`
  - Returns `{ width, height, channels = 4, pixels = <RGBA byte string> }`.
  - Returns `nil, message` on malformed input.
  - When rig was built without libjpeg headers, returns `nil` with a message saying
    JPEG support is not built.

## Build

`CMakeLists.txt` looks for libjpeg with `find_package(JPEG)`. Installing
`libjpeg62-turbo-dev` (Debian/Ubuntu) enables the real decoder; without it, `jpeg.c`
compiles a stub and `jpeg.decode` reports missing support.
