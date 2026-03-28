local rig = ...
local lua_tostring = _G.tostring

local function is_identifier(key)
   return type(key) == "string" and key:match("^[_%a][_%w]*$") ~= nil
end

local function serialize_lua(value, seen)
   local value_type = type(value)

   if value_type ~= "table" then
      if value_type == "string" then
         return string.format("%q", value)
      end
      return tostring(value)
   end

   if seen[value] then
      return "{ --[[cycle]] }"
   end
   seen[value] = true

   local parts = {}
   for k, v in pairs(value) do
      local val_repr = serialize_lua(v, seen)
      local key_repr
      if is_identifier(k) then
         key_repr = k
      else
         key_repr = "[" .. serialize_lua(k, seen) .. "]"
      end
      parts[#parts + 1] = key_repr .. " = " .. val_repr
   end

   seen[value] = nil
   return "{" .. table.concat(parts, ", ") .. "}"
end

function rig.tostring(value)
   if type(value) == "table" then
      return serialize_lua(value, {})
   end
   return lua_tostring(value)
end

rig.clear = sdl3.clear
rig.loop = sdl3.loop

if _G.on_render == nil then
   function on_render()
      rig.clear(0, 0, 0, 1)
   end
end
