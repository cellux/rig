# `schema`

Small composable schema/decoder helpers for plain Lua data.

The module is aimed at the validation patterns already common in Rig:

- runtime option tables
- arrays of names
- string-to-string maps
- optional/defaulted fields
- metatable-backed instance checks
- light normalization such as `tonumber(...)` or record post-processing

## Model

Schemas decode input values into validated, normalized output values.

- structural checks live in the builtin schema classes
- domain-specific normalization is injected by callers through transform hooks
- heavy domain logic should still stay in the owning module

## API

- `schema.assert(schema_object, value[, path])`
  - Decodes `value` through `schema_object`.
  - Raises on failure.
- `schema.check(schema_object, value[, path])`
  - Returns `true, decoded` on success.
  - Returns `false, err` on failure.
- `schema.any()`
- `schema.string(options?)`
  - Supports:
    - `non_empty = true`
    - `pattern = "..."`
- `schema.non_empty_string()`
- `schema.number(options?)`
  - Supports:
    - `coerce = true`
    - `integer = true`
    - `min`
    - `max`
- `schema.integer(options?)`
- `schema.non_negative_number(options?)`
- `schema.positive_number(options?)`
- `schema.positive_integer(options?)`
- `schema.boolean()`
- `schema.func()`
- `schema.table()`
- `schema.optional(inner[, default_value])`
  - Also available as `inner:optional(default_value)`.
  - Reuses `default_value` as-is when the input value is `nil`.
- `schema.optional_with(inner, default_factory)`
  - Also available as `inner:optional_with(default_factory)`.
  - Calls `default_factory()` each time the input value is `nil`.
- `schema.array(item_schema[, options])`
  - Supports:
    - `unique = true`
  - Expects a dense 1-based array-like table.
- `schema.map(key_schema, value_schema)`
- `schema.record(fields[, options])`
  - Supports:
    - `allow_extra = true`
  - Rejects extra fields by default.
- `schema.enum(values)`
- `schema.one_of(choices[, description])`
  - Tries each choice in order until one succeeds.
  - If `description` is provided, it is used as the failure message instead of exposing the last branch error.
- `schema.has_metatable(expected_metatable, description)`
- `schema.instance_of(expected_class[, description])`
  - Uses `expected_class:is_instance(value)`.
  - Accepts subclass instances.
- `schema.ffi.struct(ctype, fields[, options])`
  - Validates a plain Lua spec table and materializes a `ctype[1]` FFI struct bundle.
- `schema.ffi.array(ctype, item_schema[, options])`
  - Validates an array and materializes a `ctype[?]` FFI array bundle.

## Schema Methods

All schema objects provide:

- `schema_object:assert(value[, path])`
- `schema_object:check(value[, path])`
- `schema_object:optional(default_value)`
- `schema_object:optional_with(default_factory)`
- `schema_object:transform(transform_fn)`
  - Applies caller-supplied normalization after the inner schema succeeds.
- `schema_object:where(description, check_fn)`
  - Adds one extra predicate check after the inner schema succeeds.
  - Raises `"... expects <description>"` when `check_fn` returns false.

FFI builder bundles provide:

- `bundle.cdata`
- `bundle.value`
- `bundle.length`
- `bundle.keepalive`
- `bundle:retain(value)`

## Examples

```lua
local schema = require("schema")

local jobs_schema = schema.positive_number {
   coerce = true,
}

local history_schema = schema.positive_integer {
   coerce = true,
}

local roots_schema = schema.array(schema.non_empty_string())

local run_options_schema = schema.record({
   roots = roots_schema:optional_with(function()
      return { "." }
   end),
   jobs = jobs_schema:optional(1),
})

local opts = schema.assert(run_options_schema, {
   jobs = "4",
}, "test.run options")

assert(opts.jobs == 4)
assert(opts.roots[1] == ".")
assert(schema.assert(history_schema, "8", "history") == 8)
```

Use `optional_with(...)` when the default should be freshly constructed each time, such as for tables or other mutable values.

Injected normalization:

```lua
local shader_stage_schema = schema.non_empty_string()
   :transform(function(value)
      local lowered = value:lower()
      if lowered == "vertex" then
         return 1
      end
      if lowered == "fragment" then
         return 2
      end
      rig.raise("shader stage expects vertex or fragment")
   end)
```

FFI struct materialization:

```lua
local schema = require("schema")
local ffi = require("ffi")

ffi.cdef[[
typedef struct ExamplePoint {
  int x;
  int y;
} ExamplePoint;

typedef struct ExampleLine {
  ExamplePoint start;
  ExamplePoint finish;
} ExampleLine;
]]

local point_schema = schema.ffi.struct("ExamplePoint", {
   x = schema.integer { coerce = true },
   y = schema.integer { coerce = true },
})

local line_schema = schema.ffi.struct("ExampleLine", {
   start = point_schema,
   ["end"] = {
      schema = point_schema,
      to = "finish",
   },
})

local line = schema.assert(line_schema, {
   start = { x = "1", y = "2" },
   ["end"] = { x = "3", y = "4" },
}, "line")

assert(line.value.finish.x == 3)
```

Field descriptors inside `schema.ffi.struct(...)` may use:

- a schema object directly for same-name assignment
- `{ schema = ..., to = "field_name" }` for renames
- `{ schema = ..., count_field = "num_items" }` to derive counts from decoded arrays
- `{ schema = ..., assign = function(dst, value, bundle, descriptor, path) ... end }` for custom writes and keepalive retention

## Notes

- The current first version is intentionally small.
- It is better thought of as a composable decoder/validator than as a broad schema language.
- Use builtin helpers for structural patterns; inject domain normalization through `:transform(...)` and `:where(...)`.
