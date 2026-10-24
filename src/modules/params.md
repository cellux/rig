# `params`

A tiny live-parameter store for demos: named numbers, booleans, and enums that an
overlay (or user code) can tweak at runtime. It holds values only; `overlay` draws
and edits them.

Values are clamped on every mutation.

## API

- `params.params(definitions?)` / `params.Params(definitions?)`
  - Creates a store, optionally defining `definitions` in order.
- `store:define(spec)`
  - Adds a parameter. `spec.name` and `spec.kind` (`"number"` default, `"boolean"`,
    `"enum"`) are required; `spec.label` defaults to the name.
    - number: `value`, `min`, `max`, `step` (defaults to a fiftieth of the range).
    - boolean: `value`.
    - enum: `values` (array) and `value` (1-based index, default 1).
  - Returns the definition table.
- `store:get(name)` / `store:set(name, value)` — read and clamped-write a value.
- `store:adjust(name, direction?)` — adds a number step, flips a boolean, or wraps
  an enum by `direction` (+1/-1, default +1).
- `store:toggle(name)` — shorthand for `adjust(name, 1)`.
- `store:definition(name)` — the definition table (`kind`, `label`, `min`, ...).
- `store:count()` / `store:name_at(index)` / `store:each()` — declaration order.
- `store:fraction(name)` — normalized `[0, 1]` value for rendering.
- `store:format(name)` — a short display string.

## Example

```lua
local params = require("params")

local values = params.params {
   { name = "spin", min = 0.0, max = 3.0, step = 0.1, value = 0.8 },
   { name = "grid", kind = "boolean", value = true },
   { name = "palette", kind = "enum", values = { "slate", "rose", "moss" } },
}

values:get("spin")
values:adjust("spin", -1)
values:toggle("grid")
```

See `overlay.md` for the on-screen editor.
