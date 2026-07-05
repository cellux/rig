local M = ... or {}
local prelude = require("prelude")
local Class = prelude.Class
local is_class = prelude.is_class
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

local function ensure_non_empty_string(value, label)
   if type(value) ~= "string" or value == "" then
      raise((label or "value") .. " must be a non-empty string")
   end
   return value
end

M.Schema = Class()

M.DecodeSchema = Class(M.Schema)
M.OptionalSchema = Class(M.Schema)
M.ArraySchema = Class(M.Schema)
M.MapSchema = Class(M.Schema)
M.RecordSchema = Class(M.Schema)
M.EnumSchema = Class(M.Schema)
M.OneOfSchema = Class(M.Schema)
M.NumberSchema = Class(M.Schema)
M.IntegerSchema = Class(M.NumberSchema)
M.InstanceSchema = Class(M.Schema)
M.TransformSchema = Class(M.Schema)
M.PredicateSchema = Class(M.Schema)

M.ffi = {}

M.ffi.StructSchema = Class(M.Schema)
M.ffi.ArraySchema = Class(M.Schema)

function M.Schema:decode(value, path)
   raise("Schema:decode must be implemented by subclasses")
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

function M.Schema:where(description, predicate)
   return M.PredicateSchema(self, description, predicate)
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
      if decoded ~= nil then
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

function M.InstanceSchema:init(expected_class, description)
   if not is_class(expected_class) then
      raise("schema.InstanceSchema expects expected_class to be a Rig class")
   end
   if description ~= nil and (type(description) ~= "string" or description == "") then
      raise("schema.InstanceSchema expects description to be a non-empty string if provided")
   end

   self.expected_class = expected_class
   self.description = description or "a class instance"
end

function M.InstanceSchema:decode(value, path)
   if not self.expected_class:is_instance(value) then
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

function M.PredicateSchema:init(inner, description, predicate)
   self.inner = ensure_schema(inner, "schema.PredicateSchema inner")
   if type(description) ~= "string" or description == "" then
      raise("schema.PredicateSchema expects a non-empty string description")
   end
   if type(predicate) ~= "function" then
      raise("schema.PredicateSchema expects a predicate function")
   end
   self.description = description
   self.predicate = predicate
end

function M.PredicateSchema:decode(value, path)
   local decoded = self.inner:decode(value, path)
   if not self.predicate(decoded, path) then
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

function M.string_lookup(mapping, label)
   if type(mapping) ~= "table" then
      raise("schema.string_lookup expects mapping to be a table")
   end
   if label ~= nil and (type(label) ~= "string" or label == "") then
      raise("schema.string_lookup expects label to be a non-empty string if provided")
   end

   for key in pairs(mapping) do
      if type(key) ~= "string" or key == "" then
         raise("schema.string_lookup mapping keys must be non-empty strings")
      end
   end

   local value_label = label or "string value"

   return M.non_empty_string():transform(function(value)
      local normalized = mapping[value]
      if normalized == nil then
         raise("unsupported " .. value_label .. " '" .. value .. "'")
      end
      return normalized
   end)
end

local function validate_number_schema_options(label, opts)
   if type(opts) ~= "table" then
      raise(label .. " expects options to be a table if provided")
   end
end

local function number_expectation(schema_object)
   local base = schema_object.integer and "an integer" or "a number"

   if schema_object.minimum ~= nil and schema_object.maximum == nil then
      if schema_object.minimum == 0 then
         if schema_object.minimum_exclusive then
            return schema_object.integer and "a positive integer" or "a positive number"
         end
         return schema_object.integer and "a non-negative integer" or "a non-negative number"
      end
      return base
         .. " "
         .. (schema_object.minimum_exclusive and ">" or ">=")
         .. " "
         .. tostring(schema_object.minimum)
   end

   if schema_object.maximum ~= nil and schema_object.minimum == nil then
      if schema_object.maximum == 0 and schema_object.maximum_exclusive then
         return schema_object.integer and "a negative integer" or "a negative number"
      end
      return base
         .. " "
         .. (schema_object.maximum_exclusive and "<" or "<=")
         .. " "
         .. tostring(schema_object.maximum)
   end

   if schema_object.minimum ~= nil and schema_object.maximum ~= nil then
      local lower = (schema_object.minimum_exclusive and ">" or ">=")
         .. " "
         .. tostring(schema_object.minimum)
      local upper = (schema_object.maximum_exclusive and "<" or "<=")
         .. " "
         .. tostring(schema_object.maximum)
      return base .. " " .. lower .. " and " .. upper
   end

   return base
end

