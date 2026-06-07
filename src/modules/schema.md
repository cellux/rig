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
- `schema.boolean()`
- `schema.func()`
- `schema.table()`
- `schema.optional(inner[, default_value])`
  - Also available as `inner:optional(default_value)`.
- `schema.array(item_schema[, options])`
  - Supports:
    - `unique = true`
- `schema.map(key_schema, value_schema)`
- `schema.record(fields[, options])`
  - Supports:
    - `allow_extra = true`
- `schema.enum(values)`
- `schema.one_of(choices[, description])`
- `schema.has_metatable(expected_metatable, description)`

## Schema Methods

All schema objects provide:

- `schema_object:assert(value[, path])`
- `schema_object:check(value[, path])`
- `schema_object:optional(default_value)`
- `schema_object:transform(transform_fn)`
  - Applies caller-supplied normalization after the inner schema succeeds.
- `schema_object:where(description, check_fn)`
  - Adds one extra predicate check after the inner schema succeeds.

## Examples

```lua
local schema = require("schema")

local jobs_schema = schema.positive_number {
   coerce = true,
}

local roots_schema = schema.array(schema.non_empty_string())

local run_options_schema = schema.record({
   roots = roots_schema:optional({ "." }),
   jobs = jobs_schema:optional(1),
})

local opts = schema.assert(run_options_schema, {
   jobs = "4",
}, "test.run options")

assert(opts.jobs == 4)
assert(opts.roots[1] == ".")
```

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
      error("shader stage expects vertex or fragment", 0)
   end)
```

## Notes

- The current first version is intentionally small.
- It is better thought of as a composable decoder/validator than as a broad schema language.
- Use builtin helpers for structural patterns; inject domain normalization through `:transform(...)` and `:where(...)`.
