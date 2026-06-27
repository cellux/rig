# `prelude`

Small foundational helpers that are safe to use before `rig` is available.

## API

- `prelude.set(values)`
  - Builds a membership set table from the array part of `values`.
  - Each array element becomes a key with value `true`.
- `prelude.Class`
  - Metaclass shared by all class tables created by `prelude.Class(...)`.
  - Calling `prelude.Class(parent?)` creates a new callable class table.
  - Defines shared class operations such as `:super()`, `:is_instance(...)`, `:is_descendant(...)`, and `:is_ancestor(...)`.
  - Calling a class constructs one instance whose metatable is the class table.
  - If the instance resolves an `init(...)` method, it is called during construction.
  - Instances expose `:super()` to return the immediate parent class table, if any.
  - Class tables expose `:is_descendant(ancestor)` to test inheritance against a parent class.
  - Class tables expose `:is_ancestor(descendant)` to test whether another class inherits from them.
  - All class tables use `prelude.Class` as their metaclass.
  - Parent methods may be invoked explicitly as `self:super().method(self, ...)`.
  - If `parent` is provided, method lookup on the class falls back to that parent table.
- `prelude.is_class(value)`
  - Returns `true` when `value` is a class table created by `prelude.Class(...)`.
  - Returns `true` for `prelude.Class` itself.
  - Returns `false` for ordinary instances.
- `prelude.raise(message[, ...])`
  - Raises an error without adding Lua stack-location prefixes.
  - If extra arguments are provided, formats the message through `string.format(...)` first.

## Notes

- `rig.set(...)` is an alias for `prelude.set(...)`.
- `rig.Class` is an alias for `prelude.Class`.
- `rig.is_class(...)` is an alias for `prelude.is_class(...)`.
- `rig.raise(...)` is an alias for `prelude.raise(...)`.
