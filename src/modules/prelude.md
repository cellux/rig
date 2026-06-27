# `prelude`

Small foundational helpers that are safe to use before `rig` is available.

## API

- `prelude.set(values)`
  - Builds a membership set table from the array part of `values`.
  - Each array element becomes a key with value `true`.
- `prelude.class(parent?)`
  - Creates a callable class table.
  - Calling the class constructs one instance whose metatable is the class table.
  - If the instance resolves an `init(...)` method, it is called during construction.
  - Instances expose `:super()` to return the immediate parent class table, if any.
  - Class tables expose `:is_descendant(ancestor)` to test inheritance against a parent class.
  - Parent methods may be invoked explicitly as `self:super().method(self, ...)`.
  - If `parent` is provided, method lookup on the class falls back to that parent table.
- `prelude.raise(message[, ...])`
  - Raises an error without adding Lua stack-location prefixes.
  - If extra arguments are provided, formats the message through `string.format(...)` first.

## Notes

- `rig.set(...)` is an alias for `prelude.set(...)`.
- `rig.class(...)` is an alias for `prelude.class(...)`.
- `rig.raise(...)` is an alias for `prelude.raise(...)`.
