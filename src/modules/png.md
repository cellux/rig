# png

Decodes PNG data to top-down RGBA8 pixels through libpng's simplified (`png_image`)
API, loaded dynamically with LuaJIT FFI like the other system-backed modules. The
simplified API reports errors through return codes rather than `setjmp`, so it is safe
to bind directly without a C helper.

## API

- `png.decode(bytes, label?)`
  - `bytes` is a Lua string containing PNG data.
  - Returns `{ width, height, channels = 4, pixels = <RGBA byte string> }`.
  - Returns `nil, message` on malformed input.
  - `label` names the source in error messages.

## Notes

- `pixels` holds `width * height * 4` bytes, one row after another, top row first.
- libpng is resolved on first use from `libpng16` / `libpng16.so.16` / ... via
  `rig.create_ffi_library_loader`.
