local M = ... or {}
local prelude = require("prelude")
local class = prelude.class
local raise = prelude.raise
local set = prelude.set

local function path_label(path)
   if type(path) == "string" and path ~= "" then
      return path
   end
   return "value"
end

local function field_path(path, key)
   return path_label(path) .. "." .. tostring(key)
end

local function index_path(path, index)
   return path_label(path) .. "[" .. tostring(index) .. "]"
end

local function fail(path, message)
   raise(path_label(path) .. " expects " .. message)
end

local function ensure_schema(value, label)
   if not M.Schema:is_instance(value) then
      raise((label or "schema") .. " must be a schema object")
   end
   return value
end

M.Schema = class()
M.DecodeSchema = class(M.Schema)
M.OptionalSchema = class(M.Schema)
M.ArraySchema = class(M.Schema)
M.MapSchema = class(M.Schema)
M.RecordSchema = class(M.Schema)
M.EnumSchema = class(M.Schema)
M.OneOfSchema = class(M.Schema)
M.MetatableSchema = class(M.Schema)
M.TransformSchema = class(M.Schema)
M.CheckedSchema = class(M.Schema)

function M.Schema:decode(_, _)
   raise("schema.decode must be implemented by subclasses")
end

function M.Schema:check(value, path)
   local ok, normalized_or_err = pcall(self.decode, self, value, path)
   if ok then
      return true, normalized_or_err
   end
   return false, tostring(normalized_or_err)
end

function M.Schema:assert(value, path)
   local ok, normalized_or_err = self:check(value, path)
   if not ok then
      raise(normalized_or_err)
   end
   return normalized_or_err
end

function M.Schema:optional(default_value)
   return M.OptionalSchema(self, default_value)
end

function M.Schema:optional_with(default_factory)
   return M.OptionalSchema(self, nil, default_factory)
end

function M.Schema:transform(transform_fn)
   return M.TransformSchema(self, transform_fn)
end

function M.Schema:where(description, check_fn)
   return M.CheckedSchema(self, description, check_fn)
end

function M.DecodeSchema:init(description, decode_fn)
   if type(description) ~= "string" or description == "" then
      raise("schema.DecodeSchema expects a non-empty string description")
   end
   if type(decode_fn) ~= "function" then
      raise("schema.DecodeSchema expects a decode function")
   end

   self.description = description
   self.decode_fn = decode_fn
end

function M.DecodeSchema:decode(value, path)
   return self.decode_fn(value, path)
end

function M.OptionalSchema:init(inner, default_value, default_factory)
   self.inner = ensure_schema(inner, "schema.OptionalSchema inner")
   self.default_value = default_value
   if default_factory ~= nil and type(default_factory) ~= "function" then
      raise("schema.OptionalSchema default_factory must be a function if provided")
   end
   self.default_factory = default_factory
end

function M.OptionalSchema:decode(value, path)
   if value == nil then
      if self.default_factory ~= nil then
         return self.default_factory()
      end
      return self.default_value
   end
   return self.inner:decode(value, path)
end

function M.ArraySchema:init(item_schema, options)
   if options ~= nil and type(options) ~= "table" then
      raise("schema.ArraySchema expects options to be a table if provided")
   end

   self.item_schema = ensure_schema(item_schema, "schema.ArraySchema item_schema")
   self.unique = options ~= nil and options.unique == true or false
end

function M.ArraySchema:decode(value, path)
   if type(value) ~= "table" then
      fail(path, "a table")
   end

   local count = #value
   for key in pairs(value) do
      if type(key) ~= "number" or key < 1 or key ~= math.floor(key) or key > count then
         fail(path, "an array-like table")
      end
   end

   local normalized = {}
   local seen = {}

   for i = 1, count do
      if rawget(value, i) == nil then
         fail(index_path(path, i), "a value")
      end

      local item = self.item_schema:decode(value[i], index_path(path, i))
      if self.unique then
         if seen[item] then
            raise(
               index_path(path, i) .. " duplicates an earlier array value")
         end
         seen[item] = true
      end
      normalized[i] = item
   end

   return normalized
end

function M.MapSchema:init(key_schema, value_schema)
   self.key_schema = ensure_schema(key_schema, "schema.MapSchema key_schema")
   self.value_schema = ensure_schema(value_schema, "schema.MapSchema value_schema")
