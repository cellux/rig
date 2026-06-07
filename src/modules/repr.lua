local M = ... or {}
local schema = require("schema")

local indent_schema = schema.one_of({
   schema.integer {
      min = 0,
   },
   schema.string(),
}, "a string or non-negative integer")

local repr_options_schema = schema.record({
   indent = indent_schema:optional(),
})

local function is_identifier(key)
   return type(key) == "string" and key:match("^[_%a][_%w]*$") ~= nil
end

local function normalize_options(options)
   if options == nil then
      return {
         indent = nil,
      }
   end
   local normalized = schema.assert(repr_options_schema, options, "repr.repr options")
   local indent = normalized.indent
   if indent == nil then
      return {
         indent = nil,
      }
   end
   if type(indent) == "number" then
      indent = string.rep(" ", indent)
   end

   return {
      indent = indent,
   }
end

local function repr_placeholder(value, value_type)
   local label = tostring(value)
   if type(label) ~= "string" or label == "" then
      label = value_type
   end
   return string.format("%q", "<" .. label .. ">")
end

local function key_type_rank(key)
   local key_type = type(key)

   if key_type == "number" then
      return 1
   end
   if key_type == "string" then
      return 2
   end
   if key_type == "boolean" then
      return 3
   end
   if key_type == "table" then
      return 4
   end
   if key_type == "function" then
      return 5
   end
   if key_type == "userdata" then
      return 6
   end
   if key_type == "thread" then
      return 7
   end
   return 8
end

local function compare_repr_keys(a, b)
   local a_rank = key_type_rank(a)
   local b_rank = key_type_rank(b)

   if a_rank ~= b_rank then
      return a_rank < b_rank
   end

   local value_type = type(a)
   if value_type == "number" or value_type == "string" then
      return a < b
   end
   if value_type == "boolean" then
      return (a and 1 or 0) < (b and 1 or 0)
   end

   return tostring(a) < tostring(b)
end

local function repr_key(key, state)
   if type(key) == "string" and is_identifier(key) then
      return key
   end

   return "[" .. state.repr_value(key, state) .. "]"
end

local function repr_table(value, state)
   if state.seen[value] then
      return string.format("%q", "<cycle>")
   end

   state.seen[value] = true

   local fields = {}
   local sequence_length = 0
   local parent_indent = state.line_indent
   local child_indent = parent_indent

   if state.indent ~= nil then
      child_indent = parent_indent .. state.indent
      state.line_indent = child_indent
   end

   while rawget(value, sequence_length + 1) ~= nil do
      sequence_length = sequence_length + 1
      fields[#fields + 1] = {
         implicit = true,
         value = state.repr_value(rawget(value, sequence_length), state),
      }
   end

   local keys = {}
   for key in pairs(value) do
      if type(key) ~= "number" or key < 1 or key > sequence_length or key ~= math.floor(key) then
         keys[#keys + 1] = key
      end
   end
   table.sort(keys, compare_repr_keys)

   for i = 1, #keys do
      local key = keys[i]
      fields[#fields + 1] = {
         implicit = false,
         key = repr_key(key, state),
         value = state.repr_value(value[key], state),
      }
   end

   state.seen[value] = nil
   state.line_indent = parent_indent

   if #fields == 0 then
      return "{}"
   end

   if state.indent == nil then
      local parts = {}
      for i = 1, #fields do
         local field = fields[i]
         if field.implicit then
            parts[i] = field.value
         else
            parts[i] = field.key .. " = " .. field.value
         end
      end
      return "{" .. table.concat(parts, ", ") .. "}"
   end

   local lines = {"{"}

   for i = 1, #fields do
      local field = fields[i]
      if field.implicit then
         lines[#lines + 1] = child_indent .. field.value .. ","
      else
         lines[#lines + 1] = child_indent .. field.key .. " = " .. field.value .. ","
      end
   end

   lines[#lines + 1] = parent_indent .. "}"
   return table.concat(lines, "\n")
end

local function repr_value(value, state)
   local value_type = type(value)

   if value_type == "nil" then
      return "nil"
   end
   if value_type == "boolean" then
      return value and "true" or "false"
   end
   if value_type == "number" then
      if value ~= value then
         return "0/0"
      end
      if value == math.huge then
         return "math.huge"
      end
      if value == -math.huge then
         return "-math.huge"
      end
      return tostring(value)
   end
   if value_type == "string" then
      return string.format("%q", value)
   end
   if value_type == "table" then
      return repr_table(value, state)
   end

   return repr_placeholder(value, value_type)
end

function M.repr(value, options)
   local normalized = normalize_options(options)
   local state = {
      indent = normalized.indent,
      line_indent = "",
      seen = {},
      repr_value = repr_value,
   }

   return repr_value(value, state)
end

return setmetatable(M, {
   __call = function(_, ...)
      return M.repr(...)
   end,
})
