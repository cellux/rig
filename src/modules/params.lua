local M = ... or {}

local rig = require("rig")

-- A tiny live-parameter store for demos: named numbers, booleans, and enums that
-- an overlay can tweak at runtime. It is a plain value store; `overlay` (or user
-- code) drives and draws it. Values are clamped on every mutation.

local Params = rig.Class()
M.Params = Params

local function clamp(value, low, high)
   if value < low then
      return low
   end
   if value > high then
      return high
   end
   return value
end

function Params:init(definitions)
   self.order = {}
   self.definitions = {}
   if definitions ~= nil then
      for i = 1, #definitions do
         self:define(definitions[i])
      end
   end
end

-- Defines a parameter. `spec.name` and `spec.kind` (`"number"` default,
-- `"boolean"`, `"enum"`) are required; `spec.label` defaults to the name.
--   number:  `value`, `min`, `max`, `step`
--   boolean: `value`
--   enum:    `values` (array), `value` (1-based index)
function Params:define(spec)
   spec = spec or {}
   local name = spec.name
   if type(name) ~= "string" or name == "" then
      rig.raise("params.define requires a non-empty name")
   end
   if self.definitions[name] ~= nil then
      rig.raise("params.define duplicate parameter '%s'", name)
   end

   local kind = spec.kind or "number"
   local definition = {
      name = name,
      kind = kind,
      label = spec.label or name,
   }

   if kind == "number" then
      definition.min = tonumber(spec.min) or 0.0
      definition.max = tonumber(spec.max) or 1.0
      if definition.max < definition.min then
         rig.raise("params.define number '%s' max must be >= min", name)
      end
      definition.step = tonumber(spec.step)
         or ((definition.max - definition.min) / 50.0)
      if definition.step <= 0.0 then
         rig.raise("params.define number '%s' step must be positive", name)
      end
      definition.value = clamp(
         tonumber(spec.value) or definition.min,
         definition.min,
         definition.max
      )
   elseif kind == "boolean" then
      definition.value = spec.value and true or false
   elseif kind == "enum" then
      if type(spec.values) ~= "table" or #spec.values == 0 then
         rig.raise("params.define enum '%s' requires a non-empty values list", name)
      end
      definition.values = spec.values
      local index = math.floor(tonumber(spec.value) or 1)
      if index < 1 or index > #spec.values then
         rig.raise("params.define enum '%s' value is out of range", name)
      end
      definition.value = index
   else
      rig.raise("params.define unknown kind '%s'", kind)
   end

   self.definitions[name] = definition
   self.order[#self.order + 1] = name
   return definition
end

function Params:definition(name)
   local definition = self.definitions[name]
   if definition == nil then
      rig.raise("params: unknown parameter '%s'", name)
   end
   return definition
end

function Params:get(name)
   return self:definition(name).value
end

function Params:set(name, value)
   local definition = self:definition(name)
   if definition.kind == "number" then
      definition.value = clamp(
         tonumber(value) or definition.value,
         definition.min,
         definition.max
      )
   elseif definition.kind == "boolean" then
      definition.value = value and true or false
   elseif definition.kind == "enum" then
      definition.value = clamp(
         math.floor(tonumber(value) or definition.value),
         1,
         #definition.values
      )
   end
   return definition.value
end

-- Moves a parameter by `direction` steps (+1/-1): adds a number step, flips a
-- boolean, or advances an enum (wrapping).
function Params:adjust(name, direction)
   local definition = self:definition(name)
   direction = direction or 1
   if definition.kind == "number" then
      definition.value = clamp(
         definition.value + direction * definition.step,
         definition.min,
         definition.max
      )
   elseif definition.kind == "boolean" then
      if direction ~= 0 then
         definition.value = not definition.value
      end
   elseif definition.kind == "enum" then
      local count = #definition.values
      definition.value = ((definition.value - 1 + direction) % count) + 1
   end
   return definition.value
end

function Params:toggle(name)
   return self:adjust(name, 1)
end

function Params:count()
   return #self.order
end

function Params:name_at(index)
   return self.order[index]
end

-- Iterates definitions in declaration order.
function Params:each()
   local index = 0
   return function()
      index = index + 1
      local name = self.order[index]
      if name == nil then
         return nil
      end
      return name, self.definitions[name]
   end
end

-- Normalized value in `[0, 1]`, for rendering. Booleans are 0/1; enums map their
-- selected index across the list.
function Params:fraction(name)
   local definition = self:definition(name)
   if definition.kind == "number" then
      if definition.max == definition.min then
         return 0.0
      end
      return (definition.value - definition.min) / (definition.max - definition.min)
   elseif definition.kind == "boolean" then
      return definition.value and 1.0 or 0.0
   elseif definition.kind == "enum" then
      if #definition.values == 1 then
         return 0.0
      end
      return (definition.value - 1) / (#definition.values - 1)
   end
   return 0.0
end

-- Formats a value for display.
function Params:format(name)
   local definition = self:definition(name)
   if definition.kind == "number" then
      return string.format("%.3g", definition.value)
   elseif definition.kind == "boolean" then
      return definition.value and "on" or "off"
   elseif definition.kind == "enum" then
      return tostring(definition.values[definition.value])
   end
   return tostring(definition.value)
end

M.params = function(definitions)
   return Params(definitions)
end

return M