local function copy_number_schema_options(schema_object)
   return {
      coerce = schema_object.coerce,
      integer = schema_object.integer,
      min = schema_object.minimum,
      min_exclusive = schema_object.minimum_exclusive,
      max = schema_object.maximum,
      max_exclusive = schema_object.maximum_exclusive,
   }
end

function M.NumberSchema:init(options)
   local opts = options or {}
   validate_number_schema_options("schema.NumberSchema", opts)

   self.coerce = opts.coerce == true
   self.integer = opts.integer == true
   self.minimum = opts.min
   self.minimum_exclusive = opts.min_exclusive == true
   self.maximum = opts.max
   self.maximum_exclusive = opts.max_exclusive == true
end

function M.NumberSchema:with(options)
   validate_number_schema_options("schema.NumberSchema:with", options)

   local next_options = copy_number_schema_options(self)
   for key, value in pairs(options) do
      next_options[key] = value
   end
   return getmetatable(self)(next_options)
end

function M.NumberSchema:min(value)
   return self:with({
      min = value,
      min_exclusive = false,
   })
end

function M.NumberSchema:max(value)
   return self:with({
      max = value,
      max_exclusive = false,
   })
end

function M.NumberSchema:negative()
   return self:with({
      max = 0,
      max_exclusive = true,
   })
end

function M.NumberSchema:non_negative()
   return self:with({
      min = 0,
      min_exclusive = false,
   })
end

function M.NumberSchema:positive()
   return self:with({
      min = 0,
      min_exclusive = true,
   })
end

function M.NumberSchema:decode(value, path)
   local normalized = value
   if self.coerce then
      normalized = tonumber(normalized)
   end

   local expectation = number_expectation(self)

   if type(normalized) ~= "number" then
      fail(path, expectation)
   end
   if self.integer and normalized ~= math.floor(normalized) then
      fail(path, expectation)
   end
   if self.minimum ~= nil then
      if self.minimum_exclusive then
         if normalized <= self.minimum then
            fail(path, expectation)
         end
      elseif normalized < self.minimum then
         fail(path, expectation)
      end
   end
   if self.maximum ~= nil then
      if self.maximum_exclusive then
         if normalized >= self.maximum then
            fail(path, expectation)
         end
      elseif normalized > self.maximum then
         fail(path, expectation)
      end
   end

   return normalized
end

function M.IntegerSchema:init(options)
   local opts = options or {}
   validate_number_schema_options("schema.IntegerSchema", opts)

   local next_options = {
      coerce = opts.coerce == true,
      integer = true,
      min = opts.min,
      min_exclusive = opts.min_exclusive == true,
      max = opts.max,
      max_exclusive = opts.max_exclusive == true,
   }
   M.NumberSchema.init(self, next_options)
end

function M.number(options)
   return M.NumberSchema(options)
end

function M.integer(options)
   return M.IntegerSchema(options)
end

function M.number_like(options)
   local opts = options or {}
   validate_number_schema_options("schema.number_like", opts)
   local next_options = copy_number_schema_options({
      coerce = true,
      integer = opts.integer == true,
      min = opts.min,
      min_exclusive = opts.min_exclusive == true,
      max = opts.max,
      max_exclusive = opts.max_exclusive == true,
   })
   return M.NumberSchema(next_options)
end

function M.integer_like(options)
   local opts = options or {}
   validate_number_schema_options("schema.integer_like", opts)
   local next_options = {
      coerce = true,
      min = opts.min,
      min_exclusive = opts.min_exclusive == true,
      max = opts.max,
      max_exclusive = opts.max_exclusive == true,
   }
   return M.IntegerSchema(next_options)
end

function M.non_negative_number(options)
   return M.number(options):non_negative()
end

function M.positive_number(options)
   return M.number(options):positive()
end

function M.positive_integer(options)
   return M.integer(options):positive()
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

local Bundle = Class()

function Bundle:init(kind, cdata, value, length)
   if kind ~= "struct" and kind ~= "array" then
      raise("Bundle kind must be 'struct' or 'array'")
   end

   self.kind = kind
   self.cdata = cdata
   self.value = value
   self.length = length
   self.keepalive = {}
end