end

function M.MapSchema:decode(value, path)
   if type(value) ~= "table" then
      fail(path, "a table")
   end

   local normalized = {}
   for raw_key, raw_value in pairs(value) do
      local key = self.key_schema:decode(raw_key, path_label(path) .. " key")
      local item_path = field_path(path, key)
      normalized[key] = self.value_schema:decode(raw_value, item_path)
   end
   return normalized
end

function M.RecordSchema:init(fields, options)
   if type(fields) ~= "table" then
      raise("schema.RecordSchema expects fields to be a table")
   end
   if options ~= nil and type(options) ~= "table" then
      raise("schema.RecordSchema expects options to be a table if provided")
   end

   self.fields = {}
   for key, field_schema in pairs(fields) do
      if type(key) ~= "string" or key == "" then
         raise("schema.RecordSchema field names must be non-empty strings")
      end
      self.fields[key] = ensure_schema(
         field_schema,
         "schema.RecordSchema field '" .. key .. "'"
      )
   end

   self.allow_extra = options ~= nil and options.allow_extra == true
end

function M.RecordSchema:decode(value, path)
   if type(value) ~= "table" then
      fail(path, "a table")
   end

   local normalized = {}

   for key, field_schema in pairs(self.fields) do
      local field_value = rawget(value, key)
      local decoded = field_schema:decode(field_value, field_path(path, key))
      if decoded ~= nil or field_value ~= nil then
         normalized[key] = decoded
      end
   end

   for key, extra_value in pairs(value) do
      if self.fields[key] == nil then
         if not self.allow_extra then
            raise(field_path(path, key) .. " is not allowed")
         end
         normalized[key] = extra_value
      end
   end

   return normalized
end

function M.EnumSchema:init(values)
   if type(values) ~= "table" then
      raise("schema.EnumSchema expects values to be a table")
   end

   self.values = set(values)
   self.descriptions = {}

   for i = 1, #values do
      local value = values[i]
      self.descriptions[i] = tostring(value)
   end
end

function M.EnumSchema:decode(value, path)
   if not self.values[value] then
      fail(path, "one of " .. table.concat(self.descriptions, ", "))
   end
   return value
end

function M.OneOfSchema:init(choices, description)
   if type(choices) ~= "table" then
      raise("schema.OneOfSchema expects choices to be a table")
   end
   if description ~= nil and (type(description) ~= "string" or description == "") then
      raise("schema.OneOfSchema expects description to be a non-empty string if provided")
   end

   self.choices = {}
   for i = 1, #choices do
      self.choices[i] = ensure_schema(choices[i], "schema.OneOfSchema choice")
   end
   self.description = description
end

function M.OneOfSchema:decode(value, path)
   local last_err = nil

   for i = 1, #self.choices do
      local ok, normalized_or_err = self.choices[i]:check(value, path)
      if ok then
         return normalized_or_err
      end
      last_err = normalized_or_err
   end

   if self.description ~= nil then
      fail(path, self.description)
   end

   raise(last_err or (path_label(path) .. " did not match any schema choice"))
end

function M.MetatableSchema:init(expected_metatable, description)
   if type(expected_metatable) ~= "table" then
      raise("schema.MetatableSchema expects expected_metatable to be a table")
   end
   if type(description) ~= "string" or description == "" then
      raise("schema.MetatableSchema expects description to be a non-empty string")
   end

   self.expected_metatable = expected_metatable
   self.description = description
end

function M.MetatableSchema:decode(value, path)
   if getmetatable(value) ~= self.expected_metatable then
      fail(path, self.description)
   end
   return value
end

function M.TransformSchema:init(inner, transform_fn)
   self.inner = ensure_schema(inner, "schema.TransformSchema inner")
   if type(transform_fn) ~= "function" then
      raise("schema.TransformSchema expects a transform function")
   end
   self.transform_fn = transform_fn
end

function M.TransformSchema:decode(value, path)
   local decoded = self.inner:decode(value, path)
   return self.transform_fn(decoded, path)
end

