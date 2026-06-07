# `oop`

Small object-oriented helpers for Rig's Lua-side class-like abstractions.

## API

- `oop.class(parent?)`
  - Creates a callable class table.
  - Calling the class constructs one instance whose metatable is the class table.
  - If the instance resolves an `init(...)` method, it is called during construction.
  - If `parent` is provided, method lookup on the class falls back to that parent table.

## Notes

- `rig.class(...)` is an alias for `oop.class(...)`.
