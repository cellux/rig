local M = ... or {}

function M.class(parent)
   if parent ~= nil and type(parent) ~= "table" then
      error("oop.class expects parent to be a table if provided", 0)
   end

   local c = {}
   c.__index = c

   function c:is_instance(value)
      local current = getmetatable(value)

      while type(current) == "table" do
         if current == self then
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
