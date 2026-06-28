# color

- `local color = require("color")`

## Constructors

- `color.Color(r, g, b[, a])`
  - Creates a `Color` from RGBA8 byte components.
- `color.Color({ r, g, b[, a] })`
- `color.Color({ r = ..., g = ..., b = ...[, a = ...] })`
- `color.Color("#RRGGBB")`
- `color.Color("#RRGGBBAA")`
- `color.rgb(r, g, b)`
- `color.rgba(r, g, b, a)`
- `color.rgbf(r, g, b)`
  - Normalized float inputs in the `0..1` range.
- `color.rgbaf(r, g, b, a)`
  - Normalized float inputs in the `0..1` range.
- `color.hex(value)`
- `color.u32_rgba(value)`
- `color.u32_argb(value)`
- `color.u32_abgr(value)`
- `color.u32_bgra(value)`

## Generic Factory

- `color.from(value[, format])`
  - `format` supports `rgb`, `rgba`, `rgbf`, `rgbaf`, `hex`, `hex_rgb`, `hex_rgba`, `u32_rgba`, `u32_argb`, `u32_abgr`, and `u32_bgra`.
  - For `rgb`, `rgba`, `rgbf`, and `rgbaf`, pass `value` as a table.

## Type Checks

- `color.is(value)`
  - Returns `true` when `value` is a `color.Color`.

## Constants

- `color.WHITE`
  - `Color(255, 255, 255, 255)`
- `color.BLACK`
  - `Color(0, 0, 0, 255)`
- `color.TRANSPARENT`
  - `Color(0, 0, 0, 0)`

## Color Methods

- `value:set(...)`
  - Reassigns the color from any constructor input accepted by `color.Color(...)`.
- `value:setf(r, g, b[, a])`
  - Reassigns the color from normalized float components.
- `value:copy()`
- `value:with_alpha(a)`
- `value:mix(second, amount)`
  - Returns a new color containing the linear interpolation between `value` and `second`.
  - `amount` is clamped to the `0..1` range.
- `value:set_mix(first, second, amount)`
  - Replaces `value` with the linear interpolation between `first` and `second`.
  - `amount` is clamped to the `0..1` range.
- `value:to_rgb()`
- `value:to_rgba()`
- `value:to_rgbf()`
- `value:to_rgbaf()`
- `value:to(format)`
  - Returns a table for `rgb`, `rgba`, `rgbf`, and `rgbaf`.
  - Returns a string for `hex`, `hex_rgb`, and `hex_rgba`.
  - Returns a number for packed `u32_*` formats.
- `value:write_rgba8(buffer[, offset])`
  - Writes four RGBA8 bytes into an FFI buffer.
- `value:is_opaque()`

## Component Access

- Components are available as named fields:
  - `value.r`, `value.g`, `value.b`, `value.a`
