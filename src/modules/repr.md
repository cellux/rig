# `repr`

Best-effort Lua-readable value formatting.

The module itself is callable:

```lua
local repr = require("repr")
local text = repr(value, options)
```

## API

- `repr.repr(value[, options])`
  - Returns a best-effort Lua-readable representation for any value.
  - Plain values and acyclic tables are emitted as Lua-like source text.
  - Functions, threads, userdata, and cycles fall back to readable placeholder strings.
  - `options.indent` enables multiline output.
  - `options.indent` may be either an indentation string or a non-negative integer number of spaces.
  - Also available as `rig.repr(...)`.

## Notes

- The result is intended for diagnostics and readable snapshots, not as a strict serializer.
- Simple acyclic tables round-trip through `loadstring("return " .. repr.repr(value))`.
- Tables are emitted in a stable key order.
