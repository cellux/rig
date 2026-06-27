local M = ... or {}

function M.raise(message, ...)
   if select("#", ...) > 0 then
      message = string.format(message, ...)
   end
   error(message, 0)
end

function M.set(values)
   if type(values) ~= "table" then
      M.raise("set expects values to be a table")
   end

   local set = {}
   for i = 1, #values do
      set[values[i]] = true
   end
   return set
end

local class_marker_key = {}

local function is_class(value)
   return type(value) == "table" and rawget(value, class_marker_key) == true
end
M.is_class = is_class

function M.class(parent)
   if parent ~= nil and not is_class(parent) then
      M.raise("class expects parent to be a class if provided")
   end

   local c = {}
   c.__index = c
   c[class_marker_key] = true

   local function is_descendant(class_value, ancestor)
      if not is_class(class_value) or not is_class(ancestor) then
         return false
      end

      local current = class_value

      while type(current) == "table" do
         if current == ancestor then
            return true
         end

         local current_mt = getmetatable(current)
         if type(current_mt) ~= "table" then
            return false
         end

         current = rawget(current_mt, "__index")
      end

      return false
   end

   function c:super()
      return parent
   end

   function c:is_instance(value)
      return is_descendant(getmetatable(value), self)
   end

   function c:is_descendant(ancestor)
      return is_descendant(self, ancestor)
   end

   function c:is_ancestor(descendant)
      return is_descendant(descendant, self)
   end

   setmetatable(c, {
      __index = parent,
      __call = function(class_table, ...)
         local instance = setmetatable({}, class_table)
         if type(instance.init) == "function" then
            instance:init(...)
         end
         return instance
      end,
   })

   return c
end

return M