function Bundle:retain(value)
   self.keepalive[#self.keepalive + 1] = value
   return value
end

local function is_bundle(value)
   return Bundle:is_instance(value)
end

local function ffi_field_descriptor_schema()
   return M.record({
      schema = M.instance_of(M.Schema, "a schema object"),
      to = M.non_empty_string():optional(),
      assign = M.func():optional(),
      count_field = M.non_empty_string():optional(),
   })
end

local function normalize_ffi_field_descriptor(name, field_spec)
   local normalized = {
      name = name,
   }

   if M.Schema:is_instance(field_spec) then
      normalized.schema = field_spec
      normalized.to = name
      return normalized
   end

   if type(field_spec) ~= "table" then
      raise("schema.ffi field '" .. name .. "' must be a schema or field descriptor")
   end

   local descriptor = ffi_field_descriptor_schema():assert(
      field_spec,
      "schema.ffi field '" .. name .. "'"
   )
   normalized.schema = descriptor.schema
   normalized.to = descriptor.to or name
   normalized.assign = descriptor.assign
   normalized.count_field = descriptor.count_field
   return normalized
end

function M.ffi.StructSchema:init(ctype, fields, options)
   ensure_non_empty_string(ctype, "schema.ffi.StructSchema ctype")
   if type(fields) ~= "table" then
      raise("schema.ffi.StructSchema expects fields to be a table")
   end
   if options ~= nil and type(options) ~= "table" then
      raise("schema.ffi.StructSchema expects options to be a table if provided")
   end

   self.ctype = ctype
   self.fields = {}
   local record_fields = {}

   for key, field_spec in pairs(fields) do
      if type(key) ~= "string" or key == "" then
         raise("schema.ffi.StructSchema field names must be non-empty strings")
      end
      local descriptor = normalize_ffi_field_descriptor(key, field_spec)
      self.fields[key] = descriptor
      record_fields[key] = descriptor.schema
   end

   self.record_schema = M.record(record_fields, options)
end

function M.ffi.StructSchema:decode(value, path)
   local decoded = self.record_schema:decode(value, path)
   local cdata = require("ffi").new(self.ctype .. "[1]")
   local bundle = Bundle("struct", cdata, cdata[0], 1)

   for key, descriptor in pairs(self.fields) do
      local decoded_value = decoded[key]
      if decoded_value ~= nil then
         if descriptor.assign ~= nil then
            descriptor.assign(
               bundle.value,
               decoded_value,
               bundle
            )
         else
            if is_bundle(decoded_value) then
               bundle:retain(decoded_value)
               if decoded_value.kind == "struct" then
                  bundle.value[descriptor.to] = decoded_value.value
               else
                  bundle.value[descriptor.to] = decoded_value.cdata
               end
            else
               bundle.value[descriptor.to] = decoded_value
            end
         end

         if descriptor.count_field ~= nil then
            if is_bundle(decoded_value) then
               if decoded_value.kind ~= "array" then
                  raise(
                     field_path(path, key)
                        .. " count_field requires a decoded table or schema.ffi.array bundle"
                  )
               end
               bundle.value[descriptor.count_field] = decoded_value.length or 0
            elseif type(decoded_value) == "table" then
               bundle.value[descriptor.count_field] = #decoded_value
            else
               raise(
                  field_path(path, key)
                     .. " count_field requires a decoded table or schema.ffi.array bundle"
               )
            end
         end
      end
   end

   return bundle
end

function M.ffi.ArraySchema:init(ctype, item_schema, options)
   ensure_non_empty_string(ctype, "schema.ffi.ArraySchema ctype")
   if options ~= nil and type(options) ~= "table" then
      raise("schema.ffi.ArraySchema expects options to be a table if provided")
   end

   self.ctype = ctype
   self.item_schema = ensure_schema(item_schema, "schema.ffi.ArraySchema item_schema")
   self.array_schema = M.array(self.item_schema, options)
end

function M.ffi.ArraySchema:decode(value, path)
   local decoded = self.array_schema:decode(value, path)
   local count = #decoded
   local cdata = nil
   if count > 0 then
      cdata = require("ffi").new(self.ctype .. "[?]", count)
   end
   local bundle = Bundle("array", cdata, cdata, count)

   for i = 1, count do
      local item = decoded[i]
      if is_bundle(item) then
         if item.kind ~= "struct" then
            raise(index_path(path, i) .. " expects a struct-valued schema.ffi bundle")
         end
         bundle:retain(item)
         cdata[i - 1] = item.value
      else
         cdata[i - 1] = item
      end
   end

   return bundle
end

function M.ffi.StructSchema:__call(value, path)
   return self:assert(value, path)
end

function M.ffi.ArraySchema:__call(value, path)
   return self:assert(value, path)
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

function M.instance_of(expected_class, description)
   return M.InstanceSchema(expected_class, description)
end

function M.ffi.struct(ctype, fields, options)
   return M.ffi.StructSchema(ctype, fields, options)
end

function M.ffi.array(ctype, item_schema, options)
   return M.ffi.ArraySchema(ctype, item_schema, options)
end

function M.assert(schema_object, value, path)
   return ensure_schema(schema_object, "schema.assert schema"):assert(value, path)
end

function M.check(schema_object, value, path)
   return ensure_schema(schema_object, "schema.check schema"):check(value, path)
end

return M
