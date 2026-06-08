# `prelude`

Small foundational helpers that are safe to use before `rig` is available.

## API

- `prelude.class(parent?)`
  - Creates a callable class table.
  - Calling the class constructs one instance whose metatable is the class table.
  - If the instance resolves an `init(...)` method, it is called during construction.
  - If `parent` is provided, method lookup on the class falls back to that parent table.
- `prelude.raise(message[, ...])`
  - Raises an error without adding Lua stack-location prefixes.
  - If extra arguments are provided, formats the message through `string.format(...)` first.

## Notes

- `rig.class(...)` is an alias for `prelude.class(...)`.
- `rig.raise(...)` is an alias for `prelude.raise(...)`.