function M.CheckedSchema:init(inner, description, check_fn)
   self.inner = ensure_schema(inner, "schema.CheckedSchema inner")
   if type(description) ~= "string" or description == "" then
      raise("schema.CheckedSchema expects a non-empty string description")
   end
   if type(check_fn) ~= "function" then
      raise("schema.CheckedSchema expects a check function")
   end
   self.description = description
   self.check_fn = check_fn
end

function M.CheckedSchema:decode(value, path)
   local decoded = self.inner:decode(value, path)
   if not self.check_fn(decoded, path) then
      fail(path, self.description)
   end
   return decoded
end

function M.any()
   return M.DecodeSchema("any value", function(value)
      return value
   end)
end

function M.string(options)
   local opts = options or {}
   if type(opts) ~= "table" then
      raise("schema.string expects options to be a table if provided")
   end

   local non_empty = opts.non_empty == true
   local pattern = opts.pattern
   if pattern ~= nil and type(pattern) ~= "string" then
      raise("schema.string expects options.pattern to be a string if provided")
   end

   return M.DecodeSchema(
      non_empty and "a non-empty string" or "a string",
      function(value, path)
         if type(value) ~= "string" then
            fail(path, non_empty and "a non-empty string" or "a string")
         end
         if non_empty and value == "" then
            fail(path, "a non-empty string")
         end
         if pattern ~= nil and value:match(pattern) == nil then
            fail(path, "a string matching " .. pattern)
         end
         return value
      end
   )
end

function M.non_empty_string()
   return M.string {
      non_empty = true,
   }
end

function M.number(options)
   local opts = options or {}
   if type(opts) ~= "table" then
      raise("schema.number expects options to be a table if provided")
   end

   local coerce = opts.coerce == true
   local integer = opts.integer == true
   local min = opts.min
   local max = opts.max

   return M.DecodeSchema("a number", function(value, path)
      local normalized = value
      if coerce then
         normalized = tonumber(normalized)
      end
      if type(normalized) ~= "number" then
         fail(path, "a number")
      end
      if integer and normalized ~= math.floor(normalized) then
         fail(path, "an integer")
      end
      if min ~= nil and normalized < min then
         fail(path, "a number >= " .. tostring(min))
      end
      if max ~= nil and normalized > max then
         fail(path, "a number <= " .. tostring(max))
      end
      return normalized
   end)
end

function M.integer(options)
   local opts = options or {}
   opts.integer = true
   return M.number(opts)
end

function M.non_negative_number(options)
   local opts = options or {}
   opts.min = 0
   return M.number(opts)
end

function M.positive_number(options)
   local opts = options or {}
   opts.min = opts.min or 0
   return M.number(opts):where("a positive number", function(value)
      return value > 0
   end)
end

function M.positive_integer(options)
   local opts = options or {}
   return M.number(opts):where("a positive integer", function(value)
      return value == math.floor(value) and value > 0
   end)
end

function M.boolean()
   return M.DecodeSchema("a boolean", function(value, path)
      if type(value) ~= "boolean" then
         fail(path, "a boolean")
      end
      return value
   end)
end

function M.func()
   return M.DecodeSchema("a function", function(value, path)
      if type(value) ~= "function" then
         fail(path, "a function")
      end
      return value
   end)
end

function M.table()
   return M.DecodeSchema("a table", function(value, path)
      if type(value) ~= "table" then
         fail(path, "a table")
      end
      return value
   end)
end

function M.optional(inner, default_value)
   return M.OptionalSchema(inner, default_value)
end

function M.optional_with(inner, default_factory)
   return M.OptionalSchema(inner, nil, default_factory)
end

function M.array(item_schema, options)
   return M.ArraySchema(item_schema, options)
end

function M.map(key_schema, value_schema)
   return M.MapSchema(key_schema, value_schema)
end

function M.record(fields, options)
   return M.RecordSchema(fields, options)
end

function M.enum(values)
   return M.EnumSchema(values)
end

function M.one_of(choices, description)
   return M.OneOfSchema(choices, description)
end

function M.has_metatable(expected_metatable, description)
   return M.MetatableSchema(expected_metatable, description)
end

function M.assert(schema_object, value, path)
   return ensure_schema(schema_object, "schema.assert schema"):assert(value, path)
end

function M.check(schema_object, value, path)
   return ensure_schema(schema_object, "schema.check schema"):check(value, path)
end

return M
