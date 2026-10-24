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

`CMakeLists.txt` locates libjpeg with `find_package(JPEG)` for its headers only.
Installing `libjpeg62-turbo-dev` (Debian/Ubuntu) enables the real decoder; without
the headers, `jpeg.c` compiles a stub and `jpeg.decode` reports missing support.

The library itself is resolved at runtime through the `dl` loader, so rig has no hard
runtime dependency on a particular libjpeg soname: a build can use the headers while
the runtime picks up whichever `libjpeg.so` / `libjpeg.dll` is installed. When no
library can be loaded, `jpeg.decode` reports missing support.
